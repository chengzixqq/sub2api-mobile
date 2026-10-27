import Foundation
import Sub2Core

/// Session state of S3-07 (S3D1-05): the foreground check runs once at a time, and a number refused with STORE_UNAVAILABLE
/// waits out its cooldown before it may go again (30 §3.4). AppModel keeps one per session and replaces it whole.
struct PendingCheckRegistry: Sendable, Equatable {
    private(set) var isForegroundPassRunning = false
    private(set) var retryHolds: [UUID: Date] = [:]
    init() {}

    /// nil while a pass is already running.
    func startingForegroundPass() -> PendingCheckRegistry? {
        guard !isForegroundPassRunning else { return nil }
        var copy = self
        copy.isForegroundPassRunning = true
        return copy
    }
    func endingForegroundPass() -> PendingCheckRegistry {
        var copy = self
        copy.isForegroundPassRunning = false
        return copy
    }
    /// nil clears the hold.
    func holdingRetry(_ id: UUID, until date: Date?) -> PendingCheckRegistry {
        var copy = self
        copy.retryHolds[id] = date
        return copy
    }
    /// The end of a hold still running at `now`.
    func retryHeldUntil(_ id: UUID, now: Date) -> Date? {
        retryHolds[id].flatMap { $0 > now ? $0 : nil }
    }
}

/// “用同一编号重试” of a saved balance record (30 §3.4): the same key, X-Request-ID and bytes. The record is read again by
/// id, only its sender retries, Face ID follows D26, and the record is saved before it goes out (00 §0 rule 4). The result
/// of an attempt after one that may have run settles the record only when the server answered it (`retrying: true`).
@MainActor
struct BalanceRetry {
    struct Effects: Sendable {
        /// The saved record; nil once settled.
        let current: @MainActor @Sendable (UUID) -> PendingBalanceOperation?
        let permission: @MainActor @Sendable (PendingBalanceOperation) -> PendingRetryPermission
        let heldUntil: @MainActor @Sendable (UUID) -> Date?
        let isReadOnly: @MainActor @Sendable () -> Bool
        let authorize: @MainActor @Sendable (GatedAction) async -> Bool
        /// AppModel.persisted: saves the record (stamping lastSentAt) and returns the only sendable form.
        let persist: @MainActor @Sendable (PendingBalanceOperation) throws -> PersistedMoneyWrite<PendingBalanceOperation>
        let remember: @MainActor @Sendable (PendingBalanceOperation) throws -> Void
        /// AppModel.updateBalance, the only sender (S3D1-16).
        let send: @MainActor @Sendable (PersistedMoneyWrite<PendingBalanceOperation>, @escaping KeyedWriteEventHandler) async throws -> WriteOutcome<AdminUser>
        let resolve: @MainActor @Sendable (PendingBalanceOperation) throws -> Void
        let hold: @MainActor @Sendable (UUID, Date?) -> Void
        /// The session that started the retry is still the connected one.
        let isCurrent: @MainActor @Sendable () -> Bool
        let report: @MainActor @Sendable (any Error) -> Void
    }
    enum Outcome: Sendable {
        /// Settled meanwhile.
        case gone
        /// Not sent: another administrator's, a read-only token, the cooldown or a local check.
        case refused(String)
        case notAuthorized
        case notSaved(String)
        /// The record is settled; `replayed` or recovered results may be stale.
        case executed(WriteOutcome<AdminUser>)
        /// The record is settled: refused by its bytes.
        case notExecuted(String)
        /// Still to be checked.
        case kept(String)
        /// A security prompt cleared it: confirm the same record once more.
        case reconfirm(String)
        /// A newer session; the record was still settled when the server answered.
        case stale
    }

    let effects: Effects

    func run(_ id: UUID, currentBalance: Decimal?) async -> Outcome {
        guard let record = effects.current(id) else { return .gone }
        if let refusal = refusal(record) { return .refused(refusal) }
        let gated = GatedAction.balanceAdjustment(record.operation, amount: record.amount, currentBalance: currentBalance)
        guard await effects.authorize(gated) else { return .notAuthorized }
        guard effects.isCurrent() else { return .stale }
        // Face ID takes a while: the record may have been settled or held meanwhile.
        guard let latest = effects.current(id) else { return .gone }
        if let refusal = refusal(latest) { return .refused(refusal) }
        let write: PersistedMoneyWrite<PendingBalanceOperation>
        do { write = try effects.persist(latest) } catch { return .notSaved(PendingMoneyKind.balance.unsavedMessage) }
        let result: Result<WriteOutcome<AdminUser>, any Error>
        do { result = .success(try await effects.send(write, actionIDSaver(for: write.record))) } catch { result = .failure(error) }
        return settle(write.record, result: result)
    }

    private func refusal(_ record: PendingBalanceOperation) -> String? {
        if effects.permission(record) == .otherActor { return APIError.otherActorWrite.localizedDescription }
        if effects.isReadOnly() { return BalanceReconcilePresentation.readOnlyLine }
        if effects.heldUntil(record.id) != nil { return BalanceReconcilePresentation.heldLine }
        return nil
    }
    /// 30 §3.4 step 4: the action id is saved as soon as a reply carries it; a failed save leaves the request id to match by.
    private func actionIDSaver(for record: PendingBalanceOperation) -> KeyedWriteEventHandler {
        let remember = effects.remember
        return { @MainActor event in
            guard case .actionID(let actionID) = event else { return }
            try? remember(record.with(actionID: actionID))
        }
    }
    private func settle(_ record: PendingBalanceOperation, result: Result<WriteOutcome<AdminUser>, any Error>) -> Outcome {
        switch result {
        case .success(let outcome):
            settleRecord(record)
            return effects.isCurrent() ? .executed(outcome) : .stale
        case .failure(let error):
            // A local check sent nothing (checkSender, the station guard, the body).
            if let local = error as? APIError, local.statusCode == nil, local.kind == .validation { return .refused(local.localizedDescription) }
            switch BalanceReconciliation.balanceWriteOutcome(for: error, retrying: true) {
            case .executed(let user, let replayed):
                settleRecord(record)
                return effects.isCurrent() ? .executed(WriteOutcome(value: user, replayed: replayed)) : .stale
            case .notExecuted(let message):
                settleRecord(record)
                return effects.isCurrent() ? .notExecuted(message) : .stale
            case .pending(let message, let retryNotBefore):
                if let retryNotBefore { effects.hold(record.id, retryNotBefore) }
                guard effects.isCurrent() else { return .stale }
                guard let refused = error as? APIError else { return .kept(message) }
                if refused.securityOutcome == .passed { return .reconfirm(refused.localizedDescription) }
                return .kept(refused.isRefusedBeforeHandler ? refused.localizedDescription : message)
            }
        }
    }
    private func settleRecord(_ record: PendingBalanceOperation) {
        do { try effects.resolve(record) } catch { effects.report(error) }
    }
}

/// 30 §3.6: back in the foreground each balance record of this address is checked once, read-only. Only an exact match
/// (action_id / request_id) settles it with a receipt; candidates, nothing found and the 40-second grace keep it for the
/// administrator. Redeem batches are never checked on their own (60 §11.6); S6-08 adds compensations to the switch.
@MainActor
struct ForegroundReconcilePass {
    struct Effects: Sendable {
        /// The address's records, oldest first (AppModel.pendingMoneyWrites(sameAddressAs:)).
        let records: @MainActor @Sendable () -> [any PendingMoneyWrite]
        let reconcileBalance: @MainActor @Sendable (PendingBalanceOperation) async throws -> BalanceReconcileOutcome
        let applyExecuted: @MainActor @Sendable (PendingBalanceOperation, UserAdjustment) -> Void
        /// Same session, still in the foreground.
        let shouldContinue: @MainActor @Sendable () -> Bool
    }

    let effects: Effects

    /// The ids settled by an exact match.
    @discardableResult
    func run() async -> [UUID] {
        var settled: [UUID] = []
        for record in effects.records() {
            guard effects.shouldContinue() else { break }
            // Settled by hand since the pass started.
            guard effects.records().contains(where: { $0.id == record.id }) else { continue }
            switch record {
            case let op as PendingBalanceOperation:
                guard case .executed(let row)? = try? await effects.reconcileBalance(op), effects.shouldContinue() else { continue }
                effects.applyExecuted(op, row)
                settled.append(op.id)
            default:
                continue
            }
        }
        return settled
    }
}
