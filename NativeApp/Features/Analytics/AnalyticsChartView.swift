import SwiftUI
import Sub2Core

/// 40 §3 单图页 (`analyticsChart`): 计费明细 or 利润明细 alone, from the cards' feet. The title is the chart's name, the subtitle
/// “计费 · 今天”, the filter button on the right; the range bar (40 §1.2) over one full-size body (40 §2.3). The range and the filter
/// are the session's, so a change here is remembered and 统计分析 keeps it; the body reads through the same session, so what 统计分析
/// loaded shows at once, and pulling to refresh reads only this chart's requests (only its body registers, 40 §3.6). Identifier
/// analytics.chart.page.
struct AnalyticsChartView: View {
    let chart: AnalyticsChartKey

    var body: some View {
        AnalyticsSessionScope(entry: .last7) { session in
            AnalyticsChartPage(chart: chart, session: session)
        }
        .navigationTitle(chart.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AnalyticsChartPage: View {
    let chart: AnalyticsChartKey
    let session: AnalyticsSession
    @State private var sheet: AnalyticsSheet?
    @State private var loaders = AnalyticsCardLoaders()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AnalyticsRangeBar(session: session, sheet: $sheet)
                chartBody
                    .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(EdgeInsets(top: 4, leading: 16, bottom: 24, trailing: 16))
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("analytics.chart.page")
        .background(Palette.canvas)
        .navigationSubtitle(chart.pageSubtitle(rangeName: session.range.name))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AnalyticsFilterButton(session: session, sheet: $sheet) } }
        .analyticsSheets(session, sheet: $sheet)
        .analyticsPageRefresh(session, loaders: loaders)
    }

    /// Only 计费明细 and 利润明细 have a page (AnalyticsChartKey.hasSinglePage).
    @ViewBuilder private var chartBody: some View {
        switch chart {
        case .billing: AnalyticsBillingBody(size: .full)
        case .profit: AnalyticsProfitBody(size: .full)
        default: EmptyView()
        }
    }
}
