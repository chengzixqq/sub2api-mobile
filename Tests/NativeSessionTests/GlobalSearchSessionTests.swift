import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 60 §2.2 / §2.6 and S6D2b-03: debounce, cancellation, fan-out, the 30-second cache, single-section retry and 429 waits (S6-20).

private let requestIDText = "client:3f2504e0-4f89-41d3-9a0c-0305e82c3301"
private let badGateway = APIError.server(status: 502, reason: nil)

/// Answers each section from its script (the last step repeats, none means an empty page); a held section waits, and a
/// cancelled wait is counted and thrown.
private actor SearchStub: GlobalSearchSource {
    private(set) var requests: [GlobalSearchRequest] = []
    private(set) var cancelled: [SearchSection] = []
    private var held: Set<SearchSection>
    private let scripts: [SearchSection: [Result<SearchHits, any Error>]]
    init(holding held: Set<SearchSection> = [], scripts: [SearchSection: [Result<SearchHits, any Error>]] = [:]) {
        self.held = held; self.scripts = scripts
    }
    func hold(_ sections: Set<SearchSection>) { held.formUnion(sections) }
    func release(_ sections: Set<SearchSection>) { held.subtract(sections) }
    func releaseAll() { held = [] }
    func hits(for request: GlobalSearchRequest) async throws -> SearchHits {
        requests.append(request)
        let section = request.section, attempt = requests.filter { $0.section == section }.count
        while held.contains(section) {
            if Task.isCancelled { cancelled.append(section); throw CancellationError() }
            try? await Task.sleep(for: .milliseconds(1))
        }
        guard let script = scripts[section], !script.isEmpty else { return emptyHits(section) }
        return try script[min(attempt, script.count) - 1].get()
    }
}

/// Records each wait and returns only when woken.
private actor ManualSleeper {
    private(set) var requests: [Duration] = []
    private var waits: [CheckedContinuation<Void, Never>?] = []
    func sleep(_ duration: Duration) async {
        requests.append(duration)
        await withCheckedContinuation { waits.append($0) }
    }
    var count: Int { waits.count }
    func wake(_ index: Int) { waits[index]?.resume(); waits[index] = nil }
    func wakeAll() { for index in waits.indices { wake(index) } }
}

@MainActor private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
@MainActor private final class Identity {
    var me: AdminMe?
    var isCurrent = true
}

private func emptyHits(_ section: SearchSection) -> SearchHits {
    switch section {
    case .accounts: .accounts(AccountListPage(items: [], total: 0, page: 1, pageSize: 5, pages: 0))
    case .users: .users(Page(items: [], total: 0, page: 1, pageSize: 5, pages: 0))
    case .groups: .groups(Page(items: [], total: 0, page: 1, pageSize: 5, pages: 0))
    case .proxies: .proxies(Page(items: [], total: 0, page: 1, pageSize: 5, pages: 0))
    case .usage: .usage(Page(items: [], total: nil, page: 1, pageSize: 20, pages: nil, hasMore: false))
    case .errors: .errors(Page(items: [], total: 0, page: 1, pageSize: 20, pages: 0))
    }
}
private func accountHits(_ count: Int) -> SearchHits {
    let rows = (1...count).map { UpstreamAccount(id: $0, name: "账号 \($0)", platform: "openai", type: "oauth") }
    return .accounts(AccountListPage(items: rows, total: count, page: 1, pageSize: 5, pages: 1))
}
private func userHits(_ count: Int) -> SearchHits {
    .users(Page(items: (1...count).map { AdminUser(id: $0, email: "user\($0)@example.invalid") }, total: count, page: 1, pageSize: 5, pages: 1))
}
private func rateLimited(after seconds: Int) -> APIError {
    APIError(kind: .rateLimited, reason: "RATE_LIMITED", statusCode: 429, message: "请求过于频繁", retryAfter: seconds)
}

@MainActor private func makeSession(_ stub: SearchStub, _ sleeper: ManualSleeper, clock: TestClock = TestClock(),
                                    identity: Identity = Identity()) -> GlobalSearchSession {
    GlobalSearchSession(generation: UUID(), source: stub, me: { identity.me }, isCurrent: { identity.isCurrent }, now: { clock.now },
                        sleep: { await sleeper.sleep($0) })
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
private func waitForSleeps(_ sleeper: ManualSleeper, count: Int) async -> Bool { await eventually { await sleeper.requests.count >= count } }
/// For checks that something did not happen: lets the tasks run for a while first.
private func settle() async { try? await Task.sleep(for: .milliseconds(60)) }

/// One finished round of `text`: the debounce at `wait` woken and every planned section answered.
@MainActor private func finishRound(_ search: GlobalSearchSession, _ sleeper: ManualSleeper, wait index: Int) async -> Bool {
    guard await waitForSleeps(sleeper, count: index + 1) else { return false }
    await sleeper.wake(index)
    return await eventually { await search.results?.isSettled == true }
}

// MARK: Debounce and cancellation (60 §2.2)

@MainActor @Test func shortOrBlankTextSendsNothing() async {
    let stub = SearchStub(), sleeper = ManualSleeper()
    let search = makeSession(stub, sleeper)
    search.update(text: "a")
    search.update(text: "  ")
    await settle()
    #expect(await stub.requests.isEmpty)
    #expect(await sleeper.requests.isEmpty)
    #expect(search.plan == nil && search.results == nil && search.query == nil)
}

@MainActor @Test func debounceWaits300MillisecondsBeforeFanningOut() async throws {
    let stub = SearchStub(), sleeper = ManualSleeper()
    let search = makeSession(stub, sleeper)
    search.update(text: "alice")
    #expect(await waitForSleeps(sleeper, count: 1))
    #expect(await sleeper.requests == [.milliseconds(300)] && GlobalSearchSession.debounce == .milliseconds(300))
    #expect(await stub.requests.isEmpty)
    let results = try #require(search.results)
    #expect(results.phase == .results && results.visibleBlocks == [.accounts, .users, .groups, .proxies])
    #expect(results.visibleBlocks.allSatisfy { results.summary(of: $0).isSearching })
    await sleeper.wake(0)
    #expect(await eventually { await stub.requests.count == 4 })
    let plan = try #require(search.plan)
    let sent = await stub.requests
    #expect(Set(sent.map(\.section)) == [.accounts, .users, .groups, .proxies])
    #expect(sent.allSatisfy { plan.request(for: $0.section) == $0 })
}

@MainActor @Test func typingDuringTheDebounceSendsOnlyTheLastText() async {
    let stub = SearchStub(), sleeper = ManualSleeper()
    let search = makeSession(stub, sleeper)
    search.update(text: "ali")
    #expect(await waitForSleeps(sleeper, count: 1))
    search.update(text: "alice")
    #expect(await waitForSleeps(sleeper, count: 2))
    await sleeper.wake(0)
    await settle()
    #expect(await stub.requests.isEmpty)
    await sleeper.wake(1)
    #expect(await eventually { await stub.requests.count == 4 })
    let sent = await stub.requests
    #expect(sent.allSatisfy { search.plan?.request(for: $0.section) == $0 })
    #expect(search.query?.text == "alice")
}

@MainActor @Test func newInputCancelsEveryRequestOfThePreviousRound() async {
    let stub = SearchStub(holding: Set(SearchSection.allCases)), sleeper = ManualSleeper()
    let search = makeSession(stub, sleeper)
    search.update(text: requestIDText)
    #expect(await waitForSleeps(sleeper, count: 1))
    await sleeper.wake(0)
    #expect(await eventually { await stub.requests.count == 6 })
    search.update(text: "alice")
    #expect(await eventually { await stub.cancelled.count == 6 })
    await stub.releaseAll()
    await settle()
    #expect(search.results?.plan.query.text == "alice")
    #expect(search.results?.status(of: .usage) == .notSent && search.results?.status(of: .accounts) == .searching)
}

@MainActor @Test func sectionsAreSentConcurrentlyAndLandOneByOne() async {
    let stub = SearchStub(holding: Set(SearchSection.allCases), scripts: [.accounts: [.success(accountHits(2))]])
    let sleeper = ManualSleeper()
    let search = makeSession(stub, sleeper)
    search.update(text: requestIDText)
    #expect(await waitForSleeps(sleeper, count: 1))
    await sleeper.wake(0)
    #expect(await eventually { await stub.requests.count == 6 })
    await stub.release([.accounts])
    #expect(await eventually { await search.results?.status(of: .accounts) == .found(2) })
    #expect(SearchSection.allCases.dropFirst().allSatisfy { search.results?.status(of: $0) == .searching })
    #expect(search.results?.isSettled == false)
    await stub.releaseAll()
    #expect(await eventually { await search.results?.isSettled == true })
}

// MARK: Cache (60 §2.6)

@MainActor @Test func sameTrimmedTextDoesNotStartAgain() async {
    let stub = SearchStub(scripts: [.accounts: [.success(accountHits(1))]]), sleeper = ManualSleeper()
    let search = makeSession(stub, sleeper)
    search.update(text: "alice")
    #expect(await finishRound(search, sleeper, wait: 0))
    search.update(text: " alice ")
    await settle()
    #expect(await sleeper.requests.count == 1)
    #expect(await stub.requests.count == 4)
    #expect(search.results?.status(of: .accounts) == .found(1))
}

@MainActor @Test func sameQueryWithinThirtySecondsComesFromTheCache() async {
    let stub = SearchStub(scripts: [.accounts: [.success(accountHits(3))]]), sleeper = ManualSleeper(), clock = TestClock()
    let search = makeSession(stub, sleeper, clock: clock)
    search.update(text: "alice")
    #expect(await finishRound(search, sleeper, wait: 0))
    search.update(text: "")
    #expect(search.results == nil && search.plan == nil)
    clock.advance(29)
    search.update(text: "alice")
    #expect(search.results?.isSettled == true && search.results?.status(of: .accounts) == .found(3))
    await settle()
    #expect(await sleeper.requests.count == 1)
    #expect(await stub.requests.count == 4)
    search.update(text: "")
    clock.advance(1)
    search.update(text: "alice")
    #expect(search.results?.status(of: .accounts) == .searching)
    #expect(await finishRound(search, sleeper, wait: 1))
    #expect(await stub.requests.count == 8)
}

@MainActor @Test func aRoundWithAFailedSectionIsNotCached() async {
    let stub = SearchStub(scripts: [.users: [.failure(badGateway)]]), sleeper = ManualSleeper(), clock = TestClock()
    let search = makeSession(stub, sleeper, clock: clock)
    search.update(text: "alice")
    #expect(await finishRound(search, sleeper, wait: 0))
    #expect(search.results?.failedSections == [.users])
    search.update(text: "")
    clock.advance(1)
    search.update(text: "alice")
    #expect(await finishRound(search, sleeper, wait: 1))
    #expect(await stub.requests.count == 8)
}

// MARK: Retry and hidden sections (60 §2.5)

@MainActor @Test func retryResendsOnlyTheFailedSection() async throws {
    let stub = SearchStub(scripts: [.users: [.failure(badGateway), .success(userHits(1))], .accounts: [.success(accountHits(2))]])
    let sleeper = ManualSleeper()
    let search = makeSession(stub, sleeper)
    search.update(text: "alice")
    #expect(await finishRound(search, sleeper, wait: 0))
    search.retry([.accounts])
    await settle()
    #expect(await stub.requests.count == 4)
    await stub.hold([.users])
    search.retry([.users])
    #expect(search.results?.status(of: .users) == .searching && search.results?.status(of: .accounts) == .found(2))
    #expect(await eventually { await stub.requests.count == 5 })
    let plan = try #require(search.plan)
    #expect(await stub.requests.last == plan.request(for: .users))
    #expect(await sleeper.requests.count == 1)
    await stub.release([.users])
    #expect(await eventually { await search.results?.status(of: .users) == .found(1) })
    search.update(text: "")
    search.update(text: "alice")
    #expect(search.results?.status(of: .users) == .found(1))
    await settle()
    #expect(await stub.requests.count == 5)
}

@MainActor @Test func retryFailedResendsEveryFailedSection() async {
    let failing: [SearchSection: [Result<SearchHits, any Error>]] = [.accounts: [.failure(badGateway), .success(accountHits(1))],
                                                                     .users: [.failure(badGateway)], .groups: [.failure(badGateway)],
                                                                     .proxies: [.failure(badGateway)]]
    let stub = SearchStub(scripts: failing), sleeper = ManualSleeper()
    let search = makeSession(stub, sleeper)
    search.update(text: "alice")
    #expect(await finishRound(search, sleeper, wait: 0))
    #expect(search.results?.phase == .failed && search.results?.failureMessage != nil)
    await stub.hold(Set(SearchSection.allCases))
    search.retryFailed()
    #expect(search.results?.phase == .results)
    #expect([SearchBlock.accounts, .users, .groups, .proxies].allSatisfy { search.results?.summary(of: $0).isSearching == true })
    #expect(await eventually { await stub.requests.count == 8 })
    await stub.releaseAll()
    #expect(await eventually { await search.results?.isSettled == true })
    #expect(search.results?.status(of: .accounts) == .found(1) && search.results?.failedSections == [.users, .groups, .proxies])
}

@MainActor @Test func forbiddenAndOpsDisabledAnswersHideTheirSections() async {
    let stub = SearchStub(scripts: [.users: [.failure(APIError.server(status: 403, reason: "FORBIDDEN"))],
                                    .errors: [.failure(APIError.server(status: 404, reason: "OPS_DISABLED"))]])
    let sleeper = ManualSleeper()
    let search = makeSession(stub, sleeper)
    search.update(text: requestIDText)
    #expect(await finishRound(search, sleeper, wait: 0))
    #expect(search.results?.status(of: .users) == .hidden && search.results?.status(of: .errors) == .hidden)
    #expect(search.results?.failedSections.isEmpty == true && search.results?.phase == .empty)
    search.update(text: "")
    search.update(text: requestIDText)
    await settle()
    #expect(await stub.requests.count == 6)
    #expect(search.results?.status(of: .users) == .hidden)
}

// MARK: Late answers (session generation and tickets)

@MainActor @Test func answersAfterTheSessionEndedAreDropped() async {
    let stub = SearchStub(holding: Set(SearchSection.allCases)), sleeper = ManualSleeper(), identity = Identity()
    let search = makeSession(stub, sleeper, identity: identity)
    search.update(text: "alice")
    #expect(await waitForSleeps(sleeper, count: 1))
    await sleeper.wake(0)
    #expect(await eventually { await stub.requests.count == 4 })
    identity.isCurrent = false
    await stub.releaseAll()
    await settle()
    #expect(search.results?.status(of: .accounts) == .searching && search.results?.isSettled == false)
    search.update(text: "bob")
    await settle()
    #expect(search.results == nil)
    #expect(await sleeper.requests.count == 1)
    #expect(await stub.requests.count == 4)
}

@MainActor @Test func aRetryAnswerAfterNewInputIsDropped() async {
    let stub = SearchStub(scripts: [.users: [.failure(badGateway), .success(userHits(2))]]), sleeper = ManualSleeper()
    let search = makeSession(stub, sleeper)
    search.update(text: "alice")
    #expect(await finishRound(search, sleeper, wait: 0))
    await stub.hold([.users])
    search.retry([.users])
    #expect(await eventually { await stub.requests.count == 5 })
    search.update(text: "bob")
    await stub.release([.users])
    await settle()
    #expect(search.query?.text == "bob" && search.results?.status(of: .users) == .searching)
}

@MainActor @Test func planReadsTheIdentityAtEachInput() async throws {
    let identity = Identity()
    identity.me = AdminMe(workspace: AdminMe.Workspace(id: 2, permissions: AdminMe.WorkspacePermissions(monitorView: true)))
    let stub = SearchStub(), sleeper = ManualSleeper()
    let search = makeSession(stub, sleeper, identity: identity)
    search.update(text: requestIDText)
    #expect(search.plan?.sections == [.accounts, .groups, .usage] && search.plan?.showsVendorNote == true)
    #expect(await finishRound(search, sleeper, wait: 0))
    let first = await stub.requests
    #expect(Set(first.map(\.section)) == [.accounts, .groups, .usage])
    identity.me = AdminMe(features: AdminMe.Features(opsMonitoringEnabled: true),
                          server: AdminMe.Server(capabilities: [Capability.apiKeysMaskedView.rawValue]))
    search.update(text: requestIDText)
    #expect(search.plan?.sections == SearchSection.allCases && search.plan?.maskedView == true)
    #expect(await finishRound(search, sleeper, wait: 1))
    let sent = await stub.requests
    #expect(sent.count == 9)
    let usage = try #require(sent.dropFirst(3).first { $0.section == .usage })
    guard case .usage(_, _, let maskedView) = usage else { Issue.record("不是使用记录请求"); return }
    #expect(maskedView)
}

// MARK: 429 (00 §2.7.2, S6D2b-03)

@MainActor @Test func aRateLimitedSectionWaitsAndIsResentOnceForTheCurrentQuery() async throws {
    let stub = SearchStub(scripts: [.users: [.failure(rateLimited(after: 5)), .success(userHits(1))]])
    let sleeper = ManualSleeper(), clock = TestClock()
    let search = makeSession(stub, sleeper, clock: clock)
    search.update(text: "alice")
    #expect(await finishRound(search, sleeper, wait: 0))
    #expect(await waitForSleeps(sleeper, count: 2))
    #expect(await sleeper.requests[1] == .seconds(5))
    #expect(search.throttle(for: .users).throttleMessage(at: clock.now) == "请求过于频繁，5 秒后自动重试")
    #expect(search.results?.status(of: .users) == .failed && search.throttle(for: .accounts).throttleMessage(at: clock.now) == nil)
    search.retry([.users])
    search.retryFailed()
    await settle()
    #expect(await stub.requests.count == 4)
    // A new query during the wait sends every other section and lands users as failed; that round is not cached.
    search.update(text: "bob")
    #expect(search.results?.status(of: .users) == .failed)
    #expect(await finishRound(search, sleeper, wait: 2))
    #expect(await stub.requests.count == 7)
    #expect(search.results?.failedSections == [.users])
    search.update(text: "")
    search.update(text: "bob")
    #expect(await finishRound(search, sleeper, wait: 3))
    #expect(await stub.requests.count == 10)
    // The wait ends: users goes once, for bob.
    await sleeper.wake(1)
    #expect(await eventually { await search.results?.status(of: .users) == .found(1) })
    let plan = try #require(search.plan)
    #expect(await stub.requests.count == 11)
    #expect(await stub.requests.last == plan.request(for: .users))
    #expect(search.throttles.isEmpty && search.results?.failedSections.isEmpty == true)
}

@MainActor @Test func aWaitThatEndsAfterTheSessionSendsNothing() async {
    let stub = SearchStub(scripts: [.users: [.failure(rateLimited(after: 5))]]), sleeper = ManualSleeper(), identity = Identity()
    let search = makeSession(stub, sleeper, identity: identity)
    search.update(text: "alice")
    #expect(await finishRound(search, sleeper, wait: 0))
    #expect(await waitForSleeps(sleeper, count: 2))
    identity.isCurrent = false
    await sleeper.wake(1)
    await settle()
    #expect(await stub.requests.count == 4)
}

// MARK: The client source (S4D1-06)

@Test func clientSourceSendsKeyViewOnlyWithTheMaskedViewCapability() async throws {
    for masked in [true, false] {
        let transport = SessionTransport { request in
            request.url!.path.contains("/ops/")
                ? sessionOK(#"{"items":[],"total":0,"page":1,"page_size":20}"#)
                : sessionOK(#"{"items":[],"total":null,"page":1,"page_size":20,"has_more":false}"#)
        }
        let source = ClientGlobalSearchSource(client: sessionClient(transport))
        let me = AdminMe(server: AdminMe.Server(capabilities: masked ? [Capability.apiKeysMaskedView.rawValue] : []))
        let plan = try #require(GlobalSearchQuery(requestIDText)).plan(me: me)
        _ = try await source.hits(for: try #require(plan.request(for: .usage)))
        _ = try await source.hits(for: try #require(plan.request(for: .errors)))
        let requests = await transport.requests
        #expect(requests.map { $0.url?.path } == ["/api/v1/admin/usage", "/api/v1/admin/ops/request-errors"])
        let keyViews = requests.map { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "key_view" }?.value
        }
        #expect(keyViews == [masked ? "masked" : nil, nil])
    }
}
