import Foundation
import Sub2Core

/// 40 §5 模型页 under `-ui-testing` (S4-19, X44). The model's totals are its row of AnalyticsFixtures+Rank for the same source, so
/// the page's big number is the rank row's amount (claude-opus-4 $180.20 under every source); the comparison window is 90% of it
/// (↑ 11.1%), the trend splits it over the range's buckets, the users are three of DemoData's sharing 76% of it. The speed rows:
/// a filtered upstream name answers two requested models to merge, a requested one its own row, the site-wide read five models.
/// The denominator is S4-13's billing total.
extension AnalyticsFixtures {
    @MainActor static func modelSummary(_ name: AnalyticsModelName, session: AnalyticsSession, comparison: Bool = false) throws -> AnalyticsSummary {
        let usage = try modelUsage(name, session: session).scaled(comparison ? 9 : 10, 10)
        let json: [String: Any] = [
            "total_requests": usage.requests, "total_tokens": usage.tokens, "total_cache_read_tokens": usage.tokens * 54 / 100,
            "total_cost": modelAmount(usage.standard), "total_actual_cost": modelAmount(usage.actual),
            "total_account_cost": modelAmount(usage.account), "average_duration_ms": usage.requests > 0 ? 2_400 : 0,
        ]
        return try JSONDecoder().decode(AnalyticsSummary.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @MainActor static func modelTrend(_ name: AnalyticsModelName, session: AnalyticsSession) throws -> DashboardTrendReply {
        let usage = try modelUsage(name, session: session), buckets = session.range.buckets
        let weights = buckets.indices.map { modelWeights[$0 % modelWeights.count] }
        let actual = modelSplit(usage.actual, weights), standard = modelSplit(usage.standard, weights)
        let account = modelSplit(usage.account, weights), requests = modelSplit(usage.requests, weights)
        let tokens = modelSplit(usage.tokens, weights)
        let points = buckets.indices.compactMap { index -> TrendPoint? in
            guard requests[index] > 0 else { return nil }
            return TrendPoint(date: buckets[index].wireKey, requests: requests[index], totalTokens: tokens[index],
                              cost: Decimal(standard[index]) / 100, actualCost: Decimal(actual[index]) / 100,
                              accountCost: Decimal(account[index]) / 100, cacheReadTokens: tokens[index] * 54 / 100)
        }
        return DashboardTrendReply(points: points, timeZone: session.timeZone.timeZone)
    }

    /// Without `dashboard.users_ranking_sort` the old shape: no costs but the actual one, no user count.
    @MainActor static func modelUsers(_ name: AnalyticsModelName, session: AnalyticsSession, sortBy: AnalyticsRankMetric?) throws -> AnalyticsUserRanking {
        let usage = try modelUsage(name, session: session)
        let current = !UITestArguments.withheldCapabilities(arguments: ProcessInfo.processInfo.arguments)
            .contains(Capability.dashboardUsersRankingSort.rawValue)
        let rows: [[String: Any]] = usage.requests == 0 ? [] : modelTopUsers.map { user in
            let part = usage.scaled(user.percent, 100)
            var row: [String: Any] = ["user_id": user.id, "username": user.name, "email": user.email, "actual_cost": modelAmount(part.actual),
                                      "requests": part.requests, "tokens": part.tokens]
            if current { row["cost"] = modelAmount(part.standard); row["account_cost"] = modelAmount(part.account) }
            return row
        }
        var reply: [String: Any] = ["ranking": rows, "total_actual_cost": modelAmount(usage.actual), "total_requests": usage.requests,
                                    "total_tokens": usage.tokens]
        if current { reply["total_users"] = usage.requests == 0 ? 0 : 18 }
        let ranking = try JSONDecoder().decode(UserSpendingRanking.self, from: JSONSerialization.data(withJSONObject: reply))
        return AnalyticsUserRanking(ranking: ranking, serverSort: sortBy)
    }

    @MainActor static func modelSpeed(_ plan: AnalyticsModelSpeedPlan, session: AnalyticsSession, supportsCustomRange: Bool) -> AnalyticsModelSpeed {
        let window = OpsTokenStatsWindow.select(start: session.range.start, end: session.range.end, now: session.now, zone: session.timeZone,
                                                supportsCustomRange: supportsCustomRange)
        let rows: [OpsTokenStats.Item] = switch plan {
        case .filtered(let model, .upstream): [modelSpeedRow(model, 1_210, 52.4, 1_820, 9_400), modelSpeedRow(model + "-latest", 90, 47.0, 2_100, 10_200)]
        case .filtered(let model, _): [modelSpeedRow(model, 1_210, 52.4, 1_820, 9_400)]
        case .matching, .unavailable: modelSiteSpeed
        }
        return AnalyticsModelSpeed(OpsTokenStats(items: rows, window: window), plan: plan)
    }

    /// 统计分析's total over the same range and group.
    @MainActor static func modelDenominator(_ session: AnalyticsSession) async throws -> AnalyticsSummary {
        try await billingSummary(session)
    }
}

// MARK: Data

/// Money in cents.
private struct ModelUsage {
    let requests: Int
    let tokens: Int
    let actual: Int
    let standard: Int
    let account: Int

    func scaled(_ numerator: Int, _ denominator: Int) -> ModelUsage {
        ModelUsage(requests: requests * numerator / denominator, tokens: tokens * numerator / denominator, actual: actual * numerator / denominator,
                   standard: standard * numerator / denominator, account: account * numerator / denominator)
    }
}

private struct ModelUser {
    let id: Int
    let name: String
    let email: String
    let percent: Int
}

extension AnalyticsFixtures {
    private static let modelWeights = [3, 5, 4, 6, 8, 7, 9, 5, 6, 4, 7, 8]
    private static let modelTopUsers = [ModelUser(id: 10, name: "Studio-K 团队", email: "ops@studio-k.example", percent: 42),
                                        ModelUser(id: 1, name: "Alice", email: "alice@example.com", percent: 23),
                                        ModelUser(id: 3, name: "王小明", email: "xm.wang@example.com", percent: 11)]
    private static let modelSiteSpeed = [modelSpeedRow("claude-sonnet-4.5", 2_400, 61.2, 1_240, 7_800), modelSpeedRow("claude-opus-4", 1_210, 52.4, 1_820, 9_400),
                                         modelSpeedRow("gpt-5", 1_100, 78.5, 940, 6_100), modelSpeedRow("gpt-5-mini", 640, 112.0, 410, 2_300),
                                         modelSpeedRow("deepseek-v3", 620, 38.6, 1_560, 11_200)]

    /// The model's row of the rank fixture for its source; none (or `-ui-rank-empty`) is no usage.
    @MainActor private static func modelUsage(_ name: AnalyticsModelName, session: AnalyticsSession) throws -> ModelUsage {
        guard let row = try rankModels(session, source: name.source).first(where: { $0.model == name.raw }) else {
            return ModelUsage(requests: 0, tokens: 0, actual: 0, standard: 0, account: 0)
        }
        return ModelUsage(requests: row.requests, tokens: row.tokens, actual: modelCents(row.actualCost), standard: modelCents(row.standardCost),
                          account: modelCents(row.accountCost))
    }

    private static func modelSpeedRow(_ model: String, _ requests: Int, _ speed: Double, _ firstToken: Double, _ duration: Double) -> OpsTokenStats.Item {
        OpsTokenStats.Item(model: model, requestCount: requests, tokensPerSecond: speed, firstTokenMs: firstToken, durationMs: duration,
                           requestsWithFirstToken: requests * 98 / 100)
    }

    /// By `weights`, the rest to the last bucket, so a column adds up to its total.
    private static func modelSplit(_ total: Int, _ weights: [Int]) -> [Int] {
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return weights.map { _ in 0 } }
        var shares = weights.map { total * $0 / sum }
        if !shares.isEmpty { shares[shares.count - 1] += total - shares.reduce(0, +) }
        return shares
    }

    private static func modelCents(_ value: Decimal?) -> Int { NSDecimalNumber(decimal: (value ?? 0) * 100).intValue }
    private static func modelAmount(_ cents: Int) -> String { "\(cents / 100)." + (cents % 100 < 10 ? "0" : "") + "\(cents % 100)" }
}
