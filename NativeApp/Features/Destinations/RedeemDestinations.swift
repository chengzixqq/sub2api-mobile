import SwiftUI

/// 60: redeem code routes and sheets. Each case is its own line; a later item replaces only its case (X40).
struct RedeemRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .redeem：S6-04
        case .redeem: RedeemCodesView(route: RedeemRouteState(route))
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}

struct RedeemSheetDestination: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        // .redeemEdit：S6-05
        case .redeemEdit(let id): RedeemEditLoader(id: id)
        // .redeemGenerate：S6-07
        case .redeemGenerate: ComingSoonSheet(title: sheet.placeholderTitle)
        // .redeemReconcile：S6-06
        case .redeemReconcile: ComingSoonSheet(title: sheet.placeholderTitle)
        // .redeemGrant：S6-09
        case .redeemGrant: ComingSoonSheet(title: sheet.placeholderTitle)
        // 其他区域：SheetDestination 不会分派到这里
        default: ComingSoonSheet(title: sheet.placeholderTitle)
        }
    }
}
