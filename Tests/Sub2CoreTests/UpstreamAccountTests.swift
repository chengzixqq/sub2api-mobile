import Foundation
import Testing
@testable import Sub2Core

private let accountBase = #"{"id":9,"name":"账号","platform":"openai","type":"apikey","status":"active","schedulable":true"#
private func account(_ fields: String = "") throws -> UpstreamAccount {
    try JSONDecoder().decode(UpstreamAccount.self, from: Data((accountBase + (fields.isEmpty ? "" : "," + fields) + "}").utf8))
}
private func encodedText(_ account: UpstreamAccount) throws -> String { String(decoding: try JSONEncoder().encode(account), as: UTF8.self) }

@Test func fullDetailDecodesEveryNewField() throws {
    let credentials = #""credentials":{"base_url":"https://api.example.invalid","model_mapping":{"claude-x":"gpt-y"},"account_mode":"pool","api_protocol":"responses","intercept_warmup_requests":true,"pool_mode":true,"oauth_type":"code_assist","expires_at":1792051200}"#
    let proxy = #""proxy":{"id":7,"name":"线路 B","protocol":"socks5","host":"proxy.example.invalid","port":1080,"status":"active","expires_at":"2026-11-01T00:00:00Z","expiry_warn_days":7}"#
    let full = try account(#""updated_at":"2026-10-22T10:00:00Z","proxy_id":7,"proxy_fallback_origin_id":3,"proxy_fallback_origin_name":"原线路","session_idle_timeout_minutes":15,"parent_account_id":41,"credentials_status":{"has_api_key":true},"error_summary":"Authentication failed (401)","token_status":{"auto_refresh":true},"# + credentials + "," + proxy)
    #expect(full.updatedAt == "2026-10-22T10:00:00Z" && full.proxyID == 7)
    #expect(full.proxyFallbackOriginID == 3 && full.proxyFallbackOriginName == "原线路")
    #expect(full.sessionIdleTimeoutMinutes == 15 && full.parentAccountID == 41)
    #expect(full.credentialsStatus == ["has_api_key": true] && !full.credentialsArrivedUnredacted)
    let saved = try #require(full.credentials)
    #expect(saved["base_url"]?.stringValue == "https://api.example.invalid")
    #expect(saved["model_mapping"] == .object(["claude-x": .string("gpt-y")]))
    #expect(saved["account_mode"]?.stringValue == "pool" && saved["api_protocol"]?.stringValue == "responses")
    #expect(saved["intercept_warmup_requests"]?.boolValue == true && saved["pool_mode"]?.boolValue == true)
    #expect(saved["oauth_type"]?.stringValue == "code_assist" && saved["expires_at"]?.intValue == 1_792_051_200)
    let expectedProxy = AccountProxy(id: 7, name: "线路 B", status: "active", expiresAt: "2026-11-01T00:00:00Z", scheme: "socks5",
                                     host: "proxy.example.invalid", port: 1080, expiryWarnDays: 7)
    #expect(full.proxy == expectedProxy)
    #expect(full.errorSummary == "Authentication failed (401)" && full.tokenStatus?.autoRefresh == true)
}

@Test func missingKeysStayNilForOldServersAndLiteItems() throws {
    let old = try account()
    #expect(old.updatedAt == nil && old.proxyID == nil && old.proxyFallbackOriginID == nil && old.proxyFallbackOriginName == nil)
    #expect(old.credentials == nil && old.credentialsStatus == nil && old.sessionIdleTimeoutMinutes == nil && old.parentAccountID == nil)
    #expect(old.extra == nil && old.proxy == nil && !old.credentialsArrivedUnredacted)
    let lite = try account(#""group_ids":[1],"proxy_id":null,"proxy_fallback_origin_id":null,"updated_at":"2026-10-22T10:00:00Z","parent_account_id":null"#)
    #expect(lite.groupIDs == [1] && lite.proxyID == nil && lite.proxyFallbackOriginID == nil && lite.parentAccountID == nil)
    #expect(lite.updatedAt == "2026-10-22T10:00:00Z" && lite.credentials == nil && lite.credentialsStatus == nil)
}

@Test func extraIsKeptVerbatimAndDerivedValuesUnchanged() throws {
    let extraJSON = #"{"custom":{"nested":[1,{"x":null}],"ratio":0.30000000000000001},"upstream_billing_probe":{"status":"ok","fresh_until":"2026-10-15T02:00:00Z","last_error":"upstream text","data":{"effective_rate_multiplier":"1.25","observed_at":"2026-10-15T00:00:00Z"}},"model_rate_limits":{"m":{"rate_limit_reset_at":"2026-10-15T01:30:00Z"},"bad":"x"}}"#
    let raw = try JSONDecoder().decode(JSONValue.self, from: Data(extraJSON.utf8))
    let decoded = try account(#""extra":"# + extraJSON)
    let extra = try #require(decoded.extra)
    #expect(extra.raw == raw)
    #expect(extra["custom"]?["ratio"]?.decimalValue == Decimal(string: "0.30000000000000001"))
    let observedNow = Date(timeIntervalSince1970: 1_792_026_000)
    #expect(extra.upstreamBillingProbe?.historicalMultiplier(at: observedNow) == Decimal(string: "1.25"))
    #expect(extra.modelRateLimits.map(\.model) == ["m"])
    let roundTrip = try JSONDecoder().decode(UpstreamAccount.self, from: JSONEncoder().encode(decoded))
    #expect(roundTrip.extra?.raw == raw)
    #expect(roundTrip.extra?.modelRateLimits == extra.modelRateLimits)
    let rebuilt = try AccountExtra(raw: raw)
    #expect(rebuilt.raw == raw && rebuilt.upstreamBillingProbe?.status == "ok" && rebuilt.modelRateLimits == extra.modelRateLimits)
    for shape in [#""text""#, "[1,2]", "7"] {
        let odd = try account(#""extra":"# + shape)
        let oddRaw = try JSONDecoder().decode(JSONValue.self, from: Data(shape.utf8))
        #expect(odd.extra?.raw == oddRaw, "\(shape)")
        #expect(odd.extra?.upstreamBillingProbe == nil && odd.extra?.modelRateLimits.isEmpty == true, "\(shape)")
    }
}

@Test func nonObjectCredentialsAreTolerated() throws {
    for shape in [#""x""#, "[1]", "5", "null", "true"] {
        let odd = try account(#""credentials":"# + shape + #","credentials_status":"bad""#)
        #expect(odd.credentials == nil && odd.credentialsStatus == nil && !odd.credentialsArrivedUnredacted, "\(shape)")
    }
    let partial = try account(#""credentials_status":{"has_api_key":"yes"}"#)
    #expect(partial.credentialsStatus == nil)
}

@Test func sensitiveCredentialKeysNeverStayInMemory() throws {
    let old = try account(#""credentials":{"api_key":"sk-fixture","refresh_token":"","access_token":null,"cookie":false,"base_url":"https://api.example.invalid"}"#)
    #expect(old.credentials == .object(["base_url": .string("https://api.example.invalid")]))
    #expect(old.credentialsStatus == ["has_api_key": true])
    let merged = try account(#""credentials":{"api_key":"sk-fixture","service_account":{"k":1}},"credentials_status":{"has_session_key":true}"#)
    #expect(merged.credentialsStatus == ["has_session_key": true, "has_api_key": true, "has_service_account": true])
    #expect(merged.credentials == .object([:]))
    #expect(try !encodedText(old).contains("sk-fixture"))
    #expect(try !encodedText(merged).contains("sk-fixture"))
    #expect(UpstreamAccount.sensitiveCredentialKeys == [
        "access_token", "refresh_token", "id_token", "agent_private_key", "api_key", "session_key", "cookie", "password", "sso_token",
        "sso", "sso-rw", "clearTextPassword", "aws_secret_access_key", "aws_session_token", "service_account_json", "service_account", "private_key"
    ])
    let built = UpstreamAccount(id: 1, name: "夹具", platform: "openai", type: "apikey",
                                credentials: .object(["api_key": .string("sk-fixture"), "base_url": .string("https://api.example.invalid")]))
    #expect(built.credentials == .object(["base_url": .string("https://api.example.invalid")]))
    #expect(built.credentialsStatus == ["has_api_key": true] && built.credentialsArrivedUnredacted)
}

/// S2D1-09: a server before credential redaction sends secrets in the clear; the flag lets the PUT fallback refuse credential edits.
@Test func unredactedCredentialsAreFlaggedAndStripped() throws {
    let legacy = try account(#""credentials":{"access_token":"plain-fixture","base_url":"https://api.example.invalid"}"#)
    #expect(legacy.credentialsArrivedUnredacted)
    #expect(legacy.credentials?["access_token"] == nil && legacy.credentialsStatus?["has_access_token"] == true)
    #expect(try !encodedText(legacy).contains("plain-fixture"))
    let redacted = try account(#""credentials":{"base_url":"https://api.example.invalid"},"credentials_status":{"has_access_token":true}"#)
    #expect(!redacted.credentialsArrivedUnredacted && redacted.credentialsStatus?["has_access_token"] == true)
    let roundTrip = try JSONDecoder().decode(UpstreamAccount.self, from: JSONEncoder().encode(legacy))
    #expect(!roundTrip.credentialsArrivedUnredacted && roundTrip.credentialsStatus == legacy.credentialsStatus)
}

@Test func proxyKeepsAddressButNeverLogin() throws {
    let proxied = try account(#""proxy":{"id":2,"name":"线路 A","protocol":"http","host":"proxy.example.invalid","port":8080,"username":"secret-user","password":"secret-password","status":"active"}"#)
    let text = try encodedText(proxied)
    #expect(!text.contains("secret-user") && !text.contains("secret-password"))
    #expect(!text.contains(#""username""#) && !text.contains(#""password""#))
    #expect(proxied.proxy?.scheme == "http" && proxied.proxy?.host == "proxy.example.invalid" && proxied.proxy?.port == 8080)
    #expect(text.contains(#""protocol":"http""#))
    #expect(AccountFieldPresentation.value(.proxy, account: proxied, now: Date(timeIntervalSince1970: 1_800_000_000)) == "线路 A（#2）")
}

@Test func memberwiseInitsAppendDefaults() throws {
    let plain = UpstreamAccount(id: 1, name: "夹具", platform: "openai", type: "apikey")
    #expect(plain.updatedAt == nil && plain.proxyID == nil && plain.proxyFallbackOriginID == nil && plain.proxyFallbackOriginName == nil)
    #expect(plain.credentials == nil && plain.credentialsStatus == nil && plain.sessionIdleTimeoutMinutes == nil)
    #expect(plain.parentAccountID == nil && !plain.credentialsArrivedUnredacted)
    let proxy = AccountProxy(id: 1, name: "线路")
    #expect(proxy.scheme == nil && proxy.host == nil && proxy.port == nil && proxy.expiryWarnDays == nil && proxy.status == nil)
    let probe = try JSONDecoder().decode(AccountBillingProbe.self, from: Data(#"{"status":"ok"}"#.utf8))
    #expect(AccountExtra(upstreamBillingProbe: probe).raw == .object(["upstream_billing_probe": .object(["status": .string("ok")])]))
    #expect(AccountExtra().raw == .object([:]))
    let limited = AccountExtra(modelRateLimitEntries: ["m": .init(rateLimitResetAt: "2026-10-15T01:30:00Z")])
    #expect(limited["model_rate_limits"]?["m"]?["rate_limit_reset_at"]?.stringValue == "2026-10-15T01:30:00Z")
    #expect(limited.modelRateLimits.map(\.model) == ["m"])
}
