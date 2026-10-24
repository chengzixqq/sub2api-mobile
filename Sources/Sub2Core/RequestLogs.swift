import Foundation

/// The usage endpoint deliberately omits expensive COUNT(*) totals in deferred mode.
public struct RequestLogPage<T: Decodable & Sendable>: Decodable, Sendable {
    public let items: [T]
    public let total: Int?
    public let page: Int
    public let pageSize: Int
    public let hasMore: Bool
    public let totalExact: Bool
    enum CodingKeys: String, CodingKey { case items, total, page, pageSize = "page_size", pages, hasMore = "has_more", totalExact = "total_exact" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([T].self, forKey: .items)
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        page = try c.decode(Int.self, forKey: .page); pageSize = try c.decode(Int.self, forKey: .pageSize)
        guard page > 0, pageSize > 0, total.map({ $0 >= 0 }) ?? true else { throw APIError.invalidResponse }
        totalExact = try c.decodeIfPresent(Bool.self, forKey: .totalExact) ?? (total != nil)
        if let more = try c.decodeIfPresent(Bool.self, forKey: .hasMore) { hasMore = more }
        else if let pages = try c.decodeIfPresent(Int.self, forKey: .pages) { hasMore = page < pages }
        else if let total { hasMore = page <= Int.max / pageSize && page * pageSize < total }
        else { throw APIError.invalidResponse }
    }
}

public enum ErrorLogKind: String, CaseIterable, Sendable { case request, upstream }

public struct RequestLogFilter: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var model = ""
    public var requestID = ""
    public var userID: Int?
    public var accountID: Int?
    public var groupID: Int?
    public var apiKeyID: Int?
    public var requestType = ""
    public var category = ""
    public var resolved: Bool?
    public var statusCode: Int?
    public init(start: Date = Date().addingTimeInterval(-86_400), end: Date = Date(), accountID: Int? = nil, groupID: Int? = nil) {
        self.start = start; self.end = end; self.accountID = accountID; self.groupID = groupID
    }
    public func upstreamErrorFilter() -> Self {
        var copy = self
        copy.userID = nil; copy.apiKeyID = nil; copy.model = ""; copy.requestID = ""; copy.category = ""; copy.requestType = ""
        return copy
    }
    public func queryItems(page: Int, errors: Bool = false, errorKind: ErrorLogKind = .request) throws -> [URLQueryItem] {
        guard page > 0, start < end, end.timeIntervalSince(start) <= 366 * 86_400 else {
            throw APIError(kind: .validation, message: "请选择有效的时间范围（最长一年）和页码。")
        }
        if errors, errorKind == .upstream, userID != nil || apiKeyID != nil || !model.isEmpty || !requestID.isEmpty || !category.isEmpty {
            throw APIError(kind: .validation, message: "上游错误支持时间、账号、分组与状态筛选；不支持用户、密钥、模型和请求 ID 筛选。")
        }
        var values = ["page": String(page), "page_size": "30", "start_time": ServerTime.utcTimestamp(start), "end_time": ServerTime.utcTimestamp(end), "sort_by": "created_at", "sort_order": "desc"]
        for (key, value) in [("user_id", userID), ("account_id", accountID), ("group_id", groupID), ("api_key_id", apiKeyID)] {
            if let value {
                guard value > 0 else { throw APIError(kind: .validation, message: "筛选 ID 必须为正整数。") }
                values[key] = String(value)
            }
        }
        for (key, value) in [("model", model), ("request_id", requestID)] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { values[key] = trimmed }
        }
        if errors {
            values["view"] = "all"
            if !category.isEmpty { values["category"] = category }
            if let resolved { values["resolved"] = resolved ? "true" : "false" }
            if let statusCode {
                guard (100...599).contains(statusCode) else { throw APIError(kind: .validation, message: "请输入有效 HTTP 状态码。") }
                values["status_codes"] = String(statusCode)
            }
        } else {
            values["timezone"] = TimeZone.current.identifier
            values["count_mode"] = "deferred"
            if !requestType.isEmpty { values["request_type"] = requestType }
        }
        return values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
}

/// Intentionally reads only public labels from nested DTOs, never API keys or credentials.
public struct UsageRequestRecord: Decodable, Identifiable, Sendable {
    public let id: Int
    public let requestID: String
    public let createdAt: String
    public let model: String
    public let upstreamModel: String?
    public let userID: Int
    public let accountID: Int
    public let apiKeyID: Int
    public let groupID: Int?
    public let userEmail: String?
    public let accountName: String?
    public let groupName: String?
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let actualCost: Decimal?
    public let standardCost: Decimal?
    public let accountCost: Decimal?
    public let durationMs: Int?
    public let firstTokenMs: Int?
    public let requestType: String?
    public let stream: Bool?
    public let inboundEndpoint: String?
    public let upstreamRequestID: String?
    public var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }
    enum CodingKeys: String, CodingKey {
        case id, model, user, account, group, stream
        case requestID = "request_id", createdAt = "created_at", upstreamModel = "upstream_model"
        case userID = "user_id", accountID = "account_id", apiKeyID = "api_key_id", groupID = "group_id"
        case inputTokens = "input_tokens", outputTokens = "output_tokens", cacheCreationTokens = "cache_creation_tokens", cacheReadTokens = "cache_read_tokens"
        case actualCost = "actual_cost", standardCost = "total_cost", accountStatsCost = "account_stats_cost", accountRateMultiplier = "account_rate_multiplier"
        case durationMs = "duration_ms", firstTokenMs = "first_token_ms", requestType = "request_type", inboundEndpoint = "inbound_endpoint", upstreamRequestID = "upstream_request_id"
    }
    private struct Name: Decodable { let name: String?; let email: String? }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); requestID = try c.decode(String.self, forKey: .requestID)
        createdAt = try c.decode(String.self, forKey: .createdAt); model = try c.decode(String.self, forKey: .model)
        upstreamModel = try c.decodeIfPresent(String.self, forKey: .upstreamModel)
        userID = try c.decode(Int.self, forKey: .userID); accountID = try c.decode(Int.self, forKey: .accountID)
        apiKeyID = try c.decode(Int.self, forKey: .apiKeyID); groupID = try c.decodeIfPresent(Int.self, forKey: .groupID)
        userEmail = try c.decodeIfPresent(Name.self, forKey: .user)?.email
        accountName = try c.decodeIfPresent(Name.self, forKey: .account)?.name; groupName = try c.decodeIfPresent(Name.self, forKey: .group)?.name
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0; outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCreationTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0; cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
        actualCost = try c.optionalDecimal(.actualCost); standardCost = try c.optionalDecimal(.standardCost)
        let base = try c.optionalDecimal(.accountStatsCost) ?? standardCost
        let multiplier = try c.optionalDecimal(.accountRateMultiplier) ?? 1
        accountCost = base.map { $0 * multiplier }
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs); firstTokenMs = try c.decodeIfPresent(Int.self, forKey: .firstTokenMs)
        requestType = try c.decodeIfPresent(String.self, forKey: .requestType); stream = try c.decodeIfPresent(Bool.self, forKey: .stream)
        inboundEndpoint = try c.decodeIfPresent(String.self, forKey: .inboundEndpoint); upstreamRequestID = try c.decodeIfPresent(String.self, forKey: .upstreamRequestID)
    }
}

/// No raw request/response body, upstream error detail or key prefix is retained.
public struct RequestErrorRecord: Decodable, Identifiable, Sendable {
    public let id: Int
    public let createdAt: String
    public let requestID: String
    public let phase: String
    public let type: String
    public let statusCode: Int
    public let platform: String
    public let model: String
    public let upstreamModel: String?
    public let resolved: Bool
    public let message: String
    public let userID: Int?
    public let accountID: Int?
    public let groupID: Int?
    public let accountName: String?
    public let groupName: String?
    public let upstreamStatusCode: Int?
    public let upstreamMessage: String?
    public let upstreamLatencyMs: Int?
    public let responseLatencyMs: Int?
    public let firstTokenMs: Int?
    enum CodingKeys: String, CodingKey {
        case id, phase, type, platform, model, resolved, message
        case requestedModel = "requested_model", upstreamModel = "upstream_model"
        case createdAt = "created_at", requestID = "request_id", statusCode = "status_code", userID = "user_id", accountID = "account_id", groupID = "group_id"
        case accountName = "account_name", groupName = "group_name", upstreamStatusCode = "upstream_status_code", upstreamMessage = "upstream_error_message"
        case upstreamLatencyMs = "upstream_latency_ms", responseLatencyMs = "response_latency_ms", firstTokenMs = "time_to_first_token_ms"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); createdAt = try c.decode(String.self, forKey: .createdAt)
        requestID = try c.decode(String.self, forKey: .requestID); phase = try c.decode(String.self, forKey: .phase)
        type = try c.decode(String.self, forKey: .type); statusCode = try c.decode(Int.self, forKey: .statusCode)
        platform = try c.decode(String.self, forKey: .platform)
        let requested = try c.decodeIfPresent(String.self, forKey: .requestedModel)
        model = try (requested?.isEmpty == false ? requested : nil) ?? c.decode(String.self, forKey: .model)
        upstreamModel = try c.decodeIfPresent(String.self, forKey: .upstreamModel)
        resolved = try c.decode(Bool.self, forKey: .resolved)
        message = RequestLogPresentation.safeMessage(try c.decode(String.self, forKey: .message))
        userID = try c.decodeIfPresent(Int.self, forKey: .userID); accountID = try c.decodeIfPresent(Int.self, forKey: .accountID); groupID = try c.decodeIfPresent(Int.self, forKey: .groupID)
        accountName = try c.decodeIfPresent(String.self, forKey: .accountName); groupName = try c.decodeIfPresent(String.self, forKey: .groupName)
        upstreamStatusCode = try c.decodeIfPresent(Int.self, forKey: .upstreamStatusCode)
        upstreamMessage = try c.decodeIfPresent(String.self, forKey: .upstreamMessage).map(RequestLogPresentation.safeMessage)
        upstreamLatencyMs = try c.decodeIfPresent(Int.self, forKey: .upstreamLatencyMs); responseLatencyMs = try c.decodeIfPresent(Int.self, forKey: .responseLatencyMs); firstTokenMs = try c.decodeIfPresent(Int.self, forKey: .firstTokenMs)
    }
}

public enum RequestLogPresentation {
    public static func safeMessage(_ value: String) -> String {
        var value = String(value.prefix(4_096))
        // Header values can contain spaces (Basic/Digest auth and cookie lists).
        // Redact the whole header line instead of retaining a trailing credential.
        value = value.replacingOccurrences(of: #"(?i)\b(?:proxy-authorization|authorization|set-cookie|cookie)[\"']?\s*[:=]\s*[^\r\n]+"#, with: "[已隐藏凭据]", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)(https?://)[^/\s@]+@"#, with: "$1[已隐藏凭据]@", options: .regularExpression)
        for pattern in [#"(?i)(?:bearer|basic)\s+[^\s\"',;]+"#, #"(?i)\b(?:sk|sess|key)-[A-Za-z0-9_-]{8,}"#, #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, #"(?i)\b(?:api[_-]?key|x-api-key|access[_-]?token|refresh[_-]?token|session(?:_id|id|_token)?|token|secret|client_secret|password)[\"']?\s*[=:]\s*[\"']?[^\s\"',;}]+"#] {
            value = value.replacingOccurrences(of: pattern, with: "[已隐藏凭据]", options: .regularExpression)
        }
        return value
    }
    public static func date(_ raw: String) -> String {
        ServerTime.parseTimestamp(raw)?.formatted(date: .abbreviated, time: .standard) ?? raw
    }
}

extension APIClient {
    public func requestRecords(page: Int, filter: RequestLogFilter) async throws -> RequestLogPage<UsageRequestRecord> {
        try await request("admin/usage", query: filter.queryItems(page: page), timeout: RequestTimeout.read)
    }
    public func errorRecords(page: Int, filter: RequestLogFilter, kind: ErrorLogKind = .request) async throws -> RequestLogPage<RequestErrorRecord> {
        try await request("admin/ops/\(kind == .request ? "request-errors" : "upstream-errors")", query: filter.queryItems(page: page, errors: true, errorKind: kind), timeout: RequestTimeout.read)
    }
    public func errorRecord(id: Int, kind: ErrorLogKind = .request) async throws -> RequestErrorRecord {
        try await request("admin/ops/\(kind == .request ? "request-errors" : "upstream-errors")/\(validID(id))", timeout: RequestTimeout.read)
    }
}
