import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 60 §8.4 禁用 / 启用 and 删除, §9.4 保存: optimistic badge, undo, rollback, 409, 404, the read-back after a lost reply, the
// session guard and one write per code at a time.

private let used = APIError.server(status: 409, reason: "REDEEM_CODE_USED")
private let notFound = APIError.server(status: 404, reason: "REDEEM_CODE_NOT_FOUND")
private let timedOut = APIError(kind: .transport, message: "连接超时")
private let readOnly = APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")
private let clock = ServerTime.parseTimestamp("2026-10-16T09:41:00+08:00")!

private func redeemCode(_ status: String, id: Int = 7, usedBy: Int? = nil, notes: String? = "活动",
                        expiresAt: Date? = ServerTime.parseTimestamp("2026-10-23T09:12:00+08:00")) -> AdminRedeemCode {
    AdminRedeemCode(id: id, code: "a3f01b2c3d4e5f60718293a4b5c6d4e8", type: "balance", value: 10, status: status, usedBy: usedBy,
                    expiresAt: expiresAt, notes: notes)
}

@MainActor private final class FakeHost: RedeemCodeWritesHost {
    let generation: UUID
    private(set) var shown: [Int: AdminRedeemCode] = [:]
    private(set) var events: [String] = []
    init(generation: UUID, codes: [AdminRedeemCode]) {
        self.generation = generation
        for code in codes { shown[code.id] = code }
    }
    func replaceLocally(_ code: AdminRedeemCode) { shown[code.id] = code; events.append("replace \(code.id) \(code.status)") }
    func removeLocally(id: Int) { shown[id] = nil; events.append("remove \(id)") }
    func refreshCard(id: Int) async { events.append("card \(id)"); await hold() }
    func refreshStats() async { events.append("stats"); await hold() }

    /// Parks each card or counts read until `releaseReads()`, like a slow network after the write.
    var holdsReads = false
    private var parked: [CheckedContinuation<Void, Never>] = []
    func releaseReads() { holdsReads = false; let waiting = parked; parked = []; waiting.forEach { $0.resume() } }
    private func hold() async { if holdsReads { await withCheckedContinuation { parked.append($0) } } }
}

/// Answers from per-call scripts (an empty script answers like a server that ran the write); `holds` parks each update until
/// `release()`, and `duringUpdate` runs while one is out.
@MainActor private final class FakeWriteSource {
    private(set) var updates: [([Int], RedeemBatchUpdateFields)] = []
    private(set) var deletes: [Int] = []
    private(set) var reads: [Int] = []
    var updateReplies: [Result<Int, any Error>] = []
    var deleteReplies: [Result<RedeemDeleteResult, any Error>] = []
    var readReplies: [Result<AdminRedeemCode, any Error>] = []
    var holds = false
    var duringUpdate: (@MainActor () -> Void)?
    private var held: [CheckedContinuation<Void, Never>] = []

    var source: RedeemWriteSource {
        RedeemWriteSource(update: { try await self.update($0, $1) }, delete: { try await self.delete($0) }, code: { try await self.read($0) })
    }
    func release() { let parked = held; held = []; parked.forEach { $0.resume() } }

    private func update(_ ids: [Int], _ fields: RedeemBatchUpdateFields) async throws -> Int {
        updates.append((ids, fields))
        if holds { await withCheckedContinuation { held.append($0) } }
        duringUpdate?()
        return try Self.next(&updateReplies) ?? ids.count
    }
    private func delete(_ id: Int) async throws -> RedeemDeleteResult {
        deletes.append(id)
        return try Self.next(&deleteReplies) ?? .deleted
    }
    private func read(_ id: Int) async throws -> AdminRedeemCode {
        reads.append(id)
        guard let reply = try Self.next(&readReplies) else { throw notFound }
        return reply
    }
    private static func next<T>(_ script: inout [Result<T, any Error>]) throws -> T? {
        guard !script.isEmpty else { return nil }
        return try script.removeFirst().get()
    }
}

@MainActor private final class Flag { var on = true }
@MainActor private final class Counter { var value = 0 }
@MainActor private final class Slot<Value> { var value: Value? }

@MainActor private final class Bench {
    let fake: FakeWriteSource
    let receipts: ReceiptCenter
    let host: FakeHost
    let writes: RedeemCodeWrites
    /// The session the writes belong to is still the current one.
    let current: Flag
    /// Writes done without a list to update.
    let hostless: Counter

    init(_ codes: [AdminRedeemCode] = [redeemCode("unused")], attachHost: Bool = true) {
        let generation = UUID(), fake = FakeWriteSource(), current = Flag(), hostless = Counter()
        let receipts = ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
        self.fake = fake; self.receipts = receipts; self.current = current; self.hostless = hostless
        host = FakeHost(generation: generation, codes: codes)
        writes = RedeemCodeWrites(source: fake.source, receipts: receipts, generation: generation, isCurrent: { current.on },
                                  now: { clock }, timeZone: TimeZone(identifier: "Asia/Shanghai")!, onChange: { hostless.value += 1 })
        if attachHost { writes.host = host }
    }
    var receipt: String? { receipts.current?.text }
    func undo() async {
        guard let id = receipts.current?.id else { return }
        let before = host.events.count
        receipts.performAction(id: id)
        // The optimistic badge, then the card and the counts read again.
        await waitUntil { self.host.events.count >= before + 3 }
    }
}

// MARK: - 禁用 / 启用

@MainActor @Test func toggleOptimisticUpdate() async {
    let bench = Bench()
    bench.fake.holds = true
    let running = Task { await bench.writes.toggleStatus(redeemCode("unused")) }
    await waitUntil { bench.fake.updates.count == 1 }
    #expect(bench.host.shown[7]?.status == "disabled")
    #expect(bench.writes.isRunning(7))
    #expect(bench.fake.updates.first?.0 == [7])
    #expect(bench.fake.updates.first?.1 == RedeemBatchUpdateFields(status: .disabled))
    bench.fake.release()
    await running.value
    #expect(!bench.writes.isRunning(7))
    #expect(bench.receipt == "已禁用 · 不能再兑换")
    #expect(bench.receipts.current?.action?.title == "撤销")
    #expect(bench.host.events == ["replace 7 disabled", "card 7", "stats"])
}

@MainActor @Test func enableSaysItCanBeRedeemed() async {
    let bench = Bench([redeemCode("disabled")])
    await bench.writes.toggleStatus(redeemCode("disabled"))
    #expect(bench.fake.updates.first?.1 == RedeemBatchUpdateFields(status: .unused))
    #expect(bench.receipt == "已启用 · 可以兑换")
    #expect(bench.host.shown[7]?.status == "unused")
}

@MainActor @Test func toggleUndoWritesTheOldStatusBack() async {
    let bench = Bench()
    await bench.writes.toggleStatus(redeemCode("unused"))
    await bench.undo()
    #expect(bench.fake.updates.map { $0.1 } == [RedeemBatchUpdateFields(status: .disabled), RedeemBatchUpdateFields(status: .unused)])
    #expect(bench.host.shown[7]?.status == "unused")
    // Done says nothing more: the badge shows it.
    #expect(bench.receipt == nil)
    #expect(bench.host.events.suffix(3) == ["replace 7 unused", "card 7", "stats"])
}

@MainActor @Test func toggleRollsBackOnFailure() async {
    let bench = Bench()
    bench.fake.updateReplies = [.failure(readOnly)]
    await bench.writes.toggleStatus(redeemCode("unused"))
    #expect(bench.host.shown[7]?.status == "unused")
    #expect(bench.receipt == ReasonCatalog.entry(status: 403, reason: "ACCESS_TOKEN_READ_ONLY").message)
    #expect(bench.receipts.current?.action == nil)
    #expect(bench.host.events == ["replace 7 disabled", "replace 7 unused"])
}

@MainActor @Test func toggle409RefreshesCard() async {
    let bench = Bench()
    bench.fake.updateReplies = [.failure(used)]
    await bench.writes.toggleStatus(redeemCode("unused"))
    #expect(bench.receipt == "这个码已被兑换，不能再改状态")
    #expect(bench.host.events == ["replace 7 disabled", "replace 7 unused", "card 7"])
}

@MainActor @Test func toggleOnADeletedCodeRemovesIt() async {
    let bench = Bench()
    bench.fake.updateReplies = [.failure(notFound)]
    await bench.writes.toggleStatus(redeemCode("unused"))
    #expect(bench.host.shown[7] == nil)
    #expect(bench.receipt == "这个兑换码已被删除")
    await waitUntil { bench.host.events.count == 3 }
    #expect(bench.host.events == ["replace 7 disabled", "remove 7", "stats"])
}

@MainActor @Test func toggleTimeoutReadsBackOnce() async {
    let applied = Bench()
    applied.fake.updateReplies = [.failure(timedOut)]
    applied.fake.readReplies = [.success(redeemCode("disabled", notes: "后台改过"))]
    await applied.writes.toggleStatus(redeemCode("unused"))
    #expect(applied.fake.updates.count == 1 && applied.fake.reads == [7])
    #expect(applied.receipt == "已禁用 · 不能再兑换")
    #expect(applied.host.shown[7]?.notes == "后台改过")

    let missed = Bench()
    missed.fake.updateReplies = [.failure(APIError.server(status: 502, reason: nil))]
    missed.fake.readReplies = [.success(redeemCode("unused"))]
    await missed.writes.toggleStatus(redeemCode("unused"))
    #expect(missed.fake.updates.count == 1)
    #expect(missed.host.shown[7]?.status == "unused")
    #expect(missed.receipt == "结果未确认，请刷新核对后再操作")
    #expect(missed.host.events == ["replace 7 disabled", "replace 7 unused", "card 7"])

    let unreadable = Bench()
    unreadable.fake.updateReplies = [.failure(timedOut)]
    unreadable.fake.readReplies = [.failure(timedOut)]
    await unreadable.writes.toggleStatus(redeemCode("unused"))
    #expect(unreadable.host.shown[7]?.status == "unused")
    #expect(unreadable.receipt == "结果未确认，请刷新核对后再操作")
}

@MainActor @Test func redeemedOrExpiredCodesAreNotToggled() async {
    let bench = Bench([redeemCode("used", usedBy: 3), redeemCode("expired", id: 8)])
    await bench.writes.toggleStatus(redeemCode("used", usedBy: 3))
    await bench.writes.toggleStatus(redeemCode("disabled", usedBy: 3))
    await bench.writes.toggleStatus(redeemCode("expired", id: 8))
    #expect(bench.fake.updates.isEmpty && bench.host.events.isEmpty)
}

// MARK: - 删除

@MainActor @Test func deleteRemovesTheCardAndReadsTheCounts() async {
    for reply: Result<RedeemDeleteResult, any Error> in [.success(.deleted), .success(.alreadyGone), .failure(notFound)] {
        let bench = Bench()
        bench.fake.deleteReplies = [reply]
        await bench.writes.delete(redeemCode("unused"))
        #expect(bench.fake.deletes == [7])
        #expect(bench.host.shown[7] == nil)
        #expect(bench.receipt == "已删除兑换码「····d4e8」")
        #expect(bench.receipts.current?.action == nil)
        await waitUntil { bench.host.events.count == 2 }
        #expect(bench.host.events == ["remove 7", "stats"])
    }
}

@MainActor @Test func delete409RefreshesCard() async {
    let bench = Bench()
    bench.fake.deleteReplies = [.failure(used)]
    await bench.writes.delete(redeemCode("unused"))
    #expect(bench.host.shown[7] != nil)
    #expect(bench.receipt == "已被兑换的兑换码不能删除")
    await waitUntil { !bench.host.events.isEmpty }
    #expect(bench.host.events == ["card 7"])
}

@MainActor @Test func deleteTimeoutReadsBack() async {
    let gone = Bench()
    gone.fake.deleteReplies = [.failure(timedOut)]
    await gone.writes.delete(redeemCode("unused"))
    #expect(gone.fake.deletes.count == 1 && gone.fake.reads == [7])
    #expect(gone.receipt == "已删除兑换码「····d4e8」")
    #expect(gone.host.shown[7] == nil)

    let still = Bench()
    still.fake.deleteReplies = [.failure(timedOut)]
    still.fake.readReplies = [.success(redeemCode("unused"))]
    await still.writes.delete(redeemCode("unused"))
    #expect(still.fake.deletes.count == 1)
    #expect(still.host.shown[7] != nil)
    #expect(still.receipt == "结果未确认，请刷新核对后再操作")
}

// MARK: - 保存

@MainActor @Test func saveOutcomes() async {
    let renewing = Bench([redeemCode("expired")])
    var draft = RedeemEditDraft(code: redeemCode("expired"), now: clock)
    draft.expiry = .days(14)
    #expect(await renewing.writes.save(draft) == .saved)
    #expect(renewing.fake.updates.first?.1 == draft.fields(now: clock))
    #expect(renewing.receipt == "已续期 · 10/30 过期，改回未使用")
    await waitUntil { renewing.host.events.count == 2 }
    #expect(renewing.host.events == ["card 7", "stats"])

    var raced = RedeemEditDraft(code: redeemCode("unused"), now: clock)
    raced.status = .disabled
    let racing = Bench()
    racing.fake.updateReplies = [.failure(used)]
    #expect(await racing.writes.save(raced) == .switchedToNotesOnly)
    #expect(racing.receipt == nil)

    for (error, text) in [(APIError.server(status: 400, reason: "REDEEM_CODE_EXPIRES_AT_INVALID"), "过期时间要晚于现在"),
                          (APIError.server(status: 400, reason: "REDEEM_CODE_GROUP_ID_INVALID"), "分组无效，请重新选择")] {
        let refused = Bench()
        refused.fake.updateReplies = [.failure(error)]
        #expect(await refused.writes.save(raced) == .rejected(text))
        #expect(refused.host.events.isEmpty)
    }

    let removed = Bench()
    removed.fake.updateReplies = [.failure(notFound)]
    #expect(await removed.writes.save(raced) == .gone)
    #expect(removed.receipt == "这个兑换码已被删除")
    await waitUntil { removed.host.events.count == 2 }
    #expect(removed.host.events == ["remove 7", "stats"])

    // Nothing changed: nothing is sent.
    let idle = Bench()
    #expect(await idle.writes.save(RedeemEditDraft(code: redeemCode("unused"), now: clock)) == .ignored)
    #expect(idle.fake.updates.isEmpty)
}

@MainActor @Test func saveTimeoutReadsBack() async {
    var draft = RedeemEditDraft(code: redeemCode("unused"), now: clock)
    draft.notes = "工单 #8812"
    let applied = Bench()
    applied.fake.updateReplies = [.failure(timedOut)]
    applied.fake.readReplies = [.success(redeemCode("unused", notes: "工单 #8812"))]
    #expect(await applied.writes.save(draft) == .saved)
    #expect(applied.receipt == "已保存备注")
    #expect(applied.host.shown[7]?.notes == "工单 #8812")

    let missed = Bench()
    missed.fake.updateReplies = [.failure(timedOut)]
    missed.fake.readReplies = [.success(redeemCode("unused"))]
    #expect(await missed.writes.save(draft) == .unconfirmed)
    #expect(missed.fake.updates.count == 1)
    #expect(missed.receipt == nil)
}

/// 9.4: the sheet closes on the reply, then the receipt; the card and the counts are read behind it, never holding it open.
@MainActor @Test func saveClosesBeforeTheReads() async {
    var editing = RedeemEditDraft(code: redeemCode("unused"), now: clock)
    editing.notes = "工单 #8812"
    let draft = editing
    let bench = Bench()
    bench.host.holdsReads = true
    let outcome = Slot<RedeemSaveOutcome>()
    let saving = Task { outcome.value = await bench.writes.save(draft) }
    await waitUntil { outcome.value != nil && bench.host.events == ["card 7"] }
    #expect(outcome.value == .saved)
    #expect(bench.receipt == "已保存备注")
    bench.host.releaseReads()
    await saving.value
    await waitUntil { bench.host.events == ["card 7", "stats"] }
    #expect(bench.host.events == ["card 7", "stats"])

    // Deleted meanwhile: closed with “这个兑换码已被删除”, the counts behind it.
    let removed = Bench()
    removed.host.holdsReads = true
    removed.fake.updateReplies = [.failure(notFound)]
    let gone = Slot<RedeemSaveOutcome>()
    let closing = Task { gone.value = await removed.writes.save(draft) }
    await waitUntil { gone.value != nil && removed.host.events == ["remove 7", "stats"] }
    #expect(gone.value == .gone)
    #expect(removed.receipt == "这个兑换码已被删除")
    removed.host.releaseReads()
    await closing.value
}

/// 8.4: the delete confirmation closes on the reply; “已删除兑换码「····d4e8」” is not hidden under it while the counts load.
@MainActor @Test func deleteClosesBeforeTheReads() async {
    let bench = Bench()
    bench.host.holdsReads = true
    let done = Flag()
    done.on = false
    let deleting = Task { await bench.writes.delete(redeemCode("unused")); done.on = true }
    await waitUntil { done.on && bench.host.events == ["remove 7", "stats"] }
    #expect(done.on)
    #expect(bench.receipt == "已删除兑换码「····d4e8」")
    bench.host.releaseReads()
    await deleting.value

    // 409: the card is read again behind the closed confirmation too.
    let refused = Bench()
    refused.host.holdsReads = true
    refused.fake.deleteReplies = [.failure(used)]
    let answered = Flag()
    answered.on = false
    let refusing = Task { await refused.writes.delete(redeemCode("unused")); answered.on = true }
    await waitUntil { answered.on && refused.host.events == ["card 7"] }
    #expect(answered.on)
    #expect(refused.receipt == "已被兑换的兑换码不能删除")
    refused.host.releaseReads()
    await refusing.value
}

// MARK: - Session and re-entry

@MainActor @Test func generationGuardDropsLateReplies() async {
    let bench = Bench()
    bench.fake.duringUpdate = { bench.current.on = false }
    bench.fake.updateReplies = [.failure(used)]
    await bench.writes.toggleStatus(redeemCode("unused"))
    #expect(bench.receipt == nil)
    #expect(bench.host.events == ["replace 7 disabled"])

    let late = Bench()
    late.current.on = false
    await late.writes.delete(redeemCode("unused"))
    #expect(late.fake.deletes.isEmpty)

    // A host of another session is never touched.
    let other = Bench()
    let stranger = FakeHost(generation: UUID(), codes: [redeemCode("unused")])
    other.writes.host = stranger
    await other.writes.toggleStatus(redeemCode("unused"))
    #expect(stranger.events.isEmpty)
    #expect(other.receipt == "已禁用 · 不能再兑换")
}

@MainActor @Test func reentryIgnored() async {
    let bench = Bench()
    bench.fake.holds = true
    let first = Task { await bench.writes.toggleStatus(redeemCode("unused")) }
    await waitUntil { bench.fake.updates.count == 1 }
    await bench.writes.toggleStatus(redeemCode("disabled"))
    await bench.writes.delete(redeemCode("disabled"))
    #expect(bench.fake.updates.count == 1 && bench.fake.deletes.isEmpty)
    bench.fake.release()
    await first.value
    #expect(bench.fake.updates.count == 1)
}

@MainActor @Test func withoutHostOnlyTheReceiptAndTheSignal() async {
    let bench = Bench(attachHost: false)
    var draft = RedeemEditDraft(code: redeemCode("unused"), now: clock)
    draft.status = .disabled
    #expect(await bench.writes.save(draft) == .saved)
    #expect(bench.receipt == "已保存兑换码")
    #expect(bench.host.events.isEmpty)
    await waitUntil { bench.hostless.value == 1 }
    #expect(bench.hostless.value == 1)
}
