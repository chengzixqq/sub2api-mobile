import Foundation
import Sub2Core

/// 40 §2.3 the ops charts under `-ui-testing` (S4-18, C-32; S4-18b adds 错误分布 and Token 请求统计). The totals are fixed whatever the
/// range and the filter, so a test reads exact numbers; the buckets follow the server's (OpsBucket over the page range). Only
/// `opsGoneArgument` (S4-16) makes them answer 404 OPS_DISABLED: under -ui-ops-disabled the cards send nothing.
extension AnalyticsFixtures {
    /// 错误 397 · SLA 317 · 业务限制 80; upstream 429 186 · 529 64 · other 53.
    static let opsErrorTotals = OpsErrorCounts(total: 397, sla: 317, businessLimited: 80, upstream429: 186, upstream529: 64, upstreamOther: 53)
    /// 18,204 successful requests: 10% 20% 30% 23% 12% 5%.
    private static let latencyCounts = [1_820, 3_640, 5_461, 4_187, 2_184, 912]
    private static let opsWeights = [3, 5, 4, 6, 8, 7, 9, 5, 6, 4, 7, 8]
    /// Every 24th bucket from the 6th has no request, so the line breaks.
    private static let quietEvery = 24, quietOffset = 5

    /// 250 requests, 500K tokens and 2–4 switches a bucket; the first has 8 (最高 0.032).
    static func opsThroughput(_ query: OpsQuery) throws -> PerformanceTrend {
        try requireOps()
        let starts = opsStarts(query)
        let points = starts.indices.map { index -> PerformanceTrend.Point in
            guard index % quietEvery != quietOffset else { return PerformanceTrend.Point(date: starts[index], requestCount: 0, tokenConsumed: 0) }
            return PerformanceTrend.Point(date: starts[index], requestCount: 250, tokenConsumed: 500_000, switchCount: index == 0 ? 8 : 2 + index % 3)
        }
        return PerformanceTrend(bucket: opsBucket(query), windowStart: query.start, windowEnd: query.end, points: points)
    }

    static func opsLatencyHistogram(_ query: OpsQuery) throws -> OpsLatencyHistogram {
        try requireOps()
        return OpsLatencyHistogram(buckets: zip(OpsLatencyHistogram.BucketRange.allCases, latencyCounts).map {
            OpsLatencyHistogram.Bucket(range: $0, count: $1)
        })
    }

    /// 错误率 317 ÷ 18,521 (1.7%); 总耗时 P50 2.4s … 最长 182s, 首字 P50 820ms … 最长 42s.
    static func opsOverview(_ query: OpsQuery) throws -> OpsOverview {
        try requireOps()
        let totals = opsErrorTotals, success = latencyCounts.reduce(0, +)
        return OpsOverview(startTime: query.start, endTime: query.end, sla: 0.982884, errorRate: Double(totals.sla) / Double(success + totals.sla),
                           successCount: success, errorCountTotal: totals.total, businessLimitedCount: totals.businessLimited,
                           errorCountSLA: totals.sla, requestCountTotal: success + totals.total, requestCountSLA: success + totals.sla,
                           duration: OpsPercentiles(p50Ms: 2_400, p90Ms: 5_100, p95Ms: 8_200, p99Ms: 21_000, avgMs: 3_100, maxMs: 182_000),
                           ttft: OpsPercentiles(p50Ms: 820, p90Ms: 1_900, p95Ms: 2_600, p99Ms: 6_400, avgMs: 1_100, maxMs: 42_000))
    }

    /// `opsErrorTotals` spread over the buckets by fixed weights, so every total is exact.
    static func opsErrorTrend(_ query: OpsQuery) throws -> OpsErrorTrend {
        try requireOps()
        let starts = opsStarts(query), totals = opsErrorTotals
        let weights = starts.indices.map { opsWeights[$0 % opsWeights.count] }
        let sla = spread(totals.sla, weights), limited = spread(totals.businessLimited, weights)
        let upstream = [totals.upstream429, totals.upstream529, totals.upstreamOther].map { spread($0, weights) }
        let points = starts.indices.map { index in
            OpsErrorTrend.Point(start: starts[index], counts: OpsErrorCounts(total: sla[index] + limited[index], sla: sla[index],
                                                                             businessLimited: limited[index], upstream429: upstream[0][index],
                                                                             upstream529: upstream[1][index], upstreamOther: upstream[2][index]))
        }
        return OpsErrorTrend(bucket: opsBucket(query), points: points, windowStart: query.start, windowEnd: query.end)
    }

    private static func requireOps() throws {
        if ProcessInfo.processInfo.arguments.contains(opsGoneArgument) { throw LiveOpsFixtures.opsDisabledError }
    }
    private static func opsBucket(_ query: OpsQuery) -> OpsBucket { OpsBucket.forWindow(query.end.timeIntervalSince(query.start)) }
    private static func opsStarts(_ query: OpsQuery) -> [Date] { opsBucket(query).starts(from: query.start, to: query.end) }
    /// Largest remainder: the shares of `total` by `weights` rounded down, one more for the largest remainders (earlier first).
    private static func spread(_ total: Int, _ weights: [Int]) -> [Int] {
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return weights.map { _ in 0 } }
        let shares = weights.map { total * $0 / sum }
        let order = weights.indices.sorted { (total * weights[$0] % sum, $1) > (total * weights[$1] % sum, $0) }
        let extra = Set(order.prefix(total - shares.reduce(0, +)))
        return shares.indices.map { shares[$0] + (extra.contains($0) ? 1 : 0) }
    }
}

// MARK: 错误分布、Token 请求统计（S4-18b）

/// 错误分布 adds up to `opsErrorTotals` (397 · SLA 317 · 业务限制 80, 429 first at 40%); Token 请求统计 lists ten models in the server's
/// order, qwen3-coder without a speed or a first token and with the server's 0 for its duration. 测试组 (6, inactive) has neither.
extension AnalyticsFixtures {
    /// (status, total, SLA, business limits).
    private static let errorCodes = [(429, 160, 148, 12), (502, 72, 72, 0), (403, 68, 0, 68), (529, 48, 48, 0), (500, 31, 31, 0), (504, 18, 18, 0)]
    private static let tokenStatsRows: [OpsTokenStats.Item] = [
        tokenStatsRow("claude-opus-4", 1_210, 42.6, 1_840, 14_200, 1_180), tokenStatsRow("gpt-5", 1_100, 61.3, 920, 8_600, 1_100),
        tokenStatsRow("deepseek-v3", 620, 38.2, 1_210, 9_800, 600), tokenStatsRow("gemini-2.5-pro", 380, 74.8, 760, 5_200, 380),
        tokenStatsRow("gpt-4.1-mini", 350, 86.4, 410, 2_400, 350), tokenStatsRow("claude-sonnet-4", 300, 55.1, 1_020, 6_800, 290),
        tokenStatsRow("glm-4.6", 195, 33.0, 1_500, 7_400, 190), tokenStatsRow("qwen3-coder", 120, nil, nil, 0, 0),
        tokenStatsRow("kimi-k2", 90, 48.9, 980, 5_600, 88), tokenStatsRow("o4-mini", 60, 70.2, 690, 3_100, 60),
    ]
    private static let unusedGroupID = 6

    static func opsErrorDistribution(_ query: OpsQuery) throws -> OpsErrorDistribution {
        try requireOps()
        guard query.groupID != unusedGroupID else { return OpsErrorDistribution(items: []) }
        return OpsErrorDistribution(items: errorCodes.map { OpsErrorDistribution.Item(statusCode: $0.0, total: $0.1, sla: $0.2, businessLimited: $0.3) })
    }

    /// The window the client would send; no 400 (the retry over 30 days is S4-11's tests').
    static func opsTokenStats(_ query: OpsQuery, now: Date, zone: ServerTimeZone, supportsCustomRange: Bool) throws -> OpsTokenStats {
        try requireOps()
        let window = OpsTokenStatsWindow.select(start: query.start, end: query.end, now: now, zone: zone, supportsCustomRange: supportsCustomRange)
        let timeRange = if case .rolling(let rolling, _) = window { rolling.rawValue } else { "custom" }
        return OpsTokenStats(timeRange: timeRange, items: query.groupID == unusedGroupID ? [] : tokenStatsRows, window: window)
    }

    private static func tokenStatsRow(_ model: String, _ requests: Int, _ speed: Double?, _ firstToken: Double?, _ duration: Double,
                                      _ withFirstToken: Int) -> OpsTokenStats.Item {
        OpsTokenStats.Item(model: model, requestCount: requests, tokensPerSecond: speed, firstTokenMs: firstToken, durationMs: duration,
                           requestsWithFirstToken: withFirstToken)
    }
}
