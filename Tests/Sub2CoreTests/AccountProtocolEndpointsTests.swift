import Foundation
import Testing
@testable import Sub2Core

private func account(_ platform: String, type: String = "apikey", credentials: String = "{}") throws -> UpstreamAccount {
    let json = #"{"id":9,"name":"多协议","platform":"\#(platform)","type":"\#(type)","status":"active","schedulable":true,"credentials":\#(credentials)}"#
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func endpoints(_ platform: String, _ credentials: String = "{}", catalog: MetaCatalog = .builtin) throws -> AccountProtocolEndpoints {
    try #require(AccountProtocolEndpoints(account: try account(platform, credentials: credentials), catalog: catalog))
}
/// The Web's protocol_rules form (credentialsBuilder.ts, NormalizeProtocolRulesCredentials).
private func rules(_ pairs: [(String, String)]) -> JSONValue {
    .array(pairs.map { pair -> JSONValue in ["pattern": .string(pair.0), "protocol": .string(pair.1)] })
}
private let goRules = rules([("grok-*", "responses"), ("gpt-*", "responses"), ("muse-spark-*", "responses"), ("minimax-*", "anthropic"), ("qwen*", "anthropic")])
private let zenRules = rules([("grok-*", "responses"), ("gpt-*", "responses"), ("muse-spark-*", "responses"), ("claude-*", "anthropic"),
                              ("qwen3.8-max", "chat_completions"), ("qwen*", "anthropic")])
private func encoded(_ value: JSONValue) throws -> String { String(decoding: try value.jsonData(), as: UTF8.self) }

// MARK: - Reading like the backend

@Test func resolvesModeAndProtocolLikeTheBackend() throws {
    let kimi = try endpoints("kimi")
    #expect(kimi.mode == "payg" && kimi.apiProtocol == "chat_completions" && !kimi.routesByModel)
    let coding = try endpoints("kimi", #"{"account_mode":"coding","api_protocol":"responses"}"#)
    #expect(coding.mode == "coding" && coding.apiProtocol == "responses")
    #expect(try endpoints("zhipu", #"{"api_protocol":"responses"}"#).apiProtocol == "chat_completions")
    #expect(try endpoints("kimi", #"{"api_protocol":" anthropic "}"#).apiProtocol == "anthropic")
    let go = try endpoints("opencode_go")
    #expect(go.mode == "go" && go.apiProtocol == "adaptive" && go.routesByModel)
    #expect(try endpoints("kimi", #"{"account_mode":"foo","api_protocol":"bar"}"#).mode == "payg")
    #expect(AccountProtocolEndpoints(account: try account("kimi", type: "oauth"), catalog: .builtin) == nil)
    #expect(AccountProtocolEndpoints(account: try account("anthropic"), catalog: .builtin) == nil)
}

@Test func protocolOptionsFollowTheModesEndpoints() throws {
    #expect(try endpoints("kimi").protocolOptions(mode: "payg") == ["adaptive", "chat_completions", "anthropic", "responses"])
    #expect(try endpoints("zhipu").protocolOptions(mode: "coding") == ["adaptive", "chat_completions", "anthropic"])
    #expect(try endpoints("cline").protocolOptions(mode: "payg") == ["adaptive", "chat_completions"])
}

/// S2D1-23: the one table, shared with the new-account form (which passes false).
@Test func staticProtocolOptionsPutAdaptiveFirstWhenThereIsAChoice() {
    let all = ["responses": "https://r.example.invalid", "chat_completions": "https://c.example.invalid", "anthropic": "https://a.example.invalid"]
    #expect(AccountProtocolEndpoints.protocolOptions(baseURLs: all, adaptiveWhenSingle: false) == ["adaptive", "chat_completions", "anthropic", "responses"])
    let single = ["chat_completions": "https://c.example.invalid", "anthropic": ""]
    #expect(AccountProtocolEndpoints.protocolOptions(baseURLs: single, adaptiveWhenSingle: false) == ["chat_completions"])
    #expect(AccountProtocolEndpoints.protocolOptions(baseURLs: single, adaptiveWhenSingle: true) == ["adaptive", "chat_completions"])
    #expect(AccountProtocolEndpoints.protocolOptions(baseURLs: [:], adaptiveWhenSingle: true).isEmpty)
}

@Test func modeSegmentOnlyWithTwoOrMoreModes() throws {
    #expect(try endpoints("kimi").modeOptions == ["payg", "coding"])
    #expect(try endpoints("opencode_go").modeOptions == ["go", "zen"])
    for platform in ["deepseek", "cline", "command_code"] { #expect(try endpoints(platform).modeOptions.isEmpty, "\(platform)") }
}

@Test func officialEndpointDetection() throws {
    #expect(try endpoints("kimi", #"{"api_protocol":"anthropic","base_url":" https://api.moonshot.cn/anthropic/ "}"#).isOfficial)
    #expect(try endpoints("kimi", #"{"api_protocol":"anthropic","base_url":""}"#).isOfficial)
    #expect(!(try endpoints("kimi", #"{"api_protocol":"anthropic","base_url":"https://kimi-relay.example.invalid/anthropic"}"#).isOfficial))
    #expect(!(try endpoints("kimi", #"{"api_protocol":"anthropic","base_url":"https://api.moonshot.cn/v1"}"#).isOfficial))
    let adaptive = #"{"api_protocol":"adaptive","base_url":"https://api.moonshot.cn/v1","api_base_urls":{"anthropic":"https://api.moonshot.cn/anthropic","responses":""}}"#
    #expect(try endpoints("kimi", adaptive).isOfficial)
    let custom = #"{"api_protocol":"adaptive","api_base_urls":{"anthropic":"https://relay.example.invalid/anthropic"}}"#
    #expect(!(try endpoints("kimi", custom).isOfficial))
    #expect(try endpoints("opencode_go").isOfficial)
    #expect(try endpoints("opencode_go", #"{"protocol_rules":\#(try encoded(goRules))}"#).isOfficial)
    #expect(!(try endpoints("opencode_go", #"{"protocol_rules":[{"pattern":"glm-*","protocol":"anthropic"}]}"#).isOfficial))
}

// MARK: - Switching moves the endpoints along (Web EditAccountModal)

@Test func protocolSwitchRewritesBaseURLAndDropsTheAdaptiveMap() throws {
    let chat = try endpoints("kimi", #"{"api_protocol":"chat_completions","base_url":"https://api.moonshot.cn/v1"}"#)
    #expect(chat.credentialsPatch(mode: "payg", apiProtocol: "anthropic")
            == ["api_protocol": .set("anthropic"), "base_url": .set("https://api.moonshot.cn/anthropic")])
    let adaptive = try endpoints("kimi", #"{"api_protocol":"adaptive","base_url":"https://api.moonshot.cn/v1","api_base_urls":{"anthropic":"https://api.moonshot.cn/anthropic"}}"#)
    #expect(adaptive.credentialsPatch(mode: "payg", apiProtocol: "chat_completions")
            == ["api_protocol": .set("chat_completions"), "api_base_urls": .delete])
    #expect(chat.credentialsPatch(mode: "payg", apiProtocol: "chat_completions").isEmpty)
}

@Test func protocolSwitchLeavesAMissingBaseURLToTheModesDefault() throws {
    #expect(try endpoints("kimi").credentialsPatch(mode: "payg", apiProtocol: "anthropic") == ["api_protocol": .set("anthropic")])
}

@Test func switchToAdaptiveWritesThePresetMapAndTheChatBaseURL() throws {
    let anthropic = try endpoints("kimi", #"{"api_protocol":"anthropic","base_url":"https://api.moonshot.cn/anthropic"}"#)
    let presets: JSONValue = ["anthropic": "https://api.moonshot.cn/anthropic", "chat_completions": "https://api.moonshot.cn/v1",
                              "responses": "https://api.moonshot.cn/v1"]
    #expect(anthropic.credentialsPatch(mode: "payg", apiProtocol: "adaptive")
            == ["api_protocol": .set("adaptive"), "api_base_urls": .set(presets), "base_url": .set("https://api.moonshot.cn/v1")])
}

@Test func modeSwitchRewritesOnlyTheEndpointKeysThatChange() throws {
    let kimi = try endpoints("kimi", #"{"api_protocol":"responses","base_url":"https://api.moonshot.cn/v1"}"#)
    #expect(kimi.credentialsPatch(mode: "coding", apiProtocol: "responses")
            == ["account_mode": .set("coding"), "base_url": .set("https://api.kimi.com/coding/v1")])
    let zhipu = try endpoints("zhipu", #"{"api_protocol":"anthropic","base_url":"https://open.bigmodel.cn/api/anthropic"}"#)
    #expect(zhipu.credentialsPatch(mode: "coding", apiProtocol: "anthropic") == ["account_mode": .set("coding")])
}

@Test func byModelModeSwitchRewritesTheDefaultRulesOnly() throws {
    let stored = try endpoints("opencode_go", #"{"protocol_rules":\#(try encoded(goRules))}"#)
    #expect(stored.credentialsPatch(mode: "zen", apiProtocol: "adaptive")["protocol_rules"] == .set(zenRules))
    #expect(try endpoints("opencode_go").credentialsPatch(mode: "zen", apiProtocol: "adaptive")["protocol_rules"] == nil)
    let custom = try endpoints("opencode_go", #"{"protocol_rules":[{"pattern":"glm-*","protocol":"anthropic"}]}"#)
    #expect(custom.credentialsPatch(mode: "zen", apiProtocol: "adaptive").isEmpty)
}

/// Rules with several protocols keep them, as the server normalizes them.
@Test func rulesWithSeveralProtocolsKeepTheList() throws {
    let catalog = MetaCatalog(platforms: [.init(id: "relay", displayName: "Relay", multiProtocol: .init(defaultMode: "a", modes: [
        .init(mode: "a", baseURLs: ["chat_completions": "https://a.example.invalid/v1"],
              protocolRules: [.init(pattern: "gpt-*", preferredProtocol: "responses", supportedProtocols: ["responses", "chat_completions"])]),
        .init(mode: "b", baseURLs: ["chat_completions": "https://b.example.invalid/v1"], protocolRules: [.init(pattern: "Claude-*", preferredProtocol: "anthropic")])
    ]))], platformAuth: [:])
    let storedA: JSONValue = [["pattern": "gpt-*", "protocol": "responses", "protocols": ["responses", "chat_completions"]]]
    let relay = try endpoints("relay", #"{"protocol_rules":\#(try encoded(storedA))}"#, catalog: catalog)
    #expect(relay.isOfficial)
    #expect(relay.credentialsPatch(mode: "b", apiProtocol: "adaptive")["protocol_rules"] == .set([["pattern": "claude-*", "protocol": "anthropic"]]))
}

@Test func titlesForModesAndProtocols() {
    let modes = ["payg", "coding", "zen", "go", "x"].map(AccountProtocolEndpoints.modeTitle)
    #expect(modes == ["按量付费", "Coding Plan", "Zen", "GO", "x"])
    let protocols = ["adaptive", "chat_completions", "anthropic", "responses", "y"].map(AccountProtocolEndpoints.protocolTitle)
    #expect(protocols == ["自适应", "Chat Completions", "Anthropic", "Responses", "y"])
}
