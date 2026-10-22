import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func refreshClient(_ transport: ScriptedTransport, clock: ManualClock, expiresIn: TimeInterval,
                           store: (any CredentialStore)? = nil) -> APIClient {
    APIClient(server: stubServer(), credential: stubTokens(expiresAt: clock.now().addingTimeInterval(expiresIn)), credentialStore: store,
              deviceID: stubDeviceID, transport: transport, requestClock: clock.requestClock)
}

@Test func proactiveRefreshStartsSixtySecondsBeforeExpiry() async throws {
    let clock = ManualClock()
    let soon = ScriptedTransport { request in isRefresh(request) ? okReply(stubRefreshJSON) : okReply(stubUserJSON) }
    let client = refreshClient(soon, clock: clock, expiresIn: 59)
    _ = try await client.user(id: 7)
    #expect(await soon.requests.map(isRefresh) == [true, false])
    let refreshed = TokenPair(accessToken: "new-access", refreshToken: "new-refresh", expiresAt: clock.start.addingTimeInterval(3_600))
    #expect(await client.currentCredential() == .tokens(refreshed))
    let later = ScriptedTransport { _ in okReply(stubUserJSON) }
    _ = try await refreshClient(later, clock: clock, expiresIn: 61).user(id: 7)
    #expect(await later.requests.count == 1)
    let noLifetime = ScriptedTransport { request in
        isRefresh(request) ? okReply(#"{"access_token":"a2","refresh_token":"r2"}"#) : okReply(stubUserJSON)
    }
    let defaulted = refreshClient(noLifetime, clock: clock, expiresIn: -1)
    _ = try await defaulted.user(id: 7)
    guard case .tokens(let pair)? = await defaulted.currentCredential() else { Issue.record("Expected a token pair"); return }
    #expect(pair.accessToken == "a2"); #expect(pair.expiresAt == clock.start.addingTimeInterval(300))
}

@Test func refreshRequestCarriesDeviceIDWithoutAuthorization() async throws {
    let transport = ScriptedTransport { request in isRefresh(request) ? okReply(stubRefreshJSON) : okReply(stubUserJSON) }
    let client = refreshClient(transport, clock: ManualClock(), expiresIn: -1)
    _ = try await client.user(id: 7)
    let refresh = try #require(await transport.requests.first(where: isRefresh))
    #expect(refresh.httpMethod == "POST"); #expect(refresh.timeoutInterval == 20)
    #expect(sentHeader(refresh, "X-Device-ID") == stubDeviceID.uuidString.lowercased()); #expect(sentHeader(refresh, "User-Agent") == "Sub2Mobile-iOS")
    #expect(sentHeader(refresh, "Authorization") == nil); #expect(sentHeader(refresh, "x-api-key") == nil)
    #expect(sentHeader(refresh, "X-Request-ID") != nil)
    let body = try #require(refresh.httpBody)
    #expect(try JSONSerialization.jsonObject(with: body) as? [String: String] == ["refresh_token": "old-refresh"])
    try? await client.logout()
    let logout = try #require(await transport.requests.last)
    #expect(logout.url?.path == "/api/v1/auth/logout"); #expect(sentHeader(logout, "X-Device-ID") == stubDeviceID.uuidString.lowercased())
    #expect(sentHeader(logout, "X-Request-ID") != nil)
}

@Test(arguments: [
    (401, "REFRESH_TOKEN_REUSED", ReasonCatalog.Category.sessionExpired, "登录已失效，请重新登录"),
    (401, "REFRESH_TOKEN_INVALID", .sessionExpired, "登录已失效，请重新登录"),
    (401, "REFRESH_TOKEN_EXPIRED", .sessionExpired, "登录已失效，请重新登录"),
    (401, "TOKEN_REVOKED", .sessionExpired, "登录已失效，请重新登录"),
    (401, "SESSION_BINDING_MISMATCH", .sessionBinding, "网络或设备信息变化导致会话失效，请重新登录"),
    (403, "USER_NOT_ACTIVE", .sessionExpired, "该账号已被禁用"),
    (403, "BACKEND_MODE_ADMIN_ONLY", .permission, "站点处于后端模式，仅管理员可登录"),
    (400, nil, .sessionExpired, "登录已失效，请重新登录")
] as [(Int, String?, ReasonCatalog.Category, String)])
func refreshRejectionEndsSessionWithoutFurtherNetwork(status: Int, reason: String?, category: ReasonCatalog.Category, message: String) async throws {
    let clock = ManualClock(); let store = StubCredentialStore()
    let transport = ScriptedTransport { request in
        isRefresh(request) ? errorReply(status, reason: reason, headers: ["X-Request-ID": "rid-refresh"]) : okReply(stubUserJSON)
    }
    let client = refreshClient(transport, clock: clock, expiresIn: -1, store: store)
    let initial = try #require(await client.currentCredential())
    try await store.save(initial, serverID: client.server.id)
    let first = try #require(await thrownAPIError { _ = try await client.user(id: 7) })
    #expect(first.action == .clearSession); #expect(first.category == category); #expect(first.localizedDescription == message)
    #expect(first.statusCode == status); #expect(first.reason == reason); #expect(first.requestID == "rid-refresh")
    clock.advance(by: 120)
    let second = try #require(await thrownAPIError { _ = try await client.user(id: 7) })
    #expect(second == first)
    #expect(await transport.requests.count == 1)
    // Erasing the Keychain and returning to sign-in belong to the session owner (S0-11).
    #expect(await store.values[client.server.id] == initial)
}

@Test(arguments: [ScriptStep.reply(errorReply(429, reason: "RATE_LIMITED", headers: ["Retry-After": "7"])),
                  .reply(errorReply(503, reason: "SERVICE_UNAVAILABLE")), .reply(errorReply(500)),
                  .reply(HTTPResponse(statusCode: 502, data: Data("<html>".utf8))), .fail(URLError(.notConnectedToInternet)),
                  .fail(URLError(.timedOut)), .reply(HTTPResponse(statusCode: 200, data: Data("<html>wifi login</html>".utf8)))])
func transientRefreshFailureKeepsSessionAndBacksOff(step: ScriptStep) async throws {
    let clock = ManualClock(); let store = StubCredentialStore()
    let transport = ScriptedTransport { request in
        if isRefresh(request) { return try step.resolve() }
        return okReply(stubUserJSON)
    }
    let client = refreshClient(transport, clock: clock, expiresIn: -1, store: store)
    let original = await client.currentCredential()
    #expect(await thrownAPIError { _ = try await client.user(id: 7) } == .refreshDeferred)
    #expect(await client.currentCredential() == original); #expect(await store.values.isEmpty)
    #expect(await thrownAPIError { _ = try await client.user(id: 7) } == .refreshDeferred)
    #expect(await transport.requests.count == 1)
    // Consecutive failures allow the next refresh after 2, 5, 15, 30 and then 30 seconds.
    for (index, wait) in [2.0, 5, 15, 30, 30].enumerated() {
        clock.advance(by: wait - 0.5)
        _ = await thrownAPIError { _ = try await client.user(id: 7) }
        #expect(await transport.requests.count == index + 1, "still backing off before \(wait)s")
        clock.advance(by: 0.5)
        #expect(await thrownAPIError { _ = try await client.user(id: 7) } == .refreshDeferred)
        #expect(await transport.requests.count == index + 2, "refresh retried after \(wait)s")
    }
    #expect(APIError.refreshDeferred.kind == .transport)
    #expect(APIError.refreshDeferred.localizedDescription == "暂时无法续期登录，正在重试")
}

@Test func transientRefreshFailureStillUsesUnexpiredAccess() async throws {
    let transport = ScriptedTransport { request in isRefresh(request) ? errorReply(503, reason: "SERVICE_UNAVAILABLE") : okReply(stubUserJSON) }
    let client = refreshClient(transport, clock: ManualClock(), expiresIn: 30)
    #expect(try await client.user(id: 7).id == 7)
    #expect(try await client.user(id: 7).id == 7)
    let requests = await transport.requests
    #expect(requests.map(isRefresh) == [true, false, false])
    #expect(requests.filter { !isRefresh($0) }.allSatisfy { sentHeader($0, "Authorization") == "Bearer old-access" })
}

@Test func successfulRefreshResetsBackoff() async throws {
    let clock = ManualClock(); let counter = CallCounter()
    let transport = ScriptedTransport { request in
        guard isRefresh(request) else { return okReply(stubUserJSON) }
        return counter.next() == 2 ? okReply(#"{"access_token":"next-access","refresh_token":"next-refresh","expires_in":120}"#)
            : errorReply(503, reason: "SERVICE_UNAVAILABLE")
    }
    let client = refreshClient(transport, clock: clock, expiresIn: -1)
    #expect(await thrownAPIError { _ = try await client.user(id: 7) } == .refreshDeferred)
    clock.advance(by: 2)
    #expect(try await client.user(id: 7).id == 7)
    clock.advance(by: 121)
    #expect(await thrownAPIError { _ = try await client.user(id: 7) } == .refreshDeferred)
    clock.advance(by: 2)
    _ = await thrownAPIError { _ = try await client.user(id: 7) }
    // A count left over from before the success would have meant a 5-second wait here.
    #expect(await transport.requests.filter(isRefresh).count == 4)
}

@Test func unknownUnauthorizedRefreshesThenResendsOnce() async throws {
    let clock = ManualClock()
    let unknown = ScriptedTransport { request in
        if isRefresh(request) { return okReply(stubRefreshJSON) }
        if sentHeader(request, "Authorization") == "Bearer old-access" { return errorReply(401, extra: #","message":"User not authenticated""#) }
        return okReply(stubUserJSON)
    }
    #expect(try await refreshClient(unknown, clock: clock, expiresIn: 3_600).user(id: 7).id == 7)
    #expect(await unknown.requests.map(isRefresh) == [false, true, false])
    let revoked = ScriptedTransport { request in isRefresh(request) ? okReply(stubRefreshJSON) : errorReply(401, reason: "TOKEN_REVOKED") }
    let error = try #require(await thrownAPIError { _ = try await refreshClient(revoked, clock: clock, expiresIn: 3_600).user(id: 7) })
    #expect(error.action == .clearSession); #expect(error.reason == "TOKEN_REVOKED"); #expect(await revoked.requests.count == 1)
    let adminKey = ScriptedTransport { _ in errorReply(401, reason: "INVALID_ADMIN_KEY") }
    let keyClient = APIClient(server: stubServer(), credential: .adminKey("fixture"), deviceID: stubDeviceID, transport: adminKey, requestClock: clock.requestClock)
    let keyError = try #require(await thrownAPIError { _ = try await keyClient.user(id: 7) })
    #expect(keyError.action == .clearCredential); #expect(await adminKey.requests.count == 1)
}

@Test func streamReopensOnceAfterExpiredToken() async throws {
    let counter = CallCounter()
    let transport = ScriptedTransport(stream: { _ in
        let expired = counter.next() == 1
        let body = expired ? #"{"code":"TOKEN_EXPIRED","reason":"TOKEN_EXPIRED"}"# : "data: {\"type\":\"test_complete\",\"success\":true}\n\n"
        let bytes = AsyncThrowingStream<Data, any Error> { continuation in continuation.yield(Data(body.utf8)); continuation.finish() }
        return HTTPStreamResponse(statusCode: expired ? 401 : 200, headers: ["content-type": expired ? "application/json" : "text/event-stream"], bytes: bytes)
    }) { request in isRefresh(request) ? okReply(stubRefreshJSON) : errorReply(500) }
    let client = refreshClient(transport, clock: ManualClock(), expiresIn: 3_600)
    var events = [AccountTestEvent]()
    for try await event in try await client.testAccount(id: 9, model: "fixture-model") { events.append(event) }
    #expect(events.count == 1); #expect(events.first?.isSuccess == true)
    let requests = await transport.requests
    let streams = requests.filter { !isRefresh($0) }
    #expect(requests.filter(isRefresh).count == 1); #expect(streams.count == 2)
    #expect(streams[0].httpBody == streams[1].httpBody); #expect(sentHeader(streams[0], "X-Request-ID") != nil)
    #expect(sentHeader(streams[0], "X-Request-ID") == sentHeader(streams[1], "X-Request-ID"))
    #expect(streams.allSatisfy { sentHeader($0, "X-Device-ID") == stubDeviceID.uuidString.lowercased() })
    #expect(sentHeader(streams[0], "Accept") == "text/event-stream"); #expect(sentHeader(streams[1], "Authorization") == "Bearer new-access")
}

@Test func concurrentReadsShareOneRefreshFailure() async throws {
    let clock = ManualClock(); let started = OpenGate(); let release = OpenGate()
    let transport = ScriptedTransport { request in
        guard isRefresh(request) else { return okReply(stubUserJSON) }
        await started.open(); await release.wait()
        return errorReply(503, reason: "SERVICE_UNAVAILABLE")
    }
    let client = refreshClient(transport, clock: clock, expiresIn: -1)
    let reads = (0..<20).map { _ in Task { try await client.user(id: 7) } }
    await started.wait(); await release.open()
    for read in reads { await #expect(throws: APIError.refreshDeferred) { try await read.value } }
    #expect(await transport.requests.count == 1)
    // One failure means a 2-second wait; one per waiter would have pushed it to 30 seconds.
    clock.advance(by: 2)
    _ = await thrownAPIError { _ = try await client.user(id: 7) }
    #expect(await transport.requests.count == 2)
}
