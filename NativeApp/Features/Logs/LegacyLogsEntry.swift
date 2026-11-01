import SwiftUI

/// X20: the old group detail's “请求记录” and the old usage detail's account link push this by a view-destination link, so it
/// shows LogsView pushing its details the same way and keeping its own store. S4-20 deletes it after S5-06.
struct RequestLogsView: View {
    private let route: LogsRoute

    init(accountID: Int? = nil, groupID: Int? = nil, scope: LogScope = .usage) {
        route = LogsRoute(scope: scope, account: accountID.map { RouteObject(id: $0) }, group: groupID.map { RouteObject(id: $0) })
    }

    var body: some View { LogsView(route: route, pushesInPlace: true) }
}
