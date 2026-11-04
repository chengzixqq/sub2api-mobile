import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - 运维监控接口（10 §4.2、§7.2；opsOverview 也供 40 §2.7）

extension APIClient {
    /// The only overview read (X08, R19): group and model follow OpsQuery, no `mode`; a 404 `OPS_DISABLED` is thrown unchanged.
    public func opsOverview(_ query: OpsQuery, supportsModelFilter: Bool) async throws -> OpsOverview {
        try query.validate()
        return try await request("admin/ops/dashboard/overview", query: query.queryItems(supportsModelFilter: supportsModelFilter),
                                 timeout: RequestTimeout.aggregate)
    }
    /// The last `timeRange` (a RollingWindow value) up to the server's now cut to a whole second, sent as start_time / end_time.
    public func opsOverview(timeRange: String) async throws -> OpsOverview {
        let span = try rollingSeconds(timeRange)
        let end = Date(timeIntervalSince1970: serverClock.now().timeIntervalSince1970.rounded(.down))
        return try await opsOverview(start: end.addingTimeInterval(-span), end: end)
    }
    public func opsOverview(start: Date, end: Date) async throws -> OpsOverview {
        try await opsOverview(OpsQuery(start: start, end: end), supportsModelFilter: false)
    }
    /// 10 §4.2 error-rate line: `mode=raw`; the ETag and 304 are handled by ConditionalCache.
    public func opsSnapshotV2(start: Date, end: Date) async throws -> OpsSnapshotV2 {
        let query = OpsQuery(start: start, end: end)
        try query.validate()
        let reply: OpsSnapshotV2.Reply = try await request("admin/ops/dashboard/snapshot-v2",
                                                           query: query.queryItems(supportsModelFilter: false) + [URLQueryItem(name: "mode", value: "raw")],
                                                           timeout: RequestTimeout.aggregate)
        return OpsSnapshotV2(reply: reply, windowStart: start, windowEnd: end)
    }
    public func opsConcurrency() async throws -> OpsConcurrency { try await request("admin/ops/concurrency") }
    /// Bucket averages over up to 31 days, so it waits as long as the statistics aggregates.
    public func systemMetricsHistory(timeRange: String = "1h", maxPoints: Int = 60) async throws -> SystemMetricsHistory {
        _ = try rollingSeconds(timeRange)
        guard SystemMetricsHistory.maxPointsRange.contains(maxPoints) else { throw APIError(kind: .validation, message: "采样点数须在 1–1440 之间。") }
        return try await request("admin/ops/system-metrics/history", query: [URLQueryItem(name: "time_range", value: timeRange),
                                                                           URLQueryItem(name: "max_points", value: String(maxPoints))],
                                 timeout: RequestTimeout.aggregate)
    }
    public func systemLogsHealth() async throws -> SystemLogHealth { try await request("admin/ops/system-logs/health") }
    public func ingressRejections(timeRange: String = "1h", page: Int = 1, pageSize: Int = 1) async throws -> IngressRejectList {
        _ = try rollingSeconds(timeRange)
        guard page >= 1, IngressRejectList.pageSizeRange.contains(pageSize) else { throw APIError(kind: .validation, message: "页码或每页条数无效。") }
        return try await request("admin/ops/ingress-rejections", query: [URLQueryItem(name: "time_range", value: timeRange),
                                                                       URLQueryItem(name: "page", value: String(page)),
                                                                       URLQueryItem(name: "page_size", value: String(pageSize))])
    }
    /// An old server without the route answers a non-JSON 404 (`.unsupported`); the caller treats that as unreadable.
    public func opsMonitoringStatus() async throws -> OpsMonitoringStatus { try await request("admin/ops/monitoring-status") }

    // Unkeyed writes (10 §7.2): no automatic retry and no Idempotency-Key. Pick one through OpsMonitoringWriteRoute.

    public func setOpsMonitoring(enabled: Bool) async throws -> OpsMonitoringStatus {
        try await request("admin/ops/monitoring-status", method: "PUT", body: encode(["monitoring_enabled": enabled]), requestClass: .unkeyedWrite)
    }
    /// Old servers only (`.legacySettings`). The reply is the whole settings object, secrets included, so it is never decoded.
    public func enableOpsMonitoringLegacy() async throws {
        let _: EmptyReply = try await request("admin/settings", method: "PUT", body: OpsMonitoringWriteRoute.legacyEnableBody, requestClass: .unkeyedWrite)
    }

    /// The server silently falls back to 1h for any other `time_range`, so a wrong value never leaves the App.
    private func rollingSeconds(_ timeRange: String) throws -> TimeInterval {
        guard let window = RollingWindow(rawValue: timeRange) else { throw APIError(kind: .validation, message: "请选择有效的时间范围。") }
        switch window {
        case .m5: return 300
        case .m30: return 1_800
        case .h1: return 3_600
        case .h6: return 21_600
        case .h24: return 86_400
        case .d7: return 604_800
        case .d30: return 2_592_000
        }
    }
}
