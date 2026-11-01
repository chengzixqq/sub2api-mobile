import Foundation
import Testing
@testable import Sub2Core

// S5-06: 50 §2.2 members and their today, §2.5 page states, §2.6 refresh table; S5-02 owns the status card's words.

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: TimeInterval) -> String { ServerTime.utcTimestamp(now.addingTimeInterval(seconds)) }

private func account(_ id: Int, _ name: String? = nil, status: String = "active", schedulable: Bool = true, overload: String? = nil,
                     rateLimit: String? = nil, temp: String? = nil) -> UpstreamAccount {
    UpstreamAccount(id: id, name: name ?? "账号-\(id)", platform: "anthropic", type: "oauth", status: status, schedulable: schedulable, groupIDs: [1],
                    rateLimitResetAt: rateLimit, overloadUntil: overload, tempUnschedulableUntil: temp)
}
private func page(_ ids: [Int], total: Int, page: Int = 1, pages: Int = 1) -> AccountListPage {
    AccountListPage(items: ids.map { account($0) }, total: total, page: page, pageSize: GroupMemberList.pageSize, pages: pages)
}
private func today(_ cost: String) -> AccountTodayStats {
    AccountTodayStats(requests: 1, tokens: 1, cost: 0, userCost: Decimal(string: cost))
}

// MARK: 2.6 刷新策略

@Test func refreshPlanFollowsSection26() {
    let everything = Set(GroupDetailBlock.allCases)
    for trigger in [GroupDetailTrigger.enter, .pull, .foreground, .afterWrite] { #expect(GroupDetailRefreshPlan.blocks(for: trigger) == everything) }
    #expect(GroupDetailRefreshPlan.blocks(for: .poll) == [.group, .members, .memberToday, .shortage, .capacity, .alert])
    #expect(GroupDetailRefreshPlan.blocks(for: .poll, unread: [.stats]) == [.group, .members, .memberToday, .shortage, .capacity, .alert, .stats])
    #expect(GroupDetailRefreshPlan.blocks(for: .membersWritten) == [.group, .members, .memberToday, .capacity])
    #expect(GroupDetailRefreshPlan.blocks(for: .countdown) == [.group, .members, .memberToday])
    #expect(GroupDetailRefreshPlan.blocks(for: .alertReturn) == [.alert])
    #expect(GroupDetailRefreshPlan.interval == 60)
    #expect(GroupDetailRefreshPlan.delay(sinceLastRefresh: 20) == 40)
    #expect(GroupDetailRefreshPlan.delay(sinceLastRefresh: 75) == 0)
    #expect(GroupDetailRefreshPlan.delay(sinceLastRefresh: nil) == 0)
    #expect(GroupDetailRefreshPlan.delay(sinceLastRefresh: -5) == 60)
}

// MARK: 2.5 状态

@Test func pageStateDeletedWinsThenSnapshotBannerThenFailure() {
    #expect(GroupDetailPageState.resolve(hasGroup: true, loadedFromServer: true, failure: nil, deleted: true) == .deleted)
    #expect(GroupDetailPageState.resolve(hasGroup: false, loadedFromServer: false, failure: "x", deleted: true) == .deleted)
    #expect(GroupDetailPageState.resolve(hasGroup: true, loadedFromServer: false, failure: "网络错误", deleted: false)
            == .content(banner: "读取最新数据失败，显示的是列表里的快照"))
    #expect(GroupDetailPageState.resolve(hasGroup: true, loadedFromServer: true, failure: "网络错误", deleted: false) == .content(banner: nil))
    #expect(GroupDetailPageState.resolve(hasGroup: true, loadedFromServer: false, failure: nil, deleted: false) == .content(banner: nil))
    #expect(GroupDetailPageState.resolve(hasGroup: false, loadedFromServer: false, failure: "网络错误", deleted: false) == .failure(message: "网络错误"))
    #expect(GroupDetailPageState.resolve(hasGroup: false, loadedFromServer: false, failure: nil, deleted: false) == .skeleton)
}

@Test func detailCopyIsFixed() {
    #expect(GroupDetailCopy.deletedTitle == "分组" && GroupDetailCopy.loadFailedTitle == "读取分组失败")
    #expect(GroupDetailCopy.membersTitle == "成员账号" && GroupDetailCopy.membersOrdinal == "壹")
    #expect(GroupDetailCopy.membersLoadFailed == "成员加载失败" && GroupDetailCopy.membersEmpty == "没有成员账号")
}

// MARK: 2.2 成员

@Test func localMemberOrderPutsUnavailableFirst() {
    let rows = [account(1, "正常"), account(2, "停用", status: "inactive"), account(3, "暂停", schedulable: false),
                account(4, "临时", temp: at(600)), account(5, "限流", rateLimit: at(300)), account(6, "过载", overload: at(60)),
                account(7, "错误", status: "error"), account(8, "限流已过", rateLimit: at(-30))]
    #expect(GroupMemberOrder.sorted(rows, now: now).map(\.id) == [7, 6, 5, 4, 3, 2, 1, 8])
    let ties = [account(9, "B"), account(3, "A"), account(2, "A")]
    #expect(GroupMemberOrder.sorted(ties, now: now).map(\.id) == [2, 3, 9])
}

@Test func memberQueryAsksForUrgencyAndAHundredAPage() throws {
    let modern = try GroupMemberList.query(groupID: 5, supportsListQuery: true).queryItems(page: 2)
    let values = Dictionary(uniqueKeysWithValues: modern.map { ($0.name, $0.value ?? "") })
    #expect(values["group"] == "5" && values["sort_by"] == "urgency" && values["page_size"] == "100" && values["lite"] == "1" && values["page"] == "2")
    let older = try GroupMemberList.query(groupID: 5, supportsListQuery: false).queryItems(page: 1)
    #expect(older.contains(URLQueryItem(name: "sort_by", value: "name")))
}

@Test func memberListKeepsServerOrderAndAppendsPages() {
    let first = GroupMemberList(pages: [page([5, 3, 9], total: 5, pages: 2)], serverSorted: true, now: now)
    #expect(first.rows.map(\.id) == [5, 3, 9] && first.total == 5 && first.pagesRead == 1)
    #expect(first.hasMore && !first.isComplete)
    let second = first.appending(page([9, 1], total: 5, page: 2, pages: 2), now: now)
    #expect(second.rows.map(\.id) == [5, 3, 9, 1] && second.pagesRead == 2)
    #expect(!second.hasMore && !second.isComplete)
    let whole = GroupMemberList(pages: [page([5, 3, 9], total: 3)], serverSorted: true, now: now)
    #expect(!whole.hasMore && whole.isComplete)
}

@Test func memberListStopsAtTheLastPageOrTheCap() {
    let many = (1...GroupMemberList.maxPages).map { page([$0], total: 30, page: $0, pages: 30) }
    let capped = GroupMemberList(pages: many, serverSorted: true, now: now)
    #expect(capped.pagesRead == GroupMemberList.maxPages && !capped.hasMore)
    #expect(GroupMemberList.maxPages == 20 && GroupMemberList.pageSize == 100)
}

@Test func memberListSortsLocallyWithoutServerOrder() {
    let rows = AccountListPage(items: [account(1, "A"), account(2, "B", status: "error")], total: 3, page: 1, pageSize: 100, pages: 2)
    let local = GroupMemberList(pages: [rows], serverSorted: false, now: now)
    #expect(local.rows.map(\.id) == [2, 1])
    let more = AccountListPage(items: [account(3, "C", rateLimit: at(60))], total: 3, page: 2, pageSize: 100, pages: 2)
    #expect(local.appending(more, now: now).rows.map(\.id) == [2, 3, 1])
}

// MARK: 2.3 成员今日（U38）

@Test func memberTodayScopeNeedsThisGroupEchoed() {
    #expect(GroupMemberToday.empty.scope == nil)
    let echoed = GroupMemberToday.empty.merging(AccountTodayStatsBatch(stats: [1: today("1")], groupID: 4), requested: [1], groupID: 4)
    #expect(echoed.scope == .group)
    #expect(GroupMemberToday.empty.merging(AccountTodayStatsBatch(stats: [1: today("1")]), requested: [1], groupID: 4).scope == .site)
    #expect(GroupMemberToday.empty.merging(AccountTodayStatsBatch(stats: [1: today("1")], groupID: 9), requested: [1], groupID: 4).scope == .site)
    let unavailable = echoed.merging(AccountTodayStatsBatch(failedIDs: [1, 2]), requested: [1, 2], groupID: 4)
    #expect(unavailable.scope == .group)
    #expect(GroupMemberToday.empty.merging(AccountTodayStatsBatch(failedIDs: [1]), requested: [1], groupID: 4).scope == nil)
}

@Test func memberTodayCellsShowDashForFailures() {
    let batch = AccountTodayStatsBatch(stats: [1: today("380.98"), 2: today("12")], failedIDs: [3], groupID: 1)
    let read = GroupMemberToday.empty.merging(batch, requested: [1, 2, 3, 4], groupID: 1)
    #expect(read.cell(for: 1) == .value(Decimal(string: "380.98")!))
    #expect(read.cell(for: 3) == .failed && read.cell(for: 4) == .failed)
    let again = read.merging(AccountTodayStatsBatch(stats: [3: today("5")], failedIDs: [2], groupID: 1), requested: [2, 3], groupID: 1)
    #expect(again.cell(for: 3) == .value(5) && again.cell(for: 2) == .failed && again.cell(for: 1) == .value(Decimal(string: "380.98")!))
}

// MARK: 2.2 Key 与订阅数

@Test func keyCountsFromStatsOrFallback() {
    let served = GroupKeyCounts(GroupStats(totalAPIKeys: 38, activeAPIKeys: 36, subscriptionsTotal: 0, subscriptionsActive: 0))
    #expect(served == GroupKeyCounts(totalAPIKeys: 38, activeAPIKeys: 36, subscriptionsTotal: 0, subscriptionsActive: 0))
    let fallback = GroupKeyCounts(fallbackTotalAPIKeys: 3, activeSubscriptions: nil)
    #expect(fallback.totalAPIKeys == 3 && fallback.activeAPIKeys == nil && fallback.subscriptionsTotal == nil && fallback.subscriptionsActive == nil)
    #expect(GroupKeyCounts(fallbackTotalAPIKeys: nil, activeSubscriptions: 12).subscriptionsActive == 12)
}

// MARK: 2.3 / 2.6 成员摘要

@Test func nextWindowEndIsTheSoonestRunningWindowOfAnyMember() {
    let both = GroupMemberSnapshot(account(1, overload: at(72), rateLimit: at(300)))
    let temp = GroupMemberSnapshot(account(2, temp: at(1_380)))
    let past = GroupMemberSnapshot(account(3, rateLimit: at(-10)))
    #expect(GroupMemberSummary(members: [temp, both, past], now: now).nextWindowEnd == now.addingTimeInterval(72))
    #expect(GroupMemberSummary(members: [past, GroupMemberSnapshot(account(4))], now: now).nextWindowEnd == nil)
}

@Test func todayFootnoteOnlyWhenARowShowsToday() {
    #expect(!GroupMemberSummary(members: [], now: now).showsTodayFootnote)
    let unavailable = [account(1, status: "error"), account(2, rateLimit: at(60)), account(3, schedulable: false, overload: at(60))]
    #expect(!GroupMemberSummary(members: unavailable.map(GroupMemberSnapshot.init), now: now).showsTodayFootnote)
    for shown in [account(4), account(5, schedulable: false), account(6, status: "inactive")] {
        #expect(GroupMemberSummary(members: (unavailable + [shown]).map(GroupMemberSnapshot.init), now: now).showsTodayFootnote)
    }
}

// MARK: S5-08 计数回写

@Test func applyingCountsReplacesTheFiveCountsOnly() {
    let group = AdminGroup(id: 1, name: "高级组", platform: "anthropic", accountCount: 3, activeAccountCount: 2, rateLimitedAccountCount: 1,
                           sortOrder: 1, errorAccountCount: 0, idleAccountCount: 0)
    let counts = GroupAccountCounts(accountCount: 4, activeAccountCount: 3, rateLimitedAccountCount: 0, errorAccountCount: nil, idleAccountCount: 1)
    let written = group.applyingCounts(counts)
    #expect(written.counts == counts && written.errorAccountCount == nil && written.idleAccountCount == 1)
    #expect(written.name == group.name && written.sortOrder == 1 && group.accountCount == 3)
    #expect(written.matchesIgnoringCounts(group))
    var renamed = written
    renamed.name = "高级组 2"
    #expect(!renamed.matchesIgnoringCounts(group))
}

// MARK: 审查修正：成员行的本组名、旧服务端的订阅退路

@Test func memberRowsNameThisGroupFromThePageBeforeTheDirectoryLoads() {
    let home = AdminGroup(id: 1, name: "高级组", platform: "anthropic")
    // A lite row embeds no group names (dto.AccountListItem), so until the directory loads only the page knows this group's name.
    let shared = UpstreamAccount(id: 7, name: "Claude-官方-01", platform: "anthropic", type: "oauth", groupIDs: [1, 5])
    let only = UpstreamAccount(id: 8, name: "Claude-官方-02", platform: "anthropic", type: "oauth", groupIDs: [1])
    func line(_ account: UpstreamAccount, _ names: [Int: String]) -> String {
        AccountRowPresentation.secondLine(account, omit: .group, home: home.name, catalog: .builtin,
                                          directory: { GroupMemberList.groupName($0, home: home, directory: { names[$0] }) })
    }
    #expect(line(shared, [:]) == "Anthropic · 另属 #5 · OAuth")
    #expect(line(only, [:]) == "Anthropic · OAuth")
    #expect(line(shared, [1: "高级组", 5: "Claude Code 组"]) == "Anthropic · 另属 Claude Code 组 · OAuth")
    // A directory still holding the old name does not turn this group into “另属”.
    #expect(line(shared, [1: "旧名", 5: "Claude Code 组"]) == "Anthropic · 另属 Claude Code 组 · OAuth")
}

private actor KeyCountCalls {
    private(set) var calls: [String] = []
    private(set) var isSubscription: Bool?
    init(isSubscription: Bool?) { self.isSubscription = isSubscription }
    func record(_ call: String) { calls.append(call) }
    func learn(isSubscription: Bool) { self.isSubscription = isSubscription }
}

private func readKeyCounts(_ log: KeyCountCalls, stats: GroupStats?, learnsWhileStatsRuns: Bool? = nil) async throws -> GroupKeyCounts {
    try await GroupKeyCounts.read(
        stats: {
            await log.record("stats")
            if let learnsWhileStatsRuns { await log.learn(isSubscription: learnsWhileStatsRuns) }
            return stats
        },
        apiKeyCount: { await log.record("keys"); return 3 },
        activeSubscriptions: { await log.record("subscriptions"); return 12 },
        isSubscription: { await log.isSubscription })
}

@Test func keyCountsAskWhetherItIsASubscriptionGroupOnlyOnceStatsSaidOldServer() async throws {
    // Entered from elsewhere: the group's own read answers while stats is out.
    let entered = KeyCountCalls(isSubscription: nil)
    #expect(try await readKeyCounts(entered, stats: nil, learnsWhileStatsRuns: true) == GroupKeyCounts(fallbackTotalAPIKeys: 3, activeSubscriptions: 12))
    #expect(await entered.calls == ["stats", "keys", "subscriptions"])
    // Still unknown: read the count anyway (the subscription row only shows for a subscription group).
    let unknown = KeyCountCalls(isSubscription: nil)
    #expect(try await readKeyCounts(unknown, stats: nil).subscriptionsActive == 12)
    let standard = KeyCountCalls(isSubscription: false)
    #expect(try await readKeyCounts(standard, stats: nil) == GroupKeyCounts(fallbackTotalAPIKeys: 3, activeSubscriptions: nil))
    #expect(await standard.calls == ["stats", "keys"])
    let served = GroupStats(totalAPIKeys: 38, activeAPIKeys: 36, subscriptionsTotal: 2, subscriptionsActive: 1)
    let newer = KeyCountCalls(isSubscription: true)
    #expect(try await readKeyCounts(newer, stats: served) == GroupKeyCounts(served))
    #expect(await newer.calls == ["stats"])
}
