import SwiftUI
import Sub2Core

// 40 §2.3 the chart bodies: in 更多图表's list (`.card`) and alone on the chart page (`.full`, 40 §3.3). The twelve are split by
// topic: 计费 here (S4-14), 用量 in AnalyticsUsageBodies.swift (S4-17), 运行 in AnalyticsOpsBodies.swift (S4-18).

/// A body's size: a card in 更多图表 (the chart 112pt high, the table's latest six rows) or the chart page (170pt, every row).
enum BodySize: Hashable, Sendable {
    case card, full

    /// The money charts' height (计费明细, 利润明细).
    var chartHeight: CGFloat { self == .full ? 170 : 112 }
    /// The table's rows before “展开全部”; nil on the chart page.
    var rowLimit: Int? { self == .full ? nil : AnalyticsDetailTable.cardRowLimit }
    /// The spinner's height until the chart's first answer, close to the loaded body's.
    var loadingHeight: CGFloat { chartHeight + 200 }
}

// MARK: - 计费明细

/// 40 §2.3 计费明细: “实际 $1,284.50” (or the selected bar's “10月16日 8:00–9:00 · $229.00”) with the legend, 计费趋势's bars,
/// 账号成本 / 标准 / 利润, and the table newest on top with the selected bar's row highlighted. It reads the range's totals and trend
/// (shared with 计费趋势 through the session), never the comparison window (40 §3.6). Identifiers analytics.body.billing.*.
struct AnalyticsBillingBody: View {
    let size: BodySize
    @Environment(\.analyticsSession) private var session

    init(size: BodySize) { self.size = size }

    var body: some View {
        if let session { BillingBodyContent(session: session, size: size) }
    }

    /// The totals and the trend at once; a value the session already has is not read again unless `refresh`.
    static func load(_ session: AnalyticsSession, refresh: Bool) async {
        async let summary: Void = session.loadBillingSummary(refresh: refresh)
        async let trend: Void = session.loadBillingTrend(refresh: refresh)
        _ = await (summary, trend)
    }
}

private struct BillingBodyContent: View {
    let session: AnalyticsSession
    let size: BodySize
    @State private var selection = AnalyticsChartSelection()
    @State private var isExpanded = false

    var body: some View {
        let summary = session.state(.billingSummary, as: AnalyticsSummary.self)
        let trend = session.state(.billingTrend, as: DashboardTrendReply.self)
        let detail = AnalyticsBillingDetail(range: session.range, points: trend?.value?.points ?? [], summary: summary?.value)
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsBodyHead(detail.head(selected: selection.selected), id: "analytics.body.billing.head") { AnalyticsChartLegend() }
            // The trend is the body's state; the totals' failure is its own line and retries only them (S4D2b-03).
            AnalyticsCardStatusRow(summary, id: "analytics.body.billing.summary", timeZone: zone, retry: retrySummary)
            AnalyticsCardBody(trend, id: "analytics.body.billing", minHeight: size.loadingHeight, timeZone: zone, retry: retry) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    AnalyticsBarChart(series: detail.bars, selection: $selection, id: "analytics.body.billing.chart",
                                      chartTitle: AnalyticsChartKey.billing.title, height: size.chartHeight)
                    AnalyticsFigureRow(detail.figures, id: "analytics.body.billing")
                    AnalyticsDetailTableView(detail.table, highlighted: selection.selected, size: size, isExpanded: $isExpanded,
                                             id: "analytics.body.billing")
                }
            }
        }
        .analyticsCardLoading("body.billing", session: session) { [session] refresh in
            await AnalyticsBillingBody.load(session, refresh: refresh)
        }
        .onChange(of: session.scope) { _, _ in
            selection = AnalyticsChartSelection()
            isExpanded = false
        }
    }

    private var zone: TimeZone { session.timeZone.timeZone }
    private func retry() {
        let session = session
        Task { await AnalyticsBillingBody.load(session, refresh: true) }
    }
    private func retrySummary() {
        let session = session
        Task { await session.loadBillingSummary(refresh: true) }
    }
}

// MARK: - 利润明细

/// 40 §2.3 利润明细: “利润 $772.42” (or the selected bar's “10月16日 8:00–9:00 · 利润 $90.12”) with “实际扣费 − 账号成本”, the bars with a
/// loss below zero, 实际扣费 / 账号成本 / 利润 over the range, and the table newest on top; full size ends with 合计 and the note. All of
/// it is S4-13b's ProfitBreakdown over 计费趋势's reads and, on an old server, its segments. Identifiers analytics.body.profit.*.
struct AnalyticsProfitBody: View {
    let size: BodySize
    @Environment(\.analyticsSession) private var session

    init(size: BodySize) { self.size = size }

    var body: some View {
        if let session { ProfitBodyContent(session: session, size: size) }
    }

    /// The totals and the trend, then an old server's segments (none when the trend has its account costs).
    static func load(_ session: AnalyticsSession, refresh: Bool) async {
        await AnalyticsBillingBody.load(session, refresh: refresh)
        await session.loadProfitSegments()
    }
}

private struct ProfitBodyContent: View {
    let session: AnalyticsSession
    let size: BodySize
    @State private var selection = AnalyticsChartSelection()
    @State private var isExpanded = false

    var body: some View {
        let summary = session.state(.billingSummary, as: AnalyticsSummary.self)
        let trend = session.state(.billingTrend, as: DashboardTrendReply.self)
        let breakdown = session.profitBreakdown()
        let detail = breakdown.map { AnalyticsProfitDetail(range: session.range, breakdown: $0) }
        // Until the breakdown is ready the head shows the totals' profit.
        let head = detail?.head(selected: selection.selected) ?? AnalyticsProfitDetail.head(total: summary?.value?.profit, selected: nil)
        VStack(alignment: .leading, spacing: 12) {
            AnalyticsBodyHead(head, id: "analytics.body.profit.head") {
                Text(ProfitCardText.meta).font(.caption).foregroundStyle(Palette.ink3).lineLimit(1)
            }
            AnalyticsCardStatusRow(summary, id: "analytics.body.profit.summary", timeZone: zone, retry: retrySummary)
            AnalyticsCardBody(trend, id: "analytics.body.profit", minHeight: size.loadingHeight, timeZone: zone, retry: retry) { _ in
                if let breakdown, let detail {
                    content(breakdown, detail: detail)
                } else {
                    // An old server's segments still being read.
                    AnalyticsCardPlaceholder(height: size.loadingHeight, id: "analytics.body.profit.segments")
                }
            }
        }
        .analyticsCardLoading("body.profit", session: session) { [session] refresh in
            await AnalyticsProfitBody.load(session, refresh: refresh)
        }
        .onChange(of: session.scope) { _, _ in
            selection = AnalyticsChartSelection()
            isExpanded = false
        }
    }

    private func content(_ breakdown: ProfitBreakdown, detail: AnalyticsProfitDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // An old server's segments a 429 cut short: the countdown, then they are read again by themselves.
            AnalyticsCardStatusRow(session.state(.profitSegments, as: ProfitSegmentCosts.self), id: "analytics.body.profit.segments",
                                   timeZone: zone, retry: retrySegments)
            AnalyticsBarChart(series: .profit(range: session.range, breakdown: breakdown), selection: $selection,
                              id: "analytics.body.profit.chart", chartTitle: AnalyticsChartKey.profit.title, height: size.chartHeight,
                              emptyText: ProfitCardText.emptyText)
            AnalyticsFigureRow(detail.figures, id: "analytics.body.profit")
            AnalyticsDetailTableView(detail.table, highlighted: selection.selected, size: size, isExpanded: $isExpanded,
                                     id: "analytics.body.profit", emphasizesLastColumn: true)
            if size == .full {
                Text(detail.note).font(.subheadline).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("analytics.body.profit.note")
            }
        }
    }

    private var zone: TimeZone { session.timeZone.timeZone }
    private func retry() {
        let session = session
        Task { await AnalyticsProfitBody.load(session, refresh: true) }
    }
    /// New totals may change which segments are wanted.
    private func retrySummary() {
        let session = session
        Task {
            await session.loadBillingSummary(refresh: true)
            await session.loadProfitSegments()
        }
    }
    private func retrySegments() {
        let session = session
        Task { await session.loadProfitSegments() }
    }
}

// MARK: - 共用部件

/// A body's head line: the total or the selected bar on the left (one element, `id`), its legend on the right.
private struct AnalyticsBodyHead<Trailing: View>: View {
    private let text: String
    private let id: String
    private let trailing: Trailing

    init(_ text: String, id: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text; self.id = id; self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink1)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityIdentifier(id)
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// 40 §2.3 a body's table: the column heads (not read), then a row per bucket newest on top, the selected bar's on a sunken band and
/// read as selected; a card shows the latest six and “展开全部 N 小时 ⌄”, the chart page every row and 合计 when the table has one.
/// The second figure column (标准, 账号成本) is dimmed as in the design. Rows are not buttons; each reads as one line. Identifiers
/// `<id>.row.<bucket index>`, `<id>.row.total`, `<id>.expand`.
struct AnalyticsDetailTableView: View {
    private let table: AnalyticsDetailTable
    private let highlighted: Int?
    private let size: BodySize
    @Binding private var isExpanded: Bool
    private let id: String
    private let emphasizesLastColumn: Bool

    private static let headerHeight: CGFloat = 32
    private static let rowHeight: CGFloat = 40
    private static let totalHeight: CGFloat = 44
    private static let dimmedColumn = 1

    init(_ table: AnalyticsDetailTable, highlighted: Int?, size: BodySize, isExpanded: Binding<Bool>, id: String,
         emphasizesLastColumn: Bool = false) {
        self.table = table; self.highlighted = highlighted; self.size = size; _isExpanded = isExpanded; self.id = id
        self.emphasizesLastColumn = emphasizesLastColumn
    }

    var body: some View {
        VStack(spacing: 0) {
            columns(Text(table.periodTitle), cells: table.columns.map { Text($0) })
                .font(.caption.weight(.medium)).foregroundStyle(Palette.ink3)
                .frame(minHeight: Self.headerHeight)
                .accessibilityHidden(true)
            // The chart page can list a year of days.
            LazyVStack(spacing: 0) {
                ForEach(table.shownRows(limit: size.rowLimit, expanded: isExpanded)) { row in line(row) }
            }
            if size == .full, let total = table.total { totalLine(total) }
            if let title = table.expandTitle(limit: size.rowLimit, expanded: isExpanded) { expandButton(title) }
        }
    }

    private func line(_ row: AnalyticsDetailTable.Row) -> some View {
        let isSelected = row.bucketIndex != nil && row.bucketIndex == highlighted
        return VStack(spacing: 0) {
            Palette.hairline.frame(height: 1)
            columns(Text(row.period).foregroundStyle(Palette.ink1), cells: row.cells.indices.map { cell(row.cells[$0], column: $0) })
                .font(.subheadline).monospacedDigit()
                .frame(minHeight: Self.rowHeight)
                .background(isSelected ? Palette.sunken : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(id).row.\(row.id)")
    }

    private func cell(_ value: String, column: Int) -> Text {
        let isLast = column == table.columns.count - 1
        return Text(value)
            .fontWeight(emphasizesLastColumn && isLast ? .semibold : .regular)
            .foregroundStyle(column == Self.dimmedColumn ? Palette.ink2 : Palette.ink1)
    }

    private func totalLine(_ total: AnalyticsDetailTable.Row) -> some View {
        VStack(spacing: 0) {
            Palette.ruleStrong.frame(height: 1)
            columns(Text(total.period).fontWeight(.medium).foregroundStyle(Palette.ink2),
                    cells: total.cells.map { Text($0).fontWeight(.semibold).foregroundStyle(Palette.ink1) })
                .font(.subheadline).monospacedDigit()
                .frame(minHeight: Self.totalHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total.spokenLabel)
        .accessibilityIdentifier("\(id).row.\(total.id)")
    }

    private func expandButton(_ title: String) -> some View {
        VStack(spacing: 0) {
            Palette.hairline.frame(height: 1).accessibilityHidden(true)
            Button { isExpanded = true } label: {
                HStack(spacing: 4) {
                    Text(title).monospacedDigit()
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(id).expand")
        }
    }

    private func columns(_ period: Text, cells: [Text]) -> some View {
        HStack(spacing: 8) {
            period.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(cells.indices, id: \.self) { index in
                cells[index].lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 6)
    }
}
