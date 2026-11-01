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
    /// D02's groups[].shortage; nil without `accounts.status_summary`, for a vendor or after a failure: the local half rule.
    private(set) var shortages: [Int: AccountStatusGroupSummary.Shortage]?
    /// The F04 fallback's error count per group; nil until read, and a failed read keeps the last (none read: 0 errors).
    private(set) var errorCounts: [Int: Int]?
    private(set) var revision = 0
    private(set) var lastRefreshAt: Date?
    /// Platform names beyond the built-in list (X25), read once per session.
    private(set) var catalog: MetaCatalog?
    /// Set under `-ui-testing`.
    @ObservationIgnored let fixtures: GroupFixtures?
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var running: Task<Void, Never>?
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
    /// 50 §1.2: the list, usage-summary and status-summary at once (and the error fallback); the list needs only its own read, the
    /// others change only their cells. A refresh already out is awaited instead of repeated; during a 429 wait nothing is sent.
    func refreshAll() async {
        if let running { await running.value; return }
        guard isLive, listRefresh.allowsRequest(at: Date()), let session = app?.sessionContext, session.generation == generation else { return }
        needsRefresh = false
        let task = Task { [weak self] in
            guard let self else { return }
            await self.readAll(session)
        }
        running = task
        await task.value
        if running == task { running = nil }
    }
    /// `GET admin/groups/:id`. A success replaces that row in place; errors come back as they are.
    func fetch(id: Int) async throws -> AdminGroup {
        guard isLive, let session = app?.sessionContext, session.generation == generation else { throw CancellationError() }
        let group: AdminGroup
        if let context = fixtureContext { group = try context.fixtures.group(id: id, accounts: context.accounts, now: context.now) }
        else { group = try await session.client.group(id: id) }
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

    // MARK: - Internals

    private var hasAccountBuckets: Bool { app?.siteSession?.has(.groupsAccountBuckets) ?? true }

    private func apply(_ edit: GroupListEdit) {
        if list.isLoading { pendingEdits.append(edit) }
        list = list.updatingValue { GroupStoreRules.applying([edit], to: $0) }
        revision += 1
    }
    private func readAll(_ session: SessionContext) async {
        async let usageRead: Void = readUsage(session)
        async let shortageRead: Void = readShortages(session)
        async let errorRead: Void = readErrorCounts(session, groups: nil)
        async let catalogRead: Void = readCatalog()
        await readList(session)
        if session.has(.groupsAccountBuckets) { await readErrorCounts(session, groups: list.value) }
        _ = await (usageRead, shortageRead, errorRead, catalogRead)
    }
    private func readList(_ session: SessionContext) async {
        pendingEdits = []
        list = list.withLoading()
        do {
            let read: [AdminGroup]
            if let context = fixtureContext { read = try context.fixtures.readList(accounts: context.accounts, now: context.now) }
            else { read = try await session.client.groupList() }
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
    /// Not sent in simple mode (403 there, S5D2a-13).
    private func readUsage(_ session: SessionContext) async {
        let permissions = GroupPermissions(me: session.site.me, isReadOnlyToken: session.isReadOnlyToken)
        guard permissions.showsUsageAndCapacity else { return }
        usage = usage.withLoading()
        do {
            let rows: [GroupUsageSummary]
            if let fixtures { rows = try fixtures.usageSummary() }
            else {
                let zone = GroupStoreRules.usageTimeZone(isVendor: permissions.isVendor, siteZone: session.site.serverTimeZone)
                rows = try await session.client.groupUsageSummary(timezone: zone)
            }
            guard isLive else { return }
            usage = .loaded(GroupStoreRules.usageByGroup(rows), at: Date())
        } catch {
            guard isLive else { return }
            usage = error is CancellationError ? usage.withCancelledLoad() : usage.withFailure(nil)
        }
    }
    /// A vendor is refused (403), so it judges locally from the start.
    private func readShortages(_ session: SessionContext) async {
        let isVendor = GroupPermissions(me: session.site.me, isReadOnlyToken: session.isReadOnlyToken).isVendor
        guard let app, session.has(.accountsStatusSummary), !isVendor else { shortages = nil; return }
        do {
            let found: [Int: AccountStatusGroupSummary.Shortage]
            if let context = fixtureContext { found = context.fixtures.shortages(accounts: context.accounts, now: context.now) }
            else { found = GroupStoreRules.shortages(in: try await app.accountStatusSummary()) }
            guard isLive else { return }
            shortages = found
        } catch {
            guard isLive, !(error is CancellationError) else { return }
            shortages = nil
        }
    }
    /// 50 §0.1 F04 fallback: one page of error accounts counted by their group_ids.
    private func readErrorCounts(_ session: SessionContext, groups: [AdminGroup]?) async {
        guard let app, GroupStoreRules.needsErrorFallback(groups: groups, hasAccountBuckets: session.has(.groupsAccountBuckets)) else { return }
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
