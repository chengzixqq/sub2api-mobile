import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S6-09: a compensation's first send and “用同一编号重试” (60 §19.4, R03, R04, R05, S6D1-08, S6D1-15): the gate or the retry
// permission first, Face ID (balance only) before the record is saved, a record that cannot be saved is never sent, and the
// answer follows S6-08's GrantResultAction; a grant bumps the user's pages and the redeem list.

private let siteID = UUID(uuidString: "6E000000-0000-4000-8000-000000000001")!
private let grantID = UUID(uuidString: "6E000000-0000-4000-8000-0000000000AA")!
private let otherID = UUID(uuidString: "6E000000-0000-4000-8000-0000000000BB")!
private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let code = "a3f01b2c3d4e5f60718293a4b5c6d4e8"

private func compensation(_ type: CompensationType = .balance, value: Decimal = 10) -> PendingCompensation {
    PendingCompensation(id: grantID, serverID: siteID, actorUserID: 1, createdAt: start, userID: 3, userDisplayName: "王小明", userEmail: "wang@example.com",
                        code: code, type: type, value: value, groupID: type == .subscription ? 4 : nil, validityDays: type == .subscription ? 30 : nil)
}
private func issued(_ record: PendingCompensation = compensation()) -> AdminRedeemCode {
    AdminRedeemCode(id: 95_001, code: record.code, type: record.type.rawValue, value: record.value, status: "used", usedBy: record.userID)
}
private func keyed(_ disposition: KeyedWriteFailure.Disposition) -> KeyedWriteFailure {
    KeyedWriteFailure(disposition: disposition, key: grantID.uuidString.lowercased(), actionID: nil, lastError: nil)
}
private let allowed = RedeemRetryContext(permission: .allowed, isReadOnly: false, retryNotBefore: nil, isLegacyServer: false, isPastIdempotencyExpiry: false)

/// Every effect, recorded in order.
@MainActor private final class GrantHarness {
    var gate: PendingMoneyGate = .clear
    var authorizes = true
    var persistFails = false
    var isCurrent = true
    var context = allowed
    var stored: [UUID: PendingCompensation] = [:]
    var sendResult: Result<WriteOutcome<AdminRedeemCode>, any Error> = .success(WriteOutcome(value: issued()))
    var events: [KeyedWriteEvent] = []
    var switchesSessionDuringSend = false
    private(set) var log: [String] = []
    private(set) var gated: [GatedAction] = []
    private(set) var persisted: [PendingCompensation] = []
    private(set) var resolved: [UUID] = []
    private(set) var holds: [UUID: Date] = [:]
    private(set) var bumps: [Int] = []
    private(set) var balanceBumps: [Int] = []
    private(set) var progress: [BalanceWriteProgress] = []

    var effects: CompensationSubmission.Effects {
        CompensationSubmission.Effects(
            gate: { [self] _ in gate },
            authorize: { [self] action in log.append("authorize"); gated.append(action); return authorizes },
            persist: { [self] record in
                log.append("persist")
                if persistFails { throw PendingMoneyError(kind: .compensation, reason: .unsaved) }
                persisted.append(record); stored[record.id] = record
                return PersistedMoneyWrite(record) { _ in }
            },
            send: { [self] _, onEvent in
                log.append("send")
                for event in events { await onEvent(event) }
                if switchesSessionDuringSend { isCurrent = false }
                return try sendResult.get()
            },
            resolve: { [self] record in log.append("resolve"); resolved.append(record.id); stored[record.id] = nil },
            record: { [self] in stored[$0] },
            retryContext: { [self] _ in context },
            hold: { [self] id, date in holds[id] = date },
            bump: { [self] in bumps.append($0) },
            bumpBalance: { [self] in balanceBumps.append($0) },
            listChanged: { [self] in log.append("listChanged") },
            isCurrent: { [self] in isCurrent },
            now: { start })
    }
    func grant(_ record: PendingCompensation = compensation()) async -> CompensationSubmission.Outcome {
        await CompensationSubmission(effects: effects).grant(record) { [self] in progress.append($0) }
    }
    func retry(_ id: UUID = grantID) async -> CompensationSubmission.Outcome {
        await CompensationSubmission(effects: effects).retry(id) { [self] in progress.append($0) }
    }
}

// MARK: First send

@MainActor @Test func gateFaceIDPersistOrder() async {
    let blocked = GrantHarness(); blocked.gate = .blocked([otherID])
    #expect(await blocked.grant() == .blocked(otherID))
    #expect(blocked.log.isEmpty)
    let paused = GrantHarness(); paused.gate = .paused(.compensation)
    #expect(await paused.grant() == .paused(PendingMoneyKind.compensation.unreadableMessage))
    #expect(paused.log.isEmpty)

    // Balance: Face ID by the amount before anything is saved; denied, nothing is saved or sent.
    let denied = GrantHarness(); denied.authorizes = false
    #expect(await denied.grant() == .notAuthorized)
    #expect(denied.log == ["authorize"] && denied.gated == [.compensation(10)] && denied.persisted.isEmpty)

    let unsaved = GrantHarness(); unsaved.persistFails = true
    #expect(await unsaved.grant() == .notSaved("未决记录无法保存，已暂停发放"))
    #expect(unsaved.log == ["authorize", "persist"] && unsaved.progress.isEmpty)

    // Concurrency and subscriptions are not money: no Face ID.
    for type in [CompensationType.concurrency, .subscription] {
        let harness = GrantHarness(); harness.sendResult = .success(WriteOutcome(value: issued(compensation(type, value: type == .concurrency ? 2 : 30))))
        _ = await harness.grant(compensation(type, value: type == .concurrency ? 2 : 30))
        #expect(harness.log == ["persist", "send", "resolve", "listChanged"], "\(type)")
    }
}

@MainActor @Test func grantedSettlesAndBumpsTheUser() async {
    let harness = GrantHarness(); harness.events = [.waitingForServer(elapsedSeconds: 3)]
    #expect(await harness.grant() == .granted(issued(), replayed: false))
    #expect(harness.log == ["authorize", "persist", "send", "resolve", "listChanged"])
    #expect(harness.persisted == [compensation()] && harness.resolved == [grantID])
    #expect(harness.balanceBumps == [3] && harness.bumps.isEmpty)
    #expect(harness.progress == [.submitting, .waiting(elapsedSeconds: 3)])

    let concurrency = GrantHarness(); concurrency.sendResult = .success(WriteOutcome(value: issued(compensation(.concurrency, value: 2)), replayed: true))
    #expect(await concurrency.grant(compensation(.concurrency, value: 2)) == .granted(issued(compensation(.concurrency, value: 2)), replayed: true))
    #expect(concurrency.bumps == [3] && concurrency.balanceBumps.isEmpty)
}

@MainActor @Test func resultRowsOf19_4() async {
    let later = start.addingTimeInterval(10)
    let kept: [any Error] = [keyed(.unconfirmed(.transport, retryNotBefore: nil)), keyed(.unconfirmed(.storeUnavailable, retryNotBefore: later)),
                             CancellationError(), APIError.server(status: 502, reason: nil)]
    for failure in kept {
        let harness = GrantHarness(); harness.sendResult = .failure(failure)
        guard case .pending = await harness.grant() else { Issue.record("\(failure)"); continue }
        #expect(harness.resolved.isEmpty && harness.bumps.isEmpty && harness.balanceBumps.isEmpty, "\(failure)")
    }
    let held = GrantHarness(); held.sendResult = .failure(keyed(.unconfirmed(.storeUnavailable, retryNotBefore: later)))
    _ = await held.grant()
    #expect(held.holds == [grantID: later])

    func settled(_ error: APIError) async -> (CompensationSubmission.Outcome, [UUID]) {
        let harness = GrantHarness(); harness.sendResult = .failure(error)
        return (await harness.grant(), harness.resolved)
    }
    let conflict = await settled(.server(status: 409, reason: "REDEEM_CODE_CONFLICT"))
    #expect(conflict.0 == .renumber("兑换码编号冲突，已换新编号，请重新确认") && conflict.1 == [grantID])
    let group = await settled(.server(status: 404, reason: "GROUP_NOT_FOUND"))
    #expect(group.0 == .backToValue("这个分组不能用于订阅，请重新选择") && group.1 == [grantID])
    let gone = await settled(.server(status: 404, reason: "USER_NOT_FOUND"))
    #expect(gone.0 == .userGone("用户不存在或已删除") && gone.1 == [grantID])
    let invalid = await settled(.server(status: 400, reason: nil))
    #expect(invalid.0 == .rejected(APIError.server(status: 400, reason: nil).localizedDescription) && invalid.1 == [grantID])
    let forbidden = await settled(.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"))
    #expect(forbidden.0 == .rejected(APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY").localizedDescription) && forbidden.1 == [grantID])

    let stale = GrantHarness(); stale.switchesSessionDuringSend = true
    #expect(await stale.grant() == .stale)
    #expect(stale.resolved == [grantID] && stale.balanceBumps.isEmpty)
}

/// S6D1-08: a first send stopped by a security prompt the administrator then cleared is settled, and the same record (id and
/// bytes) goes through the gate, Face ID and the save again.
@MainActor @Test func clearedSecurityConfirmsTheSameGrantAgain() async throws {
    let refusal = APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed)
    let harness = GrantHarness(); harness.sendResult = .failure(refusal)
    let first = await harness.grant()
    #expect(first == .reconfirm(compensation(), notice: refusal.localizedDescription))
    #expect(harness.resolved == [grantID])
    guard case .reconfirm(let again, _) = first else { return }
    harness.sendResult = .success(WriteOutcome(value: issued()))
    #expect(await harness.grant(again) == .granted(issued(), replayed: false))
    #expect(harness.resolved == [grantID, grantID])
    #expect(harness.persisted.count == 2 && harness.persisted[0] == harness.persisted[1])
    #expect(try harness.persisted[0].requestBody() == harness.persisted[1].requestBody())
    #expect(harness.gated == [.compensation(10), .compensation(10)])
}

// MARK: “用同一编号重试”

@MainActor @Test func retryGuardsAndStale() async {
    #expect(await GrantHarness().retry() == .gone)

    let refusals: [(RedeemRetryContext, String)] = [
        (RedeemRetryContext(permission: .otherActor, isReadOnly: false, retryNotBefore: nil, isLegacyServer: false, isPastIdempotencyExpiry: false),
         APIError.otherActorWrite.localizedDescription),
        (RedeemRetryContext(permission: .allowed, isReadOnly: true, retryNotBefore: nil, isLegacyServer: false, isPastIdempotencyExpiry: false),
         BalanceReconcilePresentation.readOnlyLine),
        (RedeemRetryContext(permission: .allowed, isReadOnly: false, retryNotBefore: start.addingTimeInterval(5), isLegacyServer: false,
                            isPastIdempotencyExpiry: false), BalanceReconcilePresentation.heldLine),
    ]
    for (context, text) in refusals {
        let harness = GrantHarness(); harness.stored = [grantID: compensation()]; harness.context = context
        #expect(await harness.retry() == .refused(text))
        #expect(harness.log.isEmpty && harness.stored[grantID] != nil, "\(text)")
    }

    // A refusal before execution on a retry keeps the record: the first attempt may have run.
    let forbidden = GrantHarness(); forbidden.stored = [grantID: compensation()]; forbidden.sendResult = .failure(APIError.server(status: 403, reason: "FORBIDDEN"))
    guard case .pending = await forbidden.retry() else { Issue.record("403 on a retry"); return }
    #expect(forbidden.resolved.isEmpty && forbidden.log == ["authorize", "persist", "send"])
    // Stopped here (sender check, already going out): not sent, nothing changes.
    let local = GrantHarness(); local.stored = [grantID: compensation()]; local.sendResult = .failure(APIError.otherActorWrite)
    #expect(await local.retry() == .refused(APIError.otherActorWrite.localizedDescription))
    #expect(local.resolved.isEmpty)

    let done = GrantHarness(); done.stored = [grantID: compensation(.concurrency, value: 2)]
    done.sendResult = .success(WriteOutcome(value: issued(compensation(.concurrency, value: 2)), replayed: true))
    #expect(await done.retry() == .granted(issued(compensation(.concurrency, value: 2)), replayed: true))
    #expect(done.log == ["persist", "send", "resolve", "listChanged"] && done.bumps == [3])

    let denied = GrantHarness(); denied.stored = [grantID: compensation()]; denied.authorizes = false
    #expect(await denied.retry() == .notAuthorized)
    #expect(denied.persisted.isEmpty)

    let stale = GrantHarness(); stale.stored = [grantID: compensation()]; stale.switchesSessionDuringSend = true
    #expect(await stale.retry() == .stale)
}
