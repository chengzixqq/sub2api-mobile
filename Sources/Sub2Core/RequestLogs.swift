import Foundation

public enum ErrorLogKind: String, CaseIterable, Sendable {
    case request, upstream
    /// The one spelling of both ops paths (S4D1-08): lists, counts, details and resolve all build on it.
    public var opsPath: String { self == .request ? "admin/ops/request-errors" : "admin/ops/upstream-errors" }
}

/// The `time_range` values the ops endpoints know; any other value silently falls back to 1h there.
public enum RollingWindow: String, CaseIterable, Sendable {
    case m5 = "5m", m30 = "30m", h1 = "1h", h6 = "6h", h24 = "24h", d7 = "7d", d30 = "30d"
}

/// 40 §6.7. `admin/usage` reads fixed bounds only, and no time at all means all time (so only next to a request ID);
/// the ops endpoints read fixed bounds or a rolling window, and no time there means the last hour.
public enum LogTimeWindow: Hashable, Sendable {
    case range(Date, Date)
    case rolling(RollingWindow)
    case none
    public static let maximumRange: TimeInterval = 366 * 86_400
}

public struct RequestLogFilter: Hashable, Sendable {
    public var time: LogTimeWindow
    public var accountID: Int?
    public var groupID: Int?
    public var userID: Int?
    public var model: String?
    /// Goes to `admin/usage` with `model` only; the error endpoints match the requested model and take no source.
    public var modelSource: ModelSource?
    public var requestID: String?
    /// 1…1000: 100 for lists (00 §4.3), 1 for counts, 5 for search.
    public var pageSize: Int
    // Conditions only the old filter editor still sets (40 §6.7 keeps them internal).
    public var apiKeyID: Int?
    public var requestType = ""
    public var category = ""
    public var resolved: Bool?
    public var statusCode: Int?
    public init(time: LogTimeWindow, accountID: Int? = nil, groupID: Int? = nil, userID: Int? = nil, model: String? = nil,
                modelSource: ModelSource? = nil, requestID: String? = nil, pageSize: Int = 100) {
        self.time = time; self.accountID = accountID; self.groupID = groupID; self.userID = userID; self.model = model
        self.modelSource = modelSource; self.requestID = requestID; self.pageSize = pageSize
    }
    /// Only for a server without D03, whose upstream errors filter by time, account, group and status alone.
    public func upstreamErrorFilter() -> Self {
        var copy = self
        copy.userID = nil; copy.apiKeyID = nil; copy.model = nil; copy.modelSource = nil; copy.requestID = nil
        copy.category = ""; copy.requestType = ""
        return copy
    }
    /// `timeZone` is the site's (00 §6.3); only `admin/usage` takes it. `key_view` is never here: it follows the caller's
    /// `maskedView` (S4D1-06).
    public func queryItems(page: Int, errors: Bool, timeZone: ServerTimeZone) throws -> [URLQueryItem] {
        guard page > 0 else { throw Self.invalid("请选择有效的时间范围（最长一年）和页码。") }
        guard (1...1_000).contains(pageSize) else { throw Self.invalid("每页条数须在 1–1000 之间。") }
        var values = try timeValues(errors: errors).merging(objectValues()) { first, _ in first }
        try values.merge(errors ? errorValues() : usageValues(timeZone: timeZone)) { first, _ in first }
        values["page"] = String(page); values["page_size"] = String(pageSize)
        values["sort_by"] = "created_at"; values["sort_order"] = "desc"
        return values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    /// The 00 §4.3 cursor read: the same object filters, `since_id` and page_size 100; no page, time or sort.
    public func incrementalQueryItems(sinceID: Int, errors: Bool, timeZone: ServerTimeZone) throws -> [URLQueryItem] {
        guard sinceID >= 0 else { throw Self.invalid("无效的增量游标。") }
        return IncrementalFetch.since(sinceID).queryItems(base: try queryItems(page: 1, errors: errors, timeZone: timeZone), deferredCount: false)
    }

    private func timeValues(errors: Bool) throws -> [String: String] {
        switch time {
        case .range(let start, let end):
            guard start < end, end.timeIntervalSince(start) <= LogTimeWindow.maximumRange else {
                throw Self.invalid("请选择有效的时间范围（最长一年）和页码。")
            }
            return ["start_time": ServerTime.utcTimestamp(start), "end_time": ServerTime.utcTimestamp(end)]
        case .rolling(let window):
            guard errors else { throw Self.invalid("使用记录只支持固定的起止时间。") }
            return ["time_range": window.rawValue]
        case .none:
            guard !errors else { throw Self.invalid("错误日志需要时间范围。") }
            guard Self.trimmed(requestID) != nil else { throw Self.invalid("使用记录需要时间范围或请求 ID。") }
            return [:]
        }
    }
    private func objectValues() throws -> [String: String] {
        var values: [String: String] = [:]
        for (key, value) in [("user_id", userID), ("account_id", accountID), ("group_id", groupID), ("api_key_id", apiKeyID)] {
            guard let value else { continue }
            guard value > 0 else { throw Self.invalid("筛选 ID 必须为正整数。") }
            values[key] = String(value)
        }
        if let model = Self.trimmed(model) { values["model"] = model }
        if let requestID = Self.trimmed(requestID) { values["request_id"] = requestID }
        return values
    }
    private func errorValues() throws -> [String: String] {
        var values = ["view": "all"]
        if !category.isEmpty { values["category"] = category }
        if let resolved { values["resolved"] = resolved ? "true" : "false" }
        if let statusCode {
            guard (100...599).contains(statusCode) else { throw Self.invalid("请输入有效 HTTP 状态码。") }
            values["status_codes"] = String(statusCode)
        }
        return values
    }
    private func usageValues(timeZone: ServerTimeZone) -> [String: String] {
        var values = ["timezone": timeZone.identifier, "count_mode": "deferred"]
        if let modelSource, Self.trimmed(model) != nil { values["model_source"] = modelSource.rawValue }
        if !requestType.isEmpty { values["request_type"] = requestType }
        return values
    }
    private static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
    private static func invalid(_ message: String) -> APIError { APIError(kind: .validation, message: message) }
}

/// Intentionally reads only public labels from nested DTOs, never the plaintext `api_key.key`, passwords or credentials.
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
    public let userName: String?
    public let apiKeyName: String?
    public let apiKeyMasked: String?
    public let accountName: String?
    public let groupName: String?
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let actualCost: Decimal?
    public let standardCost: Decimal?
    /// `account_cost` (D05); older servers fall back to the snapshot formula, zero when the provider cost was not recorded.
    public let accountCost: Decimal?
    /// nil before D05; only an explicit false means the row carries no account cost.
    public let providerCostRecorded: Bool?
    public let durationMs: Int?
    public let firstTokenMs: Int?
    public let requestType: String?
    public let stream: Bool?
    public let inboundEndpoint: String?
    public let upstreamRequestID: String?
    public var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }
    enum CodingKeys: String, CodingKey {
        case id, model, user, account, group, stream
        case apiKey = "api_key"
        case requestID = "request_id", createdAt = "created_at", upstreamModel = "upstream_model"
        case userID = "user_id", accountID = "account_id", apiKeyID = "api_key_id", groupID = "group_id"
        case inputTokens = "input_tokens", outputTokens = "output_tokens", cacheCreationTokens = "cache_creation_tokens", cacheReadTokens = "cache_read_tokens"
        case actualCost = "actual_cost", standardCost = "total_cost", accountStatsCost = "account_stats_cost", accountRateMultiplier = "account_rate_multiplier"
        case accountCost = "account_cost", providerCostRecorded = "provider_cost_recorded"
        case durationMs = "duration_ms", firstTokenMs = "first_token_ms", requestType = "request_type", inboundEndpoint = "inbound_endpoint", upstreamRequestID = "upstream_request_id"
    }
    private struct Name: Decodable { let name: String? }
    private struct UserLabel: Decodable { let email: String?; let username: String? }
    /// Has no `key` field on purpose.
    private struct KeyLabel: Decodable {
        let name: String?
        let keyMasked: String?
        enum CodingKeys: String, CodingKey { case name, keyMasked = "key_masked" }
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); requestID = try c.decode(String.self, forKey: .requestID)
        createdAt = try c.decode(String.self, forKey: .createdAt); model = try c.decode(String.self, forKey: .model)
        upstreamModel = try c.decodeIfPresent(String.self, forKey: .upstreamModel)
        userID = try c.decode(Int.self, forKey: .userID); accountID = try c.decode(Int.self, forKey: .accountID)
        apiKeyID = try c.decode(Int.self, forKey: .apiKeyID); groupID = try c.decodeIfPresent(Int.self, forKey: .groupID)
        let user = try c.decodeIfPresent(UserLabel.self, forKey: .user), key = try c.decodeIfPresent(KeyLabel.self, forKey: .apiKey)
        userEmail = nonEmpty(user?.email); userName = nonEmpty(user?.username)
        apiKeyName = nonEmpty(key?.name); apiKeyMasked = nonEmpty(key?.keyMasked)
        accountName = try c.decodeIfPresent(Name.self, forKey: .account)?.name; groupName = try c.decodeIfPresent(Name.self, forKey: .group)?.name
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0; outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        cacheCreationTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0; cacheReadTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
        actualCost = try c.optionalDecimal(.actualCost); standardCost = try c.optionalDecimal(.standardCost)
        providerCostRecorded = try c.decodeIfPresent(Bool.self, forKey: .providerCostRecorded)
        accountCost = try c.optionalDecimal(.accountCost) ?? Self.snapshotCost(c, recorded: providerCostRecorded, standard: standardCost)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs); firstTokenMs = try c.decodeIfPresent(Int.self, forKey: .firstTokenMs)
        requestType = try c.decodeIfPresent(String.self, forKey: .requestType); stream = try c.decodeIfPresent(Bool.self, forKey: .stream)
        inboundEndpoint = try c.decodeIfPresent(String.self, forKey: .inboundEndpoint); upstreamRequestID = try c.decodeIfPresent(String.self, forKey: .upstreamRequestID)
    }
    /// 40 §6.7: provider_cost_recorded ? (account_stats_cost ?? total_cost) × (account_rate_multiplier ?? 1) : 0.
    private static func snapshotCost(_ c: KeyedDecodingContainer<CodingKeys>, recorded: Bool?, standard: Decimal?) throws -> Decimal? {
        guard recorded != false else { return 0 }
        let base = try c.optionalDecimal(.accountStatsCost) ?? standard
        let multiplier = try c.optionalDecimal(.accountRateMultiplier) ?? 1
        return base.map { $0 * multiplier }
    }
}

/// No raw request/response body, upstream error detail, key prefix, client IP or user agent is retained.
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
    // D04 and the other row fields of 40 §6.2; old rows send null or "" (read as nil).
    public let durationMs: Int?
    public let errorOwner: String?
    public let errorSource: String?
    public let severity: String?
    public let clientRequestID: String?
    public let userEmail: String?
    public let apiKeyID: Int?
    public let apiKeyName: String?
    public let stream: Bool?
    /// The backend's number; `UsageRequestType(code:)` names it.
    public let requestType: Int16?
    public let resolvedAt: Date?
    public let resolvedByUserName: String?
    enum CodingKeys: String, CodingKey {
        case id, phase, type, platform, model, resolved, message, severity, stream
        case requestedModel = "requested_model", upstreamModel = "upstream_model"
        case createdAt = "created_at", requestID = "request_id", statusCode = "status_code", userID = "user_id", accountID = "account_id", groupID = "group_id"
        case accountName = "account_name", groupName = "group_name", upstreamStatusCode = "upstream_status_code", upstreamMessage = "upstream_error_message"
        case upstreamLatencyMs = "upstream_latency_ms", responseLatencyMs = "response_latency_ms", firstTokenMs = "time_to_first_token_ms"
        case durationMs = "duration_ms", errorOwner = "error_owner", errorSource = "error_source", clientRequestID = "client_request_id"
        case userEmail = "user_email", apiKeyID = "api_key_id", apiKeyName = "api_key_name", requestType = "request_type"
        case resolvedAt = "resolved_at", resolvedByUserName = "resolved_by_user_name"
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
        accountName = try c.nonEmptyString(.accountName); groupName = try c.nonEmptyString(.groupName)
        upstreamStatusCode = try c.decodeIfPresent(Int.self, forKey: .upstreamStatusCode)
        upstreamMessage = try c.decodeIfPresent(String.self, forKey: .upstreamMessage).map(RequestLogPresentation.safeMessage)
        upstreamLatencyMs = try c.decodeIfPresent(Int.self, forKey: .upstreamLatencyMs); responseLatencyMs = try c.decodeIfPresent(Int.self, forKey: .responseLatencyMs); firstTokenMs = try c.decodeIfPresent(Int.self, forKey: .firstTokenMs)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        errorOwner = try c.nonEmptyString(.errorOwner); errorSource = try c.nonEmptyString(.errorSource); severity = try c.nonEmptyString(.severity)
        clientRequestID = try c.nonEmptyString(.clientRequestID); userEmail = try c.nonEmptyString(.userEmail)
        apiKeyID = try c.decodeIfPresent(Int.self, forKey: .apiKeyID); apiKeyName = try c.nonEmptyString(.apiKeyName)
        stream = try c.decodeIfPresent(Bool.self, forKey: .stream); requestType = try c.decodeIfPresent(Int16.self, forKey: .requestType)
        resolvedAt = try c.optionalTimestamp(.resolvedAt); resolvedByUserName = try c.nonEmptyString(.resolvedByUserName)
    }
}

/// 40 §6.2 user filter: `admin/usage/search-users` (at most 30, deleted users included).
public struct UsageUserMatch: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let email: String
    public let deleted: Bool
    public init(id: Int, email: String, deleted: Bool = false) { self.id = id; self.email = email; self.deleted = deleted }
    enum CodingKeys: String, CodingKey { case id, email, deleted }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
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

/// The ops DTO writes absent text as "".
private func nonEmpty(_ value: String?) -> String? { value?.isEmpty == false ? value : nil }

private extension KeyedDecodingContainer {
    func nonEmptyString(_ key: Key) throws -> String? { nonEmpty(try decodeIfPresent(String.self, forKey: key)) }
}

/// Count replies are read for `total` only, not for their row.
private struct ErrorCountReply: Decodable, Sendable { let total: Int? }

/// `key_view=masked` only when the caller passes the site's `api_keys.masked_view` (00 §0 rule 8, S4D1-06).
private func keyViewItems(masked: Bool) -> [URLQueryItem] { masked ? [URLQueryItem(name: "key_view", value: "masked")] : [] }

extension APIClient {
    /// R19: the only usage-record list (logs, request-ID search). `maskedView` has no default: pass
    /// `session.has(.apiKeysMaskedView)`. The plaintext key an old server still sends is never decoded.
    public func requestRecords(page: Int, filter: RequestLogFilter, maskedView: Bool) async throws -> Page<UsageRequestRecord> {
        let query = try filter.queryItems(page: page, errors: false, timeZone: serverTimeZone()) + keyViewItems(masked: maskedView)
        return try await request("admin/usage", query: query, timeout: RequestTimeout.read)
    }
    public func requestRecords(sinceID: Int, filter: RequestLogFilter, maskedView: Bool) async throws -> Page<UsageRequestRecord> {
        let query = try filter.incrementalQueryItems(sinceID: sinceID, errors: false, timeZone: serverTimeZone()) + keyViewItems(masked: maskedView)
        return try await request("admin/usage", query: query, timeout: RequestTimeout.read)
    }
    public func errorRecords(page: Int, filter: RequestLogFilter, kind: ErrorLogKind) async throws -> Page<RequestErrorRecord> {
        let query = try filter.queryItems(page: page, errors: true, timeZone: serverTimeZone())
        return try await request(kind.opsPath, query: query, timeout: RequestTimeout.read)
    }
    /// Only request errors take `since_id`.
    public func errorRecords(sinceID: Int, filter: RequestLogFilter) async throws -> Page<RequestErrorRecord> {
        let query = try filter.incrementalQueryItems(sinceID: sinceID, errors: true, timeZone: serverTimeZone())
        return try await request(ErrorLogKind.request.opsPath, query: query, timeout: RequestTimeout.read)
    }
    /// R19: the only error count (“近 24 小时 N 条” in 10 §3.7, 20 §2.3, 50 §2.2). The list's own parameters with view=all,
    /// so the number matches the log page it opens.
    public func errorCount(filter: RequestLogFilter, kind: ErrorLogKind) async throws -> Int {
        var counted = filter
        counted.pageSize = 1
        let query = try counted.queryItems(page: 1, errors: true, timeZone: serverTimeZone())
        let reply: ErrorCountReply = try await request(kind.opsPath, query: query, timeout: RequestTimeout.read)
        guard let total = reply.total, total >= 0 else { throw APIError.invalidResponse }
        return total
    }
    /// A blank keyword sends nothing (the server would answer an empty list).
    public func searchUsageUsers(_ keyword: String) async throws -> [UsageUserMatch] {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return try await request("admin/usage/search-users", query: [URLQueryItem(name: "q", value: text)], timeout: RequestTimeout.read)
    }
    public func errorRecord(id: Int, kind: ErrorLogKind = .request) async throws -> RequestErrorRecord {
        try await request("\(kind.opsPath)/\(validID(id))", timeout: RequestTimeout.read)
    }
}
