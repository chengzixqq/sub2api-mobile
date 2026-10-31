import Foundation
import Testing
@testable import Sub2Core

private func quick(_ id: Int, _ name: String? = nil, balance: Decimal? = 10) -> QuickTopupUser {
    QuickTopupUser(userID: id, email: "user\(id)@example.invalid", username: name, status: "active", balance: balance)
}
private func user(_ id: Int, balance: Decimal = 10) -> AdminUser {
    AdminUser(id: id, email: "user\(id)@example.invalid", username: "用户 \(id)", balance: balance)
}
private func page(_ ids: [Int], page: Int, total: Int?, pages: Int?, hasMore: Bool? = nil) -> Page<AdminUser> {
    Page(items: ids.map { user($0) }, total: total, page: page, pageSize: 20, pages: pages, hasMore: hasMore)
}
private let site = UUID(), older = UUID(), elsewhere = UUID()
private func pending(_ userID: Int, _ operation: BalanceOperation, _ amount: Decimal, server: UUID = site, minutesAgo: Double) -> PendingBalanceOperation {
    PendingBalanceOperation(serverID: server, userID: userID, amount: amount, operation: operation, actorUserID: 1,
                            createdAt: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60))
}

// MARK: - 快捷充值头像条（30 §1.3）

@Test func quickTopupPutsRecentFirstThenUnseenLowBalance() {
    let entries = UserListPresentation.quickTopupEntries(recent: [quick(3), quick(10), quick(1), quick(4)],
                                                         lowBalance: [quick(4), quick(7), quick(11), quick(12)], pendingNouns: [:])
    #expect(entries.map(\.id) == [3, 10, 1, 4, 7, 11, 12])
    #expect(entries.allSatisfy { !$0.isPending })
}

@Test func quickTopupMovesPendingUsersLastKeepingOrder() {
    let entries = UserListPresentation.quickTopupEntries(recent: [quick(3), quick(10), quick(1), quick(4)],
                                                         lowBalance: [quick(4), quick(7), quick(11), quick(12)],
                                                         pendingNouns: [3: "充值", 1: "退款"])
    #expect(entries.map(\.id) == [10, 4, 7, 11, 12, 3, 1])
    #expect(entries.suffix(2).map(\.pendingNoun) == ["充值", "退款"])
    #expect(entries.suffix(2).allSatisfy { $0.isPending })
}

@Test func quickTopupEmptyWhenBothListsEmpty() {
    #expect(UserListPresentation.quickTopupEntries(recent: [], lowBalance: [], pendingNouns: [1: "充值"]).isEmpty)
}

@Test func quickTopupCaptionAndSpokenLabel() {
    let wang = quick(3, "王小明", balance: Decimal(string: "12.40")!)
    let plain = UserListPresentation.quickTopupEntries(recent: [wang], lowBalance: [], pendingNouns: [:])[0]
    #expect(plain.displayName == "王小明")
    #expect(plain.initial == "王")
    #expect(plain.caption == "$12.40")
    #expect(plain.spokenLabel == "给王小明充值，余额 $12.40")
    let topup = UserListPresentation.quickTopupEntries(recent: [wang], lowBalance: [], pendingNouns: [3: "充值"])[0]
    #expect(topup.caption == "去核对")
    #expect(topup.spokenLabel == "王小明，上一笔充值待核对，打开详情去核对")
    let refund = UserListPresentation.quickTopupEntries(recent: [wang], lowBalance: [], pendingNouns: [3: "退款"])[0]
    #expect(refund.spokenLabel == "王小明，上一笔退款待核对，打开详情去核对")
    let missing = UserListPresentation.quickTopupEntries(recent: [quick(3, "王小明", balance: nil)], lowBalance: [], pendingNouns: [:])[0]
    #expect(missing.caption == "—")
    #expect(missing.spokenLabel == "给王小明充值，余额无数据")
}

@Test func quickTopupDisplayNameAndInitial() {
    let entries = UserListPresentation.quickTopupEntries(recent: [quick(1, "  alice "), quick(2, "   ")], lowBalance: [], pendingNouns: [:])
    #expect(entries.map(\.displayName) == ["alice", "user2"])
    #expect(entries.map(\.initial) == ["A", "U"])
}

@Test func quickTopupReplyUpdatesBalanceAndRemovesUser() {
    let reply = QuickTopupReply(recent: [quick(3), quick(1)], lowBalance: [quick(3), quick(7)], lowBalanceEnabled: true)
    let updated = reply.updatingBalance(id: 3, balance: 50)
    #expect(updated.recent.map(\.balance) == [50, 10])
    #expect(updated.lowBalance.map(\.balance) == [50, 10])
    #expect(updated.lowBalanceEnabled == true)
    #expect(reply.recent.map(\.balance) == [10, 10])
    let removed = reply.removing(id: 3)
    #expect(removed.recent.map(\.userID) == [1])
    #expect(removed.lowBalance.map(\.userID) == [7])
}

// MARK: - 待核对名词（R02、S3D1-20）

@Test func pendingNounFollowsBalanceDirections() {
    #expect(UserListPresentation.pendingNoun(for: pending(1, .add, 50, minutesAgo: 1)) == "充值")
    #expect(UserListPresentation.pendingNoun(for: pending(1, .subtract, Decimal(string: "12.5")!, minutesAgo: 1)) == "退款")
    #expect(UserListPresentation.pendingNoun(for: pending(1, .set, 0, minutesAgo: 1)) == "退款")
    #expect(UserListPresentation.pendingNoun(for: pending(1, .set, 20, minutesAgo: 1)) == "余额设置")
}

@Test func pendingNounsTakeEachUsersOldestRecordAtTheAddress() {
    let records = [pending(1, .add, 5, minutesAgo: 1), pending(1, .subtract, 3, server: older, minutesAgo: 9),
                   pending(3, .add, 8, minutesAgo: 2), pending(4, .add, 8, server: elsewhere, minutesAgo: 3)]
    #expect(UserListPresentation.pendingNouns(records, serverIDs: [site, older]) == [1: "退款", 3: "充值"])
    #expect(UserListPresentation.pendingNouns(records, serverIDs: []).isEmpty)
}

// MARK: - 今日消费（30 §1.2、§1.3、§1.5，R14）

@Test func todayCellUnavailableForReadOnlyToken() {
    let cell = UserListPresentation.todayCell(userID: 1, costs: [1: Decimal(string: "2.80")!], isReadOnlyToken: true)
    #expect(cell == .unavailable)
    #expect(cell.text == "今日 —")
}

@Test func todayCellBeforeArrivalAndMissingID() {
    #expect(UserListPresentation.todayCell(userID: 1, costs: [:], isReadOnlyToken: false) == .unavailable)
    let reply = [1: UserTodayUsage(userID: 1, todayActualCost: Decimal(string: "2.80")!), 3: UserTodayUsage(userID: 3, todayActualCost: nil)]
    let costs = UserListPresentation.mergingTodayCosts(reply, requested: [1, 2, 3], into: [9: 1])
    #expect(UserListPresentation.todayCell(userID: 1, costs: costs, isReadOnlyToken: false) == .amount(Decimal(string: "2.80")!))
    #expect(UserListPresentation.todayCell(userID: 1, costs: costs, isReadOnlyToken: false).text == "今日 $2.80")
    #expect(UserListPresentation.todayCell(userID: 2, costs: costs, isReadOnlyToken: false).text == "今日 $0.00")
    #expect(UserListPresentation.todayCell(userID: 3, costs: costs, isReadOnlyToken: false) == .unavailable)
    #expect(costs[9] == 1)
}

@Test func failedUsageBatchClearsOnlyItsIDs() {
    let costs = UserListPresentation.clearingTodayCosts([21, 22], from: [1: Decimal(string: "2.80")!, 21: 402, 22: 289])
    #expect(costs == [1: Decimal(string: "2.80")!])
    #expect(UserListPresentation.todayCell(userID: 21, costs: costs, isReadOnlyToken: false) == .unavailable)
}

@Test func usageBatchesSplitAtTwoHundredWithoutDuplicates() {
    let ids = Array((1...450).reversed()) + [7, 7, 0, -3]
    let batches = UserListPresentation.usageBatches(ids)
    #expect(batches.map(\.count) == [200, 200, 50])
    #expect(batches.flatMap { $0 } == Array(1...450))
    #expect(UserListQuery.usageBatchSize == 200)
    #expect(UserListPresentation.usageBatches([]).isEmpty)
}

@Test func todayCellTextAndSpoken() {
    #expect(UserTodayCell.unavailable.spokenText == "今日无数据")
    #expect(UserTodayCell.hidden.text == nil)
    #expect(UserTodayCell.hidden.spokenText == nil)
    let amount = UserTodayCell.amount(Decimal(string: "1020")!)
    #expect(amount.text == "今日 $1,020.00")
    #expect(amount.spokenText == amount.text)
}

// MARK: - 副标题、分页与本地写回（30 §1.3、§1.4、§1.6）

@Test func subtitleShowsSiteOnlyBeforeFirstLoad() {
    #expect(UserListPresentation.subtitle(siteName: "站点 A", total: nil) == "站点 A")
    #expect(UserListPresentation.subtitle(siteName: "站点 A", total: 26) == "站点 A · 26 位")
    #expect(UserListPresentation.subtitle(siteName: "站点 A", total: 1280) == "站点 A · 1,280 位")
}

@Test func snapshotAppendingDeduplicatesByID() {
    let first = UserListSnapshot(firstPage: page(Array(1...20), page: 1, total: 26, pages: 2))
    #expect(first.hasMore)
    let both = first.appending(page([20] + Array(21...26), page: 2, total: 26, pages: 2))
    #expect(both.rows.map(\.id) == Array(1...26))
    #expect(both.page == 2)
    #expect(!both.hasMore)
    #expect(first.rows.count == 20)
}

@Test func snapshotMergingFirstPageKeepsLaterPages() {
    let loaded = UserListSnapshot(firstPage: page(Array(1...20), page: 1, total: 26, pages: 2))
        .appending(page(Array(21...26), page: 2, total: 26, pages: 2))
    // User 27 at the top pushes 20 into the page already read; it stays, or it would be gone until the query changes.
    let merged = loaded.mergingFirstPage(page([27] + Array(1...19), page: 1, total: 27, pages: 2))
    #expect(merged.rows.map(\.id) == [27] + Array(1...26))
    #expect(merged.total == 27)
    #expect(merged.page == 2)
    #expect(merged.firstPageCount == 20)
    #expect(!merged.hasMore)
    let again = merged.mergingFirstPage(page([28, 27] + Array(1...18), page: 1, total: 28, pages: 2))
    #expect(again.rows.map(\.id) == [28, 27] + Array(1...26))
    // A row before the new page's last known row was left out by the server (deleted, no longer matching): it goes.
    let deleted = loaded.mergingFirstPage(page(Array(2...21), page: 1, total: 25, pages: 2))
    #expect(deleted.rows.map(\.id) == Array(2...26))
    #expect(deleted.firstPageCount == 20)
    let both = loaded.mergingFirstPage(page([27] + Array(1...4) + Array(6...20), page: 1, total: 26, pages: 2))
    #expect(both.rows.map(\.id) == [27] + Array(1...4) + Array(6...26))
    let fresh = UserListSnapshot(firstPage: page([1, 2], page: 1, total: 2, pages: 1)).mergingFirstPage(page([3, 1], page: 1, total: 2, pages: 1))
    #expect(fresh.rows.map(\.id) == [3, 1])
}

@Test func snapshotLocalWritesAreInPlace() {
    let snapshot = UserListSnapshot(firstPage: page([1, 2, 3], page: 1, total: 3, pages: 1))
    var renamed = user(2); renamed.username = "改名"
    let replaced = snapshot.replacing(renamed)
    #expect(replaced.rows.map(\.id) == [1, 2, 3])
    #expect(replaced.rows[1].username == "改名")
    #expect(snapshot.replacing(user(9)).rows.map(\.id) == [1, 2, 3])
    let removed = snapshot.removing(id: 2)
    #expect(removed.rows.map(\.id) == [1, 3])
    #expect(removed.total == 2)
    #expect(removed.firstPageCount == 2)
    #expect(snapshot.removing(id: 9) == snapshot)
    let topped = snapshot.updatingBalance(id: 3, balance: 99)
    #expect(topped.rows.map(\.balance) == [10, 10, 99])
    #expect(snapshot.rows.map(\.balance) == [10, 10, 10])
}

@Test func snapshotHasMoreFollowsPagesThenEnvelope() {
    #expect(UserListSnapshot(firstPage: page([1], page: 1, total: 40, pages: 2)).hasMore)
    #expect(!UserListSnapshot(firstPage: page([1], page: 1, total: 1, pages: 1)).hasMore)
    #expect(UserListSnapshot(firstPage: page([1], page: 1, total: nil, pages: nil, hasMore: true)).hasMore)
    #expect(!UserListSnapshot(firstPage: page([1], page: 1, total: nil, pages: nil, hasMore: false)).hasMore)
}

// MARK: - 失败、读屏与文案（30 §1.5，BACKLOG 缺失值读屏）

@Test func failureClassifiesForbiddenOnly() {
    #expect(UserListFailure(APIError.server(status: 403, reason: "FORBIDDEN")) == .forbidden)
    let readOnly = APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")
    #expect(UserListFailure(readOnly) == .failed(reason: readOnly.localizedDescription))
    let server = APIError.server(status: 500, envelope: ErrorEnvelope.decode(Data(#"{"code":500,"message":"dial tcp 10.0.0.1: secret"}"#.utf8)))
    #expect(UserListFailure(server) == .failed(reason: server.localizedDescription))
    #expect(!server.localizedDescription.contains("secret"))
}

@Test func rowSpokenLabelOrder() {
    let label = UserListPresentation.rowSpokenLabel(displayName: "Alice", email: "alice@example.com", balance: Decimal(string: "12.5")!,
                                                    mark: .pending, today: .amount(Decimal(string: "2.8")!))
    #expect(label == "Alice，alice@example.com，余额 $12.50，待核对，今日 $2.80")
    #expect(UserListPresentation.rowSpokenLabel(displayName: "Bob", email: "bob@example.com", balance: nil, mark: nil, today: .unavailable)
            == "Bob，bob@example.com，余额无数据，今日无数据")
    #expect(UserListPresentation.rowSpokenLabel(displayName: "赵磊", email: "lei@example.com", balance: 0, mark: nil, today: .hidden,
                                                showsDisabledBadge: true, trailingNote: "· Key 片段匹配")
            == "赵磊，lei@example.com，余额 $0.00，禁用，Key 片段匹配")
    #expect(UserListPresentation.rowSpokenLabel(displayName: "赵磊", email: "lei@example.com", balance: 0, mark: .disabled, today: .hidden,
                                                showsDisabledBadge: true) == "赵磊，lei@example.com，余额 $0.00，禁用")
}

@Test func noMatchTextAndStaleBanner() throws {
    #expect(UserListPresentation.noMatchText(query: "bob") == "没有匹配“bob”的用户")
    let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let at = try #require(ISO8601DateFormatter().date(from: "2026-10-26T06:05:00Z"))
    #expect(UserListPresentation.staleBanner(updatedAt: at, timeZone: shanghai) == "刷新失败 · 14:05 的数据")
    #expect(UserListPresentation.staleBanner(updatedAt: nil, timeZone: shanghai) == "刷新失败")
}

@Test func autoRefreshDelayCountsFromLastRefresh() {
    let now = Date(timeIntervalSince1970: 1_800_000_000), twentyAgo = now.addingTimeInterval(-20)
    #expect(UserListPresentation.autoRefreshDelay(lastRefreshAt: nil, refresh: BlockRefresh(), now: now) == 0)
    #expect(UserListPresentation.autoRefreshDelay(lastRefreshAt: twentyAgo, refresh: BlockRefresh(), now: now) == 40)
    let failed = BlockRefresh().recordingFailure(APIError.server(status: 500, reason: nil), at: twentyAgo)
    #expect(UserListPresentation.autoRefreshDelay(lastRefreshAt: twentyAgo, refresh: failed, now: now) == 100)
    let limited = BlockRefresh().recordingFailure(APIError.server(status: 429, envelope: ErrorEnvelope(reason: "RATE_LIMITED", retryAfter: 30),
                                                                  retryAfter: 30), at: twentyAgo)
    #expect(UserListPresentation.autoRefreshDelay(lastRefreshAt: twentyAgo, refresh: limited, now: now) == 10)
    #expect(UserListPresentation.autoRefreshDelay(lastRefreshAt: now.addingTimeInterval(-500), refresh: BlockRefresh(), now: now) == 0)
    #expect(UserListPresentation.autoRefreshInterval == 60)
}
