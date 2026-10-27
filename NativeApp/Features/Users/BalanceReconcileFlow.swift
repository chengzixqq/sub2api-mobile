import SwiftUI
import Sub2Core

/// 30 §3.4 核对 for one page: the check of a balance record, its dialogs, “用同一编号重试” and “放弃这笔”. The user detail's
/// banner owns one; S3-08's “先核对” and S3-11's identity strip reuse it with `.balanceReconcileFlow(_:)`.
@MainActor @Observable
final class BalanceReconcileFlow {
    struct Dialog: Identifiable {
        enum Stage { case outcome(candidate: UserAdjustment?), confirmAbandon, reconfirm }
        let id = UUID()
        let record: PendingBalanceOperation
        /// The balance the page shows, for a set's Face ID amount (D26); nil when unknown.
        let balance: Decimal?
        let prompt: BalanceReconcilePrompt
        let stage: Stage
    }

    private(set) var busyIDs: Set<UUID> = []
    private(set) var dialog: Dialog?
    /// An alert opened from another alert's button waits for that one to leave.
    @ObservationIgnored private var followUp: Task<Void, Never>?
    private static let followUpDelay: Duration = .milliseconds(450)

    func isBusy(_ id: UUID) -> Bool { busyIDs.contains(id) }

    /// Only reads (00 §2.5.5): an exact match settles the record with its receipt, “still running” and a failed query are
    /// receipts, everything else asks the administrator.
    func reconcile(_ op: PendingBalanceOperation, model: AppModel, balance: Decimal?) async {
        guard busyIDs.insert(op.id).inserted else { return }
        defer { busyIDs.remove(op.id) }
        let generation = model.sessionGeneration
        do {
            let outcome = try await model.reconcileBalance(op)
            guard generation == model.sessionGeneration else { return }
            switch outcome {
            case .executed(let row):
                model.applyReconciled(row, for: op)
            case .stillRunning:
                model.receipts.show(Receipt(text: BalanceReconcilePresentation.stillRunningText, systemImage: "clock", tone: .caution))
            default:
                await ask(about: outcome, op: op, model: model, balance: balance, generation: generation)
            }
        } catch {
            guard generation == model.sessionGeneration, !(error is CancellationError) else { return }
            model.receipts.show(Receipt(text: BalanceReconcilePresentation.failedText, systemImage: "exclamationmark.triangle", tone: .critical))
        }
    }

    /// A button of the dialog; the alert closes on its own.
    func choose(_ kind: BalanceReconcilePrompt.Action.Kind, in shown: Dialog, model: AppModel) {
        dismiss(shown.id)
        switch (kind, shown.stage) {
        case (.cancel, _):
            return
        case (.abandon, .confirmAbandon):
            do { try model.abandon(shown.record) } catch { model.report(error) }
        case (.abandon, _):
            present(Dialog(record: shown.record, balance: shown.balance, prompt: BalanceReconcilePresentation.abandonPrompt, stage: .confirmAbandon),
                    afterAlert: true)
        case (.markExecuted, .outcome(let candidate?)):
            model.applyReconciled(candidate, for: shown.record)
        case (.retry, _), (.retryNotThis, _):
            Task { await retry(shown.record, balance: shown.balance, model: model) }
        default:
            return
        }
    }
    /// The alert left without a button (or after one): only the dialog it showed is cleared.
    func dismiss(_ id: UUID?) {
        if let id, dialog?.id == id { dialog = nil }
    }

    private func ask(about outcome: BalanceReconcileOutcome, op: PendingBalanceOperation, model: AppModel, balance: Decimal?, generation: UUID) async {
        let context = await model.retryContext(for: op)
        // Settled elsewhere while the sender was looked up.
        guard generation == model.sessionGeneration, model.pendingBalance(id: op.id) != nil else { return }
        let now = model.client?.serverClock.now() ?? Date()
        guard let prompt = BalanceReconcilePresentation.prompt(for: outcome, op: op, context: context, now: now,
                                                               timeZone: model.siteSession?.serverTimeZone.timeZone ?? .current) else { return }
        let candidate: UserAdjustment? = if case .candidate(let row) = outcome { row } else { nil }
        present(Dialog(record: op, balance: balance, prompt: prompt, stage: .outcome(candidate: candidate)), afterAlert: false)
    }
    private func retry(_ op: PendingBalanceOperation, balance: Decimal?, model: AppModel) async {
        guard busyIDs.insert(op.id).inserted else { return }
        defer { busyIDs.remove(op.id) }
        switch await model.retrySameNumber(op, currentBalance: balance) {
        case .gone, .notAuthorized, .stale:
            return
        case .refused(let text), .kept(let text):
            model.receipts.show(Receipt(text: text, systemImage: "exclamationmark.triangle", tone: .caution))
        case .notSaved(let text), .notExecuted(let text):
            model.receipts.show(Receipt(text: text, systemImage: "xmark.octagon", tone: .critical))
        case .executed(let outcome):
            model.applyRetried(outcome, for: op)
        case .reconfirm(let notice):
            present(Dialog(record: op, balance: balance, prompt: BalanceReconcilePresentation.reconfirmPrompt(notice: notice), stage: .reconfirm),
                    afterAlert: true)
        }
    }
    private func present(_ next: Dialog, afterAlert: Bool) {
        followUp?.cancel()
        guard afterAlert else { dialog = next; return }
        followUp = Task { [weak self] in
            try? await Task.sleep(for: Self.followUpDelay)
            guard !Task.isCancelled else { return }
            self?.dialog = next
        }
    }
}

extension View {
    /// The flow's dialogs over this page.
    func balanceReconcileFlow(_ flow: BalanceReconcileFlow) -> some View { modifier(BalanceReconcileDialogs(flow: flow)) }
}

private struct BalanceReconcileDialogs: ViewModifier {
    let flow: BalanceReconcileFlow
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        let shown = flow.dialog
        content.alert(shown?.prompt.title ?? "", isPresented: Binding(get: { flow.dialog != nil && flow.dialog?.id == shown?.id },
                                                                       set: { if !$0 { flow.dismiss(shown?.id) } }),
                      presenting: shown) { dialog in
            ForEach(dialog.prompt.actions) { action in
                Button(action.title, role: action.isCancel ? .cancel : action.isDestructive ? .destructive : nil) {
                    flow.choose(action.kind, in: dialog, model: model)
                }
                .disabled(!action.isEnabled)
            }
        } message: { dialog in
            Text(dialog.prompt.message)
        }
    }
}
