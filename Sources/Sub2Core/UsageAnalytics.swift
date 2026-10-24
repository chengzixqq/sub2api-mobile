import Foundation

/// `model_source` of the model statistics and usage records (40 §0.1, §1.8; backend usagestats.ModelSource*).
public enum ModelSource: String, CaseIterable, Hashable, Sendable {
    case requested, upstream, mapping
}

/// Every analysis section carries exactly the same inclusive-start/exclusive-end range.
public struct AnalyticsQuery: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var accountID: Int?
    public var groupID: Int?
    public var userID: Int?
    public var model: String
    public var timeZone: String
    public init(start: Date, end: Date, accountID: Int? = nil, groupID: Int? = nil, userID: Int? = nil, model: String = "", timeZone: String = TimeZone.current.identifier) {
        self.start = start; self.end = end; self.accountID = accountID; self.groupID = groupID
        self.userID = userID; self.model = model; self.timeZone = timeZone
    }
    public var hourly: Bool { end.timeIntervalSince(start) <= 3 * 86_400 }
    public func queryItems() throws -> [URLQueryItem] {
        guard start < end, end.timeIntervalSince(start) <= 367 * 86_400,
              TimeZone(identifier: timeZone) != nil,
              [accountID, groupID, userID].allSatisfy({ $0 == nil || $0! > 0 }) else {
            throw APIError(kind: .validation, message: "请选择一年以内的有效时间范围，并填写正整数对象 ID。")
        }
        var items = ServerTime.timeRangeItems(start: start, end: end) + [URLQueryItem(name: "timezone", value: timeZone)]
        for (key, id) in [("account_id", accountID), ("group_id", groupID), ("user_id", userID)] {
            if let id { items.append(URLQueryItem(name: key, value: String(id))) }
        }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { items.append(URLQueryItem(name: "model", value: model)) }
        return items
    }
}

public struct AnalyticsSummary: Decodable, Sendable {
    public let requests: Int
    public let tokens: Int
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheTokens: Int?
    public let actualCost: Decimal?
    public let accountCost: Decimal?
    public let averageDurationMs: Double?
    /// A billing difference, not net profit: excludes infrastructure/other expenses.
    public var difference: Decimal? { guard let actualCost, let accountCost else { return nil }; return actualCost - accountCost }
    enum CodingKeys: String, CodingKey {
        case requests = "total_requests", tokens = "total_tokens", inputTokens = "total_input_tokens"
        case outputTokens = "total_output_tokens", cacheTokens = "total_cache_tokens"
        case actualCost = "total_actual_cost", accountCost = "total_account_cost", averageDurationMs = "average_duration_ms"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requests = try c.decode(Int.self, forKey: .requests); tokens = try c.decode(Int.self, forKey: .tokens)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens); outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens)
        cacheTokens = try c.decodeIfPresent(Int.self, forKey: .cacheTokens)
        actualCost = try c.optionalDecimal(.actualCost); accountCost = try c.optionalDecimal(.accountCost)
        averageDurationMs = try c.decodeIfPresent(Double.self, forKey: .averageDurationMs)
    }
}

public struct AnalyticsBreakdown: Identifiable, Decodable, Sendable {
    public let model: String?
    public let groupID: Int?
    public let groupName: String?
    public let requests: Int
    public let tokens: Int
    public let actualCost: Decimal?
    public let accountCost: Decimal?
    public var id: String { groupID.map { "group:\($0)" } ?? "model:\(model ?? "")" }
    public var name: String { groupName ?? model ?? "未命名" }
    public var difference: Decimal? { guard let actualCost, let accountCost else { return nil }; return actualCost - accountCost }
    enum CodingKeys: String, CodingKey {
        case model, groupID = "group_id", groupName = "group_name", requests, tokens = "total_tokens"
        case actualCost = "actual_cost", accountCost = "account_cost"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model); groupID = try c.decodeIfPresent(Int.self, forKey: .groupID)
        groupName = try c.decodeIfPresent(String.self, forKey: .groupName)
        requests = try c.decode(Int.self, forKey: .requests); tokens = try c.decode(Int.self, forKey: .tokens)
        actualCost = try c.optionalDecimal(.actualCost); accountCost = try c.optionalDecimal(.accountCost)
    }
}

extension APIClient {
    public func usageAnalysis(_ query: AnalyticsQuery) async throws -> AnalyticsSummary {
        try await request("admin/usage/stats", query: query.queryItems(), timeout: RequestTimeout.aggregate)
    }
    public func usageAnalysisTrend(_ query: AnalyticsQuery) async throws -> [TrendPoint] {
        struct Reply: Decodable, Sendable { let trend: [TrendPoint]? }
        let reply: Reply = try await request("admin/dashboard/trend", query: query.queryItems() + [URLQueryItem(name: "granularity", value: query.hourly ? "hour" : "day")], timeout: RequestTimeout.aggregate)
        return reply.trend ?? []
    }
    public func usageAnalysisModels(_ query: AnalyticsQuery) async throws -> [AnalyticsBreakdown] {
        struct Reply: Decodable, Sendable { let models: [AnalyticsBreakdown]? }
        let reply: Reply = try await request("admin/dashboard/models", query: query.queryItems() + [URLQueryItem(name: "model_source", value: "requested")], timeout: RequestTimeout.aggregate)
        return reply.models ?? []
    }
    public func usageAnalysisGroups(_ query: AnalyticsQuery) async throws -> [AnalyticsBreakdown] {
        struct Reply: Decodable, Sendable { let groups: [AnalyticsBreakdown]? }
        let reply: Reply = try await request("admin/dashboard/groups", query: query.queryItems(), timeout: RequestTimeout.aggregate)
        return reply.groups ?? []
    }
}
