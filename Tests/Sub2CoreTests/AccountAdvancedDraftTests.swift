import Foundation
import Testing
@testable import Sub2Core

private func account(_ platform: String = "anthropic", _ type: String = "oauth", _ fields: String = "") throws -> UpstreamAccount {
    let json = #"{"id":1,"name":"高级","platform":"\#(platform)","type":"\#(type)","status":"active","schedulable":true"#
        + (fields.isEmpty ? "" : "," + fields) + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func draft(_ platform: String = "anthropic", _ type: String = "oauth", _ fields: String = "") throws -> AccountAdvancedDraft {
    AccountAdvancedDraft(account: try account(platform, type, fields), catalog: .builtin)
}
private typealias Field = AccountAdvancedField

// MARK: - Rows

struct ApplicableCase: Sendable, CustomTestStringConvertible {
    let platform: String, type: String, fields: [AccountAdvancedField]
    var testDescription: String { "\(platform) \(type)" }
}
private let claudeToken: [AccountAdvancedField] = [.interceptWarmup, .windowCost, .sessionLimit, .rpmLimit, .tlsFingerprint, .sessionIDMasking]
private let applicableCases: [ApplicableCase] = [
    .init(platform: "anthropic", type: "oauth", fields: claudeToken),
    .init(platform: "anthropic", type: "setup-token", fields: claudeToken),
    .init(platform: "anthropic", type: "apikey", fields: [.poolMode, .upstreamBillingProbe]),
    .init(platform: "anthropic", type: "bedrock", fields: [.poolMode]),
    .init(platform: "openai", type: "oauth", fields: [.openAIPassthrough]),
    .init(platform: "openai", type: "apikey", fields: [.openAIPassthrough, .openAIResponsesMode, .poolMode, .upstreamBillingProbe]),
    .init(platform: "kimi", type: "apikey", fields: [.accountMode, .apiProtocol, .poolMode, .upstreamBillingProbe]),
    .init(platform: "deepseek", type: "apikey", fields: [.apiProtocol, .poolMode, .upstreamBillingProbe]),
    .init(platform: "cline", type: "apikey", fields: [.apiProtocol, .poolMode, .upstreamBillingProbe]),
    .init(platform: "gemini", type: "oauth", fields: []),
    .init(platform: "antigravity", type: "oauth", fields: []),
    .init(platform: "anthropic", type: "service_account", fields: []),
    .init(platform: "grok", type: "oauth", fields: []),
    .init(platform: "someday", type: "apikey", fields: [.poolMode, .upstreamBillingProbe])
]
@Test(arguments: applicableCases)
func applicableFieldsFollowTheSpecTableAndTheBackend(_ entry: ApplicableCase) throws {
    let fields = Field.applicable(to: try account(entry.platform, entry.type), catalog: .builtin)
    #expect(fields == entry.fields)
    #expect(!fields.map(\.title).contains("客户端亲和调度"))
}

@Test func rowTitlesAndNotesComeFromTheSpec() {
    #expect(Field.allCases.map(\.title) == ["拦截预热请求", "5h 窗口费用控制", "会话数量控制", "RPM 限制", "TLS 指纹模拟", "会话 ID 伪装", "账号类型",
                                           "API 协议", "自动透传（仅替换认证）", "Responses API 支持", "池模式", "自动探测上游声明倍率"])
    #expect(Field.openAIPassthrough.subtitle == "开启后模型限制不生效" && Field.poolMode.subtitle == "上游是账号池时开启，错误不标记本账号")
    #expect(Field.upstreamBillingProbe.subtitle == "只探测，不改账号计费倍率" && Field.tlsFingerprint.subtitle == nil)
    #expect([Field.windowCost, .sessionLimit, .rpmLimit].map(\.limitLabel) == ["费用阈值", "最大会话数", "基础 RPM"])
}

// MARK: - Reading

@Test func readsValuesFromCredentialsExtraAndTheTopLevelMirror() throws {
    let values = try draft("anthropic", "oauth", #""credentials":{"intercept_warmup_requests":true},"extra":{"window_cost_limit":50.5,"max_sessions":3,"enable_tls_fingerprint":true,"session_id_masking_enabled":false},"base_rpm":60"#).values
    #expect(values.interceptWarmup && values.tlsFingerprint && !values.sessionIDMasking)
    #expect(values.windowCost == AccountLimitSetting(isOn: true, text: "50.5") && values.sessionLimit == AccountLimitSetting(isOn: true, text: "3"))
    #expect(values.rpmLimit == AccountLimitSetting(isOn: true, text: "60"))
    let key = try draft("openai", "apikey", #""credentials":{"pool_mode":true},"extra":{"openai_responses_mode":"force_responses","upstream_billing_probe_enabled":true,"max_sessions":"4"}"#).values
    #expect(key.poolMode && key.upstreamBillingProbe && key.responsesMode == .forceResponses && key.sessionLimit.text == "4")
}

@Test func limitsAreOffWhenMissingZeroOrNegative() throws {
    let values = try draft("anthropic", "oauth", #""credentials":{"intercept_warmup_requests":"true"},"extra":{"window_cost_limit":0,"max_sessions":0,"base_rpm":-5},"max_sessions":3"#).values
    #expect(!values.windowCost.isOn && !values.sessionLimit.isOn && !values.rpmLimit.isOn && !values.interceptWarmup)
    #expect(try draft().values == AccountAdvancedValues())
}

@Test func anInvalidResponsesModeReadsAsAuto() throws {
    for raw in ["", #""extra":{"openai_responses_mode":"x"}"#, #""extra":{"openai_responses_mode":1}"#] {
        #expect(try draft("openai", "apikey", raw).values.responsesMode == .auto)
    }
    for mode in AccountResponsesMode.allCases {
        #expect(try draft("openai", "apikey", #""extra":{"openai_responses_mode":"\#(mode.rawValue)"}"#).values.responsesMode == mode)
    }
    #expect(AccountResponsesMode.allCases.map(\.title) == ["自动", "强制 Responses", "强制 Chat Completions"])
}

@Test func sanitizedBaseRPMMirrorsTheBackend() {
    #expect([-3, 0, 60, 10_000, 20_000].map(AccountAdvancedDraft.sanitizedBaseRPM) == [0, 0, 60, 10_000, 10_000])
}

// MARK: - Writing

@Test func switchesWriteTrueOrDeleteTheirKey() throws {
    var warmup = try draft()
    warmup.values.interceptWarmup = true
    #expect(warmup.patch().credentialsPatch == ["intercept_warmup_requests": .set(true)] && warmup.patch().extraPatch.isEmpty)
    var off = try draft("anthropic", "oauth", #""extra":{"enable_tls_fingerprint":true,"tls_fingerprint_profile_id":7,"session_id_masking_enabled":true}"#)
    off.values.tlsFingerprint = false
    off.values.sessionIDMasking = false
    #expect(off.patch().extraPatch == ["enable_tls_fingerprint": .delete, "session_id_masking_enabled": .delete])
    var pool = try draft("openai", "apikey", #""credentials":{"pool_mode":true,"pool_mode_retry_count":5}"#)
    pool.values.poolMode = false
    #expect(pool.patch().credentialsPatch == ["pool_mode": .delete])
}

@Test func passthroughOffDeletesTheLegacyKeyToo() throws {
    var legacy = try draft("openai", "oauth", #""extra":{"openai_oauth_passthrough":true}"#)
    #expect(legacy.values.openAIPassthrough)
    legacy.values.openAIPassthrough = false
    #expect(legacy.patch().extraPatch == ["openai_passthrough": .delete, "openai_oauth_passthrough": .delete])
    var current = try draft("openai", "oauth", #""extra":{"openai_passthrough":true}"#)
    current.values.openAIPassthrough = false
    #expect(current.patch().extraPatch == ["openai_passthrough": .delete])
    var on = try draft("openai", "oauth")
    on.values.openAIPassthrough = true
    #expect(on.patch().extraPatch == ["openai_passthrough": .set(true)])
}

@Test func limitPatchesWriteNumbersOrDeleteOnlyTheMainKey() throws {
    var limits = try draft("anthropic", "oauth", #""extra":{"base_rpm":60,"rpm_strategy":"tiered","window_cost_sticky_reserve":10}"#)
    limits.values.windowCost = AccountLimitSetting(isOn: true, text: "12.5")
    limits.values.sessionLimit = AccountLimitSetting(isOn: true, text: "3")
    limits.values.rpmLimit = AccountLimitSetting(isOn: true, text: "120")
    #expect(limits.patch().extraPatch == ["window_cost_limit": .set(.number(Decimal(string: "12.5")!)), "max_sessions": .set(3), "base_rpm": .set(120)])
    limits.values.rpmLimit.isOn = false
    #expect(limits.patch().extraPatch["base_rpm"] == .delete && limits.patch().extraPatch["rpm_strategy"] == nil)
    var same = try draft("anthropic", "oauth", #""extra":{"window_cost_limit":50.0}"#)
    same.values.windowCost.text = "50"
    #expect(same.changedFields.isEmpty)
    same.values.windowCost.text = "50.00"
    #expect(same.changedFields.isEmpty && !same.canSave)
}

@Test func limitValidationOnlyWhileTheRowIsOn() throws {
    var limits = try draft()
    for bad in ["", "abc", "-1", "0", "1.", "１"] {
        limits.values.windowCost = AccountLimitSetting(isOn: true, text: bad)
        #expect(limits.error(for: .windowCost) == "费用阈值需要是大于 0 的数字", "\(bad)")
    }
    for bad in ["0", "1.5", ""] {
        limits.values.sessionLimit = AccountLimitSetting(isOn: true, text: bad)
        #expect(limits.error(for: .sessionLimit) == "最大会话数需要是正整数", "\(bad)")
    }
    for bad in ["0", "10001", "20000"] {
        limits.values.rpmLimit = AccountLimitSetting(isOn: true, text: bad)
        #expect(limits.error(for: .rpmLimit) == "基础 RPM 为 1–10000 的整数", "\(bad)")
    }
    #expect(!limits.isValid && !limits.canSave && limits.change() == nil)
    limits.values.windowCost = AccountLimitSetting(isOn: false, text: "abc")
    limits.values.sessionLimit = AccountLimitSetting(isOn: true, text: " 2 ")
    limits.values.rpmLimit = AccountLimitSetting(isOn: true, text: "10000")
    #expect(limits.error(for: .windowCost) == nil && limits.error(for: .sessionLimit) == nil && limits.error(for: .rpmLimit) == nil)
    #expect(limits.isValid && limits.canSave)
}

@Test func responsesModeAutoDeletesTheKey() throws {
    var forced = try draft("openai", "apikey", #""extra":{"openai_responses_mode":"force_responses"}"#)
    forced.values.responsesMode = .auto
    #expect(forced.patch().extraPatch == ["openai_responses_mode": .delete])
    var auto = try draft("openai", "apikey")
    auto.values.responsesMode = .forceChatCompletions
    #expect(auto.patch().extraPatch == ["openai_responses_mode": .set("force_chat_completions")])
}

@Test func upstreamBillingProbeWritesTheTopLevelFlagOnly() throws {
    var probe = try draft("openai", "apikey", #""extra":{"upstream_billing_probe_enabled":false}"#)
    probe.values.upstreamBillingProbe = true
    let request = probe.patch()
    #expect(request.upstreamBillingProbeEnabled == true && request.extraPatch.isEmpty && request.credentialsPatch.isEmpty)
    #expect(String(decoding: try request.requestBody(), as: UTF8.self) == #"{"upstream_billing_probe_enabled":true}"#)
    #expect(probe.undoPatch().upstreamBillingProbeEnabled == false)
}

/// The server turns the rate sync off with the probe (admin_account.go updateLoadedAccount), so 撤销 turns it back on.
@Test func undoingTheProbeOffRestoresTheRateSyncTheServerTurnedOff() throws {
    let stored = #""extra":{"upstream_billing_probe_enabled":true,"upstream_billing_rate_sync_enabled":true}"#
    var synced = try draft("openai", "apikey", stored)
    synced.values.upstreamBillingProbe = false
    #expect(String(decoding: try synced.patch().requestBody(), as: UTF8.self) == #"{"upstream_billing_probe_enabled":false}"#)
    let undo = synced.undoPatch()
    #expect(String(decoding: try undo.requestBody(), as: UTF8.self)
            == #"{"upstream_billing_probe_enabled":true,"upstream_billing_rate_sync_enabled":true}"#)
    let probeOnly = try account("openai", "apikey", #""extra":{"upstream_billing_probe_enabled":true,"upstream_billing_rate_sync_enabled":false}"#)
    #expect(AccountPatchReadback.matches(account: try account("openai", "apikey", stored), request: undo))
    #expect(!AccountPatchReadback.matches(account: probeOnly, request: undo))
    #expect(String(decoding: try undo.fullUpdateBody(base: probeOnly), as: UTF8.self)
            == #"{"upstream_billing_probe_enabled":true,"upstream_billing_rate_sync_enabled":true}"#)

    var unsynced = try draft("openai", "apikey", #""extra":{"upstream_billing_probe_enabled":true}"#)
    unsynced.values.upstreamBillingProbe = false
    #expect(String(decoding: try unsynced.undoPatch().requestBody(), as: UTF8.self) == #"{"upstream_billing_probe_enabled":true}"#)
}

@Test func changedFieldNamesFollowTheRowOrder() throws {
    var edits = try draft()
    edits.values.sessionIDMasking = true
    edits.values.interceptWarmup = true
    edits.values.rpmLimit = AccountLimitSetting(isOn: true, text: "30")
    #expect(edits.changedFieldNames == ["拦截预热请求", "RPM 限制", "会话 ID 伪装"])
    let kimi = try draft("kimi", "apikey", #""credentials":{"base_url":"https://api.moonshot.cn/v1"}"#).withProtocol("anthropic")
    #expect(kimi.changedFieldNames == ["API 协议"])
    #expect(kimi.patch().credentialsPatch == ["api_protocol": .set("anthropic"), "base_url": .set("https://api.moonshot.cn/anthropic")])
}

@Test func undoRestoresTheBaseOrDeletesAddedKeys() throws {
    var limits = try draft("anthropic", "oauth", #""extra":{"window_cost_limit":50}"#)
    limits.values.windowCost.text = "80"
    limits.values.sessionLimit = AccountLimitSetting(isOn: true, text: "2")
    #expect(limits.undoPatch().extraPatch == ["window_cost_limit": .set(50), "max_sessions": .delete])
    var legacy = try draft("openai", "oauth", #""extra":{"openai_oauth_passthrough":true}"#)
    legacy.values.openAIPassthrough = false
    #expect(legacy.undoPatch().extraPatch == ["openai_passthrough": .delete, "openai_oauth_passthrough": .set(true)])
    let kimi = try draft("kimi", "apikey", #""credentials":{"api_protocol":"adaptive","base_url":"https://api.moonshot.cn/v1","api_base_urls":{"anthropic":"https://api.moonshot.cn/anthropic"}}"#)
        .withProtocol("chat_completions")
    #expect(kimi.undoPatch().credentialsPatch
            == ["api_protocol": .set("adaptive"), "api_base_urls": .set(["anthropic": "https://api.moonshot.cn/anthropic"])])
    let change = try #require(kimi.change())
    #expect(change.fieldNames == ["API 协议"] && change.request == kimi.patch() && change.undo == kimi.undoPatch())
}

@Test func anUnchangedDraftHasNoPatchAndCannotSave() throws {
    var edits = try draft("anthropic", "oauth", #""extra":{"base_rpm":60}"#)
    #expect(edits.changedFields.isEmpty && !edits.canSave && !edits.patch().hasChanges && edits.change() == nil)
    edits.values.tlsFingerprint = true
    edits.values.tlsFingerprint = false
    edits.values.rpmLimit.isOn = false
    edits.values.rpmLimit.isOn = true
    #expect(edits.changedFields.isEmpty && !edits.canSave)
}

@Test func modeSwitchFallsBackWhenTheNewModeLacksTheProtocol() throws {
    let catalog = MetaCatalog(platforms: [.init(id: "relay", displayName: "Relay", multiProtocol: .init(defaultMode: "a", modes: [
        .init(mode: "a", baseURLs: ["chat_completions": "https://a.example.invalid/v1", "responses": "https://a.example.invalid/v1"]),
        .init(mode: "b", baseURLs: ["chat_completions": "https://b.example.invalid/v1"])
    ]))], platformAuth: [:])
    let relay = AccountAdvancedDraft(account: try account("relay", "apikey", #""credentials":{"api_protocol":"responses","base_url":"https://a.example.invalid/v1"}"#),
                                     catalog: catalog)
    #expect(relay.modeOptions == ["a", "b"] && relay.protocolOptions == ["adaptive", "chat_completions", "responses"])
    let moved = relay.withMode("b")
    #expect(moved.values.apiProtocol == "chat_completions" && moved.changedFields == [.accountMode, .apiProtocol])
    #expect(moved.patch().credentialsPatch
            == ["account_mode": .set("b"), "api_protocol": .set("chat_completions"), "base_url": .set("https://b.example.invalid/v1")])
}

@Test func aCustomEndpointLocksModeAndProtocol() throws {
    let locked = try draft("minimax", "apikey", #""credentials":{"base_url":"https://minimax-relay.example.invalid/v1"}"#)
    #expect(locked.endpointsLocked && locked.fields.contains(.apiProtocol))
    #expect(!locked.withProtocol("anthropic").canSave)
    #expect(AccountAdvancedDraft.endpointsLockedNote == "这个账号用的是自定义接入端点，账号类型和 API 协议请在 Web 中修改。")
    #expect(!(try draft("kimi", "apikey").endpointsLocked))
}

/// The Anthropic and OpenAI rows, flipped one by one: no edit ever names a secret, so none can delete one either.
@Test func patchesNeverNameSensitiveCredentialKeys() throws {
    let accounts = [try draft(), try draft("openai", "apikey"), try draft("kimi", "apikey", #""credentials":{"api_key":"sk-fixture"}"#)]
    for base in accounts {
        for field in base.fields {
            var edited = base
            switch field.kind {
            case .toggle: edited.values[toggle: field].toggle()
            case .limit: edited.values[limit: field] = AccountLimitSetting(isOn: true, text: "7")
            case .segment: edited = edited.withMode(edited.modeOptions.last ?? "")
            case .options where field == .apiProtocol: edited = edited.withProtocol("anthropic")
            case .options: edited.values.responsesMode = .forceResponses
            }
            let keys = Set(edited.patch().credentialsPatch.keys).union(edited.undoPatch().credentialsPatch.keys)
            #expect(keys.isDisjoint(with: UpstreamAccount.sensitiveCredentialKeys), "\(field)")
        }
    }
}

@Test func readOnlyDisplayValues() throws {
    let values = try draft("anthropic", "oauth", #""credentials":{"intercept_warmup_requests":true},"extra":{"window_cost_limit":50,"max_sessions":3}"#).values
    #expect(AccountAdvancedDraft.display(.interceptWarmup, values: values) == AccountAdvancedDisplay(text: "开", isOff: false))
    #expect(AccountAdvancedDraft.display(.tlsFingerprint, values: values) == AccountAdvancedDisplay(text: "关", isOff: true))
    #expect(AccountAdvancedDraft.display(.windowCost, values: values).text == "$50.00")
    #expect(AccountAdvancedDraft.display(.sessionLimit, values: values).text == "3")
    #expect(AccountAdvancedDraft.display(.rpmLimit, values: values) == AccountAdvancedDisplay(text: "关", isOff: true))
    let kimi = try draft("kimi", "apikey", #""credentials":{"account_mode":"coding","api_protocol":"adaptive"}"#).values
    #expect(AccountAdvancedDraft.display(.accountMode, values: kimi).text == "Coding Plan")
    #expect(AccountAdvancedDraft.display(.apiProtocol, values: kimi).text == "自适应")
    var openai = try draft("openai", "apikey").values
    openai.responsesMode = .forceChatCompletions
    #expect(AccountAdvancedDraft.display(.openAIResponsesMode, values: openai) == AccountAdvancedDisplay(text: "强制 Chat Completions", isOff: false))
}
