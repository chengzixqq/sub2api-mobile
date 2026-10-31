import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-14: the monitor overview's 服务器 section in LiveOpsStore (10 §0.1, §0.2, §4.2, §4.5, §4.6; 00 §2.7.2, §4.6, §5).

private let serverFailure = APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")
private let serverCapabilities = liveOpsCapabilities + [.opsSystemMetricsHistory, .opsIngressRejectTotals, .opsJobHeartbeatStatus]
private let minute = ServerTime.parseTimestamp("2026-10-16T02:00:00Z")!
private let sampleBeats = [
    OpsJobHeartbeat(jobName: "ops_metrics_collector", lastSuccessAt: minute.addingTimeInterval(-240), lastErrorAt: minute.addingTimeInterval(-60),
                    lastError: "redis: connection pool timeout", status: "failing", expectedIntervalSeconds: 60),
    OpsJobHeartbeat(jobName: "ops_alert_evaluator", lastSuccessAt: minute.addingTimeInterval(-31), status: "ok", expectedIntervalSeconds: 60)
]
private func metrics(at createdAt: Date = minute) -> OpsSystemMetricsSnapshot {
    OpsSystemMetricsSnapshot(createdAt: createdAt, cpuUsagePercent: 40, memoryUsagePercent: 60, concurrencyQueueDepth: 4)
}
private func overview(at createdAt: Date = minute) -> OpsOverview {
    OpsOverview(healthScore: 92, sla: 0.992, qps: OpsRateSummary(current: 0.8), systemMetrics: metrics(at: createdAt), jobHeartbeats: sampleBeats)
}
private let sampleConcurrency = OpsConcurrency(platforms: ["anthropic": .init(currentInUse: 5, maxCapacity: 30, waitingInQueue: 1),
                                                           "openai": .init(currentInUse: 3, maxCapacity: 20, waitingInQueue: 0)])
private let sampleHistory = SystemMetricsHistory(bucketSeconds: 60, points: [.init(createdAt: minute.addingTimeInterval(-60), cpuUsagePercent: 35),
                                                                            .init(createdAt: minute, cpuUsagePercent: 40)])
private let sampleLogs = SystemLogHealth(avgWriteDelayMs: 850, lastError: "")
private let totalPage = IngressRejectList(items: [.init(requestCount: 3)], total: 1, page: 1, pageSize: 1, requestCountTotal: 3)

/// `rows` aggregated rows of one rejection each, cut into pages as the server does, without `request_count_total`.
private func legacyIngress(rows: Int) -> @Sendable (Int, Int) async throws -> IngressRejectList {
    { page, pageSize in
        let start = (page - 1) * pageSize, count = max(0, min(pageSize, rows - start))
        return IngressRejectList(items: Array(repeating: .init(requestCount: 1), count: count), total: rows, page: page, pageSize: pageSize)
    }
}

/// Every monitor read answers, the server section's four included; nothing fires.
private func serverSource() -> StubLiveOpsSource {
    StubLiveOpsSource(.init(overview: { _, _ in overview() }, alertEvents: { _, _ in [] }, alertCounts: { AlertCounts(firing: 0) },
                            snapshot: { OpsSnapshotV2(windowStart: $0, windowEnd: $1) }, concurrency: { sampleConcurrency },
                            metricsHistory: { _, _ in sampleHistory }, logsHealth: { sampleLogs }, ingress: { _, _ in totalPage }))
}
@MainActor private func serverHarness(_ source: StubLiveOpsSource = serverSource(), capabilities: [Capability] = serverCapabilities,
                                      sleeper: PollSleeper = PollSleeper()) -> LiveOpsHarness {
    LiveOpsHarness(source, site: liveOpsSite(capabilities), serverNow: minute, sleeper: sleeper)
}
/// A vendor workspace: not the site owner (10 §0.1).
private func vendorSite() -> SiteSession {
    let me = AdminMe(user: .init(id: 2, role: "admin"), workspace: .init(id: 3, name: "代运营"), features: .init(opsMonitoringEnabled: true),
                     server: .init(serverTimezone: liveOpsZone.identifier, serverUTCOffset: liveOpsZone.rawUTCOffset,
                                   capabilities: Set(serverCapabilities.map(\.rawValue))))
    return SiteSession(me: me, credential: sessionTokens(), accessTokenScope: nil, serverTimeZone: liveOpsZone, clockOffset: 0, probedAt: Date())
}

private func isConcurrency(_ call: StubLiveOpsSource.Call) -> Bool { call == .concurrency }
private func isHistory(_ call: StubLiveOpsSource.Call) -> Bool { if case .metricsHistory = call { true } else { false } }
private func isLogs(_ call: StubLiveOpsSource.Call) -> Bool { call == .logsHealth }
private func isIngress(_ call: StubLiveOpsSource.Call) -> Bool { if case .ingress = call { true } else { false } }
private func isServerRead(_ call: StubLiveOpsSource.Call) -> Bool { isConcurrency(call) || isHistory(call) || isLogs(call) || isIngress(call) }
private func isOverviewRange(_ call: StubLiveOpsSource.Call) -> Bool { if case .overviewRange = call { true } else { false } }

// MARK: 请求与门控（10 §0.1、§0.2、§4.2）

@MainActor @Test func serverBlocksSendSpecParameters() async {
    let source = serverSource()
    let store = serverHarness(source).store
    await store.refreshMonitorOverview(force: true)
    let calls = await source.calls
    #expect(calls.filter(isServerRead).count == 4)
    #expect(calls.filter(isConcurrency) == [.concurrency] && calls.filter(isLogs) == [.logsHealth])
    #expect(calls.filter(isHistory) == [.metricsHistory(timeRange: "1h", maxPoints: 60)])
    #expect(calls.filter(isIngress) == [.ingress(timeRange: "1h", page: 1, pageSize: 1)])
    #expect(store.monitor.concurrency.value == sampleConcurrency && store.monitor.systemMetrics.value == sampleHistory)
    #expect(store.monitor.logHealth.value == sampleLogs && store.monitor.ingress.value == .exact(3))
    #expect(store.showsMonitorServer)
}

@MainActor @Test func historyNotRequestedWithoutCapability() async {
    let source = serverSource()
    let store = serverHarness(source, capabilities: [.opsIngressRejectTotals, .opsJobHeartbeatStatus]).store
    #expect(!store.monitorBlockApplies(.systemMetrics) && store.monitorBlockApplies(.concurrency) && store.monitorBlockApplies(.run))
    await store.refreshMonitorOverview(force: true)
    await store.refreshMonitorBlock(.systemMetrics, force: true)
    #expect(await source.count(isHistory) == 0)
    #expect(store.monitor.systemMetrics.state == .idle)
    let shown = store.monitorServerDisplay(now: minute)
    #expect(!shown.loadingParts.contains(.systemMetrics) && shown.failure == nil)
}

@MainActor @Test func nonAdministratorSendsNoServerRequests() async {
    let source = serverSource()
    let store = LiveOpsHarness(source, site: vendorSite()).store
    #expect(!store.showsMonitorServer)
    #expect(MonitorOverviewBlock.serverBlocks.allSatisfy { !store.monitorBlockApplies($0) })
    await store.refreshMonitorOverview(force: true)
    await store.refreshMonitorServerParts(MonitorServerPart.allCases)
    #expect(await source.count(isServerRead) == 0)
    #expect(await source.count(isOverviewRange) == 1)
    #expect(store.monitor.overview.value == overview())
}

// MARK: history 400 重发一次（10 §4.5 第 4 行）

@MainActor @Test(arguments: ["INVALID_MAX_POINTS", "OPS_TIME_RANGE_TOO_LARGE"])
func historyParameterErrorRetriesOnceWithDefaults(reason: String) async {
    let source = serverSource(), tally = Tally()
    await source.update { $0.metricsHistory = { _, _ in
        if tally.next() == 1 { throw APIError.server(status: 400, reason: reason) }
        return sampleHistory
    } }
    let store = serverHarness(source).store
    await store.refreshMonitorBlock(.systemMetrics, force: true)
    #expect(await source.calls.filter(isHistory) == Array(repeating: StubLiveOpsSource.Call.metricsHistory(timeRange: "1h", maxPoints: 60), count: 2))
    #expect(store.monitor.systemMetrics.value == sampleHistory && store.monitor.systemMetrics.lastError == nil)
}

@MainActor @Test func historyParameterErrorGivesUpAfterOneRetry() async {
    let source = serverSource()
    await source.update { $0.metricsHistory = { _, _ in throw APIError.server(status: 400, reason: "INVALID_MAX_POINTS") } }
    let store = serverHarness(source).store
    await store.refreshMonitorBlock(.systemMetrics, force: true)
    #expect(await source.count(isHistory) == 2)
    #expect(store.monitor.systemMetrics.value == nil && store.monitor.systemMetrics.error != nil)
    #expect(store.monitor.systemMetrics.lastError?.reason == "INVALID_MAX_POINTS")
}

@MainActor @Test func otherHistoryErrorsAreNotRetried() async {
    let errors: [any Error] = [APIError.server(status: 400, reason: nil), APIError.server(status: 500, reason: "INTERNAL_ERROR"), URLError(.timedOut)]
    for error in errors {
        let source = serverSource()
        await source.update { $0.metricsHistory = { _, _ in throw error } }
        let store = serverHarness(source).store
        await store.refreshMonitorBlock(.systemMetrics, force: true)
        #expect(await source.count(isHistory) == 1)
        #expect(!MonitorServerLoads.isHistoryParameterError(error))
    }
    #expect(MonitorServerLoads.isHistoryParameterError(APIError.server(status: 400, reason: "OPS_TIME_RANGE_TOO_LARGE")))
    #expect(!MonitorServerLoads.isHistoryParameterError(APIError.server(status: 422, reason: "INVALID_MAX_POINTS")))
}

// MARK: 入口拒绝（10 §0.2、§4.2）

@MainActor @Test func ingressUsesTotalWithCapability() async {
    let source = serverSource()
    let store = serverHarness(source).store
    await store.refreshMonitorBlock(.ingress, force: true)
    #expect(await source.calls.filter(isIngress) == [.ingress(timeRange: "1h", page: 1, pageSize: 1)])
    #expect(store.monitor.ingress.value == .exact(3))
}

/// A reply without `request_count_total` is not a total: one row's sum would undercount.
@MainActor @Test func ingressFallsBackToPagingWhenTotalMissing() async {
    let source = serverSource()
    await source.update { $0.ingress = legacyIngress(rows: 5) }
    let store = serverHarness(source).store
    await store.refreshMonitorBlock(.ingress, force: true)
    #expect(await source.calls.filter(isIngress) == [.ingress(timeRange: "1h", page: 1, pageSize: 1), .ingress(timeRange: "1h", page: 1, pageSize: 200)])
    #expect(store.monitor.ingress.value == .exact(5))
}

@MainActor @Test func ingressPagesAtMostThreeWithoutCapability() async {
    let source = serverSource()
    await source.update { $0.ingress = legacyIngress(rows: 650) }
    let store = serverHarness(source, capabilities: [.opsSystemMetricsHistory, .opsJobHeartbeatStatus]).store
    await store.refreshMonitorBlock(.ingress, force: true)
    #expect(await source.calls.filter(isIngress) == (1...3).map { StubLiveOpsSource.Call.ingress(timeRange: "1h", page: $0, pageSize: 200) })
    #expect(store.monitor.ingress.value == .atLeast(600))
}

@MainActor @Test func ingressShortPageIsExact() async {
    for (rows, pages) in [(250, 2), (120, 1)] {
        let source = serverSource()
        await source.update { $0.ingress = legacyIngress(rows: rows) }
        let store = serverHarness(source, capabilities: [.opsJobHeartbeatStatus]).store
        await store.refreshMonitorBlock(.ingress, force: true)
        #expect(await source.count(isIngress) == pages)
        #expect(store.monitor.ingress.value == .exact(rows))
    }
}

// MARK: 块失败、运维开关与站点不支持（10 §4.5，00 §5）

@MainActor @Test func serverBlocksFailIndependently() async {
    let source = serverSource()
    await source.update { $0.concurrency = { throw serverFailure } }
    let store = serverHarness(source).store
    await store.refreshMonitorOverview(force: true)
    #expect(store.monitor.concurrency.error != nil && store.monitor.concurrency.lastError?.statusCode == 503)
    #expect(store.monitor.systemMetrics.value != nil && store.monitor.logHealth.value != nil && store.monitor.ingress.value != nil)
    #expect(store.monitorRefreshStatus == .partial)

    await source.update {
        $0.concurrency = { sampleConcurrency }
        $0.metricsHistory = { _, _ in throw serverFailure }
        $0.logsHealth = { throw serverFailure }
        $0.ingress = { _, _ in throw serverFailure }
    }
    await store.refreshMonitorOverview(force: true)
    #expect(store.monitor.concurrency.value == sampleConcurrency)
    #expect(store.monitor.systemMetrics.value == sampleHistory && store.monitor.logHealth.value == sampleLogs && store.monitor.ingress.value == .exact(3))
    #expect(store.monitorServerDisplay(now: minute).staleParts == [.systemMetrics, .logHealth, .ingress])
}

/// 10 §4.5 row 1: any read's 404 OPS_DISABLED turns the whole segment into the empty state; the timers stop.
@MainActor @Test func opsDisabledFromServerBlockSwitchesSegment() async {
    let source = serverSource()
    let store = serverHarness(source).store
    await store.refreshMonitorOverview(force: true)
    #expect(!store.opsDisabled)
    await source.update { $0.logsHealth = { throw opsDisabledError } }
    await store.refreshMonitorBlock(.logHealth, force: true)
    #expect(store.opsDisabled)
    let before = await source.calls.count
    await store.monitorOverviewPolling()
    #expect(await source.calls.count == before)
}

/// Appendix A S7: `enabled: false` is realtime monitoring off, a 200 that says ops monitoring is on.
@MainActor @Test func realtimeOffIsNotOpsDisabled() async {
    let source = serverSource()
    await source.update { $0.concurrency = { OpsConcurrency(enabled: false) } }
    let store = serverHarness(source).store
    await store.refreshMonitorOverview(force: true)
    #expect(store.monitor.concurrency.value == OpsConcurrency(enabled: false))
    #expect(!store.opsDisabled)
    let shown = store.monitorServerDisplay(now: minute)
    #expect(shown.concurrency.isRealtimeOff && shown.concurrency.inUse == "—" && shown.concurrency.queue == "4")
}

/// 00 §5 item 3: a route the site lacks (a non-JSON 404) is not asked again this session and shows “—” without a failure.
@MainActor @Test func unsupportedRouteStopsForSession() async {
    let source = serverSource()
    await source.update { $0.ingress = { _, _ in throw APIError.server(status: 404, envelope: nil) } }
    let store = serverHarness(source).store
    await store.refreshMonitorOverview(force: true)
    #expect(store.monitor.unsupportedBlocks == [.ingress] && !store.monitorBlockApplies(.ingress))
    await store.refreshMonitorOverview(force: true)
    await store.refreshMonitorServerParts([.ingress])
    #expect(await source.count(isIngress) == 1)
    let shown = store.monitorServerDisplay(now: minute)
    #expect(shown.failure == nil && shown.ingest.detail.hasPrefix("入口拒绝 —"))
    #expect(!store.opsDisabled)

    let next = serverSource()
    await serverHarness(next).store.refreshMonitorBlock(.ingress, force: true)
    #expect(await next.count(isIngress) == 1)
}

/// 00 §2.7.2: a 429 holds back only its own block.
@MainActor @Test func rateLimitedServerBlockWaitsAlone() async {
    let source = serverSource()
    await source.update { $0.ingress = { _, _ in throw APIError.server(status: 429, envelope: nil, retryAfter: 30) } }
    let store = serverHarness(source).store
    await store.refreshMonitorOverview(force: true)
    for block in MonitorOverviewBlock.serverBlocks { await store.refreshMonitorBlock(block, force: false) }
    #expect(await source.count(isIngress) == 1)
    #expect(await source.count(isConcurrency) == 2)
    #expect(await source.count(isLogs) == 2)
    #expect(await source.count(isHistory) == 2)
    #expect(store.monitor.ingress.refresh.throttleMessage(at: Date()) != nil)
}

/// 00 §4.6: each server block keeps its own timer and backoff.
@MainActor @Test func pollingBacksOffServerBlocksIndependently() async {
    let source = serverSource()
    await source.update { $0.logsHealth = { throw serverFailure } }
    let harness = serverHarness(source, sleeper: PollSleeper(parks: true))
    let polling = Task { await harness.store.monitorOverviewPolling() }
    await waitUntil { await harness.sleeper.parkedCount == 6 }
    #expect(await harness.sleeper.seconds.sorted() == Array(repeating: 60, count: 5) + [120])
    await harness.sleeper.releaseAll()
    await waitUntil { await harness.sleeper.parkedCount == 6 }
    #expect(await harness.sleeper.seconds.sorted() == Array(repeating: 60, count: 10) + [120, 240])
    #expect(await source.count(isLogs) == 2)
    #expect(await source.count(isConcurrency) == 2)
    await harness.sleeper.stop()
    await polling.value
}

/// The failure row's 重试 reads only its blocks.
@MainActor @Test func retryReloadsOnlyRequestedParts() async {
    let source = serverSource()
    let store = serverHarness(source).store
    await store.refreshMonitorServerParts([.concurrency])
    #expect(await source.count(isConcurrency) == 1)
    #expect(await source.count(isServerRead) == 1)
    await store.refreshMonitorServerParts([.concurrency, .ingress])
    #expect(await source.count(isConcurrency) == 2)
    #expect(await source.count(isIngress) == 1)
    #expect(await source.count(isHistory) == 0)
    #expect(await source.count(isLogs) == 0)
    #expect(await source.count(isOverviewRange) == 0)
}

// MARK: 本机攒点（10 §4.3）

@MainActor @Test func localSampleOnlyWithoutHistoryCapability() async {
    let source = serverSource(), tally = Tally()
    await source.update { $0.overview = { _, _ in overview(at: minute.addingTimeInterval(Double(tally.next()) * 60)) } }
    let store = serverHarness(source, capabilities: [.opsJobHeartbeatStatus]).store
    await store.refreshMonitorBlock(.run, force: true)
    await store.refreshMonitorBlock(.run, force: true)
    #expect(store.monitor.localSamples.map(\.createdAt) == [minute.addingTimeInterval(60), minute.addingTimeInterval(120)])
    #expect(await source.count(isHistory) == 0)

    await source.update { $0.overview = { _, _ in overview(at: minute.addingTimeInterval(120)) } }
    await store.refreshMonitorBlock(.run, force: true)
    #expect(store.monitor.localSamples.count == 2)
    await source.update { $0.overview = { _, _ in throw serverFailure } }
    await store.refreshMonitorBlock(.run, force: true)
    #expect(store.monitor.localSamples.count == 2)
    #expect(store.monitorServerDisplay(now: minute).cpu.trend == [40, 40])

    let withHistory = serverHarness(serverSource()).store
    await withHistory.refreshMonitorBlock(.run, force: true)
    #expect(withHistory.monitor.localSamples.isEmpty)
}

@MainActor @Test func localSamplesCapAtSixtyAndStartEmptyPerStore() {
    let state = MonitorState()
    for index in 0...60 { state.recordLocalSample(metrics(at: minute.addingTimeInterval(Double(index) * 60))) }
    #expect(state.localSamples.count == 60)
    #expect(state.localSamples.first?.createdAt == minute.addingTimeInterval(60))
    state.recordLocalSample(nil)
    state.recordLocalSample(OpsSystemMetricsSnapshot(cpuUsagePercent: 10))
    #expect(state.localSamples.count == 60 && state.localSamples.last?.createdAt == minute.addingTimeInterval(3_600))
    #expect(serverHarness().store.monitor.localSamples.isEmpty)
}

// MARK: 副标题、迟到结果与展示组装

@MainActor @Test func refreshStatusCountsOnlyApplicableBlocks() async {
    let withoutHistory = serverHarness(capabilities: [.opsIngressRejectTotals]).store
    await withoutHistory.refreshMonitorOverview(force: false)
    #expect(isUpdated(withoutHistory.monitorRefreshStatus))

    let vendor = LiveOpsHarness(serverSource(), site: vendorSite()).store
    await vendor.refreshMonitorOverview(force: false)
    #expect(isUpdated(vendor.monitorRefreshStatus))

    let source = serverSource()
    await source.update { $0.ingress = { _, _ in throw APIError.server(status: 404, envelope: nil) } }
    let legacy = serverHarness(source).store
    await legacy.refreshMonitorOverview(force: false)
    #expect(isUpdated(legacy.monitorRefreshStatus))
}
private func isUpdated(_ status: HomeRefreshStatus?) -> Bool { if case .updated? = status { true } else { false } }

/// 00 §4.6: an answer that lands after the session ended changes nothing, the switch included.
@MainActor @Test func lateServerResultsAfterSessionEndAreDropped() async {
    let gate = SessionGate()
    let source = serverSource()
    await source.update { $0.concurrency = { await gate.wait(); return sampleConcurrency } }
    let harness = serverHarness(source)
    let store = harness.store
    await store.noteOpsDisabled()
    let pull = Task { await store.refreshMonitorBlock(.concurrency, force: true) }
    await waitUntil { await gate.arrived }
    harness.isCurrent = false
    await gate.open()
    await pull.value
    #expect(store.monitor.concurrency.value == nil)
    #expect(store.opsDisabled)
}

@MainActor @Test func displayAssemblesStoreState() async {
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    let store = serverHarness().store
    await store.refreshMonitorOverview(force: true)
    let shown = store.monitorServerDisplay(now: minute)
    #expect(shown.jobs == .lines(MonitorPresentation.jobLines(sampleBeats, supportsStatus: true, now: minute, timeZone: shanghai)))
    #expect(shown.cpu.reading.text == "40.0%" && shown.cpu.trend == [35, 40])
    #expect(shown.concurrency.inUse == "8/50" && shown.ingest.detail == "入口拒绝 3 次（1 小时）· 1 个任务需留意")

    let local = serverHarness(capabilities: [.opsSystemMetricsHistory, .opsIngressRejectTotals]).store
    await local.refreshMonitorOverview(force: true)
    #expect(local.monitorServerDisplay(now: minute).jobs
            == .lines(MonitorPresentation.jobLines(sampleBeats, supportsStatus: false, now: minute, timeZone: shanghai)))
}
