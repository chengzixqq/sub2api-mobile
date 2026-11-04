import SwiftUI

/// 40: the usage and error log routes. Each case is its own line; a later item replaces only its case (X40).
struct LogRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .logs：S4-05
        case .logs(let logs): LogsView(route: logs)
        // .request：S4-08
        case .request(let request): RequestDetailView(route: request)
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}
