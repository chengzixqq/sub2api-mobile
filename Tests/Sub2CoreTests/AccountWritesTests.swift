import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let writtenAccountJSON = #"{"id":9,"name":"测试账号","platform":"anthropic","type":"oauth","status":"active","schedulable":false}"#
/// 2027-01-15T08:00:00Z.
private let checkNow = Date(timeIntervalSince1970: 1_800_000_000)

private func writeClient(_ transport: ScriptedTransport, clock: RequestClock = .immediate) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: clock)
}
private func account(status: String = "active", schedulable: Bool = true, _ fields: String = "") throws -> UpstreamAccount {
    let json = #"{"id":9,"name":"测试账号","platform":"anthropic","type":"oauth","status":"\#(status)","schedulable":\#(schedulable)"#
        + (fields.isEmpty ? "" : "," + fields) + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func bodyText(_ request: URLRequest) -> String { String(decoding: request.httpBody ?? Data(), as: UTF8.self) }
private func keyedFailure(_ operation: () async throws -> Void) async -> KeyedWriteFailure? {
    do { try await operation(); return nil } catch { return error as? KeyedWriteFailure }
}

// MARK: - Scheduling switch

@Test func setSchedulableWithKeySendsKeyAndRetriesSameBytes() async throws {
    let replayed = okReply(writtenAccountJSON, headers: ["X-Idempotency-Replayed": "true"])
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .fail(URLError(.networkConnectionLost)), .reply(replayed)])
    let key = UUID()
    let outcome = try await writeClient(transport).setSchedulable(id: 9, enabled: false, idempotencyKey: key)
    #expect(outcome.value.id == 9 && outcome.replayed)
    let requests = await transport.requests
    #expect(requests.count == 3)
    for request in requests {
        #expect(request.httpMethod == "POST" && request.url?.path == "/api/v1/admin/accounts/9/schedulable")
        #expect(bodyText(request) == #"{"schedulable":false}"# && request.timeoutInterval == RequestTimeout.keyedWrite)
        #expect(sentHeader(request, "Idempotency-Key") == key.uuidString.lowercased() && sentHeader(request, "X-Request-ID") == key.uuidString.lowercased())
    }
}

@Test func setSchedulableWithKeyEndsUnconfirmedOrWaitsForTheServer() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut))])
    let recorder = SleepRecorder()
    let client = writeClient(transport, clock: .recording(recorder))
    let failure = await keyedFailure { _ = try await client.setSchedulable(id: 9, enabled: true, idempotencyKey: UUID()) }
    #expect(failure?.disposition == .unconfirmed(.transport, retryNotBefore: nil))
    #expect(await transport.requests.count == 3)
    #expect(await recorder.durations == [.seconds(2), .seconds(5)])
    let waiting = ScriptedTransport(script: [.reply(errorReply(409, reason: "IDEMPOTENCY_IN_PROGRESS")), .reply(okReply(writtenAccountJSON))])
    let key = UUID()
    #expect(try await writeClient(waiting).setSchedulable(id: 9, enabled: true, idempotencyKey: key).value.id == 9)
    let sent = await waiting.requests
    #expect(sent.count == 2)
    #expect(sent.allSatisfy { sentHeader($0, "Idempotency-Key") == key.uuidString.lowercased() })
}

@Test func setSchedulableWithoutKeyIsSentOnce() async throws {
    for step in [ScriptStep.fail(URLError(.timedOut)), .reply(HTTPResponse(statusCode: 502, data: Data()))] {
        let transport = ScriptedTransport(script: [step, .reply(okReply(writtenAccountJSON))])
        #expect(await thrownAPIError { _ = try await writeClient(transport).setSchedulable(id: 9, enabled: true) } != nil)
        #expect(await transport.requests.count == 1)
    }
    let transport = ScriptedTransport(script: [.reply(okReply(writtenAccountJSON))])
    #expect(try await writeClient(transport).setSchedulable(id: 9, enabled: true, idempotencyKey: nil).value.id == 9)
    let sent = try #require(await transport.requests.first)
    #expect(sentHeader(sent, "Idempotency-Key") == nil && bodyText(sent) == #"{"schedulable":true}"#)
    #expect(sent.timeoutInterval == RequestTimeout.unkeyedWrite)
    let requestID = try #require(sentHeader(sent, "X-Request-ID"))
    #expect(requestID == requestID.lowercased() && UUID(uuidString: requestID) != nil)
}

@Test func setSchedulableKeyConflictNeedsNewKey() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(409, reason: "IDEMPOTENCY_KEY_CONFLICT"))])
    let failure = await keyedFailure { _ = try await writeClient(transport).setSchedulable(id: 9, enabled: true, idempotencyKey: UUID()) }
    #expect(failure?.disposition == .needsNewKey(.keyConflict))
    #expect(await transport.requests.count == 1)
}

// MARK: - Recovery, deletion, models, proxy fallback

@Test(arguments: [nil, true, false] as [Bool?])
func recoverStateBodyFollowsSchedulableChoice(schedulable: Bool?) async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(writtenAccountJSON))])
    #expect(try await writeClient(transport).recoverAccountState(id: 9, schedulable: schedulable).id == 9)
    let sent = try #require(await transport.requests.first)
    #expect(sent.httpMethod == "POST" && sent.url?.path == "/api/v1/admin/accounts/9/recover-state")
    #expect(sentHeader(sent, "Idempotency-Key") == nil)
    if let schedulable {
        #expect(bodyText(sent) == "{\"schedulable\":\(schedulable)}" && sentHeader(sent, "Content-Type") == "application/json")
    } else {
        #expect(sent.httpBody == nil && sentHeader(sent, "Content-Type") == nil)
    }
}

@Test func recoverStatePartialFailureIsSurfacedForReadBack() async throws {
    let failed = errorReply(500, reason: "ACCOUNT_RECOVERED_SCHEDULABLE_FAILED", extra: #","metadata":{"recovered":"true"}"#)
    let transport = ScriptedTransport(script: [.reply(failed)])
    let error = try #require(await thrownAPIError { _ = try await writeClient(transport).recoverAccountState(id: 9, schedulable: true) })
    #expect(error.reason == AccountWriteReason.recoveredSchedulableFailed && error.metadata["recovered"] == "true" && error.action == .readBack)
    #expect(AccountWriteReason.isRecoveredButStillPaused(error))
    #expect(!AccountWriteReason.isRecoveredButStillPaused(.server(status: 500, reason: nil)))
    #expect(await transport.requests.count == 1)
    let lost = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(writtenAccountJSON))])
    #expect(await thrownAPIError { _ = try await writeClient(lost).recoverAccountState(id: 9, schedulable: nil) }?.kind == .transport)
    #expect(await lost.requests.count == 1)
}

@Test func deleteAccountTreatsAccountNotFoundAsAlreadyGone() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"message":"Account deleted successfully"}"#)), .reply(errorReply(404, reason: "ACCOUNT_NOT_FOUND"))])
    let client = writeClient(transport)
    #expect(try await client.deleteAccount(id: 9) == .deleted)
    #expect(try await client.deleteAccount(id: 9) == .alreadyGone)
    for request in await transport.requests {
        #expect(request.httpMethod == "DELETE" && request.url?.path == "/api/v1/admin/accounts/9")
        #expect(request.httpBody == nil && sentHeader(request, "Idempotency-Key") == nil)
    }
    let thrown: [(ScriptStep, APIError.Kind)] = [
        (.reply(HTTPResponse(statusCode: 404, data: Data("404 page not found".utf8))), .unsupported),
        (.reply(errorReply(404, reason: "RESOURCE_NOT_FOUND")), .notFound),
        (.reply(errorReply(500)), .temporary),
        (.fail(URLError(.timedOut)), .transport)
    ]
    for (step, kind) in thrown {
        let failing = ScriptedTransport(script: [step, .reply(okReply(#"{"message":"ok"}"#))])
        #expect(await thrownAPIError { _ = try await writeClient(failing).deleteAccount(id: 9) }?.kind == kind)
        #expect(await failing.requests.count == 1)
    }
    #expect(await thrownAPIError { _ = try await client.deleteAccount(id: 0) }?.kind == .validation)
}

@Test func accountModelsUseDisplayNameWithIDFallback() async throws {
    let models = #"[{"id":"claude-a","display_name":"Claude A","type":"model"},{"id":"grok-x","owned_by":"xai"},{"id":"claude-a","display_name":"重复"},{"id":""},{"id":"m","display_name":"  "}]"#
    let transport = ScriptedTransport(script: [.reply(okReply(models))])
    let options = try await writeClient(transport).accountModels(id: 9)
    #expect(options == [AccountModelOption(id: "claude-a", displayName: "Claude A"), AccountModelOption(id: "grok-x"), AccountModelOption(id: "m")])
    #expect(options.map(\.displayName) == ["Claude A", "grok-x", "m"])
    let sent = try #require(await transport.requests.first)
    #expect(sent.httpMethod == "GET" && sent.url?.path == "/api/v1/admin/accounts/9/models")
}

@Test func revertProxyFallbackPostsWithoutBodyOrKey() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"message":"reverted"}"#)), .reply(errorReply(400, reason: "ACCOUNT_NOT_IN_FALLBACK")),
                                               .reply(errorReply(409, reason: "PROXY_FALLBACK_ORIGIN_UNAVAILABLE")), .fail(URLError(.timedOut))])
    let client = writeClient(transport)
    try await client.revertAccountProxyFallback(id: 9)
    #expect(await thrownAPIError { try await client.revertAccountProxyFallback(id: 9) }?.reason == AccountWriteReason.notInFallback)
    #expect(await thrownAPIError { try await client.revertAccountProxyFallback(id: 9) }?.reason == AccountWriteReason.fallbackOriginUnavailable)
    #expect(await thrownAPIError { try await client.revertAccountProxyFallback(id: 9) }?.kind == .transport)
    let requests = await transport.requests
    #expect(requests.count == 4)
    for request in requests {
        #expect(request.httpMethod == "POST" && request.url?.path == "/api/v1/admin/accounts/9/revert-proxy-fallback")
        #expect(request.httpBody == nil && sentHeader(request, "Idempotency-Key") == nil && sentHeader(request, "X-Request-ID") != nil)
    }
}

// MARK: - Read-back checks (20 §5.2)

@Test func writeCheckSchedulableAndActive() throws {
    let paused = try account(schedulable: false)
    #expect(AccountWriteCheck.schedulable(paused, equals: false) && !AccountWriteCheck.schedulable(paused, equals: true))
    #expect(AccountWriteCheck.schedulable(try account(), equals: true))
    #expect(AccountWriteCheck.isActive(try account()))
    for status in ["inactive", "error", "disabled"] { #expect(!AccountWriteCheck.isActive(try account(status: status)), "\(status)") }
}

@Test func writeCheckRecoveredUsesServerTime() throws {
    let cases: [(String, String, Bool)] = [
        ("error", "", false),
        ("active", #""rate_limit_reset_at":null,"overload_until":null,"temp_unschedulable_until":null"#, true),
        ("active", #""rate_limit_reset_at":"2027-01-15T09:00:00Z""#, false),
        ("active", #""rate_limit_reset_at":"2027-01-15T07:00:00Z""#, true),
        ("active", #""overload_until":"2027-01-15T08:30:00Z""#, false),
        ("active", #""temp_unschedulable_until":"2027-01-15T08:00:01Z""#, false),
        ("inactive", "", true),
        ("active", #""overload_until":"not-a-time""#, false)
    ]
    for (status, fields, expected) in cases {
        #expect(AccountWriteCheck.recovered(try account(status: status, fields), now: checkNow) == expected, "\(status) \(fields)")
    }
}

@Test func writeCheckProxyReverted() throws {
    #expect(AccountWriteCheck.proxyReverted(try account(#""proxy_id":4,"proxy_fallback_origin_id":null"#), toOrigin: 4))
    #expect(!AccountWriteCheck.proxyReverted(try account(#""proxy_id":6,"proxy_fallback_origin_id":4"#), toOrigin: 4))
    #expect(!AccountWriteCheck.proxyReverted(try account(#""proxy_id":6"#), toOrigin: 4))
    #expect(!AccountWriteCheck.proxyReverted(try account(#""proxy_id":null"#), toOrigin: 4))
}
