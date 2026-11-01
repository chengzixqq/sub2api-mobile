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
