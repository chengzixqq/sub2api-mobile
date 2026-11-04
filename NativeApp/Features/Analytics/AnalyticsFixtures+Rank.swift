import Foundation
import Sub2Core

/// 40 §1.3 / §4.2 排行 under `-ui-testing` (S4-15, C-32). One table of model usage by mapping (a -> b) gives the three sources:
/// requested sums by a (12 models, the filter sheet's five first), upstream by b and mapping is the table (13 rows, gpt-5 goes to
/// two upstream models); like the backend, rows come by total_tokens. Groups are the filter sheet's five and four more (9);
/// users are DemoData's, ten of a range of 143. A group filter keeps the claude models and three users, a model filter that
/// model's two groups. Without `dashboard.users_ranking_sort` the users come in the old shape: no costs, no user count.
extension AnalyticsFixtures {
    enum RankArgument {
        /// No usage in any segment.
        static let empty = "-ui-rank-empty"
        /// The full user ranking (limit 50) answers 500; the card's five still load.
        static let pageFailure = "-ui-rank-page-fail"
    }

    @MainActor static func rankModels(_ session: AnalyticsSession, source: ModelSource) throws -> [AnalyticsBreakdown] {
        let scale = rankScale("models.\(source.rawValue)")
        guard !rankIsEmpty else { return [] }
        let usage = rankModelUsage.filter { row in
            switch session.filter {
            case .group?: row.requested.hasPrefix("claude")
            case .model(let name)?: row.requested == name
            case nil: true
            }
        }
        let rows = summed(usage, by: { row in
            switch source {
            case .requested: row.requested
            case .upstream: row.upstream
            case .mapping: row.requested + AnalyticsModelName.arrow + row.upstream
            }
        })
        return try decodeRank(rows.sorted { $0.tokens > $1.tokens }.map { $0.json(key: "model", scale: scale) })
    }

    @MainActor static func rankGroups(_ session: AnalyticsSession) throws -> [AnalyticsBreakdown] {
        let scale = rankScale("groups")
        guard !rankIsEmpty else { return [] }
        let rows: [RankUsage] = switch session.filter {
        case .model?: [RankUsage(name: "高级组", id: 1, requests: 980, tokens: 27_400_000, actual: 15_000, account: 7_800),
                       RankUsage(name: "Claude Code 组", id: 5, requests: 230, tokens: 8_400_000, actual: 3_020, account: 1_620)]
        case .group(let id)?: rankGroupUsage.filter { $0.id == id }
        case nil: rankGroupUsage
        }
        return try decodeRank(rows.sorted { $0.tokens > $1.tokens }.map { row in
            var json = row.json(key: "group_name", scale: scale)
            json["group_id"] = row.id
            return json
        })
    }

    @MainActor static func rankUsers(_ session: AnalyticsSession, sortBy: AnalyticsRankMetric?, limit: Int) throws -> AnalyticsUserRanking {
        let scale = rankScale("users.\(limit).\(sortBy?.rawValue ?? "default")")
        if limit > AnalyticsRanking.cardRows, ProcessInfo.processInfo.arguments.contains(RankArgument.pageFailure) {
            throw APIError.server(status: 500, reason: nil)
        }
        let keyGroup = session.filter?.kind == .group
        let users = rankIsEmpty ? [] : keyGroup ? rankUserUsage.filter { [1, 10, 3].contains($0.id) } : rankUserUsage
        let ordered = users.sorted { lhs, rhs in
            switch sortBy ?? .actualCost {
            case .actualCost: lhs.actual > rhs.actual
            case .requests: lhs.requests > rhs.requests
            case .tokens: lhs.tokens > rhs.tokens
            }
        }
        let others = rankIsEmpty || keyGroup ? RankUsage(name: "", id: 0, requests: 0, tokens: 0, actual: 0, account: 0) : rankOtherUsers
        let reply = rankUserReply(Array(ordered.prefix(limit)), all: users + [others], count: users.count + (others.requests > 0 ? 133 : 0),
                                  scale: scale)
        let ranking = try JSONDecoder().decode(UserSpendingRanking.self, from: JSONSerialization.data(withJSONObject: reply))
        return AnalyticsUserRanking(ranking: ranking, serverSort: sortBy)
    }
}

// MARK: Data

/// Money in cents.
private struct RankUsage {
    let name: String
    var upstream = ""
    var email = ""
    let id: Int
    let requests: Int
    let tokens: Int
    let actual: Int
    let account: Int

    var requested: String { name }

    /// A `dashboard/models` or `dashboard/groups` row; amounts × `scale`.
    func json(key: String, scale: Int) -> [String: Any] {
        [key: name, "requests": requests, "total_tokens": tokens, "cost": rankMoney(actual * 5 / 4 * scale),
         "actual_cost": rankMoney(actual * scale), "account_cost": rankMoney(account * scale)]
    }
}

private func rankMoney(_ cents: Int) -> String { "\(cents / 100)." + (cents % 100 < 10 ? "0" : "") + "\(cents % 100)" }

extension AnalyticsFixtures {
    /// requested → upstream; the first five as AnalyticsFixtures+Filter's models.
    private static let rankModelUsage: [RankUsage] = [
        RankUsage(name: "claude-opus-4", upstream: "claude-opus-4-20250514", id: 0, requests: 1_210, tokens: 35_800_000, actual: 18_020, account: 9_400),
        RankUsage(name: "gpt-5", upstream: "gpt-5-2025-08-07", id: 0, requests: 900, tokens: 25_100_000, actual: 7_560, account: 4_100),
        RankUsage(name: "gpt-5", upstream: "gpt-5-chat-latest", id: 0, requests: 200, tokens: 5_000_000, actual: 1_680, account: 910),
        RankUsage(name: "deepseek-v3", upstream: "deepseek-chat", id: 0, requests: 620, tokens: 11_200_000, actual: 4_130, account: 2_280),
        RankUsage(name: "gemini-2.5-pro", upstream: "gemini-2.5-pro", id: 0, requests: 380, tokens: 7_300_000, actual: 2_610, account: 1_490),
        RankUsage(name: "glm-4.6", upstream: "glm-4.6", id: 0, requests: 195, tokens: 3_000_000, actual: 1_000, account: 620),
        RankUsage(name: "claude-sonnet-4.5", upstream: "claude-sonnet-4-5-20250929", id: 0, requests: 2_400, tokens: 6_900_000, actual: 860, account: 470),
        RankUsage(name: "kimi-k2", upstream: "kimi-k2-0905-preview", id: 0, requests: 310, tokens: 2_600_000, actual: 640, account: 350),
        RankUsage(name: "gpt-5-mini", upstream: "gpt-5-mini-2025-08-07", id: 0, requests: 640, tokens: 4_100_000, actual: 510, account: 260),
        RankUsage(name: "minimax-m2", upstream: "minimax-m2", id: 0, requests: 150, tokens: 1_900_000, actual: 320, account: 190),
        RankUsage(name: "qwen3-coder", upstream: "qwen3-coder-plus", id: 0, requests: 120, tokens: 1_400_000, actual: 210, account: 120),
        RankUsage(name: "claude-haiku-4.5", upstream: "claude-haiku-4-5-20251001", id: 0, requests: 260, tokens: 1_200_000, actual: 180, account: 90),
        RankUsage(name: "text-embedding-3-small", upstream: "text-embedding-3-small", id: 0, requests: 90, tokens: 15_000_000, actual: 30, account: 10),
    ]
    /// The filter sheet's shares, then four smaller groups; 0 is usage without a group.
    private static let rankGroupUsage: [RankUsage] = [
        RankUsage(name: "高级组", id: 1, requests: 1_820, tokens: 48_200_000, actual: 18_240, account: 9_610),
        RankUsage(name: "标准组", id: 2, requests: 960, tokens: 21_400_000, actual: 9_610, account: 5_120),
        RankUsage(name: "默认组", id: 3, requests: 410, tokens: 9_800_000, actual: 4_000, account: 2_230),
        RankUsage(name: "Claude Code 组", id: 5, requests: 230, tokens: 6_100_000, actual: 2_150, account: 1_240),
        RankUsage(name: "", id: 0, requests: 95, tokens: 1_900_000, actual: 1_000, account: 600),
        RankUsage(name: "企业专线", id: 4, requests: 70, tokens: 1_200_000, actual: 820, account: 450),
        RankUsage(name: "GLM 组", id: 7, requests: 80, tokens: 900_000, actual: 630, account: 330),
        RankUsage(name: "Kimi 组", id: 8, requests: 50, tokens: 600_000, actual: 410, account: 220),
        RankUsage(name: "MiniMax 组", id: 9, requests: 30, tokens: 200_000, actual: 220, account: 120),
    ]
    /// Alice has the most requests, 深蓝 AI the most Tokens; 25 has no username.
    private static let rankUserUsage: [RankUsage] = [
        RankUsage(name: "Studio-K 团队", email: "ops@studio-k.example", id: 10, requests: 860, tokens: 24_100_000, actual: 12_040, account: 6_120),
        RankUsage(name: "Nova 工作室", email: "billing@nova.example", id: 21, requests: 640, tokens: 18_300_000, actual: 9_620, account: 4_890),
        RankUsage(name: "Alice", email: "alice@example.com", id: 1, requests: 1_420, tokens: 9_800_000, actual: 6_100, account: 3_100),
        RankUsage(name: "深蓝 AI", email: "team@deepblue.example", id: 23, requests: 520, tokens: 31_200_000, actual: 4_280, account: 2_170),
        RankUsage(name: "王小明", email: "xm.wang@example.com", id: 3, requests: 410, tokens: 6_200_000, actual: 3_010, account: 1_530),
        RankUsage(name: "Atlas 科技", email: "ops@atlas.example", id: 22, requests: 300, tokens: 4_100_000, actual: 1_860, account: 940),
        RankUsage(name: "周婷", email: "ting.zhou@example.com", id: 5, requests: 210, tokens: 2_600_000, actual: 1_240, account: 630),
        RankUsage(name: "", email: "studio@pixel.example", id: 25, requests: 150, tokens: 1_700_000, actual: 830, account: 420),
        RankUsage(name: "林一", email: "yi.lin@example.com", id: 9, requests: 120, tokens: 1_300_000, actual: 620, account: 310),
        RankUsage(name: "Mira Labs", email: "hello@mira.example", id: 24, requests: 60, tokens: 600_000, actual: 310, account: 160),
    ]
    /// The other 133 users of the range, in the totals only.
    private static let rankOtherUsers = RankUsage(name: "", id: 0, requests: 630, tokens: 8_500_000, actual: 5_610, account: 2_840)

    @MainActor private static var rankReads: [String: Int] = [:]

    private static var rankIsEmpty: Bool { ProcessInfo.processInfo.arguments.contains(RankArgument.empty) }

    /// With `Argument.refreshChanges` every amount doubles from a read's second answer on (S4D2b-02 ⑥).
    @MainActor private static func rankScale(_ read: String) -> Int {
        let count = rankReads[read, default: 0]
        rankReads[read] = count + 1
        return count > 0 && ProcessInfo.processInfo.arguments.contains(Argument.refreshChanges) ? 2 : 1
    }

    /// Rows with the same name added up, in the order they first appear.
    private static func summed(_ usage: [RankUsage], by name: (RankUsage) -> String) -> [RankUsage] {
        var order: [String] = [], sums: [String: RankUsage] = [:]
        for row in usage {
            let key = name(row), sum = sums[key]
            if sum == nil { order.append(key) }
            sums[key] = RankUsage(name: key, id: 0, requests: (sum?.requests ?? 0) + row.requests, tokens: (sum?.tokens ?? 0) + row.tokens,
                                  actual: (sum?.actual ?? 0) + row.actual, account: (sum?.account ?? 0) + row.account)
        }
        return order.compactMap { sums[$0] }
    }

    private static func decodeRank(_ rows: [[String: Any]]) throws -> [AnalyticsBreakdown] {
        try JSONDecoder().decode([AnalyticsBreakdown].self, from: JSONSerialization.data(withJSONObject: rows))
    }

    private static var rankHasSort: Bool {
        !UITestArguments.withheldCapabilities(arguments: ProcessInfo.processInfo.arguments).contains(Capability.dashboardUsersRankingSort.rawValue)
    }

    /// `rows` as sent, `all` for the totals; the old shape without `dashboard.users_ranking_sort`.
    private static func rankUserReply(_ rows: [RankUsage], all: [RankUsage], count: Int, scale: Int) -> [String: Any] {
        let current = rankHasSort
        let ranking: [[String: Any]] = rows.map { row in
            var json: [String: Any] = ["user_id": row.id, "email": row.email, "username": row.name, "actual_cost": rankMoney(row.actual * scale),
                                       "requests": row.requests, "tokens": row.tokens]
            if current { json["cost"] = rankMoney(row.actual * 5 / 4 * scale); json["account_cost"] = rankMoney(row.account * scale) }
            return json
        }
        let actual = all.reduce(0) { $0 + $1.actual }, account = all.reduce(0) { $0 + $1.account }
        var reply: [String: Any] = ["ranking": ranking, "total_actual_cost": rankMoney(actual * scale),
                                    "total_requests": all.reduce(0) { $0 + $1.requests }, "total_tokens": all.reduce(0) { $0 + $1.tokens }]
        if current {
            reply["total_users"] = count
            reply["total_cost"] = rankMoney(actual * 5 / 4 * scale)
            reply["total_account_cost"] = rankMoney(account * scale)
        }
        return reply
    }
}
