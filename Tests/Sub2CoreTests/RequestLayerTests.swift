import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func layerClient(_ transport: ScriptedTransport, credential: Credential? = .adminKey("fixture"), deviceID: UUID? = stubDeviceID,
                         clock: RequestClock = .immediate) -> APIClient {
    APIClient(server: stubServer(), credential: credential, deviceID: deviceID, transport: transport, requestClock: clock)
}
private let device = stubDeviceID.uuidString.lowercased()

@Test func everyRequestCarriesFixedIdentityAndDeviceID() async throws {
    let transport = ScriptedTransport { request in request.url?.path == "/api/v1/settings/public" ? okReply("{}") : okReply(stubUserJSON) }
    let client = layerClient(transport)
    _ = try await client.user(id: 7)
    _ = try await client.publicSettings()
    let requests = await transport.requests
    #expect(requests.count == 2)
    for request in requests {
        #expect(sentHeader(request, "User-Agent") == "Sub2Mobile-iOS"); #expect(sentHeader(request, "Accept-Language") == "zh-CN")
        #expect(sentHeader(request, "Accept") == "application/json"); #expect(sentHeader(request, "X-Device-ID") == device)
        #expect(sentHeader(request, "X-Request-ID") == nil); #expect(sentHeader(request, "Content-Type") == nil)
    }
    #expect(sentHeader(requests.last, "x-api-key") == nil)
    let anonymous = ScriptedTransport { _ in okReply(stubUserJSON) }
    _ = try await layerClient(anonymous, deviceID: nil).user(id: 7)
    let first = await anonymous.requests.first
    #expect(sentHeader(first, "X-Device-ID") == nil); #expect(sentHeader(first, "User-Agent") == "Sub2Mobile-iOS")
}

@Test(arguments: [Credential.adminKey("fixture"), .accessToken("sat_fixture"), stubTokens()])
func authenticationHeadersAreMutuallyExclusive(credential: Credential) async throws {
    let transport = ScriptedTransport { _ in okReply(stubUserJSON) }
    _ = try await layerClient(transport, credential: credential).user(id: 7)
    let request = await transport.requests.first
    switch credential {
    case .adminKey(let key), .accessToken(let key):
        #expect(sentHeader(request, "x-api-key") == key); #expect(sentHeader(request, "Authorization") == nil)
    case .tokens(let pair):
        #expect(sentHeader(request, "Authorization") == "Bearer " + pair.accessToken); #expect(sentHeader(request, "x-api-key") == nil)
    }
}

@Test func callerHeadersCannotOverrideReservedHeaders() async throws {
    let transport = ScriptedTransport { _ in okReply(stubUserJSON) }
    let _: AdminUser = try await layerClient(transport).request("admin/users/7", headers: [
        "Authorization": "Bearer stolen", "X-API-Key": "other", "X-Device-ID": "other", "User-Agent": "Other", "Accept-Language": "en",
        "Idempotency-Key": "k", "x-request-id": "r", "Accept": "text/event-stream", "If-None-Match": "\"v1\""
    ])
    let request = await transport.requests.first
    #expect(sentHeader(request, "x-api-key") == "fixture"); #expect(sentHeader(request, "Authorization") == nil)
    #expect(sentHeader(request, "X-Device-ID") == device); #expect(sentHeader(request, "User-Agent") == "Sub2Mobile-iOS")
    #expect(sentHeader(request, "Accept-Language") == "zh-CN")
    #expect(sentHeader(request, "Idempotency-Key") == nil); #expect(sentHeader(request, "X-Request-ID") == nil)
    #expect(sentHeader(request, "Accept") == "text/event-stream"); #expect(sentHeader(request, "If-None-Match") == "\"v1\"")
}

@Test func writesCarryRequestIDAndKeyedWritesReuseKey() async throws {
    let transport = ScriptedTransport { _ in okReply(stubUserJSON) }
    let client = layerClient(transport)
    _ = try await client.setUserStatus(id: 7, status: "disabled")
    _ = try await client.setUserStatus(id: 7, status: "active")
    let operation = PendingBalanceOperation(serverID: client.server.id, userID: 7, amount: 1, operation: .add)
    _ = try await client.updateBalance(stubPersisted(operation))
    let requests = await transport.requests
    let first = try #require(sentHeader(requests[0], "X-Request-ID"))
    #expect(first == first.lowercased()); #expect(UUID(uuidString: first) != nil); #expect(first.utf8.count <= 64)
    #expect(sentHeader(requests[1], "X-Request-ID") != first)
    #expect(sentHeader(requests[0], "Idempotency-Key") == nil); #expect(sentHeader(requests[0], "Content-Type") == "application/json")
    let key = operation.id.uuidString.lowercased()
    #expect(sentHeader(requests[2], "Idempotency-Key") == key); #expect(sentHeader(requests[2], "X-Request-ID") == key)
}

@Test(arguments: ["read", "unkeyedWrite", "keyedWrite", "readBatch"])
func expiredTokenResendsEveryMethodOnceWithIdenticalBytes(kind: String) async throws {
    let transport = ScriptedTransport { request in
        if isRefresh(request) { return okReply(stubRefreshJSON) }
        if sentHeader(request, "Authorization") == "Bearer old-access" { return errorReply(401, reason: "TOKEN_EXPIRED") }
        return okReply(request.url?.path.hasSuffix("/batch") == true ? #"{"stats":{}}"# : stubUserJSON)
    }
    let client = layerClient(transport, credential: stubTokens())
    switch kind {
    case "read": _ = try await client.user(id: 7)
    case "unkeyedWrite": _ = try await client.setUserStatus(id: 7, status: "active")
    case "keyedWrite": _ = try await client.updateBalance(stubPersisted(PendingBalanceOperation(serverID: client.server.id, userID: 7, amount: 1, operation: .add)))
    default: _ = try await client.accountTodayStats(ids: [9])
    }
    let requests = await transport.requests
    let business = requests.filter { !isRefresh($0) }
    #expect(requests.filter(isRefresh).count == 1); #expect(business.count == 2)
    #expect(business[0].url == business[1].url); #expect(business[0].httpMethod == business[1].httpMethod)
    #expect(business[0].httpBody == business[1].httpBody)
    for name in ["X-Request-ID", "Idempotency-Key"] { #expect(sentHeader(business[0], name) == sentHeader(business[1], name), "\(name)") }
    #expect(sentHeader(business[1], "Authorization") == "Bearer new-access")
    if kind != "read" { #expect(sentHeader(business[0], "X-Request-ID") != nil) }
}

@Test func expiredTokenIsResentOnlyOnce() async throws {
    let transport = ScriptedTransport { request in isRefresh(request) ? okReply(stubRefreshJSON) : errorReply(401, reason: "TOKEN_EXPIRED") }
    let client = layerClient(transport, credential: stubTokens())
    let error = try #require(await thrownAPIError { _ = try await client.setUserStatus(id: 7, status: "active") })
    #expect(error.statusCode == 401); #expect(error.localizedDescription == "登录已失效，请重新登录")
    #expect(error.action == .clearSession); #expect(error.category == .sessionExpired)
    let requests = await transport.requests
    #expect(requests.filter(isRefresh).count == 1); #expect(requests.filter { !isRefresh($0) }.count == 2)
}

@Test(arguments: [ScriptStep.fail(URLError(.timedOut)), .fail(URLError(.networkConnectionLost)),
                  .reply(HTTPResponse(statusCode: 502, data: Data("<html>bad gateway</html>".utf8))), .reply(errorReply(503)),
                  .reply(errorReply(503, reason: "SERVICE_UNAVAILABLE")), .reply(errorReply(504))])
func readsRetryTransientFailuresTwiceWithBackoff(step: ScriptStep) async throws {
    let transport = ScriptedTransport(script: [step, step, .reply(okReply(stubUserJSON))])
    let recorder = SleepRecorder()
    let client = layerClient(transport, clock: .recording(recorder, jitter: .milliseconds(250)))
    #expect(try await client.user(id: 7).id == 7)
    #expect(await transport.requests.count == 3)
    #expect(await recorder.durations == [.milliseconds(1_250), .milliseconds(3_250)])
}

@Test func readsGiveUpAfterTwoRetries() async throws {
    let unavailable = ScriptedTransport(script: [.reply(errorReply(503, reason: "SERVICE_UNAVAILABLE"))])
    let error = try #require(await thrownAPIError { _ = try await layerClient(unavailable).user(id: 7) })
    #expect(error.statusCode == 503); #expect(await unavailable.requests.count == 3)
    let offline = ScriptedTransport(script: [.fail(URLError(.timedOut))])
    let timeout = try #require(await thrownAPIError { _ = try await layerClient(offline).user(id: 7) })
    #expect(timeout.kind == .transport); #expect(await offline.requests.count == 3)
}

@Test(arguments: [ScriptStep.reply(errorReply(400)), .reply(errorReply(403, reason: "FORBIDDEN")), .reply(errorReply(404, reason: "USER_NOT_FOUND")),
                  .reply(errorReply(409)), .reply(errorReply(429, reason: "RATE_LIMITED")), .reply(errorReply(500)),
                  .reply(errorReply(503, reason: "ACCOUNT_STATS_UNAVAILABLE")), .fail(URLError(.unsupportedURL)),
                  .reply(HTTPResponse(statusCode: 200, data: Data("<html>portal</html>".utf8)))])
func nonRetryableOutcomesSendOnce(step: ScriptStep) async throws {
    let transport = ScriptedTransport(script: [step, .reply(okReply(stubUserJSON))])
    let recorder = SleepRecorder()
    await #expect(throws: APIError.self) { try await layerClient(transport, clock: .recording(recorder)).user(id: 7) }
    #expect(await transport.requests.count == 1); #expect(await recorder.durations.isEmpty)
}

/// Keyed writes do retry on their own (00 §2.5.4); KeyedWriteExecutorTests covers them.
@Test(arguments: [ScriptStep.reply(errorReply(503)), .fail(URLError(.timedOut))])
func unkeyedWritesAndLoginNeverAutomaticallyRetry(step: ScriptStep) async throws {
    let recorder = SleepRecorder()
    let operations: [@Sendable (APIClient) async throws -> Void] = [
        { _ = try await $0.setUserStatus(id: 7, status: "active") },
        { _ = try await $0.login(email: "admin@example.invalid", password: "only-test") },
        { _ = try await $0.completeTOTP(tempToken: "temporary", code: "123456") }
    ]
    for (index, operation) in operations.enumerated() {
        let transport = ScriptedTransport(script: [step, .reply(okReply(stubUserJSON))])
        await #expect(throws: APIError.self, "operation \(index)") { try await operation(layerClient(transport, clock: .recording(recorder))) }
        #expect(await transport.requests.count == 1, "operation \(index)")
    }
    #expect(await recorder.durations.isEmpty)
}

@Test func retryWaitIsCancelledBySessionGeneration() async throws {
    let sleeping = OpenGate()
    let transport = ScriptedTransport(script: [.reply(errorReply(503)), .reply(okReply(stubUserJSON))])
    let clock = RequestClock(sleep: { _ in await sleeping.open(); try await Task.sleep(for: .seconds(60)) }, jitter: { .zero })
    let client = layerClient(transport, clock: clock)
    let read = Task { try await client.user(id: 7) }
    // If the read never waits, open the gate so the test fails instead of hanging.
    let watcher = Task { _ = try? await read.value; await sleeping.open() }
    await sleeping.wait()
    let started = ContinuousClock.now
    await client.cancelAll()
    await #expect(throws: CancellationError.self) { try await read.value }
    #expect(ContinuousClock.now - started < .seconds(10))
    _ = await watcher.value
    #expect(await transport.requests.count == 1)
}

@Test(arguments: [(["Retry-After": "7"], #","retry_after":12"#, 7), ([:], #","retry_after":12"#, 12),
                  ([:], #","metadata":{"retry_after":"9"}"#, 9), ([:], "", 30)] as [([String: String], String, Int)])
func rateLimitedReadsReportSecondsWithoutRetry(headers: [String: String], extra: String, seconds: Int) async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(429, reason: "RATE_LIMITED", headers: headers, extra: extra))])
    let error = try #require(await thrownAPIError { _ = try await layerClient(transport).user(id: 7) })
    #expect(error.kind == .rateLimited); #expect(error.retryAfter == seconds); #expect(await transport.requests.count == 1)
}

@Test func requestWithHeadersReturnsStatusAndLowercasedHeaders() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(stubUserJSON, status: 201, headers: ["X-Request-ID": "rid", "ETag": "\"e1\""])),
                                               .reply(errorReply(404, reason: "USER_NOT_FOUND", headers: ["X-Request-ID": "rid-404"]))])
    let client = layerClient(transport)
    let response: APIResponse<AdminUser> = try await client.requestWithHeaders("admin/users/7")
    #expect(response.status == 201); #expect(response.value.id == 7)
    #expect(response.header("x-request-id") == "rid"); #expect(response.header("ETag") == "\"e1\""); #expect(response.requestID == "rid")
    #expect(response.headers.keys.allSatisfy { $0 == $0.lowercased() })
    let error = try #require(await thrownAPIError { let _: AdminUser = try await client.request("admin/users/7") })
    #expect(error.requestID == "rid-404"); #expect(error.kind == .notFound)
}

@Test func timeoutsFollowRequestCategories() async throws {
    let transport = ScriptedTransport { request in isRefresh(request) ? okReply(stubRefreshJSON) : okReply("{}") }
    let client = layerClient(transport, credential: stubTokens(expiresAt: Date().addingTimeInterval(-60)))
    let identity = await client.userWriteIdentity()
    let hour = AnalyticsQuery(start: Date(timeIntervalSince1970: 1_792_022_400), end: Date(timeIntervalSince1970: 1_792_026_000))
    _ = try? await client.publicSettings()
    _ = try? await client.user(id: 7)
    _ = try? await client.users(page: 1, search: "", status: nil)
    _ = try? await client.accountTodayStats(ids: [9])
    _ = try? await client.setUserStatus(id: 7, status: "active")
    _ = try? await client.updateBalance(stubPersisted(PendingBalanceOperation(serverID: client.server.id, userID: 7, amount: 1, operation: .add)))
    _ = try? await client.setAccountsSchedulable(ids: [9], enabled: true, identity: identity)
    _ = try? await client.refreshAccount(id: 9)
    _ = try? await client.dashboard()
    _ = try? await client.dashboardTrend()
    _ = try? await client.dashboardCostSnapshot()
    _ = try? await client.dashboardMonitoring()
    _ = try? await client.requestRecords(page: 1, filter: RequestLogFilter())
    _ = try? await client.usageAnalysis(hour)
    _ = try? await client.userUsage(id: 7)
    _ = try? await client.login(email: "admin@example.invalid", password: "only-test")
    let requests = await transport.requests
    #expect(requests.filter { $0.url?.path == "/api/v1/admin/usage/stats" }.map(\.timeoutInterval) == [45, 45])
    let sent = requests.map { ("\($0.httpMethod ?? "") \($0.url?.path ?? "")", $0.timeoutInterval) }
    let timeouts = Dictionary(sent, uniquingKeysWith: { first, _ in first })
    let expected: [String: TimeInterval] = [
        "GET /api/v1/settings/public": 15, "POST /api/v1/auth/refresh": 20, "GET /api/v1/admin/users/7": 20, "GET /api/v1/admin/users": 20,
        "POST /api/v1/admin/accounts/today-stats/batch": 20, "PUT /api/v1/admin/users/7": 30, "POST /api/v1/admin/users/7/balance": 35,
        "POST /api/v1/admin/accounts/bulk-update": 65, "POST /api/v1/admin/accounts/9/refresh": 65, "GET /api/v1/admin/dashboard/stats": 90,
        "GET /api/v1/admin/dashboard/trend": 45, "GET /api/v1/admin/dashboard/snapshot-v2": 45, "GET /api/v1/admin/ops/dashboard/overview": 45,
        "GET /api/v1/admin/usage": 20, "GET /api/v1/admin/usage/stats": 45, "POST /api/v1/auth/login": 20
    ]
    #expect(timeouts == expected)
}

@Test func paginationDefaultsToTwentyAndAcceptsUpToOneThousand() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"items":[],"total":0,"page":1,"page_size":20}"#) }
    let client = layerClient(transport)
    _ = try await client.users(page: 1, search: "", status: nil)
    let url = try #require(await transport.requests.first?.url)
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "page_size", value: "20")) == true)
    let wide = try await client.pagination(1, pageSize: 1_000, search: "", status: nil)
    #expect(wide.contains(URLQueryItem(name: "page_size", value: "1000")))
    await #expect(throws: APIError.self) { try await client.pagination(0, search: "", status: nil) }
}
