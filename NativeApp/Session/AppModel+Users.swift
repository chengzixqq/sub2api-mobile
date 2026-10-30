import Foundation
import Sub2Core

// Stage 3's user wrappers and their -ui-testing branches (S3-01, D11): later items add to the MARK of their topic.
extension AppModel {
    // MARK: - 列表
    func users(query: UserListQuery) async throws -> Page<AdminUser> {
        if isUITesting {
            if ProcessInfo.processInfo.arguments.contains("-ui-session-revoked"), let profile = activeProfile,
               let invalidation = SessionInvalidation(error: APIError.server(status: 401, reason: "TOKEN_REVOKED")) {
                // Stands in for the client's report of a revoked session (D06).
                await invalidateSession(invalidation, serverID: profile.id, generation: sessionGeneration)
                throw CancellationError()
            }
            let page = try await userListFixture(query: query)
            guard ProcessInfo.processInfo.arguments.contains("-ui-count-user-loads") else { return page }
            demoUserLoads += 1
            let label = "读取 \(demoUserLoads) 次"
            return page.mapItems { var user = $0; user.username = label; return user }
        }
        return try await requireClient().users(query: query)
    }
    /// 30 §1.3 头像条; whether the site has `users.quick_topup` is the list's check.
    func quickTopup() async throws -> QuickTopupReply {
        if isUITesting {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains(UserListFixtureArgument.quickTopupError) { throw APIError.server(status: 503, reason: "QUICK_TOPUP_UNAVAILABLE") }
            if arguments.contains(UserListFixtureArgument.empty) { return QuickTopupReply(lowBalanceEnabled: true) }
            return DemoData.quickTopupFixture(users: demoUsersBySession[sessionGeneration] ?? DemoData.allUsers)
        }
        return try await requireClient().quickTopup()
    }
    /// One users-usage batch; a read-only token never calls it (R14), and the fixture refuses it the way the server does.
    func usersTodayUsage(ids: [Int]) async throws -> [Int: UserTodayUsage] {
        if isUITesting {
            if siteSession?.isReadOnlyToken == true { throw APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY") }
            if ProcessInfo.processInfo.arguments.contains(UserListFixtureArgument.usageError) { throw APIError.server(status: 500, reason: nil) }
            return DemoData.todayUsage(ids: ids)
        }
        return try await requireClient().usersTodayUsage(ids: ids)
    }
    /// settings/public's global low-balance reminder (30 §1.2), read once per session by the list.
    func userListLowBalanceGlobal() async throws -> UserLowBalanceGlobal {
        if isUITesting { return DemoData.lowBalanceGlobalFixture }
        return UserLowBalanceGlobal(settings: try await requireClient().publicSettings())
    }
    /// UserListFixtureArgument over the session's users; first-page reads are counted per session.
    private func userListFixture(query: UserListQuery) async throws -> Page<AdminUser> {
        let arguments = ProcessInfo.processInfo.arguments, generation = sessionGeneration
        if query.page == 1 {
            let loads = DemoData.userListFirstPageLoads[generation, default: 0] + 1
            DemoData.userListFirstPageLoads[generation] = loads
            if arguments.contains(UserListFixtureArgument.slow), loads == 1 { try await Task.sleep(for: .seconds(6)) }
            if arguments.contains(UserListFixtureArgument.refreshError), loads > 1 { throw APIError.server(status: 500, reason: nil) }
        }
        if arguments.contains(UserListFixtureArgument.forbidden) { throw APIError.server(status: 403, reason: "FORBIDDEN") }
        if arguments.contains(UserListFixtureArgument.error) { throw APIError.server(status: 500, reason: nil) }
        let users = arguments.contains(UserListFixtureArgument.empty) ? [] : demoUsersBySession[generation] ?? DemoData.allUsers
        return DemoData.userPage(users, query: query)
    }

    // MARK: - 详情
    /// A user the fixture does not have answers 404 USER_NOT_FOUND, as the server does.
    func user(id: Int) async throws -> AdminUser {
        if isUITesting {
            try DemoData.failUserDetailRead(.profile)
            guard let result = (demoUsersBySession[sessionGeneration] ?? DemoData.allUsers).first(where: { $0.id == id }) else {
                throw APIError.server(status: 404, reason: "USER_NOT_FOUND")
            }
            return result
        }
        return try await requireClient().user(id: id)
    }
    /// 30 §2.2 本月消费 (S3-05).
    func userMonthUsage(id: Int) async throws -> UserUsageSummary {
        if isUITesting {
            try DemoData.failUserDetailRead(.month)
            return UserUsageSummary(totalRequests: 12, totalTokens: 4200, totalCost: Decimal(string: "0.12")!, totalActualCost: DemoData.monthCostFixture[id] ?? 0)
        }
        return try await requireClient().userMonthUsage(id: id)
    }
    /// 30 §2.2 今日消费 of one user through the users-usage wrapper; no row means nothing spent today. The detail never calls it
    /// for a read-only token (R14).
    func userTodayCost(id: Int) async throws -> Decimal {
        if isUITesting { try DemoData.failUserDetailRead(.today) }
        return try await usersTodayUsage(ids: [id])[id]?.todayActualCost ?? 0
    }
    /// 30 §0.1 本人 (S3D1-14): `/admin/me`'s user. The fixtures name one only with `-ui-users-self <id>`, so by default no fixture user is self.
    var currentAdminUserID: Int? {
        if isUITesting { return UserDetailFixtureArgument.selfUserID(arguments: ProcessInfo.processInfo.arguments) }
        return siteSession?.me.user?.id
    }
    /// 30 §2.4 启用 / 禁用: with admin.idempotent_writes under a new key, retried and waited for by the executor (00 §2.5).
    func setUserStatus(id: Int, status: String) async throws -> WriteOutcome<AdminUser> {
        if isUITesting { return try fixtureSetUserStatus(id: id, status: status) }
        let client = try requireClient()
        let key = siteSession?.has(.adminIdempotentWrites) == true ? UUID() : nil
        return try await client.setUserStatus(id: id, status: status, idempotencyKey: key)
    }
    /// 30 §2.4 删除用户: `false` when the user was already gone (404 USER_NOT_FOUND), which the page treats as deleted.
    func deleteUser(id: Int) async throws -> Bool {
        if isUITesting {
            if siteSession?.isReadOnlyToken == true { throw APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY") }
            let generation = sessionGeneration
            var users = demoUsersBySession[generation] ?? DemoData.allUsers
            guard let index = users.firstIndex(where: { $0.id == id }) else { return false }
            users.remove(at: index); demoUsersBySession[generation] = users
            return true
        }
        return try await requireClient().deleteUser(id: id)
    }
    /// `-ui-user-detail-fail status` answers every status write as the server answers one for an administrator: 500, no reason.
    private func fixtureSetUserStatus(id: Int, status: String) throws -> WriteOutcome<AdminUser> {
        if siteSession?.isReadOnlyToken == true { throw APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY") }
        if UserDetailFixtureArgument.failures(arguments: ProcessInfo.processInfo.arguments).contains(.status) {
            throw APIError.server(status: 500, reason: nil)
        }
        let generation = sessionGeneration
        var users = demoUsersBySession[generation] ?? DemoData.allUsers
        guard let index = users.firstIndex(where: { $0.id == id }) else { throw APIError.server(status: 404, reason: "USER_NOT_FOUND") }
        users[index].status = status
        demoUsersBySession[generation] = users
        return WriteOutcome(value: users[index])
    }

    // MARK: - 新建与编辑
    /// The fixture (S3-10) runs on the session's users through UserCreateFixtureArgument.
    func createUser(_ operation: PendingUserCreateOperation, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminUser> {
        let client = try requireClient()
        if !isUITesting { return try await client.createUser(operation, onEvent: onEvent) }
        let generation = sessionGeneration
        guard operation.identity == (await client.userWriteIdentity()), generation == sessionGeneration else { throw CancellationError() }
        if let refusal = await fixtureSecurityRefusal(body: operation.body) { throw refusal }
        return try await fixtureCreateUser(operation, generation: generation)
    }
    /// S3-11: the fixture refuses as the server does, and is strict (S3D1-10): a key equal to the user's value is a 400, so a
    /// page that sends more than it changed fails its test.
    func updateUser(_ operation: PendingUserUpdateOperation, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminUser> {
        let client = try requireClient()
        if !isUITesting { return try await client.updateUser(operation, onEvent: onEvent) }
        let generation = sessionGeneration
        guard operation.serverID == activeProfile?.id, operation.identity == (await client.userWriteIdentity()), generation == sessionGeneration else {
            throw APIError.stationMismatch
        }
        if let refusal = await fixtureSecurityRefusal(body: operation.body) { throw refusal }
        if siteSession?.isReadOnlyToken == true { throw APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY") }
        if let result = demoUserUpdates[operation.id] { return WriteOutcome(value: result, replayed: true) }
        var users = demoUsersBySession[generation] ?? DemoData.allUsers
        guard let index = users.firstIndex(where: { $0.id == operation.userID }) else { throw APIError.server(status: 404, reason: "USER_NOT_FOUND") }
        let arguments = ProcessInfo.processInfo.arguments
        let lostReply = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: operation.key, actionID: nil, lastError: nil)
        if arguments.contains(UserEditFixtureArgument.saveDrift) { throw lostReply }
        let user = try DemoData.updatedUser(users[index], body: operation.body, users: users)
        users[index] = user; demoUsersBySession[generation] = users; demoUserUpdates[operation.id] = user
        if arguments.contains(UserEditFixtureArgument.saveUncertain) { throw lostReply }
        return WriteOutcome(value: user)
    }

    // MARK: - 编辑用户（S3-11）
    /// 30 §6.2: the user's attribute values; the fixture reads S3-10's session store (S3D1-22).
    func userAttributes(userID: Int) async throws -> [UserAttributeValue] {
        guard isUITesting else { return try await requireClient().userAttributes(userID: userID) }
        return (DemoData.attributeValues(generation: sessionGeneration)[userID] ?? [:])
            .map { UserAttributeValue(attributeID: $0.key, value: $0.value) }.sorted { $0.attributeID < $1.attributeID }
    }
    /// 30 §6.4 step 2: the site's administrators. The fixture counts the session's, plus the signed-in one when no fixture
    /// user is “本人”; `-ui-user-last-admin` answers 1.
    func adminCount() async throws -> Int {
        guard isUITesting else { return try await requireClient().adminCount() }
        if ProcessInfo.processInfo.arguments.contains(UserEditFixtureArgument.lastAdmin) { return 1 }
        let admins = (demoUsersBySession[sessionGeneration] ?? DemoData.allUsers).filter { $0.role == AdminUserRole.admin.rawValue }.count
        return admins + (currentAdminUserID == nil ? 1 : 0)
    }
    /// 30 §6.3 RPM 状态; `-ui-user-rpm-unavailable` answers as a site without the RPM cache, `-ui-user-rpm-failed` fails with 500,
    /// `-ui-user-rpm-ticking` counts one more request at every read.
    func userRPMStatus(id: Int) async throws -> UserRPMStatusReply {
        guard isUITesting else { return try await requireClient().userRPMStatus(id: id) }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(UserEditFixtureArgument.rpmFailed) { throw APIError.server(status: 500, reason: nil) }
        if arguments.contains(UserEditFixtureArgument.rpmUnavailable) { return .unavailable }
        let earlier = DemoData.userRPMReads
        DemoData.userRPMReads += 1
        return .status(DemoData.rpmStatus(userID: id, extraUsed: arguments.contains(UserEditFixtureArgument.rpmTicking) ? earlier : 0))
    }
    /// The edit page's save (UserUpdateSubmission); `isPageAlive` turns false when the page goes away.
    func userEditEffects(isPageAlive: @escaping @MainActor @Sendable () -> Bool) -> UserUpdateSubmission.Effects {
        let generation = sessionGeneration
        return UserUpdateSubmission.Effects(
            target: { [weak self] in
                await self?.userCreateTarget(generation: generation).map { UserUpdateSubmission.Target(serverID: $0.serverID, identity: $0.identity) }
            },
            sendsIdempotencyKey: { [weak self] in self?.siteSession?.has(.adminIdempotentWrites) == true },
            update: { [weak self] operation in
                guard let self else { throw CancellationError() }
                return try await updateUser(operation)
            },
            readUser: { [weak self] id in
                guard let self else { throw CancellationError() }
                return try await user(id: id)
            },
            writeAttributes: { [weak self] userID, values in
                guard let self else { throw CancellationError() }
                try await updateUserAttributes(userID: userID, values: values)
            },
            isCurrent: { [weak self] in self?.sessionGeneration == generation && isPageAlive() })
    }

    // MARK: - 余额写
    /// The only sender of a balance write (S3D1-16; S3-07's retry, S3-08's keypad): another administrator's record is refused
    /// before anything goes out, because the server derives action_id from the sender. Records of an older login at this
    /// address are accepted (C-26); a reply echoing another X-Request-ID marks the site (30 §3.4).
    func updateBalance(_ write: PersistedMoneyWrite<PendingBalanceOperation>, onEvent: @escaping KeyedWriteEventHandler) async throws -> WriteOutcome<AdminUser> {
        let record = write.record, sameAddress = sameAddressServerIDs()
        try MoneyRecordOrigin.checkSender(actorUserID: record.actorUserID, currentUserID: siteSession?.me.user?.id, recordServerID: record.serverID,
                                          currentServerID: activeProfile?.id, sameAddress: sameAddress)
        if isUITesting { return try await fixtureUpdateBalance(record, onEvent: onEvent) }
        let outcome = try await requireClient().updateBalance(write, sameAddress: sameAddress, onEvent: onEvent)
        noteRequestIDEcho(outcome.requestID, for: record)
        return outcome
    }
    /// Runs the write on the session's users. `-ui-balance-retry-step-up` with `-ui-step-up-required` refuses it until verified,
    /// through the same interception as a real refusal.
    private func fixtureUpdateBalance(_ record: PendingBalanceOperation, onEvent: KeyedWriteEventHandler) async throws -> WriteOutcome<AdminUser> {
        if siteSession?.isReadOnlyToken == true { throw APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY") }
        if ProcessInfo.processInfo.arguments.contains(BalanceReconcileFixtureArgument.retryStepUp), stepUpRequirement() == .verify {
            let refusal = APIError.server(status: 403, reason: "STEP_UP_REQUIRED")
            throw refusal.withSecurityOutcome(await interceptSecurity(refusal, isRead: false, generation: sessionGeneration))
        }
        let generation = sessionGeneration, actionID = UUID()
        await onEvent(.actionID(actionID))
        guard generation == sessionGeneration else { throw CancellationError() }
        try await BalanceFixtureArgument.interrupt(record, actionID: actionID, onEvent: onEvent)
        var users = demoUsersBySession[generation] ?? DemoData.allUsers
        guard let index = users.firstIndex(where: { $0.id == record.userID }) else { throw APIError.server(status: 404, reason: "USER_NOT_FOUND") }
        let balance = switch record.operation {
        case .add: users[index].balance + record.amount
        case .subtract: users[index].balance - record.amount
        case .set: record.amount
        }
        // A refund beyond the balance: the server's wrapped error comes back as a 500 without a reason.
        guard balance >= 0 else { throw APIError.server(status: 500, reason: nil) }
        users[index].balance = balance
        demoUsersBySession[generation] = users
        return WriteOutcome(value: users[index], actionID: actionID, requestID: record.key)
    }
    /// S3-08: the keypad's first send (BalanceSubmission) through the only sender above.
    func balanceSubmissionEffects() -> BalanceSubmission.Effects {
        let generation = sessionGeneration
        return BalanceSubmission.Effects(
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
            holdRetry: { [weak self] in self?.holdRetry($0, until: $1) },
            isCurrent: { [weak self] in self?.sessionGeneration == generation },
            now: { Date() },
            report: { [weak self] in self?.report($0) })
    }
    // MARK: - 核对

    // MARK: - Key
    func userAPIKeys(userID: Int) async throws -> [AdminAPIKey] {
        if isUITesting { try DemoData.failUserDetailRead(.keys); return DemoData.apiKeys(userID: userID) }
        return try await requireClient().userAPIKeys(userID: userID, maskedView: siteSession?.has(.apiKeysMaskedView) == true)
    }

    // MARK: - 限额

    // MARK: - 替换分组

    // MARK: - 充值与调整记录（30 §4，S3-04）
    /// The full list reads 20 a page; the detail's latest five (S3-05) pass `pageSize: 5`.
    func balanceHistory(userID: Int, page: Int, pageSize: Int = PageSize.standard) async throws -> BalanceHistoryPage {
        if isUITesting {
            if pageSize == UserDetailPresentation.ledgerPeekSize { try DemoData.failUserDetailRead(.ledger) }
            return try DemoData.balanceHistory(userID: userID, page: page, pageSize: pageSize)
        }
        return try await requireClient().balanceHistory(userID: userID, page: page, pageSize: pageSize)
    }

    // MARK: - 新建用户（S3-10）
    /// 30 §5.6: read once per session into `userAttributeDefinitions` (S3D1-05); S3-11 reads the same cache.
    func loadUserAttributeDefinitions() async throws -> [UserAttributeDefinition] {
        if let cached = userAttributeDefinitions { return cached }
        let generation = sessionGeneration
        let definitions: [UserAttributeDefinition]
        if isUITesting { definitions = DemoData.userAttributeDefinitions(arguments: ProcessInfo.processInfo.arguments) }
        else { definitions = try await requireClient().userAttributeDefinitions() }
        guard generation == sessionGeneration else { throw CancellationError() }
        userAttributeDefinitions = definitions
        return definitions
    }
    /// `-ui-user-attr-fail` refuses every write as the server refuses a bad value.
    @discardableResult
    func updateUserAttributes(userID: Int, values: [Int: String]) async throws -> [UserAttributeValue] {
        guard isUITesting else { return try await requireClient().updateUserAttributes(userID: userID, values: values) }
        if ProcessInfo.processInfo.arguments.contains(UserCreateFixtureArgument.attributeFailure) {
            throw APIError.server(status: 400, reason: "ATTRIBUTE_VALIDATION_FAILED")
        }
        let generation = sessionGeneration
        var store = DemoData.attributeValues(generation: generation)
        store[userID, default: [:]].merge(values) { _, new in new }
        DemoData.userAttributeValues[generation] = store
        return store[userID, default: [:]].map { UserAttributeValue(attributeID: $0.key, value: $0.value) }.sorted { $0.attributeID < $1.attributeID }
    }
    /// 30 §5.4 step 7: the fixture matches the session's users as the server's search does, then the address ignoring case.
    func findUserByEmail(_ email: String) async throws -> AdminUser? {
        guard isUITesting else { return try await requireClient().findUserByEmail(email) }
        if DemoData.failsUserReadBack(arguments: ProcessInfo.processInfo.arguments) { throw APIError.server(status: 503, reason: nil) }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return (demoUsersBySession[sessionGeneration] ?? DemoData.allUsers).first { $0.email.caseInsensitiveCompare(address) == .orderedSame }
    }
    /// The new user page's send (UserCreateSubmission); `isPageAlive` turns false when the page goes away.
    func userCreateEffects(isPageAlive: @escaping @MainActor @Sendable () -> Bool) -> UserCreateSubmission.Effects {
        let generation = sessionGeneration
        return UserCreateSubmission.Effects(
            authorize: { [weak self] in await self?.biometricGate.authorize($0) ?? false },
            target: { [weak self] in await self?.userCreateTarget(generation: generation) },
            sendsIdempotencyKey: { [weak self] in self?.siteSession?.has(.adminIdempotentWrites) == true },
            create: { [weak self] operation in
                guard let self else { throw CancellationError() }
                return try await createUser(operation)
            },
            findByEmail: { [weak self] email in
                guard let self else { throw CancellationError() }
                return try await findUserByEmail(email)
            },
            writeAttributes: { [weak self] userID, values in
                guard let self else { throw CancellationError() }
                try await updateUserAttributes(userID: userID, values: values)
            },
            isCurrent: { [weak self] in self?.sessionGeneration == generation && isPageAlive() })
    }
    /// The site and the client's write identity, read together for this session (D13).
    private func userCreateTarget(generation: UUID) async -> UserCreateSubmission.Target? {
        guard generation == sessionGeneration, let client, let profile = activeProfile else { return nil }
        let identity = await client.userWriteIdentity()
        guard generation == sessionGeneration else { return nil }
        return UserCreateSubmission.Target(serverID: profile.id, identity: identity)
    }
    /// A replayed number answers the first result; a used address (or `-ui-user-email-exists` once) 409 EMAIL_EXISTS.
    private func fixtureCreateUser(_ operation: PendingUserCreateOperation, generation: UUID) async throws -> WriteOutcome<AdminUser> {
        typealias Argument = UserCreateFixtureArgument
        let arguments = ProcessInfo.processInfo.arguments
        if siteSession?.isReadOnlyToken == true { throw APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY") }
        if let first = DemoData.userCreations[operation.id] { return WriteOutcome(value: first, replayed: true) }
        if arguments.contains(Argument.slow) { try await Task.sleep(for: .seconds(3)) }
        guard generation == sessionGeneration else { throw CancellationError() }
        if arguments.contains(Argument.invalid) { throw APIError.server(status: 400, reason: nil) }
        var users = demoUsersBySession[generation] ?? DemoData.allUsers
        if DemoData.answersEmailExists(operation.email, users: users, arguments: arguments) { throw APIError.server(status: 409, reason: "EMAIL_EXISTS") }
        let lostReply = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: operation.key, actionID: nil, lastError: nil)
        if arguments.contains(Argument.lost) { throw lostReply }
        let user = try DemoData.createdUser(body: operation.body, id: (users.map(\.id).max() ?? 0) + 1)
        users.insert(user, at: 0); demoUsersBySession[generation] = users
        DemoData.userCreations[operation.id] = user
        if arguments.contains(Argument.uncertain) { throw lostReply }
        return WriteOutcome(value: user)
    }
}
