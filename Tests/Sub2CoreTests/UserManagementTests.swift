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
