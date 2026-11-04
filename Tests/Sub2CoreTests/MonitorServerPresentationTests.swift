import Foundation
import Testing
@testable import Sub2Core

// S1-14: the monitor overview's 服务器 section (10 §4.3 server and job tables, §4.5, §0.5).

private let now = HomeTestData.now
private let shanghai = HomeTestData.shanghai
private let sampleMetrics = OpsSystemMetricsSnapshot(createdAt: now, cpuUsagePercent: 92, memoryUsagePercent: 78, concurrencyQueueDepth: 4)
private let sampleBeats = [
    OpsJobHeartbeat(jobName: "ops_custom_sync", status: "paused"),
    OpsJobHeartbeat(jobName: "ops_metrics_collector", lastSuccessAt: now.addingTimeInterval(-240), lastErrorAt: now.addingTimeInterval(-60),
                    lastError: "redis: connection pool timeout", status: "failing", expectedIntervalSeconds: 60),
    OpsJobHeartbeat(jobName: "ops_alert_evaluator", lastSuccessAt: now.addingTimeInterval(-31), status: "ok", expectedIntervalSeconds: 60),
    OpsJobHeartbeat(jobName: "ops_preaggregation_hourly", lastSuccessAt: now.addingTimeInterval(-2_400), status: "stale", expectedIntervalSeconds: 600),
    OpsJobHeartbeat(jobName: "ops_cleanup", lastSuccessAt: now.addingTimeInterval(-90_000), status: "stale", nextExpectedAt: now.addingTimeInterval(-3_600))
]
private let sampleOverview = OpsOverview(sla: 0.992, qps: OpsRateSummary(current: 0.8), systemMetrics: sampleMetrics, jobHeartbeats: sampleBeats)
private let sampleConcurrency = OpsConcurrency(platforms: ["anthropic": .init(currentInUse: 5, maxCapacity: 30, waitingInQueue: 1),
                                                           "openai": .init(currentInUse: 3, maxCapacity: 20, waitingInQueue: 0)])
private let sampleLogs = SystemLogHealth(avgWriteDelayMs: 850, queueDepth: 0, queueCapacity: 1_000, lastError: "")

/// `count` one-minute points ending at `now`; `cpu` / `memory` give each index's value.
private func sampleHistory(_ count: Int = 60, bucket: Int? = 60, cpu: (Int) -> Double? = { 30 + Double($0) },
                           memory: (Int) -> Double? = { _ in 60 }) -> SystemMetricsHistory {
    let points = (0..<count).map { index in
        SystemMetricsHistory.Point(createdAt: now.addingTimeInterval(Double(index - count + 1) * 60), cpuUsagePercent: cpu(index),
                                   memoryUsagePercent: memory(index))
    }
    return SystemMetricsHistory(bucketSeconds: bucket, points: points)
}
private func loaded<Value: Sendable>(_ value: Value) -> BlockDisplay<Value> { .value(value, at: now, isRefreshing: false, updateFailed: false) }
private func stale<Value: Sendable>(_ value: Value) -> BlockDisplay<Value> { .value(value, at: now, isRefreshing: false, updateFailed: true) }
private let failed503 = "服务暂时不可用"

private func display(overview: BlockDisplay<OpsOverview> = loaded(sampleOverview), history: BlockDisplay<SystemMetricsHistory> = loaded(sampleHistory()),
                     localSamples: [SystemMetricsHistory.Point] = [], concurrency: BlockDisplay<OpsConcurrency> = loaded(sampleConcurrency),
                     logHealth: BlockDisplay<SystemLogHealth> = loaded(sampleLogs),
                     ingress: BlockDisplay<MonitorPresentation.IngressRejectTally> = loaded(.exact(3)), unavailable: Set<MonitorServerPart> = [],
                     heartbeatStatusSupported: Bool = true) -> MonitorServerDisplay {
    MonitorServerPresentation.display(MonitorServerInput(overview: overview, history: history, localSamples: localSamples, concurrency: concurrency,
                                                         logHealth: logHealth, ingress: ingress, unavailable: unavailable,
                                                         heartbeatStatusSupported: heartbeatStatusSupported, now: now, timeZone: shanghai))
}

// MARK: CPU / 内存表

@Test func metersUseOverviewValuesAndCapacityTones() {
    let shown = display()
    #expect(shown.cpu.reading == MonitorPresentation.capacity(92))
    #expect(shown.cpu.reading.text == "92.0%" && shown.cpu.reading.tone == .critical && shown.cpu.reading.fraction == 0.92)
    #expect(shown.cpu.toneKey == "critical" && shown.cpu.meter.title == "CPU")
    #expect(shown.memory.reading.tone == .caution && shown.memory.toneKey == "caution" && shown.memory.meter.title == "内存")
    let calm = display(overview: loaded(OpsOverview(systemMetrics: OpsSystemMetricsSnapshot(createdAt: now, cpuUsagePercent: 40, memoryUsagePercent: 61))))
    #expect(calm.cpu.reading.tone == nil && calm.cpu.toneKey == "normal" && calm.cpu.reading.fraction == 0.4)
}

@Test func nullCurrentValueShowsDash() {
    let noCPU = display(overview: loaded(OpsOverview(systemMetrics: OpsSystemMetricsSnapshot(createdAt: now, memoryUsagePercent: 78))))
    #expect(noCPU.cpu.reading.text == "—" && noCPU.cpu.reading.fraction == nil && noCPU.cpu.reading.tone == nil && noCPU.cpu.toneKey == "normal")
    #expect(noCPU.memory.reading.text == "78.0%")
    let none = display(overview: loaded(OpsOverview()))
    #expect(none.cpu.reading.text == "—" && none.memory.reading.text == "—")
}

// MARK: §4.5 状态表

@Test func overviewFailureBlanksMetersQpsSlaAndJobs() {
    let shown = display(overview: .failed(reason: failed503))
    #expect(shown.cpu.reading.text == "—" && shown.memory.reading.text == "—")
    #expect(shown.qps == "—" && shown.sla == "—")
    #expect(shown.jobs == .missing)
    #expect(!shown.ingest.detail.contains("需留意"))
    #expect(shown.concurrency.inUse == "8/50")
    #expect(shown.ingest.trailing == "延迟 850ms")
    #expect(shown.cpu.trend.count == 60)
    // The overview's failure row is the run section's.
    #expect(shown.failure == nil && !shown.isOverviewLoading)
}

@Test func overviewFirstLoadShowsSkeleton() {
    let shown = display(overview: .placeholder, concurrency: .placeholder)
    #expect(shown.isOverviewLoading && shown.jobs == .loading)
    #expect(shown.loadingParts == [.concurrency])
    #expect(shown.failure == nil)
}

// MARK: 小折线

@Test func historyTrendBreaksAtNullAndMissingBuckets() {
    let gaps = display(history: loaded(sampleHistory(cpu: { (20...22).contains($0) ? nil : 30 })))
    #expect(gaps.cpu.trend.count == 60)
    #expect(gaps.cpu.trend[20] == nil && gaps.cpu.trend[21] == nil && gaps.cpu.trend[22] == nil && gaps.cpu.trend[19] == 30)

    // The server leaves out buckets without samples: one nil stands for the missing minutes.
    let full = sampleHistory(cpu: { $0 == 10 ? 120 : 30 })
    let holed = SystemMetricsHistory(bucketSeconds: 60, points: full.points.enumerated().filter { !(40...44).contains($0.offset) }.map(\.element))
    let trend = MonitorServerPresentation.trendValues(holed.points, meter: .cpu, maxGap: MonitorServerPresentation.maxGap(bucketSeconds: 60, heartbeats: []))
    #expect(trend.count == 56)
    #expect(trend[40] == nil && trend[39] == 30 && trend[41] == 30)
    #expect(trend[10] == 100)
    #expect(SparklineSeries(values: trend, fixedUpperBound: 100).runs.count >= 2)
}

@Test func trendNeedsTwoPoints() {
    let gap = MonitorServerPresentation.maxGap(bucketSeconds: 60, heartbeats: [])
    let one = [SystemMetricsHistory.Point(createdAt: now, cpuUsagePercent: 30)]
    #expect(MonitorServerPresentation.trendValues(one, meter: .cpu, maxGap: gap) == [])
    let blank = sampleHistory(3, cpu: { _ in nil }).points
    #expect(MonitorServerPresentation.trendValues(blank, meter: .cpu, maxGap: gap) == [])
    #expect(MonitorServerPresentation.trendValues([], meter: .memory, maxGap: gap) == [])
    #expect(display(history: loaded(SystemMetricsHistory(bucketSeconds: 60, points: one))).cpu.trend == [])

    let shuffled = [SystemMetricsHistory.Point(createdAt: now, cpuUsagePercent: 50, memoryUsagePercent: 70),
                    SystemMetricsHistory.Point(createdAt: now.addingTimeInterval(-60), cpuUsagePercent: 40, memoryUsagePercent: 65)]
    #expect(MonitorServerPresentation.trendValues(shuffled, meter: .cpu, maxGap: gap) == [40, 50])
    #expect(MonitorServerPresentation.trendValues(shuffled, meter: .memory, maxGap: gap) == [65, 70])
}

@Test func gapFollowsBucketAndCollectorInterval() {
    #expect(MonitorServerPresentation.maxGap(bucketSeconds: 60, heartbeats: []) == 150)
    #expect(MonitorServerPresentation.maxGap(bucketSeconds: nil, heartbeats: []) == 150)
    #expect(MonitorServerPresentation.maxGap(bucketSeconds: 300, heartbeats: []) == 750)
    let slowCollector = [OpsJobHeartbeat(jobName: "ops_metrics_collector", expectedIntervalSeconds: 300)]
    let gap = MonitorServerPresentation.maxGap(bucketSeconds: 60, heartbeats: slowCollector)
    #expect(gap == 750)
    let fiveMinutes = (0..<4).map { SystemMetricsHistory.Point(createdAt: now.addingTimeInterval(Double($0) * 300), cpuUsagePercent: 30) }
    #expect(MonitorServerPresentation.trendValues(fiveMinutes, meter: .cpu, maxGap: gap) == [30, 30, 30, 30])
    // The collector's interval comes from the overview's heartbeats.
    let collectorOverview = OpsOverview(systemMetrics: sampleMetrics, jobHeartbeats: slowCollector)
    let shown = display(overview: loaded(collectorOverview), history: loaded(SystemMetricsHistory(bucketSeconds: 60, points: fiveMinutes)))
    #expect(shown.cpu.trend == [30, 30, 30, 30])
}

@Test func withoutHistoryUsesLocalSamples() {
    let samples = [SystemMetricsHistory.Point(createdAt: now.addingTimeInterval(-120), cpuUsagePercent: 20, memoryUsagePercent: 60),
                   SystemMetricsHistory.Point(createdAt: now.addingTimeInterval(-60), cpuUsagePercent: nil, memoryUsagePercent: 61),
                   SystemMetricsHistory.Point(createdAt: now, cpuUsagePercent: 25, memoryUsagePercent: 62)]
    for history in [BlockDisplay<SystemMetricsHistory>.placeholder, .failed(reason: failed503), loaded(sampleHistory())] {
        let shown = display(history: history, localSamples: samples, unavailable: [.systemMetrics])
        #expect(shown.cpu.trend == [20, nil, 25])
        #expect(shown.memory.trend == [60, 61, 62])
        #expect(!shown.loadingParts.contains(.systemMetrics) && shown.failure == nil && shown.staleParts.isEmpty)
    }
}

@Test func historyFailureFlagsOnlyTheTrend() {
    let shown = display(history: .failed(reason: failed503))
    #expect(shown.failure == MonitorServerDisplay.FailureRow(parts: [.systemMetrics], title: "趋势加载失败"))
    #expect(shown.failure?.anchor == .systemMetrics)
    #expect(shown.cpu.trend == [] && shown.memory.trend == [])
    #expect(shown.cpu.reading.text == "92.0%")

    let kept = display(history: stale(sampleHistory()))
    #expect(kept.cpu.trend.count == 60 && kept.staleParts == [.systemMetrics] && kept.failure == nil)
}

// MARK: 并发、排队、QPS、SLA

@Test func concurrencySumsPlatformsAndQueue() {
    let shown = display()
    #expect(shown.concurrency == MonitorPresentation.concurrency(sampleConcurrency, queueDepth: 4))
    #expect(shown.concurrency.inUse == "8/50" && shown.concurrency.queue == "1" && !shown.concurrency.isRealtimeOff)
}

/// Appendix A S7: realtime monitoring off is not ops monitoring off.
@Test func realtimeOffShowsDashFlagAndQueueDepth() {
    let shown = display(concurrency: loaded(OpsConcurrency(enabled: false)))
    #expect(shown.concurrency.inUse == "—" && shown.concurrency.isRealtimeOff && shown.concurrency.queue == "4")
    #expect(shown.failure == nil)
    let noDepth = display(overview: loaded(OpsOverview(systemMetrics: OpsSystemMetricsSnapshot(createdAt: now))),
                          concurrency: loaded(OpsConcurrency(enabled: false)))
    #expect(noDepth.concurrency.queue == "—")
}

@Test func concurrencyFailureIsolatedToItsRow() {
    let shown = display(concurrency: .failed(reason: failed503))
    #expect(shown.concurrency.inUse == "—" && !shown.concurrency.isRealtimeOff && shown.concurrency.queue == "4")
    #expect(shown.failure == MonitorServerDisplay.FailureRow(parts: [.concurrency], title: "加载失败"))
    #expect(shown.failure?.anchor == .concurrency)
    let healthy = display()
    #expect(shown.cpu == healthy.cpu && shown.memory == healthy.memory && shown.qps == healthy.qps && shown.sla == healthy.sla)
    #expect(shown.ingest == healthy.ingest && shown.jobs == healthy.jobs)
}

@Test func qpsAndSlaFromOverview() {
    let shown = display()
    #expect(shown.qps == "0.8" && shown.sla == "99.2%")
    #expect(shown.qps == MonitorPresentation.qps(sampleOverview) && shown.sla == MonitorPresentation.sla(sampleOverview))
    #expect(display(overview: loaded(OpsOverview(sla: 0.992))).qps == "—")
}

// MARK: 任务行、日志采集行

@Test func emptyHeartbeatsGiveEmptyJobs() {
    let shown = display(overview: loaded(OpsOverview(systemMetrics: sampleMetrics)))
    #expect(shown.jobs == .empty)
    #expect(!shown.ingest.detail.contains("需留意"))
    #expect(MonitorServerPresentation.noHeartbeats == "还没有后台任务心跳")
}

@Test func heartbeatLinesFollowStatusCapability() {
    let reported = display(heartbeatStatusSupported: true)
    #expect(reported.jobs == .lines(MonitorPresentation.jobLines(sampleBeats, supportsStatus: true, now: now, timeZone: shanghai)))
    let local = display(heartbeatStatusSupported: false)
    #expect(local.jobs == .lines(MonitorPresentation.jobLines(sampleBeats, supportsStatus: false, now: now, timeZone: shanghai)))
    guard case .lines(let lines) = reported.jobs else { Issue.record("no job lines"); return }
    #expect(lines.last?.id == "ops_custom_sync" && lines.last?.title == "ops_custom_sync" && lines.last?.state == .unknown)
}

@Test func ingestLineCombinesLogsIngressAndAttention() {
    let shown = display()
    #expect(shown.ingest == MonitorPresentation.logIngest(sampleLogs, rejections: .exact(3), attentionCount: 3))
    #expect(shown.ingest.trailing == "延迟 850ms" && shown.ingest.detail == "入口拒绝 3 次（1 小时）· 3 个任务需留意" && shown.ingest.isHealthy == true)
    #expect(display(logHealth: loaded(SystemLogHealth(avgWriteDelayMs: 2_000))).ingest.trailing == "延迟 2.0s")
    #expect(display(ingress: loaded(.atLeast(600))).ingest.detail.hasPrefix("入口拒绝 ≥ 600 次（1 小时）"))
}

@Test func ingestFailuresShowDash() {
    let logs = display(logHealth: .failed(reason: failed503))
    #expect(logs.ingest.trailing == "—" && logs.ingest.isHealthy == nil)
    #expect(logs.failure?.parts == [.logHealth] && logs.failure?.anchor == .logHealth)
    let ingress = display(ingress: .failed(reason: failed503))
    #expect(ingress.ingest.detail.hasPrefix("入口拒绝 —") && ingress.failure?.parts == [.ingress])
    #expect(display(logHealth: loaded(SystemLogHealth(avgWriteDelayMs: 850, lastError: "disk full"))).ingest.isHealthy == false)
}

@Test func multipleFailuresMergeIntoOneRow() {
    let two = display(concurrency: .failed(reason: failed503), ingress: .failed(reason: failed503))
    #expect(two.failure == MonitorServerDisplay.FailureRow(parts: [.concurrency, .ingress], title: "加载失败"))
    #expect(two.failure?.anchor == nil)
    let all = display(history: .failed(reason: nil), concurrency: .failed(reason: nil), logHealth: .failed(reason: nil), ingress: .failed(reason: nil))
    #expect(all.failure?.parts == MonitorServerPart.allCases && all.failure?.title == "加载失败")
}

/// 00 §5 item 3: a route the site lacks shows “—”, never a failure.
@Test func unavailablePartsShowDashWithoutFailure() {
    let shown = display(logHealth: .failed(reason: nil), ingress: .failed(reason: nil), unavailable: [.ingress, .logHealth])
    #expect(shown.ingest.trailing == "—" && shown.ingest.detail.hasPrefix("入口拒绝 —"))
    #expect(shown.failure == nil)
    let pending = display(logHealth: .placeholder, ingress: stale(.exact(2)), unavailable: [.ingress, .logHealth])
    #expect(pending.loadingParts.isEmpty && pending.staleParts.isEmpty && pending.ingest.detail.hasPrefix("入口拒绝 —"))
}

@Test func staleValuesKeepNumbersInPartOrder() {
    let shown = display(history: stale(sampleHistory()), concurrency: stale(sampleConcurrency), logHealth: stale(sampleLogs), ingress: stale(.exact(3)))
    #expect(shown.staleParts == [.systemMetrics, .concurrency, .logHealth, .ingress])
    #expect(shown.failure == nil)
    #expect(shown.concurrency.inUse == "8/50" && shown.ingest.trailing == "延迟 850ms" && shown.cpu.trend.count == 60)
}

@Test func trendSpokenValueReadsLatestAndPeak() {
    #expect(MonitorServerPresentation.trendSpokenValue([30, nil, 95, 92]) == "最近 92.0%，最高 95.0%")
    #expect(MonitorServerPresentation.trendSpokenValue([nil, nil]) == "无数据")
    #expect(MonitorServerPresentation.trendSpokenValue([]) == "无数据")
    #expect(display().cpu.spokenTrend == MonitorServerPresentation.trendSpokenValue(display().cpu.trend))
    #expect(MonitorServerDisplay.Meter.cpu.trendLabel == "CPU 趋势" && MonitorServerDisplay.Meter.memory.trendLabel == "内存趋势")
}
