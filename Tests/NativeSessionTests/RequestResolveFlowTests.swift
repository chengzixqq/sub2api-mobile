import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 40 §7.4 标记已处理 (S4-08b): optimistic, undone by resolved=false, one write at a time with the last tap winning, never resent,
// read back when no answer came (00 §2.4), and nothing at all for a read-only token (S4D1-13).

/// Records the writes and the read-backs and answers through closures; `call` counts from 1 per kind.
private actor ResolveRecorder {
    enum Call: Equatable, Sendable { case write(Int, ErrorLogKind, Bool), read(Int, ErrorLogKind) }
    typealias WriteReply = @Sendable (_ call: Int, _ resolved: Bool) async throws -> Void
    typealias ReadReply = @Sendable (_ call: Int) async throws -> RequestErrorDetail
    private let onWrite: WriteReply
    private let onRead: ReadReply
    private(set) var calls: [Call] = []

    init(write: @escaping WriteReply, read: @escaping ReadReply) { onWrite = write; onRead = read }
    var writes: [Bool] { calls.compactMap { if case .write(_, _, let resolved) = $0 { resolved } else { nil } } }
    var reads: Int { calls.filter { if case .read = $0 { true } else { false } }.count }

    func write(_ id: Int, _ kind: ErrorLogKind, _ resolved: Bool) async throws {
        calls.append(.write(id, kind, resolved))
        try await onWrite(writes.count, resolved)
    }
    func read(_ id: Int, _ kind: ErrorLogKind) async throws -> RequestErrorDetail {
        calls.append(.read(id, kind))
        return try await onRead(reads)
    }
    nonisolated var source: RequestResolveSource {
        let detail = RequestDetailSource(usageRecord: { _ in nil }, errorDetail: { try await self.read($0, $1) },
                                         attempts: { _, _ in throw APIError.server(status: 404, reason: "OPS_REQUEST_NOT_FOUND") })
        return RequestResolveSource(detail: detail) { try await self.write($0, $1, $2) }
    }
}

/// A write that waits until the test opens it.
private actor Gate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}

/// The flow's session and token, and the rows it settled.
@MainActor private final class ResolveFlags {
    var isCurrent = true
    var isReadOnly = false
    var settled: [RequestErrorRecord] = []
}

@MainActor private final class ResolveBench {
    let recorder: ResolveRecorder
    let flags: ResolveFlags
    /// Receipts never time out here, so the test reads the last one.
    let receipts: ReceiptCenter
    let flow: RequestResolveFlow

    init(record: RequestErrorRecord?, write: @escaping ResolveRecorder.WriteReply = { _, _ in },
         read: @escaping ResolveRecorder.ReadReply = { _ in throw APIError.server(status: 500, reason: nil) }) {
        let recorder = ResolveRecorder(write: write, read: read), flags = ResolveFlags()
        let receipts = ReceiptCenter(sleep: { _ in throw CancellationError() })
        self.recorder = recorder; self.flags = flags; self.receipts = receipts
        flow = RequestResolveFlow(errorID: 201, kind: .request, record: record, source: recorder.source, receipts: receipts,
                                  isCurrent: { flags.isCurrent }, isReadOnly: { flags.isReadOnly },
                                  onSettled: { flags.settled.append($0) })
    }
    var receipt: Receipt? { receipts.current }
    var settled: [Bool] { flags.settled.map(\.resolved) }
    func tapReceiptButton() { if let id = receipts.current?.id { receipts.performAction(id: id) } }
}

private func resolveObject(resolved: Bool) -> [String: Any] {
    var row: [String: Any] = [
        "id": 201, "created_at": "2026-10-16T01:41:07Z", "request_id": "req-err-201", "phase": "upstream", "type": "upstream_error",
        "status_code": 502, "platform": "openai", "model": "gpt-4.1", "resolved": resolved, "message": "上游服务暂时不可用", "account_id": 4,
    ]
    if resolved { row["resolved_at"] = "2026-10-16T01:52:00Z"; row["resolved_by_user_name"] = "admin@example.invalid" }
    return row
}
private func resolveRecord(resolved: Bool = false) throws -> RequestErrorRecord {
    try JSONDecoder().decode(RequestErrorRecord.self, from: JSONSerialization.data(withJSONObject: resolveObject(resolved: resolved)))
}
private func resolveDetail(resolved: Bool) throws -> RequestErrorDetail {
    try JSONDecoder().decode(RequestErrorDetail.self, from: JSONSerialization.data(withJSONObject: resolveObject(resolved: resolved)))
}
private let noAnswer = APIError(kind: .transport, message: "连接超时")

/// Up to five seconds: under `swift test --parallel` a task can take a while to be scheduled.
@MainActor private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}

// MARK: - 标记与撤销

@MainActor @Test func markIsOptimisticAndOffersUndo() async throws {
    let gate = Gate()
    let bench = ResolveBench(record: try resolveRecord(), write: { _, _ in await gate.wait() })
    let task = Task { await bench.flow.toggle() }
    #expect(await eventually { await bench.recorder.writes == [true] })
    #expect(bench.flow.isResolved && bench.flow.isSending)
    #expect(bench.receipt?.text == "已标记为已处理" && bench.receipt?.action?.title == "撤销")
    await gate.open()
    await task.value
    #expect(await bench.recorder.calls == [.write(201, .request, true)])
    #expect(bench.settled == [true] && bench.flow.isResolved && !bench.flow.isSending)
}

@MainActor @Test func undoSendsFalseAndSettlesTheRow() async throws {
    let bench = ResolveBench(record: try resolveRecord())
    await bench.flow.toggle()
    bench.tapReceiptButton()
    #expect(await eventually { await bench.recorder.writes == [true, false] && !bench.flow.isSending })
    #expect(!bench.flow.isResolved && bench.settled == [true, false])
    #expect(bench.receipt == nil)
}

@MainActor @Test func undoDuringMarkIsSentAfterIt() async throws {
    let gate = Gate()
    let bench = ResolveBench(record: try resolveRecord(), write: { call, _ in if call == 1 { await gate.wait() } })
    let task = Task { await bench.flow.toggle() }
    #expect(await eventually { await bench.recorder.writes == [true] })
    bench.tapReceiptButton()
    #expect(await eventually { !bench.flow.isResolved })
    #expect(await bench.recorder.writes == [true])
    await gate.open()
    await task.value
    #expect(await bench.recorder.writes == [true, false])
    #expect(!bench.flow.isResolved && !bench.flow.isSending && bench.settled.isEmpty)
}

@MainActor @Test func retractFromResolvedHasNoReceipt() async throws {
    let bench = ResolveBench(record: try resolveRecord(resolved: true))
    await bench.flow.toggle()
    #expect(await bench.recorder.writes == [false])
    #expect(!bench.flow.isResolved && bench.receipt == nil && bench.settled == [false])
}

// MARK: - 失败

struct ResolveRefusal: Sendable, CustomTestStringConvertible {
    let name: String
    let error: APIError
    let markText: String
    let unmarkText: String
    var isGone = false
    var testDescription: String { name }
}
private let refusals = [
    ResolveRefusal(name: "500", error: APIError.server(status: 500, reason: nil), markText: "标记失败，请重试", unmarkText: "撤回失败，请重试"),
    ResolveRefusal(name: "gone", error: APIError.server(status: 404, reason: "OPS_ERROR_NOT_FOUND"), markText: "记录已不存在",
                   unmarkText: "记录已不存在", isGone: true),
    ResolveRefusal(name: "ops off", error: APIError.server(status: 404, reason: "OPS_DISABLED"), markText: "运维监控未开启，无法标记",
                   unmarkText: "运维监控未开启，无法标记"),
    ResolveRefusal(name: "read-only", error: APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"),
                   markText: "当前管理访问令牌只读，不能执行此操作", unmarkText: "当前管理访问令牌只读，不能执行此操作"),
    ResolveRefusal(name: "429", error: APIError.server(status: 429, envelope: ErrorEnvelope(reason: nil), retryAfter: 7),
                   markText: "请求过于频繁，请 7 秒后再试", unmarkText: "请求过于频繁，请 7 秒后再试"),
]

@MainActor @Test(arguments: refusals, [true, false])
func refusalRollsBackWithItsWords(_ refusal: ResolveRefusal, marking: Bool) async throws {
    let error = refusal.error
    let bench = ResolveBench(record: try resolveRecord(resolved: !marking), write: { _, _ in throw error })
    await bench.flow.toggle()
    #expect(await bench.recorder.calls == [.write(201, .request, marking)])
    #expect(bench.flow.isResolved == !marking && !bench.flow.isSending)
    #expect(bench.receipt?.text == (marking ? refusal.markText : refusal.unmarkText) && bench.receipt?.tone == .caution)
    #expect(bench.receipt?.action == nil && bench.settled.isEmpty)
    #expect(bench.flow.isGone == refusal.isGone && bench.flow.canToggle == !refusal.isGone)
    await bench.flow.toggle()
    #expect(await bench.recorder.writes.count == (refusal.isGone ? 1 : 2))
}

@MainActor @Test func noAnswerIsReadBack() async throws {
    let landed = try resolveDetail(resolved: true)
    let confirmed = ResolveBench(record: try resolveRecord(), write: { _, _ in throw noAnswer }, read: { _ in landed })
    await confirmed.flow.toggle()
    #expect(confirmed.flow.isResolved && confirmed.flow.record?.resolvedAt != nil && confirmed.settled == [true])
    #expect(confirmed.receipt?.text == "已标记为已处理")

    let notLanded = try resolveDetail(resolved: false)
    let gateway = ResolveBench(record: try resolveRecord(), write: { _, _ in throw APIError.server(status: 502, envelope: nil) },
                               read: { _ in notLanded })
    await gateway.flow.toggle()
    #expect(!gateway.flow.isResolved && gateway.receipt?.text == "标记失败，请重试" && gateway.settled.isEmpty)

    let gone = ResolveBench(record: try resolveRecord(), write: { _, _ in throw noAnswer },
                            read: { _ in throw APIError.server(status: 404, reason: "OPS_ERROR_NOT_FOUND") })
    await gone.flow.toggle()
    #expect(!gone.flow.isResolved && gone.flow.isGone && gone.receipt?.text == "记录已不存在")

    let unknown = ResolveBench(record: try resolveRecord(), write: { _, _ in throw noAnswer })
    await unknown.flow.toggle()
    #expect(!unknown.flow.isResolved && unknown.receipt?.text == "结果未确认，请刷新核对后再操作" && unknown.settled.isEmpty)

    for bench in [confirmed, gateway, gone, unknown] {
        #expect(await bench.recorder.writes.count == 1)
        #expect(await bench.recorder.reads == 1)
    }
}

// MARK: - 只读令牌、会话与详情

@MainActor @Test func readOnlyTokenSendsNoResolve() async throws {
    let bench = ResolveBench(record: try resolveRecord())
    bench.flags.isReadOnly = true
    await bench.flow.toggle()
    await bench.flow.undo()
    #expect(await bench.recorder.calls.isEmpty)
    #expect(!bench.flow.isResolved && bench.receipt == nil && bench.settled.isEmpty)
}

@MainActor @Test func endedSessionDropsTheResult() async throws {
    for fails in [false, true] {
        let gate = Gate()
        let bench = ResolveBench(record: try resolveRecord(), write: { _, _ in
            await gate.wait()
            if fails { throw APIError.server(status: 500, reason: nil) }
        })
        let task = Task { await bench.flow.toggle() }
        #expect(await eventually { await bench.recorder.writes == [true] })
        bench.flags.isCurrent = false
        await gate.open()
        await task.value
        #expect(bench.flow.isResolved && bench.receipt?.text == "已标记为已处理" && bench.settled.isEmpty)
    }
    let ended = ResolveBench(record: try resolveRecord())
    ended.flags.isCurrent = false
    await ended.flow.toggle()
    #expect(await ended.recorder.calls.isEmpty)
    #expect(!ended.flow.isResolved && ended.receipt == nil)
}

@MainActor @Test func detailReadsWaitForTheWrite() async throws {
    let gate = Gate()
    let bench = ResolveBench(record: nil, write: { _, _ in await gate.wait() })
    #expect(!bench.flow.canToggle)
    await bench.flow.toggle()
    #expect(await bench.recorder.calls.isEmpty)
    bench.flow.adopt(try resolveRecord())
    #expect(bench.flow.canToggle && !bench.flow.isResolved)
    let task = Task { await bench.flow.toggle() }
    #expect(await eventually { await bench.recorder.writes == [true] })
    bench.flow.adopt(try resolveRecord())
    #expect(bench.flow.isResolved)
    await gate.open()
    await task.value
    #expect(bench.flow.isResolved && bench.flow.record?.resolvedAt == nil)
    bench.flow.adopt(try resolveRecord(resolved: true))
    #expect(bench.flow.record?.resolvedAt != nil && bench.flow.record?.resolvedByUserName == "admin@example.invalid")
}
