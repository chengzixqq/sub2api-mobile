import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 50 §6–§7 (S5-12): the reads behind the group's API key and subscription pages.

private let premium = AdminGroup(id: 1, name: "高级组")
private let enterprise = AdminGroup(id: 4, name: "企业专线", subscriptionType: "subscription", dailyLimitUSD: 20, weeklyLimitUSD: 100, monthlyLimitUSD: 300)
private let badGateway = APIError.server(status: 502, reason: nil)
private let serverError = APIError.server(status: 500, reason: nil)

private func key(_ id: Int) -> AdminAPIKey { AdminAPIKey(id: id, userID: 21, keyMasked: "sk-…k\(id)", name: "Key \(id)") }
/// Newest first, 20 a page, like admin/groups/:id/api-keys.
private func keyPage(_ page: Int, total: Int = 38) -> Page<AdminAPIKey> {
    let ids = Array((1...total).reversed()).dropFirst((page - 1) * 20).prefix(20)
    return Page(items: ids.map(key), total: total, page: page, pageSize: 20, pages: nil)
}
private func subscriptionPage(_ page: Int) -> Page<AdminUserSubscription> {
    Page(items: (801...815).reversed().map { AdminUserSubscription(id: $0, userID: 9, groupID: 4, status: "active") }, total: 15, page: page,
         pageSize: 20, pages: nil)
}
private func ids(_ range: ClosedRange<Int>) -> [Int] { Array(range.reversed()) }

/// Counts every read; `call` counts from 1 per kind.
@MainActor private final class RecordsStub {
    var group: @MainActor (_ call: Int) async throws -> AdminGroup = { _ in premium }
    var keys: @MainActor (_ call: Int, _ page: Int) async throws -> Page<AdminAPIKey> = { _, page in keyPage(page) }
    var today: @MainActor (_ call: Int, _ ids: [Int]) async throws -> [Int: Decimal] = { _, ids in [ids[0]: Decimal(string: "12.4")!] }
    var subscriptions: @MainActor (_ call: Int, _ page: Int) async throws -> Page<AdminUserSubscription> = { _, page in subscriptionPage(page) }
    var stats: @MainActor (_ call: Int) async throws -> GroupStats? = { _ in GroupStats(totalAPIKeys: 6, activeAPIKeys: 6, subscriptionsTotal: 15, subscriptionsActive: 12) }
    var count: @MainActor (_ call: Int) async throws -> Int = { _ in 7 }
    private(set) var groupReads = 0
    private(set) var keyPages: [Int] = []
    private(set) var todayIDs: [[Int]] = []
    private(set) var subscriptionPages: [Int] = []
    private(set) var statsReads = 0
    private(set) var countReads = 0

    var source: GroupRecordsSource {
        GroupRecordsSource(
            group: { _ in self.groupReads += 1; return try await self.group(self.groupReads) },
            keys: { _, page in self.keyPages.append(page); return try await self.keys(self.keyPages.count, page) },
            keysToday: { ids in self.todayIDs.append(ids); return try await self.today(self.todayIDs.count, ids) },
            subscriptions: { _, page in self.subscriptionPages.append(page); return try await self.subscriptions(self.subscriptionPages.count, page) },
            stats: { _ in self.statsReads += 1; return try await self.stats(self.statsReads) },
            activeSubscriptionCount: { _ in self.countReads += 1; return try await self.count(self.countReads) })
    }
}

@MainActor private final class Flag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

@MainActor private func keysModel(_ stub: RecordsStub, snapshot: AdminGroup? = premium, readOnly: Flag = Flag(false),
                                  current: Flag = Flag(true)) -> GroupKeysModel {
    GroupKeysModel(groupID: 1, snapshot: snapshot, source: stub.source, isReadOnlyToken: { readOnly.value }, isCurrent: { current.value })
}
@MainActor private func subscriptionsModel(_ stub: RecordsStub, snapshot: AdminGroup? = enterprise) -> GroupSubscriptionsModel {
    GroupSubscriptionsModel(groupID: 4, snapshot: snapshot, source: stub.source, isCurrent: { true })
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

// MARK: - API 密钥

@MainActor @Test func keysEntryReadsPageOneThenTodayForThatPage() async {
    let stub = RecordsStub()
    let model = keysModel(stub)
    await model.start()
    await model.settleTodayReads()
    #expect(stub.keyPages == [1] && stub.todayIDs == [ids(19...38)] && stub.groupReads == 0)
    #expect(model.today(for: 38) == .amount(Decimal(string: "12.4")!) && model.today(for: 37) == .amount(0))
    #expect(model.page == .content && model.subtitle == "高级组 · 共 38 个")
    await model.start()
    await model.settleTodayReads()
    #expect(stub.keyPages == [1] && stub.todayIDs.count == 1)
}

/// R14: a read-only token never asks for the keys' today spend; every row says 今日 —.
@MainActor @Test func readOnlyTokenNeverSendsKeysUsage() async {
    let stub = RecordsStub()
    let model = keysModel(stub, readOnly: Flag(true))
    await model.start()
    await model.loadMore()
    await model.reload()
    await model.settleTodayReads()
    #expect(stub.todayIDs.isEmpty && stub.keyPages == [1, 2, 1])
    #expect(model.today(for: 38) == .missing && model.page == .content)
}

@MainActor @Test func todayFailureLeavesDashWithoutListFailure() async {
    let stub = RecordsStub()
    stub.today = { _, _ in throw serverError }
    let model = keysModel(stub)
    await model.start()
    await model.settleTodayReads()
    #expect(model.today(for: 38) == .missing && model.today(for: 19) == .missing)
    #expect(model.page == .content && model.pager.lastError == nil)
    await model.start()
    await model.settleTodayReads()
    #expect(stub.todayIDs.count == 1)
}

/// S5D2a-15: a pull whose today read fails keeps the amounts read before; only a key never read says 今日 —.
@MainActor @Test func todayRefreshFailureKeepsEarlierAmounts() async {
    let stub = RecordsStub()
    stub.keys = { call, page in keyPage(page, total: call == 1 ? 38 : 39) }
    stub.today = { call, ids in
        guard call == 1 else { throw serverError }
        return [ids[0]: Decimal(string: "12.4")!]
    }
    let model = keysModel(stub)
    await model.start()
    await model.settleTodayReads()
    await model.reload()
    await model.settleTodayReads()
    #expect(stub.todayIDs.count == 2 && stub.todayIDs[1] == ids(20...39))
    #expect(model.today(for: 38) == .amount(Decimal(string: "12.4")!) && model.today(for: 20) == .amount(0))
    #expect(model.today(for: 39) == .missing)
}

@MainActor @Test func loadMoreAppendsNextPageAndReadsTodayOnlyForNewRows() async {
    let stub = RecordsStub()
    stub.keys = { _, page in
        guard page == 2 else { return keyPage(page) }
        return Page(items: [20, 19].map(key) + ids(1...18).map(key), total: 38, page: 2, pageSize: 20, pages: nil)
    }
    let model = keysModel(stub)
    await model.start()
    await model.settleTodayReads()
    await model.loadMore()
    await model.settleTodayReads()
    #expect(stub.keyPages == [1, 2] && stub.todayIDs == [ids(19...38), ids(1...18)])
    #expect(model.pager.rows.map(\.id) == ids(1...38) && model.pager.feed?.hasMore == false)
    await model.loadMore()
    #expect(stub.keyPages == [1, 2])
}

@MainActor @Test func moreFailureKeepsRowsAndRetryReadsTheSamePage() async {
    let stub = RecordsStub()
    stub.keys = { call, page in
        if page == 2, call == 2 { throw badGateway }
        return keyPage(page)
    }
    let model = keysModel(stub)
    await model.start()
    await model.loadMore()
    #expect(model.pager.nextPage == .failed && model.pager.rows.count == 20 && model.page == .content)
    await model.loadMore()
    #expect(stub.keyPages == [1, 2])
    await model.retryMore()
    #expect(stub.keyPages == [1, 2, 2] && model.pager.rows.count == 38 && model.pager.nextPage == .idle)
}

/// 50 §6.5: a 400 is the App's own parameter error, shown as the list failure; only 重试 or a pull sends it again.
@MainActor @Test func parameterErrorIsListFailureAndIsNotSentAgainByItself() async {
    let stub = RecordsStub()
    stub.keys = { _, _ in throw APIError.server(status: 400, reason: nil) }
    let model = keysModel(stub)
    await model.start()
    #expect(model.page == .failure && model.pager.lastError?.statusCode == 400 && !model.pager.needsFirstRead)
    await model.start()
    #expect(stub.keyPages == [1])
    await model.reload()
    #expect(stub.keyPages == [1, 1])
}

@MainActor @Test func cancelledReadsAreReadAgainOnNextStart() async {
    let stub = RecordsStub()
    stub.keys = { call, page in
        if call == 1 { throw CancellationError() }
        return keyPage(page)
    }
    stub.today = { call, ids in
        if call == 1 { throw CancellationError() }
        return [ids[0]: 1]
    }
    let model = keysModel(stub)
    await model.start()
    #expect(model.pager.needsFirstRead && model.page == .skeleton && stub.todayIDs.isEmpty)
    await model.start()
    await model.settleTodayReads()
    #expect(stub.keyPages == [1, 1] && model.today(for: 38) == .pending)
    await model.start()
    await model.settleTodayReads()
    #expect(stub.keyPages == [1, 1] && stub.todayIDs == [ids(19...38), ids(19...38)] && model.today(for: 38) == .amount(1))
}

@MainActor @Test func pullStartsFromPageOneAndDropsAnOlderPageReply() async {
    let gate = SessionGate()
    let stub = RecordsStub()
    stub.keys = { _, page in
        if page == 2 { await gate.wait() }
        return keyPage(page)
    }
    let model = keysModel(stub)
    await model.start()
    await model.settleTodayReads()
    let more = Task { await model.loadMore() }
    #expect(await eventually { await gate.arrived })
    await model.reload()
    await gate.open()
    await more.value
    await model.settleTodayReads()
    #expect(model.pager.rows.map(\.id) == ids(19...38) && model.pager.nextPage == .idle)
    #expect(stub.todayIDs.allSatisfy { $0 == ids(19...38) })
}

@MainActor @Test func repliesFromAnEndedSessionAreDropped() async {
    let gate = SessionGate()
    let stub = RecordsStub()
    stub.keys = { _, page in await gate.wait(); return keyPage(page) }
    stub.group = { _ in await gate.wait(); return premium }
    let current = Flag(true)
    let model = keysModel(stub, snapshot: nil, current: current)
    let start = Task { await model.start() }
    #expect(await eventually { await gate.arrived })
    current.value = false
    await gate.open()
    await start.value
    await model.settleTodayReads()
    #expect(model.pager.feed == nil && stub.todayIDs.isEmpty && model.group == nil)
}

@MainActor @Test func groupSnapshotSkipsTheGroupReadAndA404MarksDeleted() async {
    let stub = RecordsStub()
    let unknown = keysModel(stub, snapshot: nil)
    #expect(unknown.subtitle == "")
    await unknown.start()
    #expect(stub.groupReads == 1 && unknown.subtitle == "高级组 · 共 38 个")

    let gone = RecordsStub()
    gone.group = { _ in throw APIError.server(status: 404, reason: "GROUP_NOT_FOUND") }
    let deleted = keysModel(gone, snapshot: nil)
    await deleted.start()
    #expect(deleted.isDeleted && deleted.page == .deleted)
    let sent = gone.keyPages
    await deleted.start()
    await deleted.loadMore()
    #expect(gone.keyPages == sent && gone.groupReads == 1)

    let kept = RecordsStub()
    kept.group = { _ in throw serverError }
    let snapshot = keysModel(kept)
    await snapshot.start()
    #expect(kept.groupReads == 0)
    await snapshot.reload()
    #expect(kept.groupReads == 1 && snapshot.group == premium && snapshot.page == .content)
}

// MARK: - 订阅

@MainActor @Test func subscriptionsActiveCountFromStatsThenFallback() async {
    let stub = RecordsStub()
    let fromStats = subscriptionsModel(stub)
    await fromStats.start()
    #expect(fromStats.subtitle == "企业专线 · 生效中 12 个" && stub.countReads == 0 && fromStats.page == .content)

    let legacy = RecordsStub()
    legacy.stats = { _ in nil }
    let fallback = subscriptionsModel(legacy)
    await fallback.start()
    #expect(fallback.subtitle == "企业专线 · 生效中 7 个" && legacy.countReads == 1)

    let failing = RecordsStub()
    failing.stats = { _ in nil }
    failing.count = { _ in throw serverError }
    let neither = subscriptionsModel(failing)
    await neither.start()
    #expect(neither.activeCount == nil && neither.subtitle == "企业专线" && neither.page == .content)

    let broken = RecordsStub()
    broken.stats = { _ in throw serverError }
    let statsFailed = subscriptionsModel(broken)
    await statsFailed.start()
    #expect(statsFailed.activeCount == nil && broken.countReads == 0 && statsFailed.page == .content && broken.subscriptionPages == [1])
    await statsFailed.start()
    #expect(broken.statsReads == 1)
}

@MainActor @Test func subscriptionsNeedTheGroupForLimits() async {
    let stub = RecordsStub()
    stub.group = { call in
        if call == 1 { throw serverError }
        return enterprise
    }
    let model = subscriptionsModel(stub, snapshot: nil)
    await model.start()
    #expect(model.page == .failure && model.failureError?.statusCode == 500 && model.pager.feed != nil)
    await model.reload()
    #expect(model.page == .content && model.group == enterprise && stub.subscriptionPages == [1, 1])

    let kept = RecordsStub()
    kept.group = { _ in throw serverError }
    let snapshot = subscriptionsModel(kept)
    await snapshot.start()
    await snapshot.reload()
    #expect(kept.groupReads == 1 && snapshot.page == .content && snapshot.group == enterprise)
}
