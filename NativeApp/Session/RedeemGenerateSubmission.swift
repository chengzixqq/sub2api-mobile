import Foundation
import Sub2Core

/// The first send of a new batch (60 §10.4–§10.5, R04, R05): a balance batch passes Face ID by its total first, then the record
/// confirmed now is saved before it goes out (00 §0 rule 4) and the answer is classified by S6-03 alone (S6D1-09). Only an
/// answer that may have run keeps the record; a refusal a security prompt then cleared settles it and is confirmed again as
/// the same record (S6D1-08).
@MainActor
struct RedeemGenerateSubmission {
    struct Effects: Sendable {
        let authorize: @MainActor @Sendable (GatedAction) async -> Bool
        /// AppModel.persisted: saves the record and returns the only sendable form.
        let persist: @MainActor @Sendable (PendingRedeemBatch) throws -> PersistedMoneyWrite<PendingRedeemBatch>
        /// Checks the sender first (S6D1-07), then `POST admin/redeem-codes/generate` under the record's number.
        let send: @MainActor @Sendable (PersistedMoneyWrite<PendingRedeemBatch>, @escaping KeyedWriteEventHandler) async throws
            -> WriteOutcome<[AdminRedeemCode]>
        /// Masked codes of a stored replay, read again by id.
        let reveal: @MainActor @Sendable ([AdminRedeemCode]) async throws -> [AdminRedeemCode]
        let resolve: @MainActor @Sendable (PendingRedeemBatch) throws -> Void
        /// STORE_UNAVAILABLE: the same number waits until then.
        let hold: @MainActor @Sendable (UUID, Date?) -> Void
        /// RedeemCodesModel.noteExternalChange (C-34).
        let listChanged: @MainActor @Sendable () -> Void
        let report: @MainActor @Sendable (any Error) -> Void
        /// The session that opened the sheet is still the connected one.
        let isCurrent: @MainActor @Sendable () -> Bool
    }
    enum Outcome: Sendable, Equatable {
        /// Face ID failed or was cancelled: nothing saved, nothing sent.
        case notAuthorized
        case notSaved(String)
        /// The record is settled.
        case generated([AdminRedeemCode], replayed: Bool)
        /// Kept to be checked (60 §11): the same sheet shows the pending page.
        case pending
        /// The record is settled: nothing was generated; back to step 3 with the reason.
        case rejected(String)
        /// A security prompt cleared it: the record is settled and confirmed once more as it is (00 §2.6.2 step 4).
        case reconfirm(PendingRedeemBatch, notice: String)
        /// A newer session; the record was still settled as the server answered.
        case stale
    }

    let effects: Effects

    func run(_ batch: PendingRedeemBatch, progress: @escaping @MainActor @Sendable (BalanceWriteProgress) -> Void) async -> Outcome {
        if let total = batch.total {
            guard await effects.authorize(.redeemGeneration(total: total)) else { return .notAuthorized }
            guard effects.isCurrent() else { return .stale }
        }
        let write: PersistedMoneyWrite<PendingRedeemBatch>
        do { write = try effects.persist(batch) } catch { return .notSaved(PendingMoneyKind.redeemBatch.unsavedMessage) }
        progress(.submitting)
        let result: Result<WriteOutcome<[AdminRedeemCode]>, any Error>
        do {
            result = .success(try await effects.send(write) { @MainActor event in
                if let step = BalanceWriteProgress(event) { progress(step) }
            })
        } catch {
            result = .failure(error)
        }
        return await settle(write.record, result: result)
    }

    private func settle(_ record: PendingRedeemBatch, result: Result<WriteOutcome<[AdminRedeemCode]>, any Error>) async -> Outcome {
        switch RedeemGenerateResult.classify(result, batchID: record.id, retrying: false) {
        case .generated(let codes, let replayed, _, let needsRefetch):
            var shown = codes
            if needsRefetch {
                // Made, but not shown: the record stays, so a check finds them.
                do { shown = try await effects.reveal(codes) } catch { return current(.pending) }
            }
            settleRecord(record)
            effects.listChanged()
            return current(.generated(shown, replayed: replayed))
        case .unconfirmed(_, let retryNotBefore):
            if let retryNotBefore { effects.hold(record.id, retryNotBefore) }
            return current(.pending)
        case .rejected(let message, _):
            settleRecord(record)
            return current(.rejected(message))
        case .reconfirm(let notice):
            settleRecord(record)
            return current(.reconfirm(record, notice: notice))
        }
    }
    /// A record that cannot be dropped stays to be checked; the answer is still shown.
    private func settleRecord(_ record: PendingRedeemBatch) {
        do { try effects.resolve(record) } catch { effects.report(error) }
    }
    private func current(_ outcome: Outcome) -> Outcome { effects.isCurrent() ? outcome : .stale }
}
