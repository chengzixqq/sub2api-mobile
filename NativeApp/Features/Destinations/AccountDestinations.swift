import SwiftUI
import Sub2Core

/// 20: account routes and sheets. Each case is its own line; a later item replaces only its case (X40).
struct AccountRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .account：S2-08
        case .account(let id, _): AccountDestination(id: id)
        // .accountScheduledTests：S2-21
        case .accountScheduledTests: ComingSoonView(title: route.placeholderTitle)
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}

struct AccountSheetDestination: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        // .accountNew：S2-19
        case .accountNew: ComingSoonSheet(title: sheet.placeholderTitle)
        // .accountTest：S2-14
        case .accountTest: ComingSoonSheet(title: sheet.placeholderTitle)
        // 其他区域：SheetDestination 不会分派到这里
        default: ComingSoonSheet(title: sheet.placeholderTitle)
        }
    }
}

/// `.account(id:)` until 20 §2 rewrites the detail page; the fixture branch is the one the request logs used.
struct AccountDestination: View {
    @Environment(AppModel.self) private var model
    let id: Int

    var body: some View {
        LoadingDestination(loadingText: "正在读取账号…") { (session: SessionContext) async throws -> UpstreamAccount in
            if model.isUITesting { return UpstreamAccount(id: id, name: "演示账号", platform: "openai", type: "apikey") }
            return try await session.client.account(id: id)
        } content: { AccountDetailView(initial: $0) }
    }
}
