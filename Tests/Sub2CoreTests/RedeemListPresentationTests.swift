import Foundation
import Testing
@testable import Sub2Core

// 60 §8.2–§8.6 and §11.3: the list's filters and queries, paging, sections, empty states, subtitle, banner and failures.

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private func instant(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private let now = instant("2026-10-16T09:41:00+08:00")
private let batch = UUID(uuidString: "0A000000-0000-4000-8000-000000000002")!
private let site = UUID(uuidString: "5A000000-0000-4000-8000-000000000001")!
private let oldLogin = UUID(uuidString: "0D000000-0000-4000-8000-000000000001")!
private let otherAddress = UUID(uuidString: "6B1F3C2A-0D4E-4F5A-8B9C-1D2E3F4A5B6C")!

private func row(_ id: Int, type: String = "balance", createdAt: Date? = now, code: String = "a3f01b2c3d4e5f60718293a4b5c6d4e8") -> AdminRedeemCode {
    AdminRedeemCode(id: id, code: code, type: type, value: 10, status: "unused", createdAt: createdAt)
}
private func page(_ items: [AdminRedeemCode], page: Int = 1, total: Int? = nil, hasMore: Bool = false) -> Page<AdminRedeemCode> {
    Page(items: items, total: total, page: page, pageSize: RedeemListPolicy.pageSize, pages: nil, hasMore: hasMore)
}
private func items(_ query: RedeemCodeListQuery, page: Int = 1) throws -> [String: String] {
    Dictionary(uniqueKeysWithValues: try query.queryItems(page: page).map { ($0.name, $0.value ?? "") })
}
private func statsItems(_ query: RedeemCodeListQuery?) -> [String: String]? {
    query.map { Dictionary(uniqueKeysWithValues: $0.statsQueryItems().map { ($0.name, $0.value ?? "") }) }
}
private func pendingBatch(_ id: UUID = batch, serverID: UUID = site, minutesAgo: Double = 5, spec: RedeemGenerateSpec = RedeemGenerateSpec(type: .balance, value: 10, count: 20))
    -> PendingRedeemBatch {
    PendingRedeemBatch(id: id, serverID: serverID, actorUserID: 1, createdAt: now.addingTimeInterval(-minutesAgo * 60), spec: spec)
}
private func banner(_ records: [any PendingMoneyWrite], sameAddress: Set<UUID> = [site, oldLogin]) -> RedeemPendingBanner? {
    RedeemPendingBanner.make(records: records, currentServerID: site, sameAddress: sameAddress, now: now, timeZone: shanghai)
}

// MARK: Filters and queries

@Test func redeemListQueryAllTypesSendsTypesWithStats() throws {
    let query = RedeemListFilter().listQuery(supportsStats: true)
    #expect(try items(query) == ["page": "1", "page_size": "50", "sort_by": "id", "sort_order": "desc",
                                 "types": "balance,concurrency,subscription,invitation"])
    #expect(!query.excludesAdminAdjustments)
    #expect(statsItems(RedeemListFilter().statsQuery(supportsStats: true)) == ["types": "balance,concurrency,subscription,invitation"])
}

@Test func redeemListQueryWithoutStatsOmitsTypes() throws {
    let query = RedeemListFilter().listQuery(supportsStats: false)
    #expect(try items(query) == ["page": "1", "page_size": "50", "sort_by": "id", "sort_order": "desc"])
    #expect(query.excludesAdminAdjustments)
    #expect(!query.admits(row(1, type: "admin_balance")) && query.admits(row(2)))
    #expect(RedeemListFilter().statsQuery(supportsStats: false) == nil)
    #expect(RedeemListFilter.totalQuery(supportsStats: false) == nil)
}

@Test func redeemListSingleTypeNeverSendsTypeWithTypes() throws {
    let filter = RedeemListFilter(type: .concurrency)
    let withStats = try items(filter.listQuery(supportsStats: true))
    #expect(withStats["types"] == "concurrency" && withStats["type"] == nil)
    let without = try items(filter.listQuery(supportsStats: false))
    #expect(without["type"] == "concurrency" && without["types"] == nil)
    // Only “全部类型” on an old server drops the admin rows on the phone.
    #expect(!filter.listQuery(supportsStats: false).excludesAdminAdjustments)
}

@Test func redeemListStatsQueryIgnoresStatus() throws {
    let filter = RedeemListFilter(search: "  wang@example.com ", status: .used, type: .balance)
    let list = try items(filter.listQuery(supportsStats: true))
    #expect(list["status"] == "used" && list["search"] == "wang@example.com" && list["types"] == "balance")
    #expect(statsItems(filter.statsQuery(supportsStats: true)) == ["search": "wang@example.com", "types": "balance"])
    // The subtitle's total is every code of the four types, whatever the search.
    #expect(statsItems(RedeemListFilter.totalQuery(supportsStats: true)) == ["types": "balance,concurrency,subscription,invitation"])
    #expect(filter.trimmedSearch == "wang@example.com")
    #expect(!filter.isUnfiltered && RedeemListFilter(search: "   ").isUnfiltered)
}

@Test func redeemListSameBatchSendsOnlyBatchID() throws {
    let filter = RedeemListFilter(search: "a3f0", status: .unused, type: .balance).showingBatch(batch)
    #expect(filter.batch == RedeemBatchChip(batchID: batch))
    #expect(try items(filter.listQuery(supportsStats: true)) == ["page": "1", "page_size": "50", "sort_by": "id", "sort_order": "desc",
                                                                 "batch_id": "0a000000-0000-4000-8000-000000000002"])
    #expect(try items(filter.listQuery(supportsStats: false))["batch_id"] != nil)
    #expect(!filter.listQuery(supportsStats: false).excludesAdminAdjustments)
    #expect(filter.statsQuery(supportsStats: true) == nil)
    #expect(filter.search.isEmpty && filter.status == nil && filter.type == nil)
}

@Test func redeemListRouteValuesBecomeFilter() {
    let filter = RedeemListFilter(route: "abc", status: "expired", type: "subscription")
    #expect(filter == RedeemListFilter(search: "abc", status: .expired, type: .subscription))
    #expect(RedeemListFilter(route: nil, status: "all", type: "admin_balance") == RedeemListFilter())
    #expect(RedeemListFilter(route: "", status: nil, type: nil).isUnfiltered)
}

// MARK: Pages

@Test func redeemListMergeDedupesByID() {
    let query = RedeemListFilter().listQuery(supportsStats: true)
    let first = RedeemListPage.empty.merging(page([row(9), row(8), row(7)], total: 5, hasMore: true), query: query)
    #expect(first.codes.map(\.id) == [9, 8, 7] && first.lastServerPage == 1 && first.hasMore && first.serverTotal == 5)
    // A new code pushed 7 onto page 2; the later copy replaces the earlier one in place.
    let renamed = AdminRedeemCode(id: 7, code: "ffff", type: "balance", value: 10, status: "disabled", createdAt: now)
    let second = first.merging(page([renamed, row(6)], page: 2, total: 6), query: query)
    #expect(second.codes.map(\.id) == [9, 8, 7, 6] && second.codes[2].status == "disabled")
    #expect(second.lastServerPage == 2 && !second.hasMore && second.serverTotal == 6 && second.nextServerPage == 3)
    // Page 1 again replaces everything.
    let reloaded = second.merging(page([row(10), row(9)], total: 7), query: query)
    #expect(reloaded.codes.map(\.id) == [10, 9] && reloaded.lastServerPage == 1)
    #expect(reloaded.contains(id: 10) && !reloaded.contains(id: 6))
}

@Test func redeemListMergeAppliesRowFilter() {
    let query = RedeemListFilter().listQuery(supportsStats: false)
    let merged = RedeemListPage.empty.merging(page([row(5), row(4, type: "admin_balance"), row(3, type: "admin_concurrency"), row(2, type: "invitation")],
                                                   total: 40, hasMore: true), query: query)
    #expect(merged.codes.map(\.id) == [5, 2] && merged.hasMore && merged.serverTotal == 40)
    #expect(RedeemListPage.admittedCount(of: page([row(4, type: "admin_balance"), row(1)]), query: query) == 1)
}

@Test func redeemListShortPageKeepsLoading() {
    let old = RedeemListFilter().listQuery(supportsStats: false)
    let short = page([row(1)], hasMore: true)
    #expect(RedeemListPolicy.continuesAutomatically(after: short, query: old, automaticReads: 0))
    #expect(RedeemListPolicy.continuesAutomatically(after: short, query: old, automaticReads: 2))
    #expect(!RedeemListPolicy.continuesAutomatically(after: short, query: old, automaticReads: 3))
    #expect(!RedeemListPolicy.continuesAutomatically(after: page([row(1)], hasMore: false), query: old, automaticReads: 0))
    let full = page((1...50).map { row($0) }, hasMore: true)
    #expect(!RedeemListPolicy.continuesAutomatically(after: full, query: old, automaticReads: 0))
    // With types the server leaves the admin rows out: a short page is the end.
    #expect(!RedeemListPolicy.continuesAutomatically(after: short, query: RedeemListFilter().listQuery(supportsStats: true), automaticReads: 0))
}

@Test func redeemListStaleAfterSixtySeconds() {
    #expect(RedeemListPolicy.isStale(lastLoadedAt: nil, now: now))
    #expect(!RedeemListPolicy.isStale(lastLoadedAt: now.addingTimeInterval(-59), now: now))
    #expect(RedeemListPolicy.isStale(lastLoadedAt: now.addingTimeInterval(-60), now: now))
    #expect(RedeemListPolicy.isStale(lastLoadedAt: now.addingTimeInterval(30), now: now))
    #expect(RedeemListPolicy.pageSize == 50 && RedeemListPolicy.searchDebounce == .milliseconds(300))
}

@Test func redeemListPageLocalEdits() {
    let loaded = RedeemListPage.empty.merging(page([row(3), row(2), row(1)]), query: RedeemListFilter().listQuery(supportsStats: true))
    let disabled = AdminRedeemCode(id: 2, code: "b", type: "balance", value: 10, status: "disabled", createdAt: now)
    #expect(loaded.replacing(disabled).codes.map(\.status) == ["unused", "disabled", "unused"])
    #expect(loaded.replacing(row(9)).codes.map(\.id) == [3, 2, 1])
    #expect(loaded.removing(id: 2).codes.map(\.id) == [3, 1])
}

// MARK: Layout

@Test func redeemListSectionsFollowServerDayBoundary() {
    let codes = [row(6, createdAt: instant("2026-10-16T00:10:00+08:00")), row(5, createdAt: instant("2026-10-15T23:50:00+08:00")),
                 row(4, createdAt: instant("2026-10-15T08:00:00+08:00")), row(3, createdAt: instant("2026-10-14T09:00:00+08:00")),
                 row(2, createdAt: nil), row(1, createdAt: instant("2026-10-16T09:00:00+08:00"))]
    let sections = RedeemListLayout.sections(codes, now: now, timeZone: shanghai)
    #expect(sections.map(\.group) == [.today, .yesterday, .earlier])
    #expect(sections.map { $0.codes.map(\.id) } == [[6, 1], [5, 4], [3, 2]])
    #expect(sections.map(\.title) == ["今天生成", "昨天生成", "更早生成"])
    #expect(sections.map(\.countText) == ["2", "2", "2"])
    // 00:10 Shanghai is still the 15th in UTC: the server's calendar decides.
    #expect(RedeemListLayout.sections([codes[0]], now: now, timeZone: TimeZone(identifier: "UTC")!).map(\.group) == [.yesterday])
    #expect(RedeemListLayout.sections([], now: now, timeZone: shanghai).isEmpty)
}

@Test func redeemListPinnedOnlyWhenNotLoaded() {
    let loaded = [row(3), row(2)]
    #expect(RedeemListLayout.pinned(row(1), in: loaded)?.id == 1)
    #expect(RedeemListLayout.pinned(row(2), in: loaded) == nil)
    #expect(RedeemListLayout.pinned(nil, in: loaded) == nil)
}

// MARK: Text

@Test func redeemListSubtitleCountsOnlyWithTotal() {
    #expect(RedeemListText.subtitle(siteName: "主站", total: 128) == "主站 · 128 个")
    #expect(RedeemListText.subtitle(siteName: "主站", total: 12_800) == "主站 · 12,800 个")
    #expect(RedeemListText.subtitle(siteName: "主站", total: nil) == "主站")
    #expect(RedeemListText.title == "兑换码" && RedeemListText.searchPrompt == "搜索兑换码或邮箱")
    #expect(RedeemListText.copiedReceipt == "已复制兑换码" && RedeemListText.locatedGone == "这个兑换码已被删除")
    #expect(RedeemListText.loadMoreFailed == "加载失败 · 重试")
}

@Test func redeemListEmptyStatesFollowTheTable() {
    #expect(RedeemListEmpty.resolve(codes: [], filter: RedeemListFilter(), siteTotal: nil) == .noCodes)
    #expect(RedeemListEmpty.resolve(codes: [], filter: RedeemListFilter(search: " q "), siteTotal: 12) == .noSearchMatch("q"))
    #expect(RedeemListEmpty.resolve(codes: [], filter: RedeemListFilter(status: .expired), siteTotal: 12) == .noTypeMatch)
    #expect(RedeemListEmpty.resolve(codes: [], filter: RedeemListFilter(type: .invitation), siteTotal: nil) == .noTypeMatch)
    // A site without codes says so whatever the chip; a search keeps its own wording.
    #expect(RedeemListEmpty.resolve(codes: [], filter: RedeemListFilter(status: .used), siteTotal: 0) == .noCodes)
    #expect(RedeemListEmpty.resolve(codes: [], filter: RedeemListFilter(search: "q"), siteTotal: 0) == .noSearchMatch("q"))
    #expect(RedeemListEmpty.resolve(codes: nil, filter: RedeemListFilter(), siteTotal: 0) == nil)
    #expect(RedeemListEmpty.resolve(codes: [row(1)], filter: RedeemListFilter(), siteTotal: 1) == nil)
    #expect(RedeemListEmpty.noCodes.title == "还没有兑换码")
    #expect(RedeemListEmpty.noSearchMatch("a3f0").title == "没有匹配“a3f0”的兑换码")
    #expect(RedeemListEmpty.noTypeMatch.title == "没有这类兑换码")
}

@Test func redeemListBatchChipTitle() {
    let chip = RedeemBatchChip(batchID: batch)
    #expect(chip.title(total: 20) == "同一批 · 20 个")
    #expect(chip.title(total: nil) == "同一批")
    #expect(chip.removeLabel(total: 20) == "移除筛选 同一批 · 20 个")
}

// MARK: Banner (11.3, X34)

@Test func redeemListBannerEarliestBatchWithTotal() throws {
    let shown = try #require(banner([pendingBatch()]))
    #expect(shown.batchID == batch)
    #expect(shown.title == "兑换码生成结果待核对")
    #expect(shown.amountLine == "20 个 × $10.00 · 合计 $200.00")
    #expect(shown.timeLine == "5 分钟前发起，未确认是否已生成")
    #expect(shown.origin == .currentSite)
}

@Test func redeemListBannerNonBalanceHasNoTotal() throws {
    let concurrency = try #require(banner([pendingBatch(spec: RedeemGenerateSpec(type: .concurrency, value: 2, count: 5))]))
    #expect(concurrency.amountLine == "5 个 × +2 并发")
    let subscription = RedeemGenerateSpec(type: .subscription, value: 0, count: 5, groupID: 4, groupName: "企业专线", validityDays: 30)
    #expect(try #require(banner([pendingBatch(spec: subscription)])).amountLine == "5 个 × 企业专线 · 30 天")
    #expect(try #require(banner([pendingBatch(spec: RedeemGenerateSpec(type: .invitation, value: 0, count: 10))])).amountLine == "10 个 × 注册邀请")
}

@Test func redeemListBannerCountsSameAddressBatches() throws {
    let newer = pendingBatch(UUID(), minutesAgo: 1)
    let older = pendingBatch(UUID(), minutesAgo: 30, spec: RedeemGenerateSpec(type: .balance, value: 5, count: 10))
    let refund = PendingBalanceOperation(id: UUID(), serverID: site, userID: 1, amount: 5, operation: .subtract, actorUserID: 1,
                                         createdAt: now.addingTimeInterval(-3_600))
    let elsewhere = pendingBatch(UUID(), serverID: otherAddress, minutesAgo: 90)
    let shown = try #require(banner([newer, refund, older, elsewhere]))
    #expect(shown.batchID == older.id)
    #expect(shown.title == "兑换码生成结果待核对等 2 批")
    #expect(shown.amountLine == "10 个 × $5.00 · 合计 $50.00")
    #expect(shown.timeLine == "30 分钟前发起，未确认是否已生成")
}

@Test func redeemListBannerMarksOldLogin() throws {
    let shown = try #require(banner([pendingBatch(serverID: oldLogin, minutesAgo: 10)]))
    #expect(shown.origin == .sameAddressOldLogin)
    #expect(shown.timeLine == "10 分钟前发起，未确认是否已生成 · 这笔在本站点的旧登录下发起")
    let today = try #require(banner([pendingBatch(minutesAgo: 120)]))
    #expect(today.timeLine == "今天 07:41 发起，未确认是否已生成")
}

@Test func redeemListBannerNilWithoutBatches() {
    #expect(banner([]) == nil)
    let refund = PendingBalanceOperation(id: UUID(), serverID: site, userID: 1, amount: 5, operation: .subtract, actorUserID: 1, createdAt: now)
    #expect(banner([refund]) == nil)
    #expect(banner([pendingBatch(serverID: otherAddress)]) == nil)
}

// MARK: Failures

@Test func redeemListFailureClassifiesReasons() {
    for reason in ["REDEEM_CODE_TYPE_INVALID", "REDEEM_CODE_TYPE_CONFLICT", "REDEEM_BATCH_ID_INVALID"] {
        #expect(RedeemListFailure(APIError.server(status: 400, reason: reason)) == .parameter(reason: reason))
    }
    #expect(RedeemListFailure(APIError.server(status: 404, reason: "REDEEM_CODE_NOT_FOUND")) == .notFound)
    #expect(RedeemListFailure(APIError.server(status: 404, envelope: nil)) == .other)
    #expect(RedeemListFailure(APIError.server(status: 400, reason: "VALIDATION_ERROR")) == .other)
    #expect(RedeemListFailure(APIError.server(status: 502, reason: nil)) == .other)
    #expect(RedeemListFailure(CancellationError()) == .other)
}

@Test func redeemListNoCodeValueInDescriptions() throws {
    let secret = "a3f01b2c3d4e5f60718293a4b5c6d4e8"
    let filter = RedeemListFilter(search: secret, status: .unused)
    #expect(!String(reflecting: filter).contains(secret) && !String(describing: filter).contains(secret))
    #expect(!String(reflecting: RedeemListFailure.parameter(reason: "REDEEM_CODE_TYPE_INVALID")).contains(secret))
    let shown = try #require(banner([pendingBatch()]))
    #expect(![shown.title, shown.amountLine, shown.timeLine].joined().contains(secret))
}
