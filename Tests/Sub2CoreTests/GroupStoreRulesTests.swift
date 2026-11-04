import Foundation
import Testing
@testable import Sub2Core

// S5-04: GroupStore's rules (50 §1.2, §1.5, §1.6) and the group rows as VoiceOver reads them (50 §1.3, 60 §2).

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func group(_ id: Int, _ name: String = "分组", sortOrder: Int? = nil, error: Int? = 0) -> AdminGroup {
    AdminGroup(id: id, name: name, accountCount: 1, activeAccountCount: 1, sortOrder: sortOrder ?? id, errorAccountCount: error, idleAccountCount: error.map { _ in 0 })
}
private func usage(_ id: Int, _ today: String) -> GroupUsageSummary {
    GroupUsageSummary(groupID: id, todayCost: Decimal(string: today), yesterdayCost: 0, totalCost: 0)
}

@Test func usageRowsAreKeyedByGroupKeepingTheFirstRow() {
    let merged = GroupStoreRules.usageByGroup([usage(1, "933.30"), usage(1, "5"), usage(0, "1"), usage(-2, "1")])
    #expect(merged.keys.sorted() == [1])
    #expect(merged[1]?.todayCost == Decimal(string: "933.30"))
    #expect(GroupStoreRules.usageByGroup([]).isEmpty)
}

@Test func shortagesMapStatusSummaryGroupsByID() {
    let summary = AccountStatusSummary(groups: [
        AccountStatusGroupSummary(groupID: 2, shortage: .init(isShort: true, source: "alert_rule", threshold: 60, current: 50)),
        AccountStatusGroupSummary(groupID: 4, shortage: .init(isShort: true, source: "default")),
        AccountStatusGroupSummary(groupID: 1)
    ])
    let shortages = GroupStoreRules.shortages(in: summary)
    #expect(shortages.keys.sorted() == [1, 2, 4])
    #expect(shortages[2]?.isShort == true && shortages[2]?.isFromAlertRule == true)
    #expect(shortages[1]?.isShort == false)
    #expect(GroupStoreRules.shortages(in: AccountStatusSummary()).isEmpty)
}

@Test func errorFallbackFollowsCapabilityThenMissingKey() {
    #expect(GroupStoreRules.needsErrorFallback(groups: nil, hasAccountBuckets: false))
    #expect(GroupStoreRules.needsErrorFallback(groups: [group(1)], hasAccountBuckets: false))
    #expect(!GroupStoreRules.needsErrorFallback(groups: [group(1), group(2)], hasAccountBuckets: true))
    #expect(GroupStoreRules.needsErrorFallback(groups: [group(1), group(2, error: nil)], hasAccountBuckets: true))
    // The list is not read yet: with the capability the fallback waits for it.
    #expect(!GroupStoreRules.needsErrorFallback(groups: nil, hasAccountBuckets: true))
}

@Test func errorAccountsQueryAsksStatusErrorLiteThousand() throws {
    for supportsListQuery in [false, true] {
        let query = GroupStoreRules.errorAccountsQuery(supportsListQuery: supportsListQuery)
        let items = try query.queryItems(page: 1)
        #expect(items.contains(URLQueryItem(name: "status", value: "error")))
        #expect(items.contains(URLQueryItem(name: "lite", value: "1")))
        #expect(items.contains(URLQueryItem(name: "page_size", value: "1000")))
        #expect(!query.needsLocalStatusFilter)
        #expect(query.supportsListQuery == supportsListQuery)
    }
}

@Test func usageTimeZoneIsSentOnlyForVendor() throws {
    let shanghai = try #require(ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00"))
    #expect(GroupStoreRules.usageTimeZone(isVendor: true, siteZone: shanghai) == shanghai)
    #expect(GroupStoreRules.usageTimeZone(isVendor: false, siteZone: shanghai) == nil)
}

@Test func usageIsReusedForSixtySeconds() {
    #expect(GroupStoreRules.usageMaxAge == 60)
    #expect(GroupStoreRules.isFresh(now.addingTimeInterval(-59), now: now, maxAge: GroupStoreRules.usageMaxAge))
    #expect(!GroupStoreRules.isFresh(now.addingTimeInterval(-60), now: now, maxAge: GroupStoreRules.usageMaxAge))
    #expect(!GroupStoreRules.isFresh(nil, now: now, maxAge: GroupStoreRules.usageMaxAge))
}

@Test func localEditsAreLaidOverAReadInDisplayOrder() {
    let read = [group(1, "高级组"), group(2, "标准组"), group(3, "默认组")]
    #expect(GroupStoreRules.applying([], to: read) == read)
    let edits: [GroupListEdit] = [.upsert(group(2, "标准组（改）")), .upsert(group(12, "移动分组")), .remove(3)]
    let applied = GroupStoreRules.applying(edits, to: read)
    #expect(applied.map(\.id) == [1, 2, 12])
    #expect(applied.map(\.name) == ["高级组", "标准组（改）", "移动分组"])
    // sort_order first, then id.
    let reordered = GroupStoreRules.applying([.upsert(group(9, "置顶", sortOrder: 0))], to: read)
    #expect(reordered.map(\.id) == [9, 1, 2, 3])
}

@Test func autoRefreshCountsFromLastRefreshAndWaitsOut429() {
    let twentyAgo = now.addingTimeInterval(-20)
    #expect(GroupStoreRules.refreshInterval == 60)
    #expect(GroupStoreRules.autoRefreshDelay(lastRefreshAt: nil, refresh: BlockRefresh(), now: now) == 0)
    #expect(GroupStoreRules.autoRefreshDelay(lastRefreshAt: twentyAgo, refresh: BlockRefresh(), now: now) == 40)
    let failed = BlockRefresh().recordingFailure(APIError.server(status: 502, reason: nil), at: twentyAgo)
    #expect(GroupStoreRules.autoRefreshDelay(lastRefreshAt: twentyAgo, refresh: failed, now: now) == 100)
    let limited = BlockRefresh().recordingFailure(APIError.server(status: 429, envelope: ErrorEnvelope(reason: "RATE_LIMITED", retryAfter: 30),
                                                                  retryAfter: 30), at: now)
    #expect(GroupStoreRules.autoRefreshDelay(lastRefreshAt: now, refresh: limited, now: now) == 30)
}

@Test func rowSpeechReadsAvailabilityBreakdownBillingAndToday() {
    let spoken = GroupRowSpeech.full(name: "高级组", platformName: "Anthropic", isExclusive: false, badge: nil, available: 2, total: 3,
                                     breakdown: "受限 1", billingLine: "费率倍数 ×0.8 · 标准计费", today: .amount(Decimal(string: "933.30")!))
    #expect(spoken == "高级组，Anthropic，可用 2 / 3，受限 1，费率倍数 ×0.8 · 标准计费，今日 $933.30")
}

@Test func rowSpeechReadsExclusiveBadgeAndMissingToday() {
    let spoken = GroupRowSpeech.full(name: "企业专线", platformName: "OpenAI", isExclusive: true, badge: "无可用账号", available: 0, total: 1,
                                     breakdown: "错误 1", billingLine: "费率倍数 ×1.2 · 订阅计费", today: .missing)
    #expect(spoken.contains("专属，无可用账号，可用 0 / 1，错误 1"))
    #expect(spoken.hasSuffix("今日无数据"))
    #expect(!spoken.contains(DisplayFormat.missing))
}

@Test func simpleModeRowSpeechLeavesOutTheThirdLine() {
    let spoken = GroupRowSpeech.full(name: "默认组", platformName: "DeepSeek", isExclusive: false, badge: nil, available: 1, total: 1,
                                     breakdown: nil, billingLine: nil, today: .hidden)
    #expect(spoken == "默认组，DeepSeek，可用 1 / 1")
    #expect(!spoken.contains("费率倍数") && !spoken.contains("今日"))
}

@Test func compactRowSpeechNamesPlatformAndInactive() {
    #expect(GroupRowSpeech.compact(name: "测试组", platformName: "Gemini", isInactive: true) == "测试组，Gemini，已停用")
    #expect(GroupRowSpeech.compact(name: "高级组", platformName: "Anthropic", isInactive: false) == "高级组，Anthropic")
}

@Test func emptyBucketsSpeakZeroOfZero() {
    let spoken = GroupRowSpeech.full(name: "Antigravity 组", platformName: "Antigravity", isExclusive: false, badge: "没有账号", available: 0,
                                     total: 0, breakdown: nil, billingLine: "费率倍数 ×1.0 · 标准计费", today: .amount(0))
    #expect(spoken.contains("没有账号，可用 0 / 0"))
    #expect(spoken.hasSuffix("今日 $0.00"))
}

// U-10 (S5-高-3, S5-中-8): a failed refresh keeps 今日 and D02's shortage, and the list's 更新失败 strip names which.

@Test func staleItemsJoinsAffected() {
    #expect(GroupStoreRules.staleItems(usageStale: true, shortagesStale: false) == "今日")
    #expect(GroupStoreRules.staleItems(usageStale: false, shortagesStale: true) == "可用状态")
    #expect(GroupStoreRules.staleItems(usageStale: true, shortagesStale: true) == "今日、可用状态")
    #expect(GroupStoreRules.staleItems(usageStale: false, shortagesStale: false) == nil)
}

@Test func shortageKeptAfterFailedRefresh() {
    // 标准组: 1 of 2 available, short by its alert rule only (the local half rule says not).
    let standard = AdminGroup(id: 2, name: "标准组", accountCount: 2, activeAccountCount: 1, sortOrder: 2, errorAccountCount: 1, idleAccountCount: 0)
    let read = BlockState<[Int: AccountStatusGroupSummary.Shortage]>.loaded(
        [2: .init(isShort: true, source: "alert_rule", threshold: 60, current: 50)], at: now)
    let failed = read.withLoading().withFailure(nil)
    #expect(GroupStoreRules.isStale(failed))
    #expect(GroupListSections.rows([standard], shortages: failed.value ?? [:]).first?.health == .low)
    // A refresh still out, or one that worked, marks nothing.
    #expect(!GroupStoreRules.isStale(failed.withLoading()))
    #expect(!GroupStoreRules.isStale(read))
    // Never read: the local half rule, unmarked.
    let never = BlockState<[Int: AccountStatusGroupSummary.Shortage]>.idle.withLoading().withFailure(nil)
    #expect(!GroupStoreRules.isStale(never))
    #expect(GroupListSections.rows([standard], shortages: never.value ?? [:]).first?.health == .ok)
}

// U-10 review: the list's strip stays through a retry still out, and a kept block's 429 wait counts down without a tap (00 §2.7.2).

@Test func staleStaysThroughARetryUntilAReadWorks() {
    let read = BlockState<[Int: GroupUsageSummary]>.loaded([7: usage(7, "18.40")], at: now)
    let failed = BlockRefresh().recordingFailure(APIError.server(status: 502, reason: nil), at: now)
    let kept = read.withLoading().withFailure(nil)
    #expect(GroupStoreRules.isStale(kept, refresh: failed))
    // The retry is out (a hanging aggregate takes a while), or was cancelled: the earlier amount stays marked.
    #expect(GroupStoreRules.isStale(kept.withLoading(), refresh: failed))
    #expect(GroupStoreRules.isStale(kept.withLoading().withCancelledLoad(), refresh: failed))
    // A read that worked clears it; a refresh of a block that never failed marks nothing.
    #expect(!GroupStoreRules.isStale(read, refresh: failed.recordingSuccess()))
    #expect(!GroupStoreRules.isStale(read.withLoading(), refresh: BlockRefresh()))
    // Never read (“今日 —”): nothing to mark.
    let never = BlockState<[Int: GroupUsageSummary]>.idle.withLoading().withFailure(nil)
    #expect(!GroupStoreRules.isStale(never, refresh: failed))
}

@Test func staleStatusHoldsTheTapWhileRetryingOrWaiting() {
    let failed = BlockRefresh().recordingFailure(APIError.server(status: 502, reason: nil), at: now)
    let waiting = BlockRefresh().recordingFailure(APIError.server(status: 429, envelope: nil, retryAfter: 60), at: now)
    let longer = BlockRefresh().recordingFailure(APIError.server(status: 429, envelope: nil, retryAfter: 120), at: now)
    #expect(GroupStoreRules.staleStatus(refreshing: false, waits: [failed], at: now) == .updateFailed)
    #expect(GroupStoreRules.staleStatus(refreshing: true, waits: [failed], at: now) == .refreshing)
    // A kept block's 429 wait: the strip counts down the wait that ends last, whatever the other block did.
    #expect(GroupStoreRules.staleStatus(refreshing: false, waits: [failed, waiting], at: now) == .throttled("请求过于频繁，60 秒后自动重试"))
    #expect(GroupStoreRules.staleStatus(refreshing: false, waits: [longer, waiting], at: now) == .throttled("请求过于频繁，120 秒后自动重试"))
    // Once the wait is over the tap is back.
    #expect(GroupStoreRules.staleStatus(refreshing: false, waits: [waiting], at: now.addingTimeInterval(60)) == .updateFailed)
}
