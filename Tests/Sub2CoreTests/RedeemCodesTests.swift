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
