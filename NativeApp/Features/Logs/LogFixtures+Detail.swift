import Foundation
import Sub2Core

/// X44: the request detail's `-ui-testing` reads (S4-08), over LogFixtures' rows and DemoData+Accounts' newest upstream errors.
/// Scripted: usage 1040 (two tries), request error 2006 (two `upstream_errors`), upstream error 3005 (no client request id: its
/// request_id answers 409 and the nearer of the two ids two tries), and account 7's 9701 (three tries, one an old event without
/// timings, two dropped) and account 3's recovered 9703. Any other id draws its detail from the row it came with; usage 1039 and
/// the rest have no chain (404). S4-08b adds the resolve fixtures here.
extension LogFixtures {
    enum DetailArgument {
        /// Every detail answers 404 OPS_ERROR_NOT_FOUND.
        static let missing = "-ui-request-detail-missing"
        /// Every detail answers 500 OPS_ERROR_LOAD_FAILED.
        static let fails = "-ui-request-detail-fails"
        /// Every detail answers 404 OPS_DISABLED while admin/me still says on.
        static let opsDisabled = "-ui-request-detail-ops-disabled"
    }

    static func requestDetailSource(arguments: [String], row: RequestErrorRecord?) -> RequestDetailSource {
        RequestDetailSource(usageRecord: { try await requestUsageRecord(filter: $0) },
                            errorDetail: { try await requestDetail(id: $0, kind: $1, row: row, arguments: arguments) },
                            attempts: { try await requestChain(id: $0, around: $1) })
    }

    /// The scripted detail, or the row's fields with phase timings; neither is 404 OPS_ERROR_NOT_FOUND.
    static func requestDetail(id: Int, kind: ErrorLogKind, row: RequestErrorRecord?, arguments: [String]) async throws -> RequestErrorDetail {
        if arguments.contains(DetailArgument.missing) { throw APIError.server(status: 404, reason: "OPS_ERROR_NOT_FOUND") }
        if arguments.contains(DetailArgument.fails) { throw APIError.server(status: 500, reason: "OPS_ERROR_LOAD_FAILED") }
        if arguments.contains(DetailArgument.opsDisabled) { throw LiveOpsFixtures.opsDisabledError }
        let base: [String: Any]
        if let fields = accountErrorFields(id) {
            base = fields
        } else if let row, row.id == id {
            base = rowFields(row)
        } else {
            throw APIError.server(status: 404, reason: "OPS_ERROR_NOT_FOUND")
        }
        return try detailDecoded(base.merging(detailExtras(id)) { _, new in new })
    }

    /// The retry chains by the id the detail asks with; others answer 404 OPS_REQUEST_NOT_FOUND.
    static func requestChain(id: String, around: Date?) async throws -> RequestAttempts {
        switch id {
        case "client:00000000-0000-4000-8000-000000001040":
            return try chain(client: 200, dropped: 0, [
                attempt(1, account: 4, "OpenAI-主力-01", code: 429, ms: 400, upstreamID: "upreq-1040-1"),
                attempt(2, account: 1, "Claude-官方-01", code: 200, ms: 3_200, upstreamID: "upreq-1040", outcome: "success"),
            ])
        case clientRequestID(9_701):
            return try chain(client: 401, dropped: 2, [
                attempt(1, account: 7, "OpenAI-备用-A", code: 401, ms: 300, upstreamID: "upreq-9701-1"),
                attempt(2, account: 7, "OpenAI-备用-A", code: 500, ms: nil, upstreamID: nil),
                attempt(3, account: 7, "OpenAI-备用-A", code: 401, ms: 200, upstreamID: "upreq-9701-3"),
            ])
        case "req-err-3005":
            let at = around ?? Date()
            let metadata = ["client_request_ids": Self.newer3005 + "," + Self.nearer3005,
                            "client_request_id_times": [at.addingTimeInterval(3_000), at.addingTimeInterval(2)].map(ServerTime.utcTimestamp).joined(separator: ",")]
            throw APIError.server(status: 409, envelope: ErrorEnvelope(reason: "OPS_REQUEST_AMBIGUOUS", metadata: metadata))
        case Self.nearer3005:
            return try chain(client: 200, dropped: 0, [
                attempt(1, account: 3, "Claude-官方-03", code: 429, ms: 600, upstreamID: "upreq-3005-1"),
                attempt(2, account: 1, "Claude-官方-01", code: 200, ms: 2_400, upstreamID: "upreq-3005-2", outcome: "success"),
            ])
        default:
            throw APIError.server(status: 404, reason: "OPS_REQUEST_NOT_FOUND")
        }
    }

    /// No usage record is scripted for a request-ID lookup yet: a recovered row's success reads as not recorded.
    static func requestUsageRecord(filter: RequestLogFilter) async throws -> UsageRequestRecord? { nil }

    // MARK: Scripts

    private static let newer3005 = "00000000-0000-4000-9000-000000030051"
    private static let nearer3005 = "00000000-0000-4000-9000-000000030052"

    private static func clientRequestID(_ id: Int) -> String { "00000000-0000-4000-9000-00000000\(id)" }

    /// DemoData+Accounts' rows (same id, request_id, code, platform, model and message), with the fields the list row omits.
    private static func accountErrorFields(_ id: Int) -> [String: Any]? {
        let fields: [String: Any]
        switch id {
        case 9_701:
            fields = ["platform": "openai", "status_code": 401, "message": "Upstream authentication failed", "account_id": 7,
                      "account_name": "OpenAI-备用-A", "group_id": 2, "group_name": "标准组", "user_id": 8, "user_email": "siyuan.chen@example.com",
                      "api_key_id": 801, "api_key_name": "生产", "severity": "P1", "duration_ms": 1_600]
        case 9_703:
            fields = ["platform": "anthropic", "status_code": 200, "message": "Recovered upstream error 429: rate limited", "account_id": 3,
                      "account_name": "Claude-官方-03", "group_id": 1, "group_name": "高级组", "user_id": 3, "user_email": "xm.wang@example.com",
                      "api_key_id": 301, "api_key_name": "脚本", "severity": "P3", "duration_ms": 2_400]
        default:
            return nil
        }
        let common: [String: Any] = [
            "id": id, "created_at": ServerTime.utcTimestamp(Date().addingTimeInterval(id == 9_701 ? -60 : -300)), "request_id": "req-upstream-\(id)",
            "phase": "upstream", "type": "upstream_error", "model": "demo-model", "resolved": false, "error_owner": "provider",
            "client_request_id": clientRequestID(id), "stream": true, "request_type": 2,
        ]
        return common.merging(fields) { _, new in new }
    }
    /// What the detail adds to a row: the phase timings, the key's prefix and, where scripted, the upstream code and events.
    private static func detailExtras(_ id: Int) -> [String: Any] {
        var extras: [String: Any] = ["auth_latency_ms": 12, "routing_latency_ms": 30, "upstream_latency_ms": 1_900, "response_latency_ms": 158,
                                     "is_business_limited": false, "api_key_prefix": "sk-demo01"]
        let start = Int64(Date().timeIntervalSince1970 * 1_000) - 60_000
        switch id {
        case 2_006:
            extras["upstream_status_code"] = 429
            extras["upstream_errors"] = events([event(4, "OpenAI-主力-01", code: 429, at: start, ms: 500),
                                                event(7, "OpenAI-备用-A", code: 429, at: start + 1_200, ms: 400)])
        case 3_005:
            extras["upstream_status_code"] = 429
            extras["upstream_errors"] = events([event(3, "Claude-官方-03", code: 429, at: start, ms: 600)])
        case 9_701:
            extras["upstream_status_code"] = 401
            extras["upstream_error_message"] = "Upstream authentication failed: invalid api key"
            extras["upstream_errors"] = events([event(7, "OpenAI-备用-A", code: 401, at: start, ms: 300, dropped: 2),
                                                event(7, "OpenAI-备用-A", code: 500, at: start + 1_000, ms: nil),
                                                event(7, "OpenAI-备用-A", code: 401, at: start + 1_500, ms: 200)])
        case 9_703:
            extras["upstream_status_code"] = 429
        default:
            break
        }
        return extras
    }

    private static func attempt(_ index: Int, account: Int, _ name: String, code: Int, ms: Int?, upstreamID: String?,
                                outcome: String = "failed") -> [String: Any] {
        var fields: [String: Any] = ["index": index, "source": outcome == "success" ? "usage" : "upstream_error", "outcome": outcome,
                                     "account_id": account, "account_name": name, "upstream_status_code": code]
        // A try from before the deployment has neither its start nor its duration (40 §7.2).
        if let ms { fields["duration_ms"] = ms }
        if let upstreamID { fields["upstream_request_id"] = upstreamID }
        return fields
    }
    private static func chain(client: Int, dropped: Int, _ attempts: [[String: Any]]) throws -> RequestAttempts {
        try detailDecoded(["client_status_code": client, "attempts": attempts, "dropped_earlier_attempts": dropped])
    }
    /// An event without a duration has no start either, so the fallback estimates it from the previous event.
    private static func event(_ account: Int, _ name: String, code: Int, at: Int64, ms: Int?, dropped: Int = 0) -> [String: Any] {
        var fields: [String: Any] = ["account_id": account, "account_name": name, "upstream_status_code": code, "at_unix_ms": at, "kind": "http_error"]
        if let ms { fields["duration_ms"] = ms; fields["started_at_unix_ms"] = at - Int64(ms) }
        if dropped > 0 { fields["dropped_earlier_attempts"] = dropped }
        return fields
    }
    /// `upstream_errors` is a JSON array in a string.
    private static func events(_ list: [[String: Any]]) -> String {
        (try? JSONSerialization.data(withJSONObject: list)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }
    /// The list row's fields as the detail sends them.
    private static func rowFields(_ row: RequestErrorRecord) -> [String: Any] {
        var fields: [String: Any] = ["id": row.id, "created_at": row.createdAt, "request_id": row.requestID, "phase": row.phase, "type": row.type,
                                     "status_code": row.statusCode, "platform": row.platform, "model": row.model, "resolved": row.resolved,
                                     "message": row.message]
        let optional: [String: Any?] = [
            "upstream_model": row.upstreamModel, "user_id": row.userID, "account_id": row.accountID, "group_id": row.groupID,
            "account_name": row.accountName, "group_name": row.groupName, "upstream_status_code": row.upstreamStatusCode,
            "upstream_error_message": row.upstreamMessage, "upstream_latency_ms": row.upstreamLatencyMs, "response_latency_ms": row.responseLatencyMs,
            "time_to_first_token_ms": row.firstTokenMs, "duration_ms": row.durationMs, "error_owner": row.errorOwner, "error_source": row.errorSource,
            "severity": row.severity, "client_request_id": row.clientRequestID, "user_email": row.userEmail, "api_key_id": row.apiKeyID,
            "api_key_name": row.apiKeyName, "stream": row.stream, "request_type": row.requestType.map { Int($0) },
            "resolved_by_user_name": row.resolvedByUserName, "resolved_at": row.resolvedAt.map(ServerTime.utcTimestamp),
        ]
        for (key, value) in optional { if let value { fields[key] = value } }
        return fields
    }
    private static func detailDecoded<Value: Decodable>(_ object: [String: Any]) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
