import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import Sub2Core

// S5-03: 50 §0.4 batch endpoint with the R06 resend, and the 0.4.4 per-account fallback.

private let memberReplyJSON = #"{"group_id":3,"results":[{"account_id":11,"action":"add","status":"added","priority":50}],"counts":{"account_count":2,"active_account_count":2,"rate_limited_account_count":0}}"#
private let legacyConflictJSON = #"{"code":409,"reason":"MIXED_CHANNEL_WARNING","error":"mixed_channel_warning","message":"mixed","metadata":{"group_id":"5","group_name":"高级组","current_platform":"Antigravity","other_platform":"Anthropic"}}"#
private let legacyMixed = GroupMemberMixedChannel(currentPlatform: "Antigravity", otherPlatform: "Anthropic")

private func memberClient(_ transport: ScriptedTransport, clock: RequestClock = .immediate) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: clock)
}
private func memberBody(_ request: URLRequest?) -> String { String(decoding: request?.httpBody ?? Data(), as: UTF8.self) }
private func memberAdds(_ ids: some Sequence<Int>) throws -> GroupMemberBatchRequest {
    try GroupMemberBatchRequest(add: ids.map { GroupMemberAdd(accountID: $0) })
}
/// The ids a batch body adds.
private func memberSentAdds(_ request: URLRequest) -> [Int] {
    let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
    return (body?["add"] as? [[String: Any]] ?? []).compactMap { $0["account_id"] as? Int }
}
/// Every account a batch body names, answered the way the server orders them.
private func memberEcho(_ request: URLRequest, active: Int? = nil) -> HTTPResponse {
    let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
    let rows = memberSentAdds(request).map { #"{"account_id":\#($0),"action":"add","status":"added","priority":50}"# }
        + (body?["remove"] as? [Int] ?? []).map { #"{"account_id":\#($0),"action":"remove","status":"removed","priority":1}"# }
    let counts = active.map { #","counts":{"account_count":9,"active_account_count":\#($0),"rate_limited_account_count":0}"# } ?? ""
    return okReply(#"{"group_id":3,"results":[\#(rows.joined(separator: ","))]\#(counts)}"#)
}
/// Lets a transport or clock closure reach the client it belongs to.
private final class MemberClientBox: Sendable {
    private let stored = Mutex<APIClient?>(nil)
    func set(_ client: APIClient) { stored.withLock { $0 = client } }
    func cancelAll() async {
        let client = stored.withLock { $0 }
        await client?.cancelAll()
    }
    func suspend() async {
        let client = stored.withLock { $0 }
        await client?.suspend()
    }
}

private func legacyAccountJSON(_ id: Int, groups: [Int], platform: String = "anthropic") -> String {
    #"{"id":\#(id),"name":"账号\#(id)","platform":"\#(platform)","type":"oauth","status":"active","schedulable":true,"group_ids":[\#(groups.map(String.init).joined(separator: ","))]}"#
}
/// GET admin/accounts/:id runs `beforeGet`, then answers from `groups` (404 ACCOUNT_NOT_FOUND when missing); PUT answers with
/// `put`; the mixed-channel pre-check with `precheck`.
private func legacyTransport(groups: [Int: [Int]], platform: String = "anthropic",
                             beforeGet: @escaping @Sendable (Int) async throws -> Void = { _ in },
                             put: @escaping @Sendable (Int, URLRequest) async throws -> HTTPResponse = { id, _ in okReply(legacyAccountJSON(id, groups: [])) },
                             precheck: @escaping @Sendable () -> HTTPResponse = { okReply(#"{"has_risk":false}"#) }) -> ScriptedTransport {
    ScriptedTransport { request in
        if request.url?.path.hasSuffix("check-mixed-channel") == true { return precheck() }
        let id = Int(request.url?.lastPathComponent ?? "") ?? 0
        switch request.httpMethod {
        case "GET":
            try await beforeGet(id)
            return groups[id].map { okReply(legacyAccountJSON(id, groups: $0, platform: platform)) } ?? errorReply(404, reason: "ACCOUNT_NOT_FOUND")
        case "PUT": return try await put(id, request)
        default: return errorReply(500)
        }
    }
}
/// “METHOD path” for each request, with the body when `bodies`.
private func legacyLines(_ transport: ScriptedTransport, bodies: Bool = true) async -> [String] {
    await transport.requests.map { request in
        let line = "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
        guard bodies, let body = request.httpBody else { return line }
        return line + " " + String(decoding: body, as: UTF8.self)
    }
}
private func legacyRun(_ transport: ScriptedTransport, groupID: Int = 5, _ request: GroupMemberBatchRequest) async throws -> GroupMemberBatchResult {
    try await GroupMembersLegacyExecutor(client: memberClient(transport), sendsIdempotencyKey: false).run(groupID: groupID, request)
}

// MARK: - Batch endpoint

@Test func memberBatchPostsBodyWithoutIdempotencyKey() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(memberReplyJSON))])
    let request = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 11)], remove: [13])
    let result = try await memberClient(transport).groupMemberBatch(groupID: 3, request)
    let sent = await transport.requests, body = try request.requestBody()
    #expect(sent.count == 1)
    #expect(sent.first?.httpMethod == "POST")
    #expect(sent.first?.url?.absoluteString == "https://requests.example.invalid/api/v1/admin/groups/3/accounts/batch")
    #expect(sent.first?.httpBody == body)
    #expect(sentHeader(sent.first, "Idempotency-Key") == nil)
    let requestID = try #require(sentHeader(sent.first, "X-Request-ID"))
    #expect(UUID(uuidString: requestID) != nil && requestID == requestID.lowercased())
    // The removal of 13 has no answer: kept as unconfirmed, never dropped.
    #expect(result == GroupMemberBatchResult(groupID: 3, results: [
        GroupMemberResultItem(accountID: 11, action: .add, status: .added, priority: 50),
        GroupMemberResultItem(accountID: 13, action: .remove, status: .failed, reason: GroupMemberReason.notConfirmed)
    ], counts: GroupAccountCounts(accountCount: 2, activeAccountCount: 2)))
}

@Test func memberBatchRejectsInvalidGroupBeforeSending() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(memberReplyJSON))])
    let request = try memberAdds([11])
    let error = try #require(await thrownAPIError { _ = try await memberClient(transport).groupMemberBatch(groupID: 0, request) })
    #expect(error.kind == .validation && error.localizedDescription == "无效的对象编号。")
    #expect(await transport.requests.isEmpty)
}

@Test func memberBatchRetriesTransportFailureOnceWithSameBytes() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(memberReplyJSON))])
    let recorder = SleepRecorder()
    let result = try await memberClient(transport, clock: .recording(recorder)).groupMemberBatch(groupID: 3, try memberAdds([11]))
    let sent = await transport.requests
    #expect(result.added == 1)
    #expect(sent.count == 2 && sent[0].httpBody == sent[1].httpBody)
    #expect(sentHeader(sent[0], "X-Request-ID") != nil && sentHeader(sent[0], "X-Request-ID") == sentHeader(sent[1], "X-Request-ID"))
    #expect(sent.allSatisfy { sentHeader($0, "Idempotency-Key") == nil })
    #expect(await recorder.durations == [.seconds(1)])
}

@Test func memberBatchGivesUpAfterOneRetry() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.networkConnectionLost))])
    let request = try memberAdds([11])
    let error = try #require(await thrownAPIError { _ = try await memberClient(transport).groupMemberBatch(groupID: 3, request) })
    #expect(error.kind == .transport && error.statusCode == nil)
    #expect(await transport.requests.count == 2)
}

@Test(arguments: [(502, nil, 2), (504, nil, 2), (503, nil, 2), (408, nil, 2), (400, "EMPTY_MEMBER_CHANGE", 1), (403, "FORBIDDEN", 1),
                  (404, "GROUP_NOT_FOUND", 1), (409, nil, 1), (429, nil, 1), (500, "GROUP_REPOSITORY_UNSUPPORTED", 1), (500, nil, 1),
                  (503, "ACCOUNT_STATS_UNAVAILABLE", 1)] as [(Int, String?, Int)])
func memberBatchRetriesGatewayStatusesOnly(status: Int, reason: String?, sends: Int) async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(status, reason: reason))])
    let request = try memberAdds([11])
    let error = try #require(await thrownAPIError { _ = try await memberClient(transport).groupMemberBatch(groupID: 3, request) })
    #expect(error.statusCode == status && error.reason == reason)
    #expect(await transport.requests.count == sends)
}

/// After a first send that may have run, a resend refused before the handler or answered by something other than the server's
/// JSON says nothing about it (00 §2.5.4 step 2): the first error stands.
@Test(arguments: [ScriptStep.fail(URLError(.timedOut)), .reply(errorReply(502))],
      [errorReply(429, reason: "RATE_LIMITED"), errorReply(403, reason: "FORBIDDEN"), errorReply(423), errorReply(503, reason: "STEP_UP_UNAVAILABLE"),
       HTTPResponse(statusCode: 404, data: Data("404 page not found".utf8)), HTTPResponse(statusCode: 400, data: Data("<html>".utf8))])
func memberBatchResendThatSaysNothingKeepsFirstError(first: ScriptStep, resend: HTTPResponse) async throws {
    let transport = ScriptedTransport(script: [first, .reply(resend)])
    let request = try memberAdds([11])
    let error = try #require(await thrownAPIError { _ = try await memberClient(transport).groupMemberBatch(groupID: 3, request) })
    #expect(error.statusCode == (try? first.resolve())?.statusCode)
    #expect(error.statusCode != nil || error.kind == .transport)
    #expect(await transport.requests.count == 2)
}

@Test func memberBatchResendBusinessAnswerSettles() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(errorReply(404, reason: "GROUP_NOT_FOUND"))])
    let request = try memberAdds([11])
    let error = try #require(await thrownAPIError { _ = try await memberClient(transport).groupMemberBatch(groupID: 3, request) })
    #expect(error.statusCode == 404 && error.reason == "GROUP_NOT_FOUND")
}

@Test func memberBatchResendThatNeverLeftKeepsFirstError() async throws {
    // The access expires during the wait and its refresh fails for a transient reason: the resend is never sent.
    let clock = ManualClock()
    let transport = ScriptedTransport { _ in throw URLError(.timedOut) }
    let client = APIClient(server: stubServer(), credential: stubTokens(expiresAt: clock.now().addingTimeInterval(120)), deviceID: stubDeviceID,
                           transport: transport, requestClock: RequestClock(now: { clock.now() }, sleep: { _ in clock.advance(by: 200) }, jitter: { .zero }))
    let request = try memberAdds([11])
    let error = try #require(await thrownAPIError { _ = try await client.groupMemberBatch(groupID: 3, request) })
    #expect(error.kind == .transport && error != .refreshDeferred)
    #expect(await transport.requests(path: "/accounts/batch").count == 1)
    #expect(await transport.requests.filter(isRefresh).count == 1)
}

@Test func memberBatchDoesNotRetryWhileSuspendedOrAfterSessionChange() async throws {
    let request = try memberAdds([11])
    // Already in the background: no wait starts, the first answer stands.
    let quiet = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(memberReplyJSON))])
    let background = memberClient(quiet)
    await background.suspend()
    let first = try #require(await thrownAPIError { _ = try await background.groupMemberBatch(groupID: 3, request) })
    #expect(first.kind == .transport)
    #expect(await quiet.requests.count == 1)

    // Sent to the background during the wait.
    let sleeping = OpenGate()
    let waiting = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(memberReplyJSON))])
    let client = memberClient(waiting, clock: RequestClock(sleep: { _ in await sleeping.open(); try await Task.sleep(for: .seconds(60)) }, jitter: { .zero }))
    let pending = Task { try await client.groupMemberBatch(groupID: 3, request) }
    let watcher = Task { _ = try? await pending.value; await sleeping.open() }
    await sleeping.wait()
    await client.suspend()
    let interrupted = try #require(await thrownAPIError { _ = try await pending.value })
    #expect(interrupted.kind == .transport)
    _ = await watcher.value
    #expect(await waiting.requests.count == 1)

    // Another session began during the wait.
    let box = MemberClientBox()
    let ended = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(memberReplyJSON))])
    let ending = memberClient(ended, clock: .recording(SleepRecorder(), onSleep: { _ in await box.cancelAll() }))
    box.set(ending)
    await #expect(throws: CancellationError.self) { try await ending.groupMemberBatch(groupID: 3, request) }
    #expect(await ended.requests.count == 1)
}

@Test func memberBatchSendsOver200InOrderAndMerges() async throws {
    let calls = CallCounter()
    let transport = ScriptedTransport { request in memberEcho(request, active: calls.next() == 1 ? 100 : 7) }
    let result = try await memberClient(transport).groupMemberBatch(groupID: 3, try memberAdds(1...250))
    let sent = await transport.requests
    #expect(sent.map(memberSentAdds) == [Array(1...200), Array(201...250)])
    #expect(Set(sent.compactMap { sentHeader($0, "X-Request-ID") }).count == 2)
    #expect(result.results.map(\.accountID) == Array(1...250) && result.added == 250)
    #expect(result.counts?.activeAccountCount == 7)
}

@Test func memberBatchLaterBatchFailureMarksRestNotDelivered() async throws {
    let request = try memberAdds(1...450)
    // Batch 2 is lost twice (sent, then resent once): unconfirmed; batch 3 is never sent.
    let calls = CallCounter()
    let lost = ScriptedTransport { request in
        guard calls.next() == 1 else { throw URLError(.timedOut) }
        return memberEcho(request, active: 5)
    }
    let result = try await memberClient(lost).groupMemberBatch(groupID: 3, request)
    #expect(await lost.requests.count == 3)
    #expect(result.results.map(\.accountID) == Array(1...450))
    #expect(result.results.prefix(200).allSatisfy { $0.status == .added })
    #expect(result.results[200..<400].allSatisfy { $0.status == .failed && $0.reason == GroupMemberReason.notConfirmed })
    #expect(result.results.suffix(50).allSatisfy { $0.status == .failed && $0.reason == GroupMemberReason.notDelivered })
    #expect(result.counts == nil)

    // Batch 2 refused outright: its own reason, the rest not delivered.
    let refusing = CallCounter()
    let refused = ScriptedTransport { request in refusing.next() == 1 ? memberEcho(request) : errorReply(403, reason: "FORBIDDEN") }
    let marked = try await memberClient(refused).groupMemberBatch(groupID: 3, request)
    #expect(await refused.requests.count == 2)
    #expect(marked.results[200..<400].allSatisfy { $0.status == .failed && $0.reason == "FORBIDDEN" })
    #expect(marked.results.suffix(50).allSatisfy { $0.reason == GroupMemberReason.notDelivered })

    // Batch 2 lost, then its resend refused before the handler or answered by a proxy page: still unconfirmed.
    for resend in [errorReply(429, reason: "RATE_LIMITED"), HTTPResponse(statusCode: 404, data: Data("404 page not found".utf8))] {
        let sending = CallCounter()
        let limited = ScriptedTransport { request in
            switch sending.next() {
            case 1: return memberEcho(request)
            case 2: throw URLError(.timedOut)
            default: return resend
            }
        }
        let unconfirmed = try await memberClient(limited).groupMemberBatch(groupID: 3, request)
        #expect(await limited.requests.count == 3)
        #expect(unconfirmed.results[200..<400].allSatisfy { $0.status == .failed && $0.reason == GroupMemberReason.notConfirmed })
        #expect(unconfirmed.results.suffix(50).allSatisfy { $0.reason == GroupMemberReason.notDelivered })
    }

    // The first batch's failure is thrown as it is.
    let gone = ScriptedTransport(script: [.reply(errorReply(404, reason: "GROUP_NOT_FOUND"))])
    let error = try #require(await thrownAPIError { _ = try await memberClient(gone).groupMemberBatch(groupID: 3, request) })
    #expect(error.statusCode == 404 && error.reason == "GROUP_NOT_FOUND")
    #expect(await gone.requests.count == 1)
}

@Test func memberRetryMarksWhatMayHaveRun() {
    let transport = APIError(kind: .transport, message: "无法连接站点")
    #expect(GroupMemberRetry.retriesOnce(after: transport) && !GroupMemberRetry.retriesOnce(after: .refreshDeferred))
    #expect(!GroupMemberRetry.retriesOnce(after: APIError.server(status: 502, reason: nil).withSecurityOutcome(.cancelled)))
    let written: [(any Error, String)] = [
        (transport, GroupMemberReason.notConfirmed), (APIError.server(status: 500, reason: nil), GroupMemberReason.notConfirmed),
        (APIError.server(status: 408, reason: nil), GroupMemberReason.notConfirmed), (APIError.invalidResponse, GroupMemberReason.notConfirmed),
        (APIError.refreshDeferred, GroupMemberReason.notDelivered), (APIError.server(status: 403, reason: "FORBIDDEN"), "FORBIDDEN"),
        (APIError.server(status: 409, reason: nil), GroupMemberReason.notDelivered),
        (KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil), GroupMemberReason.notConfirmed),
        (KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil), GroupMemberReason.notDelivered)
    ]
    for (error, reason) in written { #expect(GroupMemberRetry.unfinishedReason(error, mayHaveWritten: true) == reason) }
    // A failed read changed nothing.
    #expect(GroupMemberRetry.unfinishedReason(transport, mayHaveWritten: false) == GroupMemberReason.notDelivered)
    #expect(GroupMemberRetry.unfinishedReason(APIError.server(status: 500, reason: nil), mayHaveWritten: false) == GroupMemberReason.notDelivered)
    #expect(GroupMemberRetry.unfinishedReason(APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE"), mayHaveWritten: false) == "SERVICE_UNAVAILABLE")
    // A resend's error that says nothing about a first send that may have run.
    let silent: [APIError] = [.refreshDeferred, .stationMismatch, APIError.server(status: 429, reason: "RATE_LIMITED"),
                              APIError.server(status: 401, reason: nil), APIError.server(status: 404, envelope: nil)]
    let telling: [APIError] = [transport, .invalidResponse, APIError.server(status: 404, reason: "GROUP_NOT_FOUND"),
                               APIError.server(status: 400, reason: "INVALID_GROUP_ID"), APIError.server(status: 500, reason: nil)]
    #expect(silent.allSatisfy(GroupMemberRetry.saysNothingAboutFirstSend))
    #expect(!telling.contains(where: GroupMemberRetry.saysNothingAboutFirstSend))
}

// MARK: - 0.4.4 fallback

@Test func legacyRunsGetThenPutWithOnlyGroupIDs() async throws {
    let transport = legacyTransport(groups: [11: [3], 12: [5, 3], 13: [5, 7]])
    let request = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 11), GroupMemberAdd(accountID: 12)], remove: [13])
    let result = try await legacyRun(transport, request)
    #expect(await legacyLines(transport) == ["GET /api/v1/admin/accounts/11", #"PUT /api/v1/admin/accounts/11 {"group_ids":[3,5]}"#, "GET /api/v1/admin/accounts/12",
                                             "GET /api/v1/admin/accounts/13", #"PUT /api/v1/admin/accounts/13 {"group_ids":[7]}"#])
    #expect(result == GroupMemberBatchResult(groupID: 5, results: [GroupMemberResultItem(accountID: 11, action: .add, status: .added),
                                                                   GroupMemberResultItem(accountID: 12, action: .add, status: .unchanged),
                                                                   GroupMemberResultItem(accountID: 13, action: .remove, status: .removed)], counts: nil))
    #expect(await transport.requests.allSatisfy { sentHeader($0, "Idempotency-Key") == nil })
}

@Test func legacyKeyedPutsUseOneFreshKeyPerAccount() async throws {
    let keys = [UUID(), UUID()]
    let counter = CallCounter()
    let transport = legacyTransport(groups: [11: [], 12: [3]])
    _ = try await GroupMembersLegacyExecutor(client: memberClient(transport), sendsIdempotencyKey: true, makeKey: { keys[counter.next() - 1] })
        .run(groupID: 5, try memberAdds([11, 12]))
    let puts = await transport.requests.filter { $0.httpMethod == "PUT" }
    #expect(puts.map { sentHeader($0, "Idempotency-Key") } == keys.map { $0.uuidString.lowercased() })
    let unused = CallCounter()
    _ = try await GroupMembersLegacyExecutor(client: memberClient(legacyTransport(groups: [11: []])), sendsIdempotencyKey: false,
                                             makeKey: { _ = unused.next(); return UUID() }).run(groupID: 5, try memberAdds([11]))
    #expect(unused.next() == 1)
}

@Test func legacyMapsMixedChannelConflictAndConfirm() async throws {
    let transport = legacyTransport(groups: [11: [3], 12: []], platform: "antigravity", put: { id, _ in
        id == 11 ? HTTPResponse(statusCode: 409, data: Data(legacyConflictJSON.utf8)) : okReply(legacyAccountJSON(id, groups: [5]))
    })
    let result = try await legacyRun(transport, try memberAdds([11, 12]))
    #expect(result.results == [GroupMemberResultItem(accountID: 11, action: .add, status: .failed, reason: GroupMemberReason.mixedChannelRisk, details: legacyMixed),
                               GroupMemberResultItem(accountID: 12, action: .add, status: .added)])
    #expect(await transport.requests(path: "check-mixed-channel").isEmpty)
    let confirming = legacyTransport(groups: [11: [3]])
    _ = try await legacyRun(confirming, try memberAdds([11]).confirmingMixedChannel())
    #expect(await legacyLines(confirming).last == #"PUT /api/v1/admin/accounts/11 {"confirm_mixed_channel_risk":true,"group_ids":[3,5]}"#)
}

@Test func legacyOldServerConflictAsksMixedChannelPrecheck() async throws {
    let oldConflict = HTTPResponse(statusCode: 409, data: Data(#"{"error":"mixed_channel_warning","message":"Group 高级组 mixes channels"}"#.utf8))
    let risky = okReply(#"{"has_risk":true,"details":{"group_id":5,"group_name":"高级组","current_platform":"Antigravity","other_platform":"Anthropic"}}"#)
    let transport = legacyTransport(groups: [11: [3]], platform: "antigravity", put: { _, _ in oldConflict }, precheck: { risky })
    let result = try await legacyRun(transport, try memberAdds([11]))
    #expect(result.results == [GroupMemberResultItem(accountID: 11, action: .add, status: .failed, reason: GroupMemberReason.mixedChannelRisk, details: legacyMixed)])
    let precheck = await transport.requests(path: "check-mixed-channel")
    #expect(precheck.map { memberBody($0) } == [#"{"account_id":11,"group_ids":[3,5],"platform":"antigravity"}"#])

    // No risk after all: an unexplained 409 before anything was written is thrown.
    let noRisk = legacyTransport(groups: [11: [3]], platform: "antigravity", put: { _, _ in oldConflict })
    let request = try memberAdds([11])
    let error = try #require(await thrownAPIError { _ = try await legacyRun(noRisk, request) })
    #expect(error.statusCode == 409 && error.reason == nil)
}

@Test func legacyMissingAccountFailsAsNotFound() async throws {
    let transport = legacyTransport(groups: [12: [], 13: [5]], put: { id, _ in
        id == 12 ? errorReply(404, reason: "ACCOUNT_NOT_FOUND") : okReply(legacyAccountJSON(id, groups: []))
    })
    let request = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 11), GroupMemberAdd(accountID: 12)], remove: [13])
    let result = try await legacyRun(transport, request)
    #expect(result.results.map(\.status) == [.failed, .failed, .removed])
    #expect(result.results.map(\.reason) == [GroupMemberReason.accountNotFound, GroupMemberReason.accountNotFound, nil])
    #expect(await transport.requests.filter { $0.httpMethod == "PUT" }.map { $0.url?.path } == ["/api/v1/admin/accounts/12", "/api/v1/admin/accounts/13"])
}

@Test func legacyStopsOnRequestLevelFailure() async throws {
    let request = try GroupMemberBatchRequest(add: [GroupMemberAdd(accountID: 11), GroupMemberAdd(accountID: 12)], remove: [13])
    let groups = [11: [3], 12: [3], 13: [5]]
    // ① Nothing written yet: thrown as it is, the unkeyed PUT sent once.
    let first = legacyTransport(groups: groups, put: { _, _ in throw URLError(.timedOut) })
    let thrown = try #require(await thrownAPIError { _ = try await legacyRun(first, request) })
    #expect(thrown.kind == .transport)
    #expect(await legacyLines(first, bodies: false) == ["GET /api/v1/admin/accounts/11", "PUT /api/v1/admin/accounts/11"])

    // ② After a change: the lost PUT is unconfirmed, the rest not delivered and not read.
    let second = legacyTransport(groups: groups, put: { id, _ in
        guard id == 11 else { throw URLError(.timedOut) }
        return okReply(legacyAccountJSON(id, groups: [3, 5]))
    })
    let stopped = try await legacyRun(second, request)
    #expect(stopped.results.map(\.status) == [.added, .failed, .failed])
    #expect(stopped.results.map(\.reason) == [nil, GroupMemberReason.notConfirmed, GroupMemberReason.notDelivered])
    #expect(await second.requests(path: "/accounts/13").isEmpty)

    // ③ A refusal keeps its reason.
    let third = legacyTransport(groups: groups, put: { id, _ in id == 11 ? okReply(legacyAccountJSON(id, groups: [3, 5])) : errorReply(403, reason: "FORBIDDEN") })
    let refused = try await legacyRun(third, request)
    #expect(refused.results.map(\.reason) == [nil, "FORBIDDEN", GroupMemberReason.notDelivered])

    // ④ A keyed PUT left without an answer is unconfirmed too.
    let fourth = legacyTransport(groups: groups, put: { id, _ in
        guard id == 11 else { throw URLError(.timedOut) }
        return okReply(legacyAccountJSON(id, groups: [3, 5]))
    })
    let keyed = try await GroupMembersLegacyExecutor(client: memberClient(fourth), sendsIdempotencyKey: true).run(groupID: 5, request)
    #expect(keyed.results.map(\.reason) == [nil, GroupMemberReason.notConfirmed, GroupMemberReason.notDelivered])
    #expect(await fourth.requests(path: "/accounts/12").filter { $0.httpMethod == "PUT" }.count == 3)
}

@Test func legacyPlanKeepsOtherGroupsAndOrder() async throws {
    #expect(GroupMembersLegacyPlan.groupIDs([3, 7], groupID: 5, action: .add) == [3, 7, 5])
    #expect(GroupMembersLegacyPlan.groupIDs([5, 3, 7], groupID: 5, action: .remove) == [3, 7])
    #expect(GroupMembersLegacyPlan.groupIDs([3, 5], groupID: 5, action: .add) == nil)
    #expect(GroupMembersLegacyPlan.groupIDs([3], groupID: 5, action: .remove) == nil)
    #expect(GroupMembersLegacyPlan.currentGroupIDs(of: UpstreamAccount(id: 11, name: "a", platform: "anthropic", type: "oauth", groupIDs: [3, 3, 0, 7])) == [3, 7])
    // A detail without group_ids still names its groups: they are kept, not cleared.
    let detail = #"{"id":11,"name":"a","platform":"anthropic","type":"oauth","status":"active","schedulable":true,"groups":[{"id":3,"name":"默认"}]}"#
    let transport = ScriptedTransport { request in request.httpMethod == "GET" ? okReply(detail) : okReply(legacyAccountJSON(11, groups: [3, 5])) }
    _ = try await legacyRun(transport, try memberAdds([11]))
    #expect(memberBody(await transport.requests.last) == #"{"group_ids":[3,5]}"#)
}

@Test func legacyStopsWhenSessionChanges() async throws {
    let box = MemberClientBox()
    let transport = legacyTransport(groups: [11: [], 12: []], put: { id, _ in
        await box.cancelAll()
        return okReply(legacyAccountJSON(id, groups: [5]))
    })
    let client = memberClient(transport)
    box.set(client)
    let request = try memberAdds([11, 12])
    await #expect(throws: CancellationError.self) {
        _ = try await GroupMembersLegacyExecutor(client: client, sendsIdempotencyKey: false).run(groupID: 5, request)
    }
    #expect(await transport.requests(path: "/accounts/12").isEmpty)
}

@Test func legacyKeepsWhatChangedWhenTheBackgroundStopsARead() async throws {
    let request = try memberAdds([11, 12, 13, 14])
    let groups = [11: [3], 12: [], 13: [], 14: []]
    // ① The App goes to the background while account 13's detail is in flight: the read is cancelled, the session stays.
    let box = MemberClientBox()
    let inFlight = legacyTransport(groups: groups, beforeGet: { id in if id == 13 { await box.suspend() } })
    let client = memberClient(inFlight)
    box.set(client)
    let stopped = try await GroupMembersLegacyExecutor(client: client, sendsIdempotencyKey: false).run(groupID: 5, request)
    #expect(stopped.results.map(\.status) == [.added, .added, .failed, .failed])
    #expect(stopped.results.map(\.reason) == [nil, nil, GroupMemberReason.notDelivered, GroupMemberReason.notDelivered])
    #expect(await inFlight.requests(path: "/accounts/14").isEmpty)

    // ② Account 13's detail is lost in the background: its automatic read retry does not wait.
    let quiet = MemberClientBox()
    let lost = legacyTransport(groups: groups, beforeGet: { id in if id == 13 { throw URLError(.timedOut) } }, put: { id, _ in
        if id == 12 { await quiet.suspend() }
        return okReply(legacyAccountJSON(id, groups: [5]))
    })
    let background = memberClient(lost)
    quiet.set(background)
    let marked = try await GroupMembersLegacyExecutor(client: background, sendsIdempotencyKey: false).run(groupID: 5, request)
    #expect(marked.results.map(\.reason) == [nil, nil, GroupMemberReason.notDelivered, GroupMemberReason.notDelivered])
    #expect(await lost.requests(path: "/accounts/13").count == 1)

    // ③ Nothing changed yet: the run ends as cancelled.
    let early = MemberClientBox()
    let first = legacyTransport(groups: groups, beforeGet: { id in if id == 11 { await early.suspend() } })
    let idle = memberClient(first)
    early.set(idle)
    await #expect(throws: CancellationError.self) {
        _ = try await GroupMembersLegacyExecutor(client: idle, sendsIdempotencyKey: false).run(groupID: 5, request)
    }
    #expect(await first.requests.count == 1)
}

@Test func legacyFallbackTriggerIsRepositoryUnsupportedOnly() async throws {
    #expect(GroupMembersLegacyExecutor.isFallbackTrigger(APIError.server(status: 500, reason: "GROUP_REPOSITORY_UNSUPPORTED")))
    #expect(!GroupMembersLegacyExecutor.isFallbackTrigger(APIError.server(status: 500, reason: "INTERNAL_ERROR")))
    #expect(!GroupMembersLegacyExecutor.isFallbackTrigger(APIError.server(status: 404, envelope: nil)))
    #expect(!GroupMembersLegacyExecutor.isFallbackTrigger(APIError(kind: .transport, message: "无法连接站点")))
    #expect(!GroupMembersLegacyExecutor.isFallbackTrigger(CancellationError()))
    let transport = ScriptedTransport(script: [.reply(errorReply(500, reason: "GROUP_REPOSITORY_UNSUPPORTED"))])
    let request = try memberAdds([11])
    let error = try #require(await thrownAPIError { _ = try await memberClient(transport).groupMemberBatch(groupID: 3, request) })
    #expect(GroupMembersLegacyExecutor.isFallbackTrigger(error))
    #expect(await transport.requests.count == 1)
    #expect(GroupMembersLegacyExecutor.notice == "服务器版本较旧：成员逐个提交，可能覆盖他人同时对这些账号的修改。")
}
