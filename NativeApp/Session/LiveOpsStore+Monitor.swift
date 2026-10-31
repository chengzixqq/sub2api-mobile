import Foundation
import Observation
import Sub2Core

// S1-13, 10 §4: the monitor tab's session state. The segment chosen is kept for the session (U08); the overview's blocks are
// read side by side, each on its own timer and backoff while 概况 shows (10 §4.6, 00 §4.6). Every read is ops-gated and goes
// through `controlled(_:)`, so its 200 or 404 OPS_DISABLED is the switch's evidence (S1D1-02). S1-14 adds the server section's
// blocks below the MARKs.

/// The overview's blocks; each has its own timer.
enum MonitorOverviewBlock: CaseIterable, Sendable {
    /// `ops/dashboard/overview` (time_range 5m), with the firing list beside it for 告警中.
    case run
    /// `snapshot-v2` over the last 45 minutes, for the error-rate line.
    case errorTrend
    // S1-14 · 服务器区（LiveOpsStore+MonitorServer.swift）: only for the site owner (10 §0.1), each while it applies.
    /// `system-metrics/history` (1h, 60 points), with `ops.system_metrics_history`.
    case systemMetrics
    /// `ops/concurrency`.
    case concurrency
    /// `system-logs/health`.
    case logHealth
    /// `ingress-rejections` over the last hour: the total, or up to three pages added up.
    case ingress
}

@MainActor @Observable
final class MonitorState {
    /// U08: the segment chosen this session. A new session (another site, signing in again) makes a new store, which opens on 概况.
    var segment: MonitorSegment = .overview
    let overview = LoadState<OpsOverview>()
    /// Nine five-minute error rates, oldest first; nil where nothing counted, which breaks the line.
    let errorTrend = LoadState<[Double?]>()
    // S1-14 · 服务器区
    let systemMetrics = LoadState<SystemMetricsHistory>()
    let concurrency = LoadState<OpsConcurrency>()
    let logHealth = LoadState<SystemLogHealth>()
    let ingress = LoadState<MonitorPresentation.IngressRejectTally>()
    /// Without `ops.system_metrics_history`: the overview's snapshot after each read, at most 60 (10 §4.3). The store is made again
    /// for another site, so they start empty there.
    private(set) var localSamples: [SystemMetricsHistory.Point] = []
    /// Routes this site lacks (a non-JSON 404): not read again this session (00 §5 item 3).
    private(set) var unsupportedBlocks: Set<MonitorOverviewBlock> = []
    /// Each block's last answer, success or failure, on the store's device clock.
    @ObservationIgnored private var settled: [MonitorOverviewBlock: MonitorSettle] = [:]
    // S1-15 · 渠道段（LiveOpsStore+Channels.swift）
    /// The last channel answer's 403 CHANNEL_MONITOR_DISABLED; a success clears it, another failure leaves it.
    private(set) var channelsDisabledReason: String?
    /// When the last channel answer came in, on the store's device clock.
    @ObservationIgnored private(set) var channelsSettledAt: Date?
    /// The overview answered a non-JSON 404 (no channel-monitor-v2): not asked again this session (00 §3.3).
    private(set) var channelsUnsupported = false
    // S1-16 · 告警段（LiveOpsStore+MonitorAlerts.swift）
    /// 加载更早 itself: its wait, backoff and failure; its value is the last older page read.
    let alertsEarlier = LoadState<[AlertEvent]>()
    /// When the alert lists last answered, on the store's device clock.
    @ObservationIgnored private(set) var alertsSettledAt: MonitorSettle?

    /// What the timers ask of a block's LoadState; S1-14 adds its blocks to this one switch.
    func load(_ block: MonitorOverviewBlock) -> MonitorBlockLoad {
        switch block {
        case .run: MonitorBlockLoad(overview)
        case .errorTrend: MonitorBlockLoad(errorTrend)
        case .systemMetrics: MonitorBlockLoad(systemMetrics)
        case .concurrency: MonitorBlockLoad(concurrency)
        case .logHealth: MonitorBlockLoad(logHealth)
        case .ingress: MonitorBlockLoad(ingress)
        }
    }
    /// The wait after this block's read: the rest of a 429 wait, otherwise `base` backed off by its failures.
    func nextDelay(for block: MonitorOverviewBlock, base: TimeInterval) -> TimeInterval {
        load(block).refresh.nextDelay(base: base, at: Date())
    }
    func settledAt(_ block: MonitorOverviewBlock) -> MonitorSettle? { settled[block] }
    func markSettled(_ block: MonitorOverviewBlock, _ settle: MonitorSettle) { settled[block] = settle }
    /// For the subtitle's freshness.
    func snapshot(_ block: MonitorOverviewBlock) -> MonitorBlockSnapshot {
        switch block {
        case .run: MonitorBlockSnapshot(overview.state)
        case .errorTrend: MonitorBlockSnapshot(errorTrend.state)
        case .systemMetrics: MonitorBlockSnapshot(systemMetrics.state)
        case .concurrency: MonitorBlockSnapshot(concurrency.state)
        case .logHealth: MonitorBlockSnapshot(logHealth.state)
        case .ingress: MonitorBlockSnapshot(ingress.state)
        }
    }
    func recordLocalSample(_ metrics: OpsSystemMetricsSnapshot?) {
        localSamples = MonitorPresentation.appendingLocalSample(localSamples, from: metrics)
    }
    func markUnsupported(_ block: MonitorOverviewBlock) { unsupportedBlocks.insert(block) }
    /// Only LiveOpsStore+Channels.swift calls these, once an answer landed; an unchanged reason is not written again.
    func recordChannelsReply(disabledReason: String?) {
        if channelsDisabledReason != disabledReason { channelsDisabledReason = disabledReason }
    }
    func markChannelsSettled(at date: Date) { channelsSettledAt = date }
    func markChannelsUnsupported() { channelsUnsupported = true }
    /// Only LiveOpsStore+MonitorAlerts.swift calls it, once an answer landed.
    func markAlertsSettled(_ settle: MonitorSettle) { alertsSettledAt = settle }
}

/// One block's LoadState as the timers see it.
struct MonitorBlockLoad: Sendable {
    /// A request whose answer can still land; one left by cancelled timers does not count, and is replaced.
    let isAwaitingAnswer: Bool
    /// max(updatedAt, lastErrorAt), on LoadState's clock; a read cancelled, replaced or held back by a 429 wait leaves it.
    let answeredAt: Date?
    let lastError: APIError?
    let refresh: BlockRefresh

    @MainActor init<Value: Sendable>(_ load: LoadState<Value>) {
        isAwaitingAnswer = load.isAwaitingAnswer
        answeredAt = [load.updatedAt, load.lastErrorAt].compactMap { $0 }.max()
        lastError = load.lastError
        refresh = load.refresh
    }
}

/// When a block's last answer came in, and whether ops monitoring was on after it.
struct MonitorSettle: Sendable, Equatable {
    let at: Date
    let opsOn: Bool
}

extension LiveOpsStore {
    /// Coming back to 概况 within this many seconds of a block's last answer waits out the rest before reading it again.
    nonisolated static let monitorReentryGap: TimeInterval = 10

    // MARK: - 读取与轮询（10 §4.6）

    /// A pull or ··· 刷新: every block at once, even one in flight, with the firing list read again. It asks even while the switch
    /// says off, so a 200 can turn it back on.
    func refreshMonitorOverview(force: Bool) async {
        let blocks = MonitorOverviewBlock.allCases.filter(monitorBlockApplies)
        await withDiscardingTaskGroup { group in
            for block in blocks {
                group.addTask { await self.refreshMonitorBlock(block, force: force) }
            }
        }
    }
    /// While the caller's task lives: each block on its own timer, counted from the end of its read. A block answered under ten
    /// seconds ago while monitoring was on waits out the rest first; the timers end once ops monitoring is off or the session ended.
    func monitorOverviewPolling() async {
        let blocks = MonitorOverviewBlock.allCases.filter(monitorBlockApplies)
        await withDiscardingTaskGroup { group in
            for block in blocks {
                group.addTask { await self.pollMonitorBlock(block) }
            }
        }
    }
    /// One block; without `force` a block whose answer can still land is left to finish, and nothing is read while the switch
    /// says off. Only an answer counts as the block's last read; a cancelled one does not.
    func refreshMonitorBlock(_ block: MonitorOverviewBlock, force: Bool) async {
        guard isCurrent(), site() != nil, monitorBlockApplies(block),
              force || (!opsDisabled && !monitor.load(block).isAwaitingAnswer) else { return }
        let answered = monitor.load(block).answeredAt
        switch block {
        case .run:
            async let overview: Void = loadMonitorOverview()
            async let firing: Void = refreshFiringAlerts(maxAge: force ? 0 : Self.alertListMaxAge)
            _ = await (overview, firing)
            recordMonitorLocalSample()
        case .errorTrend:
            await loadErrorTrend()
        case .systemMetrics, .concurrency, .logHealth, .ingress:
            await refreshMonitorServerBlock(block)
        }
        guard isCurrent(), monitor.load(block).answeredAt != answered else { return }
        monitor.markSettled(block, MonitorSettle(at: localNow(), opsOn: !opsDisabled))
    }

    private func pollMonitorBlock(_ block: MonitorOverviewBlock) async {
        guard !opsDisabled else { return }
        if let wait = monitorReentryWait(block) {
            do { try await sleep(.seconds(wait)) } catch { return }
        }
        while !Task.isCancelled, isCurrent(), !opsDisabled, monitorBlockApplies(block) {
            await refreshMonitorBlock(block, force: false)
            guard !opsDisabled else { return }
            do { try await sleep(.seconds(monitorPollDelay(block))) } catch { return }
        }
    }
    /// 10 §7.2 step 3: an off answer the switch did not believe (it was turned on under 30 seconds ago) is asked again within 30
    /// seconds instead of backing off.
    private func monitorPollDelay(_ block: MonitorOverviewBlock) -> TimeInterval {
        let delay = monitor.nextDelay(for: block, base: Self.pollInterval)
        guard let error = monitor.load(block).lastError, error.statusCode == 404, error.reason == Self.opsDisabledReason else { return delay }
        return min(delay, OpsSwitchState.recheckDelay)
    }
    /// The rest of `monitorReentryGap` since the block's last answer; nil once it passed, or when that answer left monitoring off
    /// (10 §7.2 step 3: once it is on again every block is read at once).
    private func monitorReentryWait(_ block: MonitorOverviewBlock) -> TimeInterval? {
        guard let settled = monitor.settledAt(block), settled.opsOn else { return nil }
        let elapsed = localNow().timeIntervalSince(settled.at)
        guard elapsed >= 0, elapsed < Self.monitorReentryGap else { return nil }
        return Self.monitorReentryGap - elapsed
    }
    private func loadMonitorOverview() async {
        let range = MonitorTabPresentation.overviewTimeRange
        await monitor.overview.load(isCurrent: isCurrent, operation: controlled { try await $0.opsOverview(timeRange: range) })
    }
    /// The window ends at the server's last whole minute; the nine points are anchored there (MonitorPresentation).
    private func loadErrorTrend() async {
        let window = MonitorTabPresentation.errorTrendWindow(now: serverNow())
        let fetch = controlled { try await $0.opsSnapshotV2(start: window.start, end: window.end) }
        await monitor.errorTrend.load(isCurrent: isCurrent) { MonitorPresentation.errorRateSeries(try await fetch()).map(\.rate) }
    }

    // MARK: - 段计数与副标题（10 §4.1）

    /// nil while ops monitoring is off; blocks that are not read (no capability, not the owner, a route the site lacks) do not count.
    var monitorRefreshStatus: HomeRefreshStatus? {
        opsDisabled ? nil : MonitorTabPresentation.refreshStatus(MonitorOverviewBlock.allCases.filter(monitorBlockApplies).map(monitor.snapshot))
    }
    /// 告警中: the firing list once read, unless it is cut off at its limit; otherwise the counts. nil while ops monitoring is off.
    var monitorFiringCount: Int? {
        guard !opsDisabled else { return nil }
        return MonitorTabPresentation.firingCount(listCount: firing.updatedAt == nil ? nil : firingAlerts.count, listLimit: Self.firingListLimit,
                                                  counts: alertCounts)
    }
    var monitorAlertsRow: MonitorAlertsRow {
        MonitorTabPresentation.alertsRow(firingCount: monitorFiringCount, titles: firingAlerts.map(AlertPresentation.title))
    }
    /// nil while the channel monitor is off (S1-15), rather than the overview's older count.
    var monitorChannelsAttentionCount: Int? {
        guard !channelsUnavailable else { return nil }
        return MonitorTabPresentation.channelsAttentionCount(items: channels.value?.items, home: home.channels.value)
    }
    func monitorSegmentCount(_ segment: MonitorSegment) -> Int? {
        switch segment {
        case .overview: nil
        case .channels: monitorChannelsAttentionCount
        case .alerts: monitorFiringCount
        }
    }
    /// `now` is the server's clock; the blocks' times are the phone's and move by the difference first.
    func monitorSubtitle(for segment: MonitorSegment, now: Date, timeZone: TimeZone) -> String {
        let offset = now.timeIntervalSince(localNow())
        switch segment {
        case .overview:
            return MonitorTabPresentation.overviewSubtitle(monitorRefreshStatus.map { Self.shifted($0, by: offset) }, now: now, timeZone: timeZone)
        case .channels:
            return MonitorTabPresentation.channelsSubtitle(updatedAt: channels.updatedAt?.addingTimeInterval(offset), now: now, timeZone: timeZone)
        case .alerts:
            return MonitorTabPresentation.alertsSubtitle(firingCount: monitorFiringCount)
        }
    }

    private static func shifted(_ status: HomeRefreshStatus, by offset: TimeInterval) -> HomeRefreshStatus {
        guard case .updated(let at) = status else { return status }
        return .updated(at: at.addingTimeInterval(offset))
    }

    // MARK: - S1-14 服务器区（读取、门控与展示在 LiveOpsStore+MonitorServer.swift）
}
