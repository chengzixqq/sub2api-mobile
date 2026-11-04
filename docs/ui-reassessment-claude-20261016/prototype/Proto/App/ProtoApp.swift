import SwiftUI

@main
struct ProtoApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("首页", systemImage: "house") {
                    NavigationStack {
                        List {
                            Text("原型构建链路验证")
                            Text("$1,234.50").monospacedDigit()
                        }
                        .navigationTitle("首页")
                    }
                }
                Tab("账号", systemImage: "server.rack") { Text("账号") }
                Tab(role: .search) { Text("搜索") }
            }
        }
    }
}
