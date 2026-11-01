import Foundation

/// 40 §1.3 降级: an old server's trend has no `account_cost`, so each such bucket's `total_account_cost` is read on its own
/// (`APIClient.profitSegmentCosts`). Keyed by the bucket's wireKey, with the end of the window read: the bucket still running
/// moves its end, so its cost is read again. A segment that failed, was never sent or came back without the key is not here.
public struct ProfitSegmentCosts: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        public let end: Date
        public let cost: Decimal
    }

    public let segments: [String: Segment]

    public init(segments: [String: Segment] = [:]) { self.segments = segments }
    /// `costs` follow `buckets`; a nil one is left out.
    public init(_ buckets: [AnalyticsBucket], costs: [Decimal?]) {
        let read = zip(buckets, costs).compactMap { bucket, cost in cost.map { (bucket.wireKey, Segment(end: bucket.end, cost: $0)) } }
        segments = Dictionary(read, uniquingKeysWith: { _, later in later })
    }

    public func cost(for bucket: AnalyticsBucket) -> Decimal? { segments[bucket.wireKey]?.cost }
    /// Whether the bucket's window as it stands now was read.
    public func covers(_ bucket: AnalyticsBucket) -> Bool { segments[bucket.wireKey]?.end == bucket.end }
    /// The buckets `reread` take `newer`'s answer, missing where it has none (40 §1.3: a failed segment shows “—”, not an
    /// older window's cost); the others keep this one's.
    public func merging(_ newer: ProfitSegmentCosts, reread: [AnalyticsBucket]) -> ProfitSegmentCosts {
        let replaced = Set(reread.map(\.wireKey))
        return ProfitSegmentCosts(segments: segments.filter { !replaced.contains($0.key) }.merging(newer.segments) { _, new in new })
    }
}

/// 40 §1.4 利润明细: every bucket of the range with its actual charge, account cost and profit, split to cents by S4-09's ProfitRows
/// against the range's `usage/stats` totals. A bucket the trend left out is 0; a row without `account_cost` takes its segment's
/// cost, “—” when that could not be read.
public struct ProfitBreakdown: Equatable, Sendable {
    /// The card's table: the latest buckets, newest on top.
    public static let recentCount = 4

    public struct Line: Identifiable, Equatable, Sendable {
        public let bucket: AnalyticsBucket
        public let actual: Decimal?
        public let accountCost: Decimal?
        public let profit: Decimal?
        public var id: Int { bucket.index }
    }

    public let lines: [Line]
    public let totalActual: Decimal?
    public let totalAccountCost: Decimal?
    public let totalProfit: Decimal?
    /// Each column adds up to its total; false once a segment is missing (S4-14's note then leaves out “逐段相加等于合计”).
    public let isReconciled: Bool
    /// 这个范围内没有扣费: every bucket's actual charge and account cost are 0. A range of losses is not empty (S4D2b-09 ②).
    public let isEmpty: Bool

    public init(range: AnalyticsRange, trend: [TrendPoint], summary: AnalyticsSummary?, segments: ProfitSegmentCosts? = nil) {
        let slots = range.slots(trend, key: \.date)
        let actual = slots.map { $0.value?.actualCost ?? 0 }
        let costs: [Decimal?] = slots.map { slot in
            guard let point = slot.value else { return 0 }
            return point.accountCost ?? segments?.cost(for: slot.bucket)
        }
        let rows = ProfitRows(actual: actual, accountCost: costs, totalActual: summary?.actualCost, totalAccountCost: summary?.accountCost)
        lines = zip(slots, rows.rows).map { slot, row in
            Line(bucket: slot.bucket, actual: row.actual, accountCost: row.accountCost, profit: row.profit)
        }
        totalActual = rows.totalActual
        totalAccountCost = rows.totalAccountCost
        totalProfit = rows.totalProfit
        isReconciled = rows.isReconciled
        isEmpty = zip(actual, costs).allSatisfy { $0 == 0 && ($1 ?? 0) == 0 }
    }

    /// The last `count` buckets, newest first.
    public func recent(_ count: Int = ProfitBreakdown.recentCount) -> [Line] { Array(lines.suffix(max(0, count)).reversed()) }
    /// nil for no selection or one past the buckets (the range moved on).
    public func line(at index: Int?) -> Line? { index.flatMap { lines.indices.contains($0) ? lines[$0] : nil } }

    /// The buckets whose trend row has no `account_cost`; none when the totals were read without `total_account_cost` (their
    /// segments would not have it either). A bucket without a row had no usage and costs nothing.
    public static func segmentsToRead(range: AnalyticsRange, trend: [TrendPoint], summary: AnalyticsSummary?) -> [AnalyticsBucket] {
        if let summary, summary.accountCost == nil { return [] }
        return range.slots(trend, key: \.date).compactMap { slot in
            guard let point = slot.value, point.accountCost == nil else { return nil }
            return slot.bucket
        }
    }
    /// What a refresh reads again (S4D2b-09 ⑥): of `segmentsToRead`, those `previous` has no answer for, or read over another
    /// window (the bucket still running, or the one that was when it was read). A range or filter change starts with no previous.
    public static func segmentsToRefresh(range: AnalyticsRange, trend: [TrendPoint], summary: AnalyticsSummary?,
                                         previous: ProfitSegmentCosts?) -> [AnalyticsBucket] {
        let wanted = segmentsToRead(range: range, trend: trend, summary: summary)
        guard let previous else { return wanted }
        return wanted.filter { !previous.covers($0) }
    }
}

/// 40 §1.4 利润明细卡's wording and VoiceOver. Profit is never coloured and a loss reads −$ (40 §0.4).
public enum ProfitCardText {
    public static let title = "利润明细"
    public static let meta = "实际扣费 − 账号成本"
    public static let emptyText = "这个范围内没有扣费"

    /// “利润 · 近 7 天”, or the selected bucket's full name.
    public static func heroLabel(rangeName: String, selected: ProfitBreakdown.Line?) -> String {
        selected?.bucket.fullName ?? "利润 · " + rangeName
    }
    /// The range's profit, or the selected bucket's (“—” when its segment is missing, never the total).
    public static func heroValue(total: Decimal?, selected: ProfitBreakdown.Line?) -> String {
        DisplayFormat.money(selected.map(\.profit) ?? total)
    }
    /// “实际 $1.00 · 账号成本 $3.00 · 再点一下取消”.
    public static func selectionLine(_ line: ProfitBreakdown.Line) -> String {
        "实际 " + DisplayFormat.money(line.actual) + " · 账号成本 " + DisplayFormat.money(line.accountCost) + " · 再点一下取消"
    }
    /// “↑ 8.2% · 比昨天同时” when both profits are above zero, otherwise the difference in money; “比昨天同时 —” without one.
    public static func changeLine(current: Decimal?, previous: Decimal?, label: String) -> String {
        DisplayFormat.changeLine(DisplayFormat.profitChange(current: current, previous: previous), label: label)
    }
    /// The table's first column: 时段 by the hour, 日期 by the day (the design's heading).
    public static func periodColumnTitle(_ granularity: AnalyticsGranularity) -> String { granularity == .hour ? "时段" : "日期" }
    /// “10月16日 8:00 到 9:00，实际 $1.00，账号成本 无数据，利润 无数据”.
    public static func rowSpoken(_ line: ProfitBreakdown.Line) -> String {
        [("实际", line.actual), ("账号成本", line.accountCost), ("利润", line.profit)]
            .map { "，" + $0 + " " + DisplayFormat.spoken(DisplayFormat.money($1)) }
            .reduce(line.bucket.spokenLabel, +)
    }
}

extension AnalyticsBarSeries {
    /// 利润明细's bars: each bucket's profit, below zero for a loss, no dotted line, read as “利润”; empty by the breakdown's rule.
    public static func profit(range: AnalyticsRange, breakdown: ProfitBreakdown) -> AnalyticsBarSeries {
        AnalyticsBarSeries(range: range, values: breakdown.lines.map(\.profit), metricName: "利润", isEmpty: breakdown.isEmpty)
    }
}
