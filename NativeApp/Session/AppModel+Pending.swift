import Foundation
import Sub2Core

/// Money writes awaiting their result (00 §2.5.4–§2.5.5, §9.5; R01–R03; D16, D17, D25): three kinds, one file each, held
/// in `pendingMoney` and changed only through `updatePendingMoney` (AppModel.swift).
extension AppModel {
    var pendingBalances: [PendingBalanceOperation] { pendingMoney.balances }
    var pendingRedeemBatches: [PendingRedeemBatch] { pendingMoney.redeemBatches }
    var pendingCompensations: [PendingCompensation] { pendingMoney.compensations }
    func pendingPersistenceAvailable(_ kind: PendingMoneyKind) -> Bool { pendingMoney.isAvailable(kind) }
    /// The overview “待处理”, the calm layout and settings walk these, oldest first.
    func pendingMoneyWrites(serverID: UUID) -> [any PendingMoneyWrite] { pendingMoney.writes(serverID: serverID) }
    var allPendingMoneyWrites: [any PendingMoneyWrite] { pendingMoney.writes(serverID: nil) }

    /// The only way to obtain a sendable money write: its record is saved first, and a failed save sends nothing (00 §0 rule 4).
    func persisted(_ operation: PendingBalanceOperation) throws -> PersistedMoneyWrite<PendingBalanceOperation> {
        try PersistedMoneyWrite(operation) { try remember($0) }
    }
    func persisted(_ batch: PendingRedeemBatch) throws -> PersistedMoneyWrite<PendingRedeemBatch> {
        try PersistedMoneyWrite(batch) { try remember($0) }
    }
    func persisted(_ grant: PendingCompensation) throws -> PersistedMoneyWrite<PendingCompensation> {
        try PersistedMoneyWrite(grant) { try remember($0) }
    }
    /// Adds a record, or replaces the one with the same id and the same request bytes (for example to save the action id).
    func remember(_ operation: PendingBalanceOperation) throws { try updatePendingMoney { try $0.remembering(operation, in: $1) } }
    func remember(_ batch: PendingRedeemBatch) throws { try updatePendingMoney { try $0.remembering(batch, in: $1) } }
    func remember(_ grant: PendingCompensation) throws { try updatePendingMoney { try $0.remembering(grant, in: $1) } }
    func resolve(_ record: any PendingMoneyWrite) throws { try updatePendingMoney { try $0.resolving(id: record.id, in: $1) } }
    /// A file the locked device could not open at launch is read again on restore and whenever the App becomes active
    /// (D18); a notice still on screen shrinks to what stays unreadable.
    func reloadUnreadablePendingRecords() {
        guard let notice = pendingMoney.unreadableNotice else { return }
        updatePendingMoney { ledger, files in ledger.reloadingUnreadable(from: files) }
        if errorMessage == notice { errorMessage = pendingMoney.unreadableNotice }
    }

    /// UI tests: the first connected site gets DemoData's records (`-ui-pending-money`), held in memory only.
    func seedPendingFixture(serverID: UUID) {
        guard isUITesting, pendingMoney.writes(serverID: nil).isEmpty, pendingMoney.unreadableNotice == nil,
              let ledger = DemoData.pendingLedger(serverID: serverID, now: Date()) else { return }
        profileArchive[DemoData.archivedPendingSite.id] = DemoData.archivedPendingSite
        updatePendingMoney { _, _ in ledger }
    }

    /// R03 for the connected site; the pages own the two exceptions.
    func moneyWriteGate(_ intent: MoneyWriteIntent) -> PendingMoneyGate {
        guard let serverID = activeProfile?.id else { return .clear }
        return .evaluate(intent, serverID: serverID, balances: pendingMoney.balances, redeemBatches: pendingMoney.redeemBatches,
                         compensations: pendingMoney.compensations, unavailable: pendingMoney.unreadable)
    }
    /// D17, scoped to the connected site.
    func retryPermission(for record: any PendingMoneyWrite) -> PendingRetryPermission {
        .evaluate(record, activeServerID: activeProfile?.id, currentUserID: siteSession?.me.user?.id)
    }
    /// Only reads (00 §2.5.5). A record the server confirms as executed is dropped here; every other outcome is left to the
    /// page. A result for an older session is not returned.
    func reconcile(_ record: any PendingMoneyWrite) async throws -> PendingReconcileOutcome {
        guard !isUITesting else { throw AppFailure("界面测试模式不执行核对。") }
        let generation = sessionGeneration
        let outcome = try await requireClient().reconcile(record)
        if outcome.confirmsExecution {
            do { try resolve(record) } catch { report(error) }
        }
        guard generation == sessionGeneration else { throw CancellationError() }
        return outcome
    }
}
