import SwiftUI
import Sub2Core

/// 30: user routes and sheets. Each case is its own line; a later item replaces only its case (X40).
struct UserRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .user：S3-05
        case .user(let id): UserDestination(id: id)
        // .userLedger：S3-04
        case .userLedger: ComingSoonView(title: route.placeholderTitle)
        // .userNew：S3-10
        case .userNew: ComingSoonView(title: route.placeholderTitle)
        // .userEdit：S3-11
        case .userEdit: ComingSoonView(title: route.placeholderTitle)
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}

struct UserSheetDestination: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        // .balanceKeypad：S3-02（临时）→ S3-08
        case .balanceKeypad(let userID, _): LegacyBalanceSheet(userID: userID)
        // 其他区域：SheetDestination 不会分派到这里
        default: ComingSoonSheet(title: sheet.placeholderTitle)
        }
    }
}

/// `.user(id:)` until 30 §2 rewrites the detail page.
struct UserDestination: View {
    @Environment(AppModel.self) private var model
    let id: Int

    var body: some View {
        LoadingDestination(loadingText: "正在读取用户…") { _ in try await model.user(id: id) } content: { UserDetailView(initial: $0) }
    }
}
