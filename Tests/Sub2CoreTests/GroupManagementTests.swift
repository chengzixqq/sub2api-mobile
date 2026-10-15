import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let groupDTO = #"{"id":10,"name":"标准分组","description":"按量使用","platform":"openai","status":"active","rate_multiplier":"1.23456789","daily_limit_usd":"25.00000001","weekly_limit_usd":null,"is_exclusive":false,"subscription_type":"standard","rpm_limit":60,"account_count":12,"active_account_count":10,"billing_locked":false,"model_routing":{"private":[2]},"profit_control_enabled":true}"#
private actor GroupTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) throws -> HTTPResponse
    private var sent: [URLRequest] = []
    init(_ handler: @escaping @Sendable (URLRequest) throws -> HTTPResponse = { _ in HTTPResponse(statusCode: 200, data: Data("{\"code\":0,\"data\":\(groupDTO)}".utf8)) }) { self.handler = handler }
    func data(for request: URLRequest) async throws -> HTTPResponse { sent.append(request); return try handler(request) }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw APIError.invalidResponse }
    func requests() -> [URLRequest] { sent }
}
private func groupClient(_ transport: GroupTransport) -> APIClient {
    APIClient(server: ServerProfile(name: "分组测试", baseURL: URL(string: "https://groups.example.invalid")!, authentication: .adminKey), credential: .adminKey("fixture-key"), transport: transport)
}

@Test func groupDTOUsesDecimalAndMissingCountersRemainUnavailable() throws {
    let group = try JSONDecoder().decode(AdminGroup.self, from: Data(groupDTO.utf8))
    #expect(group.rateMultiplier == Decimal(string: "1.23456789"))
    #expect(group.dailyLimitUSD == Decimal(string: "25.00000001"))
    #expect(group.weeklyLimitUSD == nil && group.monthlyLimitUSD == nil)
    #expect(group.accountCount == 12 && group.rateLimitedAccountCount == nil)
    let minimal = try JSONDecoder().decode(AdminGroup.self, from: Data(#"{"id":3,"name":"旧站点","platform":"anthropic","status":"inactive"}"#.utf8))
    #expect(minimal.rateMultiplier == nil && minimal.isExclusive == nil && minimal.accountCount == nil && minimal.rpmLimit == nil)
    #expect(try JSONDecoder().decode(AdminGroup.self, from: JSONEncoder().encode(group)) == group)
}

@Test func groupUpdateOnlyEncodesChangesAndSupportsExplicitUnlimited() throws {
    let input = GroupUpdateRequest(description: "", isExclusive: false, dailyLimitUSD: .unlimited, monthlyLimitUSD: .amount(Decimal(string: "123.45678901")!))
    let body = try #require(JSONSerialization.jsonObject(with: input.requestBody()) as? [String: Any])
    #expect(body["description"] as? String == "" && body["is_exclusive"] as? Bool == false)
    #expect(body["daily_limit_usd"] is NSNull)
    #expect(body["weekly_limit_usd"] == nil && body["rate_multiplier"] == nil && body["platform"] == nil)
    #expect(body["model_routing"] == nil && body["profit_control_enabled"] == nil && body["copy_accounts_from_group_ids"] == nil)
    struct LimitWire: Decodable { let monthly_limit_usd: Decimal }
    let decoded = try JSONDecoder().decode(LimitWire.self, from: input.requestBody())
    #expect(decoded.monthly_limit_usd == Decimal(string: "123.45678901"))
    let zero = GroupUpdateRequest(dailyLimitUSD: .amount(0))
    let zeroBody = try #require(JSONSerialization.jsonObject(with: zero.requestBody()) as? [String: Any])
    #expect(zeroBody["daily_limit_usd"] as? Int == 0 && !(zeroBody["daily_limit_usd"] is NSNull))
    var observed = AdminGroup(id: 10, name: "unchanged", description: "", isExclusive: false, monthlyLimitUSD: Decimal(string: "123.45678901"))
    #expect(input.matches(observed))
    observed.monthlyLimitUSD = 9
    #expect(!input.matches(observed))
}

@Test func invalidGroupWritesFailBeforeSending() async throws {
    let transport = GroupTransport(); let client = groupClient(transport); let identity = await client.userWriteIdentity()
    let invalid = [GroupCreateRequest(name: " "), GroupCreateRequest(name: "valid", rateMultiplier: 0), GroupCreateRequest(name: "valid", platform: "unknown"), GroupCreateRequest(name: "valid", rpmLimit: -1), GroupCreateRequest(name: "valid", dailyLimitUSD: .amount(-1))]
    for input in invalid { await #expect(throws: APIError.self) { try await client.createGroup(input, identity: identity) } }
    #expect(throws: APIError.self) { try GroupUpdateRequest().validate() }
    #expect(throws: APIError.self) { try GroupUpdateRequest(status: "disabled").validate() }
    #expect(throws: APIError.self) { try GroupUpdateRequest(rateMultiplier: Decimal.nan).validate() }
    #expect(await transport.requests().isEmpty)
}

@Test func groupPaginationFiltersAndActiveSelectorUseRealRoutes() async throws {
    let transport = GroupTransport { request in
        let data: String
        if request.url?.path.hasSuffix("/all") == true { data = "[\(groupDTO)]" }
        else { data = "{\"items\":[\(groupDTO)],\"total\":21,\"page\":1,\"page_size\":20}" }
        return HTTPResponse(statusCode: 200, data: Data("{\"code\":0,\"data\":\(data)}".utf8))
    }
    let client = groupClient(transport)
    let page = try await client.groups(page: 1, search: " A&B 中文 ", platform: "openai", status: "inactive")
    #expect(page.hasMore && page.items.count == 1)
    #expect(try await client.allGroups(platform: "anthropic").count == 1)
    let requests = await transport.requests()
    let url = try #require(requests[0].url)
    let params = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(params.first { $0.name == "search" }?.value == "A&B 中文")
    #expect(params.first { $0.name == "status" }?.value == "inactive")
    #expect(params.first { $0.name == "platform" }?.value == "openai")
    #expect(requests[1].url?.path == "/api/v1/admin/groups/all")
    #expect(requests[1].url?.query == "platform=anthropic")
}

@Test func groupWritesUseOneRequestAndRejectStaleIdentity() async throws {
    let transport = GroupTransport { _ in throw URLError(.timedOut) }
    let client = groupClient(transport); let identity = await client.userWriteIdentity()
    await #expect(throws: APIError.self) { try await client.createGroup(GroupCreateRequest(name: "new"), identity: identity) }
    await #expect(throws: APIError.self) { try await client.updateGroup(id: 10, input: GroupUpdateRequest(status: "inactive"), identity: identity) }
    await #expect(throws: APIError.self) { try await client.deleteGroup(id: 10, identity: identity) }
    let sent = await transport.requests()
    #expect(sent.map(\.httpMethod) == ["POST", "PUT", "DELETE"])
    #expect(sent.allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == nil })
    await client.cancelAll()
    await #expect(throws: CancellationError.self) { try await client.updateGroup(id: 10, input: GroupUpdateRequest(name: "stale"), identity: identity) }
    await #expect(throws: CancellationError.self) { try await client.createGroup(GroupCreateRequest(name: "stale"), identity: identity) }
    #expect(await transport.requests().count == 3)
}

@Test func groupDeletionAndCapacityUseRealResponseShapes() async throws {
    let transport = GroupTransport { request in
        let data = request.httpMethod == "DELETE" ? #"{"message":"Group deleted successfully"}"# : #"[{"group_id":10,"concurrency_used":4,"concurrency_max":20,"sessions_used":null,"sessions_max":0,"rpm_used":8,"rpm_max":60}]"#
        return HTTPResponse(statusCode: 200, data: Data("{\"code\":0,\"data\":\(data)}".utf8))
    }
    let client = groupClient(transport); let identity = await client.userWriteIdentity()
    try await client.deleteGroup(id: 10, identity: identity)
    let capacity = try #require(try await client.groupCapacities().first)
    #expect(capacity.concurrencyUsed == 4 && capacity.sessionsUsed == nil && capacity.rpmUsed == 8)
    #expect(await transport.requests().last?.url?.path == "/api/v1/admin/groups/capacity-summary")
}
