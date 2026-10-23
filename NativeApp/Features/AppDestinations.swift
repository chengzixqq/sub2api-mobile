import SwiftUI
import Sub2Core

/// AppRoute → page. Pages not rewritten yet map to the existing page or to the placeholder; a later stage changes
/// only its line here. No `default`, so a new route has to be mapped.
struct RouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .logs(let logs): RequestLogsView(accountID: logs.account?.id, groupID: logs.group?.id, scope: logs.scope)
        case .analytics: AnalyticsView()
        case .groups: GroupsView()
        case .group(let id): GroupDestination(id: id)
        case .account(let id, _): AccountDestination(id: id)
        case .user(let id): UserDestination(id: id)
        case .settings: SettingsView()
        case .alert, .accountScheduledTests, .userLedger, .userNew, .userEdit, .analyticsMore, .analyticsChart, .analyticsRank,
             .analyticsModel, .request, .groupBatch, .groupKeys, .groupSubscriptions, .searchResults, .sessions, .accessTokens,
             .push, .pushTarget, .redeem, .proxies, .proxyDetail, .proxyFallbackAccounts, .announcements, .announcementDetail,
             .announcementReads:
            ComingSoonView(title: route.placeholderTitle)
        }
    }
}

/// AppSheet → sheet content.
struct SheetDestination: View {
    let sheet: AppSheet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch sheet {
        case .addSite: NavigationStack { LoginView() }
        case .accountNew, .accountTest, .balanceKeypad, .groupEdit, .groupPick, .redeemEdit, .redeemGenerate, .redeemReconcile,
             .redeemGrant, .proxyEdit, .announcementEdit:
            NavigationStack {
                ComingSoonView(title: sheet.placeholderTitle).toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("sheet.close") }
                }
            }
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

/// `.user(id:)` until 30 §2 rewrites the detail page.
struct UserDestination: View {
    @Environment(AppModel.self) private var model
    let id: Int

    var body: some View {
        LoadingDestination(loadingText: "正在读取用户…") { _ in try await model.user(id: id) } content: { UserDetailView(initial: $0) }
    }
}
