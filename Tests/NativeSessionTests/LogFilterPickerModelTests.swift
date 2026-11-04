import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 40 §6.4 按对象筛选 sheet (S4-07): the debounce, new input cancelling reads, each group on its own, and the pick written
// into the usage-record page's conditions.

/// Records every keyword and answers through closures; `call` counts from 1 per kind. A read that sees its task cancelled is
/// noted as “账号 <search>” / “用户 <keyword>”.
private actor PickerStub {
    typealias AccountHandler = @Sendable (_ call: Int, _ search: String) async throws -> [UpstreamAccount]
    typealias UserHandler = @Sendable (_ call: Int, _ keyword: String) async throws -> [UsageUserMatch]
    private let onAccounts: AccountHandler
    private let onUsers: UserHandler
    private(set) var accountCalls: [String] = []
    private(set) var userCalls: [String] = []
    private(set) var cancellations: [String] = []

    init(accounts: @escaping AccountHandler = { call, search in [account(call, name: search)] },
         users: @escaping UserHandler = { call, keyword in [UsageUserMatch(id: call, email: "\(keyword)@example.com")] }) {
        onAccounts = accounts; onUsers = users
    }
    func accounts(_ search: String) async throws -> [UpstreamAccount] {
        accountCalls.append(search)
        do { return try await onAccounts(accountCalls.count, search) } catch { noteCancel(error, "账号 " + search); throw error }
    }
    func users(_ keyword: String) async throws -> [UsageUserMatch] {
        userCalls.append(keyword)
        do { return try await onUsers(userCalls.count, keyword) } catch { noteCancel(error, "用户 " + keyword); throw error }
    }
    private func noteCancel(_ error: any Error, _ label: String) { if error is CancellationError { cancellations.append(label) } }
    nonisolated var source: LogFilterPickerSource {
        LogFilterPickerSource(accounts: { try await self.accounts($0) }, users: { try await self.users($0) })
    }
}

/// Like SessionGate, but a waiter whose task is cancelled throws CancellationError.
private actor Latch {
    private(set) var arrivals = 0
    private var isOpen = false
    func wait() async throws {
        arrivals += 1
        while !isOpen { try await Task.sleep(for: .milliseconds(2)) }
    }
    func open() { isOpen = true }
}

private actor LoadCount {
    private(set) var count = 0
    func next() -> Int { count += 1; return count }
}

@MainActor private final class Flag { var value = true }

private let failure = APIError.server(status: 502, reason: nil)
private let sampleGroups = [(1, "高级组"), (2, "标准组"), (3, "默认组"), (4, "企业专线"), (5, "Claude Code 组"), (7, "GLM 组")]
    .map { AdminGroup(id: $0.0, name: $0.1, platform: "anthropic", sortOrder: $0.0) }

private func account(_ id: Int, name: String = "Claude-官方") -> UpstreamAccount {
    UpstreamAccount(id: id, name: name, platform: "anthropic", type: "oauth")
}
@MainActor private func directory(_ load: @escaping @Sendable () async throws -> [AdminGroup] = { sampleGroups }) -> GroupDirectory {
    GroupDirectory(load: load)
}
@MainActor private func makeModel(_ stub: PickerStub, groups: GroupDirectory? = nil,
                                  isCurrent: @escaping @MainActor () -> Bool = { true }) -> LogFilterPickerModel {
    LogFilterPickerModel(source: stub.source, groups: groups, isCurrent: isCurrent, debounce: .milliseconds(30))
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
@MainActor private func settled(_ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}
private func isIdle<Value>(_ state: BlockState<Value>) -> Bool { if case .idle = state { true } else { false } }

// MARK: - 打开与搜索

@MainActor @Test func startReadsFirstAccountsAndGroupsButNoUsers() async {
    let stub = PickerStub(accounts: { _, _ in (1...8).map { account($0) } })
    let loads = LoadCount()
    let groups = directory { _ = await loads.next(); return sampleGroups }
    let model = makeModel(stub, groups: groups)
    await model.start()
    #expect(await stub.accountCalls == [""])
    #expect(await stub.userCalls.isEmpty)
    #expect(!model.showsUsers && model.userRows.isEmpty)
    #expect(model.accountRows.map(\.id) == [1, 2, 3, 4, 5, 6])
    #expect(model.groupRows.map(\.id) == [1, 2, 3, 4])
    await model.start()
    #expect(await stub.accountCalls == [""])
    #expect(await loads.count == 1)
}

@MainActor @Test func searchDebouncesAndSendsOnlyTheLastKeyword() async {
    let stub = PickerStub()
    let model = makeModel(stub, groups: directory())
    await model.start()
    model.searchChanged("c")
    model.searchChanged("cl")
    model.searchChanged("cla")
    #expect(model.searchText == "cla" && model.query == "")
    #expect(await eventually { await stub.accountCalls == ["", "cla"] })
    #expect(await eventually { await stub.userCalls == ["cla"] })
    #expect(await settled { model.userRows.map(\.email) == ["cla@example.com"] && model.accountRows.map(\.name) == ["cla"] })
    #expect(model.query == "cla" && model.showsUsers)
    #expect(model.groupRows.map(\.id) == [5])
}

@MainActor @Test func newInputCancelsReadsAlreadySent() async {
    let latch = Latch()
    let stub = PickerStub(accounts: { call, search in
        if search == "cl" { try await latch.wait() }
        return [account(call, name: search)]
    }, users: { call, keyword in
        if keyword == "cl" { try await latch.wait() }
        return [UsageUserMatch(id: call, email: "\(keyword)@example.com")]
    })
    let model = makeModel(stub)
    await model.start()
    model.searchChanged("cl")
    #expect(await eventually { await latch.arrivals == 2 })
    model.searchChanged("clx")
    #expect(await eventually { await stub.cancellations.sorted() == ["用户 cl", "账号 cl"].sorted() })
    #expect(await settled { model.accountRows.map(\.name) == ["clx"] && model.userRows.map(\.email) == ["clx@example.com"] })
    await latch.open()
    try? await Task.sleep(for: .milliseconds(60))
    #expect(model.accountRows.map(\.name) == ["clx"] && model.userRows.map(\.email) == ["clx@example.com"])
    #expect(model.accounts.error == nil && model.users.error == nil)
}

@MainActor @Test func sameKeywordWithSpacesReadsNothing() async {
    let latch = Latch()
    let stub = PickerStub(accounts: { call, search in
        if search == "cl" { try await latch.wait() }
        return [account(call, name: search)]
    })
    let model = makeModel(stub)
    await model.start()
    model.searchChanged("cl")
    #expect(await eventually { await latch.arrivals == 1 })
    model.searchChanged(" cl ")
    try? await Task.sleep(for: .milliseconds(100))
    #expect(await stub.cancellations.isEmpty)
    await latch.open()
    #expect(await settled { model.accountRows.map(\.name) == ["cl"] })
    #expect(await stub.accountCalls == ["", "cl"])
    #expect(await stub.userCalls == ["cl"])
}

@MainActor @Test func returningToACancelledKeywordReadsItAgain() async {
    let latch = Latch()
    let stub = PickerStub(accounts: { call, search in
        if call == 2 { try await latch.wait() }
        return [account(call, name: search)]
    })
    let model = makeModel(stub)
    await model.start()
    model.searchChanged("a")
    #expect(await eventually { await latch.arrivals == 1 })
    model.searchChanged("ab")
    model.searchChanged("a")
    #expect(await eventually { await stub.accountCalls == ["", "a", "a"] })
    #expect(await settled { model.accountRows.map(\.id) == [3] })
    #expect(await stub.cancellations.contains("账号 a"))
}

@MainActor @Test func clearingTheSearchHidesUsersWithoutARequest() async {
    let stub = PickerStub()
    let model = makeModel(stub)
    await model.start()
    model.searchChanged("alice")
    #expect(await settled { model.userRows.count == 1 })
    model.searchChanged("")
    #expect(await eventually { await stub.accountCalls == ["", "alice", ""] })
    #expect(await settled { model.query.isEmpty && !model.showsUsers && model.userRows.isEmpty && isIdle(model.users.state) })
    #expect(await stub.userCalls == ["alice"])
}

// MARK: - 各组独立失败、429 与会话

@MainActor @Test func eachGroupFailsAndRetriesAlone() async {
    let stub = PickerStub(accounts: { call, search in
        if call == 2 { throw failure }
        return [account(call, name: search)]
    })
    let groupLoads = LoadCount()
    let groups = directory {
        if await groupLoads.next() == 1 { throw failure }
        return sampleGroups
    }
    let model = makeModel(stub, groups: groups)
    await model.start()
    #expect(groups.state.failureReason != nil && model.groupRows.isEmpty)
    #expect(model.accountRows.map(\.id) == [1])
    model.searchChanged("cl")
    await model.applySearch()
    #expect(model.accounts.error != nil && model.accounts.lastError?.statusCode == 502)
    #expect(model.accountRows.isEmpty)
    #expect(model.userRows.map(\.email) == ["cl@example.com"])
    await model.retryAccounts()
    #expect(model.accountRows.map(\.name) == ["cl"] && model.accounts.error == nil)
    #expect(await stub.userCalls == ["cl"])
    await model.retryGroups()
    #expect(await groupLoads.count == 2)
    #expect(model.groupRows.map(\.id) == [5])
}

@MainActor @Test func throttledAccountsWaitBeforeRetry() async {
    let stub = PickerStub(accounts: { call, search in
        if call == 1 { throw APIError.server(status: 429, envelope: nil, retryAfter: 8) }
        return [account(call, name: search)]
    })
    let model = makeModel(stub)
    await model.start()
    #expect(model.accounts.lastError?.statusCode == 429)
    #expect(!model.accounts.refresh.allowsRequest(at: Date()))
    #expect(model.accounts.refresh.allowsRequest(at: Date().addingTimeInterval(9)))
    await model.retryAccounts()
    model.searchChanged("cl")
    await model.applySearch()
    #expect(await stub.accountCalls == [""])
    #expect(await stub.userCalls == ["cl"])
}

@MainActor @Test func repliesAfterTheSessionChangedAreDropped() async {
    let latch = Latch()
    let stub = PickerStub(accounts: { call, search in try await latch.wait(); return [account(call, name: search)] },
                          users: { call, keyword in try await latch.wait(); return [UsageUserMatch(id: call, email: keyword)] })
    let flag = Flag()
    let model = makeModel(stub, isCurrent: { flag.value })
    model.searchChanged("x")
    let task = Task { await model.applySearch() }
    #expect(await eventually { await latch.arrivals == 2 })
    flag.value = false
    await latch.open()
    await task.value
    #expect(model.accountRows.isEmpty && model.accounts.value == nil && model.accounts.error == nil)
    #expect(model.userRows.isEmpty && model.users.value == nil && model.users.error == nil)
}

@MainActor @Test func stopCancelsTheWaitAndReads() async {
    let latch = Latch()
    let stub = PickerStub(accounts: { call, search in
        if search == "y" { try await latch.wait() }
        return [account(call, name: search)]
    })
    let model = makeModel(stub)
    await model.start()
    model.searchChanged("x")
    model.stop()
    try? await Task.sleep(for: .milliseconds(100))
    #expect(await stub.accountCalls == [""])
    model.searchChanged("y")
    #expect(await eventually { await latch.arrivals == 1 })
    model.stop()
    #expect(await eventually { await stub.cancellations.contains("账号 y") })
}

@MainActor @Test func noMatchesOnlyWhenAllThreeLoadedEmpty() async {
    let latch = Latch()
    let stub = PickerStub(accounts: { call, search in search.hasPrefix("zz") ? [] : [account(call, name: search)] },
                          users: { _, keyword in
                              if keyword == "zzy" { try await latch.wait() }
                              return []
                          })
    let model = makeModel(stub, groups: directory())
    await model.start()
    #expect(!model.hasNoMatches)
    model.searchChanged("zzz")
    await model.applySearch()
    #expect(model.hasNoMatches)
    model.searchChanged("zzy")
    let pending = Task { await model.applySearch() }
    #expect(await eventually { await latch.arrivals == 1 })
    #expect(!model.hasNoMatches)
    await latch.open()
    await pending.value
    #expect(model.hasNoMatches)

    let failing = makeModel(PickerStub(accounts: { _, _ in [] }, users: { _, _ in [] }), groups: directory { throw failure })
    await failing.start()
    failing.searchChanged("zzz")
    await failing.applySearch()
    #expect(!failing.hasNoMatches)
}

// MARK: - 选中写进条件

@Test func pickReplacesOnlyItsOwnKind() {
    let base = LogConditions(account: LogFilterObject(id: 1), group: LogFilterObject(id: 2), user: LogFilterObject(id: 3),
                             model: "claude-opus-4", modelSource: .upstream)
    let five = LogFilterObject(id: 5, name: "五"), six = LogFilterObject(id: 6, name: "六"), seven = LogFilterObject(id: 7, name: "七")
    #expect(LogFilterPick.account(five).applied(to: base) == LogConditions(account: five, group: LogFilterObject(id: 2),
                                                                         user: LogFilterObject(id: 3), model: "claude-opus-4",
                                                                         modelSource: .upstream))
    #expect(LogFilterPick.group(six).applied(to: base) == LogConditions(account: LogFilterObject(id: 1), group: six,
                                                                      user: LogFilterObject(id: 3), model: "claude-opus-4",
                                                                      modelSource: .upstream))
    #expect(LogFilterPick.user(seven).applied(to: base) == LogConditions(account: LogFilterObject(id: 1), group: LogFilterObject(id: 2),
                                                                       user: seven, model: "claude-opus-4", modelSource: .upstream))
    #expect(LogFilterPick.group(six).applied(to: LogConditions()) == LogConditions(group: six))
}

@Test func pickNamesComeFromTheRow() {
    #expect(LogFilterPick(account: account(1, name: "Claude-官方-01")) == .account(LogFilterObject(id: 1, name: "Claude-官方-01")))
    #expect(LogFilterPick(account: account(2, name: "  ")).object == LogFilterObject(id: 2, name: nil))
    #expect(LogFilterPick(group: AdminGroup(id: 2, name: "标准组")) == .group(LogFilterObject(id: 2, name: "标准组")))
    #expect(LogFilterPick(user: UsageUserMatch(id: 3, email: "xm.wang@example.com"))
            == .user(LogFilterObject(id: 3, name: "xm.wang@example.com")))
    let conditions = LogConditions(account: LogFilterObject(id: 1), group: LogFilterObject(id: 2, name: "标准组"))
    #expect(LogFilterPick.account(LogFilterObject(id: 1, name: "Claude-官方-01")).isSameObject(in: conditions))
    #expect(!LogFilterPick.account(LogFilterObject(id: 4)).isSameObject(in: conditions))
    #expect(!LogFilterPick.user(LogFilterObject(id: 1)).isSameObject(in: conditions))
    #expect(!LogFilterPick.group(LogFilterObject(id: 1)).isSameObject(in: conditions))
}

// MARK: - LogsStoreState.pick（S4D2a-02）

private actor UsageReads {
    private(set) var filters: [RequestLogFilter] = []
    func read(_ page: Int, _ filter: RequestLogFilter) -> Page<UsageRequestRecord> {
        filters.append(filter)
        return Page(items: [], total: nil, page: page, pageSize: 100, pages: nil, hasMore: false)
    }
    nonisolated var source: LogsSource {
        LogsSource(usage: { await self.read($0, $1) },
                   errors: { page, _, _ in Page(items: [], total: 0, page: page, pageSize: 100, pages: 1) })
    }
}

@MainActor private func logsStore(_ route: LogsRoute, reads: UsageReads) -> LogsStoreState {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    return LogsStoreState(route: route, generation: UUID(), source: reads.source, timeZone: liveOpsZone, legacyServer: false,
                          supportsModelSource: true, isCurrent: { true }, now: { now })
}

@MainActor @Test func pickingTheSetObjectOnlyNamesIt() async {
    let reads = UsageReads()
    let store = logsStore(LogsRoute(account: RouteObject(id: 1), group: RouteObject(id: 2, name: "标准组")), reads: reads)
    await store.appeared()
    #expect(store.chips.chips.first?.text == "账号：#1")
    await store.pick(.account(LogFilterObject(id: 1, name: "Claude-官方-01")))
    #expect(await reads.filters.count == 1)
    #expect(store.chips.chips.map(\.text) == ["账号：Claude-官方-01", "分组：标准组"])
    #expect(store.phase == .loaded)
}

@MainActor @Test func pickingAnotherObjectReadsPageOneWithIt() async {
    let reads = UsageReads()
    let route = LogsRoute(account: RouteObject(id: 1), group: RouteObject(id: 2, name: "标准组"), user: RouteObject(id: 3, name: "王小明"),
                          model: "claude-opus-4")
    let store = logsStore(route, reads: reads)
    await store.appeared()
    await store.pick(LogFilterPick(user: UsageUserMatch(id: 8, email: "siyuan.chen@example.com")))
    let filters = await reads.filters
    #expect(filters.count == 2)
    let filter = filters.last
    #expect(filter?.userID == 8 && filter?.accountID == 1 && filter?.groupID == 2 && filter?.model == "claude-opus-4")
    #expect(store.chips.chips.map(\.text) == ["账号：#1", "分组：标准组", "用户：siyuan.chen@example.com", "模型：claude-opus-4"])
}
