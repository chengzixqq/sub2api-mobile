import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 30 §3.7 / 00 §2.5.5 / D25: exact matches only; candidates, the request-id echo and the legacy query are stage 3.

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
private func rowJSON(_ id: Int, user: Int? = 42, kind: String = "balance", actionID: String? = nil, requestID: String? = nil) -> String {
    let action = actionID.map { "\"\($0)\"" } ?? "null", request = requestID.map { "\"\($0)\"" } ?? "null"
    let userField = user.map(String.init) ?? "null"
    return #"{"id":\#(id),"kind":"\#(kind)","operation":"add","requested_value":"50.00000000","delta":"50.00000000","before_value":"12.40000000","after_value":"62.40000000","user_id":\#(userField),"action_id":\#(action),"request_id":\#(request),"created_at":"2027-01-15T08:00:05Z"}"#
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
    #expect(BalanceReconciliation.fallbackQuery(for: legacy(), now: sentAt) == nil)
    #expect(BalanceReconciliation.fallbackQuery(for: pending(email: nil), now: sentAt) == nil)
    #expect(BalanceReconciliation.fallbackQuery(for: pending(email: "  "), now: sentAt) == nil)
}

@Test func stillRunningWithinFortySeconds() throws {
    #expect(BalanceReconciliation.evaluate(pending(), rows: [], now: sentAt.addingTimeInterval(39)) == .stillRunning)
    #expect(BalanceReconciliation.evaluate(pending(), rows: [], now: sentAt.addingTimeInterval(41)) == .notExecuted)
    #expect(BalanceReconciliation.evaluate(legacy(), rows: [], now: sentAt.addingTimeInterval(41)) == .notFound)
    #expect(!PendingReconcileOutcome.balance(.notExecuted).confirmsExecution)
    #expect(!PendingReconcileOutcome.balance(.stillRunning).confirmsExecution)
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
    let failure = await thrownAPIError { _ = try await reconcilingClient(gateway, server: server).reconcileBalance(pending(serverID: server.id)) }
    #expect(failure != nil)

    let legacyServer = stubServer()
    let silent = ScriptedTransport { _ in ledgerPage() }
    let old = legacy(serverID: legacyServer.id)
    #expect(try await reconcilingClient(silent, server: legacyServer).reconcileBalance(old) == .notFound)
    #expect(await silent.requests.isEmpty)
}
