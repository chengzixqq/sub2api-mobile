import Foundation
import Observation
import Sub2Core

/// What 刷新令牌 needs (AppModel+Accounts). The refresh carries the generation of the session the user tapped in (S2D1-05).
@MainActor protocol AccountRefreshSource: AnyObject {
    var accountWriteSession: AccountWriteSession? { get }
    /// The server's zone, for the receipt's “HH:MM 到期”.
    var siteTimeZone: TimeZone { get }
    func serverNow() -> Date
    func refreshAccount(id: Int, idempotencyKey: UUID?, generation: UUID) async throws -> AccountRefreshResult
    func accountWithVersion(id: Int) async throws -> VersionedAccount
}

enum AccountTokenRefreshOutcome: Equatable, Sendable { case refreshed, unconfirmed, notApplied, reconfirm, missing, failed, ignored }

/// 20 §6.4 刷新令牌: sent at once (it cannot be undone, and asks nothing), with a key made at the tap when the site takes one
/// (R05). An unknown result is read back by `token_status.refreshed_at`: a keyed refresh may go again under its number (00
/// §2.5.4), an unkeyed one only on the user's 重试 (00 §2.4). The account the server returns or reads back goes to
/// `onChange`; one that is gone to `onMissing`. A result that arrives after the session changed is dropped.
@MainActor @Observable
final class AccountTokenRefresher {
    /// Accounts with a refresh running; another tap on them is ignored.
    private(set) var inFlight: Set<Int> = []
    @ObservationIgnored private let source: any AccountRefreshSource
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let onChange: @MainActor (UpstreamAccount) -> Void
    @ObservationIgnored private let onMissing: (@MainActor (Int) -> Void)?
    @ObservationIgnored private let makeKey: @MainActor () -> UUID
    /// Holds a same-number retry until the device time KeyedWriteFlow gave (00 §2.5.3).
    @ObservationIgnored private let waitUntil: @MainActor (Date) async throws -> Void

    init(source: any AccountRefreshSource, receipts: ReceiptCenter, onChange: @escaping @MainActor (UpstreamAccount) -> Void,
         onMissing: (@MainActor (Int) -> Void)? = nil, makeKey: @escaping @MainActor () -> UUID = { UUID() },
         waitUntil: @escaping @MainActor (Date) async throws -> Void = AccountActions.sleep(until:)) {
        self.source = source; self.receipts = receipts; self.onChange = onChange; self.onMissing = onMissing; self.makeKey = makeKey
        self.waitUntil = waitUntil
    }

    /// One user intent: the account and the key it keeps through same-number retries.
    private struct Attempt: Sendable {
        let id: Int
        let key: UUID?
    }

    func isRunning(_ accountID: Int) -> Bool { inFlight.contains(accountID) }

    @discardableResult
    func refresh(_ account: UpstreamAccount) async -> AccountTokenRefreshOutcome {
        guard !inFlight.contains(account.id), let session = source.accountWriteSession else { return .ignored }
        guard !session.isReadOnlyToken else { show(AccountActionCopy.readOnly.text, tone: .critical); return .failed }
        let attempt = Attempt(id: account.id, key: session.idempotentWrites ? makeKey() : nil)
        inFlight.insert(account.id)
        defer { inFlight.remove(account.id) }
        return await send(attempt, session: session)
    }

    /// A receipt's 重试, in the session the receipt belongs to; the receipt holds this refresher until it leaves.
    private func relaunch(_ attempt: Attempt, session: AccountWriteSession, notBefore: Date? = nil) {
        guard !inFlight.contains(attempt.id) else { return }
        inFlight.insert(attempt.id)
        Task {
            defer { self.inFlight.remove(attempt.id) }
            if let notBefore { do { try await self.waitUntil(notBefore) } catch { return } }
            _ = await self.send(attempt, session: session)
        }
    }

    private func send(_ attempt: Attempt, session: AccountWriteSession) async -> AccountTokenRefreshOutcome {
        let startedAt = source.serverNow()
        do {
            let result = try await source.refreshAccount(id: attempt.id, idempotencyKey: attempt.key, generation: session.generation)
            guard isCurrent(session) else { return .ignored }
            return refreshed(result)
        } catch {
            guard isCurrent(session) else { return .ignored }
            return await settle(error, attempt, session: session, startedAt: startedAt)
        }
    }
    private func refreshed(_ result: AccountRefreshResult) -> AccountTokenRefreshOutcome {
        onChange(result.account)
        receipts.show(Receipt(text: AccountCredentialCopy.refreshReceipt(result, timeZone: source.siteTimeZone), systemImage: "arrow.clockwise"))
        return .refreshed
    }

    private func settle(_ error: any Error, _ attempt: Attempt, session: AccountWriteSession, startedAt: Date) async -> AccountTokenRefreshOutcome {
        if AccountRefreshCopy.isMissing(error) { return gone(attempt.id, error: error) }
        switch AccountActionCopy.disposition(of: error) {
        case .cancelled: return .ignored
        case .reconfirm:
            show(error.localizedDescription, tone: .caution, retry: retry(attempt, session))
            return .reconfirm
        case .readBack: return await readBack(after: error, attempt, session: session, startedAt: startedAt)
        case .missing: return gone(attempt.id, error: error)
        case .versionConflict, .failed:
            showFailure(error)
            return .failed
        }
    }
    /// 20 §6.4: refreshed when `refreshed_at` is not older than the tap (AccountTokenReadback allows for whole seconds).
    private func readBack(after error: any Error, _ attempt: Attempt, session: AccountWriteSession, startedAt: Date) async -> AccountTokenRefreshOutcome {
        let fresh: VersionedAccount
        do {
            fresh = try await source.accountWithVersion(id: attempt.id)
        } catch {
            guard isCurrent(session) else { return .ignored }
            if error is CancellationError { return .ignored }
            if AccountRefreshCopy.isMissing(error) { return gone(attempt.id, error: error) }
            show(AccountActionCopy.unconfirmed, tone: .caution)
            return .unconfirmed
        }
        guard isCurrent(session) else { return .ignored }
        switch AccountTokenReadback.check(fresh.account, since: startedAt) {
        case .replaced: return refreshed(AccountRefreshResult(account: fresh.account))
        case .notReplaced: onChange(fresh.account); return notConfirmed(after: error, attempt, session: session)
        case .unknown:
            onChange(fresh.account)
            guard attempt.key != nil else { show(AccountActionCopy.unconfirmed, tone: .caution); return .unconfirmed }
            return notConfirmed(after: error, attempt, session: session)
        }
    }
    /// A keyed refresh goes again under its number (after 503 IDEMPOTENCY_STORE_UNAVAILABLE's cooldown); an unkeyed one is the
    /// user's to send again.
    private func notConfirmed(after error: any Error, _ attempt: Attempt, session: AccountWriteSession) -> AccountTokenRefreshOutcome {
        guard attempt.key != nil else {
            show(AccountRefreshCopy.notApplied, tone: .caution, retry: retry(attempt, session))
            return .notApplied
        }
        if let notBefore = AccountActionCopy.storeUnavailableUntil(error) {
            show(AccountRefreshCopy.storeUnavailable, tone: .caution, retry: retry(attempt, session, notBefore: notBefore))
            return .notApplied
        }
        show(AccountRefreshCopy.unconfirmedRetry, tone: .caution, retry: retry(attempt, session))
        return .unconfirmed
    }
    private func gone(_ id: Int, error: any Error) -> AccountTokenRefreshOutcome {
        onMissing?(id)
        showFailure(error)
        return .missing
    }

    private func retry(_ attempt: Attempt, _ session: AccountWriteSession, notBefore: Date? = nil) -> @MainActor @Sendable () -> Void {
        { self.relaunch(attempt, session: session, notBefore: notBefore) }
    }
    private func showFailure(_ error: any Error) {
        show(AccountRefreshCopy.failed(reason: AccountRefreshCopy.reason(for: error)), tone: .critical)
    }
    private func show(_ text: String, tone: Tone, retry: (@MainActor @Sendable () -> Void)? = nil) {
        receipts.show(Receipt(text: text, systemImage: "exclamationmark.triangle", tone: tone,
                              action: retry.map { ReceiptAction(title: AccountReceiptButton.retry.title, perform: $0) }))
    }
    private func isCurrent(_ session: AccountWriteSession) -> Bool { source.accountWriteSession?.generation == session.generation }
}
