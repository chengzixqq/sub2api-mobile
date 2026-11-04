import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One `dashboard/accounts-ranking` row (20 §10.2). `actualCost` is what users were charged, the same measure as today-stats'
/// `user_cost`; the other money and token fields are not kept until a page needs them.
public struct AccountsRankingItem: Decodable, Sendable, Equatable, Identifiable {
    /// The server rejects ≤ 0 and caps at 50.
    public static let limitRange: ClosedRange<Int> = 1...50
    public let accountID: Int
    public let accountName: String
    public let platform: String
    public let requests: Int
    public let actualCost: Decimal
    public var id: Int { accountID }

    public init(accountID: Int, accountName: String = "", platform: String = "", requests: Int = 0, actualCost: Decimal = 0) {
        self.accountID = accountID; self.accountName = accountName; self.platform = platform; self.requests = requests; self.actualCost = actualCost
    }
    enum CodingKeys: String, CodingKey { case platform, requests; case accountID = "account_id", accountName = "account_name", actualCost = "actual_cost" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(accountID: c.decode(Int.self, forKey: .accountID), accountName: c.lenientString(.accountName), platform: c.lenientString(.platform),
                      requests: c.decodeIfPresent(Int.self, forKey: .requests) ?? 0, actualCost: c.optionalDecimal(.actualCost) ?? 0)
    }
}

/// Only `ranking` is read; the totals, dates and query echo are ignored.
private struct AccountsRankingReply: Decodable, Sendable {
    let ranking: [AccountsRankingItem]
    enum CodingKeys: String, CodingKey { case ranking }
    init(from decoder: any Decoder) throws {
        ranking = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([AccountsRankingItem].self, forKey: .ranking) ?? []
    }
}

extension APIClient {
    /// 20 §10.2, R19: the only definition (calm overview, later the simple mode). Today in `timezone`, highest actual cost first;
    /// no ETag, aggregate timeout. A zone the server cannot load is a 400 without a reason (usagequery.ParseRange); nothing but
    /// the clamped limit and the zone is sent, so that 400 can only be the zone and the read goes once more without it.
    public func accountsRanking(limit: Int = 4, timezone: ServerTimeZone) async throws -> [AccountsRankingItem] {
        let path = "admin/dashboard/accounts-ranking", range = AccountsRankingItem.limitRange
        let limitItem = URLQueryItem(name: "limit", value: String(min(max(limit, range.lowerBound), range.upperBound)))
        let reply: AccountsRankingReply
        do {
            reply = try await request(path, query: [limitItem, URLQueryItem(name: "timezone", value: timezone.identifier)], timeout: RequestTimeout.aggregate)
        } catch let error as APIError where error.statusCode == 400 && (error.reason ?? "").isEmpty {
            DashboardLog.resending(path, without: "timezone", reason: "-")
            reply = try await request(path, query: [limitItem], timeout: RequestTimeout.aggregate)
        }
        return reply.ranking
    }
}
