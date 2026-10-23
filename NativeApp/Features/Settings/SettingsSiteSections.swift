import SwiftUI
import Sub2Core

/// 60 §3.3 伍: the saved sites (initial, name, sign-in badge of 00 §1.1, host in monospace, “当前”), each with ··· for deleting;
/// then 添加站点. A switch goes through the same function as the site menu and ends with its receipt; while it runs the row
/// shows progress and the other rows wait.
struct SettingsSiteRows: View {
    /// “站点与凭据” scrolls here (60 §3.1).
    static let anchorID = "settings.sites.anchor"
    let remove: (ServerProfile) -> Void
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var switchingID: UUID?

    init(remove: @escaping (ServerProfile) -> Void) { self.remove = remove }

    var body: some View {
        ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
            row(profile).id(index == 0 ? Self.anchorID : profile.id.uuidString)
        }
        Button { router.present(.addSite) } label: {
            Label("添加站点", systemImage: "plus").foregroundStyle(Palette.accent).frame(minHeight: 44)
        }
        .accessibilityIdentifier("settings.add")
    }

    private func row(_ profile: ServerProfile) -> some View {
        let isCurrent = profile.id == model.activeProfile?.id
        let isSwitching = switchingID == profile.id
        return HStack(spacing: 8) {
            Button { switchTo(profile) } label: {
                HStack(spacing: 12) {
                    Text(String(profile.name.prefix(1))).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
                        .frame(width: 32, height: 32).background(Palette.sunken, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(profile.name).font(.headline).foregroundStyle(Palette.ink1).lineLimit(1)
                            ToneBadge(text: AuthPresentation.siteBadge(profile.authentication), tone: .neutral)
                        }
                        Text(profile.baseURL.host() ?? profile.baseURL.absoluteString)
                            .font(.caption.monospaced()).foregroundStyle(Palette.ink2).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if isSwitching { ProgressView() } else if isCurrent { Text("当前").font(.subheadline).foregroundStyle(Palette.ink3) }
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isConnecting && !isSwitching)
            .accessibilityIdentifier("settings.site.\(profile.name)")
            .accessibilityValue(isCurrent ? "当前" : "")
            Menu {
                Button("删除站点和凭据", role: .destructive) { remove(profile) }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Palette.ink2).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .disabled(isSwitching)
            .accessibilityLabel("管理站点 \(profile.name)")
            .accessibilityIdentifier("settings.site.more.\(profile.name)")
        }
    }

    /// 00 §1.1: only another site switches; the receipt comes from AppModel.switchTo, which the site menu uses too.
    private func switchTo(_ profile: ServerProfile) {
        guard profile.id != model.activeProfile?.id, switchingID == nil, !model.isConnecting else { return }
        switchingID = profile.id
        let model = model
        Task {
            await model.switchTo(profile)
            switchingID = nil
        }
    }
}

/// 60 §3.3 陆: who is signed in and how (00 §1.1, §1.2, §1.9, §6.3), the session and token entries (pages of stage 6), the Web
/// admin and signing out.
struct SettingsCurrentSiteRows: View {
    let status: SettingsSiteStatus
    let logout: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    init(status: SettingsSiteStatus, logout: @escaping () -> Void) { self.status = status; self.logout = logout }

    var body: some View {
        if let profile = model.activeProfile {
            let site = model.siteSession
            SettingsValueRow(label: "身份", value: SettingsPresentation.identityLine(email: site?.identityEmail, role: site?.me.user?.role))
                .accessibilityIdentifier("settings.current.identity")
            SettingsValueRow(label: "认证方式", value: site?.authMethodLabel
                             ?? AuthPresentation.methodLabel(authMethod: nil, fallback: profile.authentication, accessTokenScope: nil))
                .accessibilityIdentifier("settings.current.auth")
            if let operatorNote = site?.operatorNote { note(operatorNote, id: "settings.current.operator") }
            SettingsValueRow(label: "站点版本", value: site?.me.server.version ?? DisplayFormat.missing)
                .accessibilityIdentifier("settings.current.version")
            if let zone = site?.serverTimeZone.settingsNote(device: .current, at: Date()) { note(zone, id: "settings.current.timezone") }
            if let hint = SettingsPresentation.sessionBindingHint(authMethod: site?.authMethod, bindingEnabled: site?.me.security.sessionBindingEnabled,
                                                                  nativeMode: status.bindingNativeMode) {
                note(hint, id: "settings.current.binding")
            }
            sessionsRow(profile: profile, site: site)
            if let site, SettingsPresentation.showsAccessTokens(site.me) {
                NavigationLink(value: AppRoute.accessTokens) { countLabel("管理访问令牌", count: status.tokenCount) }
                    .accessibilityIdentifier("settings.current.tokens")
            }
            Button { openURL(profile.baseURL) } label: {
                HStack {
                    Label("打开 Web 后台", systemImage: "safari").foregroundStyle(Palette.ink1)
                    Spacer(minLength: 8)
                    SettingsChevron()
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.current.web")
            Button(role: .destructive, action: logout) {
                Text("退出并清除凭据").foregroundStyle(Tone.critical.ink).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.logout")
        }
    }

    @ViewBuilder private func sessionsRow(profile: ServerProfile, site: SiteSession?) -> some View {
        switch SettingsPresentation.sessionsRow(authMethod: site?.authMethod, fallback: profile.authentication, sessionsSupported: status.sessionsSupported) {
        case .hidden: EmptyView()
        case .available:
            NavigationLink(value: AppRoute.sessions) { countLabel("登录设备", count: status.sessionCount) }
                .accessibilityIdentifier("settings.current.sessions")
        case .notApplicable:
            VStack(alignment: .leading, spacing: 2) {
                Text("登录设备").foregroundStyle(Palette.ink3)
                Text(SettingsPresentation.sessionsUnavailableSubtitle).font(.footnote).foregroundStyle(Palette.ink3)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.current.sessions")
        }
    }

    private func countLabel(_ title: String, count: Int?) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.ink1)
            Spacer(minLength: 8)
            if let count { Text(DisplayFormat.grouped(count)).monospacedDigit().foregroundStyle(Palette.ink2) }
        }
    }
    private func note(_ text: String, id: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Palette.ink2).accessibilityIdentifier(id)
    }
}

/// A label and its value on one row, read as one element.
struct SettingsValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(Palette.ink1)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(Palette.ink2).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
