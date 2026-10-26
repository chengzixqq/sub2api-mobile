import SwiftUI

/// 60: the search result routes. Each case is its own line; a later item replaces only its case (X40).
struct SearchRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .searchResults：S6-21
        case .searchResults: ComingSoonView(title: route.placeholderTitle)
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}
