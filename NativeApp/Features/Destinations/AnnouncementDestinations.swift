import SwiftUI

/// 60: announcement routes and sheets. Each case is its own line; a later item replaces only its case (X40).
struct AnnouncementRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // .announcements：S6-16
        case .announcements(let segment): AnnouncementsView(status: AnnouncementSegments.status(route: segment))
        // .announcementDetail：S6-17
        case .announcementDetail(let id): AnnouncementDetailView(id: id)
        // .announcementReads：S6-19
        case .announcementReads: ComingSoonView(title: route.placeholderTitle)
        // 其他区域：RouteDestination 不会分派到这里
        default: ComingSoonView(title: route.placeholderTitle)
        }
    }
}

struct AnnouncementSheetDestination: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        // .announcementEdit：S6-18
        case .announcementEdit(let id): AnnouncementEditLoader(id: id)
        // 其他区域：SheetDestination 不会分派到这里
        default: ComingSoonSheet(title: sheet.placeholderTitle)
        }
    }
}
