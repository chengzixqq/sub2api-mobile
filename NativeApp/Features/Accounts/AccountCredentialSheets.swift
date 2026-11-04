import SwiftUI
import Sub2Core

/// An open credential sheet: which one, the account's version it saves on, and the save flow (C-14).
struct AccountCredentialSheetRequest: Identifiable {
    enum Kind { case replaceKey, baseURL }
    let id = UUID()
    let kind: Kind
    let base: AccountEditBase
    let flow: AccountPatchFlow
}

extension View {
    /// 20 §6.3's 更换 API Key and Base URL sheets, hung on the detail page.
    func accountCredentialSheet(_ request: Binding<AccountCredentialSheetRequest?>) -> some View {
        sheet(item: request) { request in
            switch request.kind {
            case .replaceKey: AccountReplaceKeySheet(request: request)
            case .baseURL: AccountBaseURLSheet(request: request)
            }
        }
    }
}

/// 20 §6.3 / §6.4 更换 API Key: the key is pasted (PasteButton asks no permission) or typed into a secure field and lives only in
/// this sheet. The red button is the confirmation; with 高风险操作需要 Face ID on it verifies first (60 §3.4, a refused check sends
/// nothing), then saves through AccountPatchFlow (PATCH, or the PUT fallback). Success marks “本次已更换 Key” and shows “已更换
/// API Key” with 测试; nothing is undone. The flow's leftover states and questions show here.
struct AccountReplaceKeySheet: View {
    let request: AccountCredentialSheetRequest
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var base: AccountEditBase
    @State private var key = ""
    @State private var verifying = false

    init(request: AccountCredentialSheetRequest) {
        self.request = request
        _base = State(initialValue: request.base)
    }

    private var flow: AccountPatchFlow { request.flow }
    private var isBusy: Bool { verifying || flow.isSaving }
    private var canSubmit: Bool { !isBusy && !flow.locksForm && AccountKeySheetCopy.change(forKey: key) != nil }

    var body: some View {
        AccountCredentialSheetFrame(title: AccountKeySheetCopy.title, id: "account.cred.key.sheet", flow: flow, isBusy: isBusy) {
            AccountCredentialTarget(name: base.account.name)
            keyField
            Text(APIKeyPreview(key)?.text ?? APIKeyPreview.emptyText)
                .font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                .accessibilityIdentifier("account.cred.key.preview")
            if flow.phase != .idle, !flow.isSaving {
                AccountPatchStatusRow(flow: flow) { model.openAccountInWeb(base.account, using: openURL) }
            }
            AccountCredentialSubmit(title: AccountKeySheetCopy.submit, tint: Palette.critical, isBusy: isBusy, isEnabled: canSubmit,
                                    id: "account.cred.key.submit", action: submit)
            Text(AccountKeySheetCopy.footer(verifiesFaceID: model.biometricGate.needsVerification(.replaceCredential)))
                .font(.footnote).foregroundStyle(Palette.ink3).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account.cred.key.note")
        }
        .onChange(of: flow.savedRevision) { _, _ in
            key = ""
            dismiss()
        }
        .onChange(of: flow.reloadRevision) { _, _ in if let fresh = flow.reloadedBase { base = fresh } }
        .onDisappear { key = "" }
    }

    private var keyField: some View {
        let binding = $key
        return AccountCredentialField(label: AccountKeySheetCopy.fieldLabel) {
            SecureField("", text: $key, prompt: Text(AccountKeySheetCopy.placeholder))
                .font(.body.monospaced())
                .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(nil).privacySensitive()
                .disabled(isBusy || flow.locksForm)
                .accessibilityLabel(AccountKeySheetCopy.fieldLabel)
                .accessibilityIdentifier("account.cred.key.field")
            if key.isEmpty {
                // The paste may answer off the main thread; the key goes back to the field on it.
                PasteButton(payloadType: String.self) { @Sendable pasted in
                    guard let text = pasted.first else { return }
                    Task { @MainActor in binding.wrappedValue = text }
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .disabled(isBusy || flow.locksForm)
                .accessibilityIdentifier("account.cred.key.paste")
            }
        }
    }

    private func submit() {
        guard canSubmit, let change = AccountKeySheetCopy.change(forKey: key) else { return }
        let base = base, flow = flow, model = model, router = router
        verifying = true
        Task {
            let allowed = await model.biometricGate.authorize(.replaceCredential)
            verifying = false
            guard allowed else { return }
            await flow.save(change, base: base) { saved in
                let id = saved.account.id
                model.accountKeyMarks.record(saved.account, at: model.serverNow())
                return Receipt(text: AccountKeySheetCopy.receipt, action: ReceiptAction(title: AccountKeySheetCopy.test) { router.present(.accountTest(id: id)) })
            }
        }
    }
}

/// 20 §6.3 Base URL: an address, or empty for the official one (null; 对接上游 needs an address). 保存 Base URL / 改回官方地址 greys
/// while nothing changed or the address is wrong, saves at once through AccountPatchFlow, and the receipt offers 测试 (design
/// AeUrlSheet). No Face ID: it is not on 60 §3.4's list.
struct AccountBaseURLSheet: View {
    let request: AccountCredentialSheetRequest
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var base: AccountEditBase
    @State private var draft: AccountBaseURLDraft

    init(request: AccountCredentialSheetRequest) {
        self.request = request
        _base = State(initialValue: request.base)
        _draft = State(initialValue: AccountBaseURLDraft(account: request.base.account))
    }

    private var flow: AccountPatchFlow { request.flow }

    var body: some View {
        AccountCredentialSheetFrame(title: AccountBaseURLDraft.title, id: "account.cred.baseurl.sheet", flow: flow, isBusy: flow.isSaving) {
            AccountCredentialTarget(name: base.account.name)
            AccountCredentialField(label: AccountBaseURLDraft.title) {
                TextField("", text: $draft.text, prompt: Text(AccountBaseURLDraft.placeholder))
                    .font(.body.monospaced())
                    .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(flow.locksForm)
                    .accessibilityLabel(AccountBaseURLDraft.title)
                    .accessibilityIdentifier("account.cred.baseurl.field")
                if !draft.text.isEmpty {
                    Button(AccountBaseURLDraft.clear) { draft.text = "" }
                        .buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                        .disabled(flow.locksForm)
                        .accessibilityIdentifier("account.cred.baseurl.clear")
                }
            }
            Text(draft.note).font(.footnote).foregroundStyle(draft.error == nil ? Palette.ink2 : Tone.critical.ink)
                .accessibilityIdentifier("account.cred.baseurl.message")
            if flow.phase != .idle, !flow.isSaving {
                AccountPatchStatusRow(flow: flow) { model.openAccountInWeb(base.account, using: openURL) }
            }
            AccountCredentialSubmit(title: draft.submitTitle, tint: Palette.accentFill, isBusy: flow.isSaving,
                                    isEnabled: draft.canSubmit && !flow.locksForm, id: "account.cred.baseurl.submit", action: submit)
        }
        .onChange(of: flow.savedRevision) { _, _ in dismiss() }
        .onChange(of: flow.reloadRevision) { _, _ in
            guard let fresh = flow.reloadedBase else { return }
            base = fresh
            draft = AccountBaseURLDraft(account: fresh.account)
        }
    }

    private func submit() {
        guard !flow.isSaving, let change = draft.change else { return }
        let base = base, flow = flow, router = router, text = draft.receipt
        Task {
            await flow.save(change, base: base) { saved in
                let id = saved.account.id
                return Receipt(text: text, action: ReceiptAction(title: AccountKeySheetCopy.test) { router.present(.accountTest(id: id)) })
            }
        }
    }
}

/// Both sheets: 取消 on the left, the content on the sheet background, the flow's questions; no swipe-away while saving.
private struct AccountCredentialSheetFrame<Content: View>: View {
    let title: String
    let id: String
    let flow: AccountPatchFlow
    let isBusy: Bool
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(20)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(id)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.sheetBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isBusy).accessibilityIdentifier("sheet.close")
                }
            }
            .accountPatchPrompts(flow)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isBusy)
    }
}

/// Design `sheet-target`: the account's name and when the change takes effect.
private struct AccountCredentialTarget: View {
    let name: String

    var body: some View {
        Text(AccountKeySheetCopy.target(name: name))
            .font(.subheadline).foregroundStyle(Palette.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("account.cred.target")
    }
}

/// A labelled input on a surface, with its trailing button.
private struct AccountCredentialField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote).foregroundStyle(Palette.ink2).accessibilityHidden(true)
            HStack(spacing: 8) { content }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline))
        }
    }
}

/// The sheet's one button, spinning while it works; greyed for a read-only token (C-1).
private struct AccountCredentialSubmit: View {
    let title: String
    let tint: Color
    let isBusy: Bool
    let isEnabled: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView().tint(Palette.onAccent) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).tint(tint).controlSize(.large)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
        .readOnlyGate()
    }
}
