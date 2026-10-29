import Foundation

/// 20 §6.2: the platforms whose OAuth accounts the App can authorize. The raw value is the account's `platform`.
public enum OAuthPlatform: String, Sendable, CaseIterable {
    case anthropic, openai, gemini, antigravity, grok

    public init?(accountPlatform: String) {
        self.init(rawValue: accountPlatform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
    /// “登录 {平台} 并授权” (design AN_OAUTH `who`).
    public var signInName: String {
        switch self {
        case .anthropic: "Claude"
        case .openai: "ChatGPT"
        case .gemini, .antigravity: "Google"
        case .grok: "xAI"
        }
    }
    /// “服务器连不上 {平台}”.
    public var upstreamName: String {
        switch self {
        case .anthropic: "Claude"
        case .openai: "OpenAI"
        case .gemini, .antigravity: "Google"
        case .grok: "xAI"
        }
    }
    /// The provider page shows a code to copy; the others redirect to a local callback address.
    public var showsCode: Bool { self == .anthropic || self == .gemini }
    public var callbackAddress: String? {
        switch self {
        case .openai: "localhost:1455"
        case .antigravity: "localhost:8085"
        case .grok: "127.0.0.1:56121"
        case .anthropic, .gemini: nil
        }
    }
    public var callbackPort: UInt16? {
        switch self {
        case .openai: 1455
        case .antigravity: 8085
        case .grok: 56121
        case .anthropic, .gemini: nil
        }
    }
    /// Grok uses up its session before calling xAI, so any failed exchange needs a new link.
    public var consumesSessionOnExchange: Bool { self == .grok }

    func authURLPath(_ kind: OAuthAuthKind) -> String {
        switch self {
        case .anthropic: kind == .setupToken ? "admin/accounts/generate-setup-token-url" : "admin/accounts/generate-auth-url"
        case .openai: "admin/openai/generate-auth-url"
        case .gemini, .antigravity, .grok: "admin/\(rawValue)/oauth/auth-url"
        }
    }
    func exchangePath(_ kind: OAuthAuthKind) -> String {
        switch self {
        case .anthropic: kind == .setupToken ? "admin/accounts/exchange-setup-token-code" : "admin/accounts/exchange-code"
        case .openai: "admin/openai/exchange-code"
        case .gemini, .antigravity, .grok: "admin/\(rawValue)/oauth/exchange-code"
        }
    }
}

/// Claude's two methods; the raw value is the account `type` and `auth_kind`.
public enum OAuthAuthKind: String, Sendable, CaseIterable {
    case oauth, setupToken = "setup-token"
    public init?(accountType: String) { self.init(rawValue: accountType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
    public var title: String { self == .oauth ? "OAuth" : "Setup Token" }
    public var scopeNote: String { self == .oauth ? "完整权限" : "只授予推理权限" }
}

/// Gemini's `oauth_type`.
public enum GeminiOAuthType: String, Sendable, CaseIterable {
    case codeAssist = "code_assist", googleOne = "google_one", aiStudio = "ai_studio"
    /// Like Web's ReAuthAccountModal: anything else, missing included, is Code Assist.
    public init(credentialValue: String?) {
        self = Self(rawValue: credentialValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? .codeAssist
    }
    public var title: String {
        switch self {
        case .codeAssist: "Code Assist"
        case .googleOne: "Google One"
        case .aiStudio: "AI Studio"
        }
    }
}

/// What generate-auth-url is asked for. Each field is sent only where the platform reads it.
public struct OAuthLinkRequest: Sendable, Equatable {
    public let platform: OAuthPlatform
    public let kind: OAuthAuthKind
    /// nil (and ≤ 0) sends no `proxy_id`.
    public let proxyID: Int?
    /// `account_id`, Grok only.
    public let accountID: Int?
    /// `oauth_type`, Gemini only.
    public let geminiOAuthType: GeminiOAuthType
    /// `project_id`, Gemini Code Assist only.
    public let projectID: String?
    /// `tier_id`, Gemini only.
    public let tierID: String?

    public init(platform: OAuthPlatform, kind: OAuthAuthKind = .oauth, proxyID: Int? = nil, accountID: Int? = nil,
                geminiOAuthType: GeminiOAuthType = .codeAssist, projectID: String? = nil, tierID: String? = nil) {
        self.platform = platform; self.kind = kind
        self.proxyID = proxyID.flatMap { $0 > 0 ? $0 : nil }; self.accountID = accountID.flatMap { $0 > 0 ? $0 : nil }
        self.geminiOAuthType = geminiOAuthType; self.projectID = Self.nonEmpty(projectID); self.tierID = Self.nonEmpty(tierID)
    }
    /// The account's own proxy (20 §6.2), method (Claude) and Gemini type and tier; nil for a platform without OAuth here.
    public static func reauthorize(_ account: UpstreamAccount, kind: OAuthAuthKind? = nil, geminiOAuthType: GeminiOAuthType? = nil,
                                   projectID: String? = nil) -> OAuthLinkRequest? {
        guard let platform = OAuthPlatform(accountPlatform: account.platform) else { return nil }
        let method = platform == .anthropic ? kind ?? OAuthAuthKind(accountType: account.type) ?? .oauth : .oauth
        let type = geminiOAuthType ?? GeminiOAuthType(credentialValue: account.credentials?["oauth_type"]?.stringValue)
        return OAuthLinkRequest(platform: platform, kind: method, proxyID: account.proxyID, accountID: account.id, geminiOAuthType: type,
                                projectID: projectID, tierID: account.credentials?["tier_id"]?.stringValue)
    }

    fileprivate var body: AuthURLBody {
        let gemini = platform == .gemini
        return AuthURLBody(proxy_id: proxyID, account_id: platform == .grok ? accountID : nil, oauth_type: gemini ? geminiOAuthType.rawValue : nil,
                           project_id: gemini && geminiOAuthType == .codeAssist ? projectID : nil, tier_id: gemini ? tierID : nil)
    }
    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// The authorization session lives 30 minutes on the server. Measured on this device's monotonic clock from the moment the
/// link was asked for (20 §0.6), so neither a changed device time nor the server's clock offset moves it.
public struct OAuthLinkLifetime: Sendable, Equatable {
    public static let validity: Duration = .seconds(1_800)
    public let generatedAt: ContinuousClock.Instant
    public init(generatedAt: ContinuousClock.Instant) { self.generatedAt = generatedAt }
    public func remaining(at now: ContinuousClock.Instant) -> Duration { max(.zero, Self.validity - (now - generatedAt)) }
    /// For DisplayFormat.countdown.
    public func remainingSeconds(at now: ContinuousClock.Instant) -> TimeInterval {
        let parts = remaining(at: now).components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
    public func isExpired(at now: ContinuousClock.Instant) -> Bool { remaining(at: now) == .zero }
}

/// A generated link. Printing shows the platform and method only, never the session or state.
public struct OAuthLink: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let request: OAuthLinkRequest
    /// https with a host.
    public let authURL: URL
    public let sessionID: String
    /// The reply's `state`, or the link's `state` query item (OpenAI only puts it in the link).
    public let state: String?
    public let lifetime: OAuthLinkLifetime
    public init(request: OAuthLinkRequest, authURL: URL, sessionID: String, state: String?, lifetime: OAuthLinkLifetime) {
        self.request = request; self.authURL = authURL; self.sessionID = sessionID; self.state = state; self.lifetime = lifetime
    }
    public var platform: OAuthPlatform { request.platform }
    public var description: String { "OAuthLink(\(platform.rawValue), \(request.kind.rawValue))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["platform": platform, "kind": request.kind]) }
}

/// What the admin pasted: Claude's code as is (with its `#state`), or the code and state taken from a callback link.
public struct OAuthCode: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let value: String
    /// The callback's state; nil means the link's own state is sent.
    public let state: String?
    public init(value: String, state: String? = nil) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines); self.state = OAuthLinkRequest.nonEmpty(state)
    }
    public var description: String { "OAuthCode(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// An exchange-code reply. Held in memory only until apply-oauth-credentials (or account creation) succeeds: not Codable,
/// never printed, logged or put in a receipt or an error.
public struct OAuthTokenInfo: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let platform: OAuthPlatform
    public let kind: OAuthAuthKind
    /// For OAuthCredentialBuilder.
    let fields: [String: JSONValue]
    init(platform: OAuthPlatform, kind: OAuthAuthKind, fields: [String: JSONValue]) throws {
        guard let token = fields["access_token"]?.stringValue, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.invalidResponse
        }
        self.platform = platform; self.kind = kind; self.fields = fields
    }
    /// Only for tests and the -ui-testing fixtures; the App gets one from `exchangeCode`.
    public static func fixture(platform: OAuthPlatform, kind: OAuthAuthKind = .oauth, fields: [String: JSONValue]) throws -> OAuthTokenInfo {
        try OAuthTokenInfo(platform: platform, kind: kind, fields: fields)
    }
    /// For “已授权 · {邮箱}”.
    public var accountEmail: String? { OAuthLinkRequest.nonEmpty(fields[platform == .anthropic ? "email_address" : "email"]?.stringValue) }
    public var description: String { "OAuthTokenInfo(\(platform.rawValue), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["platform": platform, "kind": kind]) }
}

/// `POST :id/reauthorize` (account_reauthorize.go:36-46): the token stays on the server. No `preserve_status` (U19) and no
/// `redirect_uri`; nil fields are left out and the keys are sorted, so a retry sends the same bytes and session.
public struct AccountReauthorizeRequest: Encodable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let sessionID: String
    public let code: String
    public let state: String?
    public let proxyID: Int?
    /// Claude only.
    public let authKind: OAuthAuthKind?
    /// Gemini only, with `tierID`.
    public let oauthType: GeminiOAuthType?
    public let tierID: String?
    /// Throws a validation error, before anything is sent, when a platform that checks state has none.
    public init(link: OAuthLink, code: OAuthCode) throws {
        let request = link.request
        sessionID = link.sessionID; self.code = try OAuthExchange.codeValue(code)
        state = try OAuthExchange.state(link, code)
        proxyID = request.proxyID
        authKind = request.platform == .anthropic ? request.kind : nil
        oauthType = request.platform == .gemini ? request.geminiOAuthType : nil
        tierID = request.platform == .gemini ? request.tierID : nil
    }
    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id", code, state, proxyID = "proxy_id", authKind = "auth_kind", oauthType = "oauth_type", tierID = "tier_id"
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessionID, forKey: .sessionID); try c.encode(code, forKey: .code)
        try c.encodeIfPresent(state, forKey: .state); try c.encodeIfPresent(proxyID, forKey: .proxyID)
        try c.encodeIfPresent(authKind?.rawValue, forKey: .authKind); try c.encodeIfPresent(oauthType?.rawValue, forKey: .oauthType)
        try c.encodeIfPresent(tierID, forKey: .tierID)
    }
    public var description: String { "AccountReauthorizeRequest(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

private struct AuthURLBody: Encodable {
    let proxy_id: Int?
    let account_id: Int?
    let oauth_type: String?
    let project_id: String?
    let tier_id: String?
}
private struct AuthURLReply: Decodable, Sendable {
    let auth_url: String?
    let session_id: String?
    let state: String?
}
private struct ExchangeBody: Encodable {
    let account_id: Int?
    let code: String
    let oauth_type: String?
    let proxy_id: Int?
    let session_id: String
    let state: String?
    let tier_id: String?
}
private struct ApplyBody: Encodable {
    let credentials: [String: JSONValue]
    let extra: [String: JSONValue]?
    let type: String
}

/// The checks shared by exchange-code and reauthorize.
enum OAuthExchange {
    static func codeValue(_ code: OAuthCode) throws -> String {
        guard !code.value.isEmpty else { throw APIError(kind: .validation, message: "请粘贴授权码。") }
        return code.value
    }
    /// Claude's state travels inside the code; every other platform checks a state, so none means nothing is sent.
    static func state(_ link: OAuthLink, _ code: OAuthCode) throws -> String? {
        guard link.platform != .anthropic else { return nil }
        guard let state = code.state ?? link.state else { throw APIError(kind: .validation, message: "回调链接里没有 state，请粘贴完整的回调链接。") }
        return state
    }
    fileprivate static func link(_ reply: AuthURLReply, request: OAuthLinkRequest, generatedAt: ContinuousClock.Instant) throws -> OAuthLink {
        guard let raw = OAuthLinkRequest.nonEmpty(reply.auth_url), let url = URL(string: raw), url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false, let session = OAuthLinkRequest.nonEmpty(reply.session_id) else { throw APIError.invalidResponse }
        let linked = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value
        return OAuthLink(request: request, authURL: url, sessionID: session, state: OAuthLinkRequest.nonEmpty(reply.state) ?? OAuthLinkRequest.nonEmpty(linked),
                         lifetime: OAuthLinkLifetime(generatedAt: generatedAt))
    }
}

extension APIClient {
    /// 20 §6.2 generate-auth-url. Like the other three calls here, a POST without a key: 30 seconds, sent once (00 §2.3, §2.4).
    public func generateAuthURL(_ request: OAuthLinkRequest) async throws -> OAuthLink {
        guard request.kind == .oauth || request.platform == .anthropic else {
            throw APIError(kind: .validation, message: "只有 Claude 账号可以用 Setup Token 授权。")
        }
        let generatedAt = ContinuousClock.now
        let reply: AuthURLReply = try await self.request(request.platform.authURLPath(request.kind), method: "POST", body: encode(request.body))
        return try OAuthExchange.link(reply, request: request, generatedAt: generatedAt)
    }
    /// The fallback without accounts.reauthorize, and new accounts. `proxyID` is the caller's: the network section's proxy for a new
    /// account, the account's own for the fallback.
    public func exchangeCode(_ link: OAuthLink, code: OAuthCode, proxyID: Int?) async throws -> OAuthTokenInfo {
        let request = link.request
        let gemini = request.platform == .gemini
        let body = ExchangeBody(account_id: request.platform == .grok ? request.accountID : nil, code: try OAuthExchange.codeValue(code),
                                oauth_type: gemini ? request.geminiOAuthType.rawValue : nil, proxy_id: proxyID.flatMap { $0 > 0 ? $0 : nil },
                                session_id: link.sessionID, state: try OAuthExchange.state(link, code), tier_id: gemini ? request.tierID : nil)
        let reply: JSONValue = try await self.request(request.platform.exchangePath(request.kind), method: "POST", body: encode(body))
        guard let fields = reply.objectValue else { throw APIError.invalidResponse }
        return try OAuthTokenInfo(platform: request.platform, kind: request.kind, fields: fields)
    }
    public func reauthorize(accountID: Int, request: AccountReauthorizeRequest) async throws -> UpstreamAccount {
        try await self.request(accountPath(accountID, "/reauthorize"), method: "POST", body: encode(request))
    }
    /// The fallback's last step: stores the token and clears the account's blocks (the schedule switch stays). No `preserve_status`.
    public func applyOAuthCredentials(accountID: Int, type: OAuthAuthKind, credentials: [String: JSONValue],
                                      extra: [String: JSONValue]?) async throws -> UpstreamAccount {
        let path = try accountPath(accountID, "/apply-oauth-credentials")
        guard let token = credentials["access_token"]?.stringValue, !token.isEmpty else {
            throw APIError(kind: .validation, message: "授权结果里没有访问令牌，请重新授权。")
        }
        return try await request(path, method: "POST", body: encode(ApplyBody(credentials: credentials, extra: extra, type: type.rawValue)))
    }
}
