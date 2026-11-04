import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Records every read and probe and answers through closures; `call` counts list reads from 1. `inFlight` and `peak` count
/// the probes waiting in `onTest`.
private actor StubProxySource: ProxySource {
    typealias PageHandler = @Sendable (_ call: Int, _ page: Int) async throws -> Page<AdminProxy>
    typealias TestHandler = @Sendable (_ id: Int) async throws -> ProxyTestResult
    private let onPage: PageHandler
    private let onTest: TestHandler
    private(set) var pages: [Int] = []
    private(set) var queries: [ProxyListQuery] = []
    private(set) var tested: [Int] = []
    private(set) var inFlight = 0
    private(set) var peak = 0

    init(page: @escaping PageHandler = { _, page in proxyPage(sampleProxies, page: page) },
         test: @escaping TestHandler = { id in ProxyTestResult(success: true, latencyMs: 100 + id, checkedAt: probeTime) }) {
        onPage = page; onTest = test
    }
    func proxies(page: Int, query: ProxyListQuery) async throws -> Page<AdminProxy> {
        pages.append(page); queries.append(query)
        return try await onPage(pages.count, page)
    }
    func testProxy(id: Int) async throws -> ProxyTestResult {
        tested.append(id); inFlight += 1; peak = max(peak, inFlight)
        defer { inFlight -= 1 }
        return try await onTest(id)
    }
}

/// Holds each probe until its id is opened; an id opened early passes straight through.
private actor Valve {
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var opened = Set<Int>()
    var waiting: Set<Int> { Set(waiters.keys) }
    func wait(_ id: Int) async {
        if opened.contains(id) { return }
        await withCheckedContinuation { waiters[id] = $0 }
    }
    func open(_ ids: [Int]) {
        for id in ids { opened.insert(id); waiters.removeValue(forKey: id)?.resume() }
    }
}

@MainActor private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor private final class TestFlag { var value = true }

private let probeTime = Date(timeIntervalSince1970: 1_800_000_500)
private let failure = APIError.server(status: 502, reason: nil)

private func proxy(_ id: Int, name: String? = nil, status: String = "active", accounts: Int = 1, latency: Int? = 180,
                   checkedAt: Date? = Date(timeIntervalSince1970: 1_799_990_000)) -> AdminProxy {
    AdminProxy(id: id, name: name ?? "proxy-\(id)", scheme: "socks5", host: "203.0.113.\(id)", port: 1080, status: status, accountCount: accounts,
               hasAccountCountKey: true, latencyMs: latency, latencyStatus: latency == nil ? nil : "success", latencyCheckedAt: latency == nil ? nil : checkedAt,
               ipAddress: "198.51.100.\(id)", countryCode: "HK", qualityScore: 90, qualityGrade: "A")
}
private let sampleProxies = (1...3).reversed().map { proxy($0) }

/// `items` cut into pages of `size`; `pages` tells whether more follow.
private func proxyPage(_ items: [AdminProxy], page: Int, size: Int = 200, total: Int? = nil) -> Page<AdminProxy> {
    let pages = max(1, (items.count + size - 1) / size)
    return Page(items: Array(items.dropFirst((page - 1) * size).prefix(size)), total: total ?? items.count, page: page, pageSize: size, pages: pages)
}

@MainActor private func makeStore(_ stub: StubProxySource, clock: TestClock = TestClock(),
                                  isCurrent: @escaping @MainActor () -> Bool = { true }) -> ProxyStore {
    ProxyStore(generation: UUID(), source: stub, isCurrent: isCurrent, now: { clock.now })
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

@MainActor @Test func reloadAsksForTheCatalogQueryFromPageOne() async throws {
    let stub = StubProxySource()
    await makeStore(stub).reload()
    #expect(await stub.pages == [1])
    let query = try #require(await stub.queries.first)
    #expect(query == ProxyListQuery())
    let items = try query.queryItems(page: 1).map { "\($0.name)=\($0.value ?? "")" }
    #expect(items == ["page=1", "page_size=200", "sort_by=id", "sort_order=desc"])

    let ended = StubProxySource()
    let store = makeStore(ended, isCurrent: { false })
    await store.reload()
    #expect(await ended.pages.isEmpty)
    #expect(store.state == .idle)
}

@MainActor @Test func reloadFollowsEveryPageIntoOneCompleteCatalog() async {
    let rows = (1...5).reversed().map { proxy($0) }
    // Page 2 repeats id 3 (a row inserted meanwhile shifted the pages); only its first copy stays.
    let stub = StubProxySource(page: { _, page in
        switch page {
        case 1: Page(items: Array(rows[0...1]), total: 5, page: 1, pageSize: 2, pages: 3)
        case 2: Page(items: [rows[2], rows[2]], total: 5, page: 2, pageSize: 2, pages: 3)
        default: Page(items: Array(rows[3...4]), total: 5, page: 3, pageSize: 2, pages: 3)
        }
    })
    let clock = TestClock()
    let store = makeStore(stub, clock: clock)
    await store.reload()
    #expect(await stub.pages == [1, 2, 3])
    #expect(store.state == .loaded(ProxyCatalog(proxies: rows, total: 5, isComplete: true), at: clock.now))
    #expect(store.proxies.map(\.id) == [5, 4, 3, 2, 1])
    #expect(store.catalog?.count == 5)

    // `has_more` stays true but a page comes back empty: the end.
    let endless = StubProxySource(page: { _, page in
        Page(items: page == 1 ? [proxy(1)] : [], total: nil, page: page, pageSize: 200, pages: nil, hasMore: true)
    })
    let stopped = makeStore(endless)
    await stopped.reload()
    #expect(await endless.pages == [1, 2])
    #expect(stopped.catalog?.isComplete == true)
    #expect(stopped.catalog?.count == 1)

    // A server that never stops is read at most 50 pages.
    let runaway = StubProxySource(page: { call, page in
        Page(items: [proxy(call)], total: nil, page: page, pageSize: 200, pages: nil, hasMore: true)
    })
    let capped = makeStore(runaway)
    await capped.reload()
    #expect(await runaway.pages.count == ProxyStore.maxPages)
    #expect(capped.proxies.count == ProxyStore.maxPages)
}

@MainActor @Test func firstLoadShowsPartialPagesAndKeepsThemWhenALaterPageFails() async {
    let gate = SessionGate()
    let rows = (1...4).reversed().map { proxy($0) }
    let stub = StubProxySource(page: { call, page in
        if page == 2, call == 2 { await gate.wait(); throw failure }
        return proxyPage(rows, page: page, size: 2)
    })
    let clock = TestClock()
    let store = makeStore(stub, clock: clock)
    let task = Task { await store.reload() }
    #expect(await eventually { await gate.arrived })
    let partial = ProxyCatalog(proxies: Array(rows[0...1]), total: 4, isComplete: false)
    #expect(store.state == .loading(previous: partial, at: clock.now))
    #expect(store.state.display == .value(partial, at: clock.now, isRefreshing: true, updateFailed: false))
    await gate.open()
    await task.value
    #expect(store.state.value == partial)
    #expect(store.state.display == .value(partial, at: clock.now, isRefreshing: false, updateFailed: true))
    #expect(store.state.failureReason?.isEmpty == false)

    // 加载失败 · 重试 starts over from page 1.
    await store.reload()
    #expect(await stub.pages == [1, 2, 1, 2])
    #expect(store.catalog == ProxyCatalog(proxies: rows, total: 4, isComplete: true))
    #expect(store.state.failureReason == nil)

    let broken = StubProxySource(page: { _, _ in throw failure })
    let empty = makeStore(broken)
    await empty.reload()
    guard case .failed(let reason) = empty.state.display else { Issue.record("\(empty.state.display)"); return }
    #expect(reason?.isEmpty == false)
}

@MainActor @Test func refreshFailureKeepsThePreviousCompleteCatalog() async {
    let gate = SessionGate()
    let old = (1...4).reversed().map { proxy($0) }
    let renamed = old.map { proxy($0.id, name: "new-\($0.id)") }
    let stub = StubProxySource(page: { call, page in
        if call <= 2 { return proxyPage(old, page: page, size: 2) }
        if page == 2 { await gate.wait(); throw failure }
        return proxyPage(renamed, page: page, size: 2)
    })
    let clock = TestClock()
    let store = makeStore(stub, clock: clock)
    await store.reload()
    let loadedAt = clock.now
    let complete = ProxyCatalog(proxies: old, total: 4, isComplete: true)
    clock.advance(120)
    let task = Task { await store.reload() }
    #expect(await eventually { await gate.arrived })
    // Page 1 of the refresh never replaces the shown catalog.
    #expect(store.state == .loading(previous: complete, at: loadedAt))
    await gate.open()
    await task.value
    guard case .failed(let reason, let previous, let at) = store.state else { Issue.record("\(store.state)"); return }
    #expect(reason?.isEmpty == false)
    #expect(previous == complete)
    #expect(at == loadedAt)
}

@MainActor @Test func ensureFreshReloadsOnlyWhenNeeded() async {
    let clock = TestClock()
    let stub = StubProxySource()
    let store = makeStore(stub, clock: clock)
    await store.ensureFresh()
    #expect(await stub.pages.count == 1)
    clock.advance(59)
    await store.ensureFresh()
    #expect(await stub.pages.count == 1)
    clock.advance(1)
    await store.ensureFresh()
    #expect(await stub.pages.count == 2)

    // A failed read, or a catalog still missing pages, reads at once.
    let failing = StubProxySource(page: { call, page in
        if call == 1 { throw failure }
        return proxyPage((1...4).reversed().map { proxy($0) }, page: page, size: 2)
    })
    let retried = makeStore(failing, clock: clock)
    await retried.ensureFresh()
    await retried.ensureFresh()
    #expect(await failing.pages == [1, 1, 2])
    #expect(retried.catalog?.isComplete == true)

    let partialStub = StubProxySource(page: { call, page in
        if call == 2 { throw failure }
        return proxyPage((1...4).reversed().map { proxy($0) }, page: page, size: 2)
    })
    let partial = makeStore(partialStub, clock: clock)
    await partial.reload()
    #expect(partial.catalog?.isComplete == false)
    await partial.ensureFresh()
    #expect(await partialStub.pages == [1, 2, 1, 2])

    // While a read runs, no second one goes out.
    let gate = SessionGate()
    let slow = StubProxySource(page: { _, page in await gate.wait(); return proxyPage(sampleProxies, page: page) })
    let waiting = makeStore(slow, clock: clock)
    let task = Task { await waiting.ensureFresh() }
    #expect(await eventually { await gate.arrived })
    await waiting.ensureFresh()
    #expect(await slow.pages == [1])
    await gate.open()
    await task.value
    #expect(waiting.catalog?.isComplete == true)
}

@MainActor @Test func supersededLoadsAndEndedSessionsAreDropped() async {
    let gate = SessionGate()
    let stub = StubProxySource(page: { call, page in
        if call == 1 { await gate.wait(); return proxyPage([proxy(9, name: "stale")], page: page) }
        return proxyPage(sampleProxies, page: page)
    })
    let store = makeStore(stub)
    let first = Task { await store.reload() }
    #expect(await eventually { await gate.arrived })
    await store.reload()
    await gate.open()
    await first.value
    #expect(store.proxies.map(\.id) == [3, 2, 1])
    #expect(store.state.isLoading == false)

    // D13: a page answered after the session ended changes nothing.
    let flag = TestFlag()
    let late = SessionGate()
    let ending = StubProxySource(page: { _, page in await late.wait(); return proxyPage(sampleProxies, page: page) })
    let ended = makeStore(ending, isCurrent: { flag.value })
    let task = Task { await ended.reload() }
    #expect(await eventually { await late.arrived })
    let before = ended.state
    flag.value = false
    await late.open()
    await task.value
    #expect(ended.state == before)
    #expect(ended.catalog == nil)

    // A cancelled refresh goes back to the last catalog; a cancelled first load to nothing.
    let clock = TestClock()
    let cancelling = StubProxySource(page: { call, page in
        if call == 2 { throw CancellationError() }
        return proxyPage(sampleProxies, page: page)
    })
    let kept = makeStore(cancelling, clock: clock)
    await kept.reload()
    let loadedAt = clock.now
    clock.advance(30)
    await kept.reload()
    #expect(kept.state == .loaded(ProxyCatalog(proxies: sampleProxies, total: 3, isComplete: true), at: loadedAt))
    let never = makeStore(StubProxySource(page: { _, _ in throw CancellationError() }))
    await never.reload()
    #expect(never.state == .idle)
}

@MainActor @Test func testAllKeepsAtMostFourRequestsInFlight() async {
    let valve = Valve()
    let rows = (1...9).reversed().map { proxy($0) }
    let stub = StubProxySource(page: { _, page in proxyPage(rows, page: page) }, test: { id in
        await valve.wait(id)
        return ProxyTestResult(success: true, latencyMs: 100 + id, checkedAt: probeTime)
    })
    let store = makeStore(stub)
    await store.reload()
    let task = Task { await store.testAll() }
    var released = 0
    while released < rows.count {
        let expected = min(ProxyStore.maxConcurrentTests, rows.count - released)
        #expect(await eventually {
            let waiting = await valve.waiting, testing = await store.testing
            return waiting.count == expected && testing == waiting
        })
        #expect(store.isTestingAll)
        guard let next = await valve.waiting.min() else { break }
        await valve.open([next])
        released += 1
    }
    let summary = await task.value
    #expect(summary == ProxyTestSummary(tested: 9, failed: 0))
    #expect(await stub.peak == ProxyStore.maxConcurrentTests)
    #expect(await stub.tested.sorted() == Array(1...9))
    #expect(store.testing.isEmpty)
    #expect(store.isTestingAll == false)
}

@MainActor @Test func testAllWritesEachResultBackAndCountsFailures() async {
    let rows = [proxy(3), proxy(2, latency: 95), proxy(1, latency: nil)]
    let reachable = ProxyTestResult(success: true, message: "Proxy is accessible", latencyMs: 120, ipAddress: "192.0.2.1", city: "Tokyo",
                                    country: "Japan", countryCode: "JP", checkedAt: probeTime)
    let unreachable = ProxyTestResult(success: false, message: "dial tcp: i/o timeout", checkedAt: probeTime)
    let stub = StubProxySource(page: { _, page in proxyPage(rows, page: page) }, test: { id in
        switch id {
        case 3: reachable
        case 2: unreachable
        default: throw failure
        }
    })
    let store = makeStore(stub)
    await store.reload()
    let loadedAt = store.state.updatedAt
    let summary = await store.testAll()
    #expect(summary == ProxyTestSummary(tested: 3, failed: 2))
    let updated = store.proxy(id: 3)
    #expect(updated == rows[0].applying(reachable))
    #expect(updated?.latencyStatus == "success" && updated?.latencyMs == 120 && updated?.ipAddress == "192.0.2.1")
    #expect(updated?.countryCode == "JP" && updated?.latencyCheckedAt == probeTime)
    #expect(updated?.accountCount == 1 && updated?.qualityGrade == "A")
    let failed = store.proxy(id: 2)
    #expect(failed == rows[1].applying(unreachable))
    #expect(failed?.latencyStatus == "failed" && failed?.latencyMessage == "dial tcp: i/o timeout")
    // 12.4: the row whose request failed keeps what it had.
    #expect(store.proxy(id: 1) == rows[2])
    #expect(store.proxies.map(\.id) == [3, 2, 1])
    #expect(store.state.updatedAt == loadedAt)
    #expect(store.state.isLoading == false)
}

@MainActor @Test func testAllGuards() async {
    // Nothing loaded, an empty catalog, or one still missing pages: nothing is probed.
    let idle = StubProxySource()
    #expect(await makeStore(idle).testAll() == nil)
    let none = StubProxySource(page: { _, page in proxyPage([], page: page) })
    let empty = makeStore(none)
    await empty.reload()
    #expect(await empty.testAll() == nil)
    let partialStub = StubProxySource(page: { call, page in
        if call == 2 { throw failure }
        return proxyPage((1...4).reversed().map { proxy($0) }, page: page, size: 2)
    })
    let partial = makeStore(partialStub)
    await partial.reload()
    #expect(await partial.testAll() == nil)
    #expect(await idle.tested.isEmpty)
    #expect(await none.tested.isEmpty)
    #expect(await partialStub.tested.isEmpty)

    // A second 全部测试 while one runs; the session ending midway.
    let valve = Valve()
    let rows = (1...6).reversed().map { proxy($0) }
    let flag = TestFlag()
    let stub = StubProxySource(page: { _, page in proxyPage(rows, page: page) }, test: { id in
        await valve.wait(id)
        return ProxyTestResult(success: false, message: "refused", checkedAt: probeTime)
    })
    let store = makeStore(stub, isCurrent: { flag.value })
    await store.reload()
    let running = Task { await store.testAll() }
    #expect(await eventually { await valve.waiting.count == ProxyStore.maxConcurrentTests })
    #expect(await store.testAll() == nil)
    flag.value = false
    await valve.open([6])
    #expect(await eventually { await stub.inFlight == ProxyStore.maxConcurrentTests - 1 })
    await valve.open(Array(1...6))
    #expect(await running.value == nil)
    #expect(await stub.tested.count == ProxyStore.maxConcurrentTests)
    #expect(store.proxies == rows)
    #expect(store.testing.isEmpty && store.isTestingAll == false)

    // The caller's task cancelled: no more probes, no summary.
    let cancelValve = Valve()
    let cancelled = StubProxySource(page: { _, page in proxyPage(rows, page: page) }, test: { id in
        await cancelValve.wait(id)
        return ProxyTestResult(success: true, latencyMs: 50, checkedAt: probeTime)
    })
    let other = makeStore(cancelled)
    await other.reload()
    let outer = Task { await other.testAll() }
    #expect(await eventually { await cancelValve.waiting.count == ProxyStore.maxConcurrentTests })
    outer.cancel()
    await cancelValve.open(Array(1...6))
    #expect(await outer.value == nil)
    #expect(await cancelled.tested.count == ProxyStore.maxConcurrentTests)
    #expect(other.testing.isEmpty && other.isTestingAll == false)
}

@MainActor @Test func testResultsArrivingDuringAReloadSurviveTheNewCatalog() async {
    let older = Date(timeIntervalSince1970: 1_800_000_100)
    let newer = Date(timeIntervalSince1970: 1_800_000_900)
    let gate = SessionGate()
    let first = [proxy(2, checkedAt: older), proxy(1, checkedAt: older)]
    // The refresh read page 1 before our probe of 2 was saved, and after another probe of 1 that is newer than ours.
    let refreshed = [proxy(2, name: "renamed", checkedAt: older), proxy(1, latency: 333, checkedAt: newer)]
    let stub = StubProxySource(page: { call, page in
        if call == 1 { return proxyPage(first, page: page) }
        await gate.wait()
        return proxyPage(refreshed, page: page)
    }, test: { id in ProxyTestResult(success: true, latencyMs: 40 + id, checkedAt: probeTime) })
    let store = makeStore(stub)
    await store.reload()
    let reload = Task { await store.reload() }
    #expect(await eventually { await gate.arrived })
    #expect(await store.testAll() == ProxyTestSummary(tested: 2, failed: 0))
    // Shown at once on the catalog still on screen.
    #expect(store.proxy(id: 2)?.latencyMs == 42)
    await gate.open()
    await reload.value
    let merged = store.proxy(id: 2)
    #expect(merged?.name == "renamed")
    #expect(merged?.latencyMs == 42 && merged?.latencyCheckedAt == probeTime)
    #expect(store.proxy(id: 1) == refreshed[1])
}

@MainActor @Test func summaryReceiptTextAndTone() {
    let mixed = ProxyTestSummary(tested: 8, failed: 3)
    #expect(mixed.text == "已测试 8 个代理 · 3 个失败")
    #expect(mixed.tone == .critical)
    #expect(mixed.receipt.text == mixed.text && mixed.receipt.tone == .critical && mixed.receipt.systemImage == "waveform")
    #expect(mixed.receipt.action == nil)
    let clean = ProxyTestSummary(tested: 2, failed: 0)
    #expect(clean.text == "已测试 2 个代理")
    #expect(clean.tone == .ok)
    #expect(clean.receipt.tone == .ok && clean.receipt.action == nil)
}

@Test func canManageFollowsTokenScopeAndWorkspace() {
    let owner = AdminMe(authMethod: .jwt, user: .init(id: 1, email: "admin@example.com", username: "管理员", role: "admin"))
    func vendor(_ permissions: AdminMe.WorkspacePermissions) -> AdminMe {
        AdminMe(authMethod: .jwt, user: .init(id: 2, email: "vendor@example.com", username: "vendor", role: "admin"),
                workspace: .init(id: 7, name: "Vendor", permissions: permissions))
    }
    #expect(ProxyAccess.canManage(me: owner, isReadOnlyToken: false))
    #expect(!ProxyAccess.canManage(me: owner, isReadOnlyToken: true))
    #expect(ProxyAccess.canManage(me: vendor(.init(proxyManage: true)), isReadOnlyToken: false))
    #expect(!ProxyAccess.canManage(me: vendor(.init(proxyManage: true)), isReadOnlyToken: true))
    #expect(!ProxyAccess.canManage(me: vendor(.init(accountManage: true)), isReadOnlyToken: false))
    #expect(!ProxyAccess.canManage(me: vendor(.init()), isReadOnlyToken: false))
    #expect(ProxyAccess.canManage(me: nil, isReadOnlyToken: false))
}

@MainActor @Test func replaceRemoveAndLookups() async {
    let clock = TestClock()
    let gate = SessionGate()
    let stub = StubProxySource(page: { call, page in
        if call == 2 { await gate.wait(); throw failure }
        return proxyPage(sampleProxies, page: page)
    })
    let store = makeStore(stub, clock: clock)
    await store.reload()
    let loadedAt = clock.now
    clock.advance(10)
    let renamed = proxy(2, name: "sg-01")
    store.replace(renamed)
    #expect(store.proxies.map(\.name) == ["proxy-3", "sg-01", "proxy-1"])
    #expect(store.state.updatedAt == loadedAt && store.state.isLoading == false)
    store.replace(proxy(42))
    #expect(store.proxies.map(\.id) == [3, 2, 1])
    #expect(store.proxy(id: 2) == renamed)
    #expect(store.name(for: 2) == "sg-01")
    #expect(store.proxy(id: 42) == nil && store.name(for: 42) == nil)

    // While refreshing and after it failed, the kept catalog is changed the same way.
    let task = Task { await store.reload() }
    #expect(await eventually { await gate.arrived })
    store.replace(proxy(1, name: "hk-01"))
    #expect(store.state.isLoading && store.name(for: 1) == "hk-01")
    await gate.open()
    await task.value
    store.replace(proxy(3, name: "jp-01"))
    #expect(store.state.failureReason != nil && store.name(for: 3) == "jp-01")

    store.remove(id: 2)
    #expect(store.proxies.map(\.id) == [3, 1])
    #expect(store.catalog?.total == 2 && store.catalog?.count == 2)
    store.remove(id: 42)
    #expect(store.proxies.map(\.id) == [3, 1] && store.catalog?.total == 2)
    #expect(store.state.failureReason != nil)
}

/// 00 §2.7.2: a 429 shows “请求过于频繁，N 秒后自动重试” and nothing goes out for the list before the wait ends.
@MainActor @Test func rateLimitedFirstLoadWaitsBeforeTheNextRead() async {
    let stub = StubProxySource(page: { call, page in
        if call == 1 { throw APIError.server(status: 429, envelope: nil, retryAfter: 30) }
        return proxyPage(sampleProxies, page: page)
    })
    let clock = TestClock()
    let store = makeStore(stub, clock: clock)
    await store.ensureFresh()
    guard case .failed = store.state.display else { Issue.record("\(store.state.display)"); return }
    #expect(store.throttleMessage() == "请求过于频繁，30 秒后自动重试")

    // 重试, a pull, appearing again, the foreground and compliance all wait too.
    clock.advance(29)
    await store.reload()
    await store.ensureFresh()
    #expect(await stub.pages == [1])
    #expect(store.throttleMessage() == "请求过于频繁，1 秒后自动重试")

    clock.advance(1)
    await store.ensureFresh()
    #expect(await stub.pages == [1, 1])
    #expect(store.catalog?.isComplete == true)
    #expect(store.throttleMessage() == nil)
    #expect(store.refresh == BlockRefresh())
}

@MainActor @Test func rateLimitedRefreshKeepsTheCatalogAndWaits() async {
    let rows = (1...4).reversed().map { proxy($0) }
    // Calls 1–2 are the first load; call 4 is page 2 of the refresh.
    let stub = StubProxySource(page: { call, page in
        if call == 4 { throw APIError.server(status: 429, envelope: nil, retryAfter: 12) }
        return proxyPage(rows, page: page, size: 2)
    })
    let clock = TestClock()
    let store = makeStore(stub, clock: clock)
    await store.reload()
    let loadedAt = clock.now
    let complete = ProxyCatalog(proxies: rows, total: 4, isComplete: true)
    clock.advance(120)
    await store.ensureFresh()
    #expect(await stub.pages == [1, 2, 1, 2])
    #expect(store.state.display == .value(complete, at: loadedAt, isRefreshing: false, updateFailed: true))
    #expect(store.throttleMessage() == "请求过于频繁，12 秒后自动重试")

    clock.advance(11)
    await store.reload()
    await store.ensureFresh()
    #expect(await stub.pages.count == 4)

    clock.advance(1)
    await store.reload()
    #expect(await stub.pages == [1, 2, 1, 2, 1, 2])
    #expect(store.state == .loaded(complete, at: clock.now))
    #expect(store.throttleMessage() == nil)
}
