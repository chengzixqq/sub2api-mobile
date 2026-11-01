import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 40 §1.4 排行卡、§4 全部排行 (S4-15): rows, shares, the composition strip, the list header, the card foot, the user footnote,
// the users-ranking fallback on INVALID_SORT_BY and the card keys.

private let site = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
/// 2026-10-16 09:41 in Shanghai.
private let morning = Date(timeIntervalSince1970: 1_792_114_860)

/// The fixture's twelve requested models, in the backend's total_tokens order (not by cost).
private let twelveModels = """
[{"model":"claude-opus-4","requests":1210,"total_tokens":35800000,"actual_cost":"180.20","account_cost":"94.00"},
 {"model":"gpt-5","requests":1100,"total_tokens":30100000,"actual_cost":"92.40","account_cost":"50.10"},
 {"model":"text-embedding-3-small","requests":90,"total_tokens":15000000,"actual_cost":"0.30","account_cost":"0.10"},
 {"model":"deepseek-v3","requests":620,"total_tokens":11200000,"actual_cost":"41.30","account_cost":"22.80"},
 {"model":"gemini-2.5-pro","requests":380,"total_tokens":7300000,"actual_cost":"26.10","account_cost":"14.90"},
 {"model":"claude-sonnet-4.5","requests":2400,"total_tokens":6900000,"actual_cost":"8.60","account_cost":"4.70"},
 {"model":"gpt-5-mini","requests":640,"total_tokens":4100000,"actual_cost":"5.10","account_cost":"2.60"},
 {"model":"glm-4.6","requests":195,"total_tokens":3000000,"actual_cost":"10.00","account_cost":"6.20"},
 {"model":"kimi-k2","requests":310,"total_tokens":2600000,"actual_cost":"6.40","account_cost":"3.50"},
 {"model":"minimax-m2","requests":150,"total_tokens":1900000,"actual_cost":"3.20","account_cost":"1.90"},
 {"model":"qwen3-coder","requests":120,"total_tokens":1400000,"actual_cost":"2.10","account_cost":"1.20"},
 {"model":"claude-haiku-4.5","requests":260,"total_tokens":1200000,"actual_cost":"1.80","account_cost":"0.90"}]
"""

private func breakdown(_ json: String) -> [AnalyticsBreakdown] {
    try! JSONDecoder().decode([AnalyticsBreakdown].self, from: Data(json.utf8))
}
private func users(_ json: String, serverSort: AnalyticsRankMetric? = .actualCost) -> AnalyticsUserRanking {
    AnalyticsUserRanking(ranking: try! JSONDecoder().decode(UserSpendingRanking.self, from: Data(json.utf8)), serverSort: serverSort)
}
private func names(_ list: AnalyticsRankList) -> [String] { list.items.map(\.name) }

/// Three users of a range of 143, with the range's totals.
private let rangeUsers = """
{"ranking":[
 {"user_id":10,"email":"ops@studio-k.example","username":"Studio-K 团队","actual_cost":"120.40","account_cost":"61.20","requests":860,"tokens":24100000},
 {"user_id":21,"email":"billing@nova.example","username":"Nova 工作室","actual_cost":"96.20","account_cost":"48.90","requests":640,"tokens":18300000},
 {"user_id":1,"email":"alice@example.com","username":"Alice","actual_cost":"61.00","account_cost":"31.00","requests":1420,"tokens":9800000}],
 "total_users":143,"total_actual_cost":"400.00","total_requests":5000,"total_tokens":100000000}
"""

// MARK: Rows

@Test func modelRowsSortByMetricAndShareOfAllRows() {
    let rows = breakdown(twelveModels)
    let byCost = AnalyticsRanking.models(rows, source: .requested, metric: .actualCost)
    #expect(byCost.items.count == 12)
    let first = byCost.items[0]
    #expect(first.id == "model:claude-opus-4")
    #expect(first.name == "claude-opus-4")
    #expect(first.isMonospaced)
    #expect(first.value == "$180.20")
    #expect(first.shareText == "47.7%")
    #expect(first.route == .analyticsModel(model: "claude-opus-4", source: .requested))
    #expect(names(byCost).prefix(3) == ["claude-opus-4", "gpt-5", "deepseek-v3"])
    #expect(byCost.items.last?.name == "text-embedding-3-small")

    let byRequests = AnalyticsRanking.models(rows, source: .requested, metric: .requests)
    #expect(byRequests.items[0].name == "claude-sonnet-4.5")
    #expect(byRequests.items[0].value == "2,400")
    #expect(byRequests.items[0].shareText == "32.1%")
    let byTokens = AnalyticsRanking.models(rows, source: .requested, metric: .tokens)
    #expect(byTokens.items[0].value == "35.8M")
    #expect(byTokens.items[2].name == "text-embedding-3-small")
}

@Test func equalValuesFallBackToActualCostThenName() {
    let rows = breakdown("""
    [{"model":"b","requests":10,"total_tokens":1,"actual_cost":"2.00"},
     {"model":"z","requests":10,"total_tokens":1,"actual_cost":"1.00"},
     {"model":"a","requests":10,"total_tokens":1,"actual_cost":"2.00"}]
    """)
    #expect(names(AnalyticsRanking.models(rows, source: .requested, metric: .requests)) == ["a", "b", "z"])
    let zero = breakdown(#"[{"model":"a","requests":0,"total_tokens":0,"actual_cost":"0"},{"model":"b","requests":0,"total_tokens":0}]"#)
    let list = AnalyticsRanking.models(zero, source: .requested, metric: .actualCost)
    #expect(list.items.map(\.share) == [0, 0])
    #expect(list.items.map(\.shareText) == ["0.0%", "0.0%"])
    let empty = AnalyticsRanking.models([], source: .requested, metric: .actualCost)
    #expect(empty.items.isEmpty)
    #expect(empty.strip == nil)
}

@Test func mappingRowsShowTheRequestedNameAndOpenWithTheRawName() {
    let rows = breakdown("""
    [{"model":"claude-opus-4 -> claude-opus-4-20250514","requests":1210,"total_tokens":35800000,"actual_cost":"180.20","account_cost":"94.00"},
     {"model":"","requests":3,"total_tokens":10,"actual_cost":"0.10"}]
    """)
    let list = AnalyticsRanking.models(rows, source: .mapping, metric: .actualCost)
    #expect(list.items[0].name == "claude-opus-4")
    #expect(list.items[0].detail?.hasPrefix("→ claude-opus-4-20250514 · ") == true)
    #expect(list.items[0].route == .analyticsModel(model: "claude-opus-4 -> claude-opus-4-20250514", source: .mapping))
    #expect(list.items[1].name == "未命名")
    #expect(list.items[1].route == nil)
}

@Test func groupRowsNameUngroupedAndUnknownGroups() {
    let rows = breakdown("""
    [{"group_id":7,"group_name":"","requests":80,"total_tokens":900000,"actual_cost":"6.30"},
     {"group_id":1,"group_name":"高级组","requests":1820,"total_tokens":48200000,"actual_cost":"182.40"},
     {"group_id":0,"group_name":"","requests":95,"total_tokens":1900000,"actual_cost":"10.00"},
     {"group_id":9,"group_name":"","requests":30,"total_tokens":200000,"actual_cost":"2.20"}]
    """)
    let list = AnalyticsRanking.groups(rows, metric: .actualCost) { $0 == 7 ? "GLM 组" : nil }
    #expect(names(list) == ["高级组", "未分组", "GLM 组", "#9"])
    #expect(list.items.map(\.route) == [.group(id: 1), nil, .group(id: 7), .group(id: 9)])
    #expect(list.items[1].shareText == "5.0%")
    #expect(list.items.allSatisfy { !$0.isMonospaced })
}

@Test func userRowsUseRangeTotalsAndNameFallbacks() {
    let list = AnalyticsRanking.users(users(rangeUsers), metric: .actualCost)
    #expect(list.items[0].shareText == "30.1%")
    #expect(list.items[0].route == .user(id: 10))
    #expect(list.items[0].detail?.hasPrefix("ops@studio-k.example · 请求 860") == true)
    #expect(list.items[0].detail?.hasSuffix("账号成本 $61.20") == true)
    #expect(AnalyticsRanking.users(users(rangeUsers), metric: .requests).items[0].shareText == "28.4%")

    let old = users("""
    {"ranking":[{"user_id":25,"email":"studio@pixel.example","username":"","actual_cost":"8.30","tokens":1700000},
                {"user_id":0,"email":"","username":"","actual_cost":"1.70","requests":4,"tokens":10}],
     "total_actual_cost":"0"}
    """, serverSort: nil)
    let fallback = AnalyticsRanking.users(old, metric: .actualCost)
    #expect(names(fallback) == ["studio@pixel.example", "#0"])
    #expect(fallback.items.map(\.route) == [.user(id: 25), nil])
    #expect(fallback.items[0].shareText == "83.0%")
    #expect(fallback.items[0].detail?.contains("账号成本") == false)
    #expect(fallback.items[0].detail?.hasPrefix("studio@pixel.example") == false)
    let byRequests = AnalyticsRanking.users(old, metric: .requests)
    #expect(byRequests.items.map(\.value) == ["4", "—"])
}

@Test func userRowsReSortOnlyWhenTheServerDidNotSort() {
    let json = """
    {"ranking":[{"user_id":1,"username":"A","actual_cost":"30.00","requests":5,"tokens":100},
                {"user_id":2,"username":"B","actual_cost":"20.00","requests":50,"tokens":300},
                {"user_id":3,"username":"C","actual_cost":"10.00","requests":20,"tokens":200}]}
    """
    #expect(names(AnalyticsRanking.users(users(json, serverSort: .requests), metric: .requests)) == ["A", "B", "C"])
    #expect(names(AnalyticsRanking.users(users(json, serverSort: nil), metric: .requests)) == ["B", "C", "A"])
    #expect(names(AnalyticsRanking.users(users(json, serverSort: nil), metric: .tokens)) == ["B", "C", "A"])
    #expect(names(AnalyticsRanking.users(users(json, serverSort: nil), metric: .actualCost)) == ["A", "B", "C"])
}

@Test func detailLineListsTheOtherMetricsAndAccountCost() {
    let rows = breakdown(#"[{"model":"m","requests":3100,"total_tokens":15000000,"actual_cost":"61.00","account_cost":"88.20"}]"#)
    let detail = { (metric: AnalyticsRankMetric) in AnalyticsRanking.models(rows, source: .requested, metric: metric).items[0].detail }
    #expect(detail(.actualCost) == "请求 3,100 · 15M Tokens · 账号成本 $88.20")
    #expect(detail(.requests) == "实际 $61.00 · 15M Tokens · 账号成本 $88.20")
    #expect(detail(.tokens) == "实际 $61.00 · 请求 3,100 · 账号成本 $88.20")
    let mapped = breakdown(#"[{"model":"a -> b","requests":1,"total_tokens":2,"actual_cost":"1.00"}]"#)
    #expect(AnalyticsRanking.models(mapped, source: .mapping, metric: .actualCost).items[0].detail == "→ b · 请求 1 · 2 Tokens")
}

// MARK: Strip, header, foot, footnote

@Test func compositionStripCapsAtThreeAndNamesTheRest() throws {
    let models = breakdown(twelveModels)
    let strip = try #require(AnalyticsRanking.models(models, source: .requested, metric: .actualCost).strip)
    #expect(strip.caption == "前 3 占 83.2%")
    #expect(strip.total == "合计 $377.50")
    #expect(strip.parts.map(\.name) == ["claude-opus-4", "gpt-5", "deepseek-v3"])
    #expect(strip.parts.allSatisfy { $0.isMonospaced })
    #expect(strip.restLegend == "其余 9 个模型")
    #expect(abs(strip.rest - (1 - 313.90 / 377.50)) < 0.0001)
    #expect(AnalyticsRanking.models(models, source: .requested, metric: .requests).strip?.total == "合计 7,475")
    #expect(AnalyticsRanking.models(models, source: .requested, metric: .tokens).strip?.total == "合计 120.5M")

    let userStrip = try #require(AnalyticsRanking.users(users(rangeUsers), metric: .actualCost).strip)
    #expect(userStrip.total == "合计 $400.00")
    #expect(userStrip.restLegend == "其余用户 30.6%")

    let two = breakdown(#"[{"model":"a","requests":1,"total_tokens":1,"actual_cost":"3.00"},{"model":"b","requests":1,"total_tokens":1,"actual_cost":"1.00"}]"#)
    let pair = try #require(AnalyticsRanking.models(two, source: .requested, metric: .actualCost).strip)
    #expect(pair.caption == "前 2 占 100.0%")
    #expect(pair.restLegend == nil)
    #expect(pair.rest >= 0)
    #expect(AnalyticsRanking.models(Array(two.prefix(1)), source: .requested, metric: .actualCost).strip == nil)
}

@Test func groupStripNamesTheOtherGroups() {
    let json = (1...9).map { #"{"group_id":\#($0),"group_name":"组\#($0)","requests":1,"total_tokens":1,"actual_cost":"\#(10 - $0).00"}"# }
    let list = AnalyticsRanking.groups(breakdown("[" + json.joined(separator: ",") + "]"), metric: .actualCost) { _ in nil }
    #expect(list.strip?.restLegend == "其余 6 个分组")
}

@Test func listHeaderCountsRowsAndSourceOrUserTotal() {
    #expect(AnalyticsRanking.listHeader(.model, rows: 12, source: .requested, totalUsers: nil) == "12 个模型")
    #expect(AnalyticsRanking.listHeader(.model, rows: 12, source: .upstream, totalUsers: nil) == "12 个模型 · 上游模型")
    #expect(AnalyticsRanking.listHeader(.model, rows: 13, source: .mapping, totalUsers: nil) == "13 个模型 · 映射")
    #expect(AnalyticsRanking.listHeader(.group, rows: 9, source: .mapping, totalUsers: nil) == "9 个分组")
    #expect(AnalyticsRanking.listHeader(.user, rows: 10, source: .requested, totalUsers: 143) == "前 10 位 · 共 143 位")
    #expect(AnalyticsRanking.listHeader(.user, rows: 50, source: .requested, totalUsers: 1_430) == "前 50 位 · 共 1,430 位")
    #expect(AnalyticsRanking.listHeader(.user, rows: 10, source: .requested, totalUsers: nil) == "前 10 位")
}

@Test func cardFooterNeedsMoreThanFiveRows() {
    #expect(AnalyticsRanking.cardFooter(.model, rows: 12, totalUsers: nil) == AnalyticsRankFooter(title: "全部 12 个模型", meta: "含上游口径"))
    #expect(AnalyticsRanking.cardFooter(.model, rows: 5, totalUsers: nil) == nil)
    #expect(AnalyticsRanking.cardFooter(.group, rows: 9, totalUsers: nil) == AnalyticsRankFooter(title: "全部 9 个分组", meta: nil))
    #expect(AnalyticsRanking.cardFooter(.user, rows: 5, totalUsers: 143) == AnalyticsRankFooter(title: "查看前 50 位用户", meta: nil))
    #expect(AnalyticsRanking.cardFooter(.user, rows: 5, totalUsers: 5) == nil)
    #expect(AnalyticsRanking.cardFooter(.user, rows: 5, totalUsers: nil) != nil)
    #expect(AnalyticsRanking.cardFooter(.user, rows: 4, totalUsers: nil) == nil)
}

@Test func userFootnoteFollowsServerSortAndKeyGroup() {
    let total = users(rangeUsers)
    #expect(AnalyticsRanking.userFootnote(metric: .actualCost, ranking: total, keyGroup: nil) == "按实际扣费取前 50 位，共 143 位用户有用量。")
    #expect(AnalyticsRanking.userFootnote(metric: .tokens, ranking: users(rangeUsers, serverSort: .tokens), keyGroup: nil)
            == "按 Tokens 取前 50 位，共 143 位用户有用量。")
    let old = users(#"{"ranking":[]}"#, serverSort: nil)
    #expect(AnalyticsRanking.userFootnote(metric: .requests, ranking: old, keyGroup: nil) == "用户排行按实际扣费取前 50 位，这里在其中按请求重排。")
    #expect(AnalyticsRanking.userFootnote(metric: .tokens, ranking: old, keyGroup: nil) == "用户排行按实际扣费取前 50 位，这里在其中按 Tokens 重排。")
    #expect(AnalyticsRanking.userFootnote(metric: .actualCost, ranking: old, keyGroup: nil) == "按实际扣费取前 50 位。")
    #expect(AnalyticsRanking.userFootnote(metric: .actualCost, ranking: total, keyGroup: "高级组")
            == "按实际扣费取前 50 位，共 143 位用户有用量。按请求时 Key 所属的分组统计：只算各用户在「高级组」Key 上的用量。")
}

@Test func narrowedDimensionAndFixedTexts() {
    #expect(AnalyticsRankDimension.group.isNarrowed(by: .group(id: 1)))
    #expect(AnalyticsRankDimension.model.isNarrowed(by: .model(name: "gpt-5")))
    #expect(!AnalyticsRankDimension.group.isNarrowed(by: .model(name: "gpt-5")))
    #expect(!AnalyticsRankDimension.user.isNarrowed(by: .group(id: 1)))
    #expect(!AnalyticsRankDimension.user.isNarrowed(by: .model(name: "gpt-5")))
    #expect(!AnalyticsRankDimension.model.isNarrowed(by: nil))
    #expect(AnalyticsRanking.narrowedText(.group, name: "高级组") == "已筛选分组：高级组")
    #expect(AnalyticsRanking.narrowedText(.model, name: "claude-opus-4") == "已筛选模型：claude-opus-4")
    #expect(AnalyticsRankDimension.allCases.map(\.pageTitle) == ["模型分布", "用户排行", "分组使用分布"])
    #expect(AnalyticsRankDimension.allCases.map(\.segmentTitle) == ["模型", "用户", "分组"])
    #expect(AnalyticsRankDimension.allCases.map(\.emptyText) == ["这个范围内没有模型用量", "这个范围内没有用户用量", "这个范围内没有分组用量"])
    #expect(AnalyticsRankMetric.allCases.map(\.sortTitle) == ["按实际扣费", "按请求", "按 Tokens"])
    #expect(ModelSource.allCases.map(\.rankSourceTitle) == ["请求模型", "上游模型", "映射（请求 → 上游）"])
    #expect(AnalyticsRanking.cardTitle == "排行")
    #expect(AnalyticsRanking.cardTrailing == "实际扣费 · 前 5")
}

// MARK: Reads

@Test func userSortParameterFollowsCapability() {
    #expect(AnalyticsRanking.userSortParameter(.requests, supportsSort: true) == .requests)
    for metric in AnalyticsRankMetric.allCases {
        #expect(AnalyticsRanking.userSortParameter(metric, supportsSort: false) == nil)
    }
}

private let rankingReply = #"{"ranking":[{"user_id":1,"email":"a@example.com","username":"A","actual_cost":"1.00","requests":3,"tokens":9}],"total_actual_cost":"1.00","total_requests":3,"total_tokens":9}"#

private func rankingQuery() -> AnalyticsQuery {
    AnalyticsQuery(start: morning.addingTimeInterval(-86_400), end: morning, granularity: .day, timeZone: shanghai, groupID: 3)
}
private func items(_ request: URLRequest) -> [URLQueryItem] {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
}
private func readUsers(_ transport: SessionTransport, sortBy: AnalyticsRankMetric?) async throws -> AnalyticsUserRanking {
    let client = sessionClient(transport)
    return try await AnalyticsRankLoader.users(rankingQuery(), sortBy: sortBy, limit: 50) { query, sort, limit in
        try await client.usageAnalysisUsersRanking(query, sortBy: sort, limit: limit)
    }
}

@Test func usersLoaderRetriesOnceWithoutSortByOnInvalidSortBy() async throws {
    let transport = SessionTransport { request in
        items(request).contains { $0.name == "sort_by" } ? sessionFailure(400, reason: "INVALID_SORT_BY") : sessionOK(rankingReply)
    }
    let result = try await readUsers(transport, sortBy: .requests)
    #expect(result.serverSort == nil)
    #expect(result.ranking.ranking.map(\.userID) == [1])
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.url?.path.hasSuffix("/admin/dashboard/users-ranking") == true })
    let first = items(requests[0]), second = items(requests[1])
    #expect(first.contains(URLQueryItem(name: "sort_by", value: "requests")))
    #expect(first.contains(URLQueryItem(name: "limit", value: "50")))
    #expect(!second.contains { $0.name == "sort_by" })
    #expect(second.contains(URLQueryItem(name: "limit", value: "50")))
    #expect(Set(first.filter { $0.name != "sort_by" }.map(\.description)) == Set(second.map(\.description)))
    #expect(second.contains(URLQueryItem(name: "group_id", value: "3")))
}

@Test func usersLoaderRethrowsOtherFailuresWithoutRetry() async throws {
    let timezone = SessionTransport { _ in sessionFailure(400, reason: "INVALID_TIMEZONE") }
    await #expect(throws: APIError.self) { try await readUsers(timezone, sortBy: .requests) }
    #expect(await timezone.requests.count == 1)
    do { _ = try await readUsers(timezone, sortBy: .tokens) } catch let error as APIError { #expect(error.reason == "INVALID_TIMEZONE") }

    let unsorted = SessionTransport { _ in sessionFailure(400, reason: "INVALID_SORT_BY") }
    await #expect(throws: APIError.self) { try await readUsers(unsorted, sortBy: nil) }
    #expect(await unsorted.requests.count == 1)

    let fine = SessionTransport { _ in sessionOK(rankingReply) }
    #expect(try await readUsers(fine, sortBy: .tokens).serverSort == .tokens)
    #expect(try await readUsers(fine, sortBy: nil).serverSort == nil)
}

// MARK: Card keys and memory

@Test func rankKeysShareRequestedModelsAndKeepPageOnlyKeysOutOfTheUpdateLine() {
    #expect(AnalyticsRankCardPlan.key(for: .model) == .rankModels(.requested))
    #expect(AnalyticsRankCardPlan.key(for: .group) == .rankGroups)
    #expect(AnalyticsRankCardPlan.key(for: .user) == .rankCardUsers)
    #expect(AnalyticsCardKey.rankModels(.requested).showsInUpdateLine)
    #expect(!AnalyticsCardKey.rankModels(.upstream).showsInUpdateLine)
    #expect(!AnalyticsCardKey.rankModels(.mapping).showsInUpdateLine)
    #expect(AnalyticsCardKey.rankGroups.showsInUpdateLine)
    #expect(AnalyticsCardKey.rankCardUsers.showsInUpdateLine)
    let pageKeys = ([nil] + AnalyticsRankMetric.allCases.map(Optional.some)).map { AnalyticsCardKey.rankUsers(sortBy: $0) }
    #expect(Set(pageKeys).count == 4)
    #expect(!pageKeys.contains(.rankCardUsers))
    #expect(pageKeys.allSatisfy { !$0.showsInUpdateLine })
    let all = pageKeys + ModelSource.allCases.map { AnalyticsCardKey.rankModels($0) } + [.rankGroups, .rankCardUsers]
    #expect(all.allSatisfy { $0.scope == .rangeAndFilter })
}

@MainActor private func makeSession(_ scratch: ScratchDefaults) -> AnalyticsSessionState {
    AnalyticsSessionState(serverID: site, generation: UUID(), client: sessionClient(SessionTransport { _ in sessionOK("{}") }), timeZone: shanghai,
                          supportsModelSource: true, supportsOpsModelFilter: true, memory: AnalyticsMemory(defaults: scratch.defaults),
                          entry: .last7, groups: nil, clock: { morning }, isSessionCurrent: { true })
}
@MainActor private func fill<Value: Sendable>(_ session: AnalyticsSessionState, _ key: AnalyticsCardKey, _ value: Value) async {
    await session.load(key, fixture: { _ in value }) { _, _ in value }
}

@MainActor @Test func refreshDropsHiddenSegmentsOnly() async throws {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    await fill(session, .rankModels(.requested), breakdown(twelveModels))
    await fill(session, .rankGroups, [AnalyticsBreakdown]())
    await fill(session, .rankCardUsers, users(rangeUsers))
    AnalyticsRankCardPlan.dropHidden(session, showing: .user)
    #expect(session.hasValue(.rankCardUsers))
    #expect(!session.hasValue(.rankModels(.requested)))
    #expect(!session.hasValue(.rankGroups))
    let shown = try #require(session.state(.rankCardUsers, as: AnalyticsUserRanking.self)?.updatedAt)
    #expect(session.earliestUpdate == shown)
    session.setFilter(.group(id: 3))
    #expect(!session.hasValue(.rankCardUsers))
}

@MainActor @Test func aHiddenSegmentBeingReadIsNotDropped() async {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let session = makeSession(scratch)
    let gate = SessionGate()
    let rows = breakdown(twelveModels)
    let reading = Task { @MainActor in
        await session.load(.rankGroups, fixture: { _ in rows }) { _, _ in
            await gate.wait()
            return rows
        }
    }
    while !(await gate.arrived) { await Task.yield() }
    AnalyticsRankCardPlan.dropHidden(session, showing: .model)
    await gate.open()
    await reading.value
    #expect(session.hasValue(.rankGroups))
}

@MainActor @Test func rankChoiceReadsTheRememberedSortAndSource() {
    let scratch = ScratchDefaults(); defer { scratch.remove() }
    let memory = AnalyticsMemory(defaults: scratch.defaults)
    #expect(AnalyticsRankChoice.remembered(memory, dimension: .model, serverID: site) == AnalyticsRankChoice(metric: .actualCost, source: .requested))
    #expect(scratch.defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("analytics.") }.isEmpty)
    memory.setRankSort(.tokens, for: .user, serverID: site)
    memory.setRankModelSource(.mapping, serverID: site)
    #expect(AnalyticsRankChoice.remembered(memory, dimension: .user, serverID: site) == AnalyticsRankChoice(metric: .tokens, source: .mapping))
    #expect(AnalyticsRankChoice.remembered(memory, dimension: .model, serverID: site) == AnalyticsRankChoice(metric: .actualCost, source: .mapping))
}
