import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let patchedAccountJSON = #"{"id":9,"name":"测试账号","platform":"anthropic","type":"apikey","status":"active","schedulable":true}"#
private let currentTag = "\"cv-12\"", nextTag = "\"cv-13\""

private func patchClient(_ transport: ScriptedTransport, credential: Credential = .adminKey("fixture-admin-key"),
                         clock: RequestClock = .immediate) -> APIClient {
    APIClient(server: stubServer(), credential: credential, deviceID: stubDeviceID, transport: transport, requestClock: clock)
}
/// An account detail decoded like a `GET :id` reply; `fields` are more top-level members.
private func detail(id: Int = 9, name: String = "测试账号", _ fields: String = "") throws -> UpstreamAccount {
    let json = #"{"id":\#(id),"name":"\#(name)","platform":"anthropic","type":"apikey","status":"active","schedulable":true"#
        + (fields.isEmpty ? "" : "," + fields) + "}"
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
}
private func text(_ data: Data?) -> String { String(decoding: data ?? Data(), as: UTF8.self) }
private func object(_ data: Data?) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])
}
private func json(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }
private func keyedFailure(_ operation: () async throws -> Void) async -> KeyedWriteFailure? {
    do { try await operation(); return nil } catch { return error as? KeyedWriteFailure }
}
private actor EventLog {
    private(set) var values = [KeyedWriteEvent]()
    func add(_ event: KeyedWriteEvent) { values.append(event) }
}

// MARK: - Request bodies

@Test func patchValueEncodesExplicitNullAndSetValues() throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    #expect(text(try encoder.encode(JSONPatchValue.delete)) == "null")
    #expect(text(try encoder.encode(JSONPatchValue.set(.string("x")))) == "\"x\"")
    #expect(JSONPatchValue.set(.null).isDeletion && JSONPatchValue.delete.isDeletion && !JSONPatchValue.set(.bool(false)).isDeletion)
    let patch: [String: JSONPatchValue] = ["b": .set(.string("x")), "a": .delete]
    #expect(text(try encoder.encode(patch)) == #"{"a":null,"b":"x"}"#)
}

@Test func patchBodyHasOnlyChangedKeysInSortedOrder() throws {
    let request = AccountPatchRequest(name: " 新名 ", status: .inactive, credentialsPatch: ["pool_mode": .set(.bool(true)), "model_mapping": .delete])
    #expect(text(try request.requestBody()) == #"{"credentials_patch":{"model_mapping":null,"pool_mode":true},"name":"新名","status":"inactive"}"#)
}

@Test func patchBodyKeepsDecimalAndExplicitClears() throws {
    let request = AccountPatchRequest(notes: "", proxyID: 0, concurrency: 0, priority: 0, rateMultiplier: Decimal(string: "0.12345678"),
                                      loadFactor: 0, groupIDs: [], expiresAt: -5)
    let bytes = try request.requestBody()
    let fields = try object(bytes)
    #expect(fields["notes"] as? String == "" && fields["concurrency"] as? Int == 0 && fields["priority"] as? Int == 0)
    #expect(fields["group_ids"] as? [Int] == [] && fields["load_factor"] as? Int == 0)
    #expect(fields["proxy_id"] as? Int == 0 && fields["expires_at"] as? Int == 0)
    #expect(fields["name"] == nil && fields["credentials"] == nil && fields["extra"] == nil)
    #expect(text(bytes).contains("0.12345678"))
    #expect(text(try AccountPatchRequest(groupIDs: [5, 3]).requestBody()) == #"{"group_ids":[5,3]}"#)
}

@Test func patchBodyNeverCarriesWholeCredentialsOrExtra() throws {
    let request = AccountPatchRequest(credentialsPatch: ["base_url": .set(.string("https://upstream.example.invalid"))],
                                      extraPatch: ["quota_daily_limit": .set(.number(10))])
    #expect(Set(try object(request.requestBody()).keys) == ["credentials_patch", "extra_patch"])
    #expect(text(try AccountPatchRequest(upstreamBillingProbeEnabled: true).requestBody()) == #"{"upstream_billing_probe_enabled":true}"#)
}

@Test func patchBodyIsByteStable() throws {
    let mapping: JSONValue = ["z": "z-model", "a": "a-model"]
    let request = AccountPatchRequest(credentialsPatch: ["model_mapping": .set(mapping)])
    let first = try request.requestBody(), second = try request.requestBody()
    #expect(first == second)
    #expect(text(first) == #"{"credentials_patch":{"model_mapping":{"a":"a-model","z":"z-model"}}}"#)
}

@Test(arguments: [
    AccountPatchRequest(), AccountPatchRequest(confirmMixedChannelRisk: true), AccountPatchRequest(name: "  "),
    AccountPatchRequest(concurrency: -1), AccountPatchRequest(priority: -1), AccountPatchRequest(concurrency: Int(Int32.max) + 1),
    AccountPatchRequest(loadFactor: -1), AccountPatchRequest(loadFactor: 10_001), AccountPatchRequest(rateMultiplier: -1),
    AccountPatchRequest(groupIDs: [10, 10]), AccountPatchRequest(groupIDs: [0]), AccountPatchRequest(proxyID: -1),
    AccountPatchRequest(type: "foo"), AccountPatchRequest(credentialsPatch: [" ": .set(.bool(true))]), AccountPatchRequest(extraPatch: ["": .delete])
])
func patchValidationRejectsInvalidRequests(request: AccountPatchRequest) {
    let error = #expect(throws: APIError.self) { try request.validate() }
    #expect(error?.kind == .validation)
    #expect(throws: APIError.self) { _ = try request.requestBody() }
}

@Test func patchValidationAcceptsBoundaryValues() throws {
    let accepted = [AccountPatchRequest(loadFactor: 0), AccountPatchRequest(loadFactor: 10_000), AccountPatchRequest(proxyID: 0),
                    AccountPatchRequest(rateMultiplier: 0), AccountPatchRequest(type: "service_account"), AccountPatchRequest(status: .error),
                    AccountPatchRequest(expiresAt: 0), AccountPatchRequest(groupIDs: [])]
    for request in accepted { try request.validate() }
}

@Test(arguments: UpstreamAccount.sensitiveCredentialKeys.sorted())
func sensitiveCredentialKeysCannotBeDeletedLocally(key: String) throws {
    for value in [JSONPatchValue.delete, .set(.null)] {
        let error = #expect(throws: APIError.self) { try AccountPatchRequest(credentialsPatch: [key: value]).validate() }
        #expect(error?.kind == .validation)
        #expect(error?.localizedDescription.contains(key) == true)
    }
    try AccountPatchRequest(credentialsPatch: [key: .set(.string("new-fixture-value"))]).validate()
    // The backend only guards credentials_patch.
    try AccountPatchRequest(extraPatch: [key: .delete]).validate()
}

@Test func sensitiveKeyListIsTheAccountsOnlyCopy() {
    #expect(AccountCredentialKeys.sensitive == UpstreamAccount.sensitiveCredentialKeys)
    #expect(AccountCredentialKeys.sensitive.count == 17)
    #expect(AccountCredentialKeys.isSensitive("api_key") && AccountCredentialKeys.isSensitive("sso-rw"))
    #expect(!AccountCredentialKeys.isSensitive("base_url") && !AccountCredentialKeys.isSensitive("API_KEY"))
}

@Test func confirmingMixedChannelReturnsCopy() {
    let original = AccountPatchRequest(name: "新名", groupIDs: [5, 3])
    let confirmed = original.confirmingMixedChannel()
    #expect(original.confirmMixedChannelRisk == nil && confirmed.confirmMixedChannelRisk == true)
    var expected = original; expected.confirmMixedChannelRisk = true
    #expect(confirmed == expected)
    #expect(original.hasChanges && !AccountPatchRequest(confirmMixedChannelRisk: true).hasChanges)
    #expect(AccountPatchRequest(extraPatch: ["k": .delete]).hasChanges)
}

/// S2D1-10: only key names leave the value, whichever way it is printed.
@Test func patchRequestNeverPrintsValues() {
    let secret = "sk-test-secret-123456"
    let request = AccountPatchRequest(name: secret, credentialsPatch: ["api_key": .set(.string(secret))], extraPatch: ["note": .set(.string(secret))])
    let value = JSONPatchValue.set(.string(secret))
    var dumpedRequest = "", dumpedValue = ""
    dump(request, to: &dumpedRequest); dump(value, to: &dumpedValue)
    let printed = [String(describing: request), String(reflecting: request), dumpedRequest, "\(request)",
                   String(describing: value), String(reflecting: value), dumpedValue, "\(value)"]
    for output in printed { #expect(!output.contains("sk-test-secret")) }
    #expect(String(describing: request).contains("api_key") && String(describing: request).contains("name"))
    #expect(Mirror(reflecting: request).children.isEmpty && Mirror(reflecting: value).children.isEmpty)
}

// MARK: - PATCH

@Test func patchAccountSendsIfMatchAndReturnsNewETag() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(patchedAccountJSON, headers: ["ETag": nextTag]))])
    let client = patchClient(transport)
    let request = AccountPatchRequest(name: "新名", credentialsPatch: ["model_mapping": .delete])
    let result = try await client.patchAccount(id: 9, body: request, ifMatch: " \(currentTag) ")
    #expect(result.etag == nextTag && result.account.id == 9)
    let requests = await transport.requests
    #expect(requests.count == 1)
    let sent = try #require(requests.first)
    let expectedBody = try request.requestBody()
    #expect(sent.httpMethod == "PATCH" && sent.url?.path == "/api/v1/admin/accounts/9" && sent.httpBody == expectedBody)
    #expect(sentHeader(sent, "If-Match") == currentTag && sentHeader(sent, "Content-Type") == "application/json")
    #expect(sentHeader(sent, "X-Request-ID") != nil && sentHeader(sent, "Idempotency-Key") == nil)
    #expect(sent.timeoutInterval == RequestTimeout.unkeyedWrite)
}

@Test(arguments: [ScriptStep.fail(URLError(.timedOut)), .reply(HTTPResponse(statusCode: 502, data: Data("<html>bad gateway</html>".utf8)))])
func patchAccountIsNeverResentAutomatically(step: ScriptStep) async throws {
    let transport = ScriptedTransport(script: [step, .reply(okReply(patchedAccountJSON))])
    let client = patchClient(transport)
    let error = await thrownAPIError { _ = try await client.patchAccount(id: 9, body: AccountPatchRequest(status: .active), ifMatch: currentTag) }
    #expect(error != nil)
    #expect(await transport.requests.count == 1)
}

@Test func patchAccountRefreshResendsSameBytesAndIfMatch() async throws {
    let transport = ScriptedTransport { request in
        if isRefresh(request) { return okReply(stubRefreshJSON) }
        if sentHeader(request, "Authorization") == "Bearer old-access" { return errorReply(401, reason: "TOKEN_EXPIRED") }
        return okReply(patchedAccountJSON, headers: ["ETag": nextTag])
    }
    let client = patchClient(transport, credential: stubTokens())
    #expect(try await client.patchAccount(id: 9, body: AccountPatchRequest(priority: 3), ifMatch: currentTag).etag == nextTag)
    let requests = await transport.requests
    let business = requests.filter { !isRefresh($0) }
    #expect(business.count == 2)
    #expect(business[0].httpBody == business[1].httpBody)
    for name in ["If-Match", "X-Request-ID"] { #expect(sentHeader(business[0], name) == sentHeader(business[1], name), "\(name)") }
    #expect(sentHeader(business[1], "If-Match") == currentTag && sentHeader(business[1], "Authorization") == "Bearer new-access")
}

@Test func patchAccountRequiresVersionAndValidInputLocally() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(patchedAccountJSON))])
    let client = patchClient(transport)
    for tag in ["", "  "] {
        #expect(await thrownAPIError { _ = try await client.patchAccount(id: 9, body: AccountPatchRequest(priority: 1), ifMatch: tag) }?.kind == .validation)
    }
    #expect(await thrownAPIError { _ = try await client.patchAccount(id: 0, body: AccountPatchRequest(priority: 1), ifMatch: currentTag) }?.kind == .validation)
    #expect(await thrownAPIError { _ = try await client.patchAccount(id: 9, body: AccountPatchRequest(), ifMatch: currentTag) }?.kind == .validation)
    #expect(await transport.requests.isEmpty)
}

@Test func patchAccountSurfacesVersionConflictWithCurrentETag() async throws {
    let metadata = #","metadata":{"current_config_version":"13","current_etag":"\"cv-13\""}"#
    let transport = ScriptedTransport(script: [.reply(errorReply(412, reason: "ACCOUNT_VERSION_CONFLICT", extra: metadata))])
    let client = patchClient(transport)
    let error = try #require(await thrownAPIError { _ = try await client.patchAccount(id: 9, body: AccountPatchRequest(name: "新名"), ifMatch: currentTag) })
    #expect(error.statusCode == 412 && error.reason == AccountWriteReason.versionConflict && error.action == .refetch)
    #expect(AccountPatchConflict.currentETag(in: error) == nextTag)
    #expect(AccountPatchConflict.currentETag(in: .server(status: 409, reason: "ACCOUNT_VERSION_CONFLICT")) == nil)
    #expect(AccountPatchConflict.currentETag(in: .server(status: 412, reason: "ACCOUNT_VERSION_CONFLICT")) == nil)
    #expect(await transport.requests.count == 1)
}

@Test(arguments: ["INVALID_IF_MATCH", "INVALID_PATCH", "CREDENTIAL_KEY_NOT_DELETABLE"])
func patchAccountRejectionsAreRecognised(reason: String) async throws {
    let reply = errorReply(400, reason: reason, extra: #","message":"credential key api_key cannot be deleted""#)
    let transport = ScriptedTransport(script: [.reply(reply)])
    let client = patchClient(transport)
    let error = try #require(await thrownAPIError { _ = try await client.patchAccount(id: 9, body: AccountPatchRequest(name: "新名"), ifMatch: currentTag) })
    #expect(AccountWriteReason.isRejectedPatch(error) && error.reason == reason)
    #expect(!error.localizedDescription.contains("api_key"))
    #expect(await transport.requests.count == 1)
}

@Test func otherRepliesAreNotPatchRejections() {
    #expect(!AccountWriteReason.isRejectedPatch(.server(status: 400, reason: "VALIDATION_ERROR")))
    #expect(!AccountWriteReason.isRejectedPatch(.server(status: 409, reason: "INVALID_PATCH")))
    let missing = APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND")
    #expect(missing.kind == .notFound && missing.reason == AccountWriteReason.notFound)
}

// MARK: - PUT fallback

/// X24: S5-03's per-account fallback sends only these keys.
@Test func fullUpdateWithOnlyGroupsSendsOnlyThoseKeys() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(patchedAccountJSON))])
    let client = patchClient(transport)
    let base = try detail(#""credentials":{"base_url":"https://upstream.example.invalid"},"extra":{"mixed_scheduling":true}"#)
    _ = try await client.fullUpdate(id: 9, patch: AccountPatchRequest(groupIDs: [5, 3], confirmMixedChannelRisk: true), base: nil)
    _ = try await client.fullUpdate(id: 9, patch: AccountPatchRequest(groupIDs: [5, 3]), base: base)
    _ = try await client.fullUpdate(id: 9, patch: AccountPatchRequest(groupIDs: []), base: nil)
    let requests = await transport.requests
    #expect(requests.map { text($0.httpBody) } == [#"{"confirm_mixed_channel_risk":true,"group_ids":[5,3]}"#, #"{"group_ids":[5,3]}"#, #"{"group_ids":[]}"#])
    for request in requests {
        #expect(request.httpMethod == "PUT" && request.url?.path == "/api/v1/admin/accounts/9" && sentHeader(request, "Idempotency-Key") == nil)
    }
}

@Test func fullUpdateTopLevelChangesStaySparse() throws {
    #expect(text(try AccountPatchRequest(status: .active).fullUpdateBody(base: nil)) == #"{"status":"active"}"#)
    #expect(Set(try object(AccountPatchRequest(name: "新名", notes: "说明", proxyID: 0).fullUpdateBody(base: nil)).keys) == ["name", "notes", "proxy_id"])
}

@Test func fullUpdateMergesCredentialsKeepingNonSensitiveKeys() throws {
    let base = try detail(#""credentials":{"base_url":"https://upstream.example.invalid","model_mapping":{"a":"a"},"custom_error_codes":[429],"intercept_warmup_requests":true}"#)
    let patch = AccountPatchRequest(credentialsPatch: ["api_key": .set(.string("sk-new-fixture")), "model_mapping": .delete])
    let expected: JSONValue = ["credentials": ["api_key": "sk-new-fixture", "base_url": "https://upstream.example.invalid",
                                               "custom_error_codes": [429], "intercept_warmup_requests": true]]
    #expect(try json(patch.fullUpdateBody(base: base)) == expected)
}

/// The server merges credentials only when the object has keys (`len(input.Credentials) > 0`): deleting the last non-sensitive
/// keys names them as null instead of sending `{}`, which the server would skip while still answering 200.
@Test func fullUpdateDeletingTheLastNonSensitiveKeysNamesThemAsNull() throws {
    let keyed = try detail(#""credentials":{"base_url":"https://upstream.example.invalid"},"credentials_status":{"has_api_key":true}"#)
    let restored = try AccountPatchRequest(credentialsPatch: ["base_url": .delete]).fullUpdateBody(base: keyed)
    #expect(text(restored) == #"{"credentials":{"base_url":null}}"#)
    let mapped = try detail(#""credentials":{"model_mapping":{"a":"b"},"base_url":"https://upstream.example.invalid"}"#)
    let cleared = try AccountPatchRequest(credentialsPatch: ["model_mapping": .set(.null), "base_url": .delete]).fullUpdateBody(base: mapped)
    #expect(text(cleared) == #"{"credentials":{"base_url":null,"model_mapping":null}}"#)
    let kept = try AccountPatchRequest(credentialsPatch: ["model_mapping": .delete]).fullUpdateBody(base: mapped)
    #expect(try json(kept) == ["credentials": ["base_url": "https://upstream.example.invalid"]])
}

/// Only the patch's own secrets go out; the server keeps the stored ones (MergePreservingSensitiveCreds).
@Test func fullUpdateCarriesOnlyThePatchsSecrets() throws {
    let base = try detail(#""credentials":{"base_url":"https://a.example.invalid","api_key":""},"credentials_status":{"has_api_key":true,"has_access_token":true}"#)
    #expect(!base.credentialsArrivedUnredacted)
    let body = try AccountPatchRequest(credentialsPatch: ["base_url": .set(.string("https://b.example.invalid"))]).fullUpdateBody(base: base)
    #expect(try json(body) == ["credentials": ["base_url": "https://b.example.invalid"]])
}

@Test func fullUpdateMergesExtraWithoutUnnamedManagedKeys() throws {
    let base = try detail(#""extra":{"quota_daily_limit":10,"upstream_billing_probe_enabled":true,"upstream_billing_probe":{"status":"ok"},"model_rate_limits":{"m":{"rate_limit_reset_at":null}},"mixed_scheduling":true}"#)
    let dropped = try json(AccountPatchRequest(extraPatch: ["quota_daily_limit": .delete]).fullUpdateBody(base: base))
    let expected: JSONValue = ["extra": ["mixed_scheduling": true, "model_rate_limits": ["m": ["rate_limit_reset_at": .null]]]]
    #expect(dropped == expected)
    let named = try json(AccountPatchRequest(extraPatch: ["upstream_billing_rate_sync_enabled": .set(.bool(true))]).fullUpdateBody(base: base))
    #expect(named["extra"]?["upstream_billing_rate_sync_enabled"] == .bool(true) && named["extra"]?["upstream_billing_probe_enabled"] == nil)
    #expect(named["extra"]?["quota_daily_limit"] == .number(10) && named["credentials"] == nil)
}

@Test func fullUpdateNeedsAMatchingDetailForCredentialOrExtraChanges() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(patchedAccountJSON))])
    let client = patchClient(transport)
    let patches = [AccountPatchRequest(credentialsPatch: ["base_url": .set(.string("https://b.example.invalid"))]),
                   AccountPatchRequest(extraPatch: ["quota_daily_limit": .set(.number(10))])]
    for patch in patches {
        #expect(await thrownAPIError { _ = try await client.fullUpdate(id: 9, patch: patch, base: nil) }?.kind == .validation)
    }
    let other = try detail(id: 10)
    #expect(await thrownAPIError { _ = try await client.fullUpdate(id: 9, patch: AccountPatchRequest(name: "新名"), base: other) }?.kind == .validation)
    #expect(await transport.requests.isEmpty)
    let nullCredentials = try detail(#""credentials":null"#)
    let body = try AccountPatchRequest(credentialsPatch: ["base_url": .set(.string("https://b.example.invalid"))]).fullUpdateBody(base: nullCredentials)
    #expect(try json(body) == ["credentials": ["base_url": "https://b.example.invalid"]])
}

@Test func fullUpdateBodyIsDeterministicForTheSameInputs() throws {
    let base = try detail(#""credentials":{"z":"1","a":{"y":2,"b":3}},"extra":{"k":[1,2]}"#)
    let patch = AccountPatchRequest(name: "新名", credentialsPatch: ["m": .set(["q": 1, "c": 2])], extraPatch: ["k2": .set(.bool(true))])
    let first = try patch.fullUpdateBody(base: base), second = try patch.fullUpdateBody(base: base)
    #expect(first == second)
    #expect(text(first) == #"{"credentials":{"a":{"b":3,"y":2},"m":{"c":2,"q":1},"z":"1"},"extra":{"k":[1,2],"k2":true},"name":"新名"}"#)
}

@Test func fullUpdateWithKeyRetriesSameBytesThenEndsUnconfirmed() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut))])
    let recorder = SleepRecorder()
    let client = patchClient(transport, clock: .recording(recorder))
    let key = UUID()
    let failure = await keyedFailure { _ = try await client.fullUpdate(id: 9, patch: AccountPatchRequest(status: .active), base: nil, idempotencyKey: key) }
    #expect(failure?.disposition == .unconfirmed(.transport, retryNotBefore: nil))
    let requests = await transport.requests
    #expect(requests.count == 3)
    for request in requests {
        #expect(request.httpMethod == "PUT" && request.httpBody == requests[0].httpBody)
        #expect(sentHeader(request, "Idempotency-Key") == key.uuidString.lowercased() && sentHeader(request, "X-Request-ID") == key.uuidString.lowercased())
    }
    #expect(await recorder.durations == [.seconds(2), .seconds(5)])
}

@Test func fullUpdateWithKeyReportsItsRetry() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(patchedAccountJSON))])
    let events = EventLog()
    let client = patchClient(transport)
    let account = try await client.fullUpdate(id: 9, patch: AccountPatchRequest(status: .active), base: nil, idempotencyKey: UUID()) { await events.add($0) }
    #expect(account.id == 9)
    #expect(await transport.requests.count == 2)
    #expect(await events.values == [.confirming(retry: 1)])
}

@Test func fullUpdateWithoutKeyIsSentOnce() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(patchedAccountJSON))])
    let client = patchClient(transport)
    #expect(await thrownAPIError { _ = try await client.fullUpdate(id: 9, patch: AccountPatchRequest(notes: "说明"), base: nil) }?.kind == .transport)
    let requests = await transport.requests
    #expect(requests.count == 1 && sentHeader(requests.first, "Idempotency-Key") == nil)
    let requestID = try #require(sentHeader(requests.first, "X-Request-ID"))
    #expect(requestID == requestID.lowercased() && UUID(uuidString: requestID) != nil)
}

/// S2D1-09: a server older than credential redaction would drop the secrets on a whole-credentials PUT.
@Test func fullUpdateRefusesCredentialPatchOnUnredactedServer() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(patchedAccountJSON))])
    let client = patchClient(transport)
    let legacy = try detail(#""credentials":{"access_token":"legacy-secret-fixture","base_url":"https://upstream.example.invalid"}"#)
    #expect(legacy.credentialsArrivedUnredacted)
    let patch = AccountPatchRequest(credentialsPatch: ["base_url": .set(.string("https://b.example.invalid"))])
    let error = try #require(await thrownAPIError { _ = try await client.fullUpdate(id: 9, patch: patch, base: legacy) })
    #expect(error.kind == .unsupported && error.reason == AccountWriteReason.legacyCredentialsPut)
    #expect(error.localizedDescription == AccountWriteReason.legacyCredentialsPutMessage)
    #expect(await transport.requests.isEmpty)
}

@Test func fullUpdateGroupOnlyStillWorksOnUnredactedServer() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(patchedAccountJSON))])
    let client = patchClient(transport)
    let legacy = try detail(#""credentials":{"access_token":"legacy-secret-fixture"},"extra":{"k":1}"#)
    _ = try await client.fullUpdate(id: 9, patch: AccountPatchRequest(groupIDs: [4]), base: legacy)
    _ = try await client.fullUpdate(id: 9, patch: AccountPatchRequest(extraPatch: ["k": .set(.number(2))]), base: legacy)
    let requests = await transport.requests
    #expect(requests.map { text($0.httpBody) } == [#"{"group_ids":[4]}"#, #"{"extra":{"k":2}}"#])
}

// MARK: - 412 comparison and read-back

struct PatchCheckCase: Sendable, CustomTestStringConvertible {
    let label: String
    let base: String
    let current: String
    let request: AccountPatchRequest
    let expected: AccountPatchConflict
    var testDescription: String { label }
}
private let conflictCases: [PatchCheckCase] = [
    PatchCheckCase(label: "备注仍为底值", base: #""notes":"旧""#, current: #""notes":"旧""#, request: AccountPatchRequest(notes: "新"), expected: .silentRetry),
    PatchCheckCase(label: "备注被改成第三个值", base: #""notes":"旧""#, current: #""notes":"他人""#, request: AccountPatchRequest(notes: "新"), expected: .askUser),
    PatchCheckCase(label: "备注已是目标", base: #""notes":"旧""#, current: #""notes":"新""#, request: AccountPatchRequest(notes: "新"), expected: .alreadyApplied),
    PatchCheckCase(label: "别人只改了没动的字段", base: #""notes":"旧","priority":1"#, current: #""notes":"旧","priority":5"#,
                   request: AccountPatchRequest(notes: "新"), expected: .silentRetry),
    PatchCheckCase(label: "凭据子键被改", base: #""credentials":{"base_url":"https://a.example.invalid"}"#,
                   current: #""credentials":{"base_url":"https://c.example.invalid"}"#,
                   request: AccountPatchRequest(credentialsPatch: ["base_url": .set(.string("https://b.example.invalid"))]), expected: .askUser),
    PatchCheckCase(label: "凭据子键未改", base: #""credentials":{"base_url":"https://a.example.invalid"}"#,
                   current: #""credentials":{"base_url":"https://a.example.invalid","pool_mode":true}"#,
                   request: AccountPatchRequest(credentialsPatch: ["base_url": .set(.string("https://b.example.invalid"))]), expected: .silentRetry),
    PatchCheckCase(label: "扩展子键被改", base: #""extra":{"quota_daily_limit":5}"#, current: #""extra":{"quota_daily_limit":7}"#,
                   request: AccountPatchRequest(extraPatch: ["quota_daily_limit": .set(.number(10))]), expected: .askUser),
    PatchCheckCase(label: "只换敏感键", base: "", current: "", request: AccountPatchRequest(credentialsPatch: ["api_key": .set(.string("sk-new-fixture"))]),
                   expected: .silentRetry),
    PatchCheckCase(label: "备注 nil 与空串等价", base: #""notes":null"#, current: #""notes":"""#, request: AccountPatchRequest(notes: "x"), expected: .silentRetry),
    PatchCheckCase(label: "分组按集合比较", base: #""group_ids":[3,5]"#, current: #""group_ids":[5,3]"#, request: AccountPatchRequest(groupIDs: [7]),
                   expected: .silentRetry),
    PatchCheckCase(label: "分组已是目标", base: #""group_ids":[3]"#, current: #""group_ids":[3,5]"#, request: AccountPatchRequest(groupIDs: [5, 3]),
                   expected: .alreadyApplied),
    PatchCheckCase(label: "清除代理已生效", base: #""proxy_id":4"#, current: #""proxy_id":null"#, request: AccountPatchRequest(proxyID: 0), expected: .alreadyApplied),
    PatchCheckCase(label: "扩展数值 10 与 10.0", base: #""extra":{"quota_daily_limit":5}"#, current: #""extra":{"quota_daily_limit":10.0}"#,
                   request: AccountPatchRequest(extraPatch: ["quota_daily_limit": .set(.number(10))]), expected: .alreadyApplied),
    PatchCheckCase(label: "删除的键已不在", base: #""credentials":{"model_mapping":{"a":"b"}}"#, current: #""credentials":{}"#,
                   request: AccountPatchRequest(credentialsPatch: ["model_mapping": .delete]), expected: .alreadyApplied)
]

@Test(arguments: conflictCases)
func conflictResolutionTable(_ entry: PatchCheckCase) throws {
    let base = try detail(entry.base), current = try detail(entry.current)
    #expect(AccountPatchConflict.resolve(base: base, current: current, request: entry.request) == entry.expected)
}

struct ReadbackCase: Sendable, CustomTestStringConvertible {
    let label: String
    let account: String
    let request: AccountPatchRequest
    let matches: Bool
    var testDescription: String { label }
}
private let readbackCases: [ReadbackCase] = [
    ReadbackCase(label: "状态已启用", account: "", request: AccountPatchRequest(status: .active), matches: true),
    ReadbackCase(label: "停用未生效", account: "", request: AccountPatchRequest(status: .inactive), matches: false),
    ReadbackCase(label: "清除过期时间", account: #""expires_at":null"#, request: AccountPatchRequest(expiresAt: 0), matches: true),
    ReadbackCase(label: "过期时间未清除", account: #""expires_at":1800000000"#, request: AccountPatchRequest(expiresAt: -1), matches: false),
    ReadbackCase(label: "负载因子恢复默认", account: "", request: AccountPatchRequest(loadFactor: 0), matches: true),
    ReadbackCase(label: "倍率相等", account: #""rate_multiplier":1.2"#, request: AccountPatchRequest(rateMultiplier: Decimal(string: "1.2")), matches: true),
    ReadbackCase(label: "分组集合相等", account: #""group_ids":[3,5]"#, request: AccountPatchRequest(groupIDs: [5, 3]), matches: true),
    ReadbackCase(label: "已删除映射", account: #""credentials":{"base_url":"https://a.example.invalid"}"#,
                 request: AccountPatchRequest(credentialsPatch: ["model_mapping": .delete]), matches: true),
    ReadbackCase(label: "映射仍在", account: #""credentials":{"model_mapping":{"a":"b"}}"#,
                 request: AccountPatchRequest(credentialsPatch: ["model_mapping": .delete]), matches: false),
    ReadbackCase(label: "对象键序不同", account: #""credentials":{"model_mapping":{"b":"y","a":"x"}}"#,
                 request: AccountPatchRequest(credentialsPatch: ["model_mapping": .set(["a": "x", "b": "y"])]), matches: true),
    ReadbackCase(label: "上游计费探测", account: #""extra":{"upstream_billing_probe_enabled":true}"#,
                 request: AccountPatchRequest(upstreamBillingProbeEnabled: true), matches: true),
    ReadbackCase(label: "过期自动暂停缺失为 false", account: "", request: AccountPatchRequest(autoPauseOnExpired: false), matches: true),
    ReadbackCase(label: "敏感键读不到", account: "", request: AccountPatchRequest(credentialsPatch: ["api_key": .set(.string("sk-new-fixture"))]), matches: false),
    ReadbackCase(label: "确认混合渠道不参与", account: "", request: AccountPatchRequest(status: .active, confirmMixedChannelRisk: true), matches: true)
]

@Test(arguments: readbackCases)
func readbackMatchesTable(_ entry: ReadbackCase) throws {
    #expect(AccountPatchReadback.matches(account: try detail(entry.account), request: entry.request) == entry.matches)
}
