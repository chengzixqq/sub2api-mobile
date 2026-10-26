import Foundation

/// `GET admin/meta/catalog` (20 §7.2): the platforms in display order and the account types the caller may create on each.
/// Only `platform_catalog.platforms` and `platform_auth` are read; the other enumerations wait for the first screen that needs them.
public struct MetaCatalog: Decodable, Sendable, Equatable {
    public struct Platform: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let displayName: String
        public let cnProvider: Bool
        public let multiProtocol: MultiProtocol?
        public init(id: String, displayName: String, cnProvider: Bool = false, multiProtocol: MultiProtocol? = nil) {
            self.id = id; self.displayName = displayName; self.cnProvider = cnProvider; self.multiProtocol = multiProtocol
        }
        enum CodingKeys: String, CodingKey { case id; case displayName = "display_name", cnProvider = "cn_provider", multiProtocol = "multi_protocol" }
        /// An entry without an id is unusable and skipped; a missing name falls back to `GroupPlatform.title`, a malformed
        /// `multi_protocol` to none.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let id = try c.decode(String.self, forKey: .id)
            guard !id.isEmpty else { throw APIError.invalidResponse }
            let name = (try? c.decodeIfPresent(String.self, forKey: .displayName))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.init(id: id, displayName: name.isEmpty ? GroupPlatform.title(id) : name,
                      cnProvider: (try? c.decodeIfPresent(Bool.self, forKey: .cnProvider)) ?? false,
                      multiProtocol: try? c.decodeIfPresent(MultiProtocol.self, forKey: .multiProtocol))
        }
    }
    /// A provider with several endpoint sets (pay-as-you-go, coding plan …); `routing`, `responses_path` and `model_catalog` are not read yet.
    public struct MultiProtocol: Decodable, Sendable, Equatable {
        public let defaultMode: String
        /// The default mode first, as the server sends them.
        public let modes: [Mode]
        public init(defaultMode: String, modes: [Mode]) { self.defaultMode = defaultMode; self.modes = modes }
        enum CodingKeys: String, CodingKey { case modes; case defaultMode = "default_mode" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let modes = c.lossyList(Mode.self, .modes)
            guard !modes.isEmpty else { throw APIError.invalidResponse }
            try self.init(defaultMode: c.decode(String.self, forKey: .defaultMode), modes: modes)
        }
        /// Web getProviderMode: the named mode, else the default, else the first.
        public func mode(_ name: String?) -> Mode? {
            let wanted = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return modes.first { $0.mode == wanted } ?? modes.first { $0.mode == defaultMode } ?? modes.first
        }
    }
    public struct Mode: Decodable, Sendable, Equatable {
        public let mode: String
        /// Protocol (`anthropic`, `chat_completions`, `responses`) → official endpoint.
        public let baseURLs: [String: String]
        /// Model pattern → protocol, for providers routed by model.
        public let protocolRules: [ProtocolRule]
        public init(mode: String, baseURLs: [String: String], protocolRules: [ProtocolRule] = []) {
            self.mode = mode; self.baseURLs = baseURLs; self.protocolRules = protocolRules
        }
        enum CodingKeys: String, CodingKey { case mode; case baseURLs = "base_urls", protocolRules = "protocol_rules" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(mode: c.decode(String.self, forKey: .mode),
                          baseURLs: (try? c.decodeIfPresent([String: String].self, forKey: .baseURLs)) ?? [:],
                          protocolRules: c.lossyList(ProtocolRule.self, .protocolRules))
        }
    }
    public struct ProtocolRule: Decodable, Sendable, Equatable {
        public let pattern: String
        /// JSON `protocol`.
        public let preferredProtocol: String
        /// JSON `protocols`; just the preferred one when omitted.
        public let supportedProtocols: [String]
        public init(pattern: String, preferredProtocol: String, supportedProtocols: [String]? = nil) {
            self.pattern = pattern; self.preferredProtocol = preferredProtocol
            self.supportedProtocols = supportedProtocols.flatMap { $0.isEmpty ? nil : $0 } ?? [preferredProtocol]
        }
        enum CodingKeys: String, CodingKey { case pattern; case preferredProtocol = "protocol", supportedProtocols = "protocols" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(pattern: c.decode(String.self, forKey: .pattern), preferredProtocol: c.decode(String.self, forKey: .preferredProtocol),
                          supportedProtocols: try? c.decodeIfPresent([String].self, forKey: .supportedProtocols))
        }
    }

    /// Display order.
    public let platforms: [Platform]
    /// Platform → account types the caller may create, already trimmed for a vendor; `{}` means it may create none.
    public let platformAuth: [String: [String]]
    public init(platforms: [Platform], platformAuth: [String: [String]]) { self.platforms = platforms; self.platformAuth = platformAuth }
    enum CodingKeys: String, CodingKey { case platformCatalog = "platform_catalog", platformAuth = "platform_auth" }
    private enum CatalogKeys: String, CodingKey { case platforms }
    /// A section that is missing or unreadable (an empty platform list included) takes the builtin value; an unknown platform is kept.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let listed = (try? c.nestedContainer(keyedBy: CatalogKeys.self, forKey: .platformCatalog))?.lossyList(Platform.self, .platforms) ?? []
        let auth = try? c.decodeIfPresent([String: [String]].self, forKey: .platformAuth)
        self.init(platforms: listed.isEmpty ? Self.builtin.platforms : listed, platformAuth: auth ?? Self.builtin.platformAuth)
    }

    public func platform(_ id: String) -> Platform? { platforms.first { $0.id == id } }
    public func authTypes(for platform: String) -> [String] { platformAuth[platform] ?? [] }
    /// The site predates the endpoint (a non-JSON 404), or compliance is still unconfirmed after the global prompt (423).
    static func fallsBackToBuiltin(after error: APIError) -> Bool {
        (error.statusCode == 404 && error.category == .unsupported) || error.statusCode == 423
    }
}

/// Copied from sub2 `frontend/src/constants/platformCatalog.builtin.json` (main 70116315d; the backend test
/// TestFrontendBuiltinPlatformCatalogInSync keeps that file equal to domain/platforms.go) and from the station owner's
/// `platform_auth` (service/admin_meta_catalog.go). `gateway`, `litellm_provider`, `routing`, `responses_path` and
/// `model_catalog` are not copied. Re-copy when the backend registers a platform or changes an endpoint.
/// The URLs are the providers' public API endpoints, the same ones the Web fills in, not any site's address.
extension MetaCatalog {
    /// Used without `meta.catalog`, for a non-JSON 404 or a 423, and for a reply missing either section.
    public static let builtin = MetaCatalog(platforms: builtinPlatforms, platformAuth: builtinPlatformAuth)

    static let builtinPlatforms: [Platform] = [
        Platform(id: "anthropic", displayName: "Anthropic"),
        Platform(id: "openai", displayName: "OpenAI"),
        Platform(id: "gemini", displayName: "Gemini"),
        Platform(id: "antigravity", displayName: "Antigravity"),
        Platform(id: "grok", displayName: "Grok"),
        Platform(id: "kimi", displayName: "Kimi", cnProvider: true, multiProtocol: MultiProtocol(defaultMode: "payg", modes: [
            Mode(mode: "payg", baseURLs: endpoints(anthropic: "https://api.moonshot.cn/anthropic", chat: "https://api.moonshot.cn/v1",
                                                   responses: "https://api.moonshot.cn/v1")),
            Mode(mode: "coding", baseURLs: endpoints(anthropic: "https://api.kimi.com/coding", chat: "https://api.kimi.com/coding/v1",
                                                     responses: "https://api.kimi.com/coding/v1"))
        ])),
        Platform(id: "zhipu", displayName: "Zhipu GLM", cnProvider: true, multiProtocol: MultiProtocol(defaultMode: "payg", modes: [
            Mode(mode: "payg", baseURLs: endpoints(anthropic: "https://open.bigmodel.cn/api/anthropic", chat: "https://open.bigmodel.cn/api/paas/v4")),
            Mode(mode: "coding", baseURLs: endpoints(anthropic: "https://open.bigmodel.cn/api/anthropic",
                                                     chat: "https://open.bigmodel.cn/api/coding/paas/v4"))
        ])),
        Platform(id: "deepseek", displayName: "DeepSeek", cnProvider: true, multiProtocol: MultiProtocol(defaultMode: "payg", modes: [
            Mode(mode: "payg", baseURLs: endpoints(anthropic: "https://api.deepseek.com/anthropic", chat: "https://api.deepseek.com",
                                                   responses: "https://api.deepseek.com"))
        ])),
        Platform(id: "minimax", displayName: "MiniMax", cnProvider: true, multiProtocol: MultiProtocol(defaultMode: "payg", modes: [
            Mode(mode: "payg", baseURLs: endpoints(anthropic: "https://api.minimaxi.com/anthropic", chat: "https://api.minimaxi.com/v1",
                                                   responses: "https://api.minimaxi.com/v1")),
            Mode(mode: "coding", baseURLs: endpoints(anthropic: "https://api.minimaxi.com/anthropic", chat: "https://api.minimaxi.com/v1",
                                                     responses: "https://api.minimaxi.com/v1"))
        ])),
        Platform(id: "opencode_go", displayName: "OpenCode", multiProtocol: MultiProtocol(defaultMode: "go", modes: [
            Mode(mode: "go", baseURLs: endpoints(anthropic: "https://opencode.ai/zen/go", chat: "https://opencode.ai/zen/go/v1",
                                                 responses: "https://opencode.ai/zen/go/v1"),
                 protocolRules: rules(("grok-*", "responses"), ("gpt-*", "responses"), ("muse-spark-*", "responses"), ("minimax-*", "anthropic"),
                                      ("qwen*", "anthropic"))),
            Mode(mode: "zen", baseURLs: endpoints(anthropic: "https://opencode.ai/zen", chat: "https://opencode.ai/zen/v1",
                                                  responses: "https://opencode.ai/zen/v1"),
                 protocolRules: rules(("grok-*", "responses"), ("gpt-*", "responses"), ("muse-spark-*", "responses"), ("claude-*", "anthropic"),
                                      ("qwen3.8-max", "chat_completions"), ("qwen*", "anthropic")))
        ])),
        Platform(id: "typesafe", displayName: "TypeSafe / Jev"),
        Platform(id: "command_code", displayName: "Command Code", multiProtocol: MultiProtocol(defaultMode: "payg", modes: [
            Mode(mode: "payg", baseURLs: endpoints(anthropic: "https://api.commandcode.ai/provider", chat: "https://api.commandcode.ai/provider/v1",
                                                   responses: "https://api.commandcode.ai/provider/v1"),
                 protocolRules: [ProtocolRule(pattern: "claude-*", preferredProtocol: "anthropic"),
                                 ProtocolRule(pattern: "gpt-*", preferredProtocol: "responses", supportedProtocols: ["responses", "chat_completions"])])
        ])),
        Platform(id: "cline", displayName: "Cline", multiProtocol: MultiProtocol(defaultMode: "payg", modes: [
            Mode(mode: "payg", baseURLs: endpoints(chat: "https://api.cline.bot/api/v1"))
        ]))
    ]

    /// The Web CreateAccountModal's choices; every other platform offers API keys only. Antigravity's “对接上游” is an apikey account.
    static let builtinPlatformAuth: [String: [String]] = {
        let choices: [String: [String]] = [
            "anthropic": ["oauth", "setup-token", "apikey", "bedrock", "service_account"], "openai": ["oauth", "apikey"],
            "gemini": ["oauth", "apikey", "service_account"], "antigravity": ["oauth", "apikey"], "grok": ["oauth", "apikey"]
        ]
        return Dictionary(uniqueKeysWithValues: builtinPlatforms.map { ($0.id, choices[$0.id] ?? ["apikey"]) })
    }()

    private static func endpoints(anthropic: String? = nil, chat: String? = nil, responses: String? = nil) -> [String: String] {
        ["anthropic": anthropic, "chat_completions": chat, "responses": responses].compactMapValues { $0 }
    }
    /// (pattern, protocol) pairs without `protocols`.
    private static func rules(_ pairs: (String, String)...) -> [ProtocolRule] {
        pairs.map { ProtocolRule(pattern: $0.0, preferredProtocol: $0.1) }
    }
}

extension APIClient {
    /// Conditional (00 §4.2, ETag per identity tier). Other errors are thrown: skipping the request without `meta.catalog` and
    /// falling back after a failure belong to the AppModel wrapper (X25), since the client does not know the capabilities.
    public func metaCatalog() async throws -> MetaCatalog {
        do {
            let catalog: MetaCatalog = try await request("admin/meta/catalog")
            return catalog
        } catch let error as APIError where MetaCatalog.fallsBackToBuiltin(after: error) {
            return .builtin
        }
    }
}
