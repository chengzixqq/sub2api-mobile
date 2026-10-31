import Foundation
import Observation
import os
import Sub2Core

/// C-14: what the save flow needs beyond AccountWriteSource (AppModel+Accounts). A write takes the generation of the session the
/// user saved in (S2D1-05).
@MainActor protocol AccountPatchSource: AccountWriteSource {
    /// accounts.mixed_channel_details: a 409 names the group, so changed groups go out without the pre-check.
    var hasMixedChannelDetails: Bool { get }
    func checkMixedChannel(platform: String, groupIDs: [Int], accountID: Int?, generation: UUID) async throws -> MixedChannelCheck
}

/// C-14, S2D1-04: the App's one save of an account edit (20 §0.4-5…7, §3.4, §3.5), for the 基础 / 调度 sheets and S2-11, S2-12,
/// S2-16, S2-20. A PATCH with If-Match, or the PUT fallback without `accounts.patch`; a 412 is resent once when only untouched
/// fields moved, else `prompt` asks; a 409 or the pre-check asks before 继续保存; an unknown result is read back. Success hands
/// the account to `onChange`, moves `savedRevision` (the sheet closes on it) and shows the receipt with 撤销. A result that
/// arrives after the session changed is dropped.
@MainActor @Observable
final class AccountPatchFlow {
    enum Phase: Equatable, Sendable { case idle, saving, notApplied, unconfirmed, failed(String), reconfirm(String), needsWeb(String) }
    enum Prompt: Identifiable, Sendable {
        case overwrite(AccountPatchAttempt, current: AccountEditBase?, currentETag: String?)
        case mixedChannel(AccountPatchAttempt, MixedChannelWarning)
        var id: String {
            switch self {
            case .overwrite: "overwrite"
            case .mixedChannel: "mixedChannel"
            }
        }
    }
    typealias ReceiptMaker = @MainActor (AccountEditBase) -> Receipt?

    let accountID: Int
    private(set) var phase: Phase = .idle
    var prompt: Prompt?
    /// Moves on every save that went through, the prompts' included.
    private(set) var savedRevision = 0
    /// 重新载入 after a conflict: the server's copy, which the sheet takes as its new base when `reloadRevision` moves.
    private(set) var reloadedBase: AccountEditBase?
    private(set) var reloadRevision = 0
    var isSaving: Bool { phase == .saving }
    /// The form waits while a save runs and while 没有保存成功 / 结果未确认 is open: 重试 and 刷新核对 go on with the save as it
    /// was sent and close the sheet, so nothing typed meanwhile may be left out of it.
    var locksForm: Bool { phase == .saving || phase == .notApplied || phase == .unconfirmed }

    @ObservationIgnored private let source: any AccountPatchSource
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let onChange: @MainActor (AccountEditBase) -> Void
    @ObservationIgnored private let onRemoved: @MainActor () -> Void
    @ObservationIgnored private let onReload: @MainActor () -> Void
    @ObservationIgnored private let makeKey: @MainActor () -> UUID
    @ObservationIgnored private var pending: Pending?
    private static let log = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "accounts")

    /// The user's save: what it changes, its receipt, the session it was made in, and its latest send.
    private struct Pending {
        let change: AccountEditChange
        var attempt: AccountPatchAttempt
        let receipt: ReceiptMaker?
        let session: AccountWriteSession
    }

    init(source: any AccountPatchSource, receipts: ReceiptCenter, accountID: Int, onChange: @escaping @MainActor (AccountEditBase) -> Void,
         onRemoved: @escaping @MainActor () -> Void, onReload: @escaping @MainActor () -> Void,
         makeKey: @escaping @MainActor () -> UUID = { UUID() }) {
        self.source = source; self.receipts = receipts; self.accountID = accountID; self.onChange = onChange; self.onRemoved = onRemoved
        self.onReload = onReload; self.makeKey = makeKey
    }

    // MARK: - Entries

    /// `receipt` replaces the standard “已保存：…” + 撤销; returning nil shows none. Nothing is sent with a read-only token.
    @discardableResult
    func save(_ change: AccountEditChange, base: AccountEditBase, receipt: ReceiptMaker? = nil) async -> AccountEditBase? {
        guard !isSaving, let session = source.accountWriteSession else { return nil }
        guard !session.isReadOnlyToken else { phase = .failed(AccountActionCopy.readOnly.text); return nil }
        prompt = nil
        // A save the security sheet cleared goes again under its key (00 §2.6.2 step 4).
        let attempt = reconfirmedAttempt(for: change) ?? AccountPatchAttempt(accountID: accountID, base: base, request: change.request,
                                                                             idempotencyKey: usesPatch(base, session) ? nil : newKey(session))
        pending = Pending(change: change, attempt: attempt, receipt: receipt, session: session)
        return await run { await self.submit(attempt, session: session) }
    }
    /// 用我的修改覆盖: the same request with the server's version, not resent silently again.
    func overwrite() async {
        guard case .overwrite(let attempt, let current, let tag)? = prompt, let pending else { return }
        prompt = nil
        let next = current.map(attempt.overwriting(current:)) ?? tag.map(attempt.overwriting(etag:)) ?? attempt
        _ = await run { await self.send(next, session: pending.session, mayResend: false) }
    }
    /// 重新载入: the sheet stays open on the server's copy (read again when the conflict could not read it).
    func reloadAfterConflict() async {
        guard case .overwrite(_, let current, _)? = prompt, let session = pending?.session else { return }
        prompt = nil
        if let current { reloaded(current); return }
        phase = .saving
        do {
            let fresh = try await source.accountWithVersion(id: accountID)
            guard isCurrent(session) else { phase = .idle; return }
            reloaded(AccountEditBase(fresh))
        } catch {
            guard isCurrent(session) else { phase = .idle; return }
            _ = finish(AccountPatchFailure(error) == .removed ? .removed : .failed(AccountEditCopy.reloadFailed))
        }
    }
    /// 继续保存: the request with `confirm_mixed_channel_risk`, same If-Match; a keyed PUT under a new key.
    func confirmMixedChannel() async {
        guard case .mixedChannel(let attempt, _)? = prompt, let pending else { return }
        prompt = nil
        let next = attempt.confirmingMixedChannel(idempotencyKey: attempt.idempotencyKey == nil ? nil : makeKey())
        _ = await run { await self.send(next, session: pending.session, mayResend: true) }
    }
    /// 取消 on the mixed-channel question: the sheet keeps its draft.
    func dismissPrompt() { prompt = nil }
    /// 重试 after 没有保存成功: the same send (same If-Match, or same key and base).
    func retry() async {
        guard phase == .notApplied, let pending else { return }
        _ = await run { await self.send(pending.attempt, session: pending.session, mayResend: true) }
    }
    /// 刷新核对 after 结果未确认: read back once more.
    func recheck() async {
        guard phase == .unconfirmed, let pending else { return }
        _ = await run { await self.readBack(pending.attempt, session: pending.session) }
    }
    func reset() {
        phase = .idle; prompt = nil; pending = nil
    }

    // MARK: - Steps

    private func run(_ body: () async -> AccountPatchStep) async -> AccountEditBase? {
        phase = .saving
        return finish(await body())
    }
    private func finish(_ step: AccountPatchStep) -> AccountEditBase? {
        phase = .idle
        switch step {
        case .saved(let saved):
            guard let done = pending else { return nil }
            pending = nil; prompt = nil
            onChange(saved)
            savedRevision += 1
            announce(done, saved: saved)
            return saved
        case .askOverwrite(let attempt, let current, let tag):
            pending?.attempt = attempt
            if let current { onChange(current) }
            prompt = .overwrite(attempt, current: current, currentETag: tag)
        case .askMixedChannel(let attempt, let warning):
            pending?.attempt = attempt
            prompt = .mixedChannel(attempt, warning)
        case .notApplied(let attempt): pending?.attempt = attempt; phase = .notApplied
        case .unconfirmed(let attempt): pending?.attempt = attempt; phase = .unconfirmed
        case .reconfirm(let text): phase = .reconfirm(text)
        case .needsWeb(let text): phase = .needsWeb(text)
        case .failed(let text): phase = .failed(text)
        case .removed:
            pending = nil
            phase = .failed(AccountActionCopy.missingReason)
            onRemoved()
        case .cancelled: pending = nil
        }
        return nil
    }
    private func submit(_ attempt: AccountPatchAttempt, session: AccountWriteSession) async -> AccountPatchStep {
        if attempt.needsMixedChannelPrecheck(hasDetailsCapability: source.hasMixedChannelDetails),
           let asked = await precheck(attempt, session: session) {
            return asked
        }
        return await send(attempt, session: session, mayResend: true)
    }
    /// nil: no risk, go ahead.
    private func precheck(_ attempt: AccountPatchAttempt, session: AccountWriteSession) async -> AccountPatchStep? {
        do {
            let check = try await source.checkMixedChannel(platform: attempt.base.account.platform, groupIDs: attempt.request.groupIDs ?? [],
                                                           accountID: attempt.accountID, generation: session.generation)
            guard isCurrent(session) else { return .cancelled }
            return MixedChannelWarning(check: check).map { .askMixedChannel(attempt, $0) }
        } catch {
            guard isCurrent(session) else { return .cancelled }
            switch AccountPatchFailure(error) {
            case .cancelled: return .cancelled
            case .reconfirm(let text): return .reconfirm(text)
            case .removed: return .removed
            default: return .failed(AccountActionCopy.reason(for: error))
            }
        }
    }
    private func send(_ attempt: AccountPatchAttempt, session: AccountWriteSession, mayResend: Bool) async -> AccountPatchStep {
        do {
            let saved = try await write(attempt, session: session)
            return isCurrent(session) ? .saved(saved) : .cancelled
        } catch {
            guard isCurrent(session) else { return .cancelled }
            return await settle(error, attempt: attempt, session: session, mayResend: mayResend)
        }
    }
    private func write(_ attempt: AccountPatchAttempt, session: AccountWriteSession) async throws -> AccountEditBase {
        if session.patch, let tag = attempt.ifMatch {
            return AccountEditBase(try await source.patchAccount(id: attempt.accountID, body: attempt.request, ifMatch: tag, generation: session.generation))
        }
        let account = try await source.fullUpdateAccount(id: attempt.accountID, patch: attempt.request, base: attempt.base.account,
                                                         idempotencyKey: attempt.idempotencyKey, generation: session.generation)
        return AccountEditBase(account: account, etag: nil)
    }
    private func settle(_ error: any Error, attempt: AccountPatchAttempt, session: AccountWriteSession, mayResend: Bool) async -> AccountPatchStep {
        switch AccountPatchFailure(error) {
        case .versionConflict(let tag): return await resolveConflict(attempt, currentETag: tag, session: session, mayResend: mayResend)
        case .mixedChannel(let warning?): return .askMixedChannel(attempt, warning)
        case .mixedChannel(nil): return await precheck(attempt, session: session) ?? .failed(AccountActionCopy.reason(for: error))
        case .rejected(let reason):
            logRejected(error)
            return .failed(AccountEditCopy.rejected(reason: reason))
        case .removed: return .removed
        case .unknownResult: return await readBack(attempt, session: session)
        case .reconfirm(let text): return .reconfirm(text)
        case .needsWeb(let text): return .needsWeb(text)
        case .refused(let text): return .failed(text)
        case .cancelled: return .cancelled
        }
    }
    /// 20 §0.4-6 on the fresh `GET :id`: already written → done; only untouched fields moved → resend once with its version;
    /// a third value → ask. When the read fails the question carries `metadata.current_etag`.
    private func resolveConflict(_ attempt: AccountPatchAttempt, currentETag: String?, session: AccountWriteSession,
                                 mayResend: Bool) async -> AccountPatchStep {
        let fresh: VersionedAccount
        do {
            fresh = try await source.accountWithVersion(id: attempt.accountID)
        } catch {
            guard isCurrent(session) else { return .cancelled }
            return AccountPatchFailure(error) == .removed ? .removed : .askOverwrite(attempt, current: nil, currentETag: currentETag)
        }
        guard isCurrent(session) else { return .cancelled }
        let current = AccountEditBase(account: fresh.account, etag: fresh.etag ?? currentETag)
        switch AccountPatchConflict.resolve(base: attempt.base.account, current: fresh.account, request: attempt.request) {
        case .alreadyApplied: return .saved(current)
        case .silentRetry where mayResend && current.etag != nil:
            return await send(attempt.overwriting(current: current), session: session, mayResend: false)
        case .silentRetry, .askUser: return .askOverwrite(attempt, current: current, currentETag: current.etag)
        }
    }
    /// 20 §0.4-5: the fields (or, for a new secret, the version) decide; the page shows what was read either way.
    private func readBack(_ attempt: AccountPatchAttempt, session: AccountWriteSession) async -> AccountPatchStep {
        do {
            let fresh = try await source.accountWithVersion(id: attempt.accountID)
            guard isCurrent(session) else { return .cancelled }
            switch AccountPatchReadbackVerdict.evaluate(attempt: attempt, current: fresh) {
            case .applied: return .saved(AccountEditBase(fresh))
            case .notApplied: onChange(AccountEditBase(fresh)); return .notApplied(attempt)
            case .unconfirmed: onChange(AccountEditBase(fresh)); return .unconfirmed(attempt)
            }
        } catch {
            guard isCurrent(session) else { return .cancelled }
            switch AccountPatchFailure(error) {
            case .removed: return .removed
            case .cancelled: return .cancelled
            default: return .unconfirmed(attempt)
            }
        }
    }
    private func reloaded(_ base: AccountEditBase) {
        pending = nil
        phase = .idle
        onChange(base)
        reloadedBase = base
        reloadRevision += 1
    }

    // MARK: - Receipt and undo

    private func announce(_ done: Pending, saved: AccountEditBase) {
        if let receipt = done.receipt {
            if let made = receipt(saved) { receipts.show(made) }
            return
        }
        let session = done.session
        var undo: (@MainActor @Sendable () -> Void)?
        if let request = done.change.undo {
            undo = { self.startUndo(request, saved: saved, session: session) }
        }
        receipts.show(Receipt(text: AccountEditCopy.savedReceipt(done.change.fieldNames), undo: undo))
    }
    private func startUndo(_ request: AccountPatchRequest, saved: AccountEditBase, session: AccountWriteSession) {
        Task { await self.undo(request, saved: saved, session: session) }
    }
    /// 撤销 writes the old values with this save's version (20 §3.4): never resent silently, never confirming a mixed channel.
    /// Done says nothing more; a 412 offers 重新载入; an unknown result is read back.
    func undo(_ request: AccountPatchRequest, saved: AccountEditBase, session: AccountWriteSession) async {
        guard isCurrent(session) else { return }
        let attempt = AccountPatchAttempt(accountID: accountID, base: saved, request: request,
                                          idempotencyKey: usesPatch(saved, session) ? nil : newKey(session))
        do {
            let reverted = try await write(attempt, session: session)
            if isCurrent(session) { onChange(reverted) }
        } catch {
            guard isCurrent(session) else { return }
            await undoFailed(error, attempt: attempt, session: session)
        }
    }
    private func undoFailed(_ error: any Error, attempt: AccountPatchAttempt, session: AccountWriteSession) async {
        switch AccountPatchFailure(error) {
        case .cancelled: return
        case .removed: onRemoved()
        case .versionConflict: showUndoProblem(AccountEditCopy.undoConflict)
        case .unknownResult:
            switch await readBack(attempt, session: session) {
            case .saved(let fresh): onChange(fresh)
            case .cancelled: return
            case .removed: onRemoved()
            default: showUndoProblem(AccountEditCopy.unconfirmed)
            }
        case .rejected(let reason):
            logRejected(error)
            showUndoProblem(AccountEditCopy.undoFailed(AccountEditCopy.rejected(reason: reason)), reload: false)
        case .mixedChannel: showUndoProblem(AccountEditCopy.undoFailed(AccountActionCopy.reason(for: error)), reload: false)
        case .reconfirm(let text), .needsWeb(let text), .refused(let text): showUndoProblem(AccountEditCopy.undoFailed(text), reload: false)
        }
    }
    private func showUndoProblem(_ text: String, reload: Bool = true) {
        let action = reload ? ReceiptAction(title: AccountEditCopy.reload) { self.onReload() } : nil
        receipts.show(Receipt(text: text, systemImage: "exclamationmark.triangle", tone: reload ? .caution : .critical, action: action))
    }

    // MARK: - Helpers

    private func reconfirmedAttempt(for change: AccountEditChange) -> AccountPatchAttempt? {
        guard case .reconfirm = phase, let pending, pending.change.request == change.request else { return nil }
        return pending.attempt
    }
    private func usesPatch(_ base: AccountEditBase, _ session: AccountWriteSession) -> Bool { session.patch && base.etag != nil }
    private func newKey(_ session: AccountWriteSession) -> UUID? { session.idempotentWrites ? makeKey() : nil }
    private func isCurrent(_ session: AccountWriteSession) -> Bool { source.accountWriteSession?.generation == session.generation }
    /// 20 §0.5: a PATCH the App built wrongly; only the status, reason and request ID are logged (00 §3.4).
    private func logRejected(_ error: any Error) {
        guard let api = error as? APIError, AccountWriteReason.isRejectedPatch(api) else { return }
        let requestID = String((api.requestID ?? "-").prefix(64))
        Self.log.error("PATCH admin/accounts/:id \(api.statusCode ?? 0, privacy: .public) \(api.reason ?? "-", privacy: .public) \(requestID, privacy: .public)")
    }
}
