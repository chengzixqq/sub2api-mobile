import Foundation

/// 20 §0.3 names, shared by the account list, detail and new-account screens.
public enum AccountNaming {
    /// S2D1-12: a platform the app knows keeps its Chinese title (zhipu → 智谱 GLM where the catalog says “Zhipu GLM”), so the
    /// overview, groups and accounts agree; a platform the backend registers later takes the catalog's display name.
    public static func platformName(_ platform: String, catalog: MetaCatalog?) -> String {
        guard !platform.isEmpty else { return DisplayFormat.missing }
        if GroupPlatform.values.contains(platform) { return GroupPlatform.title(platform) }
        if let name = catalog?.platform(platform)?.displayName, !name.isEmpty { return name }
        return platform
    }
    /// Antigravity's “对接上游” option is created as an apikey account (admin_meta_catalog.go).
    public static func typeName(platform: String, type: String) -> String {
        if platform == "antigravity", type == "apikey" { return "对接上游" }
        switch type {
        case "": return DisplayFormat.missing
        case "oauth": return "OAuth"
        case "setup-token": return "Setup Token"
        case "apikey": return "API Key"
        case "upstream": return "对接上游"
        case "bedrock": return "AWS Bedrock"
        case "service_account": return "Vertex"
        default: return type
        }
    }
    /// The design's PLATFORMS.short (v-account-new.jsx), for new account names “{短名}-{NN}”; an unknown platform as is.
    public static func shortName(_ platform: String) -> String { shortNames[platform] ?? platform }

    private static let shortNames: [String: String] = [
        "anthropic": "Claude", "openai": "OpenAI", "gemini": "Gemini", "antigravity": "Antigravity", "grok": "Grok", "kimi": "Kimi",
        "zhipu": "GLM", "deepseek": "DeepSeek", "minimax": "MiniMax", "opencode_go": "OpenCode", "typesafe": "TypeSafe",
        "command_code": "CommandCode", "cline": "Cline"
    ]
}
