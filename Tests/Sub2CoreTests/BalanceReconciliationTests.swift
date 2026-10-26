import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 30 §3.4, §3.7 / 00 §2.5.5 / D25: exact matches, candidates, the legacy query and the execution grace after a retry.

private let sentAt = Date(timeIntervalSince1970: 1_800_000_000)
private let operationID = UUID(uuidString: "1C2D3E4F-5A6B-4C7D-8E9F-0A1B2C3D4E5F")!
private let operationKey = "1c2d3e4f-5a6b-4c7d-8e9f-0a1b2c3d4e5f"
private let ledgerAction = UUID(uuidString: "8F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E")!

private func pending(serverID: UUID = UUID(), actionID: UUID? = nil, createdAt: Date = sentAt, email: String? = "wang+ops@example.invalid") -> PendingBalanceOperation {
    PendingBalanceOperation(id: operationID, serverID: serverID, userID: 42, amount: 50, operation: .add, notes: "补偿", actorUserID: 7,
                            createdAt: createdAt, userDisplayName: "王小明", userEmail: email).with(actionID: actionID)
}
/// Saved before S0-06: no request id, createdAt or email.
private func legacy(serverID: UUID = UUID(), actionID: UUID? = nil) -> PendingBalanceOperation {
    let json = #"{"id":"\#(operationID.uuidString)","serverID":"\#(serverID.uuidString)","userID":42,"amount":50,"operation":"add","notes":""}"#
    // A fixed fixture; a decoding failure is a broken test file.
    return try! JSONDecoder().decode(PendingBalanceOperation.self, from: Data(json.utf8)).with(actionID: actionID)
}
private func rowJSON(_ id: Int, user: Int? = 42, kind: String = "balance", actionID: String? = nil, requestID: String? = nil,
                     operation: String = "add", requested: String = "50.00000000", notes: String? = nil, operatorID: Int? = nil,
                     createdAt: String? = "2027-01-15T08:00:05Z") -> String {
    func text(_ value: String?) -> String { value.map { "\"\($0)\"" } ?? "null" }
    func number(_ value: Int?) -> String { value.map(String.init) ?? "null" }
    return #"{"id":\#(id),"kind":"\#(kind)","operation":"\#(operation)","requested_value":"\#(requested)","delta":"50.00000000","before_value":"12.40000000","after_value":"62.40000000","user_id":\#(number(user)),"operator_user_id":\#(number(operatorID)),"notes":\#(text(notes)),"action_id":\#(text(actionID)),"request_id":\#(text(requestID)),"created_at":\#(text(createdAt))}"#
}
private func rows(_ items: String...) throws -> [UserAdjustment] {
    try JSONDecoder().decode([UserAdjustment].self, from: Data("[\(items.joined(separator: ","))]".utf8))
}
private func ledgerPage(_ items: String...) -> HTTPResponse {
    okReply(#"{"items":[\#(items.joined(separator: ","))],"total":\#(items.count),"page":1,"page_size":20,"pages":1}"#)
}
private func fields(_ items: [URLQueryItem]) -> [String: String] { Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }) }
private func sentFields(_ request: URLRequest) -> [String: String] {
    fields(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? [])
}
private func reconcilingClient(_ transport: ScriptedTransport, server: ServerProfile, now: Date = sentAt.addingTimeInterval(120)) -> APIClient {
    APIClient(server: server, credential: stubTokens(), deviceID: stubDeviceID, transport: transport, requestClock: .immediate,
              serverClock: ServerClock(localNow: { now }))
}

@Test func sameRequestIDOnAnotherUserIsNotExecution() throws {
    let op = pending()
    let found = try rows(rowJSON(1, user: 43, requestID: operationKey), rowJSON(2, kind: "concurrency", requestID: operationKey), rowJSON(3, user: nil, requestID: operationKey))
    #expect(found.allSatisfy { !BalanceReconciliation.isExactMatch($0, for: op) })
    #expect(BalanceReconciliation.evaluate(op, rows: found, now: sentAt.addingTimeInterval(60)) == .notExecuted)
    let mine = try rows(rowJSON(4, requestID: operationKey))
    #expect(BalanceReconciliation.evaluate(op, rows: mine, now: sentAt.addingTimeInterval(60)) == .executed(mine[0]))
}

@Test func actionIDMatchIgnoresCase() throws {
    let op = pending(actionID: ledgerAction)
    let found = try rows(rowJSON(9, actionID: ledgerAction.uuidString.uppercased()))
    #expect(BalanceReconciliation.isExactMatch(found[0], for: op))
    let outcome = BalanceReconciliation.evaluate(op, rows: found, now: sentAt.addingTimeInterval(5))
    #expect(outcome == .executed(found[0]))
    #expect(PendingReconcileOutcome.balance(outcome).confirmsExecution)
    // A legacy record only matches by the action id a later retry saved.
    let old = legacy(actionID: ledgerAction)
    let byAction = try rows(rowJSON(10, actionID: ledgerAction.uuidString.lowercased()))[0], byRequest = try rows(rowJSON(11, requestID: operationKey))[0]
    #expect(BalanceReconciliation.isExactMatch(byAction, for: old))
    #expect(!BalanceReconciliation.isExactMatch(byRequest, for: legacy()))
}

@Test func firstQueryPrefersActionIDAndSkipsLegacyWithoutOne() throws {
    let byAction = try #require(BalanceReconciliation.firstQuery(for: pending(actionID: ledgerAction)))
    #expect(fields(try byAction.queryItems()) == ["kind": "balance", "user_id": "42", "action_id": ledgerAction.uuidString.lowercased(), "page": "1", "page_size": "20"])
    let byRequest = try #require(BalanceReconciliation.firstQuery(for: pending()))
    #expect(fields(try byRequest.queryItems()) == ["kind": "balance", "user_id": "42", "request_id": operationKey, "page": "1", "page_size": "20"])
    #expect(BalanceReconciliation.firstQuery(for: legacy()) == nil)
    #expect(BalanceReconciliation.firstQuery(for: legacy(actionID: ledgerAction))?.actionID == ledgerAction)
}

@Test func fallbackQueryUsesFullEmailAndTwoMinuteUTCWindow() throws {
    let window = try #require(BalanceReconciliation.fallbackQuery(for: pending(), now: sentAt.addingTimeInterval(300)))
    #expect(fields(try window.queryItems()) == ["kind": "balance", "keyword": "wang+ops@example.invalid", "start_time": "2027-01-15T07:58:00Z",
                                                "end_time": "2027-01-15T08:05:00Z", "page": "1", "page_size": "200"])
    // A phone clock behind the record: the end is kept after the start, which the server requires.
    let clamped = try #require(BalanceReconciliation.fallbackQuery(for: pending(), now: sentAt.addingTimeInterval(-600)))
    #expect(fields(try clamped.queryItems())["end_time"] == "2027-01-15T07:58:01Z")
    // Server time = phone time + offset.
    let shifted = try #require(BalanceReconciliation.fallbackQuery(for: pending(), now: sentAt.addingTimeInterval(300), clockOffset: 30))
    #expect(fields(try shifted.queryItems())["start_time"] == "2027-01-15T07:58:30Z")
    #expect(fields(try shifted.queryItems())["end_time"] == "2027-01-15T08:05:30Z")
    // A legacy record has no createdAt or email: it is looked up by user id instead (legacyFallbackUsesUserIDKeywordWithoutStartTime).
    #expect(BalanceReconciliation.fallbackQuery(for: legacy(), now: sentAt)?.keyword == "42")
    #expect(BalanceReconciliation.fallbackQuery(for: pending(email: nil), now: sentAt) == nil)
    #expect(BalanceReconciliation.fallbackQuery(for: pending(email: "  "), now: sentAt) == nil)
}

@Test func stillRunningWithinFortySeconds() throws {
    #expect(BalanceReconciliation.evaluate(pending(), rows: [], now: sentAt.addingTimeInterval(39)) == .stillRunning)
    #expect(BalanceReconciliation.evaluate(pending(), rows: [], now: sentAt.addingTimeInterval(41)) == .notExecuted)
    // 30 §3.4: a legacy record without a retry has no grace and only candidates; none on a complete page is “not executed”.
    #expect(BalanceReconciliation.evaluate(legacy(), rows: [], now: sentAt.addingTimeInterval(41)) == .notExecuted)
    #expect(!PendingReconcileOutcome.balance(.notExecuted).confirmsExecution)
    #expect(!PendingReconcileOutcome.balance(.stillRunning).confirmsExecution)
}

/// 30 §3.4 step 2, R05: the current balance page checks the form before its confirmation dialog, so the record takes the
/// confirmation time; the grace then starts when the write was sent.
@Test func confirmingStampsCreatedAtAndKeepsNumberAndBody() throws {
    let station = UUID()
    let checked = pending(serverID: station, actionID: ledgerAction, createdAt: sentAt.addingTimeInterval(-60))
    let confirmed = checked.confirmed(at: sentAt)
    #expect(confirmed == pending(serverID: station, actionID: ledgerAction))
    #expect(confirmed.requestID == operationKey); #expect(try confirmed.requestBody() == checked.requestBody())
    #expect(BalanceReconciliation.evaluate(confirmed, rows: [], now: sentAt.addingTimeInterval(5)) == .stillRunning)
    #expect(BalanceReconciliation.evaluate(checked, rows: [], now: sentAt.addingTimeInterval(5)) == .notExecuted)
    let old = legacy()
    #expect(old.confirmed(at: sentAt) == old)
}

@Test func ignoredFiltersReturningUnrelatedRowsAreNotExecution() async throws {
    let server = stubServer()
    let transport = ScriptedTransport(script: [.reply(ledgerPage(rowJSON(1, user: 5), rowJSON(2, user: 6), rowJSON(3, user: 42, requestID: "other"))), .reply(ledgerPage())])
    let outcome = try await reconcilingClient(transport, server: server).reconcileBalance(pending(serverID: server.id))
    #expect(outcome == .notExecuted)
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(sentFields(requests[0])["request_id"] == operationKey)
    #expect(sentFields(requests[1])["keyword"] == "wang+ops@example.invalid"); #expect(sentFields(requests[1])["request_id"] == nil)
}

@Test func reconcileBalanceStopsAfterExactMatch() async throws {
    let server = stubServer()
    let transport = ScriptedTransport { _ in ledgerPage(rowJSON(7, actionID: ledgerAction.uuidString.lowercased())) }
    let outcome = try await reconcilingClient(transport, server: server).reconcileBalance(pending(serverID: server.id, actionID: ledgerAction))
    let expected = try rows(rowJSON(7, actionID: ledgerAction.uuidString.lowercased()))[0]
    #expect(outcome == .executed(expected))
    #expect(await transport.requests.count == 1)
}

@Test func reconcileBalanceRunsFallbackWhenFirstHasNoMatch() async throws {
    let server = stubServer()
    let transport = ScriptedTransport(script: [.reply(ledgerPage()), .reply(ledgerPage(rowJSON(1, user: 420, requestID: operationKey), rowJSON(2, requestID: operationKey)))])
    let outcome = try await reconcilingClient(transport, server: server, now: sentAt.addingTimeInterval(10)).reconcileBalance(pending(serverID: server.id))
    let expected = try rows(rowJSON(2, requestID: operationKey))[0]
    #expect(outcome == .executed(expected))
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(sentFields(requests[1]) == ["kind": "balance", "keyword": "wang+ops@example.invalid", "start_time": "2027-01-15T07:58:00Z",
                                        "end_time": "2027-01-15T08:00:10Z", "page": "1", "page_size": "200"])
    #expect(requests[1].url?.query(percentEncoded: true)?.contains("wang%2Bops") == true)
}

@Test func reconcileBalanceRejectsOtherStationAndPropagatesFailure() async throws {
    let transport = ScriptedTransport { _ in ledgerPage() }
    let error = await thrownAPIError { _ = try await reconcilingClient(transport, server: stubServer()).reconcileBalance(pending()) }
    #expect(error == .stationMismatch)
    #expect(await transport.requests.isEmpty)

    let server = stubServer()
    let gateway = ScriptedTransport { _ in HTTPResponse(statusCode: 502, headers: ["content-type": "text/html"], data: Data("<html>bad gateway</html>".utf8)) }
    let failure = try #require(await thrownAPIError { _ = try await reconcilingClient(gateway, server: server).reconcileBalance(pending(serverID: server.id)) })
    // The first query is a read: retried twice, then thrown without running the fallback or reaching a verdict.
    #expect(failure.kind == .temporary); #expect(failure.statusCode == 502)
    #expect(await gateway.requests.count == 3)
    #expect(await gateway.requests.allSatisfy { sentFields($0)["keyword"] == nil })

    // An old server without user-adjustments (non-JSON 404) is no answer either: never notExecuted.
    let oldSite = stubServer()
    let missing = ScriptedTransport { _ in HTTPResponse(statusCode: 404, headers: ["content-type": "text/plain"], data: Data("404 page not found".utf8)) }
    let unsupported = try #require(await thrownAPIError { _ = try await reconcilingClient(missing, server: oldSite).reconcileBalance(pending(serverID: oldSite.id)) })
    #expect(unsupported.kind == .unsupported); #expect(await missing.requests.count == 1)

    // A legacy record skips the first query and is looked up by user id (30 §3.4).
    let legacyServer = stubServer()
    let silent = ScriptedTransport { _ in ledgerPage() }
    let old = legacy(serverID: legacyServer.id)
    #expect(try await reconcilingClient(silent, server: legacyServer).reconcileBalance(old) == .notExecuted)
    let lookups = await silent.requests
    #expect(lookups.count == 1); #expect(sentFields(lookups[0])["keyword"] == "42"); #expect(sentFields(lookups[0])["start_time"] == nil)
}

// MARK: Stage 3 (30 §3.4): an unreliable request id, candidates, legacy records and the grace after a retry

private func record(amount: Decimal = 50, operation: BalanceOperation = .add, notes: String = "补偿", actor: Int? = 7) -> PendingBalanceOperation {
    PendingBalanceOperation(id: operationID, serverID: UUID(), userID: 42, amount: amount, operation: operation, notes: notes, actorUserID: actor,
                            createdAt: sentAt, userDisplayName: "王小明", userEmail: "wang+ops@example.invalid")
}

@Test func unreliableRequestIDOnlyMatchesActionID() throws {
    let byRequest = try rows(rowJSON(1, requestID: operationKey))[0]
    #expect(BalanceReconciliation.isExactMatch(byRequest, for: pending()))
    #expect(!BalanceReconciliation.isExactMatch(byRequest, for: pending(), requestIDUsable: false))
    let byAction = try rows(rowJSON(2, actionID: ledgerAction.uuidString))[0]
    #expect(BalanceReconciliation.isExactMatch(byAction, for: pending(actionID: ledgerAction), requestIDUsable: false))
    let outcome = BalanceReconciliation.evaluate(pending(actionID: ledgerAction), rows: [byRequest, byAction], now: sentAt.addingTimeInterval(60),
                                                 requestIDUsable: false)
    #expect(outcome == .executed(byAction))
}

@Test func firstQuerySkippedWhenRequestIDUnreliableWithoutActionID() throws {
    #expect(BalanceReconciliation.firstQuery(for: pending(), requestIDUsable: false) == nil)
    let byAction = try #require(BalanceReconciliation.firstQuery(for: pending(actionID: ledgerAction), requestIDUsable: false))
    #expect(fields(try byAction.queryItems()) == ["kind": "balance", "user_id": "42", "action_id": ledgerAction.uuidString.lowercased(), "page": "1", "page_size": "20"])
}

@Test func legacyFallbackUsesUserIDKeywordWithoutStartTime() throws {
    let query = try #require(BalanceReconciliation.fallbackQuery(for: legacy(), now: sentAt.addingTimeInterval(300), clockOffset: 30))
    #expect(fields(try query.queryItems()) == ["kind": "balance", "keyword": "42", "end_time": "2027-01-15T08:05:30Z", "page": "1", "page_size": "200"])
}

@Test func candidateRequiresUserOperationAmountNotesOperatorAndTime() throws {
    func isCandidate(_ json: String, of op: PendingBalanceOperation = record(), clockOffset: TimeInterval = 0) throws -> Bool {
        !BalanceReconciliation.candidates(in: try rows(json), for: op, clockOffset: clockOffset).isEmpty
    }
    #expect(try isCandidate(rowJSON(1, notes: "补偿", operatorID: 7)))
    // created_at ≥ createdAt − 2 minutes; notes are compared trimmed; a missing operator is not compared.
    #expect(try isCandidate(rowJSON(2, notes: "补偿", operatorID: 7, createdAt: "2027-01-15T07:58:00Z")))
    #expect(try isCandidate(rowJSON(3, notes: "  补偿\\n")))
    #expect(try isCandidate(rowJSON(4, requested: "50", notes: "补偿", operatorID: 7)))
    let others = [rowJSON(10, user: 43, notes: "补偿"), rowJSON(11, user: nil, notes: "补偿"), rowJSON(12, kind: "concurrency", notes: "补偿"),
                  rowJSON(13, operation: "subtract", notes: "补偿"), rowJSON(14, requested: "50.00000001", notes: "补偿"), rowJSON(15, notes: "补偿 2"),
                  rowJSON(16, notes: "补偿", operatorID: 8), rowJSON(17, notes: "补偿", createdAt: "2027-01-15T07:57:59Z"),
                  rowJSON(18, notes: "补偿", createdAt: nil), rowJSON(19, notes: nil)]
    for json in others { #expect(try !isCandidate(json)) }
    // No notes on either side, an unknown sender, and the “全部余额” refund as set / 0.
    #expect(try isCandidate(rowJSON(20), of: record(notes: "")))
    #expect(try isCandidate(rowJSON(21, notes: " "), of: record(notes: "")))
    #expect(try isCandidate(rowJSON(22, notes: "补偿", operatorID: 99), of: record(actor: nil)))
    #expect(try isCandidate(rowJSON(23, operation: "set", requested: "0.00000000", notes: "补偿"), of: record(amount: 0, operation: .set)))
    #expect(try !isCandidate(rowJSON(24, operation: "subtract", requested: "0.00000000", notes: "补偿"), of: record(amount: 0, operation: .set)))
    // The ledger's created_at is server time: the window moves with the clock offset.
    #expect(try !isCandidate(rowJSON(25, notes: "补偿", createdAt: "2027-01-15T07:58:10Z"), clockOffset: 30))
    #expect(try isCandidate(rowJSON(26, notes: "补偿", createdAt: "2027-01-15T07:58:30Z"), clockOffset: 30))
}

@Test func legacyCandidatesIgnoreTime() throws {
    let found = try rows(rowJSON(1, createdAt: "2020-01-01T00:00:00Z"), rowJSON(2, createdAt: nil), rowJSON(3, user: 420))
    #expect(BalanceReconciliation.candidates(in: found, for: legacy()) == Array(found.prefix(2)))
    #expect(BalanceReconciliation.evaluate(legacy(), rows: [found[0], found[2]], now: sentAt) == .candidate(found[0]))
}

@Test func unreliableSameAmountAndNotesIsOnlyCandidate() throws {
    let row = try rows(rowJSON(1, requestID: operationKey, notes: "补偿", operatorID: 7))[0]
    let outcome = BalanceReconciliation.evaluate(pending(), rows: [row], now: sentAt.addingTimeInterval(60), requestIDUsable: false)
    #expect(outcome == .candidate(row))
    #expect(!PendingReconcileOutcome.balance(outcome).confirmsExecution)
    #expect(BalanceReconciliation.evaluate(pending(), rows: [row], now: sentAt.addingTimeInterval(60)) == .executed(row))
}

@Test func twoCandidatesAreAmbiguous() throws {
    let found = try rows(rowJSON(1, notes: "补偿"), rowJSON(2, notes: "补偿", createdAt: "2027-01-15T08:00:20Z"))
    let outcome = BalanceReconciliation.evaluate(pending(), rows: found, now: sentAt.addingTimeInterval(60), requestIDUsable: false)
    #expect(outcome == .ambiguous(found))
    #expect(!PendingReconcileOutcome.balance(outcome).confirmsExecution)
}

@Test func rowsFromBothQueriesCountOnce() throws {
    let found = try rows(rowJSON(1, notes: "补偿"), rowJSON(1, notes: "补偿"))
    #expect(BalanceReconciliation.evaluate(pending(), rows: found, now: sentAt.addingTimeInterval(60), requestIDUsable: false) == .candidate(found[0]))
}

@Test func truncatedOrMissingFallbackIsNotConclusive() throws {
    let now = sentAt.addingTimeInterval(60)
    func outcome(_ coverage: FallbackCoverage, rows: [UserAdjustment] = [], usable: Bool = true) -> BalanceReconcileOutcome {
        BalanceReconciliation.evaluate(pending(), rows: rows, now: now, requestIDUsable: usable, coverage: coverage)
    }
    #expect(outcome(.complete) == .notExecuted)
    #expect(outcome(.truncated) == .notFound)
    #expect(outcome(.unavailable) == .notFound)
    #expect(outcome(.complete, usable: false) == .notExecuted)
    #expect(outcome(.truncated, usable: false) == .notFound)
    #expect(outcome(.unavailable, usable: false) == .notFound)
    let candidate = try rows(rowJSON(1, notes: "补偿"))
    #expect(outcome(.truncated, rows: candidate, usable: false) == .candidate(candidate[0]))
    #expect(!PendingReconcileOutcome.balance(.notFound).confirmsExecution)
}

@Test func graceStartsFromLastSend() throws {
    let retried = pending().with(lastSentAt: sentAt.addingTimeInterval(100))
    #expect(retried.graceStart == sentAt.addingTimeInterval(100))
    #expect(BalanceReconciliation.evaluate(retried, rows: [], now: sentAt.addingTimeInterval(120)) == .stillRunning)
    #expect(BalanceReconciliation.evaluate(retried, rows: [], now: sentAt.addingTimeInterval(141)) == .notExecuted)
    // The fallback window still starts at the first send.
    let window = try #require(BalanceReconciliation.fallbackQuery(for: retried, now: sentAt.addingTimeInterval(300)))
    #expect(fields(try window.queryItems())["start_time"] == "2027-01-15T07:58:00Z")
    #expect(pending().with(lastSentAt: sentAt.addingTimeInterval(-100)).graceStart == sentAt)
}

@Test func legacyRecordGetsGraceOnlyAfterARetry() throws {
    #expect(legacy().graceStart == nil)
    #expect(BalanceReconciliation.evaluate(legacy(), rows: [], now: sentAt) == .notExecuted)
    #expect(BalanceReconciliation.evaluate(legacy().with(lastSentAt: sentAt.addingTimeInterval(-10)), rows: [], now: sentAt) == .stillRunning)
}

@Test func reconcileBalanceUnreliableSkipsFirstQuery() async throws {
    let server = stubServer()
    let row = rowJSON(1, requestID: operationKey, notes: "补偿", operatorID: 7)
    let transport = ScriptedTransport { _ in ledgerPage(row) }
    let outcome = try await reconcilingClient(transport, server: server).reconcileBalance(pending(serverID: server.id), requestIDUsable: false)
    #expect(outcome == .candidate(try rows(row)[0]))
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(sentFields(requests[0])["keyword"] == "wang+ops@example.invalid"); #expect(sentFields(requests[0])["request_id"] == nil)
}

@Test func reconcileBalanceLegacyQueriesByUserID() async throws {
    let server = stubServer()
    let mine = rowJSON(3), theirs = rowJSON(4, user: 420)
    let transport = ScriptedTransport { _ in ledgerPage(mine, theirs) }
    let outcome = try await reconcilingClient(transport, server: server).reconcileBalance(legacy(serverID: server.id))
    #expect(outcome == .candidate(try rows(mine)[0]))
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(sentFields(requests[0]) == ["kind": "balance", "keyword": "42", "end_time": "2027-01-15T08:02:00Z", "page": "1", "page_size": "200"])
}

@Test func reconcileBalanceAcceptsSameAddressRecord() async throws {
    let server = stubServer(), oldLogin = UUID()
    let transport = ScriptedTransport { _ in ledgerPage() }
    let client = reconcilingClient(transport, server: server)
    #expect(try await client.reconcileBalance(pending(serverID: oldLogin), sameAddress: [server.id, oldLogin]) == .notExecuted)
    #expect(await transport.requests.count == 2)
    let elsewhere = await thrownAPIError { _ = try await client.reconcileBalance(pending(serverID: UUID()), sameAddress: [server.id, oldLogin]) }
    #expect(elsewhere == .stationMismatch)
    #expect(await transport.requests.count == 2)
    // Both parameters apply together: an unreliable request id still skips the first query.
    _ = try await client.reconcileBalance(pending(serverID: oldLogin), requestIDUsable: false, sameAddress: [server.id, oldLogin])
    let requests = await transport.requests
    #expect(requests.count == 3); #expect(sentFields(requests[2])["keyword"] == "wang+ops@example.invalid")
}

@Test func fallbackPageWithMoreIsTruncated() async throws {
    let server = stubServer()
    let truncated = okReply(#"{"items":[\#(rowJSON(1, user: 5))],"total":350,"page":1,"page_size":200,"pages":2}"#)
    let transport = ScriptedTransport(script: [.reply(ledgerPage()), .reply(truncated)])
    #expect(try await reconcilingClient(transport, server: server).reconcileBalance(pending(serverID: server.id)) == .notFound)
    #expect(await transport.requests.count == 2)
}
