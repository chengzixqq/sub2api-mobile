import Foundation
import Sub2Core

/// `-ui-testing` data of the analytics pages, one file per topic (C-32): +Filter (S4-12); 计费与利润夹具由 S4-13 写在这里, then
/// +Rank, +Perf, +More, +Ops and +Model.
enum AnalyticsFixtures {}

// MARK: - 计费（S4-13）

/// The billing reads (40 §1.3). 今天 is the overview's day (LiveOpsFixtures.stats, so 利润 matches its cell), 近 7 天 has numbers of
/// its own, any other range so much per day; a group or model filter keeps 40% of everything. The trend splits the totals over the
/// range's buckets in cents (every column adds up; the 4th hour has no row, so the card fills it with 0), each point's tokens 32%
/// input · 7% output · 54% cache read · 7% cache write, and the totals' token kinds are the points' sums. The endpoints are fixed.
/// Without `dashboard.account_cost` (-ui-without-capabilities) no reply has an account cost key.
extension AnalyticsFixtures {
    enum Argument {
        /// The totals and the trend answer 500 once, then succeed.
        static let failOnce = "-ui-analytics-fail-once"
        /// The totals and the trend always answer 504: 统计较慢，加载超时.
        static let timeout = "-ui-analytics-timeout"
        /// The totals answer 429 once, with the default 30-second wait.
        static let throttled = "-ui-analytics-throttled"
        /// The totals and the trend succeed once, then answer 500: the value stays under 更新失败.
        static let refreshFails = "-ui-analytics-refresh-fails"
        /// The comparison window always answers 500: the change line is hidden.
        static let comparisonFails = "-ui-analytics-comparison-fails"
        /// Every billing read waits 3 seconds first.
        static let slow = "-ui-analytics-slow"
        /// No usage in any range: zero totals and no trend rows.
        static let empty = "-ui-analytics-empty"
        /// For S4-15 / S4-17b: their fixtures answer other numbers from the second read on (S4D2b-02 ⑥).
        static let refreshChanges = "-ui-analytics-refresh-changes"
    }

    @MainActor static func billingSummary(_ session: AnalyticsSession) async throws -> AnalyticsSummary {
        try await answer(.summary)
        let points = billingPoints(session)
        let kinds = [\TrendPoint.inputTokens, \.outputTokens, \.cacheReadTokens, \.cacheCreationTokens].map { kind in
            points.reduce(0) { $0 + $1[keyPath: kind] }
        }
        return try summary(totals(session, comparison: false), tokenKinds: kinds, endpoints: !points.isEmpty)
    }
    @MainActor static func billingComparison(_ session: AnalyticsSession) async throws -> AnalyticsSummary {
        try await answer(.comparison)
        return try summary(totals(session, comparison: true), tokenKinds: nil, endpoints: false)
    }
    @MainActor static func billingTrend(_ session: AnalyticsSession) async throws -> DashboardTrendReply {
        try await answer(.trend)
        return DashboardTrendReply(points: billingPoints(session), timeZone: session.timeZone.timeZone)
    }
}

// MARK: Numbers

/// Money in cents.
private struct BillingTotals {
    var actual: Int
    var standard: Int
    var account: Int
    var requests: Int
    var tokens: Int
    var averageMs: Int

    static let zero = BillingTotals(actual: 0, standard: 0, account: 0, requests: 0, tokens: 0, averageMs: 0)

    /// Every amount and count × numerator ÷ denominator, rounded half up.
    func scaled(_ numerator: Int, _ denominator: Int) -> BillingTotals {
        guard denominator > 0 else { return self }
        func scale(_ value: Int) -> Int { (value * numerator * 2 + denominator) / (denominator * 2) }
        return BillingTotals(actual: scale(actual), standard: scale(standard), account: scale(account), requests: scale(requests),
                             tokens: scale(tokens), averageMs: averageMs)
    }
}

extension AnalyticsFixtures {
    private static let bucketWeights = [3, 5, 4, 6, 8, 7, 9, 5, 6, 4, 7, 8]
    /// input, output, cache read, cache write.
    private static let tokenShares = [32, 7, 54, 7]

    @MainActor private static func totals(_ session: AnalyticsSession, comparison: Bool) -> BillingTotals {
        let arguments = ProcessInfo.processInfo.arguments
        guard !arguments.contains(Argument.empty) else { return .zero }
        let totals = rangeTotals(session, comparison: comparison, arguments: arguments)
        return session.filter == nil ? totals : totals.scaled(2, 5)
    }

    @MainActor private static func rangeTotals(_ session: AnalyticsSession, comparison: Bool, arguments: [String]) -> BillingTotals {
        switch session.selection {
        case .preset(.today):
            let stats = LiveOpsFixtures.stats(session.now, profitLoss: arguments.contains(LiveOpsFixtures.Argument.profitLoss))
            let today = BillingTotals(actual: cents(stats.todayActualCost), standard: cents(stats.todayCost), account: cents(stats.todayAccountCost),
                                      requests: stats.todayRequests ?? 0, tokens: stats.todayTokens ?? 0, averageMs: 2_400)
            guard comparison else { return today }
            var yesterday = today.scaled(cents(stats.yesterdaySameTimeActualCost), today.actual)
            yesterday.actual = cents(stats.yesterdaySameTimeActualCost)
            yesterday.account = cents(stats.yesterdaySameTimeAccountCost)
            yesterday.requests = stats.yesterdaySameTimeRequests ?? 0
            return yesterday
        case .preset(.last7):
            let week = BillingTotals(actual: 841_230, standard: 1_051_538, account: 336_207, requests: 121_480, tokens: 642_500_000, averageMs: 2_310)
            guard comparison else { return week }
            var before = week.scaled(779_620, week.actual)
            before.actual = 779_620
            return before
        default:
            let days = session.range.dayCount, actual = 120_176 * days
            let range = BillingTotals(actual: actual, standard: actual * 5 / 4, account: actual * 2 / 5, requests: 17_354 * days,
                                      tokens: 91_800_000 * days, averageMs: 2_350)
            return comparison ? range.scaled(1_000, 1_074) : range
        }
    }

    @MainActor private static func billingPoints(_ session: AnalyticsSession) -> [TrendPoint] {
        guard !ProcessInfo.processInfo.arguments.contains(Argument.empty) else { return [] }
        let totals = totals(session, comparison: false), buckets = session.range.buckets
        let hourly = session.range.granularity == .hour
        let weights = buckets.indices.map { hourly && $0 == 3 ? 0 : bucketWeights[$0 % bucketWeights.count] }
        let actual = allocate(totals.actual, weights), standard = allocate(totals.standard, weights)
        let account = allocate(totals.account, weights), requests = allocate(totals.requests, weights)
        let tokens = allocate(totals.tokens, weights)
        let withholdsAccountCost = withholdsAccountCost
        return buckets.indices.compactMap { index in
            guard weights[index] > 0 else { return nil }
            let kinds = allocate(tokens[index], tokenShares)
            return TrendPoint(date: buckets[index].wireKey, requests: requests[index], totalTokens: tokens[index], cost: money(standard[index]),
                              actualCost: money(actual[index]), accountCost: withholdsAccountCost ? nil : money(account[index]),
                              inputTokens: kinds[0], outputTokens: kinds[1], cacheCreationTokens: kinds[3], cacheReadTokens: kinds[2])
        }
    }

    /// Largest remainder: the shares of `total` by `weights` rounded down, what is left to the largest remainders.
    private static func allocate(_ total: Int, _ weights: [Int]) -> [Int] {
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return weights.map { _ in 0 } }
        var shares = weights.map { total * $0 / sum }
        let remainders = weights.map { total * $0 % sum }
        let order = weights.indices.sorted { remainders[$0] != remainders[$1] ? remainders[$0] > remainders[$1] : $0 < $1 }
        for index in order.prefix(total - shares.reduce(0, +)) { shares[index] += 1 }
        return shares
    }

    private static var withholdsAccountCost: Bool {
        UITestArguments.withheldCapabilities(arguments: ProcessInfo.processInfo.arguments).contains(Capability.dashboardAccountCost.rawValue)
    }
    private static func cents(_ value: Decimal?) -> Int { NSDecimalNumber(decimal: (value ?? 0) * 100).intValue }
    private static func money(_ cents: Int) -> Decimal { Decimal(cents) / 100 }
    private static func amount(_ cents: Int) -> String { "\(cents / 100)." + (cents % 100 < 10 ? "0" : "") + "\(cents % 100)" }
}

// MARK: Replies

extension AnalyticsFixtures {
    private static func summary(_ totals: BillingTotals, tokenKinds: [Int]?, endpoints: Bool) throws -> AnalyticsSummary {
        var json: [String: Any] = [
            "total_requests": totals.requests, "total_tokens": totals.tokens, "total_cost": amount(totals.standard),
            "total_actual_cost": amount(totals.actual), "average_duration_ms": totals.requests > 0 ? totals.averageMs : 0,
        ]
        if !withholdsAccountCost { json["total_account_cost"] = amount(totals.account) }
        if let tokenKinds {
            json["total_input_tokens"] = tokenKinds[0]; json["total_output_tokens"] = tokenKinds[1]
            json["total_cache_read_tokens"] = tokenKinds[2]; json["total_cache_creation_tokens"] = tokenKinds[3]
            json["total_cache_tokens"] = tokenKinds[2] + tokenKinds[3]
        }
        if endpoints {
            json["endpoints"] = inboundEndpoints
            json["upstream_endpoints"] = upstreamEndpoints
        }
        return try JSONDecoder().decode(AnalyticsSummary.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// 60.0% / 28.0% / 12.0% of 18,200 requests, whatever the range and the filter (S4D2b-13 ⑥).
    private static var inboundEndpoints: [[String: Any]] {
        [["endpoint": "/v1/messages", "requests": 10_920, "total_tokens": 57_840_000, "cost": "765.50", "actual_cost": "612.40"],
         ["endpoint": "/v1/chat/completions", "requests": 5_096, "total_tokens": 26_992_000, "cost": "357.13", "actual_cost": "285.70"],
         ["endpoint": "/v1/responses", "requests": 2_184, "total_tokens": 11_568_000, "cost": "153.00", "actual_cost": "122.40"]]
    }
    /// 70.0% / 30.0%.
    private static var upstreamEndpoints: [[String: Any]] {
        [["endpoint": "/v1/messages", "requests": 12_740, "total_tokens": 67_480_000, "cost": "892.63", "actual_cost": "714.10"],
         ["endpoint": "/v1/chat/completions", "requests": 5_460, "total_tokens": 28_920_000, "cost": "382.50", "actual_cost": "306.00"]]
    }
}

// MARK: Failures

private enum BillingRead: Hashable, Sendable { case summary, comparison, trend }

extension AnalyticsFixtures {
    /// How many times each read has answered in this launch.
    @MainActor private static var answered: [BillingRead: Int] = [:]

    @MainActor private static func answer(_ read: BillingRead) async throws {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(Argument.slow) { try await Task.sleep(for: .seconds(3)) }
        let count = answered[read, default: 0]
        answered[read] = count + 1
        if let failure = failure(read, count: count, arguments: arguments) { throw failure }
    }

    private static func failure(_ read: BillingRead, count: Int, arguments: [String]) -> APIError? {
        let readsTheRange = read != .comparison
        if readsTheRange, arguments.contains(Argument.timeout) { return .server(status: 504, reason: nil) }
        if readsTheRange, count == 0, arguments.contains(Argument.failOnce) { return .server(status: 500, reason: nil) }
        if read == .summary, count == 0, arguments.contains(Argument.throttled) { return .server(status: 429, reason: nil) }
        if readsTheRange, count > 0, arguments.contains(Argument.refreshFails) { return .server(status: 500, reason: nil) }
        if read == .comparison, arguments.contains(Argument.comparisonFails) { return .server(status: 500, reason: nil) }
        return nil
    }
}
