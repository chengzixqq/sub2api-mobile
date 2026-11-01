import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 40 §2.3 Token 使用趋势 and 端点分布, row by row, and the stacking every stacked chart shares (S4-17); 用户用量趋势 and 请求类型
// with its fallback (S4-17b).

private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
/// 2026-10-16 09:41 in Shanghai, a Friday: today has 10 hourly buckets, the last one running.
private let morning = utc("2026-10-16T01:41:00Z")
private let today = AnalyticsRange.resolve(.preset(.today), now: morning, zone: shanghai)

private func point(_ bucket: Int, input: Int, output: Int, cacheRead: Int, cacheWrite: Int, total: Int? = nil) -> TrendPoint {
    TrendPoint(date: today.buckets[bucket].wireKey, requests: 1, totalTokens: total ?? input + output + cacheRead + cacheWrite, cost: 0,
               inputTokens: input, outputTokens: output, cacheCreationTokens: cacheWrite, cacheReadTokens: cacheRead)
}

private func summary(endpoints: String? = nil, upstream: String? = nil) throws -> AnalyticsSummary {
    var fields = ["\"total_requests\":18200", "\"total_tokens\":96400000"]
    if let endpoints { fields.append("\"endpoints\":\(endpoints)") }
    if let upstream { fields.append("\"upstream_endpoints\":\(upstream)") }
    return try JSONDecoder().decode(AnalyticsSummary.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
}

private let inbound = """
[{"endpoint":"/v1/responses","requests":2184,"total_tokens":1,"cost":"153.00","actual_cost":"122.40"},
 {"endpoint":"/v1/messages","requests":10920,"total_tokens":1,"cost":"765.50","actual_cost":"612.40"},
 {"endpoint":"/v1/chat/completions","requests":5096,"total_tokens":1,"cost":"357.13","actual_cost":"285.70"}]
"""

// MARK: - Token 使用趋势

@Test func tokenMixesFillMissingBucketsWithZero() {
    let points = [point(0, input: 3, output: 1, cacheRead: 5, cacheWrite: 1, total: 11), point(2, input: 6, output: 2, cacheRead: 9, cacheWrite: 3)]
    let mixes = AnalyticsSeries.tokenMixes(range: today, points: points)
    #expect(mixes.count == today.buckets.count)
    #expect(mixes[0] == TokenMix(input: 3, output: 1, cacheRead: 5, cacheWrite: 1, total: 11))
    #expect(mixes[1] == .zero)
    #expect(mixes[2] == TokenMix(input: 6, output: 2, cacheRead: 9, cacheWrite: 3, total: 20))
    #expect(mixes[9] == .zero)
    #expect(TokenMix(points[0])[.cacheRead] == 5 && TokenMix(points[0])[.cacheWrite] == 1)
}

@Test func tokenTotalSumsEveryKindAndTheServerTotal() {
    let points = [point(0, input: 3, output: 1, cacheRead: 5, cacheWrite: 1, total: 12), point(4, input: 6, output: 2, cacheRead: 9, cacheWrite: 3)]
    let total = AnalyticsSeries.tokenTotal(AnalyticsSeries.tokenMixes(range: today, points: points))
    #expect(total == TokenMix(input: 9, output: 3, cacheRead: 14, cacheWrite: 4, total: 32))
    #expect(TokenKind.allCases.map { total[$0] } == [9, 3, 14, 4])
    #expect(TokenKind.allCases.map(\.title) == ["输入", "输出", "缓存读", "缓存写"])
}

@Test func stackRunsBottomUpInOrderAndSkipsZeroLayers() {
    let column: [TokenKind: Double] = [.input: 3, .output: 0, .cacheRead: 5, .cacheWrite: 1]
    let stacked = AnalyticsSeries.stack([column, [:]], order: TokenKind.allCases)
    #expect(stacked[0] == [AnalyticsStackSegment(layer: .input, lower: 0, upper: 3), AnalyticsStackSegment(layer: .cacheRead, lower: 3, upper: 8),
                           AnalyticsStackSegment(layer: .cacheWrite, lower: 8, upper: 9)])
    #expect(stacked[1].isEmpty)
}

@Test func stackGapRaisesUpperSegmentsAndDropsThinOnes() {
    let column: [TokenKind: Double] = [.input: 3, .output: 0.25, .cacheRead: 5, .cacheWrite: 1]
    let stacked = AnalyticsSeries.stack([column], order: TokenKind.allCases, gap: 0.5)[0]
    // The bottom segment keeps its height; 0.25 is thinner than the gap and goes, the total height stays 9.25.
    #expect(stacked == [AnalyticsStackSegment(layer: .input, lower: 0, upper: 3), AnalyticsStackSegment(layer: .cacheRead, lower: 3.75, upper: 8.25),
                        AnalyticsStackSegment(layer: .cacheWrite, lower: 8.75, upper: 9.25)])
    // A bottom layer thinner than the gap still shows.
    #expect(AnalyticsSeries.stack([[.input: 0.2]], order: TokenKind.allCases, gap: 0.5)[0] == [AnalyticsStackSegment(layer: .input, lower: 0, upper: 0.2)])
}

@Test func onlyOneKindGivesSingleLayerColumnsFromZero() {
    let mixes = [TokenMix(input: 3, output: 1, cacheRead: 5, cacheWrite: 1, total: 10), .zero]
    #expect(AnalyticsSeries.tokenLayers(only: nil) == TokenKind.allCases)
    #expect(AnalyticsSeries.tokenLayers(only: .cacheRead) == [.cacheRead])
    let columns = AnalyticsSeries.tokenColumns(mixes, only: .cacheRead)
    #expect(columns == [[.cacheRead: 5], [.cacheRead: 0]])
    #expect(AnalyticsSeries.stack(columns, order: [.cacheRead], gap: 0.5)[0] == [AnalyticsStackSegment(layer: .cacheRead, lower: 0, upper: 5)])
    #expect(AnalyticsSeries.tokenColumns(mixes, only: nil)[0] == [.input: 3, .output: 1, .cacheRead: 5, .cacheWrite: 1])
}

@Test func hasTokensIsFalseWhenEveryKindIsZero() {
    #expect(!AnalyticsSeries.hasTokens([.zero, .zero]))
    #expect(!AnalyticsSeries.hasTokens([]))
    #expect(AnalyticsSeries.hasTokens([.zero, TokenMix(cacheWrite: 1, total: 1)]))
}

@Test func cacheReadShareDividesByTotalTokens() throws {
    let share = try #require(AnalyticsSeries.cacheReadShare(TokenMix(input: 30_000, cacheRead: 52_100, total: 96_400)))
    #expect(abs(share - 52_100.0 / 96_400.0) < 1e-9)
    #expect(AnalyticsSeries.cacheReadShare(.zero) == nil)
}

@Test func tokenFootnoteHasThreeStatesAndSelectionWins() {
    var mixes = [TokenMix](repeating: .zero, count: today.buckets.count)
    mixes[0] = TokenMix(input: 30_000_000, output: 7_000_000, cacheRead: 52_100_000, cacheWrite: 7_300_000, total: 86_600_000)
    mixes[9] = TokenMix(input: 3_000_000, output: 800_000, cacheRead: 5_200_000, cacheWrite: 800_000, total: 9_800_000)
    #expect(AnalyticsSeries.tokenFootnote(range: today, mixes: mixes, selected: nil, only: nil) == "合计 96.4M · 缓存读占 59% · 点图例只看一项")
    #expect(AnalyticsSeries.tokenFootnote(range: today, mixes: mixes, selected: 9, only: nil) == "10月16日 9:00–9:41 · 合计 9.8M")
    #expect(AnalyticsSeries.tokenFootnote(range: today, mixes: mixes, selected: 3, only: nil) == "10月16日 3:00–4:00 · 合计 0")
    #expect(AnalyticsSeries.tokenFootnote(range: today, mixes: mixes, selected: nil, only: .cacheRead) == "只看缓存读，再点一次图例恢复全部")
    #expect(AnalyticsSeries.tokenFootnote(range: today, mixes: mixes, selected: 9, only: .input) == "10月16日 9:00–9:41 · 合计 9.8M")
    // A selection past the buckets reads as none.
    #expect(AnalyticsSeries.tokenFootnote(range: today, mixes: mixes, selected: 42, only: .output) == "只看输出，再点一次图例恢复全部")
    let empty = [TokenMix](repeating: .zero, count: today.buckets.count)
    #expect(AnalyticsSeries.tokenFootnote(range: today, mixes: empty, selected: nil, only: nil) == "合计 0 · 缓存读占 — · 点图例只看一项")
}

@Test func tokenTileShowsTotalAndCacheReadShare() {
    let tile = AnalyticsSeries.tokenTile(TokenMix(input: 30_800_000, output: 6_700_000, cacheRead: 52_100_000, cacheWrite: 6_800_000, total: 96_400_000))
    #expect(tile == AnalyticsTileText(value: "96.4M", unit: "Tokens", label: "缓存读占 54%"))
    #expect(AnalyticsSeries.tokenTile(.zero) == AnalyticsTileText(value: "0", unit: "Tokens", label: "缓存读占 —"))
}

@Test func tokenTableListsTheKindsNewestFirst() throws {
    let mixes = AnalyticsSeries.tokenMixes(range: today, points: [point(9, input: 3_000_000, output: 800_000, cacheRead: 5_200_000, cacheWrite: 800_000)])
    let table = AnalyticsSeries.tokenTable(range: today, mixes: mixes)
    #expect(table.periodTitle == "时段")
    #expect(table.columns == ["输入", "输出", "缓存读", "缓存写"])
    #expect(table.rows.count == today.buckets.count && table.total == nil)
    let first = try #require(table.rows.first)
    #expect(first.bucketIndex == 9 && first.cells == ["3M", "800K", "5.2M", "800K"])
    #expect(first.spokenLabel == today.buckets[9].spokenLabel + "，输入 3M，输出 800K，缓存读 5.2M，缓存写 800K")
    #expect(table.rows.last?.cells == ["0", "0", "0", "0"])
}

// MARK: - 端点分布

@Test func endpointRowsSortByRequestsAndShareTheirSum() throws {
    let tied = "[{\"endpoint\":\"/b\",\"requests\":5,\"total_tokens\":1},{\"endpoint\":\"/a\",\"requests\":5,\"total_tokens\":1},"
        + "{\"endpoint\":\"/c\",\"requests\":10,\"total_tokens\":1}]"
    let stats = try summary(endpoints: inbound, upstream: tied)
    let rows = AnalyticsSeries.endpointRows(stats, side: .inbound)
    #expect(rows.map(\.name) == ["/v1/messages", "/v1/chat/completions", "/v1/responses"])
    #expect(rows.map(\.requests) == [10_920, 5_096, 2_184])
    #expect(rows.map(\.shareText) == ["60.0%", "28.0%", "12.0%"])
    #expect(rows[0].requestsText == "10,920")
    #expect(rows[0].costLine == "实际 $612.40")
    #expect(rows[0].spokenLabel == "/v1/messages，10,920 次请求，占 60.0%，实际 $612.40")
    // Shares are of the rows' sum (not total_requests); equal counts go by name.
    let upstream = AnalyticsSeries.endpointRows(stats, side: .upstream)
    #expect(upstream.map(\.name) == ["/c", "/a", "/b"])
    #expect(upstream.map(\.share) == [0.5, 0.25, 0.25])
    #expect(upstream[0].costLine == "实际 —" && upstream[0].spokenLabel.hasSuffix("实际 无数据"))
    #expect(EndpointSide.allCases.map(\.title) == ["入站端点", "上游端点"])
}

@Test func endpointRowsAreEmptyWhenMissingOrEmpty() throws {
    #expect(AnalyticsSeries.endpointRows(try summary(), side: .inbound).isEmpty)
    #expect(AnalyticsSeries.endpointRows(try summary(endpoints: "[]"), side: .inbound).isEmpty)
    let idle = "[{\"endpoint\":\"/v1/messages\",\"requests\":0,\"total_tokens\":0}]"
    #expect(AnalyticsSeries.endpointRows(try summary(endpoints: idle), side: .inbound).isEmpty)
    let inboundOnly = try summary(endpoints: inbound)
    #expect(AnalyticsSeries.endpointRows(inboundOnly, side: .inbound).count == 3)
    #expect(AnalyticsSeries.endpointRows(inboundOnly, side: .upstream).isEmpty)
    #expect(AnalyticsSeries.endpointRows(nil, side: .inbound).isEmpty)
}

@Test func endpointTileUsesTheFirstInboundRow() throws {
    #expect(AnalyticsSeries.endpointTile(try summary(endpoints: inbound)) == AnalyticsTileText(value: "60%", label: "/v1/messages 占请求"))
    #expect(AnalyticsSeries.endpointTile(try summary()) == AnalyticsTileText(value: "—", label: "没有用量"))
    #expect(AnalyticsSeries.endpointTile(nil) == AnalyticsTileText(value: "—", label: "没有用量"))
}

// MARK: - 用户用量趋势（S4-17b）

/// 10月10日 – 16日, by the day.
private let week = AnalyticsRange.resolve(.preset(.last7), now: morning, zone: shanghai)

private enum UserTrendFixture {
    static func point(_ date: String, user: Int, tokens: Int, actual: String? = nil, name: String? = nil,
                      email: String? = nil) throws -> UserTrendPoint {
        var fields: [String: Any] = ["date": date, "user_id": user, "requests": 1, "tokens": tokens]
        if let actual { fields["actual_cost"] = actual }
        if let name { fields["username"] = name }
        if let email { fields["email"] = email }
        return try JSONDecoder().decode(UserTrendPoint.self, from: JSONSerialization.data(withJSONObject: fields))
    }
}

@Test func userUsageSeriesMergesRowsPerUserAndFillsMissingBucketsWithZero() throws {
    let keys = week.buckets.map(\.wireKey)
    #expect(keys.first == "2026-10-10" && keys.count == 7)
    // users-trend comes by date, then tokens, and leaves out the buckets a user has no row in.
    let points = try [
        UserTrendFixture.point(keys[0], user: 7, tokens: 100, name: "A"),
        UserTrendFixture.point(keys[1], user: 8, tokens: 900, name: "B"),
        UserTrendFixture.point(keys[1], user: 7, tokens: 300, name: "A"),
        UserTrendFixture.point(keys[6], user: 7, tokens: 50, name: "A"),
    ]
    let series = UserUsageSeries(points: points, range: week, metric: .tokens)
    #expect(series.metric == .tokens && !series.isEmpty)
    #expect(series.rows.map(\.id) == [8, 7])
    #expect(series.rows[0].values == [0, 900, 0, 0, 0, 0, 0] && series.rows[0].total == 900 && series.rows[0].name == "B")
    #expect(series.rows[1].values == [100, 300, 0, 0, 0, 0, 50] && series.rows[1].total == 450 && series.rows[1].name == "A")
}

@Test func userUsageSeriesMatchesHourlyBucketsOfASingleDay() throws {
    let points = try [UserTrendFixture.point("2026-10-16 09:00", user: 1, tokens: 90), UserTrendFixture.point("2026-10-16 03:00", user: 1, tokens: 30)]
    let row = try #require(UserUsageSeries(points: points, range: today, metric: .tokens).rows.first)
    #expect(row.values.count == 10)
    #expect(row.values[3] == 30 && row.values[9] == 90)
    #expect(row.values.indices.filter { row.values[$0] != 0 } == [3, 9])
}

@Test func userUsageSeriesRanksBySelectedMetricWithUserIDTieBreakAndCapsAtTwelve() throws {
    #expect(UserUsageSeries.limit == 12 && UserUsageSeries.cardRowCount == 5)
    // Tokens fall with the id (user 5 ties user 2), actual cost rises with it.
    let points = try (1...13).reversed().map { id in
        try UserTrendFixture.point(week.buckets[2].wireKey, user: id, tokens: id == 5 ? 1_200 : (14 - id) * 100, actual: "\(id).00")
    }
    let tokens = UserUsageSeries(points: points, range: week, metric: .tokens)
    #expect(tokens.rows.map(\.userID) == [1, 2, 5, 3, 4, 6, 7, 8, 9, 10, 11, 12])
    let cost = UserUsageSeries(points: points, range: week, metric: .actualCost)
    #expect(cost.metric == .actualCost)
    #expect(cost.rows.map(\.userID) == Array((2...13).reversed()))
    #expect(cost.rows.first?.total == 13)
}

@Test func userUsageSeriesTotalsDecimalCostAndCountsEveryReplyRow() throws {
    let keys = week.buckets.map(\.wireKey)
    let points = try [
        UserTrendFixture.point(keys[0], user: 3, tokens: 10, actual: "0.1"),
        UserTrendFixture.point(keys[1], user: 3, tokens: 10, actual: "0.2"),
        UserTrendFixture.point(keys[2], user: 3, tokens: 10),
        // In another zone's calendar: no bucket, but the backend ranked with it.
        UserTrendFixture.point("2026-10-01", user: 3, tokens: 5, actual: "1.5"),
    ]
    let row = try #require(UserUsageSeries(points: points, range: week, metric: .actualCost).rows.first)
    #expect(row.values[0] + row.values[1] == Decimal(string: "0.3")!)
    #expect(row.values == [Decimal(string: "0.1")!, Decimal(string: "0.2")!, 0, 0, 0, 0, 0])
    #expect(row.total == Decimal(string: "1.8")!)
    #expect(UserUsageSeries(points: points, range: week, metric: .tokens).rows.first?.total == 35)
}

@Test func userUsageSparklineUsesEachRowsOwnScale() {
    #expect(UserUsageSeries.Row(userID: 1, name: "a", values: [0, 5, 10], total: 15).normalized == [0, 0.5, 1])
    #expect(UserUsageSeries.Row(userID: 2, name: "b", values: [100, 200], total: 300).normalized == [0.5, 1])
    let idle = UserUsageSeries.Row(userID: 3, name: "c", values: [0, 0, 0], total: 0).normalized
    #expect(idle == [0, 0, 0] && !idle.contains { $0.isNaN })
    #expect(UserUsageSeries.Row(userID: 4, name: "d", values: [], total: 0).normalized.isEmpty)
}

@Test func userTrendMetricNeedsCapabilityOnlyUnderFilter() {
    for supports in [true, false] {
        #expect(UserUsageSeries.metrics(isFiltered: false, supportsFilteredMetric: supports) == [.tokens, .actualCost])
        #expect(UserUsageSeries.requestMetric(.actualCost, isFiltered: false, supportsFilteredMetric: supports) == .actualCost)
        #expect(UserUsageSeries.requestMetric(.tokens, isFiltered: false, supportsFilteredMetric: supports) == .tokens)
    }
    #expect(UserUsageSeries.metrics(isFiltered: true, supportsFilteredMetric: true) == [.tokens, .actualCost])
    #expect(UserUsageSeries.requestMetric(.actualCost, isFiltered: true, supportsFilteredMetric: true) == .actualCost)
    // An old server reads no metric under a filter: send none.
    #expect(UserUsageSeries.metrics(isFiltered: true, supportsFilteredMetric: false) == [.tokens])
    #expect(UserUsageSeries.requestMetric(.tokens, isFiltered: true, supportsFilteredMetric: false) == nil)
    #expect(UserTrendMetric.allCases.map(\.title) == ["Tokens", "实际扣费"])
}

@Test func userTrendNoteTotalAndTileTexts() throws {
    #expect(UserUsageSeries.note(metric: .tokens, showsAll: false) == "按 Tokens 取前 12 位，这里显示前 5 位；每条线用自己的刻度，只看走势。")
    #expect(UserUsageSeries.note(metric: .tokens, showsAll: true) == "按 Tokens 取前 12 位；每条线用自己的刻度，只看走势。")
    #expect(UserUsageSeries.note(metric: .actualCost, showsAll: false) == "按实际扣费取前 12 位，这里显示前 5 位；每条线用自己的刻度，只看走势。")
    let day = week.buckets[0].wireKey
    let points = try [
        UserTrendFixture.point(day, user: 21, tokens: 12_400_000, actual: "389.20", name: "Nova 工作室"),
        UserTrendFixture.point(day, user: 22, tokens: 9_860_000, actual: "412.80", name: "Atlas 科技"),
        UserTrendFixture.point(day, user: 9, tokens: 1, name: "", email: ""),
        UserTrendFixture.point(day, user: 8, tokens: 2, name: " ", email: "x@example.com"),
    ]
    let tokens = UserUsageSeries(points: points, range: week, metric: .tokens)
    #expect(tokens.rows.map(\.name) == ["Nova 工作室", "Atlas 科技", "x@example.com", "#9"])
    #expect(tokens.rows.map(tokens.totalText) == ["12.4M", "9.9M", "2", "1"])
    #expect(tokens.tile == AnalyticsTileText(value: "12.4M", unit: "Tokens", label: "第 1 · Nova 工作室"))
    #expect(tokens.spokenLabel(0) == "第 1 名，Nova 工作室，12.4M Tokens")
    let cost = UserUsageSeries(points: points, range: week, metric: .actualCost)
    #expect(cost.rows.map(\.userID) == [22, 21, 8, 9])
    #expect(cost.totalText(cost.rows[0]) == "$412.80" && cost.totalText(cost.rows[3]) == "$0.00")
    #expect(cost.tile == AnalyticsTileText(value: "$412.80", label: "第 1 · Atlas 科技"))
    #expect(cost.spokenLabel(1) == "第 2 名，Nova 工作室，$389.20")
    let empty = UserUsageSeries(points: [], range: week, metric: .tokens)
    #expect(empty.isEmpty && empty.tile == AnalyticsTileText(value: "—", label: "没有用户用量"))
}

// MARK: - 请求类型（S4-17b）

private enum RequestTypeFixture {
    static func stats(_ rows: [(String, Int)]) throws -> [RequestTypeStat] {
        let json: [[String: Any]] = rows.map { ["request_type": $0.0, "requests": $0.1, "total_tokens": $0.1 * 10] }
        return try JSONDecoder().decode([RequestTypeStat].self, from: JSONSerialization.data(withJSONObject: json))
    }
    /// 近 7 天 with a group and a model.
    static let query = AnalyticsQuery(start: week.start, end: week.end, granularity: .day, timeZone: shanghai, groupID: 7,
                                      model: "claude-opus-4", modelSource: .requested)

    static func client(_ transport: ScriptedTransport) -> APIClient {
        let profile = ServerProfile(name: "Fixture", baseURL: URL(string: "https://analysis.example.invalid")!, authentication: .adminKey)
        return APIClient(server: profile, credential: .adminKey("fixture"), transport: transport, requestClock: .immediate, serverTimeZone: shanghai)
    }
    static func sent(_ request: URLRequest) -> [String: String] {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
}

@Test func requestTypeMixKeepsFixedOrderAndFillsMissingTypes() throws {
    let stats = try RequestTypeFixture.stats([("ws_v2", 40), ("stream", 30), ("unknown", 20), ("foo", 10), ("ws_v2", 2)])
    let mix = RequestTypeMix(stats: stats)
    #expect(mix.rows.map(\.type) == UsageRequestType.allCases)
    #expect(mix.rows.map(\.id) == [.stream, .sync, .wsV2, .cyber, .live])
    #expect(mix.rows.map(\.type.title) == ["流式", "同步", "WS", "安全策略", "Live"])
    // unknown and values the App does not know stay out; a type's rows add up.
    #expect(mix.rows.map(\.requests) == [30, 0, 42, 0, 0] && mix.total == 72)
    #expect(mix.rows.map(\.isEmpty) == [false, true, false, true, true])
}

@Test func requestTypeMixSharesBarAndTile() throws {
    let mix = RequestTypeMix(stats: try RequestTypeFixture.stats([("stream", 13_120), ("sync", 4_310), ("ws_v2", 612), ("cyber", 162)]))
    #expect(mix.total == 18_204 && !mix.isEmpty)
    #expect(mix.rows.map(\.shareText) == ["72.1%", "23.7%", "3.4%", "0.9%", "0.0%"])
    #expect(mix.rows.map(\.requestsText) == ["13,120", "4,310", "612", "162", "0"])
    #expect(abs(mix.rows.compactMap(\.share).reduce(0, +) - 1) < 1e-9)
    #expect(mix.barRows.map(\.type) == [.stream, .sync, .wsV2, .cyber])
    #expect(mix.tile == AnalyticsTileText(value: "72%", label: "流式占请求"))
    #expect(mix.rows[0].spokenLabel == "流式，13,120 次请求，占 72.1%")
    #expect(mix.rows[4].spokenLabel == "Live，0 次请求，占 0.0%")
    #expect(mix.barSpokenLabel == "流式 72.1%，同步 23.7%，WS 3.4%，安全策略 0.9%")
}

@Test func requestTypeMixWithoutRequestsIsEmpty() throws {
    let mixes = [RequestTypeMix(stats: []), RequestTypeMix(counts: [.stream: 0, .live: 0]),
                 RequestTypeMix(stats: try RequestTypeFixture.stats([("unknown", 9)]))]
    for mix in mixes {
        #expect(mix.isEmpty && mix.total == 0)
        #expect(mix.rows.map(\.type) == UsageRequestType.allCases)
        #expect(mix.rows.allSatisfy { $0.share == nil && $0.shareText == "—" && $0.isEmpty })
        #expect(mix.barRows.isEmpty)
        #expect(mix.tile == AnalyticsTileText(value: "—", label: "流式占请求"))
    }
}

@Test func requestTypeMixFromFallbackCountsEqualsStats() throws {
    let counts = RequestTypeMix(counts: [.stream: 9_800, .sync: 2_100, .cyber: 40, .live: 60])
    #expect(counts == RequestTypeMix(stats: try RequestTypeFixture.stats([("stream", 9_800), ("sync", 2_100), ("live", 60), ("cyber", 40)])))
    #expect(counts.rows.map(\.requests) == [9_800, 2_100, 0, 40, 60] && counts.total == 12_000)
}

@Test func requestTypeLoadReadsDashboardEndpointWithCapability() async throws {
    let transport = ScriptedTransport { _ in
        okReply(#"{"request_types":[{"request_type":"stream","requests":9,"total_tokens":90},{"request_type":"sync","requests":3,"total_tokens":30}]}"#)
    }
    var query = RequestTypeFixture.query
    query.requestType = .stream
    let mix = try await RequestTypeMix.load(query, client: RequestTypeFixture.client(transport), supportsRequestTypes: true)
    let requests = await transport.requests
    #expect(requests.count == 1)
    let request = try #require(requests.first)
    #expect(request.url?.path == "/api/v1/admin/dashboard/request-types")
    let sent = RequestTypeFixture.sent(request)
    #expect(sent["request_type"] == nil && sent["stream"] == nil)
    #expect(sent["group_id"] == "7" && sent["timezone"] == "Asia/Shanghai" && sent["start_time"] == ServerTime.utcTimestamp(week.start))
    #expect(mix.rows.map(\.requests) == [9, 3, 0, 0, 0])
}

@Test func requestTypeLoadFansOutFivePerTypeUsageStatsWithoutCapability() async throws {
    let counts = ["stream": 9_800, "sync": 2_100, "ws_v2": 0, "cyber": 40, "live": 60]
    let transport = ScriptedTransport { request in
        okReply(#"{"total_requests":\#(counts[RequestTypeFixture.sent(request)["request_type"] ?? ""] ?? -1),"total_tokens":0}"#)
    }
    let mix = try await RequestTypeMix.load(RequestTypeFixture.query, client: RequestTypeFixture.client(transport), supportsRequestTypes: false)
    let requests = await transport.requests
    #expect(requests.count == 5)
    #expect(requests.allSatisfy { $0.url?.path == "/api/v1/admin/usage/stats" })
    let sent = requests.map(RequestTypeFixture.sent)
    #expect(sent.compactMap { $0["request_type"] }.sorted() == UsageRequestType.allCases.map(\.rawValue).sorted())
    for items in sent {
        #expect(items["stream"] == nil)
        #expect(items["group_id"] == "7" && items["model"] == "claude-opus-4" && items["model_source"] == "requested")
        #expect(items["timezone"] == "Asia/Shanghai")
        #expect(items["start_time"] == ServerTime.utcTimestamp(week.start) && items["end_time"] == ServerTime.utcTimestamp(week.end))
    }
    #expect(mix == RequestTypeMix(counts: [.stream: 9_800, .sync: 2_100, .cyber: 40, .live: 60]))
}

@Test func requestTypeFallbackFailsWholeMixWhenOneTypeFails() async throws {
    let transport = ScriptedTransport { request in
        RequestTypeFixture.sent(request)["request_type"] == "live" ? errorReply(400) : okReply(#"{"total_requests":5,"total_tokens":0}"#)
    }
    let error = await thrownAPIError {
        _ = try await RequestTypeMix.load(RequestTypeFixture.query, client: RequestTypeFixture.client(transport), supportsRequestTypes: false)
    }
    #expect(error?.statusCode == 400)
}
