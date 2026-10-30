import Foundation
import Testing
@testable import Sub2Core

// 30 §7.3–§7.5, §0.6: the key cards' words, the group sheet and the write plans (S3-12).

private func amount(_ text: String) -> Decimal { Decimal(string: text)! }
private func at(_ text: String) -> Date { ServerTime.parseTimestamp(text)! }
/// 10:00 in Shanghai.
private let now = at("2026-10-26T02:00:00Z")
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let utc = ServerTimeZone(identifier: "UTC", utcOffset: "+00:00")!
private let groups = [
    AdminGroup(id: 1, name: "高级组", platform: "anthropic", rateMultiplier: amount("0.8"), sortOrder: 1),
    AdminGroup(id: 2, name: "标准组", platform: "openai", rateMultiplier: amount("0.8"), sortOrder: 2),
    AdminGroup(id: 3, name: "默认组", platform: "deepseek", rateMultiplier: amount("0.8"), sortOrder: 3),
    AdminGroup(id: 4, name: "企业专线", platform: "openai", rateMultiplier: amount("1.2"), isExclusive: true, subscriptionType: "subscription", sortOrder: 4),
    AdminGroup(id: 5, name: "Claude Code 组", platform: "anthropic", rateMultiplier: amount("0.8"), isExclusive: true, sortOrder: 5),
    AdminGroup(id: 6, name: "测试组", platform: "gemini", status: "inactive", sortOrder: 6),
    AdminGroup(id: 8, name: "无倍率组", platform: "kimi", rateMultiplier: nil, sortOrder: 8),
]
private let studio = UserKeyAccess(allowedGroups: [1, 2], restrictPublicGroups: true, groupRates: [2: amount("0.9")])

private func key(_ id: Int = 7, name: String = "脚本", group: Int? = 2, status: String = "active", effective: String? = nil, quota: String = "0",
                 used: String = "0", expires: Date? = nil, lastUsed: Date? = nil, mask: String? = "sk-…cret") -> AdminAPIKey {
    AdminAPIKey(id: id, userID: 10, keyMasked: mask, name: name, groupID: group, status: status, effectiveStatus: effective, lastUsedAt: lastUsed,
                quota: amount(quota), quotaUsed: amount(used), expiresAt: expires)
}
private func limited(_ limits: (String, String, String), used: (String, String, String), resets: (Date?, Date?, Date?) = (nil, nil, nil)) -> AdminAPIKey {
    AdminAPIKey(id: 9, name: "默认", rateLimit5h: amount(limits.0), rateLimit1d: amount(limits.1), rateLimit7d: amount(limits.2),
                usage5h: amount(used.0), usage1d: amount(used.1), usage7d: amount(used.2), reset5hAt: resets.0, reset1dAt: resets.1, reset7dAt: resets.2)
}
private func body(_ request: AdminAPIKeyUpdateRequest) throws -> String { String(decoding: try request.requestBody(), as: UTF8.self) }

@Test func badgeFollowsStatusTableIncludingSimpleMode() {
    let active = key(effective: "active"), inactive = key(status: "inactive"), exhausted = key(effective: "quota_exhausted")
    let expired = key(effective: "expired")
    #expect(UserKeyPresentation.badge(active, now: now, simpleMode: false) == nil)
    #expect(UserKeyPresentation.badge(inactive, now: now, simpleMode: false) == "已停用")
    #expect(UserKeyPresentation.badge(exhausted, now: now, simpleMode: false) == "额度耗尽")
    #expect(UserKeyPresentation.badge(expired, now: now, simpleMode: false) == "已过期")
    #expect(UserKeyPresentation.badge(exhausted, now: now, simpleMode: true) == "额度耗尽 · 仍可调用")
    #expect(UserKeyPresentation.badge(expired, now: now, simpleMode: true) == "已过期 · 仍可调用")
    // effective_status missing: derived locally (the legacy disabled, a passed expiry, a used-up quota).
    #expect(UserKeyPresentation.badge(key(status: "disabled"), now: now, simpleMode: false) == "已停用")
    #expect(UserKeyPresentation.badge(key(expires: now.addingTimeInterval(-60)), now: now, simpleMode: false) == "已过期")
    #expect(UserKeyPresentation.badge(key(quota: "10", used: "10"), now: now, simpleMode: false) == "额度耗尽")
    #expect(UserKeyPresentation.isIdle(inactive, now: now, simpleMode: true))
    #expect(UserKeyPresentation.isIdle(exhausted, now: now, simpleMode: false))
    #expect(!UserKeyPresentation.isIdle(exhausted, now: now, simpleMode: true))
    #expect(!UserKeyPresentation.isIdle(active, now: now, simpleMode: false))
}

@Test func sectionMetaCountsActiveBySimpleMode() {
    let keys = [key(1, effective: "active"), key(2, status: "inactive"), key(3, effective: "expired")]
    #expect(UserKeyPresentation.sectionMeta(keys, now: now, simpleMode: false) == "3 个 · 活跃 1")
    #expect(UserKeyPresentation.sectionMeta(keys, now: now, simpleMode: true) == "3 个 · 活跃 2")
    #expect(UserKeyPresentation.sectionMeta([], now: now, simpleMode: false) == "0 个")
}

@Test func maskUsesKeyMaskedOnlyAndDashWhenMissing() {
    #expect(UserKeyPresentation.mask(key(mask: "sk-…cret")) == "sk-…cret")
    #expect(UserKeyPresentation.mask(key(mask: nil)) == "—")
    #expect(UserKeyPresentation.mask(key(mask: "")) == "—")
    #expect(UserKeyPresentation.spokenHeader(key(status: "inactive"), now: now, simpleMode: false) == "脚本，已停用，sk-…cret")
    #expect(UserKeyPresentation.spokenHeader(key(name: "A&amp;B"), now: now, simpleMode: false) == "A&B，sk-…cret")
}

@Test func usageLineLimitedUnlimitedAndUnavailable() {
    let quarter = UserKeyPresentation.usageLine(key(quota: "50", used: "12.30"), today: .value(amount("9")))
    #expect(quarter.text == "$12.30 / $50.00" && quarter.trailing == "24.6%" && quarter.tone == nil)
    #expect(abs((quarter.progress ?? 0) - 0.246) < 1e-9)
    #expect(UserKeyPresentation.usageLine(key(quota: "50", used: "40"), today: .unavailable).tone == .caution)
    let nearly = UserKeyPresentation.usageLine(key(quota: "20", used: "18.40"), today: .unavailable)
    #expect(nearly.text == "$18.40 / $20.00" && nearly.trailing == "92.0%" && nearly.tone == .critical)
    let over = UserKeyPresentation.usageLine(key(quota: "10", used: "12"), today: .unavailable)
    #expect(over.trailing == "120.0%" && over.progress == 1)
    #expect(UserKeyPresentation.usageLine(key(), today: .value(amount("2.8")))
        == UserKeyUsageLine(text: "今日 $2.80", trailing: "不限额度", progress: nil, tone: nil))
    #expect(UserKeyPresentation.usageLine(key(), today: .unavailable).text == "今日 —")
    #expect(UserKeyPresentation.usageLine(key(), today: .value(0)).text == "今日 $0.00")
}

@Test func metaLineGroupRateAndLastUsed() {
    let threeMinutes = now.addingTimeInterval(-180)
    #expect(UserKeyPresentation.metaLine(key(group: 2, lastUsed: threeMinutes), groups: groups, access: studio, now: now, zone: shanghai)
        == "标准组 · 专属倍率 ×0.9 · 最近使用 3 分钟前")
    #expect(UserKeyPresentation.metaLine(key(group: 1), groups: groups, access: studio, now: now, zone: shanghai) == "高级组 · 默认 ×0.8 · 未使用")
    #expect(UserKeyPresentation.metaLine(key(group: 8), groups: groups, access: studio, now: now, zone: shanghai) == "无倍率组 · 默认 ×1 · 未使用")
    #expect(UserKeyPresentation.metaLine(key(group: nil), groups: groups, access: studio, now: now, zone: shanghai) == "不绑定分组 · 未使用")
    #expect(UserKeyPresentation.metaLine(key(group: 0), groups: groups, access: studio, now: now, zone: shanghai) == "不绑定分组 · 未使用")
    #expect(UserKeyPresentation.metaLine(key(group: 7), groups: groups, access: studio, now: now, zone: shanghai) == "分组 #7 · 未使用")
    // 01:00 in Shanghai is today there, still yesterday in UTC.
    let early = at("2026-10-25T17:00:00Z")
    #expect(UserKeyPresentation.metaLine(key(group: nil, lastUsed: early), groups: groups, access: studio, now: now, zone: shanghai)
        == "不绑定分组 · 最近使用 今天 01:00")
    #expect(UserKeyPresentation.metaLine(key(group: nil, lastUsed: early), groups: groups, access: studio, now: now, zone: utc)
        == "不绑定分组 · 最近使用 昨天 17:00")
}

@Test func expandedFactsExpiryConcurrencyIPAndRules() {
    // 20:00 UTC on the 31st is already the 1st in Shanghai.
    #expect(UserKeyPresentation.expiryText(at("2026-12-31T04:00:00Z"), zone: shanghai) == "至 2026-12-31")
    #expect(UserKeyPresentation.expiryText(at("2026-12-31T20:00:00Z"), zone: shanghai) == "至 2027-01-01")
    #expect(UserKeyPresentation.expiryText(nil, zone: shanghai) == "永久有效")
    #expect(UserKeyPresentation.concurrencyText(3, supported: true) == "3")
    #expect(UserKeyPresentation.concurrencyText(0, supported: false) == "—")
    #expect(UserKeyPresentation.concurrencyText(nil, supported: true) == "—")
    #expect(UserKeyPresentation.lastIPText(" 203.0.113.24 ") == "203.0.113.24")
    #expect(UserKeyPresentation.lastIPText("") == "—")
    #expect(UserKeyPresentation.lastIPText(nil) == "—")
    #expect(UserKeyPresentation.ipRuleText(whitelist: ["198.51.100.0/24", "192.0.2.1"], blacklist: ["203.0.113.9"])
        == "白名单 198.51.100.0/24、192.0.2.1 · 黑名单 203.0.113.9")
    #expect(UserKeyPresentation.ipRuleText(whitelist: [], blacklist: ["203.0.113.9"]) == "黑名单 203.0.113.9")
    #expect(UserKeyPresentation.ipRuleText(whitelist: [], blacklist: []) == "未设置")
}

@Test func rateLimitsThreeCellsAndCollapsedLine() {
    let reset = at("2026-10-26T03:20:00Z")
    guard case .windows(let cells) = UserKeyPresentation.rateLimits(limited(("5", "20", "0"), used: ("2.10", "9.40", "0"), resets: (reset, nil, nil)),
                                                                    now: now, zone: shanghai) else { Issue.record("三格"); return }
    #expect(cells.map(\.span) == [.fiveHours, .oneDay, .sevenDays])
    #expect(cells[0].headline == "42.0%" && cells[0].reading == "$2.10 / $5" && cells[0].tone == nil && cells[0].resetText == "11:20 重置")
    #expect(abs((cells[0].progress ?? 0) - 0.42) < 1e-9)
    #expect(cells[1].reading == "$9.40 / $20" && cells[1].headline == "47.0%" && cells[1].resetText == nil)
    #expect(cells[2] == UserKeyRateWindow(span: .sevenDays, headline: "不限", reading: "已用 $0.00", progress: nil, tone: nil, resetText: nil))
    guard case .windows(let half) = UserKeyPresentation.rateLimits(limited(("7.5", "0", "0"), used: ("6", "0", "0")), now: now, zone: shanghai) else {
        Issue.record("上限 7.5"); return
    }
    #expect(half[0].reading == "$6.00 / $7.50" && half[0].tone == .caution)
    guard case .windows(let usedOnly) = UserKeyPresentation.rateLimits(limited(("0", "0", "0"), used: ("0", "1.20", "0")), now: now, zone: shanghai) else {
        Issue.record("上限 0 有用量"); return
    }
    #expect(usedOnly.map(\.headline) == ["不限", "不限", "不限"] && usedOnly[1].reading == "已用 $1.20")
    #expect(UserKeyPresentation.rateLimits(limited(("0", "0", "0"), used: ("0", "0", "0")), now: now, zone: shanghai) == .none)
    guard case .windows(let full) = UserKeyPresentation.rateLimits(limited(("5", "0", "0"), used: ("4.60", "0", "0")), now: now, zone: shanghai) else {
        Issue.record("90%"); return
    }
    #expect(full[0].tone == .critical)
}

@Test func resetTextUsesServerDayBoundaries() {
    #expect(UserKeyPresentation.resetText(at("2026-10-26T03:20:00Z"), now: now, zone: shanghai) == "11:20 重置")
    #expect(UserKeyPresentation.resetText(at("2026-10-27T00:02:00Z"), now: now, zone: shanghai) == "明天 08:02 重置")
    #expect(UserKeyPresentation.resetText(at("2026-10-28T00:02:00Z"), now: now, zone: shanghai) == "10月28日 08:02 重置")
    #expect(UserKeyPresentation.resetText(at("2026-10-26T01:00:00Z"), now: now, zone: shanghai) == nil)
    #expect(UserKeyPresentation.resetText(nil, now: now, zone: shanghai) == nil)
    // 00:02 UTC on the 27th is tomorrow in UTC as well, 03:20 today.
    #expect(UserKeyPresentation.resetText(at("2026-10-26T03:20:00Z"), now: now, zone: utc) == "03:20 重置")
    #expect(UserKeyPresentation.resetText(at("2026-10-26T17:00:00Z"), now: now, zone: shanghai) == "明天 01:00 重置")
    #expect(UserKeyPresentation.resetText(at("2026-10-26T17:00:00Z"), now: now, zone: utc) == "17:00 重置")
}

@Test func resetActionShownWhenAnyWindowHasLimitOrUsage() {
    #expect(!UserKeyPresentation.showsResetAction(limited(("0", "0", "0"), used: ("0", "0", "0"))))
    #expect(UserKeyPresentation.showsResetAction(limited(("0", "0", "5"), used: ("0", "0", "0"))))
    #expect(UserKeyPresentation.showsResetAction(limited(("0", "0", "0"), used: ("0", "0.01", "0"))))
}

@Test func statusMenuTitleAndVisibility() {
    #expect(UserKeyPresentation.statusMenuTitle(key(status: "inactive")) == "启用 Key")
    #expect(UserKeyPresentation.statusMenuTitle(key(status: "disabled")) == "启用 Key")
    #expect(UserKeyPresentation.statusMenuTitle(key(status: "active", effective: "expired")) == "停用 Key")
    #expect(UserKeyPresentation.statusTarget(key(status: "inactive")) == .active)
    #expect(UserKeyPresentation.statusTarget(key(status: "quota_exhausted")) == .inactive)
    #expect(UserKeyPresentation.showsStatusMenu(key(), adminKeyWrites: true))
    #expect(!UserKeyPresentation.showsStatusMenu(key(), adminKeyWrites: false))
    #expect(!UserKeyPresentation.showsStatusMenu(key(mask: ""), adminKeyWrites: true))
}

@Test func emptyGapNoticeCopy() {
    #expect(UserKeyPresentation.notice == "这一段立即生效，不用保存，也不随“放弃更改”撤回")
    #expect(UserKeyPresentation.footnote == "换分组、停用的回执里可以撤销；重置速率限制、删除不能撤销。")
    #expect(UserKeyPresentation.emptyTitle == "还没有 Key")
    #expect(UserKeyPresentation.emptyDetail(adminKeyWrites: true) == "可以在这里替用户新建；用户也可以在 Web 端「API 密钥」里自己创建。")
    #expect(UserKeyPresentation.emptyDetail(adminKeyWrites: false) == "用户在 Web 端「API 密钥」里自己创建；创建后可以在这里换分组、重置速率限制。")
    #expect(UserKeyPresentation.gapTitle("新建 Key") == "新建 Key 需要后端新增接口")
    #expect(UserKeyPresentation.gapMessage
        == "管理员现在只能查看用户的 Key、换分组、重置速率限制。替用户新建、停用、删除 Key 要等后端加上管理接口；这里只是占位，不会执行任何操作。")
    #expect(UserKeyPresentation.groupSheetTitle(keyName: "脚本") == "换分组 · 脚本")
    #expect(UserKeyPresentation.groupSheetFootnote == "选中即生效；回执里可以撤销。")
}

@Test func groupOptionsOrderSubtitlesAndAvailability() {
    let subscriptions = [AdminUserSubscription(id: 1, groupID: 4, expiresAt: now.addingTimeInterval(86_400), status: "active")]
    let options = UserKeyPresentation.groupOptions(groups: groups, access: studio, subscriptions: subscriptions, currentGroupID: 2, now: now)
    #expect(options.map(\.groupID) == [nil, 1, 2, 3, 4, 5, 8])
    #expect(options[0] == UserKeyGroupOption(groupID: nil, title: "不绑定分组", subtitle: "这个 Key 不属于任何分组", isEnabled: true, isCurrent: false,
                                             grantsAccess: false))
    #expect(options[1].subtitle == "Anthropic · 公开分组 · 默认倍率 ×0.8")
    #expect(options[2].subtitle == "OpenAI · 公开分组 · 专属倍率 ×0.9" && options[2].isCurrent)
    #expect(options[3].subtitle == "DeepSeek · 公开分组 · 默认倍率 ×0.8 · 用户被限制，调用会被拒绝" && options[3].isEnabled)
    #expect(options[4].subtitle == "OpenAI · 订阅分组 · 有效订阅" && options[4].isEnabled)
    #expect(options[5] == UserKeyGroupOption(groupID: 5, title: "Claude Code 组", subtitle: "Anthropic · 专属分组 · 默认倍率 ×0.8 · 会同时授予这个分组",
                                             isEnabled: true, isCurrent: false, grantsAccess: true))
    // Not restricted: no refusal; an expired or suspended subscription does not count.
    let open = UserKeyAccess(allowedGroups: [5], groupRates: [5: amount("1.3")])
    let lapsed = [AdminUserSubscription(id: 1, groupID: 4, expiresAt: now.addingTimeInterval(-60), status: "active"),
                  AdminUserSubscription(id: 2, groupID: 4, status: "suspended")]
    let others = UserKeyPresentation.groupOptions(groups: groups, access: open, subscriptions: lapsed, currentGroupID: nil, now: now)
    #expect(others[0].isCurrent)
    #expect(others[3].subtitle == "DeepSeek · 公开分组 · 默认倍率 ×0.8")
    #expect(others[4].subtitle == "OpenAI · 订阅分组 · 需要这个分组的有效订阅" && !others[4].isEnabled)
    #expect(others[5].subtitle == "Anthropic · 专属分组 · 专属倍率 ×1.3" && !others[5].grantsAccess)
}

@Test func hasActiveSubscriptionMatchesBackendRule() {
    func sub(_ status: String?, expires: Date?) -> [AdminUserSubscription] { [AdminUserSubscription(id: 1, groupID: 4, expiresAt: expires, status: status)] }
    #expect(UserKeyPresentation.hasActiveSubscription(sub("active", expires: now.addingTimeInterval(60)), groupID: 4, now: now))
    #expect(UserKeyPresentation.hasActiveSubscription(sub("active", expires: nil), groupID: 4, now: now))
    #expect(!UserKeyPresentation.hasActiveSubscription(sub("active", expires: now), groupID: 4, now: now))
    #expect(!UserKeyPresentation.hasActiveSubscription(sub("expired", expires: nil), groupID: 4, now: now))
    #expect(!UserKeyPresentation.hasActiveSubscription(sub("active", expires: nil), groupID: 5, now: now))
}

@Test func newlyGrantedIgnoresAutoGrantFlag() {
    let group = { (id: Int) in groups.first { $0.id == id } }
    #expect(UserKeyPresentation.newlyGranted(target: group(5), access: studio))
    #expect(!UserKeyPresentation.newlyGranted(target: group(5), access: UserKeyAccess(allowedGroups: [5])))
    #expect(!UserKeyPresentation.newlyGranted(target: group(4), access: studio))
    #expect(!UserKeyPresentation.newlyGranted(target: group(3), access: studio))
    #expect(!UserKeyPresentation.newlyGranted(target: AdminGroup(id: 12, name: "停用专属", status: "inactive", isExclusive: true), access: studio))
    #expect(!UserKeyPresentation.newlyGranted(target: nil, access: studio))
}

@Test func changeRequestsCarryOneKindOfChange() throws {
    #expect(try body(UserKeyChange.group(from: 2, to: nil).request()) == #"{"group_id":0}"#)
    #expect(try body(UserKeyChange.group(from: nil, to: 5).request()) == #"{"group_id":5}"#)
    #expect(try body(UserKeyChange.status(.inactive).request()) == #"{"status":"inactive"}"#)
    #expect(try body(UserKeyChange.resetRateLimit.request()) == #"{"reset_rate_limit_usage":true}"#)
    #expect(UserKeyChange.group(from: 2, to: 5).operationName(keyName: "脚本") == "Key「脚本」换分组")
    #expect(UserKeyChange.status(.inactive).operationName(keyName: "脚本") == "Key「脚本」停用")
    #expect(UserKeyChange.status(.active).operationName(keyName: "脚本") == "Key「脚本」启用")
    #expect(UserKeyChange.resetRateLimit.operationName(keyName: "脚本") == "Key「脚本」重置速率限制")
}

@Test func groupReceiptsThreeForms() {
    #expect(UserKeyPresentation.groupReceipt(keyName: "脚本", targetName: nil, newlyGranted: false) == "「脚本」已不绑定分组")
    #expect(UserKeyPresentation.groupReceipt(keyName: "脚本", targetName: "Claude Code 组", newlyGranted: true) == "已改到「Claude Code 组」，并为用户添加了这个分组")
    #expect(UserKeyPresentation.groupReceipt(keyName: "脚本", targetName: "标准组", newlyGranted: false) == "「脚本」已改到「标准组」")
    #expect(UserKeyPresentation.groupName(7, groups: groups) == "分组 #7")
    #expect(UserKeyPresentation.groupName(2, groups: groups) == "标准组")
}

@Test func groupUndoPlanExactKeyOnlyAndTwoStep() throws {
    let granted = UserKeyGroupUndo(keyID: 7, keyName: "脚本", fromGroupID: 2, toGroupID: 5, newlyGranted: true)
    guard case .exact(let exact) = try UserKeyPresentation.groupUndoPlan(granted, exactUndoSupported: true) else { Issue.record("exact"); return }
    #expect(try body(exact) == #"{"group_id":2,"revoke_group_access_id":5}"#)
    let fromNothing = UserKeyGroupUndo(keyID: 7, keyName: "脚本", fromGroupID: nil, toGroupID: 5, newlyGranted: true)
    guard case .exact(let unbind) = try UserKeyPresentation.groupUndoPlan(fromNothing, exactUndoSupported: true) else { Issue.record("from nil"); return }
    #expect(try body(unbind) == #"{"group_id":0,"revoke_group_access_id":5}"#)
    let plain = UserKeyGroupUndo(keyID: 7, keyName: "脚本", fromGroupID: 2, toGroupID: 1, newlyGranted: false)
    guard case .keyOnly(let back) = try UserKeyPresentation.groupUndoPlan(plain, exactUndoSupported: true) else { Issue.record("keyOnly"); return }
    #expect(try body(back) == #"{"group_id":2}"#)
    guard case .twoStep(let first, let revoke) = try UserKeyPresentation.groupUndoPlan(granted, exactUndoSupported: false) else {
        Issue.record("twoStep"); return
    }
    #expect(try body(first) == #"{"group_id":2}"# && revoke == 5)
    #expect(granted.keyChange == .group(from: 5, to: 2))
}

@Test func allowedGroupsAfterRevokeKeepsUnknownIDs() {
    #expect(UserKeyPresentation.allowedGroupsAfterRevoke([5, 1, 99, 2], revoking: 5) == [1, 2, 99])
    #expect(UserKeyPresentation.allowedGroupsAfterRevoke(nil, revoking: 5) == [])
    #expect(UserKeyPresentation.undoKeptGrantReceipt == "Key 已还原；该分组还有其他 Key 在用，授权保留")
    #expect(UserKeyPresentation.twoStepPartialReceipt == "Key 已还原，但分组授权没收回，请在权限与并发里手动移除")
}

@Test func statusReceiptAndUndoAvailability() {
    let expired = key(effective: "expired"), exhausted = key(effective: "quota_exhausted"), fine = key(effective: "active")
    #expect(UserKeyPresentation.statusReceipt(keyName: "脚本", requested: .inactive, result: fine, now: now, simpleMode: false) == "已停用「脚本」")
    #expect(UserKeyPresentation.statusReceipt(keyName: "脚本", requested: .active, result: fine, now: now, simpleMode: false) == "已启用「脚本」")
    #expect(UserKeyPresentation.statusReceipt(keyName: "脚本", requested: .active, result: expired, now: now, simpleMode: false)
        == "已启用，但 Key 已过期，仍不能调用")
    #expect(UserKeyPresentation.statusReceipt(keyName: "脚本", requested: .active, result: exhausted, now: now, simpleMode: false)
        == "已启用，但 Key 额度已用完，仍不能调用")
    #expect(UserKeyPresentation.statusReceipt(keyName: "脚本", requested: .active, result: expired, now: now, simpleMode: true) == "已启用「脚本」")
    #expect(UserKeyPresentation.statusUndo(previous: AdminAPIKeyPrevious(status: "active")) == .active)
    #expect(UserKeyPresentation.statusUndo(previous: AdminAPIKeyPrevious(status: "inactive")) == .inactive)
    #expect(UserKeyPresentation.statusUndo(previous: AdminAPIKeyPrevious(status: "disabled")) == .inactive)
    #expect(UserKeyPresentation.statusUndo(previous: AdminAPIKeyPrevious(status: "quota_exhausted")) == nil)
    #expect(UserKeyPresentation.statusUndo(previous: nil) == nil)
    #expect(UserKeyPresentation.statusTook(.inactive, in: key(status: "inactive")))
    #expect(!UserKeyPresentation.statusTook(.inactive, in: key(status: "active")))
    #expect(UserKeyPresentation.statusIgnored(.inactive) == "这个站点还不支持停用 Key")
}

@Test func resetConfirmationAndReceiptCopy() {
    #expect(UserKeyPresentation.resetConfirmationTitle(keyName: "脚本") == "重置「脚本」的速率限制用量？")
    #expect(UserKeyPresentation.resetConfirmationMessage == "5 小时、1 天、7 天三个窗口的已用额度会归零，立即生效，不能撤销。")
    #expect(UserKeyPresentation.resetConfirm == "重置用量")
    #expect(UserKeyPresentation.resetReceipt == "速率限制已重置")
}

@Test func writeFailureClassificationNeverEchoesMessage() {
    let cases: [(APIError, UserKeyWriteFailure)] = [
        (.server(status: 404, reason: "API_KEY_NOT_FOUND"), .keyGone), (.server(status: 404, reason: "GROUP_NOT_FOUND"), .groupGone),
        (.server(status: 400, reason: "GROUP_NOT_ACTIVE"), .groupInactive), (.server(status: 400, reason: "SUBSCRIPTION_REQUIRED"), .subscriptionRequired),
        (.server(status: 409, reason: "GROUP_STILL_IN_USE"), .groupStillInUse), (.server(status: 502, reason: nil), .unconfirmed),
        (.server(status: 504, reason: nil), .unconfirmed), (.server(status: 503, reason: nil), .unconfirmed),
        (APIError(kind: .transport, message: "无法连接站点"), .unconfirmed), (.invalidResponse, .unconfirmed),
    ]
    for (error, expected) in cases { #expect(UserKeyWriteFailure(error) == expected) }
    #expect(UserKeyWriteFailure(APIError.server(status: 404, reason: "GROUP_NOT_FOUND"))?.message == "分组不存在")
    #expect(UserKeyWriteFailure(APIError.server(status: 400, reason: "GROUP_NOT_ACTIVE"))?.message == "这个分组已停用")
    #expect(UserKeyWriteFailure(APIError.server(status: 400, reason: "SUBSCRIPTION_REQUIRED"))?.message == "用户没有这个分组的有效订阅")
    #expect(UserKeyWriteFailure(APIError.server(status: 404, reason: "API_KEY_NOT_FOUND"))?.message == "这个 Key 已被删除")
    #expect(UserKeyWriteFailure.unconfirmed.message == "结果未确认，请刷新核对后再操作")
    // A 400 without a reason reads as the catalog's HTTP fallback (the envelope never carries the server's words).
    guard case .rejected(let text)? = UserKeyWriteFailure(APIError.server(status: 400, envelope: ErrorEnvelope(code: .int(400)))) else {
        Issue.record("400"); return
    }
    #expect(text.contains("400"))
    #expect(UserKeyWriteFailure(CancellationError()) == nil)
    #expect(UserKeyPresentation.failureReceipt(.groupInactive, undoing: true) == "撤销没有成功：这个分组已停用")
    #expect(UserKeyPresentation.failureReceipt(.groupInactive, undoing: false) == "这个分组已停用")
}

@Test func readBackConfirmsEachChangeKind() {
    #expect(UserKeyPresentation.readBackConfirms(.group(from: 2, to: 5), readBack: key(group: 5)))
    #expect(!UserKeyPresentation.readBackConfirms(.group(from: 2, to: 5), readBack: key(group: 2)))
    #expect(UserKeyPresentation.readBackConfirms(.group(from: 2, to: nil), readBack: key(group: nil)))
    #expect(UserKeyPresentation.readBackConfirms(.group(from: 2, to: nil), readBack: key(group: 0)))
    #expect(UserKeyPresentation.readBackConfirms(.status(.inactive), readBack: key(status: "inactive")))
    #expect(!UserKeyPresentation.readBackConfirms(.status(.inactive), readBack: key(status: "active")))
    #expect(UserKeyPresentation.readBackConfirms(.resetRateLimit, readBack: limited(("5", "0", "0"), used: ("0", "0", "0"))))
    #expect(!UserKeyPresentation.readBackConfirms(.resetRateLimit, readBack: limited(("5", "0", "0"), used: ("1", "0", "0"))))
    #expect(!UserKeyPresentation.readBackConfirms(.group(from: 2, to: 5), readBack: key(group: 5, mask: "")))
}
