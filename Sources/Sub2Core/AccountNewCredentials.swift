import Foundation

/// An authorization from exchange-code, built by OAuthCredentialBuilder (S2D1-03). Memory only, dropped with the form (U16).
public struct AccountNewOAuthGrant: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let platform: OAuthPlatform
    public let type: OAuthAuthKind
    let credentials: [String: JSONValue]
    let extra: [String: JSONValue]?
    /// “已授权 · {邮箱}”.
    public let email: String?
    public init(_ token: OAuthTokenInfo) {
        let built = OAuthCredentialBuilder.build(token)
        self.init(platform: token.platform, type: built.type, credentials: built.credentials, extra: built.extra, email: token.accountEmail)
    }
    init(platform: OAuthPlatform, type: OAuthAuthKind, credentials: [String: JSONValue], extra: [String: JSONValue]? = nil, email: String? = nil) {
        self.platform = platform; self.type = type; self.credentials = credentials; self.extra = extra?.isEmpty == false ? extra : nil; self.email = email
    }
    public var description: String { "AccountNewOAuthGrant(\(platform.rawValue), \(type.rawValue), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// A Service Account JSON picked from Files. The text goes only into the request body; the project and e-mail are shown.
public struct VertexServiceAccountFile: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let maxBytes = 65_536
    public let fileName: String
    public let projectID: String
    public let clientEmail: String
    /// Trimmed file text, sent as `service_account_json` (the backend reads a string or an object).
    let rawText: String
    /// The backend's parseVertexServiceAccountJSON needs project_id, client_email and private_key; the messages are the Web's.
    public init(fileName: String, data: Data) throws {
        let invalid = APIError(kind: .validation, message: "Service Account JSON 格式无效")
        guard data.count <= Self.maxBytes, let text = String(data: data, encoding: .utf8),
              let fields = try? JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8)) else { throw invalid }
        let values = ["project_id", "client_email", "private_key"].map { fields[$0]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        guard !values.contains(where: \.isEmpty) else {
            throw APIError(kind: .validation, message: "Service Account JSON 缺少 project_id、client_email 或 private_key")
        }
        self.fileName = fileName; projectID = values[0]; clientEmail = values[1]
        rawText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public var description: String { "VertexServiceAccountFile(\(fileName), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// The `type`, `credentials` and `extra` a draft creates.
public struct AccountNewCredentials: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let type: String
    public let credentials: [String: JSONValue]
    /// nil when empty.
    public let extra: [String: JSONValue]?
    init(type: String, credentials: [String: JSONValue], extra: [String: JSONValue]? = nil) {
        self.type = type; self.credentials = credentials; self.extra = extra?.isEmpty == false ? extra : nil
    }
    public var description: String { "AccountNewCredentials(\(type), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

// MARK: - Building the request (20 §7.2, Web CreateAccountModal)

extension AccountNewDraft {
    /// The credentials table of 20 §7.2; every string is trimmed. Throws while a platform, method or credential is missing or
    /// an address is malformed.
    public func builtCredentials() throws -> AccountNewCredentials {
        guard let platform, let method else { throw Self.invalid("还差 \(platform == nil ? "平台" : "认证方式")") }
        if let issue = issues.first { throw Self.invalid(issue.message) }
        if let label = missingCredentialLabel { throw Self.invalid("还差 \(label)") }
        switch method.kind {
        case .oauth:
            guard let grant = oauthGrant else { throw Self.invalid("还差 \(method.credentialLabel)") }
            return AccountNewCredentials(type: grant.type.rawValue, credentials: grant.credentials, extra: antigravityExtra(over: grant.extra))
        case .apiKey: return AccountNewCredentials(type: "apikey", credentials: apiKeyCredentials(platform))
        case .multiProtocol(let mode): return AccountNewCredentials(type: "apikey", credentials: modeCredentials(mode, method: method))
        case .upstream:
            return AccountNewCredentials(type: "apikey", credentials: ["base_url": .string(Self.trim(upstreamBaseURL)), "api_key": .string(Self.trim(upstreamAPIKey))],
                                         extra: antigravityExtra(over: nil))
        case .bedrock: return AccountNewCredentials(type: "bedrock", credentials: bedrockCredentials())
        case .vertex: return AccountNewCredentials(type: "service_account", credentials: vertexCredentials())
        }
    }

    /// The form's ranges first, then the backend's own check. `upstream_billing_probe_enabled` is on for apikey accounts as in the
    /// Web form (on a legacy server for OpenAI's only) and left out otherwise; `auto_pause_on_expired` is always sent.
    public func createRequest(confirmMixedChannel: Bool = false) throws -> AccountCreateRequest {
        guard let platform else { throw Self.invalid("还差 平台") }
        try validateSetup()
        let built = try builtCredentials()
        let request = AccountCreateRequest(name: name, notes: notes, platform: platform, type: built.type, credentials: built.credentials, extra: built.extra,
                                           proxyID: proxyID, concurrency: concurrency, priority: priority, rateMultiplier: rateMultiplier,
                                           loadFactor: loadFactor, groupIDs: groupIDs, expiresAt: expiresAt, autoPauseOnExpired: autoPauseOnExpired,
                                           upstreamBillingProbeEnabled: sendsBillingProbe(type: built.type, platform: platform) ? true : nil,
                                           confirmMixedChannelRisk: confirmMixedChannel)
        try request.validate()
        return request
    }

    /// “保存并重新测试” after the account exists (20 §7.2, §7.4-2): only what differs from `saved` (the draft the server holds).
    /// The platform cannot change; the type can. Credentials and extra go as *_patch. A secret key cannot be deleted
    /// (CREDENTIAL_KEY_NOT_DELETABLE), so one the form no longer holds is set to "", which the server reads as unset: a cleared
    /// session token or a dropped grant's refresh token must not stay in use. No mixed-channel flag.
    public func patch(since saved: AccountNewDraft) throws -> AccountPatchRequest {
        let old = try saved.createRequest(), new = try createRequest()
        guard old.platform == new.platform else { throw Self.invalid("已创建的账号不能更换平台。") }
        var patch = AccountPatchRequest()
        if new.name != old.name { patch.name = new.name }
        if new.notes != old.notes { patch.notes = new.notes ?? "" }
        if new.type != old.type { patch.type = new.type }
        if new.proxyID != old.proxyID { patch.proxyID = new.proxyID ?? 0 }
        if new.concurrency != old.concurrency { patch.concurrency = new.concurrency }
        if new.priority != old.priority { patch.priority = new.priority }
        if new.rateMultiplier != old.rateMultiplier { patch.rateMultiplier = new.rateMultiplier }
        if new.loadFactor != old.loadFactor { patch.loadFactor = new.loadFactor ?? 0 }
        if new.groupIDs != old.groupIDs { patch.groupIDs = new.groupIDs }
        if new.expiresAt != old.expiresAt { patch.expiresAt = new.expiresAt ?? 0 }
        if new.autoPauseOnExpired != old.autoPauseOnExpired { patch.autoPauseOnExpired = new.autoPauseOnExpired }
        if new.upstreamBillingProbeEnabled != old.upstreamBillingProbeEnabled { patch.upstreamBillingProbeEnabled = new.upstreamBillingProbeEnabled ?? false }
        patch.credentialsPatch = Self.changes(from: old.credentials, to: new.credentials) { AccountCredentialKeys.isSensitive($0) ? .set("") : .delete }
        patch.extraPatch = Self.changes(from: old.extra ?? [:], to: new.extra ?? [:]) { _ in .delete }
        return patch
    }
    /// A draft that cannot be built yet counts as changed: the dock says “保存并重新测试” and the 还差 list keeps it disabled.
    public func hasChanges(since saved: AccountNewDraft) -> Bool { (try? patch(since: saved).hasChanges) ?? true }

    // MARK: - Internals

    private func validateSetup() throws {
        if Self.isBlank(name) { throw Self.invalid("请输入账号名称") }
        if !AccountNewDefaults.concurrencyRange.contains(concurrency) { throw Self.invalid("并发数为 1–100 的整数") }
        if !AccountNewDefaults.priorityRange.contains(priority) { throw Self.invalid("优先级为 1–99 的整数") }
        if let loadFactor, !AccountNewDefaults.loadFactorRange.contains(loadFactor) { throw Self.invalid("负载因子为 1–10 的整数，可以不填") }
        if rateMultiplier == nil { throw Self.invalid("请填写账号计费倍率（0 表示不计费）") }
    }
    /// f3a3d8684 (2026-07-26) opened the probe to every API Key platform; the servers just before it reject it but for OpenAI
    /// (UPSTREAM_BILLING_PROBE_ACCOUNT_INVALID) and older ones ignore it. Every server with `/admin/me` is newer.
    private func sendsBillingProbe(type: String, platform: String) -> Bool {
        type == "apikey" && (!isLegacyServer || platform == OAuthPlatform.openai.rawValue)
    }
    private func apiKeyCredentials(_ platform: String) -> [String: JSONValue] {
        let base = Self.trim(baseURL)
        var credentials: [String: JSONValue] = ["api_key": .string(Self.trim(apiKey)),
                                                "base_url": .string(base.isEmpty ? AccountNewCatalog.officialBaseURL(for: platform) : base)]
        if platform == OAuthPlatform.gemini.rawValue, AccountNewCatalog.isOfficialGeminiBaseURL(baseURL) {
            credentials["tier_id"] = .string(AccountNewDefaults.geminiAIStudioTier)
        }
        return credentials
    }
    /// account_mode and api_protocol; adaptive sends every native endpoint with base_url its chat one, a concrete protocol the
    /// endpoint picked (catalog, preset or custom). protocol_rules are left to the backend's catalog defaults.
    private func modeCredentials(_ mode: MetaCatalog.Mode, method: AccountNewMethod) -> [String: JSONValue] {
        let apiProtocol = effectiveProtocol ?? AccountProtocolEndpoints.adaptive
        var credentials: [String: JSONValue] = ["api_key": .string(Self.trim(apiKey)), "account_mode": .string(mode.mode), "api_protocol": .string(apiProtocol)]
        guard apiProtocol == AccountProtocolEndpoints.adaptive else {
            if let endpoint = concreteEndpoint(method, apiProtocol: apiProtocol) { credentials["base_url"] = .string(endpoint) }
            return credentials
        }
        let endpoints = AccountProtocolEndpoints.nativeProtocolOrder.compactMap { name in method.officialEndpoint(for: name).map { (name, $0) } }
        credentials["api_base_urls"] = .object(Dictionary(endpoints.map { ($0.0, JSONValue.string($0.1)) }) { first, _ in first })
        if let chat = endpoints.first(where: { $0.0 == "chat_completions" }) ?? endpoints.first { credentials["base_url"] = .string(chat.1) }
        return credentials
    }
    private func bedrockCredentials() -> [String: JSONValue] {
        let region = Self.trim(awsRegion)
        var credentials: [String: JSONValue] = ["auth_mode": .string(bedrockAuth.rawValue),
                                                "aws_region": .string(region.isEmpty ? AccountNewDefaults.bedrockRegion : region)]
        switch bedrockAuth {
        case .sigv4:
            credentials["aws_access_key_id"] = .string(Self.trim(awsAccessKeyID))
            credentials["aws_secret_access_key"] = .string(Self.trim(awsSecretAccessKey))
            if !Self.isBlank(awsSessionToken) { credentials["aws_session_token"] = .string(Self.trim(awsSessionToken)) }
        case .apikey:
            credentials["api_key"] = .string(Self.trim(bedrockAPIKey))
        }
        return credentials
    }
    private func vertexCredentials() -> [String: JSONValue] {
        guard let vertexFile else { return [:] }
        let location = Self.trim(vertexLocation)
        return ["service_account_json": .string(vertexFile.rawText), "project_id": .string(vertexFile.projectID), "client_email": .string(vertexFile.clientEmail),
                "location": .string(location.isEmpty ? AccountNewDefaults.vertexLocation : location), "tier_id": "vertex"]
    }
    /// Antigravity's switches, only those that are on (Web buildAntigravityExtra), over the grant's own extra.
    private func antigravityExtra(over base: [String: JSONValue]?) -> [String: JSONValue]? {
        guard platform == OAuthPlatform.antigravity.rawValue else { return base }
        var extra = base ?? [:]
        if mixedScheduling { extra["mixed_scheduling"] = true }
        if allowOverages { extra["allow_overages"] = true }
        return extra
    }
    /// New or changed keys are set; a removed key gets `removal`'s value.
    private static func changes(from old: [String: JSONValue], to new: [String: JSONValue],
                                removal: (String) -> JSONPatchValue) -> [String: JSONPatchValue] {
        var patch = new.filter { old[$0.key] != $0.value }.mapValues(JSONPatchValue.set)
        for key in old.keys where new[key] == nil { patch[key] = removal(key) }
        return patch
    }
    private static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func invalid(_ message: String) -> APIError { APIError(kind: .validation, message: message) }
}
