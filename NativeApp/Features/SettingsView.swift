import SwiftUI
import Sub2Core

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var adding = false
    @State private var removeProfile: ServerProfile?
    @State private var confirmLogout = false
    var body: some View {
        List {
            Section("站点") {
                ForEach(model.profiles) { profile in
                    HStack {
                        Button { Task { await model.switchTo(profile) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(profile.name).font(.headline)
                                    Text(profile.baseURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.id == model.activeProfile?.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).frame(minHeight: 44).disabled(model.isConnecting)
                            .accessibilityIdentifier("settings.site.\(profile.name)")
                        Menu {
                            Button("删除站点和凭据", role: .destructive) { removeProfile = profile }
                        } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("管理站点 \(profile.name)")
                    }
                }
                Button { adding = true } label: { Label("添加站点", systemImage: "plus.circle") }.frame(minHeight: 44).accessibilityIdentifier("settings.add")
                if model.isConnecting { ProgressView("正在验证站点…") }
            }
            if let profile = model.activeProfile {
                Section("当前连接") {
                    LabeledValue(label: "认证方式", value: profile.authentication == .adminKey ? "Admin Key" : "邮箱和密码")
                    Button { openURL(profile.baseURL) } label: { Label("打开 Web 后台", systemImage: "safari") }.frame(minHeight: 44)
                    Button("退出并清除当前凭据", role: .destructive) { confirmLogout = true }.frame(minHeight: 44).accessibilityIdentifier("settings.logout")
                }
            }
            if !model.pendingBalances.isEmpty {
                Section("待确认余额请求") {
                    ForEach(model.pendingBalances) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(model.profileForRecord(serverID: item.serverID)?.name ?? "原站点") · 用户 #\(item.userID)")
                            Text("\(item.operation.rawValue) \(money(item.amount))").font(.caption)
                            Text(item.id.uuidString).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                            if let profile = model.profileForRecord(serverID: item.serverID) { Link("打开原站点核对", destination: profile.baseURL).frame(minHeight: 44) }
                        }
                    }
                    Text("仍保存凭据的原身份可切换后打开对应用户，使用原操作编号重试。退出或删除凭据后的旧身份记录仅供 Web 核对；新增登录不能继承旧请求。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("关于") {
                LabeledValue(label: "应用", value: "Sub2 Mobile")
                LabeledValue(label: "版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                Text("原生 iOS 管理客户端。应用更新通过重新构建并签名 IPA 完成。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .sheet(isPresented: $adding) { NavigationStack { LoginView() } }
        .confirmationDialog("删除站点？", isPresented: Binding(get: { removeProfile != nil }, set: { if !$0 { removeProfile = nil } }), titleVisibility: .visible) {
            Button("删除站点和凭据", role: .destructive) { if let profile = removeProfile { removeProfile = nil; Task { await model.remove(profile) } } }
        } message: { Text("\(removeProfile?.name ?? "")\n站点配置和本机凭据将被清除。旧身份的未决余额记录仍保留，之后仅可在 Web 后台核对。") }
        .confirmationDialog("退出当前站点？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出并清除凭据", role: .destructive) { Task { await model.logout() } }
        } message: { Text("\(model.activeProfile?.name ?? "")\n此设备上的登录凭据将被清除。") }
    }
}
