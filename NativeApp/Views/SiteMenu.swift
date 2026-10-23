import SwiftUI
import Sub2Core

/// 10 §0.7-5, design `SiteMenu`: the saved sites (name, host underneath, the current one checked), then 添加站点… and
/// 站点与凭据. 概览 and 账号 share it through `siteTitleMenu()`. System menu items expose no identifiers; UI tests find
/// them by their text.
struct SiteMenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        ForEach(model.profiles) { profile in
            // A toggle draws the menu's leading check; turning the current site off does nothing.
            Toggle(isOn: Binding(get: { profile.id == model.activeProfile?.id }, set: { if $0 { switchTo(profile) } })) {
                Text(profile.name)
                Text(profile.baseURL.host() ?? profile.baseURL.absoluteString)
            }
        }
        .disabled(model.isConnecting)
        Divider()
        Button("添加站点…") { router.present(.addSite) }
        Button("站点与凭据") { router.push(.settings(focus: .sites)) }
    }

    /// 00 §1.1 through the same switch as the settings page; the new session's tabs start on 概览 with the receipt.
    private func switchTo(_ profile: ServerProfile) {
        guard profile.id != model.activeProfile?.id, !model.isConnecting else { return }
        Task { await model.switchTo(profile) }
    }
}

extension View {
    /// The navigation title becomes the site menu. On the iOS 27 simulator a large or inline-large title never opens a
    /// title menu, so the title is inline, where the system draws the menu's chevron; a device check is still due
    /// (BACKLOG). Only this function changes if the large title should come back.
    func siteTitleMenu() -> some View {
        toolbarTitleMenu { SiteMenuContent() }.toolbarTitleDisplayMode(.inline)
    }
}
