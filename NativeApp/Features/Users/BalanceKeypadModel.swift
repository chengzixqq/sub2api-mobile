import Foundation
import Observation
import Sub2Core

/// The keypad sheet's state (30 §3.3–§3.5): the draft, the confirmation on screen and the write in flight. The record is made
/// when the confirmation is accepted (R05) and sent by BalanceSubmission; only “稍后核对” cancels that task.
@MainActor @Observable
final class BalanceKeypadModel {
    struct Confirmation: Identifiable {
        let id = UUID()
        let content: BalanceConfirmation
        /// Set when a security prompt cleared the record: the same one is confirmed again (00 §2.6.2 step 4).
        let record: PendingBalanceOperation?
    }

    /// The user as read when the sheet opened; “全部余额” and the Face ID amount of a set are measured from its balance (D26).
    let user: AdminUser
    private(set) var draft: BalanceChangeDraft
    private(set) var confirmation: Confirmation?
    /// From the confirmation until the result, Face ID included.
    private(set) var isWorking = false
    /// Set once the record is saved: “稍后核对” is offered from then on.
    private(set) var progress: BalanceWriteProgress?
    private(set) var notice: String?
    /// The sheet closes.
    private(set) var isFinished = false
    /// “先核对” from the segment's question checked here: receipts show only under the sheet, so the next one closes it.
    private(set) var hasCheckedHere = false
    @ObservationIgnored private var sending: Task<Void, Never>?

    init(user: AdminUser, mode: BalanceKeypadMode) {
        self.user = user
        draft = BalanceChangeDraft(currentBalance: user.balance, direction: mode.direction)
    }

    var mode: BalanceKeypadMode { BalanceKeypadMode(draft.direction) }
    var isUserDisabled: Bool { user.status == "disabled" }

    func setMode(_ mode: BalanceKeypadMode) { update(draft.switching(to: mode.direction)) }
    /// The segment: switches, or returns R03's first question when a record of that direction awaits its check (shown by
    /// `.balanceKeypadEntry`), as entering the keypad would.
    func requestMode(_ mode: BalanceKeypadMode, model: AppModel) -> BalanceKeypadEntry? {
        guard mode != self.mode, !isWorking else { return nil }
        if case .sameDirection(let pending) = BalanceKeypadEntry.check(userID: user.id, mode: mode, model: model) {
            return BalanceKeypadEntry(userID: user.id, mode: mode, pending: pending)
        }
        setMode(mode)
        return nil
    }
    /// That question's “先核对”: S3-07's check, its dialogs over the keypad.
    func checkFirst(_ op: PendingBalanceOperation, flow: BalanceReconcileFlow, model: AppModel) async {
        hasCheckedHere = true
        await flow.reconcile(op, model: model, balance: user.balance)
    }
    /// A receipt appeared: after a check from here the keypad leaves so it can be read; a write in flight keeps it.
    func receiptShown() {
        if hasCheckedHere, !isWorking { isFinished = true }
    }
    func editAmount(_ text: String) { update(draft.editingAmount(text)) }
    func editNotes(_ text: String) { draft = draft.editingNotes(text) }
    func chooseAllBalance() { update(draft.choosingAllBalance()) }

    /// 00 §2.5.5: an unreadable balance file pauses new writes.
    func pausedMessage(model: AppModel) -> String? {
        guard case .paused(let message) = BalanceKeypadEntry.check(userID: user.id, mode: mode, model: model) else { return nil }
        return message
    }

    /// 30 §3.3 确认框; a same-direction record awaiting its check, also one that appeared while the keypad was open, adds
    /// R03's second confirmation.
    func submit(model: AppModel) {
        guard draft.canSubmit, !isWorking, pausedMessage(model: model) == nil else { return }
        notice = nil
        confirmation = Confirmation(content: content(model: model), record: nil)
    }
    /// The confirmation left without its button.
    func dismissConfirmation(_ id: UUID) {
        if confirmation?.id == id { confirmation = nil }
    }
    /// Accepted: a new number now, or the cleared record again; then Face ID, the saved record and the send.
    func confirm(_ shown: Confirmation, model: AppModel) {
        dismissConfirmation(shown.id)
        guard !isWorking, let record = shown.record ?? newRecord(model: model) else { return }
        let gated = GatedAction.balanceAdjustment(record.operation, amount: record.amount, currentBalance: draft.currentBalance)
        let submission = BalanceSubmission(effects: model.balanceSubmissionEffects())
        isWorking = true
        sending = Task { [weak self] in
            let outcome = await submission.run(record, gated: gated) { [weak self] in self?.progress = $0 }
            self?.finish(outcome, record: record, model: model)
        }
    }
    /// “稍后核对”: the record stays to be checked (30 §3.5).
    func later() { sending?.cancel() }

    private func update(_ next: BalanceChangeDraft) {
        guard next != draft else { return }
        draft = next
        notice = nil
    }
    private func content(model: AppModel) -> BalanceConfirmation {
        let pending: PendingBalanceOperation? = if case .sameDirection(let op) = BalanceKeypadEntry.check(userID: user.id, mode: mode, model: model) {
            op
        } else {
            nil
        }
        let faceID = draft.biometricAmount.flatMap { model.biometricGate.amountConfirmationLine(amount: $0) }
        return BalanceConfirmation(draft: draft, userDisplayName: user.displayName, siteName: model.activeProfile?.name ?? "",
                                   userIsDisabled: isUserDisabled, faceIDLine: faceID, pendingSameDirection: pending)
    }
    private func newRecord(model: AppModel) -> PendingBalanceOperation? {
        guard let serverID = model.activeProfile?.id else { return nil }
        do {
            return try draft.pendingOperation(id: UUID(), serverID: serverID, userID: user.id, actorUserID: model.siteSession?.me.user?.id,
                                              createdAt: Date(), userDisplayName: user.displayName, userEmail: user.email)
        } catch {
            notice = error.localizedDescription
            return nil
        }
    }
    private func finish(_ outcome: BalanceSubmission.Outcome, record: PendingBalanceOperation, model: AppModel) {
        isWorking = false; progress = nil; sending = nil
        switch outcome {
        case .notAuthorized, .stale:
            return
        case .notSaved(let text), .notExecuted(let text), .keyConflict(let text):
            notice = text
        case .reconfirm(let again, let text):
            notice = text
            confirmation = Confirmation(content: content(model: model), record: again)
        case .pending(let text):
            model.receipts.show(Receipt(text: text, systemImage: "exclamationmark.triangle", tone: .caution))
            isFinished = true
        case .executed(let outcome):
            // 30 §3.4 result table, 200: the list and strip take the balance, the detail reads again (bumpBalance), the receipt.
            model.applyRetried(outcome, for: record)
            isFinished = true
        }
    }
}
