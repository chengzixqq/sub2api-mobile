import SwiftUI
import UIKit
import Sub2Core

/// 60 §7.4 添加其他接收方式 (S6-25): Bark, ntfy or Webhook with their fields, sent once (R06) through the push page's source —
/// the site, or under `-ui-testing` the fixture store. Added: the receipt, the page reads its list and the sheet closes. A
/// secret stays in this form only and is forgotten as it is sent; the form is covered while the App is not active (60 §0.4,
/// S6D2b-10). Field problems show after the first 添加.
struct PushTargetSheet: View {
    let source: any PushSettingsSource
    /// Added, or perhaps added: the page reads its list again.
    let onChanged: @MainActor () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = PushTargetDraft()
    @State private var showsIssues = false
    @State private var failure: PushTargetFailure?
    /// The form when `failure` came back: an edit since hides it.
    @State private var failedDraft: PushTargetDraft?
    @State private var isSubmitting = false
    @State private var confirmingDiscard = false

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(PushEditCopy.targetSheetTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(isSubmitting || draft.hasInput)
        .pushPrivacyCover(isShown: scenePhase != .active, identifier: "push.add.privacyCover")
        .alert(PushEditCopy.discardTitle, isPresented: $confirmingDiscard) {
            Button(PushEditCopy.discardConfirm, role: .destructive) { dismiss() }
            Button(PushEditCopy.keepEditing, role: .cancel) {}
        }
    }

    private var form: some View {
        Form {
            if let text = formFailure {
                Section { PushFormFailureBanner(text: text, identifier: "push.add.error") }
            }
            Section {
                Picker(PushEditCopy.platformPicker, selection: $draft.platform) {
                    ForEach(PushTargetDraft.platforms, id: \.self) { Text(PushTargetDraft.title($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("push.add.platform")
            }
            Section {
                ForEach(PushTargetDraft.fields(for: draft.platform), id: \.self) { row($0) }
            }
            .id(draft.platform)
        }
        .disabled(isSubmitting)
        .redacted(reason: scenePhase == .active ? [] : .privacy)
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("push.add.sheet")
    }

    @ViewBuilder private func row(_ field: PushTargetField) -> some View {
        let platform = draft.platform
        PushEditField(label: PushTargetDraft.label(field, platform: platform), text: binding(field),
                      prompt: PushTargetDraft.placeholder(field, platform: platform), identifier: "push.add.\(field.rawValue)",
                      isSecure: field == .secret, keyboard: keyboard(field), error: fieldError(field),
                      errorIdentifier: "push.add.error.\(field.rawValue)") {
            notes(field)
        }
    }

    @ViewBuilder private func notes(_ field: PushTargetField) -> some View {
        if field == .endpoint, draft.usesInsecureHTTP {
            PushFieldNote(text: PushEditCopy.insecureHTTPNote, identifier: "push.add.httpNote")
        }
        if field == .secret, draft.platform == .webhook {
            PushFieldNote(text: PushEditCopy.webhookSignatureNote + "\n" + PushEditCopy.webhookTimestampNote, identifier: "push.add.signatureNote")
        }
        if field == .secret, draft.needsSecretAgain, draft.issues[.secret] != nil {
            Button(PushEditCopy.dropSecret) { draft.dropSecret() }
                .font(.subheadline).frame(minHeight: 44).buttonStyle(.borderless)
                .accessibilityIdentifier("push.add.dropSecret")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消", action: cancel).disabled(isSubmitting).accessibilityIdentifier("push.add.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSubmitting {
                ProgressView().accessibilityLabel(PushEditCopy.adding).accessibilityIdentifier("push.add.submitting")
            } else {
                Button(PushEditCopy.add) { Task { await submit() } }.accessibilityIdentifier("push.add.submit")
            }
        }
    }

    // MARK: - Derived

    private var shownFailure: PushTargetFailure? { draft == failedDraft ? failure : nil }
    private var formFailure: String? {
        switch shownFailure {
        case .form(let text)?, .unconfirmed(let text)?: text
        case .field?, .cancelled?, nil: nil
        }
    }
    private func fieldError(_ field: PushTargetField) -> String? {
        if case .field(let failed, let text)? = shownFailure, failed == field { return text }
        return showsIssues ? draft.issues[field] : nil
    }
    private func keyboard(_ field: PushTargetField) -> UIKeyboardType {
        switch field {
        case .endpoint: .URL
        case .token, .secret: .asciiCapable
        case .name: .default
        }
    }
    private func binding(_ field: PushTargetField) -> Binding<String> {
        switch (field, draft.platform) {
        case (.endpoint, .ntfy): $draft.ntfyEndpoint
        case (.endpoint, .webhook): $draft.webhookURL
        case (.endpoint, _): $draft.barkEndpoint
        case (.token, .ntfy): $draft.ntfyTopic
        case (.token, _): $draft.barkKey
        case (.secret, .webhook): $draft.webhookSecret
        case (.secret, _): $draft.ntfyAccessToken
        case (.name, _): $draft.name
        }
    }

    // MARK: - Actions

    private func cancel() {
        if draft.hasInput { confirmingDiscard = true } else { dismiss() }
    }

    /// Sent once; an answer of an older session is dropped.
    private func submit() async {
        showsIssues = true
        guard !isSubmitting, let session else { return }
        guard let registration = try? draft.registration(timezone: TimeZone.current.identifier) else { return }
        let generation = session.generation
        isSubmitting = true
        defer { isSubmitting = false }
        draft.didSubmit(registration)
        do {
            let (device, created) = try await source.registerPushDevice(registration)
            guard generation == model.sessionGeneration else { return }
            model.receipts.show(Receipt(text: PushEditCopy.addedReceipt(name: PushPresentation.targetName(device), created: created)))
            onChanged()
            dismiss()
        } catch {
            guard generation == model.sessionGeneration else { return }
            let outcome = PushTargetFailure.classify(error)
            if case .unconfirmed = outcome { onChanged() }
            failure = outcome == .cancelled ? nil : outcome
            failedDraft = draft
        }
    }
}

/// A form row of the two push sheets: the label above its input, then the field's problem (critical) and its notes.
struct PushEditField<Notes: View>: View {
    let label: String
    @Binding var text: String
    var prompt = ""
    let identifier: String
    var isSecure = false
    var keyboard: UIKeyboardType = .asciiCapable
    var capitalization: TextInputAutocapitalization = .never
    var error: String?
    let errorIdentifier: String
    @ViewBuilder var notes: Notes

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline).foregroundStyle(Palette.ink2).accessibilityHidden(true)
            Group {
                if isSecure {
                    SecureField(label, text: $text, prompt: Text(prompt))
                } else {
                    TextField(label, text: $text, prompt: Text(prompt)).keyboardType(keyboard)
                }
            }
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled()
            .privacySensitive()
            .frame(minHeight: 36)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
            if let error {
                Text(error).font(.footnote).foregroundStyle(Tone.critical.ink).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(errorIdentifier)
            }
            notes
        }
        .padding(.vertical, 4)
    }
}

extension PushEditField where Notes == EmptyView {
    init(label: String, text: Binding<String>, prompt: String = "", identifier: String, keyboard: UIKeyboardType = .asciiCapable,
         capitalization: TextInputAutocapitalization = .never, error: String?, errorIdentifier: String) {
        self.init(label: label, text: text, prompt: prompt, identifier: identifier, keyboard: keyboard, capitalization: capitalization,
                  error: error, errorIdentifier: errorIdentifier) { EmptyView() }
    }
}

/// A footnote under a push form field.
struct PushFieldNote: View {
    let text: String
    let identifier: String

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
}

/// A refusal or an unconfirmed result for the whole form, at its top.
struct PushFormFailureBanner: View {
    let text: String
    let identifier: String
    var tone: Tone = .critical

    var body: some View {
        StatusBanner(tone: tone, systemImage: tone == .critical ? "exclamationmark.triangle" : "questionmark.circle", title: text)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(text)
            .accessibilityIdentifier(identifier)
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
    }
}

extension View {
    /// S6D2b-10: the App switcher's snapshot is taken after the scene leaves `.active`, so an opaque cover then keeps
    /// addresses, keys and the private key out of it (and out of its cached image).
    func pushPrivacyCover(isShown: Bool, identifier: String) -> some View {
        overlay {
            if isShown {
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill").font(.title2).foregroundStyle(Palette.ink2).accessibilityHidden(true)
                    Text(PushEditCopy.privacyCover).font(.subheadline).foregroundStyle(Palette.ink2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.sheetBackground)
                .ignoresSafeArea()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(identifier)
            }
        }
    }
}
