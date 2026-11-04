import Foundation
import Testing
@testable import Sub2Core

// 40 §1.3 / §1.4 利润明细卡, row by row, and the old server's segment-by-segment account cost (S4-13b).

private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func amount(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
/// 2026-10-16 09:41 in Shanghai, a Friday: today has 10 hourly buckets, the last one running.
private let morning = utc("2026-10-16T01:41:00Z")
private let today = AnalyticsRange.resolve(.preset(.today), now: morning, zone: shanghai)
private let week = AnalyticsRange.resolve(.preset(.last7), now: morning, zone: shanghai)

private func totals(actual: String?, account: String?) throws -> AnalyticsSummary {
    var fields = ["\"total_requests\":10", "\"total_tokens\":100"]
    if let actual { fields.append("\"total_actual_cost\":\"\(actual)\"") }
    if let account { fields.append("\"total_account_cost\":\"\(account)\"") }
    return try JSONDecoder().decode(AnalyticsSummary.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
}
private func point(_ date: String, actual: String, account: String?) -> TrendPoint {
    TrendPoint(date: date, requests: 1, totalTokens: 10, cost: amount(actual), actualCost: amount(actual), accountCost: account.map(amount))
}
private func hour(_ range: AnalyticsRange, _ value: Int) -> AnalyticsBucket { range.buckets[value] }

// MARK: - 组装

@Test func profitBreakdownFillsEveryBucketAndSplitsToTheStatsTotals() throws {
    let trend = [point("2026-10-16 08:00", actual: "229.004", account: "100.002"), point("2026-10-16 09:00", actual: "10", account: "2")]
    let breakdown = ProfitBreakdown(range: today, trend: trend, summary: try totals(actual: "239.00", account: "102.00"))
    #expect(breakdown.lines.count == 10)
    #expect(breakdown.lines.map(\.bucket) == today.buckets)
    for line in breakdown.lines.prefix(8) { #expect(line.actual == 0 && line.accountCost == 0 && line.profit == 0) }
    #expect(breakdown.lines[8].actual == 229 && breakdown.lines[8].accountCost == 100 && breakdown.lines[8].profit == 129)
    #expect(breakdown.lines[9].actual == 10 && breakdown.lines[9].accountCost == 2 && breakdown.lines[9].profit == 8)
    #expect(breakdown.lines.compactMap(\.profit).reduce(0, +) == 137)
    #expect(breakdown.totalActual == 239 && breakdown.totalAccountCost == 102 && breakdown.totalProfit == 137)
    #expect(breakdown.isReconciled)
    #expect(!breakdown.isEmpty)
}

@Test func profitBreakdownKeepsLossesAndOnlyAnIdleRangeIsEmpty() throws {
    let losses = ProfitBreakdown(range: today, trend: [point("2026-10-16 08:00", actual: "1", account: "3"),
                                                      point("2026-10-16 09:00", actual: "2", account: "4")],
                                 summary: try totals(actual: "3", account: "7"))
    #expect(losses.lines[8].profit == -2 && losses.lines[9].profit == -2 && losses.totalProfit == -4)
    #expect(!losses.isEmpty)
    let idle = ProfitBreakdown(range: today, trend: [], summary: try totals(actual: "0", account: "0"))
    #expect(idle.isEmpty)
    #expect(idle.lines.allSatisfy { $0.actual == 0 && $0.accountCost == 0 && $0.profit == 0 })
    // Only an account cost (a group charged at rate 0): a loss, not an empty range.
    let costOnly = ProfitBreakdown(range: today, trend: [point("2026-10-16 09:00", actual: "0", account: "3")],
                                   summary: try totals(actual: "0", account: "3"))
    #expect(!costOnly.isEmpty && costOnly.lines[9].profit == -3)
    let even = ProfitBreakdown(range: today, trend: [point("2026-10-16 09:00", actual: "5", account: "5")],
                               summary: try totals(actual: "5", account: "5"))
    #expect(!even.isEmpty && even.lines[9].profit == 0)
    #expect(AnalyticsBarSeries.profit(range: today, breakdown: idle).isEmpty)
    #expect(!AnalyticsBarSeries.profit(range: today, breakdown: even).isEmpty)
}

@Test func profitBreakdownListsTheLatestFourNewestFirst() throws {
    let hourly = ProfitBreakdown(range: today, trend: [], summary: nil)
    #expect(hourly.recent().map(\.bucket.shortName) == ["9:00–9:41", "8:00–9:00", "7:00–8:00", "6:00–7:00"])
    let daily = ProfitBreakdown(range: week, trend: [], summary: nil)
    #expect(daily.recent().map(\.bucket.shortName) == ["16日 周五", "15日 周四", "14日 周三", "13日 周二"])
    let midnight = AnalyticsRange.resolve(.preset(.today), now: utc("2026-10-15T16:20:00Z"), zone: shanghai)
    #expect(ProfitBreakdown(range: midnight, trend: [], summary: nil).recent().count == 1)
    #expect(hourly.line(at: nil) == nil && hourly.line(at: 99) == nil && hourly.line(at: -1) == nil)
    #expect(hourly.line(at: 8)?.bucket.fullName == "10月16日 8:00–9:00")
}

@Test func profitBreakdownTakesLegacyCostsFromSegmentsAndLeavesAFailedSegmentBlank() throws {
    let trend = [point("2026-10-16 08:00", actual: "1", account: nil), point("2026-10-16 09:00", actual: "2", account: nil)]
    let segments = ProfitSegmentCosts([hour(today, 9)], costs: [amount("0.5")])
    let breakdown = ProfitBreakdown(range: today, trend: trend, summary: try totals(actual: "3", account: "1.2"), segments: segments)
    #expect(breakdown.lines[9].accountCost == amount("0.5") && breakdown.lines[9].profit == amount("1.5"))
    #expect(breakdown.lines[8].actual == 1 && breakdown.lines[8].accountCost == nil && breakdown.lines[8].profit == nil)
    #expect(breakdown.lines[7].accountCost == 0 && breakdown.lines[7].profit == 0)
    #expect(!breakdown.isReconciled)
    #expect(breakdown.totalProfit == amount("1.8"))
}

// MARK: - 逐段读取

@Test func profitSegmentsToReadAreTheRowsLackingAccountCost() throws {
    let complete = [point("2026-10-16 08:00", actual: "1", account: "0.5"), point("2026-10-16 09:00", actual: "2", account: "1")]
    #expect(ProfitBreakdown.segmentsToRead(range: today, trend: complete, summary: nil).isEmpty)
    let legacy = [point("2026-10-16 08:00", actual: "1", account: nil), point("2026-10-16 09:00", actual: "2", account: nil)]
    let wanted = ["2026-10-16 08:00", "2026-10-16 09:00"]
    #expect(ProfitBreakdown.segmentsToRead(range: today, trend: legacy, summary: nil).map(\.wireKey) == wanted)
    #expect(ProfitBreakdown.segmentsToRead(range: today, trend: legacy, summary: try totals(actual: "3", account: "1")).map(\.wireKey) == wanted)
    // The totals have no account cost either: the segments would not, so none is read.
    #expect(ProfitBreakdown.segmentsToRead(range: today, trend: legacy, summary: try totals(actual: "3", account: nil)).isEmpty)
}

@Test func profitSegmentsToRefreshAreTheMovedAndMissingBuckets() throws {
    let legacy = [point("2026-10-16 08:00", actual: "1", account: nil), point("2026-10-16 09:00", actual: "2", account: nil)]
    #expect(ProfitBreakdown.segmentsToRefresh(range: today, trend: legacy, summary: nil, previous: nil).map(\.wireKey)
        == ["2026-10-16 08:00", "2026-10-16 09:00"])
    let read = ProfitSegmentCosts([hour(today, 8), hour(today, 9)], costs: [1, 2])
    // Nothing moved: nothing to read again.
    #expect(ProfitBreakdown.segmentsToRefresh(range: today, trend: legacy, summary: nil, previous: read).isEmpty)
    // Now moves on: only the running hour.
    let later = AnalyticsRange.resolve(.preset(.today), now: utc("2026-10-16T01:50:00Z"), zone: shanghai)
    #expect(ProfitBreakdown.segmentsToRefresh(range: later, trend: legacy, summary: nil, previous: read).map(\.wireKey) == ["2026-10-16 09:00"])
    // A missing segment is read again too.
    let partial = ProfitSegmentCosts([hour(today, 8), hour(today, 9)], costs: [nil, 2])
    #expect(ProfitBreakdown.segmentsToRefresh(range: today, trend: legacy, summary: nil, previous: partial).map(\.wireKey) == ["2026-10-16 08:00"])
    // Past the hour: the hour read while running is read again whole, the new one for the first time.
    let nextHour = AnalyticsRange.resolve(.preset(.today), now: utc("2026-10-16T02:05:00Z"), zone: shanghai)
    let rolled = legacy + [point("2026-10-16 10:00", actual: "3", account: nil)]
    #expect(ProfitBreakdown.segmentsToRefresh(range: nextHour, trend: rolled, summary: nil, previous: read).map(\.wireKey)
        == ["2026-10-16 09:00", "2026-10-16 10:00"])
}

@Test func profitSegmentMergingKeepsOlderSegmentsAndTakesNewer() {
    let older = ProfitSegmentCosts([hour(today, 7), hour(today, 8), hour(today, 9)], costs: [1, 2, 3])
    let later = AnalyticsRange.resolve(.preset(.today), now: utc("2026-10-16T01:50:00Z"), zone: shanghai)
    let merged = older.merging(ProfitSegmentCosts([hour(later, 9)], costs: [4]), reread: [hour(later, 9)])
    #expect(merged.cost(for: hour(today, 7)) == 1 && merged.cost(for: hour(today, 8)) == 2 && merged.cost(for: hour(later, 9)) == 4)
    #expect(merged.covers(hour(later, 9)) && !merged.covers(hour(today, 9)))
    // A segment read again without an answer is missing, not left at its older value.
    let failed = older.merging(ProfitSegmentCosts([hour(later, 9)], costs: [4]), reread: [hour(today, 8), hour(later, 9)])
    #expect(failed.cost(for: hour(today, 8)) == nil && failed.cost(for: hour(today, 7)) == 1 && failed.cost(for: hour(later, 9)) == 4)
    #expect(ProfitSegmentCosts().segments.isEmpty && ProfitSegmentCosts().rateLimit == nil)
    // The 429 is the newest read's: one that stopped it stays with the merge, and a read without one clears an older one.
    let limit = APIError.server(status: 429, envelope: nil, retryAfter: 120)
    let limited = older.merging(ProfitSegmentCosts([hour(later, 9)], costs: [nil], rateLimit: limit), reread: [hour(later, 9)])
    #expect(limited.rateLimit == limit && limited.cost(for: hour(today, 7)) == 1 && limited.cost(for: hour(later, 9)) == nil)
    #expect(limited.merging(ProfitSegmentCosts([hour(later, 9)], costs: [4]), reread: [hour(later, 9)]).rateLimit == nil)
}

// MARK: - 文案与读屏

@Test func profitCardTextFollowsTheProfitCardTable() throws {
    #expect(ProfitCardText.title == "利润明细")
    #expect(ProfitCardText.meta == "实际扣费 − 账号成本")
    #expect(ProfitCardText.emptyText == "这个范围内没有扣费")
    let trend = [point("2026-10-16 08:00", actual: "1", account: "3"), point("2026-10-16 09:00", actual: "1", account: nil)]
    let lines = ProfitBreakdown(range: today, trend: trend, summary: nil).lines
    #expect(ProfitCardText.heroLabel(rangeName: "近 7 天", selected: nil) == "利润 · 近 7 天")
    #expect(ProfitCardText.heroLabel(rangeName: "今天", selected: lines[8]) == "10月16日 8:00–9:00")
    #expect(ProfitCardText.heroLabel(rangeName: "今天", selected: lines[9]) == "10月16日 9:00–9:41")
    #expect(ProfitCardText.heroValue(total: amount("-12.3"), selected: nil) == "−$12.30")
    #expect(ProfitCardText.heroValue(total: amount("772.42"), selected: lines[8]) == "−$2.00")
    // The selected bucket's missing profit stays missing rather than falling back to the total.
    #expect(ProfitCardText.heroValue(total: amount("772.42"), selected: lines[9]) == "—")
    #expect(ProfitCardText.heroValue(total: nil, selected: nil) == "—")
    #expect(ProfitCardText.selectionLine(lines[8]) == "实际 $1.00 · 账号成本 $3.00 · 再点一下取消")
    #expect(ProfitCardText.selectionLine(lines[9]) == "实际 $1.00 · 账号成本 — · 再点一下取消")
    #expect(ProfitCardText.periodColumnTitle(.hour) == "时段" && ProfitCardText.periodColumnTitle(.day) == "日期")
}

@Test func profitChangeLineUsesAPercentageOnlyWhenBothProfitsAreAboveZero() {
    #expect(ProfitCardText.changeLine(current: amount("108.2"), previous: 100, label: "比昨天同时") == "↑ 8.2% · 比昨天同时")
    #expect(ProfitCardText.changeLine(current: -10, previous: 20, label: "比昨天同时") == "↓ $30.00 · 比昨天同时")
    #expect(ProfitCardText.changeLine(current: 50, previous: amount("-36.2"), label: "比前 7 天同期") == "↑ $86.20 · 比前 7 天同期")
    #expect(ProfitCardText.changeLine(current: nil, previous: 5, label: "比昨天同时") == "比昨天同时 —")
    #expect(ProfitCardText.changeLine(current: 5, previous: nil, label: "比昨天同时") == "比昨天同时 —")
}

@Test func profitSpokenLabelsReadTheMinusSignAndMissingValues() throws {
    let trend = [point("2026-10-16 08:00", actual: "1", account: nil), point("2026-10-16 09:00", actual: "1", account: "13.3")]
    let breakdown = ProfitBreakdown(range: today, trend: trend, summary: nil)
    let series = AnalyticsBarSeries.profit(range: today, breakdown: breakdown)
    #expect(series.metricName == "利润")
    #expect(series.bars[9].value == amount("-12.3") && series.bars[8].value == nil && series.bars[7].value == 0)
    #expect(series.bars.allSatisfy { $0.line == nil })
    #expect(series.yDomain.lowerBound < 0 && series.yDomain.upperBound >= 0)
    #expect(series.spokenLabel(9) == "10月16日 9:00 到 9:41，利润 −$12.30")
    #expect(series.spokenLabel(8) == "10月16日 8:00 到 9:00，利润 无数据")
    #expect(ProfitCardText.rowSpoken(breakdown.lines[8]) == "10月16日 8:00 到 9:00，实际 $1.00，账号成本 无数据，利润 无数据")
    #expect(ProfitCardText.rowSpoken(breakdown.lines[9]) == "10月16日 9:00 到 9:41，实际 $1.00，账号成本 $13.30，利润 −$12.30")
    let daily = ProfitBreakdown(range: week, trend: [], summary: nil)
    #expect(ProfitCardText.rowSpoken(daily.lines[4]).hasPrefix("10月14日 周三，"))
}
