import Foundation
import Testing
@testable import Sub2Core

// 40 §1.4 计费趋势卡, row by row (S4-13).

private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
/// 2026-10-16 09:41 in Shanghai, a Friday.
private let morning = utc("2026-10-16T01:41:00Z")
private let today = AnalyticsRange.resolve(.preset(.today), now: morning, zone: shanghai)
private let week = AnalyticsRange.resolve(.preset(.last7), now: morning, zone: shanghai)

private func summary(actual: String? = "1284.50", standard: String = "1610.14", account: String? = "512.08", requests: Int = 18_204,
                     tokens: Int = 96_400_000, duration: Double? = 2400) throws -> AnalyticsSummary {
    var fields = ["\"total_requests\":\(requests)", "\"total_tokens\":\(tokens)", "\"total_cost\":\"\(standard)\""]
    if let actual { fields.append("\"total_actual_cost\":\"\(actual)\"") }
    if let account { fields.append("\"total_account_cost\":\"\(account)\"") }
    if let duration { fields.append("\"average_duration_ms\":\(duration)") }
    return try JSONDecoder().decode(AnalyticsSummary.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
}

private func point(_ date: String, actual: Decimal?, cost: Decimal, requests: Int = 10) -> TrendPoint {
    TrendPoint(date: date, requests: requests, totalTokens: requests * 1_000, cost: cost, actualCost: actual)
}

private func card(_ range: AnalyticsRange = today, summary: AnalyticsSummary?, comparison: AnalyticsBillingCard.Comparison = .pending,
                  points: [TrendPoint] = [], selected: Int? = nil) -> AnalyticsBillingCard {
    AnalyticsBillingCard(range: range, summary: summary, comparison: comparison, points: points, selected: selected)
}

@Test func headlineIsActualCostAndRangeNameUntilABarIsSelected() throws {
    let totals = try summary()
    #expect(card(summary: totals).headline == "实际扣费 · 今天")
    #expect(card(week, summary: totals).headline == "实际扣费 · 近 7 天")
    #expect(card(summary: totals, selected: 9).headline == "10月16日 9:00–9:41")
    #expect(card(summary: totals, selected: 8).headline == "10月16日 8:00–9:00")
    #expect(card(week, summary: totals, selected: 4).headline == "10月14日 周三")
    // A selection past the bars reads as none.
    #expect(card(week, summary: totals, selected: 7).headline == "实际扣费 · 近 7 天")
}

@Test func amountComesFromTotalsOrTheSelectedBucket() throws {
    let totals = try summary()
    let points = [point("2026-10-16 09:00", actual: 229, cost: 302.1), point("2026-10-16 07:00", actual: nil, cost: 12)]
    #expect(card(summary: totals, points: points).amount == "$1,284.50")
    #expect(card(summary: totals, points: points, selected: 9).amount == "$229.00")
    #expect(card(summary: totals, points: points, selected: 8).amount == "$0.00")
    #expect(card(summary: totals, points: points, selected: 7).amount == "—")
    #expect(card(summary: nil, points: points).amount == "—")
    #expect(card(summary: try summary(actual: nil)).amount == "—")
}

@Test func changeLineComparesWithTheComparisonWindow() throws {
    let totals = try summary()
    #expect(card(summary: totals, comparison: .loaded(try summary(actual: "1188.30"))).changeLine == "↑ 8.1% · 比昨天同时")
    #expect(card(summary: try summary(actual: "1000"), comparison: .loaded(try summary(actual: "1188.30"))).changeLine
        == "↓ 15.8% · 比昨天同时")
    #expect(card(summary: totals, comparison: .loaded(try summary(actual: "0"))).changeLine == "比昨天同时 —")
    #expect(card(summary: totals, comparison: .loaded(try summary(actual: nil))).changeLine == "比昨天同时 —")
    #expect(card(week, summary: try summary(actual: "8412.30"), comparison: .loaded(try summary(actual: "7796.20"))).changeLine
        == "↑ 7.9% · 比前 7 天同期")
    // Only hidden: while the comparison loads or after it failed, while a bar is selected, without the totals.
    #expect(card(summary: totals, comparison: .pending).changeLine == nil)
    #expect(card(summary: totals, comparison: .failed).changeLine == nil)
    #expect(card(summary: totals, comparison: .loaded(try summary(actual: "1188.30")), selected: 3).changeLine == nil)
    #expect(card(summary: nil, comparison: .loaded(try summary(actual: "1188.30"))).changeLine == nil)
}

@Test func selectionLineShowsStandardAndRequests() throws {
    let totals = try summary()
    let points = [point("2026-10-16 09:00", actual: 229, cost: Decimal(string: "302.10")!, requests: 4_210)]
    #expect(card(summary: totals, points: points, selected: 9).selectionLine == "标准 $302.10 · 请求 4,210 · 再点一下取消")
    #expect(card(summary: totals, points: points, selected: 2).selectionLine == "标准 $0.00 · 请求 0 · 再点一下取消")
    #expect(card(summary: totals, points: points).selectionLine == nil)
    #expect(card(summary: totals, points: points, selected: 10).selectionLine == nil)
}

@Test func cellsShowAccountCostStandardAndProfit() throws {
    let figures = AnalyticsBillingCard.figures(try summary())
    #expect(figures.map(\.key) == ["accountCost", "standardCost", "profit"])
    #expect(figures.map(\.label) == ["账号成本", "标准", "利润"])
    #expect(figures.map(\.value) == ["$512.08", "$1,610.14", "$772.42"])
    // A loss reads −$ and never +.
    #expect(AnalyticsBillingCard.figures(try summary(account: "1400")).map(\.value) == ["$1,400.00", "$1,610.14", "\u{2212}$115.50"])
    #expect(AnalyticsBillingCard.figures(try summary(account: nil)).map(\.value) == ["—", "$1,610.14", "—"])
    #expect(AnalyticsBillingCard.figures(nil).map(\.value) == ["—", "—", "—"])
    let shown = card(summary: try summary(account: nil))
    #expect([shown.accountCost, shown.standardCost, shown.profit] == ["—", "$1,610.14", "—"])
}

@Test func requestsTokensAndAverageDuration() throws {
    let shown = card(summary: try summary())
    #expect([shown.requests, shown.tokens, shown.averageDuration] == ["18,204", "96.4M", "2.4s"])
    let idle = card(summary: try summary(actual: "0", requests: 0, tokens: 0, duration: 0))
    #expect([idle.requests, idle.tokens, idle.averageDuration] == ["0", "0", "—"])
    let missing = card(summary: nil)
    #expect([missing.requests, missing.tokens, missing.averageDuration] == ["—", "—", "—"])
    #expect(card(summary: try summary(duration: nil)).averageDuration == "—")
}

@Test func footCountsHoursOrDays() throws {
    #expect(card(summary: nil).footTitle == "全部 10 小时")
    #expect(card(week, summary: nil).footTitle == "全部 7 天")
    // The day New York's clock goes back: the repeated hour is one bucket, as AnalyticsRange counts them.
    let newYork = ServerTimeZone(identifier: "America/New_York", utcOffset: nil)!
    let fallBack = AnalyticsDay("2026-11-01")!
    let past = AnalyticsRange.resolve(.custom(from: fallBack, to: fallBack), now: utc("2026-11-02T15:00:00Z"), zone: newYork)
    #expect(past.granularity == .hour && past.buckets.count == 24)
    #expect(card(past, summary: nil).footTitle == "全部 24 小时")
}

@Test func barsFillTheRangeAndDrawStandardAsTheLine() throws {
    let days = ["2026-10-10", "2026-10-11", "2026-10-12", "2026-10-14", "2026-10-15", "2026-10-16"]
    var points = days.enumerated().map { index, day in point(day, actual: Decimal(index + 1) * 100, cost: Decimal(index + 1) * 125) }
    points[1] = point("2026-10-11", actual: nil, cost: 250)
    let shown = card(week, summary: try summary(actual: "8412.30"), points: points)
    #expect(shown.bars == AnalyticsBarSeries.billing(range: week, points: points))
    #expect(shown.bars.metricName == "实际扣费")
    #expect(shown.bars.bars.map(\.value) == [100, nil, 300, 0, 400, 500, 600])
    #expect(shown.bars.bars.map(\.line) == [125, 250, 375, 0, 500, 625, 750])
    #expect(!shown.bars.isEmpty)
    let empty = card(week, summary: try summary(actual: "0", standard: "0", account: "0", requests: 0, tokens: 0), points: [])
    #expect(empty.bars.isEmpty)
    #expect(empty.amount == "$0.00" && empty.requests == "0")
}
