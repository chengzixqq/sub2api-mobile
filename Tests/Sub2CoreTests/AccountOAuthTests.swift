import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let oauthAccountJSON = #"{"id":42,"name":"授权账号","platform":"anthropic","type":"oauth","status":"active","schedulable":true}"#

private func oauthClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}
private func oauthAccount(platform: String, type: String = "oauth", _ fields: String = "") throws -> UpstreamAccount {
    let json = #"{"id":42,"name":"授权账号","platform":"\#(platform)","type":"\#(type)","status":"active","schedulable":true"#
        + (fields.isEmpty ? "" : "," + fields) + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func bodyText(_ request: URLRequest?) -> String { String(decoding: request?.httpBody ?? Data(), as: UTF8.self) }
private func linkReply(_ url: String = "https://auth.example.com/authorize?state=st-url", session: String = "sess-1", state: String? = nil) -> HTTPResponse {
    let stateField = state.map { #","state":"\#($0)""# } ?? ""
    return okReply(#"{"auth_url":"\#(url)","session_id":"\#(session)"\#(stateField)}"#)
}
/// A link as generate-auth-url returns it, for the exchange and reauthorize bodies.
private func fixtureLink(_ request: OAuthLinkRequest, state: String?, session: String = "sess-1") -> OAuthLink {
    OAuthLink(request: request, authURL: URL(string: "https://auth.example.com/authorize")!, sessionID: session, state: state,
              lifetime: OAuthLinkLifetime(generatedAt: ContinuousClock.now))
}
private let claudeTokenJSON = #"{"access_token":"at-secret-fixture","token_type":"Bearer","expires_in":28800,"expires_at":1792022400,"refresh_token":"rt-secret-fixture","email_address":"ops@example.invalid"}"#

// MARK: - Platform names

@Test func oauthPlatformMapsAccountPlatformsAndCallbacks() {
    #expect(OAuthPlatform(accountPlatform: " Anthropic ") == .anthropic && OAuthPlatform(accountPlatform: "openai") == .openai)
    #expect(OAuthPlatform(accountPlatform: "gemini") == .gemini && OAuthPlatform(accountPlatform: "antigravity") == .antigravity)
    #expect(OAuthPlatform(accountPlatform: "grok") == .grok)
    #expect(OAuthPlatform(accountPlatform: "sora") == nil && OAuthPlatform(accountPlatform: "") == nil)
    #expect(OAuthPlatform.allCases.map(\.signInName) == ["Claude", "ChatGPT", "Google", "Google", "xAI"])
    #expect(OAuthPlatform.allCases.map(\.upstreamName) == ["Claude", "OpenAI", "Google", "Google", "xAI"])
    #expect(OAuthPlatform.allCases.map(\.callbackPort) == [nil, 1455, nil, 8085, 56121])
    #expect(OAuthPlatform.allCases.map(\.callbackAddress) == [nil, "localhost:1455", nil, "localhost:8085", "127.0.0.1:56121"])
    #expect(OAuthPlatform.allCases.filter(\.showsCode) == [.anthropic, .gemini])
    #expect(OAuthPlatform.allCases.filter(\.consumesSessionOnExchange) == [.grok])
    #expect(OAuthAuthKind(accountType: "setup-token") == .setupToken && OAuthAuthKind(accountType: "oauth") == .oauth)
    #expect(OAuthAuthKind(accountType: "apikey") == nil)
    #expect(OAuthAuthKind.allCases.map(\.title) == ["OAuth", "Setup Token"] && OAuthAuthKind.allCases.map(\.scopeNote) == ["完整权限", "只授予推理权限"])
    #expect(GeminiOAuthType(credentialValue: "google_one") == .googleOne && GeminiOAuthType(credentialValue: "ai_studio") == .aiStudio)
    #expect(GeminiOAuthType(credentialValue: nil) == .codeAssist && GeminiOAuthType(credentialValue: "x") == .codeAssist)
    #expect(GeminiOAuthType.allCases.map(\.title) == ["Code Assist", "Google One", "AI Studio"])
}

// MARK: - Authorization links

@Test func authURLRequestsUseEachPlatformPathAndBody() async throws {
    let cases: [(OAuthLinkRequest, String, String)] = [
        (OAuthLinkRequest(platform: .anthropic, proxyID: 3), "/api/v1/admin/accounts/generate-auth-url", #"{"proxy_id":3}"#),
        (OAuthLinkRequest(platform: .anthropic, kind: .setupToken), "/api/v1/admin/accounts/generate-setup-token-url", "{}"),
        (OAuthLinkRequest(platform: .openai, accountID: 9), "/api/v1/admin/openai/generate-auth-url", "{}"),
        (OAuthLinkRequest(platform: .gemini, proxyID: 5, geminiOAuthType: .codeAssist, projectID: " proj-1 ", tierID: "gcp_standard"),
         "/api/v1/admin/gemini/oauth/auth-url", #"{"oauth_type":"code_assist","project_id":"proj-1","proxy_id":5,"tier_id":"gcp_standard"}"#),
        (OAuthLinkRequest(platform: .gemini, geminiOAuthType: .googleOne, projectID: "proj-1"), "/api/v1/admin/gemini/oauth/auth-url",
         #"{"oauth_type":"google_one"}"#),
        (OAuthLinkRequest(platform: .antigravity, proxyID: 0), "/api/v1/admin/antigravity/oauth/auth-url", "{}"),
        (OAuthLinkRequest(platform: .grok, proxyID: 2, accountID: 9), "/api/v1/admin/grok/oauth/auth-url", #"{"account_id":9,"proxy_id":2}"#)
    ]
    for (request, path, body) in cases {
        let transport = ScriptedTransport(script: [.reply(linkReply())])
        _ = try await oauthClient(transport).generateAuthURL(request)
        let sent = try #require(await transport.requests.first)
        #expect(sent.httpMethod == "POST" && sent.url?.path == path, "\(path)")
        #expect(bodyText(sent) == body, "\(path)")
        #expect(sentHeader(sent, "Idempotency-Key") == nil)
    }
    let transport = ScriptedTransport(script: [.reply(linkReply())])
    let refused = await thrownAPIError { _ = try await oauthClient(transport).generateAuthURL(OAuthLinkRequest(platform: .openai, kind: .setupToken)) }
    #expect(refused?.kind == .validation)
    #expect(await transport.requests.isEmpty)
}

@Test func authURLReplyKeepsStateAndRejectsUnsafeLinks() async throws {
    let gemini = ScriptedTransport(script: [.reply(linkReply("https://accounts.google.com/o/oauth2/v2/auth?state=g7Hn3", state: "g7Hn3"))])
    let link = try await oauthClient(gemini).generateAuthURL(OAuthLinkRequest(platform: .gemini))
    #expect(link.state == "g7Hn3" && link.sessionID == "sess-1" && link.platform == .gemini)
    #expect(link.authURL.absoluteString == "https://accounts.google.com/o/oauth2/v2/auth?state=g7Hn3")
    let remaining = link.lifetime.remaining(at: ContinuousClock.now)
    #expect(remaining > .seconds(1_799) && remaining <= .seconds(1_800))
    #expect(!String(describing: link).contains("sess-1") && !String(describing: link).contains("g7Hn3"))
    let openai = ScriptedTransport(script: [.reply(linkReply("https://auth.openai.com/oauth/authorize?client_id=x&state=st-url"))])
    #expect(try await oauthClient(openai).generateAuthURL(OAuthLinkRequest(platform: .openai)).state == "st-url")
    for reply in [linkReply("http://auth.example.com/authorize"), linkReply("javascript:alert(1)"), linkReply(""), linkReply(session: " ")] {
        let transport = ScriptedTransport(script: [.reply(reply)])
        let error = await thrownAPIError { _ = try await oauthClient(transport).generateAuthURL(OAuthLinkRequest(platform: .anthropic)) }
        #expect(error == .invalidResponse)
    }
}

@Test func reauthorizeLinkRequestReadsAccountProxyTypeAndTier() throws {
    let claude = try #require(OAuthLinkRequest.reauthorize(try oauthAccount(platform: "anthropic", type: "setup-token", #""proxy_id":3"#)))
    #expect(claude.platform == .anthropic && claude.kind == .setupToken && claude.proxyID == 3)
    #expect(OAuthLinkRequest.reauthorize(try oauthAccount(platform: "anthropic", type: "setup-token"), kind: .oauth)?.kind == .oauth)
    let gemini = try #require(OAuthLinkRequest.reauthorize(
        try oauthAccount(platform: "gemini", #""credentials":{"oauth_type":"google_one","tier_id":"google_one_free"}"#)))
    #expect(gemini.geminiOAuthType == .googleOne && gemini.tierID == "google_one_free")
    #expect(OAuthLinkRequest.reauthorize(try oauthAccount(platform: "gemini"))?.geminiOAuthType == .codeAssist)
    #expect(OAuthLinkRequest.reauthorize(try oauthAccount(platform: "grok"))?.accountID == 42)
    #expect(OAuthLinkRequest.reauthorize(try oauthAccount(platform: "openai", #""proxy_id":null"#))?.proxyID == nil)
    #expect(OAuthLinkRequest.reauthorize(try oauthAccount(platform: "openai"))?.kind == .oauth)
    #expect(OAuthLinkRequest.reauthorize(try oauthAccount(platform: "sora")) == nil)
    #expect(OAuthLinkRequest.reauthorize(try oauthAccount(platform: "bedrock")) == nil)
}

@Test func linkLifetimeExpiresThirtyMinutesAfterGeneration() {
    let start = ContinuousClock.now
    let lifetime = OAuthLinkLifetime(generatedAt: start)
    #expect(OAuthLinkLifetime.validity == .seconds(1_800))
    #expect(lifetime.remaining(at: start) == .seconds(1_800) && lifetime.remainingSeconds(at: start) == 1_800)
    #expect(!lifetime.isExpired(at: start + .seconds(1_799)) && lifetime.remainingSeconds(at: start + .seconds(1_799)) == 1)
    #expect(lifetime.isExpired(at: start + .seconds(1_800)) && lifetime.remaining(at: start + .seconds(1_800)) == .zero)
    #expect(lifetime.remaining(at: start + .seconds(3_600)) == .zero)
}

// MARK: - Code exchange

@Test func exchangeCodeBodiesFollowPlatformRules() async throws {
    let cases: [(OAuthLink, OAuthCode, Int?, String, String)] = [
        (fixtureLink(OAuthLinkRequest(platform: .anthropic), state: nil), OAuthCode(value: "  abc#st1 "), 3,
         "/api/v1/admin/accounts/exchange-code", #"{"code":"abc#st1","proxy_id":3,"session_id":"sess-1"}"#),
        (fixtureLink(OAuthLinkRequest(platform: .anthropic, kind: .setupToken), state: nil), OAuthCode(value: "abc"), nil,
         "/api/v1/admin/accounts/exchange-setup-token-code", #"{"code":"abc","session_id":"sess-1"}"#),
        (fixtureLink(OAuthLinkRequest(platform: .openai), state: "st-url"), OAuthCode(value: "ac_1"), nil,
         "/api/v1/admin/openai/exchange-code", #"{"code":"ac_1","session_id":"sess-1","state":"st-url"}"#),
        (fixtureLink(OAuthLinkRequest(platform: .openai), state: "st-url"), OAuthCode(value: "ac_1", state: "st-cb"), nil,
         "/api/v1/admin/openai/exchange-code", #"{"code":"ac_1","session_id":"sess-1","state":"st-cb"}"#),
        (fixtureLink(OAuthLinkRequest(platform: .gemini, geminiOAuthType: .googleOne, tierID: "google_one_free"), state: "g7Hn3"),
         OAuthCode(value: "4/0AV"), nil, "/api/v1/admin/gemini/oauth/exchange-code",
         #"{"code":"4\/0AV","oauth_type":"google_one","session_id":"sess-1","state":"g7Hn3","tier_id":"google_one_free"}"#),
        (fixtureLink(OAuthLinkRequest(platform: .antigravity), state: "a2Lp9"), OAuthCode(value: "4/0AV"), 7,
         "/api/v1/admin/antigravity/oauth/exchange-code", #"{"code":"4\/0AV","proxy_id":7,"session_id":"sess-1","state":"a2Lp9"}"#),
        (fixtureLink(OAuthLinkRequest(platform: .grok, accountID: 9), state: "k4Vb1"), OAuthCode(value: "xg_5"), nil,
         "/api/v1/admin/grok/oauth/exchange-code", #"{"account_id":9,"code":"xg_5","session_id":"sess-1","state":"k4Vb1"}"#)
    ]
    for (link, code, proxyID, path, body) in cases {
        let transport = ScriptedTransport(script: [.reply(okReply(claudeTokenJSON))])
        let info = try await oauthClient(transport).exchangeCode(link, code: code, proxyID: proxyID)
        #expect(info.platform == link.platform && info.kind == link.request.kind)
        let sent = try #require(await transport.requests.first)
        #expect(sent.httpMethod == "POST" && sent.url?.path == path, "\(path)")
        #expect(bodyText(sent) == body, "\(path)")
    }
    let missing = ScriptedTransport(script: [.reply(okReply(#"{"token_type":"Bearer"}"#))])
    let error = await thrownAPIError {
        _ = try await oauthClient(missing).exchangeCode(fixtureLink(OAuthLinkRequest(platform: .anthropic), state: nil), code: OAuthCode(value: "abc"), proxyID: nil)
    }
    #expect(error == .invalidResponse)
}

@Test func exchangeCodeRequiresStateBeforeSending() async throws {
    for platform in [OAuthPlatform.openai, .gemini, .antigravity, .grok] {
        let transport = ScriptedTransport(script: [.reply(okReply(claudeTokenJSON))])
        let link = fixtureLink(OAuthLinkRequest(platform: platform), state: nil)
        let error = await thrownAPIError { _ = try await oauthClient(transport).exchangeCode(link, code: OAuthCode(value: "c1"), proxyID: nil) }
        #expect(error?.kind == .validation, "\(platform)")
        #expect(await transport.requests.isEmpty)
        #expect(throws: APIError.self) { _ = try AccountReauthorizeRequest(link: link, code: OAuthCode(value: "c1")) }
    }
    let transport = ScriptedTransport(script: [.reply(okReply(claudeTokenJSON))])
    _ = try await oauthClient(transport).exchangeCode(fixtureLink(OAuthLinkRequest(platform: .anthropic), state: nil), code: OAuthCode(value: "c1"), proxyID: nil)
    #expect(await transport.requests.count == 1)
    _ = try AccountReauthorizeRequest(link: fixtureLink(OAuthLinkRequest(platform: .anthropic), state: nil), code: OAuthCode(value: "c1"))
}

// MARK: - Reauthorize and apply

@Test func reauthorizeBodiesNeverCarryPreserveStatusOrRedirect() async throws {
    let cases: [(OAuthLink, OAuthCode, String)] = [
        (fixtureLink(OAuthLinkRequest(platform: .anthropic, kind: .setupToken, proxyID: 3), state: nil), OAuthCode(value: "abc#st1"),
         #"{"auth_kind":"setup-token","code":"abc#st1","proxy_id":3,"session_id":"sess-1"}"#),
        (fixtureLink(OAuthLinkRequest(platform: .openai), state: "st1"), OAuthCode(value: "ac_1"), #"{"code":"ac_1","session_id":"sess-1","state":"st1"}"#),
        (fixtureLink(OAuthLinkRequest(platform: .gemini, tierID: "gcp_standard"), state: "g7"), OAuthCode(value: "4/0AV"),
         #"{"code":"4\/0AV","oauth_type":"code_assist","session_id":"sess-1","state":"g7","tier_id":"gcp_standard"}"#),
        (fixtureLink(OAuthLinkRequest(platform: .antigravity), state: "a1"), OAuthCode(value: "c1"), #"{"code":"c1","session_id":"sess-1","state":"a1"}"#),
        (fixtureLink(OAuthLinkRequest(platform: .grok, accountID: 42), state: "k4"), OAuthCode(value: "xg"), #"{"code":"xg","session_id":"sess-1","state":"k4"}"#)
    ]
    for (link, code, body) in cases {
        let request = try AccountReauthorizeRequest(link: link, code: code)
        let transport = ScriptedTransport(script: [.reply(okReply(oauthAccountJSON))])
        let client = oauthClient(transport)
        let account = try await client.reauthorize(accountID: 42, request: request)
        #expect(account.id == 42)
        let sent = try #require(await transport.requests.first)
        #expect(sent.httpMethod == "POST" && sent.url?.path == "/api/v1/admin/accounts/42/reauthorize")
        #expect(bodyText(sent) == body)
        #expect(!body.contains("preserve_status") && !body.contains("redirect_uri"))
        #expect(try await client.encode(request) == sent.httpBody)
    }
}

@Test func reauthorizeKeepsPersistFailureMetadata() async throws {
    let request = try AccountReauthorizeRequest(link: fixtureLink(OAuthLinkRequest(platform: .openai), state: "st1"), code: OAuthCode(value: "ac_1"))
    let persist = ScriptedTransport(script: [.reply(errorReply(500, reason: "REAUTH_PERSIST_FAILED", extra: #","metadata":{"retry_within_seconds":300,"cause_reason":"X"}"#))])
    let error = await thrownAPIError { _ = try await oauthClient(persist).reauthorize(accountID: 42, request: request) }
    #expect(error?.reason == "REAUTH_PERSIST_FAILED" && error?.metadata["retry_within_seconds"] == "300")
    #expect(error?.localizedDescription == "令牌已换到，但没保存成功")
    #expect(await persist.requests.count == 1)
    let shadow = ScriptedTransport(script: [.reply(errorReply(400, reason: "REAUTH_UNSUPPORTED", extra: #","metadata":{"detail":"shadow_account"}"#))])
    let unsupported = await thrownAPIError { _ = try await oauthClient(shadow).reauthorize(accountID: 42, request: request) }
    #expect(unsupported?.metadata["detail"] == "shadow_account")
    #expect(await shadow.requests.count == 1)
}

@Test func applyOAuthCredentialsSendsOnlyTypeCredentialsAndExtra() async throws {
    let credentials: [String: JSONValue] = ["access_token": "at-fixture", "expires_at": 1_792_022_400]
    let transport = ScriptedTransport(script: [.reply(okReply(oauthAccountJSON))])
    let client = oauthClient(transport)
    let account = try await client.applyOAuthCredentials(accountID: 42, type: .oauth, credentials: credentials, extra: ["email": "ops@example.invalid"])
    #expect(account.id == 42)
    var sent = await transport.requests
    #expect(sent.first?.url?.path == "/api/v1/admin/accounts/42/apply-oauth-credentials" && sent.first?.httpMethod == "POST")
    #expect(bodyText(sent.first) == #"{"credentials":{"access_token":"at-fixture","expires_at":1792022400},"extra":{"email":"ops@example.invalid"},"type":"oauth"}"#)
    _ = try await client.applyOAuthCredentials(accountID: 42, type: .setupToken, credentials: credentials, extra: nil)
    sent = await transport.requests
    #expect(bodyText(sent.last) == #"{"credentials":{"access_token":"at-fixture","expires_at":1792022400},"type":"setup-token"}"#)
    #expect(!sent.contains { bodyText($0).contains("preserve_status") })
    for bad: [String: JSONValue] in [["expires_at": 1], ["access_token": ""], ["access_token": 5]] {
        #expect(await thrownAPIError { _ = try await client.applyOAuthCredentials(accountID: 42, type: .oauth, credentials: bad, extra: nil) }?.kind == .validation)
    }
    #expect(await thrownAPIError { _ = try await client.applyOAuthCredentials(accountID: 0, type: .oauth, credentials: credentials, extra: nil) }?.kind == .validation)
    #expect(await transport.requests.count == 2)
}

@Test func oauthWritesAreSentOnceWithoutIdempotencyKey() async throws {
    let link = fixtureLink(OAuthLinkRequest(platform: .openai), state: "st1")
    let reauthorize = try AccountReauthorizeRequest(link: link, code: OAuthCode(value: "ac_1"))
    let calls: [@Sendable (APIClient) async throws -> Void] = [
        { _ = try await $0.generateAuthURL(OAuthLinkRequest(platform: .openai)) },
        { _ = try await $0.exchangeCode(link, code: OAuthCode(value: "ac_1"), proxyID: nil) },
        { _ = try await $0.reauthorize(accountID: 42, request: reauthorize) },
        { _ = try await $0.applyOAuthCredentials(accountID: 42, type: .oauth, credentials: ["access_token": "at-fixture"], extra: nil) }
    ]
    for call in calls {
        for step in [ScriptStep.fail(URLError(.timedOut)), .reply(errorReply(502))] {
            let transport = ScriptedTransport(script: [step])
            let client = oauthClient(transport)
            #expect(await thrownAPIError { try await call(client) } != nil)
            let sent = await transport.requests
            #expect(sent.count == 1)
            #expect(sentHeader(sent.first, "Idempotency-Key") == nil && sent.first?.timeoutInterval == 30)
        }
    }
}

// MARK: - Secrets stay out of text

@Test func tokenInfoAndCodesNeverAppearInDescriptions() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(claudeTokenJSON))])
    let link = fixtureLink(OAuthLinkRequest(platform: .anthropic), state: "st-secret", session: "sess-secret")
    let info = try await oauthClient(transport).exchangeCode(link, code: OAuthCode(value: "code-secret"), proxyID: nil)
    let code = OAuthCode(value: "code-secret", state: "st-secret")
    let request = try AccountReauthorizeRequest(link: link, code: code)
    let secrets = ["at-secret-fixture", "rt-secret-fixture", "code-secret", "sess-secret", "st-secret"]
    for value in [info as Any, code, request, link] {
        var dumped = ""
        dump(value, to: &dumped)
        for text in [String(describing: value), String(reflecting: value), "\(value)", dumped] {
            #expect(!secrets.contains { text.contains($0) }, "\(text)")
        }
    }
    #expect(!((info as Any) is any Encodable))
    #expect(info.accountEmail == "ops@example.invalid")
    let openai = try OAuthTokenInfo(platform: .openai, kind: .oauth, fields: ["access_token": "at", "email": "codex@example.invalid", "email_address": "x"])
    #expect(openai.accountEmail == "codex@example.invalid")
    let fixture = try OAuthTokenInfo.fixture(platform: .grok, kind: .oauth, fields: ["access_token": "at-fixture"])
    #expect(fixture.platform == .grok)
    #expect(throws: APIError.self) { _ = try OAuthTokenInfo.fixture(platform: .grok, kind: .oauth, fields: ["access_token": ""]) }
}
