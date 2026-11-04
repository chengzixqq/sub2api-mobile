import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let firingEventJSON = #"{"id":77,"rule_id":41,"severity":"P1","status":"firing","title":"P1: 标准组错误率","fired_at":"2026-10-22T09:29:03.123456+08:00","silence":null}"#
private let olderEventJSON = #"{"id":76,"rule_id":41,"severity":"P2","status":"resolved","title":"P2: 内存","fired_at":"2026-10-22T01:29:03.123456Z"}"#
private let silenceJSON = #"{"id":9,"rule_id":41,"platform":"openai","group_id":12,"until":"2026-10-22T02:41:00Z","reason":"","created_at":"2026-10-22T01:41:00Z"}"#
private let silenceUntil = ServerTime.parseTimestamp("2026-10-22T02:41:00Z")!

private func alertsClient(_ transport: ScriptedTransport, credential: Credential = .adminKey("fixture-admin-key")) -> APIClient {
    APIClient(server: stubServer(), credential: credential, transport: transport, requestClock: .immediate)
}
private func queryItems(_ request: URLRequest?) -> [URLQueryItem] {
    request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
}
private func bodyText(_ request: URLRequest?) -> String? { request?.httpBody.map { String(decoding: $0, as: UTF8.self) } }

@Test func alertEventsSendsQueryInFixedOrder() async throws {
    let transport = ScriptedTransport { _ in okReply("[]") }
    let client = alertsClient(transport)
    _ = try await client.alertEvents(status: "firing", limit: 100)
    let cursor = try #require(AlertEventCursor(serverFiredAt: "2026-10-22T01:29:03.123456Z", id: 77))
    _ = try await client.alertEvents(status: "firing", timeRange: "24h", limit: 50, before: cursor, groupID: 12, platform: "openai")
    let sent = await transport.requests
    #expect(sent.count == 2 && sent.allSatisfy { $0.httpMethod == "GET" && $0.url?.path == "/api/v1/admin/ops/alert-events" })
    #expect(queryItems(sent[0]) == [URLQueryItem(name: "status", value: "firing"), URLQueryItem(name: "limit", value: "100")])
    #expect(sentHeader(sent[0], "Idempotency-Key") == nil && sent[0].timeoutInterval == RequestTimeout.read)
    #expect(queryItems(sent[1]).map(\.name) == ["status", "time_range", "limit", "before_fired_at", "before_id", "group_id", "platform"])
    #expect(queryItems(sent[1]).map(\.value) == ["firing", "24h", "50", "2026-10-22T01:29:03.123456Z", "77", "12", "openai"])
}

@Test func alertEventsOmitsBlankFilters() async throws {
    let transport = ScriptedTransport { _ in okReply("[]") }
    let client = alertsClient(transport)
    _ = try await client.alertEvents(status: "  ", timeRange: "", limit: 20, platform: " \n")
    _ = try await client.alertEvents(limit: 20, platform: " OpenAI ")
    let sent = await transport.requests
    #expect(queryItems(sent[0]).map(\.name) == ["limit"])
    #expect(queryItems(sent[1]) == [URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "platform", value: "OpenAI")])
}

@Test(arguments: [(0, 1), (-5, 1), (1, 1), (500, 500), (501, 500), (10_000, 500)])
func alertEventsClampsLimit(requested: Int, sent: Int) async throws {
    let transport = ScriptedTransport { _ in okReply("[]") }
    _ = try await alertsClient(transport).alertEvents(limit: requested)
    #expect(queryItems(await transport.requests.first) == [URLQueryItem(name: "limit", value: String(sent))])
}

@Test func alertEventsSendsCursorPairInUTC() async throws {
    let transport = ScriptedTransport { _ in okReply("[\(firingEventJSON)]") }
    let client = alertsClient(transport)
    let last = try #require(try await client.alertEvents(limit: 50).last)
    _ = try await client.alertEvents(limit: 50, before: last.cursor)
    let sent = await transport.requests
    let items = queryItems(sent[1])
    #expect(items.first { $0.name == "before_fired_at" }?.value == "2026-10-22T01:29:03.123456Z")
    #expect(items.first { $0.name == "before_id" }?.value == "77")
    let url = try #require(sent[1].url?.absoluteString)
    #expect(!url.contains("+") && !url.contains("%2B"))
    #expect(!queryItems(sent[0]).contains { $0.name.hasPrefix("before_") })
}

@Test(arguments: [0, -3])
func alertEventsRejectsNonPositiveGroupIDBeforeSending(groupID: Int) async throws {
    let transport = ScriptedTransport { _ in okReply("[]") }
    let error = await thrownAPIError { _ = try await alertsClient(transport).alertEvents(status: "firing", limit: 5, groupID: groupID) }
    #expect(error?.kind == .validation)
    #expect(await transport.requests.isEmpty)
}

@Test func alertEventsDecodeServerOrderAndSurfaceOpsDisabled() async throws {
    let transport = ScriptedTransport { _ in okReply(#"[\#(firingEventJSON),\#(olderEventJSON),{"severity":"P3"}]"#) }
    let events = try await alertsClient(transport).alertEvents(timeRange: "24h", limit: 50)
    #expect(events.map(\.id) == [77, 76])
    #expect(events[0].silenceSupported && !events[1].silenceSupported)
    #expect(events.map { $0.cursor?.firedAt } == ["2026-10-22T01:29:03.123456Z", "2026-10-22T01:29:03.123456Z"])
    let newer = try #require(events[0].cursor), older = try #require(events[1].cursor)
    #expect(older < newer)

    let disabled = ScriptedTransport { _ in errorReply(404, reason: "OPS_DISABLED") }
    let error = await thrownAPIError { _ = try await alertsClient(disabled).alertEvents(status: "firing", limit: 100) }
    #expect(error?.kind == .featureDisabled && error?.reason == "OPS_DISABLED")
    #expect(await disabled.requests.count == 1)
}

@Test func alertReadEndpointsUseTheirPaths() async throws {
    let rulesJSON = #"""
    [{"id":7,"name":"标准组错误率","description":"","enabled":true,"severity":"P1","metric_type":"error_rate","operator":">","threshold":5,
      "window_minutes":5,"sustained_minutes":2,"filters":{"group_id":12}},
     {"id":8,"name":"内存","enabled":true,"severity":"P2","metric_type":"memory_usage_percent","operator":">=","threshold":90,"filters":null}]
    """#
    let transport = ScriptedTransport { request in
        switch request.url?.path {
        case "/api/v1/admin/ops/alert-events/counts": okReply(#"{"firing":3,"by_severity":{"P0":1,"P1":2,"P2":0,"P3":0}}"#)
        case "/api/v1/admin/ops/alert-events/5": okReply(firingEventJSON)
        case "/api/v1/admin/ops/alert-rules": okReply(rulesJSON)
        default: errorReply(500)
        }
    }
    let client = alertsClient(transport)
    let counts = try await client.alertEventCounts()
    #expect(counts.firing == 3 && counts.count(severity: "P1") == 2)
    #expect(try await client.alertEvent(id: 5).id == 77)
    let rules = try await client.alertRules()
    #expect(rules.map(\.id) == [7, 8] && rules.allSatisfy { !$0.deleted })
    #expect(rules[1].comparison == ">=" && rules[1].windowMinutes == 0)
    let paths = await transport.requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" }
    #expect(paths == ["GET /api/v1/admin/ops/alert-events/counts", "GET /api/v1/admin/ops/alert-events/5", "GET /api/v1/admin/ops/alert-rules"])
    #expect(await thrownAPIError { _ = try await client.alertEvent(id: 0) }?.kind == .validation)
    #expect(await transport.requests.count == 3)

    let legacy = ScriptedTransport { _ in HTTPResponse(statusCode: 404, headers: ["Content-Type": "text/plain"], data: Data("404 page not found".utf8)) }
    #expect(await thrownAPIError { _ = try await alertsClient(legacy).alertEventCounts() }?.kind == .unsupported)
}

@Test func setAlertEventStatusSendsManualResolvedOnce() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"updated":true}"#) }
    let client = alertsClient(transport)
    try await client.setAlertEventStatus(id: 5)
    try await client.setAlertEventStatus(id: 5, status: "resolved")
    let sent = await transport.requests
    #expect(sent.map(\.httpMethod) == ["PUT", "PUT"] && sent.allSatisfy { $0.url?.path == "/api/v1/admin/ops/alert-events/5/status" })
    #expect(bodyText(sent[0]) == #"{"status":"manual_resolved"}"# && bodyText(sent[1]) == #"{"status":"resolved"}"#)
    let requestID = try #require(sentHeader(sent[0], "X-Request-ID"))
    #expect(UUID(uuidString: requestID) != nil && requestID == requestID.lowercased())
    #expect(sentHeader(sent[0], "Idempotency-Key") == nil && sent[0].timeoutInterval == RequestTimeout.unkeyedWrite)
    #expect(await thrownAPIError { try await client.setAlertEventStatus(id: 5, status: "firing") }?.kind == .validation)
    #expect(await thrownAPIError { try await client.setAlertEventStatus(id: 0) }?.kind == .validation)
    #expect(await transport.requests.count == 2)
}

private let unretriedFailures: [(ScriptStep, APIError.Kind)] = [(.fail(URLError(.timedOut)), .transport), (.reply(errorReply(502)), .temporary)]

@Test(arguments: unretriedFailures)
func alertStatusWriteIsNotRetried(step: ScriptStep, kind: APIError.Kind) async throws {
    let transport = ScriptedTransport(script: [step, .reply(okReply(#"{"updated":true}"#))])
    let error = await thrownAPIError { try await alertsClient(transport).setAlertEventStatus(id: 5) }
    #expect(error?.kind == kind)
    #expect(await transport.requests.count == 1)
}

@Test func createAlertSilenceBodyBytes() async throws {
    let transport = ScriptedTransport { _ in okReply(silenceJSON) }
    let client = alertsClient(transport)
    let created = try await client.createAlertSilence(ruleID: 41, platform: nil, groupID: nil, until: silenceUntil)
    _ = try await client.createAlertSilence(ruleID: 41, platform: " openai ", groupID: 12, until: silenceUntil)
    _ = try await client.createAlertSilence(ruleID: 41, platform: "openai", groupID: 12, until: silenceUntil.addingTimeInterval(0.75))
    let sent = await transport.requests
    #expect(sent.count == 3 && sent.allSatisfy { $0.httpMethod == "POST" && $0.url?.path == "/api/v1/admin/ops/alert-silences" })
    #expect(sent.allSatisfy { sentHeader($0, "Idempotency-Key") == nil })
    #expect(bodyText(sent[0]) == #"{"group_id":null,"platform":"","rule_id":41,"until":"2026-10-22T02:41:00Z"}"#)
    #expect(bodyText(sent[1]) == #"{"group_id":12,"platform":"openai","rule_id":41,"until":"2026-10-22T02:41:00Z"}"#)
    let fractional = try #require(bodyText(sent[2]))
    #expect(!fractional.contains("region") && !fractional.contains("reason"))
    let until = try #require(fractional.firstRange(of: #""until":""#).map { fractional[$0.upperBound...] })
    #expect(!until.contains(".") && until.hasSuffix(#"Z"}"#))
    #expect(created == AlertSilence(id: 9, ruleID: 41, platform: "openai", groupID: 12, until: silenceUntil))
}

@Test func createAlertSilenceValidatesLocally() async throws {
    let transport = ScriptedTransport { _ in okReply(silenceJSON) }
    let client = alertsClient(transport)
    let invalid: [(Int, Int?)] = [(0, nil), (-1, 12), (41, 0)]
    for (ruleID, groupID) in invalid {
        let error = await thrownAPIError { _ = try await client.createAlertSilence(ruleID: ruleID, platform: "openai", groupID: groupID, until: silenceUntil) }
        #expect(error?.kind == .validation)
    }
    #expect(await transport.requests.isEmpty)
}

@Test func updateAndDeleteSilenceRequests() async throws {
    let transport = ScriptedTransport { request in request.httpMethod == "DELETE" ? okReply(#"{"deleted":true}"#) : okReply(silenceJSON) }
    let client = alertsClient(transport)
    let updated = try await client.updateAlertSilence(id: 9, until: silenceUntil)
    try await client.deleteAlertSilence(id: 9)
    let sent = await transport.requests
    #expect(sent.map(\.httpMethod) == ["PUT", "DELETE"] && sent.allSatisfy { $0.url?.path == "/api/v1/admin/ops/alert-silences/9" })
    #expect(bodyText(sent[0]) == #"{"until":"2026-10-22T02:41:00Z"}"# && sent[1].httpBody == nil)
    #expect(sent.allSatisfy { sentHeader($0, "Idempotency-Key") == nil })
    #expect(updated.id == 9 && updated.until == silenceUntil)
    #expect(await thrownAPIError { _ = try await client.updateAlertSilence(id: 0, until: silenceUntil) }?.kind == .validation)
    #expect(await thrownAPIError { try await client.deleteAlertSilence(id: 0) }?.kind == .validation)
    #expect(await transport.requests.count == 2)

    let missing = ScriptedTransport { _ in errorReply(404, reason: "OPS_ALERT_SILENCE_NOT_FOUND") }
    let error = await thrownAPIError { try await alertsClient(missing).deleteAlertSilence(id: 9) }
    #expect(error?.kind == .notFound && error?.reason == "OPS_ALERT_SILENCE_NOT_FOUND")
}

@Test func silenceWriteResendsOnceAfterTokenRefresh() async throws {
    let transport = ScriptedTransport { request in
        if isRefresh(request) { return okReply(stubRefreshJSON) }
        return sentHeader(request, "Authorization") == "Bearer old-access" ? errorReply(401, reason: "TOKEN_EXPIRED") : okReply(silenceJSON)
    }
    let silence = try await alertsClient(transport, credential: stubTokens())
        .createAlertSilence(ruleID: 41, platform: "openai", groupID: 12, until: silenceUntil)
    #expect(silence.id == 9)
    let sent = await transport.requests
    let posts = sent.filter { !isRefresh($0) }
    #expect(posts.count == 2 && sent.filter(isRefresh).count == 1)
    #expect(posts[0].httpBody == posts[1].httpBody)
    #expect(sentHeader(posts[0], "X-Request-ID") != nil && sentHeader(posts[0], "X-Request-ID") == sentHeader(posts[1], "X-Request-ID"))
    #expect(sentHeader(posts[1], "Authorization") == "Bearer new-access")
}
