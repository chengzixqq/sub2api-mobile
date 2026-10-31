import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One failed upstream try in the detail's `upstream_errors` (40 §7.2 fallback). Only these keys are read: the event's
/// response body, URL, message and detail are never held. Each field is tolerant on its own, and 0 or negative reads as nil.
public struct UpstreamErrorEvent: Decodable, Sendable, Equatable {
    public let accountID: Int?
    /// Failover events often have no name.
    public let accountName: String?
    public let upstreamStatusCode: Int?
    public let atUnixMs: Int64?
    /// With `durationMs`, absent on rows written before the dispatch was observed and on WebSocket tries.
    public let startedAtUnixMs: Int64?
    public let durationMs: Int?
    public let kind: String?
    /// Set on the oldest kept event when the queue bound dropped earlier tries of the same request.
    public let droppedEarlierAttempts: Int

    public init(accountID: Int? = nil, accountName: String? = nil, upstreamStatusCode: Int? = nil, atUnixMs: Int64? = nil,
                startedAtUnixMs: Int64? = nil, durationMs: Int? = nil, kind: String? = nil, droppedEarlierAttempts: Int = 0) {
        self.accountID = accountID; self.accountName = accountName; self.upstreamStatusCode = upstreamStatusCode; self.atUnixMs = atUnixMs
        self.startedAtUnixMs = startedAtUnixMs; self.durationMs = durationMs; self.kind = kind; self.droppedEarlierAttempts = droppedEarlierAttempts
    }
    enum CodingKeys: String, CodingKey {
        case kind
        case accountID = "account_id", accountName = "account_name", upstreamStatusCode = "upstream_status_code", atUnixMs = "at_unix_ms"
        case startedAtUnixMs = "started_at_unix_ms", durationMs = "duration_ms", droppedEarlierAttempts = "dropped_earlier_attempts"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func positive<T: Decodable & BinaryInteger>(_ key: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: key)).flatMap { $0 > 0 ? $0 : nil } }
        func text(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)).flatMap { $0.isEmpty ? nil : $0 } }
        accountID = positive(.accountID); accountName = text(.accountName); upstreamStatusCode = positive(.upstreamStatusCode)
        atUnixMs = positive(.atUnixMs); startedAtUnixMs = positive(.startedAtUnixMs); kind = text(.kind)
        durationMs = (try? c.decodeIfPresent(Int.self, forKey: .durationMs)).flatMap { $0 >= 0 ? $0 : nil }
        droppedEarlierAttempts = positive(.droppedEarlierAttempts) ?? 0
    }
    /// The JSON array string of the detail; anything that is not an array of objects is an empty list.
    public static func parse(_ raw: String?) -> [UpstreamErrorEvent] {
        guard let raw, !raw.isEmpty else { return [] }
        return (try? JSONDecoder().decode(LossyList<UpstreamErrorEvent>.self, from: Data(raw.utf8)))?.items ?? []
    }
}

/// `GET admin/ops/request-errors/:id` or `upstream-errors/:id` (one table, 40 §7.2): the list record plus the detail-only
/// fields. `error_body` and `upstream_error_detail` are never decoded; messages are redacted by the record's decoding.
public struct RequestErrorDetail: Decodable, Identifiable, Sendable {
    public let record: RequestErrorRecord
    public let upstreamEvents: [UpstreamErrorEvent]
    public let authLatencyMs: Int?
    public let routingLatencyMs: Int?
    /// SLA wording: a business limit, drawn grey instead of by its code (40 §0.4).
    public let isBusinessLimited: Bool
    /// The bound key's first 8 characters, snapshotted at error time; shown as “prefix…”.
    public let apiKeyPrefix: String?

    public var id: Int { record.id }
    public var upstreamStatusCode: Int? { record.upstreamStatusCode }
    public var upstreamErrorMessage: String? { record.upstreamMessage }
    public var upstreamLatencyMs: Int? { record.upstreamLatencyMs }
    public var responseLatencyMs: Int? { record.responseLatencyMs }

    enum CodingKeys: String, CodingKey {
        case upstreamErrors = "upstream_errors", authLatencyMs = "auth_latency_ms", routingLatencyMs = "routing_latency_ms"
        case isBusinessLimited = "is_business_limited", apiKeyPrefix = "api_key_prefix"
    }
    public init(from decoder: any Decoder) throws {
        record = try RequestErrorRecord(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        upstreamEvents = UpstreamErrorEvent.parse(try? c.decodeIfPresent(String.self, forKey: .upstreamErrors))
        authLatencyMs = try c.decodeIfPresent(Int.self, forKey: .authLatencyMs)
        routingLatencyMs = try c.decodeIfPresent(Int.self, forKey: .routingLatencyMs)
        isBusinessLimited = try c.decodeIfPresent(Bool.self, forKey: .isBusinessLimited) ?? false
        let prefix = try c.decodeIfPresent(String.self, forKey: .apiKeyPrefix) ?? ""
        apiKeyPrefix = prefix.isEmpty ? nil : String(prefix.prefix(8))
    }
}

extension APIClient {
    /// R19: the only error-log detail (40 §7.2). `errorRecord(id:kind:)` stays for the old detail page until S4-08b.
    public func errorDetail(id: Int, kind: ErrorLogKind) async throws -> RequestErrorDetail {
        try await request("\(kind.opsPath)/\(validID(id))", timeout: RequestTimeout.read)
    }
    /// R19, 40 §7.4: writes an absolute value, so it carries no Idempotency-Key and needs no step-up; as an unkeyed write it is
    /// never resent on its own. 404 OPS_ERROR_NOT_FOUND / OPS_DISABLED and 403 ACCESS_TOKEN_READ_ONLY are thrown as they are.
    public func setErrorResolved(id: Int, kind: ErrorLogKind, resolved: Bool) async throws {
        let _: EmptyReply = try await request("\(kind.opsPath)/\(validID(id))/resolve", method: "PUT", body: encode(["resolved": resolved]))
    }
}
