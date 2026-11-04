import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func keyClient(_ transport: ScriptedTransport, interceptor: SecurityInterceptor? = nil,
                       cacheIdentity: ConditionalCache.Identity? = nil) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate,
              cacheIdentity: cacheIdentity, securityInterceptor: interceptor)
}
/// JSONEncoder may write "/" as "\/"; both read the same on the server.
private func body(_ data: Data?) -> String { String(decoding: data ?? Data(), as: UTF8.self).replacingOccurrences(of: #"\/"#, with: "/") }
private func sentQuery(_ request: URLRequest?) -> [String: String] {
    let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
private func amount(_ raw: String) -> Decimal { Decimal(string: raw)! }
private func everythingPrinted(_ value: Any) -> String {
    func reflected(_ value: Any) -> [String] {
        Mirror(reflecting: value).children.flatMap { child -> [String] in
            if let text = child.value as? String { return [text] }
            return reflected(child.value)
        }
    }
    var dumped = ""
    dump(value, to: &dumped)
    return ([String(describing: value), String(reflecting: value), dumped] + reflected(value)).joined(separator: "\n")
}
private func isValidation(_ make: () throws -> Any) -> Bool {
    do { _ = try make(); return false } catch { return (error as? APIError)?.kind == .validation }
}
private func keyJSON(_ id: Int, masked: String = "sk-…aaaa") -> String { #"{"id":\#(id),"key":"","key_masked":"\#(masked)","name":"Key \#(id)","status":"active"}"# }
private func pageJSON(_ items: [String], page: Int, pages: Int) -> String {
    #"{"items":[\#(items.joined(separator: ","))],"total":\#(pages * 100),"page":\#(page),"page_size":100,"pages":\#(pages)}"#
}
/// Records what the session owner was asked and answers with a fixed outcome.
private actor RevealProbe {
    private(set) var asked = [Bool]()
    let outcome: SecurityPromptOutcome
    init(_ outcome: SecurityPromptOutcome) { self.outcome = outcome }
    func intercept(isRead: Bool) -> SecurityPromptOutcome { asked.append(isRead); return outcome }
    nonisolated var interceptor: SecurityInterceptor { { [self] _, isRead in await intercept(isRead: isRead) } }
}

// MARK: - 请求体

@Test func userKeyCreateBodyMatchesSpecExample() throws {
    let draft = try AdminAPIKeyCreateRequest(name: "脚本", groupID: 3, quota: 50, expiresInDays: 30, ipWhitelist: ["198.51.100.0/24"],
                                             rateLimit5h: 5, rateLimit1d: 20)
    #expect(try body(draft.requestBody()) == #"{"expires_in_days":30,"group_id":3,"ip_blacklist":[],"ip_whitelist":["198.51.100.0/24"],"name":"脚本","quota":50,"rate_limit_1d":20,"rate_limit_5h":5,"rate_limit_7d":0}"#)
}

@Test func userKeyCreateOmitsUnboundGroupAndPermanentExpiry() throws {
    let draft = try AdminAPIKeyCreateRequest(name: "  夜间脚本 \n", quota: amount("12.3"), rateLimit7d: amount("0.1"))
    #expect(draft.name == "夜间脚本")
    #expect(try body(draft.requestBody()) == #"{"ip_blacklist":[],"ip_whitelist":[],"name":"夜间脚本","quota":12.3,"rate_limit_1d":0,"rate_limit_5h":0,"rate_limit_7d":0.1}"#)
}

@Test func userKeyCreateRejectsInvalidInput() {
    #expect(isValidation { try AdminAPIKeyCreateRequest(name: " \n ") })
    for days in [0, -1] { #expect(isValidation { try AdminAPIKeyCreateRequest(name: "a", expiresInDays: days) }, "\(days)") }
    for group in [0, -2] { #expect(isValidation { try AdminAPIKeyCreateRequest(name: "a", groupID: group) }, "\(group)") }
    for bad in [amount("-1"), Decimal.nan, amount("0.123456789"), amount("1000000000000")] {
        #expect(isValidation { try AdminAPIKeyCreateRequest(name: "a", quota: bad) }, "\(bad)")
        #expect(isValidation { try AdminAPIKeyCreateRequest(name: "a", rateLimit5h: bad) }, "\(bad)")
        #expect(isValidation { try AdminAPIKeyCreateRequest(name: "a", rateLimit1d: bad) }, "\(bad)")
        #expect(isValidation { try AdminAPIKeyCreateRequest(name: "a", rateLimit7d: bad) }, "\(bad)")
    }
}

@Test func userKeyUpdateEncodesOnlyChangedFields() throws {
    #expect(try body(AdminAPIKeyUpdateRequest(name: "新名字").requestBody()) == #"{"name":"新名字"}"#)
    #expect(try body(AdminAPIKeyUpdateRequest(status: .inactive).requestBody()) == #"{"status":"inactive"}"#)
    #expect(try body(AdminAPIKeyUpdateRequest(quota: 0).requestBody()) == #"{"quota":0}"#)
    #expect(try body(AdminAPIKeyUpdateRequest(quota: amount("12.3"), resetQuota: true).requestBody()) == #"{"quota":12.3,"reset_quota":true}"#)
    #expect(try body(AdminAPIKeyUpdateRequest(resetRateLimitUsage: true).requestBody()) == #"{"reset_rate_limit_usage":true}"#)
    #expect(try body(AdminAPIKeyUpdateRequest(rateLimit5h: 0, rateLimit7d: amount("0.1")).requestBody()) == #"{"rate_limit_5h":0,"rate_limit_7d":0.1}"#)
    #expect(try body(AdminAPIKeyUpdateRequest(name: " A&B ").requestBody()) == #"{"name":" A&B "}"#)
    #expect(isValidation { try AdminAPIKeyUpdateRequest(quota: amount("-0.5")) })
    #expect(isValidation { try AdminAPIKeyUpdateRequest(rateLimit1d: amount("0.000000001")) })
}

@Test func userKeyUpdateExpiryHasThreeStates() throws {
    #expect(try body(AdminAPIKeyUpdateRequest(name: "a").requestBody()) == #"{"name":"a"}"#)
    #expect(try body(AdminAPIKeyUpdateRequest(expiresAt: .clear).requestBody()) == #"{"expires_at":""}"#)
    let date = ServerTime.parseTimestamp("2026-12-31T23:59:59+08:00")!
    #expect(try body(AdminAPIKeyUpdateRequest(expiresAt: .set(date)).requestBody()) == #"{"expires_at":"2026-12-31T15:59:59Z"}"#)
    #expect(ServerTime.utcTimestamp(date) == "2026-12-31T15:59:59Z")
}

@Test func userKeyUpdateClearsIPListsWithEmptyArrays() throws {
    #expect(try body(AdminAPIKeyUpdateRequest(ipWhitelist: []).requestBody()) == #"{"ip_whitelist":[]}"#)
    #expect(try body(AdminAPIKeyUpdateRequest(ipBlacklist: []).requestBody()) == #"{"ip_blacklist":[]}"#)
    #expect(try body(AdminAPIKeyUpdateRequest(ipWhitelist: ["198.51.100.1"], ipBlacklist: ["203.0.113.0/24"]).requestBody())
            == #"{"ip_blacklist":["203.0.113.0/24"],"ip_whitelist":["198.51.100.1"]}"#)
}

@Test func userKeyUpdateGroupChangeStandsAlone() throws {
    #expect(try body(AdminAPIKeyUpdateRequest(groupID: 0).requestBody()) == #"{"group_id":0}"#)
    #expect(try body(AdminAPIKeyUpdateRequest(groupID: 5).requestBody()) == #"{"group_id":5}"#)
    #expect(try body(AdminAPIKeyUpdateRequest(groupID: 0, revokeGroupAccessID: 12).requestBody()) == #"{"group_id":0,"revoke_group_access_id":12}"#)
    #expect(isValidation { try AdminAPIKeyUpdateRequest(name: "a", groupID: 3) })
    #expect(isValidation { try AdminAPIKeyUpdateRequest(status: .active, groupID: 3) })
    #expect(isValidation { try AdminAPIKeyUpdateRequest(expiresAt: .clear, groupID: 3) })
    #expect(isValidation { try AdminAPIKeyUpdateRequest(ipWhitelist: [], groupID: 3) })
    #expect(isValidation { try AdminAPIKeyUpdateRequest(resetQuota: true, groupID: 3) })
    #expect(isValidation { try AdminAPIKeyUpdateRequest(resetRateLimitUsage: true, groupID: 3) })
    #expect(isValidation { try AdminAPIKeyUpdateRequest(name: "a", revokeGroupAccessID: 3) })
    #expect(isValidation { try AdminAPIKeyUpdateRequest(revokeGroupAccessID: 3) })
    #expect(isValidation { try AdminAPIKeyUpdateRequest(groupID: 0, revokeGroupAccessID: 0) })
    #expect(isValidation { try AdminAPIKeyUpdateRequest(groupID: 4, revokeGroupAccessID: 4) })
    #expect(isValidation { try AdminAPIKeyUpdateRequest(groupID: -1) })
    #expect(isValidation { try AdminAPIKeyUpdateRequest() })
    #expect(isValidation { try AdminAPIKeyUpdateRequest(name: "  ") })
}

// MARK: - 响应

@Test func userKeyWriteResultDecodesGrantRevokeAndPrevious() throws {
    let granted = try JSONDecoder().decode(AdminAPIKeyWriteResult.self, from: Data(#"""
    {"api_key":{"id":9,"key":"sk-live-SECRET-0123456789","key_masked":"sk-…6789","name":"脚本","group_id":7,"status":"active"},
     "auto_granted_group_access":true,"granted_group_id":7,"granted_group_name":"企业专线"}
    """#.utf8))
    #expect(granted.apiKey?.groupID == 7 && granted.apiKey?.keyMasked == "sk-…6789")
    #expect(granted.autoGrantedGroupAccess && granted.grantedGroupID == 7 && granted.grantedGroupName == "企业专线")
    #expect(!granted.revokedGroupAccess && granted.revokedGroupID == nil && granted.previous == nil)
    #expect(!everythingPrinted(granted).contains("SECRET"))
    let revoked = try JSONDecoder().decode(AdminAPIKeyWriteResult.self, from: Data(#"""
    {"api_key":{"id":9,"key_masked":"sk-…6789"},"auto_granted_group_access":false,"granted_group_name":"","revoked_group_access":true,"revoked_group_id":7}
    """#.utf8))
    #expect(revoked.revokedGroupAccess && revoked.revokedGroupID == 7 && revoked.grantedGroupName == nil)
    let edited = try JSONDecoder().decode(AdminAPIKeyWriteResult.self, from: Data(#"""
    {"api_key":{"id":9,"key_masked":"sk-…6789"},"auto_granted_group_access":false,
     "previous":{"name":"旧名","status":"quota_exhausted","quota":"50","quota_used":12.5,"expires_at":null,"ip_whitelist":null,"rate_limit_5h":5}}
    """#.utf8))
    #expect(edited.previous == AdminAPIKeyPrevious(name: "旧名", status: "quota_exhausted", quota: 50, quotaUsed: amount("12.5"), expiresAt: .never,
                                                   ipWhitelist: [], rateLimit5h: 5))
    let dated = try JSONDecoder().decode(AdminAPIKeyWriteResult.self, from: Data(#"{"previous":{"expires_at":"2026-12-31T15:59:59Z","ip_blacklist":["203.0.113.9"]}}"#.utf8))
    #expect(dated.previous?.expiresAt == .at(ServerTime.parseTimestamp("2026-12-31T15:59:59Z")!))
    #expect(dated.previous?.ipBlacklist == ["203.0.113.9"] && dated.previous?.ipWhitelist == nil && dated.previous?.name == nil)
    let empty = try JSONDecoder().decode(AdminAPIKeyWriteResult.self, from: Data("{}".utf8))
    #expect(empty.apiKey == nil && !empty.autoGrantedGroupAccess && !empty.revokedGroupAccess && empty.previous == nil)
}

@Test func userKeyRevealAndCreatedRedactPlaintext() throws {
    let secret = "sk-live-SECRET-0123456789"
    let reveal = try JSONDecoder().decode(APIKeyReveal.self, from: Data(#"{"id":9,"key":"\#(secret)"}"#.utf8))
    #expect(reveal.id == 9 && reveal.key == secret)
    #expect(!everythingPrinted(reveal).contains("SECRET") && reveal.debugDescription.contains("9"))
    #expect((reveal as Any) as? any Encodable == nil)
    let created = try JSONDecoder().decode(CreatedAPIKey.self, from: Data(#"""
    {"api_key":{"id":9,"key":"\#(secret)","key_masked":"sk-…6789","name":"脚本"},"auto_granted_group_access":true,"granted_group_id":4,"granted_group_name":"企业专线"}
    """#.utf8))
    #expect(created.key == secret && created.id == 9 && created.apiKey.keyMasked == "sk-…6789")
    #expect(created.autoGrantedGroupAccess && created.grantedGroupID == 4 && created.grantedGroupName == "企业专线")
    #expect(!everythingPrinted(created).contains("SECRET"))
    #expect(!everythingPrinted(WriteOutcome(value: created, replayed: true)).contains("SECRET"))
    #expect((created as Any) as? any Encodable == nil)
    for bad in [#"{"id":9}"#, #"{"id":9,"key":""}"#] {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(APIKeyReveal.self, from: Data(bad.utf8)) }
    }
    for bad in [#"{"api_key":{"id":9,"key_masked":"sk-…6789"}}"#, #"{"api_key":{"id":9,"key":""}}"#, #"{"auto_granted_group_access":true}"#] {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CreatedAPIKey.self, from: Data(bad.utf8)) }
    }
}

// MARK: - 接口

@Test func userAPIKeysFetchesEveryPageAndDropsTombstones() async throws {
    let transport = ScriptedTransport(script: [
        .reply(okReply(pageJSON([keyJSON(3), keyJSON(5, masked: ""), keyJSON(8)], page: 1, pages: 2))),
        .reply(okReply(pageJSON([keyJSON(8), keyJSON(12)], page: 2, pages: 2))),
    ])
    let keys = try await keyClient(transport).userAPIKeys(userID: 5, maskedView: true)
    #expect(keys.map(\.id) == [3, 8, 12])
    let sent = await transport.requests
    #expect(sent.count == 2)
    #expect(sent.allSatisfy { $0.httpMethod == "GET" && $0.url?.path == "/api/v1/admin/users/5/api-keys" })
    #expect(sent.map { sentQuery($0)["page"] } == ["1", "2"])
    #expect(sent.allSatisfy {
        let query = sentQuery($0)
        return query["page_size"] == "100" && query["sort_by"] == "id" && query["sort_order"] == "asc" && query["key_view"] == "masked"
    })
}

@Test func userAPIKeysOmitsKeyViewWithoutCapability() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"items":[],"total":0,"page":1,"page_size":100,"pages":0}"#))])
    let client = keyClient(transport)
    #expect(try await client.userAPIKeys(userID: 5, maskedView: false).isEmpty)
    let sent = await transport.requests
    #expect(sent.count == 1 && sentQuery(sent.first)["key_view"] == nil && sentQuery(sent.first)["sort_by"] == "id")
    #expect(await thrownAPIError { _ = try await client.userAPIKeys(userID: 0, maskedView: true) }?.kind == .validation)
    #expect(await transport.requests.count == 1)
}

@Test func userAPIKeysStopsOnRunawayPagination() async throws {
    let transport = ScriptedTransport { request in
        let page = Int(sentQuery(request)["page"] ?? "") ?? 1
        return okReply(pageJSON([keyJSON(page)], page: page, pages: 1_000))
    }
    let error = await thrownAPIError { _ = try await keyClient(transport).userAPIKeys(userID: 5, maskedView: true) }
    #expect(error?.kind == APIError.invalidResponse.kind)
    #expect(await transport.requests.count == 50)
}

@Test func userKeyReadAndUpdateUseMaskedViewWithoutIdempotencyKey() async throws {
    let transport = ScriptedTransport(script: [
        .reply(okReply(keyJSON(9, masked: "sk-…9999"))),
        .reply(okReply(#"{"api_key":\#(keyJSON(9)),"auto_granted_group_access":false,"previous":{"name":"旧名"}}"#)),
        .reply(okReply(keyJSON(9))),
        .reply(errorReply(502)),
    ])
    let client = keyClient(transport)
    #expect(try await client.apiKey(id: 9, maskedView: true).keyMasked == "sk-…9999")
    let change = try AdminAPIKeyUpdateRequest(name: "新名")
    let result = try await client.updateAPIKey(id: 9, change, maskedView: true)
    #expect(result.previous?.name == "旧名" && result.apiKey?.id == 9)
    _ = try await client.apiKey(id: 9, maskedView: false)
    #expect(await thrownAPIError { _ = try await client.updateAPIKey(id: 9, change, maskedView: false) }?.statusCode == 502)
    let sent = await transport.requests
    #expect(sent.count == 4)
    #expect(sent[0].httpMethod == "GET" && sent[0].url?.path == "/api/v1/admin/api-keys/9" && sentQuery(sent[0]) == ["key_view": "masked"])
    #expect(sent[1].httpMethod == "PUT" && sent[1].url?.path == "/api/v1/admin/api-keys/9" && sentQuery(sent[1]) == ["key_view": "masked"])
    let changeBody = try change.requestBody()
    #expect(sent[1].httpBody == changeBody && sentHeader(sent[1], "Idempotency-Key") == nil)
    let requestID = try #require(sentHeader(sent[1], "X-Request-ID"))
    #expect(requestID == requestID.lowercased() && UUID(uuidString: requestID) != nil)
    #expect(sentQuery(sent[2]).isEmpty && sentQuery(sent[3]).isEmpty && sent[3].httpMethod == "PUT")
    #expect(await thrownAPIError { _ = try await client.apiKey(id: 0, maskedView: true) }?.kind == .validation)
    #expect(await transport.requests.count == 4)
}

@Test func deleteAPIKeyReturnsDeletedAndSurfacesNotFound() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"id":9,"deleted":true}"#)), .reply(errorReply(404, reason: "API_KEY_NOT_FOUND"))])
    let client = keyClient(transport)
    #expect(try await client.deleteAPIKey(id: 9))
    let missing = await thrownAPIError { _ = try await client.deleteAPIKey(id: 9) }
    #expect(missing?.statusCode == 404 && missing?.reason == "API_KEY_NOT_FOUND")
    let sent = await transport.requests
    #expect(sent.count == 2 && sent.allSatisfy { $0.httpMethod == "DELETE" && $0.url?.path == "/api/v1/admin/api-keys/9" })
    #expect(sent[0].httpBody == nil && sentHeader(sent[0], "Idempotency-Key") == nil)
}

@Test func createUserAPIKeyUsesKeyedExecutor() async throws {
    let key = UUID()
    let created = #"{"api_key":{"id":31,"key":"sk-new-SECRET-abcd","key_masked":"sk-…abcd","name":"脚本"},"auto_granted_group_access":false}"#
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(created, headers: ["X-Idempotency-Replayed": "true"]))])
    let draft = try AdminAPIKeyCreateRequest(name: "脚本", quota: 5)
    let outcome = try await keyClient(transport).createUserAPIKey(userID: 5, draft, idempotencyKey: key)
    #expect(outcome.replayed && outcome.value.key == "sk-new-SECRET-abcd" && outcome.value.apiKey.keyMasked == "sk-…abcd")
    let sent = await transport.requests
    #expect(sent.count == 2)
    #expect(sent.allSatisfy { $0.httpMethod == "POST" && $0.url?.path == "/api/v1/admin/users/5/api-keys" })
    #expect(sent.allSatisfy { sentHeader($0, "Idempotency-Key") == key.uuidString.lowercased() && sentHeader($0, "X-Request-ID") == key.uuidString.lowercased() })
    let draftBody = try draft.requestBody()
    #expect(sent[0].httpBody == draftBody && sent[1].httpBody == draftBody)
}

@Test func revealAPIKeyIsBodylessReadResentAfterStepUp() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(403, reason: "STEP_UP_REQUIRED")), .reply(okReply(#"{"id":9,"key":"sk-live-SECRET-1"}"#))])
    let probe = RevealProbe(.passed)
    let reveal = try await keyClient(transport, interceptor: probe.interceptor).revealAPIKey(id: 9)
    #expect(reveal.id == 9 && reveal.key == "sk-live-SECRET-1")
    #expect(await probe.asked == [true])
    let sent = await transport.requests
    #expect(sent.count == 2 && sent.allSatisfy { $0.httpMethod == "POST" && $0.url?.path == "/api/v1/admin/api-keys/9/reveal" })
    #expect(sent.allSatisfy { $0.httpBody == nil && sentHeader($0, "Content-Type") == nil && sentHeader($0, "Idempotency-Key") == nil })
    #expect(sentHeader(sent[0], "X-Request-ID") != nil && sentHeader(sent[0], "X-Request-ID") == sentHeader(sent[1], "X-Request-ID"))

    let refused = ScriptedTransport(script: [.reply(errorReply(403, reason: "STEP_UP_REQUIRED"))])
    let cancelled = await thrownAPIError { _ = try await keyClient(refused, interceptor: RevealProbe(.cancelled).interceptor).revealAPIKey(id: 9) }
    #expect(cancelled?.securityOutcome == .cancelled && cancelled?.reason == "STEP_UP_REQUIRED")
    #expect(await refused.requests.count == 1)

    let cached = ScriptedTransport(script: [.reply(okReply(#"{"id":9,"key":"sk-a"}"#, headers: ["ETag": #""v1""#]))])
    let identity = ConditionalCache.Identity(userID: 1, authMethod: "admin_api_key")
    let client = keyClient(cached, cacheIdentity: identity)
    _ = try await client.revealAPIKey(id: 9)
    _ = try await client.revealAPIKey(id: 9)
    let cachedSent = await cached.requests
    #expect(cachedSent.count == 2 && cachedSent.allSatisfy { sentHeader($0, "If-None-Match") == nil })

    let mismatched = ScriptedTransport(script: [.reply(okReply(#"{"id":10,"key":"sk-other"}"#))])
    #expect(await thrownAPIError { _ = try await keyClient(mismatched).revealAPIKey(id: 9) }?.kind == APIError.invalidResponse.kind)
}

private struct SentKeyIDs: Decodable {
    let apiKeyIDs: [Int]
    enum CodingKeys: String, CodingKey { case apiKeyIDs = "api_key_ids" }
}

@Test func apiKeysTodayUsageBatchesAndMapsCosts() async throws {
    let transport = ScriptedTransport { request in
        let ids = (try? JSONDecoder().decode(SentKeyIDs.self, from: request.httpBody ?? Data()))?.apiKeyIDs ?? []
        let entries = ids.prefix(2).map { #""\#($0)":{"api_key_id":\#($0),"today_actual_cost":"2.80","total_actual_cost":9}"# }
            + [#""99999":{"today_actual_cost":1}"#, #""\#(ids.last ?? 0)x":{"today_actual_cost":1}"#]
        return okReply(#"{"stats":{\#(entries.joined(separator: ","))}}"#)
    }
    let ids = Array(1...449) + [449, 0, -3]
    let usage = try await keyClient(transport).apiKeysTodayUsage(ids: ids)
    let sent = await transport.requests
    let batches = sent.map { (try? JSONDecoder().decode(SentKeyIDs.self, from: $0.httpBody ?? Data()))?.apiKeyIDs ?? [] }
    #expect(batches.map(\.count) == [200, 200, 49])
    #expect(batches.flatMap { $0 } == Array(1...449))
    let firstBody = body(sent.first?.httpBody)
    #expect(firstBody.hasPrefix(#"{"api_key_ids":[1,2,3,"#))
    #expect(sent.allSatisfy { $0.httpMethod == "POST" && $0.url?.path == "/api/v1/admin/dashboard/api-keys-usage" && sentHeader($0, "Idempotency-Key") == nil })
    #expect(usage == [1: amount("2.8"), 2: amount("2.8"), 201: amount("2.8"), 202: amount("2.8"), 401: amount("2.8"), 402: amount("2.8")])
    #expect(usage[99999] == nil)

    let retried = ScriptedTransport(script: [.reply(errorReply(502)), .reply(okReply(#"{"stats":{"7":{"today_actual_cost":2.8}}}"#))])
    #expect(try await keyClient(retried).apiKeysTodayUsage(ids: [7]) == [7: amount("2.8")])
    #expect(await retried.requests.count == 2)

    let silent = ScriptedTransport(script: [.reply(okReply(#"{"stats":{}}"#))])
    #expect(try await keyClient(silent).apiKeysTodayUsage(ids: [0, -1]).isEmpty)
    #expect(await silent.requests.isEmpty)
}
