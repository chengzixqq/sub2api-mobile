import Foundation

/// These orderings are performed by the server over the complete result set.
public enum AccountSort: String, CaseIterable, Sendable {
    case name, id, status, schedulable, priority
    case rateMultiplier = "rate_multiplier", lastUsed = "last_used_at", created = "created_at", expires = "expires_at"
    public var title: String {
        switch self {
        case .name: "名称"; case .id: "账号 ID"; case .status: "状态"; case .schedulable: "调度状态"
        case .priority: "优先级"; case .rateMultiplier: "成本倍率"; case .lastUsed: "最近使用"; case .created: "创建时间"; case .expires: "过期时间"
        }
    }
}

public struct AccountListQuery: Equatable, Sendable {
    public var search = ""
    public var status = ""
    public var platform = ""
    public var type = ""
    public var group = ""
    public var sort: AccountSort = .name
    public var descending = false
    public var includeSchedulerScore = false
    public init() {}
    public func queryItems(page: Int) throws -> [URLQueryItem] {
        guard page > 0, group.isEmpty || group == "ungrouped" || (Int(group) ?? 0) > 0 else {
            throw APIError(kind: .validation, message: "账号页码或分组筛选无效。")
        }
        var result = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "page_size", value: "20"),
                      URLQueryItem(name: "lite", value: "true"), URLQueryItem(name: "sort_by", value: sort.rawValue),
                      URLQueryItem(name: "sort_order", value: descending ? "desc" : "asc")]
        for (key, value) in [("search", search.trimmingCharacters(in: .whitespacesAndNewlines)), ("status", status), ("platform", platform), ("type", type), ("group", group)] where !value.isEmpty {
            result.append(URLQueryItem(name: key, value: value))
        }
        if includeSchedulerScore { result.append(URLQueryItem(name: "include_scheduler_score", value: "true")) }
        return result
    }
}

/// Nil means unchanged. Empty notes/group IDs intentionally clear the value.
/// Credentials and provider-specific extra are never part of quick edits.
public struct AccountUpdateRequest: Encodable, Sendable {
    public var name: String?
    public var notes: String?
    public var concurrency: Int?
    public var priority: Int?
    public var rateMultiplier: Decimal?
    public var loadFactor: Int?
    public var groupIDs: [Int]?
    public init(name: String? = nil, notes: String? = nil, concurrency: Int? = nil, priority: Int? = nil, rateMultiplier: Decimal? = nil, loadFactor: Int? = nil, groupIDs: [Int]? = nil) {
        self.name = name?.trimmingCharacters(in: .whitespacesAndNewlines); self.notes = notes
        self.concurrency = concurrency; self.priority = priority; self.rateMultiplier = rateMultiplier
        self.loadFactor = loadFactor; self.groupIDs = groupIDs
    }
    enum CodingKeys: String, CodingKey {
        case name, notes, concurrency, priority, rateMultiplier = "rate_multiplier", loadFactor = "load_factor", groupIDs = "group_ids"
    }
    public func validate() throws {
        guard name != nil || notes != nil || concurrency != nil || priority != nil || rateMultiplier != nil || loadFactor != nil || groupIDs != nil else {
            throw APIError(kind: .validation, message: "请至少修改一个账号字段。")
        }
        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw APIError(kind: .validation, message: "账号名称不能为空。") }
        for value in [concurrency, priority].compactMap({ $0 }) {
            guard value >= 0, value <= Int(Int32.max) else { throw APIError(kind: .validation, message: "并发和优先级必须是非负整数。") }
        }
        if let loadFactor, loadFactor < 0 || loadFactor > 10_000 { throw APIError(kind: .validation, message: "负载因子必须是 0 至 10000 的整数；0 恢复默认。") }
        if let rateMultiplier, rateMultiplier.isNaN || rateMultiplier < 0 { throw APIError(kind: .validation, message: "成本倍率必须是非负数。") }
        if let groupIDs, groupIDs.contains(where: { $0 <= 0 }) || Set(groupIDs).count != groupIDs.count { throw APIError(kind: .validation, message: "分组编号无效或重复。") }
    }
    public func requestBody() throws -> Data {
        try validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(self)
    }
}

public struct PendingAccountUpdate: Sendable {
    public let serverID: UUID
    public let identity: UUID
    public let accountID: Int
    public let body: Data
    public init(serverID: UUID, identity: UUID, accountID: Int, request: AccountUpdateRequest) throws {
        guard accountID > 0 else { throw APIError(kind: .validation, message: "账号编号无效。") }
        self.serverID = serverID; self.identity = identity; self.accountID = accountID; body = try request.requestBody()
    }
}

public struct AccountBulkReply: Decodable, Sendable {
    public let success: Int
    public let failed: Int
    public let results: [Item]
    public struct Item: Decodable, Sendable {
        public let accountID: Int
        public let success: Bool
        public let error: String?
        enum CodingKeys: String, CodingKey { case accountID = "account_id", success, error }
    }
    /// Missing, duplicate or unexpected rows must never be interpreted as success.
    public func outcome(for id: Int) -> Bool? {
        let matches = results.filter { $0.accountID == id }
        return matches.count == 1 ? matches.first?.success : nil
    }
}

extension APIClient {
    public func managedAccounts(page: Int, query: AccountListQuery) async throws -> Page<UpstreamAccount> {
        try await request("admin/accounts", query: query.queryItems(page: page))
    }
    public func updateAccount(_ operation: PendingAccountUpdate) async throws -> UpstreamAccount {
        guard operation.serverID == server.id, operation.identity == userWriteIdentity() else { throw APIError.stationMismatch }
        return try await request("admin/accounts/\(operation.accountID)", method: "PUT", body: operation.body)
    }
    public func setAccountsSchedulable(ids: [Int], enabled: Bool, identity: UUID) async throws -> AccountBulkReply {
        guard identity == userWriteIdentity() else { throw APIError.stationMismatch }
        guard !ids.isEmpty, ids.count <= 50, Set(ids).count == ids.count, ids.allSatisfy({ $0 > 0 }) else {
            throw APIError(kind: .validation, message: "请选择 1 至 50 个不同账号。")
        }
        struct Body: Encodable { let account_ids: [Int]; let schedulable: Bool }
        return try await request("admin/accounts/bulk-update", method: "POST", body: encode(Body(account_ids: ids, schedulable: enabled)))
    }
    public func refreshManagedAccount(id: Int, identity: UUID) async throws {
        guard identity == userWriteIdentity() else { throw APIError.stationMismatch }
        try await refreshAccount(id: id)
    }
}
