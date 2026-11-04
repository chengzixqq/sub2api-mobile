import Foundation
import Testing
@testable import Sub2Core

// 50 §6–§7 (S5-12): the group's API key and subscription pages.

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private func moment(_ raw: String) throws -> Date {
    guard let date = ServerTime.parseTimestamp(raw) else { throw CocoaError(.formatting) }
    return date
}
private func amount(_ text: String) -> Decimal { Decimal(string: text)! }
private let nova = AdminUserSummary(id: 21, email: "billing@nova.example", username: "Nova 工作室", status: "active")
private let enterprise = AdminGroup(id: 4, name: "企业专线", subscriptionType: "subscription", dailyLimitUSD: 20, weeklyLimitUSD: 100, monthlyLimitUSD: 300)

private struct Item: Decodable, Identifiable, Sendable, Equatable { let id: Int }
private func itemPage(_ ids: [Int], total: Int?, page: Int, hasMore: Bool? = nil) -> Page<Item> {
    Page(items: ids.map(Item.init), total: total, page: page, pageSize: 20, pages: nil, hasMore: hasMore)
}

// MARK: - 剩余天数与用量色调

@Test func subscriptionDaysLeftCountsServerCalendarDays() throws {
    let now = try moment("2026-10-16T15:50:00Z")
    #expect(GroupPresentation.subscriptionDaysLeft(try moment("2026-10-16T16:10:00Z"), now: now, timeZone: shanghai) == 1)
    #expect(GroupPresentation.subscriptionDaysLeft(try moment("2026-10-16T15:55:00Z"), now: now, timeZone: shanghai) == 0)
    #expect(GroupPresentation.subscriptionDaysLeft(try moment("2026-10-20T01:00:00Z"), now: now, timeZone: shanghai) == 4)
    #expect(try #require(GroupPresentation.subscriptionDaysLeft(try moment("2026-10-14T00:00:00Z"), now: now, timeZone: shanghai)) < 0)
    #expect(GroupPresentation.subscriptionDaysLeft(nil, now: now, timeZone: shanghai) == nil)
}

@Test func subscriptionDaysTextAndToneFollowSevenDays() {
    #expect(GroupPresentation.subscriptionDaysText(0) == "今天到期" && GroupPresentation.subscriptionDaysTone(0) == .caution)
    #expect(GroupPresentation.subscriptionDaysText(-2) == "今天到期" && GroupPresentation.subscriptionDaysTone(-2) == .caution)
    #expect(GroupPresentation.subscriptionDaysText(4) == "剩余 4 天" && GroupPresentation.subscriptionDaysTone(4) == .caution)
    #expect(GroupPresentation.subscriptionDaysTone(7) == .caution)
    #expect(GroupPresentation.subscriptionDaysText(8) == "剩余 8 天" && GroupPresentation.subscriptionDaysTone(8) == nil)
}

@Test func usageToneCautionFromSeventyFiveCriticalFromNinety() {
    #expect(GroupPresentation.usageTone(used: amount("74.99"), limit: 100) == nil)
    #expect(GroupPresentation.usageTone(used: 75, limit: 100) == .caution)
    #expect(GroupPresentation.usageTone(used: amount("89.99"), limit: 100) == .caution)
    #expect(GroupPresentation.usageTone(used: 90, limit: 100) == .critical)
    #expect(GroupPresentation.usageFraction(used: 120, limit: 100) == 1.2 && GroupPresentation.usageTone(used: 120, limit: 100) == .critical)
    for limit in [nil, Decimal(0), Decimal(-5)] {
        #expect(GroupPresentation.usageFraction(used: 10, limit: limit) == nil && GroupPresentation.usageTone(used: 10, limit: limit) == nil)
    }
    #expect(GroupPresentation.usageFraction(used: nil, limit: 100) == nil && GroupPresentation.usageTone(used: nil, limit: 100) == nil)
}

// MARK: - 翻页

@Test func feedAppendsUnseenIDsAndFollowsLatestTotal() {
    let first = GroupRecordsFeed(first: itemPage(Array((19...38).reversed()), total: 38, page: 1))
    #expect(first.rows.count == 20 && first.hasMore && first.nextPage == 2 && first.total == 38)
    let second = first.appending(itemPage([20, 19] + Array((1...18).reversed()), total: 39, page: 2))
    #expect(second.rows.map(\.id) == Array((19...38).reversed()) + Array((1...18).reversed()))
    #expect(second.total == 39 && second.page == 2 && !second.hasMore)
    let emptyButMore = first.appending(itemPage([], total: 38, page: 2, hasMore: true))
    #expect(!emptyButMore.hasMore && emptyButMore.rows.count == 20)
}

@Test func feedMoreHintCountsShownRows() {
    let feed = GroupRecordsFeed(first: itemPage(Array(1...20), total: 38, page: 1))
    #expect(feed.moreHint(unit: "个") == "已显示 20 / 38 个 · 滚动到底继续加载")
    #expect(feed.moreHint(unit: "条") == "已显示 20 / 38 条 · 滚动到底继续加载")
    #expect(GroupRecordsFeed(first: itemPage(Array(1...20), total: 1234, page: 1)).moreHint(unit: "个") == "已显示 20 / 1,234 个 · 滚动到底继续加载")
    #expect(GroupRecordsFeed(first: itemPage(Array(1...20), total: nil, page: 1, hasMore: true)).moreHint(unit: "个") == "已显示 20 个 · 滚动到底继续加载")
    #expect(GroupRecordsFeed(first: itemPage(Array(1...5), total: 5, page: 1)).moreHint(unit: "个") == nil)
}

// MARK: - Key 行

private func keyRow(_ key: AdminAPIKey, today: GroupKeyToday = .pending, now: Date? = nil) throws -> GroupKeyRow {
    GroupKeyRow(key, today: today, now: try now ?? moment("2026-10-16T01:41:00Z"), timeZone: shanghai)
}

@Test func keyRowBadgesFollowAdminAPIKeyStatus() throws {
    let inactive = try keyRow(AdminAPIKey(id: 1, effectiveStatus: "inactive"))
    #expect(inactive.badge == "已停用" && inactive.badgeTone == .neutral && inactive.isDimmed && inactive.railTone == nil)
    let exhausted = try keyRow(AdminAPIKey(id: 2, effectiveStatus: "quota_exhausted"))
    #expect(exhausted.badge == "额度耗尽" && exhausted.badgeTone == .caution && exhausted.railTone == .caution && !exhausted.isDimmed)
    let expired = try keyRow(AdminAPIKey(id: 3, effectiveStatus: "expired"))
    #expect(expired.badge == "已过期" && expired.isDimmed && expired.railTone == nil)
    #expect(try keyRow(AdminAPIKey(id: 4, effectiveStatus: "active")).badge == nil)
    let now = try moment("2026-10-16T01:41:00Z")
    #expect(try keyRow(AdminAPIKey(id: 5, status: "disabled")).status == .inactive)
    #expect(try keyRow(AdminAPIKey(id: 6, status: "active", expiresAt: now.addingTimeInterval(-60))).status == .expired)
    #expect(try keyRow(AdminAPIKey(id: 7, status: "active", quota: 10, quotaUsed: 10)).status == .quotaExhausted)
}

@Test func keyRowShowsDisplayNameAndMaskOnly() throws {
    let row = try keyRow(AdminAPIKey(id: 1, keyMasked: "sk-…Kp21", name: "&lt;脚本&gt; &amp; 工具"))
    #expect(row.name == "<脚本> & 工具" && row.mask == "sk-…Kp21")
    #expect(try keyRow(AdminAPIKey(id: 2, keyMasked: nil)).mask == "—")
    #expect(try keyRow(AdminAPIKey(id: 3, keyMasked: "")).mask == "—")
    #expect(row.spokenLabel.contains("sk-…Kp21"))
}

@Test func keyRowOwnerFallsBackToEmailThenUserID() {
    #expect(GroupKeyRow.owner(AdminAPIKey(id: 1, userID: 21, user: nova)) == "Nova 工作室")
    let blank = AdminUserSummary(id: 21, email: "billing@nova.example", username: "  ", status: "active")
    #expect(GroupKeyRow.owner(AdminAPIKey(id: 2, userID: 21, user: blank)) == "billing@nova.example")
    let disabled = AdminUserSummary(id: 21, email: "billing@nova.example", username: "Nova 工作室", status: "disabled")
    #expect(GroupKeyRow.owner(AdminAPIKey(id: 3, userID: 21, user: disabled)) == "Nova 工作室（已禁用）")
    #expect(GroupKeyRow.owner(AdminAPIKey(id: 4, userID: 26)) == "用户 #26")
    #expect(GroupKeyRow.owner(AdminAPIKey(id: 5, userID: 26, user: AdminUserSummary(id: 26, email: "", username: ""))) == "用户 #26")
    #expect(GroupKeyRow.owner(AdminAPIKey(id: 6)) == "—")
    let orphan = GroupKeyRow(AdminAPIKey(id: 6), today: .pending, now: Date(), timeZone: shanghai)
    #expect(orphan.userID == nil)
    #expect(GroupKeyRow(AdminAPIKey(id: 7, user: nova), today: .pending, now: Date(), timeZone: shanghai).userID == 21)
}

@Test func keyRowLastUsedIsClockTodayDayEarlierYearAcross() throws {
    let now = try moment("2026-10-16T01:41:00Z")
    #expect(GroupKeyRow.lastUsedText(try moment("2026-10-16T01:38:00Z"), now: now, timeZone: shanghai) == "09:38")
    #expect(GroupKeyRow.lastUsedText(try moment("2026-10-15T10:00:00Z"), now: now, timeZone: shanghai) == "10/15 18:00")
    #expect(GroupKeyRow.lastUsedText(try moment("2025-12-31T02:00:00Z"), now: now, timeZone: shanghai) == "2025/12/31 10:00")
    #expect(GroupKeyRow.lastUsedText(nil, now: now, timeZone: shanghai) == "从未使用")
    let afterMidnight = try moment("2026-10-16T17:00:00Z")
    #expect(GroupKeyRow.lastUsedText(try moment("2026-10-16T16:30:00Z"), now: afterMidnight, timeZone: shanghai) == "00:30")
}

@Test func keyRowTodayAndQuota() throws {
    #expect(GroupKeyToday.amount(amount("12.4")).text == "今日 $12.40")
    #expect(GroupKeyToday.missing.text == "今日 —" && GroupKeyToday.missing.spoken == "今日无数据")
    #expect(GroupKeyToday.pending.text == "今日 —" && GroupKeyToday.pending.spoken == "今日读取中")
    let resolved = GroupKeyToday.resolve(id: 5, reply: [:])
    #expect(resolved == .amount(0) && resolved.text == "今日 $0.00")
    #expect(GroupKeyToday.resolve(id: 5, reply: [5: amount("3.1")]) == .amount(amount("3.1")))
    let quota = try #require(try keyRow(AdminAPIKey(id: 1, quota: 20, quotaUsed: amount("8.45"))).quota)
    #expect(quota.id == "quota" && quota.title == "额度" && quota.readout == "$8.45 / $20.00" && quota.tone == nil)
    #expect(abs((quota.fraction ?? 0) - 0.4225) < 0.000_001)
    #expect(try keyRow(AdminAPIKey(id: 2, quota: 20, quotaUsed: amount("18.4"))).quota?.tone == .critical)
    #expect(try keyRow(AdminAPIKey(id: 3, quota: 0, quotaUsed: 5)).quota == nil)
}

/// S5-高-3: an amount kept through a failed read says 更新失败; only a fresh amount counts as one, both keep their value.
@Test func staleTodayText() throws {
    let stale = GroupKeyToday.stale(amount("3.2"))
    #expect(stale.text == "今日 $3.20 · 更新失败" && stale.spoken == "今日 $3.20，更新失败")
    #expect(!stale.isAmount && stale.isStale && stale.lastAmount == amount("3.2"))
    #expect(GroupKeyToday.amount(amount("12.4")).lastAmount == amount("12.4") && !GroupKeyToday.amount(1).isStale)
    #expect(GroupKeyToday.pending.lastAmount == nil && GroupKeyToday.missing.lastAmount == nil && !GroupKeyToday.missing.isStale)
    #expect(GroupKeyToday.amount(amount("3.2")).afterFailure == stale && stale.afterFailure == stale)
    #expect(GroupKeyToday.pending.afterFailure == .missing && GroupKeyToday.missing.afterFailure == .missing)
    let active = AdminAPIKey(id: 1, userID: 21, keyMasked: "sk-…Kp21", name: "生产", effectiveStatus: "active",
                             lastUsedAt: try moment("2026-10-16T01:38:00Z"), user: nova)
    #expect(try keyRow(active, today: stale).spokenLabel == "生产，sk-…Kp21，Nova 工作室 · 09:38，今日 $3.20，更新失败")
    #expect(GroupRecordsCopy.todayStale == "今日金额更新失败 · 重试" && GroupRecordsCopy.activeCountStale == "生效中计数更新失败 · 重试")
}

@Test func keyRowSpokenLabelOrder() throws {
    let now = try moment("2026-10-16T01:41:00Z")
    let active = AdminAPIKey(id: 1, userID: 21, keyMasked: "sk-…Kp21", name: "生产", effectiveStatus: "active",
                             lastUsedAt: try moment("2026-10-16T01:38:00Z"), user: nova)
    #expect(try keyRow(active, today: .amount(amount("12.4"))).spokenLabel == "生产，sk-…Kp21，Nova 工作室 · 09:38，今日 $12.40")
    let zhao = AdminUserSummary(id: 6, email: "lei.zhao@example.com", username: "赵磊", status: "disabled")
    let idle = AdminAPIKey(id: 2, userID: 6, keyMasked: "sk-…7Lw0", name: "旧集成", effectiveStatus: "inactive",
                           lastUsedAt: try moment("2026-10-15T10:00:00Z"), quota: 5, quotaUsed: amount("4.1"), user: zhao)
    let row = try keyRow(idle, today: .missing, now: now)
    #expect(row.spokenLabel == "旧集成，已停用，sk-…7Lw0，赵磊（已禁用） · 10/15 18:00，今日无数据，额度 $4.10 / $5.00")
    #expect(row.secondLine == "赵磊（已禁用） · 10/15 18:00")
}

// MARK: - 订阅行

private func subscription(_ id: Int, status: String?, expires: Date?, user: AdminUserSummary? = nil, userID: Int? = nil,
                          daily: Decimal? = 0, weekly: Decimal? = amount("18.6"), monthly: Decimal? = 270) -> AdminUserSubscription {
    AdminUserSubscription(id: id, userID: userID ?? user?.id, groupID: 4, expiresAt: expires, status: status, dailyUsageUSD: daily,
                          weeklyUsageUSD: weekly, monthlyUsageUSD: monthly, user: user)
}
private let lin = AdminUserSummary(id: 9, email: "yi.lin@example.com", username: "林一", status: "active")

@Test func subscriptionRowActiveShowsDaysLeftAndThreeWindows() throws {
    let now = try moment("2026-10-16T01:41:00Z")
    let row = GroupSubscriptionRow(subscription(15, status: "active", expires: now.addingTimeInterval(4 * 86_400), user: lin),
                                   group: enterprise, now: now, timeZone: shanghai)
    #expect(row.trailing == .daysLeft(text: "剩余 4 天", tone: .caution) && row.railTone == .caution && !row.isDimmed)
    #expect(row.windows.map(\.readout) == ["$0.00 / $20", "$18.60 / $100", "$270.00 / $300"])
    #expect(row.windows[0].fraction == 0 && row.windows[1].tone == nil && row.windows[2].tone == .critical)
    #expect(row.detail == "至 2026-10-20 · yi.lin@example.com")
    let open = AdminGroup(id: 4, name: "企业专线", subscriptionType: "subscription", dailyLimitUSD: 20, weeklyLimitUSD: nil, monthlyLimitUSD: 300)
    let unlimited = GroupSubscriptionRow(subscription(15, status: "active", expires: now.addingTimeInterval(30 * 86_400), user: lin, daily: nil),
                                         group: open, now: now, timeZone: shanghai)
    #expect(unlimited.windows[1].readout == "$18.60" && unlimited.windows[1].limit == nil && unlimited.windows[1].spoken == "每周 $18.60，无限制")
    #expect(unlimited.windows[0].used == "—" && unlimited.windows[0].fraction == nil && unlimited.windows[0].spoken == "每日 无数据 / $20")
    #expect(unlimited.trailing == .daysLeft(text: "剩余 30 天", tone: nil) && unlimited.railTone == nil)
}

@Test func subscriptionRowInactiveRowsAreDimmedWithoutUsage() throws {
    let now = try moment("2026-10-16T01:41:00Z")
    let bob = AdminUserSummary(id: 2, email: "bob@example.com", username: "Bob", status: "active")
    let suspended = GroupSubscriptionRow(subscription(13, status: "suspended", expires: try moment("2026-11-20T00:00:00Z"), user: bob),
                                         group: enterprise, now: now, timeZone: shanghai)
    #expect(suspended.trailing == .badge("已暂停") && suspended.windows.isEmpty && suspended.isDimmed && suspended.detail.hasPrefix("至 2026-11-20"))
    let expired = GroupSubscriptionRow(subscription(12, status: "expired", expires: try moment("2026-10-09T02:00:00Z"), user: bob),
                                       group: enterprise, now: now, timeZone: shanghai)
    #expect(expired.trailing == .badge("已过期") && expired.detail == "2026-10-09 已到期 · bob@example.com" && expired.railTone == nil)
    for status in ["revoked", nil] {
        let other = GroupSubscriptionRow(subscription(11, status: status, expires: now.addingTimeInterval(86_400), user: bob),
                                         group: enterprise, now: now, timeZone: shanghai)
        #expect(other.trailing == .none && other.isDimmed && other.windows.isEmpty && other.railTone == nil)
    }
}

@Test func subscriptionRowNameAndInitial() throws {
    let now = try moment("2026-10-16T01:41:00Z"), expires = now.addingTimeInterval(4 * 86_400)
    let named = GroupSubscriptionRow(subscription(1, status: "active", expires: expires, user: lin), group: enterprise, now: now, timeZone: shanghai)
    #expect(named.name == "林一" && named.initial == "林" && named.userID == 9)
    let mailOnly = AdminUserSummary(id: 9, email: "lin@example.com", username: "", status: "active")
    let mailed = GroupSubscriptionRow(subscription(2, status: "active", expires: expires, user: mailOnly), group: enterprise, now: now, timeZone: shanghai)
    #expect(mailed.name == "lin@example.com" && mailed.initial == "L")
    let orphan = GroupSubscriptionRow(subscription(3, status: "active", expires: expires, userID: 26), group: enterprise, now: now, timeZone: shanghai)
    #expect(orphan.name == "用户 #26" && orphan.initial == "?" && orphan.detail == "至 2026-10-20" && orphan.userID == 26)
    #expect(named.spokenLabel == "林一，剩余 4 天，每日 $0.00 / $20，每周 $18.60 / $100，每月 $270.00 / $300，至 2026-10-20 · yi.lin@example.com")
}

// MARK: - 文案

@Test func recordsCopySubtitlesLimitsAndFailures() {
    #expect(GroupRecordsCopy.keysSubtitle(groupName: "高级组", total: 38) == "高级组 · 共 38 个")
    #expect(GroupRecordsCopy.keysSubtitle(groupName: nil, total: 38) == "共 38 个")
    #expect(GroupRecordsCopy.keysSubtitle(groupName: "高级组", total: nil) == "高级组")
    #expect(GroupRecordsCopy.keysSubtitle(groupName: nil, total: nil) == "")
    #expect(GroupRecordsCopy.subscriptionsSubtitle(groupName: "企业专线", active: 12) == "企业专线 · 生效中 12 个")
    #expect(GroupRecordsCopy.subscriptionsSubtitle(groupName: "企业专线", active: nil) == "企业专线")
    let limits = GroupRecordsCopy.limits(enterprise)
    #expect(limits.map(\.value) == ["$20", "$100", "$300"] && limits.map(\.span) == [.daily, .weekly, .monthly])
    let mixed = AdminGroup(id: 5, name: "x", dailyLimitUSD: amount("20.5"), weeklyLimitUSD: nil, monthlyLimitUSD: 0)
    #expect(GroupRecordsCopy.limits(mixed).map(\.value) == ["$20.50", "无限制", "$0"])
    #expect(GroupRecordsCopy.limitsSpoken(limits) == "每个订阅的限额，每日 $20，每周 $100，每月 $300")
    #expect(GroupRecordsCopy.isParameterError(APIError.server(status: 400, reason: nil)))
    let others: [any Error] = [APIError.server(status: 404, reason: nil), APIError.server(status: 500, reason: nil),
                               APIError(kind: .transport, message: "网络连接已中断"), APIError(kind: .validation, message: "页码必须从 1 开始。"),
                               CancellationError()]
    for error in others { #expect(!GroupRecordsCopy.isParameterError(error)) }
    #expect(GroupRecordsCopy.failureTitle(APIError.server(status: 403, reason: "FORBIDDEN")) == "你的工作区没有这个权限。")
    #expect(GroupRecordsCopy.failureTitle(APIError.server(status: 403, reason: "SIMPLE_MODE_OPERATION_UNSUPPORTED")) == "简易模式下不支持此操作。")
    #expect(GroupRecordsCopy.failureTitle(APIError.server(status: 500, reason: nil)) == "加载失败")
    #expect(GroupRecordsCopy.failureTitle(nil) == "加载失败")
}
