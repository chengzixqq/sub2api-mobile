import SwiftUI

/// 40: the usage and error log routes. Each case is its own line; a later item replaces only its case (X40).
struct LogRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .logs：S4-05
        case .logs(let logs): RequestLogsView(accountID: logs.account?.id, groupID: logs.group?.id, scope: logs.scope)
        // .request：S4-05（临时接旧详情）→ S4-08
        case .request: ComingSoonView(title: route.placeholderTitle)
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}
