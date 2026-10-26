import Foundation
import Testing
@testable import Sub2Core

// MARK: - 运维监控模型解码（10 §4.2、§7.2，S1-02）

private func decoded<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }
private func utc(_ text: String) -> Date { ServerTime.parseTimestamp(text)! }

let opsOverviewFullJSON = """
{"start_time":"2026-10-23T01:55:00.123456789+08:00","end_time":"2026-10-22T18:00:00.123456789Z","platform":"","group_id":null,\
"health_score":92,"system_metrics":{"id":1,"created_at":"2026-10-22T17:59:00Z","window_minutes":1,"cpu_usage_percent":38.2,\
"memory_used_mb":4096,"memory_total_mb":8192,"memory_usage_percent":61.5,"db_ok":true,"redis_ok":false,"goroutine_count":120,\
"concurrency_queue_depth":4},"job_heartbeats":[{"job_name":"ops_metrics_collector","last_run_at":"2026-10-22T17:59:00Z",\
"last_success_at":"2026-10-22T17:59:00Z","last_error_at":null,"last_error":null,"last_duration_ms":35,"last_result":"ok",\
"updated_at":"2026-10-22T17:59:00Z","expected_interval_seconds":60,"next_expected_at":"2026-10-22T18:00:00Z","status":"ok"}],\
"success_count":990,"error_count_total":12,"business_limited_count":2,"error_count_sla":8,"request_count_total":1000,\
"request_count_sla":998,"token_consumed":123456,"sla":0.992,"error_rate":0.0086,"upstream_error_rate":0.004,\
"upstream_error_count_excl_429_529":3,"upstream_429_count":5,"upstream_529_count":1,"qps":{"current":0.8,"peak":2.4,"avg":0.6},\
"tps":{"current":120.5,"peak":300,"avg":99.9},"output_tps":null,"duration":{"p50_ms":850,"p90_ms":1800,"p95_ms":2400,"p99_ms":null,\
"avg_ms":900,"max_ms":12000},"ttft":{"p50_ms":420,"p90_ms":null,"avg_ms":500,"max_ms":3000}}
"""

@Test func overviewDecodesEveryFieldUsedByChaptersTenAndForty() throws {
    let overview = try decoded(OpsOverview.self, opsOverviewFullJSON)
    #expect(overview.startTime == utc("2026-10-22T17:55:00.123Z")); #expect(overview.endTime == utc("2026-10-22T18:00:00.123Z"))
    #expect(abs((overview.windowSeconds ?? 0) - 300) < 0.001)
    #expect(overview.platform == ""); #expect(overview.groupID == nil)
    #expect(overview.healthScore == 92); #expect(overview.sla == 0.992); #expect(overview.errorRate == 0.0086)
    #expect(overview.upstreamErrorRate == 0.004)
    #expect(overview.successCount == 990 && overview.errorCountTotal == 12 && overview.businessLimitedCount == 2)
    #expect(overview.errorCountSLA == 8 && overview.requestCountTotal == 1000 && overview.requestCountSLA == 998)
    #expect(overview.tokenConsumed == 123_456)
    #expect(overview.upstream429Count == 5 && overview.upstream529Count == 1 && overview.upstreamErrorCountExcl429529 == 3)
    #expect(overview.qps == OpsRateSummary(current: 0.8, peak: 2.4, avg: 0.6))
    #expect(overview.tps == OpsRateSummary(current: 120.5, peak: 300, avg: 99.9))
    #expect(overview.duration == OpsPercentiles(p50Ms: 850, p90Ms: 1_800, p95Ms: 2_400, p99Ms: nil, avgMs: 900, maxMs: 12_000))
    #expect(overview.ttft == OpsPercentiles(p50Ms: 420, avgMs: 500, maxMs: 3_000))
    let metrics = try #require(overview.systemMetrics)
    #expect(metrics == OpsSystemMetricsSnapshot(createdAt: utc("2026-10-22T17:59:00Z"), cpuUsagePercent: 38.2, memoryUsagePercent: 61.5,
                                                memoryUsedMB: 4_096, memoryTotalMB: 8_192, concurrencyQueueDepth: 4, goroutineCount: 120,
                                                dbOK: true, redisOK: false))
    #expect(overview.jobHeartbeats == [OpsJobHeartbeat(jobName: "ops_metrics_collector", lastRunAt: utc("2026-10-22T17:59:00Z"),
                                                       lastSuccessAt: utc("2026-10-22T17:59:00Z"), lastDurationMs: 35, status: "ok",
                                                       expectedIntervalSeconds: 60, nextExpectedAt: utc("2026-10-22T18:00:00Z"))])
    #expect(overview.jobHeartbeats.first?.id == "ops_metrics_collector")
}

@Test func overviewToleratesMissingNullAndMistypedFields() throws {
    #expect(try decoded(OpsOverview.self, "{}") == OpsOverview())
    #expect(try decoded(OpsOverview.self, #"{"system_metrics":null,"job_heartbeats":null,"qps":null}"#) == OpsOverview())
    let mistyped = try decoded(OpsOverview.self, """
        {"health_score":"bad","qps":5,"sla":0.99,"job_heartbeats":{"job_name":"x"},"start_time":12,"end_time":"2026-10-22T18:00:00Z",\
        "system_metrics":{"cpu_usage_percent":"high","memory_usage_percent":61.5},"duration":[1]}
        """)
    #expect(mistyped.healthScore == nil); #expect(mistyped.qps == nil); #expect(mistyped.sla == 0.99)
    #expect(mistyped.jobHeartbeats.isEmpty); #expect(mistyped.startTime == nil); #expect(mistyped.windowSeconds == nil)
    #expect(mistyped.systemMetrics == OpsSystemMetricsSnapshot(memoryUsagePercent: 61.5)); #expect(mistyped.duration == nil)
    #expect(OpsOverview(startTime: utc("2026-10-22T18:00:00Z"), endTime: utc("2026-10-22T18:00:00Z")).windowSeconds == nil)
}

@Test func jobHeartbeatsSkipNullAndBrokenEntriesAndKeepRawStatus() throws {
    let overview = try decoded(OpsOverview.self, """
        {"job_heartbeats":[{"job_name":"ops_metrics_collector","status":"ok","last_success_at":"2026-10-22T17:59:00Z"},null,\
        {"last_success_at":"2026-10-22T17:59:00Z"},{"job_name":""},{"job_name":"ops_cleanup","status":"disabled",\
        "expected_interval_seconds":86400,"next_expected_at":"2026-10-23T03:00:00+08:00"},{"job_name":"custom_sync","status":"paused",\
        "last_error":"dial tcp timeout","last_error_at":"2026-10-22T17:58:00Z"},{"job_name":"ops_alert_evaluator"}]}
        """)
    let beats = overview.jobHeartbeats
    #expect(beats.map(\.jobName) == ["ops_metrics_collector", "ops_cleanup", "custom_sync", "ops_alert_evaluator"])
    #expect(beats.map(\.status) == ["ok", "disabled", "paused", nil])
    #expect(beats[1].expectedIntervalSeconds == 86_400); #expect(beats[1].nextExpectedAt == utc("2026-10-22T19:00:00Z"))
    #expect(beats[2].lastError == "dial tcp timeout"); #expect(beats[2].lastErrorAt == utc("2026-10-22T17:58:00Z"))
    #expect(beats[3] == OpsJobHeartbeat(jobName: "ops_alert_evaluator"))
}

@Test func concurrencyDecodesPlatformsAndRealtimeOffShape() throws {
    let live = try decoded(OpsConcurrency.self, """
        {"enabled":true,"platform":{"anthropic":{"platform":"anthropic","current_in_use":3,"max_capacity":20,"load_percentage":15,\
        "waiting_in_queue":1},"openai":null,"gemini":{"current_in_use":"x"}},"group":{"7":{"current_in_use":1}},"account":{}}
        """)
    #expect(live.enabled)
    #expect(live.platforms["anthropic"] == OpsConcurrency.PlatformLoad(currentInUse: 3, maxCapacity: 20, waitingInQueue: 1))
    #expect(live.platforms["openai"] == nil); #expect(live.platforms["gemini"] == OpsConcurrency.PlatformLoad())
    let off = try decoded(OpsConcurrency.self, #"{"enabled":false,"platform":{},"group":{},"account":{},"timestamp":"2026-10-22T18:00:00Z"}"#)
    #expect(off == OpsConcurrency(enabled: false))
    #expect(try decoded(OpsConcurrency.self, #"{"platform":[]}"#) == OpsConcurrency())
}

@Test func systemMetricsHistoryKeepsNullsAndSkipsBadTimestamps() throws {
    let history = try decoded(SystemMetricsHistory.self, """
        {"start_time":"2026-10-22T17:00:00Z","end_time":"2026-10-22T18:00:00Z","window_minutes":60,"bucket_seconds":60,"points":[\
        {"created_at":"2026-10-22T17:01:00Z","sample_count":1,"cpu_usage_percent":null,"memory_usage_percent":60.5,"memory_used_mb":4000},\
        {"created_at":"not a time","cpu_usage_percent":10},{"cpu_usage_percent":11},null,\
        {"created_at":"2026-10-22T17:02:00.5Z","cpu_usage_percent":38.2,"memory_usage_percent":"x","goroutine_count":3}]}
        """)
    #expect(history.startTime == utc("2026-10-22T17:00:00Z")); #expect(history.endTime == utc("2026-10-22T18:00:00Z"))
    #expect(history.bucketSeconds == 60)
    #expect(history.points == [SystemMetricsHistory.Point(createdAt: utc("2026-10-22T17:01:00Z"), memoryUsagePercent: 60.5),
                               SystemMetricsHistory.Point(createdAt: utc("2026-10-22T17:02:00.5Z"), cpuUsagePercent: 38.2)])
    #expect(history.points.first?.id == utc("2026-10-22T17:01:00Z"))
    #expect(try decoded(SystemMetricsHistory.self, #"{"points":[]}"#) == SystemMetricsHistory())
    #expect(try decoded(SystemMetricsHistory.self, #"{"points":null,"bucket_seconds":"60"}"#) == SystemMetricsHistory())
}

@Test func systemLogHealthDecodesCountersAndBlankError() throws {
    let healthy = try decoded(SystemLogHealth.self, """
        {"queue_depth":2,"queue_capacity":1000,"dropped_count":0,"write_failed_count":1,"written_count":9,"avg_write_delay_ms":850,"last_error":""}
        """)
    #expect(healthy == SystemLogHealth(avgWriteDelayMs: 850, queueDepth: 2, queueCapacity: 1_000, lastError: "", writeFailedCount: 1, droppedCount: 0))
    #expect(!healthy.hasError)
    #expect(try decoded(SystemLogHealth.self, #"{"last_error":"  \n"}"#).hasError == false)
    #expect(try decoded(SystemLogHealth.self, #"{"last_error":"disk full"}"#).hasError)
    let overflow = try decoded(SystemLogHealth.self, #"{"dropped_count":18446744073709551615,"queue_depth":3,"avg_write_delay_ms":2000}"#)
    #expect(overflow.droppedCount == nil); #expect(overflow.queueDepth == 3); #expect(overflow.avgWriteDelayMs == 2_000)
    #expect(try decoded(SystemLogHealth.self, "{}") == SystemLogHealth())
}

@Test func ingressRejectListWithAndWithoutTotals() throws {
    let current = try decoded(IngressRejectList.self, """
        {"items":[{"id":1,"bucket_start":"2026-10-22T17:00:00Z","reject_reason":"invalid_api_key","route_family":"anthropic",\
        "protocol":"http","client_ip":"192.0.2.1","request_count":3,"first_seen":"2026-10-22T17:00:00Z","last_seen":"2026-10-22T17:01:00Z"}],\
        "total":1,"page":1,"page_size":1,"request_count_total":7,"by_reason":[{"reason":"invalid_api_key","request_count":5},\
        {"reason":"missing_key","request_count":2},null,{"request_count":1}]}
        """)
    #expect(current == IngressRejectList(items: [IngressRejectList.Item(requestCount: 3)], total: 1, page: 1, pageSize: 1, requestCountTotal: 7,
                                         byReason: [IngressRejectList.ReasonCount(reason: "invalid_api_key", requestCount: 5),
                                                    IngressRejectList.ReasonCount(reason: "missing_key", requestCount: 2)]))
    let old = try decoded(IngressRejectList.self, #"{"items":[{"request_count":2},{"request_count":"x"},null],"total":3,"page":1,"page_size":200}"#)
    #expect(old.requestCountTotal == nil); #expect(old.byReason.isEmpty)
    #expect(old.items == [IngressRejectList.Item(requestCount: 2), IngressRejectList.Item(requestCount: 0)])
    #expect(old.total == 3 && old.page == 1 && old.pageSize == 200)
}

@Test func monitoringStatusMapsDisabledReason() throws {
    let configOff = try decoded(OpsMonitoringStatus.self, """
        {"config_enabled":false,"monitoring_enabled":true,"realtime_monitoring_enabled":true,"effective":false,"disabled_reason":"config_off"}
        """)
    #expect(configOff == OpsMonitoringStatus(configEnabled: false, monitoringEnabled: true, realtimeMonitoringEnabled: true, effective: false,
                                             disabledReason: "config_off"))
    #expect(configOff.reason == .configOff)
    #expect(try decoded(OpsMonitoringStatus.self, #"{"effective":false,"disabled_reason":"setting_off"}"#).reason == .settingOff)
    let on = try decoded(OpsMonitoringStatus.self, #"{"config_enabled":true,"monitoring_enabled":true,"effective":true,"disabled_reason":null}"#)
    #expect(on.disabledReason == nil); #expect(on.reason == .unknown); #expect(on.effective == true)
    let weird = try decoded(OpsMonitoringStatus.self, #"{"disabled_reason":"weird","effective":"no"}"#)
    #expect(weird.disabledReason == "weird"); #expect(weird.reason == .unknown); #expect(weird.effective == nil)
    #expect(try decoded(OpsMonitoringStatus.self, "{}") == OpsMonitoringStatus())
}

@Test(arguments: [("setting_off", OpsDisabledReason.settingOff), ("config_off", .configOff), (" config_off\n", .configOff),
                  (nil, .unknown), ("", .unknown), ("other", .unknown), ("CONFIG_OFF", .unknown)] as [(String?, OpsDisabledReason)])
func disabledReasonParsesKnownValuesAndFallsBackToUnknown(raw: String?, expected: OpsDisabledReason) {
    #expect(OpsDisabledReason(rawReason: raw) == expected)
    #expect(OpsMonitoringStatus(disabledReason: raw).reason == expected)
}

@Test func fixtureInitializersDefaultEveryField() {
    #expect(OpsOverview() == OpsOverview(jobHeartbeats: []))
    #expect(OpsOverview(healthScore: 92).healthScore == 92)
    #expect(OpsOverview().systemMetrics == nil && OpsOverview().qps == nil && OpsOverview().windowSeconds == nil)
    #expect(OpsSystemMetricsSnapshot().cpuUsagePercent == nil)
    #expect(OpsJobHeartbeat(jobName: "ops_cleanup").status == nil)
    #expect(OpsConcurrency().enabled && OpsConcurrency().platforms.isEmpty)
    #expect(SystemMetricsHistory().points.isEmpty && SystemMetricsHistory().bucketSeconds == nil)
    #expect(SystemLogHealth().avgWriteDelayMs == nil && !SystemLogHealth().hasError)
    #expect(IngressRejectList().items.isEmpty && IngressRejectList().requestCountTotal == nil)
    #expect(OpsMonitoringStatus().effective == nil && OpsMonitoringStatus().reason == .unknown)
    let start = utc("2026-10-23T01:15:00Z"), end = utc("2026-10-23T02:00:00Z")
    let snapshot = OpsSnapshotV2(windowStart: start, windowEnd: end)
    #expect(snapshot.overview == nil && snapshot.throughputPoints.isEmpty && snapshot.errorPoints.isEmpty && snapshot.generatedAt == nil)
    #expect(snapshot.windowStart == start && snapshot.windowEnd == end)
}
