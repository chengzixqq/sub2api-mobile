import Foundation
import Synchronization
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 40 §0.1 / §1.4 / §1.5 / §1.7 RPM / TPM 趋势卡's state (S4-16): the window and metric memory, the reads, ops off and the polling.

private let site = UUID(uuidString: "0B1C2D3E-4F50-4617-8293-A4B5C6D7E8F9")!
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
/// 2026-10-15 09:01:00 in Shanghai.
private let nineOhOne = Date(timeIntervalSince1970: 1_792_026_060)
private let throughputPath = "/api/v1/admin/ops/dashboard/throughput-trend"

/// `hours` ending at `end`, every bucket filled with `requests` (the newest with `newest`).
private func trend(hours: Int, end: Date = nineOhOne, requests: Int = 44, newest: Int = 46) -> PerformanceTrend {
    let start = end.addingTimeInterval(-Double(hours) * 3_600)
    let bucket = OpsBucket.forWindow(end.timeIntervalSince(start))
    let starts = bucket.starts(from: start, to: end)
    let points = starts.map { PerformanceTrend.Point(date: $0, requestCount: $0 == starts.last ? newest : requests, tokenConsumed: 1_000) }
    return PerformanceTrend(bucket: bucket, windowStart: start, windowEnd: end, points: points)
}
private func time(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    nineOhOne.addingTimeInterval(Double((hour * 60 + minute - 541) * 60 + second))
}

/// The ops hooks of AppModel, recorded; the hooks keep the probe alive.
@MainActor private final class OpsProbe {
    var isDisabled = false
    var records: [APIError?] = []
    var hooks: PerfOpsHooks {
        PerfOpsHooks(isDisabled: { self.isDisabled }, record: { error in self.records.append(error as? APIError) })
    }
}

/// The UI fixture's answers: the hours each read asked for, the window ending at `end`.
@MainActor private final class FixtureScript {
    var hours: [Int] = []
    var end = nineOhOne
    var fixture: PerfTrendState.Fixture {
        { hours in
            self.hours.append(hours)
            return trend(hours: hours, end: self.end)
        }
    }
}

/// The server's answer, switchable between reads.
private final class Reply: Sendable {
    private let response: Mutex<HTTPResponse>
    init(_ response: HTTPResponse) { self.response = Mutex(response) }
    func set(_ response: HTTPResponse) { self.response.withLock { $0 = response } }
    var current: HTTPResponse { response.withLock { $0 } }
}
private let emptyThroughput = sessionOK("{\"bucket\":\"5m\",\"points\":[]}")

@MainActor private func makeSession(_ scratch: ScratchDefaults, transport: SessionTransport = SessionTransport { _ in emptyThroughput },
                                    opsModelFilter: Bool = true, isUITesting: Bool = true) -> AnalyticsSessionState {
    AnalyticsSessionState(serverID: site, generation: UUID(), client: sessionClient(transport), timeZone: shanghai, supportsModelSource: true,
                          supportsOpsModelFilter: opsModelFilter, memory: AnalyticsMemory(defaults: scratch.defaults), entry: .today,
                          groups: nil, isUITesting: isUITesting, clock: { Date() }, isSessionCurrent: { true })
}
@MainActor private func makeState(_ scratch: ScratchDefaults, session: AnalyticsSessionState, startMetric: PerfMetric? = nil,
                                  ops: OpsProbe = OpsProbe(), script: FixtureScript = FixtureScript()) -> PerfTrendState {
    PerfTrendState(session: session, memory: AnalyticsMemory(defaults: scratch.defaults), startMetric: startMetric, hooks: ops.hooks,
                   fixture: script.fixture)
}
@MainActor private func remembered(_ scratch: ScratchDefaults, _ item: String) -> Any? {
    scratch.defaults.object(forKey: AnalyticsMemory.key(item, serverID: site))
}
private func query(_ request: URLRequest?) -> [String: String] {
    guard let url = request?.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

@MainActor @Test func perfStateRouteMetricWinsOnceAndIsRemembered() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    let state = makeState(scratch, session: session, startMetric: .tpm)
    #expect(state.metric == .tpm)
    #expect(state.performanceMetric == .tpm)
    state.appear()
    #expect(remembered(scratch, "perfMetric") as? String == "tpm")
    state.selectMetric(.rpm)
    #expect(remembered(scratch, "perfMetric") as? String == "rpm")
    // Back from a pushed page: the route does not win again.
    state.appear()
    #expect(state.metric == .rpm)
}

@MainActor @Test func perfStateWithoutRouteReadsMemoryWithoutWriting() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    let fresh = makeState(scratch, session: makeSession(scratch))
    fresh.appear()
    #expect(fresh.window == .h1 && fresh.metric == .rpm)
    #expect(remembered(scratch, "perfMetric") == nil && remembered(scratch, "perfWindow") == nil)
    memory.setPerfWindow(.h6, serverID: site)
    memory.setPerfMetric(.tpm, serverID: site)
    let state = makeState(scratch, session: makeSession(scratch))
    #expect(state.window == .h6 && state.metric == .tpm)
}

@MainActor @Test func perfWindowChangeResetsCardClearsSelectionAndRemembers() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    let state = makeState(scratch, session: session)
    await state.load(refresh: false)
    #expect(state.trend?.points.count == 60)
    state.receive(29)
    state.receive(nil)
    #expect(state.selectedDate == time(8, 30))
    state.selectWindow(.h1)
    #expect(state.trend != nil && state.selectedDate != nil)
    state.selectWindow(.h6)
    #expect(state.loadState?.value == nil)
    #expect(state.trend == nil && state.selectedDate == nil)
    #expect(remembered(scratch, "perfWindow") as? Int == 6)
    #expect(state.pollDelay(now: Date()) == 0)
    await state.load(refresh: false)
    #expect(state.trend?.points.count == 73)
}

@MainActor @Test func perfStateFollowsChangesMadeOnAnotherPage() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    let card = makeState(scratch, session: session), more = makeState(scratch, session: session)
    await card.load(refresh: false)
    more.appear()
    more.selectWindow(.h24)
    more.selectMetric(.tpm)
    await more.load(refresh: false)
    #expect(card.trend == nil)
    card.appear()
    #expect(card.window == .h24 && card.metric == .tpm)
    #expect(card.trend?.points.count == 289)
}

@MainActor @Test func perfTrendIgnoresAnotherWindowsValue() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    let script = FixtureScript()
    let hourly = makeState(scratch, session: session, script: script)
    await hourly.load(refresh: false)
    AnalyticsMemory(defaults: scratch.defaults).setPerfWindow(.h6, serverID: site)
    let six = makeState(scratch, session: session, script: script)
    #expect(six.loadState?.value != nil)
    #expect(six.trend == nil)
    #expect(six.pollDelay(now: Date()) == 0)
    // Not refreshing still reads: the hour's value is dropped first.
    await six.load(refresh: false)
    #expect(script.hours == [1, 6])
    #expect(six.trend?.points.count == 73)
}

@MainActor @Test func perfLoadSendsTrailingWindowAndFilter() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    AnalyticsMemory(defaults: scratch.defaults).setPerfWindow(.h6, serverID: site)
    let transport = SessionTransport { _ in emptyThroughput }
    let session = makeSession(scratch, transport: transport, opsModelFilter: false, isUITesting: false)
    let state = makeState(scratch, session: session)
    session.setFilter(.group(id: 3))
    await state.load(refresh: false)
    var requests = await transport.requests
    #expect(requests.map { $0.url?.path } == [throughputPath])
    let grouped = query(requests.last)
    #expect(grouped["mode"] == nil && grouped["timezone"] == nil && grouped["group_id"] == "3")
    let end = try #require(ServerTime.parseTimestamp(grouped["end_time"]))
    let start = try #require(ServerTime.parseTimestamp(grouped["start_time"]))
    #expect(grouped["end_time"]?.hasSuffix(":00Z") == true)
    #expect(end.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0)
    #expect(end.timeIntervalSince(start) == 6 * 3_600)
    #expect(state.trend != nil)
    // Without ops.dashboard_model_filter the model stays out; the card says it shows the whole site.
    session.setFilter(.model(name: "gpt-5"))
    #expect(session.opsIsSiteWide)
    await state.load(refresh: false)
    requests = await transport.requests
    let siteWide = query(requests.last)
    #expect(siteWide["model"] == nil && siteWide["model_source"] == nil && siteWide["group_id"] == nil)

    let filtering = SessionTransport { _ in emptyThroughput }
    let modelSession = makeSession(scratch, transport: filtering, opsModelFilter: true, isUITesting: false)
    modelSession.setFilter(.model(name: "gpt-5"))
    await makeState(scratch, session: modelSession).load(refresh: false)
    let filtered = query(await filtering.requests.last)
    #expect(filtered["model"] == "gpt-5" && filtered["model_source"] == "requested")
}

@MainActor @Test func perfFixturePathReceivesWindowHours() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let transport = SessionTransport { _ in emptyThroughput }
    let script = FixtureScript()
    let state = makeState(scratch, session: makeSession(scratch, transport: transport), script: script)
    await state.load(refresh: false)
    state.selectWindow(.h24)
    await state.load(refresh: false)
    #expect(script.hours == [1, 24])
    #expect(await transport.requests.isEmpty)
}

@MainActor @Test func perfOps404AndFreshSuccessAreReported() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let reply = Reply(sessionFailure(404, reason: "OPS_DISABLED"))
    let transport = SessionTransport { _ in reply.current }
    let ops = OpsProbe()
    let state = makeState(scratch, session: makeSession(scratch, transport: transport, isUITesting: false), ops: ops)
    await state.load(refresh: false)
    #expect(ops.records.count == 1)
    #expect(ops.records.first??.statusCode == 404 && ops.records.first??.reason == "OPS_DISABLED")
    #expect(state.showsOpsNotice)
    reply.set(emptyThroughput)
    await state.load(refresh: true)
    #expect(ops.records.count == 2 && ops.records.last! == nil)
    #expect(!state.showsOpsNotice)
    // A value still fresh is not read again, so nothing is reported.
    await state.load(refresh: false)
    #expect(ops.records.count == 2)
    // Other failures are not ops signals.
    for status in [500, 429] {
        reply.set(sessionFailure(status))
        await state.load(refresh: true)
    }
    #expect(ops.records.count == 2)
}

@MainActor @Test func perfNoticeAndPollingFollowTheOpsSwitch() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let reply = Reply(emptyThroughput)
    let transport = SessionTransport { _ in reply.current }
    let ops = OpsProbe()
    let state = makeState(scratch, session: makeSession(scratch, transport: transport, isUITesting: false), ops: ops)
    ops.isDisabled = true
    #expect(state.isOpsDisabled && state.showsOpsNotice)
    #expect(state.pollDelay(now: Date()) == nil)
    // Ops off sends nothing.
    await state.load(refresh: true)
    #expect(await transport.requests.isEmpty)
    // Just turned on, another instance may still answer 404: the notice stays and the card keeps reading.
    ops.isDisabled = false
    reply.set(sessionFailure(404, reason: "OPS_DISABLED"))
    await state.load(refresh: true)
    #expect(!state.isOpsDisabled && state.showsOpsNotice)
    let delay = state.pollDelay(now: Date())
    #expect(delay != nil && delay! >= 30)
}

@MainActor @Test func perfPollDelayStopsFor400And403AndWaitsFromTheLastRead() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let reply = Reply(emptyThroughput)
    let transport = SessionTransport { _ in reply.current }
    let session = makeSession(scratch, transport: transport, isUITesting: false)
    let state = makeState(scratch, session: session)
    #expect(state.pollDelay(now: Date()) == 0)
    await state.load(refresh: false)
    let updatedAt = try #require(state.loadState?.updatedAt)
    #expect(state.pollDelay(now: updatedAt.addingTimeInterval(10)) == 20)
    #expect(state.pollDelay(now: updatedAt.addingTimeInterval(45)) == 0)
    reply.set(sessionFailure(500))
    await state.load(refresh: true)
    let failedAt = try #require(state.loadState?.lastErrorAt)
    // A failure backs off from 30 seconds; the value stays.
    #expect(state.pollDelay(now: failedAt) == 60)
    #expect(state.trend != nil)
    for status in [400, 403] {
        reply.set(sessionFailure(status))
        await state.load(refresh: true)
        #expect(state.pollDelay(now: Date()) == nil)
    }
    // A read that ended without an answer (cancelled) tries again at once.
    session.reset(.perf)
    #expect(state.pollDelay(now: Date()) == 0)
}

@MainActor @Test func perfGestureUsesTheSharedReducerAndKeepsTheBucketDate() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let script = FixtureScript()
    let state = makeState(scratch, session: makeSession(scratch), script: script)
    await state.load(refresh: false)
    // Pressed and let go: selected; the same bucket again clears.
    state.receive(29); state.receive(nil)
    #expect(state.selectedPoint?.date == time(8, 30))
    #expect(state.chartSelection.selected == 29)
    state.receive(29); state.receive(nil)
    #expect(state.selectedPoint == nil)
    // Dragged on to another bucket: it moves there and stays.
    state.receive(29); state.receive(30); state.receive(nil)
    #expect(state.selectedDate == time(8, 31))
    // The metric keeps it; after the 30-second refresh the window has moved one minute and the bucket is found by its date.
    state.selectMetric(.tpm)
    script.end = time(9, 2)
    await state.load(refresh: true)
    #expect(state.selectedPoint?.date == time(8, 31))
    #expect(state.chartSelection.selected == 29)
    // A row of 性能明细 selects its point.
    let row = try #require(state.trend?.points.last)
    state.select(row)
    #expect(state.selectedPoint == row)
    state.clearSelection()
    #expect(state.selectedPoint == nil && state.chartSelection.selected == nil)
}

@MainActor @Test func perfSelectionDropsWhenPointLeavesWindowAndFilterChangeClearsCard() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let script = FixtureScript()
    let session = makeSession(scratch)
    let state = makeState(scratch, session: session, script: script)
    await state.load(refresh: false)
    state.receive(0); state.receive(nil)
    #expect(state.selectedDate == time(8, 1))
    script.end = time(9, 2)
    await state.load(refresh: true)
    #expect(state.selectedPoint == nil && state.chartSelection.selected == nil)
    // The card keeps its rolling window across ranges; a filter clears it.
    session.select(.preset(.last30))
    #expect(state.trend != nil)
    session.setFilter(.group(id: 1))
    #expect(state.loadState?.value == nil)
}
