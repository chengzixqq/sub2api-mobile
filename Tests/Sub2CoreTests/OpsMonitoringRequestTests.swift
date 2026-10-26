import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// MARK: - 运维监控接口（10 §4.2、§7.2，S1-02）

private enum OpsRequestFixture {
    static func utc(_ text: String) -> Date { ServerTime.parseTimestamp(text)! }
    static let start = utc("2026-10-23T01:15:00Z")
    static let end = utc("2026-10-23T02:00:00Z")
    static let statusJSON = #"{"config_enabled":true,"monitoring_enabled":true,"realtime_monitoring_enabled":true,"effective":true,"disabled_reason":null}"#
    static let snapshotJSON = """
        {"generated_at":"2026-10-23T02:00:01Z","overview":{"health_score":88,"error_rate":0.01},"throughput_trend":{"bucket":"1m","points":[\
        {"bucket_start":"2026-10-23T01:15:00Z","request_count":100,"token_consumed":1,"switch_count":0,"qps":1.7,"tps":0},\
        {"bucket_start":"bad","request_count":5},{"bucket_start":"2026-10-23T01:16:00Z"},null]},"error_trend":{"bucket":"1m","points":[\
        {"bucket_start":"2026-10-23T01:15:00Z","error_count_total":3,"business_limited_count":1,"error_count_sla":2},\
        {"bucket_start":"2026-10-23T01:16:00Z","error_count_sla":1},{"error_count_sla":9}]}}
        """
    /// Answers each server-section path with a small valid body.
    static func serverReply(_ request: URLRequest) -> HTTPResponse {
        let path = request.url?.path ?? ""
        if path.hasSuffix("/concurrency") { return okReply(#"{"enabled":true,"platform":{}}"#) }
        if path.hasSuffix("/system-metrics/history") { return okReply(#"{"bucket_seconds":60,"points":[]}"#) }
        if path.hasSuffix("/system-logs/health") { return okReply(#"{"avg_write_delay_ms":850,"last_error":""}"#) }
        if path.hasSuffix("/ingress-rejections") { return okReply(#"{"items":[],"total":0,"page":1,"page_size":1,"request_count_total":0,"by_reason":[]}"#) }
        if path.hasSuffix("/monitoring-status") { return okReply(statusJSON) }
        if path.hasSuffix("/dashboard/snapshot-v2") { return okReply(snapshotJSON) }
        return okReply(opsOverviewFullJSON)
    }
}

private func opsClient(_ transport: ScriptedTransport, serverClock: ServerClock = ServerClock(),
                       cacheIdentity: ConditionalCache.Identity? = nil) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate,
              cacheIdentity: cacheIdentity, serverClock: serverClock)
}
private func sentQuery(_ request: URLRequest?) -> [URLQueryItem] {
    request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
}
private func sentValues(_ request: URLRequest?) -> [String: String] {
    Dictionary(sentQuery(request).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

@Test func opsOverviewQueryMapsFiltersThroughOpsQuery() async throws {
    let transport = ScriptedTransport { _ in okReply(opsOverviewFullJSON) }
    let client = opsClient(transport)
    let query = OpsQuery(start: OpsRequestFixture.start, end: OpsRequestFixture.end, groupID: 3, model: "m+1", modelSource: .upstream)
    let overview = try await client.opsOverview(query, supportsModelFilter: true)
    _ = try await client.opsOverview(query, supportsModelFilter: false)
    let sent = await transport.requests
    #expect(overview.healthScore == 92)
    #expect(sent.count == 2 && sent.allSatisfy { $0.httpMethod == "GET" && $0.url?.path == "/api/v1/admin/ops/dashboard/overview" })
    #expect(sentQuery(sent[0]) == query.queryItems(supportsModelFilter: true))
    #expect(sentValues(sent[0]) == ["start_time": "2026-10-23T01:15:00Z", "end_time": "2026-10-23T02:00:00Z", "group_id": "3",
                                    "model": "m+1", "model_source": "upstream"])
    #expect(sentQuery(sent[1]) == query.queryItems(supportsModelFilter: false))
    #expect(sentQuery(sent[1]).map(\.name) == ["start_time", "end_time", "group_id"])
    #expect(sent.allSatisfy { $0.timeoutInterval == RequestTimeout.aggregate && sentHeader($0, "Idempotency-Key") == nil && $0.httpBody == nil })
}

@Test(arguments: [(0.0, nil), (-60.0, nil), (300.0, 0), (300.0, -2)] as [(TimeInterval, Int?)])
func opsOverviewValidatesQueryBeforeSending(span: TimeInterval, groupID: Int?) async {
    let transport = ScriptedTransport { _ in okReply(opsOverviewFullJSON) }
    let query = OpsQuery(start: OpsRequestFixture.start, end: OpsRequestFixture.start.addingTimeInterval(span), groupID: groupID)
    let error = await thrownAPIError { _ = try await opsClient(transport).opsOverview(query, supportsModelFilter: true) }
    #expect(error?.kind == .validation)
    #expect(await transport.requests.isEmpty)
}

@Test func opsOverviewConvenienceMethodsWrapOpsQuery() async throws {
    let transport = ScriptedTransport { _ in okReply(opsOverviewFullJSON) }
    let localNow = OpsRequestFixture.utc("2026-10-23T02:00:00.700Z")
    let client = opsClient(transport, serverClock: ServerClock(offset: 30, localNow: { localNow }))
    let overview = try await client.opsOverview(timeRange: "5m")
    #expect(abs((overview.windowSeconds ?? 0) - 300) < 0.001)
    var shanghai = Calendar(identifier: .gregorian); shanghai.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let dayStart = try #require(shanghai.date(from: DateComponents(year: 2026, month: 10, day: 23)))
    _ = try await client.opsOverview(start: dayStart, end: dayStart.addingTimeInterval(36_000))
    _ = try await client.opsOverview(timeRange: "1h")
    let sent = await transport.requests
    #expect(sent.count == 3)
    #expect(sentQuery(sent[0]) == [URLQueryItem(name: "start_time", value: "2026-10-23T01:55:30Z"),
                                   URLQueryItem(name: "end_time", value: "2026-10-23T02:00:30Z")])
    #expect(sentQuery(sent[1]) == [URLQueryItem(name: "start_time", value: "2026-10-22T16:00:00Z"),
                                   URLQueryItem(name: "end_time", value: "2026-10-23T02:00:00Z")])
    #expect(sentValues(sent[2])["start_time"] == "2026-10-23T01:00:30Z")
    #expect(sent.allSatisfy { $0.url?.query?.contains("+") == false && $0.url?.query?.contains("time_range") == false })
    #expect(sent.allSatisfy { $0.timeoutInterval == RequestTimeout.aggregate })
    for invalid in ["2h", "", " 5m", "15m"] {
        let error = await thrownAPIError { _ = try await client.opsOverview(timeRange: invalid) }
        #expect(error?.kind == .validation)
    }
    #expect(await transport.requests.count == 3)
}

@Test func opsSnapshotV2SendsRawModeAndHandlesETag() async throws {
    let transport = ScriptedTransport { request in
        sentHeader(request, "If-None-Match") == "\"s1\""
            ? HTTPResponse(statusCode: 304, headers: ["etag": "\"s1\""], data: Data())
            : okReply(OpsRequestFixture.snapshotJSON, headers: ["etag": "\"s1\""])
    }
    let client = opsClient(transport, cacheIdentity: ConditionalCache.Identity(userID: 1, authMethod: "admin_api_key"))
    let start = OpsRequestFixture.start, end = OpsRequestFixture.end
    let first = try await client.opsSnapshotV2(start: start, end: end)
    let second = try await client.opsSnapshotV2(start: start, end: end)
    #expect(second == first)
    #expect(first.windowStart == start && first.windowEnd == end)
    #expect(first.generatedAt == OpsRequestFixture.utc("2026-10-23T02:00:01Z"))
    #expect(first.overview?.healthScore == 88 && first.overview?.errorRate == 0.01)
    let minute = OpsRequestFixture.utc("2026-10-23T01:16:00Z")
    #expect(first.throughputPoints == [OpsSnapshotV2.ThroughputPoint(bucketStart: start, requestCount: 100),
                                       OpsSnapshotV2.ThroughputPoint(bucketStart: minute, requestCount: 0)])
    #expect(first.errorPoints == [OpsSnapshotV2.ErrorPoint(bucketStart: start, errorCountSLA: 2, businessLimitedCount: 1),
                                  OpsSnapshotV2.ErrorPoint(bucketStart: minute, errorCountSLA: 1, businessLimitedCount: 0)])
    let sent = await transport.requests
    #expect(sent.count == 2 && sent.allSatisfy { $0.url?.path == "/api/v1/admin/ops/dashboard/snapshot-v2" && $0.httpMethod == "GET" })
    #expect(sentValues(sent[0]) == ["start_time": "2026-10-23T01:15:00Z", "end_time": "2026-10-23T02:00:00Z", "mode": "raw"])
    #expect(sentHeader(sent[0], "If-None-Match") == nil); #expect(sentHeader(sent[1], "If-None-Match") == "\"s1\"")
    #expect(sent.allSatisfy { $0.timeoutInterval == RequestTimeout.aggregate })
    let error = await thrownAPIError { _ = try await client.opsSnapshotV2(start: end, end: start) }
    #expect(error?.kind == .validation)
    #expect(await transport.requests.count == 2)
}

@Test func serverSectionReadsUseSpecPathsQueriesAndTimeouts() async throws {
    let transport = ScriptedTransport { OpsRequestFixture.serverReply($0) }
    let client = opsClient(transport)
    #expect(try await client.opsConcurrency() == OpsConcurrency())
    #expect(try await client.systemMetricsHistory() == SystemMetricsHistory(bucketSeconds: 60))
    #expect(try await client.systemLogsHealth() == SystemLogHealth(avgWriteDelayMs: 850, lastError: ""))
    #expect(try await client.ingressRejections().requestCountTotal == 0)
    _ = try await client.ingressRejections(page: 2, pageSize: 200)
    _ = try await client.systemMetricsHistory(timeRange: "24h", maxPoints: 1_440)
    #expect(try await client.opsMonitoringStatus().reason == .unknown)
    let sent = await transport.requests
    let paths = sent.map { $0.url?.path ?? "" }
    #expect(paths == ["/api/v1/admin/ops/concurrency", "/api/v1/admin/ops/system-metrics/history", "/api/v1/admin/ops/system-logs/health",
                      "/api/v1/admin/ops/ingress-rejections", "/api/v1/admin/ops/ingress-rejections", "/api/v1/admin/ops/system-metrics/history",
                      "/api/v1/admin/ops/monitoring-status"])
    #expect(sentQuery(sent[0]).isEmpty && sentQuery(sent[2]).isEmpty && sentQuery(sent[6]).isEmpty)
    #expect(sentValues(sent[1]) == ["time_range": "1h", "max_points": "60"])
    #expect(sentValues(sent[3]) == ["time_range": "1h", "page": "1", "page_size": "1"])
    #expect(sentValues(sent[4]) == ["time_range": "1h", "page": "2", "page_size": "200"])
    #expect(sentValues(sent[5]) == ["time_range": "24h", "max_points": "1440"])
    #expect(sent.map(\.timeoutInterval) == [RequestTimeout.read, RequestTimeout.aggregate, RequestTimeout.read, RequestTimeout.read,
                                            RequestTimeout.read, RequestTimeout.aggregate, RequestTimeout.read])
    #expect(sent.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && sentHeader($0, "Idempotency-Key") == nil })
}

@Test func serverSectionRejectsInvalidParametersBeforeSending() async {
    let transport = ScriptedTransport { OpsRequestFixture.serverReply($0) }
    let client = opsClient(transport)
    let calls: [@Sendable () async throws -> Void] = [
        { _ = try await client.systemMetricsHistory(maxPoints: 0) }, { _ = try await client.systemMetricsHistory(maxPoints: 1_441) },
        { _ = try await client.systemMetricsHistory(timeRange: "2h") }, { _ = try await client.ingressRejections(page: 0) },
        { _ = try await client.ingressRejections(pageSize: 0) }, { _ = try await client.ingressRejections(pageSize: 201) },
        { _ = try await client.ingressRejections(timeRange: "90m") }
    ]
    for call in calls { #expect(await thrownAPIError(call)?.kind == .validation) }
    #expect(await transport.requests.isEmpty)
}

@Test func setOpsMonitoringSendsOnlyMonitoringEnabled() async throws {
    let transport = ScriptedTransport { _ in okReply(OpsRequestFixture.statusJSON) }
    let client = opsClient(transport)
    let status = try await client.setOpsMonitoring(enabled: true)
    _ = try await client.setOpsMonitoring(enabled: false)
    #expect(status == OpsMonitoringStatus(configEnabled: true, monitoringEnabled: true, realtimeMonitoringEnabled: true, effective: true))
    let sent = await transport.requests
    #expect(sent.count == 2 && sent.allSatisfy { $0.httpMethod == "PUT" && $0.url?.path == "/api/v1/admin/ops/monitoring-status" })
    #expect(sent[0].httpBody == Data(#"{"monitoring_enabled":true}"#.utf8))
    #expect(sent[1].httpBody == Data(#"{"monitoring_enabled":false}"#.utf8))
    for request in sent {
        #expect(sentQuery(request).isEmpty)
        #expect(sentHeader(request, "Content-Type") == "application/json")
        #expect(sentHeader(request, "Idempotency-Key") == nil)
        let requestID = try #require(sentHeader(request, "X-Request-ID"))
        #expect(UUID(uuidString: requestID) != nil && requestID == requestID.lowercased())
        #expect(request.timeoutInterval == RequestTimeout.unkeyedWrite)
    }
    #expect(sentHeader(sent[0], "X-Request-ID") != sentHeader(sent[1], "X-Request-ID"))
}

/// Internal so the parameterized tests below can stay internal.
enum OpsMonitoringWriteCase: CaseIterable, Sendable {
    case monitoringStatus, legacySettings
    func send(_ client: APIClient) async throws {
        switch self {
        case .monitoringStatus: _ = try await client.setOpsMonitoring(enabled: true)
        case .legacySettings: try await client.enableOpsMonitoringLegacy()
        }
    }
}

@Test(arguments: OpsMonitoringWriteCase.allCases)
func opsMonitoringWritesAreNeverRetried(write: OpsMonitoringWriteCase) async {
    let failures: [ScriptStep] = [.fail(URLError(.timedOut)), .fail(URLError(.networkConnectionLost)), .reply(errorReply(503)),
                                  .reply(errorReply(502)), .reply(errorReply(504))]
    for failure in failures {
        let transport = ScriptedTransport(script: [failure, .reply(okReply(OpsRequestFixture.statusJSON))])
        #expect(await thrownAPIError { try await write.send(opsClient(transport)) } != nil)
        #expect(await transport.requests.count == 1)
    }
    let configOff = ScriptedTransport(script: [.reply(errorReply(409, reason: "OPS_CONFIG_DISABLED"))])
    let configError = await thrownAPIError { try await write.send(opsClient(configOff)) }
    #expect(configError?.reason == "OPS_CONFIG_DISABLED" && configError?.kind == .featureDisabled)
    #expect(await configOff.requests.count == 1)
    let readOnly = ScriptedTransport(script: [.reply(errorReply(403, reason: "ACCESS_TOKEN_READ_ONLY"))])
    #expect(await thrownAPIError { try await write.send(opsClient(readOnly)) }?.reason == "ACCESS_TOKEN_READ_ONLY")
    #expect(await readOnly.requests.count == 1)
}

@Test func legacyEnableBodyHasExactlyOneKey() async throws {
    let fullSettings = #"{"site_name":"测试站","registration_enabled":true,"smtp_password":"fixture-secret","ops_monitoring_enabled":true,"default_concurrency":5}"#
    let transport = ScriptedTransport { _ in okReply(fullSettings) }
    try await opsClient(transport).enableOpsMonitoringLegacy()
    let sent = await transport.requests
    let request = try #require(sent.first)
    #expect(sent.count == 1)
    #expect(request.httpMethod == "PUT" && request.url?.path == "/api/v1/admin/settings" && sentQuery(request).isEmpty)
    let body = try #require(request.httpBody)
    #expect(body == Data(#"{"ops_monitoring_enabled":true}"#.utf8))
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(Array(object.keys) == ["ops_monitoring_enabled"]); #expect(object["ops_monitoring_enabled"] as? Bool == true)
    #expect(sentHeader(request, "Idempotency-Key") == nil); #expect(sentHeader(request, "X-Request-ID") != nil)
    #expect(request.timeoutInterval == RequestTimeout.unkeyedWrite)
}

enum OpsMonitoringReadCase: CaseIterable, Sendable {
    case overview, snapshot, concurrency, history, logHealth, ingress
    func send(_ client: APIClient) async throws {
        switch self {
        case .overview: _ = try await client.opsOverview(timeRange: "5m")
        case .snapshot: _ = try await client.opsSnapshotV2(start: OpsRequestFixture.start, end: OpsRequestFixture.end)
        case .concurrency: _ = try await client.opsConcurrency()
        case .history: _ = try await client.systemMetricsHistory()
        case .logHealth: _ = try await client.systemLogsHealth()
        case .ingress: _ = try await client.ingressRejections()
        }
    }
}

@Test(arguments: OpsMonitoringReadCase.allCases)
func opsReadsSurfaceOpsDisabledUnchanged(read: OpsMonitoringReadCase) async {
    let transport = ScriptedTransport { _ in HTTPResponse(statusCode: 404, headers: [:], data: Data(#"{"code":404,"message":"x","reason":"OPS_DISABLED"}"#.utf8)) }
    let error = await thrownAPIError { try await read.send(opsClient(transport)) }
    #expect(error?.kind == .featureDisabled && error?.reason == "OPS_DISABLED" && error?.statusCode == 404)
    #expect(await transport.requests.count == 1)
}

@Test func monitoringStatusOnOldServerIsUnsupported() async {
    let transport = ScriptedTransport { _ in HTTPResponse(statusCode: 404, headers: ["content-type": "text/plain"], data: Data("404 page not found".utf8)) }
    let error = await thrownAPIError { _ = try await opsClient(transport).opsMonitoringStatus() }
    #expect(error?.kind == .unsupported)
    #expect(await transport.requests.count == 1)
}

@Test func writeRouteFollowsCapabilityAndAdminMe() {
    let withStatus = AdminMe(server: .init(capabilities: [Capability.opsMonitoringStatus.rawValue, Capability.dashboardHome.rawValue]))
    #expect(OpsMonitoringWriteRoute.resolve(me: withStatus) == .monitoringStatus)
    let withoutStatus = AdminMe(server: .init(capabilities: [Capability.dashboardHome.rawValue]))
    #expect(OpsMonitoringWriteRoute.resolve(me: withoutStatus) == .legacySettings)
    #expect(OpsMonitoringWriteRoute.resolve(me: AdminMe()) == .legacySettings)
    let legacy = AdminMe(features: .init(opsMonitoringEnabled: false, opsMonitoringDisabledReason: "setting_off"), isLegacyServer: true)
    #expect(OpsMonitoringWriteRoute.resolve(me: legacy) == .unavailable)
    let legacyClaimingStatus = AdminMe(server: .init(capabilities: [Capability.opsMonitoringStatus.rawValue]), isLegacyServer: true)
    #expect(OpsMonitoringWriteRoute.resolve(me: legacyClaimingStatus) == .monitoringStatus)
}
