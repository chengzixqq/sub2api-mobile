import Foundation
import Testing
@testable import Sub2Core

// S5-03: 50 §5.3–§5.5 per-item results, retry and undo.

private let outcomeAnthropic = GroupMemberMixedChannel(currentPlatform: "Antigravity", otherPlatform: "Anthropic")

private func outcomeItem(_ id: Int, _ action: GroupMemberAction, _ result: GroupBatchItem.Result, priority: Int? = nil) -> GroupBatchItem {
    GroupBatchItem(accountID: id, name: "账号\(id)", action: action, result: result, priority: priority)
}
private func outcomeOf(_ items: [GroupBatchItem]) -> GroupBatchOutcome { GroupBatchOutcome(groupID: 3, groupName: "高级组", items: items) }
private func outcomeAnswer(_ items: [GroupMemberResultItem]) -> GroupMemberBatchResult { GroupMemberBatchResult(groupID: 3, results: items, counts: nil) }
/// Every account of the request done.
private func outcomeEcho(_ request: GroupMemberBatchRequest) -> GroupMemberBatchResult {
    outcomeAnswer(request.add.map { GroupMemberResultItem(accountID: $0.accountID, action: .add, status: .added, priority: $0.priority ?? 50) }
                  + request.remove.map { GroupMemberResultItem(accountID: $0, action: .remove, status: .removed, priority: 1) })
}
private func outcomeRows(_ rows: [(Int, GroupMemberAction, GroupMemberStatus)]) -> GroupMemberBatchResult {
    outcomeAnswer(rows.map { GroupMemberResultItem(accountID: $0.0, action: $0.1, status: $0.2, reason: $0.2 == .failed ? GroupMemberReason.accountNotFound : nil) })
}

@Test func outcomeBuildsItemsInRequestOrderWithSnapshots() throws {
    let request = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 11, priority: 2), GroupMemberAdd(accountID: 12)], remove: [13])
    let answer = outcomeAnswer([GroupMemberResultItem(accountID: 12, action: .add, status: .added, priority: 50),
                                GroupMemberResultItem(accountID: 11, action: .add, status: .failed, reason: GroupMemberReason.mixedChannelRisk, details: outcomeAnthropic),
                                GroupMemberResultItem(accountID: 13, action: .remove, status: .removed, priority: 7)])
    let account = UpstreamAccount(id: 11, name: "Claude-官方-01", platform: "antigravity", type: "oauth", status: "error", schedulable: false)
    let outcome = GroupBatchOutcome(groupID: 3, groupName: "高级组", request: request, result: answer,
                                    accounts: [11: GroupBatchAccount(account), 12: GroupBatchAccount(name: "Codex-02")])
    #expect(outcome.groupID == 3 && outcome.groupName == "高级组")
    #expect(outcome.items.map(\.accountID) == [11, 12, 13])
    #expect(outcome.items.map(\.name) == ["Claude-官方-01", "Codex-02", "账号 #13"])
    #expect(outcome.items.map(\.state) == [AccountStateInput(account), nil, nil])
    #expect(outcome.items.map(\.priority) == [2, 50, 7])
    #expect(outcome.items.map(\.result) == [.failed(.mixedChannel(outcomeAnthropic)), .succeeded(.added), .succeeded(.removed)])
}

@Test func outcomeMapsFailureReasonsAndRetryability() {
    func item(_ reason: String?, details: GroupMemberMixedChannel? = nil) -> GroupBatchItem {
        outcomeItem(11, .add, GroupBatchItem.result(of: GroupMemberResultItem(accountID: 11, action: .add, status: .failed, reason: reason, details: details)))
    }
    let notFound = item(GroupMemberReason.accountNotFound)
    #expect(notFound.result == .failed(.notFound) && notFound.reasonText == "账号不存在或已删除" && !notFound.isRetryable)
    let mixed = item(GroupMemberReason.mixedChannelRisk, details: outcomeAnthropic)
    #expect(mixed.reasonText == "分组里已有 Anthropic 账号，与 Antigravity 账号混用有风险")
    #expect(mixed.isRetryable && mixed.needsMixedChannelConfirmation)
    #expect(item(GroupMemberReason.mixedChannelRisk).reasonText == "分组里已有其他渠道的账号，混用有风险")
    let undelivered = item(GroupMemberReason.notDelivered)
    #expect(undelivered.result == .failed(.requestFailed) && undelivered.reasonText == "请求没有送达，账号没有改动" && undelivered.isRetryable)
    let unconfirmed = item(GroupMemberReason.notConfirmed)
    #expect(unconfirmed.result == .failed(.unconfirmed) && unconfirmed.reasonText == "结果未确认，可以重试" && unconfirmed.isRetryable)
    #expect(!unconfirmed.needsMixedChannelConfirmation)
    #expect(GroupBatchItem.result(of: nil) == .failed(.unconfirmed))
    // R11: the server's message never; GroupErrorCopy's words, then the code, then nothing.
    #expect(item("GROUP_NOT_FOUND").reasonText == "这个分组已删除")
    #expect(item("FORBIDDEN").reasonText == "你的工作区没有这个权限。")
    #expect(item("WEIRD_THING").reasonText == "没有完成（错误码 WEIRD_THING），账号没有改动")
    #expect(item("weird text with spaces").reasonText == "没有完成，账号没有改动")
    let unknown = item(nil)
    #expect(unknown.result == .failed(.other(reason: nil)) && unknown.reasonText == "没有完成，账号没有改动" && unknown.isRetryable)
    #expect(outcomeItem(12, .add, .succeeded(.added)).reasonText == nil)
}

@Test func outcomeLabelsEveryResult() {
    let rows: [(GroupMemberAction, GroupBatchItem.Result, String, Bool)] = [
        (.add, .failed(.notFound), "加入失败", false), (.remove, .failed(.requestFailed), "移出失败", false),
        (.add, .succeeded(.added), "已加入", true), (.remove, .succeeded(.removed), "已移出", true),
        (.add, .succeeded(.retriedAdded(changed: true)), "重试后已加入", true), (.add, .succeeded(.retriedAdded(changed: false)), "重试后已加入", false),
        (.remove, .succeeded(.retriedRemoved(changed: true)), "重试后已移出", true), (.remove, .succeeded(.retriedRemoved(changed: false)), "重试后已移出", false),
        (.add, .succeeded(.unchanged), "无需改动", false), (.remove, .succeeded(.undone), "已撤销", false)
    ]
    for (action, result, label, undoable) in rows {
        let item = outcomeItem(11, action, result)
        #expect(item.resultLabel == label)
        #expect(item.isUndoable == undoable)
        #expect(item.isUndone == (result == .succeeded(.undone)))
    }
}

@Test func outcomeRetryPlanSendsMixedChannelSeparately() throws {
    let antigravity = GroupMemberMixedChannel(currentPlatform: "Anthropic", otherPlatform: "Antigravity")
    let outcome = outcomeOf([outcomeItem(11, .add, .failed(.requestFailed), priority: 2), outcomeItem(12, .add, .failed(.mixedChannel(outcomeAnthropic))),
                             outcomeItem(14, .add, .failed(.mixedChannel(antigravity))), outcomeItem(13, .remove, .failed(.other(reason: "FORBIDDEN"))),
                             outcomeItem(15, .add, .failed(.notFound)), outcomeItem(16, .add, .succeeded(.added)), outcomeItem(17, .remove, .failed(.unconfirmed))])
    let plan = outcome.retryPlan()
    let resend = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 11, priority: 2)], remove: [13, 17])
    let mixed = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 12), GroupMemberAdd(accountID: 14)], confirmMixedChannelRisk: true)
    #expect(plan.resend == resend)
    #expect(plan.mixedChannel == mixed)
    let confirmation = try #require(plan.confirmation)
    #expect(confirmation.title == "仍然加入混合渠道账号？" && confirmation.confirmTitle == "仍然加入" && GroupMixedChannelConfirmation.cancelTitle == "取消")
    #expect(confirmation.message == "分组里已有 Anthropic、Antigravity 账号。同一分组混用 Anthropic 与 Antigravity 账号可能导致思考块签名校验失败，历史消息会降级为非思考模式。")
    #expect(GroupMixedChannelConfirmation(otherPlatforms: []).message
            == "分组里已有其他渠道的账号。同一分组混用 Anthropic 与 Antigravity 账号可能导致思考块签名校验失败，历史消息会降级为非思考模式。")
    #expect(GroupMixedChannelConfirmation(otherPlatforms: ["Anthropic", "Anthropic"]).message.hasPrefix("分组里已有 Anthropic 账号。"))
    let plain = outcomeOf([outcomeItem(11, .add, .failed(.unconfirmed))]).retryPlan()
    #expect(plain.mixedChannel == nil && plain.confirmation == nil && plain.resend?.accountIDs == [11] && !plain.isEmpty)
    #expect(outcomeOf([outcomeItem(15, .add, .failed(.notFound))]).retryPlan().isEmpty)
}

@Test func outcomeUndoPlanRevertsOnlyChanges() throws {
    let outcome = outcomeOf([outcomeItem(11, .add, .succeeded(.added)), outcomeItem(13, .remove, .succeeded(.removed), priority: 7),
                             outcomeItem(12, .add, .succeeded(.retriedAdded(changed: false))), outcomeItem(14, .add, .succeeded(.unchanged)),
                             outcomeItem(15, .add, .failed(.notFound)), outcomeItem(16, .remove, .succeeded(.undone)),
                             outcomeItem(18, .remove, .succeeded(.retriedRemoved(changed: true)), priority: 3)])
    let expected = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 13, priority: 7), GroupMemberAdd(accountID: 18, priority: 3)], remove: [11])
    #expect(outcome.undoPlan() == expected)
    #expect(outcome.undoPlan()?.confirmMixedChannelRisk == false)
    #expect(outcomeOf([outcomeItem(14, .add, .succeeded(.unchanged))]).undoPlan() == nil)
}

@Test func outcomeApplyingRetryMarksRetriedResults() {
    let before = outcomeOf([outcomeItem(11, .add, .failed(.requestFailed)), outcomeItem(12, .add, .failed(.unconfirmed)),
                            outcomeItem(13, .remove, .failed(.other(reason: nil))), outcomeItem(14, .add, .failed(.mixedChannel(nil))),
                            outcomeItem(15, .add, .succeeded(.added), priority: 50), outcomeItem(16, .add, .failed(.notFound))])
    let answer = outcomeAnswer([GroupMemberResultItem(accountID: 11, action: .add, status: .added, priority: 50),
                                GroupMemberResultItem(accountID: 12, action: .add, status: .unchanged),
                                GroupMemberResultItem(accountID: 13, action: .remove, status: .removed, priority: 9),
                                GroupMemberResultItem(accountID: 14, action: .add, status: .failed, reason: GroupMemberReason.accountNotFound),
                                GroupMemberResultItem(accountID: 15, action: .add, status: .failed, reason: GroupMemberReason.accountNotFound),
                                GroupMemberResultItem(accountID: 16, action: .add, status: .added),
                                GroupMemberResultItem(accountID: 99, action: .add, status: .added)])
    let after = before.applying(answer, as: .retry)
    #expect(after.items.map(\.result) == [.succeeded(.retriedAdded(changed: true)), .succeeded(.retriedAdded(changed: false)),
                                          .succeeded(.retriedRemoved(changed: true)), .failed(.notFound), .succeeded(.added), .failed(.notFound)])
    #expect(after.items.map(\.priority) == [50, nil, 9, nil, 50, nil])
    #expect(after.items.map(\.isUndoable) == [true, false, true, false, true, false])
    #expect(after.items[1].resultLabel == "重试后已加入")
    #expect(before.items[0].result == .failed(.requestFailed))
}

@Test func outcomeApplyingUndoMarksUndone() {
    let before = outcomeOf([outcomeItem(11, .add, .succeeded(.added)), outcomeItem(13, .remove, .succeeded(.removed), priority: 7),
                            outcomeItem(12, .add, .succeeded(.retriedAdded(changed: true))), outcomeItem(14, .add, .succeeded(.unchanged))])
    let answer = outcomeAnswer([GroupMemberResultItem(accountID: 11, action: .remove, status: .removed),
                                GroupMemberResultItem(accountID: 13, action: .add, status: .unchanged),
                                GroupMemberResultItem(accountID: 12, action: .remove, status: .failed, reason: GroupMemberReason.accountNotFound),
                                GroupMemberResultItem(accountID: 14, action: .remove, status: .removed)])
    let after = before.applying(answer, as: .undo)
    #expect(after.items.map(\.result) == [.succeeded(.undone), .succeeded(.undone), .succeeded(.retriedAdded(changed: true)), .succeeded(.unchanged)])
    #expect(after.successes.map(\.accountID) == [12, 14, 11, 13])
    #expect(after.undoableCount == 1)
}

@Test func outcomeStatusCardCountsAndOrder() {
    let outcome = outcomeOf([outcomeItem(11, .add, .failed(.requestFailed)), outcomeItem(12, .add, .failed(.notFound)),
                             outcomeItem(13, .add, .succeeded(.added)), outcomeItem(14, .add, .succeeded(.unchanged))])
    #expect(outcome.statusCard == .failures(failed: 2, succeeded: 2))
    #expect(outcome.retryableCount == 1 && outcome.undoableCount == 1 && outcome.succeededCount == 2)
    #expect(outcome.failures.map(\.accountID) == [11, 12] && outcome.successes.map(\.accountID) == [13, 14])
    let done = outcomeOf([outcomeItem(11, .add, .succeeded(.retriedAdded(changed: true))), outcomeItem(13, .add, .succeeded(.added)),
                          outcomeItem(14, .add, .succeeded(.unchanged))])
    #expect(done.statusCard == .allDone("全部完成 · 已加入 3 个账号"))
    let undone = done.applying(outcomeRows([(11, .remove, .removed), (13, .remove, .removed)]), as: .undo)
    #expect(undone.statusCard == .allUndone)
    #expect(undone.successes.map(\.accountID) == [14, 11, 13])
    #expect(undone.succeededCount == 1 && undone.undoableCount == 0)
}

@Test func outcomeRetryAndUndoReceipts() {
    #expect(GroupBatchOutcome.retryReceipt(outcomeRows([(11, .add, .added), (12, .add, .unchanged)]))
            == GroupMemberReceipt(text: "重试成功 · 已加入 2 个账号", systemImage: "checkmark.circle", tone: .ok, button: nil))
    #expect(GroupBatchOutcome.retryReceipt(outcomeRows([(13, .remove, .removed)])).text == "重试成功 · 已移出 1 个账号")
    #expect(GroupBatchOutcome.retryReceipt(outcomeRows([(11, .add, .added), (12, .add, .failed)]))
            == GroupMemberReceipt(text: "已加入 1 个，1 个失败", systemImage: "exclamationmark.triangle", tone: .caution, button: nil))
    #expect(GroupBatchOutcome.retryReceipt(outcomeRows([(12, .add, .failed)])).button == nil)
    #expect(GroupBatchOutcome.undoReceipt(outcomeRows([(11, .remove, .removed), (13, .add, .added)]))
            == GroupMemberReceipt(text: "已撤销 2 个账号的改动", systemImage: "arrow.uturn.backward.circle", tone: .neutral, button: nil))
    #expect(GroupBatchOutcome.undoReceipt(outcomeRows([(11, .remove, .removed), (12, .remove, .failed)]))
            == GroupMemberReceipt(text: "已撤销 1 个账号的改动 · 1 个没有撤销", systemImage: "exclamationmark.triangle", tone: .caution, button: nil))
    #expect(GroupBatchOutcome.undoReceipt(outcomeRows([(12, .remove, .failed)]))
            == GroupMemberReceipt(text: "撤销没有成功 · 1 个账号没有改动", systemImage: "xmark.octagon", tone: .critical, button: nil))
}

@Test func groupBatchCopyMatchesSpecWording() {
    #expect(GroupBatchCopy.title == "逐项结果")
    #expect(GroupBatchCopy.subtitle(groupName: "高级组", count: 3) == "高级组 · 3 个账号")
    #expect(GroupBatchCopy.failedBadge(2) == "2 个失败")
    #expect(GroupBatchCopy.succeededText(1) == "1 个成功")
    #expect(GroupBatchCopy.failuresMeta(2) == "2 个 · 没有改动")
    #expect(GroupBatchCopy.successesMeta(1) == "1 个")
    #expect(GroupBatchCopy.retryButton(2) == "重试 2 个")
    #expect(GroupBatchCopy.undoButton(1) == "撤销成功的 1 个")
    #expect(GroupBatchCopy.failureNote == "失败的账号没有改动，可以直接重试，或点开账号单独处理。")
    #expect(GroupBatchCopy.requestFailed == "没有完成，请稍后重试")
    #expect(GroupBatchCopy.allUndone == "已全部撤销")
    #expect(GroupBatchCopy.allDone("已加入 2 个账号") == "全部完成 · 已加入 2 个账号" && GroupBatchCopy.allDone(nil) == "全部完成")
    #expect(GroupBatchCopy.notFound == "账号不存在或已删除")
    #expect(GroupBatchCopy.notDelivered == "请求没有送达，账号没有改动")
    #expect(GroupBatchCopy.unconfirmed == "结果未确认，可以重试")
    #expect(GroupBatchCopy.unnamedAccount(13) == "账号 #13")
    #expect(GroupBatchCopy.retryButton(1234) == "重试 1,234 个" && GroupBatchCopy.subtitle(groupName: "高级组", count: 1234) == "高级组 · 1,234 个账号")
}

@Test func outcomeEndToEndRetryConfirmThenUndo() throws {
    let request = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 11), GroupMemberAdd(accountID: 12), GroupMemberAdd(accountID: 13)])
    let first = outcomeAnswer([GroupMemberResultItem(accountID: 11, action: .add, status: .added, priority: 50),
                               GroupMemberResultItem(accountID: 12, action: .add, status: .failed, reason: GroupMemberReason.mixedChannelRisk, details: outcomeAnthropic),
                               GroupMemberResultItem(accountID: 13, action: .add, status: .failed, reason: GroupMemberReason.notDelivered)])
    let outcome = GroupBatchOutcome(groupID: 3, groupName: "高级组", request: request, result: first)
    #expect(outcome.statusCard == .failures(failed: 2, succeeded: 1) && outcome.retryableCount == 2)
    let plan = outcome.retryPlan()
    let resend = try #require(plan.resend), mixed = try #require(plan.mixedChannel)
    #expect(resend.accountIDs == [13] && !resend.confirmMixedChannelRisk && mixed.accountIDs == [12] && mixed.confirmMixedChannelRisk)
    let retried = outcome.applying(outcomeEcho(resend), as: .retry).applying(outcomeEcho(mixed), as: .retry)
    #expect(retried.statusCard == .allDone("全部完成 · 已加入 3 个账号"))
    let undo = try #require(retried.undoPlan())
    #expect(undo.remove == [11, 12, 13] && undo.add.isEmpty)
    #expect(retried.applying(outcomeEcho(undo), as: .undo).statusCard == .allUndone)

    let withMissing = outcomeOf([outcomeItem(11, .add, .succeeded(.added)), outcomeItem(15, .add, .failed(.notFound))])
    let undoMissing = try #require(withMissing.undoPlan())
    #expect(withMissing.applying(outcomeEcho(undoMissing), as: .undo).statusCard == .failures(failed: 1, succeeded: 0))
}
