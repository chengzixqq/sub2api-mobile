import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The fields of a new silence (10 §7.1). `group_id` is always written, as null when the rule's scope has no group;
/// region and reason are never sent.
private struct AlertSilenceBody: Encodable, Sendable {
    let ruleID: Int
    let platform: String
    let groupID: Int?
    let until: String
    enum CodingKeys: String, CodingKey { case platform, until; case ruleID = "rule_id", groupID = "group_id" }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ruleID, forKey: .ruleID); try c.encode(platform, forKey: .platform); try c.encode(until, forKey: .until)
        if let groupID { try c.encode(groupID, forKey: .groupID) } else { try c.encodeNil(forKey: .groupID) }
    }
}

extension APIClient {
    /// 10 §6.2, R19: the only alert-event list (monitor alerts, the account group header, the group banner). Newest first as the
    /// server orders them. Blank filters are left out; `platform` is matched exactly by the server, so only its spaces go.
    public func alertEvents(status: String? = nil, timeRange: String? = nil, limit: Int, before: AlertEventCursor? = nil,
                            groupID: Int? = nil, platform: String? = nil) async throws -> [AlertEvent] {
        let group = try groupID.map { [URLQueryItem(name: "group_id", value: String(try validID($0)))] } ?? []
        let range = AlertEvent.listLimit
        let query = optionalQuery("status", trimmed(status)) + optionalQuery("time_range", trimmed(timeRange))
            + [URLQueryItem(name: "limit", value: String(min(max(limit, range.lowerBound), range.upperBound)))]
            + (before?.queryItems ?? []) + group + optionalQuery("platform", trimmed(platform))
        let reply: LossyList<AlertEvent> = try await request("admin/ops/alert-events", query: query)
        return reply.items
    }
    public func alertEventCounts() async throws -> AlertCounts { try await request("admin/ops/alert-events/counts") }
    public func alertEvent(id: Int) async throws -> AlertEvent { try await request("admin/ops/alert-events/\(validID(id))") }
    /// Rule summaries for events from a server without `ops.alert_event_details`.
    public func alertRules() async throws -> [AlertEventRule] {
        let reply: LossyList<AlertEventRule> = try await request("admin/ops/alert-rules")
        return reply.items
    }

    // Unkeyed writes (10 §7.1): no automatic retry and no Idempotency-Key; S1-06 reads the event back to confirm.

    /// The server answers `updated: true` even for an event that does not exist (BACKLOG D06), so nothing is returned.
    public func setAlertEventStatus(id: Int, status: String = AlertEvent.manualResolved) async throws {
        let path = "admin/ops/alert-events/\(try validID(id))/status"
        guard [AlertEvent.manualResolved, "resolved"].contains(status) else { throw APIError(kind: .validation, message: "无效的告警状态。") }
        let _: EmptyReply = try await request(path, method: "PUT", body: encode(["status": status]))
    }
    public func createAlertSilence(ruleID: Int, platform: String?, groupID: Int?, until: Date) async throws -> AlertSilence {
        let body = AlertSilenceBody(ruleID: try validID(ruleID), platform: trimmed(platform) ?? "", groupID: try groupID.map { try validID($0) },
                                    until: ServerTime.utcTimestamp(until))
        return try await request("admin/ops/alert-silences", method: "POST", body: encode(body))
    }
    /// The server also cuts every later silence of the same scope to `until`.
    public func updateAlertSilence(id: Int, until: Date) async throws -> AlertSilence {
        try await request("admin/ops/alert-silences/\(validID(id))", method: "PUT", body: encode(["until": ServerTime.utcTimestamp(until)]))
    }
    /// Ends every active silence of the same scope now.
    public func deleteAlertSilence(id: Int) async throws {
        let _: EmptyReply = try await request("admin/ops/alert-silences/\(validID(id))", method: "DELETE")
    }
}

private func trimmed(_ value: String?) -> String? { value?.trimmingCharacters(in: .whitespacesAndNewlines) }

extension AlertEvent {
    /// The server caps `limit` at 500 and rejects anything below 1.
    public static let listLimit: ClosedRange<Int> = 1...500
}
