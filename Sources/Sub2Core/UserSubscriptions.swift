import Foundation

/// 50 §7.7: one subscription, read for a user here and for a group by S5-12; the compensation wizard (S6-08, S6-09) reuses
/// it. `id` is required; any other field that is missing or malformed reads as nil.
public struct AdminUserSubscription: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let userID: Int?
    public let groupID: Int?
    public let startsAt: Date?
    public let expiresAt: Date?
    /// active / expired / suspended; the server marks a lapsed active one expired and zeroes expired windows before replying.
    public let status: String?
    public let dailyUsageUSD: Decimal?
    public let weeklyUsageUSD: Decimal?
    public let monthlyUsageUSD: Decimal?
    public let user: AdminUserSummary?
    public init(id: Int, userID: Int? = nil, groupID: Int? = nil, startsAt: Date? = nil, expiresAt: Date? = nil, status: String? = nil,
                dailyUsageUSD: Decimal? = nil, weeklyUsageUSD: Decimal? = nil, monthlyUsageUSD: Decimal? = nil, user: AdminUserSummary? = nil) {
        self.id = id; self.userID = userID; self.groupID = groupID; self.startsAt = startsAt; self.expiresAt = expiresAt; self.status = status
        self.dailyUsageUSD = dailyUsageUSD; self.weeklyUsageUSD = weeklyUsageUSD; self.monthlyUsageUSD = monthlyUsageUSD; self.user = user
    }
    enum CodingKeys: String, CodingKey {
        case id, status, user
        case userID = "user_id", groupID = "group_id", startsAt = "starts_at", expiresAt = "expires_at"
        case dailyUsageUSD = "daily_usage_usd", weeklyUsageUSD = "weekly_usage_usd", monthlyUsageUSD = "monthly_usage_usd"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys) -> Int? { try? c.decodeIfPresent(Int.self, forKey: key) }
        func time(_ key: CodingKeys) -> Date? { try? c.optionalTimestamp(key) }
        func amount(_ key: CodingKeys) -> Decimal? { try? c.optionalDecimal(key) }
        self.init(id: try c.decode(Int.self, forKey: .id), userID: number(.userID), groupID: number(.groupID), startsAt: time(.startsAt),
                  expiresAt: time(.expiresAt), status: try? c.decodeIfPresent(String.self, forKey: .status),
                  dailyUsageUSD: amount(.dailyUsageUSD), weeklyUsageUSD: amount(.weeklyUsageUSD), monthlyUsageUSD: amount(.monthlyUsageUSD),
                  user: try? c.decodeIfPresent(AdminUserSummary.self, forKey: .user))
    }
}

extension APIClient {
    /// 30 §7.2 subscription-group choices: every subscription of the user, not paged.
    public func userSubscriptions(userID: Int) async throws -> [AdminUserSubscription] {
        try await request("admin/users/\(validID(userID))/subscriptions")
    }
}
