import Foundation
import Sub2Core

/// 40 §2.3 用户用量趋势 and 请求类型 under `-ui-testing` (S4-17b, C-32). Seven of DemoData's users with fixed totals, whatever the
/// range and the filter: each total is spread over the range's buckets (北辰数据 skips every other one, so the card fills in 0), what
/// is left in the last bucket it has. By Tokens Nova 工作室 is first and Mira Labs fifth, by 实际扣费 Atlas 科技 first and Pixel 工坊
/// fifth. The request types answer the dashboard's rows; without `dashboard.request_types` the fallback's other numbers (no ws_v2),
/// so a test sees which way the card read. `Argument.empty` has no usage; with `Argument.refreshChanges` the users' totals double
/// from a segment's second read on (S4D2b-02 ⑥).
extension AnalyticsFixtures {
    @MainActor static func userUsageSeries(_ session: AnalyticsSession, metric: UserTrendMetric) throws -> UserUsageSeries {
        let scale = moreScale("userTrend.\(metric.rawValue)")
        let buckets = session.range.buckets
        let rows = moreIsEmpty ? [] : usageTrendUsers.enumerated().flatMap { seed, user in user.rows(buckets: buckets, seed: seed, scale: scale) }
        let points = try JSONDecoder().decode([UserTrendPoint].self, from: JSONSerialization.data(withJSONObject: rows))
        return UserUsageSeries(points: points, range: session.range, metric: metric)
    }

    /// 13,120 · 4,310 · 612 · 162 (流式 72.1%, no Live); the fallback 9,800 · 2,100 · 0 · 40 · 60.
    static func requestTypeMix(viaFallback: Bool) throws -> RequestTypeMix {
        guard !moreIsEmpty else { return RequestTypeMix(stats: []) }
        if viaFallback { return RequestTypeMix(counts: [.stream: 9_800, .sync: 2_100, .cyber: 40, .live: 60]) }
        let rows: [[String: Any]] = [("stream", 13_120), ("sync", 4_310), ("ws_v2", 612), ("cyber", 162)].map { type, requests in
            ["request_type": type, "requests": requests, "total_tokens": requests * 5_300]
        }
        return RequestTypeMix(stats: try JSONDecoder().decode([RequestTypeStat].self, from: JSONSerialization.data(withJSONObject: rows)))
    }
}

/// A user of the users-trend fixture: Tokens and 实际扣费 in cents over the whole range.
private struct UsageTrendUser {
    let id: Int
    let name: String
    let email: String
    let tokens: Int
    let actual: Int
    var skipsEveryOther = false

    /// `users-trend` rows, only for the buckets with usage; the weights vary by bucket and user so the lines differ.
    func rows(buckets: [AnalyticsBucket], seed: Int, scale: Int) -> [[String: Any]] {
        let used = buckets.indices.filter { !skipsEveryOther || $0 % 2 == 0 }
        let weights = used.map { 1 + ($0 * (seed + 2) + seed) % 5 }
        let tokens = spread(self.tokens * scale, weights), cents = spread(actual * scale, weights)
        return used.indices.map { index in
            ["date": buckets[used[index]].wireKey, "user_id": id, "email": email, "username": name, "requests": max(1, tokens[index] / 20_000),
             "tokens": tokens[index], "cost": moreMoney(cents[index] * 5 / 4), "actual_cost": moreMoney(cents[index])]
        }
    }

    /// The shares of `total` by `weights` rounded down, the rest in the last.
    private func spread(_ total: Int, _ weights: [Int]) -> [Int] {
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return weights.map { _ in 0 } }
        var shares = weights.map { total * $0 / sum }
        shares[shares.count - 1] += total - shares.reduce(0, +)
        return shares
    }
}

private func moreMoney(_ cents: Int) -> String { "\(cents / 100)." + (cents % 100 < 10 ? "0" : "") + "\(cents % 100)" }

extension AnalyticsFixtures {
    /// DemoData+Users' ids and names, so a row opens the user.
    private static let usageTrendUsers: [UsageTrendUser] = [
        UsageTrendUser(id: 21, name: "Nova 工作室", email: "billing@nova.example", tokens: 12_400_000, actual: 38_920),
        UsageTrendUser(id: 22, name: "Atlas 科技", email: "ops@atlas.example", tokens: 9_860_000, actual: 41_280),
        UsageTrendUser(id: 23, name: "深蓝 AI", email: "team@deepblue.example", tokens: 7_310_000, actual: 20_540),
        UsageTrendUser(id: 10, name: "Studio-K 团队", email: "ops@studio-k.example", tokens: 5_120_000, actual: 16_025),
        UsageTrendUser(id: 24, name: "Mira Labs", email: "hello@mira.example", tokens: 3_480_000, actual: 9_810),
        UsageTrendUser(id: 25, name: "Pixel 工坊", email: "studio@pixel.example", tokens: 1_960_000, actual: 12_130),
        UsageTrendUser(id: 26, name: "北辰数据", email: "data@beichen.example", tokens: 820_000, actual: 1_860, skipsEveryOther: true),
    ]

    @MainActor private static var moreReads: [String: Int] = [:]

    private static var moreIsEmpty: Bool { ProcessInfo.processInfo.arguments.contains(Argument.empty) }

    /// 2 from a read's second answer on with `Argument.refreshChanges`, else 1.
    @MainActor private static func moreScale(_ read: String) -> Int {
        let count = moreReads[read, default: 0]
        moreReads[read] = count + 1
        return count > 0 && ProcessInfo.processInfo.arguments.contains(Argument.refreshChanges) ? 2 : 1
    }
}
