import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// Records every call and answers through closures; `call` counts from 1 per kind.
private actor DetailStub {
    typealias LoadHandler = @Sendable (_ call: Int, _ id: Int, _ includeReadStats: Bool) async throws -> Announcement
    typealias SummaryHandler = @Sendable (_ call: Int) async throws -> AnnouncementReadSummary
    typealias UpdateHandler = @Sendable (_ call: Int, _ request: AnnouncementUpdateRequest) async throws -> Announcement
    typealias DeleteHandler = @Sendable (_ call: Int) async throws -> AnnouncementDeleteResult
    private let onLoad: LoadHandler
    private let onSummary: SummaryHandler
    private let onUpdate: UpdateHandler
    private let onDelete: DeleteHandler
    private(set) var loads: [(id: Int, includeReadStats: Bool)] = []
    private(set) var summaries = 0
    private(set) var updates: [AnnouncementUpdateRequest] = []
    private(set) var deletes = 0

    init(load: @escaping LoadHandler = { _, id, _ in sample(id) }, summary: @escaping SummaryHandler = { _ in sampleSummary },
         update: @escaping UpdateHandler = { _, request in sample(31, status: request.status ?? .active) },
         delete: @escaping DeleteHandler = { _ in .deleted }) {
        onLoad = load; onSummary = summary; onUpdate = update; onDelete = delete
    }
    func load(_ id: Int, _ includeReadStats: Bool) async throws -> Announcement {
        loads.append((id, includeReadStats))
        return try await onLoad(loads.count, id, includeReadStats)
    }
    func summary(_ id: Int) async throws -> AnnouncementReadSummary {
        summaries += 1
        return try await onSummary(summaries)
    }
    func update(_ id: Int, _ request: AnnouncementUpdateRequest) async throws -> Announcement {
        updates.append(request)
        return try await onUpdate(updates.count, request)
    }
    func delete(_ id: Int) async throws -> AnnouncementDeleteResult {
        deletes += 1
        return try await onDelete(deletes)
    }
    var loadCount: Int { loads.count }
    var loadedWithStats: [Bool] { loads.map(\.includeReadStats) }
    nonisolated var source: AnnouncementDetailSource {
        AnnouncementDetailSource(load: { try await self.load($0, $1) }, summary: { try await self.summary($0) },
                                 update: { try await self.update($0, $1) }, delete: { try await self.delete($0) })
    }
}

@MainActor private final class TestFlag { var value = true }
@MainActor private final class Calls {
    private(set) var count = 0
    func hit() { count += 1 }
}

private let sampleSummary = AnnouncementReadSummary(announcementID: 31, totalUsers: 1_036, eligibleCount: 1_036, readCount: 412,
                                                    eligibleReadCount: 410, computedAt: Date(timeIntervalSince1970: 1_800_000_000))
private let notFound = APIError.server(status: 404, reason: "ANNOUNCEMENT_NOT_FOUND")
private let gateway = APIError.server(status: 502, reason: nil)
private let readOnly = APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")
private let timedOut = APIError(kind: .transport, message: "连接超时；写操作结果可能尚未确认，请勿新建重复操作。")

private func sample(_ id: Int, status: AnnouncementStatus = .active) -> Announcement {
    Announcement(id: id, title: "公告 \(id)", content: "正文", status: status, notifyMode: .popup)
}

/// A receipt center whose receipts never time out during a test.
@MainActor private func stillReceipts() -> ReceiptCenter {
    ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
}

@MainActor private struct Bench {
    let model: AnnouncementDetailModel
    let receipts: ReceiptCenter
    let signal: AnnouncementChangeSignal
    let current: TestFlag
}

@MainActor private func makeBench(_ stub: DetailStub, id: Int = 31, readStats: Bool = true) -> Bench {
    let receipts = stillReceipts(), signal = AnnouncementChangeSignal.signal(for: UUID()), current = TestFlag()
    let model = AnnouncementDetailModel(id: id, source: stub.source, readStatsEnabled: readStats, receipts: receipts, signal: signal,
                                        isCurrent: { current.value })
    return Bench(model: model, receipts: receipts, signal: signal, current: current)
}

/// Up to five seconds: under `swift test --parallel` a child task can take a while to be scheduled.
private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}

// MARK: 60 §16.2 读取

@MainActor @Test func detailLoadsSummaryOnlyWhenAllowed() async {
    let stub = DetailStub()
    let bench = makeBench(stub)
    await bench.model.load()
    #expect(await stub.loadedWithStats == [true])
    #expect(await stub.summaries == 1)
    #expect(bench.model.announcement?.id == 31 && bench.model.summaryForDisplay == sampleSummary && bench.model.showsReadRow)

    let draftStub = DetailStub(load: { _, id, _ in sample(id, status: .draft) })
    let draft = makeBench(draftStub, id: 29)
    await draft.model.load()
    #expect(await draftStub.summaries == 0)
    #expect(draft.model.showsReadRow == false && draft.model.summaryForDisplay == nil)

    let oldStub = DetailStub()
    let old = makeBench(oldStub, readStats: false)
    await old.model.load()
    #expect(await oldStub.loadedWithStats == [false])
    #expect(await oldStub.summaries == 0)
    #expect(old.model.showsReadRow && old.model.summaryForDisplay == nil)
}

@MainActor @Test func detailSummaryFailureFallsBackWithoutBlockingDetail() async {
    let stub = DetailStub(summary: { _ in throw gateway })
    let bench = makeBench(stub)
    await bench.model.load()
    #expect(bench.model.summary.failureReason != nil)
    #expect(bench.model.summaryForDisplay == nil)
    #expect(bench.model.announcement?.id == 31 && bench.model.detail.failureReason == nil && !bench.model.isGone)
}

/// 60 §16.3: leaving the page (已读情况, another tab) cancels the entry read after the detail arrived; back on the page only the
/// summary is read, so the read line does not stay on the no-capability hint.
@MainActor @Test func detailSummaryCancelledByLeavingIsReadOnReturn() async {
    let gate = SessionGate()
    let stub = DetailStub(summary: { call in
        if call == 1 { await gate.wait() }
        return sampleSummary
    })
    let bench = makeBench(stub)
    let entry = Task { await bench.model.loadIfNeeded() }
    #expect(await eventually { await gate.arrived })
    entry.cancel()
    await gate.open()
    await entry.value
    #expect(bench.model.announcement?.id == 31 && bench.model.summary == .idle)

    await bench.model.loadIfNeeded()
    #expect(await stub.loadCount == 1)
    #expect(await stub.summaries == 2)
    #expect(bench.model.summaryForDisplay == sampleSummary)
    await bench.model.loadIfNeeded()
    #expect(await stub.summaries == 2)

    let draftStub = DetailStub(load: { _, id, _ in sample(id, status: .draft) })
    let draft = makeBench(draftStub, id: 29)
    await draft.model.loadIfNeeded()
    await draft.model.loadIfNeeded()
    #expect(await draftStub.loadCount == 1)
    #expect(await draftStub.summaries == 0)
}

@MainActor @Test func detailNotFoundMarksGoneAndOtherFailuresKeepShownContent() async {
    let missing = makeBench(DetailStub(load: { _, _, _ in throw notFound }))
    let before = missing.signal.revision
    await missing.model.load()
    #expect(missing.model.isGone && missing.model.detail.failureReason == nil)
    #expect(missing.signal.revision == before + 1)

    let failing = makeBench(DetailStub(load: { _, _, _ in throw gateway }))
    await failing.model.load()
    #expect(failing.model.detail.failureReason != nil && failing.model.announcement == nil && !failing.model.isGone)

    let flaky = makeBench(DetailStub(load: { call, id, _ in if call == 2 { throw gateway }; return sample(id) }))
    await flaky.model.load()
    await flaky.model.load()
    #expect(flaky.model.detail.failureReason != nil && flaky.model.announcement?.id == 31)

    let cancelled = makeBench(DetailStub(load: { _, _, _ in throw CancellationError() }))
    await cancelled.model.load()
    #expect(cancelled.model.detail == .idle)
}

// MARK: 60 §16.4 发布 / 归档 / 撤销

@MainActor @Test func detailPublishSendsStatusOnlyThenReloadsAndBumps() async {
    let stub = DetailStub(load: { call, id, _ in sample(id, status: call == 1 ? .draft : .active) },
                          update: { _, request in sample(29, status: request.status ?? .draft) })
    let bench = makeBench(stub, id: 29)
    await bench.model.load()
    let before = bench.signal.revision
    #expect(await bench.model.publish() == .done)
    #expect(await stub.updates == [.status(.active)])
    #expect(bench.receipts.current?.text == "已发布 · 符合条件的用户能看到")
    #expect(bench.receipts.current?.action == nil)
    #expect(await stub.loadCount == 2)
    #expect(bench.model.announcement?.status == .active)
    #expect(bench.signal.revision == before + 1)
    await bench.model.noteRevision(bench.signal.revision)
    #expect(await stub.loadCount == 2)

    let archived = DetailStub(load: { call, id, _ in sample(id, status: call == 1 ? .archived : .active) })
    let republish = makeBench(archived, id: 27)
    await republish.model.load()
    #expect(await republish.model.publish() == .done)
    #expect(await archived.updates == [.status(.active)])
}

@MainActor @Test func detailArchiveReceiptUndoRestoresActive() async {
    let stub = DetailStub(load: { call, id, _ in sample(id, status: call == 2 ? .archived : .active) },
                          update: { _, request in sample(30, status: request.status ?? .active) })
    let bench = makeBench(stub, id: 30)
    await bench.model.load()
    await bench.model.archive()
    #expect(await stub.updates == [.status(.archived)])
    let receipt = bench.receipts.current
    #expect(receipt?.text == "已归档 · 用户不再看到" && receipt?.action?.title == "撤销")
    let signal = bench.signal, afterArchive = signal.revision
    bench.receipts.performAction(id: receipt?.id ?? UUID())
    #expect(await eventually { await stub.updates.count == 2 })
    #expect(await stub.updates.last == .status(.active))
    #expect(await eventually { await stub.loadCount == 3 })
    #expect(await eventually { @MainActor in signal.revision == afterArchive + 1 })
    #expect(bench.receipts.current == nil)

    let failing = DetailStub(update: { call, request in
        if call == 2 { throw readOnly }
        return sample(30, status: request.status ?? .active)
    })
    let undoFails = makeBench(failing, id: 30)
    await undoFails.model.load()
    await undoFails.model.archive()
    let undoReceipts = undoFails.receipts
    undoReceipts.performAction(id: undoReceipts.current?.id ?? UUID())
    #expect(await eventually { @MainActor in undoReceipts.current?.text == "撤销没有成功：当前管理访问令牌只读，不能执行此操作" })
}

@MainActor @Test func detailUndoStillSendsAfterThePageIsGone() async {
    let stub = DetailStub(update: { _, request in sample(30, status: request.status ?? .active) })
    let receipts = stillReceipts(), signal = AnnouncementChangeSignal.signal(for: UUID())
    var model: AnnouncementDetailModel? = AnnouncementDetailModel(id: 30, source: stub.source, readStatsEnabled: true, receipts: receipts,
                                                                 signal: signal, isCurrent: { true })
    await model?.load()
    await model?.archive()
    weak let released = model
    model = nil
    #expect(released == nil)
    let before = signal.revision
    receipts.performAction(id: receipts.current?.id ?? UUID())
    #expect(await eventually { await stub.updates == [.status(.archived), .status(.active)] })
    #expect(await eventually { @MainActor in signal.revision == before + 1 })
}

@MainActor @Test func detailInFlightBlocksSecondWrite() async {
    let gate = SessionGate()
    let stub = DetailStub(update: { _, request in await gate.wait(); return sample(30, status: request.status ?? .active) })
    let bench = makeBench(stub, id: 30)
    await bench.model.load()
    let task = Task { await bench.model.archive() }
    #expect(await eventually { await gate.arrived })
    #expect(bench.model.inFlight == .archive && bench.model.isBusy)
    await bench.model.archive()
    #expect(await bench.model.publish() == .failed)
    let deleted = Calls()
    await bench.model.delete { deleted.hit() }
    #expect(await stub.updates.count == 1)
    #expect(await stub.deletes == 0)
    #expect(deleted.count == 0)
    await gate.open()
    await task.value
    #expect(bench.model.inFlight == nil && !bench.model.isBusy)
}

@MainActor @Test func detailRejectedWriteIsNotResent() async {
    let stub = DetailStub(update: { _, _ in throw readOnly })
    let bench = makeBench(stub, id: 30)
    await bench.model.load()
    let before = bench.signal.revision
    await bench.model.archive()
    #expect(bench.receipts.current?.text == "归档没有成功：当前管理访问令牌只读，不能执行此操作")
    #expect(await stub.updates.count == 1)
    #expect(await stub.loadCount == 1)
    #expect(bench.model.announcement?.status == .active && bench.signal.revision == before)
}

@MainActor @Test func detailUnconfirmedWriteReadsBack() async {
    let applied = DetailStub(load: { call, id, _ in sample(id, status: call == 1 ? .draft : .active) }, update: { _, _ in throw timedOut })
    let ok = makeBench(applied, id: 29)
    await ok.model.load()
    let before = ok.signal.revision
    #expect(await ok.model.publish() == .done)
    #expect(await applied.loadedWithStats.prefix(2) == [true, false])
    #expect(ok.receipts.current?.text == "已发布 · 符合条件的用户能看到" && ok.signal.revision == before + 1)
    #expect(await applied.updates.count == 1)

    let unchanged = DetailStub(load: { _, id, _ in sample(id, status: .draft) }, update: { _, _ in throw timedOut })
    let still = makeBench(unchanged, id: 29)
    await still.model.load()
    #expect(await still.model.publish() == .failed)
    #expect(still.receipts.current?.text == "结果未确认，请刷新核对后再操作")

    let vanished = DetailStub(load: { call, id, _ in if call == 2 { throw notFound }; return sample(id, status: .draft) },
                              update: { _, _ in throw gateway })
    let gone = makeBench(vanished, id: 29)
    await gone.model.load()
    #expect(await gone.model.publish() == .failed)
    #expect(gone.model.isGone)

    let unreadable = DetailStub(load: { call, id, _ in if call == 2 { throw gateway }; return sample(id, status: .draft) },
                                update: { _, _ in throw timedOut })
    let unknown = makeBench(unreadable, id: 29)
    await unknown.model.load()
    #expect(await unknown.model.publish() == .failed)
    #expect(unknown.receipts.current?.text == "结果未确认，请刷新核对后再操作")
    #expect(await unreadable.updates.count == 1)
}

@MainActor @Test func detailSecurityPromptPassedReturnsToConfirmation() async {
    let passed = APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed)
    let stub = DetailStub(load: { _, id, _ in sample(id, status: .draft) }, update: { _, _ in throw passed })
    let bench = makeBench(stub, id: 29)
    await bench.model.load()
    #expect(await bench.model.publish() == .reconfirm)
    #expect(bench.receipts.current?.text == "二次验证已通过，请重新确认后发送")
    #expect(await stub.updates.count == 1)

    let archiving = makeBench(DetailStub(update: { _, _ in throw passed }), id: 30)
    await archiving.model.load()
    await archiving.model.archive()
    #expect(archiving.receipts.current?.text == "二次验证已通过，请重新确认后发送")
}

@MainActor @Test func detailWriteNotFoundMarksGone() async {
    let bench = makeBench(DetailStub(update: { _, _ in throw notFound }), id: 30)
    await bench.model.load()
    let before = bench.signal.revision
    await bench.model.archive()
    #expect(bench.model.isGone && bench.signal.revision == before + 1)
}

// MARK: 60 §16.4 删除

@MainActor @Test func detailDeleteTreatsAlreadyGoneAsDeleted() async {
    for result in [AnnouncementDeleteResult.deleted, .alreadyGone] {
        let stub = DetailStub(delete: { _ in result })
        let bench = makeBench(stub)
        await bench.model.load()
        let before = bench.signal.revision
        let calls = Calls()
        await bench.model.delete { calls.hit() }
        #expect(calls.count == 1 && bench.signal.revision == before + 1 && !bench.model.isDeleting)
    }

    let thrown = makeBench(DetailStub(delete: { _ in throw notFound }))
    await thrown.model.load()
    let deleted = Calls()
    await thrown.model.delete { deleted.hit() }
    #expect(deleted.count == 1)

    let refused = makeBench(DetailStub(delete: { _ in throw readOnly }))
    await refused.model.load()
    let called = Calls()
    await refused.model.delete { called.hit() }
    #expect(called.count == 0 && refused.receipts.current?.text == "删除没有成功：当前管理访问令牌只读，不能执行此操作")

    let gate = SessionGate()
    let slow = DetailStub(delete: { _ in await gate.wait(); return .deleted })
    let busy = makeBench(slow)
    await busy.model.load()
    let task = Task { await busy.model.delete {} }
    #expect(await eventually { await gate.arrived })
    #expect(busy.model.isDeleting && busy.model.isBusy)
    await busy.model.delete {}
    #expect(await busy.model.publish() == .failed)
    await gate.open()
    await task.value
    #expect(await slow.deletes == 1)
}

@MainActor @Test func detailDeleteUnconfirmedReadsBack() async {
    let vanished = DetailStub(load: { call, id, _ in if call == 2 { throw notFound }; return sample(id) }, delete: { _ in throw timedOut })
    let gone = makeBench(vanished)
    await gone.model.load()
    let deleted = Calls()
    await gone.model.delete { deleted.hit() }
    #expect(deleted.count == 1)
    #expect(await vanished.deletes == 1)

    let stillThere = DetailStub(delete: { _ in throw timedOut })
    let kept = makeBench(stillThere)
    await kept.model.load()
    let called = Calls()
    await kept.model.delete { called.hit() }
    #expect(called.count == 0 && kept.receipts.current?.text == "删除没有成功：\(timedOut.localizedDescription)")

    let unreadable = DetailStub(load: { call, id, _ in if call == 2 { throw gateway }; return sample(id) }, delete: { _ in throw gateway })
    let unknown = makeBench(unreadable)
    await unknown.model.load()
    await unknown.model.delete { called.hit() }
    #expect(called.count == 0 && unknown.receipts.current?.text == "结果未确认，请刷新核对后再操作")
    #expect(await unreadable.deletes == 1)
}

// MARK: 00 §4.6 会话代号与迟到结果

@MainActor @Test func detailStaleSessionOrTicketDropsResults() async {
    let gate = SessionGate()
    let stub = DetailStub(load: { call, id, _ in
        if call == 1 { await gate.wait(); return sample(id, status: .archived) }
        return sample(id)
    })
    let bench = makeBench(stub)
    let first = Task { await bench.model.load() }
    #expect(await eventually { await gate.arrived })
    await bench.model.load()
    await gate.open()
    await first.value
    #expect(bench.model.announcement?.status == .active)

    let updateGate = SessionGate()
    let late = DetailStub(update: { _, request in await updateGate.wait(); return sample(30, status: request.status ?? .active) },
                          delete: { _ in await updateGate.wait(); return .deleted })
    let ended = makeBench(late, id: 30)
    await ended.model.load()
    let archive = Task { await ended.model.archive() }
    #expect(await eventually { await updateGate.arrived })
    ended.current.value = false
    await updateGate.open()
    await archive.value
    #expect(ended.receipts.current == nil && ended.model.announcement?.status == .active)
    let called = Calls()
    await ended.model.delete { called.hit() }
    await ended.model.load()
    #expect(called.count == 0)
    #expect(await late.deletes == 0)
    #expect(await late.loadCount == 1)
}

@MainActor @Test func detailRevisionReloadsOnlyForOtherWriters() async {
    let stub = DetailStub()
    let bench = makeBench(stub, id: 30)
    await bench.model.load()
    await bench.model.archive()
    let loads = await stub.loadCount
    await bench.model.noteRevision(bench.signal.revision)
    #expect(await stub.loadCount == loads)
    bench.signal.bump()
    await bench.model.noteRevision(bench.signal.revision)
    #expect(await stub.loadCount == loads + 1)
    await bench.model.noteRevision(bench.signal.revision)
    #expect(await stub.loadCount == loads + 1)
}
