import Foundation
import Testing
@testable import Sub2Core

// 40 §2.3 计费明细 / 利润明细 and §3.3 the chart page's table, row by row (S4-14).

private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func amount(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
/// 2026-10-16 09:41 in Shanghai, a Friday: today has 10 hourly buckets, the last one running.
private let morning = utc("2026-10-16T01:41:00Z")
private let today = AnalyticsRange.resolve(.preset(.today), now: morning, zone: shanghai)
private let week = AnalyticsRange.resolve(.preset(.last7), now: morning, zone: shanghai)
private let month = AnalyticsRange.resolve(.preset(.last30), now: morning, zone: shanghai)

private func summary(actual: String? = "1284.50", standard: String = "1402.00", account: String? = "512.08") throws -> AnalyticsSummary {
    var fields = ["\"total_requests\":18204", "\"total_tokens\":96400000", "\"total_cost\":\"\(standard)\""]
    if let actual { fields.append("\"total_actual_cost\":\"\(actual)\"") }
    if let account { fields.append("\"total_account_cost\":\"\(account)\"") }
    return try JSONDecoder().decode(AnalyticsSummary.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
}
private func point(_ date: String, actual: String?, cost: String = "1", requests: Int = 1, account: String? = nil) -> TrendPoint {
    TrendPoint(date: date, requests: requests, totalTokens: requests * 10, cost: amount(cost), actualCost: actual.map(amount),
               accountCost: account.map(amount))
}
private let billingPoints = [point("2026-10-16 08:00", actual: "229", cost: "250", requests: 1_234),
                             point("2026-10-16 09:00", actual: "12.5", cost: "15", requests: 80)]

// MARK: - 计费明细

@Test func billingTableListsEveryBucketNewestFirst() throws {
    let table = AnalyticsBillingDetail(range: today, points: billingPoints, summary: try summary()).table
    #expect(table.columns == ["实际", "标准", "请求"])
    #expect(table.periodTitle == "时段" && table.unit == "小时")
    #expect(table.rows.count == 10)
    #expect(table.rows.map(\.bucketIndex) == Array((0...9).reversed()))
    #expect(table.rows.first?.period == "9:00–9:41")
    #expect(table.rows.last?.period == "0:00–1:00")
    #expect(table.rows[1].cells == ["$229.00", "$250.00", "1,234"])
    #expect(table.rows[0].cells == ["$12.50", "$15.00", "80"])
    #expect(table.total == nil)

    let daily = AnalyticsBillingDetail(range: week, points: [], summary: nil).table
    #expect(daily.rows.count == 7)
    #expect(daily.rows.first?.period == "16日 周五" && daily.rows.last?.period == "10日 周六")
    #expect(daily.periodTitle == "日期" && daily.unit == "天")
}

@Test func billingTableFillsMissingBucketsWithZero() throws {
    let points = billingPoints + [point("2026-10-15 23:00", actual: "99"), point("2026-10-16 03:00", actual: nil, cost: "4", requests: 7)]
    let table = AnalyticsBillingDetail(range: today, points: points, summary: try summary()).table
    // Outside the range: dropped.
    #expect(table.rows.count == 10)
    #expect(table.rows.first { $0.bucketIndex == 2 }?.cells == ["$0.00", "$0.00", "0"])
    // A row whose actual charge is missing.
    #expect(table.rows.first { $0.bucketIndex == 3 }?.cells == ["—", "$4.00", "7"])
}

@Test func detailTableCardShowsSixRowsAndOffersTheRest() throws {
    let table = AnalyticsBillingDetail(range: today, points: billingPoints, summary: nil).table
    #expect(AnalyticsDetailTable.cardRowLimit == 6)
    #expect(table.shownRows(limit: 6, expanded: false).map(\.bucketIndex) == [9, 8, 7, 6, 5, 4])
    #expect(table.expandTitle(limit: 6, expanded: false) == "展开全部 10 小时")
    #expect(table.shownRows(limit: 6, expanded: true).count == 10)
    #expect(table.expandTitle(limit: 6, expanded: true) == nil)
    // Full size: every bucket, nothing folded.
    #expect(table.shownRows(limit: nil, expanded: false).count == 10)
    #expect(table.expandTitle(limit: nil, expanded: false) == nil)
    let days = AnalyticsBillingDetail(range: month, points: [], summary: nil).table
    #expect(days.expandTitle(limit: 6, expanded: false) == "展开全部 30 天")
    #expect(days.shownRows(limit: nil, expanded: false).count == 30)
    // 01:10: two buckets, nothing to unfold.
    let early = AnalyticsRange.resolve(.preset(.today), now: utc("2026-10-15T17:10:00Z"), zone: shanghai)
    let short = AnalyticsBillingDetail(range: early, points: [], summary: nil).table
    #expect(short.shownRows(limit: 6, expanded: false).count == 2)
    #expect(short.expandTitle(limit: 6, expanded: false) == nil)
}

@Test func billingHeadShowsTotalOrSelectedBucket() throws {
    let detail = AnalyticsBillingDetail(range: today, points: billingPoints + [point("2026-10-16 03:00", actual: nil)],
                                        summary: try summary())
    #expect(detail.head(selected: nil) == "实际 $1,284.50")
    #expect(detail.head(selected: 8) == "10月16日 8:00–9:00 · $229.00")
    #expect(detail.head(selected: 9) == "10月16日 9:00–9:41 · $12.50")
    #expect(detail.head(selected: 2) == "10月16日 2:00–3:00 · $0.00")
    #expect(detail.head(selected: 3) == "10月16日 3:00–4:00 · —")
    #expect(detail.head(selected: 10) == "实际 $1,284.50")
    #expect(detail.head(selected: -1) == "实际 $1,284.50")
    #expect(AnalyticsBillingDetail(range: today, points: [], summary: nil).head(selected: nil) == "实际 —")
    let daily = AnalyticsBillingDetail(range: week, points: [point("2026-10-14", actual: "88")], summary: nil)
    #expect(daily.head(selected: 4) == "10月14日 周三 · $88.00")
}

@Test func billingFiguresAndBarsComeFromTheCardsOwnHelpers() throws {
    let totals = try summary()
    let detail = AnalyticsBillingDetail(range: today, points: billingPoints, summary: totals)
    #expect(detail.figures == AnalyticsBillingCard.figures(totals))
    #expect(detail.figures.map(\.value) == ["$512.08", "$1,402.00", "$772.42"])
    #expect(detail.bars == AnalyticsBarSeries.billing(range: today, points: billingPoints))
    #expect(!detail.bars.isEmpty)
    let withoutCost = AnalyticsBillingDetail(range: today, points: [], summary: try summary(account: nil))
    #expect(withoutCost.figures.map(\.value) == ["—", "$1,402.00", "—"])
    #expect(AnalyticsBillingDetail(range: today, points: [], summary: nil).figures.map(\.value) == ["—", "—", "—"])
    #expect(AnalyticsBillingDetail(range: today, points: [point("2026-10-16 09:00", actual: "0")], summary: nil).bars.isEmpty)
}

@Test func billingRowsSpeakBucketAndColumns() throws {
    let table = AnalyticsBillingDetail(range: today, points: billingPoints + [point("2026-10-16 03:00", actual: nil)], summary: nil).table
    let row = try #require(table.rows.first { $0.bucketIndex == 8 })
    #expect(row.spokenLabel == "10月16日 8:00 到 9:00，实际 $229.00，标准 $250.00，请求 1,234")
    #expect(row.id == "8")
    #expect(table.rows.first { $0.bucketIndex == 3 }?.spokenLabel == "10月16日 3:00 到 4:00，实际 无数据，标准 $1.00，请求 1")
}

// MARK: - 利润明细

/// 8:00 earns 129 on 229; 9:00 loses 2 (1 against 3); the trend has every account cost.
private func profitBreakdown(_ range: AnalyticsRange = today) throws -> ProfitBreakdown {
    let trend = [point("2026-10-16 08:00", actual: "229", account: "100"), point("2026-10-16 09:00", actual: "1", account: "3")]
    return ProfitBreakdown(range: range, trend: trend, summary: try summary(actual: "230", account: "103"))
}
/// An old server: no account cost in the trend, 9:00's segment read, 8:00's failed.
private func legacyBreakdown() throws -> ProfitBreakdown {
    let trend = [point("2026-10-16 08:00", actual: "229"), point("2026-10-16 09:00", actual: "1")]
    let segments = ProfitSegmentCosts([today.buckets[9]], costs: [amount("3")])
    return ProfitBreakdown(range: today, trend: trend, summary: try summary(actual: "230", account: "103"), segments: segments)
}

@Test func profitTableUsesTheBreakdownAndDashesFailedSegments() throws {
    let breakdown = try profitBreakdown()
    let table = AnalyticsProfitDetail(range: today, breakdown: breakdown).table
    #expect(table.columns == ["实际", "账号成本", "利润"])
    #expect(table.periodTitle == ProfitCardText.periodColumnTitle(.hour) && table.unit == "小时")
    #expect(table.rows.map(\.bucketIndex) == Array((0...9).reversed()))
    #expect(table.rows[0].cells == ["$1.00", "$3.00", "−$2.00"])
    #expect(table.rows[1].cells == ["$229.00", "$100.00", "$129.00"])
    #expect(table.rows[2].cells == ["$0.00", "$0.00", "$0.00"])
    #expect(table.rows[1].spokenLabel == ProfitCardText.rowSpoken(breakdown.lines[8]))

    let legacy = AnalyticsProfitDetail(range: today, breakdown: try legacyBreakdown()).table
    #expect(legacy.rows[1].cells == ["$229.00", "—", "—"])
    #expect(legacy.rows[1].spokenLabel == "10月16日 8:00 到 9:00，实际 $229.00，账号成本 无数据，利润 无数据")
    #expect(legacy.rows[0].cells == ["$1.00", "$3.00", "−$2.00"])

    let daily = AnalyticsProfitDetail(range: week, breakdown: ProfitBreakdown(range: week, trend: [], summary: nil)).table
    #expect(daily.periodTitle == "日期" && daily.unit == "天" && daily.rows.first?.period == "16日 周五")
}

@Test func profitTotalRowAndNoteFollowGranularity() throws {
    let breakdown = try profitBreakdown()
    let detail = AnalyticsProfitDetail(range: today, breakdown: breakdown)
    let total = try #require(detail.table.total)
    #expect(total.period == "合计" && total.bucketIndex == nil && total.id == "total")
    #expect(total.cells == ["$230.00", "$103.00", "$127.00"])
    #expect(total.spokenLabel == "合计，实际 $230.00，账号成本 $103.00，利润 $127.00")
    #expect(breakdown.isReconciled)
    #expect(breakdown.lines.compactMap(\.profit).reduce(0, +) == breakdown.totalProfit)
    #expect(detail.note == "每小时的利润 = 这段的实际扣费 − 账号成本，逐段相加等于合计。")
    let daily = AnalyticsProfitDetail(range: week, breakdown: ProfitBreakdown(range: week, trend: [], summary: try summary(actual: "0", account: "0")))
    #expect(daily.note == "每天的利润 = 这段的实际扣费 − 账号成本，逐段相加等于合计。")
    // A missing segment: the rows no longer add up, so only the first half.
    let legacy = AnalyticsProfitDetail(range: today, breakdown: try legacyBreakdown())
    #expect(legacy.note == "每小时的利润 = 这段的实际扣费 − 账号成本。")
    #expect(legacy.table.total?.cells == ["$230.00", "$103.00", "$127.00"])
}

@Test func profitHeadFiguresAndEmpty() throws {
    let detail = AnalyticsProfitDetail(range: today, breakdown: try profitBreakdown())
    #expect(detail.head(selected: nil) == "利润 $127.00")
    #expect(detail.head(selected: 8) == "10月16日 8:00–9:00 · 利润 $129.00")
    #expect(detail.head(selected: 9) == "10月16日 9:00–9:41 · 利润 −$2.00")
    #expect(detail.head(selected: 12) == "利润 $127.00")
    #expect(AnalyticsProfitDetail(range: today, breakdown: try legacyBreakdown()).head(selected: 8) == "10月16日 8:00–9:00 · 利润 —")
    #expect(AnalyticsProfitDetail.head(total: nil, selected: nil) == "利润 —")
    #expect(detail.figures.map(\.key) == ["actualCost", "accountCost", "profit"])
    #expect(detail.figures.map(\.label) == ["实际扣费", "账号成本", "利润"])
    #expect(detail.figures.map(\.value) == detail.table.total?.cells)
    #expect(!detail.isEmpty)
    #expect(AnalyticsProfitDetail(range: today, breakdown: ProfitBreakdown(range: today, trend: [], summary: nil)).isEmpty)
}
