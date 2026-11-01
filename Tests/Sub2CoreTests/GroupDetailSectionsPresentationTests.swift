import Foundation
import Testing
@testable import Sub2Core

// S5-07: 50 §2.2 告警横幅 and the 24-hour counts, §2.3 告警横幅 · 贰 · 叁 · 肆, §2.5 states, §2.6 refresh choices.

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private func time(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in zone: ServerTimeZone = shanghai) -> Date {
    zone.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
private let now = time(2026, 10, 31, 9, 41)
private let errorRule = AlertEventRule(id: 11, name: "标准组错误率", metricType: "error_rate", comparison: ">", threshold: 5, windowMinutes: 5)
private func event(_ id: Int = 41, severity: String = "P1", status: String = "firing", rule: AlertEventRule? = errorRule,
                   firedAt: Date? = time(2026, 10, 31, 9, 29)) -> AlertEvent {
    AlertEvent(id: id, ruleID: 11, severity: severity, status: status, title: "P1: 标准组错误率", description: "error_rate 5.2 > 5", metricValue: 5.2,
               thresholdValue: 5, groupID: 2, firedAt: firedAt, rule: rule, groupName: "标准组")
}
private func banner(_ event: AlertEvent?, now: Date = now, zone: ServerTimeZone = shanghai) -> GroupAlertBannerContent? {
    GroupAlertBannerContent(event, now: now, timeZone: zone, latencyMetricsSupported: true)
}
private func group(_ id: Int = 1, status: String = "active", subscription: String = "standard", members: Int = 3, active: Int = 2,
                   claudeCodeOnly: Bool? = false, fallback: Int? = nil, description: String? = "") -> AdminGroup {
    AdminGroup(id: id, name: "分组 \(id)", description: description, platform: "anthropic", status: status, rateMultiplier: Decimal(string: "0.8"),
               isExclusive: false, subscriptionType: subscription, dailyLimitUSD: 20, weeklyLimitUSD: 100, monthlyLimitUSD: nil, rpmLimit: 0,
               accountCount: members, activeAccountCount: active, errorAccountCount: 0, idleAccountCount: members - active,
               claudeCodeOnly: claudeCodeOnly, fallbackGroupID: fallback)
}
private func capacity(_ concurrency: (Int?, Int?), _ sessions: (Int?, Int?), _ rpm: (Int?, Int?)) -> GroupCapacitySummary {
    GroupCapacitySummary(groupID: 1, concurrencyUsed: concurrency.0, concurrencyMax: concurrency.1, sessionsUsed: sessions.0, sessionsMax: sessions.1,
                         rpmUsed: rpm.0, rpmMax: rpm.1)
}
private let stamp = Date(timeIntervalSince1970: 1_800_000_000)

// MARK: 告警横幅

@Test func bannerTitleJoinsSeverityStatusAndRuleTitle() throws {
    let content = try #require(banner(event()))
    #expect(content.title == "P1 告警中 · 标准组错误率 5.2%")
    #expect(content.tone == .caution && content.eventID == 41)
    #expect(banner(event(severity: ""))?.title == "告警中 · 标准组错误率 5.2%")
    #expect(GroupAlertBannerContent.openTitle == "查看" && GroupAlertBannerContent.systemImage == "bell.fill")
}

@Test func bannerToneFollowsSeverityAndOnlyFiringShows() {
    #expect(banner(event(severity: "P0"))?.tone == .critical)
    #expect(banner(event(severity: "P2"))?.tone == .caution)
    #expect(banner(event(severity: "P3"))?.tone == .neutral)
    #expect(banner(event(status: "resolved")) == nil)
    #expect(banner(event(status: AlertEvent.manualResolved)) == nil)
    #expect(banner(nil) == nil)
}

@Test func bannerDetailWithRuleAndToday() {
    #expect(banner(event())?.detail == "错误率 > 5.0%（5 分钟） · 09:29 起")
}

@Test func bannerDetailEarlierDayUsesMonthDayClock() {
    #expect(banner(event(firedAt: time(2026, 10, 30, 21, 52)))?.detail == "错误率 > 5.0%（5 分钟） · 10/30 21:52 起")
    #expect(banner(event(firedAt: time(2025, 12, 31, 23, 50)))?.detail == "错误率 > 5.0%（5 分钟） · 2025/12/31 23:50 起")
    // 07:00 in Shanghai is the day before in UTC: the server's day decides.
    let early = time(2026, 10, 31, 7, 0)
    #expect(GroupAlertBannerContent.firedText(early, now: now, timeZone: shanghai) == "07:00 起")
    let utc = ServerTimeZone(identifier: "UTC", utcOffset: "+00:00")!
    #expect(GroupAlertBannerContent.firedText(early, now: now, timeZone: utc) == "10/30 23:00 起")
    #expect(GroupAlertBannerContent.firedText(nil, now: now, timeZone: shanghai) == nil)
}

@Test func bannerDetailWithoutRuleIsTimeOnly() {
    #expect(banner(event(rule: nil))?.detail == "09:29 起")
    let noOperator = AlertEventRule(id: 11, name: "标准组错误率", metricType: "error_rate", comparison: " ", threshold: 5, windowMinutes: 5)
    #expect(banner(event(rule: noOperator))?.detail == "09:29 起")
    #expect(banner(event(rule: nil, firedAt: nil))?.detail == nil)
}

@Test func bannerKeepsLastEventOnFailedRefresh() {
    let shown = event()
    #expect(GroupAlertBannerContent.shownEvent(.loaded(shown, at: stamp)) == shown)
    #expect(GroupAlertBannerContent.shownEvent(.loaded(nil, at: stamp)) == nil)
    #expect(GroupAlertBannerContent.shownEvent(.failed(reason: "x", previous: shown, at: stamp)) == shown)
    #expect(GroupAlertBannerContent.shownEvent(.failed(reason: "x", previous: nil, at: nil)) == nil)
    #expect(GroupAlertBannerContent.shownEvent(.loading(previous: shown, at: stamp)) == shown)
    #expect(GroupAlertBannerContent.shownEvent(.idle) == nil)
}

// MARK: 2.6 刷新

@Test func readsFollowTriggerPermissionsBackoffAndOps() {
    let all: Set<GroupDetailBlock> = [.capacity, .usage, .todayUsage, .alert, .errorCounts]
    func reads(_ trigger: GroupDetailTrigger, shows: Bool = true, opsOff: Bool = false, due: [GroupDetailBlock: Date] = [:],
               unread: Set<GroupDetailBlock> = []) -> Set<GroupDetailBlock> {
        GroupDetailSectionReads.reads(for: trigger, showsUsageAndCapacity: shows, opsKnownDisabled: opsOff, due: due, unread: unread, now: stamp)
    }
    #expect(GroupDetailSectionReads.blocks == all)
    for trigger in [GroupDetailTrigger.enter, .pull, .foreground, .afterWrite] { #expect(reads(trigger) == all) }
    #expect(reads(.poll) == [.capacity, .alert])
    #expect(reads(.poll, opsOff: true) == [.capacity])
    #expect(reads(.poll, due: [.capacity: stamp.addingTimeInterval(30)]) == [.alert])
    #expect(reads(.poll, due: [.capacity: stamp.addingTimeInterval(-1)]) == [.capacity, .alert])
    #expect(reads(.poll, unread: [.todayUsage, .stats]) == [.capacity, .alert, .todayUsage])
    #expect(reads(.pull, opsOff: true, due: [.capacity: stamp.addingTimeInterval(30)]) == all)
    #expect(reads(.enter, shows: false) == [.todayUsage, .alert, .errorCounts])
    #expect(reads(.poll, shows: false) == [.alert])
    #expect(reads(.membersWritten) == [.capacity])
    #expect(reads(.alertReturn) == [.alert])
    #expect(reads(.countdown).isEmpty)
}

@Test func listUsageIsReusedOnlyOnEnter() {
    #expect(GroupDetailSectionReads.reusesListUsage(.enter))
    for trigger in [GroupDetailTrigger.pull, .foreground, .afterWrite, .poll, .alertReturn, .membersWritten] {
        #expect(!GroupDetailSectionReads.reusesListUsage(trigger))
    }
}

// MARK: 贰 · 用量与容量

@Test func usageFiguresFormatMoneyAndDash() {
    let summary = GroupUsageSummary(groupID: 1, todayCost: Decimal(string: "933.3"), yesterdayCost: Decimal(string: "2985.6"),
                                    totalCost: Decimal(string: "186420.55"))
    let figures = GroupUsageFigures(summary)
    #expect([figures.today, figures.yesterday, figures.total] == ["$933.30", "$2,985.60", "$186,420.55"])
    #expect(figures.today == GroupFormat.todayValue(summary))
    let missing = GroupUsageFigures(nil)
    #expect([missing.today, missing.yesterday, missing.total] == ["—", "—", "—"])
    let noTotal = GroupUsageFigures(GroupUsageSummary(groupID: 1, todayCost: 1, yesterdayCost: 2, totalCost: nil))
    #expect([noTotal.today, noTotal.yesterday, noTotal.total] == ["$1.00", "$2.00", "—"])
    #expect(GroupUsageFigures.title == "用量与容量" && GroupUsageFigures.ordinal == "贰" && GroupUsageFigures.meta == "按 Key 所属分组 · 00:00 切分")
    #expect([GroupUsageFigures.todayTitle, GroupUsageFigures.yesterdayTitle, GroupUsageFigures.totalTitle] == ["今日", "昨日", "累计 · 全部时间"])
}

@Test func todayLineFormatsOrDashesTheWholeLine() {
    let line = GroupTodayLine(GroupTodayUsage(requests: 10_194, totalTokens: 62_940_000, accountCost: Decimal(string: "370.27")))
    #expect(line == .figures(requests: "10,194", tokens: "62.9M", accountCost: "$370.27"))
    #expect(line.spoken == "请求 10,194，Tokens 62.9M，账号成本 $370.27")
    #expect(GroupTodayLine(nil) == .missing && GroupTodayLine(nil).spoken == "无数据")
    #expect(GroupTodayLine(GroupTodayUsage(requests: 1, totalTokens: 2, accountCost: nil)) == .figures(requests: "1", tokens: "2", accountCost: "—"))
    #expect(GroupTodayLine(.zero) == .figures(requests: "0", tokens: "0", accountCost: "$0.00"))
    #expect(GroupTodayLine.label == "今日用量")
    #expect([GroupTodayLine.requestsTitle, GroupTodayLine.tokensTitle, GroupTodayLine.accountCostTitle] == ["请求", "Tokens", "账号成本"])
}

@Test func capacityRowsOnlyForPositiveMaxInSpecOrder() {
    let full = GroupCapacityDisplay.rows(capacity((5, 8), (5, 6), (26, 120)))
    #expect(full.map(\.id) == ["concurrency", "sessions", "rpm"])
    #expect(full.map(\.title) == ["并发", "会话", "调度 RPM"])
    #expect(full.map(\.readout) == ["5/8", "5/6", "26/120"])
    #expect(GroupCapacityDisplay.rows(capacity((2, 8), (0, 0), (0, 0))).map(\.id) == ["concurrency"])
    #expect(GroupCapacityDisplay.rows(capacity((nil, 8), (nil, nil), (nil, nil))).map(\.readout) == ["— / 8"])
    #expect(GroupCapacityDisplay.rows(capacity((0, 0), (nil, nil), (3, 0))).isEmpty)
    #expect(GroupCapacityDisplay.rows(nil).isEmpty)
    #expect(GroupCapacityDisplay.title == "容量")
}

@Test func capacityEmptyNotesAndFailure() {
    func make(_ state: BlockState<GroupCapacitySummary?>, _ group: AdminGroup) -> GroupCapacityDisplay {
        GroupCapacityDisplay.make(state, group: group, buckets: GroupBuckets(group: group))
    }
    let zero = capacity((0, 0), (0, 0), (0, 0))
    #expect(make(.loaded(nil, at: stamp), group(status: "inactive")) == .empty(note: "停用的分组不统计容量"))
    #expect(make(.loaded(zero, at: stamp), group(members: 0, active: 0)) == .empty(note: "没有成员账号"))
    #expect(make(.loaded(zero, at: stamp), group(members: 1, active: 0)) == .empty(note: "没有可调度的账号"))
    #expect(make(.loaded(zero, at: stamp), group(members: 3, active: 2)) == .empty(note: "暂无容量数据"))
    #expect(make(.failed(reason: "—", previous: nil, at: nil), group()) == .empty(note: nil))
    #expect(make(.idle, group()) == .placeholder)
    #expect(make(.loading(previous: nil, at: nil), group()) == .placeholder)
    let kept = make(.failed(reason: "x", previous: capacity((5, 8), (0, 0), (0, 0)), at: stamp), group())
    #expect(kept == .rows(GroupCapacityDisplay.rows(capacity((5, 8), (0, 0), (0, 0)))))
}

// MARK: 叁 · 记录与关联

@Test func logCountTrailingCoversOpsAndFailure() {
    #expect(GroupRecordValues.logCount(.loaded(.count(37), at: stamp)) == "近 24 小时 37 条")
    #expect(GroupRecordValues.logCount(.loaded(.count(1_234), at: stamp)) == "近 24 小时 1,234 条")
    #expect(GroupRecordValues.logCount(.loaded(.count(0), at: stamp)) == "近 24 小时 0 条")
    #expect(GroupRecordValues.logCount(.loaded(.opsDisabled, at: stamp)) == "运维监控未开启")
    #expect(GroupRecordValues.logCount(.failed(reason: "x", previous: nil, at: nil)) == "—")
    #expect(GroupRecordValues.logCount(.idle) == nil)
    #expect(GroupRecordValues.logCount(.loading(previous: nil, at: nil)) == nil)
    #expect(GroupRecordValues.logCount(.failed(reason: "x", previous: .count(37), at: stamp)) == "近 24 小时 37 条")
}

@Test func opsDisabledIsOnly404WithReason() {
    #expect(GroupLogCount.isOpsDisabled(APIError.server(status: 404, reason: "OPS_DISABLED")))
    #expect(!GroupLogCount.isOpsDisabled(APIError.server(status: 404, reason: "GROUP_NOT_FOUND")))
    #expect(!GroupLogCount.isOpsDisabled(APIError.server(status: 500, reason: nil)))
    #expect(!GroupLogCount.isOpsDisabled(CancellationError()))
}

@Test func groupErrorCountQueryMatchesTheLogPage() throws {
    for kind in ErrorLogKind.allCases {
        let items = try AlertErrorCountQuery(kind: kind, groupID: 2).filter.queryItems(page: 1, errors: true, timeZone: shanghai)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(values["time_range"] == "24h" && values["group_id"] == "2" && values["page_size"] == "1" && values["view"] == "all")
        #expect(values["start_time"] == nil && values["end_time"] == nil)
    }
}

@Test func keysAndSubscriptionValues() {
    let counts = GroupKeyCounts(totalAPIKeys: 38, activeAPIKeys: 36, subscriptionsTotal: 15, subscriptionsActive: 12)
    #expect(GroupRecordValues.apiKeys(.loaded(counts, at: stamp)) == "38 个")
    #expect(GroupRecordValues.apiKeys(.loaded(GroupKeyCounts(fallbackTotalAPIKeys: nil, activeSubscriptions: nil), at: stamp)) == "—")
    #expect(GroupRecordValues.apiKeys(.failed(reason: "x", previous: nil, at: nil)) == "—")
    #expect(GroupRecordValues.apiKeys(.loading(previous: nil, at: nil)) == nil)
    #expect(GroupRecordValues.activeSubscriptions(.loaded(counts, at: stamp)) == "生效中 12 个")
    #expect(GroupRecordValues.showsSubscriptions(group(subscription: "subscription")))
    #expect(!GroupRecordValues.showsSubscriptions(group(subscription: "standard")))
    #expect(GroupRecordValues.title == "记录与关联" && GroupRecordValues.ordinal == "叁")
    #expect(GroupRecordRow.allCases.map(\.title) == ["错误请求", "上游错误", "使用记录", "API 密钥", "订阅"])
}

// MARK: 肆 · 配置

@Test func configRowsKeepOnlyDescriptionInSimpleMode() {
    let standard = GroupConfigDisplay.rows(group(), fallbackName: nil, showsBilling: true)
    #expect(standard.map(\.kind) == [.rate, .billing, .rpm, .exclusive, .client, .fallback])
    let subscription = GroupConfigDisplay.rows(group(subscription: "subscription"), fallbackName: nil, showsBilling: true)
    #expect(subscription.suffix(3).map(\.kind) == [.dailyLimit, .weeklyLimit, .monthlyLimit])
    #expect(GroupConfigDisplay.limitsSpoken(subscription) == "每日 $20，每周 $100，每月 无限制")
    let claudeCode = GroupConfigDisplay.rows(group(claudeCodeOnly: true, fallback: 1), fallbackName: "高级组", showsBilling: true)
    #expect(claudeCode.first { $0.kind == .fallback }?.value == "高级组")
    #expect(claudeCode.first { $0.kind == .client }?.value == "仅限 Claude Code")
    let rejecting = GroupConfigDisplay.rows(group(claudeCodeOnly: true), fallbackName: nil, showsBilling: true)
    #expect(rejecting.first { $0.kind == .fallback }?.value == "直接拒绝")
    #expect(standard.first { $0.kind == .fallback }?.value == "—")
    #expect(GroupConfigDisplay.rows(group(description: "内部测试用"), fallbackName: nil, showsBilling: false).map(\.kind) == [.description])
    #expect(GroupConfigDisplay.rows(group(), fallbackName: nil, showsBilling: false).isEmpty)
    #expect(GroupConfigDisplay.title == "配置" && GroupConfigDisplay.ordinal == "肆" && GroupConfigDisplay.limitsTitle == "订阅限额 · 每个订阅")
}

@Test func webLinkOpensAdminGroups() {
    #expect(GroupWebLink.url(siteRoot: URL(string: "https://sub2.example.com")!)?.absoluteString == "https://sub2.example.com/admin/groups")
    #expect(GroupWebLink.url(siteRoot: URL(string: "https://sub2.example.com/")!)?.absoluteString == "https://sub2.example.com/admin/groups")
    #expect(GroupWebLink.title == "模型白名单、组合路由、图片计费" && GroupWebLink.subtitle == "在 Web 中编辑")
    #expect(GroupWebLink.openedReceipt == "已打开 Web 分组管理")
}
