import Foundation
import Testing
@testable import Sub2Core

// MARK: - 监控概况与服务器区的纯函数（10 §1.3.5、§4.3，S1-02）

private enum MonitorFixture {
    static func utc(_ text: String) -> Date { ServerTime.parseTimestamp(text)! }
    static let now = utc("2026-10-23T02:00:00Z")
    static let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    static func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }
    static func line(_ beat: OpsJobHeartbeat, supportsStatus: Bool = true) -> MonitorPresentation.JobLine {
        MonitorPresentation.jobLines([beat], supportsStatus: supportsStatus, now: now, timeZone: shanghai)[0]
    }
    static func state(_ beat: OpsJobHeartbeat) -> MonitorPresentation.JobState {
        MonitorPresentation.jobState(beat, supportsStatus: false, now: now)
    }
    static func snapshot(end: String, throughput: [(String, Int)] = [], errors: [(String, Int, Int)] = []) -> OpsSnapshotV2 {
        let windowEnd = utc(end)
        return OpsSnapshotV2(throughputPoints: throughput.map { OpsSnapshotV2.ThroughputPoint(bucketStart: utc($0.0), requestCount: $0.1) },
                             errorPoints: errors.map { OpsSnapshotV2.ErrorPoint(bucketStart: utc($0.0), errorCountSLA: $0.1, businessLimitedCount: $0.2) },
                             windowStart: windowEnd.addingTimeInterval(-2_700), windowEnd: windowEnd)
    }
    /// "10:07" on 2026-10-23 UTC.
    static func minute(_ clock: String) -> String { "2026-10-23T\(clock):00Z" }
    static func ingress(_ counts: [Int], total: Int?, pageSize: Int? = 200, requestCountTotal: Int? = nil) -> IngressRejectList {
        IngressRejectList(items: counts.map(IngressRejectList.Item.init(requestCount:)), total: total, page: 1, pageSize: pageSize,
                          requestCountTotal: requestCountTotal)
    }
}

// MARK: 健康分（1.3.5）

@Test func healthScoreTiers() {
    let cases: [(Int, String, Tone, Double)] = [(100, "良好", .ok, 1), (90, "良好", .ok, 0.9), (89, "风险", .caution, 0.89),
                                                (60, "风险", .caution, 0.6), (59, "异常", .critical, 0.59), (0, "异常", .critical, 0),
                                                (130, "良好", .ok, 1), (-5, "异常", .critical, 0)]
    for (score, word, tone, fraction) in cases {
        #expect(MonitorPresentation.health(score) == MonitorPresentation.HealthReading(value: DisplayFormat.grouped(score), word: word, tone: tone,
                                                                                         fraction: fraction))
    }
    #expect(MonitorPresentation.health(nil) == MonitorPresentation.HealthReading(value: "—", word: nil, tone: nil, fraction: nil))
}

// MARK: 任务行（4.3 任务行表与本地判定）

@Test func jobNamesMapAndSortByTableOrder() {
    let names = ["custom_b", "ops_scheduled_reports", "custom_a", "ops_metrics_collector", "ops_cleanup", "ops_preaggregation_daily",
                 "ops_alert_evaluator", "ops_preaggregation_hourly"]
    let input = names.map { OpsJobHeartbeat(jobName: $0) }
    let sorted = MonitorPresentation.sortedHeartbeats(input)
    #expect(sorted.map { MonitorPresentation.jobTitle($0.jobName) } == ["指标采集", "告警评估", "预聚合（小时）", "预聚合（天）", "清理", "定时报告",
                                                                       "custom_a", "custom_b"])
    #expect(input.map(\.jobName) == names)
    #expect(MonitorPresentation.knownJobNames.count == 6)
    #expect(MonitorPresentation.jobLines(input, supportsStatus: true, now: MonitorFixture.now, timeZone: MonitorFixture.shanghai).map(\.id)
            == sorted.map(\.jobName))
}

@Test func reportedStatusMapsWithUnknownFallback() {
    let raw: [(String?, MonitorPresentation.JobState)] = [("ok", .ok), ("failing", .failing), ("stale", .stale), ("disabled", .disabled),
                                                         ("unknown", .unknown), (" Failing ", .failing), ("paused", .unknown), (nil, .unknown)]
    for (status, expected) in raw {
        // A newer error would make the local rule say failing; with the capability only the reported status counts.
        let beat = OpsJobHeartbeat(jobName: "ops_alert_evaluator", lastSuccessAt: MonitorFixture.ago(600), lastErrorAt: MonitorFixture.ago(60), status: status)
        #expect(MonitorPresentation.jobState(beat, supportsStatus: true, now: MonitorFixture.now) == expected)
    }
}

@Test func localJudgementFollowsFourRules() {
    typealias Beat = OpsJobHeartbeat
    let ago = MonitorFixture.ago
    #expect(MonitorFixture.state(Beat(jobName: "ops_alert_evaluator", lastSuccessAt: ago(120), lastErrorAt: ago(30))) == .failing)
    #expect(MonitorFixture.state(Beat(jobName: "ops_alert_evaluator", lastErrorAt: ago(30))) == .failing)
    #expect(MonitorFixture.state(Beat(jobName: "ops_alert_evaluator", lastSuccessAt: ago(30), lastErrorAt: ago(120))) == .ok)
    for name in ["ops_metrics_collector", "ops_alert_evaluator"] {
        #expect(MonitorFixture.state(Beat(jobName: name, lastSuccessAt: ago(181))) == .stale)
        #expect(MonitorFixture.state(Beat(jobName: name, lastSuccessAt: ago(180))) == .ok)
    }
    #expect(MonitorFixture.state(Beat(jobName: "ops_preaggregation_hourly", lastSuccessAt: ago(1_801))) == .stale)
    #expect(MonitorFixture.state(Beat(jobName: "ops_preaggregation_hourly", lastSuccessAt: ago(1_800))) == .ok)
    #expect(MonitorFixture.state(Beat(jobName: "ops_preaggregation_daily", lastSuccessAt: ago(10_801))) == .stale)
    #expect(MonitorFixture.state(Beat(jobName: "ops_preaggregation_daily", lastSuccessAt: ago(10_800))) == .ok)
    for name in ["ops_cleanup", "ops_scheduled_reports", "custom_sync"] {
        #expect(MonitorFixture.state(Beat(jobName: name, lastSuccessAt: ago(172_800))) == .ok)
        #expect(MonitorFixture.state(Beat(jobName: name, lastSuccessAt: ago(172_800), lastErrorAt: ago(60))) == .failing)
    }
    // Stale wins over failing, as on the server (D08), so a job that keeps failing turns stale.
    #expect(MonitorFixture.state(Beat(jobName: "ops_metrics_collector", lastSuccessAt: ago(600), lastErrorAt: ago(60))) == .stale)
    #expect(MonitorFixture.state(Beat(jobName: "ops_metrics_collector")) == .unknown)
    #expect(MonitorFixture.state(Beat(jobName: "ops_metrics_collector", status: "ok")) == .unknown)
}

@Test func jobLineTrailingTextPerState() {
    typealias Beat = OpsJobHeartbeat
    let recent = MonitorFixture.ago(240)
    let ok = MonitorFixture.line(Beat(jobName: "ops_metrics_collector", lastSuccessAt: recent, status: "ok"))
    #expect(ok.trailing == "4 分钟前" && !ok.trailingIsCaution && ok.tone == .ok && ok.state == .ok && ok.title == "指标采集")
    #expect(MonitorFixture.line(Beat(jobName: "ops_cleanup", lastSuccessAt: MonitorFixture.utc("2026-10-22T19:00:00Z"), status: "ok")).trailing
            == "今天 03:00")
    for status in ["failing", "stale"] {
        let line = MonitorFixture.line(Beat(jobName: "ops_alert_evaluator", lastSuccessAt: recent, status: status))
        #expect(line.trailing == "最近成功 4 分钟前" && line.trailingIsCaution && line.tone == .caution)
        let never = MonitorFixture.line(Beat(jobName: "ops_alert_evaluator", status: status))
        #expect(never.trailing == "从未成功" && never.trailingIsCaution)
    }
    let disabled = MonitorFixture.line(Beat(jobName: "ops_cleanup", lastSuccessAt: recent, status: "disabled"))
    #expect(disabled.trailing == "已关闭" && !disabled.trailingIsCaution && disabled.tone == nil)
    let unknown = MonitorFixture.line(Beat(jobName: "custom_sync", status: "paused"))
    #expect(unknown.trailing == "—" && unknown.tone == nil && unknown.title == "custom_sync")
    let okNever = MonitorFixture.line(Beat(jobName: "ops_scheduled_reports", status: "ok"))
    #expect(okNever.trailing == "从未成功" && !okNever.trailingIsCaution)
}

@Test func jobLineDetailTextPerState() {
    typealias Beat = OpsJobHeartbeat
    let ago = MonitorFixture.ago
    func detail(_ beat: Beat, supportsStatus: Bool = true) -> String? { MonitorFixture.line(beat, supportsStatus: supportsStatus).detail }
    #expect(detail(Beat(jobName: "ops_alert_evaluator", lastError: "  dial tcp timeout\n\tat goroutine 7\n", status: "failing"))
            == "最近一次失败：dial tcp timeout")
    for blank in ["", " \n ", nil] as [String?] {
        #expect(detail(Beat(jobName: "ops_alert_evaluator", lastError: blank, status: "failing")) == nil)
    }
    #expect(detail(Beat(jobName: "ops_metrics_collector", status: "stale", expectedIntervalSeconds: 60)) == "超过 2 分钟没有成功，需要看一下")
    #expect(detail(Beat(jobName: "ops_preaggregation_hourly", status: "stale", expectedIntervalSeconds: 600)) == "超过 20 分钟没有成功，需要看一下")
    #expect(detail(Beat(jobName: "ops_preaggregation_daily", status: "stale", expectedIntervalSeconds: 3_600)) == "超过 2 小时没有成功，需要看一下")
    let schedule: [(String, String)] = [("2026-10-22T19:00:00Z", "今天 03:00"), ("2026-10-21T19:00:00Z", "昨天 03:00"),
                                        ("2026-10-23T19:00:00Z", "明天 03:00"), ("2026-10-20T19:00:00Z", "10月21日 03:00")]
    for (next, text) in schedule {
        let beat = Beat(jobName: "ops_cleanup", status: "stale", expectedIntervalSeconds: 86_400, nextExpectedAt: MonitorFixture.utc(next))
        #expect(detail(beat) == "按计划应在 \(text) 前完成")
    }
    #expect(detail(Beat(jobName: "ops_cleanup", status: "stale", expectedIntervalSeconds: 86_400)) == nil)
    #expect(detail(Beat(jobName: "ops_metrics_collector", status: "stale")) == nil)
    #expect(detail(Beat(jobName: "ops_metrics_collector", lastSuccessAt: ago(181)), supportsStatus: false) == "超过 3 分钟没有成功，需要看一下")
    #expect(detail(Beat(jobName: "ops_preaggregation_hourly", lastSuccessAt: ago(1_801)), supportsStatus: false) == "超过 30 分钟没有成功，需要看一下")
    #expect(detail(Beat(jobName: "ops_preaggregation_daily", lastSuccessAt: ago(10_801)), supportsStatus: false) == "超过 3 小时没有成功，需要看一下")
    #expect(detail(Beat(jobName: "ops_cleanup", lastSuccessAt: ago(600), lastErrorAt: ago(60), lastError: "disk full"), supportsStatus: false)
            == "最近一次失败：disk full")
    for status in ["ok", "disabled", "unknown"] {
        #expect(detail(Beat(jobName: "ops_alert_evaluator", lastSuccessAt: ago(60), lastError: "old", status: status, expectedIntervalSeconds: 60)) == nil)
    }
}

@Test func attentionCountsFailingAndStaleOnly() {
    let states: [MonitorPresentation.JobState] = [.ok, .failing, .stale, .disabled, .unknown, .stale]
    let lines = states.enumerated().map { MonitorPresentation.JobLine(id: "job\($0.offset)", title: "任务", state: $0.element, trailing: "—",
                                                                      trailingIsCaution: false, detail: nil) }
    #expect(MonitorPresentation.attentionCount(lines) == 3)
    #expect(MonitorPresentation.attentionCount([]) == 0)
    #expect(MonitorPresentation.JobState.allCases.filter(\.needsAttention) == [.failing, .stale])
}

// MARK: 错误率小折线（4.3）

@Test func errorRateSeriesMergesFortyFiveMinuteBucketsIntoNinePoints() {
    let minutes = (0..<45).map { MonitorFixture.utc("2026-10-23T10:00:00Z").addingTimeInterval(Double($0) * 60) }
    let snapshot = OpsSnapshotV2(throughputPoints: minutes.map { OpsSnapshotV2.ThroughputPoint(bucketStart: $0, requestCount: 100) },
                                 errorPoints: minutes.enumerated().map {
                                     OpsSnapshotV2.ErrorPoint(bucketStart: $0.element, errorCountSLA: $0.offset < 5 ? 1 : 0, businessLimitedCount: 0)
                                 },
                                 windowStart: minutes[0], windowEnd: MonitorFixture.utc("2026-10-23T10:45:00Z"))
    let series = MonitorPresentation.errorRateSeries(snapshot)
    #expect(series.count == MonitorPresentation.errorRatePointCount)
    #expect(series.map(\.start) == (0..<9).map { minutes[0].addingTimeInterval(Double($0) * 300) })
    let expected: [Double?] = [0.01, 0, 0, 0, 0, 0, 0, 0, 0]
    #expect(series.map(\.rate) == expected)
    #expect(series.first?.id == minutes[0])
}

@Test func errorRateSeriesHandlesResidualSparseAndZeroDenominator() {
    let minute = MonitorFixture.minute
    let clocks = (0..<48).map { offset -> String in
        let total = 9 * 60 + 59 + offset
        return minute(String(format: "%02d:%02d", total / 60, total % 60))
    }
    let failing = ["09:59", "10:00", "10:05", "10:06", "10:40", "10:41", "10:45", "10:46"].map(minute)
    let residual = MonitorFixture.snapshot(end: "2026-10-23T10:45:30Z", throughput: clocks.map { ($0, 10) },
                                           errors: failing.map { ($0, 1, 0) })
    let series = MonitorPresentation.errorRateSeries(residual)
    #expect(series.count == 9)
    #expect(series.first?.start == MonitorFixture.utc("2026-10-23T10:00:30Z"))
    let fifth: Double = 1.0 / 50
    let expected: [Double?] = [2.0 / 60, fifth, 0, 0, 0, 0, 0, fifth, 2 * fifth]
    #expect(series.map(\.rate) == expected)

    let sparse = MonitorPresentation.errorRateSeries(MonitorFixture.snapshot(end: "2026-10-23T10:45:00Z",
        throughput: [(minute("10:05"), 300), (minute("10:06"), 200), (minute("10:10"), 50)],
        errors: [(minute("10:05"), 3, 60), (minute("10:07"), 5, 40), (minute("10:10"), 0, 50), (minute("10:15"), 3, 0)]))
    let sparseExpected: [Double?] = [nil, 0.02, nil, nil, nil, nil, nil, nil, nil]
    #expect(sparse.map(\.rate) == sparseExpected)

    let empty = MonitorPresentation.errorRateSeries(MonitorFixture.snapshot(end: "2026-10-23T10:45:00Z"))
    #expect(empty.count == 9 && empty.allSatisfy { $0.rate == nil })
    #expect(empty.last?.start == MonitorFixture.utc("2026-10-23T10:40:00Z"))
}

// MARK: 服务器区（4.3）

@Test func capacityToneAndText() {
    #expect(MonitorPresentation.capacity(nil) == MonitorPresentation.CapacityReading(text: "—", fraction: nil, tone: nil))
    let cpu = MonitorPresentation.capacity(38.2)
    #expect(cpu.text == "38.2%" && cpu.tone == nil && abs((cpu.fraction ?? 0) - 0.382) < 1e-12)
    #expect(MonitorPresentation.capacity(61) == MonitorPresentation.CapacityReading(text: "61.0%", fraction: 0.61, tone: nil))
    #expect(MonitorPresentation.capacityTone(74.9) == nil)
    #expect(MonitorPresentation.capacityTone(75) == .caution); #expect(MonitorPresentation.capacityTone(89.9) == .caution)
    #expect(MonitorPresentation.capacityTone(90) == .critical); #expect(MonitorPresentation.capacityTone(nil) == nil)
    #expect(MonitorPresentation.capacity(120) == MonitorPresentation.CapacityReading(text: "120.0%", fraction: 1, tone: .critical))
    #expect(MonitorPresentation.capacity(-3).fraction == 0)
    #expect(MonitorPresentation.capacity(.nan) == MonitorPresentation.CapacityReading(text: "—", fraction: nil, tone: nil))
}

@Test func concurrencyAndQueueReadings() {
    typealias Load = OpsConcurrency.PlatformLoad
    let live = OpsConcurrency(platforms: ["anthropic": Load(currentInUse: 3, maxCapacity: 20, waitingInQueue: 1),
                                          "openai": Load(currentInUse: 5, maxCapacity: 30, waitingInQueue: 2)])
    #expect(MonitorPresentation.concurrency(live, queueDepth: 9) == MonitorPresentation.ConcurrencyReading(inUse: "8/50", queue: "3", isRealtimeOff: false))
    #expect(MonitorPresentation.concurrency(OpsConcurrency(enabled: false), queueDepth: 4)
            == MonitorPresentation.ConcurrencyReading(inUse: "—", queue: "4", isRealtimeOff: true))
    #expect(MonitorPresentation.concurrency(OpsConcurrency(enabled: false), queueDepth: nil)
            == MonitorPresentation.ConcurrencyReading(inUse: "—", queue: "—", isRealtimeOff: true))
    #expect(MonitorPresentation.concurrency(nil, queueDepth: 2) == MonitorPresentation.ConcurrencyReading(inUse: "—", queue: "2", isRealtimeOff: false))
    #expect(MonitorPresentation.concurrency(OpsConcurrency(), queueDepth: nil) == MonitorPresentation.ConcurrencyReading(inUse: "0/0", queue: "0", isRealtimeOff: false))
    let large = OpsConcurrency(platforms: ["a": Load(currentInUse: 1_000, maxCapacity: 2_000, waitingInQueue: 5), "b": Load(currentInUse: 24, maxCapacity: 48)])
    #expect(MonitorPresentation.concurrency(large, queueDepth: nil) == MonitorPresentation.ConcurrencyReading(inUse: "1,024/2,048", queue: "5", isRealtimeOff: false))
}

@Test func qpsAndSlaText() {
    #expect(MonitorPresentation.qps(OpsOverview(qps: OpsRateSummary(current: 0.8))) == "0.8")
    #expect(MonitorPresentation.qps(OpsOverview(qps: OpsRateSummary(current: 12))) == "12.0")
    #expect(MonitorPresentation.qps(OpsOverview()) == "—"); #expect(MonitorPresentation.qps(nil) == "—")
    #expect(MonitorPresentation.sla(OpsOverview(sla: 0.992)) == "99.2%")
    #expect(MonitorPresentation.sla(OpsOverview()) == "—"); #expect(MonitorPresentation.sla(nil) == "—")
}

@Test func logIngestLineUsesMillisFormatWithoutSpace() {
    func line(_ health: SystemLogHealth?) -> MonitorPresentation.LogIngestLine {
        MonitorPresentation.logIngest(health, rejections: .exact(0), attentionCount: 0)
    }
    #expect(line(SystemLogHealth(avgWriteDelayMs: 850, lastError: "")).trailing == "延迟 850ms")
    #expect(line(SystemLogHealth(avgWriteDelayMs: 850, lastError: "")).isHealthy == true)
    #expect(line(SystemLogHealth(avgWriteDelayMs: 2_000)).trailing == "延迟 2.0s")
    #expect(line(SystemLogHealth(avgWriteDelayMs: 12_000)).trailing == "延迟 12s")
    #expect(line(SystemLogHealth(avgWriteDelayMs: 0)).trailing == "延迟 0ms")
    #expect(line(SystemLogHealth(avgWriteDelayMs: 5, lastError: "write failed")).isHealthy == false)
    #expect(line(SystemLogHealth(lastError: "")).trailing == "—")
    #expect(line(nil).trailing == "—"); #expect(line(nil).isHealthy == nil)
}

@Test func logIngestDetailCombinesRejectionsAndAttention() {
    func detail(_ rejections: MonitorPresentation.IngressRejectTally?, _ attention: Int) -> String {
        MonitorPresentation.logIngest(SystemLogHealth(avgWriteDelayMs: 850), rejections: rejections, attentionCount: attention).detail
    }
    #expect(detail(.exact(3), 1) == "入口拒绝 3 次（1 小时）· 1 个任务需留意")
    #expect(detail(.exact(3), 0) == "入口拒绝 3 次（1 小时）")
    #expect(detail(nil, 2) == "入口拒绝 — · 2 个任务需留意")
    #expect(detail(nil, 0) == "入口拒绝 —")
    #expect(detail(.atLeast(600), 0) == "入口拒绝 ≥ 600 次（1 小时）")
    #expect(detail(.exact(1_284), 0) == "入口拒绝 1,284 次（1 小时）")
    #expect(MonitorPresentation.logIngest(nil, rejections: .exact(0), attentionCount: 1).detail == "入口拒绝 0 次（1 小时）· 1 个任务需留意")
}

@Test func ingressTallyFallsBackToThreePages() {
    typealias Tally = MonitorPresentation.IngressRejectTally
    let ingress = MonitorFixture.ingress
    let full = Array(repeating: 1, count: 200)
    let cases: [([IngressRejectList], Tally?, Bool)] = [
        ([ingress([3], 1, 1, 7)], .exact(7), false),
        ([ingress([3, 2], 2, 200, nil)], .exact(5), false),
        ([ingress(full, 450, 200, nil)], .atLeast(200), true),
        ([ingress(full, 450, 200, nil), ingress(Array(repeating: 1, count: 200), 450, 200, nil)], .atLeast(400), true),
        ([ingress(full, 250, 200, nil), ingress(Array(repeating: 3, count: 50), 250, 200, nil)], .exact(350), false),
        ([ingress(full, 900, 200, nil), ingress(full, 900, 200, nil), ingress(full, 900, 200, nil)], .atLeast(600), false),
        ([ingress(full, nil, 200, nil)], .atLeast(200), true),
        ([ingress(Array(repeating: 2, count: 150), nil, 200, nil)], .exact(300), false),
        ([ingress(full, nil, nil, nil)], .atLeast(200), true),
        ([], nil, false)
    ]
    for (pages, tally, needsMore) in cases {
        #expect(MonitorPresentation.ingressRejectTally(pages) == tally)
        #expect(MonitorPresentation.needsMoreIngressPages(pages) == needsMore)
    }
    #expect(MonitorPresentation.ingressFallbackPageSize == 200 && MonitorPresentation.ingressFallbackPageLimit == 3)
}

@Test func localSamplesAppendReplaceAndCapAtSixty() {
    typealias Point = SystemMetricsHistory.Point
    let base = MonitorFixture.now
    let first = MonitorPresentation.appendingLocalSample([], from: OpsSystemMetricsSnapshot(createdAt: base, cpuUsagePercent: 30, memoryUsagePercent: 60))
    #expect(first == [Point(createdAt: base, cpuUsagePercent: 30, memoryUsagePercent: 60)])
    let replaced = MonitorPresentation.appendingLocalSample(first, from: OpsSystemMetricsSnapshot(createdAt: base, cpuUsagePercent: 31))
    #expect(replaced == [Point(createdAt: base, cpuUsagePercent: 31)])
    #expect(MonitorPresentation.appendingLocalSample(first, from: OpsSystemMetricsSnapshot(createdAt: base.addingTimeInterval(-60), cpuUsagePercent: 1)) == first)
    #expect(MonitorPresentation.appendingLocalSample(first, from: nil) == first)
    #expect(MonitorPresentation.appendingLocalSample(first, from: OpsSystemMetricsSnapshot(cpuUsagePercent: 1)) == first)
    let sixty = (0..<60).map { Point(createdAt: base.addingTimeInterval(Double($0) * 60), cpuUsagePercent: Double($0)) }
    let newest = base.addingTimeInterval(3_600)
    let capped = MonitorPresentation.appendingLocalSample(sixty, from: OpsSystemMetricsSnapshot(createdAt: newest, cpuUsagePercent: 99))
    #expect(capped.count == MonitorPresentation.localSampleLimit)
    #expect(capped.first == sixty[1]); #expect(capped.last == Point(createdAt: newest, cpuUsagePercent: 99))
    #expect(sixty.count == 60 && sixty.first?.cpuUsagePercent == 0)
}
