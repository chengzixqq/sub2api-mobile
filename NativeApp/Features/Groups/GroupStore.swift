import Foundation
import Observation
import Sub2Core

/// -ui-testing only: the session's group fixtures with the demo accounts and site clock the account pages use (one
/// AccountDemoStore, one base time), so both count the same states.
struct GroupFixtureContext {
    let fixtures: GroupFixtures
    let accounts: [UpstreamAccount]
    let now: Date
}

/// 50 §1 (X03, C-39): the session's groups — the list, today's charge, D02's shortage and the F04 error fallback — kept on
/// AppModel so the list, the detail and the editors read and write the same rows. Reads go through the session's client or
/// AppModel's wrappers (fixtures included); a reply for an older session is dropped.
///
/// `revision` moves by one only when a list read's result is written and on `upsert`, `remove`, `applyOptimistic` and
/// `rollback`. `fetch(id:)` is the only read of one group: it replaces that row in place and moves neither the revision nor the
/// group directory.
@MainActor @Observable
final class GroupStore {
    let generation: UUID
    /// AdminGroup.displayOrder.
    private(set) var list: BlockState<[AdminGroup]> = .idle
    private(set) var listRefresh = BlockRefresh()
    private(set) var listError: APIError?
    private(set) var listErrorAt: Date?
    /// usage-summary by group; a failed refresh keeps the last success, and never read is “今日 —” (S5D2a-15).
    private(set) var usage: BlockState<[Int: GroupUsageSummary]> = .idle
    /// D02's groups[].shortage; a failed refresh keeps the last success (S5-中-8). Idle without `accounts.status_summary` or for a
    /// vendor, and with no success yet `shortages` is nil: the local half rule.
    private(set) var shortageState: BlockState<[Int: AccountStatusGroupSummary.Shortage]> = .idle
    /// Each block's 429 wait (00 §2.7.2) and whether its last read that ended failed (the 更新失败 strip).
    private(set) var usageRefresh = BlockRefresh()
    private(set) var shortageRefresh = BlockRefresh()
    /// The F04 fallback's error count per group; nil until read, and a failed read keeps the last (none read: 0 errors).
    private(set) var errorCounts: [Int: Int]?
    private(set) var revision = 0
    private(set) var lastRefreshAt: Date?
    /// Platform names beyond the built-in list (X25), read once per session.
    private(set) var catalog: MetaCatalog?
    /// S5-08: this session got 500 GROUP_REPOSITORY_UNSUPPORTED, so member writes take the 0.4.4 fallback from now on.
    private(set) var memberBatchUnsupported = false
    /// S5-08: the latest member write per group; the detail refreshes when its entry changes.
    private(set) var memberChanges: [Int: GroupMemberChange] = [:]
    /// Set under `-ui-testing`.
    @ObservationIgnored let fixtures: GroupFixtures?
    @ObservationIgnored private weak var app: AppModel?
    /// 00 §4.6: each block reads on its own (BlockRead).
    @ObservationIgnored private let listRead = BlockRead()
    @ObservationIgnored private let usageRead = BlockRead()
    @ObservationIgnored private let shortageRead = BlockRead()
    @ObservationIgnored private let errorRead = BlockRead()
    @ObservationIgnored private let catalogRead = BlockRead()
    @ObservationIgnored private var needsRefresh = false
    /// Local writes made while a list read is out, laid over its result.
    @ObservationIgnored private var pendingEdits: [GroupListEdit] = []

    init(app: AppModel, generation: UUID) {
        self.app = app
        self.generation = generation
        fixtures = app.isUITesting ? GroupFixtures.current(for: generation) : nil
    }

    var isLive: Bool { app?.sessionGeneration == generation }
    var groups: [AdminGroup] { list.value ?? [] }
    var shortages: [Int: AccountStatusGroupSummary.Shortage]? { shortageState.value }
    /// S5-高-3: 今日 shows an earlier read because the last one failed, until a read works.
    var usageStale: Bool { GroupStoreRules.isStale(usage, refresh: usageRefresh) }
    /// S5-中-8: 可用偏低 is judged by an earlier read because the last one failed, until a read works.
    var shortagesAreStale: Bool { GroupStoreRules.isStale(shortageState, refresh: shortageRefresh) }
    /// The 更新失败 strip: a kept block read again now, then a kept block's 429 wait, then 更新失败.
    func staleStatus(at now: Date) -> BlockStatusPresentation.Accessory {
        let refreshing = (usageStale && usage.isLoading) || (shortagesAreStale && shortageState.isLoading)
        let waits = [usageStale ? usageRefresh : nil, shortagesAreStale ? shortageRefresh : nil].compactMap { $0 }
        return GroupStoreRules.staleStatus(refreshing: refreshing, waits: waits, at: now)
    }
    /// The list's rows: F04's buckets, or the fallback's error counts on a server without them, and D02's shortage.
    var rows: [GroupListRow] {
        let fallback = GroupStoreRules.needsErrorFallback(groups: list.value, hasAccountBuckets: hasAccountBuckets) ? errorCounts ?? [:] : [:]
        return GroupListSections.rows(groups, fallbackErrors: fallback, shortages: shortages ?? [:])
    }
    var fixtureContext: GroupFixtureContext? {
        guard let fixtures, let app else { return nil }
        return GroupFixtureContext(fixtures: fixtures, accounts: app.accountDemo.accounts, now: app.accountFixtureNow())
    }
    func group(id: Int) -> AdminGroup? { groups.first { $0.id == id } }
    /// What the list shows as 今日: the last successful read, however old.
    func todaySummary(for groupID: Int) -> GroupUsageSummary? { usage.value?[groupID] }
    /// The detail's reuse (S5-07): only within `maxAge` of the last successful read.
    func usage(for groupID: Int, maxAge: TimeInterval = GroupStoreRules.usageMaxAge, now: Date = Date()) -> GroupUsageSummary? {
        GroupStoreRules.isFresh(usage.updatedAt, now: now, maxAge: maxAge) ? todaySummary(for: groupID) : nil
    }
    func nextAutoRefreshDelay(now: Date) -> TimeInterval {
        GroupStoreRules.autoRefreshDelay(lastRefreshAt: lastRefreshAt, refresh: listRefresh, now: now)
    }

    // MARK: - Reads

    /// On appearing: nothing while the list is younger than `maxAge`, unless a write asked for a read.
    func loadIfNeeded(maxAge: TimeInterval = GroupStoreRules.refreshInterval) async {
        guard list.value == nil || needsRefresh || !GroupStoreRules.isFresh(lastRefreshAt, now: Date(), maxAge: maxAge) else { return }
        await refreshAll()
    }
    /// 50 §1.2: the list, usage-summary and status-summary at once (and the error fallback), each its own block (00 §4.6), so a slow
    /// block or the list's 429 wait holds back no other; returns once the list is in, the others change their cells when they arrive.
    /// The list, the shortage and the fallback are read no earlier than the call (once more after a read already out, so a write's
    /// refresh gets the write); usage-summary, which no group write changes, shares a read that is out.
    func refreshAll() async {
        guard isLive, let session = app?.sessionContext, session.generation == generation else { return }
        usageRead.start { [weak self] in await self?.readUsage(session) }
        catalogRead.start { [weak self] in await self?.readCatalog() }
        refreshInBackground(shortageRead) { [weak self] in await self?.readShortages(session) }
        refreshErrorCounts(session, groups: nil)
        await listRead.refresh { [weak self] in await self?.readListThenFallback(session) }
    }
    /// `GET admin/groups/:id`. A success replaces that row in place; errors come back as they are.
    func fetch(id: Int) async throws -> AdminGroup {
        guard isLive, let session = app?.sessionContext, session.generation == generation else { throw CancellationError() }
        let group: AdminGroup
        if let context = fixtureContext {
            group = try session.site.me.isSimpleRunMode ? context.fixtures.simpleModeGroup(id: id, accounts: context.accounts, now: context.now)
                : context.fixtures.group(id: id, accounts: context.accounts, now: context.now)
        } else { group = try await session.client.group(id: id) }
        guard isLive else { throw CancellationError() }
        list = list.updatingValue { rows in rows.map { $0.id == group.id ? group : $0 } }
        return group
    }
    /// The next appearance reads again.
    func setNeedsRefresh() { needsRefresh = true }

    // MARK: - Writes

    /// A written group: here and in the group directory (X11).
    func upsert(_ group: AdminGroup) {
        apply(.upsert(group))
        app?.groupDirectory?.upsert(group)
    }
    /// Only here; returns the row before, for `rollback`.
    @discardableResult func applyOptimistic(_ group: AdminGroup) -> AdminGroup? {
        let previous = self.group(id: group.id)
        apply(.upsert(group))
        return previous
    }
    func rollback(_ previous: AdminGroup) { apply(.upsert(previous)) }
    /// The row, its usage and its directory entry.
    func remove(id: Int) {
        apply(.remove(id))
        usage = usage.updatingValue { $0.filter { $0.key != id } }
        app?.groupDirectory?.remove(id: id)
    }
    func refreshDirectory() async { await app?.groupDirectory?.refresh() }

    // MARK: - 成员写入（S5-08）

    func noteMemberBatchUnsupported() { memberBatchUnsupported = true }
    /// 50 §0.4.4: members go in one batch with `groups.member_batch`, until the batch met a 500 GROUP_REPOSITORY_UNSUPPORTED in
    /// this session.
    static func takesMemberBatch(_ session: SessionContext?, store: GroupStore?) -> Bool {
        session?.has(.groupsMemberBatch) == true && store?.memberBatchUnsupported != true
    }
    /// The reply's counts go on the row and its directory entry at once, without moving the revision (S5D2a-10); the detail
    /// reads `memberChanges` and the list reads its three requests again.
    func noteMemberChange(_ change: GroupMemberChange) {
        if let counts = change.counts, let row = group(id: change.groupID) {
            let updated = row.applyingCounts(counts)
            list = list.updatingValue { rows in rows.map { $0.id == updated.id ? updated : $0 } }
            app?.groupDirectory?.upsert(updated)
        }
        memberChanges[change.groupID] = change
        Task { await refreshAll() }
    }

    // MARK: - Internals

    private var hasAccountBuckets: Bool { app?.siteSession?.has(.groupsAccountBuckets) ?? true }

    private func apply(_ edit: GroupListEdit) {
        if list.isLoading { pendingEdits.append(edit) }
        list = list.updatingValue { GroupStoreRules.applying([edit], to: $0) }
        revision += 1
    }
    private func refreshInBackground(_ block: BlockRead, _ read: @escaping BlockRead.Read) {
        Task { await block.refresh(read) }
    }
    /// Not sent during the list's 429 wait, when a write's `setNeedsRefresh` also stays for the next appearance.
    private func readListThenFallback(_ session: SessionContext) async {
        guard listRefresh.allowsRequest(at: Date()) else { return }
        needsRefresh = false
        await readList(session)
        if session.has(.groupsAccountBuckets) { refreshErrorCounts(session, groups: list.value) }
    }
    private func readList(_ session: SessionContext) async {
        pendingEdits = []
        list = list.withLoading()
        do {
            let read: [AdminGroup]
            if let context = fixtureContext {
                read = try session.site.me.isSimpleRunMode ? context.fixtures.simpleModeList(accounts: context.accounts, now: context.now)
                    : context.fixtures.readList(accounts: context.accounts, now: context.now)
            } else { read = try await session.client.groupList() }
            guard isLive else { return }
            let now = Date()
            list = .loaded(GroupStoreRules.applying(pendingEdits, to: read), at: now)
            listRefresh = listRefresh.recordingSuccess(); listError = nil; listErrorAt = nil
            lastRefreshAt = now
            revision += 1
        } catch {
            guard isLive else { return }
            guard !(error is CancellationError) else { list = list.withCancelledLoad(); pendingEdits = []; return }
            let now = Date()
            list = list.withFailure(error.localizedDescription)
            listRefresh = listRefresh.recordingFailure(error, at: now); listError = error as? APIError; listErrorAt = now
            lastRefreshAt = now
        }
        pendingEdits = []
    }
    /// Not sent in simple mode (403 there, S5D2a-13), nor during its 429 wait.
    private func readUsage(_ session: SessionContext) async {
        let permissions = GroupPermissions(session: session, store: self)
        guard permissions.showsUsageAndCapacity, usageRefresh.allowsRequest(at: Date()) else { return }
        usage = usage.withLoading()
        do {
            let rows: [GroupUsageSummary]
            if let fixtures {
                if permissions.isSimpleMode, let refusal = GroupFixtures.simpleModeRefusal(.usageSummary) { throw refusal }
                rows = try await fixtures.usageSummary()
            } else {
                let zone = GroupStoreRules.usageTimeZone(isVendor: permissions.isVendor, siteZone: session.site.serverTimeZone)
                rows = try await session.client.groupUsageSummary(timezone: zone)
            }
            guard isLive else { return }
            usage = .loaded(GroupStoreRules.usageByGroup(rows), at: Date())
            usageRefresh = usageRefresh.recordingSuccess()
        } catch {
            guard isLive else { return }
            guard !(error is CancellationError) else { usage = usage.withCancelledLoad(); return }
            usage = usage.withFailure(nil)
            usageRefresh = usageRefresh.recordingFailure(error, at: Date())
        }
    }
    /// A vendor is refused (403), so it judges locally from the start. Not sent during its 429 wait.
    private func readShortages(_ session: SessionContext) async {
        let isVendor = GroupPermissions(me: session.site.me, isReadOnlyToken: session.isReadOnlyToken).isVendor
        guard let app, session.has(.accountsStatusSummary), !isVendor else { shortageState = .idle; shortageRefresh = BlockRefresh(); return }
        guard shortageRefresh.allowsRequest(at: Date()) else { return }
        shortageState = shortageState.withLoading()
        do {
            let found: [Int: AccountStatusGroupSummary.Shortage]
            if let context = fixtureContext { found = try context.fixtures.readShortages(accounts: context.accounts, now: context.now) }
            else { found = GroupStoreRules.shortages(in: try await app.accountStatusSummary()) }
            guard isLive else { return }
            shortageState = .loaded(found, at: Date())
            shortageRefresh = shortageRefresh.recordingSuccess()
        } catch {
            guard isLive else { return }
            guard !(error is CancellationError) else { shortageState = shortageState.withCancelledLoad(); return }
            shortageState = shortageState.withFailure(nil)
            shortageRefresh = shortageRefresh.recordingFailure(error, at: Date())
        }
    }
    /// 50 §0.1 F04 fallback: without `groups.account_buckets` with the other blocks, with it after a list that lacks the counts.
    private func refreshErrorCounts(_ session: SessionContext, groups: [AdminGroup]?) {
        guard GroupStoreRules.needsErrorFallback(groups: groups, hasAccountBuckets: session.has(.groupsAccountBuckets)) else { return }
        refreshInBackground(errorRead) { [weak self] in await self?.readErrorCounts(session) }
    }
    /// One page of error accounts counted by their group_ids.
    private func readErrorCounts(_ session: SessionContext) async {
        guard let app else { return }
        let query = GroupStoreRules.errorAccountsQuery(supportsListQuery: session.has(.accountsListQuery))
        guard let page = try? await app.managedAccounts(page: 1, query: query), isLive else { return }
        errorCounts = GroupBuckets.errorCounts(accounts: page.items)
    }
    private func readCatalog() async {
        guard catalog == nil, let app else { return }
        let read = await app.metaCatalog()
        guard isLive else { return }
        catalog = read
    }
}

extension GroupPermissions {
    /// The group pages' permissions in `session`; simple mode greys the member entries while `store`'s session cannot take
    /// members in one batch (S5-中-12).
    @MainActor init(session: SessionContext?, store: GroupStore?) {
        self.init(me: session?.site.me, isReadOnlyToken: session?.isReadOnlyToken ?? false,
                  supportsMemberBatch: GroupStore.takesMemberBatch(session, store: store))
    }
}
