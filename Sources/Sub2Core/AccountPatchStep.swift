import Foundation

/// An account with the version a PATCH sends back (20 §0.4-5): a sheet's base, or what a save returned.
public struct AccountEditBase: Sendable {
    public let account: UpstreamAccount
    /// cv-N; nil on a server without `accounts.patch`, which takes the PUT fallback.
    public let etag: String?
    public init(account: UpstreamAccount, etag: String?) { self.account = account; self.etag = etag }
    public init(_ versioned: VersionedAccount) { self.init(account: versioned.account, etag: versioned.etag) }
}

/// One send of a user's save: the request, the base the 412 comparison uses, the If-Match, and for the PUT fallback the key
/// made when the user saved (R05), kept through retries of the same body. Printing shows the account and key names only.
public struct AccountPatchAttempt: Sendable {
    public let accountID: Int
    public let base: AccountEditBase
    public let ifMatch: String?
    public let request: AccountPatchRequest
    public let idempotencyKey: UUID?

    public init(accountID: Int, base: AccountEditBase, request: AccountPatchRequest, idempotencyKey: UUID? = nil) {
        self.init(accountID: accountID, base: base, ifMatch: base.etag, request: request, idempotencyKey: idempotencyKey)
    }
    private init(accountID: Int, base: AccountEditBase, ifMatch: String?, request: AccountPatchRequest, idempotencyKey: UUID?) {
        self.accountID = accountID; self.base = base; self.ifMatch = ifMatch; self.request = request; self.idempotencyKey = idempotencyKey
    }
    /// The same request over the server's current copy (a silent resend, or 用我的修改覆盖).
    public func overwriting(current: AccountEditBase) -> AccountPatchAttempt {
        AccountPatchAttempt(accountID: accountID, base: current, ifMatch: current.etag ?? ifMatch, request: request, idempotencyKey: idempotencyKey)
    }
    /// After a 412 whose `GET :id` failed: only the version from `metadata.current_etag`.
    public func overwriting(etag: String) -> AccountPatchAttempt {
        AccountPatchAttempt(accountID: accountID, base: base, ifMatch: etag, request: request, idempotencyKey: idempotencyKey)
    }
    /// 继续保存 (20 §0.4-7): the body changes, so a keyed PUT takes a new key (00 §2.5.2); If-Match stays.
    public func confirmingMixedChannel(idempotencyKey: UUID?) -> AccountPatchAttempt {
        AccountPatchAttempt(accountID: accountID, base: base, ifMatch: ifMatch, request: request.confirmingMixedChannel(), idempotencyKey: idempotencyKey)
    }
    /// 20 §3.4: changed groups on a server whose 409 does not name the group are checked first.
    public func needsMixedChannelPrecheck(hasDetailsCapability: Bool) -> Bool {
        request.groupIDs != nil && request.confirmMixedChannelRisk != true && !hasDetailsCapability
    }
    /// A new secret cannot be read back; only its version says whether anything was written.
    var setsSecret: Bool {
        request.credentialsPatch.contains { AccountCredentialKeys.isSensitive($0.key) && !$0.value.isDeletion }
    }
}

extension AccountPatchAttempt: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "AccountPatchAttempt(account \(accountID); \(request))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// How a failed account PATCH or PUT goes on (20 §0.4, §0.5, §3.5).
public enum AccountPatchFailure: Sendable, Equatable {
    /// 412 ACCOUNT_VERSION_CONFLICT, with `metadata.current_etag`.
    case versionConflict(currentETag: String?)
    /// 409 MIXED_CHANNEL_WARNING; nil from an older server without metadata.
    case mixedChannel(MixedChannelWarning?)
    /// 400 INVALID_IF_MATCH / INVALID_PATCH / CREDENTIAL_KEY_NOT_DELETABLE: the App built it wrongly.
    case rejected(reason: String)
    /// 404 ACCOUNT_NOT_FOUND (GROUP_NOT_FOUND is a refusal).
    case removed
    /// The write may have run (00 §2.4): read the account back.
    case unknownResult
    /// The security sheet cleared it: the user saves again.
    case reconfirm(String)
    /// S2D1-09: a credential edit on a site older than credential redaction.
    case needsWeb(String)
    case refused(String)
    case cancelled

    public init(_ error: any Error) {
        if error is CancellationError { self = .cancelled; return }
        if let failure = error as? KeyedWriteFailure {
            if case .unconfirmed = failure.disposition { self = .unknownResult } else { self = .refused(failure.localizedDescription) }
            return
        }
        guard let api = error as? APIError else { self = .refused(error.localizedDescription); return }
        switch api.securityOutcome {
        case .cancelled?: self = .cancelled; return
        case .passed?: self = .reconfirm(api.localizedDescription); return
        case .blocked?, nil: break
        }
        if SecurityInterruption(api) != nil { self = .refused("尚未执行：\(api.localizedDescription)"); return }
        self = Self.classify(api)
    }
    private static func classify(_ api: APIError) -> AccountPatchFailure {
        if api.reason == AccountWriteReason.legacyCredentialsPut { return .needsWeb(api.localizedDescription) }
        guard api != .refreshDeferred else { return .refused(api.localizedDescription) }
        guard let status = api.statusCode else { return api.kind == .transport || api == .invalidResponse ? .unknownResult : .refused(api.localizedDescription) }
        switch (status, api.reason) {
        case (412, AccountWriteReason.versionConflict?): return .versionConflict(currentETag: AccountPatchConflict.currentETag(in: api))
        case (409, AccountWriteReason.mixedChannelWarning?): return .mixedChannel(MixedChannelWarning(error: api))
        case (404, AccountWriteReason.notFound?): return .removed
        default: break
        }
        if AccountWriteReason.isRejectedPatch(api), let reason = api.reason { return .rejected(reason: reason) }
        if status == 408 || RequestPolicy.isRetryableStatus(status, marker: api.reason) { return .unknownResult }
        return .refused(api.localizedDescription)
    }
}

/// Where one step of the save flow ended.
public enum AccountPatchStep: Sendable {
    /// The reply, or a read-back that already holds every target.
    case saved(AccountEditBase)
    /// 账号已被其他人修改: the server's copy when it could be read, and the version to overwrite with.
    case askOverwrite(AccountPatchAttempt, current: AccountEditBase?, currentETag: String?)
    case askMixedChannel(AccountPatchAttempt, MixedChannelWarning)
    /// The read-back shows nothing was written: 没有保存成功 + 重试 (same If-Match, or same key and base).
    case notApplied(AccountPatchAttempt)
    /// The read-back failed or cannot tell: 结果未确认.
    case unconfirmed(AccountPatchAttempt)
    case reconfirm(String)
    case needsWeb(String)
    case failed(String)
    case removed
    /// Cancelled, or the session changed: nothing is said.
    case cancelled
}

/// 20 §0.4-5: what a `GET :id` after an unknown result says (S2D1-04).
public enum AccountPatchReadbackVerdict: Sendable, Equatable {
    case applied, notApplied, unconfirmed

    /// A new secret is judged by the version: unchanged means nothing was written; a new one, or none (the PUT fallback), cannot
    /// tell. Everything else compares the fields (AccountPatchReadback).
    public static func evaluate(attempt: AccountPatchAttempt, current: VersionedAccount) -> AccountPatchReadbackVerdict {
        guard attempt.setsSecret else {
            return AccountPatchReadback.matches(account: current.account, request: attempt.request) ? .applied : .notApplied
        }
        guard let sent = attempt.ifMatch.map(version), let read = current.etag.map(version) else { return .unconfirmed }
        return sent == read ? .notApplied : .unconfirmed
    }
    /// "cv-3", W/"cv-3" and cv-3 name the same version.
    private static func version(_ tag: String) -> String {
        var text = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("W/") { text.removeFirst(2) }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}
