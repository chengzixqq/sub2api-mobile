import SwiftUI

@main
struct Sub2MobileApp: App {
    @State private var model = AppModel()
    /// Read in the App, the phase covers all windows: one iPad window going to the background leaves the shared client
    /// running while another is still active.
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.restore() }
        }
        // The only scene-phase handler in the App (D18).
        .onChange(of: scenePhase) { _, phase in model.sceneDidChange(to: AppActivity(phase)) }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    /// The global compliance and step-up sheet lives in a window above every page sheet (00 §2.7.1).
    @State private var securityPresenter = SecurityPromptPresenter()
    var body: some View {
        @Bindable var model = model
        Group {
            if model.isRestoring || model.isSigningOut {
                ProgressView(model.isSigningOut ? "正在退出并清除凭据…" : "正在恢复连接…")
            } else if model.activeProfile != nil {
                MainTabs().environment(\.sessionContext, model.sessionContext).id(model.sessionGeneration)
                    .sheet(item: $model.loginPrompt) { prompt in NavigationStack { LoginView(prompt: prompt) } }
            } else {
                // A new prompt is a new page: its fields start from that site.
                NavigationStack { LoginView(prompt: model.loginPrompt) }.id(model.loginPrompt?.id)
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onChange(of: model.securityPrompts.active, initial: true) { _, prompt in securityPresenter.sync(prompt, model: model) }
    }
}

extension AppActivity {
    init(_ phase: ScenePhase) {
        switch phase {
        case .active: self = .active
        case .background: self = .background
        default: self = .inactive
        }
    }
}

/// 10 §0.7 (U14): four tabs, “概览 · 账号 · 用户 · 监控”, and the separate search tab, each with its own stack. Rebuilt with
/// every session, so a new site starts on 概览 with empty stacks (00 §1.1).
struct MainTabs: View {
    @State private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab(MainTab.today.title, systemImage: MainTab.today.systemImage, value: MainTab.today) { stack(.today) { DashboardView().siteTitleMenu() } }
            Tab(MainTab.accounts.title, systemImage: MainTab.accounts.systemImage, value: MainTab.accounts) { stack(.accounts) { AccountsView().siteTitleMenu() } }
            Tab(MainTab.users.title, systemImage: MainTab.users.systemImage, value: MainTab.users) { stack(.users) { UsersView() } }
            Tab(MainTab.monitor.title, systemImage: MainTab.monitor.systemImage, value: MainTab.monitor) { stack(.monitor) { MonitorView() } }
            Tab(MainTab.search.title, systemImage: MainTab.search.systemImage, value: MainTab.search, role: .search) {
                stack(.search) { SearchHomeView() }
            }
        }
        .tabViewSearchActivation(.automatic)
        .tint(Palette.accent)
        .sheet(item: $router.presentedSheet) { SheetDestination(sheet: $0) }
        .environment(router)
    }

    private func stack(_ tab: MainTab, @ViewBuilder root: () -> some View) -> some View {
        let content = root()
        return NavigationStack(path: Binding(get: { router.path(for: tab) }, set: { router.setPath($0, for: tab) })) {
            content.navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
        }
        .overlay(alignment: .bottom) { ReceiptOverlay() }
    }
}
