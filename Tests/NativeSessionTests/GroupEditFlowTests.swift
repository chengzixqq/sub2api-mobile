import Foundation
import Synchronization
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 50 §3.4–§3.5, S5D2a-06 (S5-10): the group sheet's writes — when it asks, when the number is made (R05), refusals, a lost
// result read back once and never sent again by itself, the same number again, receipts and the list.

private func amount(_ raw: String) -> Decimal { Decimal(string: raw)! }
private let premium = AdminGroup(id: 1, name: "高级组", description: "", platform: "anthropic", rateMultiplier: amount("0.8"), rpmLimit: 0)
private let standardGroup = AdminGroup(id: 2, name: "标准组", description: "", platform: "openai", rateMultiplier: amount("0.8"), rpmLimit: 600)
private let nightly = AdminGroup(id: 12, name: "Claude 夜间组", description: "", platform: "anthropic", rateMultiplier: 1, rpmLimit: 0, sortOrder: 12)
private let premiumKeys = GroupStats(totalAPIKeys: 38, activeAPIKeys: 36, subscriptionsTotal: 0, subscriptionsActive: 0)
private let everyField = Set(GroupPermissions.Field.allCases)
private let lostReply = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
private let editClock = Date(timeIntervalSince1970: 1_800_000_000)
private let offline = APIError(kind: .transport, message: "无法连接站点")
private let missing = APIError.server(status: 404, reason: "GROUP_NOT_FOUND")

private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
private func renamed(_ group: AdminGroup, _ name: String) -> AdminGroup { var row = group; row.name = name; return row }
private func context(known: Set<Int> = [1, 2], editable: Set<GroupPermissions.Field> = everyField) -> GroupEditContext {
    GroupEditContext(editable: editable, knownGroupIDs: known, catalog: nil, now: editClock)
}
private func creating(_ name: String = "Claude 夜间组", exclusive: Bool = false) -> GroupEditDraft {
    var draft = GroupEditDraft.creating()
    draft.name = name
    draft.isExclusive = exclusive
    return draft
}
private func editing(_ group: AdminGroup, _ change: (inout GroupEditDraft) -> Void) -> GroupEditDraft {
    var draft = GroupEditDraft(editing: group)
    change(&draft)
    return draft
}

/// Answers from per-call scripts; an empty write script answers like a server that applied the write. A write whose identity
/// is no longer the session's throws CancellationError, as APIClient does.
@MainActor private final class ScriptedEditSource: GroupEditSource {
    private(set) var session: GroupWriteSession?
    private(set) var identity = UUID()
    private(set) var identityReads = 0
    private(set) var writes: [GroupWriteOperation] = []
    private(set) var statsReads = 0
    private(set) var reads = 0
    private(set) var searches: [String] = []
    var stats: GroupStats? = premiumKeys
    var statsHangs = false
    var writeReplies: [Result<WriteOutcome<AdminGroup>, any Error>] = []
    var readReplies: [Result<AdminGroup, any Error>] = []
    var searchReplies: [Result<[AdminGroup], any Error>] = []
    var gate: SessionGate?

    init(idempotentWrites: Bool = true, readOnly: Bool = false, readsStats: Bool = true) {
        session = GroupWriteSession(generation: UUID(), serverID: UUID(), siteName: "演示站", idempotentWrites: idempotentWrites,
                                    isReadOnlyToken: readOnly, readsStats: readsStats, isSimpleMode: false)
    }
    func switchSession() {
        guard let old = session else { return }
        session = GroupWriteSession(generation: UUID(), serverID: old.serverID, siteName: old.siteName, idempotentWrites: old.idempotentWrites,
                                    isReadOnlyToken: old.isReadOnlyToken, readsStats: old.readsStats, isSimpleMode: old.isSimpleMode)
    }

    var groupWriteSession: GroupWriteSession? { session }
    func groupWriteIdentity() async throws -> UUID { identityReads += 1; return identity }
    func fetchGroupStats(id: Int) async throws -> GroupStats? {
        statsReads += 1
        if statsHangs { try await Task.sleep(for: .seconds(3600)) }
        return stats
    }
    func fetchGroup(id: Int) async throws -> AdminGroup {
        reads += 1
        guard !readReplies.isEmpty else { throw offline }
        return try readReplies.removeFirst().get()
    }
    func sendGroupWrite(_ intent: GroupWriteDraft.Intent, operation: GroupWriteOperation, onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<AdminGroup> {
        writes.append(operation)
        if let gate { await gate.wait() }
        guard operation.identity == identity else { throw CancellationError() }
        if !writeReplies.isEmpty { return try writeReplies.removeFirst().get() }
        switch intent {
        case .create(let request): return WriteOutcome(value: AdminGroup(id: 12, name: request.name, platform: request.platform, isExclusive: request.isExclusive))
        case .update(let id, let request): return WriteOutcome(value: Self.applying(request, to: [premium, standardGroup].first { $0.id == id }!))
        }
    }
    func searchGroups(name: String, platform: String) async throws -> [AdminGroup] {
        searches.append("\(name)|\(platform)")
        guard !searchReplies.isEmpty else { return [] }
        return try searchReplies.removeFirst().get()
    }
    private static func applying(_ request: GroupUpdateRequest, to group: AdminGroup) -> AdminGroup {
        var row = group
        if let name = request.name { row.name = name }
        if let rate = request.rateMultiplier { row.rateMultiplier = rate }
        if let status = request.status { row.status = status }
        if let rpm = request.rpmLimit { row.rpmLimit = rpm }
        if let exclusive = request.isExclusive { row.isExclusive = exclusive }
        return row
    }
}

/// GroupStore as the sheet writes it.
@MainActor private final class EditFakeStore: GroupActionStore {
    private(set) var upserts: [AdminGroup] = []
    private(set) var removed: [Int] = []
    private(set) var refreshes: [Bool] = []
    func applyOptimistic(_ group: AdminGroup) -> AdminGroup? { nil }
    func rollback(_ previous: AdminGroup) {}
    func upsert(_ group: AdminGroup) { upserts.append(group) }
    func remove(id: Int) { removed.append(id) }
    func refreshAfterWrite(directory: Bool) { refreshes.append(directory) }
}

private final class PauseLog: Sendable {
    let values = Mutex<[Duration]>([])
    var all: [Duration] { values.withLock { $0 } }
}

/// One flow with its receipts (they stay up). The stats wait sleeps for an hour unless `statsTimesOut`; every other pause (a
/// cooldown) returns at once and is logged.
@MainActor private final class EditHarness {
    let source: ScriptedEditSource
    let store = EditFakeStore()
    let receipts = ReceiptCenter(sleep: { try await Task.sleep(for: $0 * 1_000) })
    let pauses = PauseLog()
    private(set) var keys: [UUID] = []
    private(set) var flow: GroupEditFlow!

    /// Opened results pages (S5-11).
    private(set) var opened: [GroupBatchOutcome] = []

    init(_ original: AdminGroup?, source: ScriptedEditSource = ScriptedEditSource(), statsTimesOut: Bool = false, members: EditMemberSource? = nil) {
        self.source = source
        let store = store, pauses = pauses, receipts = receipts
        let writer = members.map { GroupMemberWriter(source: $0, receipts: receipts, openResults: { _ in }) }
        flow = GroupEditFlow(original: original, source: source, store: { store }, receipts: receipts,
                             makeKey: { [weak self] in
                                 let key = UUID()
                                 self?.keys.append(key)
                                 return key
                             },
                             deviceNow: { editClock },
                             pause: { duration in
                                 if duration == GroupActions.statsWait {
                                     if !statsTimesOut { try await Task.sleep(for: .seconds(3600)) }
                                     return
                                 }
                                 pauses.values.withLock { $0.append(duration) }
                             },
                             memberWriter: writer, openResults: { [weak self] in self?.opened.append($0) })
    }
    var receiptText: String? { receipts.current?.text }
    var bodies: [String] { source.writes.map { text($0.body) } }
    /// 创建 / 保存, then the confirmation's button when it asks.
    func save(_ draft: GroupEditDraft, context: GroupEditContext = context()) async {
        await flow.submit(draft, context: context)
        if flow.prompt != nil { await confirm() }
    }
    func confirm() async {
        flow.confirm()
        await flow.sending?.value
    }
    var unconfirmed: GroupEditUnconfirmed? {
        if case .unconfirmed(let state) = flow.phase { state } else { nil }
    }
}

// MARK: - 新建

@MainActor @Test func publicCreateAsksFirstAndMakesTheKeyOnConfirm() async throws {
    let harness = EditHarness(nil)
    await harness.flow.submit(creating(), context: context())
    let prompt = try #require(harness.flow.prompt)
    #expect(prompt.confirmation.title == "创建公开分组「Claude 夜间组」？" && prompt.confirmation.confirmTitle == "仍然创建")
    #expect(prompt.confirmation.lines.first == "站点 演示站 · Anthropic · 费率倍数 ×1.0")
    #expect(harness.keys.isEmpty && harness.source.writes.isEmpty && harness.flow.locksForm)
    await harness.confirm()
    #expect(harness.keys.count == 1 && harness.source.writes.map(\.id) == harness.keys)
    #expect(harness.source.writes.first?.sendsIdempotencyKey == true)
    #expect(harness.store.upserts.map(\.id) == [12] && harness.store.refreshes == [true])
    #expect(harness.receiptText == "已创建「Claude 夜间组」" && harness.flow.isFinished)
}

@MainActor @Test func exclusiveCreateSendsAtOnceWithAKeyMadeOnTap() async {
    let harness = EditHarness(nil)
    harness.source.writeReplies = [.success(WriteOutcome(value: nightly, replayed: true))]
    await harness.flow.submit(creating(exclusive: true), context: context())
    #expect(harness.flow.prompt == nil && harness.keys.count == 1 && harness.source.writes.map(\.id) == harness.keys)
    #expect(harness.flow.isFinished && harness.store.refreshes == [true] && harness.receiptText == "已创建「Claude 夜间组」")
}

@MainActor @Test func cancellingTheConfirmationSendsNothing() async {
    let harness = EditHarness(nil)
    await harness.flow.submit(creating(), context: context())
    harness.flow.cancelConfirmation()
    #expect(harness.flow.phase == .editing && harness.source.writes.isEmpty && harness.keys.isEmpty)
    await harness.save(creating())
    #expect(harness.keys.count == 1 && harness.source.writes.count == 1 && harness.flow.isFinished)
}

// MARK: - 编辑

@MainActor @Test func renameOnlySavesWithoutAsking() async {
    let harness = EditHarness(standardGroup)
    await harness.flow.submit(editing(standardGroup) { $0.name = "标准组 B" }, context: context())
    #expect(harness.source.statsReads == 0 && harness.keys.count == 1)
    #expect(harness.bodies == [#"{"name":"标准组 B"}"#])
    #expect(harness.receiptText == "已保存「标准组 B」" && harness.store.upserts.map(\.name) == ["标准组 B"] && harness.flow.isFinished)
}

@MainActor @Test func riskyEditAsksWithLinesAndDisableReadsActiveKeysWithinTwoSeconds() async throws {
    let rate = EditHarness(premium)
    await rate.flow.submit(editing(premium) { $0.stepRate(up: true) }, context: context())
    let ratePrompt = try #require(rate.flow.prompt).confirmation
    #expect(ratePrompt.lines.contains("费率倍数 ×0.8 → ×0.9") && ratePrompt.lines.contains("此后的请求按新倍率计费，已产生的记录不变。"))
    #expect(ratePrompt.confirmTitle == "保存修改" && rate.source.statsReads == 0 && rate.keys.isEmpty)

    let disable = EditHarness(premium)
    await disable.flow.submit(editing(premium) { $0.isActive = false }, context: context())
    #expect(try #require(disable.flow.prompt).confirmation.lines.contains("停用分组（36 个 API 密钥会被拒绝）"))
    #expect(disable.source.statsReads == 1)

    let slowSource = ScriptedEditSource()
    slowSource.statsHangs = true
    let slow = EditHarness(premium, source: slowSource, statsTimesOut: true)
    await slow.flow.submit(editing(premium) { $0.isActive = false }, context: context())
    #expect(try #require(slow.flow.prompt).confirmation.lines.contains("停用分组（API 密钥会被拒绝）"))

    let vendor = EditHarness(premium, source: ScriptedEditSource(readsStats: false))
    await vendor.flow.submit(editing(premium) { $0.isActive = false }, context: context())
    #expect(try #require(vendor.flow.prompt).confirmation.lines.contains("停用分组（API 密钥会被拒绝）"))
    #expect(vendor.source.statsReads == 0)
}

// MARK: - 失败

@MainActor @Test func groupExistsMarksTheNameAndKeepsTheSheet() async {
    let harness = EditHarness(nil)
    harness.source.writeReplies = [.failure(APIError.server(status: 409, reason: "GROUP_EXISTS"))]
    await harness.save(creating("高级组 X", exclusive: true))
    #expect(harness.flow.phase == .failed(.nameTaken) && harness.flow.rejectedNames == ["高级组 X"])
    #expect(harness.flow.failureMessage == nil && !harness.flow.isFinished && harness.receiptText == nil && !harness.flow.locksForm)
    harness.flow.draftChanged()
    #expect(harness.flow.phase == .editing)
    await harness.save(creating("高级组 Y", exclusive: true))
    #expect(harness.keys.count == 2 && harness.source.writes.map(\.id) == harness.keys && harness.flow.isFinished)
}

@MainActor @Test func definiteRefusalShowsFixedCopyAndTheNextSaveUsesANewKey() async {
    for status in [400, 403, 422] {
        let refusal = APIError.server(status: status, reason: status == 403 ? "FORBIDDEN" : "VALIDATION_ERROR")
        let harness = EditHarness(standardGroup)
        harness.source.writeReplies = [.failure(refusal)]
        await harness.save(editing(standardGroup) { $0.name = "标准组 C" })
        #expect(harness.flow.phase == .failed(.message(GroupErrorCopy.resolve(refusal, context: .write).message)), "\(status)")
        #expect(!harness.flow.locksForm && !harness.flow.isFinished)
        await harness.save(editing(standardGroup) { $0.name = "标准组 D" })
        #expect(harness.keys.count == 2 && Set(harness.keys).count == 2 && harness.flow.isFinished)
    }
    let conflict = EditHarness(standardGroup)
    conflict.source.writeReplies = [.failure(KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil))]
    await conflict.save(editing(standardGroup) { $0.name = "标准组 E" })
    #expect(conflict.flow.phase == .failed(.message(GroupEditCopy.reconfirm(isNew: false))))
    #expect(GroupEditCopy.reconfirm(isNew: false) == "请求没有执行，请重新保存。")
}

@MainActor @Test func editOfADeletedGroupLocksTheForm() async {
    let harness = EditHarness(standardGroup)
    harness.source.writeReplies = [.failure(missing)]
    await harness.save(editing(standardGroup) { $0.name = "标准组 F" })
    #expect(harness.flow.phase == .failed(.gone) && harness.flow.failureMessage == "这个分组已删除")
    #expect(harness.store.removed == [2] && harness.flow.locksForm)
    harness.flow.draftChanged()
    await harness.save(editing(standardGroup) { $0.name = "标准组 G" })
    #expect(harness.source.writes.count == 1)
}

// MARK: - 结果不明

@MainActor @Test func keyedUnknownResultNeverResendsByItself() async throws {
    let harness = EditHarness(standardGroup)
    harness.source.writeReplies = [.failure(lostReply)]
    harness.source.readReplies = [.success(standardGroup)]
    await harness.save(editing(standardGroup) { $0.name = "标准组 H" })
    let state = try #require(harness.unconfirmed)
    #expect(state.keyed && state.text.contains("可以核对，或用同一编号重试") && state.check == .differs)
    #expect(harness.source.writes.count == 1 && harness.flow.locksForm && harness.flow.isUnconfirmed && !harness.flow.isFinished)
}

@MainActor @Test func unknownResultReadsBackOnceByItself() async throws {
    let edit = EditHarness(standardGroup)
    edit.source.writeReplies = [.failure(lostReply)]
    edit.source.readReplies = [.success(renamed(standardGroup, "标准组 I"))]
    await edit.save(editing(standardGroup) { $0.name = "标准组 I" })
    #expect(edit.source.reads == 1 && edit.source.writes.count == 1)
    #expect(edit.receiptText == "已保存「标准组 I」" && edit.flow.isFinished && edit.store.upserts.map(\.name) == ["标准组 I"])

    let create = EditHarness(nil)
    create.source.writeReplies = [.failure(lostReply)]
    await create.save(creating(exclusive: true))
    #expect(create.source.searches == ["Claude 夜间组|anthropic"] && create.source.writes.count == 1)
    #expect(try #require(create.unconfirmed).check == .notFound)
}

@MainActor @Test func serverErrorIsUnconfirmed() async throws {
    let harness = EditHarness(standardGroup)
    harness.source.writeReplies = [.failure(APIError.server(status: 500, reason: "INTERNAL_ERROR"))]
    harness.source.readReplies = [.success(standardGroup)]
    await harness.save(editing(standardGroup) { $0.name = "标准组 J" })
    let state = try #require(harness.unconfirmed)
    #expect(state.keyed && state.text == KeyedWriteFailure.unconfirmedMessage && harness.source.writes.count == 1)
}

@MainActor @Test func retrySameKeySendsTheSameNumberAndBytesAfterTheCooldown() async throws {
    let harness = EditHarness(standardGroup)
    harness.source.writeReplies = [.failure(lostReply)]
    harness.source.readReplies = [.success(standardGroup)]
    await harness.save(editing(standardGroup) { $0.name = "标准组 K" })
    await harness.flow.retrySameKey()
    #expect(harness.source.writes.count == 2 && harness.source.writes[0] == harness.source.writes[1] && harness.keys.count == 1)
    #expect(harness.receiptText == "已保存「标准组 K」" && harness.flow.isFinished && harness.pauses.all.isEmpty)

    let busy = EditHarness(standardGroup)
    let cooldown = editClock.addingTimeInterval(10)
    busy.source.writeReplies = [.failure(KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: cooldown), key: "k",
                                                           actionID: nil, lastError: nil))]
    busy.source.readReplies = [.success(standardGroup)]
    await busy.save(editing(standardGroup) { $0.name = "标准组 L" })
    #expect(try #require(busy.unconfirmed).retryNotBefore == cooldown)
    await busy.flow.retrySameKey()
    #expect(busy.pauses.all == [.seconds(10)] && busy.source.writes.count == 2 && busy.source.writes[0] == busy.source.writes[1])

    let unkeyed = EditHarness(standardGroup, source: ScriptedEditSource(idempotentWrites: false))
    unkeyed.source.writeReplies = [.failure(offline)]
    unkeyed.source.readReplies = [.failure(offline)]
    await unkeyed.save(editing(standardGroup) { $0.name = "标准组 M" })
    #expect(try #require(unkeyed.unconfirmed).keyed == false)
    await unkeyed.flow.retrySameKey()
    #expect(unkeyed.source.writes.count == 1)
}

@MainActor @Test func reconcileEditSettlesByComparingSentFields() async throws {
    let harness = EditHarness(standardGroup)
    harness.source.writeReplies = [.failure(lostReply)]
    harness.source.readReplies = [.success(standardGroup), .failure(offline), .failure(missing)]
    await harness.save(editing(standardGroup) { $0.name = "标准组 N" })
    #expect(try #require(harness.unconfirmed).check == .differs)
    await harness.flow.reconcile()
    #expect(try #require(harness.unconfirmed).check == .failed)
    await harness.flow.reconcile()
    #expect(harness.flow.phase == .failed(.gone) && harness.store.removed == [2])

    let settled = EditHarness(standardGroup)
    settled.source.writeReplies = [.failure(lostReply)]
    settled.source.readReplies = [.failure(offline), .success(renamed(standardGroup, "标准组 O"))]
    await settled.save(editing(standardGroup) { $0.name = "标准组 O" })
    await settled.flow.reconcile()
    #expect(settled.receiptText == "已保存「标准组 O」" && settled.flow.isFinished && settled.source.writes.count == 1)
}

@MainActor @Test func reconcileCreateSearchesByNameAndPlatform() async throws {
    let harness = EditHarness(nil)
    harness.source.writeReplies = [.failure(lostReply)]
    let elsewhere = AdminGroup(id: 13, name: "Claude 夜间组", platform: "openai")
    harness.source.searchReplies = [.success([premium, elsewhere]), .success([premium, nightly])]
    await harness.save(creating(exclusive: true), context: context(known: [1, 2]))
    #expect(try #require(harness.unconfirmed).check == .notFound)
    await harness.flow.reconcile()
    #expect(harness.source.searches == ["Claude 夜间组|anthropic", "Claude 夜间组|anthropic"])
    #expect(harness.receiptText == "已创建「Claude 夜间组」" && harness.store.upserts.map(\.id) == [12] && harness.flow.isFinished)
}

@MainActor @Test func unkeyedUnknownResultUnlocksWhenTheCheckShowsNothingChanged() async throws {
    let harness = EditHarness(standardGroup, source: ScriptedEditSource(idempotentWrites: false))
    harness.source.writeReplies = [.failure(offline)]
    harness.source.readReplies = [.success(standardGroup)]
    await harness.save(editing(standardGroup) { $0.name = "标准组 P" })
    #expect(harness.flow.phase == .failed(.notApplied) && !harness.flow.locksForm)
    #expect(harness.flow.failureMessage == "服务器上没有这次的修改，可以重新保存。" && harness.source.writes.first?.sendsIdempotencyKey == false)
    await harness.save(editing(standardGroup) { $0.name = "标准组 P" })
    #expect(harness.keys.count == 2 && harness.source.writes.count == 2 && harness.source.writes[0].id != harness.source.writes[1].id)
}

@MainActor @Test func vendorDroppedFieldsChangeTheReceipt() async {
    let dropped = EditHarness(premium)
    dropped.source.writeReplies = [.success(WriteOutcome(value: premium))]
    await dropped.save(editing(premium) { $0.stepRate(up: true) })
    #expect(dropped.receiptText == "已保存「高级组」 · 部分字段无权修改，未生效" && dropped.receipts.current?.tone == .caution)
    let kept = EditHarness(premium)
    await kept.save(editing(premium) { $0.stepRate(up: true) })
    #expect(kept.receiptText == "已保存「高级组」" && kept.receipts.current?.tone == .ok)
}

// MARK: - 会话

@MainActor @Test func groupEditReadOnlyTokenSendsNothing() async {
    let harness = EditHarness(nil, source: ScriptedEditSource(readOnly: true))
    await harness.flow.submit(creating(exclusive: true), context: context())
    #expect(harness.source.identityReads == 0 && harness.source.writes.isEmpty && harness.flow.phase == .editing)
}

@MainActor @Test func staleSessionDropsTheAnswer() async {
    let harness = EditHarness(standardGroup)
    let gate = SessionGate()
    harness.source.gate = gate
    let saving = Task { await harness.flow.submit(editing(standardGroup) { $0.name = "标准组 Q" }, context: context()) }
    while !(await gate.arrived) { await Task.yield() }
    harness.source.switchSession()
    await gate.open()
    await saving.value
    #expect(harness.receiptText == nil && harness.store.upserts.isEmpty && !harness.flow.isFinished)
}

@MainActor @Test func checkLaterRefreshesTheList() async {
    let harness = EditHarness(standardGroup)
    harness.source.writeReplies = [.failure(lostReply)]
    harness.source.readReplies = [.success(standardGroup)]
    await harness.save(editing(standardGroup) { $0.name = "标准组 R" })
    harness.flow.checkLater()
    #expect(harness.store.refreshes == [true] && !harness.flow.isUnconfirmed)
    await harness.flow.retrySameKey()
    #expect(harness.source.writes.count == 1)
}

// MARK: - 成员（S5-11）

private func member(_ id: Int, rateLimitedFor seconds: TimeInterval? = nil) -> UpstreamAccount {
    UpstreamAccount(id: id, name: "Claude-官方-0\(id)", platform: "anthropic", type: "oauth",
                    rateLimitResetAt: seconds.map { ServerTime.utcTimestamp(editClock.addingTimeInterval($0)) })
}
private let claude1 = member(1), claude2 = member(2), claude3 = member(3, rateLimitedFor: 600)
private let premiumCounted = AdminGroup(id: 1, name: "高级组", description: "", platform: "anthropic", rateMultiplier: amount("0.8"), rpmLimit: 0,
                                        accountCount: 3, activeAccountCount: 2)
private func memberCounts(active: Int, total: Int) -> GroupAccountCounts {
    GroupAccountCounts(accountCount: total, activeAccountCount: active, rateLimitedAccountCount: 0, errorAccountCount: 0, idleAccountCount: 0)
}
private func joined(_ id: Int) -> GroupMemberResultItem { GroupMemberResultItem(accountID: id, action: .add, status: .added, priority: 50) }
private func left(_ id: Int) -> GroupMemberResultItem { GroupMemberResultItem(accountID: id, action: .remove, status: .removed, priority: 50) }
private func refused(_ id: Int, _ reason: String) -> GroupMemberResultItem {
    GroupMemberResultItem(accountID: id, action: .add, status: .failed, reason: reason)
}
private func nightlyDraft(_ accounts: [UpstreamAccount], exclusive: Bool = false) -> GroupEditDraft {
    var draft = creating(exclusive: exclusive)
    draft.members = draft.members.adding(accounts)
    return draft
}
private func premiumDraft(_ change: (GroupMemberDraft) -> GroupMemberDraft, fields: (inout GroupEditDraft) -> Void = { _ in }) -> GroupEditDraft {
    var draft = GroupEditDraft(editing: premiumCounted)
    draft.membersLoaded([claude1, claude2, claude3])
    draft.members = change(draft.members)
    fields(&draft)
    return draft
}

/// The member writes behind the real GroupMemberWriter: each send is recorded with how many group writes had gone out before it,
/// and answers from a script; an empty script answers that everything went through, without counts.
@MainActor private final class EditMemberSource: GroupMemberWriteSource {
    enum Call: Equatable { case batch(groupID: Int, GroupMemberBatchRequest), legacy(groupID: Int, GroupMemberBatchRequest) }
    var session: GroupMemberWriteSession?
    private(set) var calls: [Call] = []
    private(set) var groupWritesBefore: [Int] = []
    private(set) var finished: [GroupMemberChange] = []
    private(set) var gone: [Int] = []
    var replies: [Result<GroupMemberBatchResult, any Error>] = []
    weak var edits: ScriptedEditSource?

    init(usesBatch: Bool = true, allowsLegacy: Bool = true) {
        session = GroupMemberWriteSession(generation: UUID(), usesBatch: usesBatch, allowsLegacy: allowsLegacy, isReadOnlyToken: false)
    }
    var groupMemberWriteSession: GroupMemberWriteSession? { session }
    func sendGroupMemberBatch(groupID: Int, _ request: GroupMemberBatchRequest, generation: UUID) async throws -> GroupMemberBatchResult {
        try answer(.batch(groupID: groupID, request), groupID: groupID, request)
    }
    func sendGroupMembersLegacy(groupID: Int, _ request: GroupMemberBatchRequest, generation: UUID) async throws -> GroupMemberBatchResult {
        try answer(.legacy(groupID: groupID, request), groupID: groupID, request)
    }
    func noteMemberBatchUnsupported() {}
    func memberWriteFinished(_ change: GroupMemberChange) { finished.append(change) }
    func groupWentAway(id: Int) { gone.append(id) }

    private func answer(_ call: Call, groupID: Int, _ request: GroupMemberBatchRequest) throws -> GroupMemberBatchResult {
        calls.append(call)
        groupWritesBefore.append(edits?.writes.count ?? 0)
        if !replies.isEmpty { return try replies.removeFirst().get() }
        return GroupMemberBatchResult(groupID: groupID, results: request.add.map { joined($0.accountID) } + request.remove.map(left), counts: nil)
    }
}

@MainActor private func memberHarness(_ original: AdminGroup?, members: EditMemberSource = EditMemberSource()) -> (EditHarness, EditMemberSource) {
    let harness = EditHarness(original, members: members)
    members.edits = harness.source
    return (harness, members)
}
@MainActor private func settle(_ done: @MainActor () -> Bool) async {
    for _ in 0..<500 where !done() { await Task.yield() }
}

@MainActor @Test func createWithMembersWritesTheGroupFirstThenBatchesToTheNewID() async throws {
    let (harness, members) = memberHarness(nil)
    members.replies = [.success(GroupMemberBatchResult(groupID: 12, results: [joined(1), joined(2), joined(3)], counts: memberCounts(active: 2, total: 3)))]
    await harness.flow.submit(nightlyDraft([claude1, claude2, claude3]), context: context())
    #expect(harness.flow.prompt == nil && harness.flow.isFinished)
    #expect(members.calls == [.batch(groupID: 12, try GroupMemberBatchRequest(add: [1, 2, 3].map { GroupMemberAdd(accountID: $0) }))])
    #expect(members.groupWritesBefore == [1] && harness.store.upserts.map(\.id) == [12])
    #expect(harness.receiptText == "已创建「Claude 夜间组」 · 已加入 3 个账号 · 可用 0 → 2" && harness.receipts.current?.tone == .ok)
    #expect(harness.receipts.current?.action == nil)
    #expect(members.finished.map(\.groupID) == [12] && members.finished.first?.counts?.activeAccountCount == 2)
}

@MainActor @Test func createAsksWhenThePickedAccountsAreNotAvailable() async throws {
    let (harness, members) = memberHarness(nil)
    await harness.flow.submit(nightlyDraft([claude3]), context: context())
    #expect(try #require(harness.flow.prompt).confirmation.confirmTitle == "仍然创建" && members.calls.isEmpty)
    await harness.confirm()
    #expect(members.calls.count == 1 && harness.receiptText == "已创建「Claude 夜间组」 · 已加入 1 个账号")
}

@MainActor @Test func createPartialFailureOffersViewOpeningTheResults() async throws {
    let (harness, members) = memberHarness(nil)
    members.replies = [.success(GroupMemberBatchResult(groupID: 12, results: [refused(1, "MIXED_CHANNEL_RISK"), joined(2), refused(3, "ACCOUNT_NOT_FOUND")],
                                                       counts: memberCounts(active: 1, total: 1)))]
    await harness.save(nightlyDraft([claude1, claude2, claude3]))
    let receipt = try #require(harness.receipts.current)
    #expect(receipt.text == "已创建「Claude 夜间组」 · 已加入 1 个，2 个失败" && receipt.tone == .caution && receipt.action?.title == "查看")
    harness.receipts.performAction(id: receipt.id)
    let outcome = try #require(harness.opened.first)
    #expect(outcome.groupID == 12 && outcome.groupName == "Claude 夜间组" && outcome.failures.count == 2)
    #expect(outcome.items.map(\.name).sorted() == ["Claude-官方-01", "Claude-官方-02", "Claude-官方-03"])
}

@MainActor @Test func membersOnlySkipsTheGroupWrite() async throws {
    let (harness, members) = memberHarness(premiumCounted)
    members.replies = [.success(GroupMemberBatchResult(groupID: 1, results: [left(2), left(3)], counts: memberCounts(active: 1, total: 1)))]
    await harness.flow.submit(premiumDraft { $0.removing(2).removing(3) }, context: context())
    #expect(harness.flow.prompt == nil && harness.source.writes.isEmpty && harness.source.identityReads == 0 && harness.keys.isEmpty)
    #expect(members.calls == [.batch(groupID: 1, try GroupMemberBatchRequest(remove: [2, 3]))] && harness.store.upserts.isEmpty)
    #expect(harness.receiptText == "已保存「高级组」 · 已移出 2 个账号 · 可用 2 → 1" && harness.flow.isFinished)
}

@MainActor @Test func emptyingTheGroupAsksThenSavesTheMembers() async throws {
    let (harness, members) = memberHarness(premiumCounted)
    members.replies = [.success(GroupMemberBatchResult(groupID: 1, results: [left(1), left(2)], counts: memberCounts(active: 0, total: 1)))]
    await harness.flow.submit(premiumDraft { $0.removing(1).removing(2) }, context: context())
    let prompt = try #require(harness.flow.prompt).confirmation
    #expect(prompt.title == "保存「高级组」的修改？" && prompt.confirmTitle == "仍然保存" && prompt.isDestructive)
    #expect(prompt.lines == ["站点 演示站 · 分组「高级组」", "成员：移出 2 个", "保存后这个分组没有可用的账号，新请求会失败。"])
    #expect(members.calls.isEmpty && harness.source.writes.isEmpty)
    await harness.confirm()
    #expect(members.calls.count == 1 && harness.source.writes.isEmpty && harness.receiptText == "已保存「高级组」 · 已移出 2 个账号 · 可用 2 → 0")
}

@MainActor @Test func fieldsGoFirstAndTheReplyGivesTheCountBefore() async throws {
    let (harness, members) = memberHarness(premiumCounted)
    var reply = premiumCounted
    reply.rateMultiplier = amount("0.9")
    reply.activeAccountCount = 3
    harness.source.writeReplies = [.success(WriteOutcome(value: reply))]
    members.replies = [.success(GroupMemberBatchResult(groupID: 1, results: [left(3)], counts: memberCounts(active: 1, total: 2)))]
    await harness.flow.submit(premiumDraft({ $0.removing(3) }, fields: { $0.stepRate(up: true) }), context: context())
    let prompt = try #require(harness.flow.prompt).confirmation
    #expect(prompt.lines.contains("费率倍数 ×0.8 → ×0.9") && prompt.lines.contains("成员：移出 1 个") && prompt.confirmTitle == "保存修改")
    await harness.confirm()
    #expect(harness.bodies == [#"{"rate_multiplier":0.9}"#] && members.groupWritesBefore == [1])
    #expect(harness.receiptText == "已保存「高级组」 · 已移出 1 个账号 · 可用 3 → 1")
}

@MainActor @Test func groupWriteFailureStopsBeforeMembers() async throws {
    let (taken, takenMembers) = memberHarness(nil)
    taken.source.writeReplies = [.failure(APIError.server(status: 409, reason: "GROUP_EXISTS"))]
    await taken.save(nightlyDraft([claude1]))
    #expect(taken.flow.phase == .failed(.nameTaken) && takenMembers.calls.isEmpty && taken.receiptText == nil)

    let (lost, lostMembers) = memberHarness(premiumCounted)
    lost.source.writeReplies = [.failure(lostReply)]
    lost.source.readReplies = [.success(premiumCounted)]
    await lost.save(premiumDraft({ $0.removing(3) }, fields: { $0.name = "高级组 A" }))
    #expect(try #require(lost.unconfirmed).check == .differs && lostMembers.calls.isEmpty && !lost.flow.isFinished)
}

@MainActor @Test func unknownResultReadBackSendsTheMembersOnce() async throws {
    let (harness, members) = memberHarness(premiumCounted)
    harness.source.writeReplies = [.failure(lostReply)]
    harness.source.readReplies = [.success(renamed(premiumCounted, "高级组 A"))]
    await harness.save(premiumDraft({ $0.removing(3) }, fields: { $0.name = "高级组 A" }))
    #expect(members.calls == [.batch(groupID: 1, try GroupMemberBatchRequest(remove: [3]))] && harness.source.reads == 1)
    #expect(harness.receiptText == "已保存「高级组 A」 · 已移出 1 个账号" && harness.flow.isFinished)
}

@MainActor @Test func createReconcileFoundSendsMembers() async throws {
    let (harness, members) = memberHarness(nil)
    harness.source.writeReplies = [.failure(lostReply)]
    harness.source.searchReplies = [.success([premium, nightly])]
    await harness.save(nightlyDraft([claude1], exclusive: true), context: context(known: [1, 2]))
    #expect(members.calls == [.batch(groupID: 12, try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 1)]))])
    #expect(harness.receiptText == "已创建「Claude 夜间组」 · 已加入 1 个账号" && harness.flow.isFinished)
}

@MainActor @Test func unconfirmedMemberWriteOffersRetryWithTheSameRequest() async throws {
    let (harness, members) = memberHarness(premiumCounted)
    members.replies = [.failure(offline), .success(GroupMemberBatchResult(groupID: 1, results: [left(2), left(3)], counts: memberCounts(active: 1, total: 1)))]
    await harness.save(premiumDraft { $0.removing(2).removing(3) })
    let receipt = try #require(harness.receipts.current)
    #expect(receipt.text == "已保存「高级组」 · 成员改动未确认" && receipt.action?.title == "重试" && receipt.tone == .caution)
    harness.receipts.performAction(id: receipt.id)
    await settle { members.calls.count == 2 && harness.receiptText != nil }
    #expect(members.calls.count == 2 && members.calls[0] == members.calls[1])
    #expect(harness.receiptText == "已移出 2 个账号 · 可用 2 → 1" && harness.receipts.current?.action == nil)
}

@MainActor @Test func rejectedOrGoneMemberWriteStillReportsTheGroup() async throws {
    let (refusal, refusalMembers) = memberHarness(premiumCounted)
    refusalMembers.replies = [.failure(APIError.server(status: 400, reason: "TOO_MANY_ACCOUNTS"))]
    await refusal.save(premiumDraft { $0.removing(3) })
    #expect(refusal.receiptText == "已保存「高级组」 · 成员没有改动：提交的成员有误，请重试。" && refusal.receipts.current?.tone == .caution)
    #expect(refusal.receipts.current?.action == nil && refusal.flow.isFinished)

    let (gone, goneMembers) = memberHarness(premiumCounted)
    goneMembers.replies = [.failure(missing)]
    await gone.save(premiumDraft { $0.removing(3) })
    #expect(gone.receiptText == "这个分组已删除" && gone.receipts.current?.tone == .critical && goneMembers.gone == [1])
}

@MainActor @Test func simpleModeLegacyIsRejectedWithPrefix() async {
    let (harness, members) = memberHarness(premiumCounted, members: EditMemberSource(usesBatch: false, allowsLegacy: false))
    await harness.save(premiumDraft { $0.removing(3) })
    #expect(harness.receiptText == "已保存「高级组」 · 成员没有改动：服务器暂不支持批量调整成员。" && members.calls.isEmpty)
}

@MainActor @Test func legacyServerGoesThroughTheFallbackWithoutCountsSuffix() async throws {
    let (harness, members) = memberHarness(premiumCounted, members: EditMemberSource(usesBatch: false))
    await harness.save(premiumDraft { $0.removing(3) })
    #expect(members.calls == [.legacy(groupID: 1, try GroupMemberBatchRequest(remove: [3]))])
    #expect(harness.receiptText == "已保存「高级组」 · 已移出 1 个账号")
}

@MainActor @Test func memberWriteForAnotherSessionShowsNoReceipt() async {
    let members = EditMemberSource()
    members.session = nil
    let (harness, _) = memberHarness(premiumCounted, members: members)
    await harness.save(premiumDraft({ $0.removing(3) }, fields: { $0.name = "高级组 B" }))
    #expect(harness.source.writes.count == 1 && harness.receiptText == nil && harness.flow.isFinished && members.calls.isEmpty)
}
