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
    // S1-14：服务器区的块接在这里。
}

@MainActor @Observable
final class MonitorState {
    /// U08: the segment chosen this session. A new session (another site, signing in again) makes a new store, which opens on 概况.
    var segment: MonitorSegment = .overview
    let overview = LoadState<OpsOverview>()
    /// Nine five-minute error rates, oldest first; nil where nothing counted, which breaks the line.
    let errorTrend = LoadState<[Double?]>()
    /// When each block's last read ended, on the store's device clock.
    @ObservationIgnored private var settled: [MonitorOverviewBlock: Date] = [:]

    func isLoading(_ block: MonitorOverviewBlock) -> Bool {
        switch block {
        case .run: overview.isLoading
        case .errorTrend: errorTrend.isLoading
        }
    }
    /// The wait after this block's read: the rest of a 429 wait, otherwise `base` backed off by its failures.
    func nextDelay(for block: MonitorOverviewBlock, base: TimeInterval) -> TimeInterval {
        switch block {
        case .run: overview.nextDelay(base: base)
        case .errorTrend: errorTrend.nextDelay(base: base)
        }
    }
    func settledAt(_ block: MonitorOverviewBlock) -> Date? { settled[block] }
    func markSettled(_ block: MonitorOverviewBlock, at date: Date) { settled[block] = date }
    /// For the subtitle's freshness.
    var blockSnapshots: [MonitorBlockSnapshot] { [MonitorBlockSnapshot(overview.state), MonitorBlockSnapshot(errorTrend.state)] }
}

extension LiveOpsStore {
    /// Coming back to 概况 within this many seconds of a block's last read waits out the rest before reading it again.
    nonisolated static let monitorReentryGap: TimeInterval = 10

    // MARK: - 读取与轮询（10 §4.6）

    /// A pull or ··· 刷新: every block at once, even one in flight, with the firing list read again. It asks even while the switch
    /// says off, so a 200 can turn it back on.
    func refreshMonitorOverview(force: Bool) async {
        await withDiscardingTaskGroup { group in
            for block in MonitorOverviewBlock.allCases {
                group.addTask { await self.refreshMonitorBlock(block, force: force) }
            }
        }
    }
    /// While the caller's task lives: each block on its own timer, counted from the end of its read. A block read under ten seconds
    /// ago waits out the rest first; the timers end once ops monitoring is off or the session ended.
    func monitorOverviewPolling() async {
        await withDiscardingTaskGroup { group in
            for block in MonitorOverviewBlock.allCases {
                group.addTask { await self.pollMonitorBlock(block) }
            }
        }
    }
    /// One block; without `force` a block already in flight is left to finish, and nothing is read while the switch says off.
    func refreshMonitorBlock(_ block: MonitorOverviewBlock, force: Bool) async {
        guard isCurrent(), site() != nil, force || (!opsDisabled && !monitor.isLoading(block)) else { return }
        switch block {
        case .run:
            async let overview: Void = loadMonitorOverview()
            async let firing: Void = refreshFiringAlerts(maxAge: force ? 0 : Self.alertListMaxAge)
            _ = await (overview, firing)
        case .errorTrend:
            await loadErrorTrend()
        }
        if isCurrent() { monitor.markSettled(block, at: localNow()) }
    }

    private func pollMonitorBlock(_ block: MonitorOverviewBlock) async {
        guard !opsDisabled else { return }
        if let wait = monitorReentryWait(block) {
            do { try await sleep(.seconds(wait)) } catch { return }
        }
        while !Task.isCancelled, isCurrent(), !opsDisabled {
            await refreshMonitorBlock(block, force: false)
            guard !opsDisabled else { return }
            do { try await sleep(.seconds(monitor.nextDelay(for: block, base: Self.pollInterval))) } catch { return }
        }
    }
    /// The rest of `monitorReentryGap` since the block's last read ended; nil once it passed.
    private func monitorReentryWait(_ block: MonitorOverviewBlock) -> TimeInterval? {
        guard let settled = monitor.settledAt(block) else { return nil }
        let elapsed = localNow().timeIntervalSince(settled)
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

    /// nil while ops monitoring is off.
    var monitorRefreshStatus: HomeRefreshStatus? {
        opsDisabled ? nil : MonitorTabPresentation.refreshStatus(monitor.blockSnapshots)
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
    var monitorChannelsAttentionCount: Int? {
        MonitorTabPresentation.channelsAttentionCount(items: channels.value?.items, home: home.channels.value)
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

    // MARK: - S1-14 服务器区
}
