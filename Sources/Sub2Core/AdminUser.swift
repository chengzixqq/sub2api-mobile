import Foundation

public struct AdminUser: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let email: String
    public var username: String?
    public var balance: Decimal
    public var status: String
    public var role: String?
    public var concurrency: Int?
    public var notes: String?
    public var rpmLimit: Int?
    public var currentConcurrency: Int?
    public var createdAt: String?
    public var updatedAt: String?
    public var lastUsedAt: String?
    public var lastActiveAt: String?
    // 30 §1.2 and §6: read leniently, so a server before these fields, or a malformed one, reads as nil (S3-01).
    public var totalRecharged: Decimal?
    /// nil: no own threshold, the global reminder applies.
    public var balanceNotifyThreshold: Decimal?
    /// "fixed" or "percentage" (of `totalRecharged`).
    public var balanceNotifyThresholdType: String?
    public var allowedGroups: [Int]?
    /// Exclusive rates by group id; the wire keys are decimal strings, and an entry with a bad key or rate is dropped.
    public var groupRates: [Int: Decimal]?
    public var restrictPublicGroups: Bool?
    public init(id: Int, email: String, username: String? = nil, balance: Decimal = 0, status: String = "active", role: String? = nil, concurrency: Int? = nil, notes: String? = nil, rpmLimit: Int? = nil, currentConcurrency: Int? = nil, createdAt: String? = nil, updatedAt: String? = nil, lastUsedAt: String? = nil, lastActiveAt: String? = nil,
                totalRecharged: Decimal? = nil, balanceNotifyThreshold: Decimal? = nil, balanceNotifyThresholdType: String? = nil, allowedGroups: [Int]? = nil,
                groupRates: [Int: Decimal]? = nil, restrictPublicGroups: Bool? = nil) {
        self.id = id; self.email = email; self.username = username; self.balance = balance; self.status = status; self.role = role; self.concurrency = concurrency
        self.notes = notes; self.rpmLimit = rpmLimit; self.currentConcurrency = currentConcurrency
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.lastUsedAt = lastUsedAt; self.lastActiveAt = lastActiveAt
        self.totalRecharged = totalRecharged; self.balanceNotifyThreshold = balanceNotifyThreshold; self.balanceNotifyThresholdType = balanceNotifyThresholdType
        self.allowedGroups = allowedGroups; self.groupRates = groupRates; self.restrictPublicGroups = restrictPublicGroups
    }
    enum CodingKeys: String, CodingKey {
        case id, email, username, balance, status, role, concurrency, notes
        case rpmLimit = "rpm_limit", currentConcurrency = "current_concurrency"
        case createdAt = "created_at", updatedAt = "updated_at", lastUsedAt = "last_used_at", lastActiveAt = "last_active_at"
        case totalRecharged = "total_recharged", balanceNotifyThreshold = "balance_notify_threshold"
        case balanceNotifyThresholdType = "balance_notify_threshold_type", allowedGroups = "allowed_groups", groupRates = "group_rates"
        case restrictPublicGroups = "restrict_public_groups"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); email = try c.decode(String.self, forKey: .email)
        username = try c.decodeIfPresent(String.self, forKey: .username); balance = try c.decimal(.balance)
        status = try c.decode(String.self, forKey: .status); role = try c.decodeIfPresent(String.self, forKey: .role)
        concurrency = try c.decodeIfPresent(Int.self, forKey: .concurrency)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        rpmLimit = try c.decodeIfPresent(Int.self, forKey: .rpmLimit)
        currentConcurrency = try c.decodeIfPresent(Int.self, forKey: .currentConcurrency)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        lastUsedAt = try c.decodeIfPresent(String.self, forKey: .lastUsedAt)
        lastActiveAt = try c.decodeIfPresent(String.self, forKey: .lastActiveAt)
        totalRecharged = try? c.optionalDecimal(.totalRecharged)
        balanceNotifyThreshold = try? c.optionalDecimal(.balanceNotifyThreshold)
        balanceNotifyThresholdType = try? c.decodeIfPresent(String.self, forKey: .balanceNotifyThresholdType)
        allowedGroups = try? c.decodeIfPresent([Int].self, forKey: .allowedGroups)
        groupRates = (try? c.decodeIfPresent([String: LenientValue<Decimal>].self, forKey: .groupRates)).map(Self.groupRates)
        restrictPublicGroups = try? c.decodeIfPresent(Bool.self, forKey: .restrictPublicGroups)
    }
    private static func groupRates(_ raw: [String: LenientValue<Decimal>]) -> [Int: Decimal] {
        let pairs = raw.compactMap { key, rate -> (Int, Decimal)? in
            guard let id = Int(key), id > 0, let value = rate.value else { return nil }
            return (id, value)
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}

extension AdminUser {
    /// 30 §0.3: the trimmed username, otherwise the part of the email before “@”.
    public var displayName: String { UserPresentation.displayName(username: username, email: email) }
}

public struct UserUsageSummary: Codable, Sendable {
    public let totalRequests: Int
    public let totalTokens: Int
    public let totalCost: Decimal
    public init(totalRequests: Int, totalTokens: Int, totalCost: Decimal) { self.totalRequests = totalRequests; self.totalTokens = totalTokens; self.totalCost = totalCost }
    enum CodingKeys: String, CodingKey { case totalRequests = "total_requests", totalTokens = "total_tokens", totalCost = "total_cost" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalRequests = try c.decode(Int.self, forKey: .totalRequests); totalTokens = try c.decode(Int.self, forKey: .totalTokens); totalCost = try c.decimal(.totalCost)
    }
}
/// The user embedded in a key (50 §6.3) or a subscription (50 §7.3); a field that is missing or malformed reads as nil.
public struct AdminUserSummary: Decodable, Sendable, Equatable {
    public let id: Int?
    public let email: String?
    public let username: String?
    public let status: String?
    public init(id: Int? = nil, email: String? = nil, username: String? = nil, status: String? = nil) {
        self.id = id; self.email = email; self.username = username; self.status = status
    }
    enum CodingKeys: String, CodingKey { case id, email, username, status }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: key) }
        self.init(id: try? c.decodeIfPresent(Int.self, forKey: .id), email: text(.email), username: text(.username), status: text(.status))
    }
}

/// One field read on its own: missing, null or malformed reads as nil instead of failing the reply (00 §5 rule 2). Unlike
/// `Lossy` it decodes through the container, so a JSON number decodes as Decimal.
struct LenientValue<Value: Decodable & Sendable>: Decodable, Sendable {
    let value: Value?
    init(from decoder: any Decoder) throws { value = try? decoder.singleValueContainer().decode(Value.self) }
}
