import SwiftUI

/// 60: proxy routes and sheets. Each case is its own line; a later item replaces only its case (X40).
struct ProxyRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .proxies：S6-11
        case .proxies: ComingSoonView(title: route.placeholderTitle)
        // .proxyDetail：S6-12
        case .proxyDetail: ComingSoonView(title: route.placeholderTitle)
        // .proxyFallbackAccounts：S6-13
        case .proxyFallbackAccounts: ComingSoonView(title: route.placeholderTitle)
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}

struct ProxySheetDestination: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        // .proxyEdit：S6-14
        case .proxyEdit: ComingSoonSheet(title: sheet.placeholderTitle)
        // 其他区域：SheetDestination 不会分派到这里
        default: ComingSoonSheet(title: sheet.placeholderTitle)
        }
    }
}
