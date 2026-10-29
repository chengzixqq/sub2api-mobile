import Foundation

/// The `POST admin/accounts` body (20 §7.2, account_handler.go CreateAccountRequest). The account is always created outside the
/// scheduler (`schedulable: false`, C01: test first, enable after) and `skip_default_group_bind` is never sent (U18). Holds the
/// credentials, so printing shows only the platform and type.
public struct AccountCreateRequest: Encodable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The backend's `oneof` for `type`.
    public static var accountTypes: Set<String> { AccountPatchRequest.accountTypes }
    /// Trimmed.
    public let name: String
    /// Trimmed; empty is nil and not sent (the backend's normalizeAccountNotes).
    public let notes: String?
    public let platform: String
    public let type: String
    /// Only for the request body.
    let credentials: [String: JSONValue]
    /// Empty is nil and not sent.
    public let extra: [String: JSONValue]?
    public let proxyID: Int?
    public let concurrency: Int
    public let priority: Int
    public let rateMultiplier: Decimal?
    public let loadFactor: Int?
    /// Sent in this order (the account's priority in each group), also when empty.
    public let groupIDs: [Int]
    /// Unix seconds.
    public let expiresAt: Int64?
    public let autoPauseOnExpired: Bool?
    public let upstreamBillingProbeEnabled: Bool?
    /// The answer to a mixed-channel warning; sent only when true, under a new key (00 §2.5.2).
    public let confirmMixedChannelRisk: Bool

    public init(name: String, notes: String? = nil, platform: String, type: String, credentials: [String: JSONValue],
                extra: [String: JSONValue]? = nil, proxyID: Int? = nil, concurrency: Int, priority: Int, rateMultiplier: Decimal? = nil,
                loadFactor: Int? = nil, groupIDs: [Int] = [], expiresAt: Int64? = nil, autoPauseOnExpired: Bool? = nil,
                upstreamBillingProbeEnabled: Bool? = nil, confirmMixedChannelRisk: Bool = false) {
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines); self.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        self.platform = platform.trimmingCharacters(in: .whitespacesAndNewlines); self.type = type
        self.credentials = credentials; self.extra = extra?.isEmpty == false ? extra : nil
        self.proxyID = proxyID; self.concurrency = concurrency; self.priority = priority; self.rateMultiplier = rateMultiplier
        self.loadFactor = loadFactor; self.groupIDs = groupIDs; self.expiresAt = expiresAt; self.autoPauseOnExpired = autoPauseOnExpired
        self.upstreamBillingProbeEnabled = upstreamBillingProbeEnabled; self.confirmMixedChannelRisk = confirmMixedChannelRisk
    }

    /// The backend's own limits; the form's narrower ranges are AccountNewDraft.createRequest's.
    public func validate() throws {
        if name.isEmpty { throw Self.invalid("请输入账号名称") }
        if platform.isEmpty || !Self.accountTypes.contains(type) { throw Self.invalid("账号类型无效。") }
        if credentials.isEmpty { throw Self.invalid("请填写凭据") }
        if [concurrency, priority].contains(where: { $0 < 0 || $0 > Int(Int32.max) }) { throw Self.invalid("并发和优先级必须是非负整数。") }
        if let rateMultiplier, rateMultiplier.isNaN || rateMultiplier < 0 { throw Self.invalid("账号计费倍率需要是不小于 0 的数字") }
        if let loadFactor, !(1...10_000).contains(loadFactor) { throw Self.invalid("负载因子为 1–10000 的整数，可以不填") }
        if groupIDs.contains(where: { $0 <= 0 }) || Set(groupIDs).count != groupIDs.count { throw Self.invalid("分组编号无效或重复。") }
        if let proxyID, proxyID <= 0 { throw Self.invalid("代理编号无效。") }
        if let expiresAt, expiresAt <= 0 { throw Self.invalid("过期时间无效。") }
    }
    static func invalid(_ message: String) -> APIError { APIError(kind: .validation, message: message) }

    /// Checked, sorted keys: the same request always gives the same bytes, which a keyed retry needs.
    public func requestBody() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
    /// A copy that answers the mixed-channel warning; this value is unchanged.
    public func confirmingMixedChannel() -> AccountCreateRequest {
        AccountCreateRequest(name: name, notes: notes, platform: platform, type: type, credentials: credentials, extra: extra, proxyID: proxyID,
                             concurrency: concurrency, priority: priority, rateMultiplier: rateMultiplier, loadFactor: loadFactor, groupIDs: groupIDs,
                             expiresAt: expiresAt, autoPauseOnExpired: autoPauseOnExpired,
                             upstreamBillingProbeEnabled: upstreamBillingProbeEnabled, confirmMixedChannelRisk: true)
    }

    enum CodingKeys: String, CodingKey {
        case name, notes, platform, type, credentials, extra, concurrency, priority, schedulable
        case proxyID = "proxy_id", rateMultiplier = "rate_multiplier", loadFactor = "load_factor", groupIDs = "group_ids"
        case expiresAt = "expires_at", autoPauseOnExpired = "auto_pause_on_expired"
        case upstreamBillingProbeEnabled = "upstream_billing_probe_enabled", confirmMixedChannelRisk = "confirm_mixed_channel_risk"
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(platform, forKey: .platform); try c.encode(type, forKey: .type)
        try c.encode(JSONValue.object(credentials), forKey: .credentials); try c.encodeIfPresent(extra.map(JSONValue.object), forKey: .extra)
        try c.encodeIfPresent(proxyID, forKey: .proxyID); try c.encode(concurrency, forKey: .concurrency); try c.encode(priority, forKey: .priority)
        try c.encodeIfPresent(rateMultiplier, forKey: .rateMultiplier); try c.encodeIfPresent(loadFactor, forKey: .loadFactor)
        try c.encode(groupIDs, forKey: .groupIDs); try c.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try c.encodeIfPresent(autoPauseOnExpired, forKey: .autoPauseOnExpired)
        try c.encodeIfPresent(upstreamBillingProbeEnabled, forKey: .upstreamBillingProbeEnabled)
        if confirmMixedChannelRisk { try c.encode(true, forKey: .confirmMixedChannelRisk) }
        try c.encode(false, forKey: .schedulable)
    }

    public var description: String { "AccountCreateRequest(\(platform), \(type), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension APIClient {
    /// `POST admin/accounts` (20 §7.4, R05). The key is made when the admin taps “创建并测试” and only on a site with
    /// `admin.idempotent_writes`: then transport failures are retried under it and an unanswered write ends as KeyedWriteFailure
    /// (00 §2.5.4). Without one it is sent once and never retried, so an unknown result is checked by name instead
    /// (AccountCreateReconciliation). A 409 MIXED_CHANNEL_WARNING and other business errors are thrown as they come.
    public func createAccount(_ request: AccountCreateRequest, idempotencyKey: UUID?,
                              onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<UpstreamAccount> {
        try await accountWrite("admin/accounts", method: "POST", body: request.requestBody(), key: idempotencyKey, onEvent: onEvent)
    }
}

/// 20 §7.5 “创建结果不明” after it turns to 待核对: `GET admin/accounts?search={name}&lite=1`, matched here. The server's search
/// is a case-insensitive substring match and names are not unique, so the match is exact and also bounded by creation time.
public enum AccountCreateReconciliation {
    public static let pageSize = 100
    /// Slack between the server's created_at and this device's ServerTime (Date has whole seconds; the write takes a while).
    public static let clockTolerance: TimeInterval = 120

    /// Newest first, with only the parameters an older server understands too.
    public static func query(name: String, platform: String) -> AccountListQuery {
        AccountListQuery(search: name.trimmingCharacters(in: .whitespacesAndNewlines), platform: platform, sort: .created, descending: true,
                         pageSize: pageSize)
    }
    /// The same name (trimmed, case kept) on the same platform, created no earlier than `notBefore` − clockTolerance when its
    /// created_at can be read; the highest id among several. `notBefore` is the ServerTime of the first send.
    public static func match(_ candidates: [UpstreamAccount], name: String, platform: String, notBefore: Date?) -> UpstreamAccount? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let earliest = notBefore?.addingTimeInterval(-clockTolerance)
        return candidates.filter { candidate in
            guard candidate.name.trimmingCharacters(in: .whitespacesAndNewlines) == wanted, candidate.platform == platform else { return false }
            guard let earliest, let createdAt = ServerTime.parseTimestamp(candidate.createdAt) else { return true }
            return createdAt >= earliest
        }.max { $0.id < $1.id }
    }
}
