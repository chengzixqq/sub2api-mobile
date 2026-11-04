import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 60 §2.1 / §2.3 / §2.6: the “查看全部” page's reads and where search rows go (S6-21).

private let failure = APIError.server(status: 500, reason: nil)

/// Answers each page number from its script (the last step repeats); a held page waits until released.
private actor PageStub {
    private(set) var asked: [Int] = []
    private var held: Set<Int> = []
    private let scripts: [Int: [Result<SearchHitPage, any Error>]]
    init(_ scripts: [Int: [Result<SearchHitPage, any Error>]]) { self.scripts = scripts }
    func hold(_ page: Int) { held.insert(page) }
    func release(_ page: Int) { held.remove(page) }
    func page(_ number: Int) async throws -> SearchHitPage {
        asked.append(number)
        while held.contains(number) { try? await Task.sleep(for: .milliseconds(1)) }
        let script = scripts[number] ?? [.failure(failure)], attempt = asked.filter { $0 == number }.count
        return try script[min(attempt, script.count) - 1].get()
    }
}

/// Records each request and answers every kind with a page of three; only `hits(for:)` exists (S6D2b-04).
private actor ListPageStubSource: GlobalSearchSource {
    private(set) var requests: [GlobalSearchRequest] = []
    func hits(for request: GlobalSearchRequest) async throws -> SearchHits {
        requests.append(request)
        switch request.section {
        case .accounts:
            let rows = (21...23).map { UpstreamAccount(id: $0, name: "账号 \($0)", platform: "openai", type: "oauth") }
            return .accounts(AccountListPage(items: rows, total: 43, page: 2, pageSize: 20, pages: 3))
        case .users: return .users(Page(items: (21...23).map { AdminUser(id: $0, email: "user\($0)@example.invalid") }, total: 23, page: 2, pageSize: 20, pages: 2))
        case .groups: return .groups(Page(items: (21...23).map { AdminGroup(id: $0, name: "分组 \($0)") }, total: 43, page: 2, pageSize: 20, pages: 3))
        case .proxies: return .proxies(Page(items: (21...23).map { AdminProxy(id: $0, name: "代理 \($0)") }, total: 23, page: 2, pageSize: 20, pages: 2))
        case .usage, .errors: throw failure
        }
    }
}

private func query(_ text: String) -> GlobalSearchQuery { GlobalSearchQuery(text)! }
private func userPage(_ ids: ClosedRange<Int>, page: Int, hasMore: Bool, total: Int? = 26) -> SearchHitPage {
    SearchHitPage(hits: ids.map { .user(AdminUser(id: $0, email: "user\($0)@example.invalid")) }, total: total, page: page, hasMore: hasMore)
}
private let firstPage = userPage(1...20, page: 1, hasMore: true)
private let secondPage = userPage(21...26, page: 2, hasMore: false)

@MainActor private func makeModel(_ stub: PageStub) -> SearchResultsListModel {
    SearchResultsListModel(kind: .users, query: query("example"), fetch: { try await stub.page($0) })
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
private func decoded<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value { try JSONDecoder().decode(type, from: Data(json.utf8)) }

@MainActor @Test func firstLoadShowsFirstPage() async {
    let stub = PageStub([1: [.success(firstPage)]])
    let model = makeModel(stub)
    #expect(model.subtitle == "搜索“example”")
    await model.load()

    #expect(model.hits.count == 20)
    #expect(model.subtitle == "搜索“example” · 26 个")
    #expect(model.nextPage == .idle)
    #expect(model.emptyText == "没有匹配“example”的用户")
    #expect(await stub.asked == [1])
    guard case .value(let snapshot, _, false, false) = model.state.display else { Issue.record("not loaded"); return }
    #expect(snapshot.hasMore)
}

@MainActor @Test func firstLoadFailureWithoutRowsIsFailed() async {
    let stub = PageStub([1: [.failure(failure)]])
    let model = makeModel(stub)
    await model.load()

    guard case .failed(let reason) = model.state.display else { Issue.record("not failed"); return }
    #expect(reason == failure.localizedDescription)
    #expect(model.hits.isEmpty)
    #expect(model.subtitle == "搜索“example”")
}

@MainActor @Test func nextPageAppendsAndStopsAtLastPage() async {
    let stub = PageStub([1: [.success(firstPage)], 2: [.success(secondPage)]])
    let model = makeModel(stub)
    await model.load()
    await model.loadNextPage()

    #expect(model.hits.map(\.objectID) == Array(1...26))
    #expect(model.state.value?.hasMore == false)
    #expect(model.nextPage == .idle)
    await model.loadNextPage()
    #expect(await stub.asked == [1, 2])
}

@MainActor @Test func nextPageFailureKeepsRowsAndRetries() async {
    let stub = PageStub([1: [.success(firstPage)], 2: [.failure(failure), .success(secondPage)]])
    let model = makeModel(stub)
    await model.load()
    await model.loadNextPage()

    #expect(model.nextPage == .failed)
    #expect(model.hits.count == 20)
    await model.loadNextPage()
    #expect(await stub.asked == [1, 2])
    await model.retryNextPage()
    #expect(model.hits.count == 26)
    #expect(model.nextPage == .idle)
}

@MainActor @Test func pullToRefreshReplacesRowsAndDropsLateNextPage() async {
    let stub = PageStub([1: [.success(firstPage)], 2: [.success(secondPage)]])
    let model = makeModel(stub)
    await model.load()
    await model.loadNextPage()
    #expect(model.hits.count == 26)

    await model.load()
    #expect(model.hits.count == 20)
    #expect(model.state.value?.page == 1)

    await stub.hold(2)
    let late = Task { await model.loadNextPage() }
    #expect(await eventually { await stub.asked.count == 4 })
    await model.load()
    await stub.release(2)
    await late.value
    #expect(model.hits.count == 20)
    #expect(model.state.value?.page == 1)
    #expect(model.nextPage == .idle)
}

@MainActor @Test func searchListRefreshFailureKeepsRows() async {
    let stub = PageStub([1: [.success(firstPage), .failure(failure)]])
    let model = makeModel(stub)
    await model.load()
    await model.load()

    guard case .value(let snapshot, _, false, true) = model.state.display else { Issue.record("rows not kept"); return }
    #expect(snapshot.hits.count == 20)
    #expect(model.subtitle == "搜索“example” · 26 个")
}

@Test func listPageSendsKindRequestsWithPageSize20() async throws {
    let source = ListPageStubSource(), q = query("example")
    let accounts = try await source.listPage(.accounts, query: q, page: 2)
    let users = try await source.listPage(.users, query: q, page: 2)
    let groups = try await source.listPage(.groups, query: q, page: 2)
    let proxies = try await source.listPage(.proxies, query: q, page: 2)

    #expect(await source.requests == SearchResultKind.allCases.map { $0.request(q, page: 2) })
    #expect(accounts.page == 2 && accounts.total == 43 && accounts.hasMore)
    #expect(users.page == 2 && users.total == 23 && !users.hasMore)
    #expect(groups.total == 43 && groups.hasMore)
    #expect(proxies.total == 23 && !proxies.hasMore)
    #expect(accounts.hits.map(\.id) == ["account-21", "account-22", "account-23"])
    #expect(users.hits.map(\.id) == ["user-21", "user-22", "user-23"])
    #expect(groups.hits.map(\.id) == ["group-21", "group-22", "group-23"])
    #expect(proxies.hits.map(\.id) == ["proxy-21", "proxy-22", "proxy-23"])
    if case .users(let sent)? = await source.requests.dropFirst().first {
        #expect(sent.pageSize == 20 && sent.page == 2 && sent.search == "example")
    } else { Issue.record("no users request") }
}

@Test func hitRoutesMatchSpecDestinations() throws {
    let usage = try decoded(UsageRequestRecord.self, #"{"id":12,"request_id":"client:12","created_at":"2026-10-16T08:00:00Z","model":"gpt-4.1","user_id":1,"account_id":4,"api_key_id":9}"#)
    let error = try decoded(RequestErrorRecord.self, #"{"id":13,"created_at":"2026-10-16T08:00:00Z","request_id":"req-13","phase":"upstream","type":"upstream_error","status_code":502,"platform":"openai","model":"gpt-4.1","resolved":false,"message":"Upstream error"}"#)

    if case .account(let id, nil, let preload?) = SearchHit.account(UpstreamAccount(id: 3, name: "账号 3", platform: "openai", type: "oauth")).route {
        #expect(id == 3 && preload.value.id == 3)
    } else { Issue.record("account route") }
    #expect(SearchHit.user(AdminUser(id: 4, email: "user4@example.invalid")).route == .user(id: 4))
    #expect(SearchHit.group(AdminGroup(id: 5, name: "分组 5")).route == .group(id: 5))
    #expect(SearchHit.proxy(AdminProxy(id: 6, name: "代理 6")).route == .proxyDetail(id: 6))
    if case .request(.usage(let preload)) = SearchHit.usage(usage).route { #expect(preload.value.id == 12) } else { Issue.record("usage route") }
    if case .request(.error(let id, .request, let initial?)) = SearchHit.error(error).route {
        #expect(id == 13 && initial.value.id == 13)
    } else { Issue.record("error route") }
}

// MARK: - Suspend and 429 (00 §4.6 D18, 00 §2.7.2)

private let rateLimited = APIError.server(status: 429, envelope: nil, retryAfter: 5)

@MainActor private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
@MainActor private func makeModel(_ stub: PageStub, clock: TestClock) -> SearchResultsListModel {
    SearchResultsListModel(kind: .users, query: query("example"), fetch: { try await stub.page($0) }, now: { clock.now })
}

@MainActor @Test func searchListFirstPageCutOffGoesOutAgainOnForeground() async {
    let stub = PageStub([1: [.failure(CancellationError()), .success(firstPage)]])
    let model = makeModel(stub)
    await model.load()
    guard case .placeholder = model.state.display else { Issue.record("not back to the placeholder"); return }

    await model.foregroundResumed()
    #expect(model.hits.count == 20)
    #expect(await stub.asked == [1, 1])
}

@MainActor @Test func searchListNextPageCutOffGoesOutAgainOnForeground() async {
    let stub = PageStub([1: [.success(firstPage)], 2: [.failure(CancellationError()), .success(secondPage)]])
    let model = makeModel(stub)
    await model.load()
    await model.loadNextPage()
    #expect(model.nextPage == .idle)

    await model.foregroundResumed()
    #expect(model.hits.count == 26)
    #expect(await stub.asked == [1, 2, 2])
}

@MainActor @Test func searchListForegroundReadsNothingWithoutACutOffRead() async {
    let stub = PageStub([1: [.success(firstPage)], 2: [.failure(failure)]])
    let model = makeModel(stub)
    await model.load()
    await model.loadNextPage()

    await model.foregroundResumed()
    #expect(model.nextPage == .failed)
    #expect(await stub.asked == [1, 2])
}

@MainActor @Test func searchListFirstPage429WaitsThenReadsOnce() async {
    let clock = TestClock()
    let stub = PageStub([1: [.failure(rateLimited), .success(firstPage)]])
    let model = makeModel(stub, clock: clock)
    await model.load()
    #expect(model.throttleMessage() == "请求过于频繁，5 秒后自动重试")

    await model.load()
    await model.resumeAfterWait()
    #expect(await stub.asked == [1])

    clock.advance(5)
    await model.resumeAfterWait()
    #expect(model.hits.count == 20)
    #expect(model.throttleMessage() == nil)
    await model.resumeAfterWait()
    #expect(await stub.asked == [1, 1])
}

@MainActor @Test func searchListNextPage429HoldsEveryReadUntilTheWaitEnds() async {
    let clock = TestClock()
    let stub = PageStub([1: [.success(firstPage)], 2: [.failure(rateLimited), .success(secondPage)]])
    let model = makeModel(stub, clock: clock)
    await model.load()
    await model.loadNextPage()
    #expect(model.nextPage == .failed)
    #expect(model.throttleMessage() == "请求过于频繁，5 秒后自动重试")

    await model.retryNextPage()
    await model.load()
    await model.resumeAfterWait()
    #expect(await stub.asked == [1, 2])
    #expect(model.hits.count == 20)

    clock.advance(5)
    await model.resumeAfterWait()
    #expect(model.hits.count == 26)
    #expect(model.nextPage == .idle)
    #expect(await stub.asked == [1, 2, 2])
}
