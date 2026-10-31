import Foundation

/// The account delete's result; 20 §0.5: an account that is already gone counts as deleted. Other resources have their own
/// (GroupDeleteResult, S5D1-03); no second type of this name.
public enum DeleteResult: Sendable, Equatable { case deleted, alreadyGone }

/// One entry of `GET :id/models` (20 §3.2 “添加模型”).
public struct AccountModelOption: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    /// `display_name`, or the id when it is missing or blank.
    public let displayName: String
    public init(id: String, displayName: String? = nil) {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.id = id; self.displayName = name.isEmpty ? id : name
    }
    enum CodingKeys: String, CodingKey { case id, displayName = "display_name" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: (try? c.decodeIfPresent(String.self, forKey: .id)) ?? "", displayName: try? c.decodeIfPresent(String.self, forKey: .displayName))
    }
}

/// The read-back checks of 20 §5.2 for a write whose result is unknown, on a fresh `GET :id`.
public enum AccountWriteCheck {
    public static func schedulable(_ account: UpstreamAccount, equals target: Bool) -> Bool { account.schedulable == target }
    /// Not in error, and the rate-limit, overload and temporary windows have all passed. `now` is the site's ServerClock time; a
    /// time that cannot be read counts as not passed.
    public static func recovered(_ account: UpstreamAccount, now: Date) -> Bool {
        guard account.status != "error" else { return false }
        return [account.rateLimitResetAt, account.overloadUntil, account.tempUnschedulableUntil].allSatisfy { raw in
            guard let raw, !raw.isEmpty else { return true }
            return ServerTime.parseTimestamp(raw).map { $0 <= now } ?? false
        }
    }
    public static func isActive(_ account: UpstreamAccount) -> Bool { account.status == "active" }
    /// After revert-proxy-fallback: back on the original proxy, no longer marked as fallen back.
    public static func proxyReverted(_ account: UpstreamAccount, toOrigin originProxyID: Int) -> Bool {
        account.proxyFallbackOriginID == nil && account.proxyID == originProxyID
    }
}

/// The reasons of 20 §0.5 the account pages act on.
public enum AccountWriteReason {
    public static let notFound = "ACCOUNT_NOT_FOUND"
    public static let versionConflict = "ACCOUNT_VERSION_CONFLICT"
    public static let invalidIfMatch = "INVALID_IF_MATCH"
    public static let invalidPatch = "INVALID_PATCH"
    public static let credentialKeyNotDeletable = "CREDENTIAL_KEY_NOT_DELETABLE"
    public static let mixedChannelWarning = "MIXED_CHANNEL_WARNING"
    public static let recoveredSchedulableFailed = "ACCOUNT_RECOVERED_SCHEDULABLE_FAILED"
    public static let notInFallback = "ACCOUNT_NOT_IN_FALLBACK"
    public static let fallbackOriginUnavailable = "PROXY_FALLBACK_ORIGIN_UNAVAILABLE"
    /// Raised locally, never by the server: a credential edit on a site older than credential redaction (S2D1-09).
    public static let legacyCredentialsPut = "LEGACY_CREDENTIALS_PUT"
    public static let legacyCredentialsPutMessage = "这个站点版本过旧，凭据相关设置请在 Web 中修改"
    /// A PATCH the App built wrongly: not retried.
    public static func isRejectedPatch(_ error: APIError) -> Bool {
        error.statusCode == 400 && [invalidIfMatch, invalidPatch, credentialKeyNotDeletable].contains(error.reason ?? "")
    }
    public static func isRecoveredButStillPaused(_ error: APIError) -> Bool {
        error.statusCode == 500 && error.reason == recoveredSchedulableFailed
    }
}

extension APIClient {
    /// `POST :id/schedulable`. With a key (admin.idempotent_writes, made when the user confirms, R05) transport failures are retried
    /// under it and an unanswered write ends as KeyedWriteFailure (00 §2.5.4); without one it is sent once (00 §2.4).
    public func setSchedulable(id: Int, enabled: Bool, idempotencyKey: UUID? = nil,
                               onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<UpstreamAccount> {
        try await accountWrite(accountPath(id, "/schedulable"), method: "POST", body: encode(["schedulable": enabled]), key: idempotencyKey, onEvent: onEvent)
    }
    /// 404 ACCOUNT_NOT_FOUND reads as already deleted; a non-JSON 404 (no such endpoint), RESOURCE_NOT_FOUND and the rest are
    /// thrown. Unkeyed and sent once.
    public func deleteAccount(id: Int) async throws -> DeleteResult {
        let path = try accountPath(id)
        do {
            let _: EmptyReply = try await request(path, method: "DELETE")
            return .deleted
        } catch let error as APIError where error.statusCode == 404 && error.reason == AccountWriteReason.notFound {
            return .alreadyGone
        }
    }
    /// Blank ids are dropped and repeated ones keep their first place.
    public func accountModels(id: Int) async throws -> [AccountModelOption] {
        let options: [AccountModelOption] = try await request(accountPath(id, "/models"))
        var seen = Set<String>()
        return options.filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.id).inserted }
    }
    /// No body and no key; success only says it ran (the reply has no account), so the caller reads `accountWithVersion(id:)`.
    public func revertAccountProxyFallback(id: Int) async throws {
        let _: EmptyReply = try await request(accountPath(id, "/revert-proxy-fallback"), method: "POST")
    }

    func accountPath(_ id: Int, _ suffix: String = "") throws -> String {
        let id = try validID(id)
        return "admin/accounts/\(id)" + suffix
    }
    /// With a key: the keyed executor. Without: sent once under a fresh number.
    func accountWrite<T: Decodable & Sendable>(_ path: String, method: String, body: Data, key: UUID?,
                                               onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<T> {
        guard let key else { return try await performUnkeyedWrite(path, method: method, body: body, requestID: UUID().uuidString.lowercased()) }
        return try await performKeyedWrite(KeyedWriteRequest(path: path, method: method, body: body, key: key), onEvent: onEvent)
    }
}
