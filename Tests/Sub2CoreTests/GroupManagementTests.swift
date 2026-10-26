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
    #expect(zero.matches(AdminGroup(id: 10, name: "zero", dailyLimitUSD: 0)))
    #expect(!zero.matches(AdminGroup(id: 10, name: "unlimited", dailyLimitUSD: nil)))
    var observed = AdminGroup(id: 10, name: "unchanged", description: "", isExclusive: false, monthlyLimitUSD: Decimal(string: "123.45678901"))
    #expect(input.matches(observed))
    observed.monthlyLimitUSD = 9
    #expect(!input.matches(observed))
}

@Test func invalidGroupWritesFailBeforeSending() async throws {
    let transport = GroupTransport(); let client = groupClient(transport); let identity = await client.userWriteIdentity()
    let invalid = [GroupCreateRequest(name: " "), GroupCreateRequest(name: "valid", rateMultiplier: 0), GroupCreateRequest(name: "valid", platform: "unknown"), GroupCreateRequest(name: "valid", platform: "composite"), GroupCreateRequest(name: "valid", rpmLimit: -1), GroupCreateRequest(name: "valid", dailyLimitUSD: .amount(-1))]
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
    let capacity = try #require(try await client.groupCapacities(groupIDs: [10], serverFiltered: false).first)
    #expect(capacity.concurrencyUsed == 4 && capacity.sessionsUsed == nil && capacity.rpmUsed == 8)
    #expect(await transport.requests().last?.url?.path == "/api/v1/admin/groups/capacity-summary")
}

@Test func groupSortOrderDecodesAndDisplayOrderMatchesServer() throws {
    let sorted = try JSONDecoder().decode(AdminGroup.self, from: Data(#"{"id":3,"name":"排序","platform":"openai","status":"active","sort_order":3}"#.utf8))
    #expect(sorted.sortOrder == 3)
    #expect(try JSONDecoder().decode(AdminGroup.self, from: JSONEncoder().encode(sorted)) == sorted)
    #expect(try JSONDecoder().decode(AdminGroup.self, from: Data(groupDTO.utf8)).sortOrder == nil)
    #expect(AdminGroup(id: 1, name: "默认").sortOrder == nil)
    let groups = [AdminGroup(id: 1, name: "a", sortOrder: 2), AdminGroup(id: 9, name: "b", sortOrder: 0),
                  AdminGroup(id: 3, name: "c"), AdminGroup(id: 4, name: "d", sortOrder: 0)]
    #expect(groups.sorted(by: AdminGroup.displayOrder).map(\.id) == [3, 4, 9, 1])
}

/// The backend reads only the literal `true` and then ignores `platform`, so the platform is applied here.
@Test func allGroupsIncludeInactiveSendsLiteralTrueAndFiltersPlatformLocally() async throws {
    let mixed = #"[{"id":1,"name":"o","platform":"openai","status":"inactive"},{"id":2,"name":"a","platform":"anthropic","status":"inactive"}]"#
    let transport = GroupTransport { _ in HTTPResponse(statusCode: 200, data: Data("{\"code\":0,\"data\":\(mixed)}".utf8)) }
    let client = groupClient(transport)
    #expect(try await client.allGroups(includeInactive: true).map(\.id) == [1, 2])
    #expect(try await client.allGroups(platform: "anthropic", includeInactive: true).map(\.id) == [2])
    #expect(try await client.allGroups(platform: "anthropic").count == 2)
    let queries = await transport.requests().map { $0.url?.query }
    #expect(queries == ["include_inactive=true", "platform=anthropic&include_inactive=true", "platform=anthropic"])
}

// MARK: - S5-01 读：模型与读接口

private func groupScriptedClient(_ transport: ScriptedTransport, clock: RequestClock = .immediate, serverTimeZone: ServerTimeZone = .device,
                                 serverClock: ServerClock = ServerClock(), cacheIdentity: ConditionalCache.Identity? = nil) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture"), deviceID: stubDeviceID, transport: transport, requestClock: clock,
              cacheIdentity: cacheIdentity, serverTimeZone: serverTimeZone, serverClock: serverClock)
}
private func groupQueryItems(_ request: URLRequest?) -> [URLQueryItem] {
    request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
}
/// Every value of a query item, so a repeated `group_id` is read in full.
private func groupQueryValues(_ request: URLRequest?, _ name: String) -> [String] {
    groupQueryItems(request).filter { $0.name == name }.compactMap(\.value)
}
private func groupPageJSON(_ ids: [Int], total: Int, page: Int) -> String {
    let items = ids.map { #"{"id":\#($0),"name":"分组\#($0)","platform":"anthropic","status":"active"}"# }.joined(separator: ",")
    return #"{"items":[\#(items)],"total":\#(total),"page":\#(page),"page_size":1000}"#
}
private func capacityRow(_ id: Int) -> String {
    #"{"group_id":\#(id),"concurrency_used":1,"concurrency_max":2,"sessions_used":null,"sessions_max":0,"rpm_used":3,"rpm_max":4}"#
}
/// One row per requested `group_id`, plus `extra` rows the request did not ask for.
private func capacityReply(_ request: URLRequest, extra: [Int] = []) -> HTTPResponse {
    okReply("[" + (groupQueryValues(request, "group_id").compactMap(Int.init) + extra).map(capacityRow).joined(separator: ",") + "]")
}
private func tooManyIDs(max: String) -> HTTPResponse {
    errorReply(400, reason: "TOO_MANY_IDS", extra: #","metadata":{"field":"group_ids","max":"\#(max)"}"#)
}

@Test func adminGroupDecodesBucketCountsAndClientRestrictionFields() throws {
    func decode(_ extra: String) throws -> AdminGroup {
        try JSONDecoder().decode(AdminGroup.self, from: Data(#"{"id":10,"name":"桶","platform":"anthropic","status":"active"\#(extra)}"#.utf8))
    }
    let full = try decode(#","account_count":6,"active_account_count":3,"rate_limited_account_count":1,"error_account_count":1,"idle_account_count":2,"claude_code_only":true,"fallback_group_id":7"#)
    #expect(full.errorAccountCount == 1 && full.idleAccountCount == 2 && full.claudeCodeOnly == true && full.fallbackGroupID == 7)
    #expect(full.counts == GroupAccountCounts(accountCount: 6, activeAccountCount: 3, rateLimitedAccountCount: 1, errorAccountCount: 1, idleAccountCount: 2))
    #expect(try JSONDecoder().decode(AdminGroup.self, from: JSONEncoder().encode(full)) == full)
    let zero = try decode(#","error_account_count":0,"idle_account_count":0,"claude_code_only":false"#)
    #expect(zero.errorAccountCount == 0 && zero.idleAccountCount == 0 && zero.claudeCodeOnly == false)
    // An older server without F04 leaves the keys out: nil, not zero, so S5-02 takes the fallback.
    let legacy = try decode("")
    #expect(legacy.errorAccountCount == nil && legacy.idleAccountCount == nil && legacy.claudeCodeOnly == nil && legacy.fallbackGroupID == nil)
    #expect(legacy.counts == GroupAccountCounts())
    #expect(try decode(#","fallback_group_id":null"#).fallbackGroupID == nil)
    let built = AdminGroup(id: 1, name: "默认")
    #expect(built.errorAccountCount == nil && built.idleAccountCount == nil && built.claudeCodeOnly == nil && built.fallbackGroupID == nil)
}

@Test func groupAccountCountsDecodesMemberBatchShapeWithMissingFields() throws {
    let full = try JSONDecoder().decode(GroupAccountCounts.self, from: Data(#"{"account_count":6,"active_account_count":4,"rate_limited_account_count":1,"error_account_count":0,"idle_account_count":1}"#.utf8))
    #expect(full == GroupAccountCounts(accountCount: 6, activeAccountCount: 4, rateLimitedAccountCount: 1, errorAccountCount: 0, idleAccountCount: 1))
    #expect(try JSONDecoder().decode(GroupAccountCounts.self, from: Data("{}".utf8)) == GroupAccountCounts(accountCount: 0, activeAccountCount: 0, rateLimitedAccountCount: 0))
    let group = AdminGroup(id: 1, name: "成员", accountCount: 6, activeAccountCount: 4, rateLimitedAccountCount: 1, errorAccountCount: 0, idleAccountCount: 1)
    #expect(group.counts == full)
}

@Test func groupPlatformConcreteDropsCompositeAndCreateDefaultsToAnthropic() throws {
    #expect(GroupPlatform.concrete == GroupPlatform.values.filter { $0 != "composite" })
    #expect(GroupPlatform.concrete.count == 13 && !GroupPlatform.concrete.contains("composite"))
    let request = GroupCreateRequest(name: "x")
    #expect(request.platform == "anthropic")
    let body = try #require(JSONSerialization.jsonObject(with: request.requestBody()) as? [String: Any])
    #expect(body["platform"] as? String == "anthropic")
    #expect(throws: APIError.self) { try GroupCreateRequest(name: "x", platform: "composite").validate() }
    #expect(GroupPlatform.title("composite") == "组合分组" && GroupPlatform.title("anthropic") == "Anthropic")
}

@Test func groupsPageSizeDefaultsToStandardAndPassesThrough() async throws {
    let transport = ScriptedTransport { _ in okReply(groupPageJSON([10], total: 1, page: 1)) }
    let client = groupScriptedClient(transport)
    _ = try await client.groups(page: 1)
    _ = try await client.groups(page: 1, pageSize: 5, search: "高级")
    _ = try await client.groups(page: 1, pageSize: PageSize.maximum)
    let sent = await transport.requests
    #expect(sent.map { groupQueryValues($0, "page_size") } == [["20"], ["5"], ["1000"]])
    #expect(groupQueryValues(sent[1], "search") == ["高级"])
    #expect(sent.allSatisfy { $0.url?.path == "/api/v1/admin/groups" })
}

@Test func groupListPagesWithMaximumPageSizeUntilTotalWithoutStatusOrSort() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(groupPageJSON([1, 2], total: 3, page: 1))),
                                               .reply(okReply(groupPageJSON([2, 3], total: 3, page: 2)))])
    let client = groupScriptedClient(transport)
    #expect(try await client.groupList().map(\.id) == [1, 2, 3])
    let sent = await transport.requests
    #expect(sent.map { groupQueryValues($0, "page") } == [["1"], ["2"]])
    #expect(sent.allSatisfy { groupQueryValues($0, "page_size") == ["1000"] })
    #expect(sent.allSatisfy { request in ["status", "sort_by", "sort_order", "search", "platform"].allSatisfy { groupQueryValues(request, $0).isEmpty } })
}

@Test func groupListStopsOnEmptyPageAndPageCap() async throws {
    let empty = ScriptedTransport(script: [.reply(okReply(groupPageJSON([1], total: 5_000, page: 1))), .reply(okReply(groupPageJSON([], total: 5_000, page: 2)))])
    #expect(try await groupScriptedClient(empty).groupList().map(\.id) == [1])
    #expect(await empty.requests.count == 2)
    let counter = CallCounter()
    let endless = ScriptedTransport { _ in let page = counter.next(); return okReply(groupPageJSON([page], total: 1_000_000, page: page)) }
    #expect(try await groupScriptedClient(endless).groupList().count == GroupListPolicy.maxPages)
    #expect(await endless.requests.count == GroupListPolicy.maxPages)
    // Only a cancellation while a page is on the wire is covered: on the actor nothing suspends between two pages, so the
    // page-to-page check(snapshot) is a guard kept by review (S5-01 第七节).
    let started = OpenGate(), release = OpenGate()
    let slow = ScriptedTransport { _ in await started.open(); await release.wait(); return okReply(groupPageJSON([1], total: 3, page: 1)) }
    let client = groupScriptedClient(slow)
    let pending = Task { try await client.groupList() }
    await started.wait(); await client.cancelAll(); await release.open()
    await #expect(throws: CancellationError.self) { _ = try await pending.value }
    #expect(await slow.requests.count == 1)
}

@Test func groupListRevalidatesThroughConditionalCache() async throws {
    let transport = ScriptedTransport { request in
        sentHeader(request, "If-None-Match") == "\"g1\"" ? HTTPResponse(statusCode: 304, headers: ["etag": "\"g1\""], data: Data())
            : okReply(groupPageJSON([10, 11], total: 2, page: 1), headers: ["etag": "\"g1\""])
    }
    let client = groupScriptedClient(transport, cacheIdentity: ConditionalCache.Identity(userID: 1, authMethod: "admin_api_key"))
    let first = try await client.groupList()
    let second = try await client.groupList()
    #expect(first.map(\.id) == [10, 11] && second == first)
    #expect(await transport.requests.map { sentHeader($0, "If-None-Match") } == [nil, "\"g1\""])
}

@Test func groupUsageSummaryDecodesDecimalsAndSendsTimezoneOnlyWhenGiven() async throws {
    let rows = #"[{"group_id":1,"today_cost":933.3,"yesterday_cost":0,"total_cost":"12.34567891"},{"group_id":2}]"#
    let transport = ScriptedTransport { _ in okReply(rows) }
    let client = groupScriptedClient(transport)
    #expect(try await client.groupUsageSummary() == [
        GroupUsageSummary(groupID: 1, todayCost: Decimal(string: "933.3"), yesterdayCost: 0, totalCost: Decimal(string: "12.34567891")),
        GroupUsageSummary(groupID: 2, todayCost: nil, yesterdayCost: nil, totalCost: nil)
    ])
    let shanghai = try #require(ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00"))
    #expect(try await client.groupUsageSummary(timezone: shanghai).map(\.id) == [1, 2])
    let sent = await transport.requests
    #expect(sent.allSatisfy { $0.url?.path == "/api/v1/admin/groups/usage-summary" && $0.timeoutInterval == 45 })
    #expect(groupQueryItems(sent[0]).isEmpty)
    #expect(groupQueryItems(sent[1]).map(\.name) == ["timezone"] && groupQueryValues(sent[1], "timezone") == ["Asia/Shanghai"])
    #expect(!(sent[1].url?.absoluteString.contains("08") ?? true))
}

@Test func groupStatsReturnsNilWithoutSubscriptionsTotalKey() async throws {
    let current = #"{"total_api_keys":38,"active_api_keys":30,"total_requests":0,"total_cost":1.5,"subscriptions_total":12,"subscriptions_active":9,"generated_at":"2026-10-23T08:00:00Z"}"#
    let legacy = #"{"total_api_keys":0,"active_api_keys":0,"total_requests":0,"total_cost":0}"#
    let transport = ScriptedTransport(script: [.reply(okReply(current)), .reply(okReply(legacy))])
    let client = groupScriptedClient(transport)
    #expect(try await client.groupStats(id: 10) == GroupStats(totalAPIKeys: 38, activeAPIKeys: 30, subscriptionsTotal: 12, subscriptionsActive: 9))
    #expect(try await client.groupStats(id: 10) == nil)
    #expect(await transport.requests.allSatisfy { $0.url?.path == "/api/v1/admin/groups/10/stats" })
    #expect(try #require(await thrownAPIError { _ = try await client.groupStats(id: 0) }).kind == .validation)
    #expect(await transport.requests.count == 2)
}

@Test func groupCapacitiesFilterOnServerOrLocally() async throws {
    let transport = ScriptedTransport { request in capacityReply(request, extra: [99]) }
    let client = groupScriptedClient(transport)
    let first = try #require(try await client.groupCapacities(groupIDs: [10], serverFiltered: true).first)
    #expect(first.groupID == 10 && first.sessionsUsed == nil && first.rpmMax == 4)
    #expect(try await client.groupCapacities(groupIDs: [0, 10], serverFiltered: true).map(\.groupID) == [10])
    #expect(try await client.groupCapacities(groupIDs: [11, 10, 10], serverFiltered: true).map(\.groupID) == [10, 11])
    #expect(try await client.groupCapacities(groupIDs: [], serverFiltered: true).isEmpty)
    #expect(try await client.groupCapacities(groupIDs: [0, -1], serverFiltered: false).isEmpty)
    #expect(await transport.requests.map { groupQueryValues($0, "group_id") } == [["10"], ["10"], ["10", "11"]])
    #expect(await transport.requests.allSatisfy { $0.url?.path == "/api/v1/admin/groups/capacity-summary" })
    // 101 ids: two requests, and a row nobody asked for (99 in the second reply) is dropped.
    #expect(try await client.groupCapacities(groupIDs: Array(1...101), serverFiltered: true).map(\.groupID) == Array(1...101))
    #expect(await transport.requests.dropFirst(3).map { groupQueryValues($0, "group_id").count } == [100, 1])
    let all = ScriptedTransport { _ in okReply("[" + [10, 11].map(capacityRow).joined(separator: ",") + "]") }
    #expect(try await groupScriptedClient(all).groupCapacities(groupIDs: [10], serverFiltered: false).map(\.groupID) == [10])
    let unfiltered = await all.requests
    #expect(unfiltered.count == 1 && groupQueryItems(unfiltered.first).isEmpty)
}

@Test func groupCapacitiesSplitOnceOnTooManyIDs() async throws {
    let limited = ScriptedTransport { request in groupQueryValues(request, "group_id").count > 50 ? tooManyIDs(max: "50") : capacityReply(request) }
    #expect(try await groupScriptedClient(limited).groupCapacities(groupIDs: Array(1...101), serverFiltered: true).count == 101)
    #expect(await limited.requests.map { groupQueryValues($0, "group_id").count } == [100, 50, 50, 1])
    let stubborn = ScriptedTransport { request in groupQueryValues(request, "group_id").count > 10 ? tooManyIDs(max: "50") : capacityReply(request) }
    let refused = await thrownAPIError { _ = try await groupScriptedClient(stubborn).groupCapacities(groupIDs: Array(1...100), serverFiltered: true) }
    #expect(refused?.reason == "TOO_MANY_IDS")
    #expect(await stubborn.requests.map { groupQueryValues($0, "group_id").count } == [100, 50])
    let missing = ScriptedTransport { _ in errorReply(404, reason: "GROUP_NOT_FOUND") }
    #expect(await thrownAPIError { _ = try await groupScriptedClient(missing).groupCapacities(groupIDs: [10], serverFiltered: true) }?.reason == "GROUP_NOT_FOUND")
}

@Test func groupTodayUsageQueriesServerDayWithAggregateTimeout() async throws {
    let shanghai = try #require(ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00"))
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-22T17:00:00Z"))
    let row = #"{"groups":[{"group_id":10,"group_name":"标准分组","requests":10194,"total_tokens":62900000,"cost":999,"actual_cost":933.3,"account_cost":370.27}],"start_date":"2026-10-23","end_date":"2026-10-23"}"#
    let transport = ScriptedTransport(script: [.reply(okReply(row)), .reply(okReply(#"{"groups":[]}"#)), .reply(okReply(#"{"groups":null}"#)), .reply(okReply(row))])
    let client = groupScriptedClient(transport, serverTimeZone: shanghai, serverClock: ServerClock(localNow: { instant }))
    #expect(try await client.groupTodayUsage(id: 10) == GroupTodayUsage(requests: 10194, totalTokens: 62_900_000, accountCost: Decimal(string: "370.27")))
    #expect(try await client.groupTodayUsage(id: 10) == .zero)
    #expect(try await client.groupTodayUsage(id: 10) == .zero)
    let newYork = try #require(ServerTimeZone(identifier: "America/New_York", utcOffset: "-04:00"))
    _ = try await client.groupTodayUsage(id: 10, serverTimeZone: newYork)
    let sent = await transport.requests
    #expect(sent[0].url?.path == "/api/v1/admin/dashboard/groups" && sent[0].timeoutInterval == 45)
    #expect(groupQueryValues(sent[0], "start_date") == ["2026-10-23"] && groupQueryValues(sent[0], "end_date") == ["2026-10-23"])
    #expect(groupQueryValues(sent[0], "timezone") == ["Asia/Shanghai"] && groupQueryValues(sent[0], "group_id") == ["10"])
    let url = sent[0].url?.absoluteString ?? ""
    #expect(!url.contains("+08:00") && !url.contains("%2B08"))
    #expect(groupQueryValues(sent[3], "start_date") == ["2026-10-22"] && groupQueryValues(sent[3], "end_date") == ["2026-10-22"])
    #expect(groupQueryValues(sent[3], "timezone") == ["America/New_York"])
    #expect(try #require(await thrownAPIError { _ = try await client.groupTodayUsage(id: 0) }).kind == .validation)
    #expect(await transport.requests.count == 4)
}

@Test func fallbackCountsReadOnlyTotal() async throws {
    let keys = #"{"items":[{"id":1,"key":"sk-fixture-plain","name":{"unexpected":true}}],"total":38,"page":1,"page_size":1,"pages":38}"#
    let transport = ScriptedTransport { request in
        request.url?.path.hasSuffix("/subscriptions") == true ? okReply(#"{"items":[{"id":3,"bad":[1]}],"total":7,"page":1,"page_size":1}"#) : okReply(keys)
    }
    let client = groupScriptedClient(transport)
    #expect(try await client.groupAPIKeyCount(id: 10, maskedView: true) == 38)
    #expect(try await client.groupAPIKeyCount(id: 10, maskedView: false) == 38)
    #expect(try await client.activeSubscriptionCount(groupID: 10) == 7)
    let sent = await transport.requests
    #expect(sent[0].url?.path == "/api/v1/admin/groups/10/api-keys" && sent[1].url?.path == "/api/v1/admin/groups/10/api-keys")
    #expect(groupQueryValues(sent[0], "page") == ["1"] && groupQueryValues(sent[0], "page_size") == ["1"] && groupQueryValues(sent[0], "key_view") == ["masked"])
    #expect(groupQueryValues(sent[1], "key_view").isEmpty && groupQueryValues(sent[1], "page_size") == ["1"])
    #expect(sent[2].url?.path == "/api/v1/admin/subscriptions")
    #expect(groupQueryValues(sent[2], "page") == ["1"] && groupQueryValues(sent[2], "page_size") == ["1"])
    #expect(groupQueryValues(sent[2], "group_id") == ["10"] && groupQueryValues(sent[2], "status") == ["active"])
    let noTotal = groupScriptedClient(ScriptedTransport { _ in okReply(#"{"items":[],"page":1,"page_size":1}"#) })
    #expect(await thrownAPIError { _ = try await noTotal.groupAPIKeyCount(id: 10, maskedView: true) }?.kind == .response)
    #expect(try #require(await thrownAPIError { _ = try await client.groupAPIKeyCount(id: 0, maskedView: true) }).kind == .validation)
    #expect(try #require(await thrownAPIError { _ = try await client.activeSubscriptionCount(groupID: 0) }).kind == .validation)
    #expect(await transport.requests.count == 3)
}
