import Foundation
import Sub2Core

// S1-14: the monitor overview's 服务器 section for `-ui-testing`. The run's five-minute overview carries the CPU / memory snapshot,
// QPS and the job heartbeats (LiveOpsFixtures+Fallback.swift); the section's own four reads are here. Times count back from the
// session's start, so the figures stay put while the page polls.
extension LiveOpsFixtures {
    /// The `-ui-without-capabilities` value of a site from before the CPU / memory history and the rejection totals. UI tests copy
    /// this literal (they cannot import the App).
    static let serverLegacyWithheldCapabilities = "ops.system_metrics_history,ops.ingress_reject_totals"
    private static let rejectionsWithTotal = [2, 1]
    private static let legacyRejectionRows = 650

    /// The collector writes once a minute: CPU 92% (critical), memory 78% (caution), four requests queued.
    static func serverSystemMetrics(now: Date) -> OpsSystemMetricsSnapshot {
        OpsSystemMetricsSnapshot(createdAt: wholeMinute(now), cpuUsagePercent: 92, memoryUsagePercent: 78, memoryUsedMB: 6_390, memoryTotalMB: 8_192,
                                 concurrencyQueueDepth: 4, goroutineCount: 412, dbOK: true, redisOK: true)
    }
    /// Every job state once: failing, stale by its interval and by its schedule, disabled, two ok and a job the App does not know.
    /// Three need attention.
    static func serverJobHeartbeats(now: Date) -> [OpsJobHeartbeat] {
        func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }
        return [
            OpsJobHeartbeat(jobName: "ops_metrics_collector", lastRunAt: ago(60), lastSuccessAt: ago(240), lastErrorAt: ago(60),
                            lastError: "redis: connection pool timeout", lastDurationMs: 30_000, status: "failing", expectedIntervalSeconds: 60),
            OpsJobHeartbeat(jobName: "ops_alert_evaluator", lastRunAt: ago(31), lastSuccessAt: ago(31), lastDurationMs: 120, status: "ok",
                            expectedIntervalSeconds: 60),
            OpsJobHeartbeat(jobName: "ops_preaggregation_hourly", lastRunAt: ago(2_400), lastSuccessAt: ago(2_400), status: "stale",
                            expectedIntervalSeconds: 600),
            OpsJobHeartbeat(jobName: "ops_preaggregation_daily", lastRunAt: ago(2_400), lastSuccessAt: ago(2_400), status: "ok",
                            expectedIntervalSeconds: 3_600),
            OpsJobHeartbeat(jobName: "ops_cleanup", lastRunAt: ago(90_000), lastSuccessAt: ago(90_000), status: "stale", nextExpectedAt: ago(3_600)),
            OpsJobHeartbeat(jobName: "ops_scheduled_reports", lastSuccessAt: ago(86_400), status: "disabled"),
            OpsJobHeartbeat(jobName: "ops_custom_sync", status: "paused")
        ]
    }
    /// 8/50 in use and one waiting across two platforms; realtime monitoring off answers `enabled: false` and nothing else.
    static func serverConcurrency(realtimeOff: Bool) -> OpsConcurrency {
        guard !realtimeOff else { return OpsConcurrency(enabled: false) }
        return OpsConcurrency(platforms: ["anthropic": .init(currentInUse: 5, maxCapacity: 30, waitingInQueue: 1),
                                          "openai": .init(currentInUse: 3, maxCapacity: 20, waitingInQueue: 0)])
    }
    /// The last hour a minute at a time, ending at the current snapshot. CPU has no value for three minutes and memory for one,
    /// so both lines break.
    static func serverMetricsHistory(now: Date) -> SystemMetricsHistory {
        let current = serverSystemMetrics(now: now), end = wholeMinute(now)
        let points = (0..<60).map { index -> SystemMetricsHistory.Point in
            guard index < 59 else { return .init(createdAt: end, cpuUsagePercent: current.cpuUsagePercent, memoryUsagePercent: current.memoryUsagePercent) }
            let cpu = (62.5 + 32.5 * sin(Double(index) / 6)).rounded(), memory = (70 + 10 * sin(Double(index) / 9)).rounded()
            return .init(createdAt: end.addingTimeInterval(Double(index - 59) * 60), cpuUsagePercent: (20...22).contains(index) ? nil : cpu,
                         memoryUsagePercent: index == 21 ? nil : memory)
        }
        return SystemMetricsHistory(startTime: end.addingTimeInterval(-3_600), endTime: end, bucketSeconds: 60, points: points)
    }
    /// Written within a second, no error.
    static func serverLogHealth() -> SystemLogHealth {
        SystemLogHealth(avgWriteDelayMs: 850, queueDepth: 0, queueCapacity: 1_000, lastError: "", writeFailedCount: 0, droppedCount: 0)
    }
    /// Three rejections in two aggregated rows with the total; an old server sends 650 rows of one each and no total.
    static func serverIngress(page: Int, pageSize: Int, withTotal: Bool) -> IngressRejectList {
        let rows = withTotal ? rejectionsWithTotal : Array(repeating: 1, count: legacyRejectionRows)
        let start = min(max(page - 1, 0) * pageSize, rows.count), end = min(start + pageSize, rows.count)
        return IngressRejectList(items: rows[start..<end].map { IngressRejectList.Item(requestCount: $0) }, total: rows.count, page: page,
                                 pageSize: pageSize, requestCountTotal: withTotal ? rows.reduce(0, +) : nil)
    }

    private static func wholeMinute(_ date: Date) -> Date { Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60) }
}

extension FixtureLiveOpsSource {
    func opsConcurrency() throws -> OpsConcurrency {
        try requireOps()
        return LiveOpsFixtures.serverConcurrency(realtimeOff: options.monitor.realtimeOff)
    }
    func systemMetricsHistory(timeRange: String, maxPoints: Int) throws -> SystemMetricsHistory {
        try requireOps()
        return LiveOpsFixtures.serverMetricsHistory(now: base)
    }
    func systemLogsHealth() throws -> SystemLogHealth {
        try requireOps()
        return LiveOpsFixtures.serverLogHealth()
    }
    func ingressRejections(timeRange: String, page: Int, pageSize: Int) throws -> IngressRejectList {
        try requireOps()
        return LiveOpsFixtures.serverIngress(page: page, pageSize: pageSize, withTotal: !options.monitor.ingressTotalsWithheld)
    }
}
