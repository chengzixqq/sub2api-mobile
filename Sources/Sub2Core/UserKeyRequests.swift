import Foundation

/// `POST admin/users/:id/api-keys` (30 §7.4), checked when built. The server always generates the key.
public struct AdminAPIKeyCreateRequest: Encodable, Sendable, Equatable {
    /// Trimmed.
    public let name: String
    /// nil: not bound, left out of the body.
    public let groupID: Int?
    /// 0 = unlimited.
    public let quota: Decimal
    /// nil: never expires, left out of the body (0 or less is a 400).
    public let expiresInDays: Int?
    public let ipWhitelist: [String]
    public let ipBlacklist: [String]
    /// 0 = unlimited.
    public let rateLimit5h: Decimal
    public let rateLimit1d: Decimal
    public let rateLimit7d: Decimal
    public init(name: String, groupID: Int? = nil, quota: Decimal = 0, expiresInDays: Int? = nil, ipWhitelist: [String] = [],
                ipBlacklist: [String] = [], rateLimit5h: Decimal = 0, rateLimit1d: Decimal = 0, rateLimit7d: Decimal = 0) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try UserKeyValidation.name(trimmed)
        guard groupID.map({ $0 > 0 }) ?? true else { throw UserKeyValidation.error("无效的分组编号。") }
        guard expiresInDays.map({ $0 > 0 }) ?? true else { throw UserKeyValidation.error("有效期天数必须大于 0。") }
        for amount in [quota, rateLimit5h, rateLimit1d, rateLimit7d] { try UserKeyValidation.amount(amount) }
        self.name = trimmed; self.groupID = groupID; self.quota = quota; self.expiresInDays = expiresInDays
        self.ipWhitelist = ipWhitelist; self.ipBlacklist = ipBlacklist
        self.rateLimit5h = rateLimit5h; self.rateLimit1d = rateLimit1d; self.rateLimit7d = rateLimit7d
    }
    enum CodingKeys: String, CodingKey {
        case name, quota
        case groupID = "group_id", expiresInDays = "expires_in_days", ipWhitelist = "ip_whitelist", ipBlacklist = "ip_blacklist"
        case rateLimit5h = "rate_limit_5h", rateLimit1d = "rate_limit_1d", rateLimit7d = "rate_limit_7d"
    }
    /// Sorted keys; amounts are JSON numbers.
    public func requestBody() throws -> Data { try UserKeyValidation.encode(self) }
}

/// `PUT admin/api-keys/:id` (30 §7.4): only what changed goes out. A group change goes alone: the server applies the fields,
/// then the rate-limit reset, then the group, and a later step failing leaves the earlier ones done.
public struct AdminAPIKeyUpdateRequest: Encodable, Sendable, Equatable {
    public enum Status: String, Sendable, Encodable { case active, inactive }
    public enum Expiry: Sendable, Equatable {
        case unchanged
        /// Never expires: sends "".
        case clear
        /// Sends `ServerTime.utcTimestamp`.
        case set(Date)
    }
    /// Sent as given, so an undo writes the stored name back exactly.
    public let name: String?
    public let status: Status?
    public let quota: Decimal?
    public let resetQuota: Bool
    public let expiresAt: Expiry
    /// [] clears the list.
    public let ipWhitelist: [String]?
    public let ipBlacklist: [String]?
    public let rateLimit5h: Decimal?
    public let rateLimit1d: Decimal?
    public let rateLimit7d: Decimal?
    public let resetRateLimitUsage: Bool
    /// 0 unbinds.
    public let groupID: Int?
    /// Only with `groupID`: withdraws the exclusive group the change being undone granted (E04).
    public let revokeGroupAccessID: Int?
    public init(name: String? = nil, status: Status? = nil, quota: Decimal? = nil, resetQuota: Bool = false, expiresAt: Expiry = .unchanged,
                ipWhitelist: [String]? = nil, ipBlacklist: [String]? = nil, rateLimit5h: Decimal? = nil, rateLimit1d: Decimal? = nil,
                rateLimit7d: Decimal? = nil, resetRateLimitUsage: Bool = false, groupID: Int? = nil, revokeGroupAccessID: Int? = nil) throws {
        self.name = name; self.status = status; self.quota = quota; self.resetQuota = resetQuota; self.expiresAt = expiresAt
        self.ipWhitelist = ipWhitelist; self.ipBlacklist = ipBlacklist
        self.rateLimit5h = rateLimit5h; self.rateLimit1d = rateLimit1d; self.rateLimit7d = rateLimit7d
        self.resetRateLimitUsage = resetRateLimitUsage; self.groupID = groupID; self.revokeGroupAccessID = revokeGroupAccessID
        try validate()
    }
    enum CodingKeys: String, CodingKey {
        case name, status, quota
        case resetQuota = "reset_quota", expiresAt = "expires_at", ipWhitelist = "ip_whitelist", ipBlacklist = "ip_blacklist"
        case rateLimit5h = "rate_limit_5h", rateLimit1d = "rate_limit_1d", rateLimit7d = "rate_limit_7d"
        case resetRateLimitUsage = "reset_rate_limit_usage", groupID = "group_id", revokeGroupAccessID = "revoke_group_access_id"
    }
    /// nil and false leave their keys out.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name); try c.encodeIfPresent(status, forKey: .status); try c.encodeIfPresent(quota, forKey: .quota)
        if resetQuota { try c.encode(true, forKey: .resetQuota) }
        switch expiresAt {
        case .unchanged: break
        case .clear: try c.encode("", forKey: .expiresAt)
        case .set(let date): try c.encode(ServerTime.utcTimestamp(date), forKey: .expiresAt)
        }
        try c.encodeIfPresent(ipWhitelist, forKey: .ipWhitelist); try c.encodeIfPresent(ipBlacklist, forKey: .ipBlacklist)
        try c.encodeIfPresent(rateLimit5h, forKey: .rateLimit5h); try c.encodeIfPresent(rateLimit1d, forKey: .rateLimit1d)
        try c.encodeIfPresent(rateLimit7d, forKey: .rateLimit7d)
        if resetRateLimitUsage { try c.encode(true, forKey: .resetRateLimitUsage) }
        try c.encodeIfPresent(groupID, forKey: .groupID); try c.encodeIfPresent(revokeGroupAccessID, forKey: .revokeGroupAccessID)
    }
    public func requestBody() throws -> Data { try UserKeyValidation.encode(self) }

    private var changesFields: Bool {
        name != nil || status != nil || quota != nil || resetQuota || expiresAt != .unchanged || ipWhitelist != nil || ipBlacklist != nil
            || rateLimit5h != nil || rateLimit1d != nil || rateLimit7d != nil
    }
    private func validate() throws {
        let changesGroup = groupID != nil || revokeGroupAccessID != nil
        guard changesFields || resetRateLimitUsage || changesGroup else { throw UserKeyValidation.error("没有要保存的修改。") }
        guard !changesGroup || !(changesFields || resetRateLimitUsage) else { throw UserKeyValidation.error("换分组要单独保存，不能与其他修改一起发送。") }
        if let groupID, groupID < 0 { throw UserKeyValidation.error("无效的分组编号。") }
        if let revokeGroupAccessID, groupID == nil || revokeGroupAccessID <= 0 || revokeGroupAccessID == groupID {
            throw UserKeyValidation.error("无效的撤销授权分组。")
        }
        if let name { try UserKeyValidation.name(name) }
        for amount in [quota, rateLimit5h, rateLimit1d, rateLimit7d].compactMap({ $0 }) { try UserKeyValidation.amount(amount) }
    }
}

/// `previous` of a PUT reply: the old values of the columns this write changed (admin_group.go `AdminUpdateAPIKeyFields`),
/// what an undo writes back. A field the write did not change is nil.
public struct AdminAPIKeyPrevious: Decodable, Sendable, Equatable {
    public enum Expiry: Sendable, Equatable {
        /// JSON null: the key had no expiry (an undo sends "").
        case never
        case at(Date)
    }
    public let name: String?
    public let status: String?
    public let quota: Decimal?
    /// Present after a quota reset, which cannot be written back.
    public let quotaUsed: Decimal?
    public let expiresAt: Expiry?
    /// null reads as [].
    public let ipWhitelist: [String]?
    public let ipBlacklist: [String]?
    public let rateLimit5h: Decimal?
    public let rateLimit1d: Decimal?
    public let rateLimit7d: Decimal?
    public init(name: String? = nil, status: String? = nil, quota: Decimal? = nil, quotaUsed: Decimal? = nil, expiresAt: Expiry? = nil,
                ipWhitelist: [String]? = nil, ipBlacklist: [String]? = nil, rateLimit5h: Decimal? = nil, rateLimit1d: Decimal? = nil,
                rateLimit7d: Decimal? = nil) {
        self.name = name; self.status = status; self.quota = quota; self.quotaUsed = quotaUsed; self.expiresAt = expiresAt
        self.ipWhitelist = ipWhitelist; self.ipBlacklist = ipBlacklist
        self.rateLimit5h = rateLimit5h; self.rateLimit1d = rateLimit1d; self.rateLimit7d = rateLimit7d
    }
    enum CodingKeys: String, CodingKey {
        case name, status, quota
        case quotaUsed = "quota_used", expiresAt = "expires_at", ipWhitelist = "ip_whitelist", ipBlacklist = "ip_blacklist"
        case rateLimit5h = "rate_limit_5h", rateLimit1d = "rate_limit_1d", rateLimit7d = "rate_limit_7d"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: key) }
        func amount(_ key: CodingKeys) -> Decimal? { try? c.optionalDecimal(key) }
        func list(_ key: CodingKeys) -> [String]? {
            c.contains(key) ? (try? c.decodeIfPresent(LossyList<String>.self, forKey: key))?.items ?? [] : nil
        }
        let expiry: Expiry? = if !c.contains(.expiresAt) { nil }
            else if (try? c.decodeNil(forKey: .expiresAt)) == true { .never }
            else { (try? c.optionalTimestamp(.expiresAt)).map(Expiry.at) }
        self.init(name: text(.name), status: text(.status), quota: amount(.quota), quotaUsed: amount(.quotaUsed), expiresAt: expiry,
                  ipWhitelist: list(.ipWhitelist), ipBlacklist: list(.ipBlacklist), rateLimit5h: amount(.rateLimit5h),
                  rateLimit1d: amount(.rateLimit1d), rateLimit7d: amount(.rateLimit7d))
    }
}

/// A PUT reply (and the grant fields of a create reply); every field may be missing. `api_key` is the masked form.
public struct AdminAPIKeyWriteResult: Decodable, Sendable, Equatable {
    /// nil when missing or unreadable: the caller reads the key again.
    public let apiKey: AdminAPIKey?
    /// True whenever the target is an exclusive standard group, even one the user had (30 §7.4): not an undo signal.
    public let autoGrantedGroupAccess: Bool
    public let grantedGroupID: Int?
    public let grantedGroupName: String?
    public let revokedGroupAccess: Bool
    public let revokedGroupID: Int?
    public let previous: AdminAPIKeyPrevious?
    public init(apiKey: AdminAPIKey? = nil, autoGrantedGroupAccess: Bool = false, grantedGroupID: Int? = nil, grantedGroupName: String? = nil,
                revokedGroupAccess: Bool = false, revokedGroupID: Int? = nil, previous: AdminAPIKeyPrevious? = nil) {
        self.apiKey = apiKey; self.autoGrantedGroupAccess = autoGrantedGroupAccess; self.grantedGroupID = grantedGroupID
        self.grantedGroupName = grantedGroupName; self.revokedGroupAccess = revokedGroupAccess; self.revokedGroupID = revokedGroupID
        self.previous = previous
    }
    enum CodingKeys: String, CodingKey {
        case previous
        case apiKey = "api_key", autoGrantedGroupAccess = "auto_granted_group_access", grantedGroupID = "granted_group_id"
        case grantedGroupName = "granted_group_name", revokedGroupAccess = "revoked_group_access", revokedGroupID = "revoked_group_id"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: key)) == true }
        func number(_ key: CodingKeys) -> Int? { try? c.decodeIfPresent(Int.self, forKey: key) }
        let groupName = try? c.decodeIfPresent(String.self, forKey: .grantedGroupName)
        self.init(apiKey: try? c.decodeIfPresent(AdminAPIKey.self, forKey: .apiKey), autoGrantedGroupAccess: flag(.autoGrantedGroupAccess),
                  grantedGroupID: number(.grantedGroupID), grantedGroupName: groupName?.isEmpty == false ? groupName : nil,
                  revokedGroupAccess: flag(.revokedGroupAccess), revokedGroupID: number(.revokedGroupID),
                  previous: try? c.decodeIfPresent(AdminAPIKeyPrevious.self, forKey: .previous))
    }
}

/// `POST admin/api-keys/:id/reveal` (E03). Memory only: not Encodable, so it cannot be saved, logged as a body or restored, and
/// every printed or reflected form leaves the key out. The sheet clears it on close, in the background and after 30 seconds.
public struct APIKeyReveal: Decodable, Sendable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let id: Int
    public let key: String
    public init(id: Int, key: String) { self.id = id; self.key = key }
    enum CodingKeys: String, CodingKey { case id, key }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let key = try c.decode(String.self, forKey: .key)
        guard !key.isEmpty else { throw APIError.invalidResponse }
        self.init(id: try c.decode(Int.self, forKey: .id), key: key)
    }
    public var description: String { "APIKeyReveal(id: \(id), key: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["id": id], displayStyle: .struct) }
}

/// The create reply: the only time the server returns the plaintext (30 §7.4), kept here alone and redacted like APIKeyReveal;
/// `apiKey` is the masked form the card list inserts.
public struct CreatedAPIKey: Decodable, Sendable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let apiKey: AdminAPIKey
    public let key: String
    public let autoGrantedGroupAccess: Bool
    public let grantedGroupID: Int?
    public let grantedGroupName: String?
    public var id: Int { apiKey.id }
    public init(apiKey: AdminAPIKey, key: String, autoGrantedGroupAccess: Bool = false, grantedGroupID: Int? = nil, grantedGroupName: String? = nil) {
        self.apiKey = apiKey; self.key = key; self.autoGrantedGroupAccess = autoGrantedGroupAccess
        self.grantedGroupID = grantedGroupID; self.grantedGroupName = grantedGroupName
    }
    /// A reply without `api_key` or its plaintext is unreadable.
    public init(from decoder: any Decoder) throws {
        let result = try AdminAPIKeyWriteResult(from: decoder)
        let plaintext = try? decoder.container(keyedBy: AdminAPIKeyWriteResult.CodingKeys.self)
            .nestedContainer(keyedBy: AdminAPIKey.CodingKeys.self, forKey: .apiKey).decode(String.self, forKey: .key)
        guard let apiKey = result.apiKey, let plaintext, !plaintext.isEmpty else { throw APIError.invalidResponse }
        self.init(apiKey: apiKey, key: plaintext, autoGrantedGroupAccess: result.autoGrantedGroupAccess, grantedGroupID: result.grantedGroupID,
                  grantedGroupName: result.grantedGroupName)
    }
    public var description: String { "CreatedAPIKey(id: \(id), key: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["id": id], displayStyle: .struct) }
}

enum UserKeyListing {
    static let pageSize = 100
    /// 5,000 keys; a reply that keeps reporting more pages is treated as malformed.
    static let maxPages = 50
    /// `maskedView` is the caller's `api_keys.masked_view`: the client keeps no capabilities, and an old server would ignore it
    /// and send the plaintext anyway, which decoding drops.
    static func keyView(_ maskedView: Bool) -> [URLQueryItem] { maskedView ? [URLQueryItem(name: "key_view", value: "masked")] : [] }
}

// MARK: - Key 读写接口（30 §7.2、§7.4；R19：每个接口只定义在这里）

extension APIClient {
    /// Every page, `id` ascending so the pages stay stable; deduplicated, tombstones dropped.
    public func userAPIKeys(userID: Int, maskedView: Bool) async throws -> [AdminAPIKey] {
        let path = "admin/users/\(try validID(userID))/api-keys"
        let order = [URLQueryItem(name: "sort_by", value: "id"), URLQueryItem(name: "sort_order", value: "asc")]
        var keys = [AdminAPIKey](), seen = Set<Int>()
        for page in 1...UserKeyListing.maxPages {
            let query = try pagination(page, pageSize: UserKeyListing.pageSize, search: "", status: nil) + order + UserKeyListing.keyView(maskedView)
            let reply: Page<AdminAPIKey> = try await request(path, query: query)
            for key in reply.items where !key.isTombstone && seen.insert(key.id).inserted { keys.append(key) }
            guard reply.hasMore, !reply.items.isEmpty else { return keys }
        }
        throw APIError.invalidResponse
    }
    /// Refreshes one card after a write (the write reply reports `current_concurrency` as 0). A deleted key answers 404
    /// API_KEY_NOT_FOUND; `isTombstone` is only a guard here.
    public func apiKey(id: Int, maskedView: Bool) async throws -> AdminAPIKey {
        try await request("admin/api-keys/\(validID(id))", query: UserKeyListing.keyView(maskedView))
    }
    /// R05: the caller makes `idempotencyKey` when 创建 is tapped and reuses it while the form is unchanged; a replay returns the
    /// same plaintext.
    public func createUserAPIKey(userID: Int, _ draft: AdminAPIKeyCreateRequest, idempotencyKey: UUID,
                                 onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<CreatedAPIKey> {
        let path = "admin/users/\(try validID(userID))/api-keys"
        return try await performKeyedWrite(KeyedWriteRequest(path: path, method: "POST", body: try draft.requestBody(), key: idempotencyKey), onEvent: onEvent)
    }
    /// Sent once without an Idempotency-Key.
    public func updateAPIKey(id: Int, _ change: AdminAPIKeyUpdateRequest, maskedView: Bool) async throws -> AdminAPIKeyWriteResult {
        try await request("admin/api-keys/\(validID(id))", method: "PUT", query: UserKeyListing.keyView(maskedView), body: change.requestBody())
    }
    /// True when the server reports it deleted; deleting a deleted key succeeds too. A 404 API_KEY_NOT_FOUND is thrown as is
    /// and the caller treats it as deleted.
    public func deleteAPIKey(id: Int) async throws -> Bool {
        let reply: DeletedKeyReply = try await request("admin/api-keys/\(validID(id))", method: "DELETE")
        return reply.deleted == true
    }
    /// A bodyless POST declared a read on purpose (00 §2.6.2 step 4, BACKLOG “读类 POST 的安全重发”): after step-up passes, the
    /// security hook sends it once more. Like any read it also retries 502 / 504 and is cancelled in the background, at most
    /// one more audit line. The caller still asks for Face ID and `ensureStepUp` first. Never conditional.
    public func revealAPIKey(id: Int) async throws -> APIKeyReveal {
        let reveal: APIKeyReveal = try await request("admin/api-keys/\(validID(id))/reveal", method: "POST", requestClass: .read)
        guard reveal.id == id else { throw APIError.invalidResponse }
        return reveal
    }
    /// Today's spend per key, `.readBatch` through `readInBatches` (S3D1-07). Only requested ids are kept; one the reply leaves
    /// out is the caller's “$0.00”. A failed batch fails the call. A read-only token must not call it (R14).
    public func apiKeysTodayUsage(ids: [Int]) async throws -> [Int: Decimal] {
        try await readInBatches(ids, size: UserListQuery.usageBatchSize) { chunk in
            let reply: APIKeysUsageReply = try await request("admin/dashboard/api-keys-usage", method: "POST",
                                                             body: encode(["api_key_ids": chunk]), requestClass: .readBatch)
            return AccountBatchIDs.matched(reply.stats, requested: Set(chunk))
        }
    }
}

private struct DeletedKeyReply: Decodable, Sendable { let deleted: Bool? }

/// `{stats: {"<api_key_id>": {today_actual_cost, …}}}`; an entry without a readable cost reads as absent.
private struct APIKeysUsageReply: Decodable, Sendable {
    private struct Entry: Decodable {
        let todayActualCost: Decimal?
        enum CodingKeys: String, CodingKey { case todayActualCost = "today_actual_cost" }
        init(from decoder: any Decoder) throws {
            todayActualCost = try? decoder.container(keyedBy: CodingKeys.self).optionalDecimal(.todayActualCost)
        }
    }
    let stats: [String: Decimal]
    enum CodingKeys: String, CodingKey { case stats }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stats = ((try? c.decodeIfPresent([String: LenientDecoded<Entry>].self, forKey: .stats)) ?? [:]).compactMapValues { $0.value?.todayActualCost }
    }
}

private enum UserKeyValidation {
    static let maximumAmount = Decimal(string: "999999999999.99999999", locale: Locale(identifier: "en_US_POSIX"))!
    static func error(_ message: String) -> APIError { APIError(kind: .validation, message: message) }
    static func name(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw error("名称不能为空。") }
    }
    /// 0 = unlimited; at most 8 decimals like every amount (00 §6.1).
    static func amount(_ value: Decimal) throws {
        guard !value.isNaN, value >= 0, value <= maximumAmount, value.hasAtMostFractionDigits(8) else {
            throw error("额度和速率限制必须是非负数，最多 8 位小数。")
        }
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
