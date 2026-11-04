import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

/// The site clock of every case: 2027-01-15T08:00:00Z.
private let actionNow = Date(timeIntervalSince1970: 1_800_000_000)
private let transportError = APIError(kind: .transport, message: "无法连接站点")
private let unconfirmedWrite = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
private let siteDown = APIError.server(status: 500, reason: nil)
/// 503 IDEMPOTENCY_STORE_UNAVAILABLE as KeyedWriteFlow ends it: the same number may go again ten seconds later.
private let storeBusyUntil = actionNow.addingTimeInterval(10)
private let storeUnavailable = KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: storeBusyUntil), key: "k",
                                                 actionID: nil, lastError: nil)

private func account(_ id: Int, name: String = "账号", status: String = "active", schedulable: Bool = true,
                     rateLimit: TimeInterval? = nil) -> UpstreamAccount {
    UpstreamAccount(id: id, name: name, platform: "openai", type: "apikey", status: status, schedulable: schedulable,
                    rateLimitResetAt: rateLimit.map { ServerTime.utcTimestamp(actionNow.addingTimeInterval($0)) })
}
private func versioned(_ account: UpstreamAccount, _ etag: String?) -> VersionedAccount { VersionedAccount(account: account, etag: etag) }
private func versionConflict(currentETag: String) -> APIError {
    APIError.server(status: 412, envelope: ErrorEnvelope(reason: "ACCOUNT_VERSION_CONFLICT", metadata: ["current_etag": currentETag]))
}

/// Records each call with the generation it carried and answers from per-call scripts; an empty script answers like a server
/// that applied the write. A write whose generation is no longer the session's throws CancellationError, as AppModel's does.
@MainActor private final class ScriptedAccountSource: AccountWriteSource {
    enum Call: Equatable {
        case recover(id: Int, schedulable: Bool?, generation: UUID)
        case schedulable(id: Int, enabled: Bool, key: UUID?, generation: UUID)
        case read(id: Int)
        case patch(id: Int, status: AccountPatchRequest.Status?, ifMatch: String, generation: UUID)
        case put(id: Int, status: AccountPatchRequest.Status?, key: UUID?, generation: UUID)
    }
    private(set) var session: AccountWriteSession?
    var now = actionNow
    private(set) var calls: [Call] = []
    var recoverReplies: [Result<UpstreamAccount, any Error>] = []
    var schedulableReplies: [Result<UpstreamAccount, any Error>] = []
    var readReplies: [Result<VersionedAccount, any Error>] = []
    var patchReplies: [Result<VersionedAccount, any Error>] = []
    var putReplies: [Result<UpstreamAccount, any Error>] = []
    /// Writes wait here before answering.
    var gate: SessionGate?

    init(idempotentWrites: Bool = true, recoverSchedulable: Bool = true, patch: Bool = true, readOnly: Bool = false) {
        session = AccountWriteSession(generation: UUID(), idempotentWrites: idempotentWrites, recoverSchedulable: recoverSchedulable,
                                      patch: patch, isReadOnlyToken: readOnly)
    }
    var generation: UUID { session?.generation ?? UUID() }
    func switchSession() {
        guard let old = session else { return }
        session = AccountWriteSession(generation: UUID(), idempotentWrites: old.idempotentWrites, recoverSchedulable: old.recoverSchedulable,
                                      patch: old.patch, isReadOnlyToken: old.isReadOnlyToken)
    }
    var schedulableCalls: Int { calls.filter { if case .schedulable = $0 { true } else { false } }.count }
    var patchCalls: Int { calls.filter { if case .patch = $0 { true } else { false } }.count }

    var accountWriteSession: AccountWriteSession? { session }
    func serverNow() -> Date { now }
    func recoverAccountState(id: Int, schedulable: Bool?, generation: UUID) async throws -> UpstreamAccount {
        calls.append(.recover(id: id, schedulable: schedulable, generation: generation))
        try await admit(generation)
        return try Self.next(&recoverReplies) ?? account(id, schedulable: schedulable ?? false)
    }
    func setAccountSchedulable(id: Int, enabled: Bool, idempotencyKey: UUID?, generation: UUID) async throws -> WriteOutcome<UpstreamAccount> {
        calls.append(.schedulable(id: id, enabled: enabled, key: idempotencyKey, generation: generation))
        try await admit(generation)
        return WriteOutcome(value: try Self.next(&schedulableReplies) ?? account(id, schedulable: enabled))
    }
    func accountWithVersion(id: Int) async throws -> VersionedAccount {
        calls.append(.read(id: id))
        return try Self.next(&readReplies) ?? versioned(account(id), "\"cv-1\"")
    }
    func patchAccount(id: Int, body: AccountPatchRequest, ifMatch: String, generation: UUID) async throws -> VersionedAccount {
        calls.append(.patch(id: id, status: body.status, ifMatch: ifMatch, generation: generation))
        try await admit(generation)
        return try Self.next(&patchReplies) ?? versioned(account(id, status: body.status?.rawValue ?? "active"), "\"cv-2\"")
    }
    func fullUpdateAccount(id: Int, patch: AccountPatchRequest, base: UpstreamAccount?, idempotencyKey: UUID?,
                           generation: UUID) async throws -> UpstreamAccount {
        calls.append(.put(id: id, status: patch.status, key: idempotencyKey, generation: generation))
        try await admit(generation)
        return try Self.next(&putReplies) ?? account(id, status: patch.status?.rawValue ?? "active")
    }

    private func admit(_ generation: UUID) async throws {
        if let gate { await gate.wait() }
        guard generation == session?.generation else { throw CancellationError() }
    }
    private static func next<T>(_ script: inout [Result<T, any Error>]) throws -> T? {
        guard !script.isEmpty else { return nil }
        return try script.removeFirst().get()
    }
}

/// One AccountActions with its receipts (they stay up: the timer sleeps for an hour) and what it reported. A same-number
/// retry's wait returns at once, recording how many calls had gone out by then.
@MainActor private final class Harness {
    struct Wait: Equatable { let until: Date; let calls: Int }
    let source: ScriptedAccountSource
    let receipts = ReceiptCenter(sleep: { try await Task.sleep(for: $0 * 1_000) })
    private(set) var changed: [UpstreamAccount] = []
    private(set) var missing: [Int] = []
    private(set) var keys: [UUID] = []
    private(set) var waits: [Wait] = []
    private(set) var actions: AccountActions!

    init(_ source: ScriptedAccountSource = ScriptedAccountSource()) {
        self.source = source
        actions = AccountActions(source: source, receipts: receipts, onChange: { [weak self] in self?.changed.append($0) },
                                 onMissing: { [weak self] in self?.missing.append($0) },
                                 makeKey: { [weak self] in let key = UUID(); self?.keys.append(key); return key },
                                 waitUntil: { [weak self] in self?.waits.append(Wait(until: $0, calls: source.calls.count)) })
    }
    var generation: UUID { source.generation }
    var receiptText: String? { receipts.current?.text }
    var receiptButton: String? { receipts.current?.action?.title }
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

// MARK: - Scheduling switch

@MainActor @Test func stopSchedulingSendsKeyWhenIdempotentAndOffersUndo() async {
    let h = Harness()
    let outcome = await h.actions.setSchedulable(account(4), enabled: false)
    #expect(outcome == .succeeded)
    #expect(h.source.calls == [.schedulable(id: 4, enabled: false, key: h.keys.first, generation: h.generation)])
    #expect(h.keys.count == 1)
    #expect(h.changed.map(\.id) == [4] && h.changed.first?.schedulable == false)
    #expect(h.receiptText == "已停止调度" && h.receiptButton == "撤销")
    #expect(h.actions.inFlight.isEmpty)
}

@MainActor @Test func withoutIdempotentWritesSendsNoKey() async {
    let h = Harness(ScriptedAccountSource(idempotentWrites: false))
    #expect(await h.actions.setSchedulable(account(5, schedulable: false), enabled: true) == .succeeded)
    #expect(h.source.calls == [.schedulable(id: 5, enabled: true, key: nil, generation: h.generation)])
    #expect(h.keys.isEmpty)
    #expect(h.receiptText == "已启用调度" && h.receiptButton == "撤销")
}

@MainActor @Test func undoSendsReverseWithFreshKeyAndShowsNoReceipt() async {
    let h = Harness()
    await h.actions.setSchedulable(account(4), enabled: false)
    let gate = SessionGate()
    h.source.gate = gate
    h.receipts.performAction(id: h.receipts.current!.id)
    #expect(h.actions.isRunning(4))
    await gate.open()
    await settle { !h.actions.isRunning(4) }
    #expect(h.keys.count == 2 && h.keys[0] != h.keys[1])
    #expect(h.source.calls.last == .schedulable(id: 4, enabled: true, key: h.keys[1], generation: h.generation))
    #expect(h.changed.count == 2 && h.changed.last?.schedulable == true)
    #expect(h.receipts.current == nil)
}

@MainActor @Test func undoFailureShowsUndoFailedReceipt() async {
    let h = Harness()
    await h.actions.setSchedulable(account(4), enabled: false)
    h.source.schedulableReplies = [.failure(siteDown)]
    await h.tapReceipt(id: 4)
    #expect(h.receiptText == "撤销没有成功：站点暂时不可用" && h.receiptButton == nil)
    #expect(h.changed.count == 1)
}

/// S2D1-05: the receipt's button carries the session it was shown in; AppModel's write refuses another session's.
@MainActor @Test func undoAfterSessionChangeSendsOldGenerationAndIsIgnored() async {
    let h = Harness()
    await h.actions.setSchedulable(account(4), enabled: false)
    let old = h.generation
    h.source.switchSession()
    await h.tapReceipt(id: 4)
    #expect(h.source.calls.last == .schedulable(id: 4, enabled: true, key: h.keys.last, generation: old))
    #expect(h.changed.count == 1 && h.receipts.current == nil)
}

/// The account detail's AccountActions go with the page, while its receipt stays up: 撤销 still sends, and the actions are
/// let go once the receipt and its write are done.
@MainActor @Test func receiptButtonStillSendsAfterThePageReleasedItsActions() async throws {
    let source = ScriptedAccountSource()
    let receipts = ReceiptCenter(sleep: { try await Task.sleep(for: $0 * 1_000) })
    let key = UUID()
    weak var released: AccountActions?
    do {
        let actions = AccountActions(source: source, receipts: receipts, onChange: { _ in }, makeKey: { key })
        released = actions
        #expect(await actions.setSchedulable(account(4), enabled: false) == .succeeded)
    }
    #expect(receipts.current?.action?.title == "撤销")
    let receiptID = try #require(receipts.current?.id)
    receipts.performAction(id: receiptID)
    await settle { source.schedulableCalls == 2 }
    #expect(source.calls == [.schedulable(id: 4, enabled: false, key: key, generation: source.generation),
                             .schedulable(id: 4, enabled: true, key: key, generation: source.generation)])
    await settle { released == nil }
    #expect(released == nil)
}

@MainActor @Test func keyedUnconfirmedReadsBackAndConfirms() async {
    let source = ScriptedAccountSource()
    source.schedulableReplies = [.failure(unconfirmedWrite)]
    source.readReplies = [.success(versioned(account(4, schedulable: false), "\"cv-3\""))]
    let h = Harness(source)
    #expect(await h.actions.setSchedulable(account(4), enabled: false) == .succeeded)
    #expect(source.calls == [.schedulable(id: 4, enabled: false, key: h.keys.first, generation: h.generation), .read(id: 4)])
    #expect(h.receiptText == "已停止调度" && h.receiptButton == "撤销")
    #expect(h.changed.count == 1)
}

@MainActor @Test func keyedUnconfirmedMismatchOffersSameKeyRetry() async {
    let source = ScriptedAccountSource()
    source.schedulableReplies = [.failure(unconfirmedWrite)]
    source.readReplies = [.success(versioned(account(4, schedulable: true), nil))]
    let h = Harness(source)
    #expect(await h.actions.setSchedulable(account(4), enabled: false) == .unconfirmed)
    #expect(h.changed.map(\.schedulable) == [true])
    #expect(h.receiptText == "停止调度结果未确认，可用同一编号重试" && h.receiptButton == "重试")
    await h.tapReceipt(id: 4)
    #expect(h.keys.count == 1 && h.waits.isEmpty)
    #expect(source.calls.last == .schedulable(id: 4, enabled: false, key: h.keys[0], generation: h.generation))
    #expect(h.receiptText == "已停止调度")
}

/// 00 §2.5.3: STORE_UNAVAILABLE ran nothing; the read-back comes first, and 重试 sends the same number only after the cooldown.
@MainActor @Test func storeUnavailableReadsBackAndRetriesSameKeyAfterCooldown() async {
    let source = ScriptedAccountSource()
    source.schedulableReplies = [.failure(storeUnavailable)]
    source.readReplies = [.success(versioned(account(4, schedulable: true), nil))]
    let h = Harness(source)
    #expect(await h.actions.setSchedulable(account(4), enabled: false) == .notApplied)
    #expect(source.calls == [.schedulable(id: 4, enabled: false, key: h.keys.first, generation: h.generation), .read(id: 4)])
    #expect(h.changed.map(\.schedulable) == [true])
    #expect(h.receiptText == "停止调度没有生效：服务器暂时无法受理，稍后用同一编号重试" && h.receiptButton == "重试")
    #expect(h.waits.isEmpty)
    await h.tapReceipt(id: 4)
    #expect(h.waits == [Harness.Wait(until: storeBusyUntil, calls: 2)])
    #expect(h.keys.count == 1)
    #expect(source.calls.last == .schedulable(id: 4, enabled: false, key: h.keys[0], generation: h.generation))
    #expect(h.receiptText == "已停止调度")
}

@MainActor @Test func unkeyedTransportMismatchWaitsForUserRetry() async {
    let source = ScriptedAccountSource(idempotentWrites: false)
    source.schedulableReplies = [.failure(transportError)]
    source.readReplies = [.success(versioned(account(4, schedulable: true), nil))]
    let h = Harness(source)
    #expect(await h.actions.setSchedulable(account(4), enabled: false) == .notApplied)
    #expect(h.receiptText == "停止调度没有生效，可以重试" && h.receiptButton == "重试")
    #expect(source.schedulableCalls == 1)
    await h.tapReceipt(id: 4)
    #expect(source.schedulableCalls == 2)
    #expect(source.calls.last == .schedulable(id: 4, enabled: false, key: nil, generation: h.generation))
}

@MainActor @Test func readBackFailureShowsUnconfirmed() async {
    let source = ScriptedAccountSource()
    source.schedulableReplies = [.failure(unconfirmedWrite)]
    source.readReplies = [.failure(transportError)]
    let h = Harness(source)
    #expect(await h.actions.setSchedulable(account(4), enabled: false) == .unconfirmed)
    #expect(h.receiptText == "结果未确认，请刷新核对后再操作" && h.receiptButton == nil)
    #expect(h.changed.isEmpty)
}

@MainActor @Test func businessFailureShowsReasonWithoutReadBack() async {
    let source = ScriptedAccountSource()
    source.schedulableReplies = [.failure(siteDown)]
    let h = Harness(source)
    #expect(await h.actions.setSchedulable(account(4), enabled: false) == .failed)
    #expect(source.calls.count == 1)
    #expect(h.receiptText == "停止调度没有成功：站点暂时不可用" && h.receiptButton == nil)
    #expect(h.changed.isEmpty)
}

@MainActor @Test func missingAccountCallsOnMissing() async {
    let source = ScriptedAccountSource()
    source.schedulableReplies = [.failure(APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND"))]
    let h = Harness(source)
    #expect(await h.actions.setSchedulable(account(4), enabled: false) == .missing)
    #expect(h.missing == [4])
    #expect(h.receiptText == "停止调度没有成功：这个账号已删除或不在本工作区")
}

@MainActor @Test func clearedSecurityPromptOffersRetryWithSameKey() async {
    let source = ScriptedAccountSource()
    source.schedulableReplies = [.failure(APIError.server(status: 423, reason: nil).withSecurityOutcome(.passed))]
    let h = Harness(source)
    #expect(await h.actions.setSchedulable(account(4), enabled: false) == .reconfirm)
    #expect(h.receiptText == "合规确认已完成，请重新确认后发送" && h.receiptButton == "重试")
    await h.tapReceipt(id: 4)
    #expect(source.schedulableCalls == 2 && h.keys.count == 1)
    #expect(source.calls.last == .schedulable(id: 4, enabled: false, key: h.keys[0], generation: h.generation))
}

@MainActor @Test func cancelledSecurityPromptAndCancellationAreSilent() async {
    for error in [APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.cancelled) as any Error, CancellationError()] {
        let source = ScriptedAccountSource()
        source.schedulableReplies = [.failure(error)]
        let h = Harness(source)
        #expect(await h.actions.setSchedulable(account(4), enabled: false) == .ignored)
        #expect(h.receipts.current == nil && h.changed.isEmpty)
    }
}

@MainActor @Test func readOnlyTokenSendsNothing() async {
    let h = Harness(ScriptedAccountSource(readOnly: true))
    #expect(await h.actions.setSchedulable(account(4), enabled: false) == .failed)
    #expect(h.receiptText == "当前管理访问令牌只读，不能执行此操作")
    #expect(await h.actions.recover(account(7, status: "error", schedulable: false), enableScheduling: true) == .failed)
    #expect(await h.actions.enableAccount(account(10, status: "inactive")) == .failed)
    #expect(h.source.calls.isEmpty && h.changed.isEmpty)
}

@MainActor @Test func secondTapWhileRunningIsIgnored() async {
    let h = Harness()
    let gate = SessionGate()
    h.source.gate = gate
    let first = Task { await h.actions.setSchedulable(account(4), enabled: false) }
    await arrived(gate)
    #expect(h.actions.isRunning(4))
    #expect(await h.actions.setSchedulable(account(4), enabled: false) == .ignored)
    let other = Task { await h.actions.setSchedulable(account(5), enabled: false) }
    await settle { h.actions.isRunning(5) }
    #expect(h.source.schedulableCalls == 2)
    await gate.open()
    #expect(await first.value == .succeeded)
    #expect(await other.value == .succeeded)
    #expect(!h.actions.isRunning(4) && !h.actions.isRunning(5))
}

@MainActor @Test func sessionChangeDuringWriteDropsResult() async {
    let h = Harness()
    let gate = SessionGate()
    h.source.gate = gate
    let write = Task { await h.actions.setSchedulable(account(4), enabled: false) }
    await arrived(gate)
    h.source.switchSession()
    await gate.open()
    #expect(await write.value == .ignored)
    #expect(h.receipts.current == nil && h.changed.isEmpty)
}

// MARK: - Recover

@MainActor @Test func recoverWithCapabilitySendsSchedulableTrueOnce() async {
    let source = ScriptedAccountSource(recoverSchedulable: true)
    source.recoverReplies = [.success(account(7, schedulable: true))]
    let h = Harness(source)
    #expect(await h.actions.recover(account(7, status: "error", schedulable: false), enableScheduling: true) == .succeeded)
    #expect(source.calls == [.recover(id: 7, schedulable: true, generation: h.generation)])
    #expect(h.receiptText == "已恢复 · 参与调度" && h.receiptButton == nil)
    #expect(h.changed.map(\.id) == [7])
}

@MainActor @Test func recoverWithoutCapabilityRecoversThenEnables() async {
    let source = ScriptedAccountSource(recoverSchedulable: false)
    source.recoverReplies = [.success(account(7, schedulable: false))]
    let h = Harness(source)
    #expect(await h.actions.recover(account(7, status: "error", schedulable: false), enableScheduling: true) == .succeeded)
    #expect(source.calls == [.recover(id: 7, schedulable: nil, generation: h.generation),
                             .schedulable(id: 7, enabled: true, key: h.keys.first, generation: h.generation)])
    #expect(h.receiptText == "已恢复 · 参与调度")
    #expect(h.changed.count == 1 && h.changed.last?.schedulable == true)
}

@MainActor @Test func recoverFallbackSecondStepFailureOffersEnableScheduling() async {
    let source = ScriptedAccountSource(recoverSchedulable: false)
    source.recoverReplies = [.success(account(7, schedulable: false))]
    source.schedulableReplies = [.failure(siteDown)]
    source.readReplies = [.success(versioned(account(7, schedulable: false), nil))]
    let h = Harness(source)
    #expect(await h.actions.recover(account(7, status: "error", schedulable: false), enableScheduling: true) == .recoveredPaused)
    #expect(h.receiptText == "已恢复 · 仍暂停调度" && h.receiptButton == "启用调度")
    await h.tapReceipt(id: 7)
    #expect(h.keys.count == 2)
    #expect(source.calls.last == .schedulable(id: 7, enabled: true, key: h.keys[1], generation: h.generation))
    #expect(h.receiptText == "已启用调度" && h.receiptButton == "撤销")
}

@MainActor @Test func recoveredSchedulableFailedReadsBack() async {
    let partial = APIError.server(status: 500, envelope: ErrorEnvelope(reason: "ACCOUNT_RECOVERED_SCHEDULABLE_FAILED", metadata: ["recovered": "true"]))
    let cases: [(read: Result<VersionedAccount, any Error>, text: String, button: String?, changes: Int)] = [
        (.success(versioned(account(7, schedulable: true), nil)), "已恢复 · 参与调度", nil, 1),
        (.success(versioned(account(7, schedulable: false), nil)), "已恢复 · 仍暂停调度", "启用调度", 1),
        (.failure(transportError), "已恢复 · 仍暂停调度", "启用调度", 0)
    ]
    for item in cases {
        let source = ScriptedAccountSource(recoverSchedulable: true)
        source.recoverReplies = [.failure(partial)]
        source.readReplies = [item.read]
        let h = Harness(source)
        await h.actions.recover(account(7, status: "error", schedulable: false), enableScheduling: true)
        #expect(source.calls.filter { if case .recover = $0 { true } else { false } }.count == 1)
        #expect(source.calls.last == .read(id: 7))
        #expect(h.receiptText == item.text && h.receiptButton == item.button)
        #expect(h.changed.count == item.changes)
    }
}

@MainActor @Test func recoverOnlySendsNoBody() async {
    let source = ScriptedAccountSource(recoverSchedulable: true)
    source.recoverReplies = [.success(account(7, schedulable: false)), .success(account(3, schedulable: true))]
    let h = Harness(source)
    #expect(await h.actions.recover(account(7, status: "error", schedulable: false), enableScheduling: false) == .recoveredPaused)
    #expect(source.calls == [.recover(id: 7, schedulable: nil, generation: h.generation)])
    #expect(h.receiptText == "已恢复 · 仍暂停调度" && h.receiptButton == "启用调度")
    #expect(await h.actions.recover(account(3, rateLimit: 600), enableScheduling: false) == .succeeded)
    #expect(source.calls.last == .recover(id: 3, schedulable: nil, generation: h.generation))
    #expect(h.receiptText == "已恢复 · 参与调度")
}

@MainActor @Test func recoverTransportReadsBackWithServerNow() async {
    // Recovered: the window is past on the site clock, so the fallback's second step follows.
    let source = ScriptedAccountSource(recoverSchedulable: false)
    source.recoverReplies = [.failure(transportError)]
    source.readReplies = [.success(versioned(account(7, schedulable: false, rateLimit: -60), nil))]
    let h = Harness(source)
    #expect(await h.actions.recover(account(7, status: "error", schedulable: false), enableScheduling: true) == .succeeded)
    #expect(source.calls == [.recover(id: 7, schedulable: nil, generation: h.generation), .read(id: 7),
                             .schedulable(id: 7, enabled: true, key: h.keys.first, generation: h.generation)])
    #expect(h.receiptText == "已恢复 · 参与调度")
    // Not recovered: still in error, or the window ends after the site's now even though the device clock is past it.
    for read in [account(7, status: "error", schedulable: false), account(7, schedulable: false, rateLimit: 60)] {
        let pending = ScriptedAccountSource(recoverSchedulable: false)
        pending.recoverReplies = [.failure(transportError)]
        pending.readReplies = [.success(versioned(read, nil))]
        let other = Harness(pending)
        #expect(await other.actions.recover(account(7, status: "error", schedulable: false), enableScheduling: true) == .notApplied)
        #expect(other.receiptText == "恢复状态没有生效，可以重试" && other.receiptButton == "重试")
        #expect(pending.schedulableCalls == 0)
    }
    let later = ScriptedAccountSource(recoverSchedulable: false)
    later.now = actionNow.addingTimeInterval(120)
    later.recoverReplies = [.failure(transportError)]
    later.readReplies = [.success(versioned(account(7, schedulable: false, rateLimit: 60), nil))]
    let third = Harness(later)
    #expect(await third.actions.recover(account(7, status: "error", schedulable: false), enableScheduling: false) == .recoveredPaused)
}

// MARK: - Enable account

private let grok = account(10, name: "Grok-旧-01", status: "inactive")

@MainActor @Test func enableAccountReadsVersionThenPatchesActive() async {
    let source = ScriptedAccountSource()
    source.readReplies = [.success(versioned(grok, "\"cv-4\""))]
    source.patchReplies = [.success(versioned(account(10, name: "Grok-旧-01"), "\"cv-5\""))]
    let h = Harness(source)
    #expect(await h.actions.enableAccount(grok) == .succeeded)
    #expect(source.calls == [.read(id: 10), .patch(id: 10, status: .active, ifMatch: "\"cv-4\"", generation: h.generation)])
    #expect(h.receiptText == "已启用账号「Grok-旧-01」" && h.receiptButton == "撤销")
    #expect(h.changed.last?.status == "active")
}

@MainActor @Test func enableAccountUsesGivenETag() async {
    let h = Harness()
    #expect(await h.actions.enableAccount(grok, etag: "\"cv-7\"") == .succeeded)
    #expect(h.source.calls == [.patch(id: 10, status: .active, ifMatch: "\"cv-7\"", generation: h.generation)])
}

@MainActor @Test func enableAccountUndoPatchesInactiveWithResponseETag() async {
    let source = ScriptedAccountSource()
    source.patchReplies = [.success(versioned(account(10, name: "Grok-旧-01"), "\"cv-5\""))]
    let h = Harness(source)
    await h.actions.enableAccount(grok, etag: "\"cv-4\"")
    await h.tapReceipt(id: 10)
    #expect(source.calls.last == .patch(id: 10, status: .inactive, ifMatch: "\"cv-5\"", generation: h.generation))
    #expect(h.changed.count == 2 && h.changed.last?.status == "inactive")
    #expect(h.receipts.current == nil)
}

@MainActor @Test func enableAccountVersionConflictRetriesSilentlyOnce() async {
    // The read-back's ETag, then metadata.current_etag when the read has none.
    for (readTag, expected) in [("\"cv-8\"" as String?, "\"cv-8\""), (nil, "\"cv-9\"")] {
        let source = ScriptedAccountSource()
        source.patchReplies = [.failure(versionConflict(currentETag: "\"cv-9\"")), .success(versioned(account(10, name: "Grok-旧-01"), "\"cv-10\""))]
        source.readReplies = [.success(versioned(grok, readTag))]
        let h = Harness(source)
        #expect(await h.actions.enableAccount(grok, etag: "\"cv-4\"") == .succeeded)
        #expect(source.calls.last == .patch(id: 10, status: .active, ifMatch: expected, generation: h.generation))
        #expect(h.receiptText == "已启用账号「Grok-旧-01」")
    }
    let source = ScriptedAccountSource()
    source.patchReplies = [.failure(versionConflict(currentETag: "\"cv-9\"")), .failure(versionConflict(currentETag: "\"cv-10\""))]
    source.readReplies = [.success(versioned(grok, "\"cv-9\""))]
    let h = Harness(source)
    #expect(await h.actions.enableAccount(grok, etag: "\"cv-4\"") == .failed)
    #expect(source.patchCalls == 2)
    #expect(h.receiptText == "启用账号没有成功：账号已被其他人修改" && h.receiptButton == nil)
}

@MainActor @Test func enableAccountConflictAlreadyActiveCountsAsSuccess() async {
    let source = ScriptedAccountSource()
    source.patchReplies = [.failure(versionConflict(currentETag: "\"cv-9\""))]
    source.readReplies = [.success(versioned(account(10, name: "Grok-旧-01"), "\"cv-9\""))]
    let h = Harness(source)
    #expect(await h.actions.enableAccount(grok, etag: "\"cv-4\"") == .succeeded)
    #expect(source.patchCalls == 1)
    #expect(h.receiptText == "已启用账号「Grok-旧-01」" && h.receiptButton == "撤销")
    await h.tapReceipt(id: 10)
    #expect(source.calls.last == .patch(id: 10, status: .inactive, ifMatch: "\"cv-9\"", generation: h.generation))
}

@MainActor @Test func enableAccountConflictWithThirdValueFails() async {
    let source = ScriptedAccountSource()
    source.patchReplies = [.failure(versionConflict(currentETag: "\"cv-9\""))]
    source.readReplies = [.success(versioned(account(10, name: "Grok-旧-01", status: "error"), "\"cv-9\""))]
    let h = Harness(source)
    #expect(await h.actions.enableAccount(grok, etag: "\"cv-4\"") == .failed)
    #expect(source.patchCalls == 1)
    #expect(h.receiptText == "启用账号没有成功：账号已被其他人修改")
    #expect(h.changed.last?.status == "error")
}

@MainActor @Test func enableAccountWithoutPatchUsesFullUpdate() async {
    let source = ScriptedAccountSource(patch: false)
    let h = Harness(source)
    #expect(await h.actions.enableAccount(grok) == .succeeded)
    #expect(source.calls == [.put(id: 10, status: .active, key: h.keys.first, generation: h.generation)])
    await h.tapReceipt(id: 10)
    #expect(h.keys.count == 2)
    #expect(source.calls.last == .put(id: 10, status: .inactive, key: h.keys[1], generation: h.generation))
    let unkeyed = Harness(ScriptedAccountSource(idempotentWrites: false, patch: false))
    await unkeyed.actions.enableAccount(grok)
    #expect(unkeyed.source.calls == [.put(id: 10, status: .active, key: nil, generation: unkeyed.generation)])
}

@MainActor @Test func enableAccountFullUpdateStoreUnavailableRetriesSameKeyAfterCooldown() async {
    let source = ScriptedAccountSource(patch: false)
    source.putReplies = [.failure(storeUnavailable)]
    source.readReplies = [.success(versioned(grok, nil))]
    let h = Harness(source)
    #expect(await h.actions.enableAccount(grok) == .notApplied)
    #expect(h.receiptText == "启用账号没有生效：服务器暂时无法受理，稍后用同一编号重试" && h.receiptButton == "重试")
    await h.tapReceipt(id: 10)
    #expect(h.waits == [Harness.Wait(until: storeBusyUntil, calls: 2)])
    #expect(h.keys.count == 1)
    #expect(source.calls.last == .put(id: 10, status: .active, key: h.keys[0], generation: h.generation))
}

/// A site that sends no ETag takes the PUT fallback; its 重试 keeps the number that PUT carried.
@MainActor @Test func enableAccountFullUpdateWithoutETagRetriesUnderSameKey() async {
    let source = ScriptedAccountSource()
    source.readReplies = Array(repeating: .success(versioned(grok, nil)), count: 3)
    source.putReplies = [.failure(unconfirmedWrite)]
    let h = Harness(source)
    #expect(await h.actions.enableAccount(grok) == .unconfirmed)
    #expect(h.receiptText == "启用账号结果未确认，可用同一编号重试" && h.receiptButton == "重试")
    await h.tapReceipt(id: 10)
    #expect(h.keys.count == 1)
    #expect(source.calls.last == .put(id: 10, status: .active, key: h.keys[0], generation: h.generation))
}

@MainActor @Test func enableAccountTransportReadsBack() async {
    let source = ScriptedAccountSource()
    source.patchReplies = [.failure(transportError)]
    source.readReplies = [.success(versioned(account(10, name: "Grok-旧-01"), "\"cv-5\""))]
    let h = Harness(source)
    #expect(await h.actions.enableAccount(grok, etag: "\"cv-4\"") == .succeeded)
    #expect(h.receiptText == "已启用账号「Grok-旧-01」")
    let pending = ScriptedAccountSource()
    pending.patchReplies = [.failure(transportError)]
    pending.readReplies = [.success(versioned(grok, "\"cv-6\""))]
    let other = Harness(pending)
    #expect(await other.actions.enableAccount(grok, etag: "\"cv-4\"") == .notApplied)
    #expect(other.receiptText == "启用账号没有生效，可以重试" && other.receiptButton == "重试")
    await other.tapReceipt(id: 10)
    #expect(pending.calls.last == .patch(id: 10, status: .active, ifMatch: "\"cv-6\"", generation: other.generation))
}
