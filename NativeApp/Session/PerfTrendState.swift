import Foundation
import Observation
import Sub2Core

extension AnalyticsCardKey {
    /// 40 §1.4 RPM / TPM (PerformanceTrend): its own rolling window, so a range change keeps it and a filter change clears it.
    static let perf = AnalyticsCardKey("perf", scope: .filterOnly)
}

extension PerfMetric {
    var performanceMetric: PerformanceMetric { self == .rpm ? .rpm : .tpm }
}

/// The card's link to the session's ops switch (S4D2b-06): AppModel.analyticsOpsDisabled and recordAnalyticsOpsResponse in the App,
/// stubs in the tests.
struct PerfOpsHooks {
    let isDisabled: @MainActor () -> Bool
    /// A new success passes nil, a new 404 OPS_DISABLED its error.
    let record: @MainActor (_ error: (any Error)?) async -> Void
}

/// 40 §1.4 / §1.5 / §1.7 RPM / TPM 趋势's state, one per PerfTrendBody: the window and the metric remembered per site and shared by
/// every place showing the chart (route.metric wins once and is written back), the read of the session's `.perf` card, the selected
/// bucket kept by its date, ops off and the 30-second polling's next wait.
@MainActor @Observable
final class PerfTrendState {
    typealias Fixture = @MainActor @Sendable (_ hours: Int) async throws -> PerformanceTrend

    let session: AnalyticsSessionState
    private(set) var window: PerfWindow
    private(set) var metric: PerfMetric
    /// The selected bucket's start; a refresh that no longer has it shows none.
    private(set) var selectedDate: Date?
    /// The chart gesture's state (AnalyticsChartSelection over the points' indices).
    private var gesture = AnalyticsChartSelection()
    @ObservationIgnored private var routeMetric: PerfMetric?
    @ObservationIgnored private let memory: AnalyticsMemory
    @ObservationIgnored private let hooks: PerfOpsHooks
    @ObservationIgnored private let fixture: Fixture

    /// Reads the memory without writing it; `startMetric` (route.metric) is written back on the first `appear()`.
    init(session: AnalyticsSessionState, memory: AnalyticsMemory, startMetric: PerfMetric?, hooks: PerfOpsHooks, fixture: @escaping Fixture) {
        self.session = session; self.memory = memory; self.hooks = hooks; self.fixture = fixture
        window = memory.perfWindow(serverID: session.serverID)
        metric = startMetric ?? memory.perfMetric(serverID: session.serverID, route: nil)
        routeMetric = startMetric
    }

    var loadState: LoadState<PerformanceTrend>? { session.state(.perf, as: PerformanceTrend.self) }
    /// The session's value when it answers this window (another page may have just read another).
    var trend: PerformanceTrend? {
        guard let value = loadState?.value, PerfTrendPresentation.windowHours(value) == window.hours else { return nil }
        return value
    }
    var performanceMetric: PerformanceMetric { metric.performanceMetric }
    var selectedPoint: PerformanceTrend.Point? { selectedIndex.flatMap { trend?.points[$0] } }
    /// For the chart's `analyticsChartSelection`: the gesture's state while it still names the selected bucket.
    var chartSelection: AnalyticsChartSelection {
        get {
            guard let index = selectedIndex else { return AnalyticsChartSelection() }
            return gesture.selected == index ? gesture : AnalyticsChartSelection(selected: index)
        }
        set {
            gesture = newValue
            let points = trend?.points ?? []
            selectedDate = newValue.selected.flatMap { points.indices.contains($0) ? points[$0].date : nil }
        }
    }
    var isOpsDisabled: Bool { hooks.isDisabled() }
    /// Ops off, or a read answered 404 OPS_DISABLED while LiveOpsStore still believes it on (just turned on elsewhere).
    var showsOpsNotice: Bool { isOpsDisabled || answeredOpsDisabled }

    // MARK: Choices

    /// Each time the chart shows: the route's metric the first time, then whatever another page chose meanwhile.
    func appear() {
        metric = memory.perfMetric(serverID: session.serverID, route: routeMetric)
        routeMetric = nil
        let remembered = memory.perfWindow(serverID: session.serverID)
        guard remembered != window else { return }
        window = remembered
        clearSelection()
    }
    /// 40 §1.7 切窗口立即重载: the card's value goes, so every place showing it reads the new window.
    func selectWindow(_ window: PerfWindow) {
        guard window != self.window else { return }
        self.window = window
        memory.setPerfWindow(window, serverID: session.serverID)
        session.reset(.perf)
        clearSelection()
    }
    /// The selection stays (the design's).
    func selectMetric(_ metric: PerfMetric) {
        guard metric != self.metric else { return }
        self.metric = metric
        memory.setPerfMetric(metric, serverID: session.serverID)
    }
    /// The chart's gesture: the bucket under it, nil when it ends (AnalyticsChartSelection.receiving).
    func receive(_ index: Int?) { chartSelection = chartSelection.receiving(index) }
    /// A row of 性能明细.
    func select(_ point: PerformanceTrend.Point) {
        guard let index = trend?.points.firstIndex(of: point) else { return }
        chartSelection = AnalyticsChartSelection(selected: index)
    }
    /// A window or filter change (40 §1.5); a range change keeps it.
    func clearSelection() {
        gesture = AnalyticsChartSelection()
        selectedDate = nil
    }

    // MARK: Reads

    /// `ops/dashboard/throughput-trend` over the window ending at the server's minute, with the session's filter; nothing while ops
    /// is off. A kept value under a 404 OPS_DISABLED is read again (ops back on). Only a result this read brought is reported: a
    /// success, or a 404 OPS_DISABLED (S4D2b-06).
    func load(refresh: Bool) async {
        guard !isOpsDisabled else { return }
        if trend == nil, session.hasValue(.perf) { session.reset(.perf) }
        let hours = window.hours, fixture = fixture
        let updatedBefore = loadState?.updatedAt, failedBefore = loadState?.lastErrorAt
        await session.load(.perf, refresh: refresh || answeredOpsDisabled, fixture: { _ in try await fixture(hours) }) { client, session in
            let window = OpsQuery.trailingWindow(hours: hours, endingAt: client.serverClock.now())
            return try await client.dashboardPerformanceTrend(session.opsQuery(start: window.start, end: window.end),
                                                              supportsModelFilter: session.supportsOpsModelFilter)
        }
        guard let state = loadState else { return }
        if let updated = state.updatedAt, updated != updatedBefore {
            await hooks.record(nil)
        } else if let failed = state.lastErrorAt, failed != failedBefore, let error = state.lastError, AccountUpstreamErrors.isOpsDisabled(error) {
            await hooks.record(error)
        }
    }
    /// How long the 30-second loop waits before reading again, from the last success or failure (a pull to refresh moves it on);
    /// 0 when no read answered yet; nil stops it: ops off, or a 400 / 403. A 429 waits its time, failures back off, except a 404
    /// OPS_DISABLED with ops on: other instances catch up within 30 seconds.
    func pollDelay(now: Date) -> TimeInterval? {
        guard !isOpsDisabled else { return nil }
        guard let load = loadState else { return 0 }
        if load.error != nil, PerfTrendPresentation.stopsPolling(after: load.lastError) { return nil }
        let base = PerfTrendPresentation.refreshInterval
        if !load.refresh.allowsRequest(at: now) { return load.refresh.nextDelay(base: base, at: now) }
        let failures = answeredOpsDisabled ? 0 : load.refresh.consecutiveFailures
        let interval = BlockRefresh.nextRefreshInterval(base: base, consecutiveFailures: failures)
        let last = [trend == nil ? nil : load.updatedAt, load.lastErrorAt].compactMap { $0 }.max()
        return PerfTrendPresentation.pollDelay(since: last, now: now, interval: interval)
    }

    private var answeredOpsDisabled: Bool { loadState?.lastError.map(AccountUpstreamErrors.isOpsDisabled) == true }
    private var selectedIndex: Int? {
        guard let selectedDate else { return nil }
        return trend?.points.firstIndex { $0.date == selectedDate }
    }
}
