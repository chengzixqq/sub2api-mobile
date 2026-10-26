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
    /// A balance record already saved is going out again under its number, so its execution grace restarts now.
    func persisted(_ operation: PendingBalanceOperation) throws -> PersistedMoneyWrite<PendingBalanceOperation> {
        try PersistedMoneyWrite(pendingMoney.resendStamped(operation, at: Date())) { try remember($0) }
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

    /// R03 for the connected site and the older logins of its address (X34); the pages own the two exceptions.
    func moneyWriteGate(_ intent: MoneyWriteIntent) -> PendingMoneyGate {
        guard activeProfile != nil else { return .clear }
        return .evaluate(intent, serverIDs: sameAddressServerIDs(), balances: pendingMoney.balances, redeemBatches: pendingMoney.redeemBatches,
                         compensations: pendingMoney.compensations, unavailable: pendingMoney.unreadable)
    }
    /// D17 and C-26: the same number only by its sender, at the connected site or an older login of its address.
    func retryPermission(for record: any PendingMoneyWrite) -> PendingRetryPermission {
        .evaluate(record, activeServerID: activeProfile?.id, currentUserID: siteSession?.me.user?.id, sameAddress: sameAddressServerIDs())
    }
    /// Only reads (00 §2.5.5), with the current identity, also for a record of an older login at this address (C-26). A record
    /// the server confirms as executed is dropped here; every other outcome is left to the page. A result for an older
    /// session is not returned.
    func reconcile(_ record: any PendingMoneyWrite) async throws -> PendingReconcileOutcome {
        guard !isUITesting else { throw AppFailure("界面测试模式不执行核对。") }
        let generation = sessionGeneration
        let outcome = try await requireClient().reconcile(record, requestIDUsable: requestIDUsable(), sameAddress: sameAddressServerIDs())
        if outcome.confirmsExecution {
            do { try resolve(record) } catch { report(error) }
        }
        guard generation == sessionGeneration else { throw CancellationError() }
        return outcome
    }

    // MARK: One address, several site ids (X34, C-26)

    /// The connected site and every saved or archived site at its normalized address; empty without a connected site.
    /// The overview, settings, banners and reconciliation pages read records through this, not by the current id alone.
    func sameAddressServerIDs() -> Set<UUID> {
        guard let activeProfile else { return [] }
        return MoneyRecordOrigin.sameAddressIDs(of: activeProfile, among: profiles + Array(profileArchive.values))
    }
    /// The site ids at the address of `serverID`; only itself for an unknown site.
    func sameAddressServerIDs(of serverID: UUID) -> Set<UUID> {
        guard let profile = profileForRecord(serverID: serverID) else { return [serverID] }
        return MoneyRecordOrigin.sameAddressIDs(of: profile, among: profiles + Array(profileArchive.values))
    }
    /// The three kinds at the address of `serverID`, oldest first.
    func pendingMoneyWrites(sameAddressAs serverID: UUID) -> [any PendingMoneyWrite] {
        pendingMoney.writes(serverIDs: sameAddressServerIDs(of: serverID))
    }

    var siteFlags: SiteFlags { SiteFlags(defaults: pushRecords.defaults) }
    /// False once a reply at this address echoed another X-Request-ID; records of its older logins use the same answer.
    func requestIDUsable() -> Bool { siteFlags.requestIDUsable(sameAddress: sameAddressServerIDs()) }
    /// 30 §3.4: called with the X-Request-ID a balance write's reply echoed; a different one marks the connected site.
    func noteRequestIDEcho(_ echoed: String?, for record: PendingBalanceOperation) {
        guard let serverID = activeProfile?.id, BalanceReconciliation.requestIDEchoMismatch(sent: record.key, echoed: echoed) else { return }
        siteFlags.markRequestIDUnreliable(serverID: serverID)
    }
}
