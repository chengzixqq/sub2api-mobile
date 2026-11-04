import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let firstBucketStart = ServerTime.parseTimestamp("2026-10-22T00:25:00Z")!

private func decodeOverview(_ json: String) throws -> ChannelOverview { try JSONDecoder().decode(ChannelOverview.self, from: Data(json.utf8)) }
private func channelClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate)
}
/// One backend ObservationBucket: 5 minutes after the previous one, with the full metrics block.
private func bucketJSON(_ index: Int) -> String {
    let start = ServerTime.utcTimestamp(firstBucketStart.addingTimeInterval(Double(index) * 300))
    return #"""
    {"bucket_start":"\#(start)","sample_start":"\#(start)","metrics":{"success_requests":50,"channel_errors":0,"client_errors":0,
     "cancelled_requests":0,"unknown_requests":0,"request_count":50,"success_rate":1,"reliability_rate":1,"sample_state":"sufficient",
     "cache_rate":null,"ttft":{"sample_count":50,"p50_ms":900,"p90_ms":null,"p95_ms":null,"avg_ms":950.5},
     "duration":{"sample_count":50,"p50_ms":3000,"p90_ms":4000,"p95_ms":5000,"avg_ms":3200},"rpm":0.6,"tpm":800,
     "retry_recovered_requests":0,"attempt_count":50},"health":{"reliability":"\#(index == 0 ? "unknown" : "healthy")","latency":"healthy"}}
    """#
}
private let backendOverviewJSON = #"""
{"presentation_defaults":{"range":"90m","refresh":"auto"},"presentation_defaults_version":1,"refresh_interval_seconds":60,
 "contract_version":2,"source":"traffic","mode":"v2",
 "coverage":{"state":"complete","detail_retention_hours":24,"unsupported_protocols":[],"collector_state":"healthy",
  "last_ingested_at":"2026-10-22T01:59:30Z","gap_reasons":[]},
 "dimensions":{"platforms":["openai"],"groups":[3]},
 "items":[{"source":"traffic","platform":"openai","group_id":3,"group_name":"标准组","rate_multiplier":1,
   "metrics":{"success_requests":996,"channel_errors":4,"client_errors":2,"cancelled_requests":0,"unknown_requests":1,"request_count":1000,
    "success_rate":0.994,"reliability_rate":0.996,"sample_state":"sufficient","cache_rate":null,
    "ttft":{"sample_count":990,"p50_ms":1400,"p90_ms":2100,"p95_ms":2600,"avg_ms":1500.2},
    "duration":{"sample_count":990,"p50_ms":3000,"p90_ms":4000,"p95_ms":5000,"avg_ms":3200},"rpm":11.1,"tpm":20000,
    "retry_recovered_requests":0,"attempt_count":1000,"error_categories":{"upstream_5xx":4}},
   "health":{"reliability":"healthy","latency":"healthy"},"buckets":[\#((0..<19).map(bucketJSON).joined(separator: ","))],"models":[],
   "current_status":{"state":"healthy","source":"traffic","updated_at":"2026-10-22T01:58:00Z","reason":"recent_traffic"},
   "traffic":{"success_requests":996,"channel_errors":4,"request_count":1000},"probe":null}]}
"""#

@Test func decodesBackendOverviewShape() throws {
    let overview = try decodeOverview(backendOverviewJSON)
    #expect(overview.refreshIntervalSeconds == 60)
    #expect(overview.coverage == ChannelCoverage(state: "complete", collectorState: "healthy"))
    let item = try #require(overview.items.first)
    #expect(overview.items.count == 1 && item.id == 3)
    #expect(item.platform == "openai" && item.groupID == 3 && item.groupName == "标准组")
    #expect(item.currentStatus == ChannelCurrentStatus(state: "healthy", reason: "recent_traffic",
                                                       updatedAt: ServerTime.parseTimestamp("2026-10-22T01:58:00Z")))
    #expect(item.metrics == ChannelMetrics(reliabilityRate: 0.996, successRate: 0.994, requestCount: 1000, channelErrors: 4,
                                           successRequests: 996, sampleState: "sufficient", ttft: ChannelLatency(p50Ms: 1400)))
    #expect(item.buckets.count == 19 && item.buckets.first?.reliability == "unknown" && item.buckets.last?.reliability == "healthy")
    let starts = item.buckets.compactMap(\.bucketStart)
    #expect(starts.count == 19 && starts == starts.sorted() && starts.first == firstBucketStart)
    #expect(item.buckets[1].metrics?.ttft?.p50Ms == 900 && item.buckets[1].metrics?.reliabilityRate == 1)
}

@Test func channelOverviewToleratesMissingAndNullFields() throws {
    let overview = try decodeOverview(#"""
    {"items":[{"platform":"anthropic","group_id":5,"group_name":"","metrics":{"reliability_rate":null,"success_rate":null,"ttft":{"p50_ms":null}},
               "current_status":{"state":"unknown","reason":"no_samples"}},
              {"platform":"openai","group_name":"无编号","current_status":"bad","buckets":[{"bucket_start":"soon","health":null},7]},
              {"group_id":"x","metrics":[]}]}
    """#)
    #expect(overview.refreshIntervalSeconds == nil && overview.coverage == nil && overview.items.count == 3)
    let first = overview.items[0]
    #expect(first.groupName == "" && first.metrics?.reliabilityRate == nil && first.metrics?.successRate == nil)
    #expect(first.metrics?.ttft == ChannelLatency(p50Ms: nil) && first.buckets.isEmpty)
    #expect(first.currentStatus == ChannelCurrentStatus(state: "unknown", reason: "no_samples", updatedAt: nil))
    let second = overview.items[1]
    #expect(second.groupID == 0 && second.currentStatus == nil && second.buckets == [ChannelBucket()])
    #expect(overview.items[2] == ChannelItem())
    #expect(try decodeOverview("{}") == ChannelOverview())
    #expect(try decodeOverview(#"{"items":null,"coverage":null,"refresh_interval_seconds":"60"}"#) == ChannelOverview())
}

@Test func channelOverviewAlwaysSendsRange() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"refresh_interval_seconds":45,"items":[]}"#) }
    let client = channelClient(transport)
    let overview = try await client.channelOverview()
    _ = try await client.channelOverview(refresh: true)
    _ = try await client.channelOverview(range: "24h")
    _ = try await client.channelOverview(range: " 90m ")
    let sent = await transport.requests
    #expect(sent.count == 4 && sent.allSatisfy { $0.httpMethod == "GET" && $0.url?.path == "/api/v1/admin/channel-monitor-v2/overview" })
    #expect(sent.map { $0.url?.query } == ["range=90m", "range=90m&refresh=true", "range=24h", "range=90m"])
    #expect(sent.allSatisfy { sentHeader($0, "Idempotency-Key") == nil && $0.timeoutInterval == RequestTimeout.read })
    #expect(overview.refreshIntervalSeconds == 45 && overview.items.isEmpty)
    #expect(ChannelOverview.ranges == ["90m", "24h", "7d", "30d"])
}

@Test(arguments: ["", "1h", "90M", "all"])
func channelOverviewRejectsUnknownRange(range: String) async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"items":[]}"#) }
    let error = await thrownAPIError { _ = try await channelClient(transport).channelOverview(range: range) }
    #expect(error?.kind == .validation)
    #expect(await transport.requests.isEmpty)
}

@Test func channelMonitorDisabledIsFeatureDisabled() async throws {
    let transport = ScriptedTransport { _ in errorReply(403, reason: "CHANNEL_MONITOR_DISABLED") }
    let error = try #require(await thrownAPIError { _ = try await channelClient(transport).channelOverview() })
    #expect(error.kind == .featureDisabled && error.category == .featureDisabled && error.action == .showDisabled)
    #expect(error.reason == "CHANNEL_MONITOR_DISABLED" && error.statusCode == 403)
    #expect(error.localizedDescription == "渠道监控未开启")
    #expect(ReasonCatalog.lookup(status: 403, reason: "CHANNEL_MONITOR_DISABLED") != nil)
    #expect(await transport.requests.count == 1)

    let administratorOnly = ScriptedTransport { _ in HTTPResponse(statusCode: 403, data: Data(#"{"code":403,"message":"administrator required"}"#.utf8)) }
    #expect(await thrownAPIError { _ = try await channelClient(administratorOnly).channelOverview() }?.kind == .permission)
}
