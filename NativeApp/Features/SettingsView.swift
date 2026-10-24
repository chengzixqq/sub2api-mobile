import SwiftUI
import Sub2Core

/// 60 §3: one page behind “界面与模式” and “站点与凭据”; the latter scrolls to 站点 once. Sections are numbered over the ones
/// shown (60 §3.3), and the confirmations keep their existing wording.
struct SettingsView: View {
    let focus: SettingsFocus
    @Environment(AppModel.self) private var model
    @State private var status = SettingsSiteStatus()
    @State private var removeProfile: ServerProfile?
    @State private var confirmLogout = false
    @State private var editingThreshold = false
    @State private var scrolledToSites = false

    init(focus: SettingsFocus = .interface) { self.focus = focus }

    private var site: SiteSession? { model.siteSession }
    private var sections: [SettingsPresentation.NumberedSection] {
        SettingsPresentation.visibleSections(showsNotifications: site.map { SettingsPresentation.showsNotifications($0.me) } ?? false,
                                             hasCurrentSite: model.activeProfile != nil, hasPending: !model.allPendingMoneyWrites.isEmpty)
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let notice = model.pendingMoney.unreadableNotice {
                    Text(notice).font(.subheadline).foregroundStyle(Tone.critical.ink)
                        .accessibilityIdentifier("settings.pending.paused")
                }
                ForEach(sections) { numbered in
                    Section {
                        rows(numbered.section)
                    } header: {
                        NumberedSectionHeader(title: numbered.section.title, ordinal: numbered.ordinal)
                    } footer: {
                        if numbered.section == .pending && !model.pendingBalances.isEmpty {
                            Text("仍保存凭据的原身份可切换后打开对应用户，使用原操作编号重试。退出或删除凭据后的旧身份记录仅供 Web 核对；新增登录不能继承旧请求。")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .task { await scrollToSitesOnce(proxy) }
        }
        .navigationTitle(focus == .sites ? "站点与凭据" : "界面与模式")
        .navigationSubtitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.sessionGeneration) {
            guard let session = model.sessionContext else { return }
            await status.load(model: model, context: session)
        }
        .sheet(isPresented: $editingThreshold) { FaceIDThresholdSheet(gate: model.biometricGate) }
        .confirmationDialog("删除站点？", isPresented: Binding(get: { removeProfile != nil }, set: { if !$0 { removeProfile = nil } }), titleVisibility: .visible) {
            Button("删除站点和凭据", role: .destructive) { if let profile = removeProfile { removeProfile = nil; remove(profile) } }
        } message: {
            if let removeProfile { Text(SettingsPresentation.removeSiteMessage(name: removeProfile.name, authentication: removeProfile.authentication)) }
        }
        .confirmationDialog("退出当前站点？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出并清除凭据", role: .destructive) { Task { await model.logout() } }
        } message: { Text("\(model.activeProfile?.name ?? "")\n此设备上的登录凭据将被清除。") }
    }

    @ViewBuilder private func rows(_ section: SettingsPresentation.Section) -> some View {
        switch section {
        case .interface: SettingsInterfaceRows()
        case .appearance: SettingsAppearanceRows()
        case .security: SettingsSecurityRows { editingThreshold = true }
        case .notifications: SettingsNotificationRows()
        case .sites: SettingsSiteRows { removeProfile = $0 }
        case .currentSite: SettingsCurrentSiteRows(status: status) { confirmLogout = true }
        case .pending: SettingsPendingRows()
        case .about: aboutRows
        }
    }

    @ViewBuilder private var aboutRows: some View {
        LabeledValue(label: "应用", value: "Sub2 Mobile")
        LabeledValue(label: "版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
        Text("原生 iOS 管理客户端。应用更新通过重新构建并签名 IPA 完成。")
            .font(.footnote).foregroundStyle(.secondary)
    }

    /// 60 §3.1: “站点与凭据” opens on 站点, once; coming back from a pushed page keeps the position.
    private func scrollToSitesOnce(_ proxy: ScrollViewProxy) async {
        guard focus == .sites, !scrolledToSites else { return }
        scrolledToSites = true
        await Task.yield()
        // Centred: the list runs under the navigation bar, so `.top` would hide the section's header behind it.
        proxy.scrollTo(SettingsSiteRows.anchorID, anchor: .center)
    }

    /// Not tied to the page: the server steps of a deletion finish even after the page is gone (D19).
    private func remove(_ profile: ServerProfile) {
        let model = model
        Task { await model.remove(profile) }
    }
}
