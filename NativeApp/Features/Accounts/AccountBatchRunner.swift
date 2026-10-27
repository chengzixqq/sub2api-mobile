import Foundation
import Observation
import Sub2Core

/// The undo of a batch: a new intent under new keys, in the session the batch ran in (20 §8.4, S2D1-05).
struct AccountBatchUndo: Sendable, Equatable {
    let ids: [Int]
    /// The switch the undo sets, the batch's opposite.
    let enabled: Bool
    let names: [Int: String]
    let generation: UUID
}

/// 20 §8.3 “批量操作结果”: every account that did not go through, and the undo a partial failure's receipt had no room for.
struct AccountBatchResults: Identifiable, Sendable {
    struct Row: Identifiable, Sendable {
        let id: Int
        let title: String
        let reason: String
    }
    let id = UUID()
    let siteName: String
    let rows: [Row]
    let undo: AccountBatchUndo?
}

/// 20 §8.4–§8.5 on the account list: Face ID, then requests of 50 one after another, read back when a result is unknown, one
/// receipt, and the selection left or kept. The rules are AccountBatchPlan's; a result after the session changed is dropped.
@MainActor @Observable
final class AccountBatchRunner {
    /// nil when idle; otherwise the switch being set, so the dock spins that button.
    private(set) var running: Bool?
    /// A keyed request is being retried or waited for: the dock says “正在确认结果…”.
    private(set) var isConfirming = false
    var results: AccountBatchResults?
    var isRunning: Bool { running != nil }

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let list: AccountListModel

    init(model: AppModel, list: AccountListModel) { self.model = model; self.list = list }

    /// The selection in list order. A failed or cancelled Face ID sends nothing and keeps the selection.
    func run(enabled: Bool) async {
        let accounts = list.selectedAccounts
        guard !isRunning, !accounts.isEmpty, let session = model.accountWriteSession else { return }
        guard !session.isReadOnlyToken else { return showReadOnly() }
        running = enabled
        defer { running = nil; isConfirming = false }
        guard await model.biometricGate.authorize(.batch), isCurrent(session) else { return }
        let names = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let prior = Dictionary(accounts.map { ($0.id, $0.schedulable) }, uniquingKeysWith: { first, _ in first })
        guard let outcome = await execute(ids: accounts.map(\.id), enabled: enabled, session: session), !outcome.isUnsent else { return }
        let undoIDs = AccountBatchPlan.undoIDs(for: outcome, prior: prior)
        let undo = undoIDs.isEmpty ? nil : AccountBatchUndo(ids: undoIDs, enabled: !enabled, names: names, generation: session.generation)
        let receipt = report(outcome, isUndo: false, undo: undo, names: names)
        if receipt.keepsSelection { await list.reload() } else { list.endSelecting() }
    }

    /// Verified like any batch write (60 §3.4); its receipt offers no further undo.
    func undo(_ request: AccountBatchUndo) async {
        guard !isRunning, let session = model.accountWriteSession, session.generation == request.generation else { return }
        guard !session.isReadOnlyToken else { return showReadOnly() }
        running = request.enabled
        defer { running = nil; isConfirming = false }
        guard await model.biometricGate.authorize(.batch), isCurrent(session) else { return }
        guard let outcome = await execute(ids: request.ids, enabled: request.enabled, session: session), !outcome.isUnsent else { return }
        report(outcome, isUndo: true, undo: nil, names: request.names)
        await list.reload()
    }

    // MARK: - Sending

    /// One key per request, made now (R05). Nil when the session changed.
    private func execute(ids: [Int], enabled: Bool, session: AccountWriteSession) async -> AccountBatchOutcome? {
        let chunks = AccountBatchPlan.chunks(ids: ids, keyed: session.idempotentWrites)
        var results: [AccountBatchChunkResult] = []
        for chunk in chunks {
            guard isCurrent(session) else { return nil }
            guard let result = await send(chunk, enabled: enabled, session: session) else { break }
            results.append(result)
            guard AccountBatchPlan.continues(after: result, chunk: chunk, enabled: enabled) else { break }
        }
        guard isCurrent(session) else { return nil }
        return AccountBatchPlan.merge(chunks: chunks, results: results, enabled: enabled)
    }
    /// Nil when cancelled: this and later requests count as not sent.
    private func send(_ chunk: AccountBatchChunk, enabled: Bool, session: AccountWriteSession) async -> AccountBatchChunkResult? {
        isConfirming = false
        do {
            let outcome = try await model.setAccountsSchedulable(ids: chunk.ids, enabled: enabled, idempotencyKey: chunk.idempotencyKey,
                                                                 onEvent: { [weak self] event in await self?.note(event) }, generation: session.generation)
            return .replied(outcome.value)
        } catch {
            switch AccountBatchPlan.disposition(of: error) {
            case .cancelled: return nil
            case .refused(let reason): return .refused(reason: reason)
            case .unconfirmed: return .unconfirmed(readback: await readBack(chunk.ids))
            }
        }
    }
    /// 20 §8.5: the switches `runtime/batch` reads now; nil when that fails as well.
    private func readBack(_ ids: [Int]) async -> [Int: Bool]? {
        guard let runtime = try? await model.accountRuntime(ids: ids) else { return nil }
        return runtime.mapValues(\.schedulable)
    }
    private func note(_ event: KeyedWriteEvent) {
        switch event {
        case .confirming, .waitingForServer: isConfirming = true
        case .actionID: break
        }
    }
    private func isCurrent(_ session: AccountWriteSession) -> Bool { model.sessionGeneration == session.generation }

    // MARK: - Receipts

    @discardableResult
    private func report(_ outcome: AccountBatchOutcome, isUndo: Bool, undo: AccountBatchUndo?, names: [Int: String]) -> AccountBatchReceipt {
        let receipt = AccountBatchPlan.receipt(for: outcome, isUndo: isUndo, canUndo: undo != nil)
        let action: ReceiptAction?
        if receipt.offersDetails {
            let details = AccountBatchResults(siteName: model.activeProfile?.name ?? "", rows: outcome.failures.map { row in
                AccountBatchResults.Row(id: row.id, title: AccountBatchPlan.rowTitle(name: names[row.id], id: row.id), reason: row.failure.text)
            }, undo: undo)
            action = ReceiptAction(title: AccountBatchPlan.detailsAction) { [weak self] in self?.results = details }
        } else if receipt.offersUndo, let undo {
            action = .undo { [weak self] in Task { await self?.undo(undo) } }
        } else {
            action = nil
        }
        model.receipts.show(Receipt(text: receipt.text, systemImage: receipt.systemImage, tone: receipt.tone, action: action))
        return receipt
    }
    /// 00 §2.6.3: nothing is sent with a read-only token (the dock is greyed already).
    private func showReadOnly() {
        let copy = AccountActionCopy.readOnly
        model.receipts.show(Receipt(text: copy.text, systemImage: copy.systemImage, tone: copy.tone))
    }
}
