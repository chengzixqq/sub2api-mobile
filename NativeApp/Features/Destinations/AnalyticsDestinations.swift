import SwiftUI

/// 40: the analytics routes. Each case is its own line; a later item replaces only its case (X40).
struct AnalyticsRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .analytics：S4-13
        case .analytics(let range, let focus, let metric):
            AnalyticsView(route: AnalyticsView.Route(range: range, focus: focus, metric: metric))
        // .analyticsMore：S4-17
        case .analyticsMore: ComingSoonView(title: route.placeholderTitle)
        // .analyticsChart：S4-14
        case .analyticsChart(let chart):
            // 40 §3.1: the other charts have no way in; 更多图表 shows them.
            if chart.hasSinglePage { AnalyticsChartView(chart: chart) } else { ComingSoonView(title: chart.title) }
        // .analyticsRank：S4-15
        case .analyticsRank(let dimension): AnalyticsRankView(dimension: dimension)
        // .analyticsModel：S4-19
        case .analyticsModel: ComingSoonView(title: route.placeholderTitle)
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}
