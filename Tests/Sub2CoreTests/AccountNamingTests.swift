import Foundation
import Testing
@testable import Sub2Core

private let namedVendor = MetaCatalog(platforms: [.init(id: "newvendor", displayName: "New Vendor")], platformAuth: [:])
private let unnamedVendor = MetaCatalog(platforms: [.init(id: "newvendor", displayName: "")], platformAuth: [:])

@Test func accountNamingPlatformNames() {
    let rows: [(platform: String, catalog: MetaCatalog?, expected: String)] = [
        ("anthropic", nil, "Anthropic"), ("anthropic", .builtin, "Anthropic"),
        // S2D1-12: the catalog says “Zhipu GLM”; a platform the app knows keeps its Chinese title.
        ("zhipu", .builtin, "智谱 GLM"), ("zhipu", nil, "智谱 GLM"),
        ("composite", .builtin, "组合分组"), ("opencode_go", .builtin, "OpenCode"), ("typesafe", .builtin, "TypeSafe / Jev"),
        ("newvendor", namedVendor, "New Vendor"), ("newvendor", nil, "newvendor"), ("newvendor", unnamedVendor, "newvendor"),
        ("", nil, "—"), ("", .builtin, "—")
    ]
    for row in rows {
        #expect(AccountNaming.platformName(row.platform, catalog: row.catalog) == row.expected, "\(row.platform)")
    }
}

@Test func accountNamingTypeNames() {
    let rows: [(platform: String, type: String, expected: String)] = [
        ("anthropic", "oauth", "OAuth"), ("openai", "setup-token", "Setup Token"), ("anthropic", "apikey", "API Key"),
        ("antigravity", "apikey", "对接上游"), ("antigravity", "oauth", "OAuth"), ("anthropic", "upstream", "对接上游"),
        ("anthropic", "bedrock", "AWS Bedrock"), ("gemini", "service_account", "Vertex"), ("kimi", "apikey", "API Key"),
        ("openai", "weird", "weird"), ("openai", "", "—"), ("antigravity", "", "—")
    ]
    for row in rows {
        #expect(AccountNaming.typeName(platform: row.platform, type: row.type) == row.expected, "\(row.platform) \(row.type)")
    }
}

@Test func accountNamingShortNames() {
    let ids = ["anthropic", "openai", "gemini", "antigravity", "grok", "kimi", "zhipu", "deepseek", "minimax", "opencode_go", "typesafe",
               "command_code", "cline"]
    #expect(ids.map(AccountNaming.shortName) == ["Claude", "OpenAI", "Gemini", "Antigravity", "Grok", "Kimi", "GLM", "DeepSeek", "MiniMax",
                                                  "OpenCode", "TypeSafe", "CommandCode", "Cline"])
    #expect(AccountNaming.shortName("newvendor") == "newvendor")
    // Every builtin platform has a short name of its own, so one added later is not silently named by its id.
    let builtinIDs = MetaCatalog.builtin.platforms.map(\.id)
    #expect(builtinIDs == ids)
    #expect(builtinIDs.allSatisfy { AccountNaming.shortName($0) != $0 })
}
