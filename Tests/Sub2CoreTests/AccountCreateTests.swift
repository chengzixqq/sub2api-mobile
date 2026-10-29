import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let createdAccountJSON = #"{"id":21,"name":"Claude-03","platform":"anthropic","type":"apikey","status":"active","schedulable":false}"#
private let fixtureSecret = "sk-ant-api03-test-0000"

private func createClient(_ transport: ScriptedTransport, clock: RequestClock = .immediate) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: clock)
}
private func sampleRequest(name: String = " Claude-03 ", notes: String? = "  ") -> AccountCreateRequest {
    AccountCreateRequest(name: name, notes: notes, platform: "anthropic", type: "apikey",
                         credentials: ["api_key": .string(fixtureSecret), "base_url": "https://api.anthropic.com"],
                         concurrency: 10, priority: 1, rateMultiplier: 1, groupIDs: [], autoPauseOnExpired: true, upstreamBillingProbeEnabled: true)
}
/// JSONEncoder may write `/` as `\/`; the bytes are compared with that undone.
private func text(_ data: Data?) -> String { String(decoding: data ?? Data(), as: UTF8.self).replacingOccurrences(of: #"\/"#, with: "/") }
private func keyedFailure(_ operation: () async throws -> Void) async -> KeyedWriteFailure? {
    do { try await operation(); return nil } catch { return error as? KeyedWriteFailure }
}
private func candidate(id: Int, name: String = "Claude-03", platform: String = "anthropic", createdAt: String? = nil) -> UpstreamAccount {
    UpstreamAccount(id: id, name: name, platform: platform, type: "apikey", createdAt: createdAt)
}

// MARK: - Request body

@Test func createBodyIsSortedWithSchedulableFalseAndNoSkipDefaultGroup() throws {
    let body = text(try sampleRequest().requestBody())
    #expect(body == #"{"auto_pause_on_expired":true,"concurrency":10,"credentials":{"api_key":"sk-ant-api03-test-0000","base_url":"https://api.anthropic.com"},"#
        + #""group_ids":[],"name":"Claude-03","platform":"anthropic","priority":1,"rate_multiplier":1,"schedulable":false,"type":"apikey","#
        + #""upstream_billing_probe_enabled":true}"#)
    for absent in ["notes", "skip_default_group_bind", "confirm_mixed_channel_risk", "proxy_id", "extra"] { #expect(!body.contains(absent)) }
}

@Test func createBodyEncodesOptionalFieldsOnlyWhenSet() throws {
    let request = AccountCreateRequest(name: "Ag-01", notes: " 备注 ", platform: "antigravity", type: "apikey",
                                       credentials: ["api_key": "ag-fixture", "base_url": "https://upstream.example.invalid"],
                                       extra: ["mixed_scheduling": true], proxyID: 3, concurrency: 5, priority: 2,
                                       rateMultiplier: Decimal(string: "0.5"), loadFactor: 5, groupIDs: [9, 2], expiresAt: 1_893_456_000)
    let body = text(try request.requestBody())
    #expect(body.contains(#""notes":"备注""#) && body.contains(#""proxy_id":3"#) && body.contains(#""load_factor":5"#))
    #expect(body.contains(#""expires_at":1893456000"#) && body.contains(#""extra":{"mixed_scheduling":true}"#))
    #expect(body.contains(#""rate_multiplier":0.5,"#) && body.contains(#""group_ids":[9,2]"#))
    #expect(!body.contains("auto_pause_on_expired") && !body.contains("upstream_billing_probe_enabled"))
    let empty = AccountCreateRequest(name: "x", platform: "openai", type: "apikey", credentials: ["api_key": "k"], extra: [:], concurrency: 1, priority: 1)
    #expect(try empty.extra == nil && !text(empty.requestBody()).contains("extra"))
}

@Test func confirmingMixedChannelOnlyAddsTheFlag() throws {
    let original = sampleRequest()
    let confirmed = original.confirmingMixedChannel()
    let before = text(try original.requestBody())
    #expect(try text(confirmed.requestBody()) == before.replacingOccurrences(of: #""concurrency":10,"#,
                                                                            with: #""concurrency":10,"confirm_mixed_channel_risk":true,"#))
    #expect(!original.confirmMixedChannelRisk && confirmed.confirmMixedChannelRisk && confirmed != original)
}

@Test(arguments: [
    (AccountCreateRequest(name: "  ", platform: "openai", type: "apikey", credentials: ["api_key": "k"], concurrency: 1, priority: 1), "请输入账号名称"),
    (AccountCreateRequest(name: "a", platform: "openai", type: "web", credentials: ["api_key": "k"], concurrency: 1, priority: 1), "账号类型无效。"),
    (AccountCreateRequest(name: "a", platform: " ", type: "apikey", credentials: ["api_key": "k"], concurrency: 1, priority: 1), "账号类型无效。"),
    (AccountCreateRequest(name: "a", platform: "openai", type: "apikey", credentials: [:], concurrency: 1, priority: 1), "请填写凭据"),
    (AccountCreateRequest(name: "a", platform: "openai", type: "apikey", credentials: ["api_key": "k"], concurrency: -1, priority: 1),
     "并发和优先级必须是非负整数。"),
    (AccountCreateRequest(name: "a", platform: "openai", type: "apikey", credentials: ["api_key": "k"], concurrency: 1, priority: 1,
                          rateMultiplier: Decimal(string: "-0.1")), "账号计费倍率需要是不小于 0 的数字"),
    (AccountCreateRequest(name: "a", platform: "openai", type: "apikey", credentials: ["api_key": "k"], concurrency: 1, priority: 1, groupIDs: [0]),
     "分组编号无效或重复。"),
    (AccountCreateRequest(name: "a", platform: "openai", type: "apikey", credentials: ["api_key": "k"], concurrency: 1, priority: 1, groupIDs: [3, 3]),
     "分组编号无效或重复。"),
    (AccountCreateRequest(name: "a", platform: "openai", type: "apikey", credentials: ["api_key": "k"], proxyID: 0, concurrency: 1, priority: 1),
     "代理编号无效。"),
    (AccountCreateRequest(name: "a", platform: "openai", type: "apikey", credentials: ["api_key": "k"], concurrency: 1, priority: 1, loadFactor: 10_001),
     "负载因子为 1–10000 的整数，可以不填"),
    (AccountCreateRequest(name: "a", platform: "openai", type: "apikey", credentials: ["api_key": "k"], concurrency: 1, priority: 1, expiresAt: 0),
     "过期时间无效。")
])
func createRequestValidationRejectsBadInput(request: AccountCreateRequest, message: String) {
    let error = #expect(throws: APIError.self) { _ = try request.requestBody() }
    #expect(error?.kind == .validation && error?.localizedDescription == message)
}

@Test func createRequestNeverRevealsCredentials() {
    let request = sampleRequest()
    for printed in [String(describing: request), String(reflecting: request), "\(request)"] { #expect(!printed.contains(fixtureSecret)) }
    var dumped = ""
    dump(request, to: &dumped)
    #expect(!dumped.contains(fixtureSecret) && Mirror(reflecting: request).children.isEmpty)
    let frozen = AccountNewFrozenRequest(request: request, key: UUID(), submittedAt: Date())
    for printed in [String(describing: frozen), String(reflecting: frozen), "\(frozen)"] { #expect(!printed.contains(fixtureSecret)) }
    #expect(Mirror(reflecting: frozen).children.isEmpty)
}

// MARK: - Sending

@Test func createAccountWithKeySendsIdempotencyKeyAndRetriesSameBytes() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(createdAccountJSON))])
    let recorder = SleepRecorder(), key = UUID(), request = sampleRequest()
    let outcome = try await createClient(transport, clock: .recording(recorder)).createAccount(request, idempotencyKey: key)
    #expect(outcome.value.id == 21 && !outcome.value.schedulable)
    let sent = await transport.requests, body = try request.requestBody()
    #expect(sent.count == 2)
    for item in sent {
        #expect(item.httpMethod == "POST" && item.url?.path == "/api/v1/admin/accounts")
        #expect(item.httpBody == body && item.timeoutInterval == RequestTimeout.keyedWrite)
        #expect(sentHeader(item, "Idempotency-Key") == key.uuidString.lowercased() && sentHeader(item, "X-Request-ID") == key.uuidString.lowercased())
    }
    #expect(await recorder.durations == [.seconds(2)])
}

@Test func createAccountWithoutKeySendsOnceAndNeverRetries() async throws {
    let failing = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(createdAccountJSON))])
    #expect(await thrownAPIError { _ = try await createClient(failing).createAccount(sampleRequest(), idempotencyKey: nil) }?.kind == .transport)
    #expect(await failing.requests.count == 1)
    let transport = ScriptedTransport(script: [.reply(okReply(createdAccountJSON))])
    let outcome = try await createClient(transport).createAccount(sampleRequest(), idempotencyKey: nil)
    #expect(outcome.value.id == 21 && !outcome.replayed)
    let sent = try #require(await transport.requests.first)
    #expect(sentHeader(sent, "Idempotency-Key") == nil && sent.timeoutInterval == RequestTimeout.unkeyedWrite)
    let requestID = try #require(sentHeader(sent, "X-Request-ID"))
    #expect(requestID == requestID.lowercased() && UUID(uuidString: requestID) != nil)
}

@Test func createAccountKeyedUnconfirmedAndReplayed() async throws {
    let lost = ScriptedTransport(script: [.fail(URLError(.timedOut))])
    let key = UUID(), request = sampleRequest()
    let failure = await keyedFailure { _ = try await createClient(lost).createAccount(request, idempotencyKey: key) }
    #expect(failure?.disposition == .unconfirmed(.transport, retryNotBefore: nil) && failure?.key == key.uuidString.lowercased())
    let attempts = await lost.requests
    #expect(attempts.count == 3 && attempts.allSatisfy { $0.httpBody == attempts[0].httpBody })
    let replay = ScriptedTransport(script: [.reply(okReply(createdAccountJSON, headers: ["X-Idempotency-Replayed": "true"]))])
    #expect(try await createClient(replay).createAccount(request, idempotencyKey: key).replayed)
    let conflict = ScriptedTransport(script: [.reply(errorReply(409, reason: "IDEMPOTENCY_KEY_CONFLICT"))])
    let renew = await keyedFailure { _ = try await createClient(conflict).createAccount(request, idempotencyKey: key) }
    #expect(renew?.disposition == .needsNewKey(.keyConflict))
}

@Test func mixedChannelConflictIsThrownOnceWithMetadata() async throws {
    let metadata = #","metadata":{"group_id":"7","group_name":"主力","current_platform":"Anthropic","other_platform":"Antigravity"},"details":{"group_id":7}"#
    let transport = ScriptedTransport(script: [.reply(errorReply(409, reason: "MIXED_CHANNEL_WARNING", extra: metadata))])
    let error = try #require(await thrownAPIError { _ = try await createClient(transport).createAccount(sampleRequest(), idempotencyKey: UUID()) })
    #expect(error.statusCode == 409 && error.metadata["group_name"] == "主力")
    #expect(await transport.requests.count == 1)
    #expect(MixedChannelWarning(error: error)?.groupName == "主力" && AccountNewFlow.mayBeMixedChannelConflict(error))
    #expect(AccountNewFlow.mayBeMixedChannelConflict(APIError.server(status: 409, reason: nil)))
    #expect(!AccountNewFlow.mayBeMixedChannelConflict(APIError.server(status: 409, reason: "IDEMPOTENCY_KEY_CONFLICT")))
    #expect(!AccountNewFlow.mayBeMixedChannelConflict(APIError.server(status: 400, reason: AccountWriteReason.mixedChannelWarning)))
}

// MARK: - Reconciliation

@Test func reconciliationQueryUsesNameAndPlatformNewestFirst() throws {
    let items = try AccountCreateReconciliation.query(name: " Claude-03 ", platform: "anthropic").queryItems(page: 1)
    let values = Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
    #expect(values["search"] == "Claude-03" && values["platform"] == "anthropic" && values["sort_by"] == "created_at")
    #expect(values["sort_order"] == "desc" && values["page_size"] == "100" && values["lite"] == "1")
    #expect(values["status"] == nil && values["include_counts"] == nil)
}

@Test func reconciliationMatchesExactNameAndPlatformOnly() {
    let sentAt = Date(timeIntervalSince1970: 1_800_000_000)
    let tooOld = ServerTime.utcTimestamp(sentAt.addingTimeInterval(-121))
    let recent = ServerTime.utcTimestamp(sentAt.addingTimeInterval(-119))
    let misses = [candidate(id: 1, name: "claude-03"), candidate(id: 2, name: "Claude-030"), candidate(id: 3, platform: "openai"),
                  candidate(id: 4, createdAt: tooOld)]
    for miss in misses { #expect(AccountCreateReconciliation.match([miss], name: "Claude-03", platform: "anthropic", notBefore: sentAt) == nil) }
    for hit in [candidate(id: 5), candidate(id: 6, createdAt: "not a time"), candidate(id: 7, createdAt: recent), candidate(id: 8, name: " Claude-03 ")] {
        #expect(AccountCreateReconciliation.match([hit], name: "Claude-03", platform: "anthropic", notBefore: sentAt)?.id == hit.id)
    }
    #expect(AccountCreateReconciliation.match([candidate(id: 4, createdAt: tooOld)], name: "Claude-03", platform: "anthropic", notBefore: nil)?.id == 4)
    let both = [candidate(id: 12, createdAt: recent), candidate(id: 30), candidate(id: 40, platform: "openai")]
    #expect(AccountCreateReconciliation.match(both, name: " Claude-03", platform: "anthropic", notBefore: sentAt)?.id == 30)
}
