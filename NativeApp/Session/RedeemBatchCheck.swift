import Foundation
import Sub2Core

/// When each pending batch last went out in this run of the App: an old server's fallback window reaches past the record's
/// time when a retry may have run it (60 §11.4 末条). Keyed by record id, like MoneyWriteInFlight.
@MainActor
final class RedeemBatchSendLog {
    private var stamps: [UUID: Date] = [:]
    init() {}
    func note(_ id: UUID, at date: Date) { stamps[id] = date }
    func lastSent(_ id: UUID) -> Date? { stamps[id] }
}

/// 60 §11.4 for one pending batch: the check (only when tapped, 11.6), “用同一编号重试” and the closing by “放弃这一批” or
/// “我已核对”. Only a batch found whole under its batch_id is settled by the read itself (AppModel.reconcile); a count that
/// does not match and an old server's guess wait for the administrator. A retry reads the record again by id, only its
/// sender at this address sends it (D17, X34), a balance batch passes Face ID first, and the record is saved before it goes
/// out (00 §0 rule 4); its answer is classified by S6-03 alone (S6D1-09).
@MainActor
struct RedeemBatchCheck {
    struct Effects: Sendable {
        /// The saved record; nil once settled.
        let record: @MainActor @Sendable (UUID) -> PendingRedeemBatch?
        /// No `redeem_codes.stats` (U43): the batch_id query is not there.
        let isLegacyServer: @MainActor @Sendable () -> Bool
        /// AppModel.reconcile: a read with the current identity that settles a batch found whole.
        let reconcile: @MainActor @Sendable (PendingRedeemBatch) async throws -> RedeemBatchReconcileOutcome
        /// The record and its last send in this run.
        let fallback: @MainActor @Sendable (PendingRedeemBatch, Date?) async throws -> RedeemBatchFallbackOutcome
        let reveal: @MainActor @Sendable ([AdminRedeemCode]) async throws -> [AdminRedeemCode]
        let retryContext: @MainActor @Sendable (PendingRedeemBatch) -> RedeemRetryContext
        let authorize: @MainActor @Sendable (GatedAction) async -> Bool
        /// AppModel.persisted: saves the record and returns the only sendable form.
        let persist: @MainActor @Sendable (PendingRedeemBatch) throws -> PersistedMoneyWrite<PendingRedeemBatch>
        /// AppModel.sendRedeemBatch, the only sender (`sendSameNumber`).
        let send: @MainActor @Sendable (PersistedMoneyWrite<PendingRedeemBatch>) async throws -> WriteOutcome<[AdminRedeemCode]>
        let resolve: @MainActor @Sendable (PendingRedeemBatch) throws -> Void
        let hold: @MainActor @Sendable (UUID, Date?) -> Void
        let noteSent: @MainActor @Sendable (UUID, Date) -> Void
        let lastSent: @MainActor @Sendable (UUID) -> Date?
        /// RedeemCodesModel.noteExternalChange (C-34).
        let listChanged: @MainActor @Sendable () -> Void
        let report: @MainActor @Sendable (any Error) -> Void
        /// The session that started it is still the connected one.
        let isCurrent: @MainActor @Sendable () -> Bool
        let now: @MainActor @Sendable () -> Date
    }
    enum CheckOutcome: Sendable, Equatable {
        /// Settled meanwhile.
        case gone
        /// Found whole under its batch_id; the record is settled.
        case generated([AdminRedeemCode])
        case notGenerated(heuristic: Bool)
        /// Under its batch_id but not all of it: kept.
        case countMismatch([AdminRedeemCode])
        /// An old server's codes that look like the batch: kept.
        case probable([AdminRedeemCode])
        case undetermined
        /// The query failed: kept.
        case failed(String)
        case stale
    }
    enum RetryOutcome: Sendable, Equatable {
        case gone
        /// Not sent: another administrator's, a read-only token, the cooldown, an expired number of an old server or a local check.
        case refused(String)
        case notAuthorized
        case notSaved(String)
        /// The record is settled.
        case succeeded([AdminRedeemCode], replayed: Bool)
        /// Still to be checked; not again before `retryNotBefore`.
        case kept(String, retryNotBefore: Date?)
        /// The record is settled: refused by its body, nothing generated.
        case rejected(String)
        /// A newer session; a settled record stays settled.
        case stale
    }

    let effects: Effects
    /// The send log of every session (keyed by record id).
    static let sendLog = RedeemBatchSendLog()

    func check(_ id: UUID) async -> CheckOutcome {
        guard let record = effects.record(id) else { return .gone }
        do {
            if !effects.isLegacyServer() {
                let outcome = try await effects.reconcile(record)
                guard effects.isCurrent() else { return .stale }
                switch outcome {
                case .generated(let codes):
                    effects.listChanged()
                    return .generated(codes)
                case .notGenerated: return .notGenerated(heuristic: false)
                case .countMismatch(let codes): return .countMismatch(codes)
                case .unverifiable: break
                }
            }
            let guess = try await effects.fallback(record, effects.lastSent(id))
            guard effects.isCurrent() else { return .stale }
            switch guess {
            case .likelyGenerated(let codes), .countMismatch(let codes): return .probable(codes)
            case .notFound: return .notGenerated(heuristic: true)
            case .inconclusive: return .undetermined
            }
        } catch {
            guard effects.isCurrent(), !(error is CancellationError) else { return .stale }
            return .failed(BalanceReconcilePresentation.failedText)
        }
    }

    func retry(_ id: UUID) async -> RetryOutcome {
        guard let record = effects.record(id) else { return .gone }
        if let refusal = refusal(record) { return .refused(refusal) }
        if let total = record.total {
            guard await effects.authorize(.redeemGeneration(total: total)) else { return .notAuthorized }
            guard effects.isCurrent() else { return .stale }
        }
        // Face ID takes a while: the record may have been settled or held meanwhile.
        guard let latest = effects.record(id) else { return .gone }
        if let refusal = refusal(latest) { return .refused(refusal) }
        let write: PersistedMoneyWrite<PendingRedeemBatch>
        do { write = try effects.persist(latest) } catch { return .notSaved(PendingMoneyKind.redeemBatch.unsavedMessage) }
        effects.noteSent(id, effects.now())
        let result: Result<WriteOutcome<[AdminRedeemCode]>, any Error>
        do { result = .success(try await effects.send(write)) } catch { result = .failure(error) }
        return await settle(write.record, result: result)
    }

    /// “放弃这一批” after its confirmation, and “我已核对”: the record goes, nothing is sent; one already gone counts as done.
    func close(_ id: UUID) throws {
        guard let record = effects.record(id) else { return }
        try effects.resolve(record)
        effects.listChanged()
    }

    /// The only way a pending batch goes out again (S3D1-16, S6D1-07): the sender is checked before anything, then `deliver`
    /// sends the record's number with the address's site ids.
    nonisolated static func sendSameNumber(_ write: PersistedMoneyWrite<PendingRedeemBatch>, currentUserID: Int?, currentServerID: UUID?, sameAddress: Set<UUID>,
                                           deliver: @Sendable (PersistedMoneyWrite<PendingRedeemBatch>, Set<UUID>) async throws -> WriteOutcome<[AdminRedeemCode]>)
    async throws -> WriteOutcome<[AdminRedeemCode]> {
        let batch = write.record
        try MoneyRecordOrigin.checkSender(actorUserID: batch.actorUserID, currentUserID: currentUserID, recordServerID: batch.serverID,
                                          currentServerID: currentServerID, sameAddress: sameAddress)
        return try await deliver(write, sameAddress)
    }

    private func refusal(_ record: PendingRedeemBatch) -> String? {
        let context = effects.retryContext(record)
        if context.permission == .otherActor { return APIError.otherActorWrite.localizedDescription }
        if !context.offersRetry { return RedeemReconcilePresentation.expiredRetryLine }
        if context.isReadOnly { return BalanceReconcilePresentation.readOnlyLine }
        if context.isHeld(now: effects.now()) { return BalanceReconcilePresentation.heldLine }
        return nil
    }
    private func settle(_ record: PendingRedeemBatch, result: Result<WriteOutcome<[AdminRedeemCode]>, any Error>) async -> RetryOutcome {
        if case .failure(let error) = result, let local = Self.localRefusal(error) { return .refused(local) }
        switch RedeemGenerateResult.classify(result, batchID: record.id, retrying: true) {
        case .generated(let codes, let replayed, _, let needsRefetch):
            var shown = codes
            if needsRefetch {
                do { shown = try await effects.reveal(codes) } catch {
                    return effects.isCurrent() ? .kept(RedeemReconcilePresentation.revealFailedText, retryNotBefore: nil) : .stale
                }
            }
            settleRecord(record)
            effects.listChanged()
            return effects.isCurrent() ? .succeeded(shown, replayed: replayed) : .stale
        case .unconfirmed(let message, let retryNotBefore):
            if let retryNotBefore { effects.hold(record.id, retryNotBefore) }
            return effects.isCurrent() ? .kept(message, retryNotBefore: retryNotBefore) : .stale
        case .rejected(let message, _):
            settleRecord(record)
            return effects.isCurrent() ? .rejected(message) : .stale
        case .reconfirm(let notice):
            // Only a first send asks again; a retry that met a security prompt keeps the record.
            return effects.isCurrent() ? .kept(notice, retryNotBefore: nil) : .stale
        }
    }
    private func settleRecord(_ record: PendingRedeemBatch) {
        do { try effects.resolve(record) } catch { effects.report(error) }
    }
    /// Nothing went out: the sender or station check, a record already going out.
    private static func localRefusal(_ error: any Error) -> String? {
        if let busy = error as? MoneyWriteInFlight.Busy { return busy.localizedDescription }
        guard let local = error as? APIError, local.statusCode == nil, local.kind == .validation else { return nil }
        return local.localizedDescription
    }
}
