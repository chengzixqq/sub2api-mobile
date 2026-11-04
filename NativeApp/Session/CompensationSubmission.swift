import Foundation
import os
import Sub2Core

/// A compensation's first send and “用同一编号重试” (60 §19.4, R03, R04, R05): the gate (no new grant while one of this user
/// awaits its check) or the retry permission first, then Face ID for a balance grant, then the record is saved before it goes
/// out (00 §0 rule 4; a failed save sends nothing) through S6-08's only sender, which marks it going out. The answer follows
/// S6-08's GrantResultAction; every answer but an uncertain one settles the record. A grant bumps the user's pages (bumpBalance
/// for balance, C-12) and the redeem list (S6D1-15).
@MainActor
struct CompensationSubmission {
    struct Effects: Sendable {
        /// AppModel.moneyWriteGate(.compensation(userID:)) over the connected address (X34).
        let gate: @MainActor @Sendable (Int) -> PendingMoneyGate
        let authorize: @MainActor @Sendable (GatedAction) async -> Bool
        /// AppModel.persisted: saves the record and returns the only sendable form.
        let persist: @MainActor @Sendable (PendingCompensation) throws -> PersistedMoneyWrite<PendingCompensation>
        /// AppModel.sendCompensation (S6-08), the only sender: the sender check and the going-out mark are its own.
        let send: @MainActor @Sendable (PersistedMoneyWrite<PendingCompensation>, @escaping KeyedWriteEventHandler) async throws
            -> WriteOutcome<AdminRedeemCode>
        let resolve: @MainActor @Sendable (PendingCompensation) throws -> Void
        /// The saved record; nil once settled.
        let record: @MainActor @Sendable (UUID) -> PendingCompensation?
        let retryContext: @MainActor @Sendable (PendingCompensation) -> RedeemRetryContext
        /// STORE_UNAVAILABLE: the same number waits until then.
        let hold: @MainActor @Sendable (UUID, Date?) -> Void
        /// UserChangeSignal.bump / bumpBalance of the granted user.
        let bump: @MainActor @Sendable (Int) -> Void
        let bumpBalance: @MainActor @Sendable (Int) -> Void
        /// RedeemCodesModel.noteExternalChange (C-34): the code joins the list.
        let listChanged: @MainActor @Sendable () -> Void
        /// The session that started it is still the connected one.
        let isCurrent: @MainActor @Sendable () -> Bool
        /// Phone time, like the cooldown.
        let now: @MainActor @Sendable () -> Date
    }
    enum Outcome: Sendable, Equatable {
        /// Another record of this user awaits its check: nothing done.
        case blocked(UUID)
        /// The compensation file cannot be read: nothing done.
        case paused(String)
        /// A retry not sent: another administrator's, a read-only token, the cooldown, or stopped before it left.
        case refused(String)
        /// Face ID failed or was cancelled: nothing saved, nothing sent.
        case notAuthorized
        case notSaved(String)
        /// The record is settled.
        case granted(AdminRedeemCode, replayed: Bool)
        /// Kept to be checked.
        case pending(String)
        /// The record is settled; step 3 again with a new code (REDEEM_CODE_CONFLICT / EXPIRED).
        case renumber(String)
        /// The record is settled; step 2 again, the group directory read again.
        case backToValue(String)
        /// The record is settled; the sheet closes.
        case userGone(String)
        /// The record is settled; confirmed again under a new key with the same code (00 §2.5.3).
        case newKey(String)
        /// The record is settled; the same record is confirmed once more (00 §2.6.2 step 4, S6D1-08).
        case reconfirm(PendingCompensation, notice: String)
        /// The record is settled: nothing was granted.
        case rejected(String)
        /// A retry's record is no longer there.
        case gone
        /// A newer session; a settled record stays settled.
        case stale
    }

    private static let logger = Logger(subsystem: "Sub2Mobile", category: "compensation")
    let effects: Effects

    /// The record confirmed now (R05), or the same record again after `reconfirm`.
    func grant(_ record: PendingCompensation, progress: @escaping @MainActor @Sendable (BalanceWriteProgress) -> Void) async -> Outcome {
        if let stop = gateStop(record) { return stop }
        if record.type == .balance {
            guard await effects.authorize(.compensation(record.value)) else { return .notAuthorized }
            guard effects.isCurrent() else { return .stale }
            if let stop = gateStop(record) { return stop }
        }
        let write: PersistedMoneyWrite<PendingCompensation>
        do { write = try effects.persist(record) } catch { return .notSaved(PendingMoneyKind.compensation.unsavedMessage) }
        progress(.submitting)
        return settle(write.record, result: await send(write, progress: progress), retrying: false)
    }

    /// The saved record read again by id; only its sender at this address sends it (D17, X34), past its idempotency expiry too
    /// (the server dedupes by code, 19.4 step 7).
    func retry(_ id: UUID, progress: @escaping @MainActor @Sendable (BalanceWriteProgress) -> Void) async -> Outcome {
        guard let record = effects.record(id) else { return .gone }
        if let refusal = refusal(record) { return .refused(refusal) }
        if record.type == .balance {
            guard await effects.authorize(.compensation(record.value)) else { return .notAuthorized }
            guard effects.isCurrent() else { return .stale }
        }
        // Face ID takes a while: the record may have been settled or held meanwhile.
        guard let latest = effects.record(id) else { return .gone }
        if let refusal = refusal(latest) { return .refused(refusal) }
        let write: PersistedMoneyWrite<PendingCompensation>
        do { write = try effects.persist(latest) } catch { return .notSaved(PendingMoneyKind.compensation.unsavedMessage) }
        progress(.submitting)
        let result = await send(write, progress: progress)
        if case .failure(let error) = result, let local = Self.localRefusal(error) { return current(.refused(local)) }
        return settle(write.record, result: result, retrying: true)
    }

    private func send(_ write: PersistedMoneyWrite<PendingCompensation>,
                      progress: @escaping @MainActor @Sendable (BalanceWriteProgress) -> Void) async -> Result<WriteOutcome<AdminRedeemCode>, any Error> {
        do {
            return .success(try await effects.send(write) { @MainActor event in
                if let step = BalanceWriteProgress(event) { progress(step) }
            })
        } catch {
            return .failure(error)
        }
    }
    private func gateStop(_ record: PendingCompensation) -> Outcome? {
        switch effects.gate(record.userID) {
        case .clear: return nil
        case .paused(let kind): return .paused(kind.unreadableMessage)
        case .overridable(let ids), .blocked(let ids): return ids.first { $0 != record.id }.map(Outcome.blocked)
        }
    }
    private func refusal(_ record: PendingCompensation) -> String? {
        let context = effects.retryContext(record)
        if context.permission == .otherActor { return APIError.otherActorWrite.localizedDescription }
        if context.isReadOnly { return BalanceReconcilePresentation.readOnlyLine }
        if context.isHeld(now: effects.now()) { return BalanceReconcilePresentation.heldLine }
        return nil
    }
    private func settle(_ record: PendingCompensation, result: Result<WriteOutcome<AdminRedeemCode>, any Error>, retrying: Bool) -> Outcome {
        let action = GrantResultAction.classify(result, retrying: retrying)
        if action.resolvesRecord {
            // A record that cannot be dropped stays to be checked; the answer is still shown.
            do { try effects.resolve(record) } catch { Self.logger.error("compensation record kept after a final answer") }
        }
        guard effects.isCurrent() else { return .stale }
        switch action {
        case .granted(let code, let replayed):
            if record.type == .balance { effects.bumpBalance(record.userID) } else { effects.bump(record.userID) }
            effects.listChanged()
            return .granted(code, replayed: replayed)
        case .renumber(let message): return .renumber(message)
        case .backToValue(let message): return .backToValue(message)
        case .userGone(let message): return .userGone(message)
        case .newKeyNeeded(let message): return .newKey(message)
        case .reconfirm(let message): return .reconfirm(record, notice: message)
        case .rejected(let message, let reportsDefect):
            // 00 §3.3 “请求无效”: the App should never send it; reported without the code.
            if reportsDefect, case .failure(let error as APIError) = result {
                Self.logger.error("create-and-redeem refused: \(error.statusCode ?? 0, privacy: .public) \(error.reason ?? "-", privacy: .public)")
            }
            return .rejected(message)
        case .pending(let message, let retryNotBefore):
            if let retryNotBefore { effects.hold(record.id, retryNotBefore) }
            return .pending(message)
        }
    }
    private func current(_ outcome: Outcome) -> Outcome { effects.isCurrent() ? outcome : .stale }
    /// Nothing went out: the sender or station check, a record already going out.
    private static func localRefusal(_ error: any Error) -> String? {
        if let busy = error as? MoneyWriteInFlight.Busy { return busy.localizedDescription }
        guard let local = error as? APIError, local.statusCode == nil, local.kind == .validation else { return nil }
        return local.localizedDescription
    }
}
