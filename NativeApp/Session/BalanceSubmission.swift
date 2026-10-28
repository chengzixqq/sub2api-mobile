import Foundation
import Sub2Core

/// The keypad's first send of a new balance record (30 §3.4, R04, R05): Face ID by how far the balance moves (D26), then the
/// record confirmed now is saved before it goes out (00 §0 rule 4), through the only sender (S3D1-16). The action id is
/// saved as soon as a reply carries it; the result follows S3-06's table, so only an uncertain one keeps the record.
@MainActor
struct BalanceSubmission {
    struct Effects: Sendable {
        let authorize: @MainActor @Sendable (GatedAction) async -> Bool
        /// AppModel.persisted: saves the record and returns the only sendable form.
        let persist: @MainActor @Sendable (PendingBalanceOperation) throws -> PersistedMoneyWrite<PendingBalanceOperation>
        let remember: @MainActor @Sendable (PendingBalanceOperation) throws -> Void
        /// AppModel.updateBalance, the only sender (S3D1-16).
        let send: @MainActor @Sendable (PersistedMoneyWrite<PendingBalanceOperation>, @escaping KeyedWriteEventHandler) async throws -> WriteOutcome<AdminUser>
        let resolve: @MainActor @Sendable (PendingBalanceOperation) throws -> Void
        /// STORE_UNAVAILABLE: the same number waits until then.
        let holdRetry: @MainActor @Sendable (UUID, Date?) -> Void
        /// The session that opened the keypad is still the connected one.
        let isCurrent: @MainActor @Sendable () -> Bool
        let now: @MainActor @Sendable () -> Date
        let report: @MainActor @Sendable (any Error) -> Void
    }
    enum Outcome: Sendable {
        /// Face ID failed or was cancelled: nothing saved, nothing sent.
        case notAuthorized
        case notSaved(String)
        /// The record is settled; a replayed or recovered result may be stale.
        case executed(WriteOutcome<AdminUser>)
        /// The record is settled: refused before it ran.
        case notExecuted(String)
        /// Kept to be checked.
        case pending(String)
        /// KEY_CONFLICT: the record is kept; a new write is confirmed again under a new number (R04).
        case keyConflict(String)
        /// A security prompt cleared it: the record is settled and confirmed once more as it is (00 §2.6.2 step 4).
        case reconfirm(PendingBalanceOperation, notice: String)
        /// A newer session; the record was still settled when the server answered.
        case stale
    }

    let effects: Effects

    func run(_ record: PendingBalanceOperation, gated: GatedAction,
             progress: @escaping @MainActor @Sendable (BalanceWriteProgress) -> Void) async -> Outcome {
        guard await effects.authorize(gated) else { return .notAuthorized }
        guard effects.isCurrent() else { return .stale }
        // Face ID took a while: the grace and the fallback window start when the record is saved.
        let write: PersistedMoneyWrite<PendingBalanceOperation>
        do { write = try effects.persist(record.confirmed(at: effects.now())) } catch { return .notSaved(PendingMoneyKind.balance.unsavedMessage) }
        progress(.submitting)
        let result: Result<WriteOutcome<AdminUser>, any Error>
        do { result = .success(try await effects.send(write, eventHandler(for: write.record, progress: progress))) } catch { result = .failure(error) }
        return settle(write.record, result: result)
    }

    /// 30 §3.4 step 4: the action id is saved at once; a failed save leaves the request id to match by.
    private func eventHandler(for record: PendingBalanceOperation,
                              progress: @escaping @MainActor @Sendable (BalanceWriteProgress) -> Void) -> KeyedWriteEventHandler {
        let remember = effects.remember
        return { @MainActor event in
            if case .actionID(let actionID) = event { try? remember(record.with(actionID: actionID)) }
            else if let step = BalanceWriteProgress(event) { progress(step) }
        }
    }
    private func settle(_ record: PendingBalanceOperation, result: Result<WriteOutcome<AdminUser>, any Error>) -> Outcome {
        switch result {
        case .success(let outcome):
            do { try effects.resolve(record) } catch { effects.report(error) }
            return current(.executed(outcome))
        case .failure(let error):
            return settle(record, error: error)
        }
    }
    private func settle(_ record: PendingBalanceOperation, error: any Error) -> Outcome {
        if let failure = error as? KeyedWriteFailure, failure.disposition == .needsNewKey(.keyConflict) {
            return current(.keyConflict(BalanceReconciliation.keyConflictMessage))
        }
        if let refused = error as? APIError, refused.securityOutcome == .passed {
            return current(resolved(record) ? .reconfirm(record, notice: refused.localizedDescription) : .notExecuted(BalanceChangeCopy.unresolvedRejection))
        }
        switch BalanceReconciliation.balanceWriteOutcome(for: error, retrying: false) {
        case .executed(let user, let replayed):
            do { try effects.resolve(record) } catch { effects.report(error) }
            return current(.executed(WriteOutcome(value: user, replayed: replayed)))
        case .notExecuted(let message):
            return current(.notExecuted(resolved(record) ? message : BalanceChangeCopy.unresolvedRejection))
        case .pending(let message, let retryNotBefore):
            if let retryNotBefore { effects.holdRetry(record.id, retryNotBefore) }
            return current(.pending(message))
        }
    }
    private func resolved(_ record: PendingBalanceOperation) -> Bool {
        do { try effects.resolve(record); return true } catch { return false }
    }
    private func current(_ outcome: Outcome) -> Outcome { effects.isCurrent() ? outcome : .stale }
}
