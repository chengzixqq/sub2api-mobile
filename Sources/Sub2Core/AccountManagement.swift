import Foundation

/// These orderings are performed by the server over the complete result set.
public enum AccountSort: String, CaseIterable, Sendable {
    case name, id, status, schedulable, priority
    case rateMultiplier = "rate_multiplier", lastUsed = "last_used_at", created = "created_at", expires = "expires_at"
    /// `accounts.list_query` only; AccountListQuery sends `name` to an older server.
    case urgency
    public var title: String {
        switch self {
        case .name: "名称"; case .id: "账号 ID"; case .status: "状态"; case .schedulable: "调度状态"
        case .priority: "优先级"; case .rateMultiplier: "成本倍率"; case .lastUsed: "最近使用"; case .created: "创建时间"; case .expires: "过期时间"
        case .urgency: "紧急度"
        }
    }
}

/// Backend `status` values. Declaration order is the joining order, so the chips' strings are fixed (20 §1.2): limited =
/// overloaded,rate_limited,temp_unschedulable; paused · disabled = unschedulable,inactive.
public enum AccountStatusFilter: String, CaseIterable, Sendable {
    case needsAttention = "needs_attention", error, overloaded, rateLimited = "rate_limited", tempUnschedulable = "temp_unschedulable"
    case unschedulable, inactive
    /// The backend's old predicate (active, schedulable, outside any rate-limit or temporary window); not D02's “正常”.
    case active
    /// D02 available.
    case schedulableNow = "schedulable_now"
    /// Understood as a single value by servers without `accounts.list_query` too.
    public var isLegacy: Bool {
        switch self {
        case .error, .rateLimited, .tempUnschedulable, .unschedulable, .inactive, .active: true
        case .needsAttention, .overloaded, .schedulableNow: false
        }
    }
}

public enum AccountGroupFilter: Hashable, Sendable { case id(Int), ungrouped }

/// R19: the App's one account list query (account tab, group members, logs filter, global search, overview error accounts).
public struct AccountListQuery: Equatable, Sendable {
    /// 00 §4.1 (U15).
    public static let defaultPageSize = 500
    /// Empty means no filter for these three.
    public var search: String
    public var platform: String
    public var type: String
    public var group: AccountGroupFilter?
    public var statuses: Set<AccountStatusFilter>
    public var sort: AccountSort
    public var descending: Bool
    /// Sent clamped to 1–1000.
    public var pageSize: Int
    /// Sent on page 1 only (R09).
    public var includeCounts: Bool
    public var includeSchedulerScore: Bool
    /// The caller's `session.has(.accountsListQuery)`. Without it no new parameter is sent (00 §5 rule 1): several or derived
    /// statuses, `urgency` and `include_counts` are left out, a single legacy status is still sent.
    public var supportsListQuery: Bool
    public init(search: String = "", platform: String = "", type: String = "", group: AccountGroupFilter? = nil, statuses: Set<AccountStatusFilter> = [],
                sort: AccountSort = .name, descending: Bool = false, pageSize: Int = AccountListQuery.defaultPageSize, includeCounts: Bool = false,
                includeSchedulerScore: Bool = false, supportsListQuery: Bool = false) {
        self.search = search; self.platform = platform; self.type = type; self.group = group; self.statuses = statuses
        self.sort = sort; self.descending = descending; self.pageSize = pageSize; self.includeCounts = includeCounts
        self.includeSchedulerScore = includeSchedulerScore; self.supportsListQuery = supportsListQuery
    }
    /// The statuses were not sent: the caller filters the rows itself by AccountDisplayState.
    public var needsLocalStatusFilter: Bool { !statuses.isEmpty && statusQueryValue == nil }
    var statusQueryValue: String? {
        guard supportsListQuery else {
            guard statuses.count == 1, let only = statuses.first, only.isLegacy else { return nil }
            return only.rawValue
        }
        return statuses.isEmpty ? nil : AccountStatusFilter.allCases.filter(statuses.contains).map(\.rawValue).joined(separator: ",")
    }
    public func queryItems(page: Int) throws -> [URLQueryItem] {
        let invalid = APIError(kind: .validation, message: "账号页码或分组筛选无效。")
        guard page > 0 else { throw invalid }
        if case .id(let id) = group, id <= 0 { throw invalid }
        let sortValue = sort == .urgency && !supportsListQuery ? AccountSort.name.rawValue : sort.rawValue
        var result = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "page_size", value: String(PageSize.clamped(pageSize))),
                      URLQueryItem(name: "lite", value: "1"), URLQueryItem(name: "sort_by", value: sortValue),
                      URLQueryItem(name: "sort_order", value: descending ? "desc" : "asc")]
        let filters = [("search", Self.searchValue(search)), ("status", statusQueryValue ?? ""), ("platform", platform), ("type", type),
                       ("group", groupQueryValue ?? "")]
        for (key, value) in filters where !value.isEmpty { result.append(URLQueryItem(name: key, value: value)) }
        if includeCounts, supportsListQuery, page == 1 { result.append(URLQueryItem(name: "include_counts", value: "1")) }
        if includeSchedulerScore { result.append(URLQueryItem(name: "include_scheduler_score", value: "1")) }
        return result
    }
    private var groupQueryValue: String? {
        switch group {
        case nil: nil
        case .ungrouped: "ungrouped"
        case .id(let id): String(id)
        }
    }
    /// The server trims and keeps the first 100 bytes, which can split a character; cut at a character boundary first.
    static func searchValue(_ raw: String) -> String {
        var result = "", bytes = 0
        for character in raw.trimmingCharacters(in: .whitespacesAndNewlines) {
            bytes += character.utf8.count
            guard bytes <= 100 else { break }
            result.append(character)
        }
        return result
    }
}

/// `data.counts` with include_counts: totals for each status value under the other filters. A missing key is unknown, not 0.
public struct AccountListCounts: Decodable, Sendable, Equatable {
    public let all: Int?
    public let needsAttention: Int?
    public let error: Int?
    public let overloaded: Int?
    public let rateLimited: Int?
    public let tempUnschedulable: Int?
    public let unschedulable: Int?
    public let inactive: Int?
    public let schedulableNow: Int?
    public init(all: Int? = nil, needsAttention: Int? = nil, error: Int? = nil, overloaded: Int? = nil, rateLimited: Int? = nil,
                tempUnschedulable: Int? = nil, unschedulable: Int? = nil, inactive: Int? = nil, schedulableNow: Int? = nil) {
        self.all = all; self.needsAttention = needsAttention; self.error = error; self.overloaded = overloaded; self.rateLimited = rateLimited
        self.tempUnschedulable = tempUnschedulable; self.unschedulable = unschedulable; self.inactive = inactive; self.schedulableNow = schedulableNow
    }
    enum CodingKeys: String, CodingKey {
        case all, error, overloaded, unschedulable, inactive
        case needsAttention = "needs_attention", rateLimited = "rate_limited", tempUnschedulable = "temp_unschedulable", schedulableNow = "schedulable_now"
    }
}

/// One page of the account list. No ETag of its own: a 304 comes back as the cached page (R08).
public struct AccountListPage: Decodable, Sendable {
    public let items: [UpstreamAccount]
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let pages: Int
    /// nil without include_counts, from an older server, or when malformed.
    public let counts: AccountListCounts?
    public var hasMore: Bool { page < pages }
    public init(items: [UpstreamAccount], total: Int, page: Int, pageSize: Int, pages: Int, counts: AccountListCounts? = nil) {
        self.items = items; self.total = total; self.page = page; self.pageSize = pageSize; self.pages = pages; self.counts = counts
    }
    private enum CodingKeys: String, CodingKey { case counts }
    public init(from decoder: any Decoder) throws {
        let base = try Page<UpstreamAccount>(from: decoder)
        guard let total = base.total, let pages = base.pages else { throw APIError.invalidResponse }
        items = base.items; self.total = total; page = base.page; pageSize = base.pageSize; self.pages = pages
        counts = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(AccountListCounts.self, forKey: .counts)
    }
    public func mapItems(_ transform: (UpstreamAccount) throws -> UpstreamAccount) rethrows -> AccountListPage {
        AccountListPage(items: try items.map(transform), total: total, page: page, pageSize: pageSize, pages: pages, counts: counts)
    }
}

/// `bulk-update`'s reply (20 §8.2). `success_ids` / `failed_ids` are nil from an older server; a missing count or result list
/// reads as 0 or empty.
public struct AccountBulkReply: Decodable, Sendable, Equatable {
    public let success: Int
    public let failed: Int
    public let successIDs: [Int]?
    public let failedIDs: [Int]?
    public let results: [Item]
    public struct Item: Decodable, Sendable, Equatable {
        public let accountID: Int
        public let success: Bool
        /// Decoded only: never shown or logged (20 §8.3, 00 §3.4).
        public let error: String?
        public init(accountID: Int, success: Bool, error: String? = nil) { self.accountID = accountID; self.success = success; self.error = error }
        enum CodingKeys: String, CodingKey { case accountID = "account_id", success, error }
    }
    public init(success: Int, failed: Int, successIDs: [Int]?, failedIDs: [Int]?, results: [Item]) {
        self.success = success; self.failed = failed; self.successIDs = successIDs; self.failedIDs = failedIDs; self.results = results
    }
    enum CodingKeys: String, CodingKey { case success, failed, results, successIDs = "success_ids", failedIDs = "failed_ids" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(success: try c.decodeIfPresent(Int.self, forKey: .success) ?? 0, failed: try c.decodeIfPresent(Int.self, forKey: .failed) ?? 0,
                  successIDs: try c.decodeIfPresent([Int].self, forKey: .successIDs), failedIDs: try c.decodeIfPresent([Int].self, forKey: .failedIDs),
                  results: try c.decodeIfPresent([Item].self, forKey: .results) ?? [])
    }
    /// Missing, duplicate or unexpected rows must never be interpreted as success. With either id list (a missing one read as
    /// empty) the row must also appear exactly once in its own list and not in the other.
    public func outcome(for id: Int) -> Bool? {
        let matches = results.filter { $0.accountID == id }
        guard matches.count == 1, let row = matches.first else { return nil }
        guard successIDs != nil || failedIDs != nil else { return row.success }
        let listed = (successIDs ?? []).filter { $0 == id }.count, refused = (failedIDs ?? []).filter { $0 == id }.count
        let consistent = row.success ? listed == 1 && refused == 0 : refused == 1 && listed == 0
        return consistent ? row.success : nil
    }
}

extension APIClient {
    /// R19: the App's one account list read. A 304 comes back as the cached page through ConditionalCache.
    public func managedAccounts(page: Int, query: AccountListQuery) async throws -> AccountListPage {
        try await request("admin/accounts", query: query.queryItems(page: page))
    }
    /// 20 §8.2: 1–50 different positive ids. With a key (admin.idempotent_writes, one per request, made at the tap, R05) the
    /// keyed executor retries it within the bulk limit (65 seconds); without one it is sent once (00 §2.4). The session check
    /// is the App's (S2D1-05).
    public func setAccountsSchedulable(ids: [Int], enabled: Bool, idempotencyKey: UUID?,
                                       onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AccountBulkReply> {
        guard !ids.isEmpty, ids.count <= AccountBatchPlan.maxPerRequest, Set(ids).count == ids.count, ids.allSatisfy({ $0 > 0 }) else {
            throw APIError(kind: .validation, message: "请选择 1 至 50 个不同账号。")
        }
        struct Body: Encodable { let account_ids: [Int]; let schedulable: Bool }
        let path = "admin/accounts/bulk-update", body = try encode(Body(account_ids: ids, schedulable: enabled))
        guard let key = idempotencyKey else { return try await performUnkeyedWrite(path, method: "POST", body: body, requestID: UUID().uuidString.lowercased()) }
        return try await performKeyedWrite(KeyedWriteRequest(path: path, method: "POST", body: body, key: key, timeout: RequestTimeout.keyedBulk),
                                           onEvent: onEvent)
    }
    /// The list's batch 刷新凭据 is gone (20 §8.7, U21); S2-15 replaces this with a keyed refresh.
    public func refreshManagedAccount(id: Int, identity: UUID) async throws {
        guard identity == userWriteIdentity() else { throw APIError.stationMismatch }
        try await refreshAccount(id: id)
    }
}
