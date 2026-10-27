import Foundation
import Testing
@testable import Sub2Core

private func decimal(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!, newYork = TimeZone(identifier: "America/New_York")!
private let presentationNow = at("2026-10-17T09:41:00+08:00")
private let starts = at("2026-10-16T08:00:00+08:00"), ends = at("2026-10-18T06:00:00+08:00")
private let readSummary = AnnouncementReadSummary(announcementID: 7, totalUsers: 1_036, eligibleCount: 1_036, readCount: 412,
                                                  eligibleReadCount: 410, computedAt: at("2026-10-17T01:41:00Z"))

// MARK: 60 §15.3 列表

@Test func announcementTargetTextFollowsSection15_3() {
    let names = [3: "企业专线", 5: "高级组"]
    func target(_ targeting: AnnouncementTargeting) -> String { AnnouncementPresentation.targetText(targeting, groupNames: names) }
    #expect(target(.everyone) == "所有用户")
    #expect(target(.single(.subscription(groupIDs: [3, 5]))) == "订阅 企业专线、高级组")
    #expect(target(.single(.subscription(groupIDs: [3, 9]))) == "订阅 企业专线、分组 #9")
    for (comparison, symbol) in [("gt", ">"), ("gte", "≥"), ("lt", "<"), ("lte", "≤"), ("eq", "=")] {
        #expect(target(.single(.balance(comparison, value: 5))) == "余额 \(symbol) $5.00")
        #expect(AnnouncementPresentation.comparisonSymbol(comparison) == symbol)
    }
    let mixed = AnnouncementTargeting(anyOf: [AnnouncementConditionGroup(allOf: [.subscription(groupIDs: [3]), .balance("lt", value: 5)]),
                                              AnnouncementConditionGroup(allOf: [.balance("gte", value: 100)])])
    #expect(target(mixed) == "订阅 企业专线 且 余额 < $5.00 或 余额 ≥ $100.00")
    #expect(AnnouncementPresentation.targetText(mixed, groupNames: { names[$0] }) == target(mixed))
    #expect(AnnouncementPresentation.targetText(.single(.subscription(groupIDs: [3])), groupNames: { _ in "  " }) == "订阅 分组 #3")
    #expect(target(.single(AnnouncementCondition(type: "role", operator: "in", groupIDs: [1]))) == "其他条件")
    #expect(target(.single(AnnouncementCondition(type: "balance", operator: "ne", value: 1))) == "其他条件")
    #expect(target(.single(AnnouncementCondition(type: "balance", operator: "eq"))) == "余额 = $0.00")
    #expect(target(.single(.balance("lte", value: decimal("12.5")))) == "余额 ≤ $12.50")
    #expect(AnnouncementPresentation.comparisonSymbol("in") == nil)
}

@Test func announcementSimpleTargetRules() {
    let simple: [AnnouncementTargeting] = [.everyone, .single(.subscription(groupIDs: [3])), .single(.balance("lt", value: 5))]
    for targeting in simple { #expect(AnnouncementPresentation.isSimpleTarget(targeting)) }
    let complex: [AnnouncementTargeting] = [
        AnnouncementTargeting(anyOf: [AnnouncementConditionGroup(allOf: [.subscription(groupIDs: [3]), .balance("lt", value: 5)])]),
        AnnouncementTargeting(anyOf: [AnnouncementConditionGroup(allOf: [.balance("lt", value: 5)]), AnnouncementConditionGroup(allOf: [.balance("gt", value: 50)])]),
        .single(AnnouncementCondition(type: "role", operator: "in", groupIDs: [1])), .single(.subscription(groupIDs: [])),
    ]
    for targeting in complex { #expect(!AnnouncementPresentation.isSimpleTarget(targeting)) }
}

@Test func announcementSimpleTargetOnlyCoversWhatThePhoneFormCanSave() throws {
    for comparison in ["gt", "gte", "lt", "lte"] {
        #expect(AnnouncementPresentation.isSimpleTarget(.single(.balance(comparison, value: decimal("0.01")))))
    }
    let webOnly: [AnnouncementTargeting] = [
        .single(.balance("eq", value: 5)), .single(.balance("lte", value: 0)), .single(.balance("lt", value: -5)),
    ]
    for targeting in webOnly { #expect(!AnnouncementPresentation.isSimpleTarget(targeting)) }
    let omittedZero = Data(#"{"any_of":[{"all_of":[{"type":"balance","operator":"gt"}]}]}"#.utf8)
    #expect(!AnnouncementPresentation.isSimpleTarget(try JSONDecoder().decode(AnnouncementTargeting.self, from: omittedZero)))
}

@Test func announcementBadgeDimAndNotifyFollowSection15_3() {
    #expect(AnnouncementPresentation.badge(.draft) == AnnouncementBadge(label: "草稿", tone: .neutral))
    #expect(AnnouncementPresentation.badge(.active) == AnnouncementBadge(label: "展示中", tone: .ok))
    #expect(AnnouncementPresentation.badge(.archived) == AnnouncementBadge(label: "已归档", tone: .neutral))
    #expect(AnnouncementPresentation.badge(nil) == nil)
    #expect(AnnouncementStatus.allCases.map { AnnouncementPresentation.isDimmed($0) } == [false, false, true])
    #expect(!AnnouncementPresentation.isDimmed(nil))
    #expect(AnnouncementPresentation.notifyTitle(.popup) == "弹窗"); #expect(AnnouncementPresentation.notifyTitle(.silent) == "静默")
    #expect(AnnouncementPresentation.notifySymbol(.popup) == "megaphone"); #expect(AnnouncementPresentation.notifySymbol(.silent) == "bell")
}

@Test func announcementScheduleLineFollowsSection15_3() {
    func line(_ announcement: Announcement, now: Date = presentationNow, local: TimeZone = shanghai) -> String {
        AnnouncementPresentation.scheduleLine(announcement, now: now, localTimeZone: local, serverTimeZone: shanghai)
    }
    let popup = Announcement(id: 1, status: .active, notifyMode: .popup, startsAt: starts, endsAt: ends)
    let range = "弹窗 · 10/16 08:00 – 10/18 06:00"
    #expect(line(popup) == range); #expect(line(popup, now: starts) == range)
    #expect(line(Announcement(id: 2, status: .active)) == "静默 · 立即 – 永久")
    #expect(line(Announcement(id: 3, status: .draft, startsAt: starts, updatedAt: at("2026-10-16T09:05:00+08:00"))) == "静默 · 更新于 10/16 09:05")
    #expect(line(popup, now: starts.addingTimeInterval(-1)) == range + "（未开始）")
    #expect(line(popup, now: ends) == range + "（已结束）"); #expect(line(popup, now: ends.addingTimeInterval(3_600)) == range + "（已结束）")
    let archived = Announcement(id: 4, status: .archived, notifyMode: .popup, startsAt: starts, endsAt: ends)
    #expect(line(archived, now: ends.addingTimeInterval(3_600)) == range)
    #expect(line(Announcement(id: 5, status: .active, notifyMode: .popup, startsAt: starts), local: newYork) == "弹窗 · 10/15 20:00 – 永久")
    #expect(line(Announcement(id: 6, status: .draft, notifyMode: .popup, updatedAt: at("2026-10-16T09:05:00+08:00")), local: newYork)
            == "弹窗 · 更新于 10/16 09:05")
    #expect(line(Announcement(id: 7, status: .active, endsAt: at("2027-01-31T09:20:00+08:00"))) == "静默 · 立即 – 2027/01/31 09:20")
}

@Test func announcementSegmentTitlesCountsAndNavigationSubtitle() {
    let counts = AnnouncementCounts(all: 5, active: 2, draft: 1, archived: 2)
    let order: [AnnouncementStatus?] = [nil, .active, .draft, .archived]
    #expect(order.map { AnnouncementPresentation.segmentTitle($0, counts: counts) } == ["全部 5", "展示中 2", "草稿 1", "已归档 2"])
    #expect(order.map { AnnouncementPresentation.segmentTitle($0, counts: nil) } == ["全部", "展示中", "草稿", "已归档"])
    #expect(order.map(AnnouncementPresentation.segmentName) == ["全部", "展示中", "草稿", "已归档"])
    let partial = AnnouncementCounts(all: 1_234, active: nil, draft: 1, archived: nil)
    #expect(AnnouncementPresentation.segmentTitle(nil, counts: partial) == "全部 1,234")
    #expect(AnnouncementPresentation.segmentTitle(.active, counts: partial) == "展示中")
    #expect(order.map { counts.count(for: $0) } == [5, 2, 1, 2])
    #expect(AnnouncementPresentation.navigationSubtitle(siteName: "主站", count: 1_036) == "主站 · 1,036 条")
    #expect(AnnouncementPresentation.navigationSubtitle(siteName: "主站", count: nil) == "主站")
    #expect(AnnouncementPresentation.navigationSubtitle(siteName: "", count: 5) == "5 条")
}

@Test func announcementListReadProgressFollowsSection15_3() {
    let stats = AnnouncementReadStats(eligibleCount: 1_036, readCount: 412, eligibleReadCount: 410)
    func progress(_ status: AnnouncementStatus?, stats: AnnouncementReadStats? = stats, supports: Bool = true) -> String? {
        AnnouncementPresentation.listReadProgress(Announcement(id: 1, status: status, readStats: stats), supportsReadStats: supports)
    }
    #expect(progress(.active) == "已读 410/1,036"); #expect(progress(.archived) == "已读 410/1,036")
    #expect(progress(.draft) == nil); #expect(progress(.active, supports: false) == nil); #expect(progress(.active, stats: nil) == nil)
}

// MARK: 60 §16.3 / §16.4 详情

@Test func announcementDetailTimesAndReadLineFollowSection16_3() {
    #expect(AnnouncementPresentation.startText(starts, now: presentationNow, timeZone: shanghai) == "10/16 08:00")
    #expect(AnnouncementPresentation.endText(ends, now: presentationNow, timeZone: shanghai) == "10/18 06:00")
    #expect(AnnouncementPresentation.startText(nil, now: presentationNow, timeZone: shanghai) == "立即")
    #expect(AnnouncementPresentation.endText(nil, now: presentationNow, timeZone: shanghai) == "永久")
    #expect(AnnouncementPresentation.timestamp(nil, now: presentationNow, timeZone: shanghai) == "—")
    #expect(AnnouncementPresentation.timestamp(at("2025-12-31T23:59:00+08:00"), now: presentationNow, timeZone: shanghai) == "2025/12/31 23:59")
    #expect(AnnouncementPresentation.rangeText(startsAt: starts, endsAt: nil, now: presentationNow, timeZone: shanghai) == "10/16 08:00 – 永久")

    func readLine(_ status: AnnouncementStatus? = .active, supports: Bool = true, summary: AnnouncementReadSummary?) -> AnnouncementReadLine? {
        AnnouncementPresentation.detailReadLine(status: status, supportsReadStats: supports, summary: summary, serverTimeZone: shanghai)
    }
    #expect(readLine(summary: readSummary)
            == AnnouncementReadLine(title: "已读情况", value: "已读 410 / 符合条件 1,036", detail: "39.6% · 另有 2 人读后已不符合条件 · 统计于 09:41"))
    let computed = at("2026-10-17T01:41:00Z")
    let exact = AnnouncementReadSummary(totalUsers: 50, eligibleCount: 40, readCount: 10, eligibleReadCount: 10, computedAt: computed)
    #expect(readLine(summary: exact)?.detail == "25.0% · 统计于 09:41")
    let nobody = AnnouncementReadSummary(totalUsers: 50, eligibleCount: 0, readCount: 3, eligibleReadCount: 0, computedAt: computed)
    #expect(readLine(summary: nobody)?.detail == "另有 3 人读后已不符合条件 · 统计于 09:41")
    let fallback = AnnouncementReadLine(title: "已读情况", value: nil, detail: "逐个用户看：是否符合条件、什么时候读的")
    #expect(readLine(supports: false, summary: readSummary) == fallback); #expect(readLine(.archived, summary: nil) == fallback)
    #expect(readLine(.draft, summary: readSummary) == nil)
}

@Test func announcementDetailSubtitleForEachStatus() {
    #expect(AnnouncementPresentation.detailSubtitle(status: .active, notifyMode: .popup) == "展示中 · 弹窗")
    #expect(AnnouncementPresentation.detailSubtitle(status: .draft, notifyMode: .silent) == "草稿 · 静默")
    #expect(AnnouncementPresentation.detailSubtitle(status: .archived, notifyMode: .popup) == "已归档 · 弹窗")
    #expect(AnnouncementPresentation.detailSubtitle(status: nil, notifyMode: .silent) == "静默")
}

@Test func announcementDisplayTitleFallsBackForBlank() {
    #expect(AnnouncementPresentation.displayTitle(" \n ") == "未命名公告"); #expect(AnnouncementPresentation.displayTitle("") == "未命名公告")
    #expect(AnnouncementPresentation.displayTitle(" 维护 通知 ") == " 维护 通知 ")
}

@Test func announcementPublishConfirmationPopupSilentAndOpenRange() {
    func confirmation(_ title: String, target: String = "所有用户", notify: AnnouncementNotifyMode = .popup, startsAt: Date?, endsAt: Date?)
        -> AnnouncementPublishConfirmation {
        AnnouncementPresentation.publishConfirmation(title: title, targetText: target, notifyMode: notify, startsAt: startsAt, endsAt: endsAt,
                                                     now: presentationNow, timeZone: shanghai)
    }
    #expect(confirmation("维护通知", startsAt: starts, endsAt: ends)
            == AnnouncementPublishConfirmation(title: "发布「维护通知」？", message: "所有用户 · 用户打开时弹窗提示\n有效期 10/16 08:00 – 10/18 06:00"))
    #expect(confirmation("  ", target: "余额 < $5.00", notify: .silent, startsAt: nil, endsAt: nil)
            == AnnouncementPublishConfirmation(title: "发布「未命名公告」？", message: "余额 < $5.00 · 静默出现在通知里\n有效期 立即 – 永久"))
    #expect(confirmation("t", startsAt: nil, endsAt: ends).message == "所有用户 · 用户打开时弹窗提示\n有效期 立即 – 10/18 06:00")
    #expect(confirmation("t", startsAt: starts, endsAt: nil).message == "所有用户 · 用户打开时弹窗提示\n有效期 10/16 08:00 – 永久")
}

// MARK: 60 §18.3 已读情况

@Test func announcementReadsHeaderFollowsSection18_3() {
    #expect(AnnouncementPresentation.readsSummaryBar(readSummary, total: 1_036, serverTimeZone: shanghai)
            == "已读 412 · 符合条件 1,036 · 共 1,036 位用户 · 统计于 09:41")
    #expect(AnnouncementPresentation.readsSummaryBar(nil, total: 1_036, serverTimeZone: shanghai) == "第 1 页 · 共 1,036 位用户")
    #expect(AnnouncementPresentation.readsSummaryBar(nil, total: nil, serverTimeZone: shanghai) == "第 1 页")
    #expect(AnnouncementPresentation.readsResultCount(total: 12, isFiltered: true) == "找到 12 位")
    #expect(AnnouncementPresentation.readsResultCount(total: 12, isFiltered: false) == nil)
    #expect(AnnouncementPresentation.readsResultCount(total: nil, isFiltered: true) == nil)
    #expect(AnnouncementPresentation.readsSearchPrompt == "搜索邮箱或用户名"); #expect(AnnouncementPresentation.eligibleOnlyTitle == "只看符合条件")
    #expect(AnnouncementPresentation.loadingMoreText == "滚到底自动加载下一页")
    #expect(AnnouncementReadStatusQuery.ReadState.allCases.map(\.title) == ["全部", "已读", "未读"])
    #expect(AnnouncementReadStatusQuery.Sort.allCases.map(\.title) == ["按邮箱", "按用户名", "按余额", "按阅读时间"])
    #expect(AnnouncementReadStatusQuery.Sort.allCases.map(\.detail) == ["升序", "升序", "从高到低", "最新在前"])
}

@Test func announcementReadRowFollowsSection18_3() {
    func row(_ row: AnnouncementReadStatusRow) -> AnnouncementReadRowText {
        AnnouncementPresentation.readRow(row, now: presentationNow, serverTimeZone: shanghai)
    }
    let read = AnnouncementReadStatusRow(userID: 42, email: "wang@example.invalid", username: "xiao wang", balance: decimal("12.4"), eligible: true,
                                         readAt: at("2026-10-16T08:12:00+08:00"))
    #expect(row(read) == AnnouncementReadRowText(initial: "X", email: "wang@example.invalid", balance: "$12.40", username: "xiao wang",
                                                 badge: AnnouncementBadge(label: "符合条件", tone: .ok), readText: "10/16 08:12", isRead: true, isDimmed: false))
    let unread = row(AnnouncementReadStatusRow(userID: 43, email: "li@example.invalid", username: "  ", eligible: false))
    #expect(unread.initial == "L"); #expect(unread.balance == "—"); #expect(unread.badge == AnnouncementBadge(label: "不符合", tone: .neutral))
    #expect(unread.readText == "未读"); #expect(!unread.isRead); #expect(unread.isDimmed)
    #expect(row(AnnouncementReadStatusRow(userID: 44, email: "", eligible: true)).initial == "?")
    #expect(row(AnnouncementReadStatusRow(userID: 45, email: "a@example.invalid", username: "小王", eligible: true)).initial == "小")
    #expect(AnnouncementPresentation.unreadText == "未读")
}

// MARK: 60 §17.3 标题

@Test func announcementTitleByteLimitFollowsSection17_3() {
    let hanzi66 = String(repeating: "公", count: 66), hanzi67 = String(repeating: "公", count: 67)
    #expect(AnnouncementPresentation.titleByteCount("  " + hanzi66 + "\n") == 198)
    #expect(!AnnouncementPresentation.isTitleTooLong(String(repeating: "a", count: 200)))
    #expect(AnnouncementPresentation.isTitleTooLong(String(repeating: "a", count: 201)))
    #expect(!AnnouncementPresentation.isTitleTooLong(hanzi66)); #expect(AnnouncementPresentation.isTitleTooLong(hanzi67))
    #expect(AnnouncementPresentation.titleTooLongFootnote == "标题太长（最多约 66 个汉字）")
    #expect(AnnouncementCreateRequest.titleByteLimit == 200)
}
