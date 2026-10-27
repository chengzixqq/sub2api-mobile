import Foundation
import Testing
@testable import Sub2Core

// 60 §8.3 row by row: code text, face value, second line, badge, expiry, day groups, buttons and the ··· menu.

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let utc = TimeZone(identifier: "UTC")!
private func instant(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private let now = instant("2026-10-16T09:41:00+08:00")
private let fullCode = "a3f01b2c3d4e5f60718293a4b5c6d4e8"
private let batchID = UUID(uuidString: "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D")!
private let wang = RedeemCodeUser(id: 42, email: "wang@example.invalid", username: "小王")

private func code(_ status: String, type: String = "balance", value: Decimal? = 10, usedBy: Int? = nil, usedAt: Date? = nil,
                  createdAt: Date? = instant("2026-10-16T09:12:00+08:00"), expiresAt: Date? = nil, groupID: Int? = nil, validityDays: Int? = nil,
                  batchID: UUID? = nil, user: RedeemCodeUser? = nil, group: RedeemCodeGroup? = nil) -> AdminRedeemCode {
    AdminRedeemCode(id: 1, code: fullCode, type: type, value: value, status: status, usedBy: usedBy, usedAt: usedAt, createdAt: createdAt,
                    expiresAt: expiresAt, groupID: groupID, validityDays: validityDays, batchID: batchID, user: user, group: group)
}
private func subtitle(_ code: AdminRedeemCode, groupName: String? = nil) -> String {
    RedeemPresentation.subtitle(code, groupName: groupName, now: now, timeZone: shanghai)
}
private func expiry(_ code: AdminRedeemCode, timeZone: TimeZone = shanghai) -> RedeemExpiryText {
    RedeemPresentation.expiry(code, now: now, timeZone: timeZone)
}

@Test func shortCodeTailAndDeleteSubject() {
    #expect(RedeemPresentation.shortCode(fullCode) == "a3f0····d4e8")
    #expect(RedeemPresentation.tail(fullCode) == "d4e8")
    #expect(RedeemPresentation.deleteSubject(fullCode) == "····d4e8")
    #expect(RedeemPresentation.shortCode("b4e1c5") == "····e1c5")
    #expect(RedeemPresentation.shortCode("") == "····")
    #expect(RedeemPresentation.tail("ab") == "ab")
}

@Test func codeLinesAndMasking() {
    #expect(RedeemPresentation.codeLines(fullCode, revealed: true) == [["a3f0", "1b2c", "3d4e", "5f60"], ["7182", "93a4", "b5c6", "d4e8"]])
    #expect(RedeemPresentation.codeLines(fullCode, revealed: true).joined().joined() == fullCode)
    #expect(RedeemPresentation.codeLines(fullCode, revealed: false) == [["a3f0", "••••", "••••", "••••"], ["••••", "••••", "••••", "d4e8"]])
    #expect(RedeemPresentation.codeLines("abc123", revealed: true) == [["abc1", "23"]])
    #expect(RedeemPresentation.codeLines(fullCode + "ffff", revealed: true).count == 3)
    #expect(RedeemPresentation.codeSpoken(fullCode, revealed: false) == "兑换码已遮罩，结尾 d4e8")
    #expect(RedeemPresentation.codeSpoken(fullCode, revealed: true) == fullCode)
}

@Test func faceValuePerType() {
    #expect(RedeemPresentation.faceValue(code("unused", value: 10)) == RedeemFaceValue(text: "$10.00", isMuted: false))
    #expect(RedeemPresentation.faceValue(code("unused", value: Decimal(string: "12.5")!)).text == "$12.50")
    #expect(RedeemPresentation.faceValue(code("unused", type: "concurrency", value: 2)).text == "+2 并发")
    #expect(RedeemPresentation.faceValue(code("unused", type: "subscription", value: 0, validityDays: 30)).text == "30 天")
    #expect(RedeemPresentation.faceValue(code("unused", type: "subscription", value: 0)).text == "—")
    #expect(RedeemPresentation.faceValue(code("unused", type: "invitation", value: 0)) == RedeemFaceValue(text: "注册邀请", isMuted: true))
    #expect(RedeemPresentation.faceValue(code("used", type: "admin_balance", value: -5)).text == "−$5.00")
    #expect(RedeemPresentation.faceValue(code("used", type: "admin_concurrency", value: -2)).text == "−2 并发")
    #expect(RedeemPresentation.faceValue(code("used", type: "admin_concurrency", value: 3)).text == "+3 并发")
    #expect(RedeemPresentation.faceValue(code("unused", type: "trial", value: 1)).text == "—")
}

@Test func typeLabelsAndPrefix() {
    #expect(RedeemCodeType.allCases.map(\.label) == ["余额", "并发数", "订阅", "邀请码"])
    #expect(RedeemPresentation.typeLabel("admin_balance") == "余额（管理员调整）")
    #expect(RedeemPresentation.typeLabel("admin_concurrency") == "并发（管理员调整）")
    #expect(RedeemPresentation.typeLabel("trial") == "其他类型")
    let subscription = code("unused", type: "subscription", value: 0, groupID: 3, validityDays: 30)
    #expect(RedeemPresentation.prefix(subscription, groupName: "目录名") == "目录名")
    #expect(RedeemPresentation.prefix(code("unused", type: "subscription", group: RedeemCodeGroup(id: 3, name: "企业专线")), groupName: "目录名") == "企业专线")
    #expect(RedeemPresentation.prefix(subscription, groupName: nil) == "订阅")
    #expect(RedeemPresentation.prefix(code("unused", type: "concurrency"), groupName: "目录名") == "并发数")
}

@Test func subtitlePerStatus() {
    let used = code("used", usedBy: 42, usedAt: instant("2026-10-16T10:00:00+08:00"), user: wang)
    #expect(subtitle(used) == "余额 · 小王 · 10/16")
    #expect(subtitle(code("expired", expiresAt: instant("2026-10-15T09:00:00+08:00"))) == "余额 · 10/15 已过期")
    #expect(subtitle(code("disabled")) == "余额 · 10/16 生成")
    #expect(subtitle(code("unused", expiresAt: instant("2026-10-23T09:12:00+08:00"))) == "余额 · 10/23 过期")
    #expect(subtitle(code("unused")) == "余额 · 永不过期")
    #expect(subtitle(code("unused", type: "invitation", value: 0)) == "邀请码 · 永不过期")
    let group = RedeemCodeGroup(id: 3, name: "企业专线")
    #expect(subtitle(code("unused", type: "subscription", value: 0, groupID: 3, group: group)) == "企业专线 · 永不过期")
    #expect(subtitle(code("unused", type: "subscription", value: 0, groupID: 3), groupName: "标准订阅") == "标准订阅 · 永不过期")
    // Redeemed and later expired: still the user and the day it was used.
    let redeemedThenExpired = code("expired", usedBy: 42, usedAt: instant("2027-01-02T08:00:00+08:00"), expiresAt: instant("2026-10-15T09:00:00+08:00"))
    #expect(subtitle(redeemedThenExpired) == "余额 · 用户 #42 · 2027/01/02")
    #expect(subtitle(code("used", usedBy: 42, user: wang)) == "余额 · 小王")
}

@Test func userNameFallbacks() {
    #expect(RedeemPresentation.userName(code("used", usedBy: 42, user: wang)) == "小王")
    let emailOnly = RedeemCodeUser(id: 42, email: "wang@example.invalid", username: "  ")
    #expect(RedeemPresentation.userName(code("used", usedBy: 42, user: emailOnly)) == "wang@example.invalid")
    #expect(RedeemPresentation.userName(code("used", usedBy: 42)) == "用户 #42")
    #expect(RedeemPresentation.userName(code("used", user: RedeemCodeUser(id: 43, email: nil, username: nil))) == "用户 #43")
    #expect(RedeemPresentation.userName(code("used")) == "—")
}

@Test func badgeToneAndDimming() {
    #expect(RedeemPresentation.badge(code("unused")) == RedeemBadge(label: "未使用", tone: .ok)); #expect(!RedeemPresentation.isDimmed(code("unused")))
    for (status, label) in [("used", "已使用"), ("expired", "已过期"), ("disabled", "已禁用"), ("weird", "未知")] {
        #expect(RedeemPresentation.badge(code(status)) == RedeemBadge(label: label, tone: .neutral))
        #expect(RedeemPresentation.isDimmed(code(status)))
    }
    #expect(RedeemCodeStatus.allCases.map(\.label) == ["未使用", "已使用", "已过期", "已禁用"])
    #expect(RedeemCodeStatus.allCases.map(\.tone) == [.ok, .neutral, .neutral, .neutral])
}

@Test func expiryLineAndCautionTone() {
    #expect(expiry(code("unused", expiresAt: instant("2026-10-23T09:12:00+08:00"))) == RedeemExpiryText(text: "10/23 09:12 · 还剩 7 天", tone: nil))
    #expect(expiry(code("unused", expiresAt: instant("2026-10-17T09:00:00+08:00"))) == RedeemExpiryText(text: "10/17 09:00 · 还剩 1 天", tone: .caution))
    #expect(expiry(code("unused", expiresAt: instant("2026-10-16T23:00:00+08:00"))) == RedeemExpiryText(text: "10/16 23:00 · 今天到期", tone: .caution))
    #expect(expiry(code("disabled", expiresAt: instant("2026-10-17T09:00:00+08:00"))) == RedeemExpiryText(text: "10/17 09:00 · 还剩 1 天", tone: nil))
    #expect(expiry(code("expired", expiresAt: instant("2026-10-15T09:00:00+08:00"))) == RedeemExpiryText(text: "10/15 09:00（已过期）", tone: nil))
    #expect(expiry(code("used", usedBy: 42, expiresAt: instant("2026-10-23T09:12:00+08:00"))) == RedeemExpiryText(text: "10/23 09:12", tone: nil))
    #expect(expiry(code("unused")) == RedeemExpiryText(text: "永不过期", tone: nil))
    // 2026-10-16T20:00Z is 10/17 04:00 in Shanghai but still 10/16 in UTC.
    let boundary = code("unused", expiresAt: instant("2026-10-16T20:00:00Z"))
    #expect(expiry(boundary) == RedeemExpiryText(text: "10/17 04:00 · 还剩 1 天", tone: .caution))
    #expect(expiry(boundary, timeZone: utc) == RedeemExpiryText(text: "10/16 20:00 · 今天到期", tone: .caution))
}

@Test func expiryPastItsDateSaysExpiredWhateverTheStatus() {
    // The server maps only an unused code past expires_at to expired: a disabled one keeps its status.
    #expect(expiry(code("disabled", expiresAt: instant("2026-10-01T09:00:00+08:00"))) == RedeemExpiryText(text: "10/01 09:00（已过期）", tone: nil))
    #expect(expiry(code("disabled", expiresAt: instant("2026-10-16T08:00:00+08:00"))) == RedeemExpiryText(text: "10/16 08:00（已过期）", tone: nil))
    #expect(expiry(code("unused", expiresAt: now)) == RedeemExpiryText(text: "10/16 09:41（已过期）", tone: nil))
    #expect(expiry(code("unused", expiresAt: now.addingTimeInterval(60))) == RedeemExpiryText(text: "10/16 09:42 · 今天到期", tone: .caution))
}

@Test func timestampAndDayKeepYearOnlyWhenDifferent() {
    #expect(RedeemPresentation.timestamp(instant("2026-10-16T09:20:00+08:00"), now: now, timeZone: shanghai) == "10/16 09:20")
    #expect(RedeemPresentation.timestamp(instant("2027-01-31T09:20:00+08:00"), now: now, timeZone: shanghai) == "2027/01/31 09:20")
    #expect(RedeemPresentation.timestamp(nil, now: now, timeZone: shanghai) == "—")
    #expect(RedeemPresentation.day(instant("2026-10-16T09:20:00+08:00"), now: now, timeZone: shanghai) == "10/16")
    #expect(RedeemPresentation.day(instant("2027-01-31T09:20:00+08:00"), now: now, timeZone: shanghai) == "2027/01/31")
    #expect(RedeemPresentation.day(nil, now: now, timeZone: shanghai) == "—")
    let newYear = instant("2026-12-31T20:00:00Z")
    #expect(RedeemPresentation.timestamp(newYear, now: now, timeZone: shanghai) == "2027/01/01 04:00")
    #expect(RedeemPresentation.timestamp(newYear, now: now, timeZone: utc) == "12/31 20:00")
    #expect(RedeemPresentation.daysUntil(instant("2026-10-23T00:30:00+08:00"), now: now, timeZone: shanghai) == 7)
}

@Test func dayGroupsFollowServerCalendar() {
    let afterMidnight = instant("2026-10-16T00:30:00+08:00")
    #expect(RedeemPresentation.dayGroup(afterMidnight, now: now, timeZone: shanghai) == .today)
    #expect(RedeemPresentation.dayGroup(afterMidnight, now: now, timeZone: utc) == .yesterday)
    #expect(RedeemPresentation.dayGroup(instant("2026-10-15T12:00:00+08:00"), now: now, timeZone: shanghai) == .yesterday)
    #expect(RedeemPresentation.dayGroup(instant("2026-10-14T23:59:00+08:00"), now: now, timeZone: shanghai) == .earlier)
    #expect(RedeemPresentation.dayGroup(nil, now: now, timeZone: shanghai) == .earlier)
    #expect([RedeemDayGroup.today, .yesterday, .earlier].map(\.title) == ["今天生成", "昨天生成", "更早生成"])
}

@Test func cardActionsPerStatusAndReadOnly() {
    #expect(RedeemPresentation.actions(code("unused"), readOnly: false) == [.disable, .edit, .more])
    #expect(RedeemPresentation.actions(code("disabled"), readOnly: false) == [.enable, .edit, .more])
    #expect(RedeemPresentation.actions(code("expired"), readOnly: false) == [.renew, .more])
    #expect(RedeemPresentation.actions(code("used", usedBy: 42), readOnly: false) == [.editNotes, .more])
    #expect(RedeemPresentation.actions(code("expired", usedBy: 42), readOnly: false) == [.editNotes, .more])
    for status in ["unused", "disabled", "expired", "used"] { #expect(RedeemPresentation.actions(code(status), readOnly: true) == [.more]) }
    #expect([RedeemCardAction.disable, .enable, .edit, .editNotes, .renew, .more].map(\.title) == ["禁用", "启用", "编辑", "编辑备注", "续期", "更多操作"])
    #expect(RedeemCardAction.allCases.filter(\.isPrimary) == [.renew])
}

@Test func trailingSwipePerStatus() {
    #expect(RedeemPresentation.trailingSwipe(code("unused"), readOnly: false) == .disable)
    #expect(RedeemPresentation.trailingSwipe(code("disabled"), readOnly: false) == .enable)
    #expect(RedeemPresentation.trailingSwipe(code("expired"), readOnly: false) == .renew)
    #expect(RedeemPresentation.trailingSwipe(code("used", usedBy: 42), readOnly: false) == nil)
    #expect(RedeemPresentation.trailingSwipe(code("disabled", usedBy: 42), readOnly: false) == nil)
    #expect(RedeemPresentation.trailingSwipe(code("unused"), readOnly: true) == nil)
}

@Test func menuItemsOrderAndConditions() {
    #expect(RedeemPresentation.menuItems(code("unused", batchID: batchID), readOnly: false) == [.copy, .viewBatch(batchID), .delete])
    #expect(RedeemPresentation.menuItems(code("unused"), readOnly: false) == [.copy, .delete])
    let used = code("used", usedBy: 42, batchID: batchID, user: wang)
    #expect(RedeemPresentation.menuItems(used, readOnly: false) == [.copy, .viewUser(userID: 42, name: "小王"), .viewBatch(batchID)])
    #expect(RedeemPresentation.menuItems(code("unused", type: "admin_balance", value: 5), readOnly: false) == [.copy])
    #expect(RedeemPresentation.menuItems(code("unused", batchID: batchID), readOnly: true) == [.copy, .viewBatch(batchID)])
    let titles = [RedeemMenuItem.copy, .viewUser(userID: 42, name: "小王"), .viewBatch(batchID), .delete].map(\.title)
    #expect(titles == ["复制兑换码", "查看使用者 小王", "查看同一批", "删除兑换码…"])
    #expect(RedeemMenuItem.delete.isDestructive); #expect(!RedeemMenuItem.copy.isDestructive)
}

@Test func menuMessageAndChipTitles() throws {
    #expect(RedeemPresentation.menuMessage(code("unused")) == "余额 · $10.00 · 未使用")
    #expect(RedeemPresentation.menuMessage(code("used", type: "subscription", value: 0, validityDays: 30)) == "订阅 · 30 天 · 已使用")
    let stats = RedeemCodeStats(total: 128, unused: 40, used: 70, expired: 12, disabled: 6)
    #expect(RedeemPresentation.statusChipTitle(nil, stats: stats) == "全部 128")
    #expect(RedeemPresentation.statusChipTitle(.unused, stats: stats) == "未使用 40")
    #expect(RedeemPresentation.statusChipTitle(.disabled, stats: nil) == "已禁用")
    #expect(RedeemPresentation.statusChipTitle(nil, stats: nil) == "全部")
    #expect(RedeemPresentation.typeChipTitle(nil) == "类型"); #expect(RedeemPresentation.typeChipTitle(.concurrency) == "并发数")
    #expect(RedeemPresentation.allTypesTitle == "全部类型")
}

@Test func activeSubscriptionGroupsOnly() {
    #expect(AdminGroup(id: 1, name: "企业专线", status: "active", subscriptionType: "subscription").isActiveSubscriptionGroup)
    #expect(!AdminGroup(id: 2, name: "停用订阅", status: "inactive", subscriptionType: "subscription").isActiveSubscriptionGroup)
    #expect(!AdminGroup(id: 3, name: "标准", status: "active", subscriptionType: "standard").isActiveSubscriptionGroup)
    #expect(!AdminGroup(id: 4, name: "未知", status: "active", subscriptionType: nil).isActiveSubscriptionGroup)
}
