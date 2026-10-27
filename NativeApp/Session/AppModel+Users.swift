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
    func user(id: Int) async throws -> AdminUser {
        if isUITesting {
            guard let result = (demoUsersBySession[sessionGeneration] ?? DemoData.allUsers).first(where: { $0.id == id }) else { throw APIError.invalidResponse }
            return result
        }
        return try await requireClient().user(id: id)
    }
    func userUsage(id: Int) async throws -> UserUsageSummary {
        if isUITesting { return UserUsageSummary(totalRequests: 12, totalTokens: 4200, totalCost: Decimal(string: "0.12")!) }
        return try await requireClient().userUsage(id: id)
    }

    // MARK: - 新建与编辑
    func createUser(_ operation: PendingUserCreateOperation) async throws -> WriteOutcome<AdminUser> {
        let client = try requireClient()
        if !isUITesting { return try await client.createUser(operation) }
        let generation = sessionGeneration
        guard operation.identity == (await client.userWriteIdentity()), generation == sessionGeneration else { throw CancellationError() }
        if let refusal = await fixtureSecurityRefusal(body: operation.body) { throw refusal }
        var payload = try JSONSerialization.jsonObject(with: operation.body) as! [String: Any]
        payload.removeValue(forKey: "password")
        var users = demoUsersBySession[generation] ?? DemoData.allUsers
        guard !users.contains(where: { $0.email == operation.email }) else {
            throw APIError(kind: .validation, message: "此邮箱已经存在。")
        }
        payload["id"] = (users.map(\.id).max() ?? 0) + 1
        payload["balance"] = payload["balance"] ?? 0
        payload["status"] = "active"
        payload["created_at"] = ISO8601DateFormatter().string(from: Date())
        let user = try JSONDecoder().decode(AdminUser.self, from: JSONSerialization.data(withJSONObject: payload))
        users.insert(user, at: 0); demoUsersBySession[generation] = users
        return WriteOutcome(value: user)
    }
    func updateUser(_ operation: PendingUserUpdateOperation) async throws -> WriteOutcome<AdminUser> {
        let client = try requireClient()
        if !isUITesting { return try await client.updateUser(operation) }
        let generation = sessionGeneration
        guard operation.serverID == activeProfile?.id, operation.identity == (await client.userWriteIdentity()), generation == sessionGeneration else {
            throw APIError.stationMismatch
        }
        if let refusal = await fixtureSecurityRefusal(body: operation.body) { throw refusal }
        if let result = demoUserUpdates[operation.id] { return WriteOutcome(value: result, replayed: true) }
        var users = demoUsersBySession[generation] ?? DemoData.allUsers
        guard let index = users.firstIndex(where: { $0.id == operation.userID }) else { throw APIError.invalidResponse }
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(users[index])) as! [String: Any]
        let changes = try JSONSerialization.jsonObject(with: operation.body) as! [String: Any]
        for (key, value) in changes where key != "password" && key != "adjustment_notes" { payload[key] = value }
        let user = try JSONDecoder().decode(AdminUser.self, from: JSONSerialization.data(withJSONObject: payload))
        users[index] = user; demoUsersBySession[generation] = users; demoUserUpdates[operation.id] = user
        return WriteOutcome(value: user)
    }

    // MARK: - 余额写

    // MARK: - 核对

    // MARK: - Key
    func userAPIKeys(userID: Int) async throws -> [AdminAPIKey] {
        if isUITesting { return DemoData.apiKeys(userID: userID) }
        return try await requireClient().userAPIKeys(userID: userID, maskedView: siteSession?.has(.apiKeysMaskedView) == true)
    }

    // MARK: - 限额

    // MARK: - 替换分组

    // MARK: - 充值与调整记录（30 §4，S3-04）
    /// The full list reads 20 a page; the detail's latest five (S3-05) pass `pageSize: 5`.
    func balanceHistory(userID: Int, page: Int, pageSize: Int = PageSize.standard) async throws -> BalanceHistoryPage {
        if isUITesting { return try DemoData.balanceHistory(userID: userID, page: page, pageSize: pageSize) }
        return try await requireClient().balanceHistory(userID: userID, page: page, pageSize: pageSize)
    }
}
