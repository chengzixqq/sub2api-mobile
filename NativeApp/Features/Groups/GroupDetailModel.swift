import Foundation
import Observation
import Sub2Core

/// 50 §2.2: every read of the group detail, so `-ui-testing` swaps them as a whole (GroupFixtures+Detail). The group itself
/// goes through the session's GroupStore (S5D2a-10), the members, their today and D02 through AppModel+Accounts (R19), the
/// key counts through S5-01. S5-07's blocks read through GroupDetailSectionsSource.
struct GroupDetailSource: Sendable {
    var group: @MainActor @Sendable (_ id: Int) async throws -> AdminGroup
    var members: @MainActor @Sendable (_ page: Int, _ query: AccountListQuery) async throws -> AccountListPage
    var memberToday: @MainActor @Sendable (_ ids: [Int], _ groupID: Int?) async throws -> AccountTodayStatsBatch
    var shortage: @MainActor @Sendable (_ groupID: Int) async throws -> AccountStatusGroupSummary.Shortage?
    var stats: @MainActor @Sendable (_ groupID: Int) async throws -> GroupStats?
    var apiKeyCount: @MainActor @Sendable (_ groupID: Int, _ maskedView: Bool) async throws -> Int
    var activeSubscriptionCount: @MainActor @Sendable (_ groupID: Int) async throws -> Int

    @MainActor static func make(_ app: AppModel) -> GroupDetailSource { app.isUITesting ? GroupFixtures.detailSource(app) : live(app) }

    @MainActor static func live(_ app: AppModel) -> GroupDetailSource {
        GroupDetailSource(
            group: { [weak app] id in
                guard let store = app?.groupStore else { throw CancellationError() }
                return try await store.fetch(id: id)
            },
            members: { [weak app] page, query in try await model(app).managedAccounts(page: page, query: query) },
            memberToday: { [weak app] ids, groupID in try await model(app).accountTodayStatsBatch(ids: ids, groupID: groupID) },
            shortage: { [weak app] groupID in
                try await model(app).accountStatusSummary(groupID: groupID).groups.first { $0.groupID == groupID }?.shortage
            },
            stats: { [weak app] groupID in try await model(app).requireClient().groupStats(id: groupID) },
            apiKeyCount: { [weak app] groupID, masked in try await model(app).requireClient().groupAPIKeyCount(id: groupID, maskedView: masked) },
            activeSubscriptionCount: { [weak app] groupID in try await model(app).requireClient().activeSubscriptionCount(groupID: groupID) })
    }
    @MainActor private static func model(_ app: AppModel?) throws -> AppModel {
        guard let app else { throw CancellationError() }
        return app
    }
}

/// 50 §2: one group detail's data. It opens on the list's row when the GroupStore has one; each block reads and fails on its
/// own (00 §4.6) and a reply for an older session is dropped. The page decides when to read: `poll()` while it is open (the first
/// pass is the entry), pull, the foreground, a write (GroupStore.revision) and the soonest member window's end.
@MainActor @Observable
final class GroupDetailModel {
    let groupID: Int
    /// The list's row until the server answers, then each read; S5-05's optimistic rows and S5-08's counts land here too.
    private(set) var group: AdminGroup?
    private(set) var loadedFromServer = false
    private(set) var isDeleted = false
    let groupRead = LoadState<AdminGroup>()
    let members = LoadState<GroupMemberList>()
    let memberToday = LoadState<GroupMemberToday>()
    /// D02's row for this group; a nil value means D02 had none and the local rule decides.
    let shortage = LoadState<AccountStatusGroupSummary.Shortage?>()
    let keyCounts = LoadState<GroupKeyCounts>()
    /// S5-07: the alert banner, 贰 and 叁's counts, read with every refresh here.
    let sections: GroupDetailSectionsModel
    private(set) var isLoadingMoreMembers = false
    private(set) var loadMoreFailed = false
    /// Parsed once per member change; the status card only passes a new `now` (S5D2a-02).
    private(set) var memberSnapshots: [GroupMemberSnapshot] = []
    private(set) var catalog: MetaCatalog = .builtin
    /// S5-08 (2.4): members swiped out, hidden while their removal is out and, once it went through, until the members are
    /// read after it; the 60-second refresh leaves them hidden.
    private(set) var hiddenMemberIDs: Set<Int> = []

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private let source: GroupDetailSource
    @ObservationIgnored private let generation: UUID
    @ObservationIgnored private var lastRefresh: ContinuousClock.Instant?
    /// Device time before which the 60-second refresh skips a block still backing off after failures (00 §4.6).
    @ObservationIgnored private var blockDue: [GroupDetailBlock: Date] = [:]
    @ObservationIgnored private var lastCountdownTarget: Date?
    @ObservationIgnored private var refreshesAfterAction = false
    /// Members whose removal is out.
    @ObservationIgnored private var removing: Set<Int> = []

    init(app: AppModel, groupID: Int, source: GroupDetailSource? = nil, sectionsSource: GroupDetailSectionsSource? = nil) {
        self.app = app
        self.groupID = groupID
        self.source = source ?? .make(app)
        generation = app.sessionGeneration
        group = app.groupStore?.group(id: groupID)
        sections = GroupDetailSectionsModel(app: app, groupID: groupID, generation: app.sessionGeneration, source: sectionsSource)
    }

    var page: GroupDetailPageState {
        GroupDetailPageState.resolve(hasGroup: group != nil, loadedFromServer: loadedFromServer, failure: groupRead.error, deleted: isDeleted)
    }
    /// F04's buckets; an older server's errors are counted from the members once all are here, otherwise from the list's fallback.
    var buckets: GroupBuckets? {
        guard let group else { return nil }
        guard group.errorAccountCount == nil else { return GroupBuckets(group: group) }
        let list = members.value
        let errors = list?.isComplete == true ? (list?.rows.filter { $0.status == "error" }.count ?? 0) : (app?.groupStore?.errorCounts?[groupID] ?? 0)
        return GroupBuckets(group: group, fallbackErrors: errors)
    }
    /// D02's shortage this page read, else the list's, else the local half rule.
    var health: GroupHealth? {
        guard let group, let buckets else { return nil }
        let found: AccountStatusGroupSummary.Shortage? = if let read = shortage.value { read } else { app?.groupStore?.shortages?[groupID] }
        return GroupHealth.resolve(group: group, buckets: buckets, shortage: found)
    }
    func memberSummary(now: Date) -> GroupMemberSummary { GroupMemberSummary(members: memberSnapshots, now: now) }

    // MARK: - Reads

    /// The blocks `trigger` asks for (50 §2.6), side by side; the members' today follows the members, since it needs their ids.
    func refresh(_ trigger: GroupDetailTrigger) async {
        guard isCurrent else { return }
        let blocks = due(GroupDetailRefreshPlan.blocks(for: trigger, unread: unread), polling: trigger == .poll)
        let showsUsageAndCapacity = app?.sessionContext.map { permissions($0).showsUsageAndCapacity } ?? true
        async let groupDone: Void = loadGroup(if: blocks.contains(.group))
        async let membersDone: Void = loadMembers(if: blocks.contains(.members), thenToday: blocks.contains(.memberToday))
        async let shortageDone: Void = loadShortage(if: blocks.contains(.shortage))
        async let sectionsDone: Void = sections.refresh(trigger, showsUsageAndCapacity: showsUsageAndCapacity)
        await loadKeyCounts(if: blocks.contains(.stats))
        _ = await (groupDone, membersDone, shortageDone, sectionsDone)
        // 00 §4.6: the next round counts from the end; one the page cancelled (a sheet, the background) does not count.
        if !Task.isCancelled { lastRefresh = .now }
    }
    /// The page's loop while it is open: the entry first, then every 60 seconds from the last refresh.
    func poll() async {
        while !Task.isCancelled, isCurrent {
            guard let lastRefresh else { await refresh(.enter); continue }
            let wait = GroupDetailRefreshPlan.delay(sinceLastRefresh: Self.seconds(ContinuousClock.Instant.now - lastRefresh))
            if wait > 0 { do { try await Task.sleep(for: .seconds(wait)) } catch { return } }
            guard !Task.isCancelled else { return }
            await refresh(.poll)
        }
    }
    /// A member's window ended: the group's counts and the members once for that end.
    func countdownElapsed(target: Date) async {
        guard lastCountdownTarget != target else { return }
        lastCountdownTarget = target
        await refresh(.countdown)
    }
    /// S5-08: after a member write.
    func reloadMembers() async { await refresh(.membersWritten) }
    /// S5-08: the write's counts show at once; the next read of the group replaces them.
    func applyCounts(_ counts: GroupAccountCounts) {
        guard isCurrent else { return }
        group = group?.applyingCounts(counts)
    }
    /// S5-08 (S5D2a-10): a member write or a member's status action ended. Its counts first, then the group, the members, their
    /// today and capacity; a members read that answered shows the rows removed meanwhile for good.
    func refreshAfterMemberWrite(_ change: GroupMemberChange) async {
        guard isCurrent, change.groupID == groupID else { return }
        if let counts = change.counts { applyCounts(counts) }
        let membersBefore = members.updatedAt
        await reloadMembers()
        if members.updatedAt != membersBefore, case .loaded = members.state { hiddenMemberIDs = removing }
    }
    /// 2.4 移出: the row leaves at once.
    func beginRemoval(_ accountID: Int) {
        removing.insert(accountID)
        hiddenMemberIDs.insert(accountID)
    }
    /// `left`: the account is out of the group, so its row stays away until the members are read again; otherwise it comes back.
    func endRemoval(_ accountID: Int, left: Bool) {
        removing.remove(accountID)
        if !left { hiddenMemberIDs.remove(accountID) }
    }
    /// GroupStore.revision moved (S5D2a-10). A row that differs only in its counts is left; otherwise it shows at once (S5-05's
    /// optimistic status) and the page reads again, after the action when one is running. A vanished row proves nothing: the
    /// next read's 404 says deleted.
    func storeChanged(whileActionRuns running: Bool) {
        guard isCurrent, let row = app?.groupStore?.group(id: groupID) else { return }
        guard let shown = group else { group = row; return }
        guard !row.matchesIgnoringCounts(shown) else { return }
        group = row
        if running { refreshesAfterAction = true } else { Task { await refresh(.afterWrite) } }
    }
    /// 2.4: once 停用 / 启用 ended, the page reads again.
    func actionEnded() {
        guard refreshesAfterAction else { return }
        refreshesAfterAction = false
        Task { await refresh(.afterWrite) }
    }
    /// Scrolled to the end: the next page, then the members' today again. A failure only marks the tail row.
    func loadMoreMembers() async {
        guard isCurrent, let list = members.value, list.hasMore, !isLoadingMoreMembers, !members.isLoading else { return }
        isLoadingMoreMembers = true
        loadMoreFailed = false
        defer { isLoadingMoreMembers = false }
        do {
            let page = try await source.members(list.pagesRead + 1, memberQuery)
            guard isCurrent, members.value?.pagesRead == list.pagesRead else { return }
            members.updateValue { $0.appending(page, now: serverNow) }
            memberSnapshots = (members.value?.rows ?? []).map(GroupMemberSnapshot.init)
        } catch {
            guard isCurrent, !(error is CancellationError) else { return }
            loadMoreFailed = true
            return
        }
        await loadMemberToday()
    }
    /// 成员加载失败 · 重试.
    func retryMembers() async { await loadMembers(if: true, thenToday: true) }
    func loadCatalog() async {
        guard let app else { return }
        let read = await app.metaCatalog()
        if isCurrent { catalog = read }
    }

    // MARK: - Blocks

    private func loadGroup(if needed: Bool) async {
        guard needed, isCurrent else { return }
        let source = source, id = groupID
        let answeredBefore = groupRead.updatedAt, failedBefore = groupRead.lastErrorAt
        await groupRead.load(isCurrent: { self.isCurrent }) { try await source.group(id) }
        noteBackoff(.group, groupRead.refresh)
        if case .loaded(let read, let at) = groupRead.state, at != answeredBefore { apply(read); return }
        if groupRead.lastErrorAt != failedBefore, let error = groupRead.lastError,
           GroupErrorCopy.resolve(error, context: .read).action == .treatAsDeleted { markDeleted() }
    }
    /// The pages already shown are read again and replace the list at once.
    private func loadMembers(if needed: Bool, thenToday: Bool) async {
        if needed, isCurrent {
            let pages = max(1, members.value?.pagesRead ?? 1), query = memberQuery, source = source, now = serverNow
            let before = members.updatedAt
            await members.load(isCurrent: { self.isCurrent }) {
                var read: [AccountListPage] = []
                for number in 1...pages {
                    let page = try await source.members(number, query)
                    read.append(page)
                    if !page.hasMore { break }
                }
                return GroupMemberList(pages: read, serverSorted: query.supportsListQuery, now: now)
            }
            noteBackoff(.members, members.refresh)
            if members.updatedAt != before, case .loaded = members.state {
                memberSnapshots = (members.value?.rows ?? []).map(GroupMemberSnapshot.init)
                loadMoreFailed = false
            }
        }
        if thenToday { await loadMemberToday() }
    }
    /// U38: `group_id` only with `accounts.today_stats_group`; the reply's echo decides the footnote.
    private func loadMemberToday() async {
        guard isCurrent, let ids = members.value?.rows.map(\.id), !ids.isEmpty else { return }
        let source = source, id = groupID, base = memberToday.value ?? .empty
        let scoped = app?.sessionContext?.has(.accountsTodayStatsGroup) == true ? id : nil
        await memberToday.load(isCurrent: { self.isCurrent }) { base.merging(try await source.memberToday(ids, scoped), requested: ids, groupID: id) }
        noteBackoff(.memberToday, memberToday.refresh)
    }
    /// Not for a vendor (403) nor without D02; a stopped group is off and one without available accounts none whatever D02 says.
    private func loadShortage(if needed: Bool) async {
        guard needed, isCurrent, let session = app?.sessionContext, session.has(.accountsStatusSummary), !permissions(session).isVendor else { return }
        if let group, group.status != "active" || (group.activeAccountCount ?? 0) == 0 { return }
        let source = source, id = groupID
        await shortage.load(isCurrent: { self.isCurrent }) { try await source.shortage(id) }
        noteBackoff(.shortage, shortage.refresh)
    }
    /// groups/:id/stats, or on an older server the two page totals; not for a vendor or in simple mode (S5D2a-13). The billing is
    /// the group's as it stands once stats answered, since the group's own read runs alongside.
    private func loadKeyCounts(if needed: Bool) async {
        guard needed, isCurrent, let session = app?.sessionContext, permissions(session).showsStats else { return }
        let source = source, id = groupID, masked = session.has(.apiKeysMaskedView)
        await keyCounts.load(isCurrent: { self.isCurrent }) {
            try await GroupKeyCounts.read(stats: { try await source.stats(id) }, apiKeyCount: { try await source.apiKeyCount(id, masked) },
                                          activeSubscriptions: { try await source.activeSubscriptionCount(id) },
                                          isSubscription: { @MainActor in self.group.map { $0.subscriptionType == "subscription" } })
        }
    }

    // MARK: - Internals

    private var isLive: Bool { app?.sessionGeneration == generation }
    private var isCurrent: Bool { isLive && !isDeleted }
    private var serverNow: Date { app?.serverNow() ?? Date() }
    private var memberQuery: AccountListQuery {
        GroupMemberList.query(groupID: groupID, supportsListQuery: app?.sessionContext?.has(.accountsListQuery) ?? false)
    }
    /// A block whose first read never answered goes out with the next refresh, not a minute later.
    private var unread: Set<GroupDetailBlock> {
        if case .idle = keyCounts.state { return [.stats] }
        return []
    }
    private func permissions(_ session: SessionContext) -> GroupPermissions {
        GroupPermissions(me: session.site.me, isReadOnlyToken: session.isReadOnlyToken)
    }
    private func apply(_ read: AdminGroup) {
        group = read
        loadedFromServer = true
        // A rename or a status change shows on every page that names the group (2.6).
        if let directory = app?.groupDirectory, let known = directory.group(id: read.id), known.name != read.name || known.status != read.status {
            directory.upsert(read)
        }
    }
    /// 50 §0.8: the page turns into “这个分组已删除” and the group leaves the list and the directory.
    private func markDeleted() {
        isDeleted = true
        members.cancel(); memberToday.cancel(); shortage.cancel(); keyCounts.cancel(); sections.cancel()
        app?.groupStore?.remove(id: groupID)
    }
    private func due(_ blocks: Set<GroupDetailBlock>, polling: Bool) -> Set<GroupDetailBlock> {
        guard polling else { return blocks }
        let now = Date()
        return blocks.filter { block in blockDue[block].map { $0 <= now } ?? true }
    }
    /// 60 → 120 → 240 → 300 seconds after consecutive failures; a success clears it. The tolerance keeps a block on the tick it is
    /// due on, since the ticks count from the refresh, not from this block's answer.
    private func noteBackoff(_ block: GroupDetailBlock, _ refresh: BlockRefresh) {
        guard refresh.consecutiveFailures > 0 else { blockDue[block] = nil; return }
        blockDue[block] = Date().addingTimeInterval(refresh.nextDelay(base: GroupDetailRefreshPlan.interval, at: Date()) - Self.backoffTolerance)
    }
    private static let backoffTolerance: TimeInterval = 5
    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
