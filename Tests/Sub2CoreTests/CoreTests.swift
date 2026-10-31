import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let userJSON = #"{"id":7,"email":"admin@example.invalid","username":"管理员","balance":"12.34567890","status":"active","role":"admin","concurrency":5}"#
private let accountJSON = #"{"id":9,"name":"测试账号","platform":"anthropic","type":"oauth","status":"active","schedulable":true,"error_message":null,"concurrency":5}"#
private let dashboardJSON = #"{"today_requests":12,"today_tokens":340,"today_cost":"0.12345678","total_users":8,"total_accounts":3,"error_accounts":1,"rpm":2.5,"tpm":22.5}"#
private let refreshJSON = #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"token_type":"Bearer"}"#
private func ok(_ json: String) -> HTTPResponse { HTTPResponse(statusCode: 200, data: Data("{\"code\":0,\"data\":\(json)}".utf8)) }
private func server(_ host: String = "first.example.invalid") -> ServerProfile { ServerProfile(name: host, baseURL: URL(string: "https://" + host)!, authentication: .password) }
private func token(expired: Bool = false) -> Credential { .tokens(TokenPair(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: Date().addingTimeInterval(expired ? -60 : 3_600))) }

private actor MemoryStore: CredentialStore {
    var values = [UUID: Credential]()
    func load(serverID: UUID) async throws -> Credential? { values[serverID] }
    func save(_ credential: Credential, serverID: UUID) async throws { values[serverID] = credential }
    func remove(serverID: UUID) async throws { values[serverID] = nil }
}
private actor Gate {
    private var isOpen = false
    private var waiters = [CheckedContinuation<Void, Never>]()
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { isOpen = true; let pending = waiters; waiters.removeAll(); for waiter in pending { waiter.resume() } }
}
private actor MockTransport: HTTPTransport {
    typealias Handler = @Sendable (URLRequest) async throws -> HTTPResponse
    typealias StreamHandler = @Sendable (URLRequest) async throws -> HTTPStreamResponse
    private let handler: Handler
    private let streamHandler: StreamHandler?
    private var seen = [URLRequest]()
    init(handler: @escaping Handler, stream: StreamHandler? = nil) { self.handler = handler; streamHandler = stream }
    func data(for request: URLRequest) async throws -> HTTPResponse { seen.append(request); return try await handler(request) }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse {
        seen.append(request)
        guard let streamHandler else { throw APIError.invalidResponse }
        return try await streamHandler(request)
    }
    func requests() -> [URLRequest] { seen }
}

@Test func explicitWireKeysAndExactMoney() throws {
    let data = Data(userJSON.utf8)
    let user = try JSONDecoder().decode(AdminUser.self, from: data)
    #expect(user.balance == Decimal(string: "12.34567890"))
    #expect(user.username == "管理员")
    let stats = try JSONDecoder().decode(DashboardStats.self, from: Data(dashboardJSON.utf8))
    #expect(stats.todayRequests == 12)
    #expect(stats.todayCost == Decimal(string: "0.12345678"))
}

@Test func paginationKeepsServerPageAndComputesMissingPageCount() throws {
    let page = try JSONDecoder().decode(Page<AdminUser>.self, from: Data("{\"items\":[\(userJSON)],\"total\":41,\"page\":2,\"page_size\":20}".utf8))
    #expect(page.page == 2); #expect(page.pages == 3); #expect(page.hasMore)
    let last = Page(items: page.items, total: 41, page: 3, pageSize: 20, pages: 3)
    #expect(!last.hasMore)
}

@Test func publicSettingsInfersLegacyProviderAndReportsConflictWithoutThrowing() throws {
    let settings = try JSONDecoder().decode(PublicSettings.self, from: Data(#"{"turnstile_enabled":false,"tencent_captcha_enabled":true,"aliyun_captcha_enabled":false}"#.utf8))
    #expect(settings.captchaEnabled); #expect(settings.captchaProvider == "tencent")
    let none = try JSONDecoder().decode(PublicSettings.self, from: Data("{}".utf8))
    #expect(!none.captchaEnabled); #expect(none.captchaProvider == nil)
    let conflict = try JSONDecoder().decode(PublicSettings.self, from: Data(#"{"turnstile_enabled":true,"tencent_captcha_enabled":true}"#.utf8))
    #expect(conflict.isCaptchaConflict)
}

@Test func secureStationValidation() throws {
    for raw in ["http://example.invalid", "https://user:password@example.invalid", "https://example.invalid/path", "https://example.invalid/?token=secret", "https://example.invalid/#fragment"] {
        let profile = ServerProfile(name: "invalid", baseURL: URL(string: raw)!, authentication: .adminKey)
        #expect(throws: APIError.self) { try profile.validatedURL() }
    }
    #expect(try server().validatedURL().host == "first.example.invalid")
}

@Test func decimalBalanceIsDeterministicStringAndCodableIdentitySurvives() throws {
    let operation = PendingBalanceOperation(serverID: UUID(), userID: 7, amount: Decimal(string: "12345678901.12345678")!, operation: .add, notes: "手动充值")
    let body = try operation.requestBody()
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(object["balance"] == "12345678901.12345678")
    #expect(object["operation"] == "add")
    let copy = try JSONDecoder().decode(PendingBalanceOperation.self, from: JSONEncoder().encode(operation))
    #expect(copy == operation); #expect(try copy.requestBody() == body)
    #expect(copy.createdAt == operation.createdAt && copy.requestID == operation.id.uuidString.lowercased())
    #expect(throws: APIError.self) { try PendingBalanceOperation(serverID: UUID(), userID: 1, amount: -1, operation: .set).validate() }
    #expect(throws: APIError.self) { try PendingBalanceOperation(serverID: UUID(), userID: 1, amount: Decimal.nan, operation: .set).validate() }
    for raw in ["0.000000001", "1000000000000", "999999999999.999999999"] {
        #expect(throws: APIError.invalidAmount) { try PendingBalanceOperation(serverID: UUID(), userID: 1, amount: Decimal(string: raw)!, operation: .set).validate() }
    }
    #expect(throws: APIError.invalidAmount) { try PendingBalanceOperation(serverID: UUID(), userID: 1, amount: 0, operation: .add).validate() }
    #expect(throws: APIError.invalidAmount) { try PendingBalanceOperation(serverID: UUID(), userID: 1, amount: 0, operation: .subtract).validate() }
    try PendingBalanceOperation(serverID: UUID(), userID: 1, amount: 0, operation: .set).validate()
    try PendingBalanceOperation(serverID: UUID(), userID: 1, amount: Decimal(string: "999999999999.99999999")!, operation: .add).validate()
}

@Test func streamsUTF8AcrossSingleByteChunksAndRequiresExplicitSuccess() throws {
    let raw = ": heartbeat\r\ndata: {\"type\":\"content\",\"text\":\"你好🌍\"}\r\n\r\ndata: {\"type\":\"test_complete\",\"success\":true}\n\n"
    var parser = AccountSSEParser(); var events = [AccountTestEvent]()
    for byte in raw.utf8 { events += try parser.append(Data([byte])) }
    _ = try parser.finish()
    #expect(events.count == 2); #expect(events.first?.content == "你好🌍"); #expect(events.last?.isSuccess == true)
    let incompleteSuccess = AccountTestEvent(type: "test_complete")
    #expect(!incompleteSuccess.isSuccess)
}

@Test func streamsRejectEOFMalformedFramesAndOversizedEvents() throws {
    var eof = AccountSSEParser()
    _ = try eof.append(Data("data: {\"type\":\"content\",\"text\":\"partial\"}\n\n".utf8))
    #expect(throws: APIError.incompleteStream) { try eof.finish() }
    var truncated = AccountSSEParser()
    _ = try truncated.append(Data("data: {\"type\":\"test_complete\",\"success\":true}\n".utf8))
    #expect(throws: APIError.incompleteStream) { try truncated.finish() }
    var malformed = AccountSSEParser()
    #expect(throws: APIError.malformedStream) { try malformed.append(Data("data: not json\n\n".utf8)) }
    var oversized = AccountSSEParser()
    #expect(throws: APIError.malformedStream) { try oversized.append(Data(repeating: 65, count: 1_048_577)) }
    var failed = AccountSSEParser()
    let event = try failed.append(Data("data: {\"type\":\"error\",\"error\":\"upstream failed\"}\n\n".utf8))
    #expect(event.first?.isLegacyConclusion == true); #expect(event.first?.isSuccess == false); _ = try failed.finish()
}

@Test func loginWireProofTOTPAndAdministratorBoundary() async throws {
    let transport = MockTransport { request in
        if request.url?.path.hasSuffix("/login/2fa") == true { return ok("{\"access_token\":\"access\",\"refresh_token\":\"refresh\",\"expires_in\":3600,\"user\":\(userJSON)}") }
        return ok(#"{"requires_2fa":true,"temp_token":"temporary","user_email_masked":"a***@example.invalid"}"#)
    }
    let client = APIClient(server: server(), transport: transport)
    let result = try await client.login(email: "admin@example.invalid", password: "only-test", proof: CaptchaProof(provider: "tencent", tencentTicket: "proof", tencentRandstr: "random"),
                                        deviceName: "iPhone", declaresCaptchaProvider: false)
    guard case .twoFactor(let challenge) = result else { Issue.record("Expected TOTP challenge"); return }
    #expect(challenge.tempToken == "temporary"); #expect(await client.currentCredential() == nil)
    let session = try await client.completeTOTP(tempToken: challenge.tempToken, code: "123456")
    #expect(session.user.role == "admin")
    let requests = await transport.requests()
    let bodyData = try #require(requests[0].httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
    #expect(body["tencent_captcha_ticket"] as? String == "proof"); #expect(body["tencent_captcha_randstr"] as? String == "random")
    #expect(body["captcha_provider"] == nil)
    #expect(requests[1].url?.path == "/api/v1/auth/login/2fa")
    let regular = MockTransport { _ in ok("{\"access_token\":\"secret\",\"user\":\(userJSON.replacingOccurrences(of: "admin\"", with: "user\""))}") }
    let regularClient = APIClient(server: server(), transport: regular)
    await #expect(throws: APIError.administratorRequired) {
        try await regularClient.login(email: "user@example.invalid", password: "test", deviceName: "iPhone", declaresCaptchaProvider: true)
    }
    #expect(await regularClient.currentCredential() == nil)
    #expect(await regular.requests().map { $0.url?.path } == ["/api/v1/auth/login", "/api/v1/auth/logout"])
}

@Test func tokenRefreshIsSingleFlightAcrossConcurrentReads() async throws {
    let started = Gate(); let release = Gate(); let store = MemoryStore(); let profile = server()
    let transport = MockTransport { request in
        if request.url?.path.hasSuffix("/auth/refresh") == true { await started.open(); await release.wait(); return ok(refreshJSON) }
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
        return ok(userJSON)
    }
    let client = APIClient(server: profile, credential: token(expired: true), credentialStore: store, transport: transport)
    let reads = (0..<20).map { _ in Task { try await client.user(id: 7) } }
    await started.wait(); await release.open()
    for read in reads { #expect(try await read.value.id == 7) }
    let requests = await transport.requests()
    #expect(requests.filter { $0.url?.path.hasSuffix("/auth/refresh") == true }.count == 1)
    let saved = await store.values[profile.id]
    let current = await client.currentCredential()
    #expect(saved == current)
}

@Test func cancellingOneRefreshWaiterDoesNotCancelSharedRefresh() async throws {
    let started = Gate(); let release = Gate()
    let transport = MockTransport { request in
        if request.url?.path.hasSuffix("/auth/refresh") == true { await started.open(); await release.wait(); return ok(refreshJSON) }
        return ok(userJSON)
    }
    let client = APIClient(server: server(), credential: token(expired: true), transport: transport)
    let cancelled = Task { try await client.user(id: 7) }
    await started.wait()
    let surviving = Task { try await client.user(id: 7) }
    cancelled.cancel(); await release.open()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(try await surviving.value.id == 7)
    #expect(try await client.user(id: 7).id == 7)
    #expect(await transport.requests().filter { $0.url?.path.hasSuffix("/auth/refresh") == true }.count == 1)
}

@Test func cancelAllFencesLateResponseAndRefreshCommit() async throws {
    let started = Gate(); let release = Gate(); let profile = server(); let store = MemoryStore()
    let transport = MockTransport { _ in await started.open(); await release.wait(); return ok(refreshJSON) }
    let client = APIClient(server: profile, credential: token(expired: true), credentialStore: store, transport: transport)
    let pending = Task { try await client.user(id: 7) }
    await started.wait(); await client.cancelAll(); await release.open()
    await #expect(throws: CancellationError.self) { try await pending.value }
    #expect(await store.values[profile.id] == nil)
    if case .tokens(let pair) = await client.currentCredential() { #expect(pair.accessToken == "old-access") }
    else { Issue.record("Old credential should remain available until explicit logout") }
}

@Test func cancelAllRejectsLateReadEvenWhenTransportIgnoresCancellation() async throws {
    let started = Gate(); let release = Gate()
    let transport = MockTransport { _ in await started.open(); await release.wait(); return ok(userJSON) }
    let client = APIClient(server: server(), credential: .adminKey("fixture"), transport: transport)
    let pending = Task { try await client.user(id: 7) }
    await started.wait(); await client.cancelAll(); await release.open()
    await #expect(throws: CancellationError.self) { try await pending.value }
}

@Test func logoutErasesLocalCredentialsEvenWhenServerIsOffline() async throws {
    let profile = server(); let store = MemoryStore(); let credential = token()
    try await store.save(credential, serverID: profile.id)
    let transport = MockTransport { _ in throw URLError(.notConnectedToInternet) }
    let client = APIClient(server: profile, credential: credential, credentialStore: store, transport: transport)
    await #expect(throws: APIError.self) { try await client.logout() }
    #expect(await client.currentCredential() == nil)
    #expect(await store.values[profile.id] == nil)
    let request = try #require(await transport.requests().first)
    #expect(request.url?.path == "/api/v1/auth/logout")
    // 00 §1.7.5 step 2: the session's own access goes along so the server ends it at once.
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
    #expect(request.httpBody.map { String(decoding: $0, as: UTF8.self) } == #"{"refresh_token":"old-refresh"}"#)
}

@Test func stationIsolationAndBalanceRetriesUseSameIdentityAndBytes() async throws {
    let profile = server()
    let transport = ScriptedTransport(script: [.reply(HTTPResponse(statusCode: 503, data: Data("{}".utf8))), .reply(ok(userJSON))])
    let recorder = SleepRecorder()
    let client = APIClient(server: profile, credential: .adminKey("local-fixture-key"), transport: transport, requestClock: .recording(recorder))
    let operation = PendingBalanceOperation(serverID: profile.id, userID: 7, amount: Decimal(string: "0.00000001")!, operation: .add)
    // A proxy 503 is a transport failure for a keyed write: the same key and bytes go out again after 2 seconds.
    #expect(try await client.updateBalance(stubPersisted(operation), sameAddress: []).value.id == 7)
    let requests = await transport.requests
    #expect(requests.count == 2); #expect(await recorder.durations == [.seconds(2)])
    #expect(requests[0].httpBody == requests[1].httpBody)
    #expect(requests[0].value(forHTTPHeaderField: "Idempotency-Key") == requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
    #expect(requests[0].value(forHTTPHeaderField: "Idempotency-Key") == operation.id.uuidString.lowercased())
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Request-ID") == operation.id.uuidString.lowercased() })
    let wrong = PendingBalanceOperation(serverID: UUID(), userID: 7, amount: 1, operation: .set)
    await #expect(throws: APIError.stationMismatch) { try await client.updateBalance(stubPersisted(wrong), sameAddress: []) }
    #expect(await transport.requests.count == 2)
    #expect(requests.allSatisfy { $0.url?.host == profile.baseURL.host })
}

@Test func expiredMutationRefreshesOnceAndErrorsAreRedacted() async throws {
    let transport = MockTransport { _ in HTTPResponse(statusCode: 401, data: Data(#"{"code":401,"reason":"TOKEN_EXPIRED","message":"secret-token-should-not-appear"}"#.utf8)) }
    let client = APIClient(server: server(), credential: token(), transport: transport)
    do { _ = try await client.setSchedulable(id: 9, enabled: false); Issue.record("Expected failure") }
    catch let error as APIError {
        #expect(error.statusCode == 401); #expect(error.reason == "TOKEN_EXPIRED"); #expect(!error.localizedDescription.contains("secret-token"))
        #expect(error.action == .clearSession)
    }
    // The write is rejected before the handler runs, so it may be resent after one refresh; the refresh itself is rejected here.
    let requests = await transport.requests()
    #expect(requests.count == 2); #expect(requests.last?.url?.path == "/api/v1/auth/refresh")
}

@Test func safeReadRefreshesOnlyOnExpiredTokenAndPaginationEncodesSearch() async throws {
    let transport = MockTransport { request in
        if request.url?.path.hasSuffix("/auth/refresh") == true { return ok(refreshJSON) }
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access" { return HTTPResponse(statusCode: 401, data: Data(#"{"code":401,"reason":"TOKEN_EXPIRED"}"#.utf8)) }
        return ok("{\"items\":[\(accountJSON)],\"total\":42,\"page\":2,\"page_size\":20,\"pages\":3}")
    }
    let client = APIClient(server: server(), credential: token(), transport: transport)
    let page = try await client.managedAccounts(page: 2, query: AccountListQuery(search: " a&b 中文 ", platform: "anthropic"))
    #expect(page.hasMore); #expect(page.page == 2)
    let requests = await transport.requests(); #expect(requests.count == 3)
    let finalURL = try #require(requests.last?.url)
    let query = try #require(URLComponents(url: finalURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.first { $0.name == "search" }?.value == "a&b 中文")
    #expect(query.first { $0.name == "page" }?.value == "2")
}

@Test func initialDashboardOnlyLoadsStatsAndUserUsageUsesRealAggregate() async throws {
    let transport = MockTransport { request in
        let path = request.url?.path ?? ""
        if path.contains("/usage/") { return ok(#"{"total_requests":5,"total_tokens":200,"total_cost":"0.25"}"#) }
        guard path.hasSuffix("/stats") else { throw URLError(.timedOut) }
        return ok(dashboardJSON)
    }
    let client = APIClient(server: server(), credential: .adminKey("fixture"), transport: transport)
    let dashboard = try await client.dashboard()
    #expect(dashboard.stats.todayRequests == 12); #expect(dashboard.trend.isEmpty)
    let initialRequests = await transport.requests()
    #expect(initialRequests.count == 1)
    #expect(initialRequests.first?.url?.path == "/api/v1/admin/dashboard/stats")
    #expect(initialRequests.first?.timeoutInterval == 90)
    let usage = try await client.userMonthUsage(id: 7)
    #expect(usage.totalRequests == 5)
    let request = try #require(await transport.requests().last)
    #expect(request.url?.path == "/api/v1/admin/usage/stats")
    let url = try #require(request.url)
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "user_id" }?.value == "7")
}

@Test func dashboardDetailsLoadExplicitlyWithShortRangeAndOwnTimeouts() async throws {
    let transport = MockTransport { request in
        if request.url?.path.hasSuffix("/trend") == true {
            return ok(#"{"trend":[{"date":"2026-10-15 10:00","requests":12,"total_tokens":340,"cost":"0.12345678"}]}"#)
        }
        return ok(#"{"error_rate":0.125,"qps":{"current":2.5}}"#)
    }
    let site = try #require(ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00"))
    let clock = ServerClock(localNow: { Date(timeIntervalSince1970: 1_792_026_000) })
    let client = APIClient(server: server(), credential: .adminKey("fixture"), transport: transport, serverTimeZone: site, serverClock: clock)
    let trend = try await client.dashboardTrend()
    #expect(trend.points.count == 1); #expect(trend.points.first?.requests == 12)
    let overview = try await client.opsOverview(timeRange: "5m")
    #expect(overview.errorRate == 0.125); #expect(overview.qps?.current == 2.5)
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let trendRequest = try #require(requests.first)
    #expect(trendRequest.timeoutInterval == 45)
    let trendURL = try #require(trendRequest.url)
    let query = try #require(URLComponents(url: trendURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.first { $0.name == "granularity" }?.value == "hour")
    #expect(query.first { $0.name == "timezone" }?.value == "Asia/Shanghai")
    let start = try #require(query.first { $0.name == "start_date" }?.value)
    let end = try #require(query.first { $0.name == "end_date" }?.value)
    let formatter = DateFormatter()
    formatter.calendar = site.calendar; formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = site.timeZone; formatter.dateFormat = "yyyy-MM-dd"
    let startDate = try #require(formatter.date(from: start)); let endDate = try #require(formatter.date(from: end))
    #expect(site.calendar.dateComponents([.day], from: startDate, to: endDate).day == 1)
    #expect(end == site.dayString(clock.now()))
    let opsRequest = try #require(requests.last)
    #expect(opsRequest.timeoutInterval == 45)
    #expect(opsRequest.url?.path == "/api/v1/admin/ops/dashboard/overview")
    let opsURL = try #require(opsRequest.url)
    // X08: the five minutes go out as start_time / end_time in UTC, never as time_range.
    let opsQuery = try #require(URLComponents(url: opsURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(opsQuery.first { $0.name == "time_range" } == nil)
    let opsStart = try #require(opsQuery.first { $0.name == "start_time" }?.value)
    let opsEnd = try #require(opsQuery.first { $0.name == "end_time" }?.value)
    #expect(opsStart.hasSuffix("Z") && opsEnd.hasSuffix("Z"))
    let opsStartDate = try #require(ServerTime.parseTimestamp(opsStart)), opsEndDate = try #require(ServerTime.parseTimestamp(opsEnd))
    #expect(opsEndDate.timeIntervalSince(opsStartDate) == 300)
}

@Test func dashboardDetailsSurfaceTheirOwnErrorsWithoutDiscardingStats() async throws {
    let transport = MockTransport { request in
        if request.url?.path.hasSuffix("/trend") == true {
            return HTTPResponse(statusCode: 503, data: Data(#"{"code":503,"reason":"UNAVAILABLE"}"#.utf8))
        }
        if request.url?.path.contains("/ops/") == true {
            return HTTPResponse(statusCode: 403, data: Data(#"{"code":403,"reason":"FORBIDDEN"}"#.utf8))
        }
        return ok(dashboardJSON)
    }
    let client = APIClient(server: server(), credential: .adminKey("fixture"), transport: transport)
    let dashboard = try await client.dashboard()
    do { _ = try await client.dashboardTrend(); Issue.record("Expected trend failure") }
    catch let error as APIError { #expect(error.statusCode == 503) }
    do { _ = try await client.opsOverview(timeRange: "5m"); Issue.record("Expected ops overview failure") }
    catch let error as APIError { #expect(error.kind == .permission) }
    #expect(dashboard.stats.todayRequests == 12)
    #expect(try await client.dashboard().stats.todayRequests == 12)
}

@Test func dashboardTimeoutSurvivesExpiredTokenRefreshRetry() async throws {
    let transport = MockTransport { request in
        if request.url?.path.hasSuffix("/auth/refresh") == true { return ok(refreshJSON) }
        #expect(request.timeoutInterval == 90)
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access" {
            return HTTPResponse(statusCode: 401, data: Data(#"{"code":401,"reason":"TOKEN_EXPIRED"}"#.utf8))
        }
        return ok(dashboardJSON)
    }
    let client = APIClient(server: server(), credential: token(), transport: transport)
    #expect(try await client.dashboard().stats.todayRequests == 12)
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests.filter { $0.url?.path.hasSuffix("/stats") == true }.count == 2)
}

@Test(arguments: ["stats", "trend", "opsOverview"])
func dashboardReadsRejectLateResultsAfterStationCancellation(section: String) async throws {
    let started = Gate(); let release = Gate()
    let transport = MockTransport { request in
        await started.open(); await release.wait()
        if request.url?.path.hasSuffix("/trend") == true { return ok(#"{"trend":[]}"#) }
        if request.url?.path.contains("/ops/") == true { return ok(#"{"qps":{"current":1}}"#) }
        return ok(dashboardJSON)
    }
    let client = APIClient(server: server(), credential: .adminKey("fixture"), transport: transport)
    let pending = Task {
        switch section {
        case "trend": _ = try await client.dashboardTrend()
        case "opsOverview": _ = try await client.opsOverview(timeRange: "5m")
        default: _ = try await client.dashboard()
        }
    }
    await started.wait(); await client.cancelAll(); await release.open()
    await #expect(throws: CancellationError.self) { try await pending.value }
}

@Test func POSTStreamIsIncrementalAndEOFIsFailure() async throws {
    let transport = MockTransport(handler: { _ in throw APIError.invalidResponse }, stream: { request in
        #expect(request.httpMethod == "POST"); #expect(request.url?.path == "/api/v1/admin/accounts/9/test")
        let bytes = AsyncThrowingStream<Data, any Error> { continuation in
            continuation.yield(Data("data: {\"type\":\"content\",\"text\":\"partial\"}\n\n".utf8))
            continuation.finish()
        }
        return HTTPStreamResponse(statusCode: 200, headers: ["content-type": "text/event-stream; charset=utf-8"], bytes: bytes)
    })
    let client = APIClient(server: server(), credential: .adminKey("fixture"), transport: transport)
    let stream = try await client.testAccount(id: 9, model: "fixture-model", expectsTestResult: false)
    var count = 0
    do { for try await event in stream { #expect(event.content == "partial"); count += 1 }; Issue.record("Expected explicit EOF failure") }
    catch let error as APIError { #expect(error == .incompleteStream) }
    #expect(count == 1)
}

@Test func errorsDistinguishCaptchaSessionComplianceAndStepUp() {
    #expect(APIError.server(status: 400, reason: "TURNSTILE_VERIFICATION_FAILED").kind == .captcha)
    #expect(APIError.server(status: 401, reason: "SESSION_BINDING_MISMATCH").kind == .sessionBinding)
    #expect(APIError.server(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED").kind == .compliance)
    #expect(APIError.server(status: 423, reason: "TOTP_STEP_UP_REQUIRED").kind == .compliance)
    #expect(APIError.server(status: 403, reason: "STEP_UP_REQUIRED").kind == .stepUp)
    #expect(APIError.server(status: 403, reason: "FORBIDDEN").kind == .permission)
}

@Test func captchaBridgeAcceptsExactProviderProofsAndCancellation() throws {
    let nonce = UUID()
    for provider in ["turnstile", "aliyun"] {
        let data = Data("{\"version\":1,\"nonce\":\"\(nonce.uuidString)\",\"provider\":\"\(provider)\",\"proof\":{\"turnstile_token\":\"fixture-proof\"}}".utf8)
        guard case .proof(let proof) = try CaptchaBridgeValidator.parse(data, nonce: nonce, provider: provider) else { Issue.record("Expected proof"); continue }
        #expect(proof.turnstileToken == "fixture-proof"); #expect(proof.tencentTicket == nil); #expect(proof.provider == provider)
        #expect(proof.aliyunParam == (provider == "aliyun" ? "fixture-proof" : nil))
    }
    let tencent = Data("{\"version\":1,\"nonce\":\"\(nonce.uuidString)\",\"provider\":\"tencent\",\"proof\":{\"tencent_captcha_ticket\":\"ticket\",\"tencent_captcha_randstr\":\"random\"}}".utf8)
    guard case .proof(let proof) = try CaptchaBridgeValidator.parse(tencent, nonce: nonce, provider: "tencent") else { Issue.record("Expected Tencent proof"); return }
    #expect(proof.tencentTicket == "ticket"); #expect(proof.tencentRandstr == "random"); #expect(proof.provider == "tencent")
    let cancel = Data("{\"version\":1,\"nonce\":\"\(nonce.uuidString)\",\"cancelled\":true}".utf8)
    guard case .cancelled = try CaptchaBridgeValidator.parse(cancel, nonce: nonce, provider: "turnstile") else { Issue.record("Expected cancellation"); return }
}

@Test func captchaBridgeRejectsBooleanVersionsNonceProviderAndExtraFields() throws {
    let nonce = UUID()
    let envelope: [String: Any] = ["version": 1, "nonce": nonce.uuidString, "provider": "turnstile", "proof": ["turnstile_token": "fixture"]]
    var wrongVersion = envelope; wrongVersion["version"] = true
    var wrongNonce = envelope; wrongNonce["nonce"] = UUID().uuidString
    var wrongProvider = envelope; wrongProvider["provider"] = "tencent"
    var extra = envelope; extra["access_token"] = "MUST_NEVER_BE_ACCEPTED"
    var emptyProof = envelope; emptyProof["proof"] = ["turnstile_token": " \n\t "]
    var wrongProof = envelope; wrongProof["proof"] = ["turnstile_token": "fixture", "tencent_captcha_ticket": "extra"]
    var oversized = envelope; oversized["proof"] = ["turnstile_token": String(repeating: "x", count: 16_385)]
    let badCancel: [String: Any] = ["version": 1, "nonce": nonce.uuidString, "cancelled": 1]
    let falseCancel: [String: Any] = ["version": 1, "nonce": nonce.uuidString, "cancelled": false]
    for object in [wrongVersion, wrongNonce, wrongProvider, extra, emptyProof, wrongProof, oversized, badCancel, falseCancel] {
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: APIError.self) { try CaptchaBridgeValidator.parse(data, nonce: nonce, provider: "turnstile") }
    }
}
