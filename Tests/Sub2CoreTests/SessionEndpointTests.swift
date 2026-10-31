import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import Sub2Core

/// Collects onSessionInvalid calls from any thread.
private final class InvalidationLog: Sendable {
    private let values = Mutex<[SessionInvalidation]>([])
    var all: [SessionInvalidation] { values.withLock { $0 } }
    var handler: @Sendable (SessionInvalidation) -> Void { { [self] value in values.withLock { $0.append(value) } } }
}

private func sessionClient(_ transport: ScriptedTransport, credential: Credential = stubTokens(), store: (any CredentialStore)? = nil,
                           clock: RequestClock = .immediate, log: InvalidationLog? = nil) -> APIClient {
    APIClient(server: stubServer(), credential: credential, credentialStore: store, deviceID: stubDeviceID, transport: transport,
              requestClock: clock, onSessionInvalid: log?.handler)
}
private func bodyText(_ request: URLRequest?) -> String? { request?.httpBody.map { String(decoding: $0, as: UTF8.self) } }

// MARK: Logout (00 §1.7.5 step 2, D15)

@Test func logoutSendsBearerAndRefreshTokenWithoutRefreshing() async throws {
    let store = StubCredentialStore()
    let transport = ScriptedTransport { _ in okReply(#"{"message":"Logged out successfully"}"#) }
    let expired = stubTokens(expiresAt: Date().addingTimeInterval(-60))
    let client = sessionClient(transport, credential: expired, store: store)
    try await store.save(expired, serverID: client.server.id)
    try await client.logout()
    let requests = await transport.requests
    #expect(requests.count == 1)
    let logout = try #require(requests.first)
    #expect(logout.url?.path == "/api/v1/auth/logout"); #expect(logout.httpMethod == "POST")
    #expect(sentHeader(logout, "Authorization") == "Bearer old-access")
    #expect(sentHeader(logout, "X-Device-ID") == stubDeviceID.uuidString.lowercased())
    #expect(bodyText(logout) == #"{"refresh_token":"old-refresh"}"#)
    #expect(await client.currentCredential() == nil)
    #expect(await store.values[client.server.id] == nil)
}

@Test func logoutWithEmptyRefreshTokenStillEndsTheAccessSession() async throws {
    let transport = ScriptedTransport { _ in okReply("{}") }
    let client = sessionClient(transport, credential: .tokens(TokenPair(accessToken: "only-access", refreshToken: "", expiresAt: Date().addingTimeInterval(600))))
    try await client.logout()
    let logout = try #require(await transport.requests.first)
    #expect(await transport.requests.count == 1)
    #expect(bodyText(logout) == "{}"); #expect(sentHeader(logout, "Authorization") == "Bearer only-access")
}

@Test(arguments: [Credential.adminKey("fixture-key"), .accessToken("sat_fixture")])
func machineCredentialLogoutSendsNothing(credential: Credential) async throws {
    let transport = ScriptedTransport { _ in okReply("{}") }
    let client = sessionClient(transport, credential: credential)
    try await client.logout()
    #expect(await transport.requests.isEmpty)
    #expect(await client.currentCredential() == nil)
}

@Test(arguments: [ScriptStep.reply(errorReply(401, reason: "TOKEN_REVOKED")), .fail(URLError(.notConnectedToInternet))])
func logoutFailureNeverReportsSessionInvalidation(step: ScriptStep) async throws {
    let log = InvalidationLog()
    let client = sessionClient(ScriptedTransport(script: [step]), log: log)
    await #expect(throws: APIError.self) { try await client.logout() }
    #expect(log.all.isEmpty)
    #expect(await client.currentCredential() == nil)
}

// MARK: Sessions, access tokens and push devices (00 §1.8, 60 §5–§7)

@Test func sessionsDecodeItemsAndRequireJWT() async throws {
    let json = #"{"items":[{"id":"0a1b","device_name":"iPhone","client_type":"ios","ip":"203.0.113.24","last_seen_at":"2026-10-17T09:41:00Z","current":true},"#
        + #"{"id":"ff00","device_name":"","user_agent":"Mozilla/5.0","current":false}]}"#
    let transport = ScriptedTransport { _ in okReply(json) }
    let items = try await sessionClient(transport).sessions()
    #expect(items.map(\.id) == ["0a1b", "ff00"]); #expect(items.map(\.current) == [true, false])
    #expect(items[0].clientType == "ios"); #expect(items[1].clientType == nil); #expect(items[1].userAgent == "Mozilla/5.0")
    let get = try #require(await transport.requests.first)
    #expect(get.url?.path == "/api/v1/auth/sessions"); #expect(get.httpMethod == "GET"); #expect(get.timeoutInterval == 15)
    for credential in [Credential.adminKey("fixture-key"), .accessToken("sat_fixture")] {
        let silent = ScriptedTransport { _ in okReply("{}") }
        let client = sessionClient(silent, credential: credential)
        await #expect(throws: APIError.self) { _ = try await client.sessions() }
        await #expect(throws: APIError.self) { _ = try await client.revokeSession(id: "0a1b") }
        await #expect(throws: APIError.self) { try await client.revokeOtherSessions() }
        #expect(await silent.requests.isEmpty)
    }
}

@Test func revokeSessionReturnsCurrentAndValidatesID() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"message":"ok","current":true}"#) }
    let client = sessionClient(transport)
    #expect(try await client.revokeSession(id: "0a1b2c") == true)
    let delete = try #require(await transport.requests.first)
    #expect(delete.httpMethod == "DELETE"); #expect(delete.url?.path == "/api/v1/auth/sessions/0a1b2c")
    #expect(sentHeader(delete, "Authorization") == "Bearer old-access")
    for invalid in ["", "a/b", "a b", String(repeating: "a", count: 129)] {
        await #expect(throws: APIError.self) { _ = try await client.revokeSession(id: invalid) }
    }
    #expect(await transport.requests.count == 1)
    let missing = sessionClient(ScriptedTransport(script: [.reply(errorReply(404, reason: "SESSION_NOT_FOUND"))]))
    let error = try #require(await thrownAPIError { _ = try await missing.revokeSession(id: "dead") })
    #expect(error.reason == "SESSION_NOT_FOUND"); #expect(error.kind == .notFound)
}

@Test func revokeOtherSessionsAlwaysKeepsCurrent() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"message":"ok"}"#) }
    try await sessionClient(transport).revokeOtherSessions()
    let post = try #require(await transport.requests.first)
    #expect(post.httpMethod == "POST"); #expect(post.url?.path == "/api/v1/auth/revoke-all-sessions")
    #expect(bodyText(post) == #"{"keep_current":true}"#)
    #expect(sentHeader(post, "Content-Type") == "application/json"); #expect(sentHeader(post, "Authorization") == "Bearer old-access")
    // A write without a key is never sent twice (00 §2.4).
    let busy = ScriptedTransport(script: [.reply(errorReply(503))])
    await #expect(throws: APIError.self) { try await sessionClient(busy).revokeOtherSessions() }
    #expect(await busy.requests.count == 1)
}

@Test func revokeAccessTokenReturnsCurrent() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"message":"ok","current":true}"#) }
    let client = sessionClient(transport, credential: .accessToken("sat_fixture"))
    #expect(try await client.revokeAccessToken(id: 5) == true)
    let delete = try #require(await transport.requests.first)
    #expect(delete.httpMethod == "DELETE"); #expect(delete.url?.path == "/api/v1/admin/access-tokens/5")
    #expect(sentHeader(delete, "x-api-key") == "sat_fixture"); #expect(sentHeader(delete, "Authorization") == nil)
    await #expect(throws: APIError.self) { _ = try await client.revokeAccessToken(id: 0) }
    #expect(await transport.requests.count == 1)
    let other = ScriptedTransport { _ in okReply(#"{"message":"ok"}"#) }
    #expect(try await sessionClient(other, credential: .accessToken("sat_fixture")).revokeAccessToken(id: 6) == false)
}

@Test func deletePushDeviceUsesDeleteWithoutBody() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"message":"Push device deleted"}"#) }
    let client = sessionClient(transport, credential: .adminKey("fixture-key"))
    try await client.deletePushDevice(id: 12)
    let delete = try #require(await transport.requests.first)
    #expect(delete.httpMethod == "DELETE"); #expect(delete.url?.path == "/api/v1/admin/push/devices/12"); #expect(delete.httpBody == nil)
    await #expect(throws: APIError.self) { try await client.deletePushDevice(id: 0) }
    #expect(await transport.requests.count == 1)
}

// MARK: Session invalidation report (D06: only through `surfaced`, once per generation)

@Test func sessionInvalidationIsReportedOncePerGeneration() async throws {
    let log = InvalidationLog()
    let transport = ScriptedTransport { _ in errorReply(401, reason: "TOKEN_REVOKED") }
    let client = sessionClient(transport, log: log)
    async let first: Void = { _ = try? await client.user(id: 1) }()
    async let second: Void = { _ = try? await client.user(id: 2) }()
    async let third: Void = { _ = try? await client.users(query: UserListQuery()) }()
    _ = await (first, second, third)
    #expect(log.all.count == 1); #expect(log.all.first?.cause == .expired); #expect(log.all.first?.reason == "TOKEN_REVOKED")
    #expect(await transport.requests(path: "/auth/refresh").isEmpty)
    // A new generation (switching back to this client after cancelAll) reports again.
    await client.cancelAll()
    let error = try #require(await thrownAPIError { _ = try await client.user(id: 3) })
    #expect(error.reason == "TOKEN_REVOKED"); #expect(log.all.count == 2)
}

@Test func keyedWriteRejectionIsReported() async throws {
    let log = InvalidationLog()
    let client = sessionClient(ScriptedTransport(script: [.reply(errorReply(401, reason: "INVALID_ADMIN_KEY"))]), credential: .adminKey("fixture-key"), log: log)
    let write = stubPersisted(PendingBalanceOperation(serverID: client.server.id, userID: 7, amount: 1, operation: .add))
    await #expect(throws: APIError.self) { _ = try await client.updateBalance(write, sameAddress: []) }
    #expect(log.all.map(\.cause) == [.invalidCredential])
}

@Test func businessErrorsThatKeepTheSessionAreNotReported() async throws {
    let log = InvalidationLog()
    let steps: [ScriptStep] = [.reply(errorReply(403, reason: "FORBIDDEN")), .reply(errorReply(404, reason: "USER_NOT_FOUND")),
                               .reply(errorReply(429, reason: "RATE_LIMITED")), .reply(errorReply(403, reason: "ACCESS_TOKEN_READ_ONLY"))]
    for step in steps {
        let client = sessionClient(ScriptedTransport(script: [step]), log: log)
        _ = await thrownAPIError { _ = try await client.user(id: 7) }
    }
    #expect(log.all.isEmpty)
}

@Test func cancelledClientNeverReportsInvalidation() async throws {
    let log = InvalidationLog(); let started = OpenGate(); let release = OpenGate()
    let transport = ScriptedTransport { _ in await started.open(); await release.wait(); return errorReply(401, reason: "TOKEN_REVOKED") }
    let client = sessionClient(transport, log: log)
    let pending = Task { try await client.user(id: 7) }
    await started.wait(); await client.cancelAll(); await release.open()
    await #expect(throws: CancellationError.self) { try await pending.value }
    #expect(log.all.isEmpty)
}

// D06 consistency: refreshVerdict == .endSession ⇔ the thrown error is a SessionInvalidation ⇔ exactly one report.
@Test(arguments: [
    (401, "REFRESH_TOKEN_INVALID"), (401, "REFRESH_TOKEN_EXPIRED"), (401, "REFRESH_TOKEN_REUSED"), (401, "TOKEN_REVOKED"),
    (401, "SESSION_BINDING_MISMATCH"), (401, nil), (401, "SOMETHING_NEW"), (400, nil), (400, "VALIDATION_ERROR"),
    (403, "USER_NOT_ACTIVE"), (403, "BACKEND_MODE_ADMIN_ONLY"), (403, "FORBIDDEN"), (403, "WORKSPACE_DISABLED"),
    (404, nil), (408, nil), (429, "RATE_LIMITED"), (500, nil), (502, nil), (503, nil)
] as [(Int, String?)])
func refreshOutcomeAndInvalidationReportAgree(status: Int, reason: String?) async throws {
    let log = InvalidationLog(); let clock = ManualClock()
    let transport = ScriptedTransport { request in isRefresh(request) ? errorReply(status, reason: reason) : okReply(stubUserJSON) }
    let client = sessionClient(transport, credential: stubTokens(expiresAt: clock.now().addingTimeInterval(-1)), clock: clock.requestClock, log: log)
    let error = try #require(await thrownAPIError { _ = try await client.user(id: 7) })
    let ends = RequestPolicy.refreshVerdict(status: status, reason: reason) == .endSession
    #expect((SessionInvalidation(error: error) != nil) == ends)
    #expect(log.all.count == (ends ? 1 : 0))
    if !ends { #expect(error == .refreshDeferred) }
}

@Test func refreshNetworkFailureKeepsTheSessionWithoutReport() async throws {
    let log = InvalidationLog(); let clock = ManualClock()
    let transport = ScriptedTransport { request in
        if isRefresh(request) { throw URLError(.notConnectedToInternet) }
        return okReply(stubUserJSON)
    }
    let expired = stubTokens(expiresAt: clock.now().addingTimeInterval(-1))
    let client = sessionClient(transport, credential: expired, clock: clock.requestClock, log: log)
    #expect(await thrownAPIError { _ = try await client.user(id: 7) } == .refreshDeferred)
    #expect(log.all.isEmpty); #expect(await client.currentCredential() == expired)
}

@Test func missingRefreshTokenIsReportedOnce() async throws {
    let log = InvalidationLog()
    let transport = ScriptedTransport { _ in okReply(stubUserJSON) }
    let client = sessionClient(transport, credential: .tokens(TokenPair(accessToken: "a", refreshToken: "", expiresAt: Date().addingTimeInterval(-1))), log: log)
    #expect(await thrownAPIError { _ = try await client.user(id: 7) } == .authenticationRequired)
    _ = await thrownAPIError { _ = try await client.user(id: 8) }
    #expect(log.all.map(\.cause) == [.expired])
    #expect(await transport.requests.isEmpty)
}
