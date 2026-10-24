import Foundation

/// D02 buckets (account_status_summary.go). `stopped` also sits in its timed bucket, so it is not added to the other counts.
public struct AccountStateCounts: Decodable, Sendable, Equatable {
    public let total, available, error, overloaded, rateLimited, tempUnschedulable, paused, inactive, stopped: Int
    /// 20 §0.2 需处理.
    public var needsAttention: Int { error + limited }
    /// 20 §0.2 受限.
    public var limited: Int { overloaded + rateLimited + tempUnschedulable }

    public init(total: Int = 0, available: Int = 0, error: Int = 0, overloaded: Int = 0, rateLimited: Int = 0, tempUnschedulable: Int = 0,
                paused: Int = 0, inactive: Int = 0, stopped: Int = 0) {
        self.total = total; self.available = available; self.error = error; self.overloaded = overloaded; self.rateLimited = rateLimited
        self.tempUnschedulable = tempUnschedulable; self.paused = paused; self.inactive = inactive; self.stopped = stopped
    }
    enum CodingKeys: String, CodingKey {
        case total, available, error, overloaded, paused, inactive, stopped
        case rateLimited = "rate_limited", tempUnschedulable = "temp_unschedulable"
    }
    /// Also read flat from a platform or group row, which embeds the counts next to its own keys.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0 }
        self.init(total: count(.total), available: count(.available), error: count(.error), overloaded: count(.overloaded),
                  rateLimited: count(.rateLimited), tempUnschedulable: count(.tempUnschedulable), paused: count(.paused),
                  inactive: count(.inactive), stopped: count(.stopped))
    }
}

public struct AccountStatusPlatformSummary: Decodable, Sendable, Equatable, Identifiable {
    public let platform: String
    public let counts: AccountStateCounts
    public var id: String { platform }
    public init(platform: String, counts: AccountStateCounts = .init()) { self.platform = platform; self.counts = counts }
    enum CodingKeys: String, CodingKey { case platform }
    public init(from decoder: any Decoder) throws {
        platform = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .platform)
        counts = try AccountStateCounts(from: decoder)
    }
}

public struct AccountStatusGroupSummary: Decodable, Sendable, Equatable, Identifiable {
    /// The raw numbers: `current` is a 0–1 ratio for `default`, a 0–100 percentage for an `alert_rule` on
    /// `group_available_ratio`, and an account count for `group_available_accounts`. The page formats by source.
    public struct Shortage: Decodable, Sendable, Equatable {
        public let isShort: Bool
        /// `alert_rule` or `default`.
        public let source: String?
        public let ruleID: Int?
        public let metricType: String?
        /// JSON `operator`.
        public let comparison: String?
        public let threshold: Double?
        public let current: Double?
        public var isFromAlertRule: Bool { source == "alert_rule" }
        public init(isShort: Bool = false, source: String? = nil, ruleID: Int? = nil, metricType: String? = nil, comparison: String? = nil,
                    threshold: Double? = nil, current: Double? = nil) {
            self.isShort = isShort; self.source = source; self.ruleID = ruleID; self.metricType = metricType
            self.comparison = comparison; self.threshold = threshold; self.current = current
        }
        enum CodingKeys: String, CodingKey {
            case source, threshold, current
            case isShort = "is_short", ruleID = "rule_id", metricType = "metric_type", comparison = "operator"
        }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(isShort: (try? c.decodeIfPresent(Bool.self, forKey: .isShort)) ?? false,
                      source: try? c.decodeIfPresent(String.self, forKey: .source), ruleID: try? c.decodeIfPresent(Int.self, forKey: .ruleID),
                      metricType: try? c.decodeIfPresent(String.self, forKey: .metricType),
                      comparison: try? c.decodeIfPresent(String.self, forKey: .comparison),
                      threshold: try? c.decodeIfPresent(Double.self, forKey: .threshold), current: try? c.decodeIfPresent(Double.self, forKey: .current))
        }
    }
    public let groupID: Int
    public let groupName: String
    public let platform: String
    public let groupStatus: String
    public let counts: AccountStateCounts
    public let shortage: Shortage
    public var id: Int { groupID }
    public init(groupID: Int, groupName: String = "", platform: String = "", groupStatus: String = "active", counts: AccountStateCounts = .init(),
                shortage: Shortage = .init()) {
        self.groupID = groupID; self.groupName = groupName; self.platform = platform; self.groupStatus = groupStatus
        self.counts = counts; self.shortage = shortage
    }
    enum CodingKeys: String, CodingKey { case platform, shortage; case groupID = "group_id", groupName = "group_name", groupStatus = "group_status" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groupID = try c.decode(Int.self, forKey: .groupID)
        groupName = c.lenientString(.groupName); platform = c.lenientString(.platform); groupStatus = c.lenientString(.groupStatus)
        counts = try AccountStateCounts(from: decoder)
        shortage = (try? c.decodeIfPresent(Shortage.self, forKey: .shortage)) ?? .init()
    }
}

/// One `accounts[]` row. `error_message` is not decoded (R12: never shown, so not kept either); `expires_at` is RFC3339 here,
/// unlike the account DTO's Unix seconds, and there is no `auto_pause_on_expired` or C02 field.
public struct AccountStatusItem: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let platform: String
    public let groupIDs: [Int]
    /// The server's D02 state; an unknown value is nil.
    public let state: AccountScheduleState?
    public let stopped: Bool
    public let status: String
    public let schedulable: Bool
    public let rateLimitResetAt: Date?
    public let overloadUntil: Date?
    public let tempUnschedulableUntil: Date?
    public let tempUnschedulableReason: String?
    public let expiresAt: Date?
    public let modelRateLimits: [AccountModelRateLimit]

    public init(id: Int, name: String = "", platform: String = "", groupIDs: [Int] = [], state: AccountScheduleState? = nil, stopped: Bool = false,
                status: String = "active", schedulable: Bool = true, rateLimitResetAt: Date? = nil, overloadUntil: Date? = nil,
                tempUnschedulableUntil: Date? = nil, tempUnschedulableReason: String? = nil, expiresAt: Date? = nil,
                modelRateLimits: [AccountModelRateLimit] = []) {
        self.id = id; self.name = name; self.platform = platform; self.groupIDs = groupIDs; self.state = state; self.stopped = stopped
        self.status = status; self.schedulable = schedulable; self.rateLimitResetAt = rateLimitResetAt; self.overloadUntil = overloadUntil
        self.tempUnschedulableUntil = tempUnschedulableUntil; self.tempUnschedulableReason = tempUnschedulableReason
        self.expiresAt = expiresAt; self.modelRateLimits = modelRateLimits
    }
    enum CodingKeys: String, CodingKey {
        case id, name, platform, state, stopped, status, schedulable
        case groupIDs = "group_ids", rateLimitResetAt = "rate_limit_reset_at", overloadUntil = "overload_until"
        case tempUnschedulableUntil = "temp_unschedulable_until", tempUnschedulableReason = "temp_unschedulable_reason"
        case expiresAt = "expires_at", modelRateLimits = "model_rate_limits"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(Int.self, forKey: .id), name: c.lenientString(.name), platform: c.lenientString(.platform),
                      groupIDs: (try? c.decodeIfPresent([Int].self, forKey: .groupIDs)) ?? [],
                      state: (try? c.decodeIfPresent(String.self, forKey: .state)).flatMap { AccountScheduleState(rawValue: $0) },
                      stopped: (try? c.decodeIfPresent(Bool.self, forKey: .stopped)) ?? false, status: c.lenientString(.status),
                      schedulable: (try? c.decodeIfPresent(Bool.self, forKey: .schedulable)) ?? false,
                      rateLimitResetAt: c.optionalTimestamp(.rateLimitResetAt), overloadUntil: c.optionalTimestamp(.overloadUntil),
                      tempUnschedulableUntil: c.optionalTimestamp(.tempUnschedulableUntil),
                      tempUnschedulableReason: try? c.decodeIfPresent(String.self, forKey: .tempUnschedulableReason),
                      expiresAt: c.optionalTimestamp(.expiresAt), modelRateLimits: c.lossyList(ModelLimitRow.self, .modelRateLimits).map(\.value))
    }
}

/// `GET admin/accounts/status-summary` (20 §10.1). The same model reads the `availability` block of `dashboard/home`
/// (no `platforms`, with `accounts_truncated`), so the overview does not need its own count types.
public struct AccountStatusSummary: Decodable, Sendable, Equatable {
    public let collectedAt: Date?
    public let totals: AccountStateCounts
    public let platforms: [AccountStatusPlatformSummary]
    public let groups: [AccountStatusGroupSummary]
    /// The backend omits an empty list, so “not requested” and “none” both read as [].
    public let accounts: [AccountStatusItem]
    /// Only `dashboard/home` availability sends it.
    public let accountsTruncated: Bool

    public init(collectedAt: Date? = nil, totals: AccountStateCounts = .init(), platforms: [AccountStatusPlatformSummary] = [],
                groups: [AccountStatusGroupSummary] = [], accounts: [AccountStatusItem] = [], accountsTruncated: Bool = false) {
        self.collectedAt = collectedAt; self.totals = totals; self.platforms = platforms; self.groups = groups
        self.accounts = accounts; self.accountsTruncated = accountsTruncated
    }
    enum CodingKeys: String, CodingKey {
        case totals, platforms, groups, accounts
        case collectedAt = "collected_at", accountsTruncated = "accounts_truncated"
    }
    /// One unreadable row is dropped rather than losing the badge and every group head.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(collectedAt: c.optionalTimestamp(.collectedAt),
                      totals: (try? c.decodeIfPresent(AccountStateCounts.self, forKey: .totals)) ?? .init(),
                      platforms: c.lossyList(AccountStatusPlatformSummary.self, .platforms),
                      groups: c.lossyList(AccountStatusGroupSummary.self, .groups), accounts: c.lossyList(AccountStatusItem.self, .accounts),
                      accountsTruncated: (try? c.decodeIfPresent(Bool.self, forKey: .accountsTruncated)) ?? false)
    }
}

/// `{model, reset_at}`; a row without a model or a readable time is dropped.
private struct ModelLimitRow: Decodable {
    let value: AccountModelRateLimit
    enum CodingKeys: String, CodingKey { case model; case resetAt = "reset_at" }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let model = try c.decode(String.self, forKey: .model)
        guard let resetAt = try c.optionalTimestamp(.resetAt) else { throw APIError.invalidResponse }
        value = AccountModelRateLimit(model: model, resetAt: resetAt)
    }
}

extension KeyedDecodingContainer {
    /// Missing, null or not an array is []; each unreadable element is skipped.
    func lossyList<Value: Decodable>(_ type: Value.Type, _ key: Key) -> [Value] {
        ((try? decodeIfPresent([Lossy<Value>].self, forKey: key)) ?? []).compactMap(\.value)
    }
    func lenientString(_ key: Key) -> String { (try? decodeIfPresent(String.self, forKey: key)) ?? "" }
}

extension APIClient {
    /// 20 §10.1, R19: the only definition; overview, accounts and groups share it. Callers gate it with
    /// `Capability.accountsStatusSummary`; an old site's non-JSON 404 arrives as `.unsupported`. Not conditional (00 §4.2).
    public func accountStatusSummary(platform: String? = nil, groupID: Int? = nil, includeAccounts: Bool = false) async throws -> AccountStatusSummary {
        var query = optionalQuery("platform", platform?.trimmingCharacters(in: .whitespacesAndNewlines))
        if let groupID {
            let id = try validID(groupID) // The backend answers 0 and negatives with INVALID_GROUP_FILTER.
            query.append(URLQueryItem(name: "group_id", value: String(id)))
        }
        if includeAccounts { query.append(URLQueryItem(name: "include_accounts", value: "true")) }
        return try await request("admin/accounts/status-summary", query: query)
    }
}
