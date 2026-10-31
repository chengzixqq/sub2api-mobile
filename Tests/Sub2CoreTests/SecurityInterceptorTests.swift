import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

/// Records what reached the session owner and answers with a fixed outcome, optionally after `release` opens.
private actor InterceptorProbe {
    struct Call: Sendable, Equatable {
        let status: Int?
        let reason: String?
        let isRead: Bool
    }
    private(set) var calls = [Call]()
    private let outcome: SecurityPromptOutcome
    private let release: OpenGate?
    private let onCall: (@Sendable () async -> Void)?
    init(_ outcome: SecurityPromptOutcome, release: OpenGate? = nil, onCall: (@Sendable () async -> Void)? = nil) {
        self.outcome = outcome; self.release = release; self.onCall = onCall
    }
    func intercept(_ error: APIError, isRead: Bool) async -> SecurityPromptOutcome {
        calls.append(Call(status: error.statusCode, reason: error.reason, isRead: isRead))
        await onCall?()
        await release?.wait()
        return outcome
    }
    nonisolated var interceptor: SecurityInterceptor { { [self] error, isRead in await intercept(error, isRead: isRead) } }
}

private func guardedClient(_ transport: ScriptedTransport, _ probe: InterceptorProbe?, credential: Credential = .adminKey("fixture"),
                           clock: RequestClock = .immediate) -> APIClient {
    APIClient(server: stubServer(), credential: credential, deviceID: stubDeviceID, transport: transport, requestClock: clock,
              securityInterceptor: probe?.interceptor)
}
private let complianceRefusal = errorReply(423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED")
private let stepUpRefusal = errorReply(403, reason: "STEP_UP_REQUIRED")

@Test func stepUpPostsCodeAndReturnsExpiry() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"verified":true,"expires_in":900}"#)), .reply(okReply(#"{"verified":true}"#))])
    let client = guardedClient(transport, nil, credential: stubTokens())
    #expect(try await client.stepUp(code: "123456") == StepUpGrant(verified: true, expiresIn: 900))
    #expect(try await client.stepUp(code: "654321").expiresIn == nil)
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST"); #expect(request.url?.path == "/api/v1/user/totp/step-up")
    #expect(request.httpBody == Data(#"{"code":"123456"}"#.utf8))
    #expect(sentHeader(request, "Authorization") == "Bearer old-access"); #expect(sentHeader(request, "x-api-key") == nil)
    #expect(sentHeader(request, "Idempotency-Key") == nil)
}

@Test func stepUpRejectsMalformedCodeWithoutSending() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"verified":true}"#))])
    let client = guardedClient(transport, nil, credential: stubTokens())
    for code in ["12345", "12a456", "１２３４５６", "1234567"] {
        #expect(await thrownAPIError { _ = try await client.stepUp(code: code) }?.kind == .twoFactor)
    }
    #expect(await transport.requests.isEmpty)
    let refused = ScriptedTransport(script: [.reply(okReply(#"{"verified":false}"#))])
    #expect(await thrownAPIError { _ = try await guardedClient(refused, nil, credential: stubTokens()).stepUp(code: "123456") }?.kind == .twoFactor)
}

@Test func complianceAcceptanceUsesExactPathAndBodyAndIsSentOnce() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"required":false,"version":"2026-06"}"#))])
    let client = guardedClient(transport, nil, credential: stubTokens())
    let status = try await client.acceptCompliance(phrase: "我已阅读并同意")
    #expect(status.required == false); #expect(status.version == "2026-06")
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST"); #expect(request.url?.path == "/api/v1/admin/compliance/accept")
    #expect(request.httpBody == Data(#"{"language":"zh","phrase":"我已阅读并同意"}"#.utf8))
    #expect(sentHeader(request, "Idempotency-Key") == nil); #expect(request.timeoutInterval == 30)
    let unavailable = ScriptedTransport(script: [.reply(errorReply(503))])
    #expect(await thrownAPIError { _ = try await guardedClient(unavailable, nil).acceptCompliance(phrase: "x") }?.statusCode == 503)
    #expect(await unavailable.requests.count == 1)
}

@Test func readBlockedByComplianceIsResentOnceAfterPrompt() async throws {
    let transport = ScriptedTransport(script: [.reply(complianceRefusal), .reply(okReply(stubUserJSON))])
    let probe = InterceptorProbe(.passed)
    let user = try await guardedClient(transport, probe).user(id: 7)
    #expect(user.id == 7)
    #expect(await probe.calls == [.init(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED", isRead: true)])
    let requests = await transport.requests
    #expect(requests.count == 2); #expect(requests[0].url == requests[1].url); #expect(requests[1].httpMethod == "GET")
    #expect(sentHeader(requests[1], "x-api-key") == "fixture")
}

@Test func readStillBlockedAfterPromptThrowsWithoutLoop() async throws {
    let transport = ScriptedTransport(script: [.reply(complianceRefusal)])
    let probe = InterceptorProbe(.passed)
    let error = try #require(await thrownAPIError { _ = try await guardedClient(transport, probe).user(id: 7) })
    #expect(error.kind == .compliance); #expect(error.securityOutcome == nil)
    #expect(await transport.requests.count == 2); #expect(await probe.calls.count == 1)
}

@Test func cancelledPromptRethrowsOriginalErrorWithOutcome() async throws {
    for refusal in [complianceRefusal, HTTPResponse(statusCode: 423, data: Data("<html>locked</html>".utf8))] {
        let transport = ScriptedTransport(script: [.reply(refusal)])
        let probe = InterceptorProbe(.cancelled)
        let error = try #require(await thrownAPIError { _ = try await guardedClient(transport, probe).user(id: 7) })
        #expect(error.statusCode == 423); #expect(error.securityOutcome == .cancelled)
        #expect(error.localizedDescription == "需要先完成管理员合规确认")
        #expect(await transport.requests.count == 1); #expect(await probe.calls.count == 1)
    }
}

@Test func writeRejectedByStepUpIsNeverAutoResent() async throws {
    let transport = ScriptedTransport(script: [.reply(stepUpRefusal), .reply(okReply(stubUserJSON))])
    let probe = InterceptorProbe(.passed)
    let error = try #require(await thrownAPIError { _ = try await guardedClient(transport, probe).setUserStatus(id: 7, status: "disabled") })
    #expect(error.securityOutcome == .passed); #expect(error.statusCode == 403); #expect(error.reason == "STEP_UP_REQUIRED")
    #expect(error.localizedDescription == "二次验证已通过，请重新确认后发送")
    #expect(await transport.requests.count == 1)
    #expect(await probe.calls == [.init(status: 403, reason: "STEP_UP_REQUIRED", isRead: false)])
}

@Test(arguments: [true, false])
func userWriteKeepsKeyAndBytesAcrossStepUpReconfirmation(keyed: Bool) async throws {
    let transport = ScriptedTransport(script: [.reply(stepUpRefusal), .reply(okReply(stubUserJSON))])
    let probe = InterceptorProbe(.passed)
    let client = guardedClient(transport, probe)
    let operation = try PendingUserCreateOperation(serverID: client.server.id, identity: await client.userWriteIdentity(),
                                                   request: UserCreateRequest(email: "a@example.invalid", password: "abcdef", role: .admin),
                                                   sendsIdempotencyKey: keyed)
    let first = try #require(await thrownAPIError { _ = try await client.createUser(operation) })
    #expect(first.securityOutcome == .passed); #expect(first.statusCode == 403)
    #expect(try await client.createUser(operation).value.id == 7)
    let requests = await transport.requests
    #expect(requests.count == 2); #expect(requests[0].httpBody == requests[1].httpBody); #expect(requests[0].httpBody == operation.body)
    for name in ["Idempotency-Key", "X-Request-ID"] { #expect(sentHeader(requests[0], name) == sentHeader(requests[1], name)) }
    #expect(sentHeader(requests[0], "X-Request-ID") == operation.key)
    #expect(sentHeader(requests[0], "Idempotency-Key") == (keyed ? operation.key : nil))
    #expect(await probe.calls == [.init(status: 403, reason: "STEP_UP_REQUIRED", isRead: false)])
}

@Test func readOnlyTokenOnUsageBatchIsReportedButNotResent() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(403, reason: "ACCESS_TOKEN_READ_ONLY")), .reply(okReply("{}"))])
    let probe = InterceptorProbe(.blocked)
    let client = guardedClient(transport, probe, credential: .accessToken("sat_fixture"))
    let error = try #require(await thrownAPIError {
        let _: EmptyReply = try await client.request("admin/dashboard/users-usage", method: "POST", body: Data(#"{"user_ids":[7]}"#.utf8),
                                                     requestClass: .readBatch)
    })
    #expect(error.kind == .readOnly); #expect(error.securityOutcome == .blocked)
    #expect(error.localizedDescription == "当前管理访问令牌只读，不能执行此操作")
    #expect(await transport.requests.count == 1)
    #expect(await probe.calls == [.init(status: 403, reason: "ACCESS_TOKEN_READ_ONLY", isRead: true)])
}

// A hook that never asks would leave these waiting: the limit turns that into a failure.
@Test(.timeLimit(.minutes(1))) func siteSwitchDuringPromptCancelsRetry() async throws {
    let release = OpenGate(), asked = OpenGate()
    let probe = InterceptorProbe(.passed, release: release, onCall: { await asked.open() })
    let transport = ScriptedTransport(script: [.reply(complianceRefusal), .reply(okReply(stubUserJSON))])
    let client = guardedClient(transport, probe)
    let pending = Task { try await client.user(id: 7) }
    await asked.wait()
    await client.cancelAll()
    await release.open()
    do { _ = try await pending.value; Issue.record("切站后不应重发") } catch { #expect(error is CancellationError) }
    #expect(await transport.requests.count == 1)
}

@Test(.timeLimit(.minutes(1))) func writeRefusedWhileSessionEndsCountsAsCancelled() async throws {
    let release = OpenGate(), asked = OpenGate()
    let probe = InterceptorProbe(.passed, release: release, onCall: { await asked.open() })
    let transport = ScriptedTransport(script: [.reply(stepUpRefusal)])
    let client = guardedClient(transport, probe)
    let pending = Task { try await client.setUserStatus(id: 7, status: "disabled") }
    await asked.wait()
    await client.cancelAll()
    await release.open()
    let error = try #require(await thrownAPIError { _ = try await pending.value })
    #expect(error.securityOutcome == .cancelled); #expect(error.statusCode == 403)
    #expect(await transport.requests.count == 1)
}

@Test func resendAfterPromptUsesTheCredentialCurrentNow() async throws {
    let clock = ManualClock(), reads = CallCounter()
    let transport = ScriptedTransport { request in
        if isRefresh(request) { return okReply(stubRefreshJSON) }
        return reads.next() == 1 ? complianceRefusal : okReply(stubUserJSON)
    }
    // While the sheet is open the access ages into its refresh window.
    let probe = InterceptorProbe(.passed, onCall: { clock.advance(by: 3_590) })
    let client = guardedClient(transport, probe, credential: stubTokens(expiresAt: clock.start.addingTimeInterval(3_600)), clock: clock.requestClock)
    #expect(try await client.user(id: 7).id == 7)
    let sent = await transport.requests.filter { !isRefresh($0) }
    #expect(sent.count == 2)
    #expect(sentHeader(sent[0], "Authorization") == "Bearer old-access"); #expect(sentHeader(sent[1], "Authorization") == "Bearer new-access")
}

@Test func accountTestRefusalCarriesTheOutcome() async throws {
    let body = #"{"code":"ADMIN_COMPLIANCE_ACK_REQUIRED","reason":"ADMIN_COMPLIANCE_ACK_REQUIRED"}"#
    let transport = ScriptedTransport(stream: { _ in
        HTTPStreamResponse(statusCode: 423, bytes: AsyncThrowingStream { $0.yield(Data(body.utf8)); $0.finish() })
    }) { _ in okReply("{}") }
    let probe = InterceptorProbe(.passed)
    let error = try #require(await thrownAPIError { _ = try await guardedClient(transport, probe).testAccount(id: 9, model: nil, expectsTestResult: false) })
    #expect(error.kind == .compliance); #expect(error.securityOutcome == .passed)
    #expect(await transport.requests.count == 1)
    #expect(await probe.calls == [.init(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED", isRead: false)])
}

@Test func withoutInterceptorOrForOtherErrorsNothingChanges() async throws {
    let transport = ScriptedTransport(script: [.reply(complianceRefusal), .reply(stepUpRefusal)])
    let plain = guardedClient(transport, nil)
    let locked = try #require(await thrownAPIError { _ = try await plain.user(id: 7) })
    #expect(locked.kind == .compliance); #expect(locked.securityOutcome == nil)
    let stepUp = try #require(await thrownAPIError { _ = try await plain.setUserStatus(id: 7, status: "active") })
    #expect(stepUp.action == .stepUp); #expect(stepUp.securityOutcome == nil)
    #expect(await transport.requests.count == 2)
    let forbidden = ScriptedTransport(script: [.reply(errorReply(403, reason: "FORBIDDEN"))])
    let probe = InterceptorProbe(.passed)
    let other = try #require(await thrownAPIError { _ = try await guardedClient(forbidden, probe).setUserStatus(id: 7, status: "active") })
    #expect(other.securityOutcome == nil); #expect(other.kind == .permission)
    #expect(await probe.calls.isEmpty)
}
