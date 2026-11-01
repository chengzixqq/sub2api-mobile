import Foundation
import Sub2Core

// 40 §1.4 排行卡、§4 全部排行 (S4-15): what a rank row, the composition strip, the list header, the card foot and the user
// footnote say, the users-ranking read with its INVALID_SORT_BY fallback, and the rank keys. Pure, so NativeSessionSupport tests
// it (40 §4.7 names only AnalyticsRankView.swift); the views are AnalyticsRankCard.swift and AnalyticsRankView.swift.

// MARK: - 文案

extension AnalyticsRankDimension {
    /// 40 §4.1 the full ranking's title.
    var pageTitle: String {
        switch self {
        case .model: "模型分布"
        case .user: "用户排行"
        case .group: "分组使用分布"
        }
    }
    var segmentTitle: String {
        switch self {
        case .model: "模型"
        case .user: "用户"
        case .group: "分组"
        }
    }
    var emptyText: String { "这个范围内没有\(segmentTitle)用量" }
    /// 40 §1.4 / §4.3: the segment is the dimension the session filters by; one row of 100% says nothing, so it is not ranked.
    func isNarrowed(by filter: AnalyticsFilter?) -> Bool {
        switch (self, filter) {
        case (.model, .model?), (.group, .group?): true
        default: false
        }
    }
}

extension AnalyticsRankMetric {
    /// 实际扣费 / 请求 / Tokens.
    var rankTitle: String {
        switch self {
        case .actualCost: "实际扣费"
        case .requests: "请求"
        case .tokens: "Tokens"
        }
    }
    /// The sort menu's items and label: 按实际扣费 / 按请求 / 按 Tokens.
    var sortTitle: String { ("按" + inlineTitle).trimmingCharacters(in: .whitespaces) }
    /// Inside a sentence the Latin word keeps a space on each side.
    fileprivate var inlineTitle: String { self == .tokens ? " \(rankTitle) " : rankTitle }
}

extension ModelSource {
    /// 40 §4.3 the sort menu's 模型口径 items.
    var rankSourceTitle: String {
        switch self {
        case .requested: "请求模型"
        case .upstream: "上游模型"
        case .mapping: "映射（请求 → 上游）"
        }
    }
    /// After the list header's count.
    var rankHeaderTag: String {
        switch self {
        case .requested: ""
        case .upstream: " · 上游模型"
        case .mapping: " · 映射"
        }
    }
}

// MARK: - 卡键

/// 40 §1.3 “结果缓存到范围或筛选改变为止”: every rank key follows the range and the filter. Their value types are fixed.
extension AnalyticsCardKey {
    /// [AnalyticsBreakdown]: `dashboard/models` by `source`. The card and the full ranking share the requested one (coming in from
    /// the card's foot reads nothing again); only it counts toward the subtitle's “N 分钟前更新” (S4D2b-14).
    static func rankModels(_ source: ModelSource) -> AnalyticsCardKey {
        AnalyticsCardKey("rank.models.\(source.rawValue)", showsInUpdateLine: source == .requested)
    }
    /// [AnalyticsBreakdown]: `dashboard/groups`, shared by the card and the full ranking.
    static let rankGroups = AnalyticsCardKey("rank.groups")
    /// AnalyticsUserRanking: the card's five users.
    static let rankCardUsers = AnalyticsCardKey("rank.users.card")
    /// AnalyticsUserRanking: the full ranking's fifty; `sortBy` nil on a site without `dashboard.users_ranking_sort`, whose one
    /// list the phone re-sorts.
    static func rankUsers(sortBy: AnalyticsRankMetric?) -> AnalyticsCardKey {
        AnalyticsCardKey("rank.users.page.\(sortBy?.rawValue ?? "default")", showsInUpdateLine: false)
    }
}

// MARK: - 行与构成条

/// One ranked row (40 §1.4, §4.3).
struct AnalyticsRankItem: Identifiable, Equatable, Sendable {
    /// “model:<raw>” / “group:<id>” / “user:<id>”.
    let id: String
    let name: String
    /// Model names.
    let isMonospaced: Bool
    /// The metric's value: money, grouped count or compact Tokens.
    let value: String
    /// Of the total, within 0…1; 0 when the total is.
    let share: Double
    let shareText: String
    /// 40 §4.3 副行, joined with “ · ”; nil when empty.
    let detail: String?
    /// nil: not tappable (未分组, an unnamed model, a deleted user).
    let route: AppRoute?
}

/// 40 §4.3 构成条: the first three and the rest.
struct AnalyticsRankStrip: Equatable, Sendable {
    struct Part: Equatable, Sendable {
        let name: String
        let share: Double
        let isMonospaced: Bool
    }
    /// “前 3 占 62.4%”, with the actual count below three rows.
    let caption: String
    /// “合计 $1,284.50”, in the metric's format.
    let total: String
    let parts: [Part]
    let rest: Double
    /// “其余 9 个模型”, “其余 6 个分组” beyond three rows; “其余用户 12.3%” when the rest shows.
    let restLegend: String?
}

struct AnalyticsRankList: Equatable, Sendable {
    let items: [AnalyticsRankItem]
    /// nil for one row or none (40 §4.3 构成条“行数 > 1”).
    let strip: AnalyticsRankStrip?
}

/// The card's way to the full ranking.
struct AnalyticsRankFooter: Equatable, Sendable {
    let title: String
    let meta: String?
}

/// A `users-ranking` reply and the order the server used: nil when no `sort_by` went out (no `dashboard.users_ranking_sort`, or
/// the INVALID_SORT_BY fallback), which is the backend's default actual-cost order.
struct AnalyticsUserRanking: Equatable, Sendable {
    let ranking: UserSpendingRanking
    let serverSort: AnalyticsRankMetric?
}

// MARK: - 排行

enum AnalyticsRanking {
    static let cardRows = 5
    static let pageUsers = UserSpendingRanking.maxLimit
    static let cardTitle = "排行"
    static let cardTrailing = "实际扣费 · 前 5"
    static let modelFooterMeta = "含上游口径"
    static let ungrouped = "未分组"
    /// The strip's named parts.
    static let stripParts = 3
    /// Below 0.05% the rest of the users would read 0.0%.
    static let minimumUserRest = 0.0005

    /// Ranked here by the metric (the backend orders by total_tokens), ties by actual cost then name; a share is of all rows.
    static func models(_ rows: [AnalyticsBreakdown], source: ModelSource, metric: AnalyticsRankMetric) -> AnalyticsRankList {
        let candidates = rows.map { row in
            let name = AnalyticsModelName(row.model, source: source)
            return RankCandidate(id: "model:\(name.raw)", name: name.displayName, sortName: name.raw, isMonospaced: true,
                                 actual: row.actualCost, requests: row.requests, tokens: row.tokens, accountCost: row.accountCost,
                                 leading: name.upstream.map { ["→ \($0)"] } ?? [],
                                 route: name.isBlank ? nil : .analyticsModel(model: name.raw, source: source))
        }
        return rank(candidates, metric: metric, total: nil, sorts: true) { count, _ in otherRows(count, unit: "个模型") }
    }

    /// group_id 0 is usage without a group: 未分组, counted but not tappable. A group without a name (deleted) takes the
    /// directory's, else “#id”.
    static func groups(_ rows: [AnalyticsBreakdown], metric: AnalyticsRankMetric, directoryName: (Int) -> String?) -> AnalyticsRankList {
        let candidates = rows.map { row in
            let id = row.groupID ?? 0
            let given = row.groupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = id <= 0 ? ungrouped : given.isEmpty ? directoryName(id) ?? "#\(id)" : given
            return RankCandidate(id: "group:\(id)", name: name, sortName: name, isMonospaced: false, actual: row.actualCost,
                                 requests: row.requests, tokens: row.tokens, accountCost: row.accountCost, leading: [],
                                 route: id > 0 ? .group(id: id) : nil)
        }
        return rank(candidates, metric: metric, total: nil, sorts: true) { count, _ in otherRows(count, unit: "个分组") }
    }

    /// Shares are of the range's totals (total_actual_cost / total_requests / total_tokens; the rows' sum where missing or 0).
    /// Rows keep the server's order unless it sorted by another metric, then they are re-sorted here.
    static func users(_ ranking: AnalyticsUserRanking, metric: AnalyticsRankMetric) -> AnalyticsRankList {
        let reply = ranking.ranking
        let candidates = reply.ranking.map { row in
            let hasUsername = !(row.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let email = (row.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return RankCandidate(id: "user:\(row.userID)", name: row.displayName, sortName: "", isMonospaced: false, actual: row.actualCost,
                                 requests: row.requests, tokens: row.tokens, accountCost: row.accountCost,
                                 leading: hasUsername && !email.isEmpty ? [email] : [], route: row.userID > 0 ? .user(id: row.userID) : nil)
        }
        let total: Decimal? = switch metric {
        case .actualCost: reply.totalActualCost
        case .requests: reply.totalRequests.map { Decimal($0) }
        case .tokens: reply.totalTokens.map { Decimal($0) }
        }
        return rank(candidates, metric: metric, total: total, sorts: (ranking.serverSort ?? .actualCost) != metric) { _, rest in
            rest >= minimumUserRest ? "其余用户 \(DisplayFormat.ratioPercent(rest))" : nil
        }
    }

    /// “12 个模型 · 上游模型”, “9 个分组”, “前 50 位 · 共 143 位” (only “前 50 位” without total_users); the count is the rows'.
    static func listHeader(_ dimension: AnalyticsRankDimension, rows: Int, source: ModelSource, totalUsers: Int?) -> String {
        switch dimension {
        case .model: "\(rows) 个模型" + source.rankHeaderTag
        case .group: "\(rows) 个分组"
        case .user: "前 \(rows) 位" + (totalUsers.map { " · 共 \(DisplayFormat.grouped($0)) 位" } ?? "")
        }
    }

    /// 40 §1.4 卡底（行数 > 5）. The card reads five users only: more than five when total_users says so, or, without it, when
    /// all five came back.
    static func cardFooter(_ dimension: AnalyticsRankDimension, rows: Int, totalUsers: Int?) -> AnalyticsRankFooter? {
        switch dimension {
        case .model: rows > cardRows ? AnalyticsRankFooter(title: "全部 \(rows) 个模型", meta: modelFooterMeta) : nil
        case .group: rows > cardRows ? AnalyticsRankFooter(title: "全部 \(rows) 个分组", meta: nil) : nil
        case .user: (totalUsers.map { $0 > cardRows } ?? (rows >= cardRows)) ? AnalyticsRankFooter(title: "查看前 \(pageUsers) 位用户", meta: nil) : nil
        }
    }

    /// 40 §4.3 用户底注, then the key group's note under a group filter.
    static func userFootnote(metric: AnalyticsRankMetric, ranking: AnalyticsUserRanking, keyGroup: String?) -> String {
        let served = ranking.serverSort ?? .actualCost
        let note = if served == metric {
            "按\(metric.inlineTitle)取前 \(pageUsers) 位" + (ranking.ranking.totalUsers.map { "，共 \(DisplayFormat.grouped($0)) 位用户有用量。" } ?? "。")
        } else {
            "用户排行按\(served.inlineTitle)取前 \(pageUsers) 位，这里在其中按\(metric.inlineTitle)重排。"
        }
        return note + (keyGroup.map(keyGroupNote) ?? "")
    }
    /// users-ranking under a group filter counts the requests made with that group's keys.
    static func keyGroupNote(_ groupName: String) -> String { "按请求时 Key 所属的分组统计：只算各用户在「\(groupName)」Key 上的用量。" }
    static func narrowedText(_ kind: AnalyticsFilter.Kind, name: String) -> String { "已筛选\(kind.title)：\(name)" }
    /// 40 §1.3 / §4.2: `sort_by` only with `dashboard.users_ranking_sort`.
    static func userSortParameter(_ metric: AnalyticsRankMetric, supportsSort: Bool) -> AnalyticsRankMetric? { supportsSort ? metric : nil }

    static func format(_ value: Decimal?, _ metric: AnalyticsRankMetric) -> String {
        switch metric {
        case .actualCost: DisplayFormat.money(value)
        case .requests: DisplayFormat.grouped(value.map { NSDecimalNumber(decimal: $0).intValue })
        case .tokens: DisplayFormat.compact(value.map { NSDecimalNumber(decimal: $0).intValue })
        }
    }

    private static func otherRows(_ count: Int, unit: String) -> String? {
        count > stripParts ? "其余 \(count - stripParts) \(unit)" : nil
    }

    private static func rank(_ candidates: [RankCandidate], metric: AnalyticsRankMetric, total: Decimal?, sorts: Bool,
                             restLegend: (_ count: Int, _ rest: Double) -> String?) -> AnalyticsRankList {
        let ordered = sorts ? sorted(candidates, by: metric) : candidates
        let sum = candidates.reduce(Decimal(0)) { $0 + ($1.amount(metric) ?? 0) }
        let denominator = total.flatMap { $0 > 0 ? $0 : nil } ?? sum
        let items = ordered.map { candidate in
            let fraction = share(candidate.amount(metric) ?? 0, of: denominator)
            return AnalyticsRankItem(id: candidate.id, name: candidate.name, isMonospaced: candidate.isMonospaced, value: candidate.text(metric),
                                     share: fraction, shareText: DisplayFormat.ratioPercent(fraction), detail: candidate.detail(excluding: metric),
                                     route: candidate.route)
        }
        return AnalyticsRankList(items: items, strip: strip(items, total: "合计 " + format(denominator, metric), restLegend: restLegend))
    }

    /// Descending by the metric, then by actual cost, then by name, then as given.
    private static func sorted(_ candidates: [RankCandidate], by metric: AnalyticsRankMetric) -> [RankCandidate] {
        candidates.enumerated().sorted { lhs, rhs in
            let (a, b) = (lhs.element, rhs.element)
            let (valueA, valueB) = (a.amount(metric) ?? 0, b.amount(metric) ?? 0)
            if valueA != valueB { return valueA > valueB }
            let (actualA, actualB) = (a.actual ?? 0, b.actual ?? 0)
            if actualA != actualB { return actualA > actualB }
            if a.sortName != b.sortName { return a.sortName < b.sortName }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    private static func share(_ value: Decimal, of total: Decimal) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: value / total).doubleValue))
    }

    private static func strip(_ items: [AnalyticsRankItem], total: String, restLegend: (Int, Double) -> String?) -> AnalyticsRankStrip? {
        guard items.count > 1 else { return nil }
        let top = Array(items.prefix(stripParts))
        let covered = min(1, top.reduce(0) { $0 + $1.share })
        let rest = max(0, 1 - covered)
        return AnalyticsRankStrip(caption: "前 \(top.count) 占 \(DisplayFormat.ratioPercent(covered))", total: total,
                                  parts: top.map { AnalyticsRankStrip.Part(name: $0.name, share: $0.share, isMonospaced: $0.isMonospaced) },
                                  rest: rest, restLegend: restLegend(items.count, rest))
    }
}

/// A row's figures before it is ranked.
private struct RankCandidate {
    let id: String
    let name: String
    let sortName: String
    let isMonospaced: Bool
    let actual: Decimal?
    let requests: Int?
    let tokens: Int?
    let accountCost: Decimal?
    /// What the detail line starts with: “→ b” for a mapping, the email of a user with a username.
    let leading: [String]
    let route: AppRoute?

    func amount(_ metric: AnalyticsRankMetric) -> Decimal? {
        switch metric {
        case .actualCost: actual
        case .requests: requests.map { Decimal($0) }
        case .tokens: tokens.map { Decimal($0) }
        }
    }
    func text(_ metric: AnalyticsRankMetric) -> String { AnalyticsRanking.format(amount(metric), metric) }

    /// 40 §4.3 副行: the two other metrics in the order 实际 → 请求 → Tokens, then 账号成本 when the reply has it.
    func detail(excluding metric: AnalyticsRankMetric) -> String? {
        let figures = AnalyticsRankMetric.allCases.filter { $0 != metric }.map { other in
            switch other {
            case .actualCost: "实际 " + text(other)
            case .requests: "请求 " + text(other)
            case .tokens: text(other) + " Tokens"
            }
        }
        let cost = accountCost.map { ["账号成本 " + DisplayFormat.money($0)] } ?? []
        let parts = leading + figures + cost
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - 读取

/// 40 §4.5: a site that refuses `sort_by` (400 INVALID_SORT_BY, which should not happen) is asked once more without it.
enum AnalyticsRankLoader {
    static let invalidSortBy = "INVALID_SORT_BY"
    typealias FetchUsers = @Sendable (AnalyticsQuery, AnalyticsRankMetric?, Int) async throws -> UserSpendingRanking

    /// Any other failure is thrown as is, without a retry.
    static func users(_ query: AnalyticsQuery, sortBy: AnalyticsRankMetric?, limit: Int, fetch: FetchUsers) async throws -> AnalyticsUserRanking {
        do {
            return AnalyticsUserRanking(ranking: try await fetch(query, sortBy, limit), serverSort: sortBy)
        } catch let error as APIError where sortBy != nil && error.reason == invalidSortBy {
            return AnalyticsUserRanking(ranking: try await fetch(query, nil, limit), serverSort: nil)
        }
    }
}

/// The full ranking's sort (one per dimension) and model source (40 §4.4), as remembered; the page writes them back only when the
/// user picks another (S4D1-03).
struct AnalyticsRankChoice: Hashable, Sendable {
    var metric: AnalyticsRankMetric
    var source: ModelSource

    @MainActor static func remembered(_ memory: AnalyticsMemory, dimension: AnalyticsRankDimension, serverID: UUID) -> AnalyticsRankChoice {
        AnalyticsRankChoice(metric: memory.rankSort(for: dimension, serverID: serverID), source: memory.rankModelSource(serverID: serverID))
    }
}

/// 40 §1.3 / §1.7: the card reads only the segment it shows.
enum AnalyticsRankCardPlan {
    static func key(for dimension: AnalyticsRankDimension) -> AnalyticsCardKey {
        switch dimension {
        case .model: .rankModels(.requested)
        case .user: .rankCardUsers
        case .group: .rankGroups
        }
    }

    /// On a refresh (pull, the 60-second tick, the foreground) the card drops the other two segments' values without reading them,
    /// so switching back reads the moved window and an old success no longer holds the subtitle back (S4D2b-20). One being read
    /// already (by the full ranking, which shares two of these keys) is left alone.
    @MainActor static func dropHidden(_ session: AnalyticsSessionState, showing: AnalyticsRankDimension) {
        for dimension in AnalyticsRankDimension.allCases where dimension != showing && !isReading(dimension, in: session) {
            session.reset(key(for: dimension))
        }
    }

    @MainActor private static func isReading(_ dimension: AnalyticsRankDimension, in session: AnalyticsSessionState) -> Bool {
        let key = key(for: dimension)
        return switch dimension {
        case .user: session.state(key, as: AnalyticsUserRanking.self)?.isAwaitingAnswer == true
        case .model, .group: session.state(key, as: [AnalyticsBreakdown].self)?.isAwaitingAnswer == true
        }
    }
}
