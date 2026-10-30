import Foundation
import Observation
import Sub2Core

/// What 重新授权 needs (AppModel+Accounts). Every write carries the generation of the session the user tapped in (S2D1-05).
@MainActor protocol AccountReauthorizeSource: OAuthLinkSource {
    func serverNow() -> Date
    func reauthorizeAccount(id: Int, request: AccountReauthorizeRequest, generation: UUID) async throws -> UpstreamAccount
    func exchangeOAuthCode(_ link: OAuthLink, code: OAuthCode, proxyID: Int?, generation: UUID) async throws -> OAuthTokenInfo
    func applyOAuthCredentials(accountID: Int, type: OAuthAuthKind, credentials: [String: JSONValue], extra: [String: JSONValue]?,
                               generation: UUID) async throws -> UpstreamAccount
    func accountWithVersion(id: Int) async throws -> VersionedAccount
}

struct AccountReauthResult: Sendable {
    let account: UpstreamAccount
    /// Only when a read-back confirmed the save: the account with its ETag.
    let version: VersionedAccount?
    let receipt: AccountCredentialReceipt
}

enum AccountReauthOutcome: Sendable, Equatable {
    case succeeded(AccountReauthResult)
    /// Shown under its step of the list.
    case stepError(AccountOAuthErrorCopy)
    /// The reauthorizer's `notice` says what happened.
    case notice
    /// 404: the sheet closes and the detail shows 已删除.
    case missing
    /// Face ID refused, the session changed or a read-only token: nothing more was sent and nothing is shown.
    case cancelled

    static func == (lhs: AccountReauthOutcome, rhs: AccountReauthOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.succeeded(let left), .succeeded(let right)):
            left.account.id == right.account.id && left.receipt == right.receipt && left.version?.etag == right.version?.etag
        case (.stepError(let left), .stepError(let right)): left == right
        case (.notice, .notice), (.missing, .missing), (.cancelled, .cancelled): true
        default: false
        }
    }
}

/// 20 §6.2–§6.5 one 替换令牌: Face ID first (60 §3.4), then `reauthorize` (the token stays on the server), or without
/// accounts.reauthorize exchange-code → OAuthCredentialBuilder → apply-oauth-credentials, the token held here until it is saved.
/// Nothing is sent again by itself (00 §2.4): REAUTH_PERSIST_FAILED and an unanswered request read the account back, and only
/// the user's 重试保存 / 重试 sends the same body (or the same token) again, without another Face ID check; while either is held a
/// new 替换令牌 is refused, so the fallback's code, spent by the exchange, is never sent again. A result that arrives after the
/// session changed is dropped.
@MainActor @Observable
final class AccountReauthorizer {
    enum Phase: Sendable, Equatable { case idle, verifying, submitting, readingBack }
    enum Notice: Sendable, Equatable {
        /// The token was not saved: 重试保存 while the window lasts, then 重新授权.
        case persistFailed
        /// No answer and the read-back cannot tell: 重试.
        case unconfirmed
        /// NOT_OAUTH / REAUTH_UNSUPPORTED: 在 Web 中编辑.
        case unsupported(String)
        case failed(String)
        /// The security sheet cleared the request (00 §2.6.2): 替换令牌 again, or 重试 with the fallback's token still held.
        case reconfirm(String)
    }
    private enum Pending: Sendable {
        case reauthorize(AccountReauthorizeRequest)
        case apply(OAuthCredentials)
    }
    private enum RetryWindow: Sendable { case closed, open, until(ContinuousClock.Instant) }
    private struct Attempt: Sendable {
        let session: AccountOAuthSession
        let platform: OAuthPlatform
        let switchedTo: OAuthAuthKind?
    }
    private static let persistFailedReason = "REAUTH_PERSIST_FAILED"

    let account: UpstreamAccount
    private(set) var phase: Phase = .idle
    private(set) var notice: Notice?
    @ObservationIgnored private let source: any AccountReauthorizeSource
    @ObservationIgnored private let gate: BiometricGate
    @ObservationIgnored private let monotonicNow: @MainActor () -> ContinuousClock.Instant
    @ObservationIgnored private var pending: Pending?
    @ObservationIgnored private var attempt: Attempt?
    @ObservationIgnored private var window: RetryWindow = .closed

    init(account: UpstreamAccount, source: any AccountReauthorizeSource, gate: BiometricGate,
         monotonicNow: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.account = account; self.source = source; self.gate = gate; self.monotonicNow = monotonicNow
    }

    var isBusy: Bool { phase != .idle }
    /// The request body or the token kept for 重试; neither is ever printed.
    var hasHeldCredentials: Bool { pending != nil }
    var verifiesWithFaceID: Bool { gate.needsVerification(.replaceCredential) }
    var now: ContinuousClock.Instant { monotonicNow() }
    func canRetry(at instant: ContinuousClock.Instant) -> Bool {
        guard pending != nil else { return false }
        switch (notice, window) {
        case (.unconfirmed?, _), (.reconfirm?, _), (.persistFailed?, .open): return true
        case (.persistFailed?, .until(let end)): return instant < end
        default: return false
        }
    }

    func submit(_ submission: OAuthSubmission, switchedTo: OAuthAuthKind?) async -> AccountReauthOutcome {
        guard phase == .idle, pending == nil, let session = source.oauthSession, !session.isReadOnlyToken else { return .cancelled }
        discard()
        notice = nil
        phase = .verifying
        let allowed = await gate.authorize(.replaceCredential)
        guard allowed, isCurrent(session) else { return dropped() }
        let attempt = Attempt(session: session, platform: submission.link.platform, switchedTo: switchedTo)
        self.attempt = attempt
        guard session.reauthorizeEndpoint else { return await exchange(submission, attempt) }
        do { pending = .reauthorize(try AccountReauthorizeRequest(link: submission.link, code: submission.code)) }
        catch { return stepped(Self.localError(error)) }
        return await send(attempt)
    }
    /// 重试保存 / 重试: the same body, or the same token, in the session it was made in.
    func retry() async -> AccountReauthOutcome {
        guard phase == .idle, let attempt, canRetry(at: monotonicNow()) else { return .cancelled }
        guard isCurrent(attempt.session) else { return dropped() }
        notice = nil
        return await send(attempt)
    }
    /// The sheet closed, or the list went back to step 1: the held body and token go.
    func discard() {
        pending = nil
        attempt = nil
        window = .closed
    }
    /// 重新授权 after the save window ran out: a new link, a new code and a new 替换令牌.
    func restart() {
        guard phase == .idle else { return }
        discard()
        notice = nil
    }

    // MARK: Sending

    private func exchange(_ submission: OAuthSubmission, _ attempt: Attempt) async -> AccountReauthOutcome {
        phase = .submitting
        let token: OAuthTokenInfo
        do {
            token = try await source.exchangeOAuthCode(submission.link, code: submission.code, proxyID: submission.proxyID,
                                                       generation: attempt.session.generation)
        } catch {
            guard isCurrent(attempt.session) else { return dropped() }
            return exchangeFailed(error, attempt)
        }
        guard isCurrent(attempt.session) else { return dropped() }
        pending = .apply(OAuthCredentialBuilder.build(token))
        return await send(attempt)
    }
    private func send(_ attempt: Attempt) async -> AccountReauthOutcome {
        guard let pending else { return .cancelled }
        phase = .submitting
        let startedAt = source.serverNow(), generation = attempt.session.generation
        do {
            let updated: UpstreamAccount
            switch pending {
            case .reauthorize(let request):
                updated = try await source.reauthorizeAccount(id: account.id, request: request, generation: generation)
            case .apply(let saved):
                updated = try await source.applyOAuthCredentials(accountID: account.id, type: saved.type, credentials: saved.credentials,
                                                                 extra: saved.extra, generation: generation)
            }
            guard isCurrent(attempt.session) else { return dropped() }
            return succeeded(updated, version: nil, attempt)
        } catch {
            guard isCurrent(attempt.session) else { return dropped() }
            return await settle(error, applying: Self.isApply(pending), attempt, startedAt: startedAt)
        }
    }

    // MARK: Failures (20 §0.5)

    private func settle(_ error: any Error, applying: Bool, _ attempt: Attempt, startedAt: Date) async -> AccountReauthOutcome {
        let api = error as? APIError
        let copy = api.flatMap {
            AccountOAuthErrorCopy.resolve($0, flow: applying ? .apply : .reauthorize, platform: attempt.platform, reasonsSupported: attempt.session.errorReasons)
        }
        if api?.statusCode == 500, api?.reason == Self.persistFailedReason {
            let window = copy?.retryWindow.map { RetryWindow.until(monotonicNow() + $0) } ?? .closed
            return await readBack(holding: .persistFailed, window: window, attempt, startedAt: startedAt)
        }
        if Self.isMissing(api, applying: applying) { return gone() }
        let disposition = AccountActionCopy.disposition(of: error)
        switch disposition {
        case .cancelled: return dropped()
        case .reconfirm:
            // The fallback's token stays: 重试 saves it without spending the code again (20 §6.2).
            let notice = Notice.reconfirm(error.localizedDescription)
            return applying ? hold(notice, .open) : show(notice)
        default: break
        }
        if let copy {
            if copy.remedies.contains(.editInWeb) { return show(.unsupported(copy.message)) }
            if !applying { return stepped(copy) }
        }
        if disposition == .readBack { return await readBack(holding: .unconfirmed, window: .open, attempt, startedAt: startedAt) }
        // The fallback's token is still here: saving it again needs no new code.
        if applying { return await readBack(holding: .persistFailed, window: .open, attempt, startedAt: startedAt) }
        return show(.failed(AccountReauthorizePresentation.failure(reason: AccountActionCopy.reason(for: error))))
    }
    private func exchangeFailed(_ error: any Error, _ attempt: Attempt) -> AccountReauthOutcome {
        switch AccountActionCopy.disposition(of: error) {
        case .cancelled: return dropped()
        case .reconfirm: return show(.reconfirm(error.localizedDescription))
        default: break
        }
        let copy = (error as? APIError).flatMap {
            AccountOAuthErrorCopy.resolve($0, flow: .exchange, platform: attempt.platform, reasonsSupported: attempt.session.errorReasons)
        }
        if let copy { return copy.remedies.contains(.editInWeb) ? show(.unsupported(copy.message)) : stepped(copy) }
        if (error as? APIError)?.kind == .validation { return stepped(Self.localError(error)) }
        return show(.failed(AccountReauthorizePresentation.failure(reason: AccountActionCopy.reason(for: error))))
    }
    /// 20 §6.5: saved when `token_status.refreshed_at` is from this send (AccountTokenReadback allows for whole seconds). The
    /// account the sheet opened with is not the value before the send: the server may have refreshed the old token since.
    private func readBack(holding notice: Notice, window: RetryWindow, _ attempt: Attempt, startedAt: Date) async -> AccountReauthOutcome {
        phase = .readingBack
        let fresh: VersionedAccount
        do {
            fresh = try await source.accountWithVersion(id: account.id)
        } catch {
            guard isCurrent(attempt.session), !(error is CancellationError) else { return dropped() }
            if AccountDetailPresentation.isRemoved(error) { return gone() }
            return hold(notice, window)
        }
        guard isCurrent(attempt.session) else { return dropped() }
        guard AccountTokenReadback.check(fresh.account, since: startedAt) == .replaced else { return hold(notice, window) }
        return succeeded(fresh.account, version: fresh, attempt)
    }

    // MARK: Endings

    private func succeeded(_ updated: UpstreamAccount, version: VersionedAccount?, _ attempt: Attempt) -> AccountReauthOutcome {
        let receipt = AccountCredentialCopy.reauthorizeReceipt(before: account, after: updated, switchedTo: attempt.switchedTo, now: source.serverNow())
        end()
        return .succeeded(AccountReauthResult(account: updated, version: version, receipt: receipt))
    }
    private func hold(_ notice: Notice, _ window: RetryWindow) -> AccountReauthOutcome {
        self.window = window
        phase = .idle
        self.notice = notice
        return .notice
    }
    private func show(_ notice: Notice) -> AccountReauthOutcome {
        end()
        self.notice = notice
        return .notice
    }
    private func stepped(_ copy: AccountOAuthErrorCopy) -> AccountReauthOutcome {
        end()
        return .stepError(copy)
    }
    private func gone() -> AccountReauthOutcome {
        end()
        return .missing
    }
    private func dropped() -> AccountReauthOutcome {
        end()
        return .cancelled
    }
    private func end() {
        discard()
        phase = .idle
    }

    private func isCurrent(_ session: AccountOAuthSession) -> Bool { source.oauthSession?.generation == session.generation }
    private static func isApply(_ pending: Pending) -> Bool {
        if case .apply = pending { return true }
        return false
    }
    /// 404 ACCOUNT_NOT_FOUND; apply-oauth-credentials answers a missing account with a 404 without reason.
    private static func isMissing(_ error: APIError?, applying: Bool) -> Bool {
        guard let error, error.statusCode == 404 else { return false }
        return error.reason == AccountWriteReason.notFound || (applying && AccountRefreshCopy.isMissing(error))
    }
    /// A body the App could not build (no state for a platform that checks one): nothing was sent.
    private static func localError(_ error: any Error) -> AccountOAuthErrorCopy {
        AccountOAuthErrorCopy(message: error.localizedDescription, step: .code, remedies: [])
    }
}
