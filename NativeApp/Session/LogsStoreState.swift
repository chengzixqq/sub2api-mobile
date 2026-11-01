import Foundation
import Observation
import Sub2Core

/// 40 §6.2: the page's two list reads, or the UI-test fixtures (LogFixtures).
struct LogsSource: Sendable {
    let usage: @Sendable (_ page: Int, _ filter: RequestLogFilter) async throws -> Page<UsageRequestRecord>
    let errors: @Sendable (_ page: Int, _ filter: RequestLogFilter, _ kind: ErrorLogKind) async throws -> Page<RequestErrorRecord>

    /// R19's methods; `key_view=masked` only with the site's `api_keys.masked_view` (S4D1-06).
    static func live(_ client: APIClient, site: SiteSession) -> LogsSource {
        let masked = site.has(.apiKeysMaskedView)
        return LogsSource(usage: { try await client.requestRecords(page: $0, filter: $1, maskedView: masked) },
                          errors: { try await client.errorRecords(page: $0, filter: $1, kind: $2) })
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
/// the last row reads the next page. Nothing goes out during a 429 wait (00 §2.7.2), and the error segments send nothing while
/// ops monitoring is off. A reply of an older read or session is dropped.
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

    /// `now` is the server clock; `phoneNow` times the 429 wait, as BlockFailureRow counts it down and reads again on the phone's
    /// clock; `opsDisabled` the session's ops switch; `reportOps` hands each error read's outcome to LiveOpsStore (S1D1-02);
    /// `countSource` answers the segments' counts.
    init(route: LogsRoute, generation: UUID, source: LogsSource, timeZone: ServerTimeZone, legacyServer: Bool, supportsModelSource: Bool,
         isCurrent: @escaping @MainActor () -> Bool, now: @escaping @MainActor () -> Date,
         phoneNow: @escaping @MainActor () -> Date = { Date() }, opsDisabled: @escaping @MainActor () -> Bool = { false },
         reportOps: @escaping @MainActor ((any Error)?) async -> Void = { _ in }, countSource: LogCountSource = .unavailable) {
        self.generation = generation; self.timeZone = timeZone; self.source = source
        self.legacyServer = legacyServer; self.supportsModelSource = supportsModelSource
        self.isCurrent = isCurrent; self.clock = now; self.phoneClock = phoneNow
        self.opsDisabled = opsDisabled; self.reportOps = reportOps
        counter = LogSegmentCounter(source: countSource) { await reportOps($0) }
        scope = route.scope
        conditions = route.conditions
    }

    func isStale(currentGeneration: UUID) -> Bool { generation != currentGeneration }
    func serverNow() -> Date { clock() }

    // MARK: Shown segment

    var chips: LogFilterChips { chips(for: scope) }
    /// The request's conditions: the greyed chips are left out (40 §6.4).
    func filter(for scope: LogScope, window: LogTimeWindow) -> RequestLogFilter { chips(for: scope).filter(time: window) }
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
        guard case .failed(let page) = phase else { return nil }
        return LogListFailure(page: page, error: shown.lastError, occurredAt: shown.lastErrorAt)
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

    /// Back from a detail nothing is read, so the list keeps its place (40 §6.4).
    func appeared() async {
        isVisible = true
        guard phase == .idle else { return }
        await loadCounted(scope)
    }
    func disappeared() { isVisible = false }
    /// D18: a shown page reads its segment's page 1 again, and only the counts the background stopped.
    func foregroundResumed() async {
        guard isVisible else { return }
        counter.resumeInterrupted()
        await loadFirstPage(scope)
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
        guard phase == .loaded, let next = shown.nextPage, sections.last?.rows.last?.id == id else { return }
        await load(scope, page: next, window: nextPageWindow())
    }
    func retry() async {
        guard let failure else { return }
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
        if isCurrent() { counter.begin(countPlan(window: window)) }
        await load(scope, page: 1, window: window)
    }
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
