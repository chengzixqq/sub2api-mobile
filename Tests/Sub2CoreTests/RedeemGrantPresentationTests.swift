import Foundation
import Testing
@testable import Sub2Core

// S6-09: the compensation sheet's own words (60 §19.1, §19.3–§19.5): steps, the value step, the block before a new grant, the
// pending pages, their receipt and buttons. Every text is compared word for word with the spec.

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let siteID = UUID(uuidString: "6D000000-0000-4000-8000-000000000001")!
private let grantID = UUID(uuidString: "6D000000-0000-4000-8000-0000000000AA")!
private let otherID = UUID(uuidString: "6D000000-0000-4000-8000-0000000000BB")!
/// 2027-01-15 16:00 in Shanghai.
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let code = "a3f01b2c3d4e5f60718293a4b5c6d4e8"

private func grant(_ type: CompensationType = .balance, value: Decimal = 10, createdAt: Date = now.addingTimeInterval(-300), id: UUID = grantID,
                   userID: Int = 3, groupID: Int? = nil, days: Int? = nil) -> PendingCompensation {
    PendingCompensation(id: id, serverID: siteID, actorUserID: 1, createdAt: createdAt, userID: userID, userDisplayName: "王小明",
                        userEmail: "wang@example.com", code: code, type: type, value: value, groupID: groupID, validityDays: days)
}
private func context(_ permission: PendingRetryPermission = .allowed, readOnly: Bool = false, heldUntil: Date? = nil,
                     actor: String? = nil) -> RedeemRetryContext {
    RedeemRetryContext(permission: permission, isReadOnly: readOnly, retryNotBefore: heldUntil, isLegacyServer: false, isPastIdempotencyExpiry: false,
                       actorLabel: actor)
}

// MARK: Steps and the value step

@Test func stepsBalancePreviewAndConcurrencyFootnote() {
    #expect(GrantStep.barTitles == ["类型", "数值", "备注"])
    #expect(GrantStep.type.title(for: nil) == "发放兑换码")
    #expect(GrantStep.value.title(for: .balance) == "余额补偿")
    #expect(GrantStep.value.title(for: .concurrency) == "并发补偿")
    #expect(GrantStep.value.title(for: .subscription) == "订阅补偿")
    #expect(GrantStep.note.title(for: .balance) == "备注与确认")
    #expect(GrantStep.type.leadingTitle == "取消" && GrantStep.value.leadingTitle == "上一步" && GrantStep.note.leadingTitle == "上一步")
    #expect(GrantStep.type.previous == nil && GrantStep.note.previous == .value)
    #expect(GrantStep.value.spokenPosition == "第 2 步，共 3 步")

    let empty = BalanceGrantPreview(text: "", balance: Decimal(string: "12.40")!)
    #expect(empty.amountText == "$0" && empty.isPlaceholder && empty.line == "输入金额" && !empty.canAdvance)
    let ten = BalanceGrantPreview(text: "10", balance: Decimal(string: "12.40")!)
    #expect(ten.amountText == "$10" && !ten.isPlaceholder && ten.after == "$22.40" && ten.line == "发放后余额 $22.40" && ten.canAdvance)
    #expect(ten.amount == 10)
    let zero = BalanceGrantPreview(text: "0", balance: 5)
    #expect(!zero.isPlaceholder && !zero.canAdvance)
    #expect(BalanceGrantPreview.maxDigits == 7 && BalanceGrantPreview.maxFractionDigits == 2)

    #expect(RedeemGrantPresentation.concurrencyFootnote(change: "并发上限 5 → 7") == "提高这个用户的并发上限。发放后：并发上限 5 → 7。")
}

@Test func subscriptionDaysAreOneToThreeThousandSixHundredFifty() {
    #expect(RedeemSubscriptionDaysChoice.days(30).grantDays(customText: "") == 30)
    #expect(RedeemSubscriptionDaysChoice.custom.grantDays(customText: "1") == 1)
    #expect(RedeemSubscriptionDaysChoice.custom.grantDays(customText: "3650") == 3_650)
    for bad in ["", "0", "3651", "abc"] { #expect(RedeemSubscriptionDaysChoice.custom.grantDays(customText: bad) == nil, "\(bad)") }
}

@Test func copyOfTheSteps() {
    #expect(RedeemGrantPresentation.typeFootnote
            == "发放会生成一个兑换码并立即替这个用户兑换，记录出现在用户的“充值与调整记录”和兑换码列表里。邀请码只能在注册时使用，不能发放。")
    #expect(RedeemGrantPresentation.notesPlaceholder == "例如：故障补偿 · 工单 #8812")
    #expect(RedeemGrantPresentation.notesFootnote == "可选。写进兑换码的备注，也显示在用户的“充值与调整记录”里。")
    #expect(RedeemGrantPresentation.groupsFootnote == "只列出订阅类型的分组。")
    #expect(RedeemGrantPresentation.sendingTitle == "正在发放…")
    #expect(RedeemGrantPresentation.faceIDDetail == "验证后发放")
}

// MARK: 19.1 the block before a new grant

@Test func blockPromptNamesTheEarliestRecordWordForWord() {
    let earlier = grant(createdAt: now.addingTimeInterval(-300))
    let later = grant(.concurrency, value: 2, createdAt: now.addingTimeInterval(-60), id: otherID)
    let decision = GrantEntryDecision.decide(gate: .blocked([otherID, grantID]), compensations: [later, earlier], groupNames: [:], now: now,
                                             timeZone: shanghai.timeZone)
    #expect(decision == .blocked(GrantBlockPrompt(recordID: grantID, message: "向 王小明 发放 $10.00 余额 · 5 分钟前发起。\n先核对，避免重复发放。")))
    #expect(GrantBlockPrompt.title == "上一次补偿的发放结果未确认" && GrantBlockPrompt.checkTitle == "先核对" && GrantBlockPrompt.cancelTitle == "取消")

    // Over an hour: the clock time, a space before 发起; a subscription by its group's name.
    let old = grant(.subscription, value: 30, createdAt: now.addingTimeInterval(-7_200), groupID: 4, days: 30)
    let named = GrantEntryDecision.decide(gate: .blocked([grantID]), compensations: [old], groupNames: [4: "企业专线"], now: now, timeZone: shanghai.timeZone)
    #expect(named == .blocked(GrantBlockPrompt(recordID: grantID, message: "向 王小明 发放 企业专线 30 天订阅 · 今天 14:00 发起。\n先核对，避免重复发放。")))

    #expect(GrantEntryDecision.decide(gate: .clear, compensations: [earlier], groupNames: [:], now: now, timeZone: shanghai.timeZone) == .open)
    #expect(GrantEntryDecision.decide(gate: .paused(.compensation), compensations: [], groupNames: [:], now: now, timeZone: shanghai.timeZone)
            == .paused(message: PendingMoneyKind.compensation.unreadableMessage))
    // A gate naming records this list does not hold opens the sheet, which checks again before sending.
    #expect(GrantEntryDecision.decide(gate: .blocked([otherID]), compensations: [earlier], groupNames: [:], now: now, timeZone: shanghai.timeZone) == .open)
}

// MARK: 19.3 the pending pages

@Test func pendingPagesForEveryState() {
    typealias P = CompensationPendingPresentation
    let awaiting = P.header(for: .awaitingCheck, userName: "王小明")
    #expect(awaiting == .init(systemImage: "hourglass", title: "请求可能已提交", message: "没有收到服务器确认。不要重新发放，先核对。", tone: .caution))
    #expect(P.footnote(for: .awaitingCheck) == "编号和兑换码已保存在本机。用同一编号重试时，服务器发放过就直接返回那一次，不会重复发放。")
    let notFound = P.header(for: .notFound, userName: "王小明")
    #expect(notFound.systemImage == "magnifyingglass" && notFound.title == "服务器上没有这次发放" && notFound.message == "这次发放没有生效。用同一编号重试，或者放弃。")
    let unused = P.header(for: .createdNotRedeemed, userName: "王小明")
    #expect(unused.title == "兑换码已创建，还没兑换给 王小明" && unused.message == "上一次执行中途停了。用同一编号重试会把这个码兑换给他。")
    #expect(P.footnote(for: .createdNotRedeemed) == "放弃后这个码留在兑换码列表里，未使用，可以删除。")
    #expect(P.header(for: .unverifiable, userName: "王小明").title == "无法确认这次发放")
    #expect(P.header(for: .regrant("原因"), userName: "王小明").title == "这次没有发给 王小明")
    #expect(P.header(for: .ended("用户不存在或已删除"), userName: "王小明").message == "用户不存在或已删除")
    #expect(P.header(for: .settled, userName: "王小明").title == "这笔已核对或已放弃")
    #expect(P.abandonPromptTitle == "放弃这次发放？" && P.abandonPromptMessage == "放弃后这笔不会再重试；如果服务器其实已经发放，以服务器为准。")
    #expect(P.abandonReceipt == "已放弃 · 不再提醒")

    #expect(CompensationPendingState(.notFound) == .notFound)
    #expect(CompensationPendingState(.createdNotRedeemed(AdminRedeemCode(id: 1, code: code, type: "balance", value: 10, status: "unused"))) == .createdNotRedeemed)
    #expect(CompensationPendingState(.issued(AdminRedeemCode(id: 1, code: code, type: "balance", value: 10, status: "used", usedBy: 3))) == nil)
    #expect(CompensationPendingState(.redeemedByOther(AdminRedeemCode(id: 1, code: code, type: "balance", value: 10, status: "used", usedBy: 9)))
            == .regrant(P.otherUserMessage))
}

@Test func pendingButtonsFollowTheSenderAndTheRequestInFlight() {
    typealias P = CompensationPendingPresentation
    func kinds(_ actions: [CompensationPendingAction]) -> [String] { actions.map { "\($0.kind.rawValue)\($0.isPrimary ? "*" : "")\($0.isEnabled ? "" : "-")" } }
    #expect(kinds(P.actions(for: .awaitingCheck, retry: context(), busy: nil, now: now)) == ["check*", "retry"])
    #expect(P.actions(for: .awaitingCheck, retry: context(), busy: nil, now: now).map(\.title) == ["核对发放结果", "用同一编号重试"])
    #expect(kinds(P.actions(for: .notFound, retry: context(), busy: nil, now: now)) == ["retry*", "abandon"])
    #expect(P.actions(for: .notFound, retry: context(), busy: nil, now: now).map(\.title) == ["用同一编号重试", "放弃这次发放"])
    #expect(kinds(P.actions(for: .createdNotRedeemed, retry: context(), busy: nil, now: now)) == ["retry*", "abandon"])
    // Another administrator's record: only checked or given up; read-only and the cooldown grey the retry.
    #expect(kinds(P.actions(for: .awaitingCheck, retry: context(.otherActor), busy: nil, now: now)) == ["check*", "abandon"])
    #expect(kinds(P.actions(for: .notFound, retry: context(.otherActor), busy: nil, now: now)) == ["abandon*"])
    #expect(kinds(P.actions(for: .awaitingCheck, retry: context(readOnly: true), busy: nil, now: now)) == ["check*", "retry-"])
    #expect(kinds(P.actions(for: .notFound, retry: context(heldUntil: now.addingTimeInterval(5)), busy: nil, now: now)) == ["retry*-", "abandon"])
    #expect(kinds(P.actions(for: .unverifiable, retry: context(), busy: nil, now: now)) == ["markChecked*"])
    #expect(kinds(P.actions(for: .regrant("x"), retry: context(), busy: nil, now: now)) == ["regrant*"])
    #expect(P.actions(for: .ended("x"), retry: context(), busy: nil, now: now).isEmpty && P.actions(for: .settled, retry: context(), busy: nil, now: now).isEmpty)
    // One request at a time: both wait, the running one says so.
    let checking = P.actions(for: .awaitingCheck, retry: context(), busy: .checking, now: now)
    #expect(checking.map(\.title) == ["正在核对…", "用同一编号重试"] && checking.allSatisfy { !$0.isEnabled })
    #expect(P.actions(for: .notFound, retry: context(), busy: .retrying, now: now).first?.title == "正在用同一编号重试…")

    #expect(P.notes(for: .awaitingCheck, retry: context(.otherActor, actor: "bob@example.com"), now: now)
            == ["这笔补偿由 bob@example.com 发起，只能由同一管理员重试；可以放弃后重新发放。"])
    #expect(P.notes(for: .notFound, retry: context(.otherActor), now: now) == ["这笔补偿由其他管理员发起，只能由同一管理员重试；可以放弃后重新发放。"])
    #expect(P.notes(for: .awaitingCheck, retry: context(readOnly: true), now: now) == ["当前登录的是只读令牌，不能修改"])
    #expect(P.notes(for: .awaitingCheck, retry: context(.allowedActorUnknown), now: now) == ["无法确认发起人"])
    #expect(P.notes(for: .unverifiable, retry: context(.otherActor), now: now).isEmpty)
}

@Test func pendingReceiptShowsOnlyTheShortCodeAndTheFullNumber() {
    let lines = CompensationPendingPresentation.receipt(grant(), siteName: "主站", groupName: nil, origin: .currentSite, timeZone: shanghai, now: now)
    #expect(lines.map(\.label) == ["对象", "站点", "内容", "发起", "兑换码", "编号"])
    #expect(lines.map(\.value) == ["王小明 · wang@example.com", "主站", "$10.00 余额", "01/15 15:55", "a3f0····d4e8", grantID.uuidString.lowercased()])
    #expect(lines.last?.isKey == true && lines.allSatisfy { $0.note == nil })
    #expect(!lines.contains { $0.value.contains(code) })
    let old = CompensationPendingPresentation.receipt(grant(.concurrency, value: 2), siteName: "主站", groupName: nil, origin: .sameAddressOldLogin,
                                                      timeZone: shanghai, now: now)
    #expect(old[1].note == "本站点的旧登录下发起" && old[2].value == "+2 并发")
}
