import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func keyedClient(_ transport: ScriptedTransport, clock: RequestClock = .immediate, credential: Credential = .adminKey("fixture")) -> APIClient {
    APIClient(server: stubServer(), credential: credential, deviceID: stubDeviceID, transport: transport, requestClock: clock)
}
private func balanceWrite(_ client: APIClient, serverID: UUID? = nil) -> PersistedMoneyWrite<PendingBalanceOperation> {
    stubPersisted(PendingBalanceOperation(serverID: serverID ?? client.server.id, userID: 7, amount: 1, operation: .add))
}
private func keyedFailure(_ operation: () async throws -> Void) async -> KeyedWriteFailure? {
    do { try await operation(); return nil } catch { return error as? KeyedWriteFailure }
}
private func inProgress(_ headers: [String: String] = [:], extra: String = "") -> HTTPResponse {
    errorReply(409, reason: "IDEMPOTENCY_IN_PROGRESS", headers: headers, extra: extra)
}
private actor Recorded<Value: Sendable> {
    private(set) var values = [Value]()
    func add(_ value: Value) { values.append(value) }
}

@Test func keyedWriteRetriesTransportFailuresWithSameKeyAndBytes() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .fail(URLError(.networkConnectionLost)), .reply(okReply(stubUserJSON))])
    let recorder = SleepRecorder()
    let client = keyedClient(transport, clock: .recording(recorder))
    let write = balanceWrite(client)
    let outcome = try await client.updateBalance(write)
    #expect(outcome.value.id == 7 && !outcome.replayed)
    let requests = await transport.requests, body = try write.record.requestBody()
    #expect(requests.count == 3)
    for request in requests {
        #expect(request.httpBody == body && request.timeoutInterval == 35)
        #expect(sentHeader(request, "Idempotency-Key") == write.record.key); #expect(sentHeader(request, "X-Request-ID") == write.record.key)
    }
    #expect(await recorder.durations == [.seconds(2), .seconds(5)])
}

@Test(arguments: [ScriptStep.fail(URLError(.timedOut)), .reply(HTTPResponse(statusCode: 502, data: Data("<html>bad gateway</html>".utf8))),
                  .reply(HTTPResponse(statusCode: 504, data: Data())), .reply(errorReply(503))])
func keyedWriteBecomesUnconfirmedAfterTwoTransportRetries(step: ScriptStep) async throws {
    let transport = ScriptedTransport(script: [step])
    let client = keyedClient(transport)
    let write = balanceWrite(client)
    let failure = try #require(await keyedFailure { _ = try await client.updateBalance(write) })
    #expect(failure.disposition == .unconfirmed(.transport, retryNotBefore: nil))
    #expect(failure.key == write.record.key)
    #expect(failure.localizedDescription == "结果未确认：服务器可能已执行。可以核对，或用同一编号重试，不会重复执行")
    #expect(await transport.requests.count == 3)
}

@Test func inProgressHonoursRetryAfterAndStopsAfterThirtySeconds() async throws {
    let clock = ManualClock(), stamps = Recorded<TimeInterval>()
    let transport = ScriptedTransport { _ in
        await stamps.add(clock.now().timeIntervalSince(clock.start))
        return inProgress(["Retry-After": "12"])
    }
    let recorder = SleepRecorder()
    let client = keyedClient(transport, clock: clock.advancingClock(recorder))
    let failure = try #require(await keyedFailure { _ = try await client.updateBalance(balanceWrite(client)) })
    #expect(failure.disposition == .unconfirmed(.stillProcessing, retryNotBefore: nil))
    #expect(failure.lastError?.reason == "IDEMPOTENCY_IN_PROGRESS")
    #expect(await stamps.values == [0, 12, 24, 30])
    #expect(await recorder.durations == [.seconds(12), .seconds(12), .seconds(6)])
    let requests = await transport.requests
    #expect(Set(requests.map { sentHeader($0, "Idempotency-Key") }).count == 1)
    #expect(requests.allSatisfy { $0.httpBody == requests[0].httpBody })
}

@Test func inProgressFallsBackToMetadataThenTwoSeconds() async throws {
    let transport = ScriptedTransport(script: [.reply(inProgress(extra: #","metadata":{"retry_after":"4"}"#)), .reply(inProgress()),
                                               .reply(okReply(stubUserJSON))])
    let recorder = SleepRecorder()
    let client = keyedClient(transport, clock: .recording(recorder))
    #expect(try await client.updateBalance(balanceWrite(client)).value.id == 7)
    #expect(await recorder.durations == [.seconds(4), .seconds(2)])
}

@Test func retryBackoffWaitsThenRetriesWithSameKey() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(409, reason: "IDEMPOTENCY_RETRY_BACKOFF", headers: ["Retry-After": "3"])),
                                               .reply(okReply(stubUserJSON))])
    let recorder = SleepRecorder()
    let client = keyedClient(transport, clock: .recording(recorder))
    #expect(try await client.updateBalance(balanceWrite(client)).value.id == 7)
    let requests = await transport.requests
    #expect(requests.count == 2 && requests[0].httpBody == requests[1].httpBody)
    #expect(sentHeader(requests[0], "Idempotency-Key") == sentHeader(requests[1], "Idempotency-Key"))
    #expect(await recorder.durations == [.seconds(3)])
}

@Test(arguments: [(409, "IDEMPOTENCY_KEY_CONFLICT", KeyedWriteFailure.NewKeyCause.keyConflict), (400, "IDEMPOTENCY_KEY_INVALID", .invalid),
                  (400, "IDEMPOTENCY_PAYLOAD_INVALID", .invalid), (400, "IDEMPOTENCY_KEY_REQUIRED", .keyRequired)]
      as [(Int, String, KeyedWriteFailure.NewKeyCause)])
func keyProblemsRequireReconfirmationWithoutRetry(status: Int, reason: String, cause: KeyedWriteFailure.NewKeyCause) async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(status, reason: reason)), .reply(okReply(stubUserJSON))])
    let recorder = SleepRecorder()
    let client = keyedClient(transport, clock: .recording(recorder))
    let failure = try #require(await keyedFailure { _ = try await client.updateBalance(balanceWrite(client)) })
    #expect(failure.disposition == .needsNewKey(cause))
    #expect(failure.localizedDescription == (cause == .keyConflict ? "请求已变化，请重新提交" : "请求无效，请重试"))
    #expect(await transport.requests.count == 1); #expect(await recorder.durations.isEmpty)
}

@Test func storeUnavailableIsNotRetriedImmediately() async throws {
    let clock = ManualClock(), recorder = SleepRecorder()
    let transport = ScriptedTransport(script: [.reply(errorReply(503, reason: "IDEMPOTENCY_STORE_UNAVAILABLE")), .reply(okReply(stubUserJSON))])
    let client = keyedClient(transport, clock: clock.advancingClock(recorder))
    let failure = try #require(await keyedFailure { _ = try await client.updateBalance(balanceWrite(client)) })
    #expect(failure.disposition == .unconfirmed(.storeUnavailable, retryNotBefore: clock.start.addingTimeInterval(10)))
    #expect(failure.localizedDescription == "服务器暂时无法受理，稍后用同一编号重试")
    #expect(await transport.requests.count == 1); #expect(await recorder.durations.isEmpty)
}

@Test(arguments: [["X-Idempotency-Recovered": "true"], ["X-Idempotency-Replayed": "true", "X-Idempotency-Expires-At": "2026-10-23T01:02:03Z"],
                  ["X-Idempotency-Degraded": "result-committed"]])
func recoveredReplayedAndDegradedResponsesCountAsSuccess(headers: [String: String]) async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(stubUserJSON, headers: headers))])
    let client = keyedClient(transport)
    let outcome = try await client.updateBalance(balanceWrite(client))
    #expect(outcome.value.id == 7)
    #expect(outcome.recovered == (headers["X-Idempotency-Recovered"] != nil))
    #expect(outcome.replayed == (headers["X-Idempotency-Replayed"] != nil))
    #expect(outcome.degraded == (headers["X-Idempotency-Degraded"] != nil))
    #expect((outcome.expiresAt != nil) == (headers["X-Idempotency-Expires-At"] != nil))
    #expect(await transport.requests.count == 1)
}

@Test(arguments: [errorReply(409, reason: "EMAIL_EXISTS"), errorReply(404, reason: "USER_NOT_FOUND"), errorReply(403, reason: "STEP_UP_REQUIRED"),
                  errorReply(423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED"), errorReply(429, reason: "RATE_LIMITED", headers: ["Retry-After": "9"]),
                  errorReply(401, reason: "TOKEN_REVOKED"), errorReply(500, extra: #","message":"upstream secret""#)])
func businessErrorsAreThrownAsAPIErrorWithoutRetry(response: HTTPResponse) async throws {
    let transport = ScriptedTransport(script: [.reply(response), .reply(okReply(stubUserJSON))])
    let recorder = SleepRecorder()
    let client = keyedClient(transport, clock: .recording(recorder))
    let error = try #require(await thrownAPIError { _ = try await client.updateBalance(balanceWrite(client)) })
    #expect(error.statusCode == response.statusCode)
    #expect(error.reason == ErrorEnvelope.decode(response.data)?.marker)
    #expect(!error.localizedDescription.contains("secret"))
    if response.statusCode == 429 { #expect(error.retryAfter == 9) }
    #expect(await transport.requests.count == 1); #expect(await recorder.durations.isEmpty)
}

/// 00 §2.5.4 step 2: after an attempt that may have run, a later one turned away before the handler does not settle the write.
@Test(arguments: [ScriptStep.fail(URLError(.timedOut)), .reply(HTTPResponse(statusCode: 504, data: Data())), .reply(inProgress(["Retry-After": "1"])),
                  .reply(errorReply(409, reason: "IDEMPOTENCY_RETRY_BACKOFF", headers: ["Retry-After": "1"]))],
      [errorReply(401, reason: "TOKEN_REVOKED"), errorReply(403, reason: "FORBIDDEN"), errorReply(403, reason: "STEP_UP_REQUIRED"),
       errorReply(423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED"), errorReply(429, reason: "RATE_LIMITED"),
       errorReply(503, reason: "STEP_UP_UNAVAILABLE")])
func rejectionBeforeExecutionAfterUncertainAttemptStaysUnconfirmed(first: ScriptStep, then rejection: HTTPResponse) async throws {
    let action = UUID()
    let transport = ScriptedTransport(script: [first, .reply(HTTPResponse(statusCode: rejection.statusCode,
                                                                         headers: ["X-Admin-Adjustment-Action-ID": action.uuidString], data: rejection.data))])
    let client = keyedClient(transport)
    let write = balanceWrite(client)
    let failure = try #require(await keyedFailure { _ = try await client.updateBalance(write) })
    #expect(failure.disposition == .unconfirmed(.transport, retryNotBefore: nil))
    #expect(failure.key == write.record.key && failure.actionID == action)
    #expect(failure.lastError?.statusCode == rejection.statusCode)
    #expect(failure.lastError?.reason == ErrorEnvelope.decode(rejection.data)?.marker)
    #expect(await transport.requests.count == 2)
}

/// The session ends while the write waits to retry (refresh rejected, or no refresh token): the first attempt may have run.
@Test(arguments: [true, false])
func sessionEndingBeforeRetryKeepsWriteUnconfirmed(refreshable: Bool) async throws {
    let clock = ManualClock(), recorder = SleepRecorder()
    let transport = ScriptedTransport { request in
        if isRefresh(request) { return errorReply(401, reason: "REFRESH_TOKEN_EXPIRED") }
        throw URLError(.timedOut)
    }
    // 61 seconds of access: enough for the first attempt, under the 60-second refresh lead after the 2-second wait.
    let tokens = TokenPair(accessToken: "old-access", refreshToken: refreshable ? "old-refresh" : "", expiresAt: clock.start.addingTimeInterval(61))
    let client = keyedClient(transport, clock: clock.advancingClock(recorder), credential: .tokens(tokens))
    let failure = try #require(await keyedFailure { _ = try await client.updateBalance(balanceWrite(client)) })
    #expect(failure.disposition == .unconfirmed(.transport, retryNotBefore: nil))
    #expect(failure.lastError?.statusCode == 401)
    #expect(await transport.requests.filter { !isRefresh($0) }.count == 1)
    #expect(await recorder.durations == [.seconds(2)])
}

/// A business answer still passes through the idempotency layer, so it settles the write even after a lost attempt.
@Test func businessAnswerAfterLostAttemptStillSettles() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(errorReply(400, reason: "INVALID_BALANCE"))])
    let client = keyedClient(transport)
    let error = try #require(await thrownAPIError { _ = try await client.updateBalance(balanceWrite(client)) })
    #expect(error.statusCode == 400 && error.reason == "INVALID_BALANCE")
    #expect(await transport.requests.count == 2)
}

@Test func actionIDIsCapturedFromAnyResponse() async throws {
    let action = UUID()
    let transport = ScriptedTransport(script: [.reply(inProgress(["Retry-After": "1", "X-Admin-Adjustment-Action-ID": action.uuidString.lowercased()])),
                                               .fail(URLError(.timedOut))])
    let events = Recorded<KeyedWriteEvent>()
    let client = keyedClient(transport)
    let failure = try #require(await keyedFailure { _ = try await client.updateBalance(balanceWrite(client)) { await events.add($0) } })
    #expect(failure.actionID == action)
    #expect(failure.disposition == .unconfirmed(.transport, retryNotBefore: nil))
    #expect(await events.values == [.actionID(action), .waitingForServer(elapsedSeconds: 0), .confirming(retry: 1), .confirming(retry: 2)])
    #expect(await transport.requests.count == 4)
    let rejecting = ScriptedTransport(script: [.reply(errorReply(500, headers: ["X-Admin-Adjustment-Action-ID": action.uuidString]))])
    let other = keyedClient(rejecting)
    let error = try #require(await thrownAPIError { _ = try await other.updateBalance(balanceWrite(other)) })
    #expect(error.actionID == action && error.statusCode == 500)
}

@Test func cancelAllDuringWaitStopsRetries() async throws {
    let sleeping = OpenGate()
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(stubUserJSON))])
    let clock = RequestClock(sleep: { _ in await sleeping.open(); try await Task.sleep(for: .seconds(60)) }, jitter: { .zero })
    let client = keyedClient(transport, clock: clock)
    let write = balanceWrite(client)
    let pending = Task { try await client.updateBalance(write) }
    // If the write never waits, open the gate so the test fails instead of hanging.
    let watcher = Task { _ = try? await pending.value; await sleeping.open() }
    await sleeping.wait()
    await client.cancelAll()
    await #expect(throws: CancellationError.self) { try await pending.value }
    _ = await watcher.value
    #expect(await transport.requests.count == 1)
}

@Test func balanceWriteRejectsOtherStationAndUnreadableSuccessIsUnconfirmed() async throws {
    let transport = ScriptedTransport(script: [.reply(HTTPResponse(statusCode: 200, data: Data("<html>portal</html>".utf8))), .reply(okReply(stubUserJSON))])
    let client = keyedClient(transport)
    await #expect(throws: APIError.stationMismatch) { try await client.updateBalance(balanceWrite(client, serverID: UUID())) }
    #expect(await transport.requests.isEmpty)
    let failure = try #require(await keyedFailure { _ = try await client.updateBalance(balanceWrite(client)) })
    #expect(failure.disposition == .unconfirmed(.unreadableResponse, retryNotBefore: nil))
    #expect(await transport.requests.count == 1)
    let emptyData = ScriptedTransport(script: [.reply(okReply("{}"))])
    let other = keyedClient(emptyData)
    #expect(await keyedFailure { _ = try await other.updateBalance(balanceWrite(other)) }?.disposition == .unconfirmed(.unreadableResponse, retryNotBefore: nil))
}

@Test func userWritesSendKeyOnlyWhenOperationAllows() async throws {
    let offline = ScriptedTransport(script: [.fail(URLError(.timedOut))])
    let client = keyedClient(offline)
    let identity = await client.userWriteIdentity()
    let input = UserCreateRequest(email: "a@example.invalid", password: "abcdef")
    let plain = try PendingUserCreateOperation(serverID: client.server.id, identity: identity, request: input, sendsIdempotencyKey: false)
    #expect(try #require(await thrownAPIError { _ = try await client.createUser(plain) }).kind == .transport)
    let first = await offline.requests
    #expect(first.count == 1 && first[0].timeoutInterval == 30 && first[0].httpBody == plain.body)
    #expect(sentHeader(first[0], "Idempotency-Key") == nil); #expect(sentHeader(first[0], "X-Request-ID") == plain.key)
    let keyed = try PendingUserCreateOperation(serverID: client.server.id, identity: identity, request: input, sendsIdempotencyKey: true)
    #expect(await keyedFailure { _ = try await client.createUser(keyed) }?.disposition == .unconfirmed(.transport, retryNotBefore: nil))
    let retried = await offline.requests.dropFirst()
    #expect(retried.count == 3 && retried.allSatisfy { sentHeader($0, "Idempotency-Key") == keyed.key && $0.httpBody == keyed.body })
    #expect(retried.allSatisfy { $0.timeoutInterval == 35 && $0.url?.path == "/api/v1/admin/users" && $0.httpMethod == "POST" })
    let action = UUID()
    let online = ScriptedTransport(script: [.reply(okReply(stubUserJSON, headers: ["X-Admin-Adjustment-Action-ID": action.uuidString]))])
    let creator = keyedClient(online)
    let operation = try PendingUserCreateOperation(serverID: creator.server.id, identity: await creator.userWriteIdentity(),
                                                   request: UserCreateRequest(email: "b@example.invalid", password: "abcdef", balance: 5), sendsIdempotencyKey: true)
    #expect(try await creator.createUser(operation).actionID == action)
    let rename = UserUpdateRequest(username: "新名称")
    #expect(try PendingUserUpdateOperation(serverID: client.server.id, identity: identity, userID: 7, request: rename, serverSupportsIdempotentWrites: true).supportsSafeRetry)
    #expect(try !PendingUserUpdateOperation(serverID: client.server.id, identity: identity, userID: 7, request: rename).supportsSafeRetry)
    #expect(!String(reflecting: keyed).contains("abcdef"))
}

@Test func expiredTokenDuringKeyedWriteResendsSameKeyAndBytes() async throws {
    let transport = ScriptedTransport { request in
        if isRefresh(request) { return okReply(stubRefreshJSON) }
        if sentHeader(request, "Authorization") == "Bearer old-access" { return errorReply(401, reason: "TOKEN_EXPIRED") }
        return okReply(stubUserJSON)
    }
    let recorder = SleepRecorder()
    let client = keyedClient(transport, clock: .recording(recorder), credential: stubTokens())
    _ = try await client.updateBalance(balanceWrite(client))
    let writes = await transport.requests.filter { !isRefresh($0) }
    #expect(writes.count == 2 && writes[0].httpBody == writes[1].httpBody)
    for name in ["Idempotency-Key", "X-Request-ID"] { #expect(sentHeader(writes[0], name) == sentHeader(writes[1], name)) }
    #expect(sentHeader(writes[1], "Authorization") == "Bearer new-access")
    #expect(await recorder.durations.isEmpty)
}

// D18: same-key retries happen only in the foreground. A wait interrupted by suspend leaves the write unconfirmed.
@Test func suspendDuringWaitLeavesWriteUnconfirmed() async throws {
    let sleeping = OpenGate()
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(stubUserJSON))])
    let clock = RequestClock(sleep: { _ in await sleeping.open(); try await Task.sleep(for: .seconds(60)) }, jitter: { .zero })
    let client = keyedClient(transport, clock: clock)
    let write = balanceWrite(client)
    let pending = Task { try await client.updateBalance(write) }
    let watcher = Task { _ = try? await pending.value; await sleeping.open() }
    await sleeping.wait()
    await client.suspend()
    let failure = try #require(await keyedFailure { _ = try await pending.value })
    #expect(failure.disposition == .unconfirmed(.transport, retryNotBefore: nil))
    #expect(failure.key == write.record.id.uuidString.lowercased())
    _ = await watcher.value
    #expect(await transport.requests.count == 1)
}

@Test func keyedRetryWaitsOnlyWhileInForeground() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .fail(URLError(.timedOut)), .reply(okReply(stubUserJSON))])
    let client = keyedClient(transport)
    await client.suspend()
    let failure = try #require(await keyedFailure { _ = try await client.updateBalance(balanceWrite(client)) })
    #expect(failure.disposition == .unconfirmed(.transport, retryNotBefore: nil))
    #expect(await transport.requests.count == 1)
    await client.resume()
    #expect(try await client.updateBalance(balanceWrite(client)).value.id == 7)
    #expect(await transport.requests.count == 3)
}

/// cross_review_notes S0-06 §1: a business answer after IN_PROGRESS still carries the action id the flow already saw.
@Test func businessErrorAfterInProgressKeepsTheFlowsActionID() async throws {
    let action = UUID()
    let transport = ScriptedTransport(script: [.reply(inProgress(["Retry-After": "1", "X-Admin-Adjustment-Action-ID": action.uuidString])),
                                               .reply(errorReply(400, reason: "INVALID_BALANCE"))])
    let client = keyedClient(transport)
    let error = try #require(await thrownAPIError { _ = try await client.updateBalance(balanceWrite(client)) })
    #expect(error.statusCode == 400); #expect(error.reason == "INVALID_BALANCE"); #expect(error.actionID == action)
    // A reply's own header wins over the one seen earlier.
    let own = UUID()
    let replied = ScriptedTransport(script: [.reply(inProgress(["Retry-After": "1", "X-Admin-Adjustment-Action-ID": action.uuidString])),
                                             .reply(errorReply(400, reason: "INVALID_BALANCE", headers: ["X-Admin-Adjustment-Action-ID": own.uuidString]))])
    let other = keyedClient(replied)
    #expect(await thrownAPIError { _ = try await other.updateBalance(balanceWrite(other)) }?.actionID == own)
    #expect(await transport.requests.count == 2)
}
