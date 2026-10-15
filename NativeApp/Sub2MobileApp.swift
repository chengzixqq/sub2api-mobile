import SwiftUI

@main
struct Sub2MobileApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.restore() }
        }
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
            } else {
                NavigationStack { LoginView() }
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }.tabItem { Label("概览", systemImage: "chart.bar.xaxis") }.accessibilityIdentifier("tab.dashboard")
            NavigationStack { AccountsView() }.tabItem { Label("账号", systemImage: "server.rack") }.accessibilityIdentifier("tab.accounts")
            NavigationStack { UsersView() }.tabItem { Label("用户", systemImage: "person.2") }.accessibilityIdentifier("tab.users")
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "gearshape") }.accessibilityIdentifier("tab.settings")
        }
        .tint(.indigo)
    }
}
