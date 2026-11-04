import Foundation
import Observation
import Sub2Core

/// The detail's writes beyond AccountWriteSource (AppModel+Accounts): each carries the generation of the session the user acted
/// in (S2D1-05) and throws CancellationError once that session is gone.
@MainActor protocol AccountDetailWriteSource: AnyObject {
    var accountWriteSession: AccountWriteSession? { get }
    func accountWithVersion(id: Int) async throws -> VersionedAccount
    func revertAccountProxyFallback(id: Int, generation: UUID) async throws
    func deleteAccount(id: Int, generation: UUID) async throws -> DeleteResult
}

enum AccountProxyRevertOutcome: Equatable, Sendable { case reverted, notInFallback, originUnavailable, unconfirmed, missing, reconfirm, failed, ignored }

/// 20 §3.4 恢复原代理, after the caller's confirmation: POST, then `GET :id` for the account and its version (the reply has
/// none), the receipt without 撤销, and the list read again. ACCOUNT_NOT_IN_FALLBACK reads the account too; PROXY_FALLBACK_ORIGIN_
/// UNAVAILABLE offers 查看原代理. An unanswered POST is read back and never resent on its own: 重试 is the user's (sending it again
/// is safe, the server then says the account is no longer fallen back). A result after the session changed is dropped.
@MainActor @Observable
final class AccountProxyRevert {
    private(set) var runningAccountID: Int?
    var isRunning: Bool { runningAccountID != nil }

    @ObservationIgnored private let source: any AccountDetailWriteSource
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let onAccount: @MainActor (VersionedAccount) -> Void
    @ObservationIgnored private let onStale: @MainActor () -> Void
    @ObservationIgnored private let onListChanged: @MainActor () -> Void

    init(source: any AccountDetailWriteSource, receipts: ReceiptCenter, onAccount: @escaping @MainActor (VersionedAccount) -> Void,
         onStale: @escaping @MainActor () -> Void, onListChanged: @escaping @MainActor () -> Void) {
        self.source = source; self.receipts = receipts; self.onAccount = onAccount; self.onStale = onStale; self.onListChanged = onListChanged
    }

    /// Nothing for an account that is not fallen back, or while another revert runs; a read-only token is told so. `openOrigin`
    /// is 查看原代理's push.
    @discardableResult
    func revert(_ account: UpstreamAccount, openOrigin: @escaping @MainActor @Sendable (Int) -> Void) async -> AccountProxyRevertOutcome {
        let attempt = Attempt(account: account, openOrigin: openOrigin)
        guard runningAccountID == nil, let originID = account.proxyFallbackOriginID, let session = source.accountWriteSession,
              let origin = AccountProxyPresentation.originName(account) else { return .ignored }
        guard !session.isReadOnlyToken else { show(AccountActionCopy.readOnly.text, tone: .critical); return .failed }
        runningAccountID = account.id
        defer { runningAccountID = nil }
        do {
            try await source.revertAccountProxyFallback(id: account.id, generation: session.generation)
            guard isCurrent(session) else { return .ignored }
            await readAccount(account.id, session: session)
            return succeeded(origin, session: session)
        } catch {
            guard isCurrent(session) else { return .ignored }
            return await settle(error, attempt: attempt, originID: originID, origin: origin, session: session)
        }
    }

    /// What 重试 sends again.
    private struct Attempt: Sendable {
        let account: UpstreamAccount
        let openOrigin: @MainActor @Sendable (Int) -> Void
    }

    private func settle(_ error: any Error, attempt: Attempt, originID: Int, origin: String,
                        session: AccountWriteSession) async -> AccountProxyRevertOutcome {
        let account = attempt.account
        if let api = error as? APIError, api.statusCode == 400, api.reason == AccountWriteReason.notInFallback {
            await readAccount(account.id, session: session)
            guard isCurrent(session) else { return .ignored }
            onListChanged()
            show(AccountProxyCopy.notInFallback, systemImage: "info.circle", tone: .neutral)
            return .notInFallback
        }
        if let api = error as? APIError, api.statusCode == 409, api.reason == AccountWriteReason.fallbackOriginUnavailable {
            let open = attempt.openOrigin
            show(AccountProxyCopy.originUnavailable, tone: .caution, action: ReceiptAction(title: AccountProxyCopy.viewOrigin) { open(originID) })
            return .originUnavailable
        }
        switch AccountActionCopy.disposition(of: error) {
        case .cancelled: return .ignored
        case .reconfirm:
            show(AccountActionCopy.reconfirm(error).text, tone: .caution, action: retry(attempt))
            return .reconfirm
        case .missing: return missing()
        case .readBack: return await verify(attempt, originID: originID, origin: origin, session: session)
        case .versionConflict, .failed:
            show(AccountProxyCopy.revertFailed(reason: AccountActionCopy.reason(for: error)), tone: .critical)
            return .failed
        }
    }
    /// 00 §2.4: the account decides whether the POST ran.
    private func verify(_ attempt: Attempt, originID: Int, origin: String, session: AccountWriteSession) async -> AccountProxyRevertOutcome {
        let account = attempt.account
        do {
            let fresh = try await source.accountWithVersion(id: account.id)
            guard isCurrent(session) else { return .ignored }
            onAccount(fresh)
            if AccountWriteCheck.proxyReverted(fresh.account, toOrigin: originID) { return succeeded(origin, session: session) }
        } catch {
            guard isCurrent(session) else { return .ignored }
            switch AccountActionCopy.disposition(of: error) {
            case .cancelled: return .ignored
            case .missing: return missing()
            default: break
            }
        }
        show(AccountProxyCopy.unconfirmed, tone: .caution, action: retry(attempt))
        return .unconfirmed
    }
    private func succeeded(_ origin: String, session: AccountWriteSession) -> AccountProxyRevertOutcome {
        guard isCurrent(session) else { return .ignored }
        onListChanged()
        show(AccountProxyCopy.reverted(origin), systemImage: "checkmark.circle", tone: .ok)
        return .reverted
    }
    private func missing() -> AccountProxyRevertOutcome {
        onStale()
        show(AccountProxyCopy.revertFailed(reason: AccountActionCopy.missingReason), tone: .critical)
        return .missing
    }
    /// The page takes the fresh account; when it cannot be read the page loads again.
    private func readAccount(_ id: Int, session: AccountWriteSession) async {
        do {
            let fresh = try await source.accountWithVersion(id: id)
            if isCurrent(session) { onAccount(fresh) }
        } catch {
            if isCurrent(session) { onStale() }
        }
    }
    private func retry(_ attempt: Attempt) -> ReceiptAction {
        ReceiptAction(title: AccountReceiptButton.retry.title) { Task { await self.revert(attempt.account, openOrigin: attempt.openOrigin) } }
    }
    private func show(_ text: String, systemImage: String = "exclamationmark.triangle", tone: Tone, action: ReceiptAction? = nil) {
        receipts.show(Receipt(text: text, systemImage: systemImage, tone: tone, action: action))
    }
    private func isCurrent(_ session: AccountWriteSession) -> Bool { source.accountWriteSession?.generation == session.generation }
}

enum AccountDeleteOutcome: Equatable, Sendable { case deleted, failed, unconfirmed, ignored }

/// 20 §3.4 删除账号…, after the delete confirmation: one DELETE. Deleted, or already gone, → `onDeleted` (the page pops and the
/// list reloads) and then “已删除账号「X」”. An unanswered DELETE is never resent: `GET :id` decides, a 404 meaning deleted. Any
/// other failure says why and leaves the page as it was.
@MainActor
final class AccountDeleteFlow {
    private let source: any AccountDetailWriteSource
    private let receipts: ReceiptCenter

    init(source: any AccountDetailWriteSource, receipts: ReceiptCenter) { self.source = source; self.receipts = receipts }

    @discardableResult
    func delete(_ account: UpstreamAccount, onDeleted: @escaping @MainActor () -> Void) async -> AccountDeleteOutcome {
        guard let session = source.accountWriteSession else { return .ignored }
        guard !session.isReadOnlyToken else { failed(AccountActionCopy.readOnly.text); return .failed }
        do {
            _ = try await source.deleteAccount(id: account.id, generation: session.generation)
            guard isCurrent(session) else { return .ignored }
            return deleted(account, onDeleted)
        } catch {
            guard isCurrent(session) else { return .ignored }
            switch AccountActionCopy.disposition(of: error) {
            case .cancelled: return .ignored
            case .missing: return deleted(account, onDeleted)
            case .readBack: return await verify(account, after: error, session: session, onDeleted: onDeleted)
            case .reconfirm:
                // 00 §2.6.2 step 4: the security sheet cleared it; deleting again from ⋯ is the second confirmation.
                receipts.show(Receipt(text: AccountActionCopy.reconfirm(error).text, systemImage: "checkmark.shield", tone: .caution))
                return .failed
            case .versionConflict, .failed:
                failed(AccountDeletionCopy.failed(reason: AccountActionCopy.reason(for: error)))
                return .failed
            }
        }
    }

    private func verify(_ account: UpstreamAccount, after error: any Error, session: AccountWriteSession,
                        onDeleted: @escaping @MainActor () -> Void) async -> AccountDeleteOutcome {
        do {
            _ = try await source.accountWithVersion(id: account.id)
            guard isCurrent(session) else { return .ignored }
            failed(AccountDeletionCopy.failed(reason: AccountActionCopy.reason(for: error)))
            return .failed
        } catch let readError {
            guard isCurrent(session) else { return .ignored }
            switch AccountActionCopy.disposition(of: readError) {
            case .cancelled: return .ignored
            case .missing: return deleted(account, onDeleted)
            default:
                receipts.show(Receipt(text: AccountDeletionCopy.unconfirmed, systemImage: "exclamationmark.triangle", tone: .caution))
                return .unconfirmed
            }
        }
    }
    private func deleted(_ account: UpstreamAccount, _ onDeleted: @MainActor () -> Void) -> AccountDeleteOutcome {
        onDeleted()
        receipts.show(Receipt(text: AccountDeletionCopy.deleted(name: account.name), systemImage: "trash"))
        return .deleted
    }
    private func failed(_ text: String) {
        receipts.show(Receipt(text: text, systemImage: "exclamationmark.triangle", tone: .critical))
    }
    private func isCurrent(_ session: AccountWriteSession) -> Bool { source.accountWriteSession?.generation == session.generation }
}

/// 20 §3.4 删除账号 wording; the confirmation itself is DeleteConfirmationCopy's (S3-00).
enum AccountDeletionCopy {
    static let objectNoun = "账号"
    static func deleted(name: String) -> String { DeleteConfirmationCopy.deletedReceipt(objectNoun: objectNoun, displayName: name) }
    static func failed(reason: String) -> String { "删除没有成功：\(reason)" }
    static let unconfirmed = "删除结果未确认，请刷新核对后再操作"
}
