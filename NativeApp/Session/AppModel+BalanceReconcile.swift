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
    /// match settles one, with its receipt. Then the address's compensations the same way (60 §19.4 step 9, S6-08); records going
    /// out are skipped, redeem batches are never checked on their own (60 §11.6). Without a `-ui-reconcile-*` argument the
    /// fixtures find nothing and keep everything.
    func reconcilePendingOnForeground() async {
        guard let serverID = activeProfile?.id, let started = pendingChecks.startingForegroundPass() else { return }
        pendingChecks = started
        let generation = sessionGeneration
        defer { if generation == sessionGeneration { pendingChecks = pendingChecks.endingForegroundPass() } }
        let effects = ForegroundReconcilePass.Effects(
            records: { [weak self] in
                self?.pendingMoneyWrites(sameAddressAs: serverID).filter { !AppModel.moneyWritesInFlight.contains($0.id) } ?? []
            },
            reconcileBalance: { [weak self] op in
                guard let self else { throw CancellationError() }
                return try await reconcileBalance(op)
            },
            applyExecuted: { [weak self] op, row in self?.applyReconciled(row, for: op) },
            shouldContinue: { [weak self] in self?.sessionGeneration == generation && self?.isSuspended == false })
        await ForegroundReconcilePass(effects: effects).run()
        await compensationForegroundPass(serverID: serverID, generation: generation).run()
    }

    // MARK: - Compensations (S6-08)

    /// Compensations going out now (60 §19.4 step 9): the foreground check skips them. Keyed by record id, so one set serves
    /// every session.
    static let moneyWritesInFlight = MoneyWriteInFlight()

    /// The only sender of a compensation, first send and “用同一编号重试” alike (60 §19.4): the sender is checked first (S3D1-16,
    /// S6D1-07) and the record is marked going out for the whole send. Nothing is settled here: the caller follows
    /// GrantResultAction. UI tests grant at once unless S6-09's fixtures step in.
    func sendCompensation(_ write: PersistedMoneyWrite<PendingCompensation>,
                          onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminRedeemCode> {
        let grant = write.record
        return try await AppModel.moneyWritesInFlight.sending(grant.id) {
            let sameAddress = sameAddressServerIDs()
            try MoneyRecordOrigin.checkSender(actorUserID: grant.actorUserID, currentUserID: siteSession?.me.user?.id, recordServerID: grant.serverID,
                                              currentServerID: activeProfile?.id, sameAddress: sameAddress)
            if isUITesting { return WriteOutcome(value: Self.fixtureRedeemCode(for: grant, status: "used", usedBy: grant.userID)) }
            return try await requireClient().createAndRedeem(write, sameAddress: sameAddress, onEvent: onEvent)
        }
    }
    /// 60 §19.4 step 6: the check found the grant redeemed for its user. Settled with its receipt, and the user's pages read
    /// again (bumpBalance for a balance grant, C-12, S3D1-03). A record settled meanwhile is left alone.
    func settleIssuedCompensation(_ grant: PendingCompensation) {
        guard pendingCompensations.contains(where: { $0.id == grant.id }) else { return }
        do { try resolve(grant) } catch { report(error); return }
        if grant.type == .balance {
            userChanges?.bumpBalance(userID: grant.userID)
            Task { await userList?.refreshQuickTopup() }
        } else {
            userChanges?.bump(userID: grant.userID)
        }
        userList?.setNeedsRefresh()
        let groupName = grant.groupID.flatMap { groupDirectory?.name(for: $0) }
        receipts.show(Receipt(text: RedeemGrantCopy.reconciledReceipt(grant, groupName: groupName), systemImage: "gift"))
    }
    /// The compensation part of reconcilePendingOnForeground: the address's records, read with the current identity.
    func compensationForegroundPass(serverID: UUID, generation: UUID) -> CompensationForegroundPass {
        CompensationForegroundPass(effects: CompensationForegroundPass.Effects(
            records: { [weak self] in self?.pendingMoneyWrites(sameAddressAs: serverID).compactMap { $0 as? PendingCompensation } ?? [] },
            isInFlight: { AppModel.moneyWritesInFlight.contains($0) },
            reconcile: { [weak self] grant in
                guard let self else { throw CancellationError() }
                return try await foregroundCompensationCheck(grant)
            },
            settle: { [weak self] grant, _ in self?.settleIssuedCompensation(grant) },
            shouldContinue: { [weak self] in self?.sessionGeneration == generation && self?.isSuspended == false }))
    }
    /// What a compensation check finds in UI tests (S6D1-15, also S6-09's check page): S3-07's executed / notfound / failed and
    /// three more; nil without one.
    func compensationReconcileFixture(_ grant: PendingCompensation) throws -> CompensationReconcileOutcome? {
        let arguments = ProcessInfo.processInfo.arguments
        func code(_ status: String, usedBy: Int?) -> AdminRedeemCode { Self.fixtureRedeemCode(for: grant, status: status, usedBy: usedBy) }
        if arguments.contains(BalanceReconcileFixtureArgument.failed) { throw APIError.server(status: 500, reason: nil) }
        if arguments.contains(BalanceReconcileFixtureArgument.executed) { return .issued(code("used", usedBy: grant.userID)) }
        if arguments.contains(BalanceReconcileFixtureArgument.notExecuted) { return .notFound }
        if arguments.contains(CompensationReconcileFixtureArgument.unused) { return .createdNotRedeemed(code("unused", usedBy: nil)) }
        if arguments.contains(CompensationReconcileFixtureArgument.otherUser) { return .redeemedByOther(code("used", usedBy: grant.userID + 1_000)) }
        if arguments.contains(CompensationReconcileFixtureArgument.unverifiable) { return .unverifiable(code("used", usedBy: nil)) }
        return nil
    }
    /// Only reads (00 §2.5.5); a result for an older session is not returned.
    private func foregroundCompensationCheck(_ grant: PendingCompensation) async throws -> CompensationReconcileOutcome? {
        let generation = sessionGeneration
        let outcome: CompensationReconcileOutcome?
        if isUITesting {
            outcome = try compensationReconcileFixture(grant)
        } else {
            outcome = try await requireClient().reconcileCompensation(grant, sameAddress: sameAddressServerIDs())
        }
        guard generation == sessionGeneration else { throw CancellationError() }
        return outcome
    }
    /// A UI test server's copy of `grant`'s code.
    private static func fixtureRedeemCode(for grant: PendingCompensation, status: String, usedBy: Int?) -> AdminRedeemCode {
        AdminRedeemCode(id: 9_301, code: grant.code, type: grant.type.rawValue, value: grant.value, status: status, usedBy: usedBy,
                        usedAt: usedBy.map { _ in Date() }, groupID: grant.groupID, validityDays: grant.validityDays, notes: grant.notes)
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

/// S6-08's `-ui-testing` answers of a compensation check besides S3-07's executed / notfound / failed (S6D1-15).
enum CompensationReconcileFixtureArgument {
    /// The code exists unused: the run stopped half way.
    static let unused = "-ui-reconcile-unused"
    /// Another user redeemed the code.
    static let otherUser = "-ui-reconcile-other-user"
    /// Marked used without a user.
    static let unverifiable = "-ui-reconcile-unverifiable"
}
