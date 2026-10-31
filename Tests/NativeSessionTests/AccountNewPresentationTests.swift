import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

private typealias Dock = AccountNewDockContent

@Test func dockRowsFollowStageTable() {
    let warning = MixedChannelWarning(groupID: 1, groupName: "高级组", currentPlatform: "Anthropic", otherPlatform: "Antigravity")
    let rows: [(AccountNewSubmission.Stage, Bool, Dock)] = [
        (.idle, true, Dock(title: "可以创建了", detail: "创建后立即停止调度，测试通过再启用", primary: .create(enabled: true))),
        (.confirmingMixedChannel(warning), true, Dock(title: "可以创建了", detail: "创建后立即停止调度，测试通过再启用", primary: .create(enabled: false))),
        (.checkingMixedChannel, true, Dock(title: "正在创建账号…", showsProgress: true, primary: .create(enabled: false))),
        (.creating(confirming: false), true, Dock(title: "正在创建账号…", showsProgress: true, primary: .create(enabled: false))),
        (.creating(confirming: true), true, Dock(title: "正在确认结果…", showsProgress: true, primary: .create(enabled: false))),
        (.pausing(accountID: 13), true, Dock(title: "账号已创建，正在停止调度…", showsProgress: true, primary: .create(enabled: false))),
        (.reconciling, true, Dock(title: "正在核对创建结果…", showsProgress: true, primary: .create(enabled: false))),
        (.rejected(reason: "请求参数错误"), true, Dock(title: "创建没有成功", detail: "请求参数错误", tone: .critical, primary: .create(enabled: true))),
        (.reconfirm(notice: "合规确认已完成，请重新确认后发送"), true, Dock(title: "合规确认已完成，请重新确认后发送", tone: .caution, primary: .create(enabled: true))),
        (.unconfirmed(reason: KeyedWriteFailure.unconfirmedMessage), true,
         Dock(title: "结果未确认", detail: KeyedWriteFailure.unconfirmedMessage, tone: .caution, primary: .retrySameKey, secondary: .reconcile)),
        (.unconfirmed(reason: KeyedWriteFailure.unconfirmedMessage), false,
         Dock(title: "结果未确认", detail: KeyedWriteFailure.unconfirmedMessage, tone: .caution, primary: .reconcile)),
        (.notCreated, true, Dock(title: "没有创建成功", tone: .caution, primary: .retrySameKey)),
        (.notCreated, false, Dock(title: "没有创建成功", tone: .caution, primary: .resend)),
        (.pauseUnconfirmed(accountID: 13, reason: "x"), true, Dock(title: "停止调度没有确认", detail: "账号 #13 可能在接收请求", tone: .critical, primary: .retryPause)),
        (.created(accountID: 13), true, Dock(title: "账号 #13 已创建 · 暂停调度"))
    ]
    for (stage, keyed, expected) in rows {
        #expect(Dock.make(stage: stage, missing: [], keyed: keyed) == expected, "\(stage)")
    }
    let titles: [Dock.Action] = [.create(enabled: true), .retrySameKey, .resend, .reconcile, .retryPause]
    #expect(titles.map(\.title) == ["创建并测试", "用同一编号重试", "重试", "核对", "重试停止调度"])
    #expect(!Dock.Action.create(enabled: false).isEnabled && Dock.Action.reconcile.isEnabled)
}

@Test func missingDockNamesItemsAndJumpLabel() {
    let missing = Dock.make(stage: .idle, missing: ["平台", "凭据", "名称"], keyed: true)
    #expect(missing.title == "还差" && missing.detail == "平台、凭据、名称" && missing.jumpsToFirstMissing && missing.primary == .create(enabled: false))
    #expect(missing.accessibilityLabel == "还差平台、凭据、名称，跳到平台")
    #expect(Dock.make(stage: .rejected(reason: "x"), missing: ["名称"], keyed: false).detail == "名称")
    let ready = Dock.make(stage: .idle, missing: [], keyed: true)
    #expect(ready.title == "可以创建了" && ready.detail == "创建后立即停止调度，测试通过再启用" && !ready.jumpsToFirstMissing)
    #expect(ready.accessibilityLabel == "可以创建了，创建后立即停止调度，测试通过再启用")
}

@Test func subtitleCountsSameMissingList() {
    #expect(AccountNewFlow.subtitle(site: "主站", missingCount: 3, createdID: nil, status: .paused) == "主站 · 还差 3 项")
    #expect(AccountNewFlow.subtitle(site: "主站", missingCount: 0, createdID: nil, status: .paused) == "主站 · 必填已填齐")
    #expect(AccountNewFlow.subtitle(site: "主站", missingCount: 0, createdID: 13, status: .unconfirmed) == "主站 · #13 已创建 · 调度状态待核对")
}

@Test func groupsTrailingAndFootnotes() {
    #expect(AccountNewCopy.groupsTrailing(selected: 0, risky: 0) == "可不选")
    #expect(AccountNewCopy.groupsTrailing(selected: 2, risky: 0) == "已选 2")
    #expect(AccountNewCopy.groupsTrailing(selected: 2, risky: 1) == "已选 2 · 1 个需确认")
    #expect(AccountNewCopy.riskFootnote(group: "高级组", otherPlatform: "Anthropic") == "「高级组」里已有 Anthropic 账号，创建时要确认混合渠道风险。")
    #expect(AccountNewCopy.noGroups(platformName: "Grok") == "没有可选的 Grok 分组，不分组也能创建。")
    #expect(AccountNewCopy.defaultGroupFootnote(platformID: "anthropic") == "不选分组时，如果站点有「anthropic-default」分组会自动加入")
    #expect(AccountNewCopy.moreSummary(expiry: nil) == "不过期" && AccountNewCopy.moreSummary(expiry: "2026-11-24 09:41") == "2026-11-24 09:41 到期")
    #expect(AccountNewCopy.moreLabel(isAntigravity: true) == "过期时间、负载因子、AI Credits" && AccountNewCopy.moreLabel(isAntigravity: false) == "过期时间、负载因子")
    #expect(AccountNewCopy.credentialsPlaceholder(platformPicked: false, isAccountMode: false) == "先选平台和认证方式")
    #expect(AccountNewCopy.credentialsPlaceholder(platformPicked: true, isAccountMode: true) == "选好账号类型后，在这里填写凭据")
}

@Test func pauseUnconfirmedCopy() {
    #expect(AccountNewCopy.pauseUnconfirmedTitle(name: "Claude-04") == "账号「Claude-04」可能还在参与调度")
    #expect(AccountNewCopy.pauseUnconfirmedMessage(id: 13) == "停止调度没有确认，账号 #13 可能正在用未验证的凭据接收请求。")
    #expect(AccountNewCopy.pauseBannerTitle == "停止调度没有确认 · 结果待核对" && AccountNewCopy.pauseBannerDetail(id: 13) == "账号 #13 可能正在参与调度。")
}

@Test func receiptsCopy() {
    let created = AccountNewCopy.createdReceipt(name: "Claude-04")
    #expect(created.text == "已创建「Claude-04」· 暂停调度" && created.systemImage == "pause.circle" && created.tone == .neutral)
    #expect(AccountNewCopy.groupsRemovedReceipt(count: 2) == "已移除 2 个不再适用的分组")
    #expect(AccountNewCopy.leftUnconfirmedReceipt(name: "Claude-04") == "「Claude-04」停止调度没有确认 · 结果待核对")
    #expect(AccountNewCopy.leftCreateUnconfirmedReceipt(name: "Claude-04") == "「Claude-04」创建结果未确认 · 请到账号列表核对")
}

@Test func createUnconfirmedQuestionCopy() {
    #expect(AccountNewCopy.createUnconfirmedTitle(name: "Claude-04") == "账号「Claude-04」可能已经创建")
    #expect(AccountNewCopy.createUnconfirmedMessage == "创建结果没有确认。关闭后不能再用同一编号重试，再新建前请先到账号列表核对，避免重复创建。")
}

@Test func authorizedWithAndWithoutEmail() {
    #expect(AccountNewCopy.authorized(email: "ops@example.com") == "已授权 · ops@example.com")
    #expect(AccountNewCopy.authorized(email: nil) == "已授权" && AccountNewCopy.authorized(email: "  ") == "已授权")
}

// MARK: - S2-20 after a failed test

@Test func afterTestDockOffersSaveOrRetest() {
    let changed = Dock.afterTest(accountID: 13, status: .paused, hasChanges: true, missing: [])
    #expect(changed == Dock(title: "保存到账号 #13", detail: "测试通过才启用调度", primary: .saveAndRetest(enabled: true)))
    let same = Dock.afterTest(accountID: 13, status: .paused, hasChanges: false, missing: [])
    #expect(same == Dock(title: "账号 #13 · 暂停调度", detail: "没有改动，用原设置再测一次", primary: .retest(enabled: true)))
    #expect(Dock.afterTest(accountID: 13, status: .error, hasChanges: false, missing: []).title == "账号 #13 · 错误（已停止调度）")
    let missing = Dock.afterTest(accountID: 13, status: .paused, hasChanges: true, missing: ["API Key"])
    #expect(missing.title == "还差" && missing.detail == "API Key" && missing.jumpsToFirstMissing && missing.primary == .saveAndRetest(enabled: false))
    #expect(missing.accessibilityLabel == "还差API Key，跳到API Key")
    let titles: [Dock.Action] = [.saveAndRetest(enabled: true), .retest(enabled: true)]
    #expect(titles.map(\.title) == ["保存并重新测试", "重新测试"])
    #expect(!Dock.Action.saveAndRetest(enabled: false).isEnabled && Dock.Action.retest(enabled: true).isEnabled)
}

@Test func testSheetPauseRowFollowsTheStage() {
    #expect(AccountNewSubmission.Stage.pausing(accountID: 13).testSheetPause == .running)
    #expect(AccountNewSubmission.Stage.pauseUnconfirmed(accountID: 13, reason: "x").testSheetPause == .unconfirmed)
    #expect(AccountNewSubmission.Stage.created(accountID: 13).testSheetPause == .done)
    #expect(AccountNewSubmission.Stage.created(accountID: 13).opensTestSheet && AccountNewSubmission.Stage.pausing(accountID: 13).opensTestSheet)
    #expect(!AccountNewSubmission.Stage.creating(confirming: false).opensTestSheet && !AccountNewSubmission.Stage.notCreated.opensTestSheet)
}
