import SwiftUI
import Sub2Core

/// What the 凭据 rows and ⋯'s credential items do; the detail wires them (S2-17 replaces `reauthorize`).
struct AccountCredentialHandlers {
    let replaceKey: () -> Void
    let editBaseURL: () -> Void
    let refresh: () -> Void
    let reauthorize: () -> Void
    /// 在 Web 中编辑 / 在 Web 中更换凭据: S2-11's AppModel.openAccountInWeb, kept for a read-only token (it writes nothing).
    let openWeb: () -> Void
}

/// 20 §3.3 凭据 (design AeInlineCred), between 调度 and 代理. A key account: 🔒 API Key with 更换 and what the key needs, and the
/// Base URL with 修改 (in the Web for a multi-protocol platform, S2D1-22). A token account: the access token's badge and time
/// left, redrawn every minute on the site clock, then 刷新令牌 and 重新授权… (立即生效). Bedrock and Vertex: the stored secret and
/// 在 Web 中更换凭据 (U17). 更换 and 修改 grey until the page has read the account, like 编辑 (S2D1-06); 刷新令牌 needs no version.
struct AccountCredentialSection: View {
    let account: UpstreamAccount
    let kind: AccountCredentialKind
    /// “本次已更换 Key” (AccountKeyReplacementMarks), ServerClock time.
    let replacedAt: Date?
    let canEdit: Bool
    let needsRefresh: Bool
    let isRefreshing: Bool
    let timeZone: TimeZone
    let now: () -> Date
    let handlers: AccountCredentialHandlers
    @Environment(\.sessionContext) private var session

    var body: some View {
        AccountEditSectionBox(title: AccountCredentialPresentation.title, key: "cred", edit: nil, footnote: kind.footer, meta: meta) {
            switch kind {
            case .key(let baseURL): keyRows(baseURL)
            case .token: tokenRows
            case .webOnly: webOnlyRows
            }
        }
    }

    /// One “只读令牌” for the section's greyed entries (Bedrock and Vertex have none), or, for 更换 and 修改, “先刷新账号” when the
    /// version could not be read.
    private var meta: String? {
        if session?.isReadOnlyToken == true, kind != .webOnly { return ReadOnlyGate.caption }
        guard case .key = kind, needsRefresh else { return nil }
        return AccountEditCopy.needsRefresh
    }

    @ViewBuilder private func keyRows(_ baseURL: AccountCredentialKind.BaseURLEdit) -> some View {
        let key = AccountCredentialPresentation.keyRow(account, replacedAt: replacedAt, now: now(), timeZone: timeZone)
        AccountCredentialLine(label: AccountKeySheetCopy.fieldName, spoken: key.value, id: "account.cred.key") {
            AccountSecretValue(text: key.value)
        } trailing: {
            inlineButton("更换", label: "更换 API Key", id: "account.cred.key.replace", action: handlers.replaceKey)
        }
        if let hint = key.hint { hintLine(hint) }
        let url = AccountCredentialPresentation.baseURL(account)
        AccountCredentialLine(label: AccountBaseURLDraft.title, spoken: url.text, id: "account.cred.baseurl") {
            urlValue(url)
        } trailing: {
            if baseURL == .inWeb {
                Button("在 Web 中编辑", action: handlers.openWeb)
                    .font(.subheadline.weight(.semibold)).buttonStyle(.borderless).frame(minHeight: 44)
                    .accessibilityIdentifier("account.cred.baseurl.web")
            } else {
                inlineButton("修改", label: "修改 Base URL", id: "account.cred.baseurl.edit", action: handlers.editBaseURL)
            }
        }
    }

    @ViewBuilder private var tokenRows: some View {
        TimelineView(.everyMinute) { _ in tokenLine(AccountCredentialPresentation.tokenRow(account, now: now(), timeZone: timeZone)) }
        hairline
        AccountCredentialAction(title: AccountRefreshCopy.title, systemImage: "arrow.clockwise", id: "account.cred.refresh",
                                tag: AccountCredentialPresentation.immediate, isRunning: isRefreshing, action: handlers.refresh)
            .readOnlyGate(showsCaption: false)
        AccountCredentialAction(title: AccountDetailAction.reauthorize.title, systemImage: "key", id: "account.cred.reauthorize",
                                tag: AccountCredentialPresentation.immediate, action: handlers.reauthorize)
            .readOnlyGate(showsCaption: false)
    }

    @ViewBuilder private var webOnlyRows: some View {
        let value = AccountCredentialPresentation.storedSecret(account)
        AccountCredentialLine(label: AccountCredentialPresentation.title, spoken: value, id: "account.cred.secret") {
            AccountSecretValue(text: value)
        } trailing: {
            EmptyView()
        }
        hairline
        AccountCredentialAction(title: AccountDetailAction.webCredential.title, systemImage: "safari", id: "account.cred.web", action: handlers.openWeb)
    }

    private func inlineButton(_ title: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(!canEdit)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
            .readOnlyGate(showsCaption: false)
    }
    private func hintLine(_ hint: AccountKeyRow.Hint) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if hint.tone == .critical { Image(systemName: "xmark.octagon.fill").accessibilityHidden(true) }
            Text(hint.text)
        }
        .font(.footnote)
        .foregroundStyle(hint.tone.ink)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account.cred.key.hint")
    }
    @ViewBuilder private func urlValue(_ url: AccountBaseURLValue) -> some View {
        if case .custom(let text) = url {
            Text(text).font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.ink1).lineLimit(1).truncationMode(.middle)
        } else {
            Text(url.text).font(.subheadline).foregroundStyle(Palette.ink3)
        }
    }
    private func tokenLine(_ row: AccountTokenRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("访问令牌").font(.subheadline).foregroundStyle(Palette.ink2)
                if let note = row.note {
                    Text(note).font(.footnote).foregroundStyle(Palette.ink3).accessibilityIdentifier("account.cred.token.note")
                }
            }
            Spacer(minLength: 8)
            if let badge = row.badge {
                Text(badge.title).font(.caption.weight(.semibold)).foregroundStyle(badge.tone.ink)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(badge.tone.wash, in: Capsule())
                    .accessibilityIdentifier("account.cred.token.badge")
            }
            Text(row.text).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink1).multilineTextAlignment(.trailing)
                .accessibilityIdentifier("account.cred.token")
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }
    private var hairline: some View { Rectangle().fill(Palette.hairline).frame(height: 1) }
}

/// A credential row: the label and value read as one element (“无数据” for “—”), its button beside them.
private struct AccountCredentialLine<Value: View, Trailing: View>: View {
    let label: String
    let spoken: String
    let id: String
    @ViewBuilder let value: Value
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).font(.subheadline).foregroundStyle(Palette.ink2)
                Spacer(minLength: 8)
                value
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(DisplayFormat.spoken(spoken)))
            .accessibilityIdentifier(id)
            trailing
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
    }
}

/// 🔒 and what is stored; never the secret itself.
private struct AccountSecretValue: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            if text != DisplayFormat.missing {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(Palette.ink3).accessibilityHidden(true)
            }
            Text(text).font(.subheadline).monospacedDigit().foregroundStyle(text == DisplayFormat.missing ? Palette.ink3 : Palette.ink1)
        }
    }
}

/// Design AeAct: an action row in the section, with “立即生效” when it takes effect outside any sheet.
private struct AccountCredentialAction: View {
    let title: String
    let systemImage: String
    let id: String
    var tag: String?
    var isRunning = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Image(systemName: systemImage).opacity(isRunning ? 0 : 1)
                    if isRunning { ProgressView() }
                }
                .frame(width: 22)
                Text(title).font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                if let tag {
                    Text(tag).font(.caption).foregroundStyle(Palette.ink3)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Palette.sunken, in: Capsule())
                }
            }
            .foregroundStyle(Palette.accent)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityValue(Text(tag ?? ""))
        .accessibilityIdentifier(id)
    }
}

/// 20 §3.4 ⋯'s credential items, first in the menu: 更换 API Key… for a key account, 刷新令牌 for a token account (S2-17 adds
/// 重新授权…); none for Bedrock and Vertex, whose 在 Web 中编辑 follows anyway.
struct AccountCredentialMenuItems: View {
    let kind: AccountCredentialKind
    let isRefreshing: Bool
    let handlers: AccountCredentialHandlers

    var body: some View {
        ForEach(kind.menuActions) { action in
            Button(action.title, systemImage: action.systemImage) {
                switch action {
                case .replaceKey: handlers.replaceKey()
                case .refresh: handlers.refresh()
                }
            }
            .disabled(action == .refresh && isRefreshing)
            .readOnlyGate(showsCaption: false)
            .accessibilityIdentifier("account.detail.more.\(action.rawValue)")
        }
    }
}

extension AccountTokenRefresher {
    /// Refreshes through AppModel+Accounts and shows its receipts in the App's one ReceiptCenter.
    convenience init(model: AppModel, onChange: @escaping @MainActor (UpstreamAccount) -> Void, onMissing: (@MainActor (Int) -> Void)? = nil) {
        self.init(source: model, receipts: model.receipts, onChange: onChange, onMissing: onMissing)
    }
}
