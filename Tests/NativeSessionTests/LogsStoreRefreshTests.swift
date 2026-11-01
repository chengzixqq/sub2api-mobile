import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Records the page's reads, the cursor reads included, and answers through closures; `call` counts every read from 1.
private actor PollStub {
    enum Kind: Equatable, Sendable { case page(Int), since(Int) }
    struct Read: Sendable {
        let kind: Kind
        let filter: RequestLogFilter
        let errorKind: ErrorLogKind?
    }
    typealias UsageHandler = @Sendable (_ call: Int, _ read: Read) async throws -> Page<UsageRequestRecord>
    typealias ErrorHandler = @Sendable (_ call: Int, _ read: Read) async throws -> Page<RequestErrorRecord>
    private let onUsage: UsageHandler
    private let onErrors: ErrorHandler
    private(set) var reads: [Read] = []

    init(usage: @escaping UsageHandler = { _, _ in pollPage([]) }, errors: @escaping ErrorHandler = { _, _ in pollPage([]) }) {
        onUsage = usage; onErrors = errors
    }
    var kinds: [Kind] { reads.map(\.kind) }
    func usage(_ read: Read) async throws -> Page<UsageRequestRecord> {
        reads.append(read)
        return try await onUsage(reads.count, read)
    }
    func errors(_ read: Read) async throws -> Page<RequestErrorRecord> {
        reads.append(read)
        return try await onErrors(reads.count, read)
    }
    nonisolated var source: LogsSource {
        LogsSource(usage: { try await self.usage(Read(kind: .page($0), filter: $1, errorKind: nil)) },
                   errors: { try await self.errors(Read(kind: .page($0), filter: $1, errorKind: $2)) },
                   usageSince: { try await self.usage(Read(kind: .since($0), filter: $1, errorKind: nil)) },
                   errorsSince: { try await self.errors(Read(kind: .since($0), filter: $1, errorKind: .request)) })
    }
}

/// The server and the phone share `now`.
@MainActor private final class PollHarness {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var isCurrent = true
    var opsOff = false

    func store(_ route: LogsRoute = LogsRoute(), stub: PollStub, sinceID: Bool = true, policy: LogListPolicy = LogListPolicy(),
               counts: LogCountStub = LogCountStub()) -> LogsStoreState {
        LogsStoreState(route: route, generation: UUID(), source: stub.source, timeZone: liveOpsZone, legacyServer: false,
                       supportsModelSource: true, isCurrent: { self.isCurrent }, now: { self.now }, phoneNow: { self.now },
                       opsDisabled: { self.opsOff }, countSource: counts.source, supportsSinceID: sinceID, policy: policy)
    }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    func lastDay() -> LogTimeWindow { .range(now.addingTimeInterval(-86_400), now) }
}

private func pollPage<Record: Decodable & Sendable>(_ items: [Record], page: Int = 1, hasMore: Bool? = false,
                                                    pages: Int? = nil) -> Page<Record> {
    Page(items: items, total: nil, page: page, pageSize: 100, pages: pages, hasMore: hasMore)
}
private func usageRecord(_ id: Int, createdAt: String) throws -> UsageRequestRecord {
    let json = """
    {"id":\(id),"request_id":"client:\(id)","created_at":"\(createdAt)","model":"claude-opus-4","user_id":1,"account_id":1,
     "api_key_id":9,"actual_cost":"0.0124","duration_ms":3200,"first_token_ms":1200,"user":{"email":"alice@example.com"}}
    """
    return try JSONDecoder().decode(UsageRequestRecord.self, from: Data(json.utf8))
}
private func usageRecord(_ id: Int, at date: Date) throws -> UsageRequestRecord {
    try usageRecord(id, createdAt: ServerTime.utcTimestamp(date))
}
/// A minute apart: id n was made 1,000 − n minutes before `now`, so the cursor of a page is its second newest row.
private func usageRows(_ ids: [Int], now: Date) throws -> [UsageRequestRecord] {
    try ids.map { try usageRecord($0, at: minutesBefore(now, 1_000 - $0)) }
}
private func minutesBefore(_ now: Date, _ minutes: Int) -> Date { now.addingTimeInterval(-TimeInterval(minutes * 60)) }
private func errorRecord(_ id: Int, at createdAt: Date) throws -> RequestErrorRecord {
    let json = """
    {"id":\(id),"created_at":"\(ServerTime.utcTimestamp(createdAt))","request_id":"req-\(id)","phase":"upstream","type":"upstream_error",
     "status_code":502,"platform":"openai","model":"gpt-4.1","resolved":false,"message":"Upstream error","account_id":4}
    """
    return try JSONDecoder().decode(RequestErrorRecord.self, from: Data(json.utf8))
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

// MARK: - 读法（00 §4.3、40 §6.6）

@MainActor @Test func pollReadsPastTheCursorAndPutsNewRowsOnTop() async throws {
    let harness = PollHarness()
    let first = try usageRows([10, 9, 8], now: harness.now), newer = try usageRows([12, 11, 10], now: harness.now)
    let stub = PollStub(usage: { _, read in read.kind == .page(1) ? pollPage(first) : pollPage(newer) })
    let store = harness.store(LogsRoute(account: RouteObject(id: 3), model: "gpt-4.1"), stub: stub)
    await store.appeared()
    #expect(store.autoRefreshes)
    harness.advance(60)
    await store.refreshTick()
    let reads = await stub.reads
    #expect(reads.map(\.kind) == [.page(1), .since(9)])
    #expect(reads[1].filter.accountID == 3 && reads[1].filter.model == "gpt-4.1")
    #expect(store.usage.rows.map(\.id) == [12, 11, 10, 9, 8])
    #expect(store.sections.flatMap(\.rows).map(\.id) == [12, 11, 10, 9, 8])
    #expect(store.phase == .loaded && store.failure == nil)
}

/// 00 §4.3 step 7: without `logs.since_id`, page 1 of 100 from the newest row's time − 120 seconds to now.
@MainActor @Test func withoutSinceIDPollsReadTheTimeWindow() async throws {
    let harness = PollHarness()
    let first = try usageRows([10, 9], now: harness.now), newest = minutesBefore(harness.now, 990)
    let stub = PollStub(usage: { _, _ in pollPage(first) })
    let store = harness.store(stub: stub, sinceID: false)
    await store.appeared()
    harness.advance(60)
    await store.refreshTick()
    let read = try #require(await stub.reads.last)
    #expect(await stub.kinds == [.page(1), .page(1)])
    #expect(read.filter.time == .range(newest.addingTimeInterval(-120), harness.now) && read.filter.pageSize == 100)
}

/// 40 §6.6: upstream errors have no since_id; every poll is a time window and none calibrates, however many there are.
@MainActor @Test func upstreamPollsTheTimeWindowAndNeverCalibrates() async throws {
    let harness = PollHarness()
    let newest = harness.now.addingTimeInterval(-300)
    let rows = [try errorRecord(6, at: newest), try errorRecord(5, at: harness.now.addingTimeInterval(-600))]
    let stub = PollStub(errors: { _, _ in pollPage(rows, hasMore: nil, pages: 1) })
    let store = harness.store(LogsRoute(scope: .upstream), stub: stub)
    await store.appeared()
    for _ in 0..<12 {
        harness.advance(60)
        await store.refreshTick()
    }
    let reads = await stub.reads
    #expect(reads.count == 13)
    #expect(reads.allSatisfy { $0.kind == .page(1) && $0.errorKind == .upstream })
    #expect(reads.dropFirst().allSatisfy { read in
        if case .range(let start, _) = read.filter.time { start == newest.addingTimeInterval(-120) } else { false }
    })
    #expect(reads.last?.filter.time == .range(newest.addingTimeInterval(-120), harness.now))
}

// MARK: - 改第 1 页重载

/// 00 §4.3 steps 4 and 6, 40 §6.5: has_more and the two since_id rejections read page 1 again, show nothing and count nothing.
@MainActor @Test func overflowingOrRejectedPollsReloadPageOneQuietly() async throws {
    let harness = PollHarness()
    let first = try usageRows([10, 9], now: harness.now), reloaded = try usageRows([30, 29], now: harness.now)
    let stub = PollStub(usage: { call, read in
        switch (read.kind, call) {
        case (.since, 2): return pollPage([], hasMore: true)
        case (.since, 4): throw APIError.server(status: 400, reason: "INVALID_SINCE_ID")
        case (.since, _): throw APIError.server(status: 400, reason: "SINCE_ID_WITH_PAGE")
        case (.page, 1): return pollPage(first)
        case (.page, _): return pollPage(reloaded)
        }
    })
    let counts = LogCountStub()
    let store = harness.store(stub: stub, counts: counts)
    await store.appeared()
    await store.counter.settled()
    let asked = await counts.calls.count
    harness.advance(60)
    await store.refreshTick()
    #expect(await stub.kinds == [.page(1), .since(9), .page(1)])
    #expect(await stub.reads.last?.filter.time == harness.lastDay())
    #expect(store.usage.rows.map(\.id) == [30, 29])
    for _ in 0..<2 {
        harness.advance(60)
        await store.refreshTick()
    }
    #expect(await stub.kinds.suffix(4) == [.since(29), .page(1), .since(29), .page(1)])
    #expect(store.failure == nil && store.phase == .loaded)
    await store.counter.settled()
    #expect(await counts.calls.count == asked)
}

/// 40 §6.6: an upstream window that holds more than one page left a gap.
@MainActor @Test func upstreamWindowOfSeveralPagesReloadsPageOne() async throws {
    let harness = PollHarness()
    let rows = [try errorRecord(6, at: harness.now.addingTimeInterval(-300))]
    let stub = PollStub(errors: { call, _ in pollPage(rows, hasMore: nil, pages: call == 2 ? 3 : 1) })
    let store = harness.store(LogsRoute(scope: .upstream), stub: stub)
    await store.appeared()
    harness.advance(60)
    await store.refreshTick()
    let reads = await stub.reads
    #expect(reads.count == 3)
    #expect(reads.last?.filter.time == harness.lastDay())
}

// MARK: - 校准、裁剪与裁尾

/// 40 §6.6: the eleventh poll reads page 1 as the first screen did and joins it by id, keeping the older pages.
@MainActor @Test func tenIncrementsThenCalibrationKeepsOlderPages() async throws {
    let harness = PollHarness()
    let first = try usageRows([10, 9], now: harness.now), older = try usageRows([8, 7], now: harness.now)
    let calibrated = try usageRows([11, 10, 9], now: harness.now)
    let stub = PollStub(usage: { call, read in
        switch read.kind {
        case .page(1): call == 1 ? pollPage(first, hasMore: true) : pollPage(calibrated, hasMore: true)
        case .page(let page): pollPage(older, page: page)
        case .since: pollPage([])
        }
    })
    let store = harness.store(stub: stub)
    await store.appeared()
    await store.loadMoreIfNeeded(after: 9)
    #expect(store.usage.rows.map(\.id) == [10, 9, 8, 7])
    for _ in 0..<10 {
        harness.advance(60)
        await store.refreshTick()
    }
    harness.advance(60)
    await store.refreshTick()
    let calibration = try #require(await stub.reads.last)
    #expect(calibration.kind == .page(1) && calibration.filter.time == harness.lastDay())
    #expect(store.usage.rows.map(\.id) == [11, 10, 9, 8, 7])
    #expect(store.usage.nextPage == nil)
    harness.advance(60)
    await store.refreshTick()
    #expect(await stub.kinds == [.page(1), .page(2)] + Array(repeating: .since(9), count: 10) + [.page(1), .since(10)])
}

/// 40 §6.6: after each merge the rows made before the window's start go; a time that does not read stays.
@MainActor @Test func pollsDropRowsOlderThanTheWindow() async throws {
    let harness = PollHarness()
    let start = harness.now
    let rows = [try usageRecord(4, createdAt: "unknown"), try usageRecord(3, at: start.addingTimeInterval(-60)),
                try usageRecord(2, at: start.addingTimeInterval(-600)), try usageRecord(1, at: start.addingTimeInterval(-86_000))]
    let stub = PollStub(usage: { _, read in pollPage(read.kind == .page(1) ? rows : []) })
    let store = harness.store(stub: stub)
    await store.appeared()
    #expect(store.usage.rows.count == 4)
    harness.advance(600)
    await store.refreshTick()
    #expect(await stub.kinds == [.page(1), .since(2)])
    #expect(store.usage.rows.map(\.id) == [4, 3, 2])
}

/// 40 §6.6: past N the tail goes only while the first visible row is within the top 20; scrolled down it waits for the way
/// back. A list over N that no poll grew is left alone.
@MainActor @Test func trimWaitsWhileScrolledDownAndLandsBackNearTheTop() async throws {
    let harness = PollHarness()
    let first = try usageRows(Array((11...40).reversed()), now: harness.now), newer = try usageRows([41], now: harness.now)
    let stub = PollStub(usage: { _, read in pollPage(read.kind == .page(1) ? first : newer) })
    let store = harness.store(stub: stub, policy: LogListPolicy(limit: 5, pageSize: 5))
    await store.appeared()
    #expect(await stub.reads.first?.filter.pageSize == 5)
    store.rowAppeared(40)
    #expect(store.usage.rows.count == 30)
    store.rowDisappeared(40)
    for id in 11...15 { store.rowAppeared(id) }
    harness.advance(60)
    await store.refreshTick()
    #expect(store.usage.rows.count == 31 && store.usage.rows.first?.id == 41)
    for id in 11...15 { store.rowDisappeared(id) }
    store.rowAppeared(30)
    #expect(store.usage.rows.map(\.id) == [41, 40, 39, 38, 37])
    #expect(store.sections.flatMap(\.rows).count == 5)
    #expect(store.usage.nextPage == 2)
}

/// 40 §6.6: N = 500 at the top, and “加载更多” reads page 6 of the window as it is now.
@MainActor @Test func standardPolicyTrimsToFiveHundredAndReadsPageSixNext() async throws {
    let harness = PollHarness()
    let first = try usageRows(Array((1...600).reversed()), now: harness.now), newer = try usageRows([601], now: harness.now)
    let stub = PollStub(usage: { _, read in
        switch read.kind {
        case .page(1): pollPage(first)
        case .page(let page): pollPage([], page: page)
        case .since: pollPage(newer)
        }
    })
    let store = harness.store(stub: stub)
    await store.appeared()
    harness.advance(60)
    await store.refreshTick()
    #expect(store.usage.rows.count == 500)
    #expect(store.usage.rows.first?.id == 601 && store.usage.rows.last?.id == 102)
    #expect(store.usage.nextPage == 6)
    harness.advance(60)
    await store.loadMoreIfNeeded(after: 102)
    let read = try #require(await stub.reads.last)
    #expect(read.kind == .page(6) && read.filter.time == harness.lastDay())
}

// MARK: - 失败、间隔与 429

/// 00 §4.6: a cancelled poll leaves nothing behind; another failure keeps the rows, says so at the end of the list and
/// stretches the interval, and 重试 polls again rather than reading page 1.
@MainActor @Test func failedPollsKeepRowsAndRetryPollsAgain() async throws {
    let harness = PollHarness()
    let first = try usageRows([10, 9, 8], now: harness.now), newer = try usageRows([12], now: harness.now)
    let stub = PollStub(usage: { call, _ in
        switch call {
        case 1: return pollPage(first)
        case 2: throw CancellationError()
        case 3: throw APIError.server(status: 502, reason: nil)
        default: return pollPage(newer)
        }
    })
    let store = harness.store(stub: stub)
    await store.appeared()
    harness.advance(60)
    await store.refreshTick()
    #expect(store.phase == .loaded && store.failure == nil)
    harness.advance(60)
    await store.refreshTick()
    #expect(store.phase == .refreshFailed)
    #expect(store.failure?.page == 1 && store.failure?.error?.statusCode == 502)
    #expect(store.usage.rows.map(\.id) == [10, 9, 8])
    #expect(store.refresh.consecutiveFailures == 1)
    #expect(store.nextAutoRefreshDelay() == 120)
    await store.retry()
    #expect(await stub.kinds == [.page(1), .since(9), .since(9), .since(9)])
    #expect(store.failure == nil && store.phase == .loaded)
    #expect(store.usage.rows.map(\.id) == [12, 10, 9, 8])
    #expect(store.refresh.consecutiveFailures == 0)
}

/// A trim on the way back up leaves the failed poll's row in place; the next merged poll clears it.
@Test func trimKeepsAFailedPollAndAMergeClearsIt() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let failed = LogSegment<UsageRequestRecord>(list: IncrementalList(items: try usageRows([10, 9, 8], now: now)), phase: .loaded)
        .refreshFailing(APIError.server(status: 502, reason: nil), at: now)
    let trimmed = failed.trimmed(try #require(LogListPolicy(limit: 2, pageSize: 2).trimmed(failed.list, firstVisibleIndex: nil)))
    #expect(trimmed.rows.map(\.id) == [10, 9] && trimmed.nextPage == 2)
    #expect(trimmed.phase == .refreshFailed && trimmed.lastError?.statusCode == 502 && trimmed.lastErrorAt == now)
    let merged = trimmed.refreshed(trimmed.list)
    #expect(merged.phase == .loaded && merged.lastError == nil && merged.lastErrorAt == nil && merged.nextPage == 2)
}

/// 00 §4.6 / §2.7.2: the wait counts from the end of the last read; a 429 holds every poll back until it is over.
@MainActor @Test func nextPollCountsFromTheLastReadAndWaitsOutA429() async throws {
    let harness = PollHarness()
    let limited = APIError(kind: .rateLimited, statusCode: 429, message: "请求过于频繁", retryAfter: 30)
    let first = try usageRows([10, 9], now: harness.now)
    let stub = PollStub(usage: { call, _ in
        if call == 2 { throw limited }
        return pollPage(call == 1 ? first : [])
    })
    let store = harness.store(stub: stub)
    #expect(store.nextAutoRefreshDelay() == 60)
    await store.appeared()
    harness.advance(20)
    #expect(store.nextAutoRefreshDelay() == 40)
    harness.advance(45)
    #expect(store.nextAutoRefreshDelay() == 0)
    await store.refreshTick()
    #expect(store.nextAutoRefreshDelay() == 30)
    await store.refreshTick()
    #expect(await stub.reads.count == 2)
    harness.advance(31)
    #expect(store.nextAutoRefreshDelay() == 89)
    await store.retry()
    #expect(await stub.reads.count == 3 && store.failure == nil)
}

// MARK: - 何时轮询

/// D18 / 40 §6.6: back from the background a shown rolling page polls at once; a hidden page waits for its return, and a
/// custom range neither polls nor stops reading page 1 again.
@MainActor @Test func foregroundPollsAShownRollingPageAndReloadsOtherwise() async throws {
    let harness = PollHarness()
    let first = try usageRows([10, 9, 8], now: harness.now), newer = try usageRows([11], now: harness.now)
    let stub = PollStub(usage: { _, read in pollPage(read.kind == .page(1) ? first : newer) })
    let store = harness.store(stub: stub)
    await store.appeared()
    await store.foregroundResumed()
    #expect(await stub.kinds == [.page(1), .since(9)])
    store.disappeared()
    await store.foregroundResumed()
    await store.refreshTick()
    #expect(await stub.reads.count == 2)
    await store.appeared()
    let start = harness.now.addingTimeInterval(-7_200), end = harness.now.addingTimeInterval(-3_600)
    await store.setTime(.custom(start: start, end: end))
    #expect(!store.autoRefreshes)
    await store.refreshTick()
    #expect(await stub.reads.count == 3)
    await store.foregroundResumed()
    #expect(await stub.kinds.suffix(2) == [.page(1), .page(1)])
    #expect(await stub.reads.last?.filter.time == .range(start, end))
}

/// Nothing polls before the segment has loaded, nor an error segment while ops monitoring is off.
@MainActor @Test func pollsWaitForALoadedSegmentAndOpsMonitoring() async throws {
    let harness = PollHarness()
    harness.opsOff = true
    let stub = PollStub(usage: { call, _ in
        if call == 1 { throw APIError.server(status: 503, reason: nil) }
        return pollPage([])
    })
    let store = harness.store(LogsRoute(scope: .errors), stub: stub)
    await store.appeared()
    #expect(store.showsOpsNotice && !store.autoRefreshes)
    await store.refreshTick()
    #expect(await stub.reads.isEmpty)
    await store.select(.usage)
    #expect(store.failure?.page == 1 && !store.autoRefreshes)
    await store.refreshTick()
    #expect(await stub.reads.count == 1)
}

/// One poll at a time; a pull that lands while it is out drops its reply, as does an ended session.
@MainActor @Test func supersededPollRepliesAreDropped() async throws {
    let gate = SessionGate()
    let harness = PollHarness()
    let first = try usageRows([10, 9], now: harness.now), newer = try usageRows([11], now: harness.now)
    let pulled = try usageRows([20, 19], now: harness.now)
    let stub = PollStub(usage: { call, read in
        switch read.kind {
        case .since: await gate.wait(); return pollPage(newer)
        case .page: return pollPage(call == 1 ? first : pulled)
        }
    })
    let store = harness.store(stub: stub)
    await store.appeared()
    let poll = Task { await store.refreshTick() }
    #expect(await eventually { await gate.arrived })
    await store.refreshTick()
    #expect(await stub.reads.count == 2)
    await store.reload()
    await gate.open()
    await poll.value
    #expect(store.usage.rows.map(\.id) == [20, 19])
    harness.isCurrent = false
    await store.refreshTick()
    #expect(await stub.reads.count == 3)
}

// MARK: - 接口参数（S4D1-06）

/// The cursor reads carry the object conditions, `since_id` and page_size 100 only; `key_view=masked` only with the site's
/// `api_keys.masked_view`, never on the error list.
@Test func liveSourceCursorReadsSendOnlyConditionsCursorAndPageSize() async throws {
    let transport = SessionTransport { _ in
        sessionOK(#"{"items":[],"total":null,"page":1,"page_size":100,"pages":null,"has_more":false,"since_id":40,"latest_id":40}"#)
    }
    let client = sessionClient(transport)
    let end = Date(timeIntervalSince1970: 1_800_000_000)
    let filter = RequestLogFilter(time: .range(end.addingTimeInterval(-86_400), end), accountID: 3, userID: 8, model: "gpt-4.1",
                                  modelSource: .upstream)
    _ = try await LogsSource.live(client, site: liveOpsSite([.apiKeysMaskedView])).usageSince(40, filter)
    _ = try await LogsSource.live(client, site: liveOpsSite([])).usageSince(40, filter)
    _ = try await LogsSource.live(client, site: liveOpsSite([.apiKeysMaskedView])).errorsSince(41, filter)
    let requests = await transport.requests
    #expect(requests.map { $0.url?.path } == ["/api/v1/admin/usage", "/api/v1/admin/usage", "/api/v1/admin/ops/request-errors"])
    let queries = requests.map { request in
        Dictionary((URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                   uniquingKeysWith: { first, _ in first })
    }
    for query in queries {
        #expect(["page", "start_time", "end_time", "time_range", "sort_by", "sort_order", "count_mode"].allSatisfy { query[$0] == nil },
                "\(query)")
        #expect(query["page_size"] == "100" && query["account_id"] == "3" && query["user_id"] == "8" && query["model"] == "gpt-4.1")
    }
    #expect(queries[0]["since_id"] == "40" && queries[0]["model_source"] == "upstream" && queries[0]["timezone"] != nil)
    #expect(queries[0]["key_view"] == "masked")
    #expect(queries[1]["key_view"] == nil)
    #expect(queries[2]["since_id"] == "41" && queries[2]["view"] == "all" && queries[2]["key_view"] == nil)
}
