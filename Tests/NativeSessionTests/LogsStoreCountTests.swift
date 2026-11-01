import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// The page's list reads, counted from 1 whatever the segment: `fail` may throw for a read; otherwise usage answers no rows
/// and the error lists answer `errorRows`.
private actor ListStub {
    private(set) var reads = 0
    private let errorRows: [RequestErrorRecord]
    private let fail: @Sendable (_ call: Int) -> (any Error)?

    init(errorRows: [RequestErrorRecord] = [], fail: @escaping @Sendable (_ call: Int) -> (any Error)? = { _ in nil }) {
        self.errorRows = errorRows; self.fail = fail
    }
    private func next() throws {
        reads += 1
        if let error = fail(reads) { throw error }
    }
    func usage(_ page: Int) throws -> Page<UsageRequestRecord> {
        try next()
        return Page(items: [], total: nil, page: page, pageSize: 100, pages: nil, hasMore: false)
    }
    func errors(_ page: Int) throws -> Page<RequestErrorRecord> {
        try next()
        return Page(items: errorRows, total: errorRows.count, page: page, pageSize: 100, pages: 1)
    }
    nonisolated var source: LogsSource {
        LogsSource(usage: { page, _ in try await self.usage(page) }, errors: { page, _, _ in try await self.errors(page) })
    }
}

/// One page in Asia/Shanghai; the server and the phone share `now`.
@MainActor private final class CountHarness {
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func store(_ scope: LogScope = .usage, list: ListStub, counts: LogCountStub) -> LogsStoreState {
        LogsStoreState(route: LogsRoute(scope: scope), generation: UUID(), source: list.source, timeZone: liveOpsZone, legacyServer: false,
                       supportsModelSource: true, isCurrent: { true }, now: { self.now }, phoneNow: { self.now },
                       countSource: counts.source)
    }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    func lastDay() -> LogTimeWindow { .range(now.addingTimeInterval(-86_400), now) }
}

private let rateLimited = APIError(kind: .rateLimited, statusCode: 429, message: "请求过于频繁", retryAfter: 30)

private func errorRows(_ ids: [Int], now: Date) throws -> [RequestErrorRecord] {
    try ids.map { id in
        let json = """
        {"id":\(id),"created_at":"\(ServerTime.utcTimestamp(now.addingTimeInterval(-TimeInterval(id) * 60)))","request_id":"req-\(id)",
         "phase":"upstream","type":"upstream_error","status_code":502,"platform":"openai","model":"gpt-4.1","resolved":false,
         "message":"Upstream error","account_id":4}
        """
        return try JSONDecoder().decode(RequestErrorRecord.self, from: Data(json.utf8))
    }
}
@MainActor private func segmentCounts(_ store: LogsStoreState) -> [LogCount] { LogScope.allCases.map { store.counter.count(for: $0) } }

// MARK: - 回到页面（D18）

/// A detail was open when the background stopped a count: the foreground leaves the hidden page alone, the return asks it.
@MainActor @Test func countsStoppedWhileAwayAreAskedOnReturn() async {
    let harness = CountHarness()
    let list = ListStub()
    let counts = LogCountStub(usage: { call, _ in
        if call == 1 { throw CancellationError() }
        return 40
    }, errors: { _, _, _ in 6 })
    let store = harness.store(list: list, counts: counts)
    await store.appeared()
    await store.counter.settled()
    store.disappeared()
    await store.foregroundResumed()
    await store.counter.settled()
    #expect(store.counter.count(for: .usage) == .pending)
    #expect(await counts.calls.count == 3)
    await store.appeared()
    await store.counter.settled()
    #expect(segmentCounts(store) == [.value(40), .value(6), .value(6)])
    #expect(await counts.calls.count == 4)
    #expect(await list.reads == 1)
}

/// Pulled, then a row opened, then the background stopped the new page 1: the old rows stay and nothing reads it again, so
/// the shown error segment asks its count as on leaving it.
@MainActor @Test func shownErrorCountStoppedWhileAwayIsAskedOnReturn() async throws {
    let harness = CountHarness()
    let list = ListStub(errorRows: try errorRows([6, 5], now: harness.now), fail: { $0 == 2 ? CancellationError() : nil })
    let counts = LogCountStub(usage: { _, _ in 40 }, errors: { _, _, kind in kind == .request ? 9 : 5 })
    let store = harness.store(.errors, list: list, counts: counts)
    await store.appeared()
    await store.reload()
    store.disappeared()
    await store.foregroundResumed()
    await store.counter.settled()
    #expect(store.hasRows && store.phase == .loaded)
    #expect(store.counter.count(for: .errors) == .pending)
    #expect(await counts.calls.count == 4)
    await store.appeared()
    await store.counter.settled()
    #expect(segmentCounts(store) == [.value(40), .value(9), .value(5)])
    #expect(await counts.calls.last == .errors(RequestLogFilter(time: harness.lastDay()), .request))
    #expect(await list.reads == 2)
}

/// Shown on return, the page reads page 1 again and its `total` is the count: the list is not asked twice.
@MainActor @Test func shownErrorCountStoppedWhileShownComesFromPageOneAgain() async throws {
    let harness = CountHarness()
    let list = ListStub(errorRows: try errorRows([6, 5], now: harness.now), fail: { $0 == 2 ? CancellationError() : nil })
    let counts = LogCountStub(usage: { _, _ in 40 }, errors: { _, _, _ in 9 })
    let store = harness.store(.errors, list: list, counts: counts)
    await store.appeared()
    await store.reload()
    await store.foregroundResumed()
    await store.counter.settled()
    #expect(segmentCounts(store) == [.value(40), .value(2), .value(9)])
    #expect(await counts.calls.count == 4)
    #expect(await list.reads == 3)
}

// MARK: - 429 等待（00 §2.7.2）

/// During the wait pull, chips, 清除筛选 and the time menu send no counts either; the counts they would ask read “—”.
@MainActor @Test func countsWaitOutA429WithTheList() async {
    let harness = CountHarness()
    let list = ListStub(fail: { $0 == 1 ? rateLimited : nil })
    let counts = LogCountStub(usage: { _, _ in 40 }, errors: { _, _, _ in 6 })
    let store = harness.store(list: list, counts: counts)
    await store.appeared()
    await store.counter.settled()
    #expect(store.failure?.page == 1)
    #expect(await counts.calls.count == 3)
    await store.reload()
    await store.setConditions(LogConditions(account: LogFilterObject(id: 3)))
    await store.removeCondition(.account)
    await store.setTime(.lastHour)
    await store.counter.settled()
    #expect(await counts.calls.count == 3)
    #expect(await list.reads == 1)
    #expect(segmentCounts(store) == [.unavailable, .unavailable, .unavailable])
    harness.advance(31)
    await store.reload()
    await store.counter.settled()
    #expect(await counts.calls.count == 6)
    #expect(segmentCounts(store) == [.value(40), .value(6), .value(6)])
}

/// The shown error segment's count follows its held-back page 1: “—”, then the row's read after the wait fills it.
@MainActor @Test func shownErrorCountFollowsItsHeldBackPageOne() async throws {
    let harness = CountHarness()
    let list = ListStub(errorRows: try errorRows([6], now: harness.now), fail: { $0 == 1 ? rateLimited : nil })
    let counts = LogCountStub(usage: { _, _ in 40 }, errors: { _, _, _ in 9 })
    let store = harness.store(.errors, list: list, counts: counts)
    await store.appeared()
    await store.counter.settled()
    await store.reload()
    await store.counter.settled()
    #expect(await counts.calls.count == 2)
    #expect(segmentCounts(store) == [.unavailable, .unavailable, .unavailable])
    harness.advance(31)
    await store.retry()
    #expect(store.counter.count(for: .errors) == .value(1))
    #expect(await counts.calls.count == 2)
}

/// Counts the background stopped come back during a 429 wait: they read “—” rather than go out.
@MainActor @Test func countsResumedDuringA429WaitReadDash() async {
    let harness = CountHarness()
    let list = ListStub(fail: { $0 == 1 ? rateLimited : nil })
    let counts = LogCountStub(usage: { call, _ in
        if call == 1 { throw CancellationError() }
        return 40
    }, errors: { _, _, _ in 6 })
    let store = harness.store(list: list, counts: counts)
    await store.appeared()
    await store.counter.settled()
    #expect(store.counter.count(for: .usage) == .pending)
    await store.foregroundResumed()
    await store.counter.settled()
    #expect(store.counter.count(for: .usage) == .unavailable)
    #expect(await counts.calls.count == 3)
    #expect(await list.reads == 1)
}
