import Foundation
import Observation
import Sub2Core

/// 40 §6.2: the page's two list reads and their cursor reads, or the UI-test fixtures (LogFixtures).
struct LogsSource: Sendable {
    typealias UsageRead = @Sendable (_ page: Int, _ filter: RequestLogFilter) async throws -> Page<UsageRequestRecord>
    typealias ErrorRead = @Sendable (_ page: Int, _ filter: RequestLogFilter, _ kind: ErrorLogKind) async throws -> Page<RequestErrorRecord>
    typealias CursorRead<Record: Decodable & Sendable> = @Sendable (_ sinceID: Int, _ filter: RequestLogFilter) async throws -> Page<Record>
    let usage: UsageRead
    let errors: ErrorRead
    /// 00 §4.3 (S4-06): asked only on a site with `logs.since_id`, and never for upstream errors, which have no cursor.
    let usageSince: CursorRead<UsageRequestRecord>
    let errorsSince: CursorRead<RequestErrorRecord>

    /// What the cursor reads answer unless given.
    static let noCursor = APIError(kind: .unsupported, message: "这里不按游标读取。")

    init(usage: @escaping UsageRead, errors: @escaping ErrorRead,
         usageSince: @escaping CursorRead<UsageRequestRecord> = { _, _ in throw LogsSource.noCursor },
         errorsSince: @escaping CursorRead<RequestErrorRecord> = { _, _ in throw LogsSource.noCursor }) {
        self.usage = usage; self.errors = errors; self.usageSince = usageSince; self.errorsSince = errorsSince
    }

    /// R19's methods; `key_view=masked` only with the site's `api_keys.masked_view` (S4D1-06).
    static func live(_ client: APIClient, site: SiteSession) -> LogsSource {
        let masked = site.has(.apiKeysMaskedView)
        return LogsSource(usage: { try await client.requestRecords(page: $0, filter: $1, maskedView: masked) },
                          errors: { try await client.errorRecords(page: $0, filter: $1, kind: $2) },
                          usageSince: { try await client.requestRecords(sinceID: $0, filter: $1, maskedView: masked) },
                          errorsSince: { try await client.errorRecords(sinceID: $0, filter: $1) })
    }
}

extension LogScope {
    var errorKind: ErrorLogKind? {
        switch self {
        case .usage: nil
        case .errors: .request
        case .upstream: .upstream
        }
    }
    /// 用量明细 / 错误请求 / 上游错误.
    var title: String { RequestDetailPresentation.sourceName(kind: errorKind) }
}

extension LogsRoute {
    /// X39: the route's objects, model and source become the page's conditions.
    var conditions: LogConditions {
        LogConditions(account: account.map(Self.object), group: group.map(Self.object), user: user.map(Self.object), model: model,
                      modelSource: modelSource)
    }
    private static func object(_ object: RouteObject) -> LogFilterObject { LogFilterObject(id: object.id, name: object.name) }
}

/// The shown segment's failure row (40 §6.5): the page that failed, and BlockFailureRow's error and time.
struct LogListFailure: Sendable {
    let page: Int
    let error: APIError?
    let occurredAt: Date?
}

/// 40 §6: the usage-record page's state, registered in PageStateRegistry under `PageStateKey.logs(route)` (LogsStore). Each
/// segment keeps its own rows and paging; the conditions and the time are shared. It reads page 1 on first appearance, on a
/// segment, time or condition change, on pull, back from the background while shown (D18) and once ops monitoring is on again;
/// the last row reads the next page. Over a rolling preset it also polls the shown segment (S4-06), back from the background
/// too. Nothing goes out during a 429 wait (00 §2.7.2), and the error segments send nothing while ops monitoring is off. A
/// reply of an older read or session is dropped.
@MainActor @Observable
final class LogsStoreState {
    let generation: UUID
    let timeZone: ServerTimeZone
    private(set) var scope: LogScope
    private(set) var conditions: LogConditions
    private(set) var time = LogTimePreset.standard
    private(set) var usage = LogSegment<UsageRequestRecord>()
    private(set) var errors = LogSegment<RequestErrorRecord>()
    private(set) var upstream = LogSegment<RequestErrorRecord>()
    private(set) var refresh = BlockRefresh()
    /// The shown segment's rows by site day, made when they change.
    private(set) var sections: [LogSection<LogRowPresentation>] = []
    private(set) var isVisible = false
    /// The segments' counts (S4-05b).
    let counter: LogSegmentCounter

    @ObservationIgnored private let source: LogsSource
    @ObservationIgnored private let legacyServer: Bool
    @ObservationIgnored private let supportsModelSource: Bool
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let phoneClock: @MainActor () -> Date
    @ObservationIgnored private let opsDisabled: @MainActor () -> Bool
    @ObservationIgnored private let reportOps: @MainActor ((any Error)?) async -> Void
    /// Changes with every read and every reset; a reply carrying an older one is dropped.
    @ObservationIgnored private var ticket = UUID()
    // S4-06 自动刷新（40 §6.6）
    @ObservationIgnored private let supportsSinceID: Bool
    @ObservationIgnored private let policy: LogListPolicy
    @ObservationIgnored private let pollInterval: TimeInterval
    /// Increments since each cursor segment's last page 1 (upstream errors are never calibrated).
    @ObservationIgnored private var pollSchedules: [LogScope: LogPollSchedule] = [:]
    /// When each segment's last page 1 or poll ended, on the phone's clock: 00 §4.6 counts the interval from there.
    @ObservationIgnored private var lastPolls: [LogScope: Date] = [:]
    @ObservationIgnored private var isPolling = false
    /// The shown rows on screen, as LogsView's rows report appearing and going (List has no visible-row API).
    @ObservationIgnored private var visibleRows: Set<Int> = []
    /// A poll left more than N rows while the list was scrolled down: the tail goes once it is back near the top.
    @ObservationIgnored private var pendingTrim = false

    /// 40 §6.6: once a minute.
    static let standardPollInterval: TimeInterval = 60

    /// `now` is the server clock; `phoneNow` times the 429 wait, as BlockFailureRow counts it down and reads again on the phone's
    /// clock; `opsDisabled` the session's ops switch; `reportOps` hands each error read's outcome to LiveOpsStore (S1D1-02);
    /// `countSource` answers the segments' counts. `supportsSinceID` is `logs.since_id`; `policy` holds N and the page size.
    init(route: LogsRoute, generation: UUID, source: LogsSource, timeZone: ServerTimeZone, legacyServer: Bool, supportsModelSource: Bool,
         isCurrent: @escaping @MainActor () -> Bool, now: @escaping @MainActor () -> Date,
         phoneNow: @escaping @MainActor () -> Date = { Date() }, opsDisabled: @escaping @MainActor () -> Bool = { false },
         reportOps: @escaping @MainActor ((any Error)?) async -> Void = { _ in }, countSource: LogCountSource = .unavailable,
         supportsSinceID: Bool = false, policy: LogListPolicy = LogListPolicy(),
         pollInterval: TimeInterval = LogsStoreState.standardPollInterval) {
        self.generation = generation; self.timeZone = timeZone; self.source = source
        self.legacyServer = legacyServer; self.supportsModelSource = supportsModelSource
        self.isCurrent = isCurrent; self.clock = now; self.phoneClock = phoneNow
        self.opsDisabled = opsDisabled; self.reportOps = reportOps
        self.supportsSinceID = supportsSinceID; self.policy = policy; self.pollInterval = pollInterval
        counter = LogSegmentCounter(source: countSource) { await reportOps($0) }
        scope = route.scope
        conditions = route.conditions
    }

    func isStale(currentGeneration: UUID) -> Bool { generation != currentGeneration }
    func serverNow() -> Date { clock() }

    // MARK: Shown segment

    var chips: LogFilterChips { chips(for: scope) }
    /// The request's conditions: the greyed chips are left out (40 §6.4).
    func filter(for scope: LogScope, window: LogTimeWindow) -> RequestLogFilter {
        chips(for: scope).filter(time: window, pageSize: policy.pageSize)
    }
    /// The custom range sheet's first values.
    func currentWindow() -> LogTimeWindow { shown.window ?? time.window(now: clock()) }
    var phase: LogSegmentPhase { shown.phase }
    var hasRows: Bool { shown.hasRows }
    /// Nothing to show yet: not read, or page 1 on its way.
    var isFirstLoading: Bool { !hasRows && (phase == .idle || phase == .loading(page: 1)) }
    var isLoadingMore: Bool {
        guard case .loading(let page) = phase else { return false }
        return page > 1
    }
    var failure: LogListFailure? {
        switch phase {
        case .failed(let page): LogListFailure(page: page, error: shown.lastError, occurredAt: shown.lastErrorAt)
        case .refreshFailed: LogListFailure(page: 1, error: shown.lastError, occurredAt: shown.lastErrorAt)
        default: nil
        }
    }
    var showsOpsNotice: Bool { scope.errorKind != nil && (phase == .opsDisabled || opsDisabled()) }
    /// 40 §6.5 empty states.
    var emptyMessage: String? {
        guard phase == .loaded, !hasRows, !showsOpsNotice else { return nil }
        return time.emptyMessage(filtered: chips.hasAppliedConditions)
    }
    func timeTitle() -> String { time.title(timeZone: timeZone, now: clock()) }
    /// “<站点名> · 近 24 小时” (40 §6.1); `device` is `TimeZone.current`.
    func subtitle(siteName: String, device: TimeZone) -> String {
        time.subtitle(siteName: siteName, timeZone: timeZone, device: device, now: clock())
    }
    /// 40 §6.1: the row's record goes along to the detail.
    func requestRoute(for row: LogRowPresentation) -> RequestRoute? {
        switch scope {
        case .usage:
            return usage.rows.first { $0.id == row.id }.map { .usage(RoutePreload($0)) }
        case .errors, .upstream:
            let kind = scope.errorKind ?? .request
            return errorSegment(scope).rows.first { $0.id == row.id }.map { .error(id: $0.id, kind: kind, initial: RoutePreload($0)) }
        }
    }

    // MARK: Lifecycle

    /// Back from a detail no list is read, so the list keeps its place (40 §6.4); counts the background stopped while the page
    /// was away are asked (D18).
    func appeared() async {
        isVisible = true
        guard phase == .idle else { return resumeCounts(listReadsAgain: false) }
        await loadCounted(scope)
    }
    func disappeared() { isVisible = false }
    /// D18: a shown page polls at once while it auto-refreshes (40 §6.6), else reads its segment's page 1 again; only the
    /// counts the background stopped are asked.
    func foregroundResumed() async {
        guard isVisible else { return }
        guard autoRefreshes else {
            resumeCounts(listReadsAgain: true)
            return await loadFirstPage(scope)
        }
        resumeCounts(listReadsAgain: false)
        await refreshTick()
    }
    /// LiveOpsStore's switch moved: an error segment that ops monitoring held back reads once it is on, as on entering.
    func opsAvailabilityChanged() async {
        guard scope.errorKind != nil, phase == .opsDisabled, !opsDisabled() else { return }
        await loadCounted(scope)
    }

    // MARK: User actions

    /// Pull to refresh: page 1 in a new window and the counts again; the rows stay until it lands.
    func reload() async { await loadCounted(scope) }
    /// 40 §6.4: the conditions and the time stay; the segment starts again from page 1 and nothing is counted again.
    func select(_ scope: LogScope) async {
        guard scope != self.scope else { return }
        counter.leaving(self.scope)
        self.scope = scope
        ticket = UUID()
        reset(scope)
        visibleRows = []; pendingTrim = false
        refreshSections()
        await loadFirstPage(scope)
    }
    func setTime(_ preset: LogTimePreset) async {
        guard preset != time else { return }
        time = preset
        resetAll()
        await loadCounted(scope)
    }
    /// The one way to change the conditions (S4-05b's chips, S4-07's picker).
    func setConditions(_ conditions: LogConditions) async {
        guard conditions != self.conditions else { return }
        self.conditions = conditions
        resetAll()
        await loadCounted(scope)
    }
    /// The last row appeared: the next page, joined by id (40 §6.4).
    func loadMoreIfNeeded(after id: Int) async {
        guard isPollable, let next = shown.nextPage, sections.last?.rows.last?.id == id else { return }
        await load(scope, page: next, window: nextPageWindow())
    }
    /// A failed poll polls again (S4-06); a failed read reads its page again.
    func retry() async {
        guard let failure else { return }
        if phase == .refreshFailed { return await refreshTick() }
        if failure.page == 1 { await loadFirstPage(scope) } else { await load(scope, page: failure.page, window: nextPageWindow()) }
    }

    // MARK: Reads

    private var shown: any LogSegmentStatus {
        switch scope {
        case .usage: usage
        case .errors, .upstream: errorSegment(scope)
        }
    }
    private func chips(for scope: LogScope) -> LogFilterChips {
        LogFilterChips(conditions, kind: scope.errorKind, legacyServer: legacyServer, supportsModelSource: supportsModelSource)
    }
    private func errorSegment(_ scope: LogScope) -> LogSegment<RequestErrorRecord> { scope == .upstream ? upstream : errors }
    private func setErrorSegment(_ segment: LogSegment<RequestErrorRecord>, for scope: LogScope) {
        if scope == .upstream { upstream = segment } else { errors = segment }
    }
    /// S4D2a-05: a rolling preset pages against the data as it is now; a custom range keeps its bounds.
    private func nextPageWindow() -> LogTimeWindow { time.isRolling ? time.window(now: clock()) : currentWindow() }
    private func reset(_ scope: LogScope) {
        switch scope {
        case .usage: usage = LogSegment()
        case .errors, .upstream: setErrorSegment(LogSegment(), for: scope)
        }
    }
    private func resetAll() {
        ticket = UUID()
        usage = LogSegment(); errors = LogSegment(); upstream = LogSegment()
        visibleRows = []; pendingTrim = false
        refreshSections()
    }
    /// Page 1 of one segment in a new window, nothing else (S4-05b counts in the user's entries, S4-06 reloads through this).
    private func loadFirstPage(_ scope: LogScope) async { await load(scope, page: 1, window: time.window(now: clock())) }

    private func load(_ scope: LogScope, page: Int, window: LogTimeWindow) async {
        switch scope {
        case .usage:
            let fetch = source.usage
            await read(page: page, scope: scope, window: window, current: { usage }, update: { usage = $0 }, fetch: fetch)
        case .errors, .upstream:
            let fetch = source.errors, kind = scope.errorKind ?? .request
            await read(page: page, scope: scope, window: window, current: { errorSegment(scope) },
                       update: { setErrorSegment($0, for: scope) }, fetch: { try await fetch($0, $1, kind) })
        }
    }

    private func read<Record: IncrementalRecord & Decodable>(
        page: Int, scope: LogScope, window: LogTimeWindow, current: () -> LogSegment<Record>, update: (LogSegment<Record>) -> Void,
        fetch: @escaping @Sendable (Int, RequestLogFilter) async throws -> Page<Record>
    ) async {
        guard isCurrent() else { return }
        let isErrorSegment = scope.errorKind != nil
        if isErrorSegment, opsDisabled() {
            if page == 1 { counter.firstPageFailed(scope, error: nil) }
            return land(current().opsOff(), update: update)
        }
        guard refresh.allowsRequest(at: phoneClock()) else {
            if page == 1 { counter.firstPageFailed(scope, error: nil) }
            return holdBack(page: page, current: current, update: update)
        }
        let ticket = UUID()
        self.ticket = ticket
        update(current().starting(page: page, window: window))
        let filter = self.filter(for: scope, window: window)
        let result: Result<Page<Record>, any Error>
        do { result = .success(try await fetch(page, filter)) } catch { result = .failure(error) }
        guard ticket == self.ticket, isCurrent() else { return }
        if page == 1 { countFirstPage(scope, result) }
        switch result {
        case .success(let reply):
            refresh = refresh.recordingSuccess()
            land(current().applying(reply, page: page), update: update)
            if page == 1 { firstPageLanded(scope) }
            if isErrorSegment { await reportOps(nil) }
        // Only a read that never got its answer: a reply that came in counts, even for a caller that has gone.
        case .failure(let error) where error is CancellationError:
            land(current().interrupted(page: page), update: update)
        case .failure(let error) where isErrorSegment && AccountUpstreamErrors.isOpsDisabled(error):
            land(current().opsOff(), update: update)
            await reportOps(error)
        case .failure(let error):
            refresh = refresh.recordingFailure(error, at: phoneClock())
            land(current().failing(page: page, error: error, at: clock()), update: update)
        }
    }
    /// A read the 429 wait held back shows as failed, so the failure row counts down and reads again (BlockFailureRow).
    private func holdBack<Record: IncrementalRecord & Decodable>(page: Int, current: () -> LogSegment<Record>, update: (LogSegment<Record>) -> Void) {
        if case .failed = current().phase { return }
        land(current().failing(page: page, error: nil, at: clock()), update: update)
    }
    private func land<Record: IncrementalRecord & Decodable>(_ segment: LogSegment<Record>, update: (LogSegment<Record>) -> Void) {
        update(segment)
        refreshSections()
    }
    /// After the shown segment's rows change (S4-06 and S4-08b call it too).
    private func refreshSections() {
        let rows = switch scope {
        case .usage: LogRowPresentation.rows(usage.rows, timeZone: timeZone)
        case .errors: LogRowPresentation.rows(errors.rows, kind: .request, timeZone: timeZone)
        case .upstream: LogRowPresentation.rows(upstream.rows, kind: .upstream, timeZone: timeZone)
        }
        let made = LogSections.make(rows, timeZone: timeZone, now: clock())
        if made != sections { sections = made }
    }
}

// MARK: - S4-05b 计数与条件

extension LogsStoreState {
    /// The empty state's “这些条件下” and “清除筛选”: a condition the shown segment applies (40 §6.5).
    var hasAppliedConditions: Bool { chips.hasAppliedConditions }
    /// 40 §6.5: an error segment over a range starting more than 30 days ago, unless ops monitoring is off.
    var retentionNote: String? {
        guard !showsOpsNotice, time.showsRetentionNotice(kind: scope.errorKind, now: clock()) else { return nil }
        return LogListCopy.retentionNotice
    }
    /// 40 §6.3: tapping a chip, greyed or not, drops its condition; the list and the counts start again.
    func removeCondition(_ kind: LogFilterKind) async { await setConditions(conditions.removing(kind)) }
    /// 40 §6.5 清除筛选: every condition goes; the time and the segment stay.
    func clearConditions() async { await setConditions(LogConditions()) }

    /// The user's entries (40 §6.6): page 1 and a new round of counts over the same window.
    private func loadCounted(_ scope: LogScope) async {
        let window = time.window(now: clock())
        if isCurrent() { counter.begin(countPlan(window: window), holdingBack: countsHeldBack) }
        await load(scope, page: 1, window: window)
    }
    private func resumeCounts(listReadsAgain: Bool) {
        counter.resumeInterrupted(listReadsAgain: listReadsAgain, holdingBack: countsHeldBack)
    }
    /// 00 §2.7.2: the counts are this page's reads too, so its 429 wait holds them back.
    private var countsHeldBack: Bool { !refresh.allowsRequest(at: phoneClock()) }
    /// Each segment's request conditions without its greyed chips; usage counts over the site's zone.
    private func countPlan(window: LogTimeWindow) -> LogCountPlan {
        LogCountPlan(usage: LogListPolicy.usageCountQuery(filter(for: .usage, window: window), timeZone: timeZone),
                     errors: filter(for: .errors, window: window), upstream: filter(for: .upstream, window: window),
                     current: scope, opsAvailable: !opsDisabled())
    }
    /// The shown error segment's count is its page 1's `total` (40 §6.2).
    private func countFirstPage<Record: IncrementalRecord & Decodable>(_ scope: LogScope, _ result: Result<Page<Record>, any Error>) {
        switch result {
        case .success(let reply): counter.firstPageLoaded(scope, total: reply.total)
        case .failure(let error): counter.firstPageFailed(scope, error: error)
        }
    }
}

extension LogListFailure {
    /// 40 §6.5 “400 其他（参数）”: a 400 other than since_id's two (S4-06 reads page 1 again for those), or the check before
    /// sending.
    var isInvalidParameters: Bool {
        guard let error else { return false }
        if error.statusCode == 400 { return !IncrementalPolicy.shouldRestartFromFirstPage(error) }
        return error.statusCode == nil && error.kind == .validation
    }
}

// MARK: - S4-06 自动刷新（40 §6.6）

/// What one poll reads (00 §4.3): past the cursor, step 7's time window, page 1 joined in (calibration), or page 1 in place
/// of rows with nothing to continue from.
private enum LogPollFetch {
    case since(Int, RequestLogFilter)
    case window(RequestLogFilter)
    case calibration(RequestLogFilter)
    case firstPage(RequestLogFilter)
}

extension LogsStoreState {
    /// 40 §6.6: a rolling preset over a segment that has loaded, unless ops monitoring holds it back. LogsView polls while this
    /// holds, the page shows and the App is active.
    var autoRefreshes: Bool {
        guard time.isRolling, !showsOpsNotice else { return false }
        return hasRows || isPollable
    }

    /// 00 §4.6: polls the shown segment for as long as the caller's task lives (LogsView keys it on D18's scene phase).
    func autoRefreshPolling() async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(max(1, nextAutoRefreshDelay()))) } catch { return }
            if nextAutoRefreshDelay() <= 0 { await refreshTick() }
        }
    }
    /// The rest of a 429 wait; otherwise the interval, doubled after failures up to 300 seconds (00 §4.6), less the time since
    /// the shown segment's last read ended. A poll on its way, or a segment not ready for one, waits a whole interval.
    func nextAutoRefreshDelay() -> TimeInterval {
        let now = phoneClock()
        guard !isPolling, isPollable, let last = lastPolls[scope] else { return pollInterval }
        guard refresh.allowsRequest(at: now) else { return refresh.nextDelay(base: pollInterval, at: now) }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed >= 0 else { return 0 }
        return max(0, BlockRefresh.nextRefreshInterval(base: pollInterval, consecutiveFailures: refresh.consecutiveFailures) - elapsed)
    }
    /// One poll of the shown segment (40 §6.6): new rows join on top and the counts stay. has_more, more than one page and
    /// since_id's two 400s read page 1 again without a word; other failures keep the rows and say so at the list's end.
    func refreshTick() async {
        guard autoRefreshes, isVisible, isPollable, !isPolling, isCurrent(), refresh.allowsRequest(at: phoneClock()) else { return }
        let scope = self.scope
        isPolling = true
        defer { isPolling = false; lastPolls[scope] = phoneClock() }
        switch scope {
        case .usage:
            await poll(scope, current: { usage }, update: { usage = $0 }, page: source.usage, since: source.usageSince)
        case .errors, .upstream:
            let page = source.errors, kind = scope.errorKind ?? .request
            await poll(scope, current: { errorSegment(scope) }, update: { setErrorSegment($0, for: scope) },
                       page: { try await page($0, $1, kind) }, since: source.errorsSince)
        }
    }
    /// LogsView's rows report showing and going; the first shown one stands for the scroll position (S4D2a-06). A trim a poll
    /// left waiting lands once the list is near the top again.
    func rowAppeared(_ id: Int) {
        visibleRows.insert(id)
        guard pendingTrim else { return }
        switch scope {
        case .usage:
            trimNearTop(current: { usage }, update: { usage = $0 })
        case .errors, .upstream:
            let scope = scope
            trimNearTop(current: { errorSegment(scope) }, update: { setErrorSegment($0, for: scope) })
        }
    }
    func rowDisappeared(_ id: Int) { visibleRows.remove(id) }

    /// Loaded, its last poll perhaps failed: nothing of the segment is on its way.
    private var isPollable: Bool { phase == .loaded || phase == .refreshFailed }

    private func poll<Record: IncrementalRecord & Decodable>(
        _ scope: LogScope, current: () -> LogSegment<Record>, update: (LogSegment<Record>) -> Void,
        page: @escaping @Sendable (Int, RequestLogFilter) async throws -> Page<Record>, since: @escaping LogsSource.CursorRead<Record>
    ) async {
        let window = time.window(now: clock()), ticket = self.ticket
        let fetch = pollFetch(scope, list: current().list, base: filter(for: scope, window: window))
        let result: Result<Page<Record>, any Error>
        do { result = .success(try await readPoll(fetch, page: page, since: since)) } catch { result = .failure(error) }
        // A reset, another read, an ended session or a page left since: the reply belongs to rows no longer shown.
        guard ticket == self.ticket, isCurrent(), !Task.isCancelled else { return }
        switch result {
        case .success(let reply):
            refresh = refresh.recordingSuccess()
            await pollLanded(reply, of: fetch, scope: scope, window: window, current: current, update: update)
            if scope.errorKind != nil { await reportOps(nil) }
        case .failure(let error):
            await pollFailed(error, scope: scope, current: current, update: update)
        }
    }
    /// 00 §4.3: past the cursor with `logs.since_id`, else step 7's window. Upstream errors always read the window and are never
    /// calibrated; every tenth increment of the others re-reads page 1 (40 §6.6).
    private func pollFetch<Record: IncrementalRecord>(_ scope: LogScope, list: IncrementalList<Record>,
                                                      base: RequestLogFilter) -> LogPollFetch {
        let hasCursor = scope != .upstream
        if hasCursor, pollSchedule(scope).next == .calibration { return .calibration(base) }
        if hasCursor, supportsSinceID {
            guard case .since(let id) = list.nextFetch(supportsSinceID: true, now: clock()) else { return .firstPage(base) }
            return .since(id, base)
        }
        guard let window = LogListPolicy.fallbackRefreshFilter(after: list, base: base, now: clock()) else { return .firstPage(base) }
        return .window(window)
    }
    private func readPoll<Record: IncrementalRecord & Decodable>(
        _ fetch: LogPollFetch, page: @Sendable (Int, RequestLogFilter) async throws -> Page<Record>, since: LogsSource.CursorRead<Record>
    ) async throws -> Page<Record> {
        switch fetch {
        case .since(let id, let filter): return try await since(id, filter)
        case .window(let filter), .calibration(let filter), .firstPage(let filter): return try await page(1, filter)
        }
    }
    private func pollLanded<Record: IncrementalRecord & Decodable>(_ reply: Page<Record>, of fetch: LogPollFetch, scope: LogScope,
                                                                    window: LogTimeWindow, current: () -> LogSegment<Record>,
                                                                    update: (LogSegment<Record>) -> Void) async {
        let list = current().list
        switch fetch {
        case .since:
            await stepped(list.applyingIncrement(reply.items, hasMore: reply.hasMore, latestID: reply.latestID), scope: scope,
                          current: current, update: update)
        case .window:
            await stepped(LogListPolicy.fallbackRefreshStep(list, reply: reply), scope: scope, current: current, update: update)
        case .calibration:
            recordPoll(.calibration, for: scope)
            landMerged(list.merging(reply.items, latestID: nil), current: current, update: update)
        case .firstPage:
            land(current().reloaded(reply, window: window), update: update)
            firstPageLanded(scope)
        }
    }
    /// has_more, or more than one page, left a gap: page 1 again, without counts (S4D2a-01).
    private func stepped<Record: IncrementalRecord & Decodable>(_ step: IncrementalStep<Record>, scope: LogScope,
                                                                 current: () -> LogSegment<Record>,
                                                                 update: (LogSegment<Record>) -> Void) async {
        switch step {
        case .reloadFirstPage:
            await loadFirstPage(scope)
        case .merged(let merged):
            recordPoll(.increment, for: scope)
            landMerged(merged, current: current, update: update)
        }
    }
    /// 00 §4.3 step 6 and 40 §6.5: since_id's two 400s read page 1 again unseen; a cancelled poll is let go; OPS_DISABLED shows
    /// the notice; anything else keeps the rows, says so and stretches the interval (00 §4.6).
    private func pollFailed<Record: IncrementalRecord & Decodable>(_ error: any Error, scope: LogScope,
                                                                    current: () -> LogSegment<Record>,
                                                                    update: (LogSegment<Record>) -> Void) async {
        if IncrementalPolicy.shouldRestartFromFirstPage(error) { return await loadFirstPage(scope) }
        if error is CancellationError { return }
        if scope.errorKind != nil, AccountUpstreamErrors.isOpsDisabled(error) {
            land(current().opsOff(), update: update)
            return await reportOps(error)
        }
        refresh = refresh.recordingFailure(error, at: phoneClock())
        land(current().refreshFailing(error, at: clock()), update: update)
    }

    /// After a poll's merge (40 §6.6): rows made before the window's start go; past N the tail goes near the top, and waits for
    /// the way back up while the list is scrolled down.
    private func landMerged<Record: IncrementalRecord & Decodable>(_ merged: IncrementalList<Record>,
                                                                    current: () -> LogSegment<Record>,
                                                                    update: (LogSegment<Record>) -> Void) {
        let kept = LogListPolicy.pruned(merged, to: time.window(now: clock()))
        let trim = policy.trimmed(kept, firstVisibleIndex: firstVisibleIndex(in: kept.items))
        pendingTrim = trim == nil && kept.items.count > policy.limit
        let segment = current().refreshed(kept)
        land(trim.map(segment.trimmed) ?? segment, update: update)
    }
    private func trimNearTop<Record: IncrementalRecord & Decodable>(current: () -> LogSegment<Record>,
                                                                     update: (LogSegment<Record>) -> Void) {
        let segment = current()
        guard isPollable, let trim = policy.trimmed(segment.list, firstVisibleIndex: firstVisibleIndex(in: segment.rows)) else { return }
        pendingTrim = false
        land(segment.trimmed(trim), update: update)
    }
    /// nil, the top, until a row shows; while the page is away a trim waits for it to show again.
    private func firstVisibleIndex<Record: IncrementalRecord>(in rows: [Record]) -> Int? {
        guard isVisible else { return Int.max }
        return rows.firstIndex { visibleRows.contains($0.id) }
    }
    /// Any page 1 restarts the calibration count, the interval and a waiting trim (40 §6.6).
    private func firstPageLanded(_ scope: LogScope) {
        recordPoll(.calibration, for: scope)
        lastPolls[scope] = phoneClock()
        pendingTrim = false
    }
    private func pollSchedule(_ scope: LogScope) -> LogPollSchedule { pollSchedules[scope] ?? LogPollSchedule() }
    /// Upstream errors keep no schedule: each of their polls already reads page 1 (S4D2a-04).
    private func recordPoll(_ read: LogPollRead, for scope: LogScope) {
        guard scope != .upstream else { return }
        pollSchedules[scope] = pollSchedule(scope).recording(read)
    }
}
