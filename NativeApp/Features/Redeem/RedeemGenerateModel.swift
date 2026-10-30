import Foundation
import Observation
import Sub2Core

/// `.redeemGenerate`'s state (60 §10): the wizard, the confirmation on screen, the send in flight and what the sheet turns into.
/// The record is made when the confirmation is accepted (R05) and sent by RedeemGenerateSubmission; only “稍后核对” cancels that
/// task. The codes live only here, in memory, until the sheet closes.
@MainActor @Observable
final class RedeemGenerateModel {
    enum Phase: Equatable {
        case editing
        case generated([AdminRedeemCode], replayed: Bool, spec: RedeemGenerateSpec)
        /// 结果待核对 (60 §11) of this record, in the same sheet.
        case pending(batchID: UUID)
    }
    struct Confirmation: Identifiable {
        let id = UUID()
        let spec: RedeemGenerateSpec
        let summary: RedeemGenerateSummary
        let message: String
        /// Set when a security prompt cleared the record: the same one is confirmed again (S6D1-08).
        let record: PendingRedeemBatch?
    }

    private(set) var wizard = RedeemGenerateWizard()
    private(set) var phase: Phase = .editing
    private(set) var confirmation: Confirmation?
    /// From the confirmation until the result, Face ID included.
    private(set) var isWorking = false
    /// Face ID is asking (60 §10.5 覆盖层).
    private(set) var isVerifying = false
    /// Set once the record is saved: “稍后核对” is offered from then on.
    private(set) var progress: BalanceWriteProgress?
    /// Step 3's line: a refusal, a record that could not be saved, a cleared security prompt.
    private(set) var notice: String?
    @ObservationIgnored private var sending: Task<Void, Never>?

    /// The wizard changes only while it is shown and nothing is going out.
    func update(_ change: (RedeemGenerateWizard) -> RedeemGenerateWizard) {
        guard phase == .editing, !isWorking else { return }
        let next = change(wizard)
        guard next != wizard else { return }
        wizard = next
        notice = nil
    }

    /// 生成 N 个兑换码: the confirmation with object, site and amount (BUILDER_GUIDE), plus the Face ID line when it will ask.
    func submit(model: AppModel, subscriptionGroups: [AdminGroup], now: Date, timeZone: TimeZone) {
        guard phase == .editing, !isWorking, let spec = wizard.spec(subscriptionGroups: subscriptionGroups) else { return }
        notice = nil
        confirmation = makeConfirmation(spec, record: nil, model: model, now: now, timeZone: timeZone)
    }
    func dismissConfirmation(_ id: UUID) {
        if confirmation?.id == id { confirmation = nil }
    }
    /// Accepted: a new number now (R05), or the cleared record again; then Face ID, the saved record and the send.
    func confirm(_ shown: Confirmation, model: AppModel) {
        dismissConfirmation(shown.id)
        guard !isWorking, let record = shown.record ?? newRecord(shown.spec, model: model) else { return }
        let submission = RedeemGenerateSubmission(effects: effects(model: model))
        isWorking = true
        sending = Task { [weak self] in
            let outcome = await submission.run(record) { [weak self] in self?.progress = $0 }
            self?.finish(outcome, record: record, model: model)
        }
    }
    /// “稍后核对”: stops waiting; the record stays to be checked.
    func later() { sending?.cancel() }

    /// The directory's active subscription groups in its order (S6D1-05); `-ui-redeem-no-subscription-groups` hides them.
    static func subscriptionGroups(model: AppModel) -> [AdminGroup] {
        let groups = (model.groupDirectory?.groups ?? []).filter(\.isActiveSubscriptionGroup)
        return model.isUITesting ? DemoData.redeemGenerateGroups(groups) : groups
    }

    private func makeConfirmation(_ spec: RedeemGenerateSpec, record: PendingRedeemBatch?, model: AppModel, now: Date, timeZone: TimeZone) -> Confirmation {
        let summary = RedeemGenerateSummary(spec: spec, now: now, timeZone: timeZone)
        let faceID = spec.total.flatMap { model.biometricGate.amountConfirmationLine(amount: $0, isTotal: true) }
        return Confirmation(spec: spec, summary: summary, message: summary.confirmMessage(siteName: model.activeProfile?.name ?? "", faceIDLine: faceID),
                            record: record)
    }
    private func newRecord(_ spec: RedeemGenerateSpec, model: AppModel) -> PendingRedeemBatch? {
        guard let serverID = model.activeProfile?.id else { return nil }
        return PendingRedeemBatch(id: UUID(), serverID: serverID, actorUserID: model.siteSession?.me.user?.id, createdAt: Date(), spec: spec)
    }
    private func finish(_ outcome: RedeemGenerateSubmission.Outcome, record: PendingRedeemBatch, model: AppModel) {
        isWorking = false; isVerifying = false; progress = nil; sending = nil
        switch outcome {
        case .notAuthorized, .stale:
            return
        case .notSaved(let text), .rejected(let text):
            notice = text
        case .reconfirm(let again, let text):
            notice = text
            let now = model.client?.serverClock.now() ?? Date(), zone = model.siteSession?.serverTimeZone.timeZone ?? .current
            confirmation = makeConfirmation(again.spec, record: again, model: model, now: now, timeZone: zone)
        case .pending:
            phase = .pending(batchID: record.id)
        case .generated(let codes, let replayed):
            phase = .generated(codes, replayed: replayed, spec: record.spec)
        }
    }

    /// The live site, or under `-ui-testing` this session's RedeemDemoStore with the `-ui-redeem-generate-*` answers.
    private func effects(model: AppModel) -> RedeemGenerateSubmission.Effects {
        let generation = model.sessionGeneration
        return RedeemGenerateSubmission.Effects(
            authorize: { [weak self, weak model] action in
                guard let model else { return false }
                guard model.biometricGate.needsVerification(action) else { return true }
                self?.isVerifying = true
                defer { self?.isVerifying = false }
                return await model.biometricGate.authorize(action)
            },
            persist: { [weak model] batch in
                guard let model else { throw CancellationError() }
                return try model.persisted(batch)
            },
            send: { [weak model] write, onEvent in
                guard let model else { throw CancellationError() }
                return try await model.sendNewRedeemBatch(write, onEvent: onEvent)
            },
            reveal: { [weak model] codes in
                guard let model else { throw CancellationError() }
                return try await model.revealGeneratedCodes(codes)
            },
            resolve: { [weak model] in try model?.resolve($0) },
            hold: { [weak model] in model?.holdRetry($0, until: $1) },
            listChanged: { RedeemCodesModel.noteExternalChange() },
            report: { [weak model] in model?.report($0) },
            isCurrent: { [weak model] in model?.sessionGeneration == generation })
    }
}

extension AppModel {
    /// A new batch's first send (S6D1-07): marked going out for the whole send, the sender checked first like every same-number
    /// send, then the site, or the fixture server under `-ui-testing`.
    fileprivate func sendNewRedeemBatch(_ write: PersistedMoneyWrite<PendingRedeemBatch>,
                                        onEvent: @escaping KeyedWriteEventHandler) async throws -> WriteOutcome<[AdminRedeemCode]> {
        try await AppModel.moneyWritesInFlight.sending(write.record.id) {
            let deliver: @Sendable (PersistedMoneyWrite<PendingRedeemBatch>, Set<UUID>) async throws -> WriteOutcome<[AdminRedeemCode]>
            if isUITesting {
                deliver = { [weak self] write, sameAddress in
                    guard let self else { throw CancellationError() }
                    return try await fixtureGenerate(write.record, sameAddress: sameAddress)
                }
            } else {
                let client = try requireClient()
                deliver = { try await client.generateRedeemCodes($0, sameAddress: $1, onEvent: onEvent) }
            }
            return try await RedeemBatchCheck.sendSameNumber(write, currentUserID: siteSession?.me.user?.id, currentServerID: activeProfile?.id,
                                                             sameAddress: sameAddressServerIDs(), deliver: deliver)
        }
    }
    fileprivate func revealGeneratedCodes(_ codes: [AdminRedeemCode]) async throws -> [AdminRedeemCode] {
        guard isUITesting else { return try await requireClient().revealingRedactedCodes(codes) }
        let store = generateDemoStore()
        return try codes.map { $0.isRedacted ? try store.code(id: $0.id) : $0 }
    }
    private func fixtureGenerate(_ batch: PendingRedeemBatch, sameAddress: Set<UUID>) throws -> WriteOutcome<[AdminRedeemCode]> {
        guard let current = activeProfile?.id else { throw APIError.stationMismatch }
        try MoneyRecordOrigin.check(recordServerID: batch.serverID, currentServerID: current, sameAddress: sameAddress)
        return try DemoData.redeemGenerateReply(for: batch, store: generateDemoStore(), now: client?.serverClock.now() ?? Date(),
                                                arguments: ProcessInfo.processInfo.arguments)
    }
    private func generateDemoStore() -> RedeemDemoStore {
        RedeemDemoStore.current(for: sessionGeneration, base: client?.serverClock.now() ?? Date())
    }
}
