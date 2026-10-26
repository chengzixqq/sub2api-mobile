import SwiftUI

/// C-2: what one delete confirmation shows and does (60 §0.4, design `confirmDelete`). `perform` is the caller's: it sends the
/// DELETE, treats 404 as already deleted, pops and shows `DeleteConfirmationCopy.deletedReceipt`, or shows its own failure;
/// the sheet closes when it returns. `expectedText` (the display name unless given; a redeem code passes the whole code with
/// `.suffix(4)`) must not be blank, or the button can never be pressed. Held only by views on the main actor.
struct DeleteRequest: Identifiable {
    typealias NameMatch = DeleteNameMatch.Rule
    let id = UUID()
    let objectNoun: String
    let displayName: String
    let siteLine: String
    let consequences: [String]
    let expectedText: String
    let match: NameMatch
    /// Only the field's placeholder; the label above it is always the component's.
    let inputPlaceholder: String?
    let perform: @MainActor () async -> Void

    /// `siteLine` defaults to “站点 <站点名> · 删除后不能恢复。”; chapters with their own first line pass it.
    init(objectNoun: String, displayName: String, siteName: String, siteLine: String? = nil, consequences: [String] = [],
         expectedText: String? = nil, match: NameMatch = .exact, inputPlaceholder: String? = nil,
         perform: @escaping @MainActor () async -> Void) {
        self.objectNoun = objectNoun
        self.displayName = displayName
        self.siteLine = siteLine ?? DeleteConfirmationCopy.siteLine(siteName: siteName)
        self.consequences = consequences
        self.expectedText = expectedText ?? displayName
        self.match = match
        self.inputPlaceholder = inputPlaceholder
        self.perform = perform
    }
}

extension View {
    /// The App's one delete confirmation. With 高风险操作需要 Face ID in force the only button is “用 Face ID 删除”, which
    /// verifies first; otherwise the name is typed (no autocapitalisation or autocorrection) before the red “删除<对象>” can be
    /// pressed. A failed or cancelled check deletes nothing and says nothing (60 §3.4). While deleting the button spins and the
    /// sheet cannot be swiped away.
    func confirmDelete(_ request: Binding<DeleteRequest?>) -> some View {
        modifier(DeleteConfirmationModifier(request: request))
    }
}

private struct DeleteConfirmationModifier: ViewModifier {
    @Binding var request: DeleteRequest?
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.sheet(item: $request) { request in
            DeleteConfirmationSheet(request: request, initialMode: model.biometricGate.deleteConfirmation)
        }
    }
}

struct DeleteConfirmationSheet: View {
    let request: DeleteRequest
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Taken once when the sheet opens, so a redraw behind it never swaps the field away.
    @State private var mode: DeleteConfirmation
    @State private var typed = ""
    @State private var isRunning = false
    @FocusState private var inputFocused: Bool

    init(request: DeleteRequest, initialMode: DeleteConfirmation) {
        self.request = request
        _mode = State(initialValue: initialMode)
    }

    private var canConfirm: Bool {
        !isRunning && (mode == .biometric || DeleteNameMatch.matches(input: typed, expected: request.expectedText, rule: request.match))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if mode == .typeName { nameField }
                buttons
            }
            .padding(20)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("delete.sheet")
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.sheetBackground)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isRunning)
        .onAppear { if mode == .typeName { inputFocused = true } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DeleteConfirmationCopy.title(objectNoun: request.objectNoun, displayName: request.displayName))
                .font(.headline).foregroundStyle(Palette.ink1)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("delete.title")
            Text(DeleteConfirmationCopy.message(siteLine: request.siteLine, consequences: request.consequences, confirmation: mode))
                .font(.subheadline).foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("delete.message")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameField: some View {
        let label = DeleteConfirmationCopy.inputLabel(expected: request.expectedText, rule: request.match)
        let placeholder = DeleteConfirmationCopy.inputPlaceholder(objectNoun: request.objectNoun, expected: request.expectedText,
                                                                  rule: request.match, custom: request.inputPlaceholder)
        return VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote).foregroundStyle(Palette.ink2).accessibilityHidden(true)
            TextField(placeholder, text: $typed)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(nil)
                .submitLabel(.done)
                .onSubmit { confirm() }
                .focused($inputFocused)
                .disabled(isRunning)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline))
                .accessibilityLabel(label)
                .accessibilityIdentifier("delete.input")
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(role: .destructive, action: confirm) {
                ZStack {
                    Text(DeleteConfirmationCopy.confirmTitle(objectNoun: request.objectNoun, confirmation: mode)).opacity(isRunning ? 0 : 1)
                    if isRunning { ProgressView().tint(Palette.onAccent) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Palette.critical).controlSize(.large)
            .disabled(!canConfirm)
            .accessibilityIdentifier("delete.confirm")
            Button(role: .cancel) { dismiss() } label: { Text("取消").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
                .disabled(isRunning)
                .accessibilityIdentifier("delete.cancel")
        }
    }

    /// The switch is read again here: if the lock screen code went away while the sheet was open, Face ID no longer guards the
    /// delete, so the name is asked for instead of deleting unchecked.
    private func confirm() {
        guard canConfirm else { return }
        let gate = model.biometricGate
        if mode == .biometric && gate.deleteConfirmation == .typeName {
            mode = .typeName
            inputFocused = true
            return
        }
        isRunning = true
        let reason = DeleteConfirmationCopy.biometricReason(objectNoun: request.objectNoun, displayName: request.displayName)
        let perform = request.perform
        // Not tied to the view: popping the page below must not cancel the DELETE.
        Task {
            guard await gate.authorize(.delete, reason: reason) else { isRunning = false; return }
            await perform()
            isRunning = false
            dismiss()
        }
    }
}
