import Foundation

/// 20 §3.3 高级 账号类型 / API 协议 of a multi-protocol API Key account (a catalog platform with `multi_protocol`), read like the
/// backend's GetAccountMode / GetOpenCodeAccountMode / GetAPIProtocol. Without the explicit protocol the backend sends to
/// `base_url` (adaptive: `api_base_urls`, by-model platforms: `protocol_rules`), so a switch moves those along the way the Web
/// edit dialog does — only while they are the providers' presets (or missing, which means the preset). A custom endpoint leaves
/// both rows to the Web (20 §3.3: the endpoints are not edited on the phone).
public struct AccountProtocolEndpoints: Equatable, Sendable {
    public static let adaptive = "adaptive"
    public static let nativeProtocolOrder = ["chat_completions", "anthropic", "responses"]
    static let modeKey = "account_mode", protocolKey = "api_protocol", baseURLKey = "base_url", baseURLsKey = "api_base_urls", rulesKey = "protocol_rules"
    static let credentialKeys: Set<String> = [modeKey, protocolKey, baseURLKey, baseURLsKey, rulesKey]

    public let profile: MetaCatalog.MultiProtocol
    /// The mode in effect: the stored one when the catalog knows it, else the default.
    public let mode: String
    public let apiProtocol: String
    /// Some mode routes by model (S2-02 does not read `routing`; today that is exactly the platforms with protocol rules).
    public let routesByModel: Bool
    /// `base_url`, `api_base_urls` and `protocol_rules` are presets of the current mode and protocol, or missing.
    public let isOfficial: Bool
    private let stored: [String: JSONValue]

    /// API Key accounts of a platform with `multi_protocol` only.
    public init?(account: UpstreamAccount, catalog: MetaCatalog) {
        guard account.type == "apikey", let profile = catalog.platform(account.platform)?.multiProtocol else { return nil }
        let stored = (account.credentials?.objectValue ?? [:]).filter { Self.credentialKeys.contains($0.key) && $0.value != .null }
        let byModel = profile.modes.contains { !$0.protocolRules.isEmpty }
        let mode = profile.mode(stored[Self.modeKey]?.stringValue)?.mode ?? profile.defaultMode
        let presets = Self.presets(profile, mode)
        let apiProtocol = Self.resolve(stored[Self.protocolKey]?.stringValue, presets: presets, routesByModel: byModel)
        self.profile = profile
        self.stored = stored
        self.mode = mode
        self.apiProtocol = apiProtocol
        routesByModel = byModel
        isOfficial = Self.official(stored, presets: presets, apiProtocol: apiProtocol, rules: byModel ? profile.mode(mode)?.protocolRules : nil)
    }

    /// The segment's choices: none for a single mode.
    public var modeOptions: [String] { profile.modes.count >= 2 ? profile.modes.map(\.mode) : [] }
    /// 自适应 and the mode's own endpoints, as the Web edit dialog lists them.
    public func protocolOptions(mode: String) -> [String] {
        Self.protocolOptions(baseURLs: Self.presets(profile, mode), adaptiveWhenSingle: true)
    }
    /// S2D1-23, the one table (the new-account form passes `adaptiveWhenSingle: false`): the native protocols with an endpoint in
    /// order, after 自适应 when there are two or more.
    public static func protocolOptions(baseURLs: [String: String], adaptiveWhenSingle: Bool) -> [String] {
        let native = nativeProtocolOrder.filter { !(baseURLs[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return native.count >= 2 || (adaptiveWhenSingle && !native.isEmpty) ? [adaptive] + native : native
    }
    /// GetAPIProtocol: responses only where the mode has the endpoint; otherwise the platform's default.
    public func resolvedProtocol(_ stored: String?, mode: String) -> String {
        Self.resolve(stored, presets: Self.presets(profile, mode), routesByModel: routesByModel)
    }

    /// The `credentials_patch` for switching to (mode, protocol): the changed account_mode / api_protocol, and the endpoint keys
    /// that then differ — a non-adaptive protocol's preset in `base_url` (left missing when it was) without `api_base_urls`;
    /// adaptive's whole preset map with `base_url` its chat endpoint; a by-model platform's default rules for the new mode. Empty
    /// for a custom endpoint, which the sheet does not offer to switch.
    public func credentialsPatch(mode newMode: String, apiProtocol newProtocol: String) -> [String: JSONPatchValue] {
        guard isOfficial, newMode != mode || newProtocol != apiProtocol else { return [:] }
        var patch: [String: JSONPatchValue] = [:]
        if newMode != mode { patch[Self.modeKey] = .set(.string(newMode)) }
        if newProtocol != apiProtocol { patch[Self.protocolKey] = .set(.string(newProtocol)) }
        let presets = Self.presets(profile, newMode)
        let target = presets[newProtocol == Self.adaptive ? "chat_completions" : newProtocol]
        if let current = stored[Self.baseURLKey]?.stringValue, !Self.isBlank(current), !Self.sameURL(current, target) {
            patch[Self.baseURLKey] = target.map { JSONPatchValue.set(.string($0)) } ?? .delete
        }
        if newProtocol == Self.adaptive {
            let map = JSONValue.object(presets.mapValues(JSONValue.string))
            if stored[Self.baseURLsKey] != map { patch[Self.baseURLsKey] = .set(map) }
        } else if stored[Self.baseURLsKey] != nil {
            patch[Self.baseURLsKey] = .delete
        }
        if routesByModel, newMode != mode, stored[Self.rulesKey] != nil {
            patch[Self.rulesKey] = Self.wire(profile.mode(newMode)?.protocolRules ?? []).map(JSONPatchValue.set) ?? .delete
        }
        return patch
    }

    /// Web accounts.ts accountMode / apiProtocol.
    public static func modeTitle(_ mode: String) -> String {
        switch mode {
        case "payg": "按量付费"
        case "coding": "Coding Plan"
        case "zen": "Zen"
        case "go": "GO"
        default: mode
        }
    }
    public static func protocolTitle(_ apiProtocol: String) -> String {
        switch apiProtocol {
        case adaptive: "自适应"
        case "chat_completions": "Chat Completions"
        case "anthropic": "Anthropic"
        case "responses": "Responses"
        default: apiProtocol
        }
    }

    // MARK: - Internals

    private static func presets(_ profile: MetaCatalog.MultiProtocol, _ mode: String) -> [String: String] {
        (profile.mode(mode)?.baseURLs ?? [:]).filter { !isBlank($0.value) }
    }
    private static func resolve(_ stored: String?, presets: [String: String], routesByModel: Bool) -> String {
        let value = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch value {
        case adaptive, "anthropic", "chat_completions": return value
        case "responses" where presets["responses"] != nil: return value
        default: return routesByModel ? adaptive : "chat_completions"
        }
    }
    private static func official(_ stored: [String: JSONValue], presets: [String: String], apiProtocol: String, rules: [MetaCatalog.ProtocolRule]?) -> Bool {
        let expected = presets[apiProtocol == adaptive ? "chat_completions" : apiProtocol]
        if let baseURL = stored[baseURLKey] {
            guard let text = baseURL.stringValue, isBlank(text) || sameURL(text, expected) else { return false }
        }
        if let map = stored[baseURLsKey] {
            guard let fields = map.objectValue else { return false }
            for (key, value) in fields {
                guard let text = value.stringValue, isBlank(text) || sameURL(text, presets[key]) else { return false }
            }
        }
        if let rules, let current = stored[rulesKey], current != .array([]) {
            guard current.arrayValue.map(normalizedRules) == wire(rules)?.arrayValue.map(normalizedRules) else { return false }
        }
        return true
    }
    /// The server's protocol_rules form (NormalizeProtocolRulesCredentials): pattern lowercased and trimmed, `protocols` only
    /// with more than one. nil for no rules.
    private static func wire(_ rules: [MetaCatalog.ProtocolRule]) -> JSONValue? {
        guard !rules.isEmpty else { return nil }
        return .array(rules.map { rule -> JSONValue in
            var item: [String: JSONValue] = ["pattern": .string(rule.pattern.trimmingCharacters(in: .whitespaces).lowercased()),
                                             "protocol": .string(rule.preferredProtocol)]
            if rule.supportedProtocols.count > 1 { item["protocols"] = .array(rule.supportedProtocols.map(JSONValue.string)) }
            return .object(item)
        })
    }
    /// A stored rule as (pattern, protocols with the preferred one first), whatever its spelling.
    private static func normalizedRules(_ items: [JSONValue]) -> [[String]] {
        items.map { item in
            let pattern = item["pattern"]?.stringValue?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            let preferred = item["protocol"]?.stringValue ?? ""
            let listed = item["protocols"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return [pattern, preferred] + listed.filter { $0 != preferred }
        }
    }
    /// Trimmed, without a trailing “/”; blank and missing are the same.
    static func sameURL(_ lhs: String?, _ rhs: String?) -> Bool { canonical(lhs) == canonical(rhs) }
    private static func canonical(_ url: String?) -> String {
        var text = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
    private static func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
