import Foundation

public enum BedrockAuthMode: String, CaseIterable, Sendable {
    case sigv4, apikey
    public var title: String { self == .sigv4 ? "SigV4" : "API Key" }
}

extension GeminiOAuthType {
    /// The tier a new Gemini account starts on (Web geminiSelectedTier's defaults), sent with auth-url / exchange-code.
    public var defaultTierID: String {
        switch self {
        case .googleOne: "google_one_free"
        case .codeAssist: "gcp_standard"
        case .aiStudio: "aistudio_free"
        }
    }
}

/// Form defaults and ranges (20 §7.3, Web CreateAccountModal, design AN_BLANK / AN_REGIONS / AN_LOCATIONS).
public enum AccountNewDefaults {
    public static let concurrency = 10
    public static let concurrencyRange = 1...100
    public static let priority = 1
    public static let priorityRange = 1...99
    public static let rateMultiplierText = "1"
    public static let loadFactorRange = 1...10
    public static let bedrockRegion = "us-east-1"
    public static let bedrockRegions = ["us-east-1", "us-west-2", "eu-west-1", "ap-northeast-1"]
    /// The Web's default; the backend would use us-central1 for an empty one.
    public static let vertexLocation = "global"
    public static let vertexLocations = ["us-east5", "europe-west1", "asia-east1", "global"]
    /// The new-account form offers these two (S2D1-03).
    public static let geminiOAuthTypes: [GeminiOAuthType] = [.googleOne, .codeAssist]
    static let geminiAIStudioTier = "aistudio_free"
}

/// One item of the dock's 还差 list; `anchor` is where tapping it scrolls.
public struct AccountNewMissing: Sendable, Equatable {
    public enum Anchor: String, Sendable, CaseIterable { case platform, oauth, credentials, name, schedule }
    public let label: String
    public let anchor: Anchor
}

/// An address that is filled in but malformed, shown under its field.
public struct AccountNewIssue: Sendable, Equatable {
    public enum Field: String, Sendable { case baseURL, customEndpoint, upstreamBaseURL }
    public let field: Field
    public let anchor: AccountNewMissing.Anchor
    public let message: String
}

public struct AccountNewConfirmation: Sendable, Equatable {
    public let title: String
    public let message: String
    /// The destructive button.
    public let confirmTitle: String
    public let cancelTitle: String
}

/// The new-account form (20 §7.2–§7.4, design AN_BLANK). Memory only: it holds keys, tokens and the Service Account JSON (U16),
/// so it is not Codable and printing shows only the platform. Platform, method, OAuth kind and mixed scheduling change through
/// the switching functions, which clear what depends on them; setting `name` marks it as typed by the admin.
public struct AccountNewDraft: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public private(set) var platform: String?
    public private(set) var method: AccountNewMethod?
    public private(set) var claudeAuthKind: OAuthAuthKind = .oauth
    public private(set) var geminiOAuthType: GeminiOAuthType = .googleOne
    /// Code Assist's GCP project.
    public var gcpProjectID = ""
    public var oauthGrant: AccountNewOAuthGrant?
    public var apiKey = ""
    /// Empty means the platform's official address.
    public var baseURL = ""
    /// Multi-protocol only; nil (or one the mode does not offer) means the method's default.
    public var apiProtocol: String?
    /// A concrete protocol's endpoint: the catalog's, or `customEndpoint`.
    public var usesCustomEndpoint = false
    public var customEndpoint = ""
    public var bedrockAuth: BedrockAuthMode = .sigv4
    public var awsAccessKeyID = "", awsSecretAccessKey = "", awsSessionToken = "", bedrockAPIKey = ""
    public var awsRegion = AccountNewDefaults.bedrockRegion
    public var vertexFile: VertexServiceAccountFile?
    public var vertexLocation = AccountNewDefaults.vertexLocation
    public var upstreamBaseURL = "", upstreamAPIKey = ""
    /// Antigravity's “在 /v1/messages 中使用”.
    public private(set) var mixedScheduling = false
    /// Antigravity's “允许超量请求（AI Credits）”.
    public var allowOverages = false
    private var typedName = ""
    public var name: String {
        get { typedName }
        set { typedName = newValue; isNameAutomatic = false }
    }
    public private(set) var isNameAutomatic = true
    public var notes = ""
    /// In the order they were picked, which is the account's priority in each group (S2D1-07).
    public var groupIDs: [Int] = []
    public var concurrency = AccountNewDefaults.concurrency
    public var priority = AccountNewDefaults.priority
    public var rateMultiplierText = AccountNewDefaults.rateMultiplierText
    public var proxyID: Int?
    /// Unix seconds; nil never expires.
    public var expiresAt: Int64?
    public var autoPauseOnExpired = true
    /// 1–10; nil leaves the default.
    public var loadFactor: Int?
    /// The session's `AdminMe.isLegacyServer`, fixed for the form's life.
    public let isLegacyServer: Bool
    public init(isLegacyServer: Bool = false) { self.isLegacyServer = isLegacyServer }

    /// The `type` sent: Claude's OAuth kind, apikey for every key method (对接上游 included), bedrock, service_account.
    public var accountType: String? {
        switch method?.kind {
        case nil: nil
        case .oauth?: platform == OAuthPlatform.anthropic.rawValue ? claudeAuthKind.rawValue : OAuthAuthKind.oauth.rawValue
        case .apiKey?, .multiProtocol?, .upstream?: "apikey"
        case .bedrock?: "bedrock"
        case .vertex?: "service_account"
        }
    }
    public var effectiveProtocol: String? {
        guard let method, method.isAccountMode else { return nil }
        if let apiProtocol, method.protocolOptions.contains(apiProtocol) { return apiProtocol }
        return method.defaultProtocol
    }
    /// A plain non-negative decimal (“0” means not billed); a sign, a comma or an exponent reads as missing.
    public var rateMultiplier: Decimal? {
        let text = rateMultiplierText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
    /// Gemini's tier for auth-url / exchange-code (OAuth), or AI Studio's on the official address.
    public var geminiTierID: String? {
        guard platform == OAuthPlatform.gemini.rawValue else { return nil }
        switch method?.kind {
        case .oauth?: return geminiOAuthType.defaultTierID
        case .apiKey? where AccountNewCatalog.isOfficialGeminiBaseURL(baseURL): return AccountNewDefaults.geminiAIStudioTier
        default: return nil
        }
    }

    /// Design anCredTouched: anything entered in the credential area, or an authorization under way (S2-17 knows).
    public func credentialsTouched(oauthInProgress: Bool = false) -> Bool {
        let typed = [apiKey, baseURL, customEndpoint, awsAccessKeyID, awsSecretAccessKey, awsSessionToken, bedrockAPIKey, upstreamBaseURL,
                     upstreamAPIKey, gcpProjectID]
        return oauthInProgress || oauthGrant != nil || vertexFile != nil || typed.contains { !Self.isBlank($0) }
    }

    /// 20 §7.3's 还差 list in its fixed order; the title's “还差 N 项” counts the same list.
    public func missing(in catalog: MetaCatalog) -> [AccountNewMissing] {
        let methodLabel = platform.flatMap { catalog.platform($0)?.multiProtocol } == nil ? "认证方式" : "账号类型"
        return missingItems(methodLabel: methodLabel)
    }
    func missingItems(methodLabel: String) -> [AccountNewMissing] {
        var items = [AccountNewMissing]()
        if platform == nil { items.append(AccountNewMissing(label: "平台", anchor: .platform)) }
        else if method == nil { items.append(AccountNewMissing(label: methodLabel, anchor: .platform)) }
        if let label = missingCredentialLabel {
            let browserCode = [OAuthPlatform.anthropic.rawValue, OAuthPlatform.gemini.rawValue].contains(platform ?? "")
            let isOAuth = if case .oauth? = method?.kind { true } else { false }
            items.append(AccountNewMissing(label: label, anchor: isOAuth && browserCode ? .oauth : .credentials))
        }
        if Self.isBlank(name) { items.append(AccountNewMissing(label: "名称", anchor: .name)) }
        if rateMultiplier == nil { items.append(AccountNewMissing(label: "计费倍率", anchor: .schedule)) }
        return items
    }
    /// nil once the method's credentials are complete.
    var missingCredentialLabel: String? {
        guard let method else { return "凭据" }
        switch method.kind {
        case .oauth: return grantMatches ? nil : method.credentialLabel
        case .apiKey: return Self.isBlank(apiKey) ? method.credentialLabel : nil
        case .multiProtocol:
            if Self.isBlank(apiKey) { return method.credentialLabel }
            return customEndpointInUse && Self.isBlank(customEndpoint) ? "自定义端点" : nil
        case .bedrock:
            let complete = bedrockAuth == .sigv4 ? !Self.isBlank(awsAccessKeyID) && !Self.isBlank(awsSecretAccessKey) : !Self.isBlank(bedrockAPIKey)
            return complete ? nil : method.credentialLabel
        case .vertex: return vertexFile == nil ? method.credentialLabel : nil
        case .upstream: return Self.isBlank(upstreamBaseURL) || Self.isBlank(upstreamAPIKey) ? method.credentialLabel : nil
        }
    }
    /// The grant is for this platform and the OAuth kind `type` will say.
    var grantMatches: Bool {
        guard let oauthGrant, let platform, oauthGrant.platform == OAuthPlatform(accountPlatform: platform) else { return false }
        return oauthGrant.type.rawValue == accountType
    }
    /// A concrete protocol with the admin's own endpoint.
    var customEndpointInUse: Bool { usesCustomEndpoint && effectiveProtocol.map { $0 != AccountProtocolEndpoints.adaptive } == true }

    /// Filled in but not an http(s) address (BaseURLRule); the request cannot be built while there is one.
    public var issues: [AccountNewIssue] {
        let checks: [(AccountNewIssue.Field, String)]
        switch method?.kind {
        case .apiKey?: checks = [(.baseURL, baseURL)]
        case .multiProtocol? where customEndpointInUse: checks = [(.customEndpoint, customEndpoint)]
        case .upstream?: checks = [(.upstreamBaseURL, upstreamBaseURL)]
        default: checks = []
        }
        return checks.filter { BaseURLRule.validate($0.1) == .invalid }
            .map { AccountNewIssue(field: $0.0, anchor: .credentials, message: BaseURLRule.invalidMessage) }
    }

    /// Takes the suggested name while the name is still the automatic one or empty.
    public mutating func suggestName(_ suggestion: String) {
        guard isNameAutomatic || Self.isBlank(typedName) else { return }
        typedName = suggestion; isNameAutomatic = true
    }

    static func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public var description: String { "AccountNewDraft(\(platform ?? DisplayFormat.missing), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

// MARK: - Switching (20 §7.4-2, -4, -5)

extension AccountNewDraft {
    /// A new platform clears the authorization, every credential input, the groups, the Antigravity switches and the OAuth kinds;
    /// the name (an automatic one becomes `suggestedName`), notes, scheduling, proxy and the 更多 fields stay. A platform with one
    /// method gets it picked.
    public func switchingPlatform(to platform: String, methods: [AccountNewMethod], suggestedName: String) -> AccountNewDraft {
        guard platform != self.platform else { return self }
        var next = AccountNewDraft(isLegacyServer: isLegacyServer)
        next.platform = platform
        next.typedName = typedName; next.isNameAutomatic = isNameAutomatic
        next.suggestName(suggestedName)
        next.notes = notes; next.concurrency = concurrency; next.priority = priority; next.rateMultiplierText = rateMultiplierText
        next.proxyID = proxyID; next.expiresAt = expiresAt; next.autoPauseOnExpired = autoPauseOnExpired; next.loadFactor = loadFactor
        return methods.count == 1 ? next.switchingMethod(to: methods[0]) : next
    }
    /// A new method clears the authorization and every credential input; groups, name, scheduling, proxy and 更多 stay.
    public func switchingMethod(to method: AccountNewMethod) -> AccountNewDraft {
        guard method.id != self.method?.id else { return self }
        var next = clearingCredentials()
        next.method = method
        if case .oauth(let kinds) = method.kind, !kinds.contains(claudeAuthKind), let first = kinds.first { next.claudeAuthKind = first }
        return next
    }
    public func switchingClaudeAuthKind(_ kind: OAuthAuthKind) -> AccountNewDraft {
        guard kind != claudeAuthKind else { return self }
        var next = self; next.claudeAuthKind = kind; next.oauthGrant = nil; return next
    }
    public func switchingGeminiOAuthType(_ type: GeminiOAuthType) -> AccountNewDraft {
        guard type != geminiOAuthType else { return self }
        var next = self; next.geminiOAuthType = type; next.oauthGrant = nil; return next
    }
    /// Turning it off drops the Anthropic / Gemini groups it allowed and returns their ids for “已移除 N 个不再适用的分组” (撤销 puts
    /// the old draft back).
    public func settingMixedScheduling(_ isOn: Bool, groups: [AdminGroup]) -> (draft: AccountNewDraft, removedGroupIDs: [Int]) {
        var next = self
        next.mixedScheduling = isOn
        guard !isOn, let platform else { return (next, []) }
        let removed = AccountNewGroups.inapplicable(groupIDs, groups: groups, platform: platform, mixedScheduling: false)
        next.groupIDs = groupIDs.filter { !removed.contains($0) }
        return (next, removed)
    }
    private func clearingCredentials() -> AccountNewDraft {
        let blank = AccountNewDraft()
        var next = self
        next.oauthGrant = nil; next.gcpProjectID = ""; next.apiKey = ""; next.baseURL = ""; next.apiProtocol = nil
        next.usesCustomEndpoint = false; next.customEndpoint = ""; next.bedrockAuth = blank.bedrockAuth
        next.awsAccessKeyID = ""; next.awsSecretAccessKey = ""; next.awsSessionToken = ""; next.bedrockAPIKey = ""; next.awsRegion = blank.awsRegion
        next.vertexFile = nil; next.vertexLocation = blank.vertexLocation; next.upstreamBaseURL = ""; next.upstreamAPIKey = ""
        return next
    }

    /// “换成 {平台}？” when something was entered.
    public func platformSwitchConfirmation(toPlatformName: String, oauthInProgress: Bool = false) -> AccountNewConfirmation? {
        guard platform != nil, credentialsTouched(oauthInProgress: oauthInProgress) else { return nil }
        let what = oauthGrant != nil || oauthInProgress ? "授权" : "凭据"
        return AccountNewConfirmation(title: "换成 \(toPlatformName)？", message: "已填写的\(what)\(groupIDs.isEmpty ? "" : "和选好的分组")会清空，名称、调度和代理保留。",
                                      confirmTitle: "更换平台", cancelTitle: "取消")
    }
    /// “改成「X」？” after the account exists, or when something was entered.
    public func methodSwitchConfirmation(to method: AccountNewMethod, createdAccountID: Int?, oauthInProgress: Bool = false) -> AccountNewConfirmation? {
        guard let current = self.method, current.id != method.id else { return nil }
        let what = method.isAccountMode ? "账号类型" : "认证方式"
        let message: String
        if let createdAccountID {
            let redo = if case .oauth = method.kind { "授权" } else { "填写凭据" }
            message = "账号 #\(createdAccountID) 已创建。换\(what)后要重新\(redo)，保存时替换原来的凭据。"
        } else if credentialsTouched(oauthInProgress: oauthInProgress) {
            message = "换\(what)会清空已填写的\(oauthGrant != nil || oauthInProgress ? "授权" : "凭据")。"
        } else {
            return nil
        }
        return AccountNewConfirmation(title: "改成「\(method.title)」？", message: message, confirmTitle: "更换", cancelTitle: "取消")
    }
    /// Switching OAuth / Setup Token or Google One / Code Assist after authorizing; `toTitle` is the kind's title.
    public func authKindSwitchConfirmation(toTitle: String, oauthInProgress: Bool = false) -> AccountNewConfirmation? {
        guard oauthGrant != nil || oauthInProgress else { return nil }
        return AccountNewConfirmation(title: "切换到 \(toTitle)？", message: "切换会丢弃当前授权，需要重新在浏览器里授权。", confirmTitle: "切换", cancelTitle: "取消")
    }
    /// 7.4-4; nil before a platform is picked (the form just closes).
    public func discardConfirmation(oauthInProgress: Bool = false) -> AccountNewConfirmation? {
        guard platform != nil else { return nil }
        let message = oauthGrant != nil || oauthInProgress ? "已填写的内容和授权结果不会保存。" : "已填写的内容不会保存。"
        return AccountNewConfirmation(title: "放弃新建账号？", message: message, confirmTitle: "放弃", cancelTitle: "继续填写")
    }
}

/// “{短名}-{NN}” (20 §7.2 名称建议).
public enum AccountNewNaming {
    /// NN is the platform's account count + 1, two digits at least; a name already taken moves on to the next number.
    public static func suggestedName(platform: String, existingCount: Int, takenNames: Set<String> = []) -> String {
        let short = AccountNaming.shortName(platform)
        var number = max(existingCount, 0) + 1
        func name(_ value: Int) -> String { "\(short)-\(value < 10 ? "0" : "")\(value)" }
        while takenNames.contains(name(number)) { number += 1 }
        return name(number)
    }
    /// status-summary's platforms[].total; without per-platform rows (dashboard/home availability) the loaded list's count.
    public static func existingCount(platform: String, summary: AccountStatusSummary?, loadedAccounts: [UpstreamAccount]) -> Int {
        if let rows = summary?.platforms, !rows.isEmpty { return rows.first { $0.platform == platform }?.counts.total ?? 0 }
        return loadedAccounts.filter { $0.platform == platform }.count
    }
}

/// The group chips (20 §7.2, Web GroupSelector): active groups of the platform and composite ones; Antigravity with mixed
/// scheduling also takes Anthropic and Gemini groups.
public enum AccountNewGroups {
    public static func allowedPlatforms(for platform: String, mixedScheduling: Bool) -> Set<String> {
        let own: Set = [platform, "composite"]
        return platform == OAuthPlatform.antigravity.rawValue && mixedScheduling ? own.union(["anthropic", "gemini"]) : own
    }
    /// In AdminGroup.displayOrder; groups/all already leaves inactive groups out.
    public static func eligible(_ groups: [AdminGroup], platform: String, mixedScheduling: Bool) -> [AdminGroup] {
        let allowed = allowedPlatforms(for: platform, mixedScheduling: mixedScheduling)
        return groups.filter { $0.status == "active" && allowed.contains($0.platform) }.sorted(by: AdminGroup.displayOrder)
    }
    /// The picked ids whose group no longer fits, in picking order; an id not among `groups` is left alone.
    public static func inapplicable(_ selected: [Int], groups: [AdminGroup], platform: String, mixedScheduling: Bool) -> [Int] {
        let allowed = allowedPlatforms(for: platform, mixedScheduling: mixedScheduling)
        let platforms = Dictionary(groups.map { ($0.id, $0.platform) }) { first, _ in first }
        return selected.filter { id in platforms[id].map { !allowed.contains($0) } ?? false }
    }
}
