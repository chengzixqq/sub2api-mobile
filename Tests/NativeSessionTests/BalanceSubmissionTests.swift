import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S3-08: the keypad's first send (30 §3.4, R04, R05, D26, S3D1-16): Face ID, the record saved at confirmation, the result.

private let siteID = UUID(uuidString: "5D000000-0000-4000-8000-000000000001")!
private let recordID = UUID(uuidString: "5D000000-0000-4000-8000-0000000000AA")!
private let openedAt = Date(timeIntervalSince1970: 1_800_000_000)
private let confirmedAt = openedAt.addingTimeInterval(20)

private func topUp() -> PendingBalanceOperation {
    PendingBalanceOperation(id: recordID, serverID: siteID, userID: 3, amount: 50, operation: .add, notes: "补偿", actorUserID: 1,
                            createdAt: openedAt, userDisplayName: "王小明", userEmail: "xm.wang@example.com")
}
private func wang(balance: Decimal = Decimal(string: "62.4")!) -> AdminUser {
    AdminUser(id: 3, email: "xm.wang@example.com", username: "王小明", balance: balance)
}

/// Every effect of a first send, recorded in order.
@MainActor private final class SubmissionHarness {
    var authorizes = true
    var persistFails = false
    var rememberFails = false
    var resolveFails = false
    var isCurrent = true
    var sendResult: Result<WriteOutcome<AdminUser>, any Error> = .success(WriteOutcome(value: wang()))
    /// Reported by the send before it returns.
    var events: [KeyedWriteEvent] = []
    /// Runs inside the send, after the events (another session takes over…).
    var duringSend: (@MainActor () -> Void)?
    private(set) var log: [String] = []
    private(set) var gated: [GatedAction] = []
    private(set) var saved: [PendingBalanceOperation] = []
    private(set) var sent: [PendingBalanceOperation] = []
    private(set) var bodies: [Data] = []
    private(set) var remembered: [PendingBalanceOperation] = []
    private(set) var rememberedBeforeReturn = false
    private(set) var resolved: [UUID] = []
    private(set) var holds: [UUID: Date?] = [:]
    private(set) var progress: [BalanceWriteProgress] = []
    private(set) var reported = 0

    var effects: BalanceSubmission.Effects {
        BalanceSubmission.Effects(
            authorize: { [self] action in log.append("authorize"); gated.append(action); return authorizes },
            persist: { [self] record in
                log.append("persist")
                if persistFails { throw PendingMoneyError(kind: .balance, reason: .paused) }
                return PersistedMoneyWrite(record) { saved.append($0) }
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
            resolve: { [self] record in
                log.append("resolve")
                if resolveFails { throw PendingMoneyError(kind: .balance, reason: .paused) }
                resolved.append(record.id)
            },
            holdRetry: { [self] id, date in holds[id] = date },
            isCurrent: { [self] in isCurrent },
            now: { confirmedAt },
            report: { [self] _ in reported += 1 })
    }
    func run(gated action: GatedAction = .balanceAdjustment(50)) async -> BalanceSubmission.Outcome {
        await BalanceSubmission(effects: effects).run(topUp(), gated: action) { [self] in progress.append($0) }
    }
}

private func text(_ outcome: BalanceSubmission.Outcome) -> String {
    switch outcome {
    case .notAuthorized: "notAuthorized"
    case .notSaved(let text): "notSaved:" + text
    case .executed(let outcome): "executed:" + (outcome.replayed ? "replayed" : outcome.recovered ? "recovered" : "new")
    case .notExecuted(let text): "notExecuted:" + text
    case .pending(let text): "pending:" + text
    case .keyConflict(let text): "keyConflict:" + text
    case .reconfirm(let record, let notice): "reconfirm:\(record.id == recordID):" + notice
    case .stale: "stale"
    }
}

@MainActor @Test func failedFaceIDSavesAndSendsNothing() async {
    let denied = SubmissionHarness(); denied.authorizes = false
    #expect(text(await denied.run(gated: .balanceAdjustment(150))) == "notAuthorized")
    #expect(denied.gated == [.balanceAdjustment(150)])
    #expect(denied.log == ["authorize"] && denied.saved.isEmpty && denied.sent.isEmpty)
    let switched = SubmissionHarness(); switched.isCurrent = false
    #expect(text(await switched.run()) == "stale")
    #expect(switched.log == ["authorize"] && switched.sent.isEmpty)
}

@MainActor @Test func recordIsSavedBeforeSendingWithTheConfirmationNumber() async throws {
    let harness = SubmissionHarness()
    #expect(text(await harness.run()) == "executed:new")
    #expect(harness.log == ["authorize", "persist", "send", "resolve"])
    let sent = try #require(harness.sent.first)
    #expect(harness.saved == [sent])
    #expect(sent.id == recordID && sent.key == recordID.uuidString.lowercased() && sent.createdAt == confirmedAt)
    #expect(harness.bodies == [try topUp().requestBody()])
    #expect(harness.progress.first == .submitting)
    #expect(harness.resolved == [recordID])
}

@MainActor @Test func unsavedRecordIsNeverSent() async {
    let harness = SubmissionHarness(); harness.persistFails = true
    #expect(text(await harness.run()) == "notSaved:" + PendingMoneyKind.balance.unsavedMessage)
    #expect(harness.sent.isEmpty && harness.resolved.isEmpty && harness.progress.isEmpty)
}

@MainActor @Test func actionIDIsSavedAsSoonAsAnyReplyCarriesIt() async throws {
    let action = UUID()
    let harness = SubmissionHarness(); harness.events = [.actionID(action)]
    harness.sendResult = .failure(APIError.server(status: 500, reason: nil))
    #expect(text(await harness.run()) == "pending:" + BalanceReconciliation.unconfirmedReceipt)
    #expect(harness.rememberedBeforeReturn)
    let remembered = try #require(harness.remembered.first)
    #expect(remembered.actionID == action && remembered.id == recordID && remembered.createdAt == confirmedAt)
    #expect(harness.progress == [.submitting])
    let failing = SubmissionHarness(); failing.events = [.actionID(action)]; failing.rememberFails = true
    #expect(text(await failing.run()) == "executed:new")
}

@MainActor @Test func waitingEventsBecomeProgress() async {
    let harness = SubmissionHarness()
    harness.events = [.confirming(retry: 1), .waitingForServer(elapsedSeconds: 3), .actionID(UUID()), .waitingForServer(elapsedSeconds: 4)]
    _ = await harness.run()
    #expect(harness.progress == [.submitting, .confirming(retry: 1), .waiting(elapsedSeconds: 3), .waiting(elapsedSeconds: 4)])
}

@MainActor @Test func executedWriteResolvesTheRecord() async {
    for (outcome, expected) in [(WriteOutcome(value: wang(), replayed: true), "executed:replayed"), (WriteOutcome(value: wang(), degraded: true), "executed:new"),
                                (WriteOutcome(value: wang(), recovered: true), "executed:recovered")] {
        let harness = SubmissionHarness(); harness.sendResult = .success(outcome)
        #expect(text(await harness.run()) == expected)
        #expect(harness.resolved == [recordID])
    }
    let unsaved = SubmissionHarness(); unsaved.resolveFails = true
    #expect(text(await unsaved.run()) == "executed:new")
    #expect(unsaved.reported == 1)
}

@MainActor @Test func definiteRefusalsResolve() async {
    let refusals: [(any Error, String)] = [
        (APIError.server(status: 400, reason: "INVALID_BALANCE"), "金额不合法，未入账"),
        (KeyedWriteFailure(disposition: .needsNewKey(.invalid), key: "k", actionID: nil, lastError: nil), "请求格式错误，未入账"),
        (APIError.server(status: 400, reason: nil), "请求无效（错误码 HTTP 400），未入账"),
        (APIError.server(status: 404, reason: "USER_NOT_FOUND"), "用户不存在或已删除"),
        (APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"), APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY").localizedDescription),
        (APIError.server(status: 429, reason: nil), APIError.server(status: 429, reason: nil).localizedDescription),
    ]
    for (error, message) in refusals {
        let harness = SubmissionHarness(); harness.sendResult = .failure(error)
        #expect(text(await harness.run()) == "notExecuted:" + message)
        #expect(harness.resolved == [recordID], Comment(rawValue: message))
    }
    let unresolved = SubmissionHarness(); unresolved.resolveFails = true
    unresolved.sendResult = .failure(APIError.server(status: 400, reason: "INVALID_BALANCE"))
    #expect(text(await unresolved.run()) == "notExecuted:" + BalanceChangeCopy.unresolvedRejection)
}

@MainActor @Test func uncertainResultsKeepTheRecord() async {
    let unconfirmed: [any Error] = [
        KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil),
        KeyedWriteFailure(disposition: .unconfirmed(.stillProcessing, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil),
        APIError.server(status: 500, reason: nil), APIError(kind: .transport, message: "网络中断"), URLError(.timedOut),
    ]
    for error in unconfirmed {
        let harness = SubmissionHarness(); harness.sendResult = .failure(error)
        #expect(text(await harness.run()) == "pending:" + BalanceReconciliation.unconfirmedReceipt)
        #expect(harness.resolved.isEmpty && harness.holds.isEmpty)
    }
    let until = confirmedAt.addingTimeInterval(30)
    let store = SubmissionHarness()
    store.sendResult = .failure(KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: until), key: "k", actionID: nil, lastError: nil))
    #expect(text(await store.run()) == "pending:" + BalanceReconciliation.storeUnavailableMessage)
    #expect(store.resolved.isEmpty && store.holds[recordID] == until)
}

@MainActor @Test func keyConflictKeepsRecordAndSheet() async {
    let harness = SubmissionHarness()
    harness.sendResult = .failure(KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil))
    #expect(text(await harness.run()) == "keyConflict:" + BalanceReconciliation.keyConflictMessage)
    #expect(harness.resolved.isEmpty)
}

@MainActor @Test func laterKeepsTheRecordPending() async {
    let harness = SubmissionHarness(); harness.sendResult = .failure(CancellationError())
    #expect(text(await harness.run()) == "pending:" + BalanceReconciliation.unconfirmedReceipt)
    #expect(harness.resolved.isEmpty && harness.saved.count == 1)
}

@MainActor @Test func clearedSecurityRefusalConfirmsTheSameNumberAgain() async {
    for refusal in [APIError.server(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED"), APIError.server(status: 403, reason: "STEP_UP_REQUIRED")] {
        let harness = SubmissionHarness(); harness.sendResult = .failure(refusal.withSecurityOutcome(.passed))
        #expect(text(await harness.run()) == "reconfirm:true:" + refusal.withSecurityOutcome(.passed).localizedDescription)
        #expect(harness.resolved == [recordID])
        let cancelled = SubmissionHarness(); cancelled.sendResult = .failure(refusal.withSecurityOutcome(.cancelled))
        #expect(text(await cancelled.run()).hasPrefix("notExecuted:"))
        #expect(cancelled.resolved == [recordID])
    }
}

@MainActor @Test func staleSessionStillSettlesTheRecord() async {
    let executed = SubmissionHarness()
    executed.duringSend = { [unowned executed] in executed.isCurrent = false }
    #expect(text(await executed.run()) == "stale")
    #expect(executed.resolved == [recordID])
    let uncertain = SubmissionHarness(); uncertain.sendResult = .failure(APIError.server(status: 502, reason: nil))
    uncertain.duringSend = { [unowned uncertain] in uncertain.isCurrent = false }
    #expect(text(await uncertain.run()) == "stale")
    #expect(uncertain.resolved.isEmpty)
}
