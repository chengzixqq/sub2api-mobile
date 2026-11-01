import SwiftUI

/// 50: group routes and sheets. Each case is its own line; a later item replaces only its case (X40).
struct GroupRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .groups：S5-04
        case .groups(let segment): GroupListView(segment: segment)
        // .group：S5-06
        case .group(let id): GroupDetailView(id: id)
        // .groupBatch：S5-09
        case .groupBatch: ComingSoonView(title: route.placeholderTitle)
        // .groupKeys：S5-12
        case .groupKeys: ComingSoonView(title: route.placeholderTitle)
        // .groupSubscriptions：S5-12
        case .groupSubscriptions: ComingSoonView(title: route.placeholderTitle)
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}

struct GroupSheetDestination: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        // .groupEdit：S5-04（临时接旧编辑器）→ S5-10
        case .groupEdit(let id): LegacyGroupEditSheet(id: id)
        // .groupPick：S5-08
        case .groupPick(let groupID): NavigationStack { GroupAccountPicker(mode: .submit(groupID: groupID)) }
        // 其他区域：SheetDestination 不会分派到这里
        default: ComingSoonSheet(title: sheet.placeholderTitle)
        }
    }
}
