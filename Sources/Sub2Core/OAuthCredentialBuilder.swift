import Foundation

/// `type`, `credentials` and `extra` for apply-oauth-credentials or a new account. Holds the token: not Codable, never printed.
public struct OAuthCredentials: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let type: OAuthAuthKind
    public let credentials: [String: JSONValue]
    /// nil when empty.
    public let extra: [String: JSONValue]?
    init(type: OAuthAuthKind, credentials: [String: JSONValue], extra: [String: JSONValue]?) {
        self.type = type; self.credentials = credentials; self.extra = extra?.isEmpty == false ? extra : nil
    }
    public var description: String { "OAuthCredentials(\(type.rawValue), \(credentials.count) keys, <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["type": type]) }
}

/// Web's composables word for word (useAccountOAuth / useOpenAIOAuth / useGeminiOAuth / useAntigravityOAuth / useGrokOAuth
/// `buildCredentials` and `buildExtraInfo`). apply-oauth-credentials merges key by key, so Gemini and Antigravity leave out empty
/// strings that would overwrite a stored refresh token; the server's Claude reply has no empty optional keys.
public enum OAuthCredentialBuilder {
    public static func build(_ token: OAuthTokenInfo) -> OAuthCredentials {
        let fields = token.fields
        switch token.platform {
        case .anthropic:
            return OAuthCredentials(type: token.kind, credentials: fields, extra: truthy(fields, ["org_uuid", "account_uuid", "email_address"]))
        case .openai:
            let required = fields.filter { ["access_token", "expires_at"].contains($0.key) && $0.value != .null }
            let optional = truthy(fields, ["refresh_token", "id_token", "email", "chatgpt_account_id", "chatgpt_user_id", "organization_id",
                                           "plan_type", "subscription_expires_at", "client_id"])
            return OAuthCredentials(type: .oauth, credentials: required.merging(optional) { first, _ in first },
                                    extra: truthy(fields, ["email", "name", "privacy_mode"]))
        case .gemini:
            let picked = present(fields, ["access_token", "refresh_token", "token_type", "scope", "project_id", "oauth_type", "tier_id"])
            return OAuthCredentials(type: .oauth, credentials: withExpiry(picked, fields["expires_at"]), extra: fields["extra"]?.objectValue)
        case .antigravity:
            let picked = present(fields, ["access_token", "refresh_token", "token_type", "project_id", "email", "plan_type"])
            return OAuthCredentials(type: .oauth, credentials: withExpiry(picked, fields["expires_at"]), extra: nil)
        case .grok:
            // Only these keys: base_url stays unset (system / CLI mode picks the host) and SSO cookies or passwords never get here.
            let picked = present(fields, ["access_token", "token_type", "expires_at", "client_id", "scope", "email", "sub", "team_id",
                                          "subscription_tier", "entitlement_status", "refresh_token", "id_token"])
            return OAuthCredentials(type: .oauth, credentials: picked, extra: truthy(fields, ["email", "subscription_tier", "entitlement_status"]))
        }
    }

    /// JavaScript's `if (value)`.
    private static func truthy(_ fields: [String: JSONValue], _ keys: [String]) -> [String: JSONValue] {
        fields.filter { keys.contains($0.key) && isTruthy($0.value) }
    }
    private static func isTruthy(_ value: JSONValue) -> Bool {
        switch value {
        case .null: false
        case .bool(let flag): flag
        case .number(let number): !number.isZero
        case .string(let text): !text.isEmpty
        case .array, .object: true
        }
    }
    /// Present, not null and not an empty string.
    private static func present(_ fields: [String: JSONValue], _ keys: [String]) -> [String: JSONValue] {
        fields.filter { keys.contains($0.key) && $0.value != .null && $0.value != .string("") }
    }
    /// Gemini / Antigravity store `expires_at` as a string: a number rounded down, a string trimmed.
    private static func withExpiry(_ credentials: [String: JSONValue], _ raw: JSONValue?) -> [String: JSONValue] {
        var result = credentials
        switch raw {
        case .number(var number)?:
            var whole = Decimal()
            NSDecimalRound(&whole, &number, 0, .down)
            result["expires_at"] = .string(whole.description)
        case .string(let text)? where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            result["expires_at"] = .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: break
        }
        return result
    }
}

/// 20 §6.3 step 3: Claude's code goes as pasted (with its `#state`, checked by the server); the callback platforms take `code`
/// and `state` from a pasted link or query string (Web OAuthAuthorizationFlow.vue). Gemini accepts both forms.
public enum OAuthCallback {
    public enum Parsed: Sendable, Equatable {
        case code(OAuthCode)
        /// `error=access_denied`: the admin refused on the provider page.
        case denied
        /// A callback without a code.
        case invalid
        case empty
    }

    public static func parse(_ input: String, platform: OAuthPlatform) -> Parsed {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        guard platform != .anthropic, looksLikeCallback(text) else { return .code(OAuthCode(value: text)) }
        let items = queryItems(text)
        if let code = items["code"].flatMap({ OAuthLinkRequest.nonEmpty($0) }) { return .code(OAuthCode(value: code, state: items["state"])) }
        return items["error"] == "access_denied" ? .denied : .invalid
    }

    private static func looksLikeCallback(_ text: String) -> Bool {
        ["?", "://", "code=", "error="].contains { text.contains($0) }
    }
    /// URLComponents first (values come back percent-decoded); a link it rejects, one with a space for example, is read
    /// with a plain pattern search.
    private static func queryItems(_ text: String) -> [String: String] {
        let link = text.contains("?") ? text : "http://localhost/callback?" + text
        if let items = URLComponents(string: link)?.queryItems {
            return items.reduce(into: [:]) { result, item in
                if result[item.name] == nil, let value = item.value { result[item.name] = value }
            }
        }
        return ["code", "state", "error"].reduce(into: [:]) { result, name in result[name] = patternValue(name, in: text) }
    }
    private static func patternValue(_ name: String, in text: String) -> String? {
        guard let range = text.range(of: "[?&]\(name)=[^&#]+", options: .regularExpression) else { return nil }
        let match = text[range]
        guard let equals = match.firstIndex(of: "=") else { return nil }
        let raw = String(match[match.index(after: equals)...])
        return raw.removingPercentEncoding ?? raw
    }
}
