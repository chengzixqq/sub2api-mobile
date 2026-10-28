import Foundation
import Testing
@testable import Sub2Core

// S3-08: the top-up / refund keypad as pure functions (30 §3.3–§3.4, R03, R05, D26, U27).

private func money(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private let siteID = UUID(uuidString: "5C000000-0000-4000-8000-000000000001")!
private let recordID = UUID(uuidString: "5C000000-0000-4000-8000-0000000000AA")!
private let confirmedAt = Date(timeIntervalSince1970: 1_800_000_000)

private func draft(_ balance: String = "12.40", _ direction: BalanceDirection = .credit, typed: String = "") -> BalanceChangeDraft {
    BalanceChangeDraft(currentBalance: money(balance), direction: direction).editingAmount(typed)
}
private func pending(_ operation: BalanceOperation, _ amount: String, id: UUID = UUID(), createdAt: Date? = confirmedAt) -> PendingBalanceOperation {
    PendingBalanceOperation(id: id, serverID: siteID, userID: 3, amount: money(amount), operation: operation, actorUserID: 1,
                            createdAt: createdAt ?? confirmedAt, userDisplayName: "王小明", userEmail: "xm.wang@example.com")
}
private func operation(of draft: BalanceChangeDraft) throws -> PendingBalanceOperation {
    try draft.pendingOperation(id: recordID, serverID: siteID, userID: 3, actorUserID: 1, createdAt: confirmedAt,
                               userDisplayName: "王小明", userEmail: "xm.wang@example.com")
}

@Test func emptyDraftShowsGreyZeroAndCannotSubmit() {
    #expect(BalanceChangeDraft.maxDigits == 7 && BalanceChangeDraft.maxFractionDigits == 2)
    for direction in [BalanceDirection.credit, .debit] {
        let empty = draft("12.40", direction)
        #expect(empty.amountDisplay == "$0")
        #expect(empty.isAmountEmpty)
        #expect(empty.previewText == "输入金额")
        #expect(empty.submitTitle == (direction == .credit ? "充值" : "退款"))
        #expect(!empty.canSubmit && !empty.exceedsBalance)
        #expect(empty.amount == nil)
    }
}

@Test func typedAmountDrivesPreviewAndSubmit() throws {
    let topUp = draft(typed: "50")
    #expect(topUp.amountDisplay == "$50" && !topUp.isAmountEmpty)
    #expect(topUp.previewText == "充值后余额 $62.40")
    #expect(topUp.submitTitle == "充值 $50.00")
    #expect(topUp.canSubmit && topUp.operation == .add && topUp.requestAmount == 50)
    let refund = draft("12.40", .debit, typed: "10")
    #expect(refund.amountDisplay == "\u{2212}$10")
    #expect(refund.previewText == "退款后余额 $2.40")
    #expect(refund.submitTitle == "退款 $10.00" && refund.operation == .subtract)
    let over = draft("12.40", .debit, typed: "12.41")
    #expect(over.exceedsBalance && !over.canSubmit)
    #expect(over.previewText == "超过当前余额")
    #expect(draft("12.40", .debit, typed: "12.4").canSubmit)
    for zero in ["0", "0.", "0.00"] {
        let value = draft(typed: zero)
        #expect(!value.canSubmit, Comment(rawValue: zero))
        #expect(value.previewText == "输入金额")
        #expect(value.submitTitle == "充值")
    }
    #expect(draft(typed: "12.").amount == 12)
    #expect(draft(typed: "12.").amountDisplay == "$12.")
}

@Test func allBalanceSendsSetZeroUntilDigitsChange() throws {
    let all = draft("12.40", .debit).choosingAllBalance()
    #expect(all.isAllBalance && all.amountText == "12.40")
    #expect(all.operation == .set && all.requestAmount == 0)
    #expect(all.amountDisplay == "\u{2212}$12.40")
    #expect(all.previewText == "退款后余额 $0.00")
    #expect(all.submitTitle == "退款 $12.40")
    #expect(all.canSubmit && !all.exceedsBalance)
    // A key the keypad refused leaves the text as it was, so the choice stays; any change of the digits or the direction ends it.
    #expect(all.editingAmount("12.40").isAllBalance)
    #expect(all.editingNotes("补偿").isAllBalance)
    let edited = all.editingAmount("12.4")
    #expect(!edited.isAllBalance && edited.operation == .subtract && edited.requestAmount == money("12.4"))
    let switched = all.switching(to: .credit)
    #expect(!switched.isAllBalance && switched.direction == .credit && switched.amountText == "12.40")
    #expect(all.switching(to: .debit) == all)
}

@Test func allBalanceOnlyForRefundWithPositiveBalance() {
    #expect(draft("12.40", .debit).canChooseAllBalance)
    #expect(!draft("12.40", .credit).canChooseAllBalance)
    #expect(!draft("0", .debit).canChooseAllBalance)
    #expect(!draft("-3", .debit).canChooseAllBalance)
    #expect(draft("12.40", .credit).choosingAllBalance() == draft("12.40", .credit))
    #expect(draft("0", .debit).choosingAllBalance() == draft("0", .debit))
    #expect(BalanceChangeDraft.keypadText(money("12.4")) == "12.40")
    #expect(BalanceChangeDraft.keypadText(money("12.405")) == "12.41")
    #expect(BalanceChangeDraft.keypadText(50) == "50.00")
    #expect(BalanceChangeDraft.keypadText(1020) == "1020.00")
}

@Test func pendingOperationFreezesTheBodyAtConfirmation() throws {
    let topUp = try operation(of: draft(typed: "50").editingNotes("  补偿 10/16 故障 \n"))
    #expect(topUp.id == recordID && topUp.serverID == siteID && topUp.userID == 3 && topUp.actorUserID == 1)
    #expect(topUp.createdAt == confirmedAt && topUp.userDisplayName == "王小明" && topUp.userEmail == "xm.wang@example.com")
    #expect(topUp.notes == "补偿 10/16 故障" && topUp.requestID == recordID.uuidString.lowercased())
    #expect(String(decoding: try topUp.requestBody(), as: UTF8.self) == #"{"balance":"50","notes":"补偿 10\/16 故障","operation":"add"}"#)
    let all = try operation(of: draft("12.40", .debit).choosingAllBalance())
    #expect(String(decoding: try all.requestBody(), as: UTF8.self) == #"{"balance":"0","notes":"","operation":"set"}"#)
    #expect(throws: APIError.invalidAmount) { try operation(of: draft(typed: "0")) }
    #expect(throws: APIError.invalidAmount) { try operation(of: draft("12.40", .debit, typed: "13")) }
}

@Test func judgedAmountFollowsD26() {
    #expect(BalanceChangeDraft.judgedAmount(operation: .add, amount: 150, currentBalance: 10) == 150)
    #expect(BalanceChangeDraft.judgedAmount(operation: .subtract, amount: 150, currentBalance: 500) == 150)
    #expect(BalanceChangeDraft.judgedAmount(operation: .set, amount: 0, currentBalance: 500) == 500)
    #expect(BalanceChangeDraft.judgedAmount(operation: .set, amount: 20, currentBalance: 500) == 480)
    #expect(BalanceChangeDraft.judgedAmount(operation: .set, amount: 520, currentBalance: 500) == 20)
    #expect(BalanceChangeDraft.judgedAmount(operation: .set, amount: 20, currentBalance: nil) == nil)
    #expect(draft(typed: "150").biometricAmount == 150)
    #expect(draft("500", .debit).choosingAllBalance().biometricAmount == 500)
}

@Test func confirmationReadsLikeTheDesign() {
    let topUp = BalanceConfirmation(draft: draft(typed: "50").editingNotes(" 补偿 "), userDisplayName: "王小明", siteName: "主站",
                                    userIsDisabled: false, faceIDLine: nil, pendingSameDirection: nil)
    #expect(topUp.title == "向「王小明」充值 $50.00？")
    #expect(topUp.message == "站点 主站 · 余额 $12.40 → $62.40\n备注：补偿")
    #expect(topUp.confirmTitle == "充值 $50.00")
    let disabled = BalanceConfirmation(draft: draft("0", typed: "150"), userDisplayName: "赵磊", siteName: "主站", userIsDisabled: true,
                                       faceIDLine: "超过 $100，确认后验证 Face ID。", pendingSameDirection: nil)
    #expect(disabled.message == "站点 主站 · 余额 $0.00 → $150.00\n该用户已禁用。\n充值后仍不能调用，需先启用。\n超过 $100，确认后验证 Face ID。")
    let disabledRefund = BalanceConfirmation(draft: draft("8", .debit, typed: "5"), userDisplayName: "赵磊", siteName: "主站", userIsDisabled: true,
                                             faceIDLine: nil, pendingSameDirection: nil)
    #expect(disabledRefund.title == "向「赵磊」退款 $5.00？")
    #expect(disabledRefund.message == "站点 主站 · 余额 $8.00 → $3.00\n该用户已禁用。")
    let all = BalanceConfirmation(draft: draft("12.40", .debit).choosingAllBalance(), userDisplayName: "王小明", siteName: "主站",
                                  userIsDisabled: false, faceIDLine: nil, pendingSameDirection: nil)
    #expect(all.title == "向「王小明」退款全部余额？")
    #expect(all.message == "站点 主站 · 余额 $12.40 → $0.00\n按服务器执行时的余额归零。")
    #expect(all.confirmTitle == "退款全部余额")
}

@Test func sameDirectionPendingWarnsAndRenamesTheButton() {
    let warned = BalanceConfirmation(draft: draft(typed: "20").editingNotes("补偿"), userDisplayName: "王小明", siteName: "主站",
                                     userIsDisabled: false, faceIDLine: nil, pendingSameDirection: pending(.add, "50"))
    #expect(warned.message == "上一笔 $50.00 充值还没核对。如果它其实已入账，这一笔会再入账一次。\n站点 主站 · 余额 $12.40 → $32.40\n备注：补偿")
    #expect(warned.confirmTitle == "仍要充值 $20.00")
    #expect(warned.title == "向「王小明」充值 $20.00？")
    let all = BalanceConfirmation(draft: draft("12.40", .debit).choosingAllBalance(), userDisplayName: "王小明", siteName: "主站",
                                  userIsDisabled: false, faceIDLine: nil, pendingSameDirection: pending(.set, "0"))
    #expect(all.message.hasPrefix("上一笔全部余额退款还没核对。"))
    #expect(all.confirmTitle == "仍要退款全部余额")
    let refund = BalanceConfirmation(draft: draft("12.40", .debit, typed: "2"), userDisplayName: "王小明", siteName: "主站",
                                     userIsDisabled: false, faceIDLine: nil, pendingSameDirection: pending(.subtract, "12.5"))
    #expect(refund.message.hasPrefix("上一笔 $12.50 退款还没核对。"))
    #expect(refund.confirmTitle == "仍要退款 $2.00")
}

@Test func pendingCheckPicksTheOldestRecordOfTheGate() {
    let later = pending(.add, "20", createdAt: confirmedAt.addingTimeInterval(60))
    let earlier = pending(.add, "50", createdAt: confirmedAt)
    let other = pending(.add, "70")
    #expect(BalancePendingCheck(gate: .overridable([later.id, earlier.id]), balances: [other, later, earlier]) == .sameDirection(earlier))
    #expect(BalancePendingCheck(gate: .overridable([UUID()]), balances: [later, earlier]) == .clear)
    #expect(BalancePendingCheck(gate: .clear, balances: [later]) == .clear)
    #expect(BalancePendingCheck(gate: .paused(.balance), balances: []) == .paused(message: PendingMoneyKind.balance.unreadableMessage))
    // A record saved before S0-06 has no createdAt and counts as the oldest.
    let legacy = try! JSONDecoder().decode(PendingBalanceOperation.self, from: Data(
        #"{"id":"5C000000-0000-4000-8000-0000000000BB","serverID":"\#(siteID.uuidString)","userID":3,"amount":"30","operation":"add","notes":""}"#.utf8))
    #expect(BalancePendingCheck(gate: .overridable([earlier.id, legacy.id]), balances: [earlier, legacy]) == .sameDirection(legacy))
}

@Test func entryPromptNamesThePendingWrite() {
    #expect(BalanceChangeCopy.entryTitle(pending(.add, "50")) == "上一笔 $50.00 充值结果未确认")
    #expect(BalanceChangeCopy.entryTitle(pending(.subtract, "12.5")) == "上一笔 $12.50 退款结果未确认")
    #expect(BalanceChangeCopy.entryTitle(pending(.set, "0")) == "上一笔全部余额退款结果未确认")
    #expect(BalanceChangeCopy.entryTitle(pending(.set, "80")) == "上一笔 $80.00 余额设置结果未确认")
    #expect(BalanceChangeCopy.entryTitle(pending(.add, "50.125")) == "上一笔 $50.125 充值结果未确认")
    #expect(BalanceChangeCopy.entryMessage == "先核对可避免重复入账")
    #expect(BalanceChangeCopy.reconcileFirst == "先核对")
    #expect(BalanceChangeCopy.proceedAnyway(.credit) == "仍要充值" && BalanceChangeCopy.proceedAnyway(.debit) == "仍要退款")
}

@Test func progressFollowsKeyedWriteEvents() {
    #expect(BalanceWriteProgress(.actionID(UUID())) == nil)
    #expect(BalanceWriteProgress(.confirming(retry: 1)) == .confirming(retry: 1))
    #expect(BalanceWriteProgress(.waitingForServer(elapsedSeconds: 12)) == .waiting(elapsedSeconds: 12))
    #expect(BalanceWriteProgress.submitting.title == "正在提交…" && BalanceWriteProgress.submitting.detail == nil)
    #expect(BalanceWriteProgress.confirming(retry: 2).title == "正在确认结果…")
    #expect(BalanceWriteProgress.waiting(elapsedSeconds: 12).title == "正在等待服务器结果…")
    #expect(BalanceWriteProgress.waiting(elapsedSeconds: 12).detail == "已等待 12 秒")
}

@Test func fixedCopy() {
    #expect(BalanceChangeCopy.userLine(name: "王小明", balance: money("12.40")) == "王小明 · 余额 $12.40")
    #expect(BalanceChangeCopy.allBalancePill(1020) == "全部余额 $1,020.00")
    #expect(BalanceChangeCopy.notesLabel == "备注" && BalanceChangeCopy.notesPlaceholder == "可选，写进充值记录")
    #expect(BalanceChangeCopy.disabledBadge == "已禁用")
    #expect(BalanceChangeCopy.verb(.credit) == "充值" && BalanceChangeCopy.verb(.debit) == "退款")
}
