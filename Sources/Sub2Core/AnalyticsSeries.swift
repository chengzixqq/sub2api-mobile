import Foundation

// 40 §2.3 更多图表's usage charts (S4-17): the stacking every stacked chart shares, Token 使用趋势 over `dashboard/trend`, 端点分布
// over the totals' `endpoints`, and the tiles' text. S4-17b adds 用户用量趋势 and 请求类型 at the end of this file.

/// Token 使用趋势's kinds, in the legend's order and bottom-up in each column.
public enum TokenKind: String, CaseIterable, Hashable, Sendable {
    case input, output, cacheRead, cacheWrite

    public var title: String {
        switch self {
        case .input: "输入"
        case .output: "输出"
        case .cacheRead: "缓存读"
        case .cacheWrite: "缓存写"
        }
    }
}

/// One bucket's tokens (or a range's) by kind; `total` is the backend's `total_tokens`, never the four added up.
public struct TokenMix: Hashable, Sendable {
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheWrite: Int
    public let total: Int

    public static let zero = TokenMix()

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, total: Int = 0) {
        self.input = input; self.output = output; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite; self.total = total
    }
    public init(_ point: TrendPoint) {
        self.init(input: point.inputTokens, output: point.outputTokens, cacheRead: point.cacheReadTokens,
                  cacheWrite: point.cacheCreationTokens, total: point.totalTokens)
    }

    public subscript(kind: TokenKind) -> Int {
        switch kind {
        case .input: input
        case .output: output
        case .cacheRead: cacheRead
        case .cacheWrite: cacheWrite
        }
    }

    public static func + (lhs: TokenMix, rhs: TokenMix) -> TokenMix {
        TokenMix(input: lhs.input + rhs.input, output: lhs.output + rhs.output, cacheRead: lhs.cacheRead + rhs.cacheRead,
                 cacheWrite: lhs.cacheWrite + rhs.cacheWrite, total: lhs.total + rhs.total)
    }
}

/// One layer's piece of a stacked column, in the chart's units.
public struct AnalyticsStackSegment<Layer: Hashable & Sendable>: Hashable, Sendable {
    public let layer: Layer
    public let lower: Double
    public let upper: Double

    public init(layer: Layer, lower: Double, upper: Double) { self.layer = layer; self.lower = lower; self.upper = upper }
}

/// 端点分布's two lists.
public enum EndpointSide: String, CaseIterable, Hashable, Sendable {
    case inbound, upstream

    public var title: String { self == .inbound ? "入站端点" : "上游端点" }
}

/// A share row (端点分布): the name, its requests and their share of the rows' sum, and what was charged for them.
public struct AnalyticsShareRow: Identifiable, Hashable, Sendable {
    public let name: String
    public let requests: Int
    /// requests ÷ the rows' requests, 0–1.
    public let share: Double
    public let actualCost: Decimal?
    public var id: String { name }

    public var requestsText: String { DisplayFormat.grouped(requests) }
    public var shareText: String { DisplayFormat.ratioPercent(share) }
    /// “实际 $612.40”.
    public var costLine: String { "实际 " + DisplayFormat.money(actualCost) }
    /// “/v1/messages，10,920 次请求，占 60.0%，实际 $612.40”.
    public var spokenLabel: String {
        "\(name)，\(requestsText) 次请求，占 \(shareText)，实际 " + DisplayFormat.spoken(DisplayFormat.money(actualCost))
    }
}

/// A tile on 更多图表卡 (40 §1.4): the big value, its unit and the line under it — “96.4M” Tokens / “缓存读占 54%”.
public struct AnalyticsTileText: Hashable, Sendable {
    public let value: String
    public let unit: String?
    public let label: String

    public init(value: String, unit: String? = nil, label: String) { self.value = value; self.unit = unit; self.label = label }
}

public enum AnalyticsSeries {
    /// Each column bottom-up in `order`; a layer at 0 or below is left out. Every segment above the column's first starts `gap`
    /// higher and keeps its top (the column's height stays), and one no thicker than `gap` is dropped.
    public static func stack<Layer: Hashable & Sendable>(_ columns: [[Layer: Double]], order: [Layer],
                                                         gap: Double = 0) -> [[AnalyticsStackSegment<Layer>]] {
        columns.map { column in
            let values: [(layer: Layer, value: Double)] = order.compactMap { layer in
                guard let value = column[layer], value > 0 else { return nil }
                return (layer, value)
            }
            let tops = values.reduce(into: [Double]()) { tops, item in tops.append((tops.last ?? 0) + item.value) }
            return values.indices.compactMap { index -> AnalyticsStackSegment<Layer>? in
                let item = values[index], lower = tops[index] - item.value
                if index == 0 { return AnalyticsStackSegment(layer: item.layer, lower: lower, upper: tops[index]) }
                guard item.value > gap else { return nil }
                return AnalyticsStackSegment(layer: item.layer, lower: lower + gap, upper: tops[index])
            }
        }
    }
}

// MARK: - Token 使用趋势

extension AnalyticsSeries {
    /// One per bucket of the range; a bucket the trend left out is `.zero` (40 §0.2).
    public static func tokenMixes(range: AnalyticsRange, points: [TrendPoint]) -> [TokenMix] {
        range.slots(points, key: \.date).map { $0.value.map(TokenMix.init) ?? .zero }
    }
    public static func tokenTotal(_ mixes: [TokenMix]) -> TokenMix { mixes.reduce(.zero, +) }

    /// Every kind, or the one the legend singles out (a one-colour bar).
    public static func tokenLayers(only: TokenKind?) -> [TokenKind] { only.map { [$0] } ?? TokenKind.allCases }
    public static func tokenColumns(_ mixes: [TokenMix], only: TokenKind?) -> [[TokenKind: Double]] {
        let layers = tokenLayers(only: only)
        return mixes.map { mix in Dictionary(uniqueKeysWithValues: layers.map { ($0, Double(mix[$0])) }) }
    }
    /// All four kinds at 0 everywhere: “这个范围内没有用量”.
    public static func hasTokens(_ mixes: [TokenMix]) -> Bool {
        mixes.contains { mix in TokenKind.allCases.contains { mix[$0] > 0 } }
    }
    /// Σcache_read ÷ Σtotal_tokens; nil without tokens.
    public static func cacheReadShare(_ total: TokenMix) -> Double? {
        total.total > 0 ? Double(total.cacheRead) / Double(total.total) : nil
    }

    /// The selected bucket first (“10月16日 9:00–9:41 · 合计 9.8M”), then the kind singled out (“只看缓存读，再点一次图例恢复全部”),
    /// else “合计 96.4M · 缓存读占 54% · 点图例只看一项”. A selection past the buckets reads as none.
    public static func tokenFootnote(range: AnalyticsRange, mixes: [TokenMix], selected: Int?, only: TokenKind?) -> String {
        if let selected, range.buckets.indices.contains(selected), mixes.indices.contains(selected) {
            return range.buckets[selected].fullName + " · 合计 " + DisplayFormat.compact(mixes[selected].total)
        }
        if let only { return "只看\(only.title)，再点一次图例恢复全部" }
        let total = tokenTotal(mixes)
        return "合计 " + DisplayFormat.compact(total.total) + " · 缓存读占 " + DisplayFormat.wholePercent(cacheReadShare(total)) + " · 点图例只看一项"
    }

    /// “96.4M” Tokens / “缓存读占 54%”.
    public static func tokenTile(_ total: TokenMix) -> AnalyticsTileText {
        AnalyticsTileText(value: DisplayFormat.compact(total.total), unit: "Tokens",
                          label: "缓存读占 " + DisplayFormat.wholePercent(cacheReadShare(total)))
    }

    /// The chart page's table: 时段 / 输入 / 输出 / 缓存读 / 缓存写, newest on top.
    public static func tokenTable(range: AnalyticsRange, mixes: [TokenMix]) -> AnalyticsDetailTable {
        let columns = TokenKind.allCases.map(\.title)
        let rows = range.buckets.map { bucket in
            let mix = mixes.indices.contains(bucket.index) ? mixes[bucket.index] : .zero
            let cells = TokenKind.allCases.map { DisplayFormat.compact(mix[$0]) }
            return AnalyticsDetailTable.Row(bucketIndex: bucket.index, period: bucket.shortName, cells: cells,
                                            spokenLabel: AnalyticsDetailTable.spoken(bucket.spokenLabel, columns: columns, cells: cells))
        }
        return AnalyticsDetailTable(granularity: range.granularity, columns: columns, rows: rows.reversed())
    }
}

// MARK: - 端点分布

extension AnalyticsSeries {
    /// By requests, most first, equal counts by name; shares of the rows' sum. Missing, empty or without requests: none.
    public static func shareRows(_ stats: [AnalyticsEndpointStat]?) -> [AnalyticsShareRow] {
        let stats = stats ?? []
        let sum = stats.reduce(0) { $0 + $1.requests }
        guard sum > 0 else { return [] }
        return stats
            .sorted { $0.requests != $1.requests ? $0.requests > $1.requests : $0.endpoint < $1.endpoint }
            .map { AnalyticsShareRow(name: $0.endpoint, requests: $0.requests, share: Double($0.requests) / Double(sum), actualCost: $0.actualCost) }
    }
    public static func endpointRows(_ summary: AnalyticsSummary?, side: EndpointSide) -> [AnalyticsShareRow] {
        shareRows(side == .inbound ? summary?.endpoints : summary?.upstreamEndpoints)
    }
    /// The first inbound row: “60%” / “/v1/messages 占请求”; none: “—” / “没有用量”.
    public static func endpointTile(_ summary: AnalyticsSummary?) -> AnalyticsTileText {
        guard let first = endpointRows(summary, side: .inbound).first else { return AnalyticsTileText(value: DisplayFormat.missing, label: "没有用量") }
        return AnalyticsTileText(value: DisplayFormat.wholePercent(first.share), label: first.name + " 占请求")
    }
}

// MARK: - 用户用量趋势（S4-17b）

extension UserTrendMetric {
    /// The segment: Tokens · 实际扣费.
    public var title: String { self == .tokens ? "Tokens" : "实际扣费" }
}

/// 40 §2.3 用户用量趋势 over `users-trend`: a row per user with a value per bucket of the range (the reply leaves out the buckets a
/// user has no row in: 0), most first by the metric's total, equal totals by id (the backend's ORDER BY), at most `limit`.
public struct UserUsageSeries: Hashable, Sendable {
    /// `users-trend`'s `limit` (40 §2.2); a card shows the first `cardRowCount`, the chart page all of them.
    public static let limit = 12
    public static let cardRowCount = 5

    public struct Row: Identifiable, Hashable, Sendable {
        public let userID: Int
        /// The username, else the email, else “#id”.
        public let name: String
        /// One per bucket of the range, in the metric's units.
        public let values: [Decimal]
        /// Every row of the reply, one outside the buckets too: what the backend ranked by.
        public let total: Decimal
        public var id: Int { userID }

        /// Each line on its own scale (40 §2.3): a value ÷ the row's largest, 0–1; all 0 without usage.
        public var normalized: [Double] {
            guard let top = values.max(), top > 0 else { return values.map { _ in 0 } }
            return values.map { min(1, max(0, NSDecimalNumber(decimal: $0 / top).doubleValue)) }
        }
    }

    public let metric: UserTrendMetric
    public let rows: [Row]
    public var isEmpty: Bool { rows.isEmpty }

    /// A missing `actual_cost` counts as 0.
    public init(points: [UserTrendPoint], range: AnalyticsRange, metric: UserTrendMetric) {
        let value: (UserTrendPoint) -> Decimal = { metric == .tokens ? Decimal($0.tokens) : $0.actualCost ?? 0 }
        let rows = Dictionary(grouping: points, by: \.userID).map { userID, points in
            Row(userID: userID, name: points[0].displayName, values: range.slots(points, key: \.date).map { $0.value.map(value) ?? 0 },
                total: points.reduce(0) { $0 + value($1) })
        }
        self.metric = metric
        self.rows = Array(rows.sorted { $0.total != $1.total ? $0.total > $1.total : $0.userID < $1.userID }.prefix(Self.limit))
    }
}

extension UserUsageSeries {
    /// 40 §2.2: under a filter without `dashboard.users_trend_filtered_metric` only Tokens.
    public static func metrics(isFiltered: Bool, supportsFilteredMetric: Bool) -> [UserTrendMetric] {
        isFiltered && !supportsFilteredMetric ? [.tokens] : UserTrendMetric.allCases
    }
    /// The `metric` sent: none where the server reads none (an old one under a filter ranks by Tokens).
    public static func requestMetric(_ selected: UserTrendMetric, isFiltered: Bool, supportsFilteredMetric: Bool) -> UserTrendMetric? {
        isFiltered && !supportsFilteredMetric ? nil : selected
    }
    /// “按 Tokens 取前 12 位，这里显示前 5 位；每条线用自己的刻度，只看走势。”; the chart page shows all, without the middle clause.
    public static func note(metric: UserTrendMetric, showsAll: Bool) -> String {
        "按" + (metric == .tokens ? " Tokens " : "实际扣费") + "取前 \(limit) 位" + (showsAll ? "" : "，这里显示前 \(cardRowCount) 位")
            + "；每条线用自己的刻度，只看走势。"
    }

    /// Tokens compact (“12.4M”), 实际扣费 in dollars.
    public func totalText(_ row: Row) -> String {
        metric == .tokens ? DisplayFormat.compact(NSDecimalNumber(decimal: row.total).intValue) : DisplayFormat.money(row.total)
    }
    /// “第 1 名，Nova 工作室，12.4M Tokens”.
    public func spokenLabel(_ index: Int) -> String {
        guard rows.indices.contains(index) else { return "" }
        let row = rows[index]
        return "第 \(index + 1) 名，\(row.name)，" + totalText(row) + (metric == .tokens ? " Tokens" : "")
    }
    /// The first user: “12.4M” Tokens / “第 1 · Nova 工作室”; none: “—” / “没有用户用量”.
    public var tile: AnalyticsTileText {
        guard let first = rows.first else { return AnalyticsTileText(value: DisplayFormat.missing, label: "没有用户用量") }
        return AnalyticsTileText(value: totalText(first), unit: metric == .tokens ? "Tokens" : nil, label: "第 1 · " + first.name)
    }
}

// MARK: - 请求类型（S4-17b）

/// 40 §2.3 请求类型: the five types in UsageRequestType's order (S4D1-07), one without requests at 0. unknown and values the App does
/// not know are left out, so the shares add up to 100%.
public struct RequestTypeMix: Hashable, Sendable {
    public struct Row: Identifiable, Hashable, Sendable {
        public let type: UsageRequestType
        public let requests: Int
        /// requests ÷ the five's sum, 0–1; nil without requests.
        public let share: Double?
        public var id: UsageRequestType { type }
        /// Hollow, and not in the bar.
        public var isEmpty: Bool { requests == 0 }
        public var requestsText: String { DisplayFormat.grouped(requests) }
        public var shareText: String { DisplayFormat.ratioPercent(share) }
        /// “流式，13,120 次请求，占 72.1%”.
        public var spokenLabel: String { "\(type.title)，\(requestsText) 次请求，占 \(shareText)" }
    }

    public let rows: [Row]
    public let total: Int
    public var isEmpty: Bool { total == 0 }
    /// The bar's pieces: the types with requests, in order.
    public var barRows: [Row] { rows.filter { !$0.isEmpty } }
    /// “流式 72.1%，同步 23.7%，…”.
    public var barSpokenLabel: String { barRows.map { $0.type.title + " " + $0.shareText }.joined(separator: "，") }

    /// `dashboard/request-types`: a type's rows add up.
    public init(stats: [RequestTypeStat]) {
        self.init(counts: stats.reduce(into: [UsageRequestType: Int]()) { counts, stat in
            if let kind = stat.kind { counts[kind, default: 0] += stat.requests }
        })
    }
    /// The fallback's `total_requests` per type.
    public init(counts: [UsageRequestType: Int]) {
        let requests = UsageRequestType.allCases.map { max(0, counts[$0] ?? 0) }
        let total = requests.reduce(0, +)
        self.total = total
        rows = zip(UsageRequestType.allCases, requests).map { type, count in
            Row(type: type, requests: count, share: total > 0 ? Double(count) / Double(total) : nil)
        }
    }

    /// “72%” / “流式占请求”; without requests “—”.
    public var tile: AnalyticsTileText {
        AnalyticsTileText(value: DisplayFormat.wholePercent(rows.first { $0.type == .stream }?.share), label: "流式占请求")
    }
}

extension RequestTypeMix {
    /// 40 §2.2: one `dashboard/request-types` with `dashboard.request_types`; without it one `usage/stats` per type, four at a time
    /// (AnalyticsFanOut), reading `total_requests`. The shares need all five, so a failure sends no more and fails the whole mix
    /// with its own error (a timeout, a 429, an old server's 400 to cyber or live).
    public static func load(_ query: AnalyticsQuery, client: APIClient, supportsRequestTypes: Bool) async throws -> RequestTypeMix {
        if supportsRequestTypes { return RequestTypeMix(stats: try await client.usageAnalysisRequestTypes(query)) }
        let types = UsageRequestType.allCases
        let results = try await AnalyticsFanOut.results(types, stopsAfter: { _ in true }) { type in
            var scoped = query
            scoped.requestType = type
            return try await client.usageAnalysis(scoped).requests
        }
        for result in results { if case .failure(let error)? = result { throw error } }
        let counts = zip(types, results).reduce(into: [UsageRequestType: Int]()) { counts, pair in
            if case .success(let requests)? = pair.1 { counts[pair.0] = requests }
        }
        return RequestTypeMix(counts: counts)
    }
}
