import Foundation
import Testing
@testable import Sub2Core

private let catalog = MetaCatalog.builtin
private let secret = "sk-secret-fixture-0000"
private let privateKey = "PRIVATE-KEY-FIXTURE"
private let vertexJSON = #"{"type":"service_account","project_id":"demo-project","client_email":"sa@demo-project.example.invalid","private_key":"PRIVATE-KEY-FIXTURE"}"#

private func methods(_ platform: String) -> [AccountNewMethod] { AccountNewCatalog.methods(for: platform, in: catalog) }
private func picked(_ platform: String, _ methodID: String, legacy: Bool = false) throws -> AccountNewDraft {
    let draft = AccountNewDraft(isLegacyServer: legacy).switchingPlatform(to: platform, methods: methods(platform),
                                                                          suggestedName: AccountNewNaming.suggestedName(platform: platform, existingCount: 0))
    return draft.switchingMethod(to: try #require(methods(platform).first { $0.id == methodID }))
}
private func keyed(_ platform: String, _ methodID: String = "apikey", base: String = "", legacy: Bool = false) throws -> AccountNewDraft {
    var draft = try picked(platform, methodID, legacy: legacy)
    draft.apiKey = " \(secret) "; draft.baseURL = base
    return draft
}
private func vertexFile() throws -> VertexServiceAccountFile { try VertexServiceAccountFile(fileName: "sa.json", data: Data(("\n" + vertexJSON + "\n").utf8)) }
private func anthropicGrant(_ kind: OAuthAuthKind, _ fields: [String: JSONValue] = [:]) throws -> AccountNewOAuthGrant {
    let token: [String: JSONValue] = ["access_token": "at-fixture"]
    return AccountNewOAuthGrant(try OAuthTokenInfo.fixture(platform: .anthropic, kind: kind, fields: token.merging(fields) { _, new in new }))
}
private func printed<T>(_ value: T) -> [String] {
    var dumped = ""
    dump(value, to: &dumped)
    return [String(describing: value), String(reflecting: value), "\(value)", dumped]
}

// MARK: - Credentials

@Test func apiKeyCredentialsFillOfficialAddresses() throws {
    let official = ["anthropic": "https://api.anthropic.com", "openai": "https://api.openai.com", "grok": "https://api.x.ai/v1",
                    "typesafe": "https://api.typesafe.ai"]
    for (platform, url) in official {
        let built = try keyed(platform).builtCredentials()
        #expect(built.type == "apikey" && built.extra == nil, "\(platform)")
        #expect(built.credentials == ["api_key": .string(secret), "base_url": .string(url)], "\(platform)")
    }
    #expect(try keyed("gemini").builtCredentials().credentials
            == ["api_key": .string(secret), "base_url": "https://generativelanguage.googleapis.com", "tier_id": "aistudio_free"])
    #expect(try keyed("gemini", base: " https://proxy.example.com ").builtCredentials().credentials
            == ["api_key": .string(secret), "base_url": "https://proxy.example.com"])
    #expect(try keyed("openai", base: " https://relay.example.invalid/v1 ").builtCredentials().credentials["base_url"] == "https://relay.example.invalid/v1")
}

@Test func multiProtocolCredentialsFollowTheCatalog() throws {
    let adaptive = try keyed("kimi", "mode.payg").builtCredentials().credentials
    #expect(adaptive == ["api_key": .string(secret), "account_mode": "payg", "api_protocol": "adaptive", "base_url": "https://api.moonshot.cn/v1",
                         "api_base_urls": ["anthropic": "https://api.moonshot.cn/anthropic", "chat_completions": "https://api.moonshot.cn/v1",
                                           "responses": "https://api.moonshot.cn/v1"]])
    var coding = try keyed("kimi", "mode.coding")
    coding.apiProtocol = "anthropic"
    #expect(try coding.builtCredentials().credentials
            == ["api_key": .string(secret), "account_mode": "coding", "api_protocol": "anthropic", "base_url": "https://api.kimi.com/coding"])
    var minimax = try keyed("minimax", "mode.payg")
    minimax.apiProtocol = "chat_completions"; minimax.usesCustomEndpoint = true; minimax.customEndpoint = " https://api.minimax.io/v1 "
    #expect(try minimax.builtCredentials().credentials["base_url"] == "https://api.minimax.io/v1")
    minimax.apiProtocol = "unknown"
    #expect(minimax.effectiveProtocol == "adaptive")
    #expect(try keyed("cline", "mode.payg").builtCredentials().credentials
            == ["api_key": .string(secret), "account_mode": "payg", "api_protocol": "chat_completions", "base_url": "https://api.cline.bot/api/v1"])
}

@Test func upstreamBedrockAndVertexCredentials() throws {
    var upstream = try picked("antigravity", "upstream")
    upstream.upstreamBaseURL = " https://upstream.example.invalid "; upstream.upstreamAPIKey = secret
    let plain = try upstream.builtCredentials()
    #expect(plain.type == "apikey" && plain.credentials == ["base_url": "https://upstream.example.invalid", "api_key": .string(secret)] && plain.extra == nil)
    upstream = upstream.settingMixedScheduling(true, groups: []).draft
    upstream.allowOverages = true
    #expect(try upstream.builtCredentials().extra == ["allow_overages": true, "mixed_scheduling": true])
    var sigv4 = try picked("anthropic", "bedrock")
    sigv4.awsAccessKeyID = "AKIAFIXTURE"; sigv4.awsSecretAccessKey = secret; sigv4.awsRegion = " "
    #expect(try sigv4.builtCredentials().credentials
            == ["auth_mode": "sigv4", "aws_region": "us-east-1", "aws_access_key_id": "AKIAFIXTURE", "aws_secret_access_key": .string(secret)])
    sigv4.awsSessionToken = "session-fixture"; sigv4.awsRegion = "eu-west-1"
    let withSession = try sigv4.builtCredentials()
    #expect(withSession.type == "bedrock" && withSession.credentials["aws_session_token"] == "session-fixture" && withSession.credentials["aws_region"] == "eu-west-1")
    var bedrockKey = try picked("anthropic", "bedrock")
    bedrockKey.bedrockAuth = .apikey; bedrockKey.bedrockAPIKey = secret
    #expect(try bedrockKey.builtCredentials().credentials == ["auth_mode": "apikey", "aws_region": "us-east-1", "api_key": .string(secret)])
    var vertex = try picked("gemini", "vertex")
    vertex.vertexFile = try vertexFile()
    let built = try vertex.builtCredentials()
    #expect(built.type == "service_account")
    #expect(built.credentials == ["service_account_json": .string(vertexJSON), "project_id": "demo-project", "client_email": "sa@demo-project.example.invalid",
                                  "location": "global", "tier_id": "vertex"])
}

@Test func oauthCredentialsComeFromTheGrant() throws {
    var setup = try picked("anthropic", "oauth").switchingClaudeAuthKind(.setupToken)
    setup.oauthGrant = try anthropicGrant(.setupToken, ["org_uuid": "org-fixture", "expires_at": 1_893_456_000])
    let built = try setup.builtCredentials()
    #expect(built.type == "setup-token" && built.credentials == ["access_token": "at-fixture", "org_uuid": "org-fixture", "expires_at": 1_893_456_000])
    #expect(built.extra == ["org_uuid": "org-fixture"] && setup.oauthGrant?.email == nil)
    setup.oauthGrant = try anthropicGrant(.oauth)
    let mismatch = #expect(throws: APIError.self) { _ = try setup.builtCredentials() }
    #expect(mismatch?.localizedDescription == "还差 授权")
    var antigravity = try picked("antigravity", "oauth").settingMixedScheduling(true, groups: []).draft
    antigravity.oauthGrant = AccountNewOAuthGrant(platform: .antigravity, type: .oauth, credentials: ["access_token": "at-fixture"], extra: ["a": 1])
    let mixed = try antigravity.builtCredentials()
    #expect(mixed.type == "oauth" && mixed.extra == ["a": 1, "mixed_scheduling": true])
    var wrongPlatform = try picked("openai", "oauth")
    wrongPlatform.oauthGrant = try anthropicGrant(.oauth)
    #expect(throws: APIError.self) { _ = try wrongPlatform.builtCredentials() }
    let email = AccountNewOAuthGrant(try OAuthTokenInfo.fixture(platform: .openai, fields: ["access_token": "at-fixture", "email": "ops@example.com"]))
    #expect(email.email == "ops@example.com" && email.type == .oauth)
}

@Test func createRequestCarriesSetupFieldsAndProbeDefault() throws {
    var draft = try keyed("anthropic")
    draft.name = " Claude-07 "; draft.notes = "  "; draft.proxyID = 4; draft.loadFactor = 3; draft.expiresAt = 1_893_456_000; draft.groupIDs = [9, 2]
    let request = try draft.createRequest()
    #expect(request.name == "Claude-07" && request.notes == nil && request.platform == "anthropic" && request.type == "apikey")
    #expect(request.proxyID == 4 && request.loadFactor == 3 && request.expiresAt == 1_893_456_000 && request.groupIDs == [9, 2])
    #expect(request.concurrency == 10 && request.priority == 1 && request.rateMultiplier == 1 && request.autoPauseOnExpired == true)
    #expect(request.upstreamBillingProbeEnabled == true && !request.confirmMixedChannelRisk)
    #expect(try draft.createRequest(confirmMixedChannel: true).confirmMixedChannelRisk)
    #expect(try !String(decoding: request.requestBody(), as: UTF8.self).contains("skip_default_group_bind"))
    var bedrock = try picked("anthropic", "bedrock")
    bedrock.bedrockAuth = .apikey; bedrock.bedrockAPIKey = secret
    var vertex = try picked("anthropic", "vertex")
    vertex.vertexFile = try vertexFile()
    var oauth = try picked("openai", "oauth")
    oauth.oauthGrant = AccountNewOAuthGrant(try OAuthTokenInfo.fixture(platform: .openai, fields: ["access_token": "at-fixture", "expires_at": 1]))
    for other in [bedrock, vertex, oauth] { #expect(try other.createRequest().upstreamBillingProbeEnabled == nil) }
    #expect(throws: APIError.self) { _ = try AccountNewDraft().createRequest() }
}

/// f3a3d8684 (2026-07-26) let every API Key platform turn the probe on; the servers from d2585097f before it answer 400
/// UPSTREAM_BILLING_PROBE_ACCOUNT_INVALID for any but OpenAI, and a server without /admin/me may be one of them.
@Test func legacyServerSendsTheProbeOnlyForOpenAIKeys() throws {
    var upstream = try picked("antigravity", "upstream", legacy: true)
    upstream.upstreamBaseURL = "https://upstream.example.invalid"; upstream.upstreamAPIKey = secret
    for draft in [try keyed("anthropic", legacy: true), try keyed("gemini", legacy: true), try keyed("grok", legacy: true),
                  try keyed("cline", "mode.payg", legacy: true), upstream] {
        let request = try draft.createRequest()
        #expect(request.upstreamBillingProbeEnabled == nil, "\(draft)")
        #expect(try !String(decoding: request.requestBody(), as: UTF8.self).contains("upstream_billing_probe_enabled"))
    }
    #expect(try keyed("openai", legacy: true).createRequest().upstreamBillingProbeEnabled == true)
    #expect(try keyed("gemini").createRequest().upstreamBillingProbeEnabled == true)
    let saved = try keyed("anthropic", legacy: true)
    var edited = saved
    edited.apiKey = "sk-new-fixture"
    #expect(try edited.patch(since: saved) == AccountPatchRequest(credentialsPatch: ["api_key": .set("sk-new-fixture")]))
}

@Test func vertexFileRequiresProjectEmailAndKey() throws {
    let file = try vertexFile()
    #expect(file.fileName == "sa.json" && file.projectID == "demo-project" && file.clientEmail == "sa@demo-project.example.invalid" && file.rawText == vertexJSON)
    let missing = #"{"project_id":"demo-project","client_email":"sa@demo-project.example.invalid","private_key":"  "}"#
    let missingError = #expect(throws: APIError.self) { _ = try VertexServiceAccountFile(fileName: "a.json", data: Data(missing.utf8)) }
    #expect(missingError?.localizedDescription == "Service Account JSON 缺少 project_id、client_email 或 private_key")
    let oversized = Data(("{\"x\":\"" + String(repeating: "a", count: VertexServiceAccountFile.maxBytes) + "\"}").utf8)
    for data in [Data("not json".utf8), Data("[1,2]".utf8), oversized, Data([0xFF, 0xFE])] {
        let error = #expect(throws: APIError.self) { _ = try VertexServiceAccountFile(fileName: "b.json", data: data) }
        #expect(error?.localizedDescription == "Service Account JSON 格式无效")
    }
    for text in printed(file) { #expect(!text.contains(privateKey)) }
}

@Test func addressFormatIssues() throws {
    var draft = try keyed("openai", base: "api.example.com")
    let issue = AccountNewIssue(field: .baseURL, anchor: .credentials, message: BaseURLRule.invalidMessage)
    #expect(draft.issues == [issue])
    let error = #expect(throws: APIError.self) { _ = try draft.createRequest() }
    #expect(error?.localizedDescription == BaseURLRule.invalidMessage)
    draft.baseURL = "  "
    #expect(draft.issues.isEmpty)
    var custom = try keyed("kimi", "mode.coding")
    custom.apiProtocol = "anthropic"; custom.usesCustomEndpoint = true; custom.customEndpoint = "ftp://x"
    #expect(custom.issues.map(\.field) == [.customEndpoint])
    custom.apiProtocol = "adaptive"
    #expect(custom.issues.isEmpty)
    var upstream = try picked("antigravity", "upstream")
    upstream.upstreamBaseURL = "upstream.example.invalid"
    #expect(upstream.issues.map(\.field) == [.upstreamBaseURL])
    #expect(try upstream.switchingMethod(to: #require(methods("antigravity").first)).issues.isEmpty)
}

// MARK: - Saving after creation

@Test func patchSinceSavedSendsOnlyChangedFields() throws {
    var saved = try keyed("anthropic", base: "https://relay.example.invalid")
    saved.name = "Claude-01"; saved.groupIDs = [1]; saved.proxyID = 4; saved.expiresAt = 1_893_456_000; saved.loadFactor = 3
    let unchanged = try saved.patch(since: saved)
    #expect(!saved.hasChanges(since: saved) && !unchanged.hasChanges)
    let base = saved
    func edited(_ change: (inout AccountNewDraft) -> Void) -> AccountNewDraft { var draft = base; change(&draft); return draft }
    var toOAuth = saved.switchingMethod(to: try #require(methods("anthropic").first))
    toOAuth.oauthGrant = try anthropicGrant(.oauth, ["expires_at": 1_893_456_000])
    let edits: [(AccountNewDraft, AccountPatchRequest)] = [
        (edited { $0.name = " 新名 " }, AccountPatchRequest(name: "新名")),
        (edited { $0.proxyID = nil }, AccountPatchRequest(proxyID: 0)),
        (edited { $0.expiresAt = nil }, AccountPatchRequest(expiresAt: 0)),
        (edited { $0.loadFactor = nil }, AccountPatchRequest(loadFactor: 0)),
        (edited { $0.notes = "备注" }, AccountPatchRequest(notes: "备注")),
        (edited { $0.groupIDs = [1, 2] }, AccountPatchRequest(groupIDs: [1, 2])),
        (edited { $0.apiKey = "sk-new-fixture" }, AccountPatchRequest(credentialsPatch: ["api_key": .set("sk-new-fixture")])),
        (edited { $0.baseURL = "" }, AccountPatchRequest(credentialsPatch: ["base_url": .set("https://api.anthropic.com")])),
        (toOAuth, AccountPatchRequest(type: "oauth", upstreamBillingProbeEnabled: false,
                                      credentialsPatch: ["access_token": .set("at-fixture"), "expires_at": .set(1_893_456_000), "base_url": .delete,
                                                         "api_key": .set("")]))
    ]
    for (draft, expected) in edits {
        let patch = try draft.patch(since: saved)
        #expect(patch == expected)
        #expect(draft.hasChanges(since: saved))
        try patch.validate()
    }
    var mixed = try picked("antigravity", "upstream").settingMixedScheduling(true, groups: []).draft
    mixed.upstreamBaseURL = "https://upstream.example.invalid"; mixed.upstreamAPIKey = secret
    let off = mixed.settingMixedScheduling(false, groups: []).draft
    #expect(try off.patch(since: mixed) == AccountPatchRequest(extraPatch: ["mixed_scheduling": .delete]))
    let other = try keyed("openai")
    let platformError = #expect(throws: APIError.self) { _ = try other.patch(since: saved) }
    #expect(platformError?.kind == .validation)
    var incomplete = saved
    incomplete.apiKey = ""
    #expect(incomplete.hasChanges(since: saved))
}

/// A secret cannot be deleted (CREDENTIAL_KEY_NOT_DELETABLE), but the server reads "" as unset (GetCredential, has_<key>), so a
/// secret the form no longer holds is blanked rather than left in use.
@Test func patchBlanksSecretsTheFormNoLongerHolds() throws {
    var saved = try picked("anthropic", "bedrock")
    saved.awsAccessKeyID = "AKIAFIXTURE"; saved.awsSecretAccessKey = secret; saved.awsSessionToken = "session-fixture"
    var longTerm = saved
    longTerm.awsAccessKeyID = "AKIALONGTERM"; longTerm.awsSecretAccessKey = "long-term-secret-fixture"; longTerm.awsSessionToken = " "
    let rotated = try longTerm.patch(since: saved)
    #expect(rotated.credentialsPatch == ["aws_access_key_id": .set("AKIALONGTERM"), "aws_secret_access_key": .set("long-term-secret-fixture"),
                                         "aws_session_token": .set("")])
    try rotated.validate()
    var cleared = saved
    cleared.awsSessionToken = ""
    #expect(cleared.hasChanges(since: saved))
    #expect(try cleared.patch(since: saved) == AccountPatchRequest(credentialsPatch: ["aws_session_token": .set("")]))
    var oauth = try picked("anthropic", "oauth")
    oauth.oauthGrant = try anthropicGrant(.oauth, ["refresh_token": "rt-fixture", "expires_at": 1_893_456_000])
    var setup = oauth.switchingClaudeAuthKind(.setupToken)
    setup.oauthGrant = try anthropicGrant(.setupToken, ["access_token": "at-setup-fixture", "expires_at": 1_924_992_000])
    let switched = try setup.patch(since: oauth)
    #expect(switched == AccountPatchRequest(type: "setup-token", credentialsPatch: ["access_token": .set("at-setup-fixture"),
                                                                                   "expires_at": .set(1_924_992_000), "refresh_token": .set("")]))
    try switched.validate()
}

@Test func secretsNeverAppearInDescriptions() throws {
    var draft = try keyed("anthropic")
    draft.awsSecretAccessKey = "aws-secret-fixture"; draft.vertexFile = try vertexFile()
    draft.oauthGrant = AccountNewOAuthGrant(platform: .anthropic, type: .oauth, credentials: ["access_token": "at-secret-fixture"])
    let built = try keyed("anthropic").builtCredentials()
    let frozen = AccountNewFrozenRequest(request: try keyed("anthropic").createRequest(), key: UUID(), submittedAt: Date())
    let texts = printed(draft) + printed(built) + printed(try #require(draft.oauthGrant)) + printed(try #require(draft.vertexFile)) + printed(frozen)
    for text in texts {
        for value in [secret, "aws-secret-fixture", privateKey, "at-secret-fixture"] { #expect(!text.contains(value)) }
    }
    #expect(Mirror(reflecting: draft).children.isEmpty && Mirror(reflecting: built).children.isEmpty)
}
