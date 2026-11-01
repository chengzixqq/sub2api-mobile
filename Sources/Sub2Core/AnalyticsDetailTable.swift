import Foundation

/// 40 §2.3 / §3.3 the table under 计费明细 and 利润明细: one row per bucket of the range, newest on top; a card shows the latest six
/// and “展开全部 10 小时”, the chart page every bucket (and, for profit, the 合计 row). Cells are DisplayFormat's output, “—” when
/// missing; each row reads as one line.
public struct AnalyticsDetailTable: Equatable, Sendable {
    public struct Row: Identifiable, Equatable, Sendable {
        /// The bucket's index; nil for 合计.
        public let bucketIndex: Int?
        /// “8:00–9:00”, “16日 周五”, “合计”.
        public let period: String
        /// One per column.
        public let cells: [String]
        /// “10月16日 8:00 到 9:00，实际 $229.00，标准 $250.00，请求 1,234”; “—” reads 无数据.
        public let spokenLabel: String
        public var id: String { bucketIndex.map(String.init) ?? "total" }
    }

    /// A card's rows before “展开全部”.
    public static let cardRowLimit = 6

    /// 时段 by the hour, 日期 by the day (the design's heading).
    public let periodTitle: String
    public let columns: [String]
    public let rows: [Row]
    /// 利润明细's 合计; nil for 计费明细.
    public let total: Row?
    /// 小时 / 天, for “展开全部 N 小时”.
    public let unit: String

    init(granularity: AnalyticsGranularity, columns: [String], rows: [Row], total: Row? = nil) {
        periodTitle = ProfitCardText.periodColumnTitle(granularity)
        unit = granularity == .hour ? "小时" : "天"
        self.columns = columns; self.rows = rows; self.total = total
    }

    /// `limit` nil (the chart page) or unfolded: every row.
    public func shownRows(limit: Int?, expanded: Bool) -> [Row] {
        guard let limit, !expanded else { return rows }
        return Array(rows.prefix(max(0, limit)))
    }
    /// “展开全部 10 小时”, while rows are folded away.
    public func expandTitle(limit: Int?, expanded: Bool) -> String? {
        guard let limit, !expanded, rows.count > limit else { return nil }
        return "展开全部 \(rows.count) " + unit
    }

    /// “<spoken period>，<column> <value>，…”.
    static func spoken(_ period: String, columns: [String], cells: [String]) -> String {
        zip(columns, cells).map { "，" + $0 + " " + DisplayFormat.spoken($1) }.reduce(period, +)
    }
}

/// 40 §2.3 计费明细: the head line, the bars (计费趋势's), 账号成本 / 标准 / 利润 and the table 时段 / 实际 / 标准 / 请求, from the range's
/// `usage/stats` totals and `dashboard/trend`. A bucket without a row is 0; a row without `actual_cost` shows “—”.
public struct AnalyticsBillingDetail: Equatable, Sendable {
    public static let columns = ["实际", "标准", "请求"]

    public let table: AnalyticsDetailTable
    public let bars: AnalyticsBarSeries
    public let figures: [AnalyticsFigure]
    private let total: Decimal?
    /// The selected bucket's head, per bucket.
    private let picks: [String]

    public init(range: AnalyticsRange, points: [TrendPoint], summary: AnalyticsSummary?) {
        let slots = range.slots(points, key: \.date)
        let rows = slots.map { slot in
            let cells = [DisplayFormat.money(Self.actual(slot)), DisplayFormat.money(slot.value?.cost ?? 0),
                         DisplayFormat.grouped(slot.value?.requests ?? 0)]
            return AnalyticsDetailTable.Row(bucketIndex: slot.bucket.index, period: slot.bucket.shortName, cells: cells,
                                            spokenLabel: AnalyticsDetailTable.spoken(slot.bucket.spokenLabel, columns: Self.columns, cells: cells))
        }
        table = AnalyticsDetailTable(granularity: range.granularity, columns: Self.columns, rows: rows.reversed())
        bars = .billing(range: range, points: points)
        figures = AnalyticsBillingCard.figures(summary)
        total = summary?.actualCost
        picks = slots.map { $0.bucket.fullName + " · " + DisplayFormat.money(Self.actual($0)) }
    }

    /// “实际 $1,284.50”, or the selected bucket's “10月16日 8:00–9:00 · $229.00”; a selection past the buckets reads as none.
    public func head(selected: Int?) -> String {
        if let selected, picks.indices.contains(selected) { return picks[selected] }
        return "实际 " + DisplayFormat.money(total)
    }

    private static func actual(_ slot: AnalyticsSlot<TrendPoint>) -> Decimal? {
        guard let point = slot.value else { return 0 }
        return point.actualCost
    }
}

/// 40 §2.3 利润明细: the head line, 实际扣费 / 账号成本 / 利润 and the table 时段 / 实际 / 账号成本 / 利润 with its 合计 row and note,
/// all from S4-13b's ProfitBreakdown (split to cents, so the rows add up to 合计 unless a segment is missing).
public struct AnalyticsProfitDetail: Equatable, Sendable {
    public static let columns = ["实际", "账号成本", "利润"]
    /// The three figures over the totals, as 合计 has them.
    private static let figureNames = [(key: "actualCost", label: "实际扣费"), (key: "accountCost", label: "账号成本"), (key: "profit", label: "利润")]

    public let table: AnalyticsDetailTable
    public let figures: [AnalyticsFigure]
    /// “每小时的利润 = 这段的实际扣费 − 账号成本，逐段相加等于合计。”（按天“每天”）; once a segment is missing the rows no longer add
    /// up, so only the first half (S4D2b-09 ③).
    public let note: String
    /// 这个范围内没有扣费 (ProfitBreakdown's rule: a range of losses is not empty).
    public let isEmpty: Bool
    private let breakdown: ProfitBreakdown

    public init(range: AnalyticsRange, breakdown: ProfitBreakdown) {
        let rows = breakdown.lines.map { line in
            AnalyticsDetailTable.Row(bucketIndex: line.bucket.index, period: line.bucket.shortName,
                                     cells: [line.actual, line.accountCost, line.profit].map { DisplayFormat.money($0) },
                                     spokenLabel: ProfitCardText.rowSpoken(line))
        }
        let totals = [breakdown.totalActual, breakdown.totalAccountCost, breakdown.totalProfit].map { DisplayFormat.money($0) }
        let total = AnalyticsDetailTable.Row(bucketIndex: nil, period: "合计", cells: totals,
                                             spokenLabel: AnalyticsDetailTable.spoken("合计", columns: Self.columns, cells: totals))
        table = AnalyticsDetailTable(granularity: range.granularity, columns: Self.columns, rows: rows.reversed(), total: total)
        figures = zip(Self.figureNames, totals).map { name, value in AnalyticsFigure(name.key, label: name.label, value: value) }
        let each = range.granularity == .hour ? "每小时" : "每天"
        note = each + "的利润 = 这段的实际扣费 − 账号成本" + (breakdown.isReconciled ? "，逐段相加等于合计。" : "。")
        isEmpty = breakdown.isEmpty
        self.breakdown = breakdown
    }

    /// “利润 $772.42”, or the selected bucket's “10月16日 8:00–9:00 · 利润 $90.12” (“—” for a missing segment).
    public static func head(total: Decimal?, selected: ProfitBreakdown.Line?) -> String {
        guard let selected else { return "利润 " + DisplayFormat.money(total) }
        return selected.bucket.fullName + " · 利润 " + DisplayFormat.money(selected.profit)
    }
    /// A selection past the buckets reads as none.
    public func head(selected: Int?) -> String {
        Self.head(total: breakdown.totalProfit, selected: breakdown.line(at: selected))
    }
}
