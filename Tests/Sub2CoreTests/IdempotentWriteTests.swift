import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func decimal(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
private func reply(_ status: Int, _ body: String, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: headers, data: Data(body.utf8))
}
private let grantCode = "0123456789abcdef0123456789abcdef"
private func grant(_ type: CompensationType, _ value: String, group: Int? = nil, days: Int? = nil, code: String = grantCode,
                   notes: String = "故障补偿", createdAt: Date = Date(), expiresAt: Date? = nil) -> PendingCompensation {
    PendingCompensation(serverID: UUID(), actorUserID: 1, createdAt: createdAt, idempotencyExpiresAt: expiresAt, userID: 42, userDisplayName: "王小明",
                        userEmail: "wang@example.invalid", code: code, type: type, value: decimal(value), groupID: group, validityDays: days, notes: notes)
}

@Test func idempotencyOutcomeFollowsResponseTable() {
    let cases: [(HTTPResponse, IdempotencyOutcome)] = [
        (okReply("{}"), .succeeded),
        (reply(200, #"{"code":500,"reason":"X"}"#), .rejected),
        (reply(200, "<html>portal</html>"), .unreadableSuccess),
        (reply(200, "{}"), .unreadableSuccess),
        (errorReply(409, reason: "IDEMPOTENCY_IN_PROGRESS", headers: ["Retry-After": "12"]), .inProgress(retryAfter: 12)),
        (errorReply(409, reason: "IDEMPOTENCY_IN_PROGRESS", extra: #","metadata":{"retry_after":"7"}"#), .inProgress(retryAfter: 7)),
        (errorReply(409, reason: "IDEMPOTENCY_IN_PROGRESS"), .inProgress(retryAfter: 2)),
        (errorReply(409, reason: "IDEMPOTENCY_IN_PROGRESS", headers: ["retry-after": "0"]), .inProgress(retryAfter: 1)),
        (errorReply(409, reason: "IDEMPOTENCY_RETRY_BACKOFF", headers: ["Retry-After": "3"]), .retryBackoff(retryAfter: 3)),
        (errorReply(409, reason: "IDEMPOTENCY_KEY_CONFLICT"), .keyConflict),
        (errorReply(400, reason: "IDEMPOTENCY_KEY_INVALID"), .invalidKeyOrPayload),
        (errorReply(400, reason: "IDEMPOTENCY_PAYLOAD_INVALID"), .invalidKeyOrPayload),
        (errorReply(400, reason: "IDEMPOTENCY_KEY_REQUIRED"), .keyRequired),
        (errorReply(503, reason: "IDEMPOTENCY_STORE_UNAVAILABLE"), .storeUnavailable),
        (reply(503, "{}"), .transportFailure),
        (errorReply(503, reason: "SERVICE_UNAVAILABLE"), .transportFailure),
        (reply(502, "<html>bad gateway</html>"), .transportFailure),
        (reply(504, ""), .transportFailure),
        (errorReply(503, reason: "STEP_UP_UNAVAILABLE"), .rejected),
        (errorReply(409, reason: "EMAIL_EXISTS"), .rejected),
        (errorReply(409, reason: "MIXED_CHANNEL_WARNING"), .rejected),
        (errorReply(403, reason: "STEP_UP_REQUIRED"), .rejected),
        (errorReply(423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED"), .rejected),
        (errorReply(429, reason: "RATE_LIMITED", headers: ["Retry-After": "9"]), .rejected),
        (errorReply(404, reason: "USER_NOT_FOUND"), .rejected),
        (errorReply(500), .rejected),
        // The (status, reason) pair decides: the same reason under another status is not an idempotency answer.
        (errorReply(400, reason: "IDEMPOTENCY_IN_PROGRESS"), .rejected)
    ]
    for (response, expected) in cases {
        #expect(IdempotencyOutcome.classify(response) == expected, "\(response.statusCode) \(text(response.data))")
    }
}

@Test func writeOutcomeReadsIdempotencyHeaders() {
    let action = UUID(), batch = UUID()
    let full = WriteOutcome(value: 1, headers: [
        "X-Idempotency-Replayed": "true", "x-idempotency-recovered": "true", "X-Idempotency-Degraded": "result-committed",
        "X-Idempotency-Expires-At": "2026-10-23T01:02:03Z", "X-Admin-Adjustment-Action-ID": action.uuidString.lowercased(),
        "x-redeem-batch-id": batch.uuidString, "X-Request-ID": "Echoed-ID"
    ])
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
    #expect(full.replayed && full.recovered && full.degraded)
    #expect(full.expiresAt == utc.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 1, minute: 2, second: 3)))
    #expect(full.actionID == action && full.batchID == batch && full.requestID == "Echoed-ID")
    #expect(WriteOutcome(value: 1, headers: ["x-idempotency-degraded": "store-unavailable"]).degraded)
    let other = WriteOutcome(value: 1, headers: ["x-idempotency-replayed": "false", "x-idempotency-degraded": " ", "x-admin-adjustment-action-id": "not-a-uuid",
                                                "x-idempotency-expires-at": "yesterday"])
    #expect(!other.replayed && !other.degraded && other.actionID == nil && other.expiresAt == nil)
    let none = WriteOutcome(value: 1, headers: [:])
    #expect(!none.replayed && !none.recovered && !none.degraded)
    #expect(none.expiresAt == nil && none.actionID == nil && none.batchID == nil && none.requestID == nil)
}

@Test func balanceBodyIsDecimalStringWithoutExponent() throws {
    let tiny = PendingBalanceOperation(serverID: UUID(), userID: 7, amount: decimal("0.00000001"), operation: .add)
    #expect(text(try tiny.requestBody()) == #"{"balance":"0.00000001","notes":"","operation":"add"}"#)
    #expect(try tiny.requestBody() == tiny.requestBody())
    let zero = PendingBalanceOperation(serverID: UUID(), userID: 7, amount: 0, operation: .set)
    #expect(text(try zero.requestBody()) == #"{"balance":"0","notes":"","operation":"set"}"#)
    let maximum = PendingBalanceOperation(serverID: UUID(), userID: 7, amount: decimal("999999999999.99999999"), operation: .add)
    let fields = try #require(JSONSerialization.jsonObject(with: maximum.requestBody()) as? [String: String])
    #expect(fields["balance"] == "999999999999.99999999")
    try PendingBalanceOperation.validateAmount(0)
    for raw in ["-1", "0.000000001", "1000000000000"] {
        #expect(throws: APIError.invalidAmount) { try PendingBalanceOperation.validateAmount(decimal(raw)) }
    }
    #expect(throws: APIError.invalidAmount) { try PendingBalanceOperation(serverID: UUID(), userID: 7, amount: 0, operation: .add).requestBody() }
}

@Test func compensationBodyEncodesValueAsJSONNumber() throws {
    #expect(text(try grant(.balance, "10.5").requestBody())
            == #"{"code":"0123456789abcdef0123456789abcdef","notes":"故障补偿","type":"balance","user_id":42,"value":10.5}"#)
    #expect(text(try grant(.concurrency, "2").requestBody())
            == #"{"code":"0123456789abcdef0123456789abcdef","notes":"故障补偿","type":"concurrency","user_id":42,"value":2}"#)
    #expect(text(try grant(.subscription, "30", group: 3, days: 30).requestBody())
            == #"{"code":"0123456789abcdef0123456789abcdef","group_id":3,"notes":"故障补偿","type":"subscription","user_id":42,"validity_days":30,"value":30}"#)
    let invalid = [grant(.balance, "0"), grant(.balance, "1.005"), grant(.balance, "1", group: 3), grant(.subscription, "30", days: 30),
                   grant(.subscription, "7", group: 3, days: 30), grant(.subscription, "4000", group: 3, days: 4000), grant(.concurrency, "51"),
                   grant(.concurrency, "1.5"), grant(.balance, "1", code: "ab"), grant(.balance, "1", code: " \(grantCode)"),
                   grant(.balance, "1", notes: String(repeating: "备", count: 1_001))]
    for item in invalid { #expect(throws: APIError.self) { try item.requestBody() } }
    let copy = try JSONDecoder().decode(PendingCompensation.self, from: JSONEncoder().encode(grant(.balance, "10.5")))
    #expect(try copy.requestBody() == grant(.balance, "10.5").requestBody())
}

@Test func createUserInitialBalanceIsJSONNumber() throws {
    let body = text(try UserCreateRequest(email: "a@example.invalid", password: "abcdef", balance: decimal("12.5")).requestBody())
    #expect(body.hasPrefix(#"{"balance":12.5,"#))
    #expect(!text(try UserCreateRequest(email: "a@example.invalid", password: "abcdef").requestBody()).contains("balance"))
}

@Test func legacyPendingBalanceRecordDecodesWithoutNewFields() throws {
    let id = UUID(), server = UUID()
    let legacy = #"[{"id":"\#(id.uuidString)","serverID":"\#(server.uuidString)","userID":7,"amount":12.5,"operation":"add","notes":""}]"#
    let record = try #require(try JSONDecoder().decode([PendingBalanceOperation].self, from: Data(legacy.utf8)).first)
    #expect(record.id == id && record.serverID == server && record.userID == 7 && record.amount == decimal("12.5") && record.operation == .add)
    #expect(record.isLegacy && record.requestID == nil && record.actorUserID == nil && record.createdAt == nil)
    #expect(record.userDisplayName == nil && record.userEmail == nil && record.actionID == nil && record.idempotencyExpiresAt == nil)
    #expect(text(try record.requestBody()) == #"{"balance":"12.5","notes":"","operation":"add"}"#)
    let rewritten = try JSONDecoder().decode(PendingBalanceOperation.self, from: JSONEncoder().encode(record))
    #expect(rewritten == record && rewritten.isLegacy)
    let stringAmount = legacy.replacingOccurrences(of: #""amount":12.5"#, with: #""amount":"12.5""#)
    #expect(try JSONDecoder().decode([PendingBalanceOperation].self, from: Data(stringAmount.utf8)).first?.amount == decimal("12.5"))
    let current = PendingBalanceOperation(serverID: server, userID: 7, amount: 50, operation: .subtract, notes: "退款", actorUserID: 3,
                                          createdAt: Date(timeIntervalSince1970: 1_800_000_000), userDisplayName: "周婷", userEmail: "zhou@example.invalid")
    #expect(!current.isLegacy && current.requestID == current.id.uuidString.lowercased())
    let action = UUID()
    let tagged = current.with(actionID: action)
    #expect(tagged.actionID == action && current.actionID == nil && tagged.id == current.id)
    #expect(try tagged.requestBody() == current.requestBody())
    #expect(try JSONDecoder().decode(PendingBalanceOperation.self, from: JSONEncoder().encode(tagged)) == tagged)
}

@Test func pendingLineTitlesFollowOperationAndR02() {
    func line(_ operation: BalanceOperation, _ amount: String, name: String? = "周婷", email: String? = nil) -> PendingMoneyWriteLine {
        PendingMoneyWriteLine(PendingMoneyWriteSummary(subject: .balance(operation, amount: decimal(amount)), createdAt: Date(), userID: 7,
                                                       userDisplayName: name, userEmail: email))
    }
    let add = line(.add, "50")
    #expect(add.title == "充值结果待核对" && add.amount == .money(50) && add.verb == "入账" && add.object == "周婷")
    #expect(add.detail(relativeTime: "2 小时前") == "周婷 · 2 小时前 · 未确认是否入账")
    #expect(line(.subtract, "5").title == "退款结果待核对")
    let all = line(.set, "0")
    #expect(all.title == "退款结果待核对" && all.amount == .allBalance && PendingMoneyWriteLine.allBalanceText == "全部余额")
    #expect(line(.set, "5").title == "余额设置结果待核对" && line(.set, "5").amount == .money(5))
    #expect(line(.add, "1", name: nil).detail(relativeTime: nil) == "用户 #7 · 未确认是否入账")
    #expect(line(.add, "1", name: "  ", email: "zhou@example.invalid").object == "zhou@example.invalid")
    let balanceGrant = grant(.balance, "10").line
    #expect(balanceGrant.title == "补偿结果待核对" && balanceGrant.amount == .money(10) && balanceGrant.verb == "发放")
    #expect(balanceGrant.detail(relativeTime: "5 分钟前") == "王小明 · 5 分钟前 · 未确认是否发放")
    #expect(grant(.subscription, "30", group: 3, days: 30).line.amount == nil)
    let batch = PendingMoneyWriteLine(PendingMoneyWriteSummary(subject: .redeemBatch(count: 20, total: 200), createdAt: nil))
    #expect(batch.title == "兑换码生成结果待核对" && batch.amount == .money(200) && batch.verb == "生成")
    #expect(batch.detail(relativeTime: "5 分钟前") == "20 个 · 5 分钟前 · 未确认是否生成")
    #expect(PendingMoneyWriteLine(PendingMoneyWriteSummary(subject: .redeemBatch(count: 3, total: nil), createdAt: nil)).amount == nil)
}

@Test func effectiveExpiryDefaultsToCreatedAtPlus24Hours() throws {
    let created = Date(timeIntervalSince1970: 1_800_000_000)
    let record = PendingBalanceOperation(serverID: UUID(), userID: 7, amount: 1, operation: .add, createdAt: created, userDisplayName: "周婷")
    #expect(record.effectiveExpiresAt == created.addingTimeInterval(86_400))
    #expect(record.key == record.id.uuidString.lowercased())
    #expect(record.summary == PendingMoneyWriteSummary(subject: .balance(.add, amount: 1), createdAt: created, userID: 7, userDisplayName: "周婷"))
    let expiry = created.addingTimeInterval(3_600)
    #expect(grant(.balance, "1", createdAt: created, expiresAt: expiry).effectiveExpiresAt == expiry)
    let legacy = #"{"id":"\#(UUID().uuidString)","serverID":"\#(UUID().uuidString)","userID":7,"amount":1,"operation":"add","notes":""}"#
    #expect(try JSONDecoder().decode(PendingBalanceOperation.self, from: Data(legacy.utf8)).effectiveExpiresAt == nil)
    let writes: [any PendingMoneyWrite] = [record, grant(.balance, "1", createdAt: created)]
    #expect(writes.map(\.summary.createdAt) == [created, created])
}

@Test func persistFailureNeverProducesSendableWrite() async throws {
    struct DiskFull: Error {}
    let transport = ScriptedTransport { _ in okReply(stubUserJSON) }
    let client = APIClient(server: stubServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate)
    let operation = PendingBalanceOperation(serverID: client.server.id, userID: 7, amount: 1, operation: .add)
    let calls = CallCounter()
    #expect(throws: DiskFull.self) { _ = try PersistedMoneyWrite(operation) { _ in _ = calls.next(); throw DiskFull() } }
    #expect(await transport.requests.isEmpty)
    let write = try PersistedMoneyWrite(operation) { record in #expect(record == operation); _ = calls.next() }
    // Each construction called persist exactly once (1, 2), so the counter is now at 3.
    #expect(write.record == operation && calls.next() == 3)
    #expect(try await client.updateBalance(write, sameAddress: []).value.id == 7)
    #expect(await transport.requests.count == 1)
}

@Test func adminUserDisplayNameFallsBackToEmailPrefix() {
    #expect(AdminUser(id: 1, email: "wang@example.invalid", username: "  王小明 ").displayName == "王小明")
    #expect(AdminUser(id: 1, email: "wang@example.invalid", username: " \n").displayName == "wang")
    #expect(AdminUser(id: 1, email: "wang@example.invalid").displayName == "wang")
}
