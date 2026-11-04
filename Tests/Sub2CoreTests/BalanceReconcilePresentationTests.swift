import Foundation
import Testing
@testable import Sub2Core

// S3-07: 30 §2.3 待核对横幅, §3.4 核对 dialogs and receipts, R02 titles, C-26 old logins (S3D1-08).

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let site = UUID(uuidString: "5A000000-0000-4000-8000-000000000001")!
private let oldLogin = UUID(uuidString: "5A000000-0000-4000-8000-000000000002")!

private func balance(_ operation: BalanceOperation, _ amount: String, id: UUID = UUID(), serverID: UUID = site, userID: Int = 1,
                     createdAt: Date? = now.addingTimeInterval(-300), name: String? = "Alice") -> PendingBalanceOperation {
    let op = PendingBalanceOperation(id: id, serverID: serverID, userID: userID, amount: Decimal(string: amount)!, operation: operation,
                                     notes: "补偿", actorUserID: 1, createdAt: createdAt ?? now, userDisplayName: name, userEmail: "alice@example.com")
    guard createdAt == nil else { return op }
    // Saved before S0-06: no createdAt.
    let json = #"{"id":"\#(id.uuidString)","serverID":"\#(serverID.uuidString)","userID":\#(userID),"amount":\#(amount),"operation":"\#(operation.rawValue)","notes":""}"#
    return try! JSONDecoder().decode(PendingBalanceOperation.self, from: Data(json.utf8))
}
private func grant(_ value: Decimal, userID: Int = 1, serverID: UUID = site, createdAt: Date = now.addingTimeInterval(-120)) -> PendingCompensation {
    PendingCompensation(serverID: serverID, actorUserID: 1, createdAt: createdAt, userID: userID, userDisplayName: "Alice",
                        userEmail: "alice@example.com", code: "GRANT-0001", type: .balance, value: value)
}
private func row(delta: String? = "50.00000000", before: String? = "12.40000000", after: String? = "62.40000000", notes: String? = "补偿",
                 createdAt: String? = "2027-01-15T01:41:00Z") throws -> UserAdjustment {
    func text(_ value: String?) -> String { value.map { "\"\($0)\"" } ?? "null" }
    let json = #"{"id":9,"kind":"balance","operation":"add","delta":\#(text(delta)),"before_value":\#(text(before)),"after_value":\#(text(after)),"user_id":1,"notes":\#(text(notes)),"created_at":\#(text(createdAt))}"#
    return try JSONDecoder().decode(UserAdjustment.self, from: Data(json.utf8))
}
private func titles(_ prompt: BalanceReconcilePrompt?) -> [String] { prompt?.actions.map(\.title) ?? [] }
private let sameAdmin = BalanceRetryContext(permission: .allowed)

@Test func bannerTitlesFollowTheSharedLine() {
    #expect(BalanceReconcilePresentation.bannerTitle(balance(.add, "50").summary) == "充值 $50.00 结果待核对")
    #expect(BalanceReconcilePresentation.bannerTitle(balance(.subtract, "12.5").summary) == "退款 $12.50 结果待核对")
    #expect(BalanceReconcilePresentation.bannerTitle(balance(.set, "0").summary) == "退款结果待核对 · 全部余额")
    #expect(BalanceReconcilePresentation.bannerTitle(balance(.set, "30").summary) == "余额设置结果待核对")
    #expect(BalanceReconcilePresentation.bannerTitle(grant(10).summary) == "补偿结果待核对 · $10.00")
    #expect(BalanceReconcilePresentation.bannerTitle(balance(.add, "0.125").summary) == "充值 $0.125 结果待核对")
}

@Test func bannerDetailShowsRelativeStart() {
    #expect(BalanceReconcilePresentation.bannerDetail(createdAt: now.addingTimeInterval(-300), now: now, timeZone: shanghai)
            == "5 分钟前发起，未收到服务器确认")
    let morning = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: shanghai, year: 2027, month: 1, day: 15, hour: 9, minute: 41).date!
    #expect(BalanceReconcilePresentation.bannerDetail(createdAt: morning, now: morning.addingTimeInterval(7_200), timeZone: shanghai)
            == "今天 09:41 发起，未收到服务器确认")
    #expect(BalanceReconcilePresentation.bannerDetail(createdAt: now, now: now, timeZone: shanghai) == "刚刚发起，未收到服务器确认")
    #expect(BalanceReconcilePresentation.bannerDetail(createdAt: nil, now: now, timeZone: shanghai) == "未收到服务器确认")
}

@Test func bannerEntriesShowEarliestBalanceThenCompensations() {
    let first = balance(.add, "50", createdAt: now.addingTimeInterval(-600))
    let second = balance(.subtract, "5", createdAt: now.addingTimeInterval(-60))
    let compensation = grant(10)
    let otherUser = balance(.add, "1", userID: 2, createdAt: now.addingTimeInterval(-900))
    let batch = PendingRedeemBatch(serverID: site, actorUserID: 1, createdAt: now, spec: RedeemGenerateSpec(type: .balance, value: 10, count: 2))
    let records: [any PendingMoneyWrite] = [otherUser, first, compensation, second, batch]
    let entries = BalanceReconcilePresentation.bannerEntries(records, userID: 1, currentServerID: site, now: now, timeZone: shanghai)
    #expect(entries.map(\.id) == [first.id, compensation.id])
    #expect(entries.map(\.kind) == [.balance, .compensation])
    #expect(entries.first?.title == "充值 $50.00 结果待核对")
    #expect(entries.first?.detail == "10 分钟前发起，未收到服务器确认")
    #expect(entries.allSatisfy { $0.originNote == nil })
    // Once the first is settled the next one shows.
    let next = BalanceReconcilePresentation.bannerEntries([otherUser, compensation, second], userID: 1, currentServerID: site, now: now, timeZone: shanghai)
    #expect(next.map(\.id) == [second.id, compensation.id])
    #expect(BalanceReconcilePresentation.bannerEntries([otherUser, batch], userID: 1, currentServerID: site, now: now, timeZone: shanghai).isEmpty)
}

@Test func bannerEntriesMarkOldLoginRecords() {
    let old = balance(.add, "50", serverID: oldLogin, createdAt: now.addingTimeInterval(-60))
    let legacy = balance(.subtract, "3", createdAt: nil)
    let entries = BalanceReconcilePresentation.bannerEntries([old, legacy], userID: 1, currentServerID: site, now: now, timeZone: shanghai)
    // A record without createdAt counts as the earliest.
    #expect(entries.map(\.id) == [legacy.id])
    #expect(entries.first?.detail == "未收到服务器确认")
    let onlyOld = BalanceReconcilePresentation.bannerEntries([old, grant(2, serverID: oldLogin)], userID: 1, currentServerID: site, now: now,
                                                             timeZone: shanghai)
    #expect(onlyOld.map(\.originNote) == ["这笔在本站点的旧登录下发起", "这笔在本站点的旧登录下发起"])
}

@Test func originAliasIsMoneyRecordOrigin() {
    let alias = PendingRecordOrigin(recordServerID: oldLogin, currentServerID: site, sameAddress: [site, oldLogin])
    #expect(alias == MoneyRecordOrigin.Kind(recordServerID: oldLogin, currentServerID: site, sameAddress: [site, oldLogin]))
    #expect(alias == .sameAddressOldLogin)
    #expect(SettingsPresentation.oldLoginRowNote == MoneyRecordOrigin.oldLoginNote)
}

@Test func executedReceiptUsesLedgerDeltaAndBalances() throws {
    #expect(BalanceReconcilePresentation.executedReceipt(try row(), for: balance(.add, "50")) == "已核对：服务器已入账 $50.00（余额 $12.40 → $62.40）")
    let refund = try row(delta: "-12.50000000", before: "25.00000000", after: "12.50000000")
    #expect(BalanceReconcilePresentation.executedReceipt(refund, for: balance(.subtract, "12.5")) == "已核对：服务器已扣除 $12.50（余额 $25.00 → $12.50）")
    let wipe = try row(delta: "-8.00000000", before: "8.00000000", after: "0.00000000")
    #expect(BalanceReconcilePresentation.executedReceipt(wipe, for: balance(.set, "0")) == "已核对：服务器已扣除 $8.00（余额 $8.00 → $0.00）")
}

@Test func executedReceiptFallsBackWithoutLedgerValues() throws {
    let bare = try row(delta: nil, before: nil, after: nil)
    #expect(BalanceReconcilePresentation.executedReceipt(bare, for: balance(.add, "50")) == "已核对：服务器已入账 $50.00")
    #expect(BalanceReconcilePresentation.executedReceipt(bare, for: balance(.subtract, "12.5")) == "已核对：服务器已扣除 $12.50")
    #expect(BalanceReconcilePresentation.executedReceipt(bare, for: balance(.set, "0")) == "已核对：服务器已扣除全部余额")
    #expect(BalanceReconcilePresentation.executedReceipt(bare, for: balance(.set, "30")) == "已核对：服务器已执行余额设置")
    let noBalances = try row(before: nil)
    #expect(BalanceReconcilePresentation.executedReceipt(noBalances, for: balance(.add, "50")) == "已核对：服务器已入账 $50.00")
}

@Test func notExecutedPromptForSameAdministrator() {
    let prompt = BalanceReconcilePresentation.prompt(for: .notExecuted, op: balance(.add, "50"), context: sameAdmin, now: now, timeZone: shanghai)
    #expect(prompt?.title == "服务器上没有这笔记录")
    #expect(prompt?.message == "可能还没执行，或请求没送达。用同一编号重试是安全的：服务器做过会直接返回原结果，不会重复入账。")
    #expect(titles(prompt) == ["用同一编号重试", "放弃这笔", "取消"])
    #expect(prompt?.actions.map(\.isDestructive) == [false, true, false])
    #expect(prompt?.actions.map(\.isCancel) == [false, false, true])
    #expect(prompt?.actions.allSatisfy(\.isEnabled) == true)
}

@Test func notExecutedPromptForOtherAdministratorHasNoRetry() {
    let other = BalanceRetryContext(permission: .otherActor, actorLabel: "bob@example.com")
    let refund = BalanceReconcilePresentation.prompt(for: .notExecuted, op: balance(.subtract, "12.5"), context: other, now: now, timeZone: shanghai)
    #expect(refund?.message == "这笔由 bob@example.com 发起，只能由同一管理员重试；可以放弃后重新退款。")
    #expect(titles(refund) == ["放弃这笔", "取消"])
    let topup = BalanceReconcilePresentation.prompt(for: .notExecuted, op: balance(.add, "50"), context: BalanceRetryContext(permission: .otherActor),
                                                    now: now, timeZone: shanghai)
    #expect(topup?.message == "这笔由其他管理员发起，只能由同一管理员重试；可以放弃后重新充值。")
    let numbered = BalanceRetryContext(permission: .otherActor, actorLabel: "管理员 #7")
    #expect(BalanceReconcilePresentation.prompt(for: .notExecuted, op: balance(.add, "50"), context: numbered, now: now, timeZone: shanghai)?.message
            == "这笔由管理员 #7 发起，只能由同一管理员重试；可以放弃后重新充值。")
}

@Test func notExecutedPromptForUnknownSenderKeepsRetry() {
    let prompt = BalanceReconcilePresentation.prompt(for: .notExecuted, op: balance(.add, "50"),
                                                     context: BalanceRetryContext(permission: .allowedActorUnknown), now: now, timeZone: shanghai)
    #expect(prompt?.message.hasSuffix("\n无法确认发起人") == true)
    #expect(titles(prompt) == ["用同一编号重试", "放弃这笔", "取消"])
    #expect(prompt?.actions.first?.isEnabled == true)
}

@Test func heldRetryIsDisabledWithStoreUnavailableLine() {
    let prompt = BalanceReconcilePresentation.prompt(for: .notExecuted, op: balance(.add, "50"),
                                                     context: BalanceRetryContext(permission: .allowed, isHeld: true), now: now, timeZone: shanghai)
    #expect(prompt?.message.hasSuffix("\n服务器暂时无法受理，稍后用同一编号重试") == true)
    #expect(prompt?.actions.map(\.isEnabled) == [false, true, true])
}

@Test func readOnlyTokenDisablesRetry() {
    let both = BalanceRetryContext(permission: .allowed, isHeld: true, isReadOnly: true)
    let prompt = BalanceReconcilePresentation.prompt(for: .notExecuted, op: balance(.add, "50"), context: both, now: now, timeZone: shanghai)
    #expect(prompt?.message.hasSuffix("\n当前登录的是只读令牌，不能修改") == true)
    #expect(prompt?.message.contains("服务器暂时无法受理") == false)
    #expect(prompt?.actions.map(\.isEnabled) == [false, true, true])
    #expect(both.mayRetry && !both.canRetryNow)
}

@Test func singleCandidatePromptOffersMarkAndRetry() throws {
    let candidate = try row()
    let topup = BalanceReconcilePresentation.prompt(for: .candidate(candidate), op: balance(.add, "50"), context: sameAdmin,
                                                    now: Date(timeIntervalSince1970: 1_800_000_000), timeZone: shanghai)
    #expect(topup?.title == "找到 1 条可能是这笔的记录")
    #expect(topup?.message == "今天 09:41 · +$50.00 · 余额 $12.40 → $62.40 · 备注：补偿")
    #expect(titles(topup) == ["是这笔，标为已入账", "不是，用同一编号重试", "取消"])
    let refundRow = try row(delta: "-12.50000000", before: "25.00000000", after: "12.50000000", notes: " ")
    let refund = BalanceReconcilePresentation.prompt(for: .candidate(refundRow), op: balance(.subtract, "12.5"), context: sameAdmin, now: now,
                                                     timeZone: shanghai)
    #expect(refund?.message.contains("\u{2212}$12.50 · 余额 $25.00 → $12.50") == true)
    #expect(refund?.message.contains("备注") == false)
    #expect(titles(refund).first == "是这笔，标为已扣除")
}

@Test func candidateForOtherAdministratorOffersAbandonInsteadOfRetry() throws {
    let prompt = BalanceReconcilePresentation.prompt(for: .candidate(try row()), op: balance(.add, "50"),
                                                     context: BalanceRetryContext(permission: .otherActor, actorLabel: "bob@example.com"),
                                                     now: now, timeZone: shanghai)
    #expect(titles(prompt) == ["是这笔，标为已入账", "放弃这笔", "取消"])
    #expect(prompt?.message.hasSuffix("\n这笔由 bob@example.com 发起，只能由同一管理员重试；可以放弃后重新充值。") == true)
}

@Test func ambiguousPromptPointsToWeb() throws {
    let rows = [try row(), try row(notes: "其他")]
    let prompt = BalanceReconcilePresentation.prompt(for: .ambiguous(rows), op: balance(.add, "50"), context: sameAdmin, now: now, timeZone: shanghai)
    #expect(prompt?.title == "无法确定这笔是否入账")
    #expect(prompt?.message == "请在 Web 的“余额调整记录”里核对")
    #expect(titles(prompt) == ["用同一编号重试", "放弃这笔", "取消"])
    let other = BalanceReconcilePresentation.prompt(for: .ambiguous(rows), op: balance(.add, "50"), context: BalanceRetryContext(permission: .otherActor),
                                                    now: now, timeZone: shanghai)
    #expect(titles(other) == ["放弃这笔", "取消"])
}

@Test func inconclusiveNotFoundUsesTheAmbiguousDialog() {
    let op = balance(.add, "50")
    #expect(BalanceReconcilePresentation.prompt(for: .notFound, op: op, context: sameAdmin, now: now, timeZone: shanghai)
            == BalanceReconcilePresentation.prompt(for: .ambiguous([]), op: op, context: sameAdmin, now: now, timeZone: shanghai))
}

@Test func executedAndStillRunningHaveNoPrompt() throws {
    let op = balance(.add, "50")
    #expect(BalanceReconcilePresentation.prompt(for: .executed(try row()), op: op, context: sameAdmin, now: now, timeZone: shanghai) == nil)
    #expect(BalanceReconcilePresentation.prompt(for: .stillRunning, op: op, context: sameAdmin, now: now, timeZone: shanghai) == nil)
    #expect(BalanceReconcilePresentation.stillRunningText == "服务器可能还在执行，请稍后再核对")
    #expect(BalanceReconcilePresentation.failedText == "核对失败，请稍后再试")
}

@Test func writtenReceiptCoversEveryOperation() {
    #expect(BalanceReconcilePresentation.writtenReceipt(for: balance(.add, "50"), replayed: false) == "已向 Alice 充值 $50.00")
    #expect(BalanceReconcilePresentation.writtenReceipt(for: balance(.subtract, "12.5"), replayed: false) == "已向 Alice 退款 $12.50")
    #expect(BalanceReconcilePresentation.writtenReceipt(for: balance(.set, "0"), replayed: false) == "已向 Alice 退款全部余额")
    #expect(BalanceReconcilePresentation.writtenReceipt(for: balance(.set, "30"), replayed: false) == "已将 Alice 的余额设置为 $30.00")
    #expect(BalanceReconcilePresentation.writtenReceipt(for: balance(.add, "50"), replayed: true) == "这笔此前已入账，没有重复执行")
    #expect(BalanceReconcilePresentation.writtenReceipt(for: balance(.add, "50", name: " "), replayed: false) == "已向 alice@example.com 充值 $50.00")
}

@Test func abandonAndReconfirmPromptCopy() {
    let abandon = BalanceReconcilePresentation.abandonPrompt
    #expect(abandon.title == "放弃这笔？")
    #expect(abandon.message == "放弃后这笔不会再重试；如果服务器其实已经执行，余额以服务器为准。")
    #expect(titles(abandon) == ["放弃这笔", "取消"])
    #expect(abandon.actions.map(\.isDestructive) == [true, false])
    let again = BalanceReconcilePresentation.reconfirmPrompt(notice: "二次验证已通过，请重新确认后发送")
    #expect(again.message == "二次验证已通过，请重新确认后发送")
    #expect(again.actions.map(\.kind) == [.retry, .cancel])
    #expect(titles(again) == ["用同一编号重试", "取消"])
}
