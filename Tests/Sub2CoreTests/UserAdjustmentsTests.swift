import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func decimal(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private func fields(_ items: [URLQueryItem]) -> [String: String] { Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }) }
private func sentFields(_ request: URLRequest?) -> [String: String] {
    fields(request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? [])
}
private let ledgerAction = UUID(uuidString: "8F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D5E")!

@Test func userAdjustmentDecodesLedgerStringsAndNullableFields() throws {
    let json = """
    {"id":12,"action_id":"8f1c2d3e-4a5b-4c6d-8e7f-901a2b3c4d5e","kind":"balance","operation":"add","requested_value":"50.00000000",
     "delta":"50.00000000","before_value":null,"after_value":"62.40000000","user_id":42,"user_email":"wang@example.invalid",
     "user_name":"王小明","operator_user_id":7,"operator_email":"ops@example.invalid","notes":null,"client_ip":"192.0.2.1",
     "request_id":null,"source":"admin","legacy_redeem_code_id":null,"created_at":"2026-10-22T09:20:00.123456+08:00"}
    """
    let row = try JSONDecoder().decode(UserAdjustment.self, from: Data(json.utf8))
    #expect(row.id == 12); #expect(row.kind == "balance"); #expect(row.operation == "add")
    #expect(row.requestedValue == decimal("50")); #expect(row.delta == decimal("50")); #expect(row.afterValue == decimal("62.4"))
    #expect(row.beforeValue == nil); #expect(row.notes == nil); #expect(row.requestID == nil)
    #expect(row.userID == 42); #expect(row.operatorUserID == 7); #expect(row.userEmail == "wang@example.invalid")
    #expect(row.createdAt == ServerTime.parseTimestamp("2026-10-22T01:20:00.123Z"))

    let sparse = try JSONDecoder().decode(UserAdjustment.self, from: Data(#"{"id":3,"requested_value":"abc","user_id":"x"}"#.utf8))
    #expect(sparse.kind == ""); #expect(sparse.requestedValue == nil); #expect(sparse.userID == nil); #expect(sparse.createdAt == nil)
}

@Test func userAdjustmentQueryEncodesUTCZuluAndCapsPageSize() throws {
    #expect(fields(try UserAdjustmentQuery().queryItems()) == ["kind": "balance", "page": "1", "page_size": "20"])

    var query = UserAdjustmentQuery()
    query.userID = 42; query.actionID = ledgerAction; query.keyword = " wang+ops@example.invalid "
    query.startTime = Date(timeIntervalSince1970: 1_799_999_880); query.endTime = Date(timeIntervalSince1970: 1_800_000_300)
    query.pageSize = 200
    let sent = fields(try query.queryItems())
    #expect(sent == ["kind": "balance", "user_id": "42", "action_id": "8f1c2d3e-4a5b-4c6d-8e7f-901a2b3c4d5e", "keyword": "wang+ops@example.invalid",
                     "start_time": "2027-01-15T07:58:00Z", "end_time": "2027-01-15T08:05:00Z", "page": "1", "page_size": "200"])
    #expect(!sent.values.contains { $0.contains("+08:00") })

    var byRequest = UserAdjustmentQuery()
    byRequest.requestID = " a1b2 "; byRequest.kind = ""
    #expect(fields(try byRequest.queryItems()) == ["request_id": "a1b2", "page": "1", "page_size": "20"])

    let invalid: [(inout UserAdjustmentQuery) -> Void] = [
        { $0.pageSize = 201 }, { $0.pageSize = 0 }, { $0.page = 0 }, { $0.userID = 0 }, { $0.kind = "money" },
        { $0.keyword = String(repeating: "a", count: 101) }, { $0.requestID = String(repeating: "r", count: 65) },
        { $0.startTime = Date(timeIntervalSince1970: 100); $0.endTime = Date(timeIntervalSince1970: 100) },
    ]
    for change in invalid {
        var candidate = UserAdjustmentQuery()
        change(&candidate)
        #expect(throws: APIError.self) { _ = try candidate.queryItems() }
    }
}

@Test func userAdjustmentsSendsGETWithExactQuery() async throws {
    let page = #"{"items":[{"id":5,"kind":"balance","user_id":42}],"total":1,"page":1,"page_size":20,"pages":1,"summary":{"record_count":1}}"#
    let transport = ScriptedTransport { _ in okReply(page) }
    let client = APIClient(server: stubServer(), credential: stubTokens(), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
    var query = UserAdjustmentQuery()
    query.userID = 42; query.requestID = "a1b2"
    let result = try await client.userAdjustments(query: query)
    #expect(result.items.map(\.id) == [5]); #expect(result.total == 1)
    let request = try #require(await transport.requests.first)
    #expect(await transport.requests.count == 1)
    #expect(request.httpMethod == "GET"); #expect(request.url?.path == "/api/v1/admin/user-adjustments"); #expect(request.httpBody == nil)
    #expect(sentFields(request) == ["kind": "balance", "user_id": "42", "request_id": "a1b2", "page": "1", "page_size": "20"])
}
