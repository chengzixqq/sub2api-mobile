import Foundation

/// 20 §3.3 高级: the switches whose keys were checked against the backend, in the table's order; everything else stays in the
/// Web (“在 Web 中编辑”). The raw value is the key on the wire (and the end of the row's accessibility identifier).
public enum AccountAdvancedField: String, CaseIterable, Sendable, Identifiable {
    case interceptWarmup = "intercept_warmup_requests"
    case windowCost = "window_cost_limit"
    case sessionLimit = "max_sessions"
    case rpmLimit = "base_rpm"
    case tlsFingerprint = "enable_tls_fingerprint"
    case sessionIDMasking = "session_id_masking_enabled"
    case accountMode = "account_mode"
    case apiProtocol = "api_protocol"
    case openAIPassthrough = "openai_passthrough"
    case openAIResponsesMode = "openai_responses_mode"
    case poolMode = "pool_mode"
    /// Read from `extra`, written as the top-level `upstream_billing_probe_enabled`.
    case upstreamBillingProbe = "upstream_billing_probe_enabled"

    public enum Kind: Sendable { case toggle, limit, segment, options }
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .interceptWarmup: "拦截预热请求"
        case .windowCost: "5h 窗口费用控制"
        case .sessionLimit: "会话数量控制"
        case .rpmLimit: "RPM 限制"
        case .tlsFingerprint: "TLS 指纹模拟"
        case .sessionIDMasking: "会话 ID 伪装"
        case .accountMode: "账号类型"
        case .apiProtocol: "API 协议"
        case .openAIPassthrough: "自动透传（仅替换认证）"
        case .openAIResponsesMode: "Responses API 支持"
        case .poolMode: "池模式"
        case .upstreamBillingProbe: "自动探测上游声明倍率"
        }
    }
    /// The spec's notes, and the design's for 预热 and the window cost.
    public var subtitle: String? {
        switch self {
        case .interceptWarmup: "标题生成等预热请求不消耗上游 Token"
        case .windowCost: "达到阈值后不接新请求"
        case .openAIPassthrough: "开启后模型限制不生效"
        case .poolMode: "上游是账号池时开启，错误不标记本账号"
        case .upstreamBillingProbe: "只探测，不改账号计费倍率"
        default: nil
        }
    }
    public var kind: Kind {
        switch self {
        case .windowCost, .sessionLimit, .rpmLimit: .limit
        case .accountMode: .segment
        case .apiProtocol, .openAIResponsesMode: .options
        default: .toggle
        }
    }
    /// The amount field under a limit switch (design AeAdvField).
    public var limitLabel: String? {
        switch self {
        case .windowCost: "费用阈值"
        case .sessionLimit: "最大会话数"
        case .rpmLimit: "基础 RPM"
        default: nil
        }
    }
    /// The rows of one account, after the backend: Anthropic OAuth / Setup Token's six (IsTLSFingerprintEnabled …); a
    /// multi-protocol API Key account's 账号类型 (two or more modes) and API 协议; OpenAI's passthrough, and on an OpenAI key its
    /// Responses mode; 池模式 for API Key and Bedrock (IsPoolMode); the probe for API Key only (IsUpstreamBillingProbeIdentity).
    public static func applicable(to account: UpstreamAccount, catalog: MetaCatalog) -> [AccountAdvancedField] {
        let isKey = account.type == "apikey", endpoints = AccountProtocolEndpoints(account: account, catalog: catalog)
        return allCases.filter { field in
            switch field {
            case .interceptWarmup, .windowCost, .sessionLimit, .rpmLimit, .tlsFingerprint, .sessionIDMasking:
                account.platform == "anthropic" && account.isTokenAccount
            case .accountMode: endpoints.map { !$0.modeOptions.isEmpty } ?? false
            case .apiProtocol: endpoints != nil
            case .openAIPassthrough: account.platform == "openai"
            case .openAIResponsesMode: account.platform == "openai" && isKey
            case .poolMode: isKey || account.type == "bedrock"
            case .upstreamBillingProbe: isKey
            }
        }
    }
}

/// A limit's switch and the amount typed under it.
public struct AccountLimitSetting: Equatable, Sendable {
    public var isOn: Bool
    public var text: String
    public init(isOn: Bool = false, text: String = "") { self.isOn = isOn; self.text = text }
}

/// `extra.openai_responses_mode`; missing or unknown is 自动.
public enum AccountResponsesMode: String, CaseIterable, Sendable, Identifiable {
    case auto, forceResponses = "force_responses", forceChatCompletions = "force_chat_completions"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .auto: "自动"
        case .forceResponses: "强制 Responses"
        case .forceChatCompletions: "强制 Chat Completions"
        }
    }
}

/// A row's read-only value: 开 / 关 (dimmed), an amount, a mode or protocol name.
public struct AccountAdvancedDisplay: Equatable, Sendable {
    public let text: String
    public let isOff: Bool
    public init(text: String, isOff: Bool) { self.text = text; self.isOff = isOff }
}

/// What the rows read now, as the backend reads it: booleans only for the switches; a limit is on above 0 (numbers or numeric
/// strings, parseExtraFloat64 / parseExtraInt), and without its `extra` key the DTO's top-level copy counts.
public struct AccountAdvancedValues: Equatable, Sendable {
    public var interceptWarmup = false
    public var windowCost = AccountLimitSetting()
    public var sessionLimit = AccountLimitSetting()
    public var rpmLimit = AccountLimitSetting()
    public var tlsFingerprint = false
    public var sessionIDMasking = false
    /// nil unless the account is a multi-protocol API Key account.
    public var accountMode: String?
    public var apiProtocol: String?
    public var openAIPassthrough = false
    public var responsesMode = AccountResponsesMode.auto
    public var poolMode = false
    public var upstreamBillingProbe = false

    public init() {}
    public init(account: UpstreamAccount, endpoints: AccountProtocolEndpoints?) {
        let credentials = account.credentials, extra = account.extra
        interceptWarmup = credentials?[AccountAdvancedField.interceptWarmup.rawValue]?.boolValue == true
        windowCost = Self.limit(extra?[AccountAdvancedField.windowCost.rawValue].map(Self.number) ?? account.windowCostLimit)
        sessionLimit = Self.limit((extra?[AccountAdvancedField.sessionLimit.rawValue].map(Self.number) ?? account.maxSessions.map { Decimal($0) })
            .map { Decimal(Self.whole($0)) })
        rpmLimit = Self.limit((extra?[AccountAdvancedField.rpmLimit.rawValue].map(Self.number) ?? account.baseRPM.map { Decimal($0) })
            .map { Decimal(AccountAdvancedDraft.sanitizedBaseRPM(Self.whole($0))) })
        tlsFingerprint = extra?[AccountAdvancedField.tlsFingerprint.rawValue]?.boolValue == true
        sessionIDMasking = extra?[AccountAdvancedField.sessionIDMasking.rawValue]?.boolValue == true
        accountMode = endpoints?.mode
        apiProtocol = endpoints?.apiProtocol
        openAIPassthrough = AccountModelMapping.passthroughEnabled(account)
        responsesMode = extra?[AccountAdvancedField.openAIResponsesMode.rawValue]?.stringValue.flatMap(AccountResponsesMode.init(rawValue:)) ?? .auto
        poolMode = credentials?[AccountAdvancedField.poolMode.rawValue]?.boolValue == true
        upstreamBillingProbe = extra?[AccountAdvancedField.upstreamBillingProbe.rawValue]?.boolValue == true
    }

    public subscript(toggle field: AccountAdvancedField) -> Bool {
        get {
            switch field {
            case .interceptWarmup: interceptWarmup
            case .tlsFingerprint: tlsFingerprint
            case .sessionIDMasking: sessionIDMasking
            case .openAIPassthrough: openAIPassthrough
            case .poolMode: poolMode
            case .upstreamBillingProbe: upstreamBillingProbe
            default: false
            }
        }
        set {
            switch field {
            case .interceptWarmup: interceptWarmup = newValue
            case .tlsFingerprint: tlsFingerprint = newValue
            case .sessionIDMasking: sessionIDMasking = newValue
            case .openAIPassthrough: openAIPassthrough = newValue
            case .poolMode: poolMode = newValue
            case .upstreamBillingProbe: upstreamBillingProbe = newValue
            default: break
            }
        }
    }
    public subscript(limit field: AccountAdvancedField) -> AccountLimitSetting {
        get {
            switch field {
            case .windowCost: windowCost
            case .sessionLimit: sessionLimit
            case .rpmLimit: rpmLimit
            default: AccountLimitSetting()
            }
        }
        set {
            switch field {
            case .windowCost: windowCost = newValue
            case .sessionLimit: sessionLimit = newValue
            case .rpmLimit: rpmLimit = newValue
            default: break
            }
        }
    }

    /// A number, or a numeric string; anything else is 0 (off).
    private static func number(_ value: JSONValue) -> Decimal {
        if let number = value.decimalValue { return number }
        let text = value.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")).flatMap { $0.isNaN ? nil : $0 } ?? 0
    }
    /// Go's int(float64) for the positive values that count; anything at or below 0 is off either way.
    static func whole(_ value: Decimal) -> Int {
        var source = value, result = Decimal()
        NSDecimalRound(&result, &source, 0, .down)
        return Int(exactly: NSDecimalNumber(decimal: result).doubleValue) ?? 0
    }
    private static func limit(_ value: Decimal?) -> AccountLimitSetting {
        guard let value, value > 0 else { return AccountLimitSetting() }
        return AccountLimitSetting(isOn: true, text: NSDecimalNumber(decimal: value).stringValue)
    }
}
