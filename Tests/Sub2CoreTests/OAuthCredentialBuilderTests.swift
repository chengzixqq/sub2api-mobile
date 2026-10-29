import Foundation
import Testing
@testable import Sub2Core

private func token(_ platform: OAuthPlatform, kind: OAuthAuthKind = .oauth, _ fields: [String: JSONValue]) throws -> OAuthTokenInfo {
    try OAuthTokenInfo(platform: platform, kind: kind, fields: fields)
}

// MARK: - Credentials

@Test func claudeCredentialsKeepTokenReplyAndExtraCarriesIdentity() throws {
    let reply: [String: JSONValue] = [
        "access_token": "at-fixture", "token_type": "Bearer", "expires_in": 28_800, "expires_at": 1_792_022_400, "refresh_token": "rt-fixture",
        "scope": "user:inference", "org_uuid": "org-1", "account_uuid": "acct-1", "email_address": "ops@example.invalid"
    ]
    let built = OAuthCredentialBuilder.build(try token(.anthropic, reply))
    #expect(built.type == .oauth && built.credentials == reply)
    #expect(built.extra == ["org_uuid": "org-1", "account_uuid": "acct-1", "email_address": "ops@example.invalid"])
    let bare = OAuthCredentialBuilder.build(try token(.anthropic, kind: .setupToken, ["access_token": "at-fixture", "org_uuid": ""]))
    #expect(bare.type == .setupToken && bare.extra == nil)
}

@Test func openAICredentialsPickComposableKeys() throws {
    let reply: [String: JSONValue] = [
        "access_token": "at-fixture", "expires_at": 1_792_022_400, "expires_in": 864_000, "refresh_token": "rt-fixture", "id_token": "id-fixture",
        "email": "codex@example.invalid", "chatgpt_account_id": "acct-1", "chatgpt_user_id": "user-1", "organization_id": "org-1",
        "plan_type": "plus", "subscription_expires_at": 1_800_000_000, "client_id": "app_1", "auth_mode": "chatgpt", "privacy_mode": "on",
        "name": "Ops"
    ]
    let built = OAuthCredentialBuilder.build(try token(.openai, reply))
    #expect(Set(built.credentials.keys) == ["access_token", "expires_at", "refresh_token", "id_token", "email", "chatgpt_account_id", "chatgpt_user_id",
                                             "organization_id", "plan_type", "subscription_expires_at", "client_id"])
    #expect(built.credentials["expires_at"] == 1_792_022_400 && built.type == .oauth)
    #expect(built.extra == ["email": "codex@example.invalid", "name": "Ops", "privacy_mode": "on"])
    let sparse = OAuthCredentialBuilder.build(try token(.openai, ["access_token": "at-fixture", "refresh_token": "", "name": ""]))
    #expect(Set(sparse.credentials.keys) == ["access_token"] && sparse.extra == nil)
}

@Test func geminiAndAntigravityStringifyExpiryAndDropEmptyValues() throws {
    let gemini = OAuthCredentialBuilder.build(try token(.gemini, [
        "access_token": "at-fixture", "refresh_token": "", "token_type": "Bearer", "expires_at": .number(Decimal(string: "1792022400.9")!),
        "scope": "cloud", "project_id": "proj-1", "oauth_type": "google_one", "tier_id": "google_one_free", "extra": ["drive": "ok"], "email": "g@example.invalid"
    ]))
    #expect(gemini.credentials == ["access_token": "at-fixture", "token_type": "Bearer", "expires_at": "1792022400", "scope": "cloud",
                                   "project_id": "proj-1", "oauth_type": "google_one", "tier_id": "google_one_free"])
    #expect(gemini.extra == ["drive": "ok"])
    let padded = OAuthCredentialBuilder.build(try token(.gemini, ["access_token": "at-fixture", "expires_at": " 1792022400 ", "extra": "x"]))
    #expect(padded.credentials == ["access_token": "at-fixture", "expires_at": "1792022400"] && padded.extra == nil)
    let antigravity = OAuthCredentialBuilder.build(try token(.antigravity, [
        "access_token": "at-fixture", "refresh_token": "rt-fixture", "expires_at": 1_792_022_400, "project_id": "proj-2",
        "email": "a@example.invalid", "plan_type": "", "token_type": "Bearer", "scope": "x"
    ]))
    #expect(antigravity.credentials == ["access_token": "at-fixture", "refresh_token": "rt-fixture", "expires_at": "1792022400",
                                        "project_id": "proj-2", "email": "a@example.invalid", "token_type": "Bearer"])
    #expect(antigravity.extra == nil)
}

@Test func grokCredentialsDropEmptyValuesAndNeverSetBaseURL() throws {
    let built = OAuthCredentialBuilder.build(try token(.grok, [
        "access_token": "at-secret-fixture", "token_type": "Bearer", "expires_at": "2026-10-24T08:30:00Z", "client_id": "cli", "team_id": "",
        "base_url": "https://api.example.invalid", "sso_token": "sso-secret", "refresh_token": "rt-fixture", "email": "x@example.invalid",
        "subscription_tier": "pro"
    ]))
    #expect(built.credentials == ["access_token": "at-secret-fixture", "token_type": "Bearer", "expires_at": "2026-10-24T08:30:00Z", "client_id": "cli",
                                  "refresh_token": "rt-fixture", "email": "x@example.invalid", "subscription_tier": "pro"])
    #expect(built.extra == ["email": "x@example.invalid", "subscription_tier": "pro"])
    #expect(OAuthCredentialBuilder.build(try token(.grok, ["access_token": "at"])).extra == nil)
    var dumped = ""
    dump(built, to: &dumped)
    for text in [String(describing: built), String(reflecting: built), dumped] { #expect(!text.contains("at-secret-fixture")) }
}

// MARK: - Callback parsing

@Test func callbackParsingTable() {
    func code(_ value: String, _ state: String?) -> OAuthCallback.Parsed { .code(OAuthCode(value: value, state: state)) }
    let cases: [(String, OAuthPlatform, OAuthCallback.Parsed)] = [
        ("  abc123#state9  ", .anthropic, code("abc123#state9", nil)),
        ("http://localhost:1455/auth/callback?code=ac_1&scope=x&state=st1", .openai, code("ac_1", "st1")),
        ("http://localhost:8085/callback?state=a2Lp9&code=4%2F0AVMB", .antigravity, code("4/0AVMB", "a2Lp9")),
        ("http://127.0.0.1:56121/callback?code=xg_5&state=k4", .grok, code("xg_5", "k4")),
        ("code=abc&state=s", .openai, code("abc", "s")),
        ("?code=abc&state=s", .grok, code("abc", "s")),
        ("4/0AVMBsJh7", .gemini, code("4/0AVMBsJh7", nil)),
        ("http://localhost:1455/auth/callback?code=4/0AV&state=g7", .gemini, code("4/0AV", "g7")),
        ("http://localhost:1455/auth/callback?error=access_denied&state=s", .openai, .denied),
        ("http://localhost:1455/auth/callback?state=s", .openai, .invalid),
        ("?error=server_error", .openai, .invalid),
        ("", .openai, .empty), ("  ", .anthropic, .empty),
        ("http://local host/cb?code=a%20b&state=c", .openai, code("a b", "c"))
    ]
    for (input, platform, expected) in cases {
        #expect(OAuthCallback.parse(input, platform: platform) == expected, "\(input)")
    }
}
