import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Records every count and answers through closures; `call` counts the asks of that endpoint from 1 (usage, or both error
/// lists together). LogsStoreStateTests uses it too.
actor LogCountStub {
    typealias UsageHandler = @Sendable (_ call: Int, _ query: AnalyticsQuery) async throws -> Int
    typealias ErrorHandler = @Sendable (_ call: Int, _ filter: RequestLogFilter, _ kind: ErrorLogKind) async throws -> Int
    private let onUsage: UsageHandler
    private let onErrors: ErrorHandler
    private(set) var calls: [LogCountRequest] = []
    /// Asks that have come back, thrown or not.
    private(set) var answered = 0
    private var usageCalls = 0
    private var errorCalls = 0

    init(usage: @escaping UsageHandler = { _, _ in 0 }, errors: @escaping ErrorHandler = { _, _, _ in 0 }) {
        onUsage = usage; onErrors = errors
    }
    func usage(_ query: AnalyticsQuery) async throws -> Int {
        calls.append(.usage(query))
        usageCalls += 1
        defer { answered += 1 }
        return try await onUsage(usageCalls, query)
    }
    func errors(_ filter: RequestLogFilter, _ kind: ErrorLogKind) async throws -> Int {
        calls.append(.errors(filter, kind))
        errorCalls += 1
        defer { answered += 1 }
        return try await onErrors(errorCalls, filter, kind)
    }
    nonisolated var source: LogCountSource {
        LogCountSource(usage: { try await self.usage($0) }, errors: { try await self.errors($0, $1) })
    }
}

private let countEnd = Date(timeIntervalSince1970: 1_800_000_000)
private let countWindow = LogTimeWindow.range(countEnd.addingTimeInterval(-86_400), countEnd)
private let usageQuery = AnalyticsQuery(start: countEnd.addingTimeInterval(-86_400), end: countEnd, granularity: .day, timeZone: liveOpsZone,
                                        userID: 1)
private let errorsFilter = RequestLogFilter(time: countWindow, userID: 1)
private let upstreamFilter = RequestLogFilter(time: countWindow, accountID: 7, userID: 1)

private func countPlan(current: LogScope, opsAvailable: Bool = true, usage: AnalyticsQuery? = usageQuery) -> LogCountPlan {
    LogCountPlan(usage: usage, errors: errorsFilter, upstream: upstreamFilter, current: current, opsAvailable: opsAvailable)
}
@MainActor private func counts(_ counter: LogSegmentCounter) -> [LogCount] { LogScope.allCases.map { counter.count(for: $0) } }

/// What the counter handed to LiveOpsStore.
@MainActor private final class Reports {
    private(set) var reasons: [String] = []
    func record(_ error: any Error) { reasons.append((error as? APIError)?.reason ?? "other") }
}

/// Up to five seconds: under `swift test --parallel` a child task can take a while to be scheduled.
private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}

// MARK: - 分段文字与计划

@Test func segmentTitleFormatsPendingValueAndDash() {
    #expect(LogCount.pending.segmentTitle("用量明细") == "用量明细")
    #expect(LogCount.value(0).segmentTitle("用量明细") == "用量明细 0")
    #expect(LogCount.value(1_284).segmentTitle("用量明细") == "用量明细 1,284")
    #expect(LogCount.value(9_999).segmentTitle("错误请求") == "错误请求 9,999")
    #expect(LogCount.value(12_345).segmentTitle("上游错误") == "上游错误 12.3K")
    #expect(LogCount.unavailable.segmentTitle("用量明细") == "用量明细 —")
}

@Test func planOnUsageAsksAllThreeSegments() {
    let plan = countPlan(current: .usage)
    #expect(plan.requests == [.usage: .usage(usageQuery), .errors: .errors(errorsFilter, .request),
                              .upstream: .errors(upstreamFilter, .upstream)])
    #expect(plan.listScope == nil && plan.listFallback == nil && plan.unavailable.isEmpty)
}

@Test func planOnErrorSegmentTakesItsCountFromTheList() {
    let errors = countPlan(current: .errors)
    #expect(errors.requests == [.usage: .usage(usageQuery), .upstream: .errors(upstreamFilter, .upstream)])
    #expect(errors.listScope == .errors && errors.listFallback == .errors(errorsFilter, .request))
    let upstream = countPlan(current: .upstream)
    #expect(upstream.requests == [.usage: .usage(usageQuery), .errors: .errors(errorsFilter, .request)])
    #expect(upstream.listScope == .upstream && upstream.listFallback == .errors(upstreamFilter, .upstream))
    #expect(errors.unavailable.isEmpty && upstream.unavailable.isEmpty)
}

@MainActor @Test func planWithOpsOffAsksOnlyUsage() async {
    let plan = countPlan(current: .errors, opsAvailable: false)
    #expect(plan.requests == [.usage: .usage(usageQuery)])
    #expect(plan.unavailable == [.errors, .upstream] && plan.listScope == nil && plan.listFallback == nil)
    let counter = LogSegmentCounter(source: LogCountStub().source)
    counter.begin(plan)
    #expect(counter.count(for: .errors) == .unavailable && counter.count(for: .upstream) == .unavailable)
    // Without a fixed range there is no usage query: “—”.
    let unranged = countPlan(current: .usage, usage: nil)
    #expect(unranged.unavailable == [.usage] && unranged.requests[.usage] == nil)
}

// MARK: - 一轮计数

@MainActor @Test func beginSendsPlannedRequestsAndSettlesValues() async {
    let stub = LogCountStub(usage: { _, _ in 40 }, errors: { _, _, kind in kind == .upstream ? 6 : 99 })
    let counter = LogSegmentCounter(source: stub.source)
    counter.begin(countPlan(current: .errors))
    #expect(counts(counter) == [.pending, .pending, .pending])
    await counter.settled()
    let calls = await stub.calls
    #expect(calls.count == 2 && Set(calls) == [.usage(usageQuery), .errors(upstreamFilter, .upstream)])
    #expect(counts(counter) == [.value(40), .pending, .value(6)])
    counter.firstPageLoaded(.errors, total: 7)
    #expect(counter.count(for: .errors) == .value(7))
}

@MainActor @Test func listTotalCountsOnlyOncePerPass() async {
    let counter = LogSegmentCounter(source: LogCountStub().source)
    counter.begin(countPlan(current: .errors))
    counter.firstPageLoaded(.errors, total: 7)
    counter.firstPageLoaded(.errors, total: 9)
    #expect(counter.count(for: .errors) == .value(7))
    counter.begin(countPlan(current: .errors))
    counter.firstPageLoaded(.errors, total: 9)
    #expect(counter.count(for: .errors) == .value(9))
    await counter.settled()
    counter.firstPageLoaded(.upstream, total: 99)
    #expect(counter.count(for: .upstream) == .value(0))
}

@MainActor @Test func failedFirstPageReadsDashThenRetryFillsIt() async {
    let counter = LogSegmentCounter(source: LogCountStub().source)
    counter.begin(countPlan(current: .errors))
    counter.firstPageFailed(.errors, error: APIError.server(status: 500, reason: nil))
    #expect(counter.count(for: .errors) == .unavailable)
    counter.firstPageLoaded(.errors, total: 3)
    #expect(counter.count(for: .errors) == .value(3))
    counter.begin(countPlan(current: .upstream))
    counter.firstPageFailed(.upstream, error: CancellationError())
    #expect(counter.count(for: .upstream) == .pending)
    counter.firstPageFailed(.upstream, error: nil)
    #expect(counter.count(for: .upstream) == .unavailable)
    counter.begin(countPlan(current: .upstream))
    counter.firstPageLoaded(.upstream, total: nil)
    #expect(counter.count(for: .upstream) == .unavailable)
    await counter.settled()
}

@MainActor @Test func leavingBeforeListTotalAsksErrorCountOnce() async {
    let stub = LogCountStub(errors: { _, _, kind in kind == .request ? 4 : 6 })
    let counter = LogSegmentCounter(source: stub.source)
    counter.begin(countPlan(current: .errors))
    await counter.settled()
    #expect(await stub.calls.count == 2)
    counter.leaving(.errors)
    await counter.settled()
    #expect(await stub.calls.count == 3)
    #expect(await stub.calls.last == .errors(errorsFilter, .request))
    #expect(counter.count(for: .errors) == .value(4))
    counter.leaving(.errors)
    counter.firstPageLoaded(.errors, total: 9)
    await counter.settled()
    #expect(await stub.calls.count == 3)
    #expect(counter.count(for: .errors) == .value(4))
}

@MainActor @Test func switchingSegmentsNeverRecounts() async {
    let stub = LogCountStub(usage: { _, _ in 40 }, errors: { _, _, _ in 6 })
    let counter = LogSegmentCounter(source: stub.source)
    counter.begin(countPlan(current: .usage))
    await counter.settled()
    let settled = counts(counter)
    counter.leaving(.usage)
    counter.leaving(.upstream)
    counter.firstPageLoaded(.upstream, total: 99)
    await counter.settled()
    #expect(await stub.calls.count == 3)
    #expect(counts(counter) == settled && settled == [.value(40), .value(6), .value(6)])
    // A listed segment already counted by its page 1 is not asked again on leaving.
    counter.begin(countPlan(current: .upstream))
    counter.firstPageLoaded(.upstream, total: 5)
    counter.leaving(.upstream)
    await counter.settled()
    #expect(await stub.calls.count == 5)
    #expect(counter.count(for: .upstream) == .value(5))
}

// MARK: - 失败、运维关闭与迟到

@MainActor @Test func opsDisabledCountReadsDashAndReportsOnce() async {
    let reports = Reports()
    let stub = LogCountStub(usage: { _, _ in 40 }, errors: { _, _, _ in throw APIError.server(status: 404, reason: "OPS_DISABLED") })
    let counter = LogSegmentCounter(source: stub.source) { reports.record($0) }
    counter.begin(countPlan(current: .errors))
    await counter.settled()
    #expect(counter.count(for: .upstream) == .unavailable)
    #expect(counter.count(for: .usage) == .value(40))
    #expect(reports.reasons == ["OPS_DISABLED"])
}

@MainActor @Test func failuresReadDashWithoutRetry() async {
    let failures: [any Error] = [
        APIError.server(status: 500, reason: nil),
        APIError(kind: .rateLimited, statusCode: 429, message: "请求过于频繁", retryAfter: 30),
        URLError(.timedOut),
        APIError(kind: .validation, message: "请选择一年以内的有效时间范围。"),
    ]
    for failure in failures {
        let stub = LogCountStub(usage: { _, _ in throw failure }, errors: { _, _, _ in throw failure })
        let counter = LogSegmentCounter(source: stub.source)
        counter.begin(countPlan(current: .usage))
        await counter.settled()
        #expect(counts(counter) == [.unavailable, .unavailable, .unavailable], "\(failure)")
        #expect(await stub.calls.count == 3)
    }
}

@MainActor @Test func unavailableSourceReadsDash() async {
    let counter = LogSegmentCounter(source: .unavailable)
    counter.begin(countPlan(current: .usage))
    await counter.settled()
    #expect(counts(counter) == [.unavailable, .unavailable, .unavailable])
}

@MainActor @Test func lateResultsOfAnOlderPassAreDropped() async {
    let gate = SessionGate()
    let stub = LogCountStub(usage: { call, _ in
        if call == 1 { await gate.wait() }
        return call
    })
    let counter = LogSegmentCounter(source: stub.source)
    counter.begin(countPlan(current: .errors, opsAvailable: false))
    #expect(await eventually { await gate.arrived })
    counter.begin(countPlan(current: .errors, opsAvailable: false))
    await counter.settled()
    #expect(counter.count(for: .usage) == .value(2))
    await gate.open()
    #expect(await eventually { await stub.answered == 2 })
    try? await Task.sleep(for: .milliseconds(20))
    #expect(counter.count(for: .usage) == .value(2))
}

@MainActor @Test func cancelledCountsResumeOnForeground() async {
    let stub = LogCountStub(usage: { call, _ in
        if call == 1 { throw CancellationError() }
        return 40
    }, errors: { _, _, _ in 6 })
    let counter = LogSegmentCounter(source: stub.source)
    counter.begin(countPlan(current: .usage))
    await counter.settled()
    #expect(counts(counter) == [.pending, .value(6), .value(6)])
    counter.resumeInterrupted()
    await counter.settled()
    #expect(counts(counter) == [.value(40), .value(6), .value(6)])
    #expect(await stub.calls.count == 4)
    counter.resumeInterrupted()
    await counter.settled()
    #expect(await stub.calls.count == 4)
}

@MainActor @Test func stoppedListPageIsAskedOnlyWhenNotReadAgain() async {
    let stub = LogCountStub(errors: { _, _, kind in kind == .request ? 4 : 6 })
    let counter = LogSegmentCounter(source: stub.source)
    counter.begin(countPlan(current: .errors))
    await counter.settled()
    counter.firstPageFailed(.errors, error: CancellationError())
    counter.resumeInterrupted()
    counter.firstPageLoaded(.errors, total: 7)
    await counter.settled()
    #expect(await stub.calls.count == 2)
    #expect(counter.count(for: .errors) == .value(7))
    counter.begin(countPlan(current: .errors))
    await counter.settled()
    counter.firstPageFailed(.errors, error: CancellationError())
    counter.resumeInterrupted(listReadsAgain: false)
    await counter.settled()
    #expect(await stub.calls.count == 5)
    #expect(await stub.calls.last == .errors(errorsFilter, .request))
    counter.firstPageLoaded(.errors, total: 99)
    #expect(counter.count(for: .errors) == .value(4))
    counter.resumeInterrupted(listReadsAgain: false)
    await counter.settled()
    #expect(await stub.calls.count == 5)
}

@MainActor @Test func heldBackAsksReadDashWithoutGoingOut() async {
    let stub = LogCountStub(usage: { call, _ in
        if call == 1 { throw CancellationError() }
        return 40
    })
    let counter = LogSegmentCounter(source: stub.source)
    counter.begin(countPlan(current: .errors), holdingBack: true)
    #expect(counts(counter) == [.unavailable, .pending, .unavailable])
    counter.firstPageFailed(.errors, error: nil)
    #expect(counter.count(for: .errors) == .unavailable)
    counter.firstPageLoaded(.errors, total: 3)
    #expect(counter.count(for: .errors) == .value(3))
    #expect(await stub.calls.isEmpty)
    counter.begin(countPlan(current: .upstream))
    await counter.settled()
    counter.firstPageFailed(.upstream, error: CancellationError())
    #expect(await stub.calls.count == 2)
    counter.resumeInterrupted(listReadsAgain: false, holdingBack: true)
    await counter.settled()
    #expect(await stub.calls.count == 2)
    #expect(counts(counter) == [.unavailable, .value(0), .unavailable])
}

@MainActor @Test func resultsAfterCancelAreDropped() async {
    let gate = SessionGate()
    let stub = LogCountStub(usage: { _, _ in await gate.wait(); return 40 })
    let counter = LogSegmentCounter(source: stub.source)
    counter.begin(countPlan(current: .errors))
    #expect(await eventually { await gate.arrived })
    counter.cancel()
    counter.firstPageLoaded(.errors, total: 3)
    await gate.open()
    #expect(await eventually { await stub.answered == 2 })
    try? await Task.sleep(for: .milliseconds(20))
    #expect(counter.count(for: .usage) == .pending && counter.count(for: .errors) == .pending)
    counter.resumeInterrupted()
    #expect(await stub.calls.count == 2)
}

// MARK: - 接口与置灰

@Test func clientSourceReadsTotalRequestsAndErrorTotal() async throws {
    let transport = SessionTransport { request in
        request.url?.path == "/api/v1/admin/usage/stats"
            ? sessionOK(#"{"total_requests":1284,"total_tokens":0}"#)
            : sessionOK(#"{"items":[],"total":6,"page":1,"page_size":1,"pages":6}"#)
    }
    let source = LogCountSource.client(sessionClient(transport))
    let query = AnalyticsQuery(start: countEnd.addingTimeInterval(-86_400), end: countEnd, granularity: .day, timeZone: liveOpsZone,
                               userID: 1, model: "claude-opus-4", modelSource: .upstream)
    #expect(try await source.usage(query) == 1_284)
    #expect(try await source.errors(RequestLogFilter(time: countWindow, userID: 1), .upstream) == 6)
    let requests = await transport.requests
    #expect(requests.map { $0.url?.path } == ["/api/v1/admin/usage/stats", "/api/v1/admin/ops/upstream-errors"])
    let queries = requests.map { request in
        Dictionary((URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                   uniquingKeysWith: { first, _ in first })
    }
    #expect(queries[0]["start_time"] == ServerTime.utcTimestamp(countEnd.addingTimeInterval(-86_400)))
    #expect(queries[0]["end_time"] == ServerTime.utcTimestamp(countEnd) && queries[0]["end_time"]?.hasSuffix("Z") == true)
    #expect(queries[0]["timezone"] == "Asia/Shanghai" && queries[0]["user_id"] == "1")
    #expect(queries[0]["model"] == "claude-opus-4" && queries[0]["model_source"] == "upstream")
    #expect(queries[0]["page"] == nil && queries[0]["count_mode"] == nil && queries[0]["key_view"] == nil)
    #expect(queries[1]["page"] == "1" && queries[1]["page_size"] == "1" && queries[1]["view"] == "all" && queries[1]["user_id"] == "1")
}

@Test func greyedConditionsStayOutOfCountRequests() throws {
    let conditions = LogConditions(user: LogFilterObject(id: 1, name: "Alice"), model: "claude-opus-4")
    func plan(_ conditions: LogConditions, legacy: Bool) -> LogCountPlan {
        func chips(_ kind: ErrorLogKind?) -> LogFilterChips {
            LogFilterChips(conditions, kind: kind, legacyServer: legacy, supportsModelSource: true)
        }
        return LogCountPlan(usage: LogListPolicy.usageCountQuery(chips(nil).filter(time: countWindow), timeZone: liveOpsZone),
                            errors: chips(.request).filter(time: countWindow), upstream: chips(.upstream).filter(time: countWindow),
                            current: .usage, opsAvailable: true)
    }
    let legacy = plan(conditions, legacy: true)
    guard case .errors(let upstream, .upstream)? = legacy.requests[.upstream],
          case .errors(let errors, .request)? = legacy.requests[.errors],
          case .usage(let usage)? = legacy.requests[.usage] else { Issue.record("missing requests"); return }
    #expect(upstream.userID == nil && upstream.model == nil)
    #expect(errors.userID == 1 && errors.model == "claude-opus-4")
    #expect(usage.userID == 1 && usage.model == "claude-opus-4" && usage.modelSource == .requested)

    var bySource = conditions
    bySource.modelSource = .upstream
    let current = plan(bySource, legacy: false)
    guard case .errors(let sourced, .request)? = current.requests[.errors],
          case .usage(let sourcedUsage)? = current.requests[.usage] else { Issue.record("missing requests"); return }
    #expect(sourced.model == nil && sourced.userID == 1)
    #expect(sourcedUsage.model == "claude-opus-4" && sourcedUsage.modelSource == .upstream)
}
