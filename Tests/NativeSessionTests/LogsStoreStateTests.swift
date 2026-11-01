import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Records every read and answers through closures; `call` counts every read from 1, whatever the segment.
private actor LogsStub {
    struct Read: Sendable {
        let page: Int
        let filter: RequestLogFilter
        let kind: ErrorLogKind?
    }
    typealias UsageHandler = @Sendable (_ call: Int, _ read: Read) async throws -> Page<UsageRequestRecord>
    typealias ErrorHandler = @Sendable (_ call: Int, _ read: Read) async throws -> Page<RequestErrorRecord>
    private let onUsage: UsageHandler
    private let onErrors: ErrorHandler
    private(set) var reads: [Read] = []

    init(usage: @escaping UsageHandler = { _, read in usagePage([], page: read.page) },
         errors: @escaping ErrorHandler = { _, read in errorPage([], page: read.page) }) {
        onUsage = usage; onErrors = errors
    }
    func usage(_ page: Int, _ filter: RequestLogFilter) async throws -> Page<UsageRequestRecord> {
        let read = Read(page: page, filter: filter, kind: nil)
        reads.append(read)
        return try await onUsage(reads.count, read)
    }
    func errors(_ page: Int, _ filter: RequestLogFilter, _ kind: ErrorLogKind) async throws -> Page<RequestErrorRecord> {
        let read = Read(page: page, filter: filter, kind: kind)
        reads.append(read)
        return try await onErrors(reads.count, read)
    }
    nonisolated var source: LogsSource {
        LogsSource(usage: { try await self.usage($0, $1) }, errors: { try await self.errors($0, $1, $2) })
    }
}

/// The store's clock, session flag, ops switch and what it reported to LiveOpsStore (“nil” for a success).
@MainActor private final class Harness {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    /// Server minus phone time, as ServerClock keeps it; `phone` moves with `now`.
    var serverOffset: TimeInterval = 0
    var phone: Date { now.addingTimeInterval(-serverOffset) }
    var isCurrent = true
    var opsOff = false
    private(set) var reports: [String] = []
    let generation = UUID()

    func store(_ route: LogsRoute = LogsRoute(), stub: LogsStub, legacyServer: Bool = false,
               counts: LogCountSource = .unavailable) -> LogsStoreState {
        LogsStoreState(route: route, generation: generation, source: stub.source, timeZone: liveOpsZone, legacyServer: legacyServer,
                       supportsModelSource: true, isCurrent: { self.isCurrent }, now: { self.now }, phoneNow: { self.phone },
                       opsDisabled: { self.opsOff },
                       reportOps: { error in self.reports.append(error.map { ($0 as? APIError)?.reason ?? "other" } ?? "nil") },
                       countSource: counts)
    }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    func lastDay() -> LogTimeWindow { .range(now.addingTimeInterval(-86_400), now) }
}

private let opsOffReply = APIError.server(status: 404, reason: "OPS_DISABLED")

/// `hour:minute` on the site's calendar, `daysAgo` days before `now`'s day.
private func siteTime(_ now: Date, daysAgo: Int = 0, hour: Int, minute: Int = 0) -> Date {
    let calendar = liveOpsZone.calendar
    let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
    return day.addingTimeInterval(TimeInterval(hour * 3_600 + minute * 60))
}
private func usageRecord(_ id: Int, at createdAt: Date) throws -> UsageRequestRecord {
    let json = """
    {"id":\(id),"request_id":"client:\(id)","created_at":"\(ServerTime.utcTimestamp(createdAt))","model":"claude-opus-4","user_id":1,
     "account_id":1,"api_key_id":9,"actual_cost":"0.0124","duration_ms":3200,"first_token_ms":1200,
     "user":{"email":"alice@example.com"},"account":{"name":"Claude-官方-01"}}
    """
    return try JSONDecoder().decode(UsageRequestRecord.self, from: Data(json.utf8))
}
private func errorRecord(_ id: Int, at createdAt: Date, status: Int = 502) throws -> RequestErrorRecord {
    let json = """
    {"id":\(id),"created_at":"\(ServerTime.utcTimestamp(createdAt))","request_id":"req-\(id)","phase":"upstream","type":"upstream_error",
     "status_code":\(status),"platform":"openai","model":"gpt-4.1","resolved":false,"message":"Upstream error","account_id":4}
    """
    return try JSONDecoder().decode(RequestErrorRecord.self, from: Data(json.utf8))
}
private func usagePage(_ records: [UsageRequestRecord], page: Int = 1, hasMore: Bool = false) -> Page<UsageRequestRecord> {
    Page(items: records, total: nil, page: page, pageSize: 100, pages: nil, hasMore: hasMore)
}
/// Like `ops/upstream-errors`: no `has_more`, so `page < pages` decides.
private func errorPage(_ records: [RequestErrorRecord], page: Int = 1, pages: Int = 1) -> Page<RequestErrorRecord> {
    Page(items: records, total: records.count, page: page, pageSize: 100, pages: pages)
}
private func usageRows(_ ids: [Int], now: Date) throws -> [UsageRequestRecord] {
    try ids.map { try usageRecord($0, at: now.addingTimeInterval(-TimeInterval(1_000 - $0) * 60)) }
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

// MARK: - 首屏、返回与分节

@MainActor @Test func firstAppearanceReadsPageOneWithRouteConditions() async throws {
    let gate = SessionGate()
    let harness = Harness()
    let rows = [try errorRecord(5, at: harness.now.addingTimeInterval(-60))]
    let stub = LogsStub(errors: { _, read in await gate.wait(); return errorPage(rows, page: read.page) })
    let route = LogsRoute(scope: .errors, group: RouteObject(id: 2, name: "标准组"), user: RouteObject(id: 1, name: "Alice"))
    let store = harness.store(route, stub: stub)
    let task = Task { await store.appeared() }
    #expect(await eventually { await gate.arrived })
    #expect(store.isFirstLoading)
    await gate.open()
    await task.value
    let reads = await stub.reads
    #expect(reads.count == 1)
    let read = try #require(reads.first)
    #expect(read.page == 1 && read.kind == .request)
    #expect(read.filter.groupID == 2 && read.filter.userID == 1 && read.filter.accountID == nil && read.filter.pageSize == 100)
    #expect(read.filter.time == harness.lastDay())
    #expect(store.phase == .loaded && !store.isFirstLoading)
}

@MainActor @Test func returningToThePageReadsNothing() async throws {
    let harness = Harness()
    let rows = try usageRows([3, 2, 1], now: harness.now)
    let stub = LogsStub(usage: { _, read in usagePage(rows, page: read.page) })
    let store = harness.store(stub: stub)
    await store.appeared()
    let shown = store.sections
    store.disappeared()
    await store.appeared()
    #expect(await stub.reads.count == 1)
    #expect(store.sections == shown)
    #expect(store.isVisible)
}

@MainActor @Test func rowsBecomeServerDaySectionsWhenTheyLand() async throws {
    let harness = Harness()
    let rows = [try usageRecord(2, at: siteTime(harness.now, hour: 9)), try usageRecord(1, at: siteTime(harness.now, daysAgo: 1, hour: 23, minute: 30))]
    let stub = LogsStub(usage: { _, read in usagePage(rows, page: read.page) })
    let store = harness.store(stub: stub)
    #expect(store.sections.isEmpty)
    await store.appeared()
    #expect(store.sections.map(\.title) == ["今天", "昨天"])
    #expect(store.sections.map { $0.rows.map(\.id) } == [[2], [1]])
    #expect(store.sections.first?.rows.first?.time == "09:00")
    #expect(store.sections.last?.rows.first?.time == "23:30")
}

// MARK: - 翻页

@MainActor @Test func nextPageOfARollingPresetUsesTheNewNow() async throws {
    let harness = Harness()
    let first = try usageRows([10, 9, 8], now: harness.now), second = try usageRows([8, 7], now: harness.now)
    let stub = LogsStub(usage: { _, read in read.page == 1 ? usagePage(first, hasMore: true) : usagePage(second, page: read.page) })
    let store = harness.store(stub: stub)
    await store.appeared()
    harness.advance(60)
    await store.loadMoreIfNeeded(after: 9)
    #expect(await stub.reads.count == 1)
    await store.loadMoreIfNeeded(after: 8)
    var reads = await stub.reads
    #expect(reads.map(\.page) == [1, 2])
    #expect(reads.last?.filter.time == harness.lastDay())
    #expect(store.usage.rows.map(\.id) == [10, 9, 8, 7])
    #expect(store.sections.flatMap(\.rows).map(\.id) == [10, 9, 8, 7])

    let start = harness.now.addingTimeInterval(-7_200), end = harness.now.addingTimeInterval(-3_600)
    await store.setTime(.custom(start: start, end: end))
    harness.advance(60)
    await store.loadMoreIfNeeded(after: 8)
    reads = await stub.reads
    #expect(reads.suffix(2).map(\.page) == [1, 2])
    #expect(reads.suffix(2).allSatisfy { $0.filter.time == .range(start, end) })
}

@MainActor @Test func nextPageStopsWhenTheReplyHasNoMore() async throws {
    let harness = Harness()
    let errors = [try errorRecord(6, at: harness.now.addingTimeInterval(-60)), try errorRecord(5, at: harness.now.addingTimeInterval(-120))]
    let usage = try usageRows([3], now: harness.now)
    let stub = LogsStub(usage: { _, read in usagePage(usage, page: read.page) }, errors: { _, read in errorPage(errors, page: read.page) })
    let store = harness.store(LogsRoute(scope: .upstream), stub: stub)
    await store.appeared()
    #expect(store.upstream.nextPage == nil)
    await store.loadMoreIfNeeded(after: 5)
    #expect(await stub.reads.count == 1)
    await store.select(.usage)
    await store.loadMoreIfNeeded(after: 3)
    #expect(await stub.reads.map(\.page) == [1, 1])
}

// MARK: - 分段、下拉、失败

@MainActor @Test func switchingSegmentKeepsConditionsAndReadsItsFirstPage() async throws {
    let gate = SessionGate()
    let harness = Harness()
    let usage = try usageRows([3], now: harness.now)
    let stub = LogsStub(usage: { _, read in usagePage(usage, page: read.page) },
                        errors: { _, read in await gate.wait(); return errorPage([], page: read.page) })
    let route = LogsRoute(account: RouteObject(id: 3), group: RouteObject(id: 1), user: RouteObject(id: 8))
    let store = harness.store(route, stub: stub)
    await store.appeared()
    let task = Task { await store.select(.upstream) }
    #expect(await eventually { await gate.arrived })
    #expect(store.scope == .upstream)
    #expect(store.isFirstLoading && store.sections.isEmpty)
    await gate.open()
    await task.value
    let reads = await stub.reads
    let upstream = try #require(reads.last)
    #expect(upstream.page == 1 && upstream.kind == .upstream)
    #expect(upstream.filter.accountID == 3 && upstream.filter.groupID == 1 && upstream.filter.userID == 8)
    await store.select(.upstream)
    #expect(await stub.reads.count == 2)
}

@MainActor @Test func pullToRefreshReadsPageOneInANewWindow() async throws {
    let gate = SessionGate()
    let harness = Harness()
    let first = try usageRows([10, 9], now: harness.now), second = try usageRows([8], now: harness.now)
    let stub = LogsStub(usage: { call, read in
        if call == 3 { await gate.wait() }
        return read.page == 1 ? usagePage(first, hasMore: true) : usagePage(second, page: read.page)
    })
    let store = harness.store(stub: stub)
    await store.appeared()
    await store.loadMoreIfNeeded(after: 9)
    #expect(store.usage.rows.map(\.id) == [10, 9, 8])
    harness.advance(120)
    let task = Task { await store.reload() }
    #expect(await eventually { await gate.arrived })
    #expect(store.usage.rows.map(\.id) == [10, 9, 8])
    await gate.open()
    await task.value
    let reload = try #require(await stub.reads.last)
    #expect(reload.page == 1 && reload.filter.time == harness.lastDay())
    #expect(store.usage.rows.map(\.id) == [10, 9])
    #expect(store.usage.nextPage == 2)
}

@MainActor @Test func failedReadKeepsRowsAndRetryRepeatsThatPage() async throws {
    let harness = Harness()
    let first = try usageRows([10, 9], now: harness.now), second = try usageRows([8], now: harness.now)
    let stub = LogsStub(usage: { call, read in
        if call == 2 { throw APIError.server(status: 500, reason: nil) }
        if call == 4 { throw APIError.server(status: 503, reason: nil) }
        return read.page == 1 ? usagePage(first, hasMore: true) : usagePage(second, page: read.page)
    })
    let store = harness.store(stub: stub)
    await store.appeared()
    await store.loadMoreIfNeeded(after: 9)
    #expect(store.failure?.page == 2)
    #expect(store.failure?.error?.statusCode == 500)
    #expect(store.hasRows && store.usage.rows.map(\.id) == [10, 9])
    await store.retry()
    #expect(await stub.reads.map(\.page) == [1, 2, 2])
    #expect(store.failure == nil && store.usage.rows.map(\.id) == [10, 9, 8])
    await store.reload()
    #expect(store.failure?.page == 1)
    #expect(store.usage.rows.map(\.id) == [10, 9, 8])
    #expect(store.emptyMessage == nil)
}

@MainActor @Test func firstReadFailureHasNoRowsToKeep() async throws {
    let harness = Harness()
    let rows = try usageRows([3], now: harness.now)
    let stub = LogsStub(usage: { call, read in
        if call == 1 { throw APIError.server(status: 503, reason: nil) }
        return usagePage(rows, page: read.page)
    })
    let store = harness.store(stub: stub)
    await store.appeared()
    #expect(store.failure?.page == 1)
    #expect(!store.hasRows && !store.isFirstLoading && store.emptyMessage == nil)
    await store.retry()
    #expect(store.failure == nil && store.hasRows)
}

// MARK: - 运维关闭

@MainActor @Test func opsOffSkipsErrorReads() async throws {
    let harness = Harness()
    harness.opsOff = true
    let rows = try usageRows([3], now: harness.now)
    let stub = LogsStub(usage: { _, read in usagePage(rows, page: read.page) })
    let store = harness.store(stub: stub)
    await store.appeared()
    for scope in [LogScope.errors, .upstream] {
        await store.select(scope)
        #expect(store.showsOpsNotice && store.failure == nil && store.emptyMessage == nil)
    }
    #expect(await stub.reads.allSatisfy { $0.kind == nil })
    await store.select(.usage)
    #expect(!store.showsOpsNotice && store.hasRows)
    #expect(await stub.reads.count == 2)
}

@MainActor @Test func opsDisabledReplyShowsNoticeAndIsReported() async {
    let harness = Harness()
    let stub = LogsStub(errors: { _, _ in throw opsOffReply })
    let store = harness.store(LogsRoute(scope: .errors), stub: stub)
    await store.appeared()
    #expect(store.phase == .opsDisabled)
    #expect(store.showsOpsNotice && store.failure == nil)
    #expect(harness.reports == ["OPS_DISABLED"])
    #expect(store.refresh.consecutiveFailures == 0)
}

@MainActor @Test func errorReadSuccessReportsOpsAvailable() async {
    let harness = Harness()
    let stub = LogsStub()
    let store = harness.store(stub: stub)
    await store.appeared()
    #expect(harness.reports.isEmpty)
    await store.select(.errors)
    #expect(harness.reports == ["nil"])
}

@MainActor @Test func opsTurningOnReadsTheShownErrorSegment() async {
    let harness = Harness()
    harness.opsOff = true
    let stub = LogsStub()
    let store = harness.store(LogsRoute(scope: .errors), stub: stub)
    await store.appeared()
    #expect(store.showsOpsNotice)
    #expect(await stub.reads.isEmpty)
    harness.opsOff = false
    await store.opsAvailabilityChanged()
    #expect(await stub.reads.map(\.kind) == [.request])
    #expect(!store.showsOpsNotice && store.phase == .loaded)
    await store.select(.usage)
    await store.opsAvailabilityChanged()
    #expect(await stub.reads.count == 2)
}

// MARK: - 时间与条件

@MainActor @Test func timeMenuRestartsWithItsWindow() async {
    let harness = Harness()
    let stub = LogsStub()
    let store = harness.store(stub: stub)
    await store.appeared()
    await store.select(.errors)
    await store.select(.usage)
    #expect(store.errors.phase == .loaded)
    await store.setTime(.lastHour)
    let read = await stub.reads.last
    #expect(read?.kind == nil && read?.page == 1)
    #expect(read?.filter.time == .range(harness.now.addingTimeInterval(-3_600), harness.now))
    #expect(store.errors.phase == .idle)
    #expect(store.timeTitle() == "近 1 小时")
    await store.select(.errors)
    #expect(await stub.reads.last?.filter.time == .range(harness.now.addingTimeInterval(-3_600), harness.now))
    #expect(await stub.reads.count == 5)
}

@MainActor @Test func customRangeIsSentAsItsFixedBounds() async {
    let harness = Harness()
    let stub = LogsStub()
    let store = harness.store(stub: stub)
    let start = harness.now.addingTimeInterval(-2 * 86_400), end = harness.now.addingTimeInterval(-86_400)
    await store.setTime(.custom(start: start, end: end))
    harness.advance(600)
    await store.reload()
    #expect(await stub.reads.map(\.filter.time) == [.range(start, end), .range(start, end)])
    #expect(store.currentWindow() == .range(start, end))
}

@MainActor @Test func newConditionsRestartAndKeepTime() async {
    let harness = Harness()
    let stub = LogsStub()
    let store = harness.store(stub: stub)
    await store.appeared()
    await store.setTime(.last7Days)
    await store.select(.errors)
    await store.setConditions(LogConditions(account: LogFilterObject(id: 3)))
    let read = await stub.reads.last
    #expect(read?.kind == .request && read?.page == 1 && read?.filter.accountID == 3)
    #expect(read?.filter.time == .range(harness.now.addingTimeInterval(-7 * 86_400), harness.now))
    #expect(store.time == .last7Days && store.scope == .errors)
    #expect(store.usage.phase == .idle && store.upstream.phase == .idle)
    #expect(store.conditions == LogConditions(account: LogFilterObject(id: 3)))
}

// MARK: - 迟到回执、会话、回前台、429

@MainActor @Test func lateRepliesOfAnOlderLoadAreDropped() async throws {
    let gate = SessionGate()
    let harness = Harness()
    let usage = try usageRows([3], now: harness.now)
    let errors = [try errorRecord(5, at: harness.now.addingTimeInterval(-60))]
    let stub = LogsStub(usage: { _, read in await gate.wait(); return usagePage(usage, page: read.page) },
                        errors: { _, read in errorPage(errors, page: read.page) })
    let store = harness.store(stub: stub)
    let task = Task { await store.appeared() }
    #expect(await eventually { await gate.arrived })
    await store.select(.errors)
    #expect(store.sections.flatMap(\.rows).map(\.id) == [5])
    await gate.open()
    await task.value
    #expect(store.usage.rows.isEmpty)
    #expect(store.sections.flatMap(\.rows).map(\.id) == [5])
}

@MainActor @Test func endedSessionDropsRepliesAndMarksTheStoreStale() async throws {
    let gate = SessionGate()
    let harness = Harness()
    let rows = try usageRows([3], now: harness.now)
    let stub = LogsStub(usage: { _, read in await gate.wait(); return usagePage(rows, page: read.page) })
    let store = harness.store(stub: stub)
    let task = Task { await store.appeared() }
    #expect(await eventually { await gate.arrived })
    harness.isCurrent = false
    await gate.open()
    await task.value
    #expect(!store.hasRows && store.failure == nil)
    #expect(store.isStale(currentGeneration: UUID()))
    #expect(!store.isStale(currentGeneration: harness.generation))
}

@MainActor @Test func cancelledFirstReadIsReadAgainOnForeground() async throws {
    let harness = Harness()
    let rows = try usageRows([3], now: harness.now)
    let stub = LogsStub(usage: { call, read in
        if call == 1 { throw CancellationError() }
        return usagePage(rows, page: read.page)
    })
    let store = harness.store(stub: stub)
    await store.appeared()
    #expect(store.phase == .idle && store.failure == nil)
    store.disappeared()
    await store.foregroundResumed()
    #expect(await stub.reads.count == 1)
    await store.appeared()
    #expect(await stub.reads.count == 2)
    #expect(store.hasRows)
    await store.foregroundResumed()
    #expect(await stub.reads.map(\.page) == [1, 1, 1])
}

@MainActor @Test func throttledReadsWaitForRetryAfter() async {
    let harness = Harness()
    let limited = APIError(kind: .rateLimited, statusCode: 429, message: "请求过于频繁", retryAfter: 30)
    let stub = LogsStub(usage: { call, read in
        if call == 1 { throw limited }
        return usagePage([], page: read.page)
    })
    let store = harness.store(stub: stub)
    await store.appeared()
    #expect(store.refresh.notBefore == harness.phone.addingTimeInterval(30))
    #expect(store.failure?.page == 1)
    await store.reload()
    await store.retry()
    await store.select(.errors)
    #expect(await stub.reads.count == 1)
    #expect(store.failure?.page == 1)
    await store.select(.usage)
    harness.advance(31)
    await store.retry()
    #expect(await stub.reads.count == 2)
    #expect(store.failure == nil)
}

/// The failure row counts the wait down and reads again on the phone's clock (BlockFailureRow); a site clock behind the
/// phone's (the Date header is cut to the second) must not hold that read back.
@MainActor @Test func throttleWaitRunsOnThePhoneClockLikeTheFailureRow() async throws {
    let harness = Harness()
    harness.serverOffset = -1
    let limited = APIError(kind: .rateLimited, statusCode: 429, message: "请求过于频繁", retryAfter: 30)
    let stub = LogsStub(usage: { call, read in
        if call == 1 { throw limited }
        return usagePage([], page: read.page)
    })
    let store = harness.store(stub: stub)
    await store.appeared()
    let notBefore = try #require(store.refresh.notBefore)
    #expect(notBefore == harness.phone.addingTimeInterval(30))
    // ResendAfterWait sleeps `notBefore.timeIntervalSinceNow`, then the row calls retry.
    harness.advance(notBefore.timeIntervalSince(harness.phone))
    await store.retry()
    #expect(await stub.reads.count == 2)
    #expect(store.failure == nil)
}

// MARK: - 去向、筛选与接口

@MainActor @Test func rowRoutesCarryTheirRecord() async throws {
    let harness = Harness()
    let usage = try usageRows([7], now: harness.now)
    let error = try errorRecord(5, at: harness.now.addingTimeInterval(-60))
    let stub = LogsStub(usage: { _, read in usagePage(usage, page: read.page) }, errors: { _, read in errorPage([error], page: read.page) })
    let store = harness.store(stub: stub)
    await store.appeared()
    let usageRow = try #require(store.sections.first?.rows.first)
    guard case .usage(let preload)? = store.requestRoute(for: usageRow) else { Issue.record("not a usage route"); return }
    #expect(preload.value.id == 7)
    for (scope, kind) in [(LogScope.errors, ErrorLogKind.request), (.upstream, .upstream)] {
        await store.select(scope)
        let row = try #require(store.sections.first?.rows.first)
        guard case .error(let id, let routeKind, let initial)? = store.requestRoute(for: row) else { Issue.record("not an error route"); return }
        #expect(id == 5 && routeKind == kind && initial?.value.id == 5)
    }
    let missing = LogRowPresentation(try errorRecord(99, at: harness.now), kind: .upstream, timeZone: liveOpsZone)
    #expect(store.requestRoute(for: missing) == nil)
}

@MainActor @Test func legacyServerUpstreamFilterDropsUserAndModel() async throws {
    let harness = Harness()
    let route = LogsRoute(scope: .upstream, account: RouteObject(id: 3), user: RouteObject(id: 1), model: "claude-opus-4")
    let stub = LogsStub()
    let legacy = harness.store(route, stub: stub, legacyServer: true)
    await legacy.appeared()
    await legacy.select(.usage)
    let current = harness.store(route, stub: stub)
    await current.appeared()
    let reads = await stub.reads
    #expect(reads.count == 3)
    #expect(reads[0].kind == .upstream && reads[0].filter.accountID == 3 && reads[0].filter.userID == nil && reads[0].filter.model == nil)
    #expect(reads[1].kind == nil && reads[1].filter.userID == 1 && reads[1].filter.model == "claude-opus-4")
    #expect(reads[2].kind == .upstream && reads[2].filter.userID == 1 && reads[2].filter.model == "claude-opus-4")
}

@Test func liveSourceSendsKeyViewOnlyWithMaskedViewCapability() async throws {
    let transport = SessionTransport { request in
        request.url?.path == "/api/v1/admin/usage"
            ? sessionOK(#"{"items":[],"total":null,"page":1,"page_size":100,"pages":null,"has_more":false}"#)
            : sessionOK(#"{"items":[],"total":0,"page":1,"page_size":100,"pages":1}"#)
    }
    let client = sessionClient(transport)
    let end = Date(timeIntervalSince1970: 1_800_000_000)
    let filter = RequestLogFilter(time: .range(end.addingTimeInterval(-86_400), end))
    _ = try await LogsSource.live(client, site: liveOpsSite([.apiKeysMaskedView])).usage(1, filter)
    _ = try await LogsSource.live(client, site: liveOpsSite([])).usage(1, filter)
    _ = try await LogsSource.live(client, site: liveOpsSite([.apiKeysMaskedView])).errors(1, filter, .upstream)
    let requests = await transport.requests
    #expect(requests.map { $0.url?.path } == ["/api/v1/admin/usage", "/api/v1/admin/usage", "/api/v1/admin/ops/upstream-errors"])
    let queries = requests.map { request in
        Dictionary((URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                   uniquingKeysWith: { first, _ in first })
    }
    #expect(queries[0]["key_view"] == "masked")
    #expect(queries[0]["page"] == "1" && queries[0]["page_size"] == "100" && queries[0]["count_mode"] == "deferred")
    #expect(queries[1]["key_view"] == nil)
    #expect(queries[2]["key_view"] == nil && queries[2]["view"] == "all")
}

@MainActor @Test func routeConditionsKeepObjectNamesAndModelSource() {
    let route = LogsRoute(account: RouteObject(id: 1, name: "Claude-官方-01"), group: RouteObject(id: 2), user: RouteObject(id: 1, name: "Alice"),
                          model: "gpt-4.1", modelSource: .upstream)
    let expected = LogConditions(account: LogFilterObject(id: 1, name: "Claude-官方-01"), group: LogFilterObject(id: 2),
                                 user: LogFilterObject(id: 1, name: "Alice"), model: "gpt-4.1", modelSource: .upstream)
    #expect(route.conditions == expected)
    #expect(Harness().store(route, stub: LogsStub()).conditions == expected)
}

@MainActor @Test func subtitleAndEmptyMessageFollowTimeAndConditions() async {
    let harness = Harness()
    let store = harness.store(stub: LogsStub())
    #expect(store.subtitle(siteName: "演示站", device: liveOpsZone.timeZone) == "演示站 · 近 24 小时")
    #expect(store.subtitle(siteName: "演示站", device: TimeZone(identifier: "UTC")!) == "演示站 · 近 24 小时（站点时间 UTC+8）")
    #expect(store.emptyMessage == nil)
    await store.appeared()
    #expect(store.emptyMessage == "近 24 小时内没有记录")
    await store.setTime(.last7Days)
    #expect(store.subtitle(siteName: "演示站", device: liveOpsZone.timeZone) == "演示站 · 近 7 天")
    #expect(store.emptyMessage == "近 7 天内没有记录")

    let filtered = harness.store(LogsRoute(user: RouteObject(id: 1, name: "Alice")), stub: LogsStub())
    await filtered.appeared()
    #expect(filtered.emptyMessage == "近 24 小时内，这些条件下没有记录")
    let failing = harness.store(stub: LogsStub(usage: { _, _ in throw APIError.server(status: 502, reason: nil) }))
    await failing.appeared()
    #expect(failing.emptyMessage == nil)
}

@Test func segmentTitlesAndKinds() {
    #expect(LogScope.allCases.map(\.title) == ["用量明细", "错误请求", "上游错误"])
    #expect(LogScope.allCases.map(\.errorKind) == [nil, .request, .upstream])
}

@MainActor @Test func leavingThePageDropsItsChanges() async {
    let harness = Harness()
    let registry = PageStateRegistry(), router = AppRouter()
    let route = LogsRoute(scope: .usage, user: RouteObject(id: 1, name: "Alice"))
    let key = PageStateKey.logs(route)
    router.push(.logs(route))
    let first = registry.state(key, tab: .today, prunedBy: router) { harness.store(route, stub: LogsStub()) }
    await first.setTime(.lastHour)
    router.push(.request(.usageRequestID("client:1")))
    router.setPath([.logs(route)], for: .today)
    #expect(registry.state(key, tab: .today, prunedBy: router) { harness.store(route, stub: LogsStub()) } === first)
    router.popToRoot(.today)
    router.push(.logs(route))
    let again = registry.state(key, tab: .today, prunedBy: router) { harness.store(route, stub: LogsStub()) }
    #expect(again !== first)
    #expect(again.time == .standard)
}

@Test func segmentReplacingListKeepsPaging() throws {
    let window = LogTimeWindow.range(Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 60))
    let failed = LogSegment<UsageRequestRecord>(nextPage: 3, window: window).failing(page: 3, error: APIError.server(status: 500, reason: nil),
                                                                                    at: Date(timeIntervalSince1970: 30))
    let replaced = failed.replacingList(IncrementalList(items: [try usageRecord(1, at: Date(timeIntervalSince1970: 10))]))
    #expect(replaced.rows.map(\.id) == [1])
    #expect(replaced.nextPage == 3 && replaced.window == window && replaced.phase == .failed(page: 3))
    #expect(replaced.lastError?.statusCode == 500 && replaced.lastErrorAt == Date(timeIntervalSince1970: 30))
    #expect(replaced.opsOff().rows.isEmpty && replaced.opsOff().nextPage == nil && replaced.opsOff().window == window)
}

// MARK: - S4-05b 计数、条件与参数无效

/// The usage query and the two error filters a round asks over `window` without conditions.
private func plainCountRequests(_ window: LogTimeWindow) -> Set<LogCountRequest> {
    guard case .range(let start, let end) = window else { return [] }
    let filter = RequestLogFilter(time: window)
    return [.usage(AnalyticsQuery(start: start, end: end, granularity: .day, timeZone: liveOpsZone)), .errors(filter, .request),
            .errors(filter, .upstream)]
}
@MainActor private func segmentCounts(_ store: LogsStoreState) -> [LogCount] { LogScope.allCases.map { store.counter.count(for: $0) } }

@MainActor @Test func countsAreAskedOnEntryPullTimeAndConditionsOnly() async throws {
    let harness = Harness()
    let rows = try usageRows([3, 2], now: harness.now)
    let counts = LogCountStub(usage: { _, _ in 40 }, errors: { _, _, kind in kind == .request ? 6 : 5 })
    let store = harness.store(stub: LogsStub(usage: { _, read in usagePage(rows, page: read.page, hasMore: read.page == 1) }),
                              counts: counts.source)
    await store.appeared()
    await store.counter.settled()
    #expect(Set(await counts.calls) == plainCountRequests(harness.lastDay()))
    #expect(segmentCounts(store) == [.value(40), .value(6), .value(5)])
    await store.loadMoreIfNeeded(after: 2)
    await store.select(.errors)
    await store.select(.usage)
    store.disappeared()
    await store.appeared()
    await store.counter.settled()
    #expect(await counts.calls.count == 3)
    harness.advance(60)
    await store.reload()
    await store.counter.settled()
    #expect(await counts.calls.count == 6)
    #expect(Set(await counts.calls.suffix(3)) == plainCountRequests(harness.lastDay()))
    await store.setTime(.lastHour)
    await store.counter.settled()
    await store.setConditions(LogConditions(account: LogFilterObject(id: 3)))
    await store.counter.settled()
    #expect(await counts.calls.count == 12)
    #expect(await counts.calls.suffix(3).allSatisfy { request in
        switch request {
        case .usage(let query): query.accountID == 3 && query.end.timeIntervalSince(query.start) == 3_600
        case .errors(let filter, _): filter.accountID == 3 && filter.pageSize == 100
        }
    })
}

@MainActor @Test func shownErrorSegmentCountsFromItsFirstPage() async throws {
    let harness = Harness()
    let rows = [try errorRecord(6, at: harness.now.addingTimeInterval(-60)), try errorRecord(5, at: harness.now.addingTimeInterval(-120))]
    let counts = LogCountStub(usage: { _, _ in 40 }, errors: { _, _, _ in 9 })
    let store = harness.store(LogsRoute(scope: .errors), stub: LogsStub(errors: { _, read in errorPage(rows, page: read.page) }),
                              counts: counts.source)
    await store.appeared()
    await store.counter.settled()
    #expect(segmentCounts(store) == [.value(40), .value(2), .value(9)])
    #expect(await counts.calls.count == 2)
    #expect(!(await counts.calls.contains(.errors(RequestLogFilter(time: harness.lastDay()), .request))))
    await store.select(.upstream)
    await store.select(.errors)
    await store.counter.settled()
    #expect(await counts.calls.count == 2)
    #expect(store.counter.count(for: .errors) == .value(2))
}

@MainActor @Test func leavingTheShownErrorSegmentEarlyAsksItsCount() async throws {
    let gate = SessionGate()
    let harness = Harness()
    let counts = LogCountStub(errors: { _, _, kind in kind == .request ? 4 : 1 })
    let store = harness.store(LogsRoute(scope: .errors), stub: LogsStub(errors: { _, read in
        if read.kind == .request { await gate.wait() }
        return errorPage([], page: read.page)
    }), counts: counts.source)
    let task = Task { await store.appeared() }
    #expect(await eventually { await gate.arrived })
    await store.select(.usage)
    await store.counter.settled()
    #expect(store.counter.count(for: .errors) == .value(4))
    await gate.open()
    await task.value
    #expect(store.counter.count(for: .errors) == .value(4))
}

@MainActor @Test func opsOffAndOpsDisabledCountsReadDash() async {
    let harness = Harness()
    harness.opsOff = true
    let counts = LogCountStub(usage: { _, _ in 40 }, errors: { _, _, _ in throw opsOffReply })
    let store = harness.store(stub: LogsStub(), counts: counts.source)
    await store.appeared()
    await store.counter.settled()
    #expect(segmentCounts(store) == [.value(40), .unavailable, .unavailable])
    #expect(await counts.calls.count == 1)
    #expect(harness.reports.isEmpty)
    harness.opsOff = false
    await store.reload()
    await store.counter.settled()
    #expect(store.counter.count(for: .errors) == .unavailable)
    #expect(harness.reports == ["OPS_DISABLED", "OPS_DISABLED"])
}

@MainActor @Test func foregroundResumesInterruptedCountsWithoutANewRound() async throws {
    let harness = Harness()
    let counts = LogCountStub(usage: { call, _ in
        if call == 1 { throw CancellationError() }
        return 40
    }, errors: { _, _, _ in 6 })
    let store = harness.store(stub: LogsStub(), counts: counts.source)
    await store.appeared()
    await store.counter.settled()
    #expect(store.counter.count(for: .usage) == .pending)
    await store.foregroundResumed()
    await store.counter.settled()
    #expect(store.counter.count(for: .usage) == .value(40))
    #expect(await counts.calls.count == 4)
}

@MainActor @Test func removingAChipReloadsWithoutItAndCountsAgain() async {
    let harness = Harness()
    let stub = LogsStub()
    let counts = LogCountStub()
    let route = LogsRoute(scope: .usage, account: RouteObject(id: 3, name: "Claude-官方-03"), user: RouteObject(id: 1, name: "Alice"),
                          model: "gpt-4.1", modelSource: .upstream)
    let store = harness.store(route, stub: stub, counts: counts.source)
    await store.appeared()
    await store.counter.settled()
    await store.removeCondition(.user)
    await store.counter.settled()
    let read = await stub.reads.last
    #expect(read?.page == 1 && read?.kind == nil && read?.filter.userID == nil && read?.filter.accountID == 3)
    #expect(store.conditions == LogConditions(account: LogFilterObject(id: 3, name: "Claude-官方-03"), model: "gpt-4.1",
                                             modelSource: .upstream))
    let calls = await counts.calls
    #expect(calls.count == 6)
    #expect(calls.suffix(3).contains { if case .usage(let query) = $0 { query.userID == nil && query.accountID == 3 } else { false } })
    await store.removeCondition(.model)
    #expect(store.conditions == LogConditions(account: LogFilterObject(id: 3, name: "Claude-官方-03")))
    #expect(store.hasAppliedConditions)
}

@MainActor @Test func clearingConditionsKeepsTimeAndSegment() async {
    let harness = Harness()
    let stub = LogsStub()
    let store = harness.store(LogsRoute(scope: .upstream, group: RouteObject(id: 2, name: "标准组"), user: RouteObject(id: 1)), stub: stub)
    await store.appeared()
    await store.setTime(.last7Days)
    await store.clearConditions()
    let read = await stub.reads.last
    #expect(read?.kind == .upstream && read?.filter.groupID == nil && read?.filter.userID == nil)
    #expect(read?.filter.time == .range(harness.now.addingTimeInterval(-7 * 86_400), harness.now))
    #expect(store.conditions == LogConditions() && store.time == .last7Days && store.scope == .upstream)
    #expect(!store.hasAppliedConditions)
    #expect(store.emptyMessage == "近 7 天内没有记录")
}

@MainActor @Test func greyedOnlyConditionsCountAsNone() async {
    let harness = Harness()
    let store = harness.store(LogsRoute(scope: .upstream, user: RouteObject(id: 1, name: "Alice")), stub: LogsStub(), legacyServer: true)
    await store.appeared()
    #expect(!store.hasAppliedConditions)
    #expect(store.emptyMessage == "近 24 小时内没有记录")
    await store.select(.usage)
    #expect(store.hasAppliedConditions)
}

@Test func invalidParametersFrom400AndLocalValidation() {
    let failures: [APIError] = [
        .server(status: 400, reason: nil), .server(status: 400, reason: "INVALID_TIME_RANGE"),
        APIError(kind: .validation, message: "请选择一年以内的有效时间范围，并填写正整数对象 ID。"),
    ]
    for error in failures { #expect(LogListFailure(page: 1, error: error, occurredAt: nil).isInvalidParameters, "\(error)") }
}

@Test func sinceIDAndOtherFailuresAreNotParameterErrors() {
    let failures: [APIError?] = [
        .server(status: 400, reason: "INVALID_SINCE_ID"), .server(status: 400, reason: "SINCE_ID_WITH_PAGE"), opsOffReply,
        .server(status: 500, reason: nil), APIError(kind: .transport, message: "无法连接站点"), nil,
    ]
    for error in failures {
        #expect(!LogListFailure(page: 2, error: error, occurredAt: nil).isInvalidParameters, "\(String(describing: error))")
    }
}

@MainActor @Test func retentionNoticeOnlyOnErrorSegmentsOverLongRanges() async {
    let harness = Harness()
    let store = harness.store(stub: LogsStub())
    let longAgo = LogTimePreset.custom(start: harness.now.addingTimeInterval(-45 * 86_400), end: harness.now.addingTimeInterval(-86_400))
    await store.appeared()
    await store.setTime(longAgo)
    #expect(store.retentionNote == nil)
    await store.select(.errors)
    #expect(store.retentionNote == "运维错误日志默认只保留 30 天，更早的可能已清理")
    await store.setTime(.last30Days)
    #expect(store.retentionNote == nil)
    await store.setTime(longAgo)
    harness.opsOff = true
    #expect(store.retentionNote == nil)
}
