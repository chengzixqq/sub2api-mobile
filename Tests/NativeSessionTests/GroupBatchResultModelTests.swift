import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S5-09: the per-item results page (50 §5.4, §5.5): 重试 n 个 resends as sent and sends the mixed-channel items alone once
// confirmed, 撤销成功的 s 个 sends the reverse, a request that did not finish leaves the items and says so, the session guard.

private let batchMixed = GroupMemberMixedChannel(currentPlatform: "Anthropic", otherPlatform: "Antigravity")

private func batchItem(_ id: Int, _ action: GroupMemberAction, _ result: GroupBatchItem.Result, priority: Int? = nil) -> GroupBatchItem {
    GroupBatchItem(accountID: id, name: "账号\(id)", action: action, result: result, priority: priority)
}
private func batchOutcome(_ items: [GroupBatchItem]) -> GroupBatchOutcome { GroupBatchOutcome(groupID: 5, groupName: "Claude Code 组", items: items) }
/// Every account of the request done: an add with its priority (50 without one), a removal answering 50.
private func batchEcho(_ request: GroupMemberBatchRequest) -> GroupMemberBatchResult {
    GroupMemberBatchResult(groupID: 5, results: request.add.map { GroupMemberResultItem(accountID: $0.accountID, action: .add, status: .added, priority: $0.priority ?? 50) }
                           + request.remove.map { GroupMemberResultItem(accountID: $0, action: .remove, status: .removed, priority: 50) }, counts: nil)
}

/// The page's send: records each request and answers from the script (nil, or an empty script, echoes it as done); sends wait
/// at the gate when there is one.
@MainActor private final class BatchStub {
    private(set) var requests: [GroupMemberBatchRequest] = []
    var replies: [GroupMemberSendResult?] = []
    var gate: SessionGate?
    var isCurrent = true
    let receipts = ReceiptCenter(sleep: { try await Task.sleep(for: $0 * 1_000) })

    var receiptText: String? { receipts.current?.text }
    func send(_ request: GroupMemberBatchRequest) async -> GroupMemberSendResult {
        requests.append(request)
        if let gate { await gate.wait() }
        let reply = replies.isEmpty ? nil : replies.removeFirst()
        return reply ?? .result(batchEcho(request), usedLegacy: false)
    }
    func page(_ outcome: GroupBatchOutcome) -> GroupBatchResultModel {
        GroupBatchResultModel(outcome: outcome, endpoints: GroupBatchEndpoints(send: { [unowned self] in await self.send($0) }),
                              receipts: receipts, isCurrent: { [unowned self] in self.isCurrent })
    }
}

private func batchArrived(_ gate: SessionGate) async {
    var spins = 0
    while !(await gate.arrived), spins < 10_000 { await Task.yield(); spins += 1 }
}

// MARK: - 重试（5.4）

@MainActor @Test func retryResendsRequestFailedItemsAsSent() async throws {
    let stub = BatchStub()
    let page = stub.page(batchOutcome([batchItem(11, .add, .failed(.requestFailed), priority: 2), batchItem(13, .remove, .failed(.unconfirmed))]))
    let resend = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 11, priority: 2)], remove: [13])
    #expect(page.retryCount == 2)
    #expect(await page.retry() == .done)
    #expect(stub.requests == [resend])
    #expect(page.outcome.failures.isEmpty)
    #expect(page.outcome.successes.map(\.resultLabel) == ["重试后已加入", "重试后已移出"])
    #expect(stub.receiptText == "重试成功 · 已加入 1 个、已移出 1 个账号")
    #expect(page.running == nil && page.failureLine == nil && page.retryCount == 0)
}

@MainActor @Test func mixedChannelRetryWaitsForConfirmationThenGoesAloneWithConfirm() async throws {
    let stub = BatchStub()
    let page = stub.page(batchOutcome([batchItem(4, .add, .succeeded(.added), priority: 50), batchItem(7, .add, .failed(.notFound)),
                                      batchItem(3, .add, .failed(.mixedChannel(batchMixed)))]))
    #expect(page.retryCount == 1)
    #expect(await page.retry() == .needsConfirmation)
    #expect(stub.requests.isEmpty)
    let prompt = try #require(page.mixedChannelPrompt)
    #expect(prompt.title == "仍然加入混合渠道账号？" && prompt.confirmTitle == "仍然加入")
    #expect(prompt.message.hasPrefix("分组里已有 Antigravity 账号。"))
    let confirmed = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 3)], confirmMixedChannelRisk: true)
    #expect(await page.confirmMixedChannel() == .done)
    #expect(stub.requests == [confirmed])
    #expect(page.outcome.items.first { $0.accountID == 3 }?.resultLabel == "重试后已加入")
    #expect(page.outcome.failures.map(\.accountID) == [7])
    #expect(page.retryCount == 0 && page.mixedChannelPrompt == nil)
    #expect(stub.receiptText == "重试成功 · 已加入 1 个账号")
}

@MainActor @Test func cancellingMixedChannelSendsNothing() async {
    let stub = BatchStub()
    let before = batchOutcome([batchItem(11, .add, .failed(.requestFailed)), batchItem(3, .add, .failed(.mixedChannel(batchMixed)))])
    let page = stub.page(before)
    #expect(await page.retry() == .needsConfirmation)
    page.cancelMixedChannel()
    #expect(stub.requests.isEmpty)
    #expect(page.mixedChannelPrompt == nil && page.running == nil)
    #expect(page.outcome == before)
    #expect(stub.receiptText == nil)
}

@MainActor @Test func plainAndMixedRetriesGoAsTwoRequestsInOrder() async throws {
    let stub = BatchStub()
    let page = stub.page(batchOutcome([batchItem(11, .add, .failed(.requestFailed)), batchItem(3, .add, .failed(.mixedChannel(batchMixed)))]))
    let resend = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 11)])
    let confirmed = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 3)], confirmMixedChannelRisk: true)
    #expect(await page.retry() == .needsConfirmation)
    #expect(await page.confirmMixedChannel() == .done)
    #expect(stub.requests == [resend, confirmed])
    #expect(page.outcome.failures.isEmpty)
    #expect(page.outcome.successes.map(\.accountID) == [11, 3])
    #expect(stub.receiptText == "重试成功 · 已加入 2 个账号")
}

@MainActor @Test func retryThatStillFailsTakesTheNewReason() async {
    let stub = BatchStub()
    stub.replies = [.result(GroupMemberBatchResult(groupID: 5, results: [GroupMemberResultItem(accountID: 11, action: .add, status: .failed,
                                                                                            reason: GroupMemberReason.accountNotFound)], counts: nil),
                            usedLegacy: false)]
    let page = stub.page(batchOutcome([batchItem(11, .add, .failed(.requestFailed))]))
    #expect(await page.retry() == .stillFailing)
    #expect(page.outcome.failures.map(\.reasonText) == ["账号不存在或已删除"])
    #expect(page.retryCount == 0)
    #expect(stub.receiptText == "加入失败 · 1 个账号没有改动")
    #expect(page.failureLine == nil)
}

// MARK: - 请求级失败（5.5）

@MainActor @Test func requestLevelFailureKeepsItemsAndShowsTheLine() async {
    let stub = BatchStub()
    stub.replies = [.unconfirmed]
    let before = batchOutcome([batchItem(11, .add, .failed(.requestFailed))])
    let page = stub.page(before)
    #expect(await page.retry() == .failed)
    #expect(page.outcome == before)
    #expect(page.failureLine == "没有完成，请稍后重试")
    #expect(stub.receiptText == nil && page.running == nil)
    #expect(await page.retry() == .done)
    #expect(page.failureLine == nil)
    #expect(stub.requests.count == 2)
}

@MainActor @Test func refusalShowsTheWritersWordsInsteadOfRetryLater() async {
    let stub = BatchStub()
    stub.replies = [.groupGone("这个分组已删除"), .rejected("你的工作区没有这个权限。")]
    let page = stub.page(batchOutcome([batchItem(11, .add, .failed(.requestFailed))]))
    #expect(await page.retry() == .failed)
    #expect(page.failureLine == "这个分组已删除")
    #expect(await page.retry() == .failed)
    #expect(page.failureLine == "你的工作区没有这个权限。")
    #expect(page.outcome.failures.map(\.accountID) == [11])
}

@MainActor @Test func secondRequestFailureKeepsFirstRequestResults() async {
    let stub = BatchStub()
    stub.replies = [nil, .unconfirmed]
    let page = stub.page(batchOutcome([batchItem(11, .add, .failed(.requestFailed)), batchItem(3, .add, .failed(.mixedChannel(batchMixed)))]))
    #expect(await page.retry() == .needsConfirmation)
    #expect(await page.confirmMixedChannel() == .failed)
    #expect(stub.requests.count == 2)
    #expect(page.outcome.successes.map(\.accountID) == [11])
    #expect(page.outcome.failures.map(\.result) == [.failed(.mixedChannel(batchMixed))])
    #expect(page.failureLine == "没有完成，请稍后重试")
    #expect(stub.receiptText == nil)
}

// MARK: - 撤销（5.4）

@MainActor @Test func undoSendsInverseOfChangedItemsOnly() async throws {
    let stub = BatchStub()
    let page = stub.page(batchOutcome([batchItem(11, .add, .succeeded(.added), priority: 50), batchItem(12, .add, .succeeded(.unchanged)),
                                      batchItem(7, .add, .failed(.notFound)), batchItem(13, .remove, .succeeded(.removed), priority: 7)]))
    let reverse = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 13, priority: 7)], remove: [11])
    #expect(page.undoCount == 2)
    #expect(await page.undo() == .done)
    #expect(stub.requests == [reverse])
    #expect(page.outcome.successes.map(\.accountID) == [12, 11, 13])
    #expect(page.outcome.successes.map(\.resultLabel) == ["无需改动", "已撤销", "已撤销"])
    #expect(page.outcome.failures.map(\.accountID) == [7])
    #expect(stub.receiptText == "已撤销 2 个账号的改动")
    #expect(page.undoCount == 0)
}

@MainActor @Test func retryThenUndoEndsAllUndone() async {
    let stub = BatchStub()
    let page = stub.page(batchOutcome([batchItem(3, .add, .failed(.mixedChannel(batchMixed)))]))
    #expect(await page.retry() == .needsConfirmation)
    #expect(await page.confirmMixedChannel() == .done)
    #expect(page.outcome.statusCard == .allDone("全部完成 · 已加入 1 个账号"))
    #expect(page.undoCount == 1)
    #expect(await page.undo() == .done)
    #expect(page.outcome.statusCard == .allUndone)
    #expect(page.undoCount == 0 && page.retryCount == 0)
}

// MARK: - 互斥与会话（5.5）

@MainActor @Test func batchSecondTapWhileRunningIsIgnored() async {
    let stub = BatchStub()
    let gate = SessionGate()
    stub.gate = gate
    let page = stub.page(batchOutcome([batchItem(11, .add, .failed(.requestFailed)), batchItem(12, .add, .succeeded(.added))]))
    let first = Task { await page.retry() }
    await batchArrived(gate)
    #expect(page.running == .retry)
    #expect(await page.retry() == .ignored)
    #expect(await page.undo() == .ignored)
    await gate.open()
    #expect(await first.value == .done)
    #expect(stub.requests.count == 1)
    #expect(page.running == nil)
}

@MainActor @Test func answerAfterSessionEndedIsDropped() async {
    let stub = BatchStub()
    let gate = SessionGate()
    stub.gate = gate
    let before = batchOutcome([batchItem(11, .add, .failed(.requestFailed))])
    let page = stub.page(before)
    let first = Task { await page.retry() }
    await batchArrived(gate)
    stub.isCurrent = false
    await gate.open()
    #expect(await first.value == .ignored)
    #expect(page.outcome == before)
    #expect(stub.receiptText == nil && page.failureLine == nil && page.running == nil)
    #expect(await page.retry() == .ignored)
    #expect(stub.requests.count == 1)
}

@MainActor @Test func ignoredSendLeavesThePageAsItWas() async {
    let stub = BatchStub()
    stub.replies = [.ignored]
    let before = batchOutcome([batchItem(11, .add, .failed(.requestFailed))])
    let page = stub.page(before)
    #expect(await page.retry() == .ignored)
    #expect(page.outcome == before && page.failureLine == nil && stub.receiptText == nil)
}

@MainActor @Test func nothingRetryableSendsNothing() async {
    let stub = BatchStub()
    let page = stub.page(batchOutcome([batchItem(7, .add, .failed(.notFound)), batchItem(4, .add, .succeeded(.added))]))
    #expect(page.retryCount == 0)
    #expect(await page.retry() == .ignored)
    let failedOnly = stub.page(batchOutcome([batchItem(7, .add, .failed(.notFound))]))
    #expect(failedOnly.undoCount == 0)
    #expect(await failedOnly.undo() == .ignored)
    #expect(stub.requests.isEmpty)
}
