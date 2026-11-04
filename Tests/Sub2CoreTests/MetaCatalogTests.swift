import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let catalogOwner = ConditionalCache.Identity(userID: 1, authMethod: "admin_api_key")
private let catalogJSON = #"""
{"platform_catalog":{"platforms":[
  {"id":"anthropic","display_name":"Anthropic","gateway":"anthropic","cn_provider":false,"litellm_provider":"anthropic"},
  {"id":"kimi","display_name":"Kimi","gateway":"openai","cn_provider":true,"multi_protocol":{"default_mode":"payg","routing":"by_inbound","modes":[
    {"mode":"payg","base_urls":{"anthropic":"https://kimi.example.invalid/anthropic","chat_completions":"https://kimi.example.invalid/v1"}},
    {"mode":"coding","base_urls":{"anthropic":"https://kimi.example.invalid/coding"}}]}},
  {"id":"opencode_go","display_name":"OpenCode","cn_provider":false,"multi_protocol":{"default_mode":"go","routing":"by_model","model_catalog":true,"modes":[
    {"mode":"go","base_urls":{"responses":"https://opencode.example.invalid/v1"},"protocol_rules":[
      {"pattern":"gpt-*","protocol":"responses","protocols":["responses","chat_completions"]},{"pattern":"qwen*","protocol":"anthropic"}]}]}}
 ],"composite_precedence":["anthropic","kimi","opencode_go"]},
 "account_types":["oauth","setup-token","apikey"],
 "platform_auth":{"anthropic":["oauth","setup-token","apikey"],"kimi":["apikey"]},
 "account_status_filters":["active"],"request_types":["sync"],"error_phases":["request"],"user_roles":["admin"],"api_protocols":["adaptive"]}
"""#

private func decodeCatalog(_ json: String) throws -> MetaCatalog { try JSONDecoder().decode(MetaCatalog.self, from: Data(json.utf8)) }
private func catalogClient(_ transport: ScriptedTransport, identity: ConditionalCache.Identity? = nil) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate, cacheIdentity: identity)
}

@Test func metaCatalogDecodesPlatformsAuthAndMultiProtocol() throws {
    let catalog = try decodeCatalog(catalogJSON)
    #expect(catalog.platforms.map(\.id) == ["anthropic", "kimi", "opencode_go"])
    #expect(catalog.platforms.map(\.displayName) == ["Anthropic", "Kimi", "OpenCode"])
    #expect(catalog.platforms.map(\.cnProvider) == [false, true, false])
    #expect(catalog.platform("anthropic")?.multiProtocol == nil)
    let kimi = try #require(catalog.platform("kimi")?.multiProtocol)
    #expect(kimi.defaultMode == "payg" && kimi.modes.map(\.mode) == ["payg", "coding"])
    #expect(kimi.modes[0].baseURLs == ["anthropic": "https://kimi.example.invalid/anthropic", "chat_completions": "https://kimi.example.invalid/v1"])
    #expect(kimi.modes[0].protocolRules.isEmpty)
    let rules = try #require(catalog.platform("opencode_go")?.multiProtocol?.modes.first?.protocolRules)
    #expect(rules == [.init(pattern: "gpt-*", preferredProtocol: "responses", supportedProtocols: ["responses", "chat_completions"]),
                      .init(pattern: "qwen*", preferredProtocol: "anthropic")])
    #expect(rules[1].supportedProtocols == ["anthropic"])
    #expect(catalog.authTypes(for: "anthropic") == ["oauth", "setup-token", "apikey"] && catalog.authTypes(for: "kimi") == ["apikey"])
    #expect(catalog.platformAuth.count == 2)
}

@Test func metaCatalogToleratesMissingSectionsAndBadEntries() throws {
    let noAuth = try decodeCatalog(#"{"platform_catalog":{"platforms":[{"id":"anthropic","display_name":"Anthropic"}]}}"#)
    #expect(noAuth.platforms.map(\.id) == ["anthropic"] && noAuth.platformAuth == MetaCatalog.builtin.platformAuth)
    // A vendor without account management gets {}: it may create nothing, which is not “missing”.
    let emptyAuth = try decodeCatalog(#"{"platform_catalog":{"platforms":[{"id":"anthropic","display_name":"Anthropic"}]},"platform_auth":{}}"#)
    #expect(emptyAuth.platformAuth.isEmpty && emptyAuth.authTypes(for: "anthropic").isEmpty)
    for json in [#"{"platform_auth":{"kimi":["apikey"]}}"#, #"{"platform_catalog":{"platforms":[]},"platform_auth":{"kimi":["apikey"]}}"#,
                 #"{"platform_catalog":null,"platform_auth":{"kimi":["apikey"]}}"#] {
        let catalog = try decodeCatalog(json)
        #expect(catalog.platforms == MetaCatalog.builtin.platforms && catalog.platformAuth == ["kimi": ["apikey"]], "\(json)")
    }
    let lenient = try decodeCatalog(#"""
    {"platform_catalog":{"platforms":[{"display_name":"无编号"},{"id":"zhipu","cn_provider":true},{"id":"kimi","display_name":"Kimi","multi_protocol":"payg"},
      {"id":"minimax","display_name":"MiniMax","multi_protocol":{"default_mode":"payg","modes":[]}},{"id":"newvendor","display_name":"New Vendor"}]},
     "platform_auth":{"kimi":["apikey"],"retired":["apikey"]}}
    """#)
    #expect(lenient.platforms.map(\.id) == ["zhipu", "kimi", "minimax", "newvendor"])
    #expect(lenient.platform("zhipu")?.displayName == "智谱 GLM" && lenient.platform("zhipu")?.cnProvider == true)
    #expect(lenient.platform("kimi")?.multiProtocol == nil && lenient.platform("minimax")?.multiProtocol == nil)
    #expect(lenient.platform("newvendor")?.displayName == "New Vendor")
    #expect(lenient.authTypes(for: "retired") == ["apikey"])
}

@Test func metaCatalogRevalidatesThroughConditionalCache() async throws {
    let transport = ScriptedTransport { request in
        sentHeader(request, "If-None-Match") == "\"m1\"" ? HTTPResponse(statusCode: 304, headers: ["etag": "\"m1\""], data: Data())
            : okReply(catalogJSON, headers: ["etag": "\"m1\""])
    }
    let client = catalogClient(transport, identity: catalogOwner)
    let first = try await client.metaCatalog()
    let second = try await client.metaCatalog()
    #expect(first == second && second.platforms.count == 3)
    let sent = await transport.requests
    #expect(sent.map(\.httpMethod) == ["GET", "GET"] && sent.allSatisfy { $0.url?.path == "/api/v1/admin/meta/catalog" })
    #expect(sent.map { sentHeader($0, "If-None-Match") } == [nil, "\"m1\""])
}

@Test func metaCatalogFallsBackToBuiltinOnlyForMissingEndpointAndCompliance() async throws {
    let missing = HTTPResponse(statusCode: 404, headers: ["content-type": "text/plain"], data: Data("404 page not found".utf8))
    let compliance = errorReply(423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED")
    for reply in [missing, compliance] {
        let catalog = try await catalogClient(ScriptedTransport { _ in reply }).metaCatalog()
        #expect(catalog == .builtin)
    }
    for reply in [errorReply(404, reason: "RESOURCE_NOT_FOUND"), errorReply(403, reason: "FORBIDDEN"), errorReply(500)] {
        let client = catalogClient(ScriptedTransport { _ in reply })
        let error = try #require(await thrownAPIError { _ = try await client.metaCatalog() })
        #expect(error.statusCode == reply.statusCode)
        #expect(!MetaCatalog.fallsBackToBuiltin(after: error))
    }
    #expect(MetaCatalog.fallsBackToBuiltin(after: APIError.from(missing)))
    #expect(MetaCatalog.fallsBackToBuiltin(after: APIError.from(compliance)))
}

@Test func builtinCatalogMatchesSub2BuiltinJSON() throws {
    let builtin = MetaCatalog.builtin
    let ids = ["anthropic", "openai", "gemini", "antigravity", "grok", "kimi", "zhipu", "deepseek", "minimax", "opencode_go", "typesafe",
               "command_code", "cline"]
    #expect(builtin.platforms.map(\.id) == ids)
    #expect(builtin.platforms.map(\.displayName) == ["Anthropic", "OpenAI", "Gemini", "Antigravity", "Grok", "Kimi", "Zhipu GLM", "DeepSeek",
                                                     "MiniMax", "OpenCode", "TypeSafe / Jev", "Command Code", "Cline"])
    #expect(builtin.platforms.filter(\.cnProvider).map(\.id) == ["kimi", "zhipu", "deepseek", "minimax"])
    #expect(builtin.platforms.filter { $0.multiProtocol != nil }.map(\.id) == ["kimi", "zhipu", "deepseek", "minimax", "opencode_go", "command_code", "cline"])
    func modes(_ id: String) -> [String] { builtin.platform(id)?.multiProtocol?.modes.map(\.mode) ?? [] }
    #expect(modes("kimi") == ["payg", "coding"] && modes("zhipu") == ["payg", "coding"] && modes("deepseek") == ["payg"])
    #expect(modes("minimax") == ["payg", "coding"] && modes("opencode_go") == ["go", "zen"] && modes("command_code") == ["payg"] && modes("cline") == ["payg"])
    #expect(builtin.platforms.compactMap(\.multiProtocol).map(\.defaultMode) == ["payg", "payg", "payg", "payg", "go", "payg", "payg"])
    func protocols(_ id: String, _ mode: String) -> Set<String> {
        Set(builtin.platform(id)?.multiProtocol?.modes.first { $0.mode == mode }?.baseURLs.keys.map { $0 } ?? [])
    }
    let threeProtocols: Set<String> = ["anthropic", "chat_completions", "responses"]
    #expect(protocols("kimi", "coding") == threeProtocols && protocols("deepseek", "payg") == threeProtocols)
    #expect(protocols("zhipu", "payg") == ["anthropic", "chat_completions"] && protocols("zhipu", "coding") == ["anthropic", "chat_completions"])
    #expect(protocols("cline", "payg") == ["chat_completions"] && protocols("opencode_go", "zen") == threeProtocols)
    let openCode = try #require(builtin.platform("opencode_go")?.multiProtocol)
    #expect(openCode.modes.map(\.protocolRules.count) == [5, 6])
    #expect(openCode.modes.last?.protocolRules.dropFirst(4).first == .init(pattern: "qwen3.8-max", preferredProtocol: "chat_completions"))
    let commandRules = try #require(builtin.platform("command_code")?.multiProtocol?.modes.first?.protocolRules)
    #expect(commandRules == [.init(pattern: "claude-*", preferredProtocol: "anthropic"),
                             .init(pattern: "gpt-*", preferredProtocol: "responses", supportedProtocols: ["responses", "chat_completions"])])
    #expect(builtin.platforms.compactMap(\.multiProtocol).flatMap(\.modes).allSatisfy { $0.baseURLs.values.allSatisfy { $0.hasPrefix("https://") } })
    #expect(Set(builtin.platformAuth.keys) == Set(ids))
    #expect(builtin.authTypes(for: "anthropic") == ["oauth", "setup-token", "apikey", "bedrock", "service_account"])
    #expect(builtin.authTypes(for: "openai") == ["oauth", "apikey"] && builtin.authTypes(for: "gemini") == ["oauth", "apikey", "service_account"])
    #expect(builtin.authTypes(for: "antigravity") == ["oauth", "apikey"] && builtin.authTypes(for: "grok") == ["oauth", "apikey"])
    #expect(ids.dropFirst(5).allSatisfy { builtin.authTypes(for: $0) == ["apikey"] })
}

@Test func metaCatalogModeLookupFallsBackToDefault() throws {
    let kimi = try #require(MetaCatalog.builtin.platform("kimi")?.multiProtocol)
    #expect(kimi.mode("coding")?.mode == "coding" && kimi.mode(" coding ")?.mode == "coding")
    #expect(kimi.mode("nope")?.mode == "payg" && kimi.mode(nil)?.mode == "payg")
    let stray = MetaCatalog.MultiProtocol(defaultMode: "gone", modes: [.init(mode: "go", baseURLs: [:]), .init(mode: "zen", baseURLs: [:])])
    #expect(stray.mode(nil)?.mode == "go" && stray.mode("zen")?.mode == "zen")
    #expect(MetaCatalog.MultiProtocol(defaultMode: "payg", modes: []).mode("payg") == nil)
    #expect(MetaCatalog.builtin.platform("x") == nil && MetaCatalog.builtin.authTypes(for: "x").isEmpty)
}
