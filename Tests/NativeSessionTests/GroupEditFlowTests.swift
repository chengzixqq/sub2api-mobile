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
    GroupEditContext(editable: editable, knownGroupIDs: known, catalog: nil)
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

    init(_ original: AdminGroup?, source: ScriptedEditSource = ScriptedEditSource(), statsTimesOut: Bool = false) {
        self.source = source
        let store = store, pauses = pauses
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
                             })
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
