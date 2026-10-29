import Foundation
import Observation
import Sub2Core

/// The check sheet of one pending batch (60 §11.3–§11.5): one request at a time, both buttons waiting while it runs, each
/// answer kept only for the session that asked. The record itself is AppModel's, so a check here also clears the overview's
/// row, the settings row and the list's banner.
@MainActor @Observable
final class RedeemReconcileModel {
    enum Phase: Equatable {
        case pending(RedeemReconcileStage)
        case result(RedeemResultKind, codes: [AdminRedeemCode])
    }
    struct Notice: Equatable {
        let text: String
        let tone: Tone
    }

    let batchID: UUID
    /// The record as the sheet found it: the receipt and the result page keep it after it was settled.
    let snapshot: PendingRedeemBatch?
    private(set) var phase: Phase
    private(set) var busy: RedeemReconcilePresentation.Busy?
    private(set) var notice: Notice?
    /// “我已核对” was tapped.
    private(set) var isConfirmed = false
    /// Another administrator's email for the restriction line.
    private(set) var actorLabel: String?

    init(batchID: UUID, record: PendingRedeemBatch?) {
        self.batchID = batchID; snapshot = record
        phase = .pending(record == nil ? .settled : .awaitingCheck)
    }

    /// A pending page whose record was settled elsewhere says so.
    func stage(recordExists: Bool) -> RedeemReconcileStage? {
        guard case .pending(let stage) = phase else { return nil }
        switch stage {
        case .settled, .refused: return stage
        case .awaitingCheck, .notGenerated, .undetermined: return recordExists ? stage : .settled
        }
    }

    func loadActorLabel(model: AppModel) async {
        guard let snapshot, actorLabel == nil, model.retryPermission(for: snapshot) == .otherActor else { return }
        actorLabel = await model.pendingActorLabel(for: snapshot)
    }

    func check(model: AppModel) async {
        guard busy == nil else { return }
        busy = .checking; notice = nil
        defer { busy = nil }
        switch await model.redeemBatchCheck().check(batchID) {
        case .gone: phase = .pending(.settled)
        case .generated(let codes): phase = .result(.checked, codes: codes)
        case .notGenerated(let heuristic): phase = .pending(.notGenerated(heuristic: heuristic))
        case .countMismatch(let codes): phase = .result(.countMismatch(expected: snapshot?.count ?? codes.count), codes: codes)
        case .probable(let codes): phase = .result(.probable(expected: snapshot?.count ?? codes.count), codes: codes)
        case .undetermined: phase = .pending(.undetermined)
        case .failed(let text): notice = Notice(text: text, tone: .critical)
        case .stale: break
        }
    }

    func retry(model: AppModel) async {
        guard busy == nil else { return }
        busy = .retrying; notice = nil
        defer { busy = nil }
        switch await model.redeemBatchCheck().retry(batchID) {
        case .gone: phase = .pending(.settled)
        case .refused(let text): notice = Notice(text: text, tone: .caution)
        case .notAuthorized, .stale: break
        case .notSaved(let text): notice = Notice(text: text, tone: .critical)
        case .succeeded(let codes, let replayed): phase = .result(replayed ? .replayed : .generated, codes: codes)
        // STORE_UNAVAILABLE's cooldown is the grey button's own line.
        case .kept(let text, let retryNotBefore): notice = retryNotBefore == nil ? Notice(text: text, tone: .caution) : nil
        case .rejected(let text): phase = .pending(.refused(text))
        }
    }

    /// After its confirmation; false keeps the sheet open with the reason.
    func abandon(model: AppModel) -> Bool {
        do { try model.redeemBatchCheck().close(batchID) } catch {
            notice = Notice(text: error.localizedDescription, tone: .critical)
            return false
        }
        model.receipts.show(Receipt(text: RedeemReconcilePresentation.abandonReceipt, systemImage: "xmark.circle", tone: .neutral))
        return true
    }

    /// A count that does not match, or an old server's guess, checked on the web: the record goes, the codes stay on screen.
    func confirmChecked(model: AppModel) {
        guard !isConfirmed else { return }
        do { try model.redeemBatchCheck().close(batchID) } catch {
            notice = Notice(text: error.localizedDescription, tone: .critical)
            return
        }
        isConfirmed = true
        model.receipts.show(Receipt(text: RedeemReconcilePresentation.confirmedReceipt))
    }
}

extension AppModel {
    /// S6-06's check, retry and closing of a pending batch on the site, or under `-ui-testing` on this session's RedeemDemoStore
    /// with the `-ui-redeem-*` answers (RedeemFixtures). Every send goes through `sendRedeemBatch`.
    func redeemBatchCheck() -> RedeemBatchCheck {
        let generation = sessionGeneration
        return RedeemBatchCheck(effects: RedeemBatchCheck.Effects(
            record: { [weak self] id in self?.pendingRedeemBatches.first { $0.id == id } },
            isLegacyServer: { [weak self] in self?.isLegacyRedeemServer ?? false },
            reconcile: { [weak self] batch in
                guard let self else { throw CancellationError() }
                return try await readRedeemBatch(batch)
            },
            fallback: { [weak self] batch, sentAt in
                guard let self else { throw CancellationError() }
                return try await guessRedeemBatch(batch, sentAt: sentAt)
            },
            reveal: { [weak self] codes in
                guard let self else { throw CancellationError() }
                return try await revealRedeemCodes(codes)
            },
            retryContext: { [weak self] batch in self?.redeemRetryContext(for: batch) ?? .refusing },
            authorize: { [weak self] in await self?.biometricGate.authorize($0) ?? false },
            persist: { [weak self] batch in
                guard let self else { throw CancellationError() }
                return try persisted(batch)
            },
            send: { [weak self] write in
                guard let self else { throw CancellationError() }
                return try await sendRedeemBatch(write)
            },
            resolve: { [weak self] in try self?.resolve($0) },
            hold: { [weak self] in self?.holdRetry($0, until: $1) },
            noteSent: { RedeemBatchCheck.sendLog.note($0, at: $1) },
            lastSent: { RedeemBatchCheck.sendLog.lastSent($0) },
            listChanged: { RedeemCodesModel.noteExternalChange() },
            report: { [weak self] in self?.report($0) },
            isCurrent: { [weak self] in self?.sessionGeneration == generation },
            now: { Date() }))
    }

    /// U43: without `redeem_codes.stats` the site keeps no batch to look up.
    var isLegacyRedeemServer: Bool { siteSession.map { !$0.has(.redeemCodesStats) } ?? false }

    /// What the sheet may offer now (D17, R03, X34); `actorLabel` only words the line of another administrator's batch.
    func redeemRetryContext(for batch: PendingRedeemBatch, actorLabel: String? = nil) -> RedeemRetryContext {
        RedeemRetryContext(permission: retryPermission(for: batch), isReadOnly: siteSession?.isReadOnlyToken ?? true, retryNotBefore: retryHeldUntil(batch.id),
                           isLegacyServer: isLegacyRedeemServer, isPastIdempotencyExpiry: batch.effectiveExpiresAt.map { $0 <= Date() } ?? false,
                           actorLabel: actorLabel)
    }

    /// The only sender of a pending batch's same number (S6D1-07): marked going out for the whole send, the sender checked
    /// first, then the site, or the fixture server under `-ui-testing`.
    func sendRedeemBatch(_ write: PersistedMoneyWrite<PendingRedeemBatch>) async throws -> WriteOutcome<[AdminRedeemCode]> {
        try await AppModel.moneyWritesInFlight.sending(write.record.id) {
            let deliver: @Sendable (PersistedMoneyWrite<PendingRedeemBatch>, Set<UUID>) async throws -> WriteOutcome<[AdminRedeemCode]>
            if isUITesting {
                deliver = { [weak self] write, sameAddress in
                    guard let self else { throw CancellationError() }
                    return try await fixtureRedeemRetry(write.record, sameAddress: sameAddress)
                }
            } else {
                let client = try requireClient()
                deliver = { try await client.generateRedeemCodes($0, sameAddress: $1) }
            }
            return try await RedeemBatchCheck.sendSameNumber(write, currentUserID: siteSession?.me.user?.id, currentServerID: activeProfile?.id,
                                                             sameAddress: sameAddressServerIDs(), deliver: deliver)
        }
    }

    /// The batch_id query, which settles a batch found whole (AppModel.reconcile); the fixture does the same.
    private func readRedeemBatch(_ batch: PendingRedeemBatch) async throws -> RedeemBatchReconcileOutcome {
        guard isUITesting else {
            guard case .redeemBatch(let outcome) = try await reconcile(batch) else { throw AppFailure("无法核对这类记录。") }
            return outcome
        }
        let outcome = try DemoData.redeemReconcileOutcome(for: batch, store: redeemDemoStore(), now: redeemFixtureNow, arguments: ProcessInfo.processInfo.arguments)
        if case .generated = outcome {
            do { try resolve(batch) } catch { report(error) }
        }
        return outcome
    }
    private func guessRedeemBatch(_ batch: PendingRedeemBatch, sentAt: Date?) async throws -> RedeemBatchFallbackOutcome {
        guard isUITesting else {
            let generation = sessionGeneration
            let outcome = try await requireClient().reconcileRedeemBatchFallback(batch, sentAt: sentAt, sameAddress: sameAddressServerIDs())
            guard generation == sessionGeneration else { throw CancellationError() }
            return outcome
        }
        return try DemoData.redeemFallbackOutcome(for: batch, store: redeemDemoStore(), now: redeemFixtureNow, arguments: ProcessInfo.processInfo.arguments)
    }
    private func revealRedeemCodes(_ codes: [AdminRedeemCode]) async throws -> [AdminRedeemCode] {
        guard isUITesting else { return try await requireClient().revealingRedactedCodes(codes) }
        let store = redeemDemoStore()
        return try codes.map { $0.isRedacted ? try store.code(id: $0.id) : $0 }
    }
    private func fixtureRedeemRetry(_ batch: PendingRedeemBatch, sameAddress: Set<UUID>) throws -> WriteOutcome<[AdminRedeemCode]> {
        guard let current = activeProfile?.id else { throw APIError.stationMismatch }
        try MoneyRecordOrigin.check(recordServerID: batch.serverID, currentServerID: current, sameAddress: sameAddress)
        return try DemoData.redeemRetryReply(for: batch, store: redeemDemoStore(), legacy: isLegacyRedeemServer, now: redeemFixtureNow,
                                             arguments: ProcessInfo.processInfo.arguments)
    }
    private func redeemDemoStore() -> RedeemDemoStore { RedeemDemoStore.current(for: sessionGeneration, base: redeemFixtureNow) }
    private var redeemFixtureNow: Date { client?.serverClock.now() ?? Date() }
}

extension RedeemRetryContext {
    /// No session: nothing may go out.
    static let refusing = RedeemRetryContext(permission: .otherActor, isReadOnly: true, retryNotBefore: nil, isLegacyServer: false, isPastIdempotencyExpiry: false)
}
