import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func decimal(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
private func fields(_ items: [URLQueryItem]) -> [String: String] { Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }) }
private let batchID = UUID(uuidString: "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D")!
private let batchKey = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"

@Test func adminRedeemCodeDecodesDecimalValueAndOptionalBatch() throws {
    let json = """
    [{"id":1,"code":"a3f0d4e8","type":"balance","value":10.5,"status":"unused","used_by":null,"created_at":"2026-10-16T09:12:00+08:00",
      "group_id":null,"validity_days":0,"notes":"活动","batch_id":"\(batchKey.uppercased())","created_by":7},
     {"id":2,"code":"b4e1","type":"admin_balance","value":-5,"status":"used","used_by":42,"used_at":"2026-10-16T10:00:00Z","notes":""},
     {"id":3,"code":"c5f2","type":"subscription","value":30,"status":"expired","used_by":9,"batch_id":"\(batchKey)"}]
    """
    let codes = try JSONDecoder().decode([AdminRedeemCode].self, from: Data(json.utf8))
    #expect(codes[0].value == decimal("10.5")); #expect(codes[0].batchID == batchID); #expect(codes[0].usedBy == nil)
    #expect(codes[0].createdAt == ServerTime.parseTimestamp("2026-10-16T01:12:00Z")); #expect(codes[0].createdBy == 7)
    #expect(!codes[0].isRedeemed)
    #expect(codes[1].batchID == nil); #expect(codes[1].value == decimal("-5")); #expect(codes[1].isRedeemed); #expect(codes[1].expiresAt == nil)
    #expect(codes[2].batchID == batchID); #expect(codes[2].isRedeemed)
}

@Test func generateSpecEncodesSortedKeysAndJSONNumber() throws {
    let balance = RedeemGenerateSpec(type: .balance, value: decimal("10.5"), count: 20, expiresInDays: 7, notes: "活动")
    #expect(text(try balance.requestBody(batchID: batchID))
            == #"{"batch_id":"\#(batchKey)","count":20,"expires_in_days":7,"notes":"活动","type":"balance","value":10.5}"#)
    #expect(balance.total == decimal("210"))

    let subscription = RedeemGenerateSpec(type: .subscription, value: 0, count: 5, groupID: 3, groupName: "企业专线", validityDays: 30)
    #expect(text(try subscription.requestBody(batchID: batchID))
            == #"{"batch_id":"\#(batchKey)","count":5,"group_id":3,"type":"subscription","validity_days":30,"value":0}"#)
    #expect(subscription.total == nil)

    let invitation = RedeemGenerateSpec(type: .invitation, value: 0, count: 10)
    #expect(text(try invitation.requestBody(batchID: batchID)) == #"{"batch_id":"\#(batchKey)","count":10,"type":"invitation","value":0}"#)
}

@Test func pendingRedeemBatchBodyIsByteStableAcrossFileRoundTrip() throws {
    let spec = RedeemGenerateSpec(type: .balance, value: decimal("0.1"), count: 3, expiresInDays: 30, notes: "工单 #8812")
    let created = Date(timeIntervalSince1970: 1_800_000_000.25)
    let batch = PendingRedeemBatch(id: batchID, serverID: UUID(), actorUserID: 7, createdAt: created, spec: spec)
    let restored = try JSONDecoder().decode([PendingRedeemBatch].self, from: JSONEncoder().encode([batch]))
    #expect(restored == [batch])
    #expect(try restored[0].requestBody() == batch.requestBody())
    #expect(batch.key == batchKey); #expect(text(try batch.requestBody()).contains(#""batch_id":"\#(batchKey)""#))
    #expect(batch.count == 3); #expect(batch.total == decimal("0.3"))
    #expect(batch.summary == PendingMoneyWriteSummary(subject: .redeemBatch(count: 3, total: decimal("0.3")), createdAt: created))
    #expect(batch.effectiveExpiresAt == created.addingTimeInterval(IdempotencyPolicy.defaultExpiry))
}

@Test func generateSpecValidationRejectsBasicRules() {
    let rejected = [
        RedeemGenerateSpec(type: .balance, value: 10, count: 0),
        RedeemGenerateSpec(type: .balance, value: 0, count: 1),
        RedeemGenerateSpec(type: .concurrency, value: 0, count: 1),
        RedeemGenerateSpec(type: .balance, value: -1, count: 1),
        RedeemGenerateSpec(type: .invitation, value: 0, count: -1),
    ]
    for spec in rejected { #expect(throws: APIError.self) { try spec.validate() } }
    #expect(throws: APIError.self) { _ = try rejected[0].requestBody(batchID: batchID) }
    for spec in [RedeemGenerateSpec(type: .subscription, value: 0, count: 1, groupID: 3, validityDays: 30), RedeemGenerateSpec(type: .invitation, value: 0, count: 1),
                 RedeemGenerateSpec(type: .concurrency, value: 2, count: 100)] {
        #expect(throws: Never.self) { try spec.validate() }
    }
}

@Test func redeemCodeListQueryEncodesBatchAndSearch() async throws {
    let byBatch = RedeemCodeListQuery(batchID: batchID, pageSize: 100, ascending: true)
    #expect(fields(try byBatch.queryItems(page: 1)) == ["batch_id": batchKey, "page": "1", "page_size": "100", "sort_by": "id", "sort_order": "asc"])
    let bySearch = RedeemCodeListQuery(search: "  a3f0  ")
    #expect(fields(try bySearch.queryItems(page: 2)) == ["search": "a3f0", "page": "2", "page_size": "50", "sort_by": "id", "sort_order": "desc"])
    #expect(fields(try RedeemCodeListQuery(search: "   ").queryItems(page: 1))["search"] == nil)
    #expect(throws: APIError.self) { _ = try RedeemCodeListQuery().queryItems(page: 0) }
    #expect(throws: APIError.self) { _ = try RedeemCodeListQuery(pageSize: 0).queryItems(page: 1) }

    let transport = ScriptedTransport { _ in okReply(#"{"items":[{"id":1,"code":"a3f0","status":"unused"}],"total":1,"page":1,"page_size":100,"pages":1}"#) }
    let client = APIClient(server: stubServer(), credential: stubTokens(), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
    let page = try await client.redeemCodes(page: 1, query: byBatch)
    #expect(page.items.map(\.code) == ["a3f0"])
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "GET"); #expect(request.url?.path == "/api/v1/admin/redeem-codes")
    let sent = fields(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? [])
    #expect(sent["batch_id"] == batchKey); #expect(sent["types"] == nil); #expect(sent["status"] == nil)
}

// MARK: S6-03 model, queries, stats and writes (60 §8.2, §8.7, §9.2)

private let fullCode = "a3f01b2c3d4e5f60718293a4b5c6d4e8"
private func redeemClient(_ transport: ScriptedTransport, clock: RequestClock = .immediate) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture"), deviceID: stubDeviceID, transport: transport, requestClock: clock)
}
private func sentFields(_ request: URLRequest?) -> [String: String] {
    fields(request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? [])
}
private func encoded(_ fields: RedeemBatchUpdateFields) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return text(try encoder.encode(fields))
}

@Test func adminRedeemCodeDecodesUserAndGroupWhenPresent() throws {
    let json = """
    [{"id":1,"code":"c1","type":"subscription","value":0,"status":"used","used_by":42,
      "user":{"id":42,"email":"wang@example.invalid","username":"小王","balance":3},"group":{"id":3,"name":"企业专线","platform":"anthropic"}},
     {"id":2,"code":"c2","status":"unused","user":null,"group":null},
     {"id":3,"code":"c3","status":"unused","user":"oops","group":[1]},
     {"id":4,"code":"c4","status":"unused","user":{"email":"x@example.invalid"}}]
    """
    let codes = try JSONDecoder().decode([AdminRedeemCode].self, from: Data(json.utf8))
    #expect(codes.count == 4)
    #expect(codes[0].user == RedeemCodeUser(id: 42, email: "wang@example.invalid", username: "小王"))
    #expect(codes[0].group == RedeemCodeGroup(id: 3, name: "企业专线"))
    for code in codes.dropFirst() { #expect(code.user == nil); #expect(code.group == nil) }
    #expect(codes[2].status == "unused")
}

@Test func adminRedeemCodeDerivedFieldsAndRedactedCode() {
    let adjustment = AdminRedeemCode(id: 1, code: "***", type: "admin_balance", value: -5, status: "used", usedBy: 42)
    #expect(adjustment.codeType == nil); #expect(adjustment.codeStatus == .used)
    #expect(adjustment.isAdminAdjustment); #expect(adjustment.isRedacted)
    let code = AdminRedeemCode(id: 2, code: fullCode, type: "balance", value: 10, status: "unused")
    #expect(code.codeType == .balance); #expect(code.codeStatus == .unused)
    #expect(!code.isAdminAdjustment); #expect(!code.isRedacted)
    #expect(AdminRedeemCode(id: 3, code: "", type: "balance", status: "weird").codeStatus == nil)
    for description in [String(reflecting: code), String(describing: code), "\(code)"] {
        #expect(!description.contains(fullCode)); #expect(description.contains("a3f0····d4e8"))
    }
}

@Test func keepingRelationsFillsMissingUserAndGroupFromListedCode() {
    let user = RedeemCodeUser(id: 42, email: "wang@example.invalid", username: "小王"), group = RedeemCodeGroup(id: 3, name: "企业专线")
    let listed = AdminRedeemCode(id: 1, code: fullCode, type: "subscription", status: "unused", groupID: 3, user: user, group: group)
    let fresh = AdminRedeemCode(id: 1, code: fullCode, type: "subscription", status: "disabled", groupID: 3, notes: "新备注")
    let merged = fresh.keepingRelations(of: listed)
    #expect(merged.user == user); #expect(merged.group == group); #expect(merged.status == "disabled"); #expect(merged.notes == "新备注")
    let own = RedeemCodeUser(id: 43, email: nil, username: "小李")
    let withUser = AdminRedeemCode(id: 1, code: fullCode, type: "subscription", status: "used", usedBy: 43, user: own)
    #expect(withUser.keepingRelations(of: listed).user == own); #expect(withUser.keepingRelations(of: listed).group == group)
    let other = AdminRedeemCode(id: 2, code: fullCode, type: "subscription", status: "unused", user: user, group: group)
    #expect(fresh.keepingRelations(of: other) == fresh); #expect(fresh.keepingRelations(of: nil) == fresh)
}

@Test func listQueryWithCapabilitySendsAllFourTypesOrOne() throws {
    let all = RedeemCodeListQuery(sendsTypes: true)
    #expect(fields(try all.queryItems(page: 1))
            == ["page": "1", "page_size": "50", "sort_by": "id", "sort_order": "desc", "types": "balance,concurrency,subscription,invitation"])
    #expect(all.types == RedeemCodeType.allCases); #expect(!all.excludesAdminAdjustments)
    let one = RedeemCodeListQuery(type: .subscription, status: .unused, sendsTypes: true)
    let sent = fields(try one.queryItems(page: 2))
    #expect(sent["types"] == "subscription"); #expect(sent["status"] == "unused"); #expect(sent["type"] == nil); #expect(sent["page"] == "2")
    #expect(one.types == [.subscription])
    #expect(fields(try RedeemCodeListQuery(sendsTypes: true).queryItems(page: 1))["status"] == nil)
}

@Test func listQueryWithoutCapabilityFallsBackAndFiltersLocally() throws {
    let all = RedeemCodeListQuery(status: .expired)
    let sent = fields(try all.queryItems(page: 1))
    #expect(sent["types"] == nil); #expect(sent["type"] == nil); #expect(sent["status"] == "expired")
    #expect(all.types == nil); #expect(all.excludesAdminAdjustments)
    #expect(!all.admits(AdminRedeemCode(id: 1, code: "b4e1", type: "admin_balance", status: "used")))
    #expect(!all.admits(AdminRedeemCode(id: 2, code: "b4e2", type: "admin_concurrency", status: "used")))
    #expect(all.admits(AdminRedeemCode(id: 3, code: "b4e3", type: "balance", status: "expired")))
    let one = RedeemCodeListQuery(type: .balance)
    #expect(fields(try one.queryItems(page: 1))["type"] == "balance"); #expect(fields(try one.queryItems(page: 1))["types"] == nil)
    #expect(!one.excludesAdminAdjustments); #expect(one.admits(AdminRedeemCode(id: 1, code: "b4e1", type: "admin_balance", status: "used")))
    for sendsTypes in [false, true] {
        for type in [nil] + RedeemCodeType.allCases.map(Optional.some) {
            let keys = fields(try RedeemCodeListQuery(type: type, sendsTypes: sendsTypes).queryItems(page: 1))
            #expect(!(keys["type"] != nil && keys["types"] != nil))
        }
    }
}

@Test func listQueryByBatchDropsTypesAndStatus() throws {
    let byBatch = RedeemCodeListQuery(batchID: batchID, type: .balance, status: .used, sendsTypes: true)
    #expect(fields(try byBatch.queryItems(page: 1)) == ["batch_id": batchKey, "page": "1", "page_size": "50", "sort_by": "id", "sort_order": "desc"])
    #expect(byBatch.types == nil); #expect(!byBatch.excludesAdminAdjustments)
    #expect(byBatch.admits(AdminRedeemCode(id: 1, code: "b4e1", type: "admin_balance", status: "used")))
    let spec = RedeemGenerateSpec(type: .invitation, value: 0, count: 1)
    let reconcile = RedeemBatchReconciliation.query(for: PendingRedeemBatch(id: batchID, serverID: UUID(), actorUserID: 7, spec: spec))
    #expect(fields(try reconcile.queryItems(page: 1)) == ["batch_id": batchKey, "page": "1", "page_size": "100", "sort_by": "id", "sort_order": "asc"])
}

@Test func statsQueryItemsMatchListFiltersWithoutStatusOrPaging() {
    let query = RedeemCodeListQuery(search: " a3f0 ", type: .balance, status: .unused, sendsTypes: true)
    #expect(fields(query.statsQueryItems()) == ["search": "a3f0", "types": "balance"])
    #expect(fields(RedeemCodeListQuery(status: .used, sendsTypes: true).statsQueryItems()) == ["types": "balance,concurrency,subscription,invitation"])
    #expect(fields(RedeemCodeListQuery(status: .used).statsQueryItems()).isEmpty)
    #expect(fields(RedeemCodeListQuery(type: .invitation).statsQueryItems()) == ["type": "invitation"])
    #expect(fields(RedeemCodeListQuery(batchID: batchID, status: .used, sendsTypes: true).statsQueryItems()) == ["batch_id": batchKey])
}

private let statsJSON = #"""
{"total_codes":128,"active_codes":40,"used_codes":70,"expired_codes":12,"total_value_distributed":123.45,
 "by_type":{"balance":60,"concurrency":30,"subscription":20,"invitation":18,"trial":0},"by_status":{"unused":40,"used":70,"expired":12,"disabled":6}}
"""#
private let legacyStatsJSON = #"{"total_codes":0,"active_codes":0,"used_codes":0,"expired_codes":0,"total_value_distributed":0,"by_type":{}}"#

@Test func redeemCodeStatsDecodesByStatusAndRejectsLegacyMock() async throws {
    let stats = try JSONDecoder().decode(RedeemCodeStats.self, from: Data(statsJSON.utf8))
    #expect(stats.total == 128); #expect(stats.unused == 40); #expect(stats.used == 70); #expect(stats.expired == 12); #expect(stats.disabled == 6)
    #expect(stats.byType["balance"] == 60); #expect(stats.totalValueDistributed == decimal("123.45"))
    #expect(stats.count(nil) == 128); #expect(stats.count(.unused) == 40); #expect(stats.count(.disabled) == 6)
    #expect(throws: (any Error).self) { _ = try JSONDecoder().decode(RedeemCodeStats.self, from: Data(legacyStatsJSON.utf8)) }

    let client = redeemClient(ScriptedTransport { _ in okReply(legacyStatsJSON) })
    let error = await thrownAPIError { _ = try await client.redeemCodeStats(query: RedeemCodeListQuery()) }
    #expect(error == .invalidResponse)
}

@Test func redeemCodeStatsRequestsStatsPathWithoutConditionalHeaders() async throws {
    let transport = ScriptedTransport { _ in okReply(statsJSON, headers: ["etag": "\"s1\""]) }
    let client = APIClient(server: stubServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate,
                           cacheIdentity: ConditionalCache.Identity(userID: 1, authMethod: "admin_api_key"), conditionalCache: ConditionalCache())
    let query = RedeemCodeListQuery(search: "wang", status: .unused, sendsTypes: true)
    _ = try await client.redeemCodeStats(query: query)
    let stats = try await client.redeemCodeStats(query: query)
    #expect(stats.total == 128)
    let requests = await transport.requests
    #expect(requests.count == 2)
    for request in requests {
        #expect(request.httpMethod == "GET"); #expect(request.url?.path == "/api/v1/admin/redeem-codes/stats")
        #expect(sentHeader(request, "If-None-Match") == nil)
        #expect(sentFields(request) == ["search": "wang", "types": "balance,concurrency,subscription,invitation"])
    }
}

@Test func redeemCodeByIDUsesPathAndRejectsInvalidID() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"id":7,"code":"a3f0","type":"balance","value":10,"status":"unused"}"#)),
                                               .reply(errorReply(404, reason: "REDEEM_CODE_NOT_FOUND"))])
    let client = redeemClient(transport)
    let code = try await client.redeemCode(id: 7)
    #expect(code.id == 7); #expect(code.user == nil)
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "GET"); #expect(request.url?.path == "/api/v1/admin/redeem-codes/7")
    let invalid = await thrownAPIError { _ = try await client.redeemCode(id: 0) }
    #expect(invalid?.kind == .validation); #expect(await transport.requests.count == 1)
    let missing = await thrownAPIError { _ = try await client.redeemCode(id: 8) }
    #expect(missing?.kind == .notFound); #expect(missing?.reason == "REDEEM_CODE_NOT_FOUND")
}

@Test func batchUpdateFieldsEncodeAbsentVersusNull() throws {
    let at = try #require(ServerTime.parseTimestamp("2026-10-23T09:12:00+08:00"))
    #expect(try encoded(RedeemBatchUpdateFields()) == "{}"); #expect(RedeemBatchUpdateFields().isEmpty)
    #expect(try encoded(RedeemBatchUpdateFields(notes: "活动")) == #"{"notes":"活动"}"#)
    #expect(try encoded(RedeemBatchUpdateFields(notes: "")) == #"{"notes":""}"#)
    #expect(try encoded(RedeemBatchUpdateFields(status: .disabled)) == #"{"status":"disabled"}"#)
    #expect(try encoded(RedeemBatchUpdateFields(status: .unused, expiresAt: .never)) == #"{"expires_at":null,"status":"unused"}"#)
    #expect(try encoded(RedeemBatchUpdateFields(expiresAt: .at(at))) == #"{"expires_at":"2026-10-23T01:12:00Z"}"#)
    #expect(try encoded(RedeemBatchUpdateFields(groupID: .cleared)) == #"{"group_id":null}"#)
    #expect(try encoded(RedeemBatchUpdateFields(groupID: .id(3), notes: "工单 #8812")) == #"{"group_id":3,"notes":"工单 #8812"}"#)
    #expect(!RedeemBatchUpdateFields(notes: "x").isEmpty)
    #expect(!RedeemBatchUpdateFields(notes: "x").touchesUsedSensitiveFields)
    for fields in [RedeemBatchUpdateFields(status: .unused), RedeemBatchUpdateFields(expiresAt: .never), RedeemBatchUpdateFields(groupID: .id(3))] {
        #expect(fields.touchesUsedSensitiveFields)
    }
    #expect(throws: APIError.self) { _ = try encoded(RedeemBatchUpdateFields(groupID: .id(0))) }
}

@Test func updateRedeemCodesPostsIdsAndFieldsWithoutIdempotencyKey() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"updated":2,"message":"Redeem codes updated successfully"}"#) }
    let client = redeemClient(transport)
    let updated = try await client.updateRedeemCodes(ids: [5, 3, 5], fields: RedeemBatchUpdateFields(status: .disabled))
    #expect(updated == 2)
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST"); #expect(request.url?.path == "/api/v1/admin/redeem-codes/batch-update")
    #expect(request.httpBody.map(text) == #"{"fields":{"status":"disabled"},"ids":[5,3]}"#)
    #expect(sentHeader(request, "Idempotency-Key") == nil); #expect(request.timeoutInterval == 30)
}

@Test func updateRedeemCodesRejectsEmptyFieldsAndIDsLocally() async {
    let transport = ScriptedTransport { _ in okReply(#"{"updated":1}"#) }
    let client = redeemClient(transport)
    let cases: [([Int], RedeemBatchUpdateFields)] = [([1], RedeemBatchUpdateFields()), ([], RedeemBatchUpdateFields(notes: "x")),
                                                       ([0], RedeemBatchUpdateFields(notes: "x")), ([1], RedeemBatchUpdateFields(groupID: .id(-1)))]
    for (ids, fields) in cases {
        let error = await thrownAPIError { _ = try await client.updateRedeemCodes(ids: ids, fields: fields) }
        #expect(error?.kind == .validation)
    }
    #expect(await transport.requests.isEmpty)
}

@Test func updateRedeemCodesIsNotRetriedAfterTransportFailureOr502() async {
    for step in [ScriptStep.fail(URLError(.timedOut)), .reply(HTTPResponse(statusCode: 502, data: Data("<html>bad gateway</html>".utf8)))] {
        let transport = ScriptedTransport(script: [step, .reply(okReply(#"{"updated":1}"#))])
        let error = await thrownAPIError { _ = try await redeemClient(transport).updateRedeemCodes(ids: [1], fields: RedeemBatchUpdateFields(status: .unused)) }
        #expect(error != nil); #expect(await transport.requests.count == 1)
    }
    let used = ScriptedTransport { _ in errorReply(409, reason: "REDEEM_CODE_USED") }
    let error = await thrownAPIError { _ = try await redeemClient(used).updateRedeemCodes(ids: [1], fields: RedeemBatchUpdateFields(status: .disabled)) }
    #expect(error?.statusCode == 409); #expect(error?.reason == "REDEEM_CODE_USED"); #expect(await used.requests.count == 1)
}

@Test func deleteRedeemCodeTreatsNotFoundAsGone() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"message":"Redeem code deleted successfully"}"#)),
                                               .reply(errorReply(404, reason: "REDEEM_CODE_NOT_FOUND")),
                                               .reply(HTTPResponse(statusCode: 404, data: Data("404 page not found".utf8))),
                                               .reply(errorReply(409, reason: "REDEEM_CODE_USED"))])
    let client = redeemClient(transport)
    #expect(try await client.deleteRedeemCode(id: 9) == .deleted)
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "DELETE"); #expect(request.url?.path == "/api/v1/admin/redeem-codes/9")
    #expect(try await client.deleteRedeemCode(id: 9) == .alreadyGone)
    #expect(await thrownAPIError { _ = try await client.deleteRedeemCode(id: 9) }?.kind == .unsupported)
    #expect(await thrownAPIError { _ = try await client.deleteRedeemCode(id: 9) }?.reason == "REDEEM_CODE_USED")
    #expect(await thrownAPIError { _ = try await client.deleteRedeemCode(id: 0) }?.kind == .validation)
    #expect(await transport.requests.count == 4)
}

// MARK: S6-03 generate (60 §10.2, §10.4, R04, X34, S6D1-07, S6D1-08)

private let generatedJSON = #"[{"id":11,"code":"a3f01b2c3d4e5f60718293a4b5c6d4e8","type":"balance","value":10,"status":"unused","batch_id":"0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"},{"id":12,"code":"b3f01b2c3d4e5f60718293a4b5c6d4e9","type":"balance","value":10,"status":"unused","batch_id":"0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"}]"#
private let redactedJSON = #"[{"id":11,"code":"***","type":"balance","value":10,"status":"unused"},{"id":12,"code":"***","type":"balance","value":10,"status":"unused"}]"#
private let cooldownEnd = Date(timeIntervalSince1970: 1_800_000_010)
private func batch(_ client: APIClient, serverID: UUID? = nil) -> PendingRedeemBatch {
    PendingRedeemBatch(id: batchID, serverID: serverID ?? client.server.id, actorUserID: 7,
                       spec: RedeemGenerateSpec(type: .balance, value: 10, count: 2, expiresInDays: 7, notes: "活动"))
}
private func keyed(_ disposition: KeyedWriteFailure.Disposition) -> KeyedWriteFailure {
    KeyedWriteFailure(disposition: disposition, key: batchKey, actionID: nil, lastError: nil)
}
private func classify(_ error: any Error, retrying: Bool = false) -> RedeemGenerateResult { RedeemGenerateResult.classify(error, retrying: retrying) }
private let unconfirmedResult = RedeemGenerateResult.unconfirmed(message: "结果未确认，已记为待核对", retryNotBefore: nil)
private actor Stamps {
    private(set) var values = [TimeInterval]()
    func add(_ value: TimeInterval) { values.append(value) }
}

@Test func generateSendsBatchKeyHeadersAndReturnsBatchID() async throws {
    let transport = ScriptedTransport { _ in okReply(generatedJSON, headers: ["X-Redeem-Batch-ID": batchKey]) }
    let client = redeemClient(transport)
    let record = batch(client)
    let outcome = try await client.generateRedeemCodes(stubPersisted(record), sameAddress: [])
    #expect(outcome.value.map(\.id) == [11, 12]); #expect(outcome.batchID == batchID); #expect(!outcome.replayed)
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST"); #expect(request.url?.path == "/api/v1/admin/redeem-codes/generate")
    #expect(sentHeader(request, "Idempotency-Key") == batchKey); #expect(sentHeader(request, "X-Request-ID") == batchKey)
    #expect(request.httpBody == (try record.requestBody())); #expect(request.timeoutInterval == 35)
    let result = RedeemGenerateResult.classify(outcome, batchID: batchID)
    #expect(result == .generated(codes: outcome.value, replayed: false, batchConfirmed: true, needsRefetch: false))
    #expect(result.resolvesRecord)
}

@Test func generateReplayReportsReplayedAndKeepsRedactedCodes() async throws {
    let transport = ScriptedTransport { _ in okReply(redactedJSON, headers: ["X-Redeem-Batch-ID": batchKey, "X-Idempotency-Replayed": "true"]) }
    let client = redeemClient(transport)
    let outcome = try await client.generateRedeemCodes(stubPersisted(batch(client)), sameAddress: [])
    #expect(outcome.replayed); #expect(outcome.value.allSatisfy { $0.isRedacted })
    #expect(RedeemGenerateResult.classify(outcome, batchID: batchID) == .generated(codes: outcome.value, replayed: true, batchConfirmed: true, needsRefetch: true))
    let legacy = WriteOutcome(value: outcome.value, replayed: true)
    #expect(RedeemGenerateResult.classify(legacy, batchID: batchID) == .generated(codes: outcome.value, replayed: true, batchConfirmed: false, needsRefetch: true))
    let otherBatch = WriteOutcome(value: outcome.value, batchID: UUID())
    #expect(RedeemGenerateResult.classify(otherBatch, batchID: batchID) == .generated(codes: outcome.value, replayed: false, batchConfirmed: false, needsRefetch: true))
}

@Test func generateRetriesTransportTwiceThenUnconfirmedAndWaitsThirtySecondsInProgress() async throws {
    let lost = ScriptedTransport { _ in throw URLError(.timedOut) }
    let recorder = SleepRecorder()
    let client = redeemClient(lost, clock: .recording(recorder))
    let record = batch(client)
    do { _ = try await client.generateRedeemCodes(stubPersisted(record), sameAddress: []); Issue.record("expected an unconfirmed write") }
    catch {
        #expect((error as? KeyedWriteFailure)?.disposition == .unconfirmed(.transport, retryNotBefore: nil))
        #expect(classify(error) == unconfirmedResult); #expect(!classify(error).resolvesRecord)
    }
    let requests = await lost.requests, body = try record.requestBody()
    #expect(requests.count == 3); #expect(await recorder.durations == [.seconds(2), .seconds(5)])
    #expect(requests.allSatisfy { $0.httpBody == body && sentHeader($0, "Idempotency-Key") == batchKey })

    let clock = ManualClock(), stamps = Stamps()
    let busy = ScriptedTransport { _ in
        await stamps.add(clock.now().timeIntervalSince(clock.start))
        return errorReply(409, reason: "IDEMPOTENCY_IN_PROGRESS", headers: ["Retry-After": "12"])
    }
    let waiting = redeemClient(busy, clock: clock.advancingClock(SleepRecorder()))
    do { _ = try await waiting.generateRedeemCodes(stubPersisted(batch(waiting)), sameAddress: []); Issue.record("expected an unconfirmed write") }
    catch { #expect((error as? KeyedWriteFailure)?.disposition == .unconfirmed(.stillProcessing, retryNotBefore: nil)) }
    #expect(await stamps.values == [0, 12, 24, 30])
}

@Test func generateAcceptsSameAddressRecordAndRejectsOtherAddress() async throws {
    let transport = ScriptedTransport { _ in okReply(generatedJSON, headers: ["X-Redeem-Batch-ID": batchKey]) }
    let client = redeemClient(transport)
    let oldLogin = UUID()
    let sameAddress: Set<UUID> = [client.server.id, oldLogin]
    let outcome = try await client.generateRedeemCodes(stubPersisted(batch(client, serverID: oldLogin)), sameAddress: sameAddress)
    #expect(outcome.value.count == 2); #expect(await transport.requests.count == 1)
    let error = await thrownAPIError { _ = try await client.generateRedeemCodes(stubPersisted(batch(client, serverID: UUID())), sameAddress: sameAddress) }
    #expect(error == .stationMismatch); #expect(await transport.requests.count == 1)
    let alone = await thrownAPIError { _ = try await client.generateRedeemCodes(stubPersisted(batch(client, serverID: oldLogin)), sameAddress: []) }
    #expect(alone == .stationMismatch); #expect(await transport.requests.count == 1)
}

@Test func generateResultClassifiesFirstAttempt() {
    #expect(classify(keyed(.unconfirmed(.storeUnavailable, retryNotBefore: cooldownEnd)))
            == .unconfirmed(message: "服务器暂时无法受理，稍后用同一编号重试", retryNotBefore: cooldownEnd))
    for cause: KeyedWriteFailure.UnconfirmedCause in [.transport, .stillProcessing, .unreadableResponse] {
        #expect(classify(keyed(.unconfirmed(cause, retryNotBefore: nil))) == unconfirmedResult)
    }
    #expect(classify(keyed(.needsNewKey(.keyConflict))) == .unconfirmed(message: "这个操作编号已被另一笔请求占用，请先核对", retryNotBefore: nil))
    #expect(classify(keyed(.needsNewKey(.invalid))) == .rejected(message: "请求格式错误，未生成", returnsToForm: false))
    #expect(classify(keyed(.needsNewKey(.keyRequired))) == .rejected(message: "请求格式错误，未生成", returnsToForm: false))
    #expect(classify(APIError.server(status: 409, reason: "REDEEM_BATCH_CONFLICT"))
            == .rejected(message: "这个编号已用于参数不同的一批兑换码，请重新生成", returnsToForm: true))
    let backToForm: [APIError] = [.server(status: 409, reason: "REDEEM_CODE_EXPIRED"), .server(status: 400, reason: "REDEEM_CODE_EXPIRES_IN_DAYS_INVALID"),
                                  .server(status: 400, reason: nil), .server(status: 400, envelope: nil), .server(status: 404, reason: nil),
                                  .server(status: 422, reason: nil)]
    for error in backToForm { #expect(classify(error) == .rejected(message: error.localizedDescription, returnsToForm: true)) }
    let stepUp = APIError.server(status: 403, reason: "STEP_UP_REQUIRED")
    let refused: [APIError] = [.server(status: 401, reason: nil), stepUp, stepUp.withSecurityOutcome(.cancelled), .server(status: 423, reason: nil),
                               .server(status: 429, reason: "RATE_LIMITED"), .server(status: 503, reason: "STEP_UP_UNAVAILABLE"),
                               .server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"), APIError(kind: .validation, message: "兑换码的数量与面值必须大于 0。")]
    for error in refused { #expect(classify(error) == .rejected(message: error.localizedDescription, returnsToForm: false)) }
    let pending: [any Error] = [APIError.server(status: 500, reason: nil), APIError.server(status: 503, reason: "IDEMPOTENCY_STORE_UNAVAILABLE"),
                                APIError(kind: .transport, message: "无法连接站点"), CancellationError(), URLError(.timedOut)]
    for error in pending { #expect(classify(error) == unconfirmedResult) }
    for result in [classify(stepUp), classify(APIError.server(status: 409, reason: "REDEEM_BATCH_CONFLICT"))] { #expect(result.resolvesRecord) }
}

@Test func classifyFirstSendClearedSecurityIsReconfirm() {
    let stepUp = APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed)
    #expect(classify(stepUp) == .reconfirm(notice: "二次验证已通过，请重新确认后发送"))
    let compliance = APIError.server(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED").withSecurityOutcome(.passed)
    #expect(classify(compliance) == .reconfirm(notice: "合规确认已完成，请重新确认后发送"))
    #expect(classify(stepUp).resolvesRecord)
}

@Test func generateResultKeepsRecordWhenRetryingAfterUnknown() throws {
    let stepUp = APIError.server(status: 403, reason: "STEP_UP_REQUIRED")
    let kept: [APIError] = [.server(status: 401, reason: nil), stepUp, stepUp.withSecurityOutcome(.cancelled), .server(status: 423, reason: nil),
                            .server(status: 429, reason: "RATE_LIMITED"), .server(status: 404, reason: "RESOURCE_NOT_FOUND"), .server(status: 404, envelope: nil),
                            .server(status: 409, reason: "REDEEM_CODE_EXPIRED"), .server(status: 400, reason: nil), .server(status: 400, envelope: nil),
                            .server(status: 500, reason: nil), .stationMismatch, .otherActorWrite]
    for error in kept { #expect(classify(error, retrying: true) == unconfirmedResult) }
    #expect(classify(APIError.server(status: 409, reason: "REDEEM_BATCH_CONFLICT"), retrying: true)
            == .unconfirmed(message: "这个编号下已有一批参数不同的兑换码，请先核对", retryNotBefore: nil))
    for reason in ["REDEEM_CODE_EXPIRES_IN_DAYS_INVALID", "REDEEM_CODE_EXPIRY_CONFLICT", "REDEEM_BATCH_ID_INVALID"] {
        let error = APIError.server(status: 400, reason: reason)
        #expect(classify(error, retrying: true) == .rejected(message: error.localizedDescription, returnsToForm: true))
    }
    #expect(classify(keyed(.needsNewKey(.invalid)), retrying: true) == .rejected(message: "请求格式错误，未生成", returnsToForm: false))
    #expect(classify(keyed(.needsNewKey(.keyConflict)), retrying: true) == .unconfirmed(message: "这个操作编号已被另一笔请求占用，请先核对", retryNotBefore: nil))

    let codes = try JSONDecoder().decode([AdminRedeemCode].self, from: Data(generatedJSON.utf8))
    let success: Result<WriteOutcome<[AdminRedeemCode]>, any Error> = .success(WriteOutcome(value: codes, replayed: true, batchID: batchID))
    #expect(RedeemGenerateResult.classify(success, batchID: batchID, retrying: true)
            == .generated(codes: codes, replayed: true, batchConfirmed: true, needsRefetch: false))
    let failure: Result<WriteOutcome<[AdminRedeemCode]>, any Error> = .failure(stepUp)
    #expect(RedeemGenerateResult.classify(failure, batchID: batchID, retrying: true) == unconfirmedResult)
    #expect(RedeemGenerateResult.classify(failure, batchID: batchID, retrying: false) == .rejected(message: stepUp.localizedDescription, returnsToForm: false))
}

@Test func classifyRetryClearedSecurityKeepsRecord() {
    let cleared = APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed)
    let result = classify(cleared, retrying: true)
    #expect(result == .unconfirmed(message: "二次验证已通过，请重新确认后发送", retryNotBefore: nil))
    #expect(!result.resolvesRecord)
}
