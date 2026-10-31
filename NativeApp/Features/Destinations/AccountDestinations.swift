import SwiftUI
import Sub2Core

/// 20: account routes and sheets. Each case is its own line; a later item replaces only its case (X40).
struct AccountRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .account：S2-08
        case .account(let id, let focus, let preload): AccountDetailScreen(id: id, focus: focus, preload: preload?.value)
        // .accountScheduledTests：S2-21
        case .accountScheduledTests(let accountID): AccountScheduledTestsView(accountID: accountID)
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
        case .accountNew: AccountNewView()
        // .accountTest：S2-14
        case .accountTest(let id): AccountTestSheet(accountID: id)
        // 其他区域：SheetDestination 不会分派到这里
        default: ComingSoonSheet(title: sheet.placeholderTitle)
        }
    }
}

/// The detail by id for pages that push it themselves (request logs, the group page's transitional account list): the
/// page reads the account and shows skeletons meanwhile (20 §2.5).
struct AccountDestination: View {
    let id: Int

    var body: some View { AccountDetailScreen(id: id) }
}
