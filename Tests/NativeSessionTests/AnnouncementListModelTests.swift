import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Records every read and answers through closures; `call` counts from 1 per kind.
private actor AnnouncementStub {
    typealias PageHandler = @Sendable (_ call: Int, _ page: Int, _ query: AnnouncementListQuery) async throws -> Page<Announcement>
    typealias CountsHandler = @Sendable (_ call: Int) async throws -> AnnouncementCounts
    private let onPage: PageHandler
    private let onCounts: CountsHandler
    private(set) var pages: [Int] = []
    private(set) var queries: [AnnouncementListQuery] = []
    private(set) var countReads = 0

    init(page: @escaping PageHandler = { _, page, _ in announcementPage(1...3, page: page) },
         counts: @escaping CountsHandler = { _ in sampleCounts }) {
        onPage = page; onCounts = counts
    }
    func page(_ page: Int, _ query: AnnouncementListQuery) async throws -> Page<Announcement> {
        pages.append(page); queries.append(query)
        return try await onPage(pages.count, page, query)
    }
    func counts() async throws -> AnnouncementCounts {
        countReads += 1
        return try await onCounts(countReads)
    }
    nonisolated var source: AnnouncementListSource {
        AnnouncementListSource(page: { try await self.page($0, $1) }, counts: { try await self.counts() })
    }
}

@MainActor private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor private final class TestFlag { var value = true }

private let sampleCounts = AnnouncementCounts(all: 5, active: 2, draft: 1, archived: 2)
private let failure = APIError.server(status: 502, reason: nil)

private func announcementPage(_ ids: ClosedRange<Int>, page: Int = 1, pages: Int = 1, total: Int? = nil) -> Page<Announcement> {
    Page(items: ids.map { Announcement(id: $0, title: "公告 \($0)", status: .active) }, total: total ?? ids.count, page: page,
         pageSize: 20, pages: pages)
}
private func emptyPage() -> Page<Announcement> { Page(items: [], total: 0, page: 1, pageSize: 20, pages: 1) }

@MainActor private func makeModel(_ stub: AnnouncementStub, status: AnnouncementStatus? = nil, readStats: Bool = true,
                                  clock: TestClock = TestClock(), isCurrent: @escaping @MainActor () -> Bool = { true }) -> AnnouncementListModel {
    AnnouncementListModel(source: stub.source, status: status, includeReadStats: readStats, isCurrent: isCurrent, now: { clock.now })
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

@Test func segmentRouteFallsBackToAll() {
    #expect(AnnouncementSegments.status(route: nil) == nil)
    #expect(AnnouncementSegments.status(route: "") == nil)
    #expect(AnnouncementSegments.status(route: "all") == nil)
    #expect(AnnouncementSegments.status(route: "foo") == nil)
    #expect(AnnouncementSegments.status(route: "active") == .active)
    #expect(AnnouncementSegments.status(route: "draft") == .draft)
    #expect(AnnouncementSegments.status(route: "archived") == .archived)
    #expect(AnnouncementSegments.order == [nil, .active, .draft, .archived])
}

@MainActor @Test func firstLoadReadsPageOneAndCountsTogether() async {
    let gate = SessionGate()
    let stub = AnnouncementStub(counts: { _ in await gate.wait(); return sampleCounts })
    let clock = TestClock()
    let model = makeModel(stub, clock: clock)
    let task = Task { await model.appeared(revision: 0) }
    #expect(await eventually { await gate.arrived })
    #expect(await eventually { await stub.pages == [1] })
    // The rows show before the counts arrive.
    #expect(await eventually { await model.items.count == 3 })
    #expect(model.counts == nil)
    await gate.open()
    await task.value
    #expect(model.items.map(\.id) == [1, 2, 3])
    #expect(model.loadedAt == clock.now)
    #expect(model.counts == sampleCounts)
    #expect(await stub.queries.first?.status == nil)
}

@MainActor @Test func queryAsksForReadStatsOnlyWithCapability() async {
    let without = AnnouncementStub(), with = AnnouncementStub()
    await makeModel(without, readStats: false).reload()
    await makeModel(with, readStats: true).reload()
    #expect(await without.queries.map(\.includeReadStats) == [false])
    #expect(await with.queries.map(\.includeReadStats) == [true])
}

@MainActor @Test func segmentCountsFollowEachRouteAndSurviveFailures() async {
    let partial = AnnouncementStub(counts: { call in
        switch call {
        case 1: sampleCounts
        case 2: AnnouncementCounts(all: 6, active: nil, draft: 1, archived: 2)
        default: throw failure
        }
    })
    let model = makeModel(partial)
    await model.reload()
    #expect(AnnouncementSegments.order.map { model.count(for: $0) } == [5, 2, 1, 2])
    await model.reload()
    #expect(model.count(for: .active) == nil)
    #expect(model.count(for: nil) == 6)
    await model.reload()
    #expect(model.count(for: nil) == 6)
    #expect(model.state.failureReason == nil)
    #expect(model.items.count == 3)

    let broken = AnnouncementStub(counts: { _ in throw failure })
    let fresh = makeModel(broken)
    await fresh.reload()
    #expect(fresh.items.count == 3)
    #expect(AnnouncementSegments.order.allSatisfy { fresh.count(for: $0) == nil })
}

@MainActor @Test func subtitleCountUsesAllCountThenFirstPageTotal() async {
    let counted = makeModel(AnnouncementStub())
    await counted.reload()
    #expect(counted.subtitleCount == 5)

    let missing = AnnouncementStub(page: { _, _, _ in announcementPage(1...3, total: 9) },
                                   counts: { _ in AnnouncementCounts(all: nil, active: 2, draft: 1, archived: 2) })
    let all = makeModel(missing)
    await all.reload()
    #expect(all.subtitleCount == 9)
    await all.select(.draft)
    #expect(all.subtitleCount == nil)
}

@MainActor @Test func selectingSegmentReloadsFirstPageOnly() async {
    let stub = AnnouncementStub()
    let model = makeModel(stub)
    await model.reload()
    await model.select(.draft)
    #expect(model.status == .draft)
    #expect(await stub.pages == [1, 1])
    #expect(await stub.queries.last?.status == .draft)
    #expect(await stub.countReads == 1)
    await model.select(.draft)
    #expect(await stub.pages.count == 2)
    await model.select(nil)
    #expect(await stub.queries.last?.status == nil)
}

@MainActor @Test func emptyKindsFollowTheListStates() async {
    let none = AnnouncementStub(page: { _, _, _ in emptyPage() }, counts: { _ in AnnouncementCounts(all: 0, active: 0, draft: 0, archived: 0) })
    let empty = makeModel(none, status: .draft)
    #expect(empty.emptyKind == nil)
    await empty.reload()
    #expect(empty.emptyKind == .noAnnouncements)

    let drafts = AnnouncementStub(page: { _, _, query in query.status == .draft ? emptyPage() : announcementPage(1...3) })
    let segment = makeModel(drafts, status: .draft)
    await segment.reload()
    #expect(segment.emptyKind == .emptySegment)
    await segment.select(nil)
    #expect(segment.emptyKind == nil)

    let uncounted = AnnouncementStub(page: { _, _, _ in emptyPage() }, counts: { _ in throw failure })
    let all = makeModel(uncounted)
    await all.reload()
    #expect(all.emptyKind == .noAnnouncements)

    let failing = makeModel(AnnouncementStub(page: { _, _, _ in throw failure }))
    await failing.reload()
    #expect(failing.emptyKind == nil)
}

@MainActor @Test func failureWithoutValueThenRetry() async {
    let stub = AnnouncementStub(page: { call, page, _ in
        if call == 1 { throw failure }
        return announcementPage(1...3, page: page)
    })
    let model = makeModel(stub)
    await model.reload()
    #expect(model.state.value == nil)
    #expect(model.state.failureReason == failure.localizedDescription)
    await model.reload()
    #expect(model.state.failureReason == nil)
    #expect(model.items.count == 3)
}

@MainActor @Test func refreshFailureKeepsShownRows() async {
    let stub = AnnouncementStub(page: { call, page, _ in
        if call == 2 { throw failure }
        return announcementPage(1...3, page: page)
    })
    let clock = TestClock()
    let model = makeModel(stub, clock: clock)
    await model.reload()
    let loadedAt = model.loadedAt
    clock.advance(5)
    await model.reload()
    #expect(model.state.failureReason != nil)
    #expect(model.state.value?.count == 3)
    #expect(model.loadedAt == loadedAt)
}

@MainActor @Test func rateLimitedListWaitsBeforeNextRequest() async {
    let stub = AnnouncementStub(page: { call, page, _ in
        if call == 1 { throw APIError.server(status: 429, envelope: nil, retryAfter: 30) }
        return announcementPage(1...3, page: page)
    })
    let clock = TestClock()
    let model = makeModel(stub, clock: clock)
    await model.appeared(revision: 0)
    #expect(model.throttleMessage() == "请求过于频繁，30 秒后自动重试")
    clock.advance(29)
    await model.reload()
    await model.appeared(revision: 0)
    await model.foregroundResumed()
    #expect(await stub.pages == [1])
    clock.advance(1)
    await model.reload()
    #expect(await stub.pages == [1, 1])
    #expect(model.items.count == 3)
}

@MainActor @Test func loadMoreAppendsNextPageOnlyAfterLastRow() async {
    let stub = AnnouncementStub(page: { _, page, _ in
        page == 1 ? announcementPage(1...20, pages: 2, total: 22) : announcementPage(20...22, page: 2, pages: 2, total: 22)
    })
    let model = makeModel(stub)
    await model.reload()
    #expect(model.hasMore)
    await model.loadMoreIfNeeded(after: 19)
    #expect(await stub.pages == [1])
    async let first: Void = model.loadMoreIfNeeded(after: 20)
    async let second: Void = model.loadMoreIfNeeded(after: 20)
    _ = await (first, second)
    #expect(await stub.pages == [1, 2])
    #expect(model.items.map(\.id) == Array(1...22))
    #expect(model.hasMore == false)
    await model.loadMoreIfNeeded(after: 22)
    #expect(await stub.pages == [1, 2])
}

@MainActor @Test func loadMoreFailureShowsRetryAndDoesNotLoop() async {
    let stub = AnnouncementStub(page: { call, page, _ in
        if page == 1 { return announcementPage(1...20, pages: 2, total: 25) }
        if call == 2 { throw failure }
        return announcementPage(21...25, page: 2, pages: 2, total: 25)
    })
    let model = makeModel(stub)
    await model.reload()
    await model.loadMoreIfNeeded(after: 20)
    #expect(model.nextPage == .failed)
    #expect(model.items.count == 20)
    #expect(model.state.failureReason == nil)
    await model.loadMoreIfNeeded(after: 20)
    #expect(await stub.pages == [1, 2])
    await model.retryMore()
    #expect(model.nextPage == .idle)
    #expect(model.items.count == 25)
}

@MainActor @Test func reloadResetsPagingAndDropsLatePageTwo() async {
    let gate = SessionGate()
    let stub = AnnouncementStub(page: { _, page, _ in
        if page == 2 { await gate.wait(); return announcementPage(21...22, page: 2, pages: 2, total: 22) }
        return announcementPage(1...20, pages: 2, total: 22)
    })
    let model = makeModel(stub)
    await model.reload()
    let late = Task { await model.loadMoreIfNeeded(after: 20) }
    #expect(await eventually { await gate.arrived })
    await model.reload()
    await gate.open()
    await late.value
    #expect(model.items.map(\.id) == Array(1...20))
    #expect(model.nextPage == .idle)
    await model.loadMoreIfNeeded(after: 20)
    #expect(await stub.pages == [1, 2, 1, 2])
    #expect(model.items.count == 22)
}

@MainActor @Test func reappearingReloadsOnlyAfterSixtySeconds() async {
    let stub = AnnouncementStub()
    let clock = TestClock()
    let model = makeModel(stub, clock: clock)
    await model.appeared(revision: 0)
    model.disappeared()
    clock.advance(59)
    await model.appeared(revision: 0)
    #expect(await stub.pages == [1])
    model.disappeared()
    clock.advance(1)
    await model.appeared(revision: 0)
    #expect(await stub.pages == [1, 1])
    #expect(await stub.countReads == 2)
}

@MainActor @Test func revisionAndInvalidateReloadWhenVisibleOrOnNextAppearance() async {
    let stub = AnnouncementStub()
    let model = makeModel(stub)
    await model.appeared(revision: 0)
    await model.revisionChanged(1)
    #expect(await stub.pages.count == 2)
    #expect(await stub.countReads == 2)
    model.disappeared()
    await model.revisionChanged(2)
    #expect(await stub.pages.count == 2)
    await model.appeared(revision: 2)
    #expect(await stub.pages.count == 3)
    model.disappeared()
    await model.appeared(revision: 2)
    #expect(await stub.pages.count == 3)
    model.disappeared()
    await model.appeared(revision: 3)
    #expect(await stub.pages.count == 4)
    model.disappeared()
    await model.invalidate()
    #expect(await stub.pages.count == 4)
    await model.appeared(revision: 3)
    #expect(await stub.pages.count == 5)
}

@MainActor @Test func foregroundReloadsOnlyWhileVisible() async {
    let stub = AnnouncementStub()
    let model = makeModel(stub)
    await model.appeared(revision: 0)
    await model.foregroundResumed()
    #expect(await stub.pages.count == 2)
    model.disappeared()
    await model.foregroundResumed()
    #expect(await stub.pages.count == 2)
}

@MainActor @Test func lateResultForAnOldSegmentOrSessionIsDropped() async {
    let gate = SessionGate()
    let stub = AnnouncementStub(page: { call, _, query in
        if call == 1 { await gate.wait() }
        return query.status == .archived ? announcementPage(7...8) : announcementPage(1...3)
    })
    let model = makeModel(stub)
    let first = Task { await model.reload() }
    #expect(await eventually { await gate.arrived })
    await model.select(.archived)
    await gate.open()
    await first.value
    #expect(model.items.map(\.id) == [7, 8])

    let current = TestFlag()
    let session = makeModel(AnnouncementStub(), isCurrent: { current.value })
    let ended = AnnouncementStub(page: { _, _, _ in throw failure })
    let stale = makeModel(ended, isCurrent: { current.value })
    current.value = false
    await session.reload()
    await stale.reload()
    #expect(session.items.isEmpty && session.counts == nil)
    #expect(stale.state.failureReason == nil)

    let gated = SessionGate()
    let ending = AnnouncementStub(page: { _, _, _ in await gated.wait(); return announcementPage(1...3) })
    let flag = TestFlag()
    let switching = makeModel(ending, isCurrent: { flag.value })
    let pending = Task { await switching.reload() }
    #expect(await eventually { await gated.arrived })
    flag.value = false
    await gated.open()
    await pending.value
    #expect(switching.items.isEmpty && switching.counts == nil)
}

@MainActor @Test func cancellationLeavesNoFailure() async {
    let model = makeModel(AnnouncementStub(page: { _, _, _ in throw CancellationError() }))
    await model.reload()
    #expect(model.state.failureReason == nil)
    #expect(model.state.value == nil)
    #expect(model.state.isLoading == false)
    #expect(model.refresh.consecutiveFailures == 0)
}

/// 60 §15.6: a write made while the list was covered still reloads it even if leaving again cancelled the first try.
@MainActor @Test func cancelledReloadLeavesThePendingWriteForTheNextAppearance() async {
    for signalled in [true, false] {
        let gate = SessionGate()
        let stub = AnnouncementStub(page: { call, page, _ in
            if call == 2 { await gate.wait() }
            return announcementPage(1...3, page: page)
        })
        let clock = TestClock()
        let model = makeModel(stub, clock: clock)
        await model.appeared(revision: 0)
        let loadedAt = model.loadedAt
        model.disappeared()
        // The detail's write reaches the list either through onChange or only as a moved revision on return.
        if signalled { await model.revisionChanged(1) }
        clock.advance(10)
        let shown = Task { await model.appeared(revision: 1) }
        #expect(await eventually { await gate.arrived })
        shown.cancel()
        model.disappeared()
        await gate.open()
        await shown.value
        #expect(model.loadedAt == loadedAt)
        clock.advance(10)
        await model.appeared(revision: 1)
        #expect(await stub.pages == [1, 1, 1])
        #expect(model.loadedAt == clock.now)
        model.disappeared()
        await model.appeared(revision: 1)
        #expect(await stub.pages == [1, 1, 1])
    }
}
