import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 50 §0.5, §0.8 and S5D2a-05 / -06: the four group actions, their numbers (R05), receipts, undo, read-back and retries.

private let premium = AdminGroup(id: 1, name: "高级组", platform: "anthropic", status: "active", accountCount: 3)
private let enterprise = AdminGroup(id: 4, name: "企业专线", platform: "openai", subscriptionType: "subscription", accountCount: 1)
private let trial = AdminGroup(id: 6, name: "测试组", platform: "gemini", status: "inactive", accountCount: 1)
private let antigravity = AdminGroup(id: 10, name: "Antigravity 组", platform: "antigravity", accountCount: 0)
private let premiumCopy = AdminGroup(id: 12, name: "高级组 (Copy)", platform: "anthropic", status: "inactive", accountCount: 3)
private let premiumStats = GroupStats(totalAPIKeys: 38, activeAPIKeys: 36, subscriptionsTotal: 0, subscriptionsActive: 0)
private let lostReply = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
private let groupCooldown = Date(timeIntervalSince1970: 1_800_000_010)
private let storeBusy = KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: groupCooldown), key: "k",
                                          actionID: nil, lastError: nil)
private let offline = APIError(kind: .transport, message: "无法连接站点")
private let groupGone = APIError.server(status: 404, reason: "GROUP_NOT_FOUND")
private let keysWithoutNumber = "使用这个分组的 API 密钥会被拒绝（提示“所属分组已删除”），需在用户的 Key 里换分组。"

private func status(_ group: AdminGroup, _ value: String) -> AdminGroup { var row = group; row.status = value; return row }
private func text(_ operation: GroupWriteOperation?) -> String? { operation.map { String(decoding: $0.body, as: UTF8.self) } }

/// Answers from per-call scripts; an empty script answers like a server that applied the write. `events` lists every call in
/// order (the harness adds “key” for each number made). A write whose identity is no longer the session's throws
/// CancellationError, as APIClient does.
@MainActor private final class ScriptedGroupSource: GroupActionSource {
    private(set) var session: GroupWriteSession?
    private(set) var identity = UUID()
    var events: [String] = []
    private(set) var writes: [GroupWriteOperation] = []
    var stats: Result<GroupStats?, any Error> = .success(premiumStats)
    /// Waits for cancellation, as a slow read does.
    var statsHangs = false
    var statsGate: SessionGate?
    var readReplies: [Result<AdminGroup, any Error>] = []
    var updateReplies: [Result<WriteOutcome<AdminGroup>, any Error>] = []
    var deleteReplies: [Result<WriteOutcome<GroupDeleteResult>, any Error>] = []
    var duplicateReplies: [Result<WriteOutcome<AdminGroup>, any Error>] = []
    var gate: SessionGate?
    /// Read as each write arrives, before it answers.
    var probe: (@MainActor () -> String?)?
    private(set) var probed: [String?] = []
    private let known = Dictionary(uniqueKeysWithValues: [premium, enterprise, trial, antigravity].map { ($0.id, $0) })

    init(idempotentWrites: Bool = true, readOnly: Bool = false, readsStats: Bool = true, simpleMode: Bool = false) {
        session = GroupWriteSession(generation: UUID(), serverID: UUID(), siteName: "测试站", idempotentWrites: idempotentWrites,
                                    isReadOnlyToken: readOnly, readsStats: readsStats, isSimpleMode: simpleMode)
    }
    func switchSession() {
        guard let old = session else { return }
        session = GroupWriteSession(generation: UUID(), serverID: old.serverID, siteName: old.siteName, idempotentWrites: old.idempotentWrites,
                                    isReadOnlyToken: old.isReadOnlyToken, readsStats: old.readsStats, isSimpleMode: old.isSimpleMode)
        identity = UUID()
    }

    var groupWriteSession: GroupWriteSession? { session }
    func groupWriteIdentity() async throws -> UUID { identity }
    func fetchGroupStats(id: Int) async throws -> GroupStats? {
        events.append("stats \(id)")
        if let statsGate { await statsGate.wait() }
        if statsHangs { try await Task.sleep(for: .seconds(3600)) }
        return try stats.get()
    }
    func fetchGroup(id: Int) async throws -> AdminGroup {
        events.append("read \(id)")
        guard !readReplies.isEmpty else { throw groupGone }
        return try readReplies.removeFirst().get()
    }
    func sendGroupUpdate(_ operation: GroupWriteOperation, request: GroupUpdateRequest) async throws -> WriteOutcome<AdminGroup> {
        try await admit(operation, "update")
        if !updateReplies.isEmpty { return try updateReplies.removeFirst().get() }
        guard case .update(let id) = operation.kind, let row = known[id], let target = request.status else { throw groupGone }
        return WriteOutcome(value: status(row, target))
    }
    func sendGroupDelete(_ operation: GroupWriteOperation) async throws -> WriteOutcome<GroupDeleteResult> {
        try await admit(operation, "delete")
        return deleteReplies.isEmpty ? WriteOutcome(value: .deleted) : try deleteReplies.removeFirst().get()
    }
    func sendGroupDuplicate(_ operation: GroupWriteOperation) async throws -> WriteOutcome<AdminGroup> {
        try await admit(operation, "duplicate")
        return duplicateReplies.isEmpty ? WriteOutcome(value: premiumCopy) : try duplicateReplies.removeFirst().get()
    }

    private func admit(_ operation: GroupWriteOperation, _ name: String) async throws {
        let target: Int = switch operation.kind {
        case .update(let id), .delete(let id), .duplicate(let id): id
        case .create: 0
        }
        events.append("\(name) \(target)")
        writes.append(operation)
        if let probe { probed.append(probe()) }
        if let gate { await gate.wait() }
        guard operation.identity == identity else { throw CancellationError() }
    }
}

/// GroupStore as the actions see it: the rows and what was done to them.
@MainActor private final class FakeGroupStore: GroupActionStore {
    private(set) var rows: [Int: AdminGroup]
    private(set) var upserts: [Int] = []
    private(set) var removed: [Int] = []
    /// One per refresh after a write: true when the group directory is read again too.
    private(set) var refreshes: [Bool] = []

    init(_ groups: [AdminGroup]) { rows = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) }) }
    func applyOptimistic(_ group: AdminGroup) -> AdminGroup? {
        let previous = rows[group.id]
        rows[group.id] = group
        return previous
    }
    func rollback(_ previous: AdminGroup) { rows[previous.id] = previous }
    func upsert(_ group: AdminGroup) { rows[group.id] = group; upserts.append(group.id) }
    func remove(id: Int) { rows[id] = nil; removed.append(id) }
    func refreshAfterWrite(directory: Bool) { refreshes.append(directory) }
}

/// One GroupActions with its receipts (they stay up: the timer sleeps for an hour). The confirmation's stats wait sleeps for
/// an hour too, or returns at once with `statsTimesOut`; a same-number retry's wait returns at once and is recorded.
@MainActor private final class GroupHarness {
    struct Wait: Equatable { let until: Date; let writes: Int }
    let source: ScriptedGroupSource
    let store: FakeGroupStore
    let receipts = ReceiptCenter(sleep: { try await Task.sleep(for: $0 * 1_000) })
    private(set) var keys: [UUID] = []
    private(set) var opened: [Int] = []
    private(set) var waits: [Wait] = []
    private(set) var actions: GroupActions!

    init(_ source: ScriptedGroupSource = ScriptedGroupSource(), statsTimesOut: Bool = false) {
        let store = FakeGroupStore([premium, enterprise, trial, antigravity])
        let sleep: @Sendable (Duration) async throws -> Void
        if statsTimesOut { sleep = { @Sendable _ in } } else { sleep = { @Sendable in try await Task.sleep(for: $0 * 1_000) } }
        self.source = source
        self.store = store
        actions = GroupActions(source: source, store: { store }, receipts: receipts,
                               openGroup: { [weak self] in self?.opened.append($0) },
                               makeKey: { [weak self] in
                                   let key = UUID()
                                   self?.keys.append(key)
                                   source.events.append("key")
                                   return key
                               },
                               waitUntil: { [weak self] in self?.waits.append(Wait(until: $0, writes: source.writes.count)) },
                               sleep: sleep)
    }
    var receiptText: String? { receipts.current?.text }
    var receiptButton: String? { receipts.current?.action?.title }
    /// 停用分组… then the alert's 停用分组.
    @discardableResult func disable(_ group: AdminGroup) async -> GroupActionOutcome {
        await actions.requestDisable(group)
        guard let prompt = actions.disablePrompt else { return .ignored }
        return await actions.confirmDisable(prompt)
    }
    /// 删除分组… then the confirmation.
    @discardableResult func delete(_ group: AdminGroup, leaving: (@MainActor () -> Void)? = nil) async -> GroupActionOutcome {
        await actions.requestDelete(group)
        guard let prompt = actions.deletePrompt else { return .ignored }
        return await actions.performDelete(prompt, leaving: leaving)
    }
    /// Taps the receipt's button and waits until what it started has finished.
    func tapReceipt(id: Int) async {
        guard let receipt = receipts.current else { return }
        receipts.performAction(id: receipt.id)
        await settle { !self.actions.isRunning(id) }
    }
}

@MainActor private func settle(_ done: @MainActor () -> Bool) async {
    var spins = 0
    while !done(), spins < 10_000 { await Task.yield(); spins += 1 }
}
private func arrived(_ gate: SessionGate) async {
    var spins = 0
    while !(await gate.arrived), spins < 10_000 { await Task.yield(); spins += 1 }
}

// MARK: - 停用 / 启用

@MainActor @Test func disablePromptCarriesActiveKeyCountAndMakesNoKey() async throws {
    let h = GroupHarness()
    let gate = SessionGate()
    h.source.statsGate = gate
    let asking = Task { await h.actions.requestDisable(premium) }
    await arrived(gate)
    #expect(h.actions.isRunning(1))
    await gate.open()
    await asking.value
    #expect(!h.actions.isRunning(1))
    let prompt = try #require(h.actions.disablePrompt)
    #expect(prompt.confirmation.title == "停用「高级组」？")
    #expect(prompt.confirmation.lines == ["站点 测试站", "使用这个分组的 36 个 API 密钥会被拒绝（提示“所属分组已停用”）。可以随时重新启用。"])
    #expect(prompt.confirmation.confirmTitle == "停用分组")
    #expect(h.source.writes.isEmpty && h.keys.isEmpty)
}

@MainActor @Test func disablePromptDropsTheNumberWhenStatsAreMissing() async {
    let plain = "使用这个分组的 API 密钥会被拒绝（提示“所属分组已停用”）。可以随时重新启用。"
    let older = GroupHarness()
    older.source.stats = .success(nil)
    let refused = GroupHarness()
    refused.source.stats = .failure(APIError.server(status: 403, reason: "FORBIDDEN"))
    let slow = GroupHarness(statsTimesOut: true)
    slow.source.statsHangs = true
    let vendor = GroupHarness(ScriptedGroupSource(readsStats: false))
    for h in [older, refused, slow, vendor] {
        await h.actions.requestDisable(premium)
        #expect(h.actions.disablePrompt?.confirmation.lines.last == plain)
        #expect(h.source.writes.isEmpty && h.keys.isEmpty && !h.actions.isRunning(1))
    }
    #expect(!vendor.source.events.contains("stats 1"))
}

@MainActor @Test func disableSendsStatusOnlyUnderTheKeyMadeAtConfirm() async throws {
    let h = GroupHarness()
    let store = h.store
    h.source.probe = { store.rows[1]?.status }
    await h.actions.requestDisable(premium)
    let prompt = try #require(h.actions.disablePrompt)
    #expect(h.keys.isEmpty)
    #expect(await h.actions.confirmDisable(prompt) == .succeeded)
    #expect(h.actions.disablePrompt == nil)
    let write = try #require(h.source.writes.first)
    #expect(h.source.writes.count == 1 && write.kind == .update(groupID: 1))
    #expect(text(write) == #"{"status":"inactive"}"#)
    #expect(write.key == h.keys.first?.uuidString.lowercased() && write.sendsIdempotencyKey)
    #expect(h.source.probed == ["inactive"])
    #expect(h.store.rows[1]?.status == "inactive" && h.store.upserts == [1] && h.store.refreshes == [false])
    #expect(h.receiptText == "已停用「高级组」" && h.receiptButton == "撤销")
    #expect(h.receipts.current?.systemImage == "pause.fill")
}

@MainActor @Test func undoWritesBackUnderANewKeyAndSaysNothing() async {
    let h = GroupHarness()
    await h.disable(premium)
    await h.tapReceipt(id: 1)
    #expect(h.keys.count == 2 && h.keys[0] != h.keys[1])
    #expect(h.source.writes.count == 2 && text(h.source.writes.last) == #"{"status":"active"}"#)
    #expect(h.source.writes.last?.key == h.keys[1].uuidString.lowercased())
    #expect(h.store.rows[1]?.status == "active")
    #expect(h.receipts.current == nil)
}

@MainActor @Test func refusedUndoRollsBackAndSaysSo() async {
    let h = GroupHarness()
    await h.disable(premium)
    h.source.updateReplies = [.failure(APIError.server(status: 403, reason: "FORBIDDEN"))]
    await h.tapReceipt(id: 1)
    #expect(h.store.rows[1]?.status == "inactive")
    #expect(h.receiptText == "撤销没有成功：你的工作区没有这个权限。" && h.receiptButton == nil)
}

@MainActor @Test func enableRunsAtOnceWithUndo() async {
    let h = GroupHarness()
    #expect(await h.actions.enable(trial) == .succeeded)
    #expect(h.actions.disablePrompt == nil && !h.source.events.contains("stats 6"))
    #expect(text(h.source.writes.first) == #"{"status":"active"}"#)
    #expect(h.store.rows[6]?.status == "active")
    #expect(h.receiptText == "已启用「测试组」" && h.receiptButton == "撤销")
}

@MainActor @Test func refusedStatusRollsBackWithFixedWording() async {
    let h = GroupHarness()
    h.source.updateReplies = [.failure(APIError.server(status: 403, reason: "FORBIDDEN"))]
    #expect(await h.disable(premium) == .failed)
    #expect(h.store.rows[1]?.status == "active" && h.store.refreshes.isEmpty)
    #expect(h.receiptText == "停用没有成功：你的工作区没有这个权限。" && h.receiptButton == nil)
    #expect(!h.source.events.contains("read 1") && h.source.writes.count == 1)

    let gone = GroupHarness()
    gone.source.updateReplies = [.failure(groupGone)]
    #expect(await gone.disable(premium) == .gone)
    #expect(gone.store.rows[1] == nil && gone.store.removed == [1])
    #expect(gone.receiptText == "停用没有成功：这个分组已删除")
}

/// Simple mode and a vendor without group_ops drop the field and still answer 200.
@MainActor @Test func acceptedReplyWithOldStatusIsNotASuccess() async {
    let h = GroupHarness()
    h.source.updateReplies = [.success(WriteOutcome(value: premium))]
    #expect(await h.disable(premium) == .notApplied)
    #expect(h.store.rows[1]?.status == "active")
    #expect(h.receiptText == "停用没有生效：服务器没有接受这项修改" && h.receiptButton == nil)
}

@MainActor @Test func unconfirmedStatusReadsBackOnceAndSettles() async {
    let h = GroupHarness()
    h.source.updateReplies = [.failure(lostReply)]
    h.source.readReplies = [.success(status(premium, "inactive"))]
    #expect(await h.disable(premium) == .succeeded)
    #expect(h.source.writes.count == 1 && h.source.events.contains("read 1"))
    #expect(h.store.rows[1]?.status == "inactive")
    #expect(h.receiptText == "已停用「高级组」" && h.receiptButton == "撤销")
}

@MainActor @Test func unconfirmedStatusOffersTheSameNumber() async {
    let h = GroupHarness()
    h.source.updateReplies = [.failure(lostReply)]
    h.source.readReplies = [.success(premium)]
    #expect(await h.disable(premium) == .unconfirmed)
    #expect(h.store.rows[1]?.status == "active")
    #expect(h.receiptText == "停用结果未确认，可用同一编号重试" && h.receiptButton == "用同一编号重试")
    await h.tapReceipt(id: 1)
    #expect(h.source.writes.count == 2 && h.source.writes[1] == h.source.writes[0])
    #expect(h.keys.count == 1)
    #expect(h.receiptText == "已停用「高级组」")
}

@MainActor @Test func storeUnavailableRetryWaitsForTheCooldown() async {
    let h = GroupHarness()
    h.source.updateReplies = [.failure(storeBusy)]
    h.source.readReplies = [.success(premium)]
    #expect(await h.disable(premium) == .unconfirmed)
    #expect(h.receiptText == "停用没有生效：服务器暂时无法受理，稍后用同一编号重试" && h.receiptButton == "用同一编号重试")
    await h.tapReceipt(id: 1)
    #expect(h.waits == [GroupHarness.Wait(until: groupCooldown, writes: 1)])
    #expect(h.source.writes.count == 2 && h.source.writes[1] == h.source.writes[0])
}

@MainActor @Test func unkeyedUnconfirmedOffersAPlainRetry() async {
    let h = GroupHarness(ScriptedGroupSource(idempotentWrites: false))
    h.source.updateReplies = [.failure(offline)]
    h.source.readReplies = [.success(premium)]
    #expect(await h.disable(premium) == .notApplied)
    #expect(h.source.writes.first?.sendsIdempotencyKey == false)
    #expect(h.receiptText == "停用没有生效，可以重试" && h.receiptButton == "重试")
    await h.tapReceipt(id: 1)
    #expect(h.source.writes.count == 2 && h.source.writes[1].key != h.source.writes[0].key)
    #expect(text(h.source.writes[1]) == #"{"status":"inactive"}"#)
    #expect(h.receiptText == "已停用「高级组」")
}

@MainActor @Test func failedReadBackOffersCheck() async {
    let h = GroupHarness()
    h.source.updateReplies = [.failure(lostReply)]
    h.source.readReplies = [.failure(offline), .success(status(premium, "inactive"))]
    #expect(await h.disable(premium) == .unconfirmed)
    #expect(h.store.rows[1]?.status == "active")
    #expect(h.receiptText == "停用结果未确认，请刷新核对后再操作" && h.receiptButton == "核对")
    await h.tapReceipt(id: 1)
    #expect(h.source.writes.count == 1)
    #expect(h.receiptText == "已停用「高级组」")

    let gone = GroupHarness()
    gone.source.updateReplies = [.failure(lostReply)]
    gone.source.readReplies = [.failure(groupGone)]
    #expect(await gone.disable(premium) == .gone)
    #expect(gone.store.removed == [1] && gone.receiptText == "停用没有成功：这个分组已删除")
}

// MARK: - 复制

@MainActor @Test func duplicateAlwaysKeyedUpsertsCopyAndOffersView() async throws {
    let h = GroupHarness(ScriptedGroupSource(idempotentWrites: false))
    #expect(await h.actions.duplicate(premium) == .succeeded)
    let write = try #require(h.source.writes.first)
    #expect(write.kind == .duplicate(sourceGroupID: 1) && write.sendsIdempotencyKey && write.body.isEmpty)
    #expect(write.key == h.keys.first?.uuidString.lowercased())
    #expect(h.store.rows[12] == premiumCopy && h.store.refreshes == [true])
    #expect(h.receiptText == "已复制为「高级组 (Copy)」 · 停用中 · 3 个成员账号" && h.receiptButton == "查看")
    h.receipts.performAction(id: try #require(h.receipts.current).id)
    #expect(h.opened == [12])

    let unknown = GroupHarness()
    var bare = premiumCopy
    bare.accountCount = nil
    unknown.source.duplicateReplies = [.success(WriteOutcome(value: bare))]
    await unknown.actions.duplicate(premium)
    #expect(unknown.receiptText == "已复制为「高级组 (Copy)」 · 停用中 · 0 个成员账号")
}

@MainActor @Test func recoveredOrReplayedDuplicateIsASuccess() async {
    for outcome in [WriteOutcome(value: premiumCopy, recovered: true), WriteOutcome(value: premiumCopy, replayed: true)] {
        let h = GroupHarness()
        h.source.duplicateReplies = [.success(outcome)]
        #expect(await h.actions.duplicate(premium) == .succeeded)
        #expect(h.store.rows[12] == premiumCopy && !h.source.events.contains("read 1"))
        #expect(h.receiptButton == "查看")
    }
}

/// The backend reads the copy back after committing it, so a 500 may follow a copy that exists (S5D2a-06).
@MainActor @Test func duplicateServerErrorRefreshesAndOffersTheSameNumber() async {
    let h = GroupHarness()
    h.source.duplicateReplies = [.failure(APIError.server(status: 500, reason: nil))]
    #expect(await h.actions.duplicate(premium) == .unconfirmed)
    #expect(h.store.refreshes == [true] && h.store.upserts.isEmpty)
    #expect(h.receiptText == "复制结果未确认，已刷新列表，请核对是否已有副本" && h.receiptButton == "用同一编号重试")
    await h.tapReceipt(id: 1)
    #expect(h.source.writes.count == 2 && h.source.writes[1] == h.source.writes[0])
    #expect(h.receiptText == "已复制为「高级组 (Copy)」 · 停用中 · 3 个成员账号")

    let busy = GroupHarness()
    busy.source.duplicateReplies = [.failure(storeBusy)]
    #expect(await busy.actions.duplicate(premium) == .unconfirmed)
    #expect(busy.receiptText == "复制没有生效：服务器暂时无法受理，稍后用同一编号重试")
    await busy.tapReceipt(id: 1)
    #expect(busy.waits == [GroupHarness.Wait(until: groupCooldown, writes: 1)] && busy.source.writes.count == 2)
}

// MARK: - 删除

@MainActor @Test func deletePromptListsOnlyNonZeroConsequences() async throws {
    let h = GroupHarness()
    h.source.stats = .success(GroupStats(totalAPIKeys: 6, activeAPIKeys: 6, subscriptionsTotal: 15, subscriptionsActive: 12))
    await h.actions.requestDelete(enterprise)
    let prompt = try #require(h.actions.deletePrompt)
    #expect(prompt.siteName == "测试站" && prompt.group == enterprise)
    #expect(prompt.consequences == ["使用这个分组的 6 个 API 密钥会被拒绝（提示“所属分组已删除”），需在用户的 Key 里换分组。",
                                    "删除 15 条订阅记录（生效中 12 条）。", "1 个成员账号移出分组，账号本身保留。"])
    #expect(h.keys.isEmpty && h.source.writes.isEmpty)

    let older = GroupHarness()
    older.source.stats = .success(nil)
    await older.actions.requestDelete(enterprise)
    #expect(older.actions.deletePrompt?.consequences == [keysWithoutNumber, "删除这个分组的全部订阅记录。", "1 个成员账号移出分组，账号本身保留。"])

    let simple = GroupHarness(ScriptedGroupSource(readsStats: false, simpleMode: true))
    await simple.actions.requestDelete(enterprise)
    #expect(simple.actions.deletePrompt?.consequences == [keysWithoutNumber, "删除这个分组的全部订阅记录。"])
    #expect(!simple.source.events.contains("stats 4"))

    let empty = GroupHarness()
    empty.source.stats = .success(GroupStats(totalAPIKeys: 0, activeAPIKeys: 0, subscriptionsTotal: 0, subscriptionsActive: 0))
    await empty.actions.requestDelete(antigravity)
    #expect(empty.actions.deletePrompt?.consequences == [])
}

@MainActor @Test func deleteFromDetailLeavesBeforeSending() async {
    let h = GroupHarness()
    let source = h.source
    #expect(await h.delete(premium, leaving: { source.events.append("leave") }) == .succeeded)
    #expect(Array(h.source.events.suffix(3)) == ["leave", "key", "delete 1"])
    let list = GroupHarness()
    #expect(await list.delete(premium) == .succeeded)
    #expect(list.source.writes.first?.kind == .delete(groupID: 1))
}

@MainActor @Test func deletedOrAlreadyGoneRemovesEverywhere() async {
    for reply in [GroupDeleteResult.deleted, .alreadyGone] {
        let h = GroupHarness()
        h.source.deleteReplies = [.success(WriteOutcome(value: reply))]
        #expect(await h.delete(antigravity) == .succeeded)
        #expect(h.store.rows[10] == nil && h.store.removed == [10] && h.store.refreshes == [true])
        #expect(h.receiptText == "已删除分组「Antigravity 组」" && h.receipts.current?.systemImage == "trash" && h.receiptButton == nil)
    }
}

@MainActor @Test func notEmptyDeleteKeepsTheGroup() async {
    let h = GroupHarness()
    h.source.deleteReplies = [.failure(APIError.server(status: 409, reason: "GROUP_NOT_EMPTY"))]
    #expect(await h.delete(premium) == .failed)
    #expect(h.store.rows[1] != nil && h.store.removed.isEmpty)
    #expect(h.receiptText == "删除没有成功：分组里还有账号，先移出成员再删除。")
}

@MainActor @Test func unconfirmedDeleteDecidesBy404() async {
    let h = GroupHarness()
    h.source.deleteReplies = [.failure(lostReply)]
    h.source.readReplies = [.failure(groupGone)]
    #expect(await h.delete(premium) == .succeeded)
    #expect(h.store.removed == [1] && h.receiptText == "已删除分组「高级组」")

    let still = GroupHarness()
    still.source.deleteReplies = [.failure(lostReply)]
    still.source.readReplies = [.success(premium)]
    #expect(await still.delete(premium) == .unconfirmed)
    #expect(still.store.removed.isEmpty)
    #expect(still.receiptText == "删除结果未确认，可用同一编号重试" && still.receiptButton == "用同一编号重试")
    await still.tapReceipt(id: 1)
    #expect(still.source.writes.count == 2 && still.source.writes[1] == still.source.writes[0])
    #expect(still.store.removed == [1] && still.receiptText == "已删除分组「高级组」")
}

// MARK: - 守卫

@MainActor @Test func groupReadOnlyTokenSendsNothing() async {
    let h = GroupHarness(ScriptedGroupSource(readOnly: true))
    await h.actions.requestDisable(premium)
    #expect(h.actions.disablePrompt == nil)
    #expect(await h.actions.enable(trial) == .failed)
    #expect(await h.actions.duplicate(premium) == .failed)
    await h.actions.requestDelete(premium)
    #expect(h.actions.deletePrompt == nil)
    let generation = h.source.session?.generation ?? UUID()
    let disable = GroupDisablePrompt(id: UUID(), group: premium, confirmation: GroupCopy.disableConfirmation(name: "高级组", siteName: "测试站",
                                     activeAPIKeys: nil), generation: generation)
    #expect(await h.actions.confirmDisable(disable) == .failed)
    let delete = GroupDeletePrompt(id: UUID(), group: premium, siteName: "测试站", consequences: [], generation: generation)
    #expect(await h.actions.performDelete(delete, leaving: nil) == .failed)
    #expect(h.source.events.isEmpty && h.source.writes.isEmpty && h.keys.isEmpty)
    #expect(h.receiptText == "当前管理访问令牌只读，不能执行此操作")
}

@MainActor @Test func busyGroupAndStaleSessionAreIgnored() async {
    let h = GroupHarness()
    let gate = SessionGate()
    h.source.gate = gate
    let first = Task { await h.actions.enable(trial) }
    await arrived(gate)
    #expect(h.store.rows[6]?.status == "active")
    #expect(await h.actions.enable(trial) == .ignored)
    #expect(h.source.writes.count == 1)
    h.source.switchSession()
    await gate.open()
    #expect(await first.value == .ignored)
    #expect(h.receipts.current == nil && h.store.rows[6]?.status == "inactive" && h.store.upserts.isEmpty)

    let later = GroupHarness()
    await later.actions.enable(trial)
    later.source.switchSession()
    await later.tapReceipt(id: 6)
    #expect(later.source.writes.count == 1)
}

/// A prompt from an earlier session is not sent.
@MainActor @Test func staleConfirmationIsIgnored() async throws {
    let h = GroupHarness()
    await h.actions.requestDisable(premium)
    let prompt = try #require(h.actions.disablePrompt)
    h.source.switchSession()
    #expect(await h.actions.confirmDisable(prompt) == .ignored)
    #expect(h.source.writes.isEmpty && h.keys.isEmpty)
}

@MainActor @Test func newKeyRefusalAsksToActAgain() async throws {
    let h = GroupHarness()
    h.source.updateReplies = [.failure(KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil))]
    #expect(await h.disable(premium) == .reconfirm)
    #expect(h.store.rows[1]?.status == "active")
    #expect(h.receiptText == "停用没有执行，请重新操作" && h.receiptButton == "重试")
    h.actions.disablePrompt = nil
    h.receipts.performAction(id: try #require(h.receipts.current).id)
    await settle { h.actions.disablePrompt != nil }
    #expect(h.actions.disablePrompt?.group == premium && h.source.writes.count == 1)

    let enabling = GroupHarness()
    enabling.source.updateReplies = [.failure(KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil))]
    #expect(await enabling.actions.enable(trial) == .reconfirm)
    await enabling.tapReceipt(id: 6)
    #expect(enabling.source.writes.count == 2 && enabling.source.writes[1].key != enabling.source.writes[0].key)
    #expect(enabling.receiptText == "已启用「测试组」")
}
