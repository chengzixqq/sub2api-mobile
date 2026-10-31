import Foundation

/// The 高级 sheet's copy of an account (20 §3.3, §3.4): the rows that apply, what they read, and the PATCH with only the changed
/// keys — a switch on writes true and off deletes its key (as the Web does); a limit writes its amount or deletes its key, never
/// the companion settings; 自动 deletes the Responses mode; the probe goes at the top level; 账号类型 / API 协议 bring their
/// endpoint keys (AccountProtocolEndpoints). 撤销 writes every sent key back as it was stored, or deletes it, and turns back on
/// the rate sync that the server turned off with the probe.
public struct AccountAdvancedDraft: Equatable, Sendable {
    public static let webRowTitle = "在 Web 中编辑"
    public static let webRowSubtitle = "自定义错误码、请求头覆写等其余设置"
    public static let endpointsLockedNote = "这个账号用的是自定义接入端点，账号类型和 API 协议请在 Web 中修改。"
    static let legacyPassthroughKey = "openai_oauth_passthrough"
    static let rateSyncKey = "upstream_billing_rate_sync_enabled"
    private static let credentialKeys = AccountProtocolEndpoints.credentialKeys
        .union([AccountAdvancedField.interceptWarmup, .poolMode].map(\.rawValue))
    private static let extraKeys = Set([AccountAdvancedField.windowCost, .sessionLimit, .rpmLimit, .tlsFingerprint, .sessionIDMasking,
                                        .openAIPassthrough, .openAIResponsesMode].map(\.rawValue)
                                       + [AccountAdvancedDraft.legacyPassthroughKey, AccountAdvancedDraft.rateSyncKey])

    public let fields: [AccountAdvancedField]
    public let base: AccountAdvancedValues
    public var values: AccountAdvancedValues
    public let endpoints: AccountProtocolEndpoints?
    /// The stored values of the keys this sheet may write, for 撤销; no secret is among them.
    private let storedCredentials: [String: JSONValue]
    private let storedExtra: [String: JSONValue]

    public init(account: UpstreamAccount, catalog: MetaCatalog) {
        let endpoints = AccountProtocolEndpoints(account: account, catalog: catalog)
        self.endpoints = endpoints
        fields = AccountAdvancedField.applicable(to: account, catalog: catalog)
        base = AccountAdvancedValues(account: account, endpoints: endpoints)
        values = base
        storedCredentials = (account.credentials?.objectValue ?? [:]).filter { Self.credentialKeys.contains($0.key) }
        storedExtra = (account.extra?.raw.objectValue ?? [:]).filter { Self.extraKeys.contains($0.key) }
    }

    // MARK: 账号类型 / API 协议

    public var modeOptions: [String] { endpoints?.modeOptions ?? [] }
    /// For the mode now chosen.
    public var protocolOptions: [String] {
        guard let endpoints else { return [] }
        return endpoints.protocolOptions(mode: values.accountMode ?? endpoints.mode)
    }
    /// A custom endpoint: both rows read only (endpointsLockedNote).
    public var endpointsLocked: Bool { endpoints.map { !$0.isOfficial } ?? false }
    /// A mode without the chosen protocol's endpoint falls back to Chat Completions.
    public func withMode(_ mode: String) -> AccountAdvancedDraft {
        guard let endpoints else { return self }
        var copy = self
        copy.values.accountMode = mode
        let options = endpoints.protocolOptions(mode: mode)
        if let current = values.apiProtocol, !options.contains(current) {
            copy.values.apiProtocol = options.contains("chat_completions") ? "chat_completions" : options.first
        }
        return copy
    }
    public func withProtocol(_ apiProtocol: String) -> AccountAdvancedDraft {
        var copy = self
        copy.values.apiProtocol = apiProtocol
        return copy
    }

    // MARK: Changes and checks

    /// In row order; an amount counts by its value (“50” is 50.0).
    public var changedFields: [AccountAdvancedField] { fields.filter(isChanged) }
    public var changedFieldNames: [String] { changedFields.map(\.title) }
    /// Under a limit while it is on.
    public func error(for field: AccountAdvancedField) -> String? {
        guard field.kind == .limit, values[limit: field].isOn, Self.amount(field, values[limit: field].text) == nil else { return nil }
        switch field {
        case .windowCost: return "费用阈值需要是大于 0 的数字"
        case .sessionLimit: return "最大会话数需要是正整数"
        default: return "基础 RPM 为 1–10000 的整数"
        }
    }
    public var isValid: Bool { fields.allSatisfy { error(for: $0) == nil } }
    public var canSave: Bool { !changedFields.isEmpty && isValid && patch().hasChanges }

    private func isChanged(_ field: AccountAdvancedField) -> Bool {
        switch field.kind {
        case .toggle: return values[toggle: field] != base[toggle: field]
        case .segment: return values.accountMode != base.accountMode
        case .options: return field == .apiProtocol ? values.apiProtocol != base.apiProtocol : values.responsesMode != base.responsesMode
        case .limit:
            let now = values[limit: field], was = base[limit: field]
            guard now.isOn == was.isOn else { return true }
            guard now.isOn else { return false }
            guard let new = Self.amount(field, now.text), let old = Self.amount(field, was.text) else { return now.text != was.text }
            return new != old
        }
    }

    // MARK: Requests

    public func patch() -> AccountPatchRequest {
        var request = AccountPatchRequest()
        let changed = changedFields
        for field in changed { write(field, into: &request) }
        if let endpoints, changed.contains(.accountMode) || changed.contains(.apiProtocol) {
            let keys = endpoints.credentialsPatch(mode: values.accountMode ?? endpoints.mode, apiProtocol: values.apiProtocol ?? endpoints.apiProtocol)
            request.credentialsPatch.merge(keys) { _, new in new }
        }
        return request
    }
    public func undoPatch() -> AccountPatchRequest {
        let forward = patch()
        var undo = AccountPatchRequest()
        for key in forward.credentialsPatch.keys { undo.credentialsPatch[key] = Self.restore(storedCredentials[key]) }
        for key in forward.extraPatch.keys { undo.extraPatch[key] = Self.restore(storedExtra[key]) }
        if let probe = forward.upstreamBillingProbeEnabled {
            undo.upstreamBillingProbeEnabled = base.upstreamBillingProbe
            // updateLoadedAccount writes the rate sync false whenever the probe goes off; it comes back only named beside the probe.
            if !probe, storedExtra[Self.rateSyncKey]?.boolValue == true { undo.upstreamBillingRateSyncEnabled = true }
        }
        return undo
    }
    /// What 保存 hands to AccountPatchFlow; nil while nothing can be saved (S2D1-08).
    public func change() -> AccountEditChange? {
        guard canSave else { return nil }
        return AccountEditChange(fieldNames: changedFieldNames, request: patch(), undo: undoPatch())
    }

    private func write(_ field: AccountAdvancedField, into request: inout AccountPatchRequest) {
        let key = field.rawValue
        switch field {
        case .interceptWarmup, .poolMode: request.credentialsPatch[key] = Self.flag(values[toggle: field])
        case .tlsFingerprint, .sessionIDMasking: request.extraPatch[key] = Self.flag(values[toggle: field])
        case .openAIPassthrough:
            request.extraPatch[key] = Self.flag(values.openAIPassthrough)
            // The backend still reads the old OAuth key when the new one is missing (IsOpenAIPassthroughEnabled).
            if !values.openAIPassthrough, storedExtra[Self.legacyPassthroughKey] != nil { request.extraPatch[Self.legacyPassthroughKey] = .delete }
        case .windowCost, .sessionLimit, .rpmLimit:
            let setting = values[limit: field]
            if !setting.isOn { request.extraPatch[key] = .delete } else if let amount = Self.amount(field, setting.text) { request.extraPatch[key] = .set(.number(amount)) }
        case .openAIResponsesMode:
            request.extraPatch[key] = values.responsesMode == .auto ? .delete : .set(.string(values.responsesMode.rawValue))
        case .upstreamBillingProbe: request.upstreamBillingProbeEnabled = values.upstreamBillingProbe
        case .accountMode, .apiProtocol: break
        }
    }

    // MARK: Display

    /// The detail's read-only rows.
    public static func display(_ field: AccountAdvancedField, values: AccountAdvancedValues) -> AccountAdvancedDisplay {
        switch field.kind {
        case .toggle: return values[toggle: field] ? AccountAdvancedDisplay(text: "开", isOff: false) : off
        case .segment: return AccountAdvancedDisplay(text: AccountProtocolEndpoints.modeTitle(values.accountMode ?? ""), isOff: false)
        case .options:
            let text = field == .apiProtocol ? AccountProtocolEndpoints.protocolTitle(values.apiProtocol ?? "") : values.responsesMode.title
            return AccountAdvancedDisplay(text: text, isOff: false)
        case .limit:
            let setting = values[limit: field]
            guard setting.isOn else { return off }
            guard let amount = amount(field, setting.text) else { return AccountAdvancedDisplay(text: setting.text, isOff: false) }
            let text = field == .windowCost ? DisplayFormat.money(amount) : DisplayFormat.grouped(NSDecimalNumber(decimal: amount).intValue)
            return AccountAdvancedDisplay(text: text, isOff: false)
        }
    }
    private static let off = AccountAdvancedDisplay(text: "关", isOff: true)

    /// handler/admin/account_handler.go sanitizeExtraBaseRPM: below 0 is 0, above 10000 is 10000.
    public static func sanitizedBaseRPM(_ value: Int) -> Int { min(max(value, 0), 10_000) }

    /// A valid amount for the limit (ASCII digits): the cost above 0, the session count a positive whole number, the RPM 1–10000.
    static func amount(_ field: AccountAdvancedField, _ text: String) -> Decimal? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .windowCost:
            guard text.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
                  let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
            return value
        case .sessionLimit, .rpmLimit:
            guard text.range(of: #"^[0-9]{1,9}$"#, options: .regularExpression) != nil, let value = Int(text), value > 0,
                  field == .sessionLimit || value <= 10_000 else { return nil }
            return Decimal(value)
        default: return nil
        }
    }
    private static func flag(_ isOn: Bool) -> JSONPatchValue { isOn ? .set(.bool(true)) : .delete }
    private static func restore(_ value: JSONValue?) -> JSONPatchValue { value.map(JSONPatchValue.set) ?? .delete }
}
