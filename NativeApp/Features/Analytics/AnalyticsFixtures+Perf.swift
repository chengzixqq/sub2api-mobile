import Foundation
import Sub2Core

/// RPM / TPM 趋势 under `-ui-testing` (40 §1.4, S4-16): a fixed “now” 23 seconds past 09:01 in Asia/Shanghai, so the last hour is 60
/// full 1-minute buckets and 6 / 24 hours have a partial first (240 seconds) and last (60 seconds) 5-minute bucket. 44 requests and
/// 220K tokens a minute (2,640 an hour: 平均 44 / 220K); in the last hour 08:10 has 34 / 160K and 08:30 52 / 260K (峰值); the newest
/// bucket 46 / 240K, as the overview's cells. Counts follow the seconds a bucket covers.
extension AnalyticsFixtures {
    static let perfNow = Date(timeIntervalSince1970: 1_792_026_083)
    /// /admin/me says ops monitoring is on, yet every ops chart read answers 404 OPS_DISABLED; S4-18 / S4-18b's +Ops fixtures read
    /// it too. Under -ui-ops-disabled / -ui-ops-config-off the cards send nothing, and turning ops on lets the reads succeed.
    static let opsGoneArgument = "-ui-analytics-ops-gone"

    static func perfTrend(hours: Int, arguments: [String] = ProcessInfo.processInfo.arguments) throws -> PerformanceTrend {
        if arguments.contains(opsGoneArgument) { throw LiveOpsFixtures.opsDisabledError }
        let window = OpsQuery.trailingWindow(hours: hours, endingAt: perfNow)
        let bucket = OpsBucket.forWindow(window.end.timeIntervalSince(window.start))
        let starts = bucket.starts(from: window.start, to: window.end)
        let shape = PerformanceTrend(bucket: bucket, windowStart: window.start, windowEnd: window.end,
                                     points: starts.map { PerformanceTrend.Point(date: $0, requestCount: 0, tokenConsumed: 0) })
        let points = shape.points.enumerated().map { index, point in
            let rate = perfRate(index: index, count: starts.count, bucket: bucket), covered = shape.coveredSeconds(point)
            return PerformanceTrend.Point(date: point.date, requestCount: Int((rate.requests * covered / 60).rounded()),
                                          tokenConsumed: Int((rate.tokens * covered / 60).rounded()))
        }
        return PerformanceTrend(bucket: bucket, windowStart: window.start, windowEnd: window.end, points: points)
    }

    /// Per minute: the newest bucket, then the last hour's two marked minutes (08:01 + 9 and + 29), else the base.
    private static func perfRate(index: Int, count: Int, bucket: OpsBucket) -> (requests: Double, tokens: Double) {
        if index == count - 1 { return (46, 240_000) }
        guard bucket == .minute else { return (44, 220_000) }
        switch index {
        case 9: return (34, 160_000)
        case 29: return (52, 260_000)
        default: return (44, 220_000)
        }
    }
}
