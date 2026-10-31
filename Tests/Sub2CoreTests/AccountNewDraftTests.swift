import Foundation
import Testing
@testable import Sub2Core

private let catalog = MetaCatalog.builtin

private func methods(_ platform: String) -> [AccountNewMethod] { AccountNewCatalog.methods(for: platform, in: catalog) }
private func method(_ platform: String, _ id: String) throws -> AccountNewMethod { try #require(methods(platform).first { $0.id == id }) }
/// A draft with the platform picked the way the form does it, and optionally a method.
private func picked(_ platform: String, _ methodID: String? = nil, existing: Int = 0) throws -> AccountNewDraft {
    let draft = AccountNewDraft().switchingPlatform(to: platform, methods: methods(platform),
                                                    suggestedName: AccountNewNaming.suggestedName(platform: platform, existingCount: existing))
    guard let methodID else { return draft }
    return draft.switchingMethod(to: try method(platform, methodID))
}
private func labels(_ draft: AccountNewDraft) -> [String] { draft.missing(in: catalog).map(\.label) }
private func group(_ id: Int, _ platform: String, sort: Int? = nil, status: String = "active") -> AdminGroup {
    AdminGroup(id: id, name: "分组 \(id)", platform: platform, status: status, sortOrder: sort)
}
private func grant(_ platform: OAuthPlatform, kind: OAuthAuthKind = .oauth) throws -> AccountNewOAuthGrant {
    AccountNewOAuthGrant(try OAuthTokenInfo.fixture(platform: platform, kind: kind, fields: ["access_token": "at-fixture", "email": "ops@example.com"]))
}

// MARK: - Shelves and method rows

@Test func shelvesFollowCatalogOrderAndPlatformAuth() {
    let sections = AccountNewCatalog.sections(catalog)
    #expect(sections.map(\.shelf) == [.common, .domestic, .more] && sections.map(\.shelf.title) == ["常用", "国内厂商", "更多"])
    #expect(sections.map { $0.platforms.map(\.id) } == [["anthropic", "openai", "gemini", "antigravity", "grok"], ["kimi", "zhipu", "deepseek", "minimax"],
                                                         ["opencode_go", "typesafe", "command_code", "cline"]])
    #expect(sections[1].platforms[1].name == "智谱 GLM" && sections[2].platforms[1].name == "TypeSafe / Jev")
    #expect(sections[0].platforms[0].methodSummary == "OAuth · API Key · Bedrock · Vertex")
    #expect(sections[0].platforms[3].methodSummary == "OAuth · 对接上游" && sections[1].platforms[0].methodSummary == "按量付费 · Coding Plan")
    var auth = catalog.platformAuth
    auth["grok"] = nil
    let vendor = AccountNewCatalog.sections(MetaCatalog(platforms: catalog.platforms, platformAuth: auth))
    #expect(!vendor.flatMap(\.platforms).map(\.id).contains("grok"))
    #expect(AccountNewCatalog.sections(MetaCatalog(platforms: catalog.platforms, platformAuth: [:])).isEmpty)
    #expect(AccountNewCatalog.sections(MetaCatalog(platforms: catalog.platforms, platformAuth: ["openai": ["apikey"]])).map(\.shelf) == [.common])
}

@Test func methodRowsMapPlatformAuth() {
    let anthropic = methods("anthropic")
    #expect(anthropic.map(\.id) == ["oauth", "apikey", "bedrock", "vertex"])
    #expect(anthropic.map(\.title) == ["Claude Code", "Claude Console", "AWS Bedrock", "Vertex"])
    #expect(anthropic.map(\.subtitle) == ["OAuth / Setup Token", "API Key", "SigV4 / API Key", "Service Account"])
    #expect(anthropic.map(\.detail) == ["在浏览器登录 Claude 授权", "粘贴 sk-ant-api03- 开头的 Key", "AWS 访问密钥和 Region", "从“文件”选择 Service Account JSON"])
    #expect(anthropic[0].kind == .oauth(types: [.oauth, .setupToken]) && anthropic.map(\.credentialLabel) == ["授权", "API Key", "AWS 凭据", "JSON 文件"])
    #expect(methods("openai").map(\.title) == ["ChatGPT OAuth", "API Key"] && methods("openai").map(\.subtitle) == ["浏览器授权", "Responses API"])
    #expect(methods("gemini").map(\.title) == ["Google OAuth", "AI Studio", "Vertex"] && methods("gemini")[0].subtitle == "Google One / Code Assist")
    let antigravity = methods("antigravity")
    #expect(antigravity.map(\.title) == ["Antigravity OAuth", "对接上游"] && antigravity[1].kind == .upstream)
    #expect(antigravity[1].credentialLabel == "上游地址和 Key" && antigravity[1].subtitle == "Base URL + API Key")
    #expect(methods("grok").map(\.title) == ["Grok OAuth", "API Key"] && methods("grok")[1].subtitle == "xAI API")
    let kimi = methods("kimi")
    #expect(kimi.map(\.id) == ["mode.payg", "mode.coding"] && kimi.map(\.title) == ["按量付费", "Coding Plan"] && kimi.allSatisfy(\.isAccountMode))
    #expect(kimi.map(\.detail) == ["消耗账户余额，按 Token 计费", "订阅制编程套餐，按 5 小时 / 每周窗口限流"] && kimi.map(\.subtitle) == ["API Key", "API Key"])
    #expect(methods("opencode_go").map(\.title) == ["GO", "Zen"])
    #expect(methods("typesafe").map(\.title) == ["API Key"] && methods("typesafe")[0].subtitle == "Anthropic 协议" && methods("typesafe")[0].kind == .apiKey)
    let narrowed = MetaCatalog(platforms: catalog.platforms, platformAuth: ["anthropic": ["setup-token", "apikey", "upstream"]])
    let narrow = AccountNewCatalog.methods(for: "anthropic", in: narrowed)
    #expect(narrow.map(\.id) == ["oauth", "apikey"] && narrow[0].kind == .oauth(types: [.setupToken]))
    #expect(AccountNewCatalog.methods(for: "nowhere", in: catalog).isEmpty)
}

@Test func protocolOptionsAndOfficialEndpoints() throws {
    let payg = try method("kimi", "mode.payg")
    #expect(payg.protocolOptions == ["adaptive", "chat_completions", "anthropic", "responses"] && payg.defaultProtocol == "adaptive")
    #expect(payg.officialEndpoint(for: "anthropic") == "https://api.moonshot.cn/anthropic" && payg.officialEndpoint(for: "adaptive") == nil)
    let zhipu = try method("zhipu", "mode.coding")
    #expect(zhipu.protocolOptions == ["adaptive", "chat_completions", "anthropic"])
    let cline = try method("cline", "mode.payg")
    #expect(cline.protocolOptions == ["chat_completions"] && cline.defaultProtocol == "chat_completions")
    let plain = try method("openai", "apikey")
    #expect(plain.protocolOptions.isEmpty && plain.defaultProtocol == nil && plain.officialEndpoint(for: "anthropic") == nil)
    let official = ["openai": "https://api.openai.com", "gemini": "https://generativelanguage.googleapis.com", "grok": "https://api.x.ai/v1",
                    "typesafe": "https://api.typesafe.ai", "anthropic": "https://api.anthropic.com", "kimi": "https://api.anthropic.com"]
    for (platform, url) in official { #expect(AccountNewCatalog.officialBaseURL(for: platform) == url) }
    let gemini = ["": true, "  ": true, "https://generativelanguage.googleapis.com": true, "https://GENERATIVELANGUAGE.googleapis.com/": true,
                  "https://generativelanguage.googleapis.com/v1beta": false, "http://generativelanguage.googleapis.com": false,
                  "https://generativelanguage.googleapis.com:8443": false, "https://proxy.example.com": false,
                  "https://generativelanguage.googleapis.com?x=1": false, "generativelanguage.googleapis.com": false]
    for (url, expected) in gemini { #expect(AccountNewCatalog.isOfficialGeminiBaseURL(url) == expected, "\(url)") }
}

// MARK: - Missing list

@Test func missingListFollowsSpecOrder() throws {
    #expect(AccountNewDraft().missing(in: catalog) == [AccountNewMissing(label: "平台", anchor: .platform),
                                                         AccountNewMissing(label: "凭据", anchor: .credentials), AccountNewMissing(label: "名称", anchor: .name)])
    let anthropic = try picked("anthropic")
    #expect(anthropic.name == "Claude-01" && labels(anthropic) == ["认证方式", "凭据"])
    #expect(try labels(picked("kimi")) == ["账号类型", "凭据"])
    #expect(try picked("typesafe").missing(in: catalog) == [AccountNewMissing(label: "API Key", anchor: .credentials)])
    #expect(try picked("anthropic", "oauth").missing(in: catalog) == [AccountNewMissing(label: "授权", anchor: .oauth)])
    #expect(try picked("gemini", "oauth").missing(in: catalog) == [AccountNewMissing(label: "授权", anchor: .oauth)])
    #expect(try picked("openai", "oauth").missing(in: catalog) == [AccountNewMissing(label: "授权", anchor: .credentials)])
    #expect(try labels(picked("openai", "apikey")) == ["API Key"])
    var coding = try picked("kimi", "mode.coding")
    coding.apiProtocol = "anthropic"; coding.usesCustomEndpoint = true
    #expect(labels(coding) == ["API Key"])
    coding.apiKey = "sk-fixture"
    #expect(labels(coding) == ["自定义端点"])
    coding.apiProtocol = "adaptive"
    #expect(labels(coding).isEmpty)
    var sigv4 = try picked("anthropic", "bedrock")
    sigv4.awsAccessKeyID = "AKIAFIXTURE"
    #expect(labels(sigv4) == ["AWS 凭据"])
    sigv4.bedrockAuth = .apikey
    #expect(labels(sigv4) == ["AWS 凭据"])
    #expect(try labels(picked("gemini", "vertex")) == ["JSON 文件"])
    var upstream = try picked("antigravity", "upstream")
    upstream.upstreamBaseURL = "https://upstream.example.invalid"
    #expect(labels(upstream) == ["上游地址和 Key"])
    upstream.upstreamAPIKey = "ag-fixture"
    #expect(labels(upstream).isEmpty)
    upstream.name = "  "
    #expect(upstream.missing(in: catalog) == [AccountNewMissing(label: "名称", anchor: .name)])
    for text in ["", "-1", "abc", "1e3", "1,5"] {
        upstream.rateMultiplierText = text
        #expect(labels(upstream) == ["名称", "计费倍率"], "\(text)")
    }
    upstream.name = "Ag-01"
    for text in ["0", " 0.5 ", "12"] {
        upstream.rateMultiplierText = text
        #expect(labels(upstream).isEmpty, "\(text)")
    }
}

// MARK: - Names, defaults, groups

@Test func autoNameUsesShortNameAndNextNumber() throws {
    #expect(AccountNewNaming.suggestedName(platform: "anthropic", existingCount: 2) == "Claude-03")
    #expect(AccountNewNaming.suggestedName(platform: "zhipu", existingCount: 0) == "GLM-01")
    #expect(AccountNewNaming.suggestedName(platform: "openai", existingCount: 9) == "OpenAI-10")
    #expect(AccountNewNaming.suggestedName(platform: "grok", existingCount: 99) == "Grok-100")
    #expect(AccountNewNaming.suggestedName(platform: "anthropic", existingCount: 2, takenNames: ["Claude-03", "Claude-04"]) == "Claude-05")
    let loaded = [UpstreamAccount(id: 1, name: "a", platform: "anthropic", type: "oauth"), UpstreamAccount(id: 2, name: "b", platform: "anthropic", type: "apikey"),
                  UpstreamAccount(id: 3, name: "c", platform: "openai", type: "apikey")]
    let summary = AccountStatusSummary(platforms: [AccountStatusPlatformSummary(platform: "anthropic", counts: AccountStateCounts(total: 7))])
    #expect(AccountNewNaming.existingCount(platform: "anthropic", summary: summary, loadedAccounts: loaded) == 7)
    #expect(AccountNewNaming.existingCount(platform: "gemini", summary: summary, loadedAccounts: loaded) == 0)
    #expect(AccountNewNaming.existingCount(platform: "anthropic", summary: nil, loadedAccounts: loaded) == 2)
    #expect(AccountNewNaming.existingCount(platform: "anthropic", summary: AccountStatusSummary(), loadedAccounts: loaded) == 2)
    var draft = try picked("anthropic", existing: 2)
    #expect(draft.name == "Claude-03" && draft.isNameAutomatic)
    draft.suggestName("Claude-04")
    #expect(draft.name == "Claude-04")
    draft.name = "主力 Claude"
    draft.suggestName("Claude-05")
    #expect(draft.name == "主力 Claude" && !draft.isNameAutomatic)
    #expect(draft.switchingPlatform(to: "openai", methods: methods("openai"), suggestedName: "OpenAI-01").name == "主力 Claude")
    draft.name = ""
    let switched = draft.switchingPlatform(to: "openai", methods: methods("openai"), suggestedName: "OpenAI-01")
    #expect(switched.name == "OpenAI-01" && switched.isNameAutomatic)
}

@Test func defaultsAndRangesAreEnforced() throws {
    let blank = AccountNewDraft()
    #expect(blank.concurrency == 10 && blank.priority == 1 && blank.rateMultiplierText == "1" && blank.loadFactor == nil && blank.autoPauseOnExpired)
    #expect(blank.awsRegion == "us-east-1" && blank.vertexLocation == "global" && blank.bedrockAuth == .sigv4)
    #expect(blank.claudeAuthKind == .oauth && blank.geminiOAuthType == .googleOne && blank.platform == nil && blank.method == nil)
    #expect(AccountNewDefaults.geminiOAuthTypes == [.googleOne, .codeAssist])
    #expect([GeminiOAuthType.googleOne, .codeAssist, .aiStudio].map(\.defaultTierID) == ["google_one_free", "gcp_standard", "aistudio_free"])
    var draft = try picked("openai", "apikey")
    draft.apiKey = "sk-fixture"
    let rejected: [(WritableKeyPath<AccountNewDraft, Int>, Int, String)] = [
        (\.concurrency, 0, "并发数为 1–100 的整数"), (\.concurrency, 101, "并发数为 1–100 的整数"),
        (\.priority, 0, "优先级为 1–99 的整数"), (\.priority, 100, "优先级为 1–99 的整数")
    ]
    for (path, value, message) in rejected {
        var bad = draft
        bad[keyPath: path] = value
        let error = #expect(throws: APIError.self) { _ = try bad.createRequest() }
        #expect(error?.localizedDescription == message)
    }
    for value in [0, 11] {
        var bad = draft
        bad.loadFactor = value
        let error = #expect(throws: APIError.self) { _ = try bad.createRequest() }
        #expect(error?.localizedDescription == "负载因子为 1–10 的整数，可以不填")
    }
    var noRate = draft
    noRate.rateMultiplierText = "-1"
    let rateError = #expect(throws: APIError.self) { _ = try noRate.createRequest() }
    #expect(rateError?.localizedDescription == "请填写账号计费倍率（0 表示不计费）")
    for (concurrency, priority, load) in [(1, 1, Int?.some(1)), (100, 99, 10), (50, 50, nil)] {
        var good = draft
        good.concurrency = concurrency; good.priority = priority; good.loadFactor = load
        _ = try good.createRequest()
    }
    let rates: [(String, Decimal?)] = [("1", 1), ("0", 0), (" 0.5 ", Decimal(string: "0.5")), ("1,5", nil), ("", nil), ("1.", nil)]
    for (text, value) in rates {
        draft.rateMultiplierText = text
        #expect(draft.rateMultiplier == value, "\(text)")
    }
}

@Test func groupFilterKeepsOwnPlatformAndComposite() throws {
    let groups = [group(1, "anthropic", sort: 2), group(2, "composite", sort: 1), group(3, "openai"), group(4, "antigravity", sort: 3),
                  group(5, "gemini", sort: 4), group(6, "anthropic", status: "inactive")]
    #expect(AccountNewGroups.eligible(groups, platform: "anthropic", mixedScheduling: false).map(\.id) == [2, 1])
    #expect(AccountNewGroups.eligible(groups, platform: "antigravity", mixedScheduling: false).map(\.id) == [2, 4])
    #expect(AccountNewGroups.eligible(groups, platform: "antigravity", mixedScheduling: true).map(\.id) == [2, 1, 4, 5])
    #expect(AccountNewGroups.eligible(groups, platform: "anthropic", mixedScheduling: true).map(\.id) == [2, 1])
    #expect(AccountNewGroups.allowedPlatforms(for: "antigravity", mixedScheduling: true) == ["antigravity", "composite", "anthropic", "gemini"])
    #expect(AccountNewGroups.inapplicable([1, 4, 5, 999], groups: groups, platform: "antigravity", mixedScheduling: false) == [1, 5])
    var draft = try picked("antigravity", "upstream")
    draft = draft.settingMixedScheduling(true, groups: groups).draft
    draft.groupIDs = [1, 4, 5, 999]
    let opened = draft.settingMixedScheduling(true, groups: groups)
    #expect(opened.removedGroupIDs.isEmpty && opened.draft.groupIDs == [1, 4, 5, 999] && opened.draft.mixedScheduling)
    let closed = draft.settingMixedScheduling(false, groups: groups)
    #expect(closed.removedGroupIDs == [1, 5] && closed.draft.groupIDs == [4, 999] && !closed.draft.mixedScheduling)
}

// MARK: - Switching and confirmations

@Test func switchingPlatformClearsCredentialsButKeepsSetup() throws {
    var draft = try picked("anthropic", "apikey")
    draft.apiKey = "sk-ant-api03-fixture"; draft.baseURL = "https://relay.example.invalid"; draft.groupIDs = [1]; draft.proxyID = 4
    draft.concurrency = 20; draft.priority = 5; draft.rateMultiplierText = "1.5"; draft.expiresAt = 1_893_456_000; draft.autoPauseOnExpired = false
    draft.loadFactor = 3; draft.notes = "备注"; draft.awsSecretAccessKey = "aws-fixture"; draft.allowOverages = true; draft.customEndpoint = "x"
    let openai = draft.switchingPlatform(to: "openai", methods: methods("openai"), suggestedName: "OpenAI-02")
    #expect(openai.platform == "openai" && openai.method == nil && openai.name == "OpenAI-02")
    #expect(openai.apiKey.isEmpty && openai.baseURL.isEmpty && openai.oauthGrant == nil && openai.awsSecretAccessKey.isEmpty && openai.groupIDs.isEmpty)
    #expect(!openai.allowOverages && !openai.mixedScheduling && openai.customEndpoint.isEmpty && openai.apiProtocol == nil)
    #expect(openai.proxyID == 4 && openai.concurrency == 20 && openai.priority == 5 && openai.rateMultiplierText == "1.5" && openai.loadFactor == 3)
    #expect(openai.expiresAt == 1_893_456_000 && !openai.autoPauseOnExpired && openai.notes == "备注")
    #expect(draft.switchingPlatform(to: "anthropic", methods: methods("anthropic"), suggestedName: "Claude-09") == draft)
    let typesafe = draft.switchingPlatform(to: "typesafe", methods: methods("typesafe"), suggestedName: "TypeSafe-01")
    #expect(typesafe.method?.id == "apikey")
    #expect(try picked("anthropic").platformSwitchConfirmation(toPlatformName: "OpenAI") == nil)
    var keyOnly = try picked("anthropic", "apikey")
    keyOnly.apiKey = "sk-ant-api03-fixture"
    #expect(keyOnly.platformSwitchConfirmation(toPlatformName: "OpenAI")
            == AccountNewConfirmation(title: "换成 OpenAI？", message: "已填写的凭据会清空，名称、调度和代理保留。", confirmTitle: "更换平台", cancelTitle: "取消"))
    var authorized = try picked("anthropic", "oauth")
    authorized.oauthGrant = try grant(.anthropic)
    authorized.groupIDs = [1]
    #expect(authorized.platformSwitchConfirmation(toPlatformName: "OpenAI")?.message == "已填写的授权和选好的分组会清空，名称、调度和代理保留。")
    #expect(try picked("openai", "oauth").platformSwitchConfirmation(toPlatformName: "Grok", oauthInProgress: true)?.message
            == "已填写的授权会清空，名称、调度和代理保留。")
}

@Test func methodAndAuthKindSwitchConfirmations() throws {
    var draft = try picked("anthropic", "apikey")
    draft.apiKey = "sk-ant-api03-fixture"; draft.groupIDs = [3]
    let oauth = try method("anthropic", "oauth")
    let switched = draft.switchingMethod(to: oauth)
    #expect(switched.method?.id == "oauth" && switched.apiKey.isEmpty && switched.groupIDs == [3] && switched.name == draft.name)
    #expect(try draft.switchingMethod(to: method("anthropic", "apikey")) == draft)
    let setupCatalog = MetaCatalog(platforms: catalog.platforms, platformAuth: ["anthropic": ["setup-token"]])
    let setupOnly = AccountNewCatalog.methods(for: "anthropic", in: setupCatalog).first { $0.id == "oauth" }
    #expect(try draft.switchingMethod(to: #require(setupOnly)).claudeAuthKind == .setupToken)
    #expect(draft.methodSwitchConfirmation(to: oauth, createdAccountID: 21)
            == AccountNewConfirmation(title: "改成「Claude Code」？", message: "账号 #21 已创建。换认证方式后要重新授权，保存时替换原来的凭据。",
                                      confirmTitle: "更换", cancelTitle: "取消"))
    let kimi = try picked("kimi", "mode.payg")
    #expect(try kimi.methodSwitchConfirmation(to: method("kimi", "mode.coding"), createdAccountID: 21)?.message
            == "账号 #21 已创建。换账号类型后要重新填写凭据，保存时替换原来的凭据。")
    #expect(draft.methodSwitchConfirmation(to: oauth, createdAccountID: nil)?.message == "换认证方式会清空已填写的凭据。")
    #expect(try picked("anthropic", "apikey").methodSwitchConfirmation(to: oauth, createdAccountID: nil) == nil)
    #expect(try draft.methodSwitchConfirmation(to: method("anthropic", "apikey"), createdAccountID: 21) == nil)
    var authorized = try picked("anthropic", "oauth")
    #expect(authorized.authKindSwitchConfirmation(toTitle: "Setup Token") == nil)
    authorized.oauthGrant = try grant(.anthropic)
    #expect(authorized.authKindSwitchConfirmation(toTitle: OAuthAuthKind.setupToken.title)
            == AccountNewConfirmation(title: "切换到 Setup Token？", message: "切换会丢弃当前授权，需要重新在浏览器里授权。", confirmTitle: "切换", cancelTitle: "取消"))
    #expect(try picked("gemini", "oauth").authKindSwitchConfirmation(toTitle: "Code Assist", oauthInProgress: true)?.title == "切换到 Code Assist？")
    let kind = authorized.switchingClaudeAuthKind(.setupToken)
    #expect(kind.claudeAuthKind == .setupToken && kind.oauthGrant == nil)
    let gemini = try picked("gemini", "oauth").switchingGeminiOAuthType(.codeAssist)
    #expect(gemini.geminiOAuthType == .codeAssist && gemini.geminiTierID == "gcp_standard")
    #expect(AccountNewDraft().discardConfirmation() == nil)
    #expect(authorized.discardConfirmation()
            == AccountNewConfirmation(title: "放弃新建账号？", message: "已填写的内容和授权结果不会保存。", confirmTitle: "放弃", cancelTitle: "继续填写"))
    #expect(draft.discardConfirmation()?.message == "已填写的内容不会保存。")
}
