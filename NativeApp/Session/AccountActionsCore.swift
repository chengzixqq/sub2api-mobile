import Foundation
import Observation
import os
import Sub2Core

/// What an account action reads of the session at the user's tap (S2D1-05); its generation goes with every write it sends.
struct AccountWriteSession: Sendable, Equatable {
    let generation: UUID
    /// admin.idempotent_writes: the switch and the PUT fallback carry a key made at the tap (R05).
    let idempotentWrites: Bool
    /// accounts.recover_schedulable: “恢复并启用调度” is one recover-state.
    let recoverSchedulable: Bool
    /// accounts.patch: 启用账号 is a PATCH with If-Match, otherwise the PUT fallback.
    let patch: Bool
    let isReadOnlyToken: Bool
}

/// The account reads and writes the actions use (AppModel+Accounts, C-16). A write carries the generation of the session the
/// user acted in and throws CancellationError once that session is gone.
@MainActor protocol AccountWriteSource: AnyObject {
    var accountWriteSession: AccountWriteSession? { get }
    func serverNow() -> Date
    func recoverAccountState(id: Int, schedulable: Bool?, generation: UUID) async throws -> UpstreamAccount
    func setAccountSchedulable(id: Int, enabled: Bool, idempotencyKey: UUID?, generation: UUID) async throws -> WriteOutcome<UpstreamAccount>
    func accountWithVersion(id: Int) async throws -> VersionedAccount
    func patchAccount(id: Int, body: AccountPatchRequest, ifMatch: String, generation: UUID) async throws -> VersionedAccount
    func fullUpdateAccount(id: Int, patch: AccountPatchRequest, base: UpstreamAccount?, idempotencyKey: UUID?,
                           generation: UUID) async throws -> UpstreamAccount
}

enum AccountActionOutcome: Equatable, Sendable { case succeeded, recoveredPaused, notApplied, unconfirmed, reconfirm, missing, failed, ignored }

/// 20 §5: 恢复状态, 启用 / 停止调度 and 启用账号 for the detail, the list's swipe and the group's member rows (C-7). Each ends in
/// one receipt (撤销, 启用调度 or 重试) and hands every account the server returns or reads back to `onChange`; the caller
/// decides what to refresh. A result that arrives after the session changed is dropped.
@MainActor @Observable
final class AccountActions {
    /// Accounts with an action running; another tap on them is ignored.
    private(set) var inFlight: Set<Int> = []
    @ObservationIgnored private let source: any AccountWriteSource
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let onChange: @MainActor (UpstreamAccount) -> Void
    @ObservationIgnored private let onMissing: (@MainActor (Int) -> Void)?
    @ObservationIgnored private let makeKey: @MainActor () -> UUID
    private static let log = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "accounts")

    init(source: any AccountWriteSource, receipts: ReceiptCenter, onChange: @escaping @MainActor (UpstreamAccount) -> Void,
         onMissing: (@MainActor (Int) -> Void)? = nil, makeKey: @escaping @MainActor () -> UUID = { UUID() }) {
        self.source = source; self.receipts = receipts; self.onChange = onChange; self.onMissing = onMissing; self.makeKey = makeKey
    }

    func isRunning(_ accountID: Int) -> Bool { inFlight.contains(accountID) }

    /// “恢复并启用调度” (`enableScheduling`), “只恢复状态” and “恢复状态”; never undone (20 §5.4).
    @discardableResult
    func recover(_ account: UpstreamAccount, enableScheduling: Bool) async -> AccountActionOutcome {
        await run(account.id) { session in
            let twoSteps = enableScheduling && !session.recoverSchedulable
            return await sendRecover(Recovery(id: account.id, enableScheduling: enableScheduling, secondKey: twoSteps ? newKey(session) : nil),
                                     session: session)
        }
    }
    /// 停止 / 启用调度; with admin.idempotent_writes the key is made here, at the tap (R05).
    @discardableResult
    func setSchedulable(_ account: UpstreamAccount, enabled: Bool) async -> AccountActionOutcome {
        await run(account.id) { session in
            await sendSchedulable(Switch(id: account.id, enabled: enabled, key: newKey(session), isUndo: false), session: session)
        }
    }
    /// 启用账号: PATCH {status: active} with If-Match, the version read first unless `etag` is given; without accounts.patch
    /// the PUT fallback (X24), keyed with admin.idempotent_writes.
    @discardableResult
    func enableAccount(_ account: UpstreamAccount, etag: String? = nil) async -> AccountActionOutcome {
        await run(account.id) { session in
            let change = StatusChange(id: account.id, target: .active, isUndo: false, key: session.patch ? nil : newKey(session),
                                      undoTarget: AccountActionCopy.undoStatus(from: account.status))
            return await writeStatus(change, base: account, etag: etag, session: session)
        }
    }

    // MARK: - Running

    /// Nothing is sent without a session or while this account is busy; a read-only token gets the catalog's words (00 §2.6.3).
    private func run(_ id: Int, _ body: (AccountWriteSession) async -> AccountActionOutcome) async -> AccountActionOutcome {
        guard !inFlight.contains(id), let session = source.accountWriteSession else { return .ignored }
        guard !session.isReadOnlyToken else { show(AccountActionCopy.readOnly); return .failed }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        return await body(session)
    }
    /// A receipt's button: sent in the session the receipt belongs to, whose writes AppModel refuses once it has ended.
    private func relaunch(_ id: Int, _ body: @escaping @MainActor @Sendable (AccountActions) async -> AccountActionOutcome) {
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        Task { [weak self] in
            guard let self else { return }
            _ = await body(self)
            self.inFlight.remove(id)
        }
    }
    private func newKey(_ session: AccountWriteSession) -> UUID? { session.idempotentWrites ? makeKey() : nil }
    private func isCurrent(_ session: AccountWriteSession) -> Bool { source.accountWriteSession?.generation == session.generation }

    // MARK: - Scheduling switch

    /// One intent of the switch: a retry keeps its key, an undo is a new intent.
    private struct Switch: Sendable {
        let id: Int
        let enabled: Bool
        let key: UUID?
        let isUndo: Bool
        var kind: AccountActionKind { isUndo ? .undo : .setSchedulable(enabled) }
    }

    private func sendSchedulable(_ change: Switch, session: AccountWriteSession) async -> AccountActionOutcome {
        do {
            let outcome = try await source.setAccountSchedulable(id: change.id, enabled: change.enabled, idempotencyKey: change.key,
                                                                 generation: session.generation)
            guard isCurrent(session) else { return .ignored }
            return switched(outcome.value, change, session: session)
        } catch {
            guard isCurrent(session) else { return .ignored }
            if let settled = settle(error, kind: change.kind, id: change.id, retry: retrySwitch(change, session)) { return settled }
            switch await readBack(change.id, session: session) {
            case nil: return .ignored
            case .failure(let readError)?: return readBackFailed(readError, id: change.id, kind: change.kind)
            case .success(let fresh)?:
                if AccountWriteCheck.schedulable(fresh.account, equals: change.enabled) { return switched(fresh.account, change, session: session) }
                onChange(fresh.account)
                return notConfirmed(change.kind, keyed: change.key != nil, retry: retrySwitch(change, session))
            }
        }
    }
    /// An undo that went through says nothing more: the row shows it.
    private func switched(_ account: UpstreamAccount, _ change: Switch, session: AccountWriteSession) -> AccountActionOutcome {
        onChange(account)
        guard !change.isUndo else { return .succeeded }
        show(AccountActionCopy.scheduled(enabled: change.enabled)) { [weak self] in
            guard let self else { return }
            let undo = Switch(id: change.id, enabled: !change.enabled, key: self.newKey(session), isUndo: true)
            self.relaunch(change.id) { await $0.sendSchedulable(undo, session: session) }
        }
        return .succeeded
    }
    private func retrySwitch(_ change: Switch, _ session: AccountWriteSession) -> @MainActor @Sendable () -> Void {
        { [weak self] in self?.relaunch(change.id) { await $0.sendSchedulable(change, session: session) } }
    }

    // MARK: - Recover

    /// The fallback's second step keeps its key through retries (00 §2.5.2).
    private struct Recovery: Sendable {
        let id: Int
        let enableScheduling: Bool
        let secondKey: UUID?
    }

    private func sendRecover(_ recovery: Recovery, session: AccountWriteSession) async -> AccountActionOutcome {
        let oneStep = recovery.enableScheduling && session.recoverSchedulable
        do {
            let account = try await source.recoverAccountState(id: recovery.id, schedulable: oneStep ? true : nil, generation: session.generation)
            guard isCurrent(session) else { return .ignored }
            return await enableAfterRecovery(account, recovery, session: session)
        } catch {
            guard isCurrent(session) else { return .ignored }
            if let settled = settle(error, kind: .recover, id: recovery.id, retry: retryRecovery(recovery, session)) { return settled }
            return await verifyRecovery(error, recovery, session: session)
        }
    }
    /// Without accounts.recover_schedulable “恢复并启用调度” switches scheduling on afterwards; whatever goes wrong there, the
    /// read-back (or else the recovered account) decides the receipt.
    private func enableAfterRecovery(_ account: UpstreamAccount, _ recovery: Recovery, session: AccountWriteSession) async -> AccountActionOutcome {
        guard recovery.enableScheduling, !account.schedulable else { return recovered(account, session: session) }
        do {
            let outcome = try await source.setAccountSchedulable(id: recovery.id, enabled: true, idempotencyKey: recovery.secondKey,
                                                                 generation: session.generation)
            guard isCurrent(session) else { return .ignored }
            return recovered(outcome.value, session: session)
        } catch {
            guard isCurrent(session) else { return .ignored }
            switch await readBack(recovery.id, session: session) {
            case nil: return .ignored
            case .success(let fresh)?: return recovered(fresh.account, session: session)
            case .failure?: return recovered(account, session: session)
            }
        }
    }
    /// 20 §5.5: recovered = not in error and every window past on the site clock. 500 ACCOUNT_RECOVERED_SCHEDULABLE_FAILED has
    /// recovered already, so only its switch is read, and an unreadable one counts as still paused (API_ERROR_CODES).
    private func verifyRecovery(_ error: any Error, _ recovery: Recovery, session: AccountWriteSession) async -> AccountActionOutcome {
        let partial = (error as? APIError).map(AccountWriteReason.isRecoveredButStillPaused) == true
        switch await readBack(recovery.id, session: session) {
        case nil: return .ignored
        case .failure(let readError)?:
            return partial ? recoveredReceipt(id: recovery.id, schedulable: false, session: session)
                : readBackFailed(readError, id: recovery.id, kind: .recover)
        case .success(let fresh)?:
            if partial { return recovered(fresh.account, session: session) }
            guard AccountWriteCheck.recovered(fresh.account, now: source.serverNow()) else {
                onChange(fresh.account)
                return notConfirmed(.recover, keyed: false, retry: retryRecovery(recovery, session))
            }
            return await enableAfterRecovery(fresh.account, recovery, session: session)
        }
    }
    private func recovered(_ account: UpstreamAccount, session: AccountWriteSession) -> AccountActionOutcome {
        onChange(account)
        return recoveredReceipt(id: account.id, schedulable: account.schedulable, session: session)
    }
    /// Still paused: “启用调度” is a new switch intent, whose own receipt offers 撤销.
    private func recoveredReceipt(id: Int, schedulable: Bool, session: AccountWriteSession) -> AccountActionOutcome {
        guard !schedulable else { show(AccountActionCopy.recovered(schedulable: true)); return .succeeded }
        show(AccountActionCopy.recovered(schedulable: false)) { [weak self] in
            guard let self else { return }
            let change = Switch(id: id, enabled: true, key: self.newKey(session), isUndo: false)
            self.relaunch(id) { await $0.sendSchedulable(change, session: session) }
        }
        return .recoveredPaused
    }
    private func retryRecovery(_ recovery: Recovery, _ session: AccountWriteSession) -> @MainActor @Sendable () -> Void {
        { [weak self] in self?.relaunch(recovery.id) { await $0.sendRecover(recovery, session: session) } }
    }

    // MARK: - Enable account

    /// 启用账号 or its undo; `key` only for the PUT fallback, kept through retries.
    private struct StatusChange: Sendable {
        let id: Int
        let target: AccountPatchRequest.Status
        let isUndo: Bool
        let key: UUID?
        /// What the undo writes back; nil gives no undo.
        let undoTarget: AccountPatchRequest.Status?
        var kind: AccountActionKind { isUndo ? .undo : .enableAccount }
        var request: AccountPatchRequest { AccountPatchRequest(status: target) }
        func keyed(_ key: UUID?) -> StatusChange { StatusChange(id: id, target: target, isUndo: isUndo, key: key, undoTarget: undoTarget) }
    }

    /// Without an ETag the version is read first; a server that sends none takes the PUT fallback.
    private func writeStatus(_ change: StatusChange, base: UpstreamAccount?, etag: String?, session: AccountWriteSession) async -> AccountActionOutcome {
        guard session.patch else { return await putStatus(change, session: session) }
        if let etag { return await patchStatus(change, base: base, etag: etag, session: session, isConflictRetry: false) }
        switch await readBack(change.id, session: session) {
        case nil: return .ignored
        case .failure(let error)?: return versionUnreadable(error, change)
        case .success(let fresh)?:
            guard let tag = fresh.etag else { return await putStatus(change.keyed(newKey(session)), session: session) }
            return await patchStatus(change, base: fresh.account, etag: tag, session: session, isConflictRetry: false)
        }
    }
    private func patchStatus(_ change: StatusChange, base: UpstreamAccount?, etag: String, session: AccountWriteSession,
                             isConflictRetry: Bool) async -> AccountActionOutcome {
        do {
            let reply = try await source.patchAccount(id: change.id, body: change.request, ifMatch: etag, generation: session.generation)
            guard isCurrent(session) else { return .ignored }
            return statusApplied(reply, change, session: session)
        } catch {
            guard isCurrent(session) else { return .ignored }
            if AccountActionCopy.disposition(of: error) == .versionConflict {
                return isConflictRetry ? statusFailed(error, change) : await resolveConflict(error, change, base: base, session: session)
            }
            if let settled = settle(error, kind: change.kind, id: change.id, retry: retryStatus(change, base: base, etag: etag, session)) {
                return settled
            }
            return await verifyStatus(change, session: session)
        }
    }
    private func putStatus(_ change: StatusChange, session: AccountWriteSession) async -> AccountActionOutcome {
        do {
            let account = try await source.fullUpdateAccount(id: change.id, patch: change.request, base: nil, idempotencyKey: change.key,
                                                             generation: session.generation)
            guard isCurrent(session) else { return .ignored }
            return statusApplied(VersionedAccount(account: account, etag: nil), change, session: session)
        } catch {
            guard isCurrent(session) else { return .ignored }
            if let settled = settle(error, kind: change.kind, id: change.id, retry: retryStatus(change, base: nil, etag: nil, session)) {
                return settled
            }
            return await verifyStatus(change, session: session)
        }
    }
    /// 20 §0.4-6 for this one field: still the old status → resend once with the new ETag; already the target → done; a third
    /// value → “账号已被其他人修改” with the fresh account.
    private func resolveConflict(_ error: any Error, _ change: StatusChange, base: UpstreamAccount?, session: AccountWriteSession) async -> AccountActionOutcome {
        switch await readBack(change.id, session: session) {
        case nil: return .ignored
        case .failure?: return statusFailed(error, change)
        case .success(let fresh)?:
            switch AccountPatchConflict.resolve(base: base ?? fresh.account, current: fresh.account, request: change.request) {
            case .alreadyApplied: return statusApplied(fresh, change, session: session)
            case .askUser:
                onChange(fresh.account)
                return statusFailed(error, change)
            case .silentRetry:
                guard let tag = fresh.etag ?? (error as? APIError).flatMap(AccountPatchConflict.currentETag) else { return statusFailed(error, change) }
                return await patchStatus(change, base: fresh.account, etag: tag, session: session, isConflictRetry: true)
            }
        }
    }
    /// 20 §5.5: done when `status` reads the target.
    private func verifyStatus(_ change: StatusChange, session: AccountWriteSession) async -> AccountActionOutcome {
        switch await readBack(change.id, session: session) {
        case nil: return .ignored
        case .failure(let error)?: return readBackFailed(error, id: change.id, kind: change.kind)
        case .success(let fresh)?:
            if fresh.account.status == change.target.rawValue { return statusApplied(fresh, change, session: session) }
            onChange(fresh.account)
            return notConfirmed(change.kind, keyed: change.key != nil, retry: retryStatus(change, base: fresh.account, etag: fresh.etag, session))
        }
    }
    /// The undo writes the old status back with the reply's ETag (read first when there is none), under a new key on PUT.
    private func statusApplied(_ fresh: VersionedAccount, _ change: StatusChange, session: AccountWriteSession) -> AccountActionOutcome {
        onChange(fresh.account)
        guard !change.isUndo else { return .succeeded }
        guard let undoTarget = change.undoTarget else {
            show(AccountActionCopy.accountEnabled(name: fresh.account.name, canUndo: false))
            return .succeeded
        }
        show(AccountActionCopy.accountEnabled(name: fresh.account.name)) { [weak self] in
            guard let self else { return }
            let undo = StatusChange(id: change.id, target: undoTarget, isUndo: true, key: session.patch ? nil : self.newKey(session), undoTarget: nil)
            self.relaunch(change.id) { await $0.writeStatus(undo, base: fresh.account, etag: fresh.etag, session: session) }
        }
        return .succeeded
    }
    /// The version could not be read before the PATCH, so nothing was sent.
    private func versionUnreadable(_ error: any Error, _ change: StatusChange) -> AccountActionOutcome {
        switch AccountActionCopy.disposition(of: error) {
        case .cancelled: return .ignored
        case .missing: return gone(change.id, kind: change.kind, error: error)
        default: return statusFailed(error, change)
        }
    }
    private func statusFailed(_ error: any Error, _ change: StatusChange) -> AccountActionOutcome {
        show(AccountActionCopy.failed(change.kind, error: error))
        return .failed
    }
    private func retryStatus(_ change: StatusChange, base: UpstreamAccount?, etag: String?, _ session: AccountWriteSession) -> @MainActor @Sendable () -> Void {
        { [weak self] in self?.relaunch(change.id) { await $0.writeStatus(change, base: base, etag: etag, session: session) } }
    }

    // MARK: - Failures and read-back

    /// The failures every action answers alike; nil for one whose result `GET :id` decides.
    private func settle(_ error: any Error, kind: AccountActionKind, id: Int, retry: @escaping @MainActor @Sendable () -> Void) -> AccountActionOutcome? {
        switch AccountActionCopy.disposition(of: error) {
        case .readBack: return nil
        case .cancelled: return .ignored
        case .reconfirm:
            show(AccountActionCopy.reconfirm(error), action: retry)
            return .reconfirm
        case .missing: return gone(id, kind: kind, error: error)
        case .versionConflict, .failed:
            logRejected(error)
            show(AccountActionCopy.failed(kind, error: error))
            return .failed
        }
    }
    /// 20 §0.5: the caller drops the account.
    private func gone(_ id: Int, kind: AccountActionKind, error: any Error) -> AccountActionOutcome {
        onMissing?(id)
        show(AccountActionCopy.failed(kind, error: error))
        return .missing
    }
    /// nil when the session changed meanwhile.
    private func readBack(_ id: Int, session: AccountWriteSession) async -> Result<VersionedAccount, any Error>? {
        do {
            let fresh = try await source.accountWithVersion(id: id)
            return isCurrent(session) ? .success(fresh) : nil
        } catch {
            return isCurrent(session) ? .failure(error) : nil
        }
    }
    /// 00 §2.4: a result nobody could read back.
    private func readBackFailed(_ error: any Error, id: Int, kind: AccountActionKind) -> AccountActionOutcome {
        switch AccountActionCopy.disposition(of: error) {
        case .cancelled: return .ignored
        case .missing: return gone(id, kind: kind, error: error)
        default:
            show(AccountActionCopy.unconfirmedReceipt)
            return .unconfirmed
        }
    }
    /// The read-back shows the write did not happen: a keyed one may go again under its number, an unkeyed one on the user's tap.
    private func notConfirmed(_ kind: AccountActionKind, keyed: Bool, retry: @escaping @MainActor @Sendable () -> Void) -> AccountActionOutcome {
        show(keyed ? AccountActionCopy.unconfirmedRetry(kind) : AccountActionCopy.notApplied(kind), action: retry)
        return keyed ? .unconfirmed : .notApplied
    }
    private func show(_ copy: AccountReceiptCopy, action: (@MainActor @Sendable () -> Void)? = nil) {
        let button = copy.button.flatMap { kind in action.map { ReceiptAction(title: kind.title, perform: $0) } }
        receipts.show(Receipt(text: copy.text, systemImage: copy.systemImage, tone: copy.tone, action: button))
    }
    /// 20 §0.5: a PATCH the App built wrongly is a defect; only the status, reason and request ID are logged (00 §3.4).
    private func logRejected(_ error: any Error) {
        guard let api = error as? APIError, AccountWriteReason.isRejectedPatch(api) else { return }
        let requestID = String((api.requestID ?? "-").prefix(64))
        Self.log.error("PATCH admin/accounts/:id \(api.statusCode ?? 0, privacy: .public) \(api.reason ?? "-", privacy: .public) \(requestID, privacy: .public)")
    }
}
