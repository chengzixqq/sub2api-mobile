import Foundation
import Testing
@testable import Sub2Core

// S5-08: 50 §2.4 member row actions and §4 添加账号's words, order and dock.

/// The site clock of every case.
private let memberNow = Date(timeIntervalSince1970: 1_800_000_000)

private func memberAccount(_ id: Int, name: String = "账号", platform: String = "openai", type: String = "apikey", status: String = "active",
                           schedulable: Bool = true, groups: [Int] = [], rateLimitedFor seconds: TimeInterval? = nil,
                           expiredPause: Bool = false) -> UpstreamAccount {
    UpstreamAccount(id: id, name: name, platform: platform, type: type, status: status, schedulable: schedulable,
                    expiresAt: expiredPause ? Int64(memberNow.timeIntervalSince1970) - 60 : nil, groupIDs: groups,
                    rateLimitResetAt: seconds.map { ServerTime.utcTimestamp(memberNow.addingTimeInterval($0)) },
                    autoPauseOnExpired: expiredPause ? true : nil)
}
private func memberGroup(_ id: Int = 4, name: String = "企业专线", platform: String = "openai", status: String = "active", accounts: Int? = 1,
                         active: Int? = 0) -> AdminGroup {
    AdminGroup(id: id, name: name, platform: platform, status: status, accountCount: accounts, activeAccountCount: active)
}

@Test func memberStatusActionFollowsTheAccountState() {
    let overloaded = UpstreamAccount(id: 2, name: "账号", platform: "openai", type: "apikey",
                                     overloadUntil: ServerTime.utcTimestamp(memberNow.addingTimeInterval(60)))
    let temporary = UpstreamAccount(id: 3, name: "账号", platform: "openai", type: "apikey",
                                    tempUnschedulableUntil: ServerTime.utcTimestamp(memberNow.addingTimeInterval(60)))
    let cases: [(UpstreamAccount, GroupMemberStatusAction?)] = [
        (memberAccount(1, status: "error", schedulable: false), .recover), (overloaded, .recover), (temporary, .recover),
        (memberAccount(4, rateLimitedFor: 300), .recover), (memberAccount(5, schedulable: false, rateLimitedFor: 300), .recover),
        (memberAccount(6, schedulable: false), .enableScheduling), (memberAccount(7), .stopScheduling)
    ]
    for (account, expected) in cases {
        #expect(GroupMemberPresentation.statusAction(for: account, now: memberNow) == expected, "\(account.id)")
    }
    #expect(GroupMemberStatusAction.allCases.map(\.title) == ["恢复状态", "启用调度", "停止调度"])
    #expect(GroupMemberStatusAction.allCases.map(\.systemImage) == ["arrow.counterclockwise", "play.fill", "pause.fill"])
}

/// S2D1-20: 启用调度 does not wake an account its expiry paused; a disabled account has no status action, only 移出.
@Test func memberStatusActionSkipsExpiredPauseAndDisabledAccounts() {
    #expect(GroupMemberPresentation.statusAction(for: memberAccount(1, expiredPause: true), now: memberNow) == nil)
    #expect(GroupMemberPresentation.statusAction(for: memberAccount(2, schedulable: false, expiredPause: true), now: memberNow) == nil)
    #expect(GroupMemberPresentation.statusAction(for: memberAccount(3, status: "inactive"), now: memberNow) == nil)
}

@Test func removalConfirmsOnlyTheLastAvailableAccountOfAnActiveGroup() {
    let available = memberAccount(4)
    #expect(GroupMemberPresentation.removalNeedsConfirmation(available, in: memberGroup(active: 1), now: memberNow))
    #expect(!GroupMemberPresentation.removalNeedsConfirmation(available, in: memberGroup(active: 2), now: memberNow))
    #expect(!GroupMemberPresentation.removalNeedsConfirmation(available, in: memberGroup(status: "inactive", active: 1), now: memberNow))
    #expect(!GroupMemberPresentation.removalNeedsConfirmation(memberAccount(3, rateLimitedFor: 300), in: memberGroup(active: 1), now: memberNow))
    #expect(!GroupMemberPresentation.removalNeedsConfirmation(available, in: memberGroup(active: nil), now: memberNow))
    #expect(GroupMemberPresentation.isAvailable(available, now: memberNow))
    #expect(!GroupMemberPresentation.isAvailable(memberAccount(6, schedulable: false), now: memberNow))
}

@Test func removalConfirmationNamesAccountGroupAndSite() {
    let confirmation = GroupMemberPresentation.removalConfirmation(accountName: "OpenAI-主力-01", groupName: "标准组", siteName: "演示站")
    #expect(confirmation.title == "把「OpenAI-主力-01」移出「标准组」？")
    #expect(confirmation.message == "站点 演示站\n它是这个分组唯一可用的账号，移出后这个分组的新请求会失败。账号本身保留。")
    #expect(confirmation.confirmTitle == "仍然移出" && confirmation.isDestructive)
    #expect(GroupMemberPresentation.removeTitle == "移出")
}

@Test func pickerWordsFollowTheGroupPlatform() {
    #expect(GroupPickerPresentation.title(groupName: "企业专线") == "添加到「企业专线」")
    #expect(GroupPickerPresentation.searchPrompt(platform: "openai") == "搜索 OpenAI 账号")
    #expect(GroupPickerPresentation.sectionTitle(platform: "openai") == "OpenAI 账号")
    #expect(GroupPickerPresentation.footnote(platform: "openai") == "只列出 OpenAI 账号：其他平台的账号不会被这个分组调度。个别账号失败不影响其他账号。")
    #expect(GroupPickerPresentation.searchPrompt(platform: "composite") == "搜索账号")
    #expect(GroupPickerPresentation.sectionTitle(platform: "composite") == "账号")
    #expect(GroupPickerPresentation.footnote(platform: "composite") == "组合分组可以加入任意具体平台的账号。")
    #expect(GroupPickerPresentation.searchPrompt(platform: "zhipu") == "搜索 智谱 GLM 账号")
    #expect(GroupPickerPresentation.draftTitle == "添加账号")
    #expect(GroupPickerPresentation.failedTitle == "账号加载失败")
    #expect(GroupPickerPresentation.schedulableText == "可调度")
}

/// 4.2 排除、4.3 排序: schedulable → paused / disabled → the rest, each tier in the server's order.
@Test func pickerCandidatesLeaveOutMembersAndRankSchedulableFirst() {
    let rows = [memberAccount(1, status: "error", schedulable: false), memberAccount(2), memberAccount(3, schedulable: false),
                memberAccount(4, rateLimitedFor: 300), memberAccount(5, status: "inactive"), memberAccount(6, groups: [7])]
    let direct = GroupPickerPresentation.candidates(rows, memberOf: 7, excluded: [], now: memberNow)
    #expect(direct.map(\.id) == [2, 3, 5, 1, 4])
    let draft = GroupPickerPresentation.candidates(rows, memberOf: nil, excluded: [2], now: memberNow)
    #expect(draft.map(\.id) == [6, 3, 5, 1, 4])
}

@Test func pickerSecondLineShowsStoppedMarkTypeAndGroups() {
    let names = [1: "高级组", 5: "Claude Code 组"]
    func line(_ account: UpstreamAccount) -> String { GroupPickerPresentation.secondLine(account, now: memberNow) { names[$0] } }
    #expect(line(memberAccount(3, platform: "anthropic", type: "oauth", schedulable: false, groups: [1, 5], rateLimitedFor: 300))
        == "已停止调度 · OAuth · 已在 高级组、Claude Code 组")
    #expect(line(memberAccount(4)) == "API Key · 未分组")
    #expect(line(memberAccount(5, groups: [12])) == "API Key · 已在 #12")
    #expect(line(memberAccount(7, status: "error", schedulable: false, groups: [1])) == "API Key · 已在 高级组")
}

@Test func pickerStatusTextIsSchedulableOnlyForAvailable() {
    func text(_ account: UpstreamAccount) -> String? { GroupPickerPresentation.statusText(AccountDisplayState(account, now: memberNow)) }
    #expect(text(memberAccount(1)) == "可调度")
    #expect(text(memberAccount(2, schedulable: false)) == nil)
    #expect(text(memberAccount(3, status: "error")) == nil)
    #expect(text(memberAccount(4, rateLimitedFor: 300)) == nil)
}

@Test func pickerEmptyTextTellsNoAccountsAllMembersAndNoMatch() {
    #expect(GroupPickerPresentation.emptyText(platform: "openai", platformTotal: 0, available: 0) == "还没有 OpenAI 账号")
    #expect(GroupPickerPresentation.emptyText(platform: "openai", platformTotal: 2, available: 0) == "OpenAI 账号都已在这个分组里")
    #expect(GroupPickerPresentation.emptyText(platform: "openai", platformTotal: 2, available: 2) == "没有匹配的账号")
    #expect(GroupPickerPresentation.emptyText(platform: "anthropic", platformTotal: 3, available: 0) == "Anthropic 账号都已在这个分组里")
    #expect(GroupPickerPresentation.emptyText(platform: "composite", platformTotal: 0, available: 0) == "还没有账号")
    #expect(GroupPickerPresentation.emptyText(platform: "composite", platformTotal: 3, available: 0) == "账号都已在这个分组里")
}

@Test func pickerDockCountsOnlySchedulableSelections() {
    let enterprise = memberGroup(accounts: 1, active: 0)
    let none = GroupPickerPresentation.dock(selected: [], group: enterprise, now: memberNow)
    #expect(none == GroupPickerDock(preview: "选择要加入的账号", buttonTitle: "加入", isEnabled: false))
    let one = GroupPickerPresentation.dock(selected: [memberAccount(4)], group: enterprise, now: memberNow)
    #expect(one == GroupPickerDock(preview: "加入后可用 0 → 1 / 2", buttonTitle: "加入 1 个账号", isEnabled: true))
    let failing = GroupPickerPresentation.dock(selected: [memberAccount(7, status: "error", schedulable: false)], group: enterprise, now: memberNow)
    #expect(failing.preview == "加入后可用 0 → 0 / 2")
    let premium = memberGroup(1, name: "高级组", platform: "anthropic", accounts: 3, active: 2)
    let mixed = [memberAccount(8, platform: "anthropic"), memberAccount(9, platform: "anthropic", rateLimitedFor: 300)]
    #expect(GroupPickerPresentation.dock(selected: mixed, group: premium, now: memberNow).preview == "加入后可用 2 → 3 / 5")
    #expect(GroupPickerPresentation.dock(selected: mixed, group: premium, now: memberNow).buttonTitle == "加入 2 个账号")
    let composite = memberGroup(12, name: "混合组", platform: "composite", accounts: 0, active: 0)
    let anyPlatform = [memberAccount(10, platform: "anthropic"), memberAccount(11, platform: "openai")]
    #expect(GroupPickerPresentation.dock(selected: anyPlatform, group: composite, now: memberNow).preview == "加入后可用 0 → 2 / 2")
}

@Test func pickerDraftAddTitleCountsTheSelection() {
    #expect(GroupPickerPresentation.draftAddTitle(count: 2) == "添加 2")
    #expect(GroupPickerPresentation.draftAddTitle(count: 0) == "添加 0")
}
