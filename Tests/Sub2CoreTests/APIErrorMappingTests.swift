import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// Private stubs keep names clear of the shared request test support added later.
private actor ErrorMappingTransport: HTTPTransport {
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

private let mappingUserJSON = #"{"id":7,"email":"admin@example.invalid","username":"管理员","balance":"1","status":"active","role":"admin","concurrency":5}"#
private func mappingSuccess(_ json: String) -> HTTPResponse { HTTPResponse(statusCode: 200, data: Data("{\"code\":0,\"data\":\(json)}".utf8)) }
private func mappingReply(_ status: Int, _ body: String, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: headers, data: Data(body.utf8))
}
private func mappingServer() -> ServerProfile { ServerProfile(name: "mapping", baseURL: URL(string: "https://mapping.example.invalid")!, authentication: .password) }
private func mappingTokens(expired: Bool = false) -> Credential {
    .tokens(TokenPair(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: Date().addingTimeInterval(expired ? -60 : 3_600)))
}
private func thrownError(_ operation: () async throws -> Void) async -> APIError? {
    do { try await operation(); return nil } catch { return error as? APIError }
}

@Test func fromResponseCarriesRequestIDRetryAfterAndMetadata() {
    let limited = APIError.from(mappingReply(429, #"{"code":"RATE_LIMITED","reason":"RATE_LIMITED","retry_after":12,"error":"rate limit exceeded","message":"x"}"#,
                                             headers: ["X-Request-ID": "req-fixture-1", "Retry-After": "7"]))
    #expect(limited.kind == .rateLimited); #expect(limited.reason == "RATE_LIMITED"); #expect(limited.retryAfter == 7)
    #expect(limited.requestID == "req-fixture-1"); #expect(limited.statusCode == 429)
    #expect(limited.localizedDescription == "请求过于频繁，请 7 秒后再试")
    let pending = APIError.from(mappingReply(409, #"{"code":409,"reason":"IDEMPOTENCY_IN_PROGRESS","metadata":{"retry_after":"12"}}"#))
    #expect(pending.kind == .idempotency); #expect(pending.metadata["retry_after"] == "12"); #expect(pending.retryAfter == 12)
}

@Test func successStatusWithNonZeroCodeIsTreatedAs500() {
    let failed = APIError.from(mappingReply(200, #"{"code":"SOMETHING","reason":"SOMETHING"}"#))
    #expect(failed.statusCode == 500); #expect(failed.kind == .temporary); #expect(failed.reason == "SOMETHING")
    #expect(APIError.from(mappingReply(200, #"{"data":{}}"#)) == .invalidResponse)
    #expect(APIError.from(mappingReply(200, "not json")) == .invalidResponse)
}

@Test func nonJSON404IsUnsupportedButJSON404IsNotFound() {
    let gateway = APIError.from(mappingReply(404, "404 page not found", headers: ["content-type": "text/plain"]))
    #expect(gateway.kind == .unsupported); #expect(gateway.action == .hideFeature); #expect(gateway.reason == nil)
    #expect(gateway.localizedDescription == "站点版本较旧，暂不支持此功能")
    #expect(APIError.from(mappingReply(404, #"{"code":404,"reason":"ACCOUNT_NOT_FOUND"}"#)).kind == .notFound)
    #expect(APIError.from(mappingReply(404, #"{"code":404,"message":"x"}"#)).kind == .notFound)
}

@Test func htmlBadGatewayIsTemporaryWithoutReason() {
    let error = APIError.from(mappingReply(502, "<html><body><h1>502 Bad Gateway</h1></body></html>"))
    #expect(error.kind == .temporary); #expect(error.reason == nil); #expect(error.localizedDescription == "站点暂时不可用")
    #expect(!error.localizedDescription.contains("<"))
}

@Test func serverMessageIsNeverEchoed() {
    let secret = #""message":"upstream https://upstream.example.invalid failed with sk-fixture-secret <b>boom</b>""#
    for (status, reason) in [(403, "FORBIDDEN"), (500, "INTERNAL"), (400, "NEW_REASON"), (400, "")] {
        let error = APIError.from(mappingReply(status, "{\"code\":\(status),\"reason\":\"\(reason)\",\(secret)}"))
        let shown = [error.localizedDescription] + error.diagnostics.map(\.value)
        for fragment in ["upstream.example.invalid", "sk-fixture-secret", "<b>"] {
            #expect(!shown.contains { $0.contains(fragment) }, "\(status) \(fragment)")
        }
    }
}

@Test func lockedIsComplianceAndNeverStepUp() {
    let locked = APIError.from(mappingReply(423, #"{"code":"ADMIN_COMPLIANCE_ACK_REQUIRED","reason":"ADMIN_COMPLIANCE_ACK_REQUIRED","metadata":{"version":"1","document_url_zh":"https://docs.example.invalid/zh"}}"#))
    #expect(locked.kind == .compliance); #expect(locked.action == .complianceFlow)
    #expect(locked.metadata["document_url_zh"] == "https://docs.example.invalid/zh")
    let otherLocked = APIError.from(mappingReply(423, #"{"code":"TOTP_STEP_UP_REQUIRED","reason":"TOTP_STEP_UP_REQUIRED"}"#))
    #expect(otherLocked.kind == .compliance); #expect(otherLocked.action != .stepUp)
    let stepUp = APIError.from(mappingReply(403, #"{"code":"STEP_UP_REQUIRED","reason":"STEP_UP_REQUIRED","message":"x"}"#))
    #expect(stepUp.kind == .stepUp); #expect(stepUp.action == .stepUp)
    #expect(APIError.from(mappingReply(403, #"{"code":"ACCESS_TOKEN_READ_ONLY","reason":"ACCESS_TOKEN_READ_ONLY"}"#)).kind == .readOnly)
    let setup = APIError.from(mappingReply(403, #"{"code":"STEP_UP_TOTP_NOT_ENABLED","reason":"STEP_UP_TOTP_NOT_ENABLED"}"#))
    #expect(setup.kind == .stepUp); #expect(setup.action == .explainStepUpSetup)
}

@Test func notModifiedIsNotDecoded() {
    let error = APIError.from(mappingReply(304, #"{"code":"X","reason":"X"}"#, headers: ["x-request-id": "req-304"]))
    #expect(error.statusCode == 304); #expect(error.kind == .response); #expect(error.reason == nil)
}

@Test func diagnosticsShowDashForMissingValues() {
    #expect(APIError.invalidResponse.diagnostics.map(\.value) == ["—", "—", "—"])
    let error = APIError.from(mappingReply(503, #"{"code":503,"reason":"SERVICE_UNAVAILABLE"}"#, headers: ["x-request-id": "req-fixture-2"]))
    #expect(error.diagnostics.map(\.label) == ["HTTP 状态", "错误码", "请求 ID"])
    #expect(error.diagnostics.map(\.value) == ["503", "SERVICE_UNAVAILABLE", "req-fixture-2"])
}

@Test func legacyServerFactoryKeepsWorking() {
    let missing = APIError.server(status: 404, reason: nil)
    #expect(missing.kind == .notFound); #expect(missing.statusCode == 404)
    let conflict = APIError.server(status: 503, reason: "CAPTCHA_PROVIDER_CONFLICT")
    #expect(conflict.kind == .captcha); #expect(conflict.localizedDescription == "站点同时开启了多个验证码服务，请在 Web 后台修正")
    #expect(APIError.server(status: 404, reason: "OPS_DISABLED").kind == .featureDisabled)
    #expect(APIError.stationMismatch == .stationMismatch); #expect(APIError.incompleteStream == .incompleteStream)
    #expect(APIError.administratorRequired == .administratorRequired)
    #expect(APIError.stationMismatch.category == nil); #expect(APIError.stationMismatch.metadata.isEmpty)
}

@Test func localErrorsCarrySessionActionAndConnectionText() {
    #expect(APIError.authenticationRequired.category == .sessionExpired)
    #expect(APIError.authenticationRequired.action == .clearSession)
    #expect(APIError.authenticationRequired.localizedDescription == "登录已失效，请重新登录")
    #expect(APIError.transport(URLError(.notConnectedToInternet)).localizedDescription == "无法连接站点")
    #expect(APIError.transport(URLError(.timedOut)).kind == .transport)
}

@Test func middlewareStringCodeTokenExpiredRefreshesRead() async throws {
    let transport = ErrorMappingTransport { request in
        if request.url?.path.hasSuffix("/auth/refresh") == true {
            return mappingSuccess(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#)
        }
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access" {
            return mappingReply(401, #"{"code":"TOKEN_EXPIRED","reason":"TOKEN_EXPIRED","message":"Token has expired"}"#)
        }
        return mappingSuccess(mappingUserJSON)
    }
    let client = APIClient(server: mappingServer(), credential: mappingTokens(), transport: transport)
    #expect(try await client.user(id: 7).id == 7)
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url == requests[2].url)
    #expect(requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
}

@Test func middlewareStepUpKeepsReasonAndIsNotReplayed() async throws {
    let transport = ErrorMappingTransport { _ in mappingReply(403, #"{"code":"STEP_UP_REQUIRED","reason":"STEP_UP_REQUIRED","message":"step up"}"#) }
    let client = APIClient(server: mappingServer(), credential: mappingTokens(), transport: transport)
    let error = try #require(await thrownError { _ = try await client.setSchedulable(id: 9, enabled: false) })
    #expect(error.reason == "STEP_UP_REQUIRED"); #expect(error.kind == .stepUp); #expect(error.action == .stepUp)
    #expect(await transport.requests().count == 1)
}

@Test func clientErrorsExposeResponseHeaders() async throws {
    let transport = ErrorMappingTransport { request in
        if request.url?.path.hasSuffix("/users/7") == true {
            return mappingReply(503, #"{"code":503,"reason":"SERVICE_UNAVAILABLE"}"#, headers: ["x-request-id": "req-fixture-3"])
        }
        return mappingReply(429, #"{"code":"RATE_LIMITED","reason":"RATE_LIMITED","message":"slow"}"#, headers: ["retry-after": "9"])
    }
    let client = APIClient(server: mappingServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate)
    let unavailable = try #require(await thrownError { _ = try await client.user(id: 7) })
    #expect(unavailable.requestID == "req-fixture-3"); #expect(unavailable.kind == .temporary)
    #expect(await transport.requests().count == 3) // a transient read is retried twice (00 §2.4)
    let limited = try #require(await thrownError { _ = try await client.user(id: 8) })
    #expect(limited.retryAfter == 9); #expect(limited.localizedDescription == "请求过于频繁，请 9 秒后再试")
}

@Test func emptyReplyWithNonZeroCodeFails() async throws {
    let rejected = ErrorMappingTransport { _ in mappingReply(200, #"{"code":"X","reason":"X"}"#) }
    let failing = APIClient(server: mappingServer(), credential: .adminKey("fixture"), transport: rejected)
    let error = try #require(await thrownError { try await failing.refreshAccount(id: 9) })
    #expect(error.statusCode == 500); #expect(error.reason == "X")
    let accepted = ErrorMappingTransport { _ in mappingReply(200, #"{"code":0}"#) }
    try await APIClient(server: mappingServer(), credential: .adminKey("fixture"), transport: accepted).refreshAccount(id: 9)
}

@Test func loginUsesLoginContextTexts() async throws {
    let cases: [(HTTPResponse, String, ReasonCatalog.Action)] = [
        (mappingReply(401, #"{"code":401,"reason":"INVALID_CREDENTIALS","message":"x"}"#), "邮箱或密码错误", .noRetry),
        (mappingReply(403, #"{"code":403,"reason":"USER_NOT_ACTIVE"}"#), "该账号已被禁用", .clearSession),
        (mappingReply(429, #"{"code":"RATE_LIMITED","reason":"RATE_LIMITED","retry_after":12}"#, headers: ["Retry-After": "12"]), "登录过于频繁，请 12 秒后再试", .waitRetryAfter)
    ]
    for (response, message, action) in cases {
        let transport = ErrorMappingTransport { _ in response }
        let client = APIClient(server: mappingServer(), transport: transport)
        let error = try #require(await thrownError { _ = try await client.login(email: "admin@example.invalid", password: "only-test") })
        #expect(error.localizedDescription == message); #expect(error.action == action)
        #expect(await transport.requests().count == 1)
    }
}

@Test func twoFactorUsesLoginTexts() async throws {
    let tooMany = ErrorMappingTransport { _ in mappingReply(429, #"{"code":429,"reason":"TOTP_TOO_MANY_ATTEMPTS"}"#) }
    let first = try #require(await thrownError { _ = try await APIClient(server: mappingServer(), transport: tooMany).completeTOTP(tempToken: "temporary", code: "123456") })
    #expect(first.kind == .twoFactor); #expect(first.localizedDescription == "尝试次数过多，请 15 分钟后再试")
    let expired = ErrorMappingTransport { _ in mappingReply(400, #"{"code":400,"reason":"TOTP_LOGIN_SESSION_EXPIRED"}"#) }
    let second = try #require(await thrownError { _ = try await APIClient(server: mappingServer(), transport: expired).completeTOTP(tempToken: "temporary", code: "123456") })
    #expect(second.localizedDescription == "验证超时，请重新登录")
}

@Test func refreshFailureUsesRefreshContext() async throws {
    let outcomes: [(String, ReasonCatalog.Category, String)] = [
        (#"{"code":401,"reason":"REFRESH_TOKEN_REUSED"}"#, .sessionExpired, "登录已失效，请重新登录"),
        (#"{"code":403,"reason":"USER_NOT_ACTIVE"}"#, .sessionExpired, "该账号已被禁用")
    ]
    for (body, category, message) in outcomes {
        let status = body.contains("403") ? 403 : 401
        let transport = ErrorMappingTransport { request in
            guard request.url?.path.hasSuffix("/auth/refresh") == true else { return mappingSuccess(mappingUserJSON) }
            return mappingReply(status, body)
        }
        let client = APIClient(server: mappingServer(), credential: mappingTokens(expired: true), transport: transport)
        let error = try #require(await thrownError { _ = try await client.user(id: 7) })
        #expect(error.action == .clearSession); #expect(error.category == category); #expect(error.localizedDescription == message)
    }
}

@Test func streamErrorBodyUsesEnvelope() async throws {
    let body = #"{"code":"ADMIN_COMPLIANCE_ACK_REQUIRED","reason":"ADMIN_COMPLIANCE_ACK_REQUIRED","metadata":{"version":"1"}}"#
    let transport = ErrorMappingTransport(handler: { _ in throw APIError.invalidResponse }, stream: { _ in
        let bytes = AsyncThrowingStream<Data, any Error> { continuation in continuation.yield(Data(body.utf8)); continuation.finish() }
        return HTTPStreamResponse(statusCode: 423, headers: ["x-request-id": "req-fixture-4"], bytes: bytes)
    })
    let client = APIClient(server: mappingServer(), credential: .adminKey("fixture"), transport: transport)
    let error = try #require(await thrownError { _ = try await client.testAccount(id: 9, model: nil) })
    #expect(error.kind == .compliance); #expect(error.requestID == "req-fixture-4"); #expect(error.metadata["version"] == "1")
}

@Test func nonJSON404FromReadIsUnsupported() async throws {
    let transport = ErrorMappingTransport { _ in mappingReply(404, "404 page not found", headers: ["content-type": "text/plain"]) }
    let client = APIClient(server: mappingServer(), credential: .adminKey("fixture"), transport: transport)
    let error = try #require(await thrownError { _ = try await client.user(id: 7) })
    #expect(error.kind == .unsupported)
    #expect(await transport.requests().count == 1)
}

@Test func successBodiesKeepModelErrorsAndContractChecks() async throws {
    // A captcha conflict is reported to the login page instead of failing the decode (00 §9.4).
    let conflict = ErrorMappingTransport { _ in mappingSuccess(#"{"turnstile_enabled":true,"tencent_captcha_enabled":true}"#) }
    #expect(try await APIClient(server: mappingServer(), transport: conflict).publicSettings().isCaptchaConflict)
    let counters = ErrorMappingTransport { _ in mappingSuccess(#"{"items":[],"total":-1,"page":1,"page_size":20}"#) }
    let page = await thrownError { _ = try await APIClient(server: mappingServer(), credential: .adminKey("fixture"), transport: counters).users(page: 1, search: "", status: nil) }
    #expect(page == .invalidResponse)
    for body in [#"{"code":0}"#, #"{"code":0,"data":{"id":"x"}}"#, #"{"data":{}}"#, "<html></html>"] {
        let transport = ErrorMappingTransport { _ in mappingReply(200, body) }
        let error = await thrownError { _ = try await APIClient(server: mappingServer(), credential: .adminKey("fixture"), transport: transport).user(id: 7) }
        #expect(error == .invalidResponse, "\(body)")
    }
}
