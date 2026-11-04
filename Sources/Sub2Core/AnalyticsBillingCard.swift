import Foundation

/// 40 §1.4 计费趋势卡, row by row: the totals of `usage/stats` over the range and its filter, the comparison window's total for the
/// change line, and `dashboard/trend` for the bars, a selected bar showing its own bucket.
public struct AnalyticsBillingCard: Equatable, Sendable {
    /// The comparison window's `usage/stats`; a failure only hides the change line.
    public enum Comparison: Equatable, Sendable {
        case pending, failed, loaded(AnalyticsSummary)

        /// The change line divides two reads of the same moment, and a range up to now moves both windows on every refresh: a
        /// comparison whose last read failed hides the line (40 §1.3), its earlier value too, and so do totals left from before a
        /// failed refresh. `lastReadFailed`: the last answer was a failure and no read succeeded since. A read under way keeps the
        /// earlier value.
        public init(_ state: BlockState<AnalyticsSummary>?, lastReadFailed: Bool, totalsLastReadFailed: Bool) {
            if lastReadFailed || totalsLastReadFailed { self = .failed; return }
            switch state {
            case .failed?, .disabled?: self = .failed
            case .loaded(let value, _)?, .loading(let value?, _)?: self = .loaded(value)
            case .idle?, .loading(nil, _)?, nil: self = .pending
            }
        }
    }

    /// “实际扣费 · 近 7 天”, or the selected bucket's full name.
    public let headline: String
    /// The total actual charge, or the selected bucket's (“$0.00” without a row, “—” when its amount is missing).
    public let amount: String
    /// “↑ 8.1% · 比昨天同时”; nil while a bar is selected, without the totals, or while the comparison is pending or failed.
    public let changeLine: String?
    /// “标准 $302.10 · 请求 4,210 · 再点一下取消” while a bar is selected.
    public let selectionLine: String?
    public let bars: AnalyticsBarSeries
    public let accountCost: String
    public let standardCost: String
    public let profit: String
    public let requests: String
    public let tokens: String
    /// “—” without requests.
    public let averageDuration: String
    /// “全部 10 小时” / “全部 7 天”: the buckets the detail page lists.
    public let footTitle: String

    public init(range: AnalyticsRange, summary: AnalyticsSummary?, comparison: Comparison, points: [TrendPoint], selected: Int?) {
        let slots = range.slots(points, key: \.date)
        let pick = selected.flatMap { slots.indices.contains($0) ? slots[$0] : nil }
        headline = pick?.bucket.fullName ?? "实际扣费 · " + range.name
        if let pick {
            amount = pick.value.map { DisplayFormat.money($0.actualCost) } ?? DisplayFormat.money(0)
            selectionLine = "标准 " + DisplayFormat.money(pick.value?.cost ?? 0) + " · 请求 " + DisplayFormat.grouped(pick.value?.requests ?? 0)
                + " · 再点一下取消"
            changeLine = nil
        } else {
            amount = DisplayFormat.money(summary?.actualCost)
            selectionLine = nil
            changeLine = Self.changeLine(summary: summary, comparison: comparison, label: range.comparison.label)
        }
        bars = .billing(range: range, points: points)
        let figures = Self.figures(summary)
        accountCost = figures[0].value; standardCost = figures[1].value; profit = figures[2].value
        requests = DisplayFormat.grouped(summary?.requests)
        tokens = DisplayFormat.compact(summary?.tokens)
        averageDuration = (summary?.requests ?? 0) > 0 ? DisplayFormat.duration(summary?.averageDurationMs, style: .list) : DisplayFormat.missing
        footTitle = Self.footTitle(range)
    }

    /// 40 §1.6: the totals' 重试本项 reads the trend again too, so the trend's own line goes when it would offer the same retry under
    /// a totals line that has one (a failure, or 更新失败 over kept totals). A refusal (400 / 403) on either side keeps both lines.
    public static func showsTrendFailure(summaryFailed: Bool, summaryRetries: Bool, trendFailed: Bool, trendRetries: Bool) -> Bool {
        !(summaryFailed && summaryRetries && trendFailed && trendRetries)
    }

    /// “全部 10 小时” / “全部 7 天”, also 利润明细's foot (S4-13b).
    public static func footTitle(_ range: AnalyticsRange) -> String {
        "全部 \(range.buckets.count) " + (range.granularity == .hour ? "小时" : "天")
    }

    /// 账号成本 / 标准 / 利润 (keys accountCost / standardCost / profit); without `total_account_cost` the first and the last are “—”.
    public static func figures(_ summary: AnalyticsSummary?) -> [AnalyticsFigure] {
        [AnalyticsFigure("accountCost", label: "账号成本", value: DisplayFormat.money(summary?.accountCost)),
         AnalyticsFigure("standardCost", label: "标准", value: DisplayFormat.money(summary?.standardCost)),
         AnalyticsFigure("profit", label: "利润", value: DisplayFormat.money(summary?.profit))]
    }

    private static func changeLine(summary: AnalyticsSummary?, comparison: Comparison, label: String) -> String? {
        guard let summary, case .loaded(let previous) = comparison else { return nil }
        return DisplayFormat.changeLine(DisplayFormat.ratioChange(current: summary.actualCost, previous: previous.actualCost), label: label)
    }
}

extension AnalyticsBarSeries {
    /// Each bucket's `actual_cost` as its bar and `cost` (standard) as the dotted line, “实际扣费”: 0 for a bucket without a row, nil for
    /// a row whose actual charge is missing.
    public static func billing(range: AnalyticsRange, points: [TrendPoint]) -> AnalyticsBarSeries {
        let slots = range.slots(points, key: \.date)
        let values: [Decimal?] = slots.map { slot in
            guard let point = slot.value else { return 0 }
            return point.actualCost
        }
        return AnalyticsBarSeries(range: range, values: values, line: slots.map { $0.value?.cost ?? 0 }, metricName: "实际扣费")
    }
}
