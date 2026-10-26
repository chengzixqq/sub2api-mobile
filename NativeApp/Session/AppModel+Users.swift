import Foundation
import Sub2Core

// Stage 3's user wrappers and their -ui-testing branches (S3-01, D11): later items add to the MARK of their topic.
extension AppModel {
    // MARK: - 列表
    /// `status` only filters the fixture list: the old status picker stays until S3-02, and a real site is never sent it (U29).
    func users(query: UserListQuery, status: String? = nil) async throws -> Page<AdminUser> {
        if isUITesting {
            if ProcessInfo.processInfo.arguments.contains("-ui-session-revoked"), let profile = activeProfile,
               let invalidation = SessionInvalidation(error: APIError.server(status: 401, reason: "TOKEN_REVOKED")) {
                // Stands in for the client's report of a revoked session (D06).
                await invalidateSession(invalidation, serverID: profile.id, generation: sessionGeneration)
                throw CancellationError()
            }
            let page = DemoData.userPage(demoUsersBySession[sessionGeneration] ?? DemoData.allUsers, query: query, status: status)
            guard ProcessInfo.processInfo.arguments.contains("-ui-count-user-loads") else { return page }
            demoUserLoads += 1
            let label = "读取 \(demoUserLoads) 次"
            return page.mapItems { var user = $0; user.username = label; return user }
        }
        return try await requireClient().users(query: query)
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
    func userKeys(id: Int, page: Int) async throws -> Page<UserAPIKey> {
        if isUITesting { return Page(items: DemoData.keys, total: 1, page: 1, pageSize: 20, pages: 1) }
        return try await requireClient().userKeys(id: id, page: page)
    }

    // MARK: - 限额

    // MARK: - 替换分组
}
