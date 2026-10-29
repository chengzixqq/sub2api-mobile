import SwiftUI
import Sub2Core

/// 60 §9 编辑兑换码. The list opens it with the card it shows (9.6, no read); 取消 on the left, 保存 or 续期 on the right. While
/// saving the button spins, the form waits and the sheet cannot be swiped away (9.5). Saved or gone closes it; a 409 keeps it
/// open with notes only; a refusal or a lost reply stays on it, and the same save may be sent again.
struct RedeemEditSheet: View {
    let writes: RedeemCodeWrites
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    /// Taken once when the sheet opens, so a list refresh behind it never resets what is typed.
    @State private var draft: RedeemEditDraft
    @State private var isSaving = false
    @State private var notice: RedeemEditNotice?

    init(code: AdminRedeemCode, writes: RedeemCodeWrites) {
        self.writes = writes
        _draft = State(initialValue: RedeemEditDraft(code: code, now: Date()))
    }

    private var clock: Date { session?.client.serverClock.now() ?? Date() }

    var body: some View {
        NavigationStack {
            RedeemEditForm(draft: $draft, now: clock, serverZone: session?.site.serverTimeZone ?? .device,
                           groups: model.groupDirectory?.groups ?? [], notice: notice)
                .disabled(isSaving)
                .navigationTitle(draft.sheetTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(isSaving)
        .task(id: session?.generation) { await model.groupDirectory?.ensureLoaded() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
                .disabled(isSaving)
                .accessibilityIdentifier("redeem.edit.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView().accessibilityLabel("正在保存").accessibilityIdentifier("redeem.edit.saving")
            } else {
                Button(draft.saveTitle, action: save)
                    .disabled(!draft.canSave(now: clock))
                    .accessibilityIdentifier("redeem.edit.save")
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        let sent = draft
        isSaving = true
        notice = nil
        // Not tied to the view: the sheet cannot close while it runs.
        Task {
            let outcome = await writes.save(sent)
            isSaving = false
            switch outcome {
            case .saved, .gone: dismiss()
            case .switchedToNotesOnly:
                draft.switchToNotesOnly()
                notice = RedeemEditNotice(text: RedeemEditCopy.editUsed, tone: .caution)
            case .rejected(let text): notice = RedeemEditNotice(text: text, tone: .critical)
            case .unconfirmed: notice = RedeemEditNotice(text: RedeemEditCopy.saveUnconfirmed, tone: .caution)
            case .ignored: break
            }
        }
    }
}

/// `.redeemEdit(id:)` from a route: the code is read first (GET :id, without user and group); a failed read offers 重试, 取消
/// always closes. A save here makes the shown list read again.
struct RedeemEditLoader: View {
    let id: Int
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: (code: AdminRedeemCode, writes: RedeemCodeWrites)?
    @State private var failure: String?
    @State private var attempt = 0

    var body: some View {
        if let loaded {
            RedeemEditSheet(code: loaded.code, writes: loaded.writes)
        } else {
            NavigationStack { placeholder }
        }
    }

    private var placeholder: some View {
        Group {
            if let failure {
                FailureView(message: failure) { retry() }
                    .accessibilityElement(children: .contain).accessibilityIdentifier("redeem.edit.failure")
            } else {
                ProgressView(RedeemListText.loading).accessibilityIdentifier("redeem.edit.loading")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.sheetBackground)
        .navigationTitle("编辑兑换码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("redeem.edit.cancel") }
        }
        .task(id: attempt) { await load() }
    }

    private func retry() {
        failure = nil
        attempt += 1
    }

    private func load() async {
        guard loaded == nil, let session, session.generation == model.sessionGeneration else { return }
        do {
            let code = try await model.redeemCodesSource(for: session).code(id)
            guard session.generation == model.sessionGeneration, !Task.isCancelled else { return }
            loaded = (code, model.redeemCodeWrites(for: session))
        } catch {
            guard session.generation == model.sessionGeneration, !(error is CancellationError), !Task.isCancelled else { return }
            failure = RedeemWriteFailure.classify(error) == .gone ? RedeemEditCopy.gone : error.localizedDescription
        }
    }
}
