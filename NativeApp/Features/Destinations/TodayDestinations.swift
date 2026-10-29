import SwiftUI

/// 10: the 概览 and 监控 pages' routes. Each case is its own line; a later item replaces only its case (X40).
struct TodayRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .alert：S1-12
        case .alert(let id): AlertDetailView(id: id)
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}
