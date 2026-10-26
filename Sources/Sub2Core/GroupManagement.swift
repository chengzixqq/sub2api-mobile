import Foundation

/// A projection of the administrator DTO. Unknown server configuration is never written back.
public struct AdminGroup: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public var name: String
    public var description: String?
    public var platform: String
    public var status: String
    public var rateMultiplier: Decimal?
    public var isExclusive: Bool?
    public var subscriptionType: String?
    public var dailyLimitUSD: Decimal?
    public var weeklyLimitUSD: Decimal?
    public var monthlyLimitUSD: Decimal?
    public var rpmLimit: Int?
    public var accountCount: Int?
    public var activeAccountCount: Int?
    public var rateLimitedAccountCount: Int?
    public var billingLocked: Bool?
    public var createdAt: String?
    public var updatedAt: String?
    /// `sort_order`; order groups with `displayOrder`.
    public var sortOrder: Int?

    public init(id: Int, name: String, description: String? = nil, platform: String = "openai", status: String = "active", rateMultiplier: Decimal? = 1, isExclusive: Bool? = false, subscriptionType: String? = "standard", dailyLimitUSD: Decimal? = nil, weeklyLimitUSD: Decimal? = nil, monthlyLimitUSD: Decimal? = nil, rpmLimit: Int? = 0, accountCount: Int? = nil, activeAccountCount: Int? = nil, rateLimitedAccountCount: Int? = nil, billingLocked: Bool? = nil, createdAt: String? = nil, updatedAt: String? = nil, sortOrder: Int? = nil) {
        self.id = id; self.name = name; self.description = description; self.platform = platform; self.status = status
        self.rateMultiplier = rateMultiplier; self.isExclusive = isExclusive; self.subscriptionType = subscriptionType
        self.dailyLimitUSD = dailyLimitUSD; self.weeklyLimitUSD = weeklyLimitUSD; self.monthlyLimitUSD = monthlyLimitUSD
        self.rpmLimit = rpmLimit; self.accountCount = accountCount; self.activeAccountCount = activeAccountCount
        self.rateLimitedAccountCount = rateLimitedAccountCount; self.billingLocked = billingLocked
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.sortOrder = sortOrder
    }
    enum CodingKeys: String, CodingKey {
        case id, name, description, platform, status
        case rateMultiplier = "rate_multiplier", isExclusive = "is_exclusive", subscriptionType = "subscription_type"
        case dailyLimitUSD = "daily_limit_usd", weeklyLimitUSD = "weekly_limit_usd", monthlyLimitUSD = "monthly_limit_usd"
        case rpmLimit = "rpm_limit", accountCount = "account_count", activeAccountCount = "active_account_count"
        case rateLimitedAccountCount = "rate_limited_account_count", billingLocked = "billing_locked"
        case createdAt = "created_at", updatedAt = "updated_at", sortOrder = "sort_order"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        platform = try c.decode(String.self, forKey: .platform); status = try c.decode(String.self, forKey: .status)
        rateMultiplier = try c.optionalDecimal(.rateMultiplier); isExclusive = try c.decodeIfPresent(Bool.self, forKey: .isExclusive)
        subscriptionType = try c.decodeIfPresent(String.self, forKey: .subscriptionType)
        dailyLimitUSD = try c.optionalDecimal(.dailyLimitUSD); weeklyLimitUSD = try c.optionalDecimal(.weeklyLimitUSD); monthlyLimitUSD = try c.optionalDecimal(.monthlyLimitUSD)
        rpmLimit = try c.decodeIfPresent(Int.self, forKey: .rpmLimit)
        accountCount = try c.decodeIfPresent(Int.self, forKey: .accountCount); activeAccountCount = try c.decodeIfPresent(Int.self, forKey: .activeAccountCount)
        rateLimitedAccountCount = try c.decodeIfPresent(Int.self, forKey: .rateLimitedAccountCount)
        billingLocked = try c.decodeIfPresent(Bool.self, forKey: .billingLocked)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt); updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder)
    }
}
extension AdminGroup {
    /// The backend's order (ListActive / ListWithFilters): sort_order ascending, a missing one as 0, then id.
    /// Use as `groups.sorted(by: AdminGroup.displayOrder)`.
    public static func displayOrder(_ lhs: AdminGroup, _ rhs: AdminGroup) -> Bool {
        (lhs.sortOrder ?? 0, lhs.id) < (rhs.sortOrder ?? 0, rhs.id)
    }
}

public enum GroupPlatform {
    public static let values = ["anthropic", "openai", "gemini", "antigravity", "grok", "kimi", "zhipu", "deepseek", "minimax", "opencode_go", "typesafe", "command_code", "cline", "composite"]
    public static func title(_ value: String) -> String {
        switch value {
        case "openai": "OpenAI"; case "anthropic": "Anthropic"; case "gemini": "Gemini"; case "antigravity": "Antigravity"
        case "grok": "Grok"; case "kimi": "Kimi"; case "zhipu": "智谱 GLM"; case "deepseek": "DeepSeek"; case "minimax": "MiniMax"
        case "opencode_go": "OpenCode"; case "typesafe": "TypeSafe / Jev"; case "command_code": "Command Code"; case "cline": "Cline"
        case "composite": "组合分组"; default: value
        }
    }
}

/// nil on a request means unchanged; unlimited explicitly encodes JSON null.
public enum GroupLimitChange: Sendable, Equatable, Encodable {
    case unlimited
    case amount(Decimal)
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .unlimited: try c.encodeNil(); case .amount(let value): try c.encode(value) }
    }
    fileprivate func validate() throws {
        if case .amount(let value) = self { try GroupWriteValidation.decimal(value, positive: false) }
    }
}

public struct GroupCreateRequest: Encodable, Sendable {
    public var name: String
    public var description: String
    public var platform: String
    public var rateMultiplier: Decimal
    public var isExclusive: Bool
    public var subscriptionType: String
    public var rpmLimit: Int
    public var dailyLimitUSD: GroupLimitChange
    public var weeklyLimitUSD: GroupLimitChange
    public var monthlyLimitUSD: GroupLimitChange
    public init(name: String, description: String = "", platform: String = "openai", rateMultiplier: Decimal = 1, isExclusive: Bool = false, subscriptionType: String = "standard", rpmLimit: Int = 0, dailyLimitUSD: GroupLimitChange = .unlimited, weeklyLimitUSD: GroupLimitChange = .unlimited, monthlyLimitUSD: GroupLimitChange = .unlimited) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines); self.description = description; self.platform = platform
        self.rateMultiplier = rateMultiplier; self.isExclusive = isExclusive; self.subscriptionType = subscriptionType; self.rpmLimit = rpmLimit
        self.dailyLimitUSD = dailyLimitUSD; self.weeklyLimitUSD = weeklyLimitUSD; self.monthlyLimitUSD = monthlyLimitUSD
    }
    enum CodingKeys: String, CodingKey {
        case name, description, platform
        case rateMultiplier = "rate_multiplier", isExclusive = "is_exclusive", subscriptionType = "subscription_type", rpmLimit = "rpm_limit"
        case dailyLimitUSD = "daily_limit_usd", weeklyLimitUSD = "weekly_limit_usd", monthlyLimitUSD = "monthly_limit_usd"
    }
    public func validate() throws {
        try GroupWriteValidation.name(name); try GroupWriteValidation.decimal(rateMultiplier, positive: true)
        guard GroupPlatform.values.contains(platform) else { throw GroupWriteValidation.error("请选择受支持的分组平台。") }
        try GroupWriteValidation.subscription(subscriptionType); try GroupWriteValidation.rpm(rpmLimit)
        try dailyLimitUSD.validate(); try weeklyLimitUSD.validate(); try monthlyLimitUSD.validate()
    }
    public func requestBody() throws -> Data { try validate(); return try GroupWriteValidation.encode(self) }
}

public struct GroupUpdateRequest: Encodable, Sendable {
    public var name: String?
    public var description: String?
    public var rateMultiplier: Decimal?
    public var isExclusive: Bool?
    public var status: String?
    public var subscriptionType: String?
    public var rpmLimit: Int?
    public var dailyLimitUSD: GroupLimitChange?
    public var weeklyLimitUSD: GroupLimitChange?
    public var monthlyLimitUSD: GroupLimitChange?
    public init(name: String? = nil, description: String? = nil, rateMultiplier: Decimal? = nil, isExclusive: Bool? = nil, status: String? = nil, subscriptionType: String? = nil, rpmLimit: Int? = nil, dailyLimitUSD: GroupLimitChange? = nil, weeklyLimitUSD: GroupLimitChange? = nil, monthlyLimitUSD: GroupLimitChange? = nil) {
        self.name = name?.trimmingCharacters(in: .whitespacesAndNewlines); self.description = description
        self.rateMultiplier = rateMultiplier; self.isExclusive = isExclusive; self.status = status; self.subscriptionType = subscriptionType
        self.rpmLimit = rpmLimit; self.dailyLimitUSD = dailyLimitUSD; self.weeklyLimitUSD = weeklyLimitUSD; self.monthlyLimitUSD = monthlyLimitUSD
    }
    enum CodingKeys: String, CodingKey {
        case name, description, status
        case rateMultiplier = "rate_multiplier", isExclusive = "is_exclusive", subscriptionType = "subscription_type", rpmLimit = "rpm_limit"
        case dailyLimitUSD = "daily_limit_usd", weeklyLimitUSD = "weekly_limit_usd", monthlyLimitUSD = "monthly_limit_usd"
    }
    public func validate() throws {
        guard name != nil || description != nil || rateMultiplier != nil || isExclusive != nil || status != nil || subscriptionType != nil || rpmLimit != nil || dailyLimitUSD != nil || weeklyLimitUSD != nil || monthlyLimitUSD != nil else {
            throw GroupWriteValidation.error("请至少修改一个分组字段。")
        }
        if let name { try GroupWriteValidation.name(name) }
        if let rateMultiplier { try GroupWriteValidation.decimal(rateMultiplier, positive: true) }
        if let status, !["active", "inactive"].contains(status) { throw GroupWriteValidation.error("无效的分组状态。") }
        if let subscriptionType { try GroupWriteValidation.subscription(subscriptionType) }
        if let rpmLimit { try GroupWriteValidation.rpm(rpmLimit) }
        try dailyLimitUSD?.validate(); try weeklyLimitUSD?.validate(); try monthlyLimitUSD?.validate()
    }
    public func requestBody() throws -> Data { try validate(); return try GroupWriteValidation.encode(self) }
    /// Reconciliation checks only submitted fields, so a concurrent unrelated edit is preserved.
    public func matches(_ group: AdminGroup) -> Bool {
        (name == nil || name == group.name) && (description == nil || description == (group.description ?? ""))
        && (rateMultiplier == nil || rateMultiplier == group.rateMultiplier) && (isExclusive == nil || isExclusive == group.isExclusive)
        && (status == nil || status == group.status) && (subscriptionType == nil || subscriptionType == group.subscriptionType)
        && (rpmLimit == nil || rpmLimit == group.rpmLimit) && matchesLimit(dailyLimitUSD, group.dailyLimitUSD)
        && matchesLimit(weeklyLimitUSD, group.weeklyLimitUSD) && matchesLimit(monthlyLimitUSD, group.monthlyLimitUSD)
    }
    private func matchesLimit(_ change: GroupLimitChange?, _ value: Decimal?) -> Bool {
        switch change { case nil: true; case .unlimited: value == nil; case .amount(let amount): value == amount }
    }
}

public struct GroupCapacitySummary: Codable, Sendable, Identifiable {
    public var id: Int { groupID }
    public let groupID: Int
    public let concurrencyUsed: Int?
    public let concurrencyMax: Int?
    public let sessionsUsed: Int?
    public let sessionsMax: Int?
    public let rpmUsed: Int?
    public let rpmMax: Int?
    enum CodingKeys: String, CodingKey {
        case groupID = "group_id", concurrencyUsed = "concurrency_used", concurrencyMax = "concurrency_max"
        case sessionsUsed = "sessions_used", sessionsMax = "sessions_max", rpmUsed = "rpm_used", rpmMax = "rpm_max"
    }
}

extension APIClient {
    public func groups(page: Int, search: String = "", platform: String? = nil, status: String? = nil) async throws -> Page<AdminGroup> {
        try await request("admin/groups", query: pagination(page, search: search, status: status) + optionalQuery("platform", platform))
    }
    /// With `includeInactive` the backend reads only the literal `true` and then ignores `platform`, so the platform is applied here.
    public func allGroups(platform: String? = nil, includeInactive: Bool = false) async throws -> [AdminGroup] {
        let inactive = includeInactive ? [URLQueryItem(name: "include_inactive", value: "true")] : []
        let groups: [AdminGroup] = try await request("admin/groups/all", query: optionalQuery("platform", platform) + inactive)
        guard includeInactive, let platform, !platform.isEmpty else { return groups }
        return groups.filter { $0.platform == platform }
    }
    public func group(id: Int) async throws -> AdminGroup { try await request("admin/groups/\(validID(id))") }
    public func groupCapacities() async throws -> [GroupCapacitySummary] { try await request("admin/groups/capacity-summary") }
    public func createGroup(_ input: GroupCreateRequest, identity: UUID) async throws -> AdminGroup {
        try checkGroupIdentity(identity)
        return try await request("admin/groups", method: "POST", body: input.requestBody())
    }
    public func updateGroup(id: Int, input: GroupUpdateRequest, identity: UUID) async throws -> AdminGroup {
        try checkGroupIdentity(identity)
        return try await request("admin/groups/\(validID(id))", method: "PUT", body: input.requestBody())
    }
    public func deleteGroup(id: Int, identity: UUID) async throws {
        try checkGroupIdentity(identity)
        let _: GroupDeleteReply = try await request("admin/groups/\(validID(id))", method: "DELETE")
    }
    private func checkGroupIdentity(_ identity: UUID) throws {
        try Task.checkCancellation()
        guard identity == userWriteIdentity() else { throw CancellationError() }
    }
}

private struct GroupDeleteReply: Decodable, Sendable { let message: String }
private enum GroupWriteValidation {
    static func error(_ message: String) -> APIError { APIError(kind: .validation, message: message) }
    static func name(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 100 else { throw error("分组名称须为 1 至 100 个字符。") }
    }
    static func decimal(_ value: Decimal, positive: Bool) throws {
        guard !value.isNaN, positive ? value > 0 : value >= 0, value <= Decimal(string: "999999999999.99999999")! else {
            throw error(positive ? "计费倍率须大于 0，且不超过 999999999999.99999999。" : "限额须为有效的非负金额。")
        }
    }
    static func subscription(_ value: String) throws {
        guard ["standard", "subscription"].contains(value) else { throw error("无效的分组计费类型。") }
    }
    static func rpm(_ value: Int) throws {
        guard value >= 0, value <= Int(Int32.max) else { throw error("RPM 限额须为 0 至 2147483647 的整数。") }
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
}
