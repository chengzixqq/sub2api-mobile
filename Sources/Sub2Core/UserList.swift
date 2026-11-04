import Foundation

/// `GET admin/users` (30 §1.2), the only user list query (R19): the list, the administrator count and global search use it.
/// Sort and subscriptions are fixed; ETag revalidation stays inside ConditionalCache (R08).
public struct UserListQuery: Sendable, Equatable {
    /// users-usage and api-keys-usage carry at most this many ids per request (S3D1-07); the server accepts 1000.
    public static let usageBatchSize = 200
    public var search: String?
    public var page: Int
    public var pageSize: Int
    /// "admin" for the administrator count (S3-09); nil sends none.
    public var role: String?
    public init(search: String? = nil, page: Int = 1, pageSize: Int = PageSize.standard, role: String? = nil) {
        self.search = search; self.page = page; self.pageSize = pageSize; self.role = role
    }
    /// Trimmed and cut to 100 characters, never inside one; nil when nothing is left. The server cuts by rune again.
    public var normalizedSearch: String? {
        guard let trimmed = search?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(UserListLimits.searchLength))
    }
    /// 00 §4.1 and §9.1 like `pagination`: page from 1; a page size outside 1–1000 stops a Debug build and is clamped otherwise.
    public func queryItems() throws -> [URLQueryItem] {
        guard page >= 1 else { throw APIError(kind: .validation, message: "页码必须从 1 开始。") }
        assert((1...PageSize.maximum).contains(pageSize), "page_size must stay within 1...1000")
        var items = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "page_size", value: String(PageSize.clamped(pageSize))),
                     URLQueryItem(name: "sort_by", value: "created_at"), URLQueryItem(name: "sort_order", value: "desc"),
                     URLQueryItem(name: "include_subscriptions", value: "false")]
        if let search = normalizedSearch { items.append(URLQueryItem(name: "search", value: search)) }
        if let role = role?.trimmingCharacters(in: .whitespaces), !role.isEmpty { items.append(URLQueryItem(name: "role", value: role)) }
        return items
    }
}

enum UserListLimits {
    static let searchLength = 100
}

/// One `quick-topup` entry (E05). The items are not AdminUser: only `user_id` is required, and a bad entry drops only itself.
public struct QuickTopupUser: Decodable, Sendable, Equatable, Identifiable {
    public let userID: Int
    public let email: String
    public let username: String?
    public let status: String?
    public let balance: Decimal?
    /// `recent` only.
    public let lastAdjustedAt: Date?
    public let lastDelta: Decimal?
    public let lastOperation: String?
    /// `low_balance` only: the threshold the server compared with, from the user or the site (`threshold_source`).
    public let effectiveThreshold: Decimal?
    public let thresholdSource: String?
    public let thresholdType: String?
    public var id: Int { userID }
    public var displayName: String { UserPresentation.displayName(username: username, email: email) }

    public init(userID: Int, email: String, username: String? = nil, status: String? = nil, balance: Decimal? = nil, lastAdjustedAt: Date? = nil,
                lastDelta: Decimal? = nil, lastOperation: String? = nil, effectiveThreshold: Decimal? = nil, thresholdSource: String? = nil,
                thresholdType: String? = nil) {
        self.userID = userID; self.email = email; self.username = username; self.status = status; self.balance = balance
        self.lastAdjustedAt = lastAdjustedAt; self.lastDelta = lastDelta; self.lastOperation = lastOperation
        self.effectiveThreshold = effectiveThreshold; self.thresholdSource = thresholdSource; self.thresholdType = thresholdType
    }
    enum CodingKeys: String, CodingKey {
        case email, username, status, balance
        case userID = "user_id", lastAdjustedAt = "last_adjusted_at", lastDelta = "last_delta", lastOperation = "last_operation"
        case effectiveThreshold = "effective_threshold", thresholdSource = "threshold_source", thresholdType = "threshold_type"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let userID = try c.decode(Int.self, forKey: .userID)
        guard userID > 0 else { throw APIError.invalidResponse }
        func text(_ key: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: key) }
        self.init(userID: userID, email: text(.email) ?? "", username: text(.username), status: text(.status),
                  balance: try? c.optionalDecimal(.balance), lastAdjustedAt: try? c.optionalTimestamp(.lastAdjustedAt),
                  lastDelta: try? c.optionalDecimal(.lastDelta), lastOperation: text(.lastOperation),
                  effectiveThreshold: try? c.optionalDecimal(.effectiveThreshold), thresholdSource: text(.thresholdSource),
                  thresholdType: text(.thresholdType))
    }
}

/// `{recent, low_balance, low_balance_enabled}`; every field may be missing or malformed and then reads as empty or nil.
public struct QuickTopupReply: Decodable, Sendable, Equatable {
    /// Newest adjustment first, as the server sorts it.
    public let recent: [QuickTopupUser]
    public let lowBalance: [QuickTopupUser]
    public let lowBalanceEnabled: Bool?
    public init(recent: [QuickTopupUser] = [], lowBalance: [QuickTopupUser] = [], lowBalanceEnabled: Bool? = nil) {
        self.recent = recent; self.lowBalance = lowBalance; self.lowBalanceEnabled = lowBalanceEnabled
    }
    enum CodingKeys: String, CodingKey { case recent; case lowBalance = "low_balance", lowBalanceEnabled = "low_balance_enabled" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func list(_ key: CodingKeys) -> [QuickTopupUser] { (try? c.decodeIfPresent(LossyList<QuickTopupUser>.self, forKey: key))?.items ?? [] }
        self.init(recent: list(.recent), lowBalance: list(.lowBalance), lowBalanceEnabled: try? c.decodeIfPresent(Bool.self, forKey: .lowBalanceEnabled))
    }
}

/// One `users-usage` entry (30 §1.2). `totalActualCost` covers the last 30 days, not the month: the detail page's month comes
/// from usage/stats. A cost the reply leaves out or garbles is nil, shown as “—”.
public struct UserTodayUsage: Sendable, Equatable {
    public struct Platform: Decodable, Sendable, Equatable {
        public let platform: String
        public let todayActualCost: Decimal?
        public let totalActualCost: Decimal?
        public init(platform: String, todayActualCost: Decimal?, totalActualCost: Decimal?) {
            self.platform = platform; self.todayActualCost = todayActualCost; self.totalActualCost = totalActualCost
        }
        enum CodingKeys: String, CodingKey { case platform; case todayActualCost = "today_actual_cost", totalActualCost = "total_actual_cost" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(platform: c.decode(String.self, forKey: .platform), todayActualCost: try? c.optionalDecimal(.todayActualCost),
                          totalActualCost: try? c.optionalDecimal(.totalActualCost))
        }
    }
    public let userID: Int
    public let todayActualCost: Decimal?
    public let totalActualCost: Decimal?
    public let byPlatform: [Platform]
    public init(userID: Int, todayActualCost: Decimal?, totalActualCost: Decimal? = nil, byPlatform: [Platform] = []) {
        self.userID = userID; self.todayActualCost = todayActualCost; self.totalActualCost = totalActualCost; self.byPlatform = byPlatform
    }
}

extension APIClient {
    /// R19's only user list read; `status` is never sent (U29).
    public func users(query: UserListQuery) async throws -> Page<AdminUser> {
        try await request("admin/users", query: query.queryItems())
    }
    /// The server's defaults (8 recent, 8 low balance, 30 days). Whether the site has `users.quick_topup` is the caller's check.
    public func quickTopup() async throws -> QuickTopupReply {
        try await request("admin/users/quick-topup")
    }
    /// `.readBatch`, never conditional. Only requested ids are kept; one the reply leaves out is the caller's “$0.00”. A failed
    /// request fails the whole call, so no partial map comes back. A read-only token must not call it (R14).
    public func usersTodayUsage(ids: [Int]) async throws -> [Int: UserTodayUsage] {
        try await readInBatches(ids, size: UserListQuery.usageBatchSize) { chunk in
            let reply: UsersUsageReply = try await request("admin/dashboard/users-usage", method: "POST", body: encode(["user_ids": chunk]),
                                                           requestClass: .readBatch)
            let matched = AccountBatchIDs.matched(reply.stats, requested: Set(chunk))
            return Dictionary(uniqueKeysWithValues: matched.map { ($0.key, $0.value.usage(userID: $0.key)) })
        }
    }
    /// The one “at most `size` ids per request” loop (S3D1-07, 00 §4.5): ids go out positive, unique and ascending, one request
    /// after another. A TOO_MANY_IDS whose `metadata.max` is a positive number below that request's size splits it once; any
    /// other failure, or a second refusal, is thrown.
    func readInBatches<Value: Sendable>(_ ids: [Int], size: Int, _ read: ([Int]) async throws -> [Int: Value]) async throws -> [Int: Value] {
        var merged = [Int: Value]()
        for chunk in AccountBatchIDs.batches(AccountBatchIDs.normalized(ids), size: size) {
            let part: [Int: Value]
            do { part = try await read(chunk) }
            catch let error as APIError where error.action == .splitBatch {
                guard let limit = error.metadata["max"].flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), limit > 0, limit < chunk.count else { throw error }
                var smaller = [Int: Value]()
                for piece in AccountBatchIDs.batches(chunk, size: limit) { smaller.merge(try await read(piece)) { _, latest in latest } }
                part = smaller
            }
            merged.merge(part) { _, latest in latest }
        }
        return merged
    }
}

/// `{stats: {"<user_id>": entry}}`; an entry that does not decode reads as absent.
private struct UsersUsageReply: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let todayActualCost: Decimal?
        let totalActualCost: Decimal?
        let byPlatform: [UserTodayUsage.Platform]
        enum CodingKeys: String, CodingKey { case todayActualCost = "today_actual_cost", totalActualCost = "total_actual_cost", byPlatform = "by_platform" }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            todayActualCost = try? c.optionalDecimal(.todayActualCost); totalActualCost = try? c.optionalDecimal(.totalActualCost)
            byPlatform = (try? c.decodeIfPresent(LossyList<UserTodayUsage.Platform>.self, forKey: .byPlatform))?.items ?? []
        }
        func usage(userID: Int) -> UserTodayUsage {
            UserTodayUsage(userID: userID, todayActualCost: todayActualCost, totalActualCost: totalActualCost, byPlatform: byPlatform)
        }
    }
    let stats: [String: Entry]
    enum CodingKeys: String, CodingKey { case stats }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stats = ((try? c.decodeIfPresent([String: LenientDecoded<Entry>].self, forKey: .stats)) ?? [:]).compactMapValues(\.value)
    }
}
