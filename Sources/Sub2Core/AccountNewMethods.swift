import Foundation

/// The three shelves of the new-account platform picker (20 §7.3).
public enum AccountNewShelf: String, CaseIterable, Sendable, Identifiable {
    case common, domestic, more
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .common: "常用"
        case .domestic: "国内厂商"
        case .more: "更多"
        }
    }
}

/// One platform row: AccountNaming's name and the design's anTypeSummary (“OAuth · API Key · Bedrock · Vertex”).
public struct AccountNewPlatformChoice: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let methodSummary: String
}

public struct AccountNewShelfSection: Sendable, Equatable, Identifiable {
    public let shelf: AccountNewShelf
    public let platforms: [AccountNewPlatformChoice]
    public var id: String { shelf.rawValue }
}

/// One “认证方式 / 账号类型” row (20 §7.3, design anTypes): what the admin picks and which credentials it needs.
public struct AccountNewMethod: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// Browser authorization; Claude offers OAuth and Setup Token (those platform_auth allows, in that order).
        case oauth(types: [OAuthAuthKind])
        case apiKey
        /// One mode of a multi-protocol API Key platform.
        case multiProtocol(MetaCatalog.Mode)
        case bedrock, vertex
        /// Antigravity's 对接上游, created as an apikey account.
        case upstream
    }
    /// oauth, apikey, bedrock, vertex, upstream, or mode.<mode>.
    public let id: String
    public let kind: Kind
    public let title: String
    public let subtitle: String
    /// The design's `need` line.
    public let detail: String

    /// The 还差 item while its credentials are not complete.
    public var credentialLabel: String {
        switch kind {
        case .oauth: "授权"
        case .apiKey, .multiProtocol: "API Key"
        case .bedrock: "AWS 凭据"
        case .vertex: "JSON 文件"
        case .upstream: "上游地址和 Key"
        }
    }
    /// A multi-protocol mode: the row is a 账号类型 rather than a 认证方式.
    public var isAccountMode: Bool { if case .multiProtocol = kind { true } else { false } }
    /// The mode's native protocols, after 自适应 when there are two or more (S2D1-23, design anProtocols); [] for other methods.
    public var protocolOptions: [String] {
        guard case .multiProtocol(let mode) = kind else { return [] }
        return AccountProtocolEndpoints.protocolOptions(baseURLs: mode.baseURLs, adaptiveWhenSingle: false)
    }
    public var defaultProtocol: String? { protocolOptions.first }
    /// The catalog's endpoint for a native protocol of this mode.
    public func officialEndpoint(for apiProtocol: String) -> String? {
        guard case .multiProtocol(let mode) = kind, let url = mode.baseURLs[apiProtocol]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty else { return nil }
        return url
    }
}

/// The platform picker and method rows from `meta/catalog` (20 §7.2–§7.3): only what platform_auth lets this identity create.
public enum AccountNewCatalog {
    public static let commonPlatformIDs = ["anthropic", "openai", "gemini", "antigravity", "grok"]

    /// Catalog order within each shelf; a platform without a method and an empty shelf are left out.
    public static func sections(_ catalog: MetaCatalog) -> [AccountNewShelfSection] {
        var shelves = [AccountNewShelf: [AccountNewPlatformChoice]]()
        for platform in catalog.platforms {
            let rows = methods(for: platform.id, in: catalog)
            guard !rows.isEmpty else { continue }
            let shelf: AccountNewShelf = commonPlatformIDs.contains(platform.id) ? .common : platform.cnProvider ? .domestic : .more
            shelves[shelf, default: []].append(AccountNewPlatformChoice(id: platform.id, name: AccountNaming.platformName(platform.id, catalog: catalog),
                                                                        methodSummary: summary(rows)))
        }
        return AccountNewShelf.allCases.compactMap { shelf in shelves[shelf].map { AccountNewShelfSection(shelf: shelf, platforms: $0) } }
    }

    /// 20 §7.3's mapping; a type platform_auth does not list gives no row, and an unknown type is ignored.
    public static func methods(for platform: String, in catalog: MetaCatalog) -> [AccountNewMethod] {
        let auth = catalog.authTypes(for: platform)
        if let modes = catalog.platform(platform)?.multiProtocol?.modes, !modes.isEmpty {
            return auth.contains("apikey") ? modes.map(modeRow) : []
        }
        return rows(for: platform).compactMap { (type, row) -> AccountNewMethod? in
            if case .oauth(let kinds) = row.kind {
                let allowed = kinds.filter { auth.contains($0.rawValue) }
                return allowed.isEmpty ? nil : AccountNewMethod(id: row.id, kind: .oauth(types: allowed), title: row.title, subtitle: row.subtitle, detail: row.detail)
            }
            return auth.contains(type) ? row : nil
        }
    }

    /// The address an API Key account gets when Base URL is left empty (Web CreateAccountModal).
    public static func officialBaseURL(for platform: String) -> String {
        switch platform {
        case "openai": "https://api.openai.com"
        case "gemini": "https://generativelanguage.googleapis.com"
        case "grok": "https://api.x.ai/v1"
        case "typesafe": "https://api.typesafe.ai"
        default: "https://api.anthropic.com"
        }
    }
    /// Web isOfficialGeminiBaseUrl: empty, or exactly https://generativelanguage.googleapis.com (a trailing / allowed).
    public static func isOfficialGeminiBaseURL(_ url: String) -> Bool {
        let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return true }
        guard let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              parts.host?.lowercased() == "generativelanguage.googleapis.com" else { return false }
        let path = parts.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        return (parts.port == nil || parts.port == 443) && path.isEmpty && (parts.query ?? "").isEmpty
    }

    // MARK: - Rows

    /// (platform_auth type, row) in the design's order.
    private static func rows(for platform: String) -> [(String, AccountNewMethod)] {
        switch platform {
        case "anthropic":
            [("oauth", oauth("Claude Code", subtitle: "OAuth / Setup Token", detail: "在浏览器登录 Claude 授权", types: [.oauth, .setupToken])),
             ("apikey", apiKey("Claude Console", subtitle: "API Key", detail: "粘贴 sk-ant-api03- 开头的 Key")),
             ("bedrock", AccountNewMethod(id: "bedrock", kind: .bedrock, title: "AWS Bedrock", subtitle: "SigV4 / API Key", detail: "AWS 访问密钥和 Region")),
             ("service_account", vertex)]
        case "openai":
            [("oauth", oauth("ChatGPT OAuth", detail: "在浏览器登录 ChatGPT 授权")),
             ("apikey", apiKey("API Key", subtitle: "Responses API", detail: "粘贴 sk- 开头的 Key"))]
        case "gemini":
            [("oauth", oauth("Google OAuth", subtitle: "Google One / Code Assist", detail: "在浏览器登录 Google 授权")),
             ("apikey", apiKey("AI Studio", subtitle: "API Key", detail: "粘贴 AIza 开头的 Key")), ("service_account", vertex)]
        case "antigravity":
            [("oauth", oauth("Antigravity OAuth", detail: "在浏览器登录 Google 授权")),
             ("apikey", AccountNewMethod(id: "upstream", kind: .upstream, title: "对接上游", subtitle: "Base URL + API Key", detail: "通过上游地址和 Key 连接"))]
        case "grok":
            [("oauth", oauth("Grok OAuth", detail: "在浏览器登录 xAI 授权")), ("apikey", apiKey("API Key", subtitle: "xAI API", detail: "粘贴 xai- 开头的 Key"))]
        default:
            [("apikey", apiKey("API Key", subtitle: "Anthropic 协议", detail: "粘贴站点给的 Key"))]
        }
    }
    private static let vertex = AccountNewMethod(id: "vertex", kind: .vertex, title: "Vertex", subtitle: "Service Account",
                                                 detail: "从“文件”选择 Service Account JSON")
    private static func oauth(_ title: String, subtitle: String = "浏览器授权", detail: String, types: [OAuthAuthKind] = [.oauth]) -> AccountNewMethod {
        AccountNewMethod(id: "oauth", kind: .oauth(types: types), title: title, subtitle: subtitle, detail: detail)
    }
    private static func apiKey(_ title: String, subtitle: String, detail: String) -> AccountNewMethod {
        AccountNewMethod(id: "apikey", kind: .apiKey, title: title, subtitle: subtitle, detail: detail)
    }
    private static func modeRow(_ mode: MetaCatalog.Mode) -> AccountNewMethod {
        AccountNewMethod(id: "mode." + mode.mode, kind: .multiProtocol(mode), title: AccountProtocolEndpoints.modeTitle(mode.mode), subtitle: "API Key",
                         detail: modeDetail(mode.mode))
    }
    /// Design AN_MODES.
    private static func modeDetail(_ mode: String) -> String {
        switch mode {
        case "payg": "消耗账户余额，按 Token 计费"
        case "coding": "订阅制编程套餐，按 5 小时 / 每周窗口限流"
        case "zen": "按量付费网关，按 Token 计费"
        case "go": "订阅制网关，按 5 小时 / 周 / 月窗口限流"
        default: "粘贴站点给的 Key"
        }
    }
    private static func summary(_ rows: [AccountNewMethod]) -> String {
        let names = rows.map { row -> String in
            switch row.kind {
            case .oauth: "OAuth"
            case .apiKey: "API Key"
            case .multiProtocol: row.title
            case .bedrock: "Bedrock"
            case .vertex: "Vertex"
            case .upstream: "对接上游"
            }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }.joined(separator: " · ")
    }
}
