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

struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }.tabItem { Label("概览", systemImage: "chart.bar.xaxis") }.accessibilityIdentifier("tab.dashboard")
            NavigationStack { AccountsView() }.tabItem { Label("账号", systemImage: "server.rack") }.accessibilityIdentifier("tab.accounts")
            NavigationStack { UsersView() }.tabItem { Label("用户", systemImage: "person.2") }.accessibilityIdentifier("tab.users")
            NavigationStack { ManagementView() }.tabItem { Label("管理", systemImage: "square.grid.2x2") }.accessibilityIdentifier("tab.management")
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "gearshape") }.accessibilityIdentifier("tab.settings")
        }
        .tint(.indigo)
    }
}

struct ManagementView: View {
    var body: some View {
        List {
            Section("排查与分析") {
                NavigationLink { RequestLogsView() } label: { Label("请求记录与错误日志", systemImage: "list.bullet.rectangle") }
                    .accessibilityIdentifier("management.logs")
                NavigationLink { AnalyticsView() } label: { Label("统计分析", systemImage: "chart.xyaxis.line") }
                    .accessibilityIdentifier("management.analytics")
            }
            Section("资源管理") {
                NavigationLink { GroupsView() } label: { Label("分组管理", systemImage: "folder.badge.gearshape") }
                    .accessibilityIdentifier("management.groups")
            }
        }.navigationTitle("管理")
    }
}
