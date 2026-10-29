import Foundation
import Sub2Core

// S1-13: the monitor overview's reads for `-ui-testing`. The run reads `opsOverview(timeRange: "5m")`, the home fixture's last
// five minutes (LiveOpsFixtures+Fallback.swift), so 概况 shows what the overview's 运行 shows. S1-14 adds the server section here.

/// Failure switches for the overview's blocks; they go with any home variant.
struct MonitorFixtureOptions: Equatable, Sendable {
    /// `ops/dashboard/overview` answers 503, so 运行 shows “—” and 加载失败 · 重试.
    static let overviewFailsArgument = "-ui-monitor-overview-fails"
    /// snapshot-v2 answers 503, so the line becomes 趋势加载失败 · 重试.
    static let trendFailsArgument = "-ui-monitor-trend-fails"
    var overviewFails = false
    var trendFails = false

    init(overviewFails: Bool = false, trendFails: Bool = false) { self.overviewFails = overviewFails; self.trendFails = trendFails }
    init(arguments: [String]) {
        self.init(overviewFails: arguments.contains(Self.overviewFailsArgument), trendFails: arguments.contains(Self.trendFailsArgument))
    }
}

extension LiveOpsFixtures {
    /// One SLA error a minute, plus these in the first minute of each five-minute point: 5–10 of 600 requests (0.8%–1.7%).
    private static let extraErrors = [0, 1, 0, 2, 0, 1, 3, 5, 2]
    private static let requestsPerMinute = 120

    /// snapshot-v2 as the server buckets it: one bucket a minute from floor(start) to the minute holding the last instant
    /// before `end` (45 for whole minutes, 46 otherwise). The five minutes from 25 to 20 minutes before `end` have no requests,
    /// so the line breaks once.
    static func opsSnapshotV2(start: Date, end: Date) -> OpsSnapshotV2 {
        let first = (start.timeIntervalSince1970 / 60).rounded(.down) * 60
        let last = (end.timeIntervalSince1970 / 60).rounded(.up) * 60 - 60
        let origin = end.addingTimeInterval(-MonitorPresentation.errorRateWindow)
        let buckets = stride(from: first, through: last, by: 60).map { Date(timeIntervalSince1970: $0) }
        let counts = buckets.map { minuteCounts($0, origin: origin, end: end) }
        let throughput = zip(buckets, counts).map { OpsSnapshotV2.ThroughputPoint(bucketStart: $0.0, requestCount: $0.1.requests) }
        let errors = zip(buckets, counts).map { OpsSnapshotV2.ErrorPoint(bucketStart: $0.0, errorCountSLA: $0.1.errors, businessLimitedCount: 0) }
        return OpsSnapshotV2(overview: fiveMinuteOverview(base: end), throughputPoints: throughput, errorPoints: errors, generatedAt: end,
                             windowStart: start, windowEnd: end)
    }

    private static func minuteCounts(_ bucket: Date, origin: Date, end: Date) -> (requests: Int, errors: Int) {
        // Nothing in [end − 25 min, end − 20 min).
        let before = end.timeIntervalSince(bucket)
        if before > 1_200, before <= 1_500 { return (0, 0) }
        let minute = max(0, Int(bucket.timeIntervalSince(origin) / 60))
        let point = min(minute / 5, extraErrors.count - 1)
        return (requestsPerMinute, 1 + (minute % 5 == 0 ? extraErrors[point] : 0))
    }
}

extension FixtureLiveOpsSource {
    func opsSnapshotV2(start: Date, end: Date) throws -> OpsSnapshotV2 {
        try requireOps()
        if options.monitor.trendFails { throw Self.unreachableError }
        return LiveOpsFixtures.opsSnapshotV2(start: start, end: end)
    }
}
