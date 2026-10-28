import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let analyticsZone = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let siteLocal = ServerTimeZone(identifier: "Local", utcOffset: "+08:00")!
/// 2026-10-15T00:00:00Z
private let analyticsStart = Date(timeIntervalSince1970: 1_792_022_400)
private let minimalPayloads = [
    "stats": #"{"total_requests":0,"total_tokens":0}"#, "trend": #"{"trend":null}"#, "models": #"{"models":null}"#, "groups": #"{"groups":null}"#,
    "users-ranking": #"{"ranking":null}"#, "users-trend": #"{"trend":null}"#, "request-types": #"{"request_types":null}"#
]

private func analyticsScope(_ span: TimeInterval = 3_600, granularity: AnalyticsGranularity = .hour, zone: ServerTimeZone = analyticsZone,
                            groupID: Int? = nil, model: String? = nil, source: ModelSource? = nil, requestType: UsageRequestType? = nil) -> AnalyticsQuery {
    AnalyticsQuery(start: analyticsStart, end: analyticsStart.addingTimeInterval(span), granularity: granularity, timeZone: zone, groupID: groupID,
                   model: model, modelSource: source, requestType: requestType)
}
/// Answers each path's last component with the given payload, else with the smallest valid one.
private func analyticsTransport(_ payloads: [String: String] = [:]) -> ScriptedTransport {
    ScriptedTransport { request in
        let name = request.url?.lastPathComponent ?? ""
        return okReply(payloads[name] ?? minimalPayloads[name] ?? "{}")
    }
}
private func analyticsClient(_ transport: ScriptedTransport) -> APIClient {
    let profile = ServerProfile(name: "Fixture", baseURL: URL(string: "https://analysis.example.invalid")!, authentication: .adminKey)
    return APIClient(server: profile, credential: .adminKey("fixture"), transport: transport, requestClock: .immediate, serverTimeZone: analyticsZone)
}
private func sentNames(_ request: URLRequest?) -> [String] {
    (request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []).map(\.name)
}
private func sentItems(_ request: URLRequest?) -> [String: String] {
    itemsDictionary(request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? [])
}
private func itemsDictionary(_ items: [URLQueryItem]) -> [String: String] {
    Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
private func decodeJSON<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }

// MARK: - 解码

@Test func analyticsKeepsDecimalProfitAndMissingAccountCostDistinct() throws {
    let value = try decodeJSON(AnalyticsSummary.self, #"{"total_requests":3,"total_tokens":2000000,"total_actual_cost":"9007199254740993.12","total_account_cost":"9007199254740993.11"}"#)
    #expect(value.profit == Decimal(string: "0.01"))
    let missing = try decodeJSON(AnalyticsSummary.self, #"{"total_requests":0,"total_tokens":0,"total_actual_cost":0}"#)
    #expect(missing.accountCost == nil)
    #expect(missing.profit == nil)
    let null = try decodeJSON(AnalyticsSummary.self, #"{"total_requests":0,"total_tokens":0,"total_actual_cost":1,"total_account_cost":null}"#)
    #expect(null.accountCost == nil)
    #expect(null.profit == nil)
    let zero = try decodeJSON(AnalyticsSummary.self, #"{"total_requests":1,"total_tokens":1,"total_actual_cost":"2.50","total_account_cost":0}"#)
    #expect(zero.accountCost == 0)
    #expect(zero.profit == Decimal(string: "2.50"))
}

@Test func analyticsSummaryDecodesStandardCostCacheTokensAndEndpoints() throws {
    let json = #"""
    {"total_requests":12,"total_input_tokens":100,"total_output_tokens":200,"total_cache_tokens":300,"total_cache_creation_tokens":120,
     "total_cache_read_tokens":180,"total_tokens":600,"total_cost":"9.75","total_actual_cost":4.5,"total_account_cost":"1.25","average_duration_ms":812.5,
     "endpoints":[{"endpoint":"/v1/messages","requests":8,"total_tokens":400,"cost":"6.5","actual_cost":3},
                  {"endpoint":"/v1/chat/completions","requests":4,"total_tokens":200,"cost":3.25,"actual_cost":"1.5"}],
     "upstream_endpoints":[{"endpoint":"/v1/responses","requests":7,"total_tokens":350,"cost":"5","actual_cost":"2.5"},
                           {"endpoint":"/v1/messages","requests":5,"total_tokens":250,"cost":"4.75","actual_cost":2}]}
    """#
    let value = try decodeJSON(AnalyticsSummary.self, json)
    #expect(value.requests == 12 && value.tokens == 600 && value.inputTokens == 100 && value.outputTokens == 200)
    #expect(value.cacheTokens == 300 && value.cacheCreationTokens == 120 && value.cacheReadTokens == 180)
    #expect(value.standardCost == Decimal(string: "9.75") && value.actualCost == Decimal(string: "4.5") && value.accountCost == Decimal(string: "1.25"))
    #expect(value.averageDurationMs == 812.5)
    let endpoints = try #require(value.endpoints)
    #expect(endpoints.map(\.id) == ["/v1/messages", "/v1/chat/completions"])
    #expect(endpoints.map(\.requests) == [8, 4] && endpoints.map(\.totalTokens) == [400, 200])
    #expect(endpoints.map(\.standardCost) == [Decimal(string: "6.5"), Decimal(string: "3.25")])
    #expect(endpoints.map(\.actualCost) == [Decimal(3), Decimal(string: "1.5")])
    let upstream = try #require(value.upstreamEndpoints)
    #expect(upstream.map(\.endpoint) == ["/v1/responses", "/v1/messages"])
    #expect(upstream.map(\.requests) == [7, 5] && upstream.map(\.totalTokens) == [350, 250])
    #expect(upstream.map(\.standardCost) == [Decimal(5), Decimal(string: "4.75")])
    #expect(upstream.map(\.actualCost) == [Decimal(string: "2.5"), Decimal(2)])
}

@Test func analyticsSummaryWithoutNewKeysKeepsThemNil() throws {
    let old = try decodeJSON(AnalyticsSummary.self, #"{"total_requests":2,"total_tokens":30,"total_actual_cost":"0.5"}"#)
    #expect(old.standardCost == nil && old.cacheCreationTokens == nil && old.cacheReadTokens == nil)
    #expect(old.endpoints == nil && old.upstreamEndpoints == nil)
    let empty = try decodeJSON(AnalyticsSummary.self, #"{"total_requests":0,"total_tokens":0,"endpoints":[],"upstream_endpoints":null}"#)
    #expect(empty.endpoints == [])
    #expect(empty.upstreamEndpoints == nil)
    let sparse = try decodeJSON(AnalyticsSummary.self, #"{"total_requests":1,"total_tokens":1,"endpoints":[{"endpoint":"/v1/messages"}]}"#)
    let row = try #require(sparse.endpoints?.first)
    #expect(row.requests == 0 && row.totalTokens == 0 && row.standardCost == nil && row.actualCost == nil)
}

@Test func breakdownDecodesStandardCostAndTokenKinds() throws {
    let models = try decodeJSON([AnalyticsBreakdown].self, #"""
    [{"model":"claude-opus-4","requests":9,"input_tokens":10,"output_tokens":20,"cache_creation_tokens":30,"cache_read_tokens":40,"total_tokens":100,
      "cost":"7.5","actual_cost":"3.25","account_cost":"1.20"},
     {"model":"claude-opus-4 -> claude-opus-4-20250514","requests":1,"total_tokens":2,"cost":0,"actual_cost":1}]
    """#)
    let model = models[0]
    #expect(model.inputTokens == 10 && model.outputTokens == 20 && model.cacheCreationTokens == 30 && model.cacheReadTokens == 40)
    #expect(model.standardCost == Decimal(string: "7.5"))
    #expect(model.profit == Decimal(string: "2.05"))
    #expect(model.id == "model:claude-opus-4")
    #expect(models[1].name == "claude-opus-4 -> claude-opus-4-20250514")
    #expect(models[1].profit == nil)
    let groups = try decodeJSON([AnalyticsBreakdown].self,
                                #"[{"group_id":3,"group_name":"高级组","requests":5,"total_tokens":50,"cost":"2","actual_cost":"1.5","account_cost":0}]"#)
    let group = groups[0]
    #expect(group.inputTokens == nil && group.outputTokens == nil && group.cacheCreationTokens == nil && group.cacheReadTokens == nil)
    #expect(group.standardCost == 2)
    #expect(group.id == "group:3" && group.name == "高级组")
    #expect(group.profit == Decimal(string: "1.5"))
}

@Test func trendPointDecodesTokenKindsAndAccountCost() throws {
    let point = try decodeJSON(TrendPoint.self, #"""
    {"date":"2026-10-16 09:00","requests":12,"input_tokens":100,"output_tokens":200,"cache_creation_tokens":30,"cache_read_tokens":40,
     "total_tokens":370,"cost":"9.99","actual_cost":"4.25","account_cost":"1.75"}
    """#)
    #expect(point.inputTokens == 100 && point.outputTokens == 200 && point.cacheCreationTokens == 30 && point.cacheReadTokens == 40)
    #expect(point.totalTokens == 370)
    #expect(point.cost == Decimal(string: "9.99"))
    #expect(point.actualCost == Decimal(string: "4.25"))
    #expect(point.accountCost == Decimal(string: "1.75"))
    let zero = try decodeJSON(TrendPoint.self, #"{"date":"2026-10-16","requests":0,"total_tokens":0,"cost":0,"actual_cost":0,"account_cost":0}"#)
    #expect(zero.accountCost == 0)
    let again = try JSONDecoder().decode(TrendPoint.self, from: JSONEncoder().encode(point))
    #expect(again.accountCost == point.accountCost)
    #expect(again.inputTokens == 100 && again.outputTokens == 200 && again.cacheCreationTokens == 30 && again.cacheReadTokens == 40)
    #expect(try JSONDecoder().decode(TrendPoint.self, from: JSONEncoder().encode(zero)).accountCost == 0)
}

@Test func trendPointWithoutAccountCostKeyIsNilNotZero() throws {
    let inputs = [#"{"date":"2026-10-16","requests":1,"total_tokens":2,"cost":"1","actual_cost":"0.5"}"#,
                  #"{"date":"2026-10-16","requests":1,"total_tokens":2,"cost":"1","actual_cost":"0.5","account_cost":null}"#]
    for input in inputs {
        let point = try decodeJSON(TrendPoint.self, input)
        #expect(point.accountCost == nil)
        #expect([point.inputTokens, point.outputTokens, point.cacheCreationTokens, point.cacheReadTokens].allSatisfy { $0 == 0 })
        #expect(try JSONDecoder().decode(TrendPoint.self, from: JSONEncoder().encode(point)).accountCost == nil)
    }
    let built = TrendPoint(date: "2026-10-16", requests: 1, totalTokens: 2, cost: 1)
    #expect(built.accountCost == nil)
    #expect([built.inputTokens, built.outputTokens, built.cacheCreationTokens, built.cacheReadTokens].allSatisfy { $0 == 0 })
}

// MARK: - 查询参数

@Test func analyticsRejectsInvalidRangesAndIDs() throws {
    let day: TimeInterval = 86_400
    func query(_ span: TimeInterval, accountID: Int? = nil, groupID: Int? = nil, userID: Int? = nil) -> AnalyticsQuery {
        AnalyticsQuery(start: analyticsStart, end: analyticsStart.addingTimeInterval(span), granularity: .day, timeZone: analyticsZone,
                       accountID: accountID, groupID: groupID, userID: userID)
    }
    let invalid = [query(0), query(-1), query(368 * day), query(60, accountID: 0), query(60, accountID: -1), query(60, groupID: 0),
                   query(60, groupID: -3), query(60, userID: 0), query(60, userID: -9)]
    for item in invalid { #expect(throws: APIError.self) { try item.queryItems() } }
    for item in [query(367 * day), query(1), query(60, accountID: 1, groupID: 2, userID: 3)] { _ = try item.queryItems() }
}

@Test func analyticsQuerySendsSiteTimeZoneVerbatimAndUTCInstants() async throws {
    let shanghai = try itemsDictionary(analyticsScope().queryItems())
    #expect(shanghai["timezone"] == "Asia/Shanghai")
    #expect(shanghai["start_time"] == "2026-10-15T00:00:00Z" && shanghai["end_time"] == "2026-10-15T01:00:00Z")
    #expect(try itemsDictionary(analyticsScope(zone: siteLocal).queryItems())["timezone"] == "Local")
    let newYork = try #require(ServerTimeZone(identifier: "America/New_York", utcOffset: "-04:00"))
    let elsewhere = try itemsDictionary(analyticsScope(zone: newYork).queryItems())
    #expect(elsewhere["start_time"] == shanghai["start_time"] && elsewhere["end_time"] == shanghai["end_time"])
    #expect(elsewhere["timezone"] == "America/New_York")
    #expect(analyticsScope() == analyticsScope() && Set([analyticsScope(), analyticsScope()]).count == 1)
    #expect(analyticsScope(zone: siteLocal) != analyticsScope() && analyticsScope(granularity: .day) != analyticsScope())

    let transport = analyticsTransport()
    _ = try await analyticsClient(transport).usageAnalysis(analyticsScope(zone: siteLocal))
    let raw = try #require(await transport.requests.first?.url?.query)
    #expect(!raw.contains("+") && !raw.contains("%2B"))
    #expect(raw.contains("timezone=Local"))
}

@Test func modelSourceOnlyAccompaniesModel() throws {
    for model in [nil, "", "   "] as [String?] {
        let names = try analyticsScope(model: model, source: .upstream).queryItems().map(\.name)
        #expect(!names.contains("model") && !names.contains("model_source"))
    }
    let bare = try itemsDictionary(analyticsScope(model: " m ").queryItems())
    #expect(bare["model"] == "m")
    #expect(bare["model_source"] == nil)
    for source in ModelSource.allCases {
        let items = try analyticsScope(model: "m", source: source).queryItems()
        #expect(itemsDictionary(items)["model_source"] == source.rawValue)
        #expect(items.filter { $0.name == "model_source" }.count == 1)
    }
    #expect(try !analyticsScope(model: "m").queryItems().map(\.name).contains("request_type"))
}

// MARK: - 接口

@Test func analysisSectionsUseExactlyTheSameScopeAndExclusiveRange() async throws {
    let transport = analyticsTransport()
    let client = analyticsClient(transport)
    let query = AnalyticsQuery(start: analyticsStart, end: analyticsStart.addingTimeInterval(3600), granularity: .hour, timeZone: analyticsZone,
                               accountID: 42, groupID: 7, userID: 9, model: " gpt&中文 ")
    _ = try await client.usageAnalysis(query)
    #expect(try await client.usageAnalysisTrend(query).points.isEmpty)
    #expect(try await client.usageAnalysisModels(query, source: .requested).isEmpty)
    #expect(try await client.usageAnalysisGroups(query).isEmpty)
    let requests = await transport.requests
    #expect(requests.count == 4)
    for request in requests {
        #expect(request.httpMethod == "GET")
        let items = sentItems(request)
        #expect(items["start_time"] == "2026-10-15T00:00:00Z")
        #expect(items["end_time"] == "2026-10-15T01:00:00Z")
        #expect(items["account_id"] == "42"); #expect(items["group_id"] == "7"); #expect(items["user_id"] == "9")
        #expect(items["model"] == "gpt&中文"); #expect(items["timezone"] == "Asia/Shanghai")
    }
    let models = try #require(requests.first { $0.url?.lastPathComponent == "models" })
    #expect(sentNames(models).filter { $0 == "model_source" }.count == 1)
    #expect(sentItems(models)["model_source"] == "requested")
}

@Test func granularityIsExplicitAndOnlyOnTrendEndpoints() async throws {
    let transport = analyticsTransport()
    let client = analyticsClient(transport)
    let week = analyticsScope(7 * 86_400, granularity: .hour)
    _ = try await client.usageAnalysisTrend(week)
    _ = try await client.usageAnalysisTrend(analyticsScope(3_600, granularity: .day))
    _ = try await client.usageAnalysisUsersTrend(analyticsScope(granularity: .day), metric: nil, limit: 12)
    _ = try await client.usageAnalysis(week)
    _ = try await client.usageAnalysisModels(week, source: .requested)
    _ = try await client.usageAnalysisGroups(week)
    _ = try await client.usageAnalysisUsersRanking(week, sortBy: nil, limit: 5)
    _ = try await client.usageAnalysisRequestTypes(week)
    let requests = await transport.requests
    #expect(requests.count == 8)
    #expect(requests.prefix(3).map { sentItems($0)["granularity"] } == ["hour", "day", "day"])
    #expect(requests.dropFirst(3).allSatisfy { !sentNames($0).contains("granularity") })
}

@Test func modelsDimensionReplacesTheFilterSource() async throws {
    let transport = analyticsTransport()
    let client = analyticsClient(transport)
    let query = analyticsScope(model: "a", source: .upstream)
    _ = try await client.usageAnalysisModels(query, source: .mapping)
    _ = try await client.usageAnalysisModels(query, source: .requested)
    let requests = await transport.requests
    #expect(requests.map { sentNames($0).filter { $0 == "model_source" }.count } == [1, 1])
    #expect(requests.map { sentItems($0)["model_source"] } == ["mapping", "requested"])
    #expect(requests.allSatisfy { sentItems($0)["model"] == "a" })
    #expect(query.modelSource == .upstream)
}

@Test func trendReplyReadsBucketsInReportedZone() async throws {
    let reported = #"""
    {"trend":[{"date":"2026-10-15 09:00","requests":3,"total_tokens":4,"cost":"1","actual_cost":"0.5","account_cost":"0.2"}],
     "query":{"timezone":"America/New_York"}}
    """#
    let reply = try await analyticsClient(analyticsTransport(["trend": reported])).usageAnalysisTrend(analyticsScope())
    #expect(reply.timeZone.identifier == "America/New_York")
    #expect(reply.points.first?.accountCost == Decimal(string: "0.2"))
    let fallbacks = [#"{"trend":[]}"#, #"{"trend":[],"query":{"timezone":""}}"#, #"{"trend":null,"query":{"timezone":"Not/AZone"}}"#,
                     #"{"trend":[],"query":"broken"}"#, #"{}"#]
    for payload in fallbacks {
        let fallback = try await analyticsClient(analyticsTransport(["trend": payload])).usageAnalysisTrend(analyticsScope())
        #expect(fallback.timeZone.identifier == "Asia/Shanghai")
        #expect(fallback.points.isEmpty)
    }
}

@Test func usersRankingSendsSortByOnlyWhenGivenAndBoundsLimit() async throws {
    let transport = analyticsTransport()
    let client = analyticsClient(transport)
    let query = analyticsScope(86_400, granularity: .day, groupID: 7, model: "m", source: .requested)
    _ = try await client.usageAnalysisUsersRanking(query, sortBy: nil, limit: 5)
    for metric in AnalyticsRankMetric.allCases { _ = try await client.usageAnalysisUsersRanking(query, sortBy: metric, limit: 50) }
    for limit in [0, 51, -1] {
        let error = await thrownAPIError { _ = try await client.usageAnalysisUsersRanking(query, sortBy: .requests, limit: limit) }
        #expect(error?.kind == .validation)
    }
    _ = try await client.usageAnalysis(query)
    let requests = await transport.requests
    #expect(requests.count == 5)
    let rankings = Array(requests.prefix(4))
    #expect(rankings.allSatisfy { $0.url?.path == "/api/v1/admin/dashboard/users-ranking" && $0.httpMethod == "GET" && $0.timeoutInterval == 45 })
    #expect(rankings.map { sentItems($0)["sort_by"] } == [nil, "actual_cost", "requests", "tokens"])
    #expect(rankings.map { sentItems($0)["limit"] } == ["5", "50", "50", "50"])
    let stats = sentItems(requests.last)
    for request in rankings {
        var scope = sentItems(request)
        scope["sort_by"] = nil; scope["limit"] = nil
        #expect(scope == stats)
    }
    #expect(AnalyticsRankMetric.allCases.map(\.rawValue) == ["actual_cost", "requests", "tokens"])
}

@Test func usersRankingDecodesTotalsAndToleratesOldServers() throws {
    let full = try decodeJSON(UserSpendingRanking.self, #"""
    {"ranking":[{"user_id":7,"email":"a@example.com","username":"alice","actual_cost":"12.5","cost":"20","account_cost":"4.25","requests":30,"tokens":4000},
                {"user_id":8,"email":"b@example.com","username":"  ","actual_cost":1,"cost":2,"account_cost":0,"requests":1,"tokens":2},
                {"user_id":9,"email":"","username":"","actual_cost":0,"cost":0,"account_cost":0,"requests":0,"tokens":0}],
     "total_users":31,"total_actual_cost":"13.5","total_cost":"22","total_account_cost":"4.25","total_requests":31,"total_tokens":4002}
    """#)
    let first = full.ranking[0]
    #expect(first.id == 7 && first.email == "a@example.com" && first.username == "alice")
    #expect(first.actualCost == Decimal(string: "12.5") && first.standardCost == 20 && first.accountCost == Decimal(string: "4.25"))
    #expect(first.requests == 30 && first.tokens == 4000)
    #expect(full.totalUsers == 31 && full.totalRequests == 31 && full.totalTokens == 4002)
    #expect(full.totalActualCost == Decimal(string: "13.5") && full.totalStandardCost == 22 && full.totalAccountCost == Decimal(string: "4.25"))
    #expect(full.ranking.map(\.displayName) == ["alice", "b@example.com", "#9"])
    let old = try decodeJSON(UserSpendingRanking.self, #"""
    {"ranking":[{"user_id":7,"email":"a@example.com","username":"alice","actual_cost":"12.5","requests":30,"tokens":4000}],
     "total_actual_cost":"12.5","total_requests":30,"total_tokens":4000}
    """#)
    #expect(old.ranking[0].standardCost == nil && old.ranking[0].accountCost == nil)
    #expect(old.ranking[0].actualCost == Decimal(string: "12.5"))
    #expect(old.totalUsers == nil && old.totalStandardCost == nil && old.totalAccountCost == nil)
    #expect(old.totalActualCost == Decimal(string: "12.5") && old.totalRequests == 30)
    #expect(try decodeJSON(UserSpendingRanking.self, #"{"ranking":null}"#).ranking.isEmpty)
    #expect(try decodeJSON(UserSpendingRanking.self, "{}").ranking.isEmpty)
}

@Test func usersTrendSendsMetricOnlyWhenGiven() async throws {
    let transport = analyticsTransport()
    let client = analyticsClient(transport)
    let query = analyticsScope(7 * 86_400, granularity: .day, groupID: 7)
    _ = try await client.usageAnalysisUsersTrend(query, metric: nil, limit: 12)
    _ = try await client.usageAnalysisUsersTrend(query, metric: .tokens, limit: 12)
    _ = try await client.usageAnalysisUsersTrend(query, metric: .actualCost, limit: 12)
    let error = await thrownAPIError { _ = try await client.usageAnalysisUsersTrend(query, metric: .tokens, limit: 0) }
    #expect(error?.kind == .validation)
    let requests = await transport.requests
    #expect(requests.count == 3)
    #expect(requests.allSatisfy { $0.url?.path == "/api/v1/admin/dashboard/users-trend" && $0.httpMethod == "GET" && $0.timeoutInterval == 45 })
    #expect(requests.map { sentItems($0)["metric"] } == [nil, "tokens", "actual_cost"])
    #expect(requests.allSatisfy { sentItems($0)["limit"] == "12" && sentItems($0)["granularity"] == "day" && sentItems($0)["group_id"] == "7" })
    #expect(UserTrendMetric.allCases.map(\.rawValue) == ["tokens", "actual_cost"])
}

@Test func usersTrendDecodesPointsAndReportedZone() async throws {
    let payload = #"""
    {"trend":[{"date":"2026-10-15","user_id":7,"email":"a@example.com","username":"alice","requests":3,"tokens":40,"cost":"2.5","actual_cost":"1.25"},
              {"date":"2026-10-16","user_id":7,"email":"a@example.com","username":"alice"},
              {"date":"2026-10-15","user_id":8,"email":"b@example.com","username":""}],
     "query":{"timezone":"America/New_York"}}
    """#
    let client = analyticsClient(analyticsTransport(["users-trend": payload]))
    let reply = try await client.usageAnalysisUsersTrend(analyticsScope(granularity: .day), metric: .tokens, limit: 12)
    #expect(reply.timeZone.identifier == "America/New_York")
    let first = reply.points[0], sparse = reply.points[1]
    #expect(first.userID == 7 && first.requests == 3 && first.tokens == 40)
    #expect(first.standardCost == Decimal(string: "2.5") && first.actualCost == Decimal(string: "1.25"))
    #expect(sparse.requests == 0 && sparse.tokens == 0 && sparse.standardCost == nil && sparse.actualCost == nil)
    #expect(reply.points.map(\.id) == ["7@2026-10-15", "7@2026-10-16", "8@2026-10-15"])
    #expect(reply.points.map(\.displayName) == ["alice", "alice", "b@example.com"])
    let empty = try await analyticsClient(analyticsTransport(["users-trend": #"{"trend":null}"#]))
        .usageAnalysisUsersTrend(analyticsScope(), metric: nil, limit: 12)
    #expect(empty.points.isEmpty)
    #expect(empty.timeZone.identifier == "Asia/Shanghai")
}

@Test func requestTypesNeverSendRequestTypeOrStream() async throws {
    let payload = #"""
    {"request_types":[{"request_type":"stream","requests":9,"total_tokens":90,"cost":"3","actual_cost":"1.5","account_cost":"0.5"},
                      {"request_type":"ws_v2","requests":2,"total_tokens":20,"cost":1,"actual_cost":0.5,"account_cost":0},
                      {"request_type":"foo","requests":1,"total_tokens":1}]}
    """#
    let transport = analyticsTransport(["request-types": payload])
    let stats = try await analyticsClient(transport).usageAnalysisRequestTypes(analyticsScope(groupID: 7, requestType: .stream))
    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/api/v1/admin/dashboard/request-types" && request.httpMethod == "GET" && request.timeoutInterval == 45)
    let sent = sentItems(request)
    #expect(sent["request_type"] == nil && sent["stream"] == nil)
    #expect(sent["group_id"] == "7" && sent["timezone"] == "Asia/Shanghai" && sent["start_time"] == "2026-10-15T00:00:00Z")
    #expect(stats.map(\.kind) == [.stream, .wsV2, nil])
    #expect(stats.map(\.requestType) == ["stream", "ws_v2", "foo"])
    #expect(stats[0].requests == 9 && stats[0].totalTokens == 90 && stats[0].id == "stream")
    #expect(stats[0].standardCost == 3 && stats[0].actualCost == Decimal(string: "1.5") && stats[0].accountCost == Decimal(string: "0.5"))
    #expect(stats[1].accountCost == 0)
    #expect(stats[2].standardCost == nil && stats[2].accountCost == nil)
    for empty in [#"{"request_types":[]}"#, #"{"request_types":null}"#] {
        #expect(try await analyticsClient(analyticsTransport(["request-types": empty])).usageAnalysisRequestTypes(analyticsScope()).isEmpty)
    }
}

@Test func requestTypeFanOutUsesUsageStatsRequestType() async throws {
    #expect(UsageRequestType.allCases.map(\.rawValue) == ["stream", "sync", "ws_v2", "cyber", "live"])
    let transport = analyticsTransport()
    let client = analyticsClient(transport)
    for type in UsageRequestType.allCases { _ = try await client.usageAnalysis(analyticsScope(requestType: type)) }
    _ = try await client.usageAnalysis(analyticsScope())
    let requests = await transport.requests
    #expect(requests.map { sentItems($0)["request_type"] } == ["stream", "sync", "ws_v2", "cyber", "live", nil])
    #expect(requests.allSatisfy { $0.url?.path == "/api/v1/admin/usage/stats" && !sentNames($0).contains("stream") })
}

@Test func analyticsEndpointsUseGetAndAggregateTimeout() async throws {
    let transport = analyticsTransport()
    let client = analyticsClient(transport)
    let query = analyticsScope()
    _ = try await client.usageAnalysis(query)
    _ = try await client.usageAnalysisTrend(query)
    _ = try await client.usageAnalysisModels(query, source: .requested)
    _ = try await client.usageAnalysisGroups(query)
    _ = try await client.usageAnalysisUsersRanking(query, sortBy: nil, limit: 5)
    _ = try await client.usageAnalysisUsersTrend(query, metric: nil, limit: 12)
    _ = try await client.usageAnalysisRequestTypes(query)
    let requests = await transport.requests
    let dashboard = ["trend", "models", "groups", "users-ranking", "users-trend", "request-types"].map { "/api/v1/admin/dashboard/\($0)" }
    #expect(requests.map { $0.url?.path ?? "" } == ["/api/v1/admin/usage/stats"] + dashboard)
    #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.timeoutInterval == RequestTimeout.aggregate })
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "If-None-Match") == nil })
}
