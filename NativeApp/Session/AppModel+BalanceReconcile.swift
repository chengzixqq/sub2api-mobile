import Foundation
import Sub2Core

/// S3-07: the pending banner's data, the check, “用同一编号重试”, “放弃这笔” and the foreground check (30 §2.3, §3.4, §3.6;
/// C-26, S3D1-05, S3D1-16, S3D1-19). The money rules live in BalanceReconcileSession.swift; this file wires them to the session.
extension AppModel {
    // MARK: - Banner

    func pendingBalance(id: UUID) -> PendingBalanceOperation? { pendingBalances.first { $0.id == id } }
    /// The user's records at the connected address, as the banner shows them; `now` is phone time like createdAt.
    func pendingBannerEntries(userID: Int, now: Date) -> [PendingBannerEntry] {
        guard let serverID = activeProfile?.id else { return [] }
        return BalanceReconcilePresentation.bannerEntries(pendingMoneyWrites(sameAddressAs: serverID), userID: userID, currentServerID: serverID,
                                                          now: now, timeZone: siteSession?.serverTimeZone.timeZone ?? .current)
    }
    func hasPendingBanner(userID: Int) -> Bool { !pendingBannerEntries(userID: userID, now: Date()).isEmpty }

    // MARK: - Check

    /// Only reads, with the current identity, also a record of an older login at this address (C-26). Nothing is settled
    /// here; a result for an older session is not returned.
    func reconcileBalance(_ op: PendingBalanceOperation) async throws -> BalanceReconcileOutcome {
        let generation = sessionGeneration
        let outcome: BalanceReconcileOutcome
        if isUITesting {
            let balance = (demoUsersBySession[generation] ?? DemoData.allUsers).first { $0.id == op.userID }?.balance ?? 0
            guard let fixture = try DemoData.reconcileOutcome(for: op, balance: balance, arguments: ProcessInfo.processInfo.arguments) else {
                throw AppFailure("界面测试模式不执行核对。")
            }
            outcome = fixture
        } else {
            outcome = try await requireClient().reconcileBalance(op, requestIDUsable: requestIDUsable(), sameAddress: sameAddressServerIDs())
        }
        guard generation == sessionGeneration else { throw CancellationError() }
        return outcome
    }
    /// The ledger shows the write ran (an exact match, or a candidate the administrator picked): settled, with 30 §3.4 step 3's
    /// receipt; the detail reads the user and the records again. A record settled meanwhile is left alone.
    func applyReconciled(_ row: UserAdjustment, for op: PendingBalanceOperation) {
        guard pendingBalance(id: op.id) != nil else { return }
        do { try resolve(op) } catch { report(error); return }
        userChanges?.bump(userID: op.userID)
        userList?.setNeedsRefresh()
        Task { await userList?.refreshQuickTopup() }
        receipts.show(Receipt(text: BalanceReconcilePresentation.executedReceipt(row, for: op)))
    }
    /// What the dialog may offer: the sender's email is read only for another administrator's record.
    func retryContext(for op: PendingBalanceOperation) async -> BalanceRetryContext {
        let permission = retryPermission(for: op)
        let label = permission == .otherActor ? await pendingActorLabel(for: op) : nil
        return BalanceRetryContext(permission: permission, actorLabel: label, isHeld: retryHeldUntil(op.id) != nil,
                                   isReadOnly: siteSession?.isReadOnlyToken == true)
    }
    /// 30 §3.4 “这笔由 <邮箱> 发起”: the record keeps only the sender's id, which means the same user at this address; nil without a
    /// sender or for another address, “管理员 #7” when the user cannot be read.
    func pendingActorLabel(for record: any PendingMoneyWrite) async -> String? {
        guard let actor = record.actorUserID, sameAddressServerIDs().contains(record.serverID) else { return nil }
        guard let email = try? await user(id: actor).email.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else {
            return "管理员 #\(actor)"
        }
        return email
    }

    // MARK: - Retry and abandon

    /// “用同一编号重试” (30 §3.4) through BalanceRetry and the only sender, AppModel+Users.updateBalance.
    func retrySameNumber(_ op: PendingBalanceOperation, currentBalance: Decimal?) async -> BalanceRetry.Outcome {
        let generation = sessionGeneration
        let effects = BalanceRetry.Effects(
            current: { [weak self] in self?.pendingBalance(id: $0) },
            permission: { [weak self] in self?.retryPermission(for: $0) ?? .otherActor },
            heldUntil: { [weak self] in self?.retryHeldUntil($0) },
            isReadOnly: { [weak self] in self?.siteSession?.isReadOnlyToken ?? true },
            authorize: { [weak self] in await self?.biometricGate.authorize($0) ?? false },
            persist: { [weak self] record in
                guard let self else { throw CancellationError() }
                return try persisted(record)
            },
            remember: { [weak self] in try self?.remember($0) },
            send: { [weak self] write, onEvent in
                guard let self else { throw CancellationError() }
                return try await updateBalance(write, onEvent: onEvent)
            },
            resolve: { [weak self] in try self?.resolve($0) },
            hold: { [weak self] in self?.holdRetry($0, until: $1) },
            isCurrent: { [weak self] in self?.sessionGeneration == generation },
            report: { [weak self] in self?.report($0) })
        return await BalanceRetry(effects: effects).run(op.id, currentBalance: currentBalance)
    }
    /// The retry ran (30 §3.4 result table, 200): the list and strip take the new balance, the detail reloads (bumpBalance, C-12).
    func applyRetried(_ outcome: WriteOutcome<AdminUser>, for op: PendingBalanceOperation) {
        if let balance = GatedAction.balanceAfter(outcome) { userList?.updateBalance(id: op.userID, balance: balance) } else { userList?.setNeedsRefresh() }
        Task { await userList?.refreshQuickTopup() }
        userChanges?.bumpBalance(userID: op.userID)
        receipts.show(Receipt(text: BalanceReconcilePresentation.writtenReceipt(for: op, replayed: outcome.replayed || outcome.recovered)))
    }
    /// “放弃这笔” after its second confirmation: the record goes, nothing is sent.
    func abandon(_ record: any PendingMoneyWrite) throws { try resolve(record) }
    /// 30 §3.4 step 4 for S3-08's first sends: the action id is saved as soon as any reply carries it.
    func balanceActionIDSaver(for op: PendingBalanceOperation) -> KeyedWriteEventHandler {
        { @MainActor [weak self] event in
            guard case .actionID(let actionID) = event else { return }
            try? self?.remember(op.with(actionID: actionID))
        }
    }
    /// STORE_UNAVAILABLE: the same number waits until `date` (nil clears it).
    func holdRetry(_ id: UUID, until date: Date?) { pendingChecks = pendingChecks.holdingRetry(id, until: date) }
    func retryHeldUntil(_ id: UUID) -> Date? { pendingChecks.retryHeldUntil(id, now: Date()) }

    // MARK: - Foreground

    /// 30 §3.6, after the client resumed (S3D1-19): each balance record of this address once, one pass at a time; only an exact
    /// match settles one, with its receipt. Without a `-ui-reconcile-*` argument the fixtures find nothing and keep everything.
    /// S6-08 adds compensations to ForegroundReconcilePass.
    func reconcilePendingOnForeground() async {
        guard let serverID = activeProfile?.id, let started = pendingChecks.startingForegroundPass() else { return }
        pendingChecks = started
        let generation = sessionGeneration
        defer { if generation == sessionGeneration { pendingChecks = pendingChecks.endingForegroundPass() } }
        let effects = ForegroundReconcilePass.Effects(
            records: { [weak self] in self?.pendingMoneyWrites(sameAddressAs: serverID) ?? [] },
            reconcileBalance: { [weak self] op in
                guard let self else { throw CancellationError() }
                return try await reconcileBalance(op)
            },
            applyExecuted: { [weak self] op, row in self?.applyReconciled(row, for: op) },
            shouldContinue: { [weak self] in self?.sessionGeneration == generation && self?.isSuspended == false })
        await ForegroundReconcilePass(effects: effects).run()
    }

    // MARK: - Fixtures

    /// `-ui-pending-old-site` and `-ui-pending-compensation-here` (DemoData+Users), after `-ui-pending-money`'s records; memory only.
    func seedPendingVariants(for profile: ServerProfile) {
        guard isUITesting, let variants = DemoData.pendingVariants(current: profile, now: Date(), arguments: ProcessInfo.processInfo.arguments),
              !allPendingMoneyWrites.contains(where: { variants.ids.contains($0.id) }) else { return }
        if let site = variants.oldLoginSite { profileArchive[site.id] = site }
        do {
            for record in variants.balances { try remember(record) }
            for record in variants.batches { try remember(record) }
            for record in variants.compensations { try remember(record) }
        } catch { report(error) }
    }
}
