import Foundation

/// One row of `GET admin/user-adjustments` (30 §3.2): amounts are 8-decimal strings and every field may be missing, so a
/// malformed value is nil rather than a failed page. Reconciliation (BalanceReconciliation) and stage 3's ledger share it.
public struct UserAdjustment: Identifiable, Decodable, Sendable, Equatable {
    public let id: Int
    public let actionID: String?
    public let kind: String
    public let operation: String
    public let requestedValue: Decimal?
    public let delta: Decimal?
    public let beforeValue: Decimal?
    public let afterValue: Decimal?
    public let userID: Int?
    public let userEmail: String?
    public let operatorUserID: Int?
    public let operatorEmail: String?
    public let notes: String?
    public let requestID: String?
    public let source: String?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, operation, delta, notes, source
        case actionID = "action_id", requestedValue = "requested_value", beforeValue = "before_value", afterValue = "after_value"
        case userID = "user_id", userEmail = "user_email", operatorUserID = "operator_user_id", operatorEmail = "operator_email"
        case requestID = "request_id", createdAt = "created_at"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        actionID = try? c.decodeIfPresent(String.self, forKey: .actionID)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        operation = (try? c.decodeIfPresent(String.self, forKey: .operation)) ?? ""
        requestedValue = try? c.optionalDecimal(.requestedValue); delta = try? c.optionalDecimal(.delta)
        beforeValue = try? c.optionalDecimal(.beforeValue); afterValue = try? c.optionalDecimal(.afterValue)
        userID = try? c.decodeIfPresent(Int.self, forKey: .userID)
        userEmail = try? c.decodeIfPresent(String.self, forKey: .userEmail)
        operatorUserID = try? c.decodeIfPresent(Int.self, forKey: .operatorUserID)
        operatorEmail = try? c.decodeIfPresent(String.self, forKey: .operatorEmail)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        requestID = try? c.decodeIfPresent(String.self, forKey: .requestID)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        createdAt = try c.optionalTimestamp(.createdAt)
    }
}

/// Filters of `GET admin/user-adjustments` (backend `parseUserAdjustmentFilter`). `request_id`, `action_id` and `user_id`
/// have no capability and an old server ignores them, so callers always re-check the rows locally (00 §2.5.5).
public struct UserAdjustmentQuery: Equatable, Sendable {
    /// The server caps page_size here.
    public static let maximumPageSize = 200
    public static let maximumKeywordLength = 100
    public var kind = "balance"
    public var userID: Int?
    public var requestID: String?
    public var actionID: UUID?
    public var keyword = ""
    public var startTime: Date?
    public var endTime: Date?
    public var page = 1
    public var pageSize = PageSize.standard
    public init() {}

    /// Times are UTC `Z` (00 §2.8); only the filters that are set are sent.
    public func queryItems() throws -> [URLQueryItem] {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = requestID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard page > 0, (1...Self.maximumPageSize).contains(pageSize), ["", "balance", "concurrency"].contains(kind),
              userID.map({ $0 > 0 }) ?? true, keyword.count <= Self.maximumKeywordLength, requestID.utf8.count <= 64 else { throw Self.invalid }
        if let startTime, let endTime, startTime >= endTime { throw Self.invalid }
        var values = ["page": String(page), "page_size": String(pageSize)]
        if !kind.isEmpty { values["kind"] = kind }
        if let userID { values["user_id"] = String(userID) }
        if !requestID.isEmpty { values["request_id"] = requestID }
        if let actionID { values["action_id"] = actionID.uuidString.lowercased() }
        if !keyword.isEmpty { values["keyword"] = keyword }
        if let startTime { values["start_time"] = ServerTime.utcTimestamp(startTime) }
        if let endTime { values["end_time"] = ServerTime.utcTimestamp(endTime) }
        return values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    private static let invalid = APIError(kind: .validation, message: "充值与调整记录的查询条件无效。")
}

extension APIClient {
    /// The only definition (R19); stage 3's ledger pages reuse it.
    public func userAdjustments(query: UserAdjustmentQuery) async throws -> Page<UserAdjustment> {
        try await request("admin/user-adjustments", query: query.queryItems())
    }
}
