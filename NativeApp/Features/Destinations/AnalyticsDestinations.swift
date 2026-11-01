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
        case .analyticsChart: ComingSoonView(title: route.placeholderTitle)
        // .analyticsRank：S4-15
        case .analyticsRank: ComingSoonView(title: route.placeholderTitle)
        // .analyticsModel：S4-19
        case .analyticsModel: ComingSoonView(title: route.placeholderTitle)
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}
