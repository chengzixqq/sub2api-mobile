import SwiftUI
import Sub2Core

/// AppRoute → page, one line per area (X02). Each area maps its own cases in Features/Destinations/<区域>Destinations.swift,
/// so this file no longer changes. No `default`, so a new route has to be given an area.
struct RouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .alert: TodayRouteDestination(route: route)
        case .account, .accountScheduledTests: AccountRouteDestination(route: route)
        case .user, .userLedger, .userNew, .userEdit: UserRouteDestination(route: route)
        case .logs, .request: LogRouteDestination(route: route)
        case .analytics, .analyticsMore, .analyticsChart, .analyticsRank, .analyticsModel: AnalyticsRouteDestination(route: route)
        case .groups, .group, .groupBatch, .groupKeys, .groupSubscriptions: GroupRouteDestination(route: route)
        case .settings, .sessions, .accessTokens, .push, .pushTarget: SettingsRouteDestination(route: route)
        case .redeem: RedeemRouteDestination(route: route)
        case .proxies, .proxyDetail, .proxyFallbackAccounts: ProxyRouteDestination(route: route)
        case .announcements, .announcementDetail, .announcementReads: AnnouncementRouteDestination(route: route)
        case .searchResults: SearchRouteDestination(route: route)
        }
    }
}

/// AppSheet → sheet content, one line per area like `RouteDestination`.
struct SheetDestination: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .addSite: NavigationStack { LoginView() }
        case .accountNew, .accountTest: AccountSheetDestination(sheet: sheet)
        case .balanceKeypad: UserSheetDestination(sheet: sheet)
        case .groupEdit, .groupPick: GroupSheetDestination(sheet: sheet)
        case .redeemEdit, .redeemGenerate, .redeemReconcile, .redeemGrant: RedeemSheetDestination(sheet: sheet)
        case .proxyEdit: ProxySheetDestination(sheet: sheet)
        case .announcementEdit: AnnouncementSheetDestination(sheet: sheet)
        }
    }
}

/// A route whose page comes in a later version.
struct ComingSoonView: View {
    let title: String

    var body: some View {
        ContentUnavailableView("即将推出", systemImage: "hammer", description: Text("这个页面会在后续版本提供。"))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("route.placeholder")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// A sheet whose page comes in a later version; 关闭 dismisses the whole sheet.
struct ComingSoonSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ComingSoonView(title: title).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("sheet.close") }
            }
        }
    }
}

/// Reads a route's object by id before showing its page. A reply for an older session is dropped; a read the
/// background stopped is read again on return (D18).
struct LoadingDestination<Value: Sendable, Content: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var value: Value?
    @State private var failure: String?
    @State private var attempt = 0
    private let loadingText: String
    private let load: @MainActor (SessionContext) async throws -> Value
    private let content: (Value) -> Content

    init(loadingText: String, load: @escaping @MainActor (SessionContext) async throws -> Value, @ViewBuilder content: @escaping (Value) -> Content) {
        self.loadingText = loadingText; self.load = load; self.content = content
    }

    var body: some View {
        Group {
            if let value { content(value) }
            else if let failure { FailureView(message: failure) { retry() } }
            else { ProgressView(loadingText) }
        }
        .task(id: attempt) { await fetch() }
        .onChange(of: model.foregroundRevision) { _, _ in if value == nil { retry() } }
    }
    private func retry() { failure = nil; attempt += 1 }
    private func fetch() async {
        guard value == nil, let session else { return }
        do {
            let result = try await load(session)
            guard session.generation == model.sessionGeneration, !Task.isCancelled else { return }
            value = result
        } catch {
            guard session.generation == model.sessionGeneration, !(error is CancellationError), !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }
}
