import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Records every read and answers through closures; `call` counts from 1 per kind.
private actor ReadsStub {
    typealias PageHandler = @Sendable (_ call: Int, _ page: Int, _ query: AnnouncementReadStatusQuery) async throws -> Page<AnnouncementReadStatusRow>
    typealias TitleHandler = @Sendable (_ call: Int) async throws -> Announcement
    typealias SummaryHandler = @Sendable (_ call: Int) async throws -> AnnouncementReadSummary
    private let onPage: PageHandler
    private let onTitle: TitleHandler
    private let onSummary: SummaryHandler
    private(set) var pages: [Int] = []
    private(set) var queries: [AnnouncementReadStatusQuery] = []
    private(set) var ids: [Int] = []
    private(set) var titleReads = 0
    private(set) var summaryReads = 0

    init(page: @escaping PageHandler = { _, page, _ in rosterPage(1...3, page: page) },
         title: @escaping TitleHandler = { _ in Announcement(id: 31, title: "维护通知", status: .active) },
         summary: @escaping SummaryHandler = { _ in sampleSummary }) {
        onPage = page; onTitle = title; onSummary = summary
    }
    func page(_ id: Int, _ page: Int, _ query: AnnouncementReadStatusQuery) async throws -> Page<AnnouncementReadStatusRow> {
        ids.append(id); pages.append(page); queries.append(query)
        return try await onPage(pages.count, page, query)
    }
    func title(_ id: Int) async throws -> Announcement {
        titleReads += 1
        return try await onTitle(titleReads)
    }
    func summary(_ id: Int) async throws -> AnnouncementReadSummary {
        summaryReads += 1
        return try await onSummary(summaryReads)
    }
    /// The title and summary reads so far.
    func headerReads() -> [Int] { [titleReads, summaryReads] }
    nonisolated var source: AnnouncementReadsSource {
        AnnouncementReadsSource(announcement: { try await self.title($0) }, page: { try await self.page($0, $1, $2) },
                                summary: { try await self.summary($0) })
    }
}

@MainActor private final class ReadsFlag { var value = true }

private let failure = APIError.server(status: 502, reason: nil)
private let gone = APIError.server(status: 404, reason: "ANNOUNCEMENT_NOT_FOUND")
private let invalidFilter = APIError.server(status: 400, reason: "INVALID_READ_STATUS_FILTER")
private let sampleSummary = AnnouncementReadSummary(announcementID: 31, totalUsers: 1036, eligibleCount: 1036, readCount: 412, eligibleReadCount: 410,
                                                    computedAt: Date(timeIntervalSince1970: 1_792_115_460))
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

private func rosterRow(_ id: Int) -> AnnouncementReadStatusRow {
    AnnouncementReadStatusRow(userID: id, email: "user\(id)@example.com", username: "user\(id)", balance: Decimal(id), eligible: true)
}
private func rosterPage(_ ids: ClosedRange<Int>, page: Int = 1, pages: Int = 1, total: Int? = nil) -> Page<AnnouncementReadStatusRow> {
    Page(items: ids.map(rosterRow), total: total ?? ids.count, page: page, pageSize: 50, pages: pages)
}

@MainActor private func makeModel(_ stub: ReadsStub, readStats: Bool = true, debounce: Duration = .milliseconds(30),
                                  isCurrent: @escaping @MainActor () -> Bool = { true }) -> AnnouncementReadsModel {
    AnnouncementReadsModel(announcementID: 31, supportsReadStats: readStats, source: stub.source, isCurrent: isCurrent, debounce: debounce)
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

@MainActor @Test func startLoadsTitleSummaryAndFirstPageConcurrently() async {
    let gate = SessionGate()
    let stub = ReadsStub(page: { _, page, _ in await gate.wait(); return rosterPage(1...3, page: page, total: 1036) })
    let model = makeModel(stub)
    let task = Task { await model.start() }
    #expect(await eventually { await gate.arrived })
    // The title and the summary go out while page 1 is still waiting.
    #expect(await eventually { await stub.headerReads() == [1, 1] })
    await gate.open()
    await task.value
    #expect(model.rows.map(\.userID) == [1, 2, 3])
    #expect(model.title == "维护通知")
    #expect(model.summary == sampleSummary)
    #expect(model.summaryText(serverTimeZone: shanghai) == "已读 412 · 符合条件 1,036 · 共 1,036 位用户 · 统计于 09:51")
    #expect(model.foundText == nil)
    #expect(await stub.ids == [31])
    let query = await stub.queries.first
    #expect(query?.effectiveSort == .email && query?.isFiltered == false && query?.supportsReadStats == true)
    // Back from a user's page: nothing is read again (60 §18.6).
    await model.start()
    #expect(await stub.pages == [1])
    #expect(await stub.titleReads == 1)
}

@MainActor @Test func withoutCapabilityUsesPageTotalAndNoSummaryRequest() async {
    let stub = ReadsStub(page: { _, page, _ in rosterPage(1...3, page: page, total: 1036) })
    let model = makeModel(stub, readStats: false)
    await model.start()
    #expect(await stub.summaryReads == 0)
    #expect(model.summaryText(serverTimeZone: shanghai) == "第 1 页 · 共 1,036 位用户")
    #expect(model.sorts == [.email, .username, .balance])
    #expect(await stub.queries.first?.supportsReadStats == false)
}

@MainActor @Test func summaryFailureFallsBackToPageTotal() async {
    let stub = ReadsStub(page: { _, page, _ in rosterPage(1...3, page: page, total: 26) },
                         summary: { call in if call == 1 { throw failure }; return sampleSummary })
    let model = makeModel(stub)
    await model.start()
    #expect(model.summary == nil)
    #expect(model.summaryText(serverTimeZone: shanghai) == "第 1 页 · 共 26 位用户")
    await model.reload()
    #expect(model.summary == sampleSummary)
}

@MainActor @Test func searchDebouncesAndCancelsEarlierInput() async {
    let stub = ReadsStub(page: { _, page, query in
        AnnouncementQueryProbe.search(query) == nil ? rosterPage(1...3, page: page, total: 26) : rosterPage(2...2, page: page)
    })
    let model = makeModel(stub)
    await model.start()
    model.searchChanged("b")
    model.searchChanged("bo")
    #expect(model.searchText == "bo")
    #expect(await eventually { await stub.pages.count == 2 })
    try? await Task.sleep(for: .milliseconds(80))
    #expect(await stub.queries.map(\.search) == ["", "bo"])
    #expect(await eventually { await model.rows.map(\.userID) == [2] })
    #expect(model.foundText == "找到 1 位")
    // The fallback bar keeps the unfiltered total; a search is not a new title or summary read.
    #expect(model.unfilteredTotal == 26)
    #expect(await stub.titleReads == 1)
    // The same words with spaces around them read nothing.
    model.searchChanged(" bo ")
    try? await Task.sleep(for: .milliseconds(80))
    #expect(await stub.pages.count == 2)
}

@MainActor @Test func typingOnKeepsTheSearchAlreadySent() async {
    let gate = SessionGate()
    let stub = ReadsStub(page: { _, page, query in
        switch AnnouncementQueryProbe.search(query) {
        case nil: return rosterPage(1...3, page: page, total: 26)
        case "bo"?: await gate.wait(); return rosterPage(2...2, page: page)
        default: return rosterPage(5...6, page: page)
        }
    })
    let model = makeModel(stub)
    await model.start()
    model.searchChanged("bo")
    #expect(await eventually { await gate.arrived })
    // A space typed while page 1 of “bo” is on its way: the same search, nothing new goes out, and the read already sent lands.
    model.searchChanged("bo ")
    try? await Task.sleep(for: .milliseconds(80))
    await gate.open()
    #expect(await eventually { await model.rows.map(\.userID) == [2] })
    #expect(!model.state.isLoading)
    #expect(await stub.pages.count == 2)

    // Other words while “bo” is still out: the newer search wins and the older reply is dropped when it lands.
    let held = SessionGate()
    let slow = ReadsStub(page: { _, page, query in
        switch AnnouncementQueryProbe.search(query) {
        case nil: return rosterPage(1...3, page: page, total: 26)
        case "bo"?: await held.wait(); return rosterPage(2...2, page: page)
        default: return rosterPage(5...6, page: page)
        }
    })
    let switching = makeModel(slow)
    await switching.start()
    switching.searchChanged("bo")
    #expect(await eventually { await held.arrived })
    switching.searchChanged("al")
    #expect(await eventually { await switching.rows.map(\.userID) == [5, 6] })
    await held.open()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(switching.rows.map(\.userID) == [5, 6])
    #expect(await slow.queries.map(\.search) == ["", "bo", "al"])
}

@MainActor @Test func filterAndSortChangesReloadFirstPage() async {
    let stub = ReadsStub(page: { call, page, _ in
        call == 1 ? rosterPage(1...3, page: page, pages: 2, total: 6) : rosterPage(10...11, page: page)
    })
    let model = makeModel(stub)
    await model.start()
    await model.setReadState(.read)
    #expect(model.rows.map(\.userID) == [10, 11])
    await model.setEligibleOnly(true)
    await model.setSort(.readAt)
    await model.setSort(.readAt)
    let queries = await stub.queries
    #expect(await stub.pages == [1, 1, 1, 1])
    #expect(queries.map(\.readState) == [.all, .read, .read, .read])
    #expect(queries.map(\.eligibleOnly) == [false, false, true, true])
    #expect(queries.last?.effectiveSort == .readAt)
    #expect(model.foundText == "找到 2 位")
    #expect(await stub.headerReads() == [1, 1])
}

@MainActor @Test func loadMoreAppendsNextPageAndDeduplicates() async {
    let stub = ReadsStub(page: { _, page, _ in
        page == 1 ? rosterPage(1...3, page: 1, pages: 2, total: 5) : rosterPage(3...5, page: 2, pages: 2, total: 5)
    })
    let model = makeModel(stub)
    await model.start()
    #expect(model.hasMore)
    await model.loadMoreIfNeeded(after: 2)
    #expect(await stub.pages == [1])
    await model.loadMoreIfNeeded(after: 3)
    #expect(model.rows.map(\.userID) == [1, 2, 3, 4, 5])
    #expect(!model.hasMore)
    await model.loadMoreIfNeeded(after: 5)
    #expect(await stub.pages == [1, 2])
}

@MainActor @Test func loadMoreFailureKeepsRowsAndRetries() async {
    let stub = ReadsStub(page: { call, page, _ in
        if page == 2, call == 2 { throw failure }
        return page == 1 ? rosterPage(1...3, page: 1, pages: 2) : rosterPage(4...5, page: 2, pages: 2)
    })
    let model = makeModel(stub)
    await model.start()
    await model.loadMoreIfNeeded(after: 3)
    #expect(model.nextPage == .failed)
    #expect(model.rows.map(\.userID) == [1, 2, 3])
    // The failed footer waits for 重试.
    await model.loadMoreIfNeeded(after: 3)
    #expect(await stub.pages == [1, 2])
    await model.retryMore()
    #expect(model.nextPage == .idle)
    #expect(model.rows.map(\.userID) == [1, 2, 3, 4, 5])
}

@MainActor @Test func lateAndStaleResultsAreDropped() async {
    let gate = SessionGate()
    let stub = ReadsStub(page: { call, page, _ in
        if call == 1 { await gate.wait(); return rosterPage(1...3, page: page) }
        return rosterPage(7...8, page: page)
    })
    let model = makeModel(stub)
    let first = Task { await model.start() }
    #expect(await eventually { await gate.arrived })
    await model.setReadState(.unread)
    #expect(model.rows.map(\.userID) == [7, 8])
    await gate.open()
    await first.value
    #expect(model.rows.map(\.userID) == [7, 8])

    // An ended session sends nothing, and what it asked for before ending is dropped.
    let flag = ReadsFlag()
    let ended = ReadsStub()
    flag.value = false
    await makeModel(ended, isCurrent: { flag.value }).start()
    #expect(await ended.pages.isEmpty)
    #expect(await ended.headerReads() == [0, 0])
    flag.value = true
    let held = SessionGate()
    let late = ReadsStub(page: { _, page, _ in await held.wait(); return rosterPage(1...2, page: page) },
                         title: { _ in await held.wait(); return Announcement(id: 31, title: "旧会话") },
                         summary: { _ in await held.wait(); return sampleSummary })
    let switching = makeModel(late, isCurrent: { flag.value })
    let task = Task { await switching.start() }
    #expect(await eventually { await late.pages == [1] })
    #expect(await eventually { await late.headerReads() == [1, 1] })
    flag.value = false
    await held.open()
    await task.value
    #expect(switching.rows.isEmpty)
    #expect(switching.title == nil && switching.summary == nil)
}

@MainActor @Test func notFoundShowsGoneAndInvalidFilterFails() async {
    let missing = ReadsStub(page: { _, _, _ in throw gone }, title: { _ in throw gone })
    let model = makeModel(missing)
    await model.start()
    #expect(model.isGone)
    #expect(model.rows.isEmpty)
    await model.reload()
    #expect(await missing.pages == [1])

    let invalid = ReadsStub(page: { call, page, _ in
        if call == 2 { throw invalidFilter }
        return rosterPage(1...3, page: page)
    })
    let filtered = makeModel(invalid)
    await filtered.start()
    await filtered.setReadState(.read)
    #expect(!filtered.isGone)
    #expect(filtered.state.failureReason == invalidFilter.localizedDescription)
    #expect(filtered.state.value == nil)
    // A 400 is the app's own mistake: it is not sent again on its own.
    try? await Task.sleep(for: .milliseconds(50))
    #expect(await invalid.pages == [1, 1])
}

@MainActor @Test func refreshFailureKeepsRows() async {
    let stub = ReadsStub(page: { call, page, _ in
        if call == 2 { throw failure }
        return rosterPage(1...3, page: page)
    })
    let model = makeModel(stub)
    await model.start()
    await model.reload()
    #expect(model.rows.map(\.userID) == [1, 2, 3])
    guard case .value(_, _, _, let updateFailed) = model.state.display else {
        Issue.record("rows dropped: \(model.state)")
        return
    }
    #expect(updateFailed)
    await model.reload()
    #expect(model.state.failureReason == nil)
}

/// What the stub sees of the query's search, as sent.
private enum AnnouncementQueryProbe {
    static func search(_ query: AnnouncementReadStatusQuery) -> String? {
        (try? query.queryItems(page: 1))?.first { $0.name == "search" }?.value
    }
}
