import Foundation

/// One key of `credentials_patch` / `extra_patch` (20 §3.2): a new value, which replaces a nested object whole, or an explicit
/// JSON null that deletes the key. Printing never shows the value (S2D1-10).
public enum JSONPatchValue: Encodable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case set(JSONValue)
    case delete
    /// `.set(.null)` deletes as well: the server reads both as null.
    public var isDeletion: Bool { self == .delete || self == .set(.null) }
    public func encode(to encoder: any Encoder) throws {
        guard case .set(let value) = self, !isDeletion else {
            var c = encoder.singleValueContainer(); try c.encodeNil(); return
        }
        try value.encode(to: encoder)
    }
    public var description: String { isDeletion ? "delete" : "set(<redacted>)" }
    public var debugDescription: String { "JSONPatchValue." + description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .enum) }
}

/// Secret credential keys: never read back, and a patch may replace but not delete them (CREDENTIAL_KEY_NOT_DELETABLE).
public enum AccountCredentialKeys {
    public static var sensitive: Set<String> { UpstreamAccount.sensitiveCredentialKeys }
    public static func isSensitive(_ key: String) -> Bool { sensitive.contains(key) }
}

/// A sparse account edit (20 §3.2): nil fields and absent patch keys are not sent. The PATCH body carries `credentials_patch` /
/// `extra_patch`; the PUT fallback merges them onto the account detail instead (`fullUpdateBody`). Printing shows key names only.
public struct AccountPatchRequest: Encodable, Sendable, Equatable {
    public enum Status: String, Sendable, CaseIterable { case active, inactive, error }
    /// The backend's `oneof` for `type`.
    public static let accountTypes: Set<String> = ["oauth", "setup-token", "apikey", "upstream", "bedrock", "service_account"]
    /// Sent trimmed.
    public var name: String?
    /// "" clears the notes.
    public var notes: String?
    public var type: String?
    /// 0 clears the proxy.
    public var proxyID: Int?
    public var concurrency: Int?
    public var priority: Int?
    public var rateMultiplier: Decimal?
    /// 0 restores the default.
    public var loadFactor: Int?
    public var status: Status?
    /// Sent in this order, which is the account's priority in each group; [] leaves every group.
    public var groupIDs: [Int]?
    /// 0 or less is sent as 0, which clears it.
    public var expiresAt: Int64?
    public var autoPauseOnExpired: Bool?
    public var upstreamBillingProbeEnabled: Bool?
    /// Only the answer to a 409 MIXED_CHANNEL_WARNING; not a change of its own.
    public var confirmMixedChannelRisk: Bool?
    public var credentialsPatch: [String: JSONPatchValue]
    public var extraPatch: [String: JSONPatchValue]
    public init(name: String? = nil, notes: String? = nil, type: String? = nil, proxyID: Int? = nil, concurrency: Int? = nil, priority: Int? = nil,
                rateMultiplier: Decimal? = nil, loadFactor: Int? = nil, status: Status? = nil, groupIDs: [Int]? = nil, expiresAt: Int64? = nil,
                autoPauseOnExpired: Bool? = nil, upstreamBillingProbeEnabled: Bool? = nil, confirmMixedChannelRisk: Bool? = nil,
                credentialsPatch: [String: JSONPatchValue] = [:], extraPatch: [String: JSONPatchValue] = [:]) {
        self.name = name; self.notes = notes; self.type = type; self.proxyID = proxyID; self.concurrency = concurrency; self.priority = priority
        self.rateMultiplier = rateMultiplier; self.loadFactor = loadFactor; self.status = status; self.groupIDs = groupIDs; self.expiresAt = expiresAt
        self.autoPauseOnExpired = autoPauseOnExpired; self.upstreamBillingProbeEnabled = upstreamBillingProbeEnabled
        self.confirmMixedChannelRisk = confirmMixedChannelRisk; self.credentialsPatch = credentialsPatch; self.extraPatch = extraPatch
    }
    enum CodingKeys: String, CodingKey {
        case name, notes, type, concurrency, priority, status, credentials, extra
        case proxyID = "proxy_id", rateMultiplier = "rate_multiplier", loadFactor = "load_factor", groupIDs = "group_ids", expiresAt = "expires_at"
        case autoPauseOnExpired = "auto_pause_on_expired", upstreamBillingProbeEnabled = "upstream_billing_probe_enabled"
        case confirmMixedChannelRisk = "confirm_mixed_channel_risk", credentialsPatch = "credentials_patch", extraPatch = "extra_patch"
    }
    /// Backend `managedAccountExtraKeys` (service/account_patch.go): owned by their own endpoints and jobs, so a merged `extra`
    /// leaves them out unless the patch names them, and the server keeps the stored values.
    static let managedExtraKeys: Set<String> = [
        "upstream_billing_probe_enabled", "upstream_billing_rate_sync_enabled", "upstream_billing_probe",
        "ollama_cloud_usage_session", "ollama_cloud_usage_auto_refresh", "ollama_cloud_usage_snapshot",
        "opencode_go_usage_auto_refresh", "opencode_go_usage_snapshot"
    ]

    /// The top-level members in their wire form; `confirm_mixed_channel_risk` is not among them.
    var topLevelValues: [(key: CodingKeys, value: JSONValue)] {
        let fields: [(CodingKeys, JSONValue?)] = [
            (.name, name.map { .string($0.trimmingCharacters(in: .whitespacesAndNewlines)) }), (.notes, notes.map(JSONValue.string)),
            (.type, type.map(JSONValue.string)), (.proxyID, proxyID.map(Self.number)), (.concurrency, concurrency.map(Self.number)),
            (.priority, priority.map(Self.number)), (.rateMultiplier, rateMultiplier.map(JSONValue.number)), (.loadFactor, loadFactor.map(Self.number)),
            (.status, status.map { .string($0.rawValue) }), (.groupIDs, groupIDs.map { .array($0.map(Self.number)) }),
            (.expiresAt, expiresAt.map { .number(Decimal(max($0, 0))) }), (.autoPauseOnExpired, autoPauseOnExpired.map(JSONValue.bool)),
            (.upstreamBillingProbeEnabled, upstreamBillingProbeEnabled.map(JSONValue.bool))
        ]
        return fields.compactMap { key, value in value.map { (key: key, value: $0) } }
    }
    private static func number(_ value: Int) -> JSONValue { .number(Decimal(value)) }

    public var hasChanges: Bool { !topLevelValues.isEmpty || !credentialsPatch.isEmpty || !extraPatch.isEmpty }
    public func validate() throws {
        guard hasChanges else { throw Self.invalid("请至少修改一个账号字段。") }
        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw Self.invalid("请输入账号名称") }
        for value in [concurrency, priority].compactMap({ $0 }) where value < 0 || value > Int(Int32.max) {
            throw Self.invalid("并发和优先级必须是非负整数。")
        }
        if let loadFactor, !(0...10_000).contains(loadFactor) { throw Self.invalid("负载因子为 1–10000 的整数；留空或 0 恢复默认") }
        if let rateMultiplier, rateMultiplier.isNaN || rateMultiplier < 0 { throw Self.invalid("账号计费倍率需要是不小于 0 的数字") }
        if let groupIDs, groupIDs.contains(where: { $0 <= 0 }) || Set(groupIDs).count != groupIDs.count { throw Self.invalid("分组编号无效或重复。") }
        if let proxyID, proxyID < 0 { throw Self.invalid("代理编号无效。") }
        if let type, !Self.accountTypes.contains(type) { throw Self.invalid("账号类型无效。") }
        try validatePatchKeys()
    }
    private func validatePatchKeys() throws {
        if (Array(credentialsPatch.keys) + Array(extraPatch.keys)).contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw Self.invalid("凭据或扩展字段的键不能为空。")
        }
        // The backend's CREDENTIAL_KEY_NOT_DELETABLE; extra_patch has no such rule.
        if let key = credentialsPatch.filter({ AccountCredentialKeys.isSensitive($0.key) && $0.value.isDeletion }).keys.sorted().first {
            throw Self.invalid("敏感凭据（\(key)）不能删除，只能更换。")
        }
    }
    static func invalid(_ message: String) -> APIError { APIError(kind: .validation, message: message) }

    /// The PATCH body: checked, sorted keys, explicit nulls kept, never a whole `credentials` / `extra`.
    public func requestBody() throws -> Data { try validate(); return try Self.encoded(self) }
    /// The PUT body without `accounts.patch` (20 §3.2, appendix A S30 / S31, X24): the same sparse top level, plus `credentials` /
    /// `extra` only when their patch has keys, merged onto `base`, the `GET :id` detail. The detail's secrets are left out (the
    /// server keeps the stored ones) and so are the managed extra keys the patch does not name. Nothing is read here, so the
    /// same inputs always give the same bytes for a keyed retry.
    public func fullUpdateBody(base: UpstreamAccount?) throws -> Data {
        try validate()
        guard !credentialsPatch.isEmpty || !extraPatch.isEmpty else { return try Self.encoded(FullUpdateBody(request: self, credentials: nil, extra: nil)) }
        guard let base else { throw Self.invalid("缺少账号的最新详情，无法合并凭据，请刷新后重试。") }
        // S2D1-09: a server older than credential redaction replaces the whole credentials, secrets included.
        if !credentialsPatch.isEmpty, base.credentialsArrivedUnredacted {
            throw APIError(kind: .unsupported, reason: AccountWriteReason.legacyCredentialsPut, message: AccountWriteReason.legacyCredentialsPutMessage)
        }
        let storedCredentials = (base.credentials?.objectValue ?? [:]).filter { !AccountCredentialKeys.isSensitive($0.key) }
        let storedExtra = (base.extra?.raw.objectValue ?? [:]).filter { !Self.managedExtraKeys.contains($0.key) || extraPatch[$0.key] != nil }
        return try Self.encoded(FullUpdateBody(request: self, credentials: credentialsPatch.isEmpty ? nil : Self.putCredentials(storedCredentials, credentialsPatch),
                                               extra: extraPatch.isEmpty ? nil : Self.merged(storedExtra, extraPatch)))
    }
    /// The server merges `credentials` only when it has keys, so emptying them would send a `{}` it skips while answering 200;
    /// the deleted keys go out as null instead, which the server stores as missing and keeps the secrets beside.
    static func putCredentials(_ base: [String: JSONValue], _ patch: [String: JSONPatchValue]) -> [String: JSONValue] {
        let merged = Self.merged(base, patch)
        return merged.isEmpty ? patch.filter { $0.value.isDeletion }.mapValues { _ in .null } : merged
    }
    /// A copy that answers the mixed-channel warning; a keyed write sends it under a new key (00 §2.5.2).
    public func confirmingMixedChannel() -> AccountPatchRequest {
        var copy = self; copy.confirmMixedChannelRisk = true; return copy
    }
    /// `.set` replaces, a deletion removes.
    static func merged(_ base: [String: JSONValue], _ patch: [String: JSONPatchValue]) -> [String: JSONValue] {
        let values = patch.compactMapValues { change -> JSONValue? in
            guard case .set(let value) = change, !change.isDeletion else { return nil }
            return value
        }
        return base.filter { patch[$0.key] == nil }.merging(values) { _, new in new }
    }
    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try encodeTopLevel(into: &c)
        if !credentialsPatch.isEmpty { try c.encode(credentialsPatch, forKey: .credentialsPatch) }
        if !extraPatch.isEmpty { try c.encode(extraPatch, forKey: .extraPatch) }
    }
    fileprivate func encodeTopLevel(into c: inout KeyedEncodingContainer<CodingKeys>) throws {
        for (key, value) in topLevelValues { try c.encode(value, forKey: key) }
        try c.encodeIfPresent(confirmMixedChannelRisk, forKey: .confirmMixedChannelRisk)
    }
}

extension AccountPatchRequest: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Key names only (S2D1-10): any value can be a secret.
    public var description: String {
        let flag = confirmMixedChannelRisk == nil ? [] : [CodingKeys.confirmMixedChannelRisk.stringValue]
        let keys = topLevelValues.map { $0.key.stringValue } + flag
            + credentialsPatch.keys.sorted().map { "credentials_patch.\($0)=<redacted>" } + extraPatch.keys.sorted().map { "extra_patch.\($0)=<redacted>" }
        return "AccountPatchRequest(\(keys.joined(separator: ", ")))"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

private struct FullUpdateBody: Encodable {
    let request: AccountPatchRequest
    let credentials: [String: JSONValue]?
    let extra: [String: JSONValue]?
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AccountPatchRequest.CodingKeys.self)
        try request.encodeTopLevel(into: &c)
        try c.encodeIfPresent(credentials, forKey: .credentials)
        try c.encodeIfPresent(extra, forKey: .extra)
    }
}

extension APIClient {
    /// PATCH with If-Match (20 §0.4-5): an unkeyed write, sent once (00 §2.4); only a TOKEN_EXPIRED refresh resends the same bytes
    /// and version. A 412 carries the current ETag (AccountPatchConflict.currentETag), a 409 the mixed group (MixedChannelWarning).
    /// The reply's ETag is the next If-Match.
    public func patchAccount(id: Int, body: AccountPatchRequest, ifMatch: String) async throws -> VersionedAccount {
        let tag = ifMatch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { throw AccountPatchRequest.invalid("缺少账号版本号，请先刷新账号。") }
        let path = try accountPath(id), bytes = try body.requestBody()
        let response: APIResponse<UpstreamAccount> = try await requestWithHeaders(path, method: "PATCH", body: bytes, headers: ["If-Match": tag])
        let etag = response.header("ETag")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VersionedAccount(account: response.value, etag: etag?.isEmpty == false ? etag : nil)
    }
    /// The fallback without `accounts.patch`: PUT of `fullUpdateBody(base:)`, read nothing first. A retry of the same intent passes
    /// the same key and base. With a key (admin.idempotent_writes, R05) transport failures are retried under it and an unanswered
    /// write ends as KeyedWriteFailure (00 §2.5.4); without one it is sent once. A replayed reply may hold an older snapshot.
    public func fullUpdate(id: Int, patch: AccountPatchRequest, base: UpstreamAccount?, idempotencyKey: UUID? = nil,
                           onEvent: KeyedWriteEventHandler? = nil) async throws -> UpstreamAccount {
        let path = try accountPath(id)
        if let base, base.id != id { throw AccountPatchRequest.invalid("账号详情与要修改的账号不一致，请刷新后重试。") }
        let outcome: WriteOutcome<UpstreamAccount> = try await accountWrite(path, method: "PUT", body: patch.fullUpdateBody(base: base),
                                                                           key: idempotencyKey, onEvent: onEvent)
        return outcome.value
    }
}
