import Foundation
import Observation
import Sub2Core

/// One query's rows (at most 2,000), the page-1 counts, and what the 2,000-row note compares.
struct AccountListSnapshot: Sendable {
    var rows: [UpstreamAccount]
    /// The server's total for the query (an old server: before the chip is applied).
    var total: Int
    var counts: AccountListCounts?
    /// Rows read (an old server: before the chip is applied).
    var loadedCount: Int
    /// A new query's first pages, shown while the rest are read; one cut short (the tab left, a sheet opened) stays partial until
    /// the next full refresh, which reads it page by page again.
    var isPartial = false
}

/// 20 §1.2–§1.6: the account tab's data. Layout and timing are the Sub2Core rules (AccountListLayout, AccountListRefresh); this
/// runs the requests. States, list times and fixtures use the site clock (20 §0.6, D03); refresh marks use the device clock, which
/// only measures elapsed time. The page keeps one per session (the tabs are rebuilt with it), calls `setVisible` on appear and
/// disappear, `foregroundResumed` when `foregroundRevision` changes and `reload` when `securityPrompts.complianceRevision` does.
@MainActor @Observable
final class AccountListModel {
    let generation: UUID
    private(set) var chip: AccountListChip
    /// Empty = every platform.
    private(set) var platform: String
    /// The group page's transitional entry (X32; removed with it in S5-13).
    let groupID: Int?
    /// No value + loading = first load; value + loading = “正在刷新…”; value + failed = the stale-data banner; failed alone = error page.
    private(set) var list: BlockState<AccountListSnapshot> = .idle
    /// Pages after the first are still coming (“正在加载更多账号…”).
    private(set) var isLoadingMore = false
    private(set) var listRefresh = BlockRefresh()
    private(set) var summary: BlockState<AccountStatusSummary> = .idle
    private(set) var today: BlockState<AccountTodayStatsBatch> = .idle
    private(set) var catalog: MetaCatalog = .builtin
    private(set) var sections: [AccountPlatformSection] = []
    private(set) var collapsed: Set<String>
    /// 20 §8.1 (S2-07): selection mode pauses the light refresh (20 §1.6).
    private(set) var isSelecting = false
    private(set) var selection = AccountSelection()

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private let serverNow: @Sendable () -> Date
    @ObservationIgnored private let siteID: UUID?
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var hasSheet = false
    @ObservationIgnored private var marks = AccountListRefresh.Marks()
    @ObservationIgnored private var frozenOrder: [String]?
    /// Sections are ranked again until a full refresh after opening or a pull has its summary (20 §1.3).
    @ObservationIgnored private var reordersSections = true
    @ObservationIgnored private var loadedQuery: AccountListQuery?
    /// Every row an old server sent; the chip, counts and order are derived from them here.
    @ObservationIgnored private var legacyRows: [UpstreamAccount]?
    /// 400 INVALID_ACCOUNT_STATUS_FILTER: this session reads the list as an old server's (20 §0.5).
    @ObservationIgnored private var forcesLegacy = false
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var listTicket = UUID()
    @ObservationIgnored private var runtimeTicket = UUID()
    @ObservationIgnored private var summaryTicket = UUID()
    @ObservationIgnored private var todayTicket = UUID()
    /// The light refresh's blocks wait out their own 429 and back off on their own failures (00 §2.7.2, §4.6).
    @ObservationIgnored private var runtimeBlock = AccountListRefresh.LightBlock()
    @ObservationIgnored private var summaryBlock = AccountListRefresh.LightBlock()
    @ObservationIgnored private var todayBlock = AccountListRefresh.LightBlock()
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// Collapsed platforms by site, kept while the App runs.
    private static var collapsedBySite: [UUID: Set<String>] = [:]

    var rows: [UpstreamAccount] { list.value?.rows ?? [] }
    var counts: AccountListCounts? { list.value?.counts }
    /// U15; not while pages are still coming, after pages were cut short or after a failed read.
    var overflowNote: String? {
        guard let snapshot = list.value, !snapshot.isPartial else { return nil }
        if case .failed = list { return nil }
        return AccountListLayout.overflowNote(total: snapshot.total, loaded: snapshot.loadedCount)
    }

    init(model: AppModel, chip: AccountListChip = .all, platform: String = "", groupID: Int? = nil) {
        app = model
        generation = model.sessionGeneration
        self.chip = chip
        self.platform = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        self.groupID = groupID
        let clock = model.sessionContext?.client.serverClock, site = model.activeProfile?.id
        serverNow = { clock?.now() ?? Date() }
        siteID = site
        collapsed = site.flatMap { Self.collapsedBySite[$0] } ?? []
    }

    // MARK: - Entry points

    /// Entering the tab: a full refresh, the group directory (loaded once, then refreshed in the background) and the catalog.
    func activate() async {
        async let groups: Void = refreshGroups()
        async let names: Void = loadCatalog()
        await reload()
        _ = await (groups, names)
    }
    /// Retry, compliance accepted, a write elsewhere: a full refresh replacing any running one.
    func reload() async { await runFull(replacing: true) }
    /// Pull to refresh also ranks the sections again.
    func pullToRefresh() async {
        reordersSections = true
        await runFull(replacing: true)
    }
    /// 20 §1.6: runtime merged over the rows, then status-summary and today. A changed status or switch, or a row the reply left
    /// out, makes it a full refresh; without runtime_batch it is one. A failed runtime read keeps the last values silently.
    func refreshLight() async { await refreshLight(scheduled: false) }
    /// A row's countdown reached zero: derive again now; a light refresh follows, at most once in 10 seconds and not while paused.
    func countdownElapsed() async {
        rederive()
        let now = Date()
        guard let kind = AccountListRefresh.countdownRefresh(at: now, gate: gate, marks: marks, supportsRuntime: supportsRuntime,
                                                            throttle: listRefresh) else { return }
        marks = marks.recordingCountdown(at: now)
        await perform(kind, scheduled: true)
    }
    /// Back in the foreground: a light refresh at once, and the timer again.
    func foregroundResumed() async {
        restartTimer()
        guard gate.isOpen else { return }
        await perform(AccountListRefresh.resolved(.light, supportsRuntime: supportsRuntime))
    }
    /// The old list stays until the new one arrives; an old server's rows are filtered again without a request.
    func select(_ chip: AccountListChip) async {
        guard chip != self.chip else { return }
        self.chip = chip
        if let legacyRows, loadedQuery == currentQuery() {
            list = list.updatingValue { legacySnapshot(legacyRows, total: $0.total) }
            relayout()
            return
        }
        await reload()
    }
    func select(platform: String) async {
        let trimmed = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != self.platform else { return }
        self.platform = trimmed
        await reload()
    }
    /// A tab intent sets both at once, so the list is read once (10 §0.7-4).
    func select(_ chip: AccountListChip, platform: String) async {
        let trimmed = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != self.platform else { return await select(chip) }
        self.chip = chip
        self.platform = trimmed
        await reload()
    }
    func setVisible(_ visible: Bool) { isVisible = visible; restartTimer() }
    func setSheetPresented(_ presented: Bool) { hasSheet = presented; restartTimer() }

    /// 20 §5.6: an account a write returned or read back replaces its row at once (the platform order stays), then the list is
    /// read again in full.
    func applyWrite(_ account: UpstreamAccount) {
        guard isLive else { return }
        changeRows { rows in rows.map { $0.id == account.id ? account : $0 } }
        Task { await reload() }
    }
    /// 20 §0.5: the account is gone: its row leaves at once, and the list is read again.
    func noteMissing(id: Int) {
        guard isLive else { return }
        changeRows { rows in rows.filter { $0.id != id } }
        Task { await reload() }
    }
    private func changeRows(_ change: ([UpstreamAccount]) -> [UpstreamAccount]) {
        if let legacyRows {
            let changed = change(legacyRows)
            self.legacyRows = changed
            list = list.updatingValue { legacySnapshot(changed, total: $0.total) }
        } else {
            list = list.updatingValue { snapshot in
                var next = snapshot
                next.rows = change(snapshot.rows)
                return next
            }
        }
        relayout()
    }

    func toggleCollapsed(_ platform: String) {
        collapsed = collapsed.symmetricDifference([platform])
        if let siteID { Self.collapsedBySite[siteID] = collapsed }
    }
    func isCollapsed(_ platform: String) -> Bool { collapsed.contains(platform) }
    func chipCount(_ chip: AccountListChip) -> Int? { counts.flatMap(chip.count(in:)) }
    /// nil when the read failed or has no figures for the account: the row shows “—” (20 §1.5).
    func todayStats(for id: Int) -> AccountTodayStats? {
        isTodayUnavailable(for: id) ? nil : today.value?.stats[id]
    }
    /// S2D1-18: a failed read, a failed id, or an id the loaded batch has no figures for.
    func isTodayUnavailable(for id: Int) -> Bool {
        if case .failed = today { return true }
        guard let batch = today.value else { return false }
        return batch.failedIDs.contains(id) || batch.stats[id] == nil
    }

    /// 20 §1.3 header alerts (S2-22): a platform's events in LiveOpsStore's firing list, the monitor's 告警中 (10 §0.5); none
    /// while that list is unread or its last read failed (a retry's old list included) or ops monitoring is off (20 §1.5), and
    /// none on the group page's entry.
    func firingAlerts(platform: String) -> [AlertEvent] {
        guard groupID == nil, isLive, let ops = app?.liveOps,
              AccountAlertMatch.isListUsable(ops.firing, opsDisabled: ops.opsDisabled) else { return [] }
        return ops.firingAlerts(platform: platform)
    }

    // MARK: 选择模式（S2-07）

    func beginSelecting() {
        selection = AccountSelection()
        isSelecting = true
        restartTimer()
    }
    /// “完成”, or a batch that went through: the selection is cleared and the list read again at once (20 §8.6).
    func endSelecting() {
        selection = AccountSelection()
        isSelecting = false
        restartTimer()
        Task { await reload() }
    }
    func toggleSelection(_ id: Int) { selection = selection.toggling(id) }
    /// 全选 / 取消全选 over a section's loaded rows, collapsed or not.
    func toggleSectionSelection(_ sectionIDs: [Int]) { selection = selection.togglingAll(sectionIDs) }
    /// In the order the list shows them.
    var selectedAccounts: [UpstreamAccount] { sections.flatMap(\.rows).filter { selection.contains($0.id) } }

    // MARK: - Full refresh

    /// Timer and light refreshes skip while one runs; the user's replace it.
    private func runFull(replacing: Bool) async {
        if !replacing, listTask != nil { return }
        guard isLive, listRefresh.allowsRequest(at: Date()) else { return }
        listTask?.cancel()
        marks = marks.recording(.full, at: Date())
        let ticket = UUID()
        listTicket = ticket
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fullRefresh(ticket: ticket)
        }
        listTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if listTicket == ticket { listTask = nil }
    }
    private func fullRefresh(ticket: UUID) async {
        let query = currentQuery()
        list = list.withLoading()
        defer {
            if listTicket == ticket {
                isLoadingMore = false
                if list.isLoading { list = list.withCancelledLoad() }
                // Cancelled after the first pages were shown: the rows stay, and the timer reads the rest when it runs again.
                if case .loaded(let snapshot, _) = list, snapshot.isPartial { marks = marks.forgettingFull() }
            }
        }
        do {
            let progressive = query.supportsListQuery && (loadedQuery != query || list.value?.isPartial == true)
            let result = try await readPages(query, ticket: ticket, progressive: progressive)
            guard listTicket == ticket, isLive, !Task.isCancelled else { return }
            show(result, for: query)
            listRefresh = listRefresh.recordingSuccess()
        } catch {
            guard listTicket == ticket, isLive, !(error is CancellationError), !Task.isCancelled else { return }
            if query.supportsListQuery, AccountListQuery.shouldFallBackToLegacy(after: error) {
                forcesLegacy = true
                return await fullRefresh(ticket: ticket)
            }
            list = list.withFailure(error.localizedDescription)
            listRefresh = listRefresh.recordingFailure(error, at: Date())
            relayout()
            return
        }
        await refreshCompanions(AccountListRefresh.Round(start: Date(), isScheduled: false))
        if listTicket == ticket { reordersSections = false }
    }

    private struct PageResult { var rows: [UpstreamAccount]; var total: Int; var counts: AccountListCounts? }

    /// Page 1, then the next pages up to 2,000 rows. `progressive` (a new query) shows each page as it comes; a refresh of the
    /// shown query gathers the pages first and replaces the list once.
    private func readPages(_ query: AccountListQuery, ticket: UUID, progressive: Bool) async throws -> PageResult {
        guard let app else { throw CancellationError() }
        let limit = AccountListLayout.rowLimit
        var page = try await app.managedAccounts(page: 1, query: query)
        var result = PageResult(rows: AccountListRefresh.appending(page.items, to: [], limit: limit), total: page.total, counts: page.counts)
        while let next = AccountListRefresh.nextPage(after: page, loaded: result.rows.count, limit: limit) {
            guard listTicket == ticket, isLive, !Task.isCancelled else { throw CancellationError() }
            if progressive { show(result, for: query, morePages: true) }
            page = try await app.managedAccounts(page: next, query: query)
            result.rows = AccountListRefresh.appending(page.items, to: result.rows, limit: limit)
        }
        return result
    }
    private func show(_ result: PageResult, for query: AccountListQuery, morePages: Bool = false) {
        loadedQuery = query
        if query.supportsListQuery {
            legacyRows = nil
            let snapshot = AccountListSnapshot(rows: result.rows, total: result.total, counts: result.counts, loadedCount: result.rows.count,
                                               isPartial: morePages)
            list = .loaded(snapshot, at: serverNow())
        } else {
            legacyRows = result.rows
            list = .loaded(legacySnapshot(result.rows, total: result.total), at: serverNow())
        }
        isLoadingMore = morePages
        relayout()
    }
    /// An old server's rows through the chip, D02 counts and the urgency order (20 §1.2).
    private func legacySnapshot(_ all: [UpstreamAccount], total: Int) -> AccountListSnapshot {
        let now = serverNow()
        let rows = AccountListLocal.urgencySorted(AccountListLocal.filter(all, chip: chip, now: now), now: now)
        return AccountListSnapshot(rows: rows, total: total, counts: AccountListLocal.counts(all, now: now), loadedCount: all.count)
    }

    // MARK: - Light refresh and companions

    /// A block waiting out a 429 sends nothing in any round; a failing one also sits out scheduled rounds while it backs off.
    private func refreshLight(scheduled: Bool) async {
        guard supportsRuntime, list.value != nil else { return await runFull(replacing: false) }
        let round = AccountListRefresh.Round(start: Date(), isScheduled: scheduled)
        marks = marks.recording(.light, at: round.start)
        guard let app, listTask == nil, isLive else { return }
        let current = legacyRows ?? rows
        if !current.isEmpty, runtimeBlock.allowsRequest(in: round) {
            let ticket = UUID()
            runtimeTicket = ticket
            runtimeBlock = runtimeBlock.requesting(in: round)
            do {
                let runtime = try await app.accountRuntime(ids: current.map(\.id))
                runtimeBlock = runtimeBlock.recordingSuccess()
                guard runtimeTicket == ticket, listTask == nil, isLive, !Task.isCancelled else { return }
                if AccountListRefresh.needsFullRefresh(current, runtime: runtime) { return await runFull(replacing: false) }
                merge(runtime)
            } catch {
                guard !(error is CancellationError), !Task.isCancelled else { return }
                runtimeBlock = runtimeBlock.recordingFailure(error, at: Date())
            }
        }
        await refreshCompanions(round)
    }
    /// status-summary, today and the firing alerts, side by side after each list or runtime read.
    private func refreshCompanions(_ round: AccountListRefresh.Round) async {
        async let summaryRead: Void = loadSummary(round)
        async let todayRead: Void = loadToday(round)
        async let alertsRead: Void = refreshFiringAlerts()
        _ = await (summaryRead, todayRead, alertsRead)
    }
    /// A failure falls back to local header counts silently. The badge takes the site's error count with the device time it was read.
    private func loadSummary(_ round: AccountListRefresh.Round) async {
        guard let app, has(.accountsStatusSummary) else { summary = .idle; return }
        guard summaryBlock.allowsRequest(in: round) else { return }
        let ticket = UUID(), readAt = Date()
        summaryTicket = ticket
        summaryBlock = summaryBlock.requesting(in: round)
        summary = summary.withLoading()
        do {
            let result = try await app.accountStatusSummary()
            guard summaryTicket == ticket, isLive else { return }
            summary = .loaded(result, at: serverNow())
            summaryBlock = summaryBlock.recordingSuccess()
            app.accountBadge.update(errorCount: result.totals.error, at: readAt)
        } catch {
            guard summaryTicket == ticket, isLive else { return }
            summary = error is CancellationError ? summary.withCancelledLoad() : summary.withFailure(error.localizedDescription)
            if !(error is CancellationError) { summaryBlock = summaryBlock.recordingFailure(error, at: Date()) }
        }
        relayout()
    }
    /// Every loaded row (an old server's whole list, so a chip change needs no new read); S2-02 splits the ids by 200.
    private func loadToday(_ round: AccountListRefresh.Round) async {
        let ids = (legacyRows ?? rows).map(\.id)
        guard let app, !ids.isEmpty else { today = .idle; return }
        guard todayBlock.allowsRequest(in: round) else { return }
        let ticket = UUID()
        todayTicket = ticket
        todayBlock = todayBlock.requesting(in: round)
        today = today.withLoading()
        do {
            let result = try await app.accountTodayStatsBatch(ids: ids)
            guard todayTicket == ticket, isLive else { return }
            today = .loaded(result, at: serverNow())
            todayBlock = todayBlock.recordingSuccess()
        } catch {
            guard todayTicket == ticket, isLive else { return }
            today = error is CancellationError ? today.withCancelledLoad() : today.withFailure(error.localizedDescription)
            if !(error is CancellationError) { todayBlock = todayBlock.recordingFailure(error, at: Date()) }
        }
    }
    /// 20 §1.2, §1.6: while the tab shows, the monitor's refresh of the one firing list, which reuses a read under 60 seconds old.
    private func refreshFiringAlerts() async {
        guard groupID == nil, isVisible, isLive, let ops = app?.liveOps else { return }
        await ops.refreshFiringAlerts()
    }
    private func refreshGroups() async {
        guard let directory = app?.groupDirectory else { return }
        if directory.state.value == nil { await directory.ensureLoaded() } else { await directory.refresh() }
        if isLive { relayout() }
    }
    private func loadCatalog() async {
        guard let app else { return }
        let result = await app.metaCatalog()
        if isLive { catalog = result }
    }

    // MARK: - Layout and timer

    private func merge(_ runtime: [Int: AccountRuntime]) {
        if let legacyRows {
            let merged = AccountListRefresh.merging(legacyRows, runtime: runtime)
            self.legacyRows = merged
            list = list.updatingValue { legacySnapshot(merged, total: $0.total) }
        } else {
            list = list.updatingValue { snapshot in
                var next = snapshot
                next.rows = AccountListRefresh.merging(snapshot.rows, runtime: runtime)
                return next
            }
        }
        relayout()
    }
    private func rederive() {
        if let legacyRows { list = list.updatingValue { legacySnapshot(legacyRows, total: $0.total) } }
        relayout()
    }
    private func relayout() {
        guard let rows = list.value?.rows else { sections = []; return }
        let result = AccountListLayout.sections(rows: rows, chip: chip, summary: usableSummary, groups: app?.groupDirectory?.groups ?? [],
                                                frozenOrder: reordersSections ? nil : frozenOrder, now: serverNow())
        sections = result.sections
        frozenOrder = result.frozenOrder
        // A chip or a refresh that dropped a row drops its tick too, so 已选 N never counts a hidden account.
        if list.value?.isPartial != true, !selection.isEmpty { selection = selection.keeping(Set(rows.map(\.id))) }
    }
    /// A failed summary falls back to local counts; one being refreshed keeps its last value (20 §1.5).
    var usableSummary: AccountStatusSummary? {
        if case .failed = summary { return nil }
        return summary.value
    }

    /// `scheduled`: the timer or a countdown, not the user or the foreground.
    private func perform(_ kind: AccountListRefresh.Kind, scheduled: Bool = false) async {
        switch kind {
        case .light: await refreshLight(scheduled: scheduled)
        case .full: await runFull(replacing: false)
        }
    }
    /// One loop while the gate is open: sleep until `nextCheck`, run what is due. A closed gate or a released model ends it.
    private func restartTimer() {
        timer?.cancel()
        timer = nil
        guard gate.isOpen, isLive else { return }
        timer = Task { [weak self] in
            while let delay = self?.nextTimerDelay() {
                try? await Task.sleep(for: .seconds(max(delay, 1)))
                guard !Task.isCancelled else { return }
                await self?.timerFired()
            }
        }
    }
    private func nextTimerDelay() -> TimeInterval? {
        isLive ? AccountListRefresh.nextCheck(at: Date(), gate: gate, marks: marks, throttle: listRefresh) : nil
    }
    private func timerFired() async {
        guard let kind = AccountListRefresh.due(at: Date(), gate: gate, marks: marks, supportsRuntime: supportsRuntime,
                                                throttle: listRefresh) else { return }
        await perform(kind, scheduled: true)
    }

    private var gate: AccountListRefresh.Gate {
        AccountListRefresh.Gate(isForeground: app.map { !$0.isSuspended } ?? false, isVisible: isVisible, isSelecting: isSelecting, hasSheet: hasSheet)
    }
    private func currentQuery() -> AccountListQuery {
        AccountListLayout.listQuery(chip: chip, platform: platform, groupID: groupID, supportsListQuery: !forcesLegacy && has(.accountsListQuery))
    }
    private var supportsRuntime: Bool { has(.accountsRuntimeBatch) }
    private func has(_ capability: Capability) -> Bool { isLive && app?.sessionContext?.has(capability) == true }
    private var isLive: Bool { app?.sessionGeneration == generation }
}
