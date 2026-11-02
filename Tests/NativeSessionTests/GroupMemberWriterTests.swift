import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S5-08: GroupMemberWriter, the one way member writes go out (S5D2a-08): batch or the 0.4.4 fallback, receipts with 撤销 / 查看 /
// 重试 (0.4.3, 0.8, 2.4), the session guard and the read-only token.

private let memberTransport = APIError(kind: .transport, message: "无法连接站点")
private let repositoryUnsupported = APIError.server(status: 500, reason: "GROUP_REPOSITORY_UNSUPPORTED")

private func pickAccount(_ id: Int, _ name: String, status: String = "active") -> UpstreamAccount {
    UpstreamAccount(id: id, name: name, platform: "openai", type: "apikey", status: status, schedulable: status == "active")
}
private let mainAccount = pickAccount(4, "OpenAI-主力-01")
private let spareAccount = pickAccount(7, "OpenAI-备用-A", status: "error")
private let enterprise = GroupMemberTarget(id: 4, name: "企业专线", activeBefore: 0)
private let premium = GroupMemberTarget(id: 1, name: "高级组", activeBefore: 2)

private func counts(active: Int, total: Int) -> GroupAccountCounts {
    GroupAccountCounts(accountCount: total, activeAccountCount: active, rateLimitedAccountCount: 0, errorAccountCount: total - active, idleAccountCount: 0)
}
private func answer(_ items: [GroupMemberResultItem], counts: GroupAccountCounts? = nil, groupID: Int = 4) -> GroupMemberBatchResult {
    GroupMemberBatchResult(groupID: groupID, results: items, counts: counts)
}
private func added(_ id: Int, priority: Int = 50) -> GroupMemberResultItem { GroupMemberResultItem(accountID: id, action: .add, status: .added, priority: priority) }
private func removed(_ id: Int, priority: Int) -> GroupMemberResultItem { GroupMemberResultItem(accountID: id, action: .remove, status: .removed, priority: priority) }
private func mixed(_ id: Int) -> GroupMemberResultItem {
    GroupMemberResultItem(accountID: id, action: .add, status: .failed, reason: GroupMemberReason.mixedChannelRisk,
                          details: GroupMemberMixedChannel(currentPlatform: "Antigravity", otherPlatform: "Anthropic"))
}

/// Records each send with its generation and answers from per-call scripts; an empty script echoes the request as done. A send
/// whose generation is no longer the session's throws CancellationError, as AppModel's does.
@MainActor private final class ScriptedMemberSource: GroupMemberWriteSource {
    enum Call: Equatable {
        case batch(groupID: Int, GroupMemberBatchRequest, generation: UUID)
        case legacy(groupID: Int, GroupMemberBatchRequest, generation: UUID)
    }
    private(set) var session: GroupMemberWriteSession?
    private(set) var calls: [Call] = []
    var batchReplies: [Result<GroupMemberBatchResult, any Error>] = []
    var legacyReplies: [Result<GroupMemberBatchResult, any Error>] = []
    private(set) var unsupportedNotes = 0
    private(set) var finished: [GroupMemberChange] = []
    private(set) var gone: [Int] = []
    /// Sends wait here before answering.
    var gate: SessionGate?

    init(usesBatch: Bool = true, allowsLegacy: Bool = true, readOnly: Bool = false) {
        session = GroupMemberWriteSession(generation: UUID(), usesBatch: usesBatch, allowsLegacy: allowsLegacy, isReadOnlyToken: readOnly)
    }
    var generation: UUID { session?.generation ?? UUID() }
    func switchSession() {
        guard let old = session else { return }
        session = GroupMemberWriteSession(generation: UUID(), usesBatch: old.usesBatch, allowsLegacy: old.allowsLegacy, isReadOnlyToken: old.isReadOnlyToken)
    }

    var groupMemberWriteSession: GroupMemberWriteSession? { session }
    func sendGroupMemberBatch(groupID: Int, _ request: GroupMemberBatchRequest, generation: UUID) async throws -> GroupMemberBatchResult {
        calls.append(.batch(groupID: groupID, request, generation: generation))
        try await admit(generation)
        return try Self.next(&batchReplies) ?? Self.echo(request, groupID: groupID)
    }
    func sendGroupMembersLegacy(groupID: Int, _ request: GroupMemberBatchRequest, generation: UUID) async throws -> GroupMemberBatchResult {
        calls.append(.legacy(groupID: groupID, request, generation: generation))
        try await admit(generation)
        return try Self.next(&legacyReplies) ?? Self.echo(request, groupID: groupID)
    }
    func noteMemberBatchUnsupported() { unsupportedNotes += 1 }
    func memberWriteFinished(_ change: GroupMemberChange) { finished.append(change) }
    func groupWentAway(id: Int) { gone.append(id) }

    private func admit(_ generation: UUID) async throws {
        if let gate { await gate.wait() }
        guard generation == session?.generation else { throw CancellationError() }
    }
    private static func echo(_ request: GroupMemberBatchRequest, groupID: Int) -> GroupMemberBatchResult {
        answer(request.add.map { added($0.accountID, priority: $0.priority ?? 50) } + request.remove.map { removed($0, priority: 50) }, groupID: groupID)
    }
    private static func next<T>(_ script: inout [Result<T, any Error>]) throws -> T? {
        guard !script.isEmpty else { return nil }
        return try script.removeFirst().get()
    }
}

/// One writer with its receipts (they stay up: the timer sleeps for an hour) and the result pages it opened.
@MainActor private final class MemberHarness {
    let source: ScriptedMemberSource
    let receipts = ReceiptCenter(sleep: { try await Task.sleep(for: $0 * 1_000) })
    private(set) var opened: [GroupBatchOutcome] = []
    private(set) var writer: GroupMemberWriter!

    init(_ source: ScriptedMemberSource = ScriptedMemberSource()) {
        self.source = source
        writer = GroupMemberWriter(source: source, receipts: receipts, openResults: { [weak self] in self?.opened.append($0) })
    }
    var generation: UUID { source.generation }
    var receiptText: String? { receipts.current?.text }
    var receiptButton: String? { receipts.current?.action?.title }
    /// Taps the receipt's button and waits until what it started has finished.
    func tapReceipt() async {
        guard let receipt = receipts.current else { return }
        receipts.performAction(id: receipt.id)
        await memberSettle { self.writer.busyAccounts.isEmpty && !self.writer.isSubmitting }
    }
}

@MainActor private func memberSettle(_ done: @MainActor () -> Bool) async {
    var spins = 0
    while !done(), spins < 10_000 { await Task.yield(); spins += 1 }
}
private func memberArrived(_ gate: SessionGate) async {
    var spins = 0
    while !(await gate.arrived), spins < 10_000 { await Task.yield(); spins += 1 }
}

// MARK: - 添加账号（4.4）

@MainActor @Test func addSendsAccountsInTapOrderWithoutPriority() async throws {
    let h = MemberHarness()
    let gate = SessionGate()
    h.source.gate = gate
    let task = Task { await h.writer.add([spareAccount, mainAccount], to: enterprise) }
    await memberArrived(gate)
    #expect(h.writer.isSubmitting)
    await gate.open()
    _ = await task.value
    #expect(!h.writer.isSubmitting)
    let request = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 7), GroupMemberAdd(accountID: 4)])
    #expect(h.source.calls == [.batch(groupID: 4, request, generation: h.generation)])
}

@MainActor @Test func fullAddSuccessOffersUndoThatRemovesWhatWasAdded() async throws {
    let h = MemberHarness()
    let result = answer([added(4)], counts: counts(active: 1, total: 2))
    h.source.batchReplies = [.success(result)]
    #expect(await h.writer.add([mainAccount], to: enterprise) == .result(result, usedLegacy: false))
    #expect(h.source.finished.map(\.groupID) == [4] && h.source.finished.first?.counts == result.counts)
    #expect(h.receiptText == "已加入 1 个账号 · 可用 0 → 1" && h.receiptButton == "撤销")
    await h.tapReceipt()
    #expect(h.source.calls.last == .batch(groupID: 4, try GroupMemberBatchRequest(remove: [4]), generation: h.generation))
    #expect(h.receipts.current == nil)
    #expect(h.source.finished.count == 2)
}

@MainActor @Test func addFailuresOfferTheResultsWithTheAccountsAsSent() async throws {
    let h = MemberHarness()
    let partial = answer([added(4), mixed(7)], counts: counts(active: 1, total: 2))
    h.source.batchReplies = [.success(partial)]
    _ = await h.writer.add([mainAccount, spareAccount], to: enterprise)
    #expect(h.receiptText == "已加入 1 个，1 个失败" && h.receiptButton == "查看")
    await h.tapReceipt()
    let request = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 4), GroupMemberAdd(accountID: 7)])
    #expect(h.opened == [GroupBatchOutcome(groupID: 4, groupName: "企业专线", request: request, result: partial,
                                           accounts: [4: GroupBatchAccount(mainAccount), 7: GroupBatchAccount(spareAccount)])])

    h.source.batchReplies = [.success(answer([mixed(4), mixed(7)]))]
    _ = await h.writer.add([mainAccount, spareAccount], to: enterprise)
    #expect(h.receiptText == "加入失败 · 2 个账号没有改动" && h.receiptButton == "查看")
}

/// 0.8: still lost after S5-03's one resend; 重试 sends the same body (the endpoint answers a done change `unchanged`).
@MainActor @Test func lostAddOffersRetryWithTheSameRequest() async throws {
    let h = MemberHarness()
    h.source.batchReplies = [.failure(memberTransport), .success(answer([added(4)], counts: counts(active: 1, total: 2)))]
    #expect(await h.writer.add([mainAccount], to: enterprise) == .unconfirmed)
    #expect(h.source.finished.map(\.counts) == [nil])
    #expect(h.receiptText == "成员改动未确认" && h.receiptButton == "重试" && h.receipts.current?.tone == .caution)
    await h.tapReceipt()
    #expect(h.source.calls.count == 2 && h.source.calls[0] == h.source.calls[1])
    #expect(h.receiptText == "已加入 1 个账号 · 可用 0 → 1")
}

/// The picker is gone by the time 重试 is tapped, so a refusal of the resent add says so in a receipt (as a removal's does).
@MainActor @Test func refusedRetryOfALostAddSaysGroupErrorCopy() async {
    let h = MemberHarness()
    h.source.batchReplies = [.failure(memberTransport), .failure(APIError.server(status: 403, reason: "FORBIDDEN"))]
    #expect(await h.writer.add([mainAccount], to: enterprise) == .unconfirmed)
    await h.tapReceipt()
    #expect(h.source.calls.count == 2)
    #expect(h.receiptText == "你的工作区没有这个权限。" && h.receiptButton == nil && h.receipts.current?.tone == .critical)
}

/// `active_account_count` is omitempty on the group DTO: a group without it had 0 available (00 §6.5), so the add still says “可用 0 → 1”.
@MainActor @Test func targetOfAGroupWithoutTheActiveCountStartsFromZero() async {
    let group = AdminGroup(id: 4, name: "企业专线", activeAccountCount: nil)
    #expect(GroupMemberTarget(group).activeBefore == 0)
    let h = MemberHarness()
    h.source.batchReplies = [.success(answer([added(4)], counts: counts(active: 1, total: 2)))]
    _ = await h.writer.add([mainAccount], to: GroupMemberTarget(group))
    #expect(h.receiptText == "已加入 1 个账号 · 可用 0 → 1")
}

@MainActor @Test func repositoryUnsupportedSwitchesToTheFallbackOnce() async throws {
    let h = MemberHarness()
    h.source.batchReplies = [.failure(repositoryUnsupported)]
    let sent = await h.writer.add([mainAccount], to: enterprise)
    let request = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 4)])
    #expect(h.source.calls == [.batch(groupID: 4, request, generation: h.generation), .legacy(groupID: 4, request, generation: h.generation)])
    #expect(h.source.unsupportedNotes == 1 && h.writer.fellBackToLegacy)
    guard case .result(_, let usedLegacy) = sent else { Issue.record("\(sent)"); return }
    #expect(usedLegacy)
    #expect(h.receiptText == "已加入 1 个账号")
}

@MainActor @Test func withoutMemberBatchGoesStraightToTheFallback() async throws {
    let h = MemberHarness(ScriptedMemberSource(usesBatch: false))
    _ = await h.writer.add([mainAccount], to: enterprise)
    #expect(h.source.calls == [.legacy(groupID: 4, try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 4)]), generation: h.generation)])
    #expect(h.source.unsupportedNotes == 0)
}

/// S5D2a-08: the fallback's PUT would unbind composite groups in simple mode, so nothing goes out one by one.
@MainActor @Test func simpleModeNeverFallsBackToTheFallback() async {
    let unsupported = "服务器暂不支持批量调整成员。"
    let old = MemberHarness(ScriptedMemberSource(usesBatch: false, allowsLegacy: false))
    #expect(await old.writer.add([mainAccount], to: enterprise) == .rejected(unsupported))
    #expect(old.source.calls.isEmpty && old.receipts.current == nil)

    let h = MemberHarness(ScriptedMemberSource(allowsLegacy: false))
    h.source.batchReplies = [.failure(repositoryUnsupported)]
    #expect(await h.writer.remove(mainAccount, from: enterprise, wasAvailable: true) == .rejected(unsupported))
    #expect(h.source.calls.count == 1 && h.source.unsupportedNotes == 1)
    #expect(h.receiptText == unsupported)
}

@MainActor @Test func definiteRefusalOfAnAddComesBackWithoutReceipt() async {
    let h = MemberHarness()
    h.source.batchReplies = [.failure(APIError.server(status: 400, reason: "SIMPLE_MODE_GROUP_NOT_BINDABLE")),
                             .failure(APIError.server(status: 400, reason: "INVALID_ACCOUNT_ID"))]
    #expect(await h.writer.add([mainAccount], to: enterprise) == .rejected("简易模式下不能给组合分组添加账号。"))
    #expect(h.receipts.current == nil && h.source.finished.isEmpty && h.source.calls.count == 1)
    #expect(await h.writer.add([mainAccount], to: enterprise) == .rejected("提交的成员有误，请重试。"))
}

// MARK: - 成员左滑 · 移出（2.4）

@MainActor @Test func removalShowsTheAvailabilityDropAndUndoBringsThePriorityBack() async throws {
    let h = MemberHarness()
    let first = pickAccount(1, "Claude-官方-01")
    h.source.batchReplies = [.success(answer([removed(1, priority: 7)], counts: counts(active: 1, total: 2), groupID: 1))]
    let gate = SessionGate()
    h.source.gate = gate
    let task = Task { await h.writer.remove(first, from: premium, wasAvailable: true) }
    await memberArrived(gate)
    #expect(h.writer.busyAccounts == [1])
    #expect(await h.writer.remove(first, from: premium, wasAvailable: true) == .ignored)
    await gate.open()
    _ = await task.value
    #expect(h.source.calls == [.batch(groupID: 1, try GroupMemberBatchRequest(remove: [1]), generation: h.generation)])
    #expect(h.receiptText == "已移出「Claude-官方-01」 · 可用 2 → 1" && h.receiptButton == "撤销")
    await h.tapReceipt()
    #expect(h.source.calls.last == .batch(groupID: 1, try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 1, priority: 7)]),
                                          generation: h.generation))
    #expect(h.writer.busyAccounts.isEmpty)
}

@MainActor @Test func removingAnUnavailableOrAbsentMemberSaysNoAvailabilityAndUnchangedHasNoUndo() async {
    let h = MemberHarness()
    let limited = pickAccount(3, "Claude-官方-03")
    h.source.batchReplies = [.success(answer([removed(3, priority: 1)], counts: counts(active: 2, total: 2), groupID: 1)),
                             .success(answer([GroupMemberResultItem(accountID: 3, action: .remove, status: .unchanged)], groupID: 1))]
    _ = await h.writer.remove(limited, from: premium, wasAvailable: false)
    #expect(h.receiptText == "已移出「Claude-官方-03」" && h.receiptButton == "撤销")
    _ = await h.writer.remove(limited, from: premium, wasAvailable: false)
    #expect(h.receiptText == "已移出「Claude-官方-03」" && h.receiptButton == nil)
}

@MainActor @Test func refusedRemovalSaysGroupErrorCopy() async {
    let h = MemberHarness()
    h.source.batchReplies = [.failure(APIError.server(status: 403, reason: "FORBIDDEN"))]
    #expect(await h.writer.remove(mainAccount, from: enterprise, wasAvailable: false) == .rejected("你的工作区没有这个权限。"))
    #expect(h.receiptText == "你的工作区没有这个权限。" && h.receiptButton == nil && h.receipts.current?.tone == .critical)
    #expect(h.source.finished.isEmpty)
}

@MainActor @Test func refusedUndoSaysTheUndoDidNotHappen() async {
    let h = MemberHarness()
    h.source.batchReplies = [.success(answer([removed(4, priority: 3)])), .failure(APIError.server(status: 403, reason: "FORBIDDEN"))]
    _ = await h.writer.remove(mainAccount, from: enterprise, wasAvailable: false)
    await h.tapReceipt()
    #expect(h.receiptText == "撤销没有成功：你的工作区没有这个权限。" && h.receiptButton == nil)
}

@MainActor @Test func aMissingGroupIsReportedGone() async {
    for reason in ["GROUP_NOT_FOUND", "RESOURCE_NOT_FOUND"] {
        let h = MemberHarness()
        h.source.batchReplies = [.failure(APIError.server(status: 404, reason: reason))]
        #expect(await h.writer.remove(mainAccount, from: enterprise, wasAvailable: true) == .groupGone("这个分组已删除"))
        #expect(h.source.gone == [4] && h.receiptText == "这个分组已删除")
        #expect(h.source.finished.isEmpty)
    }
}

// MARK: - 会话与只读

@MainActor @Test func anAnswerAfterTheSessionChangedIsDropped() async {
    let h = MemberHarness()
    let gate = SessionGate()
    h.source.gate = gate
    let task = Task { await h.writer.add([mainAccount], to: enterprise) }
    await memberArrived(gate)
    h.source.switchSession()
    await gate.open()
    #expect(await task.value == .ignored)
    #expect(h.receipts.current == nil && h.source.finished.isEmpty && !h.writer.isSubmitting)

    let cancelled = MemberHarness()
    cancelled.source.batchReplies = [.failure(CancellationError())]
    #expect(await cancelled.writer.remove(mainAccount, from: enterprise, wasAvailable: true) == .ignored)
    #expect(cancelled.receipts.current == nil && cancelled.writer.busyAccounts.isEmpty)
}

@MainActor @Test func aReadOnlyTokenSendsNothing() async throws {
    let h = MemberHarness(ScriptedMemberSource(readOnly: true))
    #expect(await h.writer.add([mainAccount], to: enterprise) == .ignored)
    #expect(h.receiptText == AccountActionCopy.readOnly.text)
    #expect(await h.writer.remove(mainAccount, from: enterprise, wasAvailable: true) == .ignored)
    #expect(await h.writer.send(try GroupMemberBatchRequest(remove: [4]), to: 4) == .rejected(AccountActionCopy.readOnly.text))
    #expect(h.source.calls.isEmpty)
}

/// S5-09 and S5-11 send without a receipt; the write still refreshes the group.
@MainActor @Test func sendReportsWithoutAReceipt() async throws {
    let h = MemberHarness()
    let result = answer([added(4)], counts: counts(active: 1, total: 2))
    h.source.batchReplies = [.success(result), .failure(memberTransport)]
    let request = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 4)], confirmMixedChannelRisk: true)
    #expect(await h.writer.send(request, to: 4) == .result(result, usedLegacy: false))
    #expect(await h.writer.send(request, to: 4) == .unconfirmed)
    #expect(h.receipts.current == nil)
    #expect(h.source.finished.map(\.counts) == [result.counts, nil])
    #expect(h.source.calls.first == .batch(groupID: 4, request, generation: h.generation))
}
