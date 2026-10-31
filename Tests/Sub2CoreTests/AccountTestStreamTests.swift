import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import Sub2Core

// 20 §4.2 / §4.7, C07: with accounts.test_result only test_result ends the stream; an old server is read to EOF.

private let startFrame = "data: {\"type\":\"test_start\",\"model\":\"m\"}\n\n"
private let errorFrame = "data: {\"type\":\"error\",\"error\":\"API returned 401: bad\"}\n\n"
private let statusFrame = "data: {\"type\":\"status\",\"text\":\"Retrying\"}\n\n"
private let contentFrame = "data: {\"type\":\"content\",\"text\":\"你好\"}\n\n"
private let completeFrame = "data: {\"type\":\"test_complete\",\"success\":true}\n\n"
private let failedResultFrame = "data: {\"type\":\"test_result\",\"data\":{\"success\":false,\"started_at\":\"2026-10-17T09:40:00Z\","
    + "\"first_token_ms\":null,\"total_ms\":800,\"upstream_status\":401,\"account\":{\"status\":\"error\",\"schedulable\":false,"
    + "\"rate_limit_reset_at\":null,\"temp_unschedulable_until\":null,\"error_summary\":\"凭据无效\",\"error_kind\":\"auth\"},"
    + "\"recovery\":null,\"marked\":{\"error\":true,\"rate_limited\":false,\"temp_unschedulable\":false}}}\n\n"
private let passedResultFrame = "data: {\"type\":\"test_result\",\"data\":{\"success\":true,\"total_ms\":3420,"
    + "\"usage\":{\"input_tokens\":12,\"output_tokens\":38},\"recovery\":{\"cleared_error\":true,\"cleared_rate_limit\":false}}}\n\n"

/// Feeds `raw` one byte at a time, so UTF-8, CRLF and frames straddle chunks.
private func bytewise(_ parser: inout AccountSSEParser, _ raw: String) throws -> [AccountTestEvent] {
    var events = [AccountTestEvent]()
    for byte in raw.utf8 { events += try parser.append(Data([byte])) }
    return events
}
private func event(_ json: String) throws -> AccountTestEvent { try JSONDecoder().decode(AccountTestEvent.self, from: Data(json.utf8)) }

private func streamClient(_ transport: ScriptedTransport, onSessionInvalid: (@Sendable (SessionInvalidation) -> Void)? = nil) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport,
              requestClock: .immediate, onSessionInvalid: onSessionInvalid)
}
private func sseResponse(_ bytes: AsyncThrowingStream<Data, any Error>) -> HTTPStreamResponse {
    HTTPStreamResponse(statusCode: 200, headers: ["content-type": "text/event-stream; charset=utf-8"], bytes: bytes)
}
private func finishedBytes(_ raw: String) -> AsyncThrowingStream<Data, any Error> {
    AsyncThrowingStream { continuation in continuation.yield(Data(raw.utf8)); continuation.finish() }
}

private final class InvalidationRecorder: Sendable {
    private let values = Mutex<[SessionInvalidation]>([])
    var all: [SessionInvalidation] { values.withLock { $0 } }
    var handler: @Sendable (SessionInvalidation) -> Void { { [self] value in values.withLock { $0.append(value) } } }
}

private actor EventLog {
    private(set) var events = [AccountTestEvent]()
    private(set) var ended = false
    func append(_ event: AccountTestEvent) { events.append(event) }
    func end() { ended = true }
}

// MARK: - Parser

@Test func resultModeReadsPastErrorUntilTestResult() throws {
    var parser = AccountSSEParser(expectsTestResult: true)
    var events = try bytewise(&parser, startFrame + errorFrame)
    #expect(!parser.receivedTerminal && !parser.receivedConclusion)
    events += try bytewise(&parser, statusFrame)
    #expect(!parser.receivedTerminal && !parser.receivedConclusion)
    events += try bytewise(&parser, failedResultFrame)
    #expect(parser.receivedTerminal && parser.receivedConclusion)
    #expect(try parser.append(Data(contentFrame.utf8)).isEmpty)
    _ = try parser.finish()
    #expect(events.map(\.type) == ["test_start", "error", "status", "test_result"])
    #expect(events[0].model == "m"); #expect(events[1].message == "API returned 401: bad"); #expect(events[2].content == "Retrying")
    #expect(events[3].isTestResult && !events[3].isSuccess)
    #expect(events[3].data?.success == false); #expect(events[3].data?.upstreamStatus == 401)
    #expect(events[3].data?.account?.errorKind == "auth"); #expect(events[3].data?.marked?.error == true)
}

@Test func resultModeTreatsTestCompleteAsNotFinal() throws {
    var parser = AccountSSEParser(expectsTestResult: true)
    let complete = try bytewise(&parser, contentFrame + completeFrame)
    #expect(complete.last?.isSuccess == true && complete.last?.isLegacyConclusion == true)
    #expect(!parser.receivedConclusion && !parser.receivedTerminal)
    let result = try bytewise(&parser, passedResultFrame)
    #expect(parser.receivedConclusion && parser.receivedTerminal)
    #expect(result.first?.data?.usage == AccountTestResult.Usage(inputTokens: 12, outputTokens: 38))
    #expect(result.first?.data?.recovery == AccountTestResult.Recovery(clearedError: true, clearedRateLimit: false))
    _ = try parser.finish()
}

@Test(arguments: [errorFrame, completeFrame, contentFrame, ""])
func resultModeEOFWithoutTestResultIsIncomplete(_ raw: String) throws {
    var parser = AccountSSEParser(expectsTestResult: true)
    _ = try bytewise(&parser, raw)
    #expect(throws: APIError.incompleteStream) { try parser.finish() }
}

@Test func legacyModeConcludesAtCompleteOrErrorButKeepsReading() throws {
    for conclusion in [completeFrame, errorFrame] {
        var parser = AccountSSEParser()
        let first = try bytewise(&parser, contentFrame + conclusion)
        #expect(first.count == 2); #expect(parser.receivedConclusion && !parser.receivedTerminal)
        let later = try bytewise(&parser, statusFrame)
        #expect(later.map(\.type) == ["status"])
        _ = try parser.finish()
    }
    var unfinished = AccountSSEParser()
    _ = try bytewise(&unfinished, contentFrame + statusFrame)
    #expect(throws: APIError.incompleteStream) { try unfinished.finish() }
}

@Test func testResultDecodesC07Payload() throws {
    let decoded = try event(#"{"type":"test_result","data":{"success":true,"started_at":"2026-10-17T09:40:00Z","first_token_ms":1210,"#
        + #""total_ms":3420,"upstream_status":200,"usage":{"input_tokens":12,"output_tokens":38},"account":{"status":"active","#
        + #""schedulable":false,"rate_limit_reset_at":null,"temp_unschedulable_until":null,"error_summary":""},"#
        + #""recovery":{"cleared_error":true,"cleared_rate_limit":false},"marked":{"error":false,"rate_limited":false,"temp_unschedulable":false}}}"#)
    let data = try #require(decoded.data)
    #expect(data.success); #expect(data.startedAt == ServerTime.parseTimestamp("2026-10-17T09:40:00Z"))
    #expect(data.firstTokenMs == 1210 && data.totalMs == 3420 && data.upstreamStatus == 200)
    #expect(data.usage == AccountTestResult.Usage(inputTokens: 12, outputTokens: 38))
    #expect(data.account == AccountTestResult.AccountState(status: "active", schedulable: false))
    #expect(data.recovery == AccountTestResult.Recovery(clearedError: true, clearedRateLimit: false))
    #expect(data.marked == AccountTestResult.Marked(error: false, rateLimited: false, tempUnschedulable: false))
    let precise = try event(#"{"type":"test_result","data":{"success":false,"started_at":"2026-10-17T17:40:00.123456789+08:00","total_ms":5}}"#)
    #expect(precise.data?.startedAt == ServerTime.parseTimestamp("2026-10-17T09:40:00.123Z"))
}

@Test func testResultToleratesNullsMissingAndMalformedData() throws {
    let sparse = try event(#"{"type":"test_result","data":{"success":false,"first_token_ms":null,"upstream_status":null,"account":null,"#
        + #""recovery":null,"marked":null,"total_ms":12,"unknown":{"x":1}}}"#)
    let data = try #require(sparse.data)
    #expect(!data.success && data.totalMs == 12)
    #expect(data.firstTokenMs == nil && data.upstreamStatus == nil && data.usage == nil)
    #expect(data.account == nil && data.recovery == nil && data.marked == nil && data.startedAt == nil)
    let limited = try event(#"{"type":"test_result","data":{"success":false,"account":{"status":"active","schedulable":true,"#
        + #""rate_limit_reset_at":"2026-10-17T10:00:00Z","temp_unschedulable_until":"bad","error_summary":"限流","error_kind":"rate_limit"}}}"#)
    #expect(limited.data?.account?.rateLimitResetAt == ServerTime.parseTimestamp("2026-10-17T10:00:00Z"))
    #expect(limited.data?.account?.tempUnschedulableUntil == nil)
    #expect(limited.data?.account?.errorSummary == "限流" && limited.data?.account?.errorKind == "rate_limit")
    for malformed in [#"{"type":"test_result","data":"done"}"#, #"{"type":"test_result","data":{"total_ms":5}}"#, #"{"type":"test_result"}"#] {
        let result = try event(malformed)
        #expect(result.isTestResult && result.data == nil)
        var parser = AccountSSEParser(expectsTestResult: true)
        _ = try parser.append(Data(("data: " + malformed + "\n\n").utf8))
        #expect(parser.receivedTerminal); _ = try parser.finish()
    }
    #expect(try event(#"{"type":"content","text":"x","data":{"success":true}}"#).data == nil)
}

// MARK: - testAccount

// The stream's task holds the client weakly, so each test keeps its client alive until the stream has ended.

@Test(.timeLimit(.minutes(1))) func testAccountSendsBodyAcceptAndStopsAtTestResult() async throws {
    let (bytes, feed) = AsyncThrowingStream<Data, any Error>.makeStream()
    let wire = Data((errorFrame + failedResultFrame).utf8)
    let cut = wire.firstIndex(of: 0xE5)! + 1 // inside 凭
    feed.yield(Data(wire[..<cut])); feed.yield(Data(wire[cut...]))
    let transport = ScriptedTransport(stream: { request in
        #expect(request.httpMethod == "POST"); #expect(request.url?.path == "/api/v1/admin/accounts/9/test")
        #expect(sentHeader(request, "Accept") == "text/event-stream"); #expect(sentHeader(request, "Content-Type") == "application/json")
        #expect(request.httpBody == Data(#"{"model_id":"claude-sonnet-4-5"}"#.utf8)); #expect(sentHeader(request, "X-Request-ID") != nil)
        return sseResponse(bytes)
    }) { _ in errorReply(500) }
    let client = streamClient(transport)
    var events = [AccountTestEvent]()
    for try await event in try await client.testAccount(id: 9, model: "claude-sonnet-4-5", expectsTestResult: true) { events.append(event) }
    #expect(events.map(\.type) == ["error", "test_result"])
    #expect(events.last?.data?.account?.errorSummary == "凭据无效")
    feed.finish()
    withExtendedLifetime(client) {}
}

@Test(arguments: [
    (nil, nil, nil, #"{"model_id":""}"#),
    (" m ", " ", "", #"{"model_id":"m"}"#),
    (nil, "hi", "compact", #"{"mode":"compact","model_id":"","prompt":"hi"}"#),
] as [(String?, String?, String?, String)])
func testAccountBodyCarriesPromptAndModeOnlyWhenSet(_ model: String?, _ prompt: String?, _ mode: String?, _ body: String) async throws {
    let transport = ScriptedTransport(stream: { _ in sseResponse(finishedBytes(completeFrame)) }) { _ in errorReply(500) }
    let client = streamClient(transport)
    for try await _ in try await client.testAccount(id: 9, model: model, prompt: prompt, mode: mode, expectsTestResult: false) {}
    let sent = try #require(await transport.requests.first)
    #expect(String(decoding: sent.httpBody ?? Data(), as: UTF8.self) == body)
    withExtendedLifetime(client) {}
}

@Test(.timeLimit(.minutes(1))) func testAccountResultModeEOFAfterErrorThrowsIncomplete() async throws {
    let transport = ScriptedTransport(stream: { _ in sseResponse(finishedBytes(errorFrame)) }) { _ in errorReply(500) }
    let client = streamClient(transport)
    var types = [String]()
    do {
        for try await event in try await client.testAccount(id: 9, model: nil, expectsTestResult: true) { types.append(event.type) }
        Issue.record("Expected an incomplete stream")
    } catch let error as APIError { #expect(error == .incompleteStream) }
    #expect(types == ["error"])
    withExtendedLifetime(client) {}
}

@Test(.timeLimit(.minutes(1))) func testAccountLegacyModeWaitsForEOFAfterTestComplete() async throws {
    let (bytes, feed) = AsyncThrowingStream<Data, any Error>.makeStream()
    feed.yield(Data(completeFrame.utf8))
    let transport = ScriptedTransport(stream: { _ in sseResponse(bytes) }) { _ in errorReply(500) }
    let client = streamClient(transport)
    let stream = try await client.testAccount(id: 9, model: nil, expectsTestResult: false)
    let log = EventLog(), first = OpenGate()
    // The gate also opens when the stream ends or fails, so a wrong ending fails the test instead of hanging it.
    let consumer = Task {
        defer { Task { await first.open() } }
        for try await event in stream { await log.append(event); await first.open() }
        await log.end()
    }
    await first.wait()
    try await Task.sleep(for: .milliseconds(300))
    #expect(await log.ended == false)
    feed.finish()
    try await consumer.value
    #expect(await log.ended); #expect(await log.events.map(\.isSuccess) == [true])
    withExtendedLifetime(client) {}
}

@Test func testAccountOpenRejectionIsSurfacedOnce() async throws {
    let body = #"{"code":401,"reason":"INVALID_ADMIN_KEY"}"#
    let transport = ScriptedTransport(stream: { _ in
        HTTPStreamResponse(statusCode: 401, headers: ["content-type": "application/json"], bytes: finishedBytes(body))
    }) { _ in errorReply(500) }
    let invalidations = InvalidationRecorder()
    let client = streamClient(transport, onSessionInvalid: invalidations.handler)
    let error = try #require(await thrownAPIError { _ = try await client.testAccount(id: 9, model: nil, expectsTestResult: true) })
    #expect(error.action == .clearCredential); #expect(error.reason == "INVALID_ADMIN_KEY")
    #expect(invalidations.all.count == 1); #expect(invalidations.all.first?.reason == "INVALID_ADMIN_KEY")
    #expect(await transport.requests.count == 1)
}
