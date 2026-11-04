import Foundation

/// `model_source` of the model statistics and usage records (40 §0.1, §1.8; backend usagestats.ModelSource*).
public enum ModelSource: String, CaseIterable, Hashable, Sendable {
    case requested, upstream, mapping
}

/// `dashboard/trend` and `users-trend` buckets, chosen by the caller (40 §1.2: only a single day goes by the hour). S1-07's type (S1D1-23).
public typealias AnalyticsGranularity = TrendGranularity

// MARK: - 查询

/// Every analysis section carries exactly the same inclusive-start/exclusive-end range, in UTC `Z`, bucketed in the site's zone
/// (40 §0.2, R20).
public struct AnalyticsQuery: Hashable, Sendable {
    public var start: Date
    public var end: Date
    /// Only `dashboard/trend` and `users-trend` send it.
    public var granularity: AnalyticsGranularity
    /// Sent verbatim as `timezone`, “Local” included.
    public var timeZone: ServerTimeZone
    /// Account and user scopes serve the log counts (S4-04); the analytics page filters by group or model only.
    public var accountID: Int?
    public var groupID: Int?
    public var userID: Int?
    public var model: String?
    /// Goes out only with a model; nil on a site without `usage.model_source`, which then gets the model alone.
    public var modelSource: ModelSource?
    /// Only for the request-type fallback, one `usage/stats` per type (40 §2.2).
    public var requestType: UsageRequestType?

    public init(start: Date, end: Date, granularity: AnalyticsGranularity, timeZone: ServerTimeZone, accountID: Int? = nil, groupID: Int? = nil,
                userID: Int? = nil, model: String? = nil, modelSource: ModelSource? = nil, requestType: UsageRequestType? = nil) {
        self.start = start; self.end = end; self.granularity = granularity; self.timeZone = timeZone; self.accountID = accountID
        self.groupID = groupID; self.userID = userID; self.model = model; self.modelSource = modelSource; self.requestType = requestType
    }

    public func queryItems() throws -> [URLQueryItem] {
        guard start < end, end.timeIntervalSince(start) <= 367 * 86_400, [accountID, groupID, userID].allSatisfy({ ($0 ?? 1) > 0 }) else {
            throw APIError(kind: .validation, message: "请选择一年以内的有效时间范围，并填写正整数对象 ID。")
        }
        var items = ServerTime.timeRangeItems(start: start, end: end) + [URLQueryItem(name: "timezone", value: timeZone.identifier)]
        for (key, id) in [("account_id", accountID), ("group_id", groupID), ("user_id", userID)] {
            if let id { items.append(URLQueryItem(name: key, value: String(id))) }
        }
        if let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            items.append(URLQueryItem(name: "model", value: model))
            if let modelSource { items.append(URLQueryItem(name: "model_source", value: modelSource.rawValue)) }
        }
        if let requestType { items.append(URLQueryItem(name: "request_type", value: requestType.rawValue)) }
        return items
    }
    var granularityItem: URLQueryItem { URLQueryItem(name: "granularity", value: granularity.rawValue) }

    // ServerTimeZone is only Equatable; equal zones share the identifier.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(start); hasher.combine(end); hasher.combine(granularity); hasher.combine(timeZone.identifier)
        hasher.combine(accountID); hasher.combine(groupID); hasher.combine(userID); hasher.combine(model); hasher.combine(modelSource)
        hasher.combine(requestType)
    }
}

/// `users-ranking`'s `sort_by` (with `dashboard.users_ranking_sort`), and the order of the model and group ranks.
public enum AnalyticsRankMetric: String, CaseIterable, Hashable, Sendable {
    case actualCost = "actual_cost", requests, tokens
}

/// `users-trend`'s `metric`; with a filter it needs `dashboard.users_trend_filtered_metric`.
public enum UserTrendMetric: String, CaseIterable, Hashable, Sendable {
    case tokens, actualCost = "actual_cost"
}

// MARK: - 解码

/// One row of `endpoints` / `upstream_endpoints` in `usage/stats`.
public struct AnalyticsEndpointStat: Identifiable, Decodable, Sendable, Equatable {
    public let endpoint: String
    public let requests: Int
    public let totalTokens: Int
    /// `cost`: the standard price, before the group rate.
    public let standardCost: Decimal?
    public let actualCost: Decimal?
    public var id: String { endpoint }
    enum CodingKeys: String, CodingKey { case endpoint, requests, totalTokens = "total_tokens", standardCost = "cost", actualCost = "actual_cost" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try c.decode(String.self, forKey: .endpoint)
        requests = try c.decodeIfPresent(Int.self, forKey: .requests) ?? 0; totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        standardCost = try c.optionalDecimal(.standardCost); actualCost = try c.optionalDecimal(.actualCost)
    }
}

public struct AnalyticsSummary: Decodable, Sendable, Equatable {
    public let requests: Int
    public let tokens: Int
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheTokens: Int?
    public let cacheCreationTokens: Int?
    public let cacheReadTokens: Int?
    /// `total_cost`: the standard price, before the group rate.
    public let standardCost: Decimal?
    public let actualCost: Decimal?
    /// nil when `total_account_cost` is missing; never read as 0.
    public let accountCost: Decimal?
    public let averageDurationMs: Double?
    /// nil when left out (an old server, or no data); an empty list stays empty.
    public let endpoints: [AnalyticsEndpointStat]?
    public let upstreamEndpoints: [AnalyticsEndpointStat]?
    /// 利润 (40 §0.4): the actual charge minus the account cost, without servers or other expenses; nil without the account cost.
    public var profit: Decimal? { guard let actualCost, let accountCost else { return nil }; return actualCost - accountCost }
    enum CodingKeys: String, CodingKey {
        case requests = "total_requests", tokens = "total_tokens", inputTokens = "total_input_tokens"
        case outputTokens = "total_output_tokens", cacheTokens = "total_cache_tokens"
        case cacheCreationTokens = "total_cache_creation_tokens", cacheReadTokens = "total_cache_read_tokens", standardCost = "total_cost"
        case actualCost = "total_actual_cost", accountCost = "total_account_cost", averageDurationMs = "average_duration_ms"
        case endpoints, upstreamEndpoints = "upstream_endpoints"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requests = try c.decode(Int.self, forKey: .requests); tokens = try c.decode(Int.self, forKey: .tokens)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens); outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens)
        cacheTokens = try c.decodeIfPresent(Int.self, forKey: .cacheTokens)
        cacheCreationTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens)
        cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens)
        standardCost = try c.optionalDecimal(.standardCost)
        actualCost = try c.optionalDecimal(.actualCost); accountCost = try c.optionalDecimal(.accountCost)
        averageDurationMs = try c.decodeIfPresent(Double.self, forKey: .averageDurationMs)
        endpoints = try c.decodeIfPresent([AnalyticsEndpointStat].self, forKey: .endpoints)
        upstreamEndpoints = try c.decodeIfPresent([AnalyticsEndpointStat].self, forKey: .upstreamEndpoints)
    }
}

/// A `dashboard/models` or `dashboard/groups` row; group rows have no token kinds.
public struct AnalyticsBreakdown: Identifiable, Decodable, Sendable, Equatable {
    public let model: String?
    public let groupID: Int?
    public let groupName: String?
    public let requests: Int
    public let tokens: Int
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheCreationTokens: Int?
    public let cacheReadTokens: Int?
    /// `cost`: the standard price, before the group rate.
    public let standardCost: Decimal?
    public let actualCost: Decimal?
    public let accountCost: Decimal?
    public var id: String { groupID.map { "group:\($0)" } ?? "model:\(model ?? "")" }
    public var name: String { groupName ?? model ?? "未命名" }
    /// 利润, as in AnalyticsSummary.profit.
    public var profit: Decimal? { guard let actualCost, let accountCost else { return nil }; return actualCost - accountCost }
    enum CodingKeys: String, CodingKey {
        case model, groupID = "group_id", groupName = "group_name", requests, tokens = "total_tokens"
        case inputTokens = "input_tokens", outputTokens = "output_tokens", cacheCreationTokens = "cache_creation_tokens"
        case cacheReadTokens = "cache_read_tokens", standardCost = "cost", actualCost = "actual_cost", accountCost = "account_cost"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model); groupID = try c.decodeIfPresent(Int.self, forKey: .groupID)
        groupName = try c.decodeIfPresent(String.self, forKey: .groupName)
        requests = try c.decode(Int.self, forKey: .requests); tokens = try c.decode(Int.self, forKey: .tokens)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens); outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens)
        cacheCreationTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens)
        cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens)
        standardCost = try c.optionalDecimal(.standardCost)
        actualCost = try c.optionalDecimal(.actualCost); accountCost = try c.optionalDecimal(.accountCost)
    }
}

/// `users-ranking` (40 §1.3). Before `dashboard.users_ranking_sort` the rows have no costs and there are no user or cost totals.
public struct UserSpendingRanking: Decodable, Sendable, Equatable {
    /// The server quietly clamps anything above it.
    public static let maxLimit = 50
    public struct Row: Identifiable, Decodable, Sendable, Equatable {
        public let userID: Int
        public let email: String?
        public let username: String?
        public let actualCost: Decimal?
        /// `cost`: the standard price, before the group rate.
        public let standardCost: Decimal?
        public let accountCost: Decimal?
        public let requests: Int?
        public let tokens: Int?
        public var id: Int { userID }
        public var displayName: String { analyticsUserName(userID, username: username, email: email) }
        enum CodingKeys: String, CodingKey {
            case userID = "user_id", email, username, actualCost = "actual_cost", standardCost = "cost", accountCost = "account_cost", requests, tokens
        }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            userID = try c.decode(Int.self, forKey: .userID)
            email = try c.decodeIfPresent(String.self, forKey: .email); username = try c.decodeIfPresent(String.self, forKey: .username)
            actualCost = try c.optionalDecimal(.actualCost); standardCost = try c.optionalDecimal(.standardCost)
            accountCost = try c.optionalDecimal(.accountCost)
            requests = try c.decodeIfPresent(Int.self, forKey: .requests); tokens = try c.decodeIfPresent(Int.self, forKey: .tokens)
        }
    }
    public let ranking: [Row]
    public let totalUsers: Int?
    public let totalActualCost: Decimal?
    /// `total_cost`.
    public let totalStandardCost: Decimal?
    public let totalAccountCost: Decimal?
    public let totalRequests: Int?
    public let totalTokens: Int?
    enum CodingKeys: String, CodingKey {
        case ranking, totalUsers = "total_users", totalActualCost = "total_actual_cost", totalStandardCost = "total_cost"
        case totalAccountCost = "total_account_cost", totalRequests = "total_requests", totalTokens = "total_tokens"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ranking = try c.decodeIfPresent([Row].self, forKey: .ranking) ?? []
        totalUsers = try c.decodeIfPresent(Int.self, forKey: .totalUsers)
        totalActualCost = try c.optionalDecimal(.totalActualCost); totalStandardCost = try c.optionalDecimal(.totalStandardCost)
        totalAccountCost = try c.optionalDecimal(.totalAccountCost)
        totalRequests = try c.decodeIfPresent(Int.self, forKey: .totalRequests); totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens)
    }
}

/// One user's bucket in `users-trend` (40 §2.2); the server only sends buckets that have data.
public struct UserTrendPoint: Identifiable, Decodable, Sendable, Equatable {
    public let date: String
    public let userID: Int
    public let email: String?
    public let username: String?
    public let requests: Int
    public let tokens: Int
    /// `cost`: the standard price, before the group rate.
    public let standardCost: Decimal?
    public let actualCost: Decimal?
    public var id: String { "\(userID)@\(date)" }
    public var displayName: String { analyticsUserName(userID, username: username, email: email) }
    enum CodingKeys: String, CodingKey {
        case date, userID = "user_id", email, username, requests, tokens, standardCost = "cost", actualCost = "actual_cost"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date); userID = try c.decode(Int.self, forKey: .userID)
        email = try c.decodeIfPresent(String.self, forKey: .email); username = try c.decodeIfPresent(String.self, forKey: .username)
        requests = try c.decodeIfPresent(Int.self, forKey: .requests) ?? 0; tokens = try c.decodeIfPresent(Int.self, forKey: .tokens) ?? 0
        standardCost = try c.optionalDecimal(.standardCost); actualCost = try c.optionalDecimal(.actualCost)
    }
}

/// `users-trend` points with the zone their offset-less buckets belong to (00 §6.4).
public struct UserTrendReply: Sendable {
    public let points: [UserTrendPoint]
    public let timeZone: TimeZone
    public init(points: [UserTrendPoint], timeZone: TimeZone) { self.points = points; self.timeZone = timeZone }
}

/// One `dashboard/request-types` row; `requestType` is kept as sent, and `kind` is nil for a value the App does not know.
public struct RequestTypeStat: Identifiable, Decodable, Sendable, Equatable {
    public let requestType: String
    public let requests: Int
    public let totalTokens: Int
    /// `cost`: the standard price, before the group rate.
    public let standardCost: Decimal?
    public let actualCost: Decimal?
    public let accountCost: Decimal?
    public var kind: UsageRequestType? { UsageRequestType(rawValue: requestType) }
    public var id: String { requestType }
    enum CodingKeys: String, CodingKey {
        case requestType = "request_type", requests, totalTokens = "total_tokens", standardCost = "cost", actualCost = "actual_cost"
        case accountCost = "account_cost"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestType = try c.decode(String.self, forKey: .requestType)
        requests = try c.decodeIfPresent(Int.self, forKey: .requests) ?? 0; totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        standardCost = try c.optionalDecimal(.standardCost); actualCost = try c.optionalDecimal(.actualCost)
        accountCost = try c.optionalDecimal(.accountCost)
    }
}

/// 40 §1.4: the username, else the email, else the number.
private func analyticsUserName(_ id: Int, username: String?, email: String?) -> String {
    for name in [username, email] {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
    }
    return "#\(id)"
}

/// A missing or null `trend` is no buckets; a malformed `query` block is ignored.
private struct AnalyticsTrendReply<Point: Decodable & Sendable>: Decodable, Sendable {
    let trend: [Point]
    let query: QueryMetadata?
    enum CodingKeys: String, CodingKey { case trend, query }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trend = try c.decodeIfPresent([Point].self, forKey: .trend) ?? []
        query = try? c.decodeIfPresent(QueryMetadata.self, forKey: .query)
    }
}

// MARK: - 接口

extension APIClient {
    public func usageAnalysis(_ query: AnalyticsQuery) async throws -> AnalyticsSummary {
        try await request("admin/usage/stats", query: query.queryItems(), timeout: RequestTimeout.aggregate)
    }
    /// The only ranged `dashboard/trend` read (S4D1-12). Buckets are read in the reply's `query.timezone`, else in the zone sent;
    /// a reply that lands after a site switch is dropped.
    public func usageAnalysisTrend(_ query: AnalyticsQuery) async throws -> DashboardTrendReply {
        let items = try query.queryItems() + [query.granularityItem]
        let snapshot = currentGeneration()
        let reply: AnalyticsTrendReply<TrendPoint> = try await request("admin/dashboard/trend", query: items, timeout: RequestTimeout.aggregate)
        try check(snapshot)
        return DashboardTrendReply(points: reply.trend, timeZone: ServerTime.bucketTimeZone(reported: reply.query?.timezone, requested: query.timeZone))
    }
    /// `source` names the rows; the server also reads the same key as the model filter's source, so only this one is sent.
    public func usageAnalysisModels(_ query: AnalyticsQuery, source: ModelSource) async throws -> [AnalyticsBreakdown] {
        struct Reply: Decodable, Sendable { let models: [AnalyticsBreakdown]? }
        var scoped = query
        scoped.modelSource = nil
        let items = try scoped.queryItems() + [URLQueryItem(name: "model_source", value: source.rawValue)]
        let reply: Reply = try await request("admin/dashboard/models", query: items, timeout: RequestTimeout.aggregate)
        return reply.models ?? []
    }
    public func usageAnalysisGroups(_ query: AnalyticsQuery) async throws -> [AnalyticsBreakdown] {
        struct Reply: Decodable, Sendable { let groups: [AnalyticsBreakdown]? }
        let reply: Reply = try await request("admin/dashboard/groups", query: query.queryItems(), timeout: RequestTimeout.aggregate)
        return reply.groups ?? []
    }
    /// `sortBy` nil sends no `sort_by` (a site without `dashboard.users_ranking_sort`). The server would quietly change a limit
    /// outside 1–50, so it is refused here.
    public func usageAnalysisUsersRanking(_ query: AnalyticsQuery, sortBy: AnalyticsRankMetric?, limit: Int) async throws -> UserSpendingRanking {
        guard (1...UserSpendingRanking.maxLimit).contains(limit) else { throw APIError(kind: .validation, message: "排行人数需在 1–50 之间。") }
        var items = try query.queryItems() + [URLQueryItem(name: "limit", value: String(limit))]
        if let sortBy { items.append(URLQueryItem(name: "sort_by", value: sortBy.rawValue)) }
        return try await request("admin/dashboard/users-ranking", query: items, timeout: RequestTimeout.aggregate)
    }
    /// `metric` nil sends none (a filtered query on a site without `dashboard.users_trend_filtered_metric`). Zones as in the trend.
    public func usageAnalysisUsersTrend(_ query: AnalyticsQuery, metric: UserTrendMetric?, limit: Int) async throws -> UserTrendReply {
        guard limit > 0 else { throw APIError(kind: .validation, message: "趋势人数需大于 0。") }
        var items = try query.queryItems() + [query.granularityItem, URLQueryItem(name: "limit", value: String(limit))]
        if let metric { items.append(URLQueryItem(name: "metric", value: metric.rawValue)) }
        let snapshot = currentGeneration()
        let reply: AnalyticsTrendReply<UserTrendPoint> = try await request("admin/dashboard/users-trend", query: items, timeout: RequestTimeout.aggregate)
        try check(snapshot)
        return UserTrendReply(points: reply.trend, timeZone: ServerTime.bucketTimeZone(reported: reply.query?.timezone, requested: query.timeZone))
    }
    /// Already split by type: the server answers 400 to `request_type` or `stream`, so the query's own type is dropped.
    public func usageAnalysisRequestTypes(_ query: AnalyticsQuery) async throws -> [RequestTypeStat] {
        struct Reply: Decodable, Sendable { let requestTypes: [RequestTypeStat]?; enum CodingKeys: String, CodingKey { case requestTypes = "request_types" } }
        var scoped = query
        scoped.requestType = nil
        let reply: Reply = try await request("admin/dashboard/request-types", query: scoped.queryItems(), timeout: RequestTimeout.aggregate)
        return reply.requestTypes ?? []
    }
}
