import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-13: LiveOpsStore's monitor overview (10 §4.1, §4.2, §4.5, §4.6; 00 §4.6; U08).

private let serverFailure = APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private func utc(_ text: String) -> Date { ServerTime.parseTimestamp(text)! }
private func isOverviewRange(_ call: StubLiveOpsSource.Call) -> Bool { if case .overviewRange = call { true } else { false } }
private func isOverviewWindow(_ call: StubLiveOpsSource.Call) -> Bool { if case .overview = call { true } else { false } }
private func isSnapshot(_ call: StubLiveOpsSource.Call) -> Bool { if case .snapshot = call { true } else { false } }
private func isAlertList(_ call: StubLiveOpsSource.Call) -> Bool { if case .alertEvents = call { true } else { false } }

/// 45 one-minute buckets from `start`, 100 requests and one SLA error each: every five-minute point is 1%.
private func snapshot(start: Date, end: Date) -> OpsSnapshotV2 {
    let minutes = (0..<45).map { start.addingTimeInterval(Double($0) * 60) }
    return OpsSnapshotV2(throughputPoints: minutes.map { .init(bucketStart: $0, requestCount: 100) },
                         errorPoints: minutes.map { .init(bucketStart: $0, errorCountSLA: 1, businessLimitedCount: 0) },
                         windowStart: start, windowEnd: end)
}
private let overview = OpsOverview(healthScore: 92, errorRate: 0.0086, upstream429Count: 3, upstream529Count: 0)
/// Every monitor read answers, the server section's too (S1-14); nothing fires. The site has none of the server capabilities,
/// so 服务器 reads 并发, 日志采集 and 入口拒绝 (paged): five timers in all.
private func monitorSource() -> StubLiveOpsSource {
    StubLiveOpsSource(.init(overview: { _, _ in overview }, alertEvents: { _, _ in [] }, alertCounts: { AlertCounts(firing: 0) },
                            snapshot: { snapshot(start: $0, end: $1) }, concurrency: { OpsConcurrency() }, logsHealth: { SystemLogHealth() },
                            ingress: { _, _ in IngressRejectList() }))
}
private let timerCount = 5
private func isServerRead(_ call: StubLiveOpsSource.Call) -> Bool {
    switch call {
    case .concurrency, .logsHealth, .ingress: true
    default: false
    }
}

@MainActor @Test func segmentStartsOnOverviewForEachStore() {
    let first = LiveOpsHarness().store
    #expect(first.monitor.segment == .overview)
    first.monitor.segment = .alerts
    #expect(first.monitor.segment == .alerts)
    // A new session makes a new store, which starts on 概况 again.
    #expect(LiveOpsHarness().store.monitor.segment == .overview)
}

@MainActor @Test func overviewRoundRequestsFiveMinuteOverviewAndFortyFiveMinuteTrend() async {
    let source = monitorSource()
    let store = LiveOpsHarness(source, serverNow: utc("2026-10-16T02:00:42Z")).store
    await store.refreshMonitorOverview(force: false)
    let calls = await source.calls
    #expect(calls.filter(isOverviewRange) == [.overviewRange("5m")])
    #expect(!calls.contains(where: isOverviewWindow))
    #expect(calls.filter(isSnapshot) == [.snapshot(start: utc("2026-10-16T01:15:00Z"), end: utc("2026-10-16T02:00:00Z"))])
    #expect(calls.filter(isAlertList) == [.alertEvents(status: "firing", limit: 100)])
    #expect(store.monitor.overview.value == overview)
    #expect(store.monitor.errorTrend.value == Array(repeating: 0.01, count: 9))
}

/// 10 §4.5: the run and the line fail on their own; a failed refresh keeps the earlier figures.
@MainActor @Test func blocksSucceedAndFailIndependently() async {
    let source = monitorSource()
    await source.update { $0.snapshot = { _, _ in throw serverFailure } }
    let store = LiveOpsHarness(source).store
    await store.refreshMonitorOverview(force: false)
    #expect(store.monitor.overview.value == overview && store.monitor.overview.error == nil)
    #expect(store.monitor.errorTrend.value == nil && store.monitor.errorTrend.error != nil)
    #expect(store.monitorRefreshStatus == .partial)

    await source.update {
        $0.overview = { _, _ in throw serverFailure }
        $0.snapshot = { snapshot(start: $0, end: $1) }
    }
    await store.refreshMonitorOverview(force: true)
    #expect(MonitorTabPresentation.health(store.monitor.overview.state.display) == .score(MonitorPresentation.health(92), updateFailed: true))
    #expect(store.monitor.errorTrend.value?.count == 9)
    #expect(store.monitorRefreshStatus == .partial)

    await source.update { $0.overview = { _, _ in overview } }
    await store.refreshMonitorOverview(force: true)
    #expect(isUpdated(store.monitorRefreshStatus))
}
private func isUpdated(_ status: HomeRefreshStatus?) -> Bool { if case .updated? = status { true } else { false } }

/// 10 §4.5, §7.2: a 404 OPS_DISABLED turns the switch off (its reason is read once) and the timers end by themselves.
@MainActor @Test func opsDisabledReplyFlipsStoreAndStopsPolling() async {
    let source = StubLiveOpsSource(.init(overview: { _, _ in throw opsDisabledError }, alertEvents: { _, _ in throw opsDisabledError },
                                         monitoringStatus: { OpsMonitoringStatus(configEnabled: true, monitoringEnabled: false, effective: false,
                                                                                 disabledReason: "setting_off") },
                                         snapshot: { _, _ in throw opsDisabledError }, concurrency: { throw opsDisabledError },
                                         logsHealth: { throw opsDisabledError }, ingress: { _, _ in throw opsDisabledError }))
    let harness = LiveOpsHarness(source, site: liveOpsSite(liveOpsCapabilities + [.opsMonitoringStatus]))
    let store = harness.store
    await store.monitorOverviewPolling()
    #expect(store.opsDisabled)
    #expect(await source.count { $0 == .monitoringStatus } == 1)
    #expect(await source.count(isOverviewRange) == 1)
    #expect(await source.count(isSnapshot) <= 1)
    #expect(await harness.sleeper.seconds.isEmpty)
    #expect(store.monitorFiringCount == nil && store.monitorRefreshStatus == nil)
    // While off, the timers do not start again; only a pull asks.
    let before = await source.calls.count
    await store.monitorOverviewPolling()
    await store.refreshMonitorOverview(force: false)
    #expect(await source.calls.count == before)
}

/// A pull still asks while the switch says off; a 200 turns it back on (S1-08's available signal).
@MainActor @Test func successfulReplyRestoresOpsAfterDisabledEvidence() async {
    let source = monitorSource()
    let store = LiveOpsHarness(source).store
    await store.noteOpsDisabled()
    #expect(store.opsDisabled)
    await store.refreshMonitorOverview(force: true)
    #expect(await source.count(isOverviewRange) == 1)
    #expect(!store.opsDisabled)
    #expect(store.monitor.overview.value == overview)
}

/// 00 §4.6: each block backs off on its own failures (60 → 120 → 240), the line keeps its minute.
@MainActor @Test func pollingBacksOffPerBlock() async {
    let source = monitorSource()
    await source.update { $0.overview = { _, _ in throw serverFailure } }
    let harness = LiveOpsHarness(source, sleeper: PollSleeper(parks: true))
    let store = harness.store
    let polling = Task { await store.monitorOverviewPolling() }
    await waitUntil { await harness.sleeper.parkedCount == timerCount }
    #expect(await harness.sleeper.seconds.sorted() == Array(repeating: 60, count: timerCount - 1) + [120])
    await harness.sleeper.releaseAll()
    await waitUntil { await harness.sleeper.parkedCount == timerCount }
    #expect(await harness.sleeper.seconds.sorted() == Array(repeating: 60, count: 2 * (timerCount - 1)) + [120, 240])
    #expect(await source.count(isOverviewRange) == 2)
    #expect(await source.count(isSnapshot) == 2)
    await harness.sleeper.stop()
    await polling.value
    let after = await source.calls.count
    await Task.yield()
    #expect(await source.calls.count == after)
}

/// Coming back to the segment within ten seconds of the last read waits out the rest before reading again.
@MainActor @Test func pollingWaitsOutReentryGap() async {
    let source = monitorSource()
    let harness = LiveOpsHarness(source, sleeper: PollSleeper(parks: true))
    await harness.store.refreshMonitorOverview(force: false)
    harness.advance(by: 4)
    let polling = Task { await harness.store.monitorOverviewPolling() }
    await waitUntil { await harness.sleeper.parkedCount == timerCount }
    #expect(await harness.sleeper.seconds == Array(repeating: 6, count: timerCount))
    #expect(await source.count(isOverviewRange) == 1)
    #expect(await source.count(isSnapshot) == 1)
    await harness.sleeper.stop()
    await polling.value

    let later = monitorSource()
    let other = LiveOpsHarness(later, sleeper: PollSleeper(parks: true))
    await other.store.refreshMonitorOverview(force: false)
    other.advance(by: 11)
    let next = Task { await other.store.monitorOverviewPolling() }
    await waitUntil { await other.sleeper.parkedCount == timerCount }
    #expect(await other.sleeper.seconds == Array(repeating: 60, count: timerCount))
    #expect(await later.count(isOverviewRange) == 2)
    #expect(await later.count(isSnapshot) == 2)
    await other.sleeper.stop()
    await next.value
}

/// The run block reuses a firing list under a minute old; a pull reads it again.
@MainActor @Test func forcedRefreshReloadsFiringWithinMaxAge() async {
    let source = monitorSource()
    let harness = LiveOpsHarness(source)
    let store = harness.store
    await store.refreshFiringAlerts()
    harness.advance(by: 10)
    await store.refreshMonitorBlock(.run, force: false)
    #expect(await source.count(isAlertList) == 1)
    await store.refreshMonitorOverview(force: true)
    #expect(await source.count(isAlertList) == 2)
}

@MainActor @Test func countsAndSubtitlesFollowStore() async {
    let events = [AlertEvent(id: 41, severity: "P1", status: "firing", title: "P1: 标准组错误率"),
                  AlertEvent(id: 40, severity: "P2", status: "firing", title: "P2: Anthropic 上游错误率")]
    let source = monitorSource()
    await source.update {
        $0.alertEvents = { _, _ in events }
        $0.alertCounts = { AlertCounts(firing: 2, bySeverity: ["P1": 1, "P2": 1]) }
    }
    let store = LiveOpsHarness(source).store
    #expect(store.monitorAlertsRow == MonitorAlertsRow(title: "告警中 —", detail: nil, tone: nil))
    await store.refreshFiringAlerts()
    #expect(store.monitorFiringCount == 2)
    #expect(store.monitorAlertsRow == MonitorAlertsRow(title: "告警中 2 条", detail: "标准组错误率、Anthropic 上游错误率", tone: .caution))
    store.markResolved(eventID: 41, at: Date())
    #expect(store.monitorFiringCount == 1)
    #expect(store.monitorSegmentCount(.alerts) == 1 && store.monitorSegmentCount(.overview) == nil)
    #expect(store.monitorSubtitle(for: .alerts, now: Date(), timeZone: shanghai) == "告警 · 1 条进行中")

    #expect(store.monitorSegmentCount(.channels) == nil)
    #expect(store.monitorSubtitle(for: .channels, now: Date(), timeZone: shanghai) == "渠道 · 近 90 分钟")
    let items = ["warning", "critical", "healthy"].enumerated().map {
        ChannelItem(platform: "openai", groupID: $0.offset + 1, currentStatus: ChannelCurrentStatus(state: $0.element))
    }
    await store.channels.load(isCurrent: { true }) { ChannelOverview(items: items) }
    #expect(store.monitorSegmentCount(.channels) == 2)
    #expect(store.monitorSubtitle(for: .channels, now: Date(), timeZone: shanghai) == "渠道 · 近 90 分钟 · 刚刚更新")

    await store.noteOpsDisabled()
    #expect(store.monitorSubtitle(for: .overview, now: Date(), timeZone: shanghai) == "运行与服务器")
    #expect(store.monitorSubtitle(for: .alerts, now: Date(), timeZone: shanghai) == "告警")
    #expect(store.monitorSegmentCount(.alerts) == nil)
}

/// 00 §4.6: an answer that lands after the session ended changes nothing, the switch included.
@MainActor @Test func lateResultsAfterSessionEndAreDropped() async {
    let gate = SessionGate()
    let source = monitorSource()
    await source.update { $0.overview = { _, _ in await gate.wait(); return overview } }
    let harness = LiveOpsHarness(source)
    let store = harness.store
    await store.noteOpsDisabled()
    let pull = Task { await store.refreshMonitorBlock(.run, force: true) }
    await waitUntil { await gate.arrived }
    harness.isCurrent = false
    await gate.open()
    await pull.value
    #expect(store.monitor.overview.value == nil)
    #expect(store.opsDisabled)
}

// MARK: 计时器重启与开启后的读取（审查修正）

private let switchedOn = OpsMonitoringStatus(configEnabled: true, monitoringEnabled: true, effective: true)
private let switchedOff = OpsMonitoringStatus(configEnabled: true, monitoringEnabled: false, effective: false, disabledReason: "setting_off")

/// A read the timers' task stopped half way (leaving 概况, the App going inactive) showed nothing: the next timers read at once.
@MainActor @Test func cancelledReadsDoNotDeferRestartedTimers() async {
    let gate = SessionGate()
    let source = monitorSource()
    await source.update {
        $0.overview = { _, _ in await gate.wait(); return overview }
        $0.snapshot = { start, end in await gate.wait(); return snapshot(start: start, end: end) }
        $0.concurrency = { await gate.wait(); return OpsConcurrency() }
        $0.logsHealth = { await gate.wait(); return SystemLogHealth() }
        $0.ingress = { _, _ in await gate.wait(); return IngressRejectList() }
    }
    let harness = LiveOpsHarness(source, sleeper: PollSleeper(parks: true))
    let store = harness.store
    let first = Task { await store.monitorOverviewPolling() }
    await waitUntil {
        let overviews = await source.count(isOverviewRange), snapshots = await source.count(isSnapshot), server = await source.count(isServerRead)
        return overviews == 1 && snapshots == 1 && server == timerCount - 2
    }
    first.cancel()
    await harness.sleeper.stop()
    await gate.open()
    await first.value
    #expect(store.monitor.overview.value == nil && store.monitor.errorTrend.value == nil)

    let before = await harness.sleeper.seconds.count
    await store.monitorOverviewPolling()
    #expect(await source.count(isOverviewRange) == 2)
    #expect(await source.count(isSnapshot) == 2)
    let waits = await harness.sleeper.seconds
    #expect(Array(waits.dropFirst(before)) == Array(repeating: 60, count: timerCount))
    #expect(store.monitor.overview.value == overview)
}

/// SwiftUI starts the new timers before the stopped ones' reads come back: those reads, the firing list's included, are replaced
/// instead of leaving the block empty for a minute; their late answers change nothing.
@MainActor @Test func restartedTimersReplaceReadsLeftInFlight() async {
    let gate = SessionGate(), overviews = Tally(), lists = Tally()
    let source = monitorSource()
    await source.update {
        $0.overview = { _, _ in if overviews.next() == 1 { await gate.wait() }; return overview }
        $0.alertEvents = { _, _ in if lists.next() == 1 { await gate.wait() }; return [] }
    }
    let harness = LiveOpsHarness(source, sleeper: PollSleeper(parks: true))
    let store = harness.store
    let first = Task { await store.monitorOverviewPolling() }
    // All but the run answer at once and wait; the new timers read the run again and wait out the rest of ten seconds for the others.
    await waitUntil {
        let parked = await harness.sleeper.parkedCount, reads = await source.count(isOverviewRange), listReads = await source.count(isAlertList)
        return parked == timerCount - 1 && reads == 1 && listReads == 1
    }
    first.cancel()
    let second = Task { await store.monitorOverviewPolling() }
    await waitUntil { await harness.sleeper.parkedCount == 2 * timerCount - 1 }
    #expect(await source.count(isOverviewRange) == 2)
    #expect(await source.count(isAlertList) == 2)
    #expect(store.monitor.overview.value == overview)
    #expect(store.firing.value == [])

    await gate.open()
    await harness.sleeper.stop()
    await first.value
    await second.value
    #expect(store.monitor.overview.value == overview && store.firing.value == [])
}

/// 10 §7.2 step 3: off answers just before 开启运维监控 do not hold the blocks back once it is on; they are read at once.
@MainActor @Test func enablingReadsBlocksAtOnceAfterOffAnswers() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }, overview: { _, _ in throw opsDisabledError },
                                         alertEvents: { _, _ in throw opsDisabledError }, alertCounts: { throw opsDisabledError },
                                         monitoringStatus: { switchedOff }, setOpsMonitoring: { _ in switchedOn },
                                         snapshot: { _, _ in throw opsDisabledError }, concurrency: { throw opsDisabledError },
                                         logsHealth: { throw opsDisabledError }, ingress: { _, _ in throw opsDisabledError }))
    let harness = LiveOpsHarness(source, site: liveOpsSite(liveOpsCapabilities + [.opsMonitoringStatus]), sleeper: PollSleeper(parks: true))
    let store = harness.store
    await store.refreshMonitorOverview(force: true)
    #expect(store.opsDisabled)
    await source.update {
        $0.overview = { _, _ in overview }
        $0.alertEvents = { _, _ in [] }
        $0.alertCounts = { AlertCounts(firing: 0) }
        $0.snapshot = { snapshot(start: $0, end: $1) }
        $0.concurrency = { OpsConcurrency() }
        $0.logsHealth = { SystemLogHealth() }
        $0.ingress = { _, _ in IngressRejectList() }
    }
    #expect(await store.enableOpsMonitoring() == .enabled)
    #expect(!store.opsDisabled)

    let polling = Task { await store.monitorOverviewPolling() }
    await waitUntil { await harness.sleeper.parkedCount == timerCount }
    #expect(await harness.sleeper.seconds == Array(repeating: 60, count: timerCount))
    #expect(await source.count(isOverviewRange) == 2)
    #expect(await source.count(isSnapshot) == 2)
    #expect(store.monitor.overview.value == overview && store.monitor.errorTrend.value?.count == 9)
    await harness.sleeper.stop()
    await polling.value
}

/// 10 §7.2 step 3: for 30 seconds after the App turned it on, an instance that has not switched yet may still answer 404
/// OPS_DISABLED; the switch stays on and the block asks again after 30 seconds instead of backing off.
@MainActor @Test func offAnswerRightAfterEnablingIsAskedAgainWithinThirtySeconds() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }, overview: { _, _ in overview }, alertEvents: { _, _ in [] },
                                         alertCounts: { AlertCounts(firing: 0) }, setOpsMonitoring: { _ in switchedOn },
                                         snapshot: { snapshot(start: $0, end: $1) }, concurrency: { OpsConcurrency() },
                                         logsHealth: { SystemLogHealth() }, ingress: { _, _ in IngressRejectList() }))
    let harness = LiveOpsHarness(source, site: liveOpsSite(liveOpsCapabilities + [.opsMonitoringStatus], opsEnabled: false),
                                 sleeper: PollSleeper(parks: true))
    let store = harness.store
    #expect(await store.enableOpsMonitoring() == .enabled)
    await source.update { $0.overview = { _, _ in throw opsDisabledError } }

    let polling = Task { await store.monitorOverviewPolling() }
    await waitUntil { await harness.sleeper.parkedCount == timerCount }
    #expect(!store.opsDisabled)
    #expect(store.monitor.overview.error != nil)
    #expect(await harness.sleeper.seconds.sorted() == [30] + Array(repeating: 60, count: timerCount - 1))
    await harness.sleeper.stop()
    await polling.value
}
