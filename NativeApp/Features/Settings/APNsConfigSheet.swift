import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Sub2Core

/// 60 §7.4 编辑站点 APNs 配置 (S6-25): the switch, Team ID, Key ID, the private key (a .p8 file or pasted), Topic and the
/// environment; only changed fields are sent, the key only when a new one was given. Saving checks step-up first (00 §2.6.1):
/// with the site's switch on and no grant the verification sheet comes up and a pass sends this save; with it off any sign-in
/// saves. A refusal after sending is never resent: STEP_UP_REQUIRED cleared by the sheet waits for 保存 again, a machine
/// credential or TOTP refusal reads admin/me so 编辑 greys, INVALID_APNS_CONFIG marks its field. The key leaves the form as
/// it is sent and is never shown back once recognized; the form is covered while the App is not active (60 §0.4, S6D2b-10).
struct APNsConfigSheet: View {
    /// The page's settings. Read again while the form is open (after a save without an answer, or back in the foreground),
    /// the form counts its changes from them.
    let config: PushAPNsConfig
    /// Saved (the server's settings) or perhaps saved (nil): the page shows them, or reads them again.
    let onChanged: @MainActor (PushAPNsConfig?) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft: APNsConfigDraft
    @State private var importing = false
    @State private var keyFileFailure: String?
    @State private var showsIssues = false
    @State private var failure: APNsConfigFailure?
    /// The form when `failure` came back: an edit since hides it.
    @State private var failedDraft: APNsConfigDraft?
    @State private var isSaving = false
    @State private var confirmingDiscard = false

    init(config: PushAPNsConfig, onChanged: @escaping @MainActor (PushAPNsConfig?) -> Void) {
        self.config = config
        self.onChanged = onChanged
        _draft = State(initialValue: APNsConfigDraft(config: config))
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(PushPresentation.apnsSectionTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(isSaving || draft.hasChanges)
        .onChange(of: config) { _, fresh in rebase(on: fresh) }
        .pushPrivacyCover(isShown: scenePhase != .active, identifier: "apns.privacyCover")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { importKey($0) }
        .alert(PushEditCopy.discardTitle, isPresented: $confirmingDiscard) {
            Button(PushEditCopy.discardConfirm, role: .destructive) { dismiss() }
            Button(PushEditCopy.keepEditing, role: .cancel) {}
        }
    }

    private var form: some View {
        Form {
            if let note = editability.note, !note.isEmpty {
                Section { PushFormFailureBanner(text: note, identifier: "apns.editNote", tone: .caution) }
            }
            if let shown = formFailure {
                Section { PushFormFailureBanner(text: shown.text, identifier: "apns.error", tone: shown.tone) }
            }
            Section {
                Toggle(PushEditCopy.enabledTitle, isOn: $draft.enabled)
                    .tint(Palette.accentFill).frame(minHeight: 44).accessibilityIdentifier("apns.enabled")
                errorLine(.enabled)
            }
            Section(PushEditCopy.credentialsTitle) {
                PushEditField(label: "Team ID", text: $draft.teamID, identifier: "apns.teamID", capitalization: .characters,
                              error: error(.teamID), errorIdentifier: "apns.error.teamID")
                PushEditField(label: "Key ID", text: $draft.keyID, identifier: "apns.keyID", capitalization: .characters,
                              error: error(.keyID), errorIdentifier: "apns.error.keyID")
            }
            privateKeySection
            Section(PushEditCopy.deliveryTitle) {
                PushEditField(label: "Topic", text: $draft.topic, prompt: PushEditCopy.topicPlaceholder, identifier: "apns.topic", keyboard: .URL,
                              error: error(.topic), errorIdentifier: "apns.error.topic")
                VStack(alignment: .leading, spacing: 6) {
                    Text("环境").font(.subheadline).foregroundStyle(Palette.ink2).accessibilityHidden(true)
                    Picker("环境", selection: $draft.environment) {
                        ForEach(PushAPNsEnvironment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("apns.environment")
                    errorLine(.environment)
                }
                .padding(.vertical, 4)
            }
        }
        .disabled(!editability.isAvailable || isSaving)
        .redacted(reason: scenePhase == .active ? [] : .privacy)
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("apns.sheet")
    }

    /// Import or paste while the site can store a key; a recognized key shows only as 已读取, with 清除.
    private var privateKeySection: some View {
        Section(PushEditCopy.privateKeyTitle) {
            LabeledValue(label: "状态", value: draft.privateKeyStatus)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("私钥状态").accessibilityValue(draft.privateKeyStatus)
                .accessibilityIdentifier("apns.keyStatus")
            Button(PushEditCopy.importKey) { keyFileFailure = nil; importing = true }
                .frame(minHeight: 44)
                .disabled(!draft.canEditPrivateKey)
                .accessibilityIdentifier("apns.importKey")
            if draft.acceptsPrivateKeyInput {
                PEMTextView(text: Binding(get: { draft.privateKey }, set: { draft.setPrivateKey($0) }), label: PushEditCopy.pasteKeyPlaceholder,
                            identifier: "apns.privateKey")
                    .frame(minHeight: 88)
                    .overlay(alignment: .topLeading) {
                        if draft.privateKey.isEmpty {
                            Text(PushEditCopy.pasteKeyPlaceholder).font(.footnote).foregroundStyle(Palette.ink3)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
            } else if draft.hasNewPrivateKey {
                Button(PushEditCopy.clearKey, role: .destructive) { draft.clearPrivateKey() }
                    .frame(minHeight: 44).accessibilityIdentifier("apns.clearKey")
            }
            if draft.needsPrivateKeyAgain, !draft.hasNewPrivateKey {
                Button(PushEditCopy.keepCurrentKey) { draft.keepCurrentPrivateKey() }
                    .frame(minHeight: 44).accessibilityIdentifier("apns.keepKey")
            }
            if !draft.canEditPrivateKey { PushFieldNote(text: PushPresentation.encryptionKeyMissing, identifier: "apns.keyNote") }
            if let keyFileFailure {
                Text(keyFileFailure).font(.footnote).foregroundStyle(Tone.critical.ink).accessibilityIdentifier("apns.keyFileError")
            }
            errorLine(.privateKey)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消", action: cancel).disabled(isSaving).accessibilityIdentifier("apns.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView().accessibilityLabel(PushEditCopy.saving).accessibilityIdentifier("apns.saving")
            } else {
                Button(PushEditCopy.save) { Task { await save() } }
                    .disabled(!editability.isAvailable || !draft.hasChanges)
                    .accessibilityIdentifier("apns.save")
            }
        }
    }

    @ViewBuilder private func errorLine(_ field: PushAPNsField) -> some View {
        if let text = error(field) {
            Text(text).font(.footnote).foregroundStyle(Tone.critical.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("apns.error.\(Self.identifier(field))")
        }
    }

    // MARK: - Derived

    /// Follows the session: a reload after a refusal, or a read-only mark, greys the form at once.
    private var editability: PushAPNsEditability {
        guard let session else { return .disabled("") }
        return PushPresentation.apnsEditability(isReadOnlyToken: session.isReadOnlyToken, security: session.site.me.security,
                                                authMethod: session.site.authMethod)
    }
    private var shownFailure: APNsConfigFailure? { draft == failedDraft ? failure : nil }
    private var formFailure: (text: String, tone: Tone)? {
        switch shownFailure {
        case .form(let text)?, .staleSecurity(let text)?: (text, .critical)
        case .reconfirm(let text)?, .unconfirmed(let text)?: (text, .caution)
        case .field?, .cancelled?, nil: nil
        }
    }
    private func error(_ field: PushAPNsField) -> String? {
        if case .field(let failed, let text)? = shownFailure, failed == field { return text }
        return showsIssues ? draft.issues[field] : nil
    }
    private static func identifier(_ field: PushAPNsField) -> String {
        switch field {
        case .enabled: "enabled"
        case .teamID: "teamID"
        case .keyID: "keyID"
        case .privateKey: "privateKey"
        case .topic: "topic"
        case .environment: "environment"
        }
    }

    // MARK: - Actions

    private func cancel() {
        if draft.hasChanges { confirmingDiscard = true } else { dismiss() }
    }

    /// isRead true only words the verification sheet: a pass before sending sends this save (00 §2.6.1). Sent once.
    private func save() async {
        showsIssues = true
        guard !isSaving, let session, editability.isAvailable, draft.hasChanges, draft.issues.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        switch await model.ensureStepUp(purpose: PushEditCopy.stepUpPurpose, isRead: true) {
        case .passed: break
        case .cancelled: return
        case .blocked(let text): show(.form(text)); return
        }
        guard session.generation == model.sessionGeneration else { return }
        let update = draft.update
        draft.didSubmit(update)
        do {
            let saved = try await model.updatePushConfig(update, in: session)
            guard session.generation == model.sessionGeneration else { return }
            model.receipts.show(Receipt(text: PushEditCopy.savedReceipt))
            onChanged(saved)
            dismiss()
        } catch {
            guard session.generation == model.sessionGeneration else { return }
            let outcome = APNsConfigFailure.classify(error)
            switch outcome {
            case .staleSecurity: try? await model.reloadSiteSession()
            case .unconfirmed: onChanged(nil)
            case .cancelled, .reconfirm, .field, .form: break
            }
            show(outcome)
        }
    }
    private func show(_ outcome: APNsConfigFailure) {
        failure = outcome == .cancelled ? nil : outcome
        failedDraft = draft
    }
    /// A failure on show stays on show.
    private func rebase(on fresh: PushAPNsConfig) {
        let showsFailure = draft == failedDraft
        draft = draft.rebased(on: fresh)
        if showsFailure { failedDraft = draft }
    }

    /// Any file may be picked (.p8 has no system type): read inside its security scope, small, and a PEM block, or refused.
    private func importKey(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else {
            keyFileFailure = PushEditCopy.keyFileUnreadable
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= APNsConfigDraft.maxPrivateKeyBytes, let data = try? Data(contentsOf: url), let key = APNsConfigDraft.privateKey(fromFile: data) else {
            keyFileFailure = PushEditCopy.keyFileUnreadable
            return
        }
        keyFileFailure = nil
        draft.setPrivateKey(key)
    }
}

/// The private key's editor: a UITextView without smart punctuation, autocorrection or spell checking, so a typed PEM keeps
/// its dashes (SwiftUI's TextEditor cannot turn smart dashes off).
private struct PEMTextView: UIViewRepresentable {
    @Binding var text: String
    let label: String
    let identifier: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.autocorrectionType = .no; view.spellCheckingType = .no; view.autocapitalizationType = .none
        view.smartDashesType = .no; view.smartQuotesType = .no; view.smartInsertDeleteType = .no
        view.keyboardType = .asciiCapable
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.accessibilityLabel = label
        view.accessibilityIdentifier = identifier
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        if view.text != text { view.text = text }
        view.isEditable = context.environment.isEnabled
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textViewDidChange(_ textView: UITextView) { text.wrappedValue = textView.text }
    }
}

extension AppModel {
    /// 60 §7.4 `PUT admin/push/config`, sent once (S6-22). Under `-ui-testing` the site's refusals come first, in the
    /// backend's order — a read-only token, then the step-up guard (switch, machine credential, TOTP, grant) — through the
    /// same interception as a real one; then DemoData.pushStore, which the push page reads too.
    func updatePushConfig(_ update: PushAPNsConfigUpdate, in session: SessionContext) async throws -> PushAPNsConfig {
        guard isUITesting else { return try await session.client.updatePushConfig(update) }
        if let refusal = await apnsFixtureRefusal() { throw refusal }
        return try await DemoData.pushStore.updateConfig(update)
    }

    private func apnsFixtureRefusal() async -> APIError? {
        let reason: String
        if siteSession?.isReadOnlyToken == true {
            reason = "ACCESS_TOKEN_READ_ONLY"
        } else {
            switch stepUpRequirement() {
            case .notRequired: return nil
            case .machineCredential: reason = "STEP_UP_ADMIN_API_KEY_FORBIDDEN"
            case .totpNotEnabled: reason = "STEP_UP_TOTP_NOT_ENABLED"
            case .verify: reason = "STEP_UP_REQUIRED"
            }
        }
        let refusal = APIError.server(status: 403, reason: reason)
        return refusal.withSecurityOutcome(await interceptSecurity(refusal, isRead: false, generation: sessionGeneration))
    }
}
