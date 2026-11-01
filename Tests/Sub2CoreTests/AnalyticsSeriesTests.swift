import Foundation
import Testing
@testable import Sub2Core

// 40 §2.3 Token 使用趋势 and 端点分布, row by row, and the stacking every stacked chart shares (S4-17).

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
