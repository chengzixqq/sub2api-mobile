import Foundation
import Testing
@testable import Sub2Core

// S6-07: the generate wizard's steps and inputs (60 §10.1, §10.3) and the + interception (60 §8.4, R03, X34).

private let utc = TimeZone(identifier: "UTC")!
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func group(_ id: Int, _ name: String) -> AdminGroup {
    AdminGroup(id: id, name: name, subscriptionType: "subscription", sortOrder: id)
}
private let subscriptions = [group(4, "企业专线"), group(9, "团队专线")]

private func pressing(_ wizard: RedeemGenerateWizard, _ keys: String) -> RedeemGenerateWizard {
    keys.reduce(wizard) { $0.editingValueText(KeypadInput.apply(KeypadKey($1)!, to: $0.valueText, maxDigits: RedeemGenerateWizard.valueMaxDigits,
                                                                    maxFractionDigits: RedeemGenerateWizard.valueMaxFractionDigits)) }
}
private func batch(_ id: String, minutesAgo: Double, spec: RedeemGenerateSpec, serverID: UUID = UUID()) -> PendingRedeemBatch {
    PendingRedeemBatch(id: UUID(uuidString: id)!, serverID: serverID, actorUserID: 1, createdAt: now.addingTimeInterval(-minutesAgo * 60), spec: spec)
}

@Test func stepsAndLeadingButton() {
    let start = RedeemGenerateWizard()
    #expect(start.step == .type)
    #expect(start.step.leadingTitle == "取消")
    #expect(RedeemGenerateStep.barTitles == ["类型", "面额与数量", "有效期"])
    #expect(RedeemGenerateStep.value.spokenPosition == "第 2 步，共 3 步")
    let second = start.choosing(.concurrency)
    #expect(second.step == .value && second.type == .concurrency)
    #expect(second.step.leadingTitle == "上一步" && second.step.navigationTitle == "面额与数量")
    let third = second.advancing(subscriptionGroups: [])
    #expect(third.step == .expiry && third.step.navigationTitle == "有效期与确认")
    // Back keeps what was filled in; the first step goes nowhere.
    let back = third.settingConcurrency(3).goingBack().goingBack()
    #expect(back.step == .type && back.type == .concurrency && back.concurrency == 3)
    #expect(back.goingBack() == back)
}

@Test func balanceKeypadHasNoDefaultAndSixDigits() {
    let balance = RedeemGenerateWizard().choosing(.balance)
    #expect(balance.amountDisplay == "$0" && balance.isAmountEmpty)
    #expect(balance.amount == nil && balance.total == nil)
    #expect(!balance.canAdvance(subscriptionGroups: []))
    #expect(balance.previewTotal == "$0.00")
    let ten = pressing(balance, "10")
    #expect(ten.amountDisplay == "$10" && !ten.isAmountEmpty && ten.amount == 10)
    #expect(ten.canAdvance(subscriptionGroups: []))
    #expect(pressing(balance, "1234567").valueText == "123456")
    #expect(pressing(balance, "12.345").valueText == "12.34")
    #expect(pressing(balance, ".").valueText == "")
    #expect(pressing(balance, "05").valueText == "5")
    // A text the keypad could not have typed is refused.
    #expect(ten.editingValueText("1x").valueText == "10")
    #expect(ten.editingValueText("1").valueText == "1")
    let twenty = ten.settingCount(20)
    #expect(twenty.total == 200 && twenty.previewTotal == "$200.00")
    // “0” and “0.” are not a face value.
    #expect(!pressing(balance, "0").canAdvance(subscriptionGroups: []))
}

@Test func concurrencyStepperClampsAndDescribes() throws {
    let concurrency = RedeemGenerateWizard().choosing(.concurrency)
    #expect(concurrency.concurrency == 1)
    #expect(concurrency.settingConcurrency(0).concurrency == 1 && concurrency.settingConcurrency(51).concurrency == 50)
    let two = concurrency.settingConcurrency(2)
    #expect(two.concurrencyLine == "增加并发 +2")
    #expect(two.total == nil && two.canAdvance(subscriptionGroups: []))
    #expect(try two.form(subscriptionGroups: []).validated() == RedeemGenerateSpec(type: .concurrency, value: 2, count: 1))
}

@Test func subscriptionGroupsAndDays() throws {
    let subscription = RedeemGenerateWizard().choosing(.subscription)
    #expect(subscription.subscriptionDays == .days(30))
    #expect(RedeemSubscriptionDaysChoice.options.map(\.title) == ["7 天", "30 天", "90 天", "自定义"])
    #expect(RedeemSubscriptionDaysChoice.options.map(\.identifier) == ["7", "30", "90", "custom"])
    #expect(!subscription.canAdvance(subscriptionGroups: []))
    #expect(subscription.selectedGroup(in: subscriptions)?.id == 4)
    #expect(subscription.canAdvance(subscriptionGroups: subscriptions))
    let picked = subscription.selectingGroup(id: 9)
    #expect(picked.selectedGroup(in: subscriptions)?.id == 9)
    // A group gone from the options falls back to the first.
    #expect(picked.selectedGroup(in: [subscriptions[0]])?.id == 4)
    #expect(try picked.form(subscriptionGroups: subscriptions).validated()
            == RedeemGenerateSpec(type: .subscription, value: 0, count: 1, groupID: 9, groupName: "团队专线", validityDays: 30))
    let custom = picked.choosingSubscriptionDays(.custom)
    #expect(!custom.canAdvance(subscriptionGroups: subscriptions))
    #expect(!custom.editingCustomSubscriptionDays("0").canAdvance(subscriptionGroups: subscriptions))
    #expect(!custom.editingCustomSubscriptionDays("3651").canAdvance(subscriptionGroups: subscriptions))
    #expect(custom.editingCustomSubscriptionDays("365").canAdvance(subscriptionGroups: subscriptions))
    #expect(custom.editingCustomSubscriptionDays("12a34567").customSubscriptionDaysText == "1234")
    #expect(custom.editingCustomSubscriptionDays("１２").customSubscriptionDaysText == "")
}

@Test func invitationOnlyNeedsCount() throws {
    let invitation = RedeemGenerateWizard().choosing(.invitation).settingCount(10)
    #expect(invitation.canAdvance(subscriptionGroups: []))
    #expect(invitation.total == nil)
    #expect(try invitation.form(subscriptionGroups: []).validated() == RedeemGenerateSpec(type: .invitation, value: 0, count: 10))
}

@Test func countStepperAndPicks() {
    let wizard = RedeemGenerateWizard()
    #expect(wizard.count == 1)
    #expect(RedeemGenerateWizard.countPicks == [1, 10, 20, 50, 100])
    #expect(wizard.settingCount(0).count == 1 && wizard.settingCount(101).count == 100)
}

@Test func expiryChoicesAndCustomDays() {
    let wizard = pressing(RedeemGenerateWizard().choosing(.balance), "10").advancing(subscriptionGroups: [])
    #expect(wizard.expiry == .never && wizard.expiresInDays == nil && wizard.canSubmit(subscriptionGroups: []))
    #expect(RedeemGenerateExpiryChoice.options.map(\.title) == ["永不过期", "1 天", "3 天", "7 天", "自定义"])
    #expect(RedeemGenerateExpiryChoice.options.map(\.identifier) == ["never", "1", "3", "7", "custom"])
    #expect(wizard.choosingExpiry(.days(7)).expiresInDays == 7)
    let custom = wizard.choosingExpiry(.custom)
    #expect(!custom.isExpiryValid && !custom.canSubmit(subscriptionGroups: []) && custom.spec(subscriptionGroups: []) == nil)
    #expect(!custom.editingCustomExpiryDays("0").canSubmit(subscriptionGroups: []))
    #expect(!custom.editingCustomExpiryDays("3651").canSubmit(subscriptionGroups: []))
    #expect(custom.editingCustomExpiryDays("3650").canSubmit(subscriptionGroups: []))
    #expect(custom.editingCustomExpiryDays("3650").expiresInDays == 3650)
    #expect(custom.editingCustomExpiryDays("９").customExpiryDaysText == "")
}

@Test func notesAreOptionalAndCappedAt1000() {
    let wizard = pressing(RedeemGenerateWizard().choosing(.balance), "10")
    #expect(RedeemGenerateWizard.notesPlaceholder == "活动批次、工单号（选填）")
    #expect(wizard.canSubmit(subscriptionGroups: []))
    let long = wizard.editingNotes(String(repeating: "批", count: 1_001))
    #expect(long.notes.unicodeScalars.count == 1_000)
    // The server counts runes: a flag is two.
    let flags = wizard.editingNotes(String(repeating: "🇨🇳", count: 501))
    #expect(flags.notes.unicodeScalars.count == 1_000)
    #expect(flags.canSubmit(subscriptionGroups: []))
}

@Test func formCarriesEveryFieldToTheSpec() throws {
    let balance = pressing(RedeemGenerateWizard().choosing(.balance), "10").settingCount(20).advancing(subscriptionGroups: [])
        .choosingExpiry(.days(7)).editingNotes(" 活动批次 A ")
    #expect(balance.spec(subscriptionGroups: []) == RedeemGenerateSpec(type: .balance, value: 10, count: 20, expiresInDays: 7, notes: "活动批次 A"))
    // Fields of another type are not sent.
    let switched = balance.goingBack().goingBack().choosing(.invitation)
    #expect(switched.spec(subscriptionGroups: []) == RedeemGenerateSpec(type: .invitation, value: 0, count: 20, expiresInDays: 7, notes: "活动批次 A"))
    let empty = RedeemGenerateWizard().choosing(.balance)
    #expect(!empty.canSubmit(subscriptionGroups: []) && empty.spec(subscriptionGroups: []) == nil)
}

@Test func advancingNeedsAValidSecondStep() {
    let empty = RedeemGenerateWizard().choosing(.balance)
    #expect(empty.advancing(subscriptionGroups: []).step == .value)
    let subscription = RedeemGenerateWizard().choosing(.subscription)
    #expect(subscription.advancing(subscriptionGroups: []).step == .value)
    #expect(subscription.advancing(subscriptionGroups: subscriptions).step == .expiry)
}

// MARK: The + interception (60 §8.4)

@Test func entryDecisionOpensWhenClearAndPausesWhenUnreadable() {
    let only = batch("0A000000-0000-4000-8000-000000000002", minutesAgo: 5, spec: RedeemGenerateSpec(type: .balance, value: 10, count: 20))
    #expect(RedeemGenerateEntryDecision.decide(gate: .clear, batches: [only], now: now, timeZone: utc) == .open)
    #expect(RedeemGenerateEntryDecision.decide(gate: .paused(.redeemBatch), batches: [only], now: now, timeZone: utc)
            == .paused(message: "未决兑换码记录无法读取，已暂停新的兑换码生成。请保留应用数据并检查设备存储。"))
    // The gate's records were settled meanwhile.
    #expect(RedeemGenerateEntryDecision.decide(gate: .overridable([UUID()]), batches: [only], now: now, timeZone: utc) == .open)
}

@Test func interceptShowsTheEarliestBatch() {
    let money = batch("0A000000-0000-4000-8000-000000000002", minutesAgo: 5, spec: RedeemGenerateSpec(type: .balance, value: 10, count: 20))
    let older = batch("0A000000-0000-4000-8000-000000000009", minutesAgo: 10, spec: RedeemGenerateSpec(type: .concurrency, value: 2, count: 5))
    #expect(RedeemGenerateIntercept.title == "上一批兑换码的生成结果未确认")
    #expect([RedeemGenerateIntercept.reconcileTitle, RedeemGenerateIntercept.overrideTitle, RedeemGenerateIntercept.cancelTitle]
            == ["先核对", "仍要生成新的一批", "取消"])
    let one = RedeemGenerateEntryDecision.decide(gate: .overridable([money.id]), batches: [money, older], now: now, timeZone: utc)
    #expect(one == .intercept(RedeemGenerateIntercept(batchID: money.id, message: "20 个 × $10.00 · 合计 $200.00\n5 分钟前发起。先核对，避免重复生成。")))
    let both = RedeemGenerateEntryDecision.decide(gate: .overridable([money.id, older.id]), batches: [money, older], now: now, timeZone: utc)
    #expect(both == .intercept(RedeemGenerateIntercept(batchID: older.id, message: "5 个 × +2 并发\n10 分钟前发起。先核对，避免重复生成。")))
    // An older time ends in a digit: “今天 09:36 发起”.
    let morning = batch("0A000000-0000-4000-8000-000000000003", minutesAgo: 180, spec: RedeemGenerateSpec(type: .invitation, value: 0, count: 10))
    guard case .intercept(let earlier) = RedeemGenerateEntryDecision.decide(gate: .overridable([morning.id]), batches: [morning], now: now, timeZone: utc) else {
        Issue.record("not intercepted"); return
    }
    let time = DisplayFormat.relativeTime(morning.createdAt, now: now, timeZone: utc)
    #expect(earlier.message == "10 个 × 注册邀请\n\(time) 发起。先核对，避免重复生成。")
}

@Test func receiptListsTheBatchAndTheTotalOfBalanceCodesOnly() {
    let balance = RedeemGenerateSummary(spec: RedeemGenerateSpec(type: .balance, value: 10, count: 20), now: now, timeZone: utc)
    #expect(balance.receiptLines.map(\.label) == ["类型", "每个", "数量", "过期", "合计"])
    #expect(balance.receiptLines.map(\.value) == ["余额", "$10.00", "× 20", "永不过期", "$200.00"])
    let invitation = RedeemGenerateSummary(spec: RedeemGenerateSpec(type: .invitation, value: 0, count: 10, expiresInDays: 7), now: now, timeZone: utc)
    #expect(invitation.receiptLines.map(\.id) == ["type", "each", "count", "expiry"])
    #expect(invitation.receiptLines[3].value.hasPrefix("7 天后过期（"))
}
