import SwiftUI

/// 60: settings routes. Each case is its own line; a later item replaces only its case (X40).
struct SettingsRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .settings：S0-15 已定，阶段 1–6 不改
        case .settings(let focus): SettingsView(focus: focus)
        // .sessions：S6-01
        case .sessions: ComingSoonView(title: route.placeholderTitle)
        // .accessTokens：S6-02
        case .accessTokens: ComingSoonView(title: route.placeholderTitle)
        // .push：S6-24
        case .push: ComingSoonView(title: route.placeholderTitle)
        // .pushTarget：S6-24
        case .pushTarget: ComingSoonView(title: route.placeholderTitle)
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}
