import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S3-07: “用同一编号重试” (30 §3.4, D17, D26, S3D1-16), the foreground check (30 §3.6) and their session registry (S3D1-05).

private let siteID = UUID(uuidString: "5B000000-0000-4000-8000-000000000001")!
private let recordID = UUID(uuidString: "5B000000-0000-4000-8000-0000000000AA")!
private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func refund(id: UUID = recordID, operation: BalanceOperation = .subtract, amount: Decimal = Decimal(string: "12.5")!) -> PendingBalanceOperation {
    PendingBalanceOperation(id: id, serverID: siteID, userID: 1, amount: amount, operation: operation, notes: "退回", actorUserID: 1,
                            createdAt: start, userDisplayName: "Alice", userEmail: "alice@example.com")
}
private func alice(balance: Decimal = 0) -> AdminUser { AdminUser(id: 1, email: "alice@example.com", username: "Alice", balance: balance) }

/// Every effect of a retry, recorded in order.
@MainActor private final class RetryHarness {
    var records: [UUID: PendingBalanceOperation]
    var permission = PendingRetryPermission.allowed
    var heldUntil: Date?
    var isReadOnly = false
    var authorizes = true
    var persistFails = false
    var rememberFails = false
    var isCurrent = true
    var sendResult: Result<WriteOutcome<AdminUser>, any Error> = .success(WriteOutcome(value: AdminUser(id: 1, email: "alice@example.com")))
    /// Reported by the send before it returns.
    var events: [KeyedWriteEvent] = []
    /// Runs inside the send, after the events (another session takes over, the record is settled elsewhere…).
    var duringSend: (@MainActor () -> Void)?
    private(set) var log: [String] = []
    private(set) var gated: [GatedAction] = []
    private(set) var sent: [PendingBalanceOperation] = []
    private(set) var bodies: [Data] = []
    private(set) var remembered: [PendingBalanceOperation] = []
    private(set) var rememberedBeforeReturn = false
    private(set) var resolved: [UUID] = []
    private(set) var holds: [UUID: Date?] = [:]

    init(_ records: PendingBalanceOperation...) { self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }) }

    var effects: BalanceRetry.Effects {
        BalanceRetry.Effects(
            current: { [self] in records[$0] },
            permission: { [self] _ in permission },
            heldUntil: { [self] _ in heldUntil },
            isReadOnly: { [self] in isReadOnly },
            authorize: { [self] action in log.append("authorize"); gated.append(action); return authorizes },
            persist: { [self] record in
                log.append("persist")
                if persistFails { throw PendingMoneyError(kind: .balance, reason: .paused) }
                return PersistedMoneyWrite(record) { records[$0.id] = $0 }
            },
            remember: { [self] record in
                if rememberFails { throw PendingMoneyError(kind: .balance, reason: .paused) }
                remembered.append(record)
            },
            send: { [self] write, onEvent in
                log.append("send"); sent.append(write.record); bodies.append(try write.record.requestBody())
                for event in events { await onEvent(event) }
                rememberedBeforeReturn = !remembered.isEmpty
                duringSend?()
                return try sendResult.get()
            },
            resolve: { [self] record in log.append("resolve"); resolved.append(record.id); records[record.id] = nil },
            hold: { [self] id, date in holds[id] = date },
            isCurrent: { [self] in isCurrent },
            report: { _ in })
    }
    func run(currentBalance: Decimal? = nil) async -> BalanceRetry.Outcome {
        await BalanceRetry(effects: effects).run(recordID, currentBalance: currentBalance)
    }
}

private func text(_ outcome: BalanceRetry.Outcome) -> String {
    switch outcome {
    case .gone: "gone"
    case .refused(let text): "refused:" + text
    case .notAuthorized: "notAuthorized"
    case .notSaved(let text): "notSaved:" + text
    case .executed(let outcome): "executed:" + (outcome.replayed ? "replayed" : "new")
    case .notExecuted(let text): "notExecuted:" + text
    case .kept(let text): "kept:" + text
    case .reconfirm(let text): "reconfirm:" + text
    case .stale: "stale"
    }
}

// MARK: PendingCheckRegistry

@Test func registryRunsOneForegroundPassAtATime() throws {
    let idle = PendingCheckRegistry()
    let running = try #require(idle.startingForegroundPass())
    #expect(running.isForegroundPassRunning && !idle.isForegroundPassRunning)
    #expect(running.startingForegroundPass() == nil)
    #expect(running.endingForegroundPass().startingForegroundPass() != nil)
}

@Test func registryRetryHoldExpiresAndClears() {
    let idle = PendingCheckRegistry()
    let held = idle.holdingRetry(recordID, until: start.addingTimeInterval(10))
    #expect(held.retryHeldUntil(recordID, now: start) == start.addingTimeInterval(10))
    #expect(held.retryHeldUntil(recordID, now: start.addingTimeInterval(10)) == nil)
    #expect(held.retryHeldUntil(UUID(), now: start) == nil)
    #expect(held.holdingRetry(recordID, until: nil).retryHeldUntil(recordID, now: start) == nil)
    #expect(idle.retryHolds.isEmpty)
}

// MARK: BalanceRetry

@MainActor @Test func retryChecksPermissionHoldAndReadOnlyBeforeAnything() async {
    let other = RetryHarness(refund()); other.permission = .otherActor
    #expect(text(await other.run()) == "refused:这笔由其他管理员发起，不能用同一编号重试。")
    let held = RetryHarness(refund()); held.heldUntil = start
    #expect(text(await held.run()) == "refused:服务器暂时无法受理，稍后用同一编号重试")
    let readOnly = RetryHarness(refund()); readOnly.isReadOnly = true
    #expect(text(await readOnly.run()) == "refused:当前登录的是只读令牌，不能修改")
    let gone = RetryHarness()
    #expect(text(await gone.run()) == "gone")
    for harness in [other, held, readOnly, gone] {
        #expect(harness.log.isEmpty && harness.resolved.isEmpty && harness.holds.isEmpty)
    }
}

@MainActor @Test func retryFailedFaceIDSavesAndSendsNothing() async {
    let harness = RetryHarness(refund()); harness.authorizes = false
    #expect(text(await harness.run(currentBalance: 30)) == "notAuthorized")
    #expect(harness.log == ["authorize"])
    #expect(harness.gated == [.balanceAdjustment(Decimal(string: "12.5")!)])
    // D26: a set moves the balance from what it is now; unknown when the page has no balance.
    let set = RetryHarness(refund(operation: .set, amount: 0)); set.authorizes = false
    _ = await set.run(currentBalance: 30)
    _ = await set.run(currentBalance: nil)
    #expect(set.gated == [.balanceAdjustment(30), .balanceAdjustment(nil)])
}

@MainActor @Test func retrySavesBeforeSendingWithTheSameNumber() async throws {
    let original = refund()
    let harness = RetryHarness(original)
    #expect(text(await harness.run()) == "executed:new")
    #expect(harness.log == ["authorize", "persist", "send", "resolve"])
    let sent = try #require(harness.sent.first)
    #expect(sent.id == original.id && sent.key == original.key && sent.requestID == original.requestID)
    #expect(harness.bodies == [try original.requestBody()])
    #expect(harness.resolved == [original.id])
}

@MainActor @Test func retryUnsavedRecordIsNeverSent() async {
    let harness = RetryHarness(refund()); harness.persistFails = true
    #expect(text(await harness.run()) == "notSaved:未决记录无法保存，已暂停此操作")
    #expect(harness.log == ["authorize", "persist"])
    #expect(harness.sent.isEmpty && harness.resolved.isEmpty)
}

@MainActor @Test func retrySavesTheActionIDAsSoonAsAReplyCarriesIt() async {
    let action = UUID()
    let harness = RetryHarness(refund())
    harness.events = [.confirming(retry: 1), .actionID(action)]
    harness.sendResult = .failure(APIError.server(status: 500, reason: nil))
    _ = await harness.run()
    #expect(harness.rememberedBeforeReturn)
    #expect(harness.remembered.map(\.actionID) == [action])
    #expect(harness.remembered.first?.id == recordID)
    // A failed save of the action id does not change the result.
    let failing = RetryHarness(refund()); failing.rememberFails = true; failing.events = [.actionID(action)]
    #expect(text(await failing.run()) == "executed:new")
    #expect(failing.resolved == [recordID])
}

@MainActor @Test func retryOutcomesFollowTheResultTable() async {
    func outcome(_ error: any Error) async -> (String, RetryHarness) {
        let harness = RetryHarness(refund()); harness.sendResult = .failure(error)
        return (text(await harness.run()), harness)
    }
    let (invalid, invalidHarness) = await outcome(APIError.server(status: 400, reason: "INVALID_BALANCE"))
    #expect(invalid == "notExecuted:金额不合法，未入账" && invalidHarness.resolved == [recordID])
    for status in [401, 403, 404, 429, 500] {
        let (result, harness) = await outcome(APIError.server(status: status, reason: status == 404 ? "USER_NOT_FOUND" : nil))
        #expect(result.hasPrefix("kept:"), "\(status): \(result)")
        #expect(harness.resolved.isEmpty && harness.holds.isEmpty, "\(status)")
    }
    let until = start.addingTimeInterval(10)
    let (store, storeHarness) = await outcome(KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: until), key: "k",
                                                                 actionID: nil, lastError: nil))
    #expect(store == "kept:服务器暂时无法受理，稍后用同一编号重试")
    #expect(storeHarness.resolved.isEmpty && storeHarness.holds[recordID] == until)
    let (conflict, conflictHarness) = await outcome(KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil))
    #expect(conflict == "kept:这个操作编号已被另一笔请求占用，请先核对" && conflictHarness.resolved.isEmpty)
    for error in [URLError(.timedOut), CancellationError()] as [any Error] {
        let (result, harness) = await outcome(error)
        #expect(result == "kept:结果未确认，已记为待核对" && harness.resolved.isEmpty)
    }
}

@MainActor @Test func retryClearedSecurityRefusalKeepsTheRecordForReconfirmation() async {
    let refusal = APIError.server(status: 403, reason: "STEP_UP_REQUIRED")
    let passed = RetryHarness(refund()); passed.sendResult = .failure(refusal.withSecurityOutcome(.passed))
    let result = text(await passed.run())
    #expect(result.hasPrefix("reconfirm:") && result != "reconfirm:")
    #expect(passed.resolved.isEmpty)
    let cancelled = RetryHarness(refund()); cancelled.sendResult = .failure(refusal.withSecurityOutcome(.cancelled))
    #expect(text(await cancelled.run()).hasPrefix("kept:"))
    #expect(cancelled.resolved.isEmpty)
}

@MainActor @Test func otherActorRecordSendsNothing() async {
    // The only sender refuses on its own (MoneyRecordOrigin.checkSender), even when the page thought it was allowed.
    let harness = RetryHarness(refund()); harness.sendResult = .failure(APIError.otherActorWrite)
    #expect(text(await harness.run()) == "refused:这笔由其他管理员发起，不能用同一编号重试。")
    #expect(harness.resolved.isEmpty && harness.holds.isEmpty)
    #expect(harness.records[recordID] != nil)
}

@MainActor @Test func retryStaleSessionStillSettlesTheRecord() async {
    let done = RetryHarness(refund())
    done.duringSend = { [unowned done] in done.isCurrent = false }
    #expect(text(await done.run()) == "stale")
    #expect(done.resolved == [recordID])
    let unknown = RetryHarness(refund()); unknown.sendResult = .failure(URLError(.networkConnectionLost))
    unknown.duringSend = { [unowned unknown] in unknown.isCurrent = false }
    #expect(text(await unknown.run()) == "stale")
    #expect(unknown.resolved.isEmpty)
    // Settled elsewhere while Face ID was up: nothing is sent.
    let settled = RetryHarness(refund())
    let gone = BalanceRetry.Effects(current: { [unowned settled] id in settled.log.isEmpty ? settled.records[id] : nil },
                                    permission: settled.effects.permission, heldUntil: settled.effects.heldUntil,
                                    isReadOnly: settled.effects.isReadOnly, authorize: settled.effects.authorize, persist: settled.effects.persist,
                                    remember: settled.effects.remember, send: settled.effects.send, resolve: settled.effects.resolve,
                                    hold: settled.effects.hold, isCurrent: settled.effects.isCurrent, report: settled.effects.report)
    #expect(text(await BalanceRetry(effects: gone).run(recordID, currentBalance: nil)) == "gone")
    #expect(settled.sent.isEmpty)
}

// MARK: ForegroundReconcilePass

@MainActor private final class PassHarness {
    var records: [any PendingMoneyWrite]
    var outcomes: [UUID: BalanceReconcileOutcome] = [:]
    var continues = true
    var stopAfterFirst = false
    private(set) var checked: [UUID] = []
    private(set) var applied: [UUID] = []
    init(_ records: [any PendingMoneyWrite]) { self.records = records }
    var effects: ForegroundReconcilePass.Effects {
        ForegroundReconcilePass.Effects(
            records: { [self] in records },
            reconcileBalance: { [self] op in
                checked.append(op.id)
                if stopAfterFirst { continues = false }
                guard let outcome = outcomes[op.id] else { throw APIError.server(status: 500, reason: nil) }
                return outcome
            },
            applyExecuted: { [self] op, _ in applied.append(op.id); records.removeAll { $0.id == op.id } },
            shouldContinue: { [self] in continues })
    }
}

@MainActor @Test func foregroundPassOnlyActsOnExactMatches() async throws {
    let row = try JSONDecoder().decode(UserAdjustment.self, from: Data(#"{"id":1,"kind":"balance","operation":"subtract","user_id":1}"#.utf8))
    let exact = refund(id: UUID()), candidate = refund(id: UUID()), running = refund(id: UUID()), absent = refund(id: UUID()),
        failing = refund(id: UUID())
    let batch = PendingRedeemBatch(serverID: siteID, actorUserID: 1, createdAt: start, spec: RedeemGenerateSpec(type: .balance, value: 1, count: 1))
    let grant = PendingCompensation(serverID: siteID, actorUserID: 1, createdAt: start, userID: 1, userDisplayName: "Alice",
                                    userEmail: "alice@example.com", code: "GRANT-0001", type: .balance, value: 1)
    let harness = PassHarness([exact, batch, candidate, grant, running, absent, failing])
    harness.outcomes = [exact.id: .executed(row), candidate.id: .candidate(row), running.id: .stillRunning, absent.id: .notExecuted]
    let settled = await ForegroundReconcilePass(effects: harness.effects).run()
    #expect(settled == [exact.id])
    #expect(harness.applied == [exact.id])
    #expect(harness.checked == [exact.id, candidate.id, running.id, absent.id, failing.id])
    #expect(harness.records.count == 6)

    let stopping = PassHarness([exact, candidate])
    stopping.outcomes = [exact.id: .executed(row)]
    stopping.stopAfterFirst = true
    #expect(await ForegroundReconcilePass(effects: stopping.effects).run().isEmpty)
    #expect(stopping.checked == [exact.id] && stopping.applied.isEmpty)
}
