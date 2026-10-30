import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-14: the `-ui-testing` server section reads (LiveOpsFixtures+Server.swift).

private let base = ServerTime.parseTimestamp("2026-10-16T02:00:42Z")!
private func refused(_ call: () async throws -> Void) async -> APIError? {
    do { try await call(); return nil } catch { return error as? APIError }
}

/// The run's overview carries the server figures: every job state, three that need attention.
@Test func serverFixtureCoversHeartbeatStates() {
    let overview = LiveOpsFixtures.fiveMinuteOverview(base: base)
    let lines = MonitorPresentation.jobLines(overview.jobHeartbeats, supportsStatus: true, now: base, timeZone: LiveOpsFixtures.serverTimeZone.timeZone)
    let states = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0.state) })
    #expect(states == ["ops_metrics_collector": .failing, "ops_alert_evaluator": .ok, "ops_preaggregation_hourly": .stale,
                       "ops_preaggregation_daily": .ok, "ops_cleanup": .stale, "ops_scheduled_reports": .disabled, "ops_custom_sync": .unknown])
    #expect(MonitorPresentation.attentionCount(lines) == 3)
    #expect(lines.first { $0.id == "ops_cleanup" }?.detail?.hasPrefix("按计划应在") == true)
    #expect(lines.first { $0.id == "ops_preaggregation_hourly" }?.detail?.hasSuffix("没有成功，需要看一下") == true)
    let metrics = overview.systemMetrics
    #expect(metrics?.cpuUsagePercent == 92 && metrics?.memoryUsagePercent == 78 && metrics?.concurrencyQueueDepth == 4)
    #expect(metrics?.createdAt == ServerTime.parseTimestamp("2026-10-16T02:00:00Z"))
    #expect(MonitorPresentation.qps(overview) == "0.8")
}

@Test func serverHistoryFixtureBreaksAndEndsAtCurrentValue() {
    let history = LiveOpsFixtures.serverMetricsHistory(now: base)
    let current = LiveOpsFixtures.serverSystemMetrics(now: base)
    #expect(history.bucketSeconds == 60 && history.points.count == 60)
    #expect(history.points.last?.createdAt == current.createdAt)
    #expect(history.points.last?.cpuUsagePercent == current.cpuUsagePercent && history.points.last?.memoryUsagePercent == current.memoryUsagePercent)
    #expect((20...22).allSatisfy { history.points[$0].cpuUsagePercent == nil } && history.points[21].memoryUsagePercent == nil)
    #expect(history.points.compactMap(\.cpuUsagePercent).allSatisfy { (30...95).contains($0) })
}

@Test func realtimeOffArgumentParsesAndFlipsConcurrency() async throws {
    #expect(MonitorFixtureOptions(arguments: ["-ui-monitor-realtime-off"]) == MonitorFixtureOptions(realtimeOff: true))
    #expect(MonitorFixtureOptions(arguments: ["-ui-monitor-realtime-off", "-ui-monitor-overview-fails"])
            == MonitorFixtureOptions(overviewFails: true, realtimeOff: true))
    let off = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: ["-ui-testing", "-ui-monitor-realtime-off"]), base: base)
    #expect(try await off.opsConcurrency() == OpsConcurrency(enabled: false))
    let on = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(), base: base)
    #expect(MonitorPresentation.concurrency(try await on.opsConcurrency(), queueDepth: 4).inUse == "8/50")
}

@Test func ingressFixtureFollowsWithheldTotals() async throws {
    let current = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: ["-ui-testing"]), base: base)
    #expect(try await current.ingressRejections(timeRange: "1h", page: 1, pageSize: 1).requestCountTotal == 3)
    #expect(try await MonitorServerLoads.ingressTally(using: current, totalsSupported: true) == .exact(3))

    let arguments = ["-ui-testing", UITestArguments.withoutCapabilities, LiveOpsFixtures.serverLegacyWithheldCapabilities]
    #expect(MonitorFixtureOptions(arguments: arguments).ingressTotalsWithheld)
    let legacy = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: arguments), base: base)
    let third = try await legacy.ingressRejections(timeRange: "1h", page: 3, pageSize: 200)
    #expect(third.requestCountTotal == nil && third.total == 650 && third.items.count == 200)
    #expect(try await MonitorServerLoads.ingressTally(using: legacy, totalsSupported: false) == .atLeast(600))
}

@Test func serverFixtureHonoursOpsSwitch() async throws {
    for argument in ["-ui-ops-disabled", "-ui-ops-config-off"] {
        let off = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: [argument]), base: base)
        #expect(await refused { _ = try await off.opsConcurrency() } == LiveOpsFixtures.opsDisabledError)
        #expect(await refused { _ = try await off.systemMetricsHistory(timeRange: "1h", maxPoints: 60) } == LiveOpsFixtures.opsDisabledError)
        #expect(await refused { _ = try await off.systemLogsHealth() } == LiveOpsFixtures.opsDisabledError)
        #expect(await refused { _ = try await off.ingressRejections(timeRange: "1h", page: 1, pageSize: 1) } == LiveOpsFixtures.opsDisabledError)
    }
    let on = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(), base: base)
    #expect(try await on.systemMetricsHistory(timeRange: "1h", maxPoints: 60).points.count == 60)
    #expect(try await on.systemLogsHealth().avgWriteDelayMs == 850)
}

/// The run section and the overview's fallback read the same five-minute figures as before.
@Test func overviewFixtureKeepsRunAndHomeValues() {
    let overview = LiveOpsFixtures.fiveMinuteOverview(base: base)
    #expect(overview.healthScore == 94 && overview.sla == 0.992 && overview.errorRate == 0.008)
    #expect(overview.upstream429Count == 12 && overview.upstream529Count == 3)
    #expect(overview.requestCountTotal == 230 && overview.tokenConsumed == 1_200_000 && overview.windowSeconds == 300)
}
