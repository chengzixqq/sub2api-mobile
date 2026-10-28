import Foundation
import Testing
@testable import Sub2Core

// S6-08: the compensation sheet's wording (60 §19.3) — the subject line, the plan, the summary, the receipt rows, the
// confirmation and the receipts. Dates follow the server's zone (00 §6.3).

private let code = "a3f01b2c3d4e5f60718293a4b5c6d4e8"
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let now = ISO8601DateFormatter().date(from: "2026-10-16T08:00:00Z")!
private let wang = AdminUser(id: 42, email: "wang@example.com", username: "王小明", balance: Decimal(string: "12.40")!, concurrency: 5)
private func day(_ raw: String) -> Date { ISO8601DateFormatter().date(from: raw + "T08:00:00Z")! }
private let newPlan = SubscriptionGrantPlan(kind: .new, currentExpiry: nil, newExpiry: day("2026-11-15"))
private let extendPlan = SubscriptionGrantPlan(kind: .extend, currentExpiry: day("2026-10-30"), newExpiry: day("2026-11-29"))
private let resumePlan = SubscriptionGrantPlan(kind: .resume, currentExpiry: day("2026-10-30"), newExpiry: day("2026-11-29"))
private let renewPlan = SubscriptionGrantPlan(kind: .renew, currentExpiry: day("2026-10-10"), newExpiry: day("2026-11-15"))
private let renewUnknown = SubscriptionGrantPlan(kind: .renew, currentExpiry: nil, newExpiry: day("2026-11-15"))
private func summary(_ value: RedeemGrantDraft.Value, user: AdminUser = wang, groupName: String? = "企业专线",
                     plan: SubscriptionGrantPlan? = extendPlan) -> GrantSummary {
    GrantSummary(draft: RedeemGrantDraft(value: value), user: user, groupName: groupName, plan: plan, now: now, timeZone: shanghai)
}
private func subject(_ type: CompensationType?, user: AdminUser = wang, plan: SubscriptionGrantPlan? = nil) -> String {
    RedeemGrantCopy.subjectLine(user: user, type: type, groupName: "企业专线", plan: plan, now: now, timeZone: shanghai)
}
private func grant(_ type: CompensationType, value: Decimal, groupID: Int? = nil, days: Int? = nil) -> PendingCompensation {
    PendingCompensation(serverID: UUID(), actorUserID: 7, userID: 42, userDisplayName: "王小明", userEmail: "wang@example.com", code: code,
                        type: type, value: value, groupID: groupID, validityDays: days)
}

@Test func subjectLinesPerStep() {
    #expect(subject(nil) == "wang@example.com")
    #expect(subject(.balance) == "余额 $12.40")
    #expect(subject(.concurrency) == "并发上限 5")
    #expect(subject(.concurrency, user: AdminUser(id: 1, email: "a@example.com", concurrency: 0)) == "并发上限 不限制")
    #expect(subject(.concurrency, user: AdminUser(id: 1, email: "a@example.com")) == "并发上限 —")
    #expect(subject(.subscription, plan: newPlan) == "企业专线 未订阅")
    #expect(subject(.subscription, plan: extendPlan) == "企业专线 至 10/30")
    #expect(subject(.subscription, plan: renewPlan) == "企业专线 10/10 已过期")
    #expect(subject(.subscription, plan: renewUnknown) == "企业专线 已过期")
    #expect(subject(.subscription, plan: resumePlan) == "企业专线 已暂停，至 10/30")
    #expect(subject(.subscription) == "企业专线")
}

@Test func planChangeAndNoteCopy() {
    let rows: [(SubscriptionGrantPlan, String, String)] = [
        (newPlan, "新开通 · 到期 11/15", "还没有这个订阅：从今天开通。"),
        (extendPlan, "到期 10/30 → 11/29", "已有生效中的订阅：在原到期日 10/30 上延长。"),
        (resumePlan, "恢复生效 · 到期 10/30 → 11/29", "订阅暂停中：在原到期日上延长，并恢复为生效。"),
        (renewPlan, "重新开通 · 到期 11/15", "订阅 10/10 已过期：从今天重新算，用量清零。"),
        (renewUnknown, "重新开通 · 到期 11/15", "订阅已过期：从今天重新算，用量清零。"),
    ]
    for (plan, change, note) in rows {
        #expect(RedeemGrantCopy.planChange(plan, now: now, timeZone: shanghai) == change)
        #expect(RedeemGrantCopy.planNote(plan, now: now, timeZone: shanghai) == note)
    }
    let nextYear = SubscriptionGrantPlan(kind: .extend, currentExpiry: day("2026-12-20"), newExpiry: day("2027-01-19"))
    #expect(RedeemGrantCopy.planChange(nextYear, now: now, timeZone: shanghai) == "到期 12/20 → 2027/01/19")
    #expect(RedeemGrantCopy.subscriptionsUnavailableNote == "暂时读不到这个用户的订阅，发放后以服务器结果为准")
}

@Test func summaryAndSubmitTitles() {
    let balance = summary(.balance(10))
    #expect(balance.type == .balance && balance.isMoney && balance.amount == 10)
    #expect(balance.what == "$10.00 余额" && balance.short == "$10.00" && balance.value == "$10.00")
    #expect(balance.change == "余额 $12.40 → $22.40" && balance.submitTitle == "发放 $10.00")
    let half = summary(.balance(Decimal(string: "10.5")!))
    #expect(half.short == "$10.50" && half.change == "余额 $12.40 → $22.90")

    let concurrency = summary(.concurrency(2))
    #expect(!concurrency.isMoney && concurrency.amount == 2)
    #expect(concurrency.what == "+2 并发" && concurrency.short == "+2 并发" && concurrency.value == "+2 并发")
    #expect(concurrency.change == "并发上限 5 → 7" && concurrency.submitTitle == "发放 +2 并发")
    #expect(summary(.concurrency(2), user: AdminUser(id: 1, email: "a@example.com")).change == "并发上限 +2")

    let subscription = summary(.subscription(groupID: 3, days: 30))
    #expect(!subscription.isMoney && subscription.amount == 30)
    #expect(subscription.what == "企业专线 30 天订阅" && subscription.short == "30 天订阅" && subscription.value == "企业专线 · 30 天")
    #expect(subscription.change == "到期 10/30 → 11/29" && subscription.submitTitle == "发放 30 天订阅")
    #expect(summary(.subscription(groupID: 3, days: 30), plan: nil).change == "到期以服务器结果为准")
    #expect(summary(.subscription(groupID: 3, days: 30), groupName: nil).what == "分组 #3 30 天订阅")
}

@Test func receiptRowsHideTheFullCode() {
    func rows(_ summary: GrantSummary) -> [GrantReceiptRow] { RedeemGrantCopy.receiptRows(summary, user: wang, siteName: "主站", code: code) }
    let balance = rows(summary(.balance(10)))
    #expect(balance == [GrantReceiptRow(label: "对象", value: "王小明 · wang@example.com"), GrantReceiptRow(label: "站点", value: "主站"),
                        GrantReceiptRow(label: "类型", value: "余额"), GrantReceiptRow(label: "变化", value: "余额 $12.40 → $22.40"),
                        GrantReceiptRow(label: "兑换码", value: "a3f0····d4e8"), GrantReceiptRow(label: "发放", value: "$10.00", isEmphasized: true)])
    let concurrency = rows(summary(.concurrency(2)))
    #expect(concurrency.map { $0.label } == ["对象", "站点", "类型", "数值", "变化", "兑换码"])
    #expect(concurrency[2].value == "并发" && concurrency[3].value == "+2 并发" && concurrency[4].value == "并发上限 5 → 7")
    let subscription = rows(summary(.subscription(groupID: 3, days: 30)))
    #expect(subscription.map { $0.label } == ["对象", "站点", "类型", "数值", "变化", "兑换码"])
    #expect(subscription[2].value == "订阅" && subscription[3].value == "企业专线 · 30 天" && subscription[4].value == "到期 10/30 → 11/29")
    let all = balance + concurrency + subscription
    #expect(all.allSatisfy { !$0.value.contains(code) })
    #expect(all.filter { $0.isEmphasized }.map { $0.label } == ["发放"])
}

@Test func confirmationCopy() {
    let balance = RedeemGrantCopy.confirmation(summary(.balance(10)), userName: "王小明", siteName: "主站", notes: "", userDisabled: false, faceIDLine: nil)
    #expect(balance == GrantConfirmation(title: "向「王小明」发放 $10.00 余额？", message: "站点 主站 · 余额 $12.40 → $22.40", button: "发放 $10.00",
                                         isDestructive: true))
    let full = RedeemGrantCopy.confirmation(summary(.balance(10)), userName: "王小明", siteName: "主站", notes: "故障补偿", userDisabled: true,
                                            faceIDLine: "超过 $100，确认后验证 Face ID。")
    #expect(full.message == "站点 主站 · 余额 $12.40 → $22.40\n备注：故障补偿\n该用户已禁用。\n发放后仍不能调用，需先启用。\n超过 $100，确认后验证 Face ID。")
    let concurrency = RedeemGrantCopy.confirmation(summary(.concurrency(2)), userName: "王小明", siteName: "主站", notes: "", userDisabled: false,
                                                   faceIDLine: nil)
    #expect(concurrency == GrantConfirmation(title: "向「王小明」发放 +2 并发？", message: "站点 主站 · 并发上限 5 → 7", button: "发放 +2 并发",
                                             isDestructive: false))
    let subscription = RedeemGrantCopy.confirmation(summary(.subscription(groupID: 3, days: 30)), userName: "王小明", siteName: "主站", notes: "",
                                                    userDisabled: false, faceIDLine: nil)
    #expect(subscription.title == "向「王小明」发放 企业专线 30 天订阅？" && subscription.button == "发放 30 天订阅" && !subscription.isDestructive)
    #expect(subscription.message == "站点 主站 · 到期 10/30 → 11/29")
}

@Test func receiptsAndFootnotes() {
    #expect(RedeemGrantCopy.grantedReceipt(userName: "王小明", what: "$10.00 余额", replayed: false) == "已向 王小明 发放 $10.00 余额")
    #expect(RedeemGrantCopy.grantedReceipt(userName: "王小明", what: "$10.00 余额", replayed: true) == "这笔补偿此前已发放，没有重复执行")
    #expect(RedeemGrantCopy.reconciledReceipt(grant(.balance, value: 10), groupName: nil) == "已核对：已向 王小明 发放 $10.00 余额")
    #expect(RedeemGrantCopy.reconciledReceipt(grant(.balance, value: Decimal(string: "10.5")!), groupName: nil) == "已核对：已向 王小明 发放 $10.50 余额")
    #expect(RedeemGrantCopy.reconciledReceipt(grant(.concurrency, value: 2), groupName: nil) == "已核对：已向 王小明 发放 +2 并发")
    let subscription = grant(.subscription, value: 30, groupID: 3, days: 30)
    #expect(RedeemGrantCopy.reconciledReceipt(subscription, groupName: "企业专线") == "已核对：已向 王小明 发放 企业专线 30 天订阅")
    #expect(RedeemGrantCopy.reconciledReceipt(subscription, groupName: nil) == "已核对：已向 王小明 发放 分组 #3 30 天订阅")
    #expect(RedeemGrantCopy.rebateFootnote == "按兑换处理：开启邀请返利时，邀请人会照常得到返利（和用户自己兑换一样，不看“管理员充值参与返利”开关）。")
    #expect(CompensationType.allCases.map { $0.grantLabel } == ["余额", "并发", "订阅"])
    #expect(CompensationType.allCases.map { $0.grantTitle } == ["余额补偿", "并发补偿", "订阅补偿"])
    #expect(CompensationType.allCases.map { $0.grantHint } == ["直接计入余额，按资金操作确认。", "提高这个用户的并发上限。", "开通或延长一个订阅分组。"])
}
