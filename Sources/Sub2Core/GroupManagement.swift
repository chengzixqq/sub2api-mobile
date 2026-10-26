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
    /// `error_account_count` / `idle_account_count` (F04): a missing key is nil, an older server whose buckets S5-02 counts
    /// itself; a present 0 is 0.
    public var errorAccountCount: Int?
    public var idleAccountCount: Int?
    /// `claude_code_only`; simple-mode replies leave it out.
    public var claudeCodeOnly: Bool?
    /// `fallback_group_id`; null and missing are both nil.
    public var fallbackGroupID: Int?

    public init(id: Int, name: String, description: String? = nil, platform: String = "openai", status: String = "active", rateMultiplier: Decimal? = 1, isExclusive: Bool? = false, subscriptionType: String? = "standard", dailyLimitUSD: Decimal? = nil, weeklyLimitUSD: Decimal? = nil, monthlyLimitUSD: Decimal? = nil, rpmLimit: Int? = 0, accountCount: Int? = nil, activeAccountCount: Int? = nil, rateLimitedAccountCount: Int? = nil, billingLocked: Bool? = nil, createdAt: String? = nil, updatedAt: String? = nil, sortOrder: Int? = nil, errorAccountCount: Int? = nil, idleAccountCount: Int? = nil, claudeCodeOnly: Bool? = nil, fallbackGroupID: Int? = nil) {
        self.id = id; self.name = name; self.description = description; self.platform = platform; self.status = status
        self.rateMultiplier = rateMultiplier; self.isExclusive = isExclusive; self.subscriptionType = subscriptionType
        self.dailyLimitUSD = dailyLimitUSD; self.weeklyLimitUSD = weeklyLimitUSD; self.monthlyLimitUSD = monthlyLimitUSD
        self.rpmLimit = rpmLimit; self.accountCount = accountCount; self.activeAccountCount = activeAccountCount
        self.rateLimitedAccountCount = rateLimitedAccountCount; self.billingLocked = billingLocked
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.sortOrder = sortOrder
        self.errorAccountCount = errorAccountCount; self.idleAccountCount = idleAccountCount
        self.claudeCodeOnly = claudeCodeOnly; self.fallbackGroupID = fallbackGroupID
    }
    enum CodingKeys: String, CodingKey {
        case id, name, description, platform, status
        case rateMultiplier = "rate_multiplier", isExclusive = "is_exclusive", subscriptionType = "subscription_type"
        case dailyLimitUSD = "daily_limit_usd", weeklyLimitUSD = "weekly_limit_usd", monthlyLimitUSD = "monthly_limit_usd"
        case rpmLimit = "rpm_limit", accountCount = "account_count", activeAccountCount = "active_account_count"
        case rateLimitedAccountCount = "rate_limited_account_count", billingLocked = "billing_locked"
        case createdAt = "created_at", updatedAt = "updated_at", sortOrder = "sort_order"
        case errorAccountCount = "error_account_count", idleAccountCount = "idle_account_count"
        case claudeCodeOnly = "claude_code_only", fallbackGroupID = "fallback_group_id"
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
        errorAccountCount = try c.decodeIfPresent(Int.self, forKey: .errorAccountCount); idleAccountCount = try c.decodeIfPresent(Int.self, forKey: .idleAccountCount)
        claudeCodeOnly = try c.decodeIfPresent(Bool.self, forKey: .claudeCodeOnly); fallbackGroupID = try c.decodeIfPresent(Int.self, forKey: .fallbackGroupID)
    }
}
extension AdminGroup {
    /// The backend's order (ListActive / ListWithFilters): sort_order ascending, a missing one as 0, then id.
    /// Use as `groups.sorted(by: AdminGroup.displayOrder)`.
    public static func displayOrder(_ lhs: AdminGroup, _ rhs: AdminGroup) -> Bool {
        (lhs.sortOrder ?? 0, lhs.id) < (rhs.sortOrder ?? 0, rhs.id)
    }
    /// The bucket inputs in the member batch reply's shape; the omitempty counts read as 0 (00 §6.5).
    public var counts: GroupAccountCounts {
        GroupAccountCounts(accountCount: accountCount ?? 0, activeAccountCount: activeAccountCount ?? 0, rateLimitedAccountCount: rateLimitedAccountCount ?? 0,
                           errorAccountCount: errorAccountCount, idleAccountCount: idleAccountCount)
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
    /// New groups only (50 §3.2): composite groups are created on the web. Same order as `values`.
    public static let concrete = values.filter { $0 != "composite" }
}

/// The four buckets' inputs: AdminGroup.counts and the member batch reply's `counts` (same keys). Account, active and
/// rate-limited are omitempty on the group DTO, so missing is 0 (00 §6.5); error and idle stay nil on a server without F04.
public struct GroupAccountCounts: Codable, Sendable, Equatable {
    public let accountCount: Int
    public let activeAccountCount: Int
    public let rateLimitedAccountCount: Int
    public let errorAccountCount: Int?
    public let idleAccountCount: Int?
    public init(accountCount: Int = 0, activeAccountCount: Int = 0, rateLimitedAccountCount: Int = 0, errorAccountCount: Int? = nil, idleAccountCount: Int? = nil) {
        self.accountCount = accountCount; self.activeAccountCount = activeAccountCount; self.rateLimitedAccountCount = rateLimitedAccountCount
        self.errorAccountCount = errorAccountCount; self.idleAccountCount = idleAccountCount
    }
    enum CodingKeys: String, CodingKey {
        case accountCount = "account_count", activeAccountCount = "active_account_count", rateLimitedAccountCount = "rate_limited_account_count"
        case errorAccountCount = "error_account_count", idleAccountCount = "idle_account_count"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(accountCount: c.decodeIfPresent(Int.self, forKey: .accountCount) ?? 0,
                      activeAccountCount: c.decodeIfPresent(Int.self, forKey: .activeAccountCount) ?? 0,
                      rateLimitedAccountCount: c.decodeIfPresent(Int.self, forKey: .rateLimitedAccountCount) ?? 0,
                      errorAccountCount: c.decodeIfPresent(Int.self, forKey: .errorAccountCount),
                      idleAccountCount: c.decodeIfPresent(Int.self, forKey: .idleAccountCount))
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
    public init(name: String, description: String = "", platform: String = "anthropic", rateMultiplier: Decimal = 1, isExclusive: Bool = false, subscriptionType: String = "standard", rpmLimit: Int = 0, dailyLimitUSD: GroupLimitChange = .unlimited, weeklyLimitUSD: GroupLimitChange = .unlimited, monthlyLimitUSD: GroupLimitChange = .unlimited) {
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
        guard GroupPlatform.concrete.contains(platform) else { throw GroupWriteValidation.error("请选择受支持的分组平台。") }
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
    /// capacity-summary takes at most this many ids (00 §4.5).
    static let idsPerRequest = 100
}

/// One row of `GET admin/groups/usage-summary`: the actual charge of a group.
public struct GroupUsageSummary: Decodable, Sendable, Equatable, Identifiable {
    public var id: Int { groupID }
    public let groupID: Int
    public let todayCost: Decimal?
    public let yesterdayCost: Decimal?
    public let totalCost: Decimal?
    public init(groupID: Int, todayCost: Decimal?, yesterdayCost: Decimal?, totalCost: Decimal?) {
        self.groupID = groupID; self.todayCost = todayCost; self.yesterdayCost = yesterdayCost; self.totalCost = totalCost
    }
    enum CodingKeys: String, CodingKey { case groupID = "group_id", todayCost = "today_cost", yesterdayCost = "yesterday_cost", totalCost = "total_cost" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(groupID: c.decode(Int.self, forKey: .groupID), todayCost: c.optionalDecimal(.todayCost),
                      yesterdayCost: c.optionalDecimal(.yesterdayCost), totalCost: c.optionalDecimal(.totalCost))
    }
}
/// `GET admin/groups/:id/stats` (F02). total_requests is always 0 and total_cost is not shown, so neither is read.
public struct GroupStats: Decodable, Sendable, Equatable {
    public let totalAPIKeys: Int
    public let activeAPIKeys: Int
    public let subscriptionsTotal: Int
    public let subscriptionsActive: Int
    public init(totalAPIKeys: Int, activeAPIKeys: Int, subscriptionsTotal: Int, subscriptionsActive: Int) {
        self.totalAPIKeys = totalAPIKeys; self.activeAPIKeys = activeAPIKeys; self.subscriptionsTotal = subscriptionsTotal; self.subscriptionsActive = subscriptionsActive
    }
    enum CodingKeys: String, CodingKey {
        case totalAPIKeys = "total_api_keys", activeAPIKeys = "active_api_keys"
        case subscriptionsTotal = "subscriptions_total", subscriptionsActive = "subscriptions_active"
    }
}
/// One group's requests, tokens and account cost today (`admin/dashboard/groups`); `cost` is the standard price and is not read.
public struct GroupTodayUsage: Sendable, Equatable {
    public let requests: Int
    public let totalTokens: Int
    public let accountCost: Decimal?
    public init(requests: Int, totalTokens: Int, accountCost: Decimal?) { self.requests = requests; self.totalTokens = totalTokens; self.accountCost = accountCost }
    /// No row: the group had no request today, a real zero.
    public static let zero = GroupTodayUsage(requests: 0, totalTokens: 0, accountCost: 0)
}
/// 50 §1.2: past 1000 groups `groupList` pages on, up to this many pages.
enum GroupListPolicy { static let maxPages = 20 }

extension APIClient {
    /// The one group list read (X26): `groupList` asks 1000 a page, global search 5.
    public func groups(page: Int, pageSize: Int = PageSize.standard, search: String = "", platform: String? = nil, status: String? = nil) async throws -> Page<AdminGroup> {
        try await request("admin/groups", query: pagination(page, pageSize: pageSize, search: search, status: status) + optionalQuery("platform", platform))
    }
    /// With `includeInactive` the backend reads only the literal `true` and then ignores `platform`, so the platform is applied here.
    public func allGroups(platform: String? = nil, includeInactive: Bool = false) async throws -> [AdminGroup] {
        let inactive = includeInactive ? [URLQueryItem(name: "include_inactive", value: "true")] : []
        let groups: [AdminGroup] = try await request("admin/groups/all", query: optionalQuery("platform", platform) + inactive)
        guard includeInactive, let platform, !platform.isEmpty else { return groups }
        return groups.filter { $0.platform == platform }
    }
    public func group(id: Int) async throws -> AdminGroup { try await request("admin/groups/\(validID(id))") }
    /// 50 §1.2: every group in the server's order (sort_order, id) and of every status, 1000 a page while fewer than `total`
    /// have arrived, at most GroupListPolicy.maxPages pages; a repeated id keeps its first row. ETag / 304 stay inside the
    /// conditional cache (R08), and pages of two sessions are never joined.
    public func groupList() async throws -> [AdminGroup] {
        let snapshot = currentGeneration()
        var collected = [AdminGroup](), seen = Set<Int>()
        for number in 1...GroupListPolicy.maxPages {
            let page = try await groups(page: number, pageSize: PageSize.maximum)
            try check(snapshot)
            for group in page.items where seen.insert(group.id).inserted { collected.append(group) }
            guard !page.items.isEmpty, page.total.map({ collected.count < $0 }) ?? page.hasMore else { break }
        }
        return collected
    }
    /// The vendor passes the site's zone; the site owner passes nil and the server uses its own (50 §1.2).
    public func groupUsageSummary(timezone: ServerTimeZone? = nil) async throws -> [GroupUsageSummary] {
        try await request("admin/groups/usage-summary", query: optionalQuery("timezone", timezone?.identifier), timeout: RequestTimeout.aggregate)
    }
    /// The one capacity read (R19). Ids go out positive, unique and ascending (00 §4.5). With `serverFiltered` (the caller's
    /// groups.capacity_filter) each id is a `group_id`, at most 100 a request, split once on TOO_MANY_IDS; without it one
    /// unfiltered request. Either way only the requested groups are kept, since an older server ignores the parameter.
    /// A disabled group has no row.
    public func groupCapacities(groupIDs: [Int], serverFiltered: Bool) async throws -> [GroupCapacitySummary] {
        let requested = AccountBatchIDs.normalized(groupIDs)
        guard !requested.isEmpty else { return [] }
        guard serverFiltered else {
            let wanted = Set(requested)
            let rows: [GroupCapacitySummary] = try await request("admin/groups/capacity-summary")
            return rows.filter { wanted.contains($0.groupID) }
        }
        let matched = try await readInBatches(requested, size: GroupCapacitySummary.idsPerRequest) { chunk in
            let wanted = Set(chunk)
            let rows: [GroupCapacitySummary] = try await request("admin/groups/capacity-summary", query: chunk.map { URLQueryItem(name: "group_id", value: String($0)) })
            return Dictionary(rows.filter { wanted.contains($0.groupID) }.map { ($0.groupID, $0) }) { first, _ in first }
        }
        return requested.compactMap { matched[$0] }
    }
    /// F02: nil when the reply has no `subscriptions_total` (an older server's all-zero placeholder); the caller then reads
    /// groupAPIKeyCount and activeSubscriptionCount.
    public func groupStats(id: Int) async throws -> GroupStats? {
        let reply: GroupStatsReply = try await request("admin/groups/\(validID(id))/stats")
        return reply.stats
    }
    /// 50 §2.2 fallback, `total` only. `maskedView` is the caller's api_keys.masked_view; an older server sends plain keys,
    /// which never reach a model.
    public func groupAPIKeyCount(id: Int, maskedView: Bool) async throws -> Int {
        let view = maskedView ? [URLQueryItem(name: "key_view", value: "masked")] : []
        let reply: PageTotal = try await request("admin/groups/\(validID(id))/api-keys", query: pagination(1, pageSize: 1, search: "", status: nil) + view)
        return reply.total
    }
    /// 50 §2.2 fallback: the group's active subscriptions, `total` only.
    public func activeSubscriptionCount(groupID: Int) async throws -> Int {
        let group = try validID(groupID)
        let reply: PageTotal = try await request("admin/subscriptions", query: pagination(1, pageSize: 1, search: "", status: "active")
                                                 + [URLQueryItem(name: "group_id", value: String(group))])
        return reply.total
    }
    /// 50 §2.2: start_date = end_date = today on the server's calendar (00 §2.8). No row means no request today, a real zero.
    public func groupTodayUsage(id: Int, serverTimeZone zone: ServerTimeZone? = nil) async throws -> GroupTodayUsage {
        struct Reply: Decodable, Sendable { let groups: [AnalyticsBreakdown]? }
        let groupID = try validID(id), now = serverClock.now()
        let day = (zone ?? serverTimeZone()).dayQueryItems(from: now, to: now)
        let reply: Reply = try await request("admin/dashboard/groups", query: day + [URLQueryItem(name: "group_id", value: String(groupID))],
                                             timeout: RequestTimeout.aggregate)
        guard let row = reply.groups?.first(where: { $0.groupID == groupID }) else { return .zero }
        return GroupTodayUsage(requests: row.requests, totalTokens: row.tokens, accountCost: row.accountCost)
    }
}

/// F02 is told by the `subscriptions_total` key, not by a capability.
private struct GroupStatsReply: Decodable, Sendable {
    let stats: GroupStats?
    init(from decoder: any Decoder) throws {
        guard try decoder.container(keyedBy: GroupStats.CodingKeys.self).contains(.subscriptionsTotal) else { stats = nil; return }
        stats = try GroupStats(from: decoder)
    }
}
/// A page whose items are never decoded.
private struct PageTotal: Decodable, Sendable { let total: Int }
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
