import Foundation
import Sub2Core

/// S6-09's session wiring of the compensation sheet: the submission's effects, the read-only check of a pending compensation,
/// the user's subscriptions, the grant's receipt, and under `-ui-testing` the fixture server's answers (RedeemFixtures). Every
/// send goes through S6-08's `sendCompensation`.
extension AppModel {
    /// `verifying` turns the sheet's Face ID overlay on and off around the check.
    func compensationSubmission(verifying: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }) -> CompensationSubmission {
        let generation = sessionGeneration
        return CompensationSubmission(effects: CompensationSubmission.Effects(
            gate: { [weak self] userID in self?.moneyWriteGate(.compensation(userID: userID)) ?? .paused(.compensation) },
            authorize: { [weak self] action in
                guard let self else { return false }
                guard biometricGate.needsVerification(action) else { return true }
                verifying(true)
                defer { verifying(false) }
                return await biometricGate.authorize(action)
            },
            persist: { [weak self] grant in
                guard let self else { throw CancellationError() }
                return try persisted(grant)
            },
            send: { [weak self] write, onEvent in
                guard let self else { throw CancellationError() }
                return try await deliverCompensation(write, onEvent: onEvent)
            },
            resolve: { [weak self] in try self?.resolve($0) },
            record: { [weak self] id in self?.pendingCompensations.first { $0.id == id } },
            retryContext: { [weak self] in self?.compensationRetryContext(for: $0) ?? .refusing },
            hold: { [weak self] in self?.holdRetry($0, until: $1) },
            bump: { [weak self] userID in
                self?.userChanges?.bump(userID: userID)
                self?.userList?.setNeedsRefresh()
            },
            bumpBalance: { [weak self] userID in
                guard let self else { return }
                userChanges?.bumpBalance(userID: userID)
                userList?.setNeedsRefresh()
                Task { await self.userList?.refreshQuickTopup() }
            },
            listChanged: { RedeemCodesModel.noteExternalChange() },
            isCurrent: { [weak self] in self?.sessionGeneration == generation },
            now: { Date() }))
    }

    /// What the pending page may offer now (D17, X34); a compensation retries past its idempotency expiry (19.4 step 7).
    func compensationRetryContext(for grant: PendingCompensation, actorLabel: String? = nil) -> RedeemRetryContext {
        RedeemRetryContext(permission: retryPermission(for: grant), isReadOnly: siteSession?.isReadOnlyToken ?? true, retryNotBefore: retryHeldUntil(grant.id),
                           isLegacyServer: false, isPastIdempotencyExpiry: false, actorLabel: actorLabel)
    }

    /// 60 §19.4 step 6: only reads, with the current identity, also for an older login at this address (C-26); nothing is settled
    /// here. Under `-ui-testing` the `-ui-reconcile-*` answers (S6-08, S6D1-15); without one the check fails.
    func checkCompensation(_ grant: PendingCompensation) async throws -> CompensationReconcileOutcome {
        let generation = sessionGeneration
        let outcome: CompensationReconcileOutcome
        if isUITesting {
            guard let fixture = try compensationReconcileFixture(grant) else { throw AppFailure("界面测试模式不执行核对。") }
            outcome = fixture
        } else {
            outcome = try await requireClient().reconcileCompensation(grant, sameAddress: sameAddressServerIDs())
        }
        guard generation == sessionGeneration else { throw CancellationError() }
        return outcome
    }

    /// The user the sheet grants to, read by id (a route carries no object).
    func grantUser(id: Int) async throws -> AdminUser {
        let user = try await user(id: id)
        return isUITesting ? DemoData.grantUser(user, arguments: ProcessInfo.processInfo.arguments) : user
    }
    /// 60 §19.2: read once when the subscription type is chosen.
    func grantSubscriptions(userID: Int) async throws -> [AdminUserSubscription] {
        if isUITesting {
            return try DemoData.grantSubscriptions(userID: userID, now: client?.serverClock.now() ?? Date(), arguments: ProcessInfo.processInfo.arguments)
        }
        return try await requireClient().userSubscriptions(userID: userID)
    }
    /// The directory's active subscription groups in its order (S6D1-05).
    var grantSubscriptionGroups: [AdminGroup] { (groupDirectory?.groups ?? []).filter(\.isActiveSubscriptionGroup) }
    var grantGroupNames: [Int: String] {
        Dictionary((groupDirectory?.groups ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// 60 §19.3 成功回执: “已向 王小明 发放 $10.00 余额” with a gift, or the replay's line; “查看兑换码” pushes `.redeem(open:)` on the
    /// current stack. The code itself is never shown.
    func showGrantReceipt(_ code: AdminRedeemCode, replayed: Bool, grant: PendingCompensation, router: AppRouter) {
        let what = RedeemGrantCopy.what(of: grant, groupName: grant.groupID.flatMap { groupDirectory?.name(for: $0) })
        let id = code.id
        receipts.show(Receipt(text: RedeemGrantCopy.grantedReceipt(userName: grant.userDisplayName, what: what, replayed: replayed), systemImage: "gift",
                              action: ReceiptAction(title: RedeemGrantPresentation.viewCodeAction) { router.push(.redeem(open: id)) }))
    }

    /// S6-08's only sender; under `-ui-testing` the fixture server answers instead of its stub, and a grant changes the
    /// session's fixture user as the server would.
    private func deliverCompensation(_ write: PersistedMoneyWrite<PendingCompensation>,
                                     onEvent: @escaping KeyedWriteEventHandler) async throws -> WriteOutcome<AdminRedeemCode> {
        let outcome = try await sendCompensation(write, onEvent: onEvent)
        guard isUITesting else { return outcome }
        let grant = write.record, now = client?.serverClock.now() ?? Date()
        let reply = try DemoData.grantReply(for: grant, store: RedeemDemoStore.current(for: sessionGeneration, base: now), now: now,
                                            arguments: ProcessInfo.processInfo.arguments)
        if !reply.replayed {
            var users = demoUsersBySession[sessionGeneration] ?? DemoData.allUsers
            if let index = users.firstIndex(where: { $0.id == grant.userID }) {
                users[index] = DemoData.granted(users[index], by: grant)
                demoUsersBySession[sessionGeneration] = users
            }
        }
        return reply
    }
}
