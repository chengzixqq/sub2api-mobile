import Foundation
import Testing
@testable import Sub2Core

// 30 §2.3–§2.5: the user detail's wording and decisions (S3-05).

private func amount(_ text: String) -> Decimal { Decimal(string: text)! }
private let now = Date(timeIntervalSince1970: 1_792_026_000)
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

private func detailUser(_ id: Int = 3, username: String? = "王小明", email: String = "xm.wang@example.com", status: String = "active",
                        role: String? = "user", concurrency: Int? = 1) -> AdminUser {
    AdminUser(id: id, email: email, username: username, status: status, role: role, concurrency: concurrency)
}
private func summary(_ keys: [AdminAPIKey], groups: [Int: String] = [2: "标准组"], simpleMode: Bool = false,
                     canManageKeys: Bool = true) -> UserKeySummary {
    UserDetailPresentation.keySummary(keys, groupNames: groups, now: now, timeZone: shanghai, simpleMode: simpleMode, canManageKeys: canManageKeys)
}
private func ledgerPage(count: Int, total: Int, recharged: Decimal?) -> BalanceHistoryPage {
    let items = (0..<count).map { BalanceHistoryItem(id: 100 - $0, type: "balance", value: 1) }
    return BalanceHistoryPage(items: items, total: total, page: 1, pageSize: 5, pages: max((total + 4) / 5, 1), totalRecharged: recharged, breakdown: nil)
}

@Test func balanceSublineCoversTodayAndMonthGaps() {
    #expect(UserDetailPresentation.balanceSubline(today: amount("2.80"), month: amount("86.10")) == "今日消费 $2.80 · 本月 $86.10")
    #expect(UserDetailPresentation.balanceSubline(today: nil, month: amount("86.10")) == "今日消费 — · 本月 $86.10")
    #expect(UserDetailPresentation.balanceSubline(today: amount("2.80"), month: nil) == "今日消费 $2.80")
    #expect(UserDetailPresentation.balanceSubline(today: nil, month: nil) == "今日消费 —")
    #expect(UserDetailPresentation.balanceSpoken(balance: amount("12.5"), today: amount("2.8"), month: amount("86.1"), isLow: false)
        == "可用余额 $12.50，今日消费 $2.80，本月 $86.10")
    #expect(UserDetailPresentation.balanceSpoken(balance: amount("3.2"), today: nil, month: nil, isLow: true)
        == "可用余额 $3.20，今日消费 无数据，余额低")
}

@Test func keySummaryJoinsNamesGroupsIdleAndLatestUse() {
    let keys = [
        AdminAPIKey(id: 1, name: "开发密钥", groupID: 2, status: "active", effectiveStatus: "active", lastUsedAt: now.addingTimeInterval(-180)),
        AdminAPIKey(id: 2, name: "脚本", groupID: 2, status: "inactive", effectiveStatus: "inactive", lastUsedAt: now.addingTimeInterval(-7_200)),
        AdminAPIKey(id: 3, name: "备用", status: "active", effectiveStatus: "quota_exhausted", quota: 10, quotaUsed: 10),
    ]
    let line = summary(keys)
    #expect(line.meta == "3 个 · 活跃 1")
    #expect(line.title == "开发密钥、脚本、备用")
    #expect(line.groups == ["标准组", "未绑定分组"])
    #expect(line.idle == ["脚本 已停用", "备用 额度耗尽"])
    #expect(line.lastUse == "最近使用 3 分钟前")
    #expect(line.emptyNote == nil)
    #expect(line.detail == "标准组、未绑定分组 · 脚本 已停用、备用 额度耗尽 · 最近使用 3 分钟前")
    #expect(line.spokenLabel == "API Key 3 个 · 活跃 1，开发密钥、脚本、备用，标准组、未绑定分组 · 脚本 已停用、备用 额度耗尽 · 最近使用 3 分钟前")
}

@Test func keySummaryEdgeCases() {
    // An escaped name shows unescaped (S3D1-12); a group the directory does not know shows its id; group 0 is unbound.
    let keys = [AdminAPIKey(id: 9, name: "R&amp;D", groupID: 9, status: "active", effectiveStatus: "expired"),
                AdminAPIKey(id: 10, name: "临时", groupID: 0, status: "active", effectiveStatus: "active")]
    let line = summary(keys, groups: [:])
    #expect(line.title == "R&D、临时")
    #expect(line.groups == ["分组 #9", "未绑定分组"])
    #expect(line.idle == ["R&D 已过期"])
    #expect(line.lastUse == "未使用")
    // run_mode simple: expired and quota-exhausted keys still call (30 §0.1), so they are neither idle nor inactive.
    let simple = summary(keys, groups: [:], simpleMode: true)
    #expect(simple.idle.isEmpty)
    #expect(simple.meta == "2 个 · 活跃 2")
    #expect(simple.detail == "分组 #9、未绑定分组 · 未使用")
    let none = summary([])
    #expect(none.meta == "0 个")
    #expect(none.title == "还没有 Key")
    #expect(none.emptyNote == "可以在编辑用户里新建")
    #expect(none.detail == "可以在编辑用户里新建")
    #expect(summary([], canManageKeys: false).emptyNote == "用户在 Web 端创建 Key 后显示在这里")
}

@Test func ledgerMetaAndMoreLink() {
    #expect(UserDetailPresentation.ledgerMeta(ledgerPage(count: 0, total: 0, recharged: 0)) == nil)
    #expect(UserDetailPresentation.ledgerMeta(ledgerPage(count: 3, total: 3, recharged: 60)) == "总充值 $60.00")
    #expect(UserDetailPresentation.ledgerMeta(ledgerPage(count: 1, total: 1, recharged: nil)) == "总充值 —")
    #expect(UserDetailPresentation.ledgerMoreText(total: 5) == nil)
    #expect(UserDetailPresentation.ledgerMoreText(total: 6) == "全部 6 条")
    #expect(UserDetailPresentation.ledgerMoreText(total: 1_280) == "全部 1,280 条")
    #expect(UserDetailPresentation.ledgerPeek(ledgerPage(count: 7, total: 24, recharged: 70)).map(\.id) == [100, 99, 98, 97, 96])
    #expect(UserDetailPresentation.ledgerPeekSize == 5)
}

@Test func profileRowsFollowSpec() {
    let plain = UserDetailPresentation.profileRows(detailUser(3, concurrency: 0), isSelf: false)
    #expect(plain.map(\.label) == ["用户 ID", "状态", "角色", "并发上限"])
    #expect(plain.map(\.value) == ["3", "启用", "用户", "不限制"])
    #expect(Set(plain.map(\.id)).count == 4)
    let me = UserDetailPresentation.profileRows(detailUser(1024, status: "disabled", role: "admin", concurrency: nil), isSelf: true)
    #expect(me.map(\.value) == ["1024", "禁用", "管理员 · 你", "—"])
    #expect(UserDetailPresentation.profileRows(detailUser(5, role: "vendor", concurrency: 5), isSelf: false).map(\.value) == ["5", "启用", "供应商", "5"])
}

@Test func isSelfComparesIDOnly() {
    #expect(UserDetailPresentation.isSelf(detailUser(8, email: "someone-else@example.com"), meID: 8))
    #expect(!UserDetailPresentation.isSelf(detailUser(8), meID: 1))
    #expect(!UserDetailPresentation.isSelf(detailUser(8), meID: nil))
}

@Test func isSimpleRunModeTrimsAndLowercases() {
    #expect(AdminMe(server: .init(runMode: " Simple ")).isSimpleRunMode)
    #expect(!AdminMe(server: .init(runMode: "standard")).isSimpleRunMode)
    #expect(!AdminMe().isSimpleRunMode)
}

@Test func menuItemsFollowRoleAndStatus() {
    let active = UserDetailPresentation.menuItems(for: detailUser(3))
    #expect(active == [.edit, .setStatus(enable: false), .compensation, .delete])
    #expect(active.map(\.title) == ["编辑用户", "禁用用户", "发放兑换码（补偿）…", "删除用户…"])
    #expect(active.map(\.isDestructive) == [false, false, false, true])
    #expect(UserDetailPresentation.menuItems(for: detailUser(6, status: "disabled")) == [.edit, .setStatus(enable: true), .compensation, .delete])
    #expect(UserDetailMenuItem.setStatus(enable: true).title == "启用用户")
    let admin = detailUser(8, role: "admin")
    #expect(UserDetailPresentation.menuItems(for: admin) == [.edit, .compensation])
    #expect(UserDetailPresentation.menuNote(for: admin, isSelf: true) == "这是你当前登录的账号。管理员不能禁用或删除。")
    #expect(UserDetailPresentation.menuNote(for: admin, isSelf: false) == "管理员不能禁用或删除。")
    #expect(UserDetailPresentation.menuNote(for: detailUser(3), isSelf: false) == nil)
}

@Test func statusReceiptsAndFailures() {
    #expect(UserDetailPresentation.statusReceipt(displayName: "王小明", disabling: true, activeKeyCount: 2) == "已禁用 王小明 · 2 个 Key 停止调用")
    #expect(UserDetailPresentation.statusReceipt(displayName: "王小明", disabling: true, activeKeyCount: 0) == "已禁用 王小明")
    #expect(UserDetailPresentation.statusReceipt(displayName: "王小明", disabling: true, activeKeyCount: nil) == "已禁用 王小明")
    #expect(UserDetailPresentation.statusReceipt(displayName: "王小明", disabling: false, activeKeyCount: 2) == "已启用 王小明")
    let unconfirmed = UserStatusFailure(text: "结果未确认，已刷新为服务器当前状态", readsBack: true)
    #expect(UserDetailPresentation.statusFailure(APIError.server(status: 500, reason: nil))
        == UserStatusFailure(text: "操作失败：服务器未能完成请求", readsBack: true))
    #expect(UserDetailPresentation.statusFailure(KeyedWriteFailure(disposition: .unconfirmed(.stillProcessing, retryNotBefore: nil), key: "k",
                                                                   actionID: nil, lastError: nil)) == unconfirmed)
    #expect(UserDetailPresentation.statusFailure(APIError(kind: .transport, message: "连接超时")) == unconfirmed)
    #expect(UserDetailPresentation.statusFailure(CocoaError(.featureUnsupported)) == unconfirmed)
    #expect(UserDetailPresentation.statusFailure(APIError.server(status: 404, reason: "USER_NOT_FOUND")).readsBack)
    // A read-only token changed nothing: the catalog's words, no read back, never the server's message (00 §3.4).
    let readOnly = UserDetailPresentation.statusFailure(APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"))
    #expect(readOnly == UserStatusFailure(text: "当前管理访问令牌只读，不能执行此操作", readsBack: false))
    let refused = UserDetailPresentation.statusFailure(APIError.server(status: 409, reason: nil))
    #expect(refused.text == "操作冲突，请刷新后重试" && refused.readsBack)
}

@Test func deleteConfirmationCopy() {
    #expect(UserDetailPresentation.deleteConsequences(keyCount: 2) == ["名下 2 个 Key 一并删除。"])
    #expect(UserDetailPresentation.deleteConsequences(keyCount: 0).isEmpty)
    #expect(UserDetailPresentation.deleteConsequences(keyCount: nil) == ["名下的 Key 会一并删除。"])
    #expect(UserDetailPresentation.deleteExpectedText(detailUser(username: "王小明")) == "王小明")
    #expect(UserDetailPresentation.deleteExpectedText(detailUser(username: "  ", email: "nobody@example.com")) == "nobody@example.com")
    #expect(UserDetailPresentation.deleteExpectedText(detailUser(username: nil, email: "x@example.com")) == "x@example.com")
    #expect(UserDetailPresentation.deleteSiteLine(siteName: "生产站") == "站点 生产站")
}
