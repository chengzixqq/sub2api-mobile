import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let managedUserJSON = #"{"id":24,"email":"person@example.invalid","username":"示例","role":"user","balance":"1.00000001","concurrency":2,"status":"active"}"#
private func userReply() -> HTTPResponse {
    HTTPResponse(statusCode: 200, data: Data("{\"code\":0,\"data\":\(managedUserJSON)}".utf8))
}
private func userServer() -> ServerProfile {
    ServerProfile(name: "用户测试", baseURL: URL(string: "https://users.example.invalid")!, authentication: .adminKey)
}
private actor UserWriteTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) async throws -> HTTPResponse
    private var captured: [URLRequest] = []
    init(_ handler: @escaping @Sendable (URLRequest) async throws -> HTTPResponse = { _ in userReply() }) { self.handler = handler }
    func data(for request: URLRequest) async throws -> HTTPResponse { captured.append(request); return try await handler(request) }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw APIError.invalidResponse }
    func requests() -> [URLRequest] { captured }
}

@Test func userMetadataDecodesRealDTOAndRemainsOptional() throws {
    let old = try JSONDecoder().decode(AdminUser.self, from: Data(managedUserJSON.utf8))
    #expect(old.notes == nil && old.createdAt == nil && old.lastUsedAt == nil && old.lastActiveAt == nil)
    #expect(old.rpmLimit == nil && old.currentConcurrency == nil)
    let json = #"{"id":24,"email":"person@example.invalid","balance":0,"status":"active","notes":"内部备注","rpm_limit":0,"current_concurrency":1,"created_at":"2026-10-01T01:02:03.123Z","updated_at":"2026-10-15T04:05:06Z","last_used_at":null,"last_active_at":"2026-10-14T00:00:00Z"}"#
    let current = try JSONDecoder().decode(AdminUser.self, from: Data(json.utf8))
    #expect(current.notes == "内部备注" && current.rpmLimit == 0 && current.currentConcurrency == 1)
    #expect(current.createdAt == "2026-10-01T01:02:03.123Z")
    #expect(current.lastUsedAt == nil && current.lastActiveAt == "2026-10-14T00:00:00Z")
    let roundtrip = try JSONDecoder().decode(AdminUser.self, from: JSONEncoder().encode(current))
    #expect(roundtrip.updatedAt == current.updatedAt && roundtrip.notes == current.notes)
}

@Test func userWriteValidationPreservesPasswordAndExplicitClears() throws {
    let create = UserCreateRequest(email: " person@example.invalid ", password: "  secret  ", concurrency: 0, balance: Decimal(string: "12.00000001"))
    let json = try #require(JSONSerialization.jsonObject(with: create.requestBody()) as? [String: Any])
    #expect(json["email"] as? String == "person@example.invalid")
    #expect(json["password"] as? String == "  secret  ")
    #expect(json["concurrency"] as? Int == 0)
    #expect(json["rpm_limit"] as? Int == 0)
    let update = UserUpdateRequest(password: "", username: "", notes: "", concurrency: 0, adjustmentNotes: "调整并发")
    let changes = try #require(JSONSerialization.jsonObject(with: update.requestBody()) as? [String: Any])
    #expect(changes["password"] == nil && changes["email"] == nil && changes["role"] == nil)
    #expect(changes["username"] as? String == "" && changes["notes"] as? String == "")
    #expect(changes["concurrency"] as? Int == 0 && changes["adjustment_notes"] as? String == "调整并发")
    #expect(!String(reflecting: create).contains("secret"))
    #expect(!String(reflecting: update).contains("调整并发"))
}

@Test func invalidUserWritesFailBeforeAnyRequest() async throws {
    let transport = UserWriteTransport()
    let client = APIClient(server: userServer(), credential: .adminKey("fixture-key"), transport: transport)
    let identity = await client.userWriteIdentity()
    let badCreates = [
        UserCreateRequest(email: "invalid", password: "abcdef"),
        UserCreateRequest(email: "a@example.invalid", password: "abcde"),
        UserCreateRequest(email: "a@example.invalid", password: String(repeating: "密", count: 25)),
        UserCreateRequest(email: "a@example.invalid", password: "abcdef", concurrency: -1),
        UserCreateRequest(email: "a@example.invalid", password: "abcdef", rpmLimit: -1),
        UserCreateRequest(email: "a@example.invalid", password: "abcdef", balance: Decimal(string: "0.000000001"))
    ]
    for input in badCreates {
        #expect(throws: APIError.self) { try PendingUserCreateOperation(serverID: client.server.id, identity: identity, request: input, sendsIdempotencyKey: false) }
    }
    #expect(throws: APIError.self) { try UserUpdateRequest().validate() }
    #expect(throws: APIError.self) { try UserUpdateRequest(password: "short").validate() }
    #expect(throws: APIError.self) { try UserUpdateRequest(concurrency: -1).validate() }
    #expect(await transport.requests().isEmpty)
}

@Test func concurrencyRetryKeepsIdenticalBodyAndIdempotencyKey() async throws {
    let transport = UserWriteTransport { _ in throw URLError(.timedOut) }
    let server = userServer()
    let client = APIClient(server: server, credential: .adminKey("fixture-key"), transport: transport, requestClock: .immediate)
    let operation = try PendingUserUpdateOperation(serverID: server.id, identity: await client.userWriteIdentity(), userID: 24,
        request: UserUpdateRequest(email: "person@example.invalid", password: "new-secret", concurrency: 0, adjustmentNotes: "测试"))
    // Each explicit retry runs the 00 §2.5.4 confirmation: the same key and bytes three times, then “unconfirmed”.
    for _ in 0..<2 {
        await #expect(throws: KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: operation.key,
                                                actionID: nil, lastError: APIError.transport(URLError(.timedOut)))) { try await client.updateUser(operation) }
    }
    let sent = await transport.requests()
    #expect(sent.count == 6)
    #expect(sent.allSatisfy { $0.httpMethod == "PUT" && $0.url?.path == "/api/v1/admin/users/24" })
    #expect(sent.allSatisfy { $0.httpBody == operation.body })
    #expect(sent.allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == operation.key && $0.value(forHTTPHeaderField: "X-Request-ID") == operation.key })
    #expect(!String(reflecting: operation).contains("new-secret"))
}

private func userTokens() -> Credential {
    .tokens(TokenPair(accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: Date().addingTimeInterval(3600)))
}

@Test func expiredTokenWritesResendOnceWithSameBytes() async throws {
    let transport = UserWriteTransport { request in
        if request.url?.path == "/api/v1/auth/refresh" {
            return HTTPResponse(statusCode: 200, data: Data(#"{"code":0,"data":{"access_token":"fresh-access","refresh_token":"fresh-refresh","expires_in":3600}}"#.utf8))
        }
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access" {
            return HTTPResponse(statusCode: 401, data: Data(#"{"code":"TOKEN_EXPIRED","reason":"TOKEN_EXPIRED","message":"blocked"}"#.utf8))
        }
        return userReply()
    }
    let server = userServer()
    let client = APIClient(server: server, credential: userTokens(), transport: transport)
    let identity = await client.userWriteIdentity()
    let operation = try PendingUserUpdateOperation(serverID: server.id, identity: identity, userID: 24, request: UserUpdateRequest(role: .admin, concurrency: 2))
    _ = try await client.updateUser(operation)
    _ = try await client.createUser(PendingUserCreateOperation(serverID: server.id, identity: identity,
                                                               request: UserCreateRequest(email: "a@example.invalid", password: "abcdef", role: .admin), sendsIdempotencyKey: false))
    let sent = await transport.requests()
    #expect(sent.filter { $0.url?.path == "/api/v1/auth/refresh" }.count == 1)
    let updates = sent.filter { $0.httpMethod == "PUT" }, creates = sent.filter { $0.httpMethod == "POST" && $0.url?.path == "/api/v1/admin/users" }
    #expect(updates.count == 2); #expect(creates.count == 1)
    #expect(updates[0].httpBody == updates[1].httpBody)
    for name in ["X-Request-ID", "Idempotency-Key"] {
        #expect(updates[0].value(forHTTPHeaderField: name) == updates[1].value(forHTTPHeaderField: name))
    }
    #expect(updates[0].value(forHTTPHeaderField: "Idempotency-Key") == operation.id.uuidString.lowercased())
    #expect(updates[1].value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access")
    #expect(creates[0].value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access")
}

@Test func stepUpWritesAreNeverResent() async throws {
    let transport = UserWriteTransport { _ in
        HTTPResponse(statusCode: 403, data: Data(#"{"code":403,"reason":"STEP_UP_REQUIRED","message":"blocked"}"#.utf8))
    }
    let server = userServer()
    let client = APIClient(server: server, credential: userTokens(), transport: transport)
    let identity = await client.userWriteIdentity()
    let operation = try PendingUserUpdateOperation(serverID: server.id, identity: identity, userID: 24, request: UserUpdateRequest(role: .admin, concurrency: 2))
    await #expect(throws: APIError.self) { try await client.updateUser(operation) }
    let create = try PendingUserCreateOperation(serverID: server.id, identity: identity,
                                                request: UserCreateRequest(email: "a@example.invalid", password: "abcdef", role: .admin), sendsIdempotencyKey: true)
    await #expect(throws: APIError.self) { try await client.createUser(create) }
    #expect(await transport.requests().count == 2)
}

@Test func preparedUserWriteRejectsOtherStationAndOldIdentity() async throws {
    let transport = UserWriteTransport()
    let server = userServer()
    let client = APIClient(server: server, credential: .adminKey("fixture-key"), transport: transport)
    let identity = await client.userWriteIdentity()
    let changes = UserUpdateRequest(notes: "测试", concurrency: 4)
    let wrongStation = try PendingUserUpdateOperation(serverID: UUID(), identity: identity, userID: 24, request: changes)
    await #expect(throws: APIError.stationMismatch) { try await client.updateUser(wrongStation) }
    let stale = try PendingUserUpdateOperation(serverID: server.id, identity: identity, userID: 24, request: changes)
    let input = UserCreateRequest(email: "a@example.invalid", password: "abcdef")
    let otherStation = try PendingUserCreateOperation(serverID: UUID(), identity: identity, request: input, sendsIdempotencyKey: false)
    await #expect(throws: APIError.stationMismatch) { try await client.createUser(otherStation) }
    await client.cancelAll()
    await #expect(throws: CancellationError.self) { try await client.updateUser(stale) }
    let staleCreate = try PendingUserCreateOperation(serverID: server.id, identity: identity, request: input, sendsIdempotencyKey: false)
    await #expect(throws: CancellationError.self) { try await client.createUser(staleCreate) }
    #expect(await transport.requests().isEmpty)
}

@Test func creationAndOrdinaryEditUseRealRoutesWithoutFalseIdempotency() async throws {
    let transport = UserWriteTransport()
    let server = userServer()
    let client = APIClient(server: server, credential: .adminKey("fixture-key"), transport: transport)
    let identity = await client.userWriteIdentity()
    let create = try PendingUserCreateOperation(serverID: server.id, identity: identity,
                                                request: UserCreateRequest(email: "person@example.invalid", password: "abcdef", role: .vendor), sendsIdempotencyKey: false)
    #expect(create.email == "person@example.invalid" && !String(reflecting: create).contains("abcdef"))
    let created = try await client.createUser(create)
    #expect(created.value.id == 24 && !created.replayed)
    let edit = try PendingUserUpdateOperation(serverID: server.id, identity: identity, userID: 24, request: UserUpdateRequest(username: "新名称", notes: ""))
    #expect(!edit.supportsSafeRetry)
    _ = try await client.updateUser(edit)
    let sent = await transport.requests()
    #expect(sent.count == 2 && sent[0].httpMethod == "POST" && sent[1].httpMethod == "PUT")
    #expect(sent[0].url?.path == "/api/v1/admin/users")
    #expect(sent.allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == nil })
    // Without a key the frozen operation number is still the X-Request-ID, so the server ledger can be matched.
    #expect(sent[0].value(forHTTPHeaderField: "X-Request-ID") == create.key && sent[1].value(forHTTPHeaderField: "X-Request-ID") == edit.key)
}

// D24: the editor passes `admin.idempotent_writes` from /admin/me to both operations.
@Test(arguments: [true, false])
func userWritesCarryIdempotencyKeyOnlyWithCapability(capable: Bool) async throws {
    let me = try JSONDecoder().decode(AdminMe.self, from: Data("{\"server\":{\"capabilities\":[\(capable ? "\"admin.idempotent_writes\"" : "")]}}".utf8))
    let transport = UserWriteTransport()
    let server = userServer()
    let client = APIClient(server: server, credential: .adminKey("fixture-key"), transport: transport)
    let identity = await client.userWriteIdentity()
    let create = try PendingUserCreateOperation(serverID: server.id, identity: identity, request: UserCreateRequest(email: "a@example.invalid", password: "abcdef", role: .user),
                                                sendsIdempotencyKey: me.has(.adminIdempotentWrites))
    let edit = try PendingUserUpdateOperation(serverID: server.id, identity: identity, userID: 24, request: UserUpdateRequest(username: "新名称"),
                                              serverSupportsIdempotentWrites: me.has(.adminIdempotentWrites))
    _ = try await client.createUser(create)
    _ = try await client.updateUser(edit)
    let sent = await transport.requests()
    #expect(sent.count == 2)
    #expect(sent[0].value(forHTTPHeaderField: "Idempotency-Key") == (capable ? create.key : nil))
    #expect(sent[1].value(forHTTPHeaderField: "Idempotency-Key") == (capable ? edit.key : nil))
    #expect(sent[0].value(forHTTPHeaderField: "X-Request-ID") == create.key && sent[1].value(forHTTPHeaderField: "X-Request-ID") == edit.key)
}

/// 60 §3.4: the editor checks Face ID against the initial balance the operation carries, not the form.
@Test func createOperationKeepsTheInitialBalanceForTheFaceIDGate() throws {
    let server = UUID(), identity = UUID()
    let funded = try PendingUserCreateOperation(serverID: server, identity: identity,
                                                request: UserCreateRequest(email: "new@example.com", password: "fixture-password", balance: 150),
                                                sendsIdempotencyKey: true)
    #expect(funded.initialBalance == 150)
    let empty = try PendingUserCreateOperation(serverID: server, identity: identity,
                                               request: UserCreateRequest(email: "new@example.com", password: "fixture-password"),
                                               sendsIdempotencyKey: true)
    #expect(empty.initialBalance == nil)
}

/// S3-01 moved these from APIClient.swift to UserManagement.swift: routes, request classes and numbers stay as they were.
@Test func movedUserMethodsKeepRoutesAndClasses() async throws {
    let transport = ScriptedTransport { request in
        switch request.url?.path ?? "" {
        case "/api/v1/admin/usage/stats": okReply(#"{"total_requests":1,"total_tokens":2,"total_cost":"0.5"}"#)
        case "/api/v1/admin/users/24/api-keys": okReply(#"{"items":[],"total":0,"page":2,"page_size":20}"#)
        default: okReply(managedUserJSON)
        }
    }
    let client = APIClient(server: userServer(), credential: .adminKey("fixture-key"), transport: transport, requestClock: .immediate,
                           serverTimeZone: ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!)
    let identity = await client.userWriteIdentity(), serverID = client.server.id
    let create = try PendingUserCreateOperation(serverID: serverID, identity: identity, request: UserCreateRequest(email: "new@example.invalid", password: "abcdef"),
                                                sendsIdempotencyKey: true)
    let update = try PendingUserUpdateOperation(serverID: serverID, identity: identity, userID: 24, request: UserUpdateRequest(username: "新名称"))
    let balance = PendingBalanceOperation(serverID: serverID, userID: 24, amount: 1, operation: .add)
    _ = try await client.createUser(create)
    _ = try await client.updateUser(update)
    #expect(try await client.userMonthUsage(id: 24).totalCost == Decimal(string: "0.5"))
    _ = try await client.userAPIKeys(userID: 24, maskedView: false)
    _ = try await client.setUserStatus(id: 24, status: "disabled")
    _ = try await client.updateBalance(stubPersisted(balance), sameAddress: [])
    let sent = await transport.requests
    #expect(sent.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == [
        "POST /api/v1/admin/users", "PUT /api/v1/admin/users/24", "GET /api/v1/admin/usage/stats", "GET /api/v1/admin/users/24/api-keys",
        "PUT /api/v1/admin/users/24", "POST /api/v1/admin/users/24/balance"])
    #expect(sent.map(\.timeoutInterval) == [35, 30, 45, 20, 30, 35])
    #expect(sent.map { sentHeader($0, "Idempotency-Key") } == [create.key, nil, nil, nil, nil, balance.id.uuidString.lowercased()])
    #expect(sentHeader(sent[0], "X-Request-ID") == create.key && sentHeader(sent[1], "X-Request-ID") == update.key)
    #expect(sentHeader(sent[5], "X-Request-ID") == balance.id.uuidString.lowercased())
    let usageQuery = sent[2].url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    #expect(usageQuery.contains(URLQueryItem(name: "user_id", value: "24")) && usageQuery.contains(URLQueryItem(name: "timezone", value: "Asia/Shanghai")))
    let keysQuery = sent[3].url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    #expect(keysQuery == [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "page_size", value: "100"), URLQueryItem(name: "sort_by", value: "id"),
                          URLQueryItem(name: "sort_order", value: "asc")])
    #expect(String(decoding: sent[4].httpBody ?? Data(), as: UTF8.self) == #"{"status":"disabled"}"#)
}

/// The old entry forwards to `updateBalance(_:sameAddress: [])` (R19) and still refuses a record of another site.
@Test func legacyUpdateBalanceStillRejectsOtherStation() async throws {
    let transport = ScriptedTransport { _ in okReply(managedUserJSON) }
    let client = APIClient(server: userServer(), credential: .adminKey("fixture-key"), transport: transport, requestClock: .immediate)
    let other = PendingBalanceOperation(serverID: UUID(), userID: 24, amount: 1, operation: .add)
    #expect(await thrownAPIError { _ = try await client.updateBalance(stubPersisted(other), sameAddress: []) } == .stationMismatch)
    #expect(await transport.requests.isEmpty)
    let own = PendingBalanceOperation(serverID: client.server.id, userID: 24, amount: 1, operation: .add)
    #expect(try await client.updateBalance(stubPersisted(own), sameAddress: []).value.id == 24)
    let request = try #require(await transport.requests.first)
    let key = own.id.uuidString.lowercased()
    #expect(sentHeader(request, "Idempotency-Key") == key && sentHeader(request, "X-Request-ID") == key)
}

/// 30 §0.3: “用户 / 供应商 / 管理员”, also in the settings identity line.
@Test func roleTitlesUseUserVendorAdmin() {
    #expect(AdminUserRole.allCases.map(\.title) == ["用户", "供应商", "管理员"])
    #expect(SettingsPresentation.identityLine(email: "x@example.invalid", role: "vendor") == "x@example.invalid · 供应商")
    #expect(SettingsPresentation.identityLine(email: "x@example.invalid", role: "user") == "x@example.invalid · 用户")
}

// MARK: - S3-05 用户详情

private func detailClient(_ transport: ScriptedTransport, clock: RequestClock = .immediate, serverClock: ServerClock = ServerClock()) -> APIClient {
    APIClient(server: userServer(), credential: .adminKey("fixture-key"), transport: transport, requestClock: clock,
              serverTimeZone: ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!, serverClock: serverClock)
}
private func sentQuery(_ request: URLRequest?) -> [String: String] {
    guard let url = request?.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
private func usageSummary(_ tail: String) throws -> UserUsageSummary {
    let json = "{\"total_requests\":1,\"total_tokens\":2,\"total_cost\":\"0.5\"" + tail + "}"
    return try JSONDecoder().decode(UserUsageSummary.self, from: Data(json.utf8))
}

/// 30 §2.2 本月消费: the server's month to date in its zone, and total_actual_cost (what was charged), not total_cost.
@Test func userMonthUsageUsesServerZoneMonthAndActualCost() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"total_requests":3,"total_tokens":40,"total_cost":"1.5","total_actual_cost":"86.1"}"#) }
    // 15:50Z on the phone, an hour ahead on the server: 00:50 on 1 November in Shanghai.
    let clock = ServerClock(offset: 3_600, localNow: { ISO8601DateFormatter().date(from: "2026-10-31T15:50:00Z")! })
    let client = detailClient(transport, serverClock: clock)
    let usage = try await client.userMonthUsage(id: 24)
    #expect(usage.totalActualCost == Decimal(string: "86.1") && usage.totalCost == Decimal(string: "1.5"))
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "GET" && request.url?.path == "/api/v1/admin/usage/stats" && request.timeoutInterval == 45)
    #expect(sentQuery(request) == ["start_date": "2026-11-01", "end_date": "2026-11-01", "timezone": "Asia/Shanghai", "user_id": "24"])
    #expect(await thrownAPIError { _ = try await client.userMonthUsage(id: 0) }?.kind == .validation)
    #expect(await transport.requests.count == 1)
}

@Test func usageSummaryDecodesActualCostOptionally() throws {
    #expect(try usageSummary("").totalActualCost == nil)
    #expect(try usageSummary(#","total_actual_cost":null"#).totalActualCost == nil)
    #expect(try usageSummary(#","total_actual_cost":"abc""#).totalActualCost == nil)
    #expect(try usageSummary(#","total_actual_cost":[1]"#).totalActualCost == nil)
    #expect(try usageSummary(#","total_actual_cost":1.25"#).totalActualCost == Decimal(string: "1.25"))
    #expect(try usageSummary(#","total_actual_cost":"2.5""#).totalActualCost == Decimal(string: "2.5"))
    #expect(try usageSummary(#","total_actual_cost":"2.5""#).totalCost == Decimal(string: "0.5"))
    #expect(UserUsageSummary(totalRequests: 1, totalTokens: 2, totalCost: 1).totalActualCost == nil)
    #expect(UserUsageSummary(totalRequests: 1, totalTokens: 2, totalCost: 1, totalActualCost: 3).totalActualCost == 3)
}

/// 30 §2.4 with admin.idempotent_writes: the same key and bytes after a timeout; IN_PROGRESS beyond 30 seconds is unconfirmed.
@Test func userStatusWithKeyGoesThroughKeyedWrite() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(managedUserJSON))])
    let client = detailClient(transport)
    let key = UUID()
    let outcome = try await client.setUserStatus(id: 24, status: "disabled", idempotencyKey: key)
    #expect(outcome.value.id == 24)
    let sent = await transport.requests
    #expect(sent.count == 2)
    for request in sent {
        #expect(request.httpMethod == "PUT" && request.url?.path == "/api/v1/admin/users/24" && request.timeoutInterval == 35)
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"status":"disabled"}"#)
        #expect(sentHeader(request, "Idempotency-Key") == key.uuidString.lowercased())
        #expect(sentHeader(request, "X-Request-ID") == key.uuidString.lowercased())
    }
    let manual = ManualClock()
    let busy = ScriptedTransport { _ in errorReply(409, reason: "IDEMPOTENCY_IN_PROGRESS", headers: ["Retry-After": "12"]) }
    let waiting = detailClient(busy, clock: manual.advancingClock(SleepRecorder()))
    do {
        _ = try await waiting.setUserStatus(id: 24, status: "active", idempotencyKey: UUID())
        Issue.record("IN_PROGRESS past the wait budget must not succeed")
    } catch let failure as KeyedWriteFailure {
        #expect(failure.disposition == .unconfirmed(.stillProcessing, retryNotBefore: nil))
    }
    #expect(manual.now().timeIntervalSince(manual.start) == 30)
    let idle = ScriptedTransport { _ in okReply(managedUserJSON) }
    let guarded = detailClient(idle)
    #expect(await thrownAPIError { _ = try await guarded.setUserStatus(id: 24, status: "frozen", idempotencyKey: UUID()) }?.kind == .validation)
    #expect(await thrownAPIError { _ = try await guarded.setUserStatus(id: 0, status: "active", idempotencyKey: nil) }?.kind == .validation)
    #expect(await idle.requests.isEmpty)
}

/// Without admin.idempotent_writes the new entry sends what the old two-argument one sends, once.
@Test func userStatusWithoutKeyIsByteForByteTheOldWrite() async throws {
    let transport = ScriptedTransport { _ in okReply(managedUserJSON) }
    let client = detailClient(transport)
    let old = try await client.setUserStatus(id: 24, status: "active")
    let new = try await client.setUserStatus(id: 24, status: "active", idempotencyKey: nil)
    #expect(old.id == new.value.id)
    let sent = await transport.requests
    #expect(sent.count == 2)
    #expect(sent.map(\.httpMethod) == ["PUT", "PUT"] && sent[0].url == sent[1].url && sent[0].httpBody == sent[1].httpBody)
    #expect(String(decoding: sent[1].httpBody ?? Data(), as: UTF8.self) == #"{"status":"active"}"#)
    #expect(sent.map { sentHeader($0, "Idempotency-Key") } == [nil, nil])
    #expect(sent.map(\.timeoutInterval) == [30, 30])
    #expect(sent.allSatisfy { sentHeader($0, "X-Request-ID") != nil })
    let flaky = ScriptedTransport(script: [.fail(URLError(.timedOut))])
    let once = detailClient(flaky)
    await #expect(throws: (any Error).self) { _ = try await once.setUserStatus(id: 24, status: "disabled", idempotencyKey: nil) }
    #expect(await flaky.requests.count == 1)
}

/// 30 §2.4 删除用户: a bare DELETE (a repeat answers 404), so 404 USER_NOT_FOUND means it is gone.
@Test func deleteUserSendsBareDeleteAndTreatsUserNotFoundAsGone() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"message":"User deleted successfully"}"#) }
    #expect(try await detailClient(transport).deleteUser(id: 24))
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "DELETE" && request.url?.path == "/api/v1/admin/users/24")
    #expect((request.httpBody ?? Data()).isEmpty && sentHeader(request, "Idempotency-Key") == nil)
    let gone = ScriptedTransport { _ in errorReply(404, reason: "USER_NOT_FOUND") }
    #expect(try await detailClient(gone).deleteUser(id: 24) == false)
    #expect(await gone.requests.count == 1)
    let unused = ScriptedTransport { _ in okReply("{}") }
    #expect(await thrownAPIError { _ = try await detailClient(unused).deleteUser(id: 0) }?.kind == .validation)
    #expect(await unused.requests.isEmpty)
}

@Test(arguments: [ScriptStep.reply(errorReply(500)), .reply(errorReply(403, reason: "ACCESS_TOKEN_READ_ONLY")),
                  .reply(errorReply(401, reason: "USER_NOT_FOUND")), .fail(URLError(.timedOut))])
func deleteUserKeepsOtherFailures(step: ScriptStep) async throws {
    let transport = ScriptedTransport(script: [step])
    await #expect(throws: (any Error).self) { _ = try await detailClient(transport).deleteUser(id: 24) }
    #expect(await transport.requests.count == 1)
}

// MARK: - S3-09 新建 / 编辑用户的请求体与核对读取

private func posixDecimal(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
private func bodyObject(_ data: Data) throws -> [String: Any] { try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
private func bodyText(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
private func validationMessage(_ body: () throws -> Void) -> String? {
    do { try body(); return nil } catch { return (error as? APIError)?.errorDescription }
}

/// 30 §5.3 / §5.7: groups sorted and unique, the restriction always sent, a blank initial balance left out.
@Test func createRequestCarriesGroupsAndOmitsMissingBalance() throws {
    let grouped = try bodyObject(UserCreateRequest(email: "a@example.invalid", password: "abcdef", allowedGroups: [7, 5, 5], restrictPublicGroups: true).requestBody())
    #expect(grouped["allowed_groups"] as? [Int] == [5, 7] && grouped["restrict_public_groups"] as? Bool == true && grouped["balance"] == nil)
    let none = try bodyObject(UserCreateRequest(email: "a@example.invalid", password: "abcdef").requestBody())
    #expect(none["allowed_groups"] == nil && none["restrict_public_groups"] as? Bool == false)
    let funded = try UserCreateRequest(email: "a@example.invalid", password: "abcdef", balance: 20).requestBody()
    #expect(bodyText(funded).contains(#""balance":20,"#))
    #expect(validationMessage { _ = try UserCreateRequest(email: "a@example.invalid", password: "abcdef", allowedGroups: [0]).requestBody() } == "无效的分组编号。")
}

/// 30 §5.4 step 5 example body, key for key.
@Test func createRequestMatchesSpecExampleBody() throws {
    let request = UserCreateRequest(email: "qi.he@example.com", password: "Qm7v-Tr2p-Hx9k", username: "何琪", notes: "", role: .user, concurrency: 1, rpmLimit: 0,
                                    balance: 20, allowedGroups: [5], restrictPublicGroups: false)
    let data = try request.requestBody(), json = try bodyObject(data)
    #expect(Set(json.keys) == ["allowed_groups", "balance", "concurrency", "email", "notes", "password", "restrict_public_groups", "role", "rpm_limit", "username"])
    #expect(json["email"] as? String == "qi.he@example.com" && json["password"] as? String == "Qm7v-Tr2p-Hx9k" && json["username"] as? String == "何琪")
    #expect(json["notes"] as? String == "" && json["role"] as? String == "user" && json["concurrency"] as? Int == 1 && json["rpm_limit"] as? Int == 0)
    #expect(json["allowed_groups"] as? [Int] == [5] && json["restrict_public_groups"] as? Bool == false)
    #expect(bodyText(data).hasPrefix(#"{"allowed_groups":[5],"balance":20,"#))
    #expect(!String(reflecting: request).contains("Qm7v"))
}

/// 30 §10: a cleared rate is an explicit JSON null under a string key.
@Test func updateRequestEncodesGroupRatesWithExplicitNull() throws {
    let request = UserUpdateRequest(groupRates: [5: posixDecimal("1.3"), 7: nil, 9: 2])
    #expect(try bodyText(request.requestBody()) == #"{"group_rates":{"5":1.3,"7":null,"9":2}}"#)
    let wide = try bodyObject(UserUpdateRequest(groupRates: [12: posixDecimal("1.5"), 3: nil]).requestBody())
    let rates = try #require(wide["group_rates"] as? [String: Any])
    #expect(rates["12"] as? Double == 1.5 && rates["3"] is NSNull && rates.count == 2)
}

/// The server clears every rate on `{}` (SyncUserGroupRates), and `balance` is never editable here.
@Test func updateRequestDropsEmptyGroupRatesAndNeverCarriesBalance() throws {
    let notes = UserUpdateRequest(notes: "x", groupRates: [:])
    #expect(notes.groupRates == nil)
    #expect(try !bodyText(notes.requestBody()).contains("group_rates"))
    #expect(validationMessage { try UserUpdateRequest(groupRates: [:]).validate() } == "请至少修改一个用户字段。")
    #expect(try bodyText(UserUpdateRequest(allowedGroups: []).requestBody()) == #"{"allowed_groups":[]}"#)
    let singles = [UserUpdateRequest(status: "disabled"), UserUpdateRequest(allowedGroups: [3]), UserUpdateRequest(restrictPublicGroups: false)]
    for request in singles { #expect(validationMessage { try request.validate() } == nil) }
    let everything = UserUpdateRequest(email: "b@example.invalid", password: "abcdef", username: "u", notes: "n", role: .vendor, concurrency: 3, rpmLimit: 10,
                                       adjustmentNotes: "扩容", status: "active", allowedGroups: [2, 1], restrictPublicGroups: true, groupRates: [1: 1])
    for request in singles + [notes, everything] { #expect(try bodyObject(request.requestBody())["balance"] == nil) }
    #expect(try bodyObject(everything.requestBody())["allowed_groups"] as? [Int] == [1, 2])
}

@Test(arguments: [
    (UserUpdateRequest(status: "banned"), "无效的用户状态。"),
    (UserUpdateRequest(groupRates: [5: 0]), "要大于 0，最多 3 位小数"),
    (UserUpdateRequest(groupRates: [5: -1]), "要大于 0，最多 3 位小数"),
    (UserUpdateRequest(groupRates: [5: Decimal(string: "1.2345")!]), "要大于 0，最多 3 位小数"),
    (UserUpdateRequest(allowedGroups: [0]), "无效的分组编号。"),
    (UserUpdateRequest(groupRates: [0: 1]), "无效的分组编号。"),
    (UserUpdateRequest(adjustmentNotes: "原因"), "请至少修改一个用户字段。")
])
func updateRequestValidatesNewFields(request: UserUpdateRequest, message: String) async throws {
    #expect(validationMessage { try request.validate() } == message)
    let transport = ScriptedTransport { _ in okReply("{}") }
    let client = APIClient(server: userServer(), credential: .adminKey("fixture-key"), transport: transport)
    let identity = await client.userWriteIdentity()
    #expect(throws: APIError.self) { try PendingUserUpdateOperation(serverID: client.server.id, identity: identity, userID: 24, request: request) }
    #expect(await transport.requests.isEmpty)
}

@Test func validRatesPassUpdateValidation() {
    for text in ["1.234", "0.001", "2"] {
        #expect(validationMessage { try UserUpdateRequest(groupRates: [5: posixDecimal(text)]).validate() } == nil)
    }
}

/// 30 §6.4: adjustment notes go out only with a concurrency change, trimmed and non-empty.
@Test func adjustmentNotesTravelOnlyWithConcurrency() throws {
    #expect(try bodyObject(UserUpdateRequest(notes: "a", adjustmentNotes: "原因").requestBody())["adjustment_notes"] == nil)
    #expect(try bodyObject(UserUpdateRequest(concurrency: 4, adjustmentNotes: "  ").requestBody())["adjustment_notes"] == nil)
    #expect(try bodyObject(UserUpdateRequest(concurrency: 4, adjustmentNotes: " 扩容 ").requestBody())["adjustment_notes"] as? String == "扩容")
}

/// 30 §6.7, 00 §2.5.1: with admin.idempotent_writes every edit is keyed; without it only a concurrency change is.
@Test(arguments: [true, false])
func capableSitesAlwaysRetryUserUpdatesSafely(capable: Bool) throws {
    let requests = [UserUpdateRequest(username: "新名称"), UserUpdateRequest(groupRates: [5: 2]), UserUpdateRequest(status: "disabled"),
                    UserUpdateRequest(allowedGroups: [5], restrictPublicGroups: false), UserUpdateRequest(concurrency: 3)]
    let safe = try requests.map {
        try PendingUserUpdateOperation(serverID: UUID(), identity: UUID(), userID: 24, request: $0, serverSupportsIdempotentWrites: capable).supportsSafeRetry
    }
    #expect(safe == (capable ? [true, true, true, true, true] : [false, false, false, false, true]))
}

/// S3-11 compares the frozen request with a GET when the result is unknown (30 §6.5).
@Test func pendingUpdateKeepsTheFrozenRequest() throws {
    let request = UserUpdateRequest(password: "fixture-secret", groupRates: [5: posixDecimal("1.375")])
    let operation = try PendingUserUpdateOperation(serverID: UUID(), identity: UUID(), userID: 24, request: request)
    let body = try request.requestBody()
    #expect(operation.request == request && operation.body == body)
    let described = String(reflecting: operation)
    #expect(!described.contains("fixture-secret") && !described.contains("1.375"))
}

/// 30 §6.2 降级预检: role=admin, one row, only `total` is read.
@Test func adminCountSendsRoleAdminPageSizeOneAndReadsTotal() async throws {
    let transport = ScriptedTransport { _ in
        okReply(#"{"items":[{"id":7,"email":"admin@example.invalid","balance":0,"status":"active","role":"admin"}],"total":3,"page":1,"page_size":1,"pages":3}"#)
    }
    let client = detailClient(transport)
    #expect(try await client.adminCount() == 3)
    let sent = await transport.requests
    #expect(sent.count == 1 && sent.first?.httpMethod == "GET" && sent.first?.url?.path == "/api/v1/admin/users")
    let query = sentQuery(sent.first)
    #expect(query["role"] == "admin" && query["page"] == "1" && query["page_size"] == "1" && query["include_subscriptions"] == "false")
    #expect(query["search"] == nil)
}

@Test func adminCountWithoutTotalIsInvalidResponse() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"items":[],"page":1,"page_size":1,"has_more":false}"#) }
    #expect(await thrownAPIError { _ = try await detailClient(transport).adminCount() } == .invalidResponse)
}

private func listedUser(_ id: Int, _ email: String, notes: String? = nil) -> String {
    let notesField = notes.map { ",\"notes\":\"\($0)\"" } ?? ""
    return "{\"id\":\(id),\"email\":\"\(email)\",\"balance\":0,\"status\":\"active\"\(notesField)}"
}

/// 00 §2.5.5 / 30 §5.4 step 7: search matches usernames, notes and keys too, so only the whole address counts.
@Test func findUserByEmailMatchesWholeAddressIgnoringCase() async throws {
    let items = [listedUser(31, "xperson@example.invalid"), listedUser(32, "other@example.invalid", notes: "person@example.invalid"),
                 listedUser(33, "person@example.invalid")]
    let transport = ScriptedTransport { _ in okReply("{\"items\":[\(items.joined(separator: ","))],\"total\":3,\"page\":1,\"page_size\":20}") }
    let found = try await detailClient(transport).findUserByEmail(" Person@Example.invalid ")
    #expect(found?.id == 33)
    let first = await transport.requests.first
    let query = sentQuery(first)
    #expect(query["search"] == "Person@Example.invalid" && query["page"] == "1" && query["page_size"] == "20")
}

@Test func findUserByEmailReturnsNilWithoutExactMatchAndRejectsBlank() async throws {
    let transport = ScriptedTransport { _ in okReply("{\"items\":[\(listedUser(31, "xperson@example.invalid"))],\"total\":1,\"page\":1,\"page_size\":20}") }
    #expect(try await detailClient(transport).findUserByEmail("person@example.invalid") == nil)
    let unused = ScriptedTransport { _ in okReply("{}") }
    #expect(await thrownAPIError { _ = try await detailClient(unused).findUserByEmail("  ") }?.kind == .validation)
    #expect(await unused.requests.isEmpty)
}
