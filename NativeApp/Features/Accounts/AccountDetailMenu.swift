import SwiftUI
import Sub2Core

/// 20 §3.4 ⋯: the credential items first (S2-16's AccountCredentialMenuItems, with S2-17's 重新授权…), then “在 Web 中编辑”, and
/// “删除账号…” in red, always last. There is no “编辑账号”: each section edits itself. Opening the Web is not a server write, so
/// a read-only token keeps it.
struct AccountDetailMenu<Credentials: View>: View {
    let onOpenWeb: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let credentials: Credentials

    var body: some View {
        Menu {
            credentials
            Button("在 Web 中编辑", systemImage: "safari", action: onOpenWeb)
                .accessibilityIdentifier("account.detail.more.web")
            Button("删除账号…", systemImage: "trash", role: .destructive, action: onDelete)
                .readOnlyGate(showsCaption: false)
                .accessibilityIdentifier("account.detail.more.delete")
        } label: {
            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("更多")
        .accessibilityIdentifier("account.detail.more")
    }
}

extension DeleteRequest {
    /// 60 §0.4 / 20 §3.4: “删除账号「X」？”, “站点 X · 删除后不能恢复。”, the whole name typed unless Face ID guards it.
    static func account(_ account: UpstreamAccount, siteName: String, perform: @escaping @MainActor () async -> Void) -> DeleteRequest {
        DeleteRequest(objectNoun: AccountDeletionCopy.objectNoun, displayName: account.name, siteName: siteName, perform: perform)
    }
}
