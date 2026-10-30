import SwiftUI
import Sub2Core

extension View {
    /// 20 §6.1 every 重新授权… entry (the 凭据 row, ⋯, the state card's button) sets `request`. A stopped account asks first (20 §6.4-1,
    /// design aeOpenReauth), before any link exists, so cancelling wastes nothing; `preserve_status` is never sent (U19).
    func accountReauthorize(_ request: Binding<UpstreamAccount?>, platformName: @escaping (UpstreamAccount) -> String,
                            onFinished: @escaping @MainActor (AccountReauthResult) -> Void, onMissing: @escaping @MainActor () -> Void,
                            onEditInWeb: @escaping @MainActor (UpstreamAccount) -> Void) -> some View {
        modifier(AccountReauthorizeEntry(request: request, platformName: platformName, onFinished: onFinished, onMissing: onMissing,
                                         onEditInWeb: onEditInWeb))
    }
}

extension AccountReauthResult {
    /// 20 §6.3 回执: 测试 opens the connection test, 启用调度 turns the switch on through AccountActions; nothing to undo.
    @MainActor func receipt(router: AppRouter, actions: AccountActions) -> Receipt {
        let account = account, followUp = receipt.followUp
        let action = switch followUp {
        case .test: ReceiptAction(title: followUp.title) { router.present(.accountTest(id: account.id)) }
        case .enableScheduling: ReceiptAction(title: followUp.title) { Task { await actions.setSchedulable(account, enabled: true) } }
        }
        return Receipt(text: receipt.text, systemImage: "key", action: action)
    }
}

private struct AccountReauthorizeEntry: ViewModifier {
    @Binding var request: UpstreamAccount?
    let platformName: (UpstreamAccount) -> String
    let onFinished: @MainActor (AccountReauthResult) -> Void
    let onMissing: @MainActor () -> Void
    let onEditInWeb: @MainActor (UpstreamAccount) -> Void
    @State private var confirming: UpstreamAccount?
    @State private var presented: UpstreamAccount?

    func body(content: Content) -> some View {
        let question = confirming.map { AccountReauthorizePresentation.inactiveConfirmation(name: $0.name, schedulable: $0.schedulable) }
        content
            .onChange(of: request?.id, initial: true) { _, _ in open() }
            .alert(Text(question?.title ?? ""), isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                   presenting: confirming) { account in
                Button(AccountReauthorizePresentation.continueTitle) { presented = account }
                Button("取消", role: .cancel) { request = nil }
            } message: { _ in
                Text(question?.message ?? "")
            }
            .sheet(item: $presented, onDismiss: { request = nil }) { account in
                AccountReauthorizeSheet(account: account, platformName: platformName(account), onFinished: onFinished, onMissing: onMissing,
                                        onEditInWeb: { onEditInWeb(account) })
            }
    }
    private func open() {
        guard let account = request, presented == nil, confirming == nil else { return }
        if AccountReauthorizePresentation.needsInactiveConfirmation(account) { confirming = account } else { presented = account }
    }
}

/// 20 §6.3–§6.5 重新授权 (design AeReauthSheet, tall): the account and its proxy, the three-step list (pasted, no listener: 20 §6.3),
/// then red 替换令牌 and what it does. The red button is the confirmation; with Face ID on it verifies first and a refused check sends
/// nothing. A failed save, an unknown result, an account the phone cannot authorize or another failure shows above the button.
/// While a link is made or the token saved the sheet cannot be swiped away.
struct AccountReauthorizeSheet: View {
    let account: UpstreamAccount
    let platformName: String
    let onFinished: @MainActor (AccountReauthResult) -> Void
    let onMissing: @MainActor () -> Void
    let onEditInWeb: @MainActor () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        AccountReauthorizeContent(app: model, account: account, platformName: platformName, onFinished: onFinished, onMissing: onMissing,
                                  onEditInWeb: onEditInWeb)
    }
}

private struct AccountReauthorizeContent: View {
    let app: AppModel
    let platformName: String
    let onFinished: @MainActor (AccountReauthResult) -> Void
    let onMissing: @MainActor () -> Void
    let onEditInWeb: @MainActor () -> Void
    /// Set when the account cannot be authorized here: no link is offered (S2D1-21).
    let unsupported: String?
    @Environment(\.dismiss) private var dismiss
    @State private var flow: OAuthFlowModel?
    @State private var reauthorizer: AccountReauthorizer

    init(app: AppModel, account: UpstreamAccount, platformName: String, onFinished: @escaping @MainActor (AccountReauthResult) -> Void,
         onMissing: @escaping @MainActor () -> Void, onEditInWeb: @escaping @MainActor () -> Void) {
        self.app = app; self.platformName = platformName; self.onFinished = onFinished; self.onMissing = onMissing; self.onEditInWeb = onEditInWeb
        let precheck = AccountReauthorizePresentation.precheck(account)
        let made = precheck == nil ? OAuthFlowModel.reauthorize(account, source: app) : nil
        unsupported = made == nil ? precheck ?? AccountOAuthErrorCopy.unsupportedText(nil) : nil
        _flow = State(initialValue: made)
        _reauthorizer = State(initialValue: AccountReauthorizer(account: account, source: app, gate: app.biometricGate))
    }

    private var account: UpstreamAccount { reauthorizer.account }
    private var isBusy: Bool { flow?.isBusy == true || reauthorizer.isBusy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    target
                    if let flow {
                        OAuthFlow(model: flow, platformName: platformName, proxyName: account.proxyID == nil ? nil : account.proxy?.name,
                                  listensForCallback: false, remedy: { remedy(for: $0, flow: flow) })
                        submitArea(flow)
                    } else if let unsupported {
                        ReauthNotice(tone: .critical, text: unsupported, id: "account.reauth.unsupported") { editInWebButton }
                    }
                }
                .padding(20)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("account.reauth.sheet")
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.sheetBackground)
            .navigationTitle(AccountReauthorizePresentation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isBusy).accessibilityIdentifier("account.reauth.cancel")
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isBusy)
        .onDisappear { reauthorizer.discard() }
    }

    private var target: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(account.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
            Text(AccountReauthorizePresentation.targetLine(proxyID: account.proxyID, proxyName: account.proxy?.name))
                .font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account.reauth.target")
    }

    /// The notice of the last attempt, 替换令牌 (grey until a link and a code are there), and the note under it (S2-15's sentence).
    private func submitArea(_ flow: OAuthFlowModel) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let instant = flow.now
            VStack(alignment: .leading, spacing: 12) {
                if let notice = reauthorizer.notice { noticeBlock(notice, flow: flow, at: instant) }
                AccountReauthorizeSubmit(isBusy: reauthorizer.isBusy, isEnabled: !isBusy && Self.isReady(flow.submission(at: instant))) {
                    submit(flow)
                }
                Text(AccountCredentialCopy.replaceTokenNote(account, switchedTo: flow.typeSwitchTarget,
                                                            verifiesWithFaceID: reauthorizer.verifiesWithFaceID, now: app.serverNow()))
                    .font(.footnote).foregroundStyle(Palette.ink3).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("account.reauth.note")
            }
        }
    }

    @ViewBuilder private func noticeBlock(_ notice: AccountReauthorizer.Notice, flow: OAuthFlowModel, at instant: ContinuousClock.Instant) -> some View {
        switch notice {
        case .persistFailed:
            ReauthNotice(tone: .critical, text: AccountReauthorizePresentation.persistFailedTitle, id: "account.reauth.persistFailed") {
                if reauthorizer.canRetry(at: instant) {
                    noticeButton(AccountOAuthErrorCopy.Remedy.retrySave.title, id: "account.reauth.retrySave") { retry(flow) }
                } else {
                    noticeButton(AccountOAuthErrorCopy.Remedy.reauthorize.title, id: "account.reauth.restart") { restart(flow) }
                }
            }
        case .unconfirmed:
            ReauthNotice(tone: .caution, text: AccountReauthorizePresentation.unconfirmedTitle, id: "account.reauth.unconfirmed") {
                noticeButton(AccountOAuthErrorCopy.Remedy.retry.title, id: "account.reauth.retry") { retry(flow) }
            }
        case .unsupported(let text):
            ReauthNotice(tone: .critical, text: text, id: "account.reauth.unsupported") { editInWebButton }
        case .failed(let text), .reconfirm(let text):
            ReauthNotice(tone: notice == .failed(text) ? .critical : .caution, text: text, id: "account.reauth.failure") { EmptyView() }
        }
    }
    private var editInWebButton: some View {
        noticeButton(AccountOAuthErrorCopy.Remedy.editInWeb.title, id: "account.reauth.editInWeb") { onEditInWeb() }
    }
    private func noticeButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.bordered).frame(minHeight: 44).disabled(isBusy).accessibilityIdentifier(id)
    }

    // MARK: Actions

    /// The list's remedies that are this sheet's: 重试 sends a new 替换令牌, 在 Web 中编辑 leaves for the Web.
    private func remedy(for remedy: AccountOAuthErrorCopy.Remedy, flow: OAuthFlowModel) -> (() -> Void)? {
        switch remedy {
        case .retry: return { submit(flow) }
        case .editInWeb: return { onEditInWeb() }
        case .reauthorize: return { restart(flow) }
        default: return nil
        }
    }
    private func submit(_ flow: OAuthFlowModel) {
        guard !isBusy, case .ready(let submission) = flow.submission(at: flow.now) else { return }
        let switched = flow.typeSwitchTarget, reauthorizer = reauthorizer
        flow.clearError()
        Task { handle(await reauthorizer.submit(submission, switchedTo: switched), flow: flow) }
    }
    private func retry(_ flow: OAuthFlowModel) {
        let reauthorizer = reauthorizer
        Task { handle(await reauthorizer.retry(), flow: flow) }
    }
    private func restart(_ flow: OAuthFlowModel) {
        reauthorizer.restart()
        flow.restart()
    }
    private func handle(_ outcome: AccountReauthOutcome, flow: OAuthFlowModel) {
        switch outcome {
        case .succeeded(let result):
            onFinished(result)
            dismiss()
        case .stepError(let copy): flow.show(copy)
        case .missing:
            onMissing()
            dismiss()
        case .notice, .cancelled: break
        }
    }
    private static func isReady(_ state: OAuthSubmissionState) -> Bool {
        if case .ready = state { return true }
        return false
    }
}

/// The red 替换令牌, spinning while it verifies and saves; greyed for a read-only token (C-1).
private struct AccountReauthorizeSubmit: View {
    let isBusy: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(AccountReauthorizePresentation.submit).opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView().tint(Palette.onAccent) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).tint(Palette.critical).controlSize(.large)
        .disabled(!isEnabled)
        .accessibilityLabel(AccountReauthorizePresentation.submit)
        .accessibilityIdentifier("account.reauth.submit")
        .readOnlyGate()
    }
}

/// A notice on its tone's wash: the text (its identifier) and the button that follows.
private struct ReauthNotice<Action: View>: View {
    let tone: Tone
    let text: String
    let id: String
    @ViewBuilder let action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: tone == .critical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill").accessibilityHidden(true)
                Text(text).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(id)
            }
            .foregroundStyle(tone.ink)
            action
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.wash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
