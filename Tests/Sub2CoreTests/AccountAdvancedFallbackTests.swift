import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// The 模型 / 高级 sheets' saves on a site without accounts.patch (20 §3.2 退路, appendix A S30 / S31, S2D1-09): the PUT merges the
// change onto the redacted `GET :id` detail, so every non-sensitive key stays, no secret is sent (the server keeps the stored
// ones) and nothing prints a credential value.

private let replyJSON = #"{"id":9,"name":"退路账号","platform":"kimi","type":"apikey","status":"active","schedulable":true}"#
private func detail(platform: String = "kimi", _ fields: String) throws -> UpstreamAccount {
    let json = #"{"id":9,"name":"退路账号","platform":"\#(platform)","type":"apikey","status":"active","schedulable":true,"# + fields + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func client(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}
private func sentBody(_ transport: ScriptedTransport) async throws -> JSONValue {
    let request = try #require(await transport.requests.last)
    #expect(request.httpMethod == "PUT")
    return try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
}
private let redactedCredentials = #""credentials":{"base_url":"https://api.moonshot.cn/v1","account_mode":"payg","api_protocol":"chat_completions","#
    + #""model_mapping":{"kimi-k2":"kimi-k2"},"pool_mode_retry_count":5,"header_override":{"x-a":"b"},"temp_unschedulable_rules":[{"status":529,"minutes":1.25}]},"#
    + #""credentials_status":{"has_api_key":true}"#

@Test func putFallbackKeepsEveryNonSensitiveCredentialWhenSavingTheModelMapping() async throws {
    let base = try detail(redactedCredentials)
    var models = AccountModelsDraft(account: base)
    models.mapping = models.mapping.adding(models: ["kimi-k2-turbo"])
    let transport = ScriptedTransport(script: [.reply(okReply(replyJSON))])
    _ = try await client(transport).fullUpdate(id: 9, patch: models.patch(), base: base)
    let expected: JSONValue = ["credentials": [
        "base_url": "https://api.moonshot.cn/v1", "account_mode": "payg", "api_protocol": "chat_completions",
        "model_mapping": ["kimi-k2": "kimi-k2", "kimi-k2-turbo": "kimi-k2-turbo"], "pool_mode_retry_count": 5, "header_override": ["x-a": "b"],
        "temp_unschedulable_rules": [["status": 529, "minutes": .number(Decimal(string: "1.25")!)]]
    ]]
    #expect(try await sentBody(transport) == expected)
}

@Test func putFallbackClearingTheMappingDropsOnlyThatKey() throws {
    let base = try detail(redactedCredentials)
    var models = AccountModelsDraft(account: base)
    models.mapping = AccountModelMapping()
    let body = try JSONDecoder().decode(JSONValue.self, from: models.patch().fullUpdateBody(base: base))
    let credentials = try #require(body["credentials"]?.objectValue)
    #expect(credentials["model_mapping"] == nil && credentials.count == 6 && body["extra"] == nil)
    #expect(Set(credentials.keys).isDisjoint(with: UpstreamAccount.sensitiveCredentialKeys))
}

/// A protocol switch on the fallback: the endpoint keys move, the rest stays, the key the server keeps is never named.
@Test func putFallbackProtocolSwitchSendsNoSecret() throws {
    let base = try detail(redactedCredentials)
    let advanced = AccountAdvancedDraft(account: base, catalog: .builtin).withProtocol("anthropic")
    let body = try JSONDecoder().decode(JSONValue.self, from: advanced.patch().fullUpdateBody(base: base))
    #expect(body["credentials"]?["api_protocol"] == "anthropic" && body["credentials"]?["base_url"] == "https://api.moonshot.cn/anthropic")
    #expect(body["credentials"]?["pool_mode_retry_count"] == 5 && body["credentials"]?["api_key"] == nil && body["credentials_status"] == nil)
}

/// The managed probe keys stay out of the merged extra (or the server answers 400 CONFLICTING_UPSTREAM_BILLING_PROBE_ENABLED);
/// the switch goes at the top level.
@Test func putFallbackExtraKeepsUnrelatedKeysAndLeavesTheManagedProbeKeysOut() throws {
    let base = try detail(platform: "openai", #""extra":{"custom_error_codes":[529],"quota_daily_used":3,"upstream_billing_probe_enabled":false,"upstream_billing_probe":{"status":"ok"}}"#)
    var advanced = AccountAdvancedDraft(account: base, catalog: .builtin)
    advanced.values.openAIPassthrough = true
    advanced.values.upstreamBillingProbe = true
    let body = try JSONDecoder().decode(JSONValue.self, from: advanced.patch().fullUpdateBody(base: base))
    let expected: JSONValue = ["extra": ["custom_error_codes": [529], "quota_daily_used": 3, "openai_passthrough": true], "upstream_billing_probe_enabled": true]
    #expect(body == expected)
}

@Test func patchPathSendsOnlyThePatchMapsWithIfMatch() async throws {
    let base = try detail(redactedCredentials)
    var advanced = AccountAdvancedDraft(account: base, catalog: .builtin)
    advanced.values.poolMode = true
    advanced.values.upstreamBillingProbe = true
    let transport = ScriptedTransport(script: [.reply(okReply(replyJSON, headers: ["ETag": "\"cv-8\""]))])
    _ = try await client(transport).patchAccount(id: 9, body: advanced.patch(), ifMatch: "\"cv-7\"")
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "PATCH" && sentHeader(request, "If-Match") == "\"cv-7\"")
    #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"credentials_patch":{"pool_mode":true},"upstream_billing_probe_enabled":true}"#)
}

/// A server before redaction (S2D1-09): the credential edits stop locally, before anything is sent.
@Test func putFallbackOnAnUnredactedServerSendsNothing() async throws {
    let base = try detail(#""credentials":{"api_key":"sk-test-LEAKED-1234","refresh_token":"rt-LEAKED","model_mapping":{"a":"a"}}"#)
    #expect(base.credentialsArrivedUnredacted && base.credentials?["api_key"] == nil)
    var models = AccountModelsDraft(account: base)
    models.mapping = AccountModelMapping()
    let transport = ScriptedTransport(script: [])
    let error = await thrownAPIError { _ = try await client(transport).fullUpdate(id: 9, patch: models.patch(), base: base) }
    #expect(error?.reason == AccountWriteReason.legacyCredentialsPut)
    #expect(await transport.requests.isEmpty)
}

@Test func draftsAndRequestsNeverPrintCredentialValues() throws {
    let base = try detail(#""credentials":{"api_key":"sk-test-LEAKED-1234","base_url":"https://relay.example.invalid/v1"}"#)
    var models = AccountModelsDraft(account: base)
    models.mapping = models.mapping.adding(models: ["kimi-k2"])
    let advanced = AccountAdvancedDraft(account: base, catalog: .builtin).withProtocol("anthropic")
    let printed: [Any] = [models, advanced, models.patch(), advanced.patch(), advanced.undoPatch()]
    for value in printed {
        #expect(!String(describing: value).contains("LEAKED") && !String(reflecting: value).contains("LEAKED"))
    }
    #expect(!String(describing: models.patch()).contains("kimi-k2"))
}
