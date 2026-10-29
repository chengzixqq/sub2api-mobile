import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S6-07: the first send of a new redeem batch (60 §10.4–§10.5, R04, R05, 00 §0 rule 4, S6D1-07…09). The record confirmed now is
// Face ID'd (balance batches, by the total), saved, sent, and settled by S6-03's classification.

private let siteID = UUID(uuidString: "6C000000-0000-4000-8000-000000000001")!
private let batchID = UUID(uuidString: "6C000000-0000-4000-8000-0000000000BB")!
private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let balanceSpec = RedeemGenerateSpec(type: .balance, value: 10, count: 20, expiresInDays: 7)

private func newBatch(_ spec: RedeemGenerateSpec = balanceSpec) -> PendingRedeemBatch {
    PendingRedeemBatch(id: batchID, serverID: siteID, actorUserID: 1, createdAt: start, spec: spec)
}
private func codes(masked: Bool = false) -> [AdminRedeemCode] {
    [21, 22].map { AdminRedeemCode(id: $0, code: masked ? "***" : String(format: "%032lx", $0), type: "balance", value: 10, status: "unused", batchID: batchID) }
}
private func keyed(_ disposition: KeyedWriteFailure.Disposition) -> KeyedWriteFailure {
    KeyedWriteFailure(disposition: disposition, key: batchID.uuidString.lowercased(), actionID: nil, lastError: nil)
}

/// Every effect of a first send, recorded in order.
@MainActor private final class GenerateHarness {
    var authorizes = true
    var persistFails = false
    var resolveFails = false
    var revealFails = false
    var isCurrent = true
    var sendResult: Result<WriteOutcome<[AdminRedeemCode]>, any Error> = .success(WriteOutcome(value: codes(), batchID: batchID))
    /// Reported by the send before it answers.
    var events: [KeyedWriteEvent] = []
    /// The session changes while the request is out.
    var switchesSessionDuringSend = false
    private(set) var log: [String] = []
    private(set) var gated: [GatedAction] = []
    private(set) var persisted: [PendingRedeemBatch] = []
    private(set) var resolved: [UUID] = []
    private(set) var holds: [UUID: Date] = [:]
    private(set) var reports = 0
    private(set) var progress: [BalanceWriteProgress] = []

    var effects: RedeemGenerateSubmission.Effects {
        RedeemGenerateSubmission.Effects(
            authorize: { [self] action in log.append("authorize"); gated.append(action); return authorizes },
            persist: { [self] record in
                log.append("persist")
                if persistFails { throw PendingMoneyError(kind: .redeemBatch, reason: .unsaved) }
                persisted.append(record)
                return PersistedMoneyWrite(record) { _ in }
            },
            send: { [self] _, onEvent in
                log.append("send")
                for event in events { await onEvent(event) }
                if switchesSessionDuringSend { isCurrent = false }
                return try sendResult.get()
            },
            reveal: { [self] masked in
                log.append("reveal")
                if revealFails { throw APIError.server(status: 502, reason: nil) }
                return masked.map { AdminRedeemCode(id: $0.id, code: String(format: "%032lx", $0.id), type: $0.type, value: $0.value, status: $0.status) }
            },
            resolve: { [self] record in
                log.append("resolve")
                if resolveFails { throw PendingMoneyError(kind: .redeemBatch, reason: .unsaved) }
                resolved.append(record.id)
            },
            hold: { [self] id, date in holds[id] = date },
            listChanged: { [self] in log.append("listChanged") },
            report: { [self] _ in reports += 1 },
            isCurrent: { [self] in isCurrent })
    }
    func run(_ batch: PendingRedeemBatch = newBatch()) async -> RedeemGenerateSubmission.Outcome {
        await RedeemGenerateSubmission(effects: effects).run(batch) { [self] in progress.append($0) }
    }
}

@MainActor @Test func deniedFaceIDNeitherSavesNorSends() async {
    let harness = GenerateHarness(); harness.authorizes = false
    #expect(await harness.run() == .notAuthorized)
    #expect(harness.log == ["authorize"])
    #expect(harness.gated == [.redeemGeneration(total: 200)])
    #expect(harness.persisted.isEmpty && harness.progress.isEmpty)
}

@MainActor @Test func nonBalanceBatchSkipsFaceID() async {
    let specs = [RedeemGenerateSpec(type: .concurrency, value: 2, count: 5),
                 RedeemGenerateSpec(type: .subscription, value: 0, count: 5, groupID: 4, groupName: "企业专线", validityDays: 30),
                 RedeemGenerateSpec(type: .invitation, value: 0, count: 10)]
    for spec in specs {
        let harness = GenerateHarness()
        #expect(await harness.run(newBatch(spec)) == .generated(codes(), replayed: false))
        #expect(harness.log == ["persist", "send", "resolve", "listChanged"], "\(spec.type)")
    }
}

@MainActor @Test func unsavedBatchIsNeverSent() async {
    let harness = GenerateHarness(); harness.persistFails = true
    #expect(await harness.run() == .notSaved("未决记录无法保存，已暂停生成"))
    #expect(harness.log == ["authorize", "persist"])
    #expect(harness.progress.isEmpty)
}

@MainActor @Test func successResolvesAndReturnsCodes() async {
    let harness = GenerateHarness()
    #expect(await harness.run() == .generated(codes(), replayed: false))
    #expect(harness.log == ["authorize", "persist", "send", "resolve", "listChanged"])
    #expect(harness.persisted == [newBatch()] && harness.resolved == [batchID])
    #expect(harness.progress == [.submitting])

    let replayed = GenerateHarness(); replayed.sendResult = .success(WriteOutcome(value: codes(), replayed: true, batchID: batchID))
    #expect(await replayed.run() == .generated(codes(), replayed: true))
    #expect(replayed.resolved == [batchID])
}

@MainActor @Test func maskedReplayIsReadAgainBeforeItIsShown() async {
    let masked = GenerateHarness(); masked.sendResult = .success(WriteOutcome(value: codes(masked: true), replayed: true))
    #expect(await masked.run() == .generated(codes().map { AdminRedeemCode(id: $0.id, code: $0.code, type: $0.type, value: $0.value, status: $0.status) },
                                             replayed: true))
    #expect(masked.log == ["authorize", "persist", "send", "reveal", "resolve", "listChanged"])

    // The codes were made but cannot be shown: the record stays to be checked.
    let unread = GenerateHarness(); unread.sendResult = .success(WriteOutcome(value: codes(masked: true), replayed: true)); unread.revealFails = true
    #expect(await unread.run() == .pending)
    #expect(unread.resolved.isEmpty)
}

@MainActor @Test func unconfirmedKeepsTheRecord() async {
    let later = start.addingTimeInterval(30)
    let failures: [any Error] = [keyed(.unconfirmed(.transport, retryNotBefore: nil)), keyed(.unconfirmed(.storeUnavailable, retryNotBefore: later)),
                                 keyed(.needsNewKey(.keyConflict)), CancellationError(), APIError.server(status: 500, reason: nil)]
    for failure in failures {
        let harness = GenerateHarness(); harness.sendResult = .failure(failure)
        #expect(await harness.run() == .pending, "\(failure)")
        #expect(harness.resolved.isEmpty && !harness.log.contains("listChanged"), "\(failure)")
    }
    let held = GenerateHarness(); held.sendResult = .failure(keyed(.unconfirmed(.storeUnavailable, retryNotBefore: later)))
    _ = await held.run()
    #expect(held.holds == [batchID: later])
}

@MainActor @Test func definiteRejectionResolvesAndReturnsToStepThree() async {
    let refusals: [(APIError, String)] = [
        (.server(status: 409, reason: "REDEEM_CODE_EXPIRED"), APIError.server(status: 409, reason: "REDEEM_CODE_EXPIRED").localizedDescription),
        (.server(status: 404, reason: "GROUP_NOT_FOUND"), APIError.server(status: 404, reason: "GROUP_NOT_FOUND").localizedDescription),
        (.server(status: 409, reason: "REDEEM_BATCH_CONFLICT"), "这个编号已用于参数不同的一批兑换码，请重新生成"),
        // Refused before anything went out: another administrator's or another site's record never leaves.
        (.otherActorWrite, APIError.otherActorWrite.localizedDescription),
    ]
    for (error, message) in refusals {
        let harness = GenerateHarness(); harness.sendResult = .failure(error)
        #expect(await harness.run() == .rejected(message), "\(error)")
        #expect(harness.resolved == [batchID], "\(error)")
    }
}

@MainActor @Test func clearedSecurityRefusalReconfirmsTheSameRecord() async throws {
    let harness = GenerateHarness()
    let refusal = APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed)
    harness.sendResult = .failure(refusal)
    let first = await harness.run()
    #expect(first == .reconfirm(newBatch(), notice: refusal.localizedDescription))
    #expect(harness.resolved == [batchID])
    guard case .reconfirm(let again, _) = first else { return }
    harness.sendResult = .success(WriteOutcome(value: codes(), batchID: batchID))
    #expect(await harness.run(again) == .generated(codes(), replayed: false))
    // The same number and the same bytes go out again.
    #expect(harness.persisted.map(\.id) == [batchID, batchID])
    #expect(try harness.persisted[1].requestBody() == harness.persisted[0].requestBody())
    #expect(harness.resolved == [batchID, batchID])
}

@MainActor @Test func resolveFailureIsReportedAndTheCodesStillShow() async {
    let harness = GenerateHarness(); harness.resolveFails = true
    #expect(await harness.run() == .generated(codes(), replayed: false))
    #expect(harness.reports == 1)
}

@MainActor @Test func staleSessionStillSettlesTheBatch() async {
    let done = GenerateHarness(); done.switchesSessionDuringSend = true
    #expect(await done.run() == .stale)
    #expect(done.resolved == [batchID])
    let lost = GenerateHarness(); lost.switchesSessionDuringSend = true; lost.sendResult = .failure(keyed(.unconfirmed(.transport, retryNotBefore: nil)))
    #expect(await lost.run() == .stale)
    #expect(lost.resolved.isEmpty)
}

@MainActor @Test func generateProgressFollowsKeyedWriteEvents() async {
    let harness = GenerateHarness()
    harness.events = [.actionID(UUID()), .confirming(retry: 1), .waitingForServer(elapsedSeconds: 12)]
    _ = await harness.run()
    #expect(harness.progress == [.submitting, .confirming(retry: 1), .waiting(elapsedSeconds: 12)])
    #expect(harness.progress.last?.detail == "已等待 12 秒")
}
