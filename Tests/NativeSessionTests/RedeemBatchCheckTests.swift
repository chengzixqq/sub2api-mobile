import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S6-06: the check, “用同一编号重试” and the closing of a pending redeem batch (60 §11.4, 00 §2.5.2, D17, X34, S6D1-07, S6D1-09).

private let siteID = UUID(uuidString: "6B000000-0000-4000-8000-000000000001")!
private let batchID = UUID(uuidString: "6B000000-0000-4000-8000-0000000000BB")!
private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let balanceSpec = RedeemGenerateSpec(type: .balance, value: 10, count: 2, expiresInDays: 7)

private func pendingBatch(_ spec: RedeemGenerateSpec = balanceSpec, serverID: UUID = siteID, actor: Int? = 1) -> PendingRedeemBatch {
    PendingRedeemBatch(id: batchID, serverID: serverID, actorUserID: actor, createdAt: start, spec: spec)
}
private func codes(masked: Bool = false) -> [AdminRedeemCode] {
    [11, 12].map { AdminRedeemCode(id: $0, code: masked ? "***" : String(format: "%032lx", $0), type: "balance", value: 10, status: "unused", batchID: batchID) }
}
private func allowed(readOnly: Bool = false, heldUntil: Date? = nil, legacy: Bool = false, expired: Bool = false,
                     permission: PendingRetryPermission = .allowed) -> RedeemRetryContext {
    RedeemRetryContext(permission: permission, isReadOnly: readOnly, retryNotBefore: heldUntil, isLegacyServer: legacy, isPastIdempotencyExpiry: expired)
}
private func keyed(_ disposition: KeyedWriteFailure.Disposition) -> KeyedWriteFailure {
    KeyedWriteFailure(disposition: disposition, key: batchID.uuidString.lowercased(), actionID: nil, lastError: nil)
}

/// Every effect of a check or a retry, recorded in order.
@MainActor private final class BatchHarness {
    var records: [UUID: PendingRedeemBatch]
    var legacy = false
    var context = allowed()
    var reconcileResult: Result<RedeemBatchReconcileOutcome, any Error> = .success(.notGenerated)
    var fallbackResult: Result<RedeemBatchFallbackOutcome, any Error> = .success(.notFound)
    var revealFails = false
    var authorizes = true
    var persistFails = false
    var resolveFails = false
    var isCurrent = true
    var sendResult: Result<WriteOutcome<[AdminRedeemCode]>, any Error> = .success(WriteOutcome(value: codes(), batchID: batchID))
    /// Replaces the scripted send (the same-address cases go through a real APIClient).
    var deliver: (@MainActor (PersistedMoneyWrite<PendingRedeemBatch>) async throws -> WriteOutcome<[AdminRedeemCode]>)?
    private(set) var log: [String] = []
    private(set) var gated: [GatedAction] = []
    private(set) var resolved: [UUID] = []
    private(set) var holds: [UUID: Date] = [:]
    private(set) var fallbackSentAt: [Date?] = []

    init(_ records: PendingRedeemBatch...) { self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }) }

    var effects: RedeemBatchCheck.Effects {
        RedeemBatchCheck.Effects(
            record: { [self] in records[$0] },
            isLegacyServer: { [self] in legacy },
            reconcile: { [self] _ in log.append("reconcile"); return try reconcileResult.get() },
            fallback: { [self] _, sent in log.append("fallback"); fallbackSentAt.append(sent); return try fallbackResult.get() },
            reveal: { [self] masked in
                log.append("reveal")
                if revealFails { throw APIError.server(status: 502, reason: nil) }
                return masked.map { AdminRedeemCode(id: $0.id, code: String(format: "%032lx", $0.id), type: $0.type, value: $0.value, status: $0.status) }
            },
            retryContext: { [self] _ in context },
            authorize: { [self] action in log.append("authorize"); gated.append(action); return authorizes },
            persist: { [self] record in
                log.append("persist")
                if persistFails { throw PendingMoneyError(kind: .redeemBatch, reason: .unsaved) }
                return PersistedMoneyWrite(record) { records[$0.id] = $0 }
            },
            send: { [self] write in
                log.append("send")
                if let deliver { return try await deliver(write) }
                return try sendResult.get()
            },
            resolve: { [self] record in
                log.append("resolve")
                if resolveFails { throw PendingMoneyError(kind: .redeemBatch, reason: .unsaved) }
                resolved.append(record.id); records[record.id] = nil
            },
            hold: { [self] id, date in holds[id] = date },
            listChanged: { [self] in log.append("listChanged") },
            report: { _ in },
            isCurrent: { [self] in isCurrent },
            now: { start.addingTimeInterval(60) })
    }
    var check: RedeemBatchCheck { RedeemBatchCheck(effects: effects) }
}

// MARK: Check

@MainActor @Test func checkLeavesSettlingToTheReadAndKeepsEveryOtherOutcome() async {
    let found = BatchHarness(pendingBatch()); found.reconcileResult = .success(.generated(codes()))
    #expect(await found.check.check(batchID) == .generated(codes()))
    // AppModel.reconcile settles a whole batch by itself; the check only tells the list.
    #expect(found.log == ["reconcile", "listChanged"]); #expect(found.resolved.isEmpty)

    let none = BatchHarness(pendingBatch())
    #expect(await none.check.check(batchID) == .notGenerated(heuristic: false))
    let partial = BatchHarness(pendingBatch()); partial.reconcileResult = .success(.countMismatch([codes()[0]]))
    #expect(await partial.check.check(batchID) == .countMismatch([codes()[0]]))
    let failed = BatchHarness(pendingBatch()); failed.reconcileResult = .failure(APIError.server(status: 500, reason: nil))
    #expect(await failed.check.check(batchID) == .failed("核对失败，请稍后再试"))
    for harness in [none, partial, failed] { #expect(harness.resolved.isEmpty && harness.records[batchID] != nil) }

    let older = BatchHarness(pendingBatch()); older.isCurrent = false
    #expect(await older.check.check(batchID) == .stale)
    let cancelled = BatchHarness(pendingBatch()); cancelled.reconcileResult = .failure(CancellationError())
    #expect(await cancelled.check.check(batchID) == .stale)
    let gone = BatchHarness()
    #expect(await gone.check.check(batchID) == .gone); #expect(gone.log.isEmpty)
}

@MainActor @Test func checkUsesTheFallbackOnAnOldServerOrWhenBatchIDIsIgnored() async {
    // The window reaches to the last send saved with the record, which outlives the App.
    let legacy = BatchHarness(pendingBatch().with(lastSentAt: start.addingTimeInterval(400))); legacy.legacy = true
    legacy.fallbackResult = .success(.likelyGenerated(codes()))
    #expect(await legacy.check.check(batchID) == .probable(codes()))
    #expect(legacy.log == ["fallback"]); #expect(legacy.fallbackSentAt == [start.addingTimeInterval(400)]); #expect(legacy.resolved.isEmpty)

    let expected: [(RedeemBatchFallbackOutcome, RedeemBatchCheck.CheckOutcome)] = [
        (.notFound, .notGenerated(heuristic: true)), (.inconclusive, .undetermined), (.countMismatch([codes()[0]]), .probable([codes()[0]])),
    ]
    for (fallback, outcome) in expected {
        let harness = BatchHarness(pendingBatch()); harness.legacy = true; harness.fallbackResult = .success(fallback)
        #expect(await harness.check.check(batchID) == outcome)
    }
    let ignored = BatchHarness(pendingBatch()); ignored.reconcileResult = .success(.unverifiable)
    ignored.fallbackResult = .success(.likelyGenerated(codes()))
    #expect(await ignored.check.check(batchID) == .probable(codes())); #expect(ignored.log == ["reconcile", "fallback"])
}

// MARK: Retry

@MainActor @Test func retryRefusesBeforeVerifyingSavingOrSending() async {
    let cases: [(RedeemRetryContext, String)] = [
        (allowed(permission: .otherActor), "这笔由其他管理员发起，不能用同一编号重试。"),
        (allowed(readOnly: true), "当前登录的是只读令牌，不能修改"),
        (allowed(heldUntil: start.addingTimeInterval(70)), "服务器暂时无法受理，稍后用同一编号重试"),
        (allowed(legacy: true, expired: true), RedeemReconcilePresentation.expiredRetryLine),
    ]
    for (context, text) in cases {
        let harness = BatchHarness(pendingBatch()); harness.context = context
        #expect(await harness.check.retry(batchID) == .refused(text))
        #expect(harness.log.isEmpty)
    }
    // A cooldown that has run out no longer stops it.
    let over = BatchHarness(pendingBatch()); over.context = allowed(heldUntil: start.addingTimeInterval(30))
    #expect(await over.check.retry(batchID) == .succeeded(codes(), replayed: false))
    #expect(await BatchHarness().check.retry(batchID) == .gone)
}

@MainActor @Test func retryVerifiesABalanceBatchThenSavesBeforeSending() async {
    let harness = BatchHarness(pendingBatch())
    #expect(await harness.check.retry(batchID) == .succeeded(codes(), replayed: false))
    #expect(harness.log == ["authorize", "persist", "send", "resolve", "listChanged"])
    #expect(harness.gated == [.redeemGeneration(total: 20)]); #expect(harness.resolved == [batchID])

    let concurrency = BatchHarness(pendingBatch(RedeemGenerateSpec(type: .concurrency, value: 2, count: 5)))
    _ = await concurrency.check.retry(batchID)
    #expect(concurrency.log.first == "persist"); #expect(concurrency.gated.isEmpty)

    let denied = BatchHarness(pendingBatch()); denied.authorizes = false
    #expect(await denied.check.retry(batchID) == .notAuthorized); #expect(denied.log == ["authorize"])
    let unsaved = BatchHarness(pendingBatch()); unsaved.persistFails = true
    #expect(await unsaved.check.retry(batchID) == .notSaved("未决记录无法保存，已暂停生成"))
    #expect(unsaved.log == ["authorize", "persist"]); #expect(unsaved.records[batchID] != nil)
}

@MainActor @Test func retryRevealsMaskedCodesBeforeSettling() async {
    let replay = BatchHarness(pendingBatch()); replay.sendResult = .success(WriteOutcome(value: codes(masked: true), replayed: true))
    #expect(await replay.check.retry(batchID) == .succeeded(codes().map { AdminRedeemCode(id: $0.id, code: $0.code, type: $0.type, value: $0.value, status: $0.status) },
                                                         replayed: true))
    #expect(replay.log.suffix(4) == ["send", "reveal", "resolve", "listChanged"])

    let unreadable = BatchHarness(pendingBatch()); unreadable.sendResult = .success(WriteOutcome(value: codes(masked: true), replayed: true))
    unreadable.revealFails = true
    #expect(await unreadable.check.retry(batchID) == .kept(RedeemReconcilePresentation.revealFailedText, retryNotBefore: nil))
    #expect(unreadable.resolved.isEmpty)
}

@MainActor @Test func retryFollowsTheSharedClassification() async {
    let cooldown = start.addingTimeInterval(70)
    let kept: [(any Error, String, Date?)] = [
        (keyed(.unconfirmed(.transport, retryNotBefore: nil)), "结果未确认，已记为待核对", nil),
        (keyed(.unconfirmed(.storeUnavailable, retryNotBefore: cooldown)), "服务器暂时无法受理，稍后用同一编号重试", cooldown),
        (APIError.server(status: 500, reason: nil), "结果未确认，已记为待核对", nil),
        // A retry that meets another batch under its number asks for a check instead of closing the record.
        (APIError.server(status: 409, reason: "REDEEM_BATCH_CONFLICT"), "这个编号下已有一批参数不同的兑换码，请先核对", nil),
    ]
    for (error, text, notBefore) in kept {
        let harness = BatchHarness(pendingBatch()); harness.sendResult = .failure(error)
        #expect(await harness.check.retry(batchID) == .kept(text, retryNotBefore: notBefore))
        #expect(harness.resolved.isEmpty); #expect(harness.holds[batchID] == notBefore)
    }
    let refusedBody = BatchHarness(pendingBatch())
    refusedBody.sendResult = .failure(APIError.server(status: 400, reason: "REDEEM_CODE_EXPIRES_IN_DAYS_INVALID"))
    guard case .rejected = await refusedBody.check.retry(batchID) else { Issue.record("expected a refusal"); return }
    #expect(refusedBody.resolved == [batchID])

    let local = BatchHarness(pendingBatch()); local.sendResult = .failure(APIError.otherActorWrite)
    #expect(await local.check.retry(batchID) == .refused("这笔由其他管理员发起，不能用同一编号重试。")); #expect(local.resolved.isEmpty)

    let older = BatchHarness(pendingBatch())
    older.deliver = { [older] _ in older.isCurrent = false; return WriteOutcome(value: codes(), batchID: batchID) }
    #expect(await older.check.retry(batchID) == .stale); #expect(older.resolved == [batchID])
}

// MARK: Close

@MainActor @Test func closeSettlesTheRecordAndToleratesOneAlreadyGone() throws {
    let harness = BatchHarness(pendingBatch())
    try harness.check.close(batchID)
    #expect(harness.resolved == [batchID]); #expect(harness.log == ["resolve", "listChanged"])
    let gone = BatchHarness()
    try gone.check.close(batchID)
    #expect(gone.log.isEmpty)
    let unsaved = BatchHarness(pendingBatch()); unsaved.resolveFails = true
    do { try unsaved.check.close(batchID); Issue.record("expected a save failure") } catch { #expect(error is PendingMoneyError) }
}

// MARK: Same address (X34, S6D1-07)

private let generatedJSON = #"[{"id":11,"code":"a3f01b2c3d4e5f60718293a4b5c6d4e8","type":"balance","value":10,"status":"unused"}]"#

/// The real sender: the sender check, then APIClient at the connected site with the address's site ids.
@MainActor private func sameAddressHarness(_ record: PendingRedeemBatch, client: APIClient, oldLogin: UUID) -> BatchHarness {
    let harness = BatchHarness(record), sameAddress: Set<UUID> = [client.server.id, oldLogin]
    harness.context = allowed(permission: .evaluate(actorUserID: record.actorUserID, currentUserID: 1, recordServerID: record.serverID,
                                                    currentServerID: client.server.id, sameAddress: sameAddress))
    harness.deliver = { write in
        try await RedeemBatchCheck.sendSameNumber(write, currentUserID: 1, currentServerID: client.server.id, sameAddress: sameAddress) {
            try await client.generateRedeemCodes($0, sameAddress: $1)
        }
    }
    return harness
}

@MainActor @Test func oldSiteBatchRetrySendsOnceWithSameAddress() async throws {
    let transport = SessionTransport { _ in sessionOK(generatedJSON) }
    let client = sessionClient(transport), oldLogin = UUID()
    let harness = sameAddressHarness(pendingBatch(RedeemGenerateSpec(type: .concurrency, value: 2, count: 1), serverID: oldLogin), client: client,
                                     oldLogin: oldLogin)
    guard case .succeeded(let sent, _) = await harness.check.retry(batchID) else { Issue.record("expected the batch"); return }
    #expect(sent.map(\.id) == [11]); #expect(await transport.paths() == ["/api/v1/admin/redeem-codes/generate"])
}

@MainActor @Test func otherAddressBatchSendsNothing() async throws {
    let transport = SessionTransport { _ in sessionOK(generatedJSON) }
    let client = sessionClient(transport)
    let harness = sameAddressHarness(pendingBatch(serverID: UUID()), client: client, oldLogin: UUID())
    #expect(await harness.check.retry(batchID) == .refused("这笔由其他管理员发起，不能用同一编号重试。"))
    // The sender check stops it even when a page would offer it.
    let write = PersistedMoneyWrite(pendingBatch(serverID: UUID())) { _ in }
    await #expect(throws: APIError.otherActorWrite) {
        _ = try await RedeemBatchCheck.sendSameNumber(write, currentUserID: 1, currentServerID: client.server.id, sameAddress: [client.server.id]) {
            try await client.generateRedeemCodes($0, sameAddress: $1)
        }
    }
    #expect(await transport.paths().isEmpty)
}

@MainActor @Test func otherActorRetrySendsNothing() async throws {
    let transport = SessionTransport { _ in sessionOK(generatedJSON) }
    let client = sessionClient(transport), oldLogin = UUID()
    let harness = sameAddressHarness(pendingBatch(serverID: oldLogin, actor: 2), client: client, oldLogin: oldLogin)
    #expect(await harness.check.retry(batchID) == .refused("这笔由其他管理员发起，不能用同一编号重试。"))
    let unknownOnOldLogin = sameAddressHarness(pendingBatch(serverID: oldLogin, actor: nil), client: client, oldLogin: oldLogin)
    #expect(await unknownOnOldLogin.check.retry(batchID) == .refused("这笔由其他管理员发起，不能用同一编号重试。"))
    #expect(await transport.paths().isEmpty)
}
