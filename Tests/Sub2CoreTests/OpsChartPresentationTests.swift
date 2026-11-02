import Foundation
import Testing
@testable import Sub2Core

// 40 §2.3 平均账号切换、请求时长分布、错误趋势 and §2.5 (S4-18). S4-18b appends 错误分布 and Token 请求统计 at the end.

private enum OpsChartFixture {
    static func utc(_ text: String) -> Date { ServerTime.parseTimestamp(text)! }
    static let zone = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
    /// Site time 2026-10-16 09:41, a Friday.
    static let now = utc("2026-10-16T01:41:00Z")
    static let todayStart = utc("2026-10-15T16:00:00Z")

    static func range(_ selection: AnalyticsRangeSelection, now: Date = now) -> AnalyticsRange {
        AnalyticsRange.resolve(selection, now: now, zone: zone)
    }
    static func day(_ text: String) -> AnalyticsDay { AnalyticsDay(text)! }
    static func singleDay(_ text: String) -> AnalyticsRange { range(.custom(from: day(text), to: day(text))) }

    /// One point per bucket from `start`: (requests, switches).
    static func throughput(_ bucket: OpsBucket, from start: Date = todayStart, _ counts: [(Int, Int)]) -> PerformanceTrend {
        let points = counts.enumerated().map { index, count in
            PerformanceTrend.Point(date: start.addingTimeInterval(Double(index) * bucket.seconds), requestCount: count.0, tokenConsumed: 0,
                                   switchCount: count.1)
        }
        return PerformanceTrend(bucket: bucket, windowStart: start, windowEnd: start.addingTimeInterval(Double(counts.count) * bucket.seconds),
                                points: points)
    }

    static let latencyCounts = [1_820, 3_640, 5_461, 4_187, 2_184, 912]
    static func histogram(_ counts: [Int] = latencyCounts) -> OpsLatencyHistogram {
        OpsLatencyHistogram(buckets: zip(OpsLatencyHistogram.BucketRange.allCases, counts).map { OpsLatencyHistogram.Bucket(range: $0, count: $1) })
    }
    static let overview = OpsOverview(errorRate: 0.017116, successCount: 18_204, errorCountTotal: 397, businessLimitedCount: 80, errorCountSLA: 317,
                                      requestCountSLA: 18_521,
                                      duration: OpsPercentiles(p50Ms: 2_400, p90Ms: 5_100, p95Ms: 8_200, p99Ms: 21_000, avgMs: 3_100, maxMs: 182_000),
                                      ttft: OpsPercentiles(p50Ms: 820, p90Ms: 1_900, p95Ms: 2_600, p99Ms: 6_400, avgMs: 1_100, maxMs: 42_000))

    /// `count` points `bucket` apart from `start`, each with `counts(index)`.
    static func errorTrend(_ bucket: OpsBucket, from start: Date = todayStart, count: Int,
                           counts: (Int) -> OpsErrorCounts = { _ in OpsErrorCounts(total: 3, sla: 2, businessLimited: 1) }) -> OpsErrorTrend {
        let points = (0..<count).map { OpsErrorTrend.Point(start: start.addingTimeInterval(Double($0) * bucket.seconds), counts: counts($0)) }
        return OpsErrorTrend(bucket: bucket, points: points, windowStart: start, windowEnd: start.addingTimeInterval(Double(count) * bucket.seconds))
    }
}

// MARK: - 平均账号切换

@Test func switchSummaryAddsSwitchesAndRequests() {
    let summary = OpsSwitchSummary(OpsChartFixture.throughput(.fiveMinutes, [(250, 3), (250, 8), (0, 0), (100, 1)]))
    #expect(summary.switches == 12 && summary.requests == 600)
    #expect(summary.switchesText == "12" && summary.averageText == "0.020" && summary.highestText == "0.032")
    #expect(summary.figures == [AnalyticsFigure("switches", label: "切换次数", value: "12"),
                                AnalyticsFigure("average", label: "平均 · 次/请求", value: "0.020"),
                                AnalyticsFigure("highest", label: "最高 · 次/请求", value: "0.032")])
    #expect(OpsSwitchSummary(OpsChartFixture.throughput(.hour, [(100_000, 1_234)])).switchesText == "1,234")
}

@Test func switchHighestSkipsBucketsWithoutRequests() {
    // A bucket without requests but with switches (an odd server value): counted, not drawn, never the highest.
    let summary = OpsSwitchSummary(OpsChartFixture.throughput(.fiveMinutes, [(100, 1), (0, 2), (200, 4)]))
    #expect(summary.switches == 7 && summary.requests == 300)
    #expect(summary.points.map(\.rate) == [0.01, 0.02])
    #expect(summary.highest == 0.02 && summary.highestText == "0.020")
}

@Test func switchWithoutRequestsShowsDashes() {
    let summary = OpsSwitchSummary(OpsChartFixture.throughput(.fiveMinutes, [(0, 0), (0, 0)]))
    #expect(summary.average == nil && summary.highest == nil && summary.points.isEmpty)
    #expect(summary.switchesText == "0" && summary.averageText == "—" && summary.highestText == "—")
}

@Test func switchPointsBreakTheLineAtBucketsWithoutRequests() {
    let trend = OpsChartFixture.throughput(.fiveMinutes, [(5, 1), (5, 2), (0, 0), (5, 0), (0, 0), (0, 0), (5, 5)])
    let summary = OpsSwitchSummary(trend)
    #expect(summary.points.map(\.segment) == [0, 0, 1, 2])
    #expect(summary.points.map(\.rate) == [0.2, 0.4, 0, 1])
    #expect(summary.points.map(\.date) == [0, 1, 3, 6].map { trend.points[$0].date })
    // A bucket the server left out breaks the line too; leading empty buckets start the first segment.
    let gap = OpsChartFixture.throughput(.minute, [(0, 0), (2, 1), (2, 1)])
    let missing = PerformanceTrend(bucket: .minute, windowStart: gap.windowStart, windowEnd: gap.windowEnd.addingTimeInterval(120),
                                   points: gap.points + [PerformanceTrend.Point(date: gap.windowEnd.addingTimeInterval(60), requestCount: 4,
                                                                                tokenConsumed: 0, switchCount: 1)])
    #expect(OpsSwitchSummary(missing).points.map(\.segment) == [0, 0, 1])
}

@Test(arguments: [(OpsBucket.minute, "曲线每分钟一点。"), (.fiveMinutes, "曲线每 5 分钟一点。"), (.hour, "曲线每小时一点。")])
func switchFootnoteFollowsTheBucket(bucket: OpsBucket, opening: String) {
    let footnote = OpsSwitchSummary(OpsChartFixture.throughput(bucket, [(10, 1)])).footnote
    #expect(footnote == opening + "请求因限流、过载或错误换到另一个账号，记一次切换。")
}

@Test func switchSupportsRangesUpToThirtyOneDaysAndAnHour() {
    let start = OpsChartFixture.todayStart
    #expect(OpsSwitchSummary.supports(start: start, end: start.addingTimeInterval(31 * 86_400 + 3_600)))
    #expect(!OpsSwitchSummary.supports(start: start, end: start.addingTimeInterval(31 * 86_400 + 3_601)))
    #expect(OpsSwitchSummary.spanLimitText == "平均账号切换只支持 31 天以内的范围")
    let lastMonth = OpsChartFixture.range(.preset(.lastMonth))
    #expect(OpsSwitchSummary.supports(start: lastMonth.start, end: lastMonth.end))
}

@Test func switchTicksOnTodayEveryThreeHoursEndingAtNow() {
    let today = OpsChartFixture.range(.preset(.today))
    let ticks = OpsSwitchSummary.axisTicks(for: today)
    // 9时 falls within the last 15% of the window, beside 现在.
    #expect(ticks.map(\.label) == ["0时", "3时", "6时", "现在"])
    #expect(ticks.map(\.date) == [0, 3, 6].map { OpsChartFixture.todayStart.addingTimeInterval(Double($0) * 3_600) } + [today.end])
    #expect(ticks.map(\.isNow) == [false, false, false, true])
}

@Test func switchTicksOnAPastDayEverySixHours() {
    let ticks = OpsSwitchSummary.axisTicks(for: OpsChartFixture.singleDay("2026-10-15"))
    #expect(ticks.map(\.label) == ["0时", "6时", "12时", "18时"])
    #expect(ticks.first?.date == OpsChartFixture.utc("2026-10-14T16:00:00Z") && ticks.allSatisfy { !$0.isNow })
}

@Test func switchTicksOnSeveralDaysAboutFourDates() {
    let week = OpsSwitchSummary.axisTicks(for: OpsChartFixture.range(.preset(.last7)))
    #expect(week.map(\.label) == ["10/10", "10/12", "10/14", "10/16"])
    #expect(week.last?.date == OpsChartFixture.todayStart && week.allSatisfy { !$0.isNow })
    #expect(OpsSwitchSummary.axisTicks(for: OpsChartFixture.range(.preset(.last30))).map(\.label) == ["9/22", "9/30", "10/8", "10/16"])
}

@Test func switchAxisAndSpokenPoints() {
    let today = OpsChartFixture.range(.preset(.today))
    let point = OpsSwitchSummary.Point(date: OpsChartFixture.utc("2026-10-16T01:40:00Z"), rate: 0.0123, segment: 0)
    #expect(OpsSwitchSummary.spokenPoint(point, range: today) == "今天 09:40，0.012 次/请求")
    #expect(OpsSwitchSummary.axisLabel(0.015) == "0.02" && OpsSwitchSummary.axisLabel(0) == "0.00")
}

// MARK: - 请求时长分布

@Test func latencyColumnsUseFixedLabelsHeightsAndWholeShares() {
    let summary = OpsLatencySummary(histogram: OpsChartFixture.histogram(), overview: OpsChartFixture.overview)
    #expect(summary.columns.map(\.label) == ["<100ms", "100–200", "200–500", "0.5–1s", "1–2s", "≥2s"])
    #expect(summary.columns.map(\.shareText) == ["10%", "20%", "30%", "23%", "12%", "5%"])
    #expect(summary.columns[2].height == 1 && abs(summary.columns[0].height - 1_820.0 / 5_461) < 1e-9)
    #expect(summary.columns[0].spokenLabel == "<100ms，10%，1,820 次")
    #expect(!summary.isEmpty)
}

@Test func latencyFootnoteCountsSuccessfulRequests() {
    #expect(OpsLatencySummary(histogram: OpsChartFixture.histogram(), overview: nil).footnote == "成功请求 18,204 次的总耗时分布")
}

@Test func latencyWithoutRequestsIsEmptyWithDashes() {
    let summary = OpsLatencySummary(histogram: OpsChartFixture.histogram([0, 0, 0, 0, 0, 0]), overview: OpsChartFixture.overview)
    #expect(summary.isEmpty && summary.footnote == nil && OpsLatencySummary.emptyText == "这个范围内没有成功请求")
    #expect(summary.rows(full: false).allSatisfy { $0.values == ["—", "—", "—", "—"] })
    #expect(summary.tileValue == "—")
}

@Test func latencyPercentileRowsOnCardAndFullScreen() {
    let summary = OpsLatencySummary(histogram: OpsChartFixture.histogram(), overview: OpsChartFixture.overview)
    #expect(OpsLatencySummary.headers(full: false) == ["P50", "P90", "P95", "P99"])
    #expect(OpsLatencySummary.headers(full: true) == ["P50", "P90", "P95", "P99", "平均", "最长"])
    let full = summary.rows(full: true)
    #expect(full.map(\.title) == ["总耗时", "首字"] && full.map(\.key) == ["duration", "ttft"])
    #expect(full[0].values == ["2.4s", "5.1s", "8.2s", "21s", "3.1s", "182s"])
    #expect(full[1].values == ["820ms", "1.9s", "2.6s", "6.4s", "1.1s", "42s"])
    #expect(summary.rows(full: false).map(\.values.count) == [4, 4])
    #expect(summary.rows(full: false)[0].spokenValue(headers: OpsLatencySummary.headers(full: false)) == "P50 2.4s，P90 5.1s，P95 8.2s，P99 21s")
}

@Test func latencyPercentilesWithoutOverviewOrNullFieldsShowDashes() {
    let missing = OpsLatencySummary(histogram: OpsChartFixture.histogram(), overview: nil).rows(full: true)
    #expect(missing.allSatisfy { $0.values == Array(repeating: "—", count: 6) })
    let partial = OpsOverview(duration: OpsPercentiles(p50Ms: 2_400), ttft: OpsPercentiles(p50Ms: 820, p90Ms: 1_900, p95Ms: 2_600))
    let rows = OpsLatencySummary(histogram: OpsChartFixture.histogram(), overview: partial).rows(full: false)
    #expect(rows[1].values == ["820ms", "1.9s", "2.6s", "—"])
    #expect(rows[1].spokenValue(headers: OpsLatencySummary.headers(full: false)).hasSuffix("P99 无数据"))
}

@Test func latencyTileReadsDurationP50() {
    let summary = OpsLatencySummary(histogram: OpsChartFixture.histogram(), overview: OpsChartFixture.overview)
    #expect(summary.tileValue == "2.4s" && OpsLatencySummary.tileCaption == "P50 总耗时")
    #expect(OpsLatencySummary(histogram: OpsChartFixture.histogram(), overview: nil).tileValue == "—")
}

// MARK: - 错误趋势

@Test func errorTrendNumbersLegendAndUpstreamLine() {
    let totals = OpsErrorCounts(total: 397, sla: 317, businessLimited: 80, upstream429: 186, upstream529: 64, upstreamOther: 53)
    let trend = OpsChartFixture.errorTrend(.hour, from: OpsChartFixture.utc("2026-10-09T16:00:00Z"), count: 1) { _ in totals }
    let summary = OpsErrorTrendSummary(trend: trend, overview: OpsChartFixture.overview, range: OpsChartFixture.range(.preset(.last7)))
    #expect(summary.totals == totals && !summary.isEmpty)
    #expect(summary.figures == [AnalyticsFigure("errors", label: "错误", value: "397"), AnalyticsFigure("rate", label: "错误率 · SLA", value: "1.7%"),
                                AnalyticsFigure("sla", label: "SLA 口径", value: "317")])
    #expect(summary.legendSLA == "SLA 错误 317" && summary.legendBusinessLimited == "业务限制 80")
    #expect(summary.upstreamLine == "上游失败（含重试成功）：429 186 · 529 64 · 其他 53")
    #expect(OpsErrorLayer.allCases.map(\.title) == ["SLA 错误", "业务限制"])
}

@Test func errorTrendRateComesFromOverviewAndIsDashWithoutSLARequests() {
    let trend = OpsChartFixture.errorTrend(.fiveMinutes, count: 3)
    let today = OpsChartFixture.range(.preset(.today))
    func rate(_ overview: OpsOverview?) -> String { OpsErrorTrendSummary(trend: trend, overview: overview, range: today).errorRateText }
    #expect(rate(OpsChartFixture.overview) == "1.7%")
    #expect(rate(nil) == "—")
    #expect(rate(OpsOverview(errorRate: nil, requestCountSLA: 100)) == "—")
    #expect(rate(OpsOverview(errorRate: 0, requestCountSLA: 0)) == "—")
    #expect(rate(OpsOverview(errorRate: 0, requestCountSLA: 100)) == "0.0%")
}

@Test func errorTrendBarsByHourOnADayAndByDayOnLongerRanges() {
    // Today to 09:41 in five-minute buckets: one bar an hour.
    let trend = OpsChartFixture.errorTrend(.fiveMinutes, count: 117) { index in
        OpsErrorCounts(total: 1 + index % 3, sla: 1, businessLimited: index % 3)
    }
    let today = OpsErrorTrendSummary(trend: trend, overview: nil, range: OpsChartFixture.range(.preset(.today)))
    #expect(today.bars.map(\.label) == (0...9).map { "\($0)时" })
    #expect(today.ticks.map(\.index) == [0, 3, 6, 9] && today.ticks.map(\.label) == ["0时", "3时", "6时", "现在"])
    let hourly = Dictionary(grouping: trend.points) { Int($0.start.timeIntervalSince(OpsChartFixture.todayStart) / 3_600) }
    #expect(today.bars.map(\.total) == (0...9).map { hour in hourly[hour, default: []].reduce(0) { $0 + $1.counts.total } })
    #expect(today.bars.map { $0.sla + $0.businessLimited } == today.bars.map(\.total))
    #expect(today.columns[1] == [.sla: Double(today.bars[1].sla), .businessLimited: Double(today.bars[1].businessLimited)])
    #expect(today.footnote.hasPrefix("后端每 5 分钟一桶，这里按小时合计。"))
    // Seven days in hour buckets: one bar a site day, the last one 今天.
    let week = OpsChartFixture.range(.preset(.last7))
    let daily = OpsErrorTrendSummary(trend: OpsChartFixture.errorTrend(.hour, from: week.start, count: 154), overview: nil, range: week)
    #expect(daily.bars.map(\.label) == ["10/10", "10/11", "10/12", "10/13", "10/14", "10/15", "10/16"])
    #expect(daily.bars.map(\.total) == [72, 72, 72, 72, 72, 72, 30])
    #expect(daily.ticks.last == AnalyticsAxisTick(index: 6, label: "今天", isNow: true))
    #expect(daily.bars[0].spokenName == "10月10日 周六")
}

@Test func errorTrendFiveMinuteBarsInTheFirstTwoHoursOfToday() {
    let now = OpsChartFixture.utc("2026-10-15T17:30:00Z")
    let range = OpsChartFixture.range(.preset(.today), now: now)
    let summary = OpsErrorTrendSummary(trend: OpsChartFixture.errorTrend(.minute, count: 90), overview: nil, range: range)
    #expect(summary.bars.count == 18 && summary.bars.first?.label == "00:00" && summary.bars.last?.label == "01:25")
    #expect(summary.bars.allSatisfy { $0.total == 15 })
    #expect(summary.ticks.map(\.index) == [0, 6, 17] && summary.ticks.map(\.label) == ["00:00", "00:30", "现在"])
    #expect(summary.bars.first?.spokenName == "00:00 到 00:05" && summary.bars.last?.end == now)
    #expect(summary.footnote.hasPrefix("后端每分钟一桶，这里按 5 分钟合计。"))
}

@Test func errorTrendSingleDayWithHourBucketsKeepsHourBars() {
    // A past single day answered in hour buckets (a 25-hour day where clocks go back): hour bars, not one day bar.
    let day = OpsChartFixture.singleDay("2026-10-15")
    let summary = OpsErrorTrendSummary(trend: OpsChartFixture.errorTrend(.hour, from: day.start, count: 24), overview: nil, range: day)
    #expect(summary.bars.count == 24 && summary.bars.map(\.total) == Array(repeating: 3, count: 24))
    #expect(summary.bars[9].label == "9时" && summary.ticks.map(\.label) == ["0时", "6时", "12时", "18时"])
    #expect(summary.footnote.hasPrefix("后端每小时一桶。"))
}

@Test(arguments: [(OpsBucket.minute, "后端每分钟一桶，这里按 5 分钟合计。"), (.fiveMinutes, "后端每 5 分钟一桶，这里按小时合计。"),
                  (.hour, "后端每小时一桶，这里按天合计。")])
func errorTrendFootnoteFollowsTheBucket(bucket: OpsBucket, opening: String) {
    let range = OpsChartFixture.range(bucket == .hour ? .preset(.last7) : .preset(.today))
    let summary = OpsErrorTrendSummary(trend: OpsChartFixture.errorTrend(bucket, from: range.start, count: 2), overview: nil, range: range)
    #expect(summary.footnote == opening + "错误率 = SLA 口径错误 ÷（成功 + SLA 口径错误），不算业务限制（用户自己的余额、额度、频率限制）。")
}

@Test func errorTrendWithoutErrorsIsEmpty() {
    let week = OpsChartFixture.range(.preset(.last7))
    let summary = OpsErrorTrendSummary(trend: OpsChartFixture.errorTrend(.hour, from: week.start, count: 0), overview: nil, range: week)
    #expect(summary.isEmpty && OpsErrorTrendSummary.emptyText == "这个范围内没有错误")
    #expect(summary.bars.count == 7 && summary.bars.allSatisfy { $0.total == 0 })
    #expect(summary.figures.first?.value == "0" && summary.upstreamLine == "上游失败（含重试成功）：429 0 · 529 0 · 其他 0")
}

@Test func errorTrendBucketBeforeTheRangeCountsInTheFirstBar() {
    // Kolkata's site day starts at :30 UTC; the hour bucket holding it begins half an hour before the range.
    let kolkata = ServerTimeZone(identifier: "Asia/Kolkata", utcOffset: "+05:30")!
    let range = AnalyticsRange.resolve(.preset(.last7), now: OpsChartFixture.now, zone: kolkata)
    let trend = OpsChartFixture.errorTrend(.hour, from: range.start.addingTimeInterval(-1_800), count: 2)
    let summary = OpsErrorTrendSummary(trend: trend, overview: nil, range: range)
    #expect(summary.bars[0].total == 6 && summary.totals.total == 6)
}

// MARK: - 卡头提示（40 §2.1、§2.5）

@Test func headerNotesSiteWideThenRetention() {
    let today = OpsChartFixture.range(.preset(.today))
    #expect(OpsChartCopy.headerNotes(siteWide: true, readsErrorLogs: true, range: today) == [OpsChartCopy.siteWideNote])
    // 上月 on 10-16 starts 9-01, before 30 days ago.
    let lastMonth = OpsChartFixture.range(.preset(.lastMonth))
    #expect(OpsChartCopy.headerNotes(siteWide: true, readsErrorLogs: true, range: lastMonth) == [OpsChartCopy.siteWideNote, OpsRetention.hint])
    #expect(OpsChartCopy.headerNotes(siteWide: false, readsErrorLogs: true, range: lastMonth) == [OpsRetention.hint])
    #expect(OpsChartCopy.headerNotes(siteWide: true, readsErrorLogs: false, range: lastMonth) == [OpsChartCopy.siteWideNote])
    #expect(OpsChartCopy.headerNotes(siteWide: false, readsErrorLogs: false, range: lastMonth).isEmpty)
    #expect(OpsChartCopy.siteWideNote == "运行类图表不支持按这个模型筛选，这里显示全站")
}

// MARK: - 错误分布、Token 请求统计与运行类磁贴（S4-18b）

private enum OpsTableFixture {
    /// The UI fixture's rows: 397 / SLA 317 / 业务限制 80, as 错误趋势's totals.
    static let distribution = OpsErrorDistribution(items: [
        .init(statusCode: 502, total: 72, sla: 72, businessLimited: 0), .init(statusCode: 429, total: 160, sla: 148, businessLimited: 12),
        .init(statusCode: 403, total: 68, sla: 0, businessLimited: 68), .init(statusCode: 529, total: 48, sla: 48, businessLimited: 0),
        .init(statusCode: 500, total: 31, sla: 31, businessLimited: 0), .init(statusCode: 504, total: 18, sla: 18, businessLimited: 0),
    ])

    static func item(_ model: String, _ requests: Int, _ speed: Double?, _ firstToken: Double?, _ duration: Double?) -> OpsTokenStats.Item {
        OpsTokenStats.Item(model: model, requestCount: requests, tokensPerSecond: speed, firstTokenMs: firstToken, durationMs: duration,
                           requestsWithFirstToken: requests)
    }
    /// The UI fixture's ten models in the server's order.
    static let items = [item("claude-opus-4", 1_210, 42.6, 1_840, 14_200), item("gpt-5", 1_100, 61.3, 920, 8_600),
                        item("deepseek-v3", 620, 38.2, 1_210, 9_800), item("gemini-2.5-pro", 380, 74.8, 760, 5_200),
                        item("gpt-4.1-mini", 350, 86.44, 410, 2_400), item("claude-sonnet-4", 300, 55.1, 1_020, 6_800),
                        item("glm-4.6", 195, 33, 1_500, 7_400), item("qwen3-coder", 120, nil, nil, 0),
                        item("kimi-k2", 90, 48.9, 980, 5_600), item("o4-mini", 60, 70.2, 690, 3_100)]
    static func stats(_ items: [OpsTokenStats.Item] = items, window: OpsTokenStatsWindow = .custom) -> OpsTokenStats {
        OpsTokenStats(items: items, window: window)
    }
    static func table(_ order: OpsTokenStatsOrder = .requests, full: Bool = false, pinned: String? = nil, group: String? = nil,
                      stats: OpsTokenStats = stats()) -> OpsTokenStatsTable {
        OpsTokenStatsTable(stats, order: order, full: full, pinnedModel: pinned, groupName: group)
    }
}

@Test func errorDistributionRowsKeepTheOrderWithWholeShares() {
    let summary = OpsErrorDistributionSummary(OpsTableFixture.distribution)
    #expect(!summary.isEmpty)
    #expect(summary.rows.map(\.statusCode) == [429, 502, 403, 529, 500, 504])
    #expect(summary.rows.map(\.codeText) == ["429", "502", "403", "529", "500", "504"])
    #expect(summary.rows.map(\.countText) == ["160", "72", "68", "48", "31", "18"])
    #expect(summary.rows.map(\.shareText) == ["40%", "18%", "17%", "12%", "8%", "5%"])
    #expect(summary.rows.map(\.tone) == [.caution, .critical, .critical, .critical, .critical, .critical])
    #expect(summary.rows.first?.bar == OpsErrorDistribution.BarLength(sla: 148.0 / 160, businessLimited: 12.0 / 160))
    #expect(summary.rows.dropFirst(2).first?.bar == OpsErrorDistribution.BarLength(sla: 0, businessLimited: 68.0 / 160))
}

@Test func errorDistributionRowReadsCodeCountShareAndParts() {
    let summary = OpsErrorDistributionSummary(OpsTableFixture.distribution)
    #expect(summary.rows.first?.spokenLabel == "状态码 429，160 条，占 40%，SLA 148，业务限制 12")
    #expect(summary.rows.dropFirst(2).first?.spokenLabel == "状态码 403，68 条，占 17%，SLA 0，业务限制 68")
    let large = OpsErrorDistributionSummary(OpsErrorDistribution(items: [.init(statusCode: 500, total: 1_204, sla: 1_204, businessLimited: 0)]))
    #expect(large.rows.first?.countText == "1,204" && large.rows.first?.shareText == "100%")
    #expect(large.rows.first?.spokenLabel == "状态码 500，1,204 条，占 100%，SLA 1,204，业务限制 0")
}

@Test func errorDistributionEmptyAndLegend() {
    let empty = OpsErrorDistributionSummary(OpsErrorDistribution(items: []))
    #expect(empty.isEmpty && empty.rows.isEmpty && OpsErrorDistributionSummary.emptyText == "这个范围内没有错误")
    #expect(OpsErrorDistributionSummary.legend.map(\.title) == ["429 限流", "其他错误（含 504、529）", "业务限制（不计 SLA）"])
    #expect(OpsErrorDistributionSummary.legend.map(\.tone) == [.caution, .critical, .neutral])
    #expect(OpsErrorDistributionSummary.legendSpoken == "429 限流，其他错误（含 504、529），业务限制（不计 SLA）")
}

@Test(arguments: [
    (OpsTokenStatsOrder.requests, ["claude-opus-4", "gpt-5", "deepseek-v3", "gemini-2.5-pro", "gpt-4.1-mini"]),
    (.speed, ["gpt-4.1-mini", "gemini-2.5-pro", "o4-mini", "gpt-5", "claude-sonnet-4"]),
    (.firstToken, ["gpt-4.1-mini", "o4-mini", "gemini-2.5-pro", "gpt-5", "kimi-k2"]),
])
func tokenStatsCardShowsFiveRowsInTheOrder(order: OpsTokenStatsOrder, models: [String]) {
    let table = OpsTableFixture.table(order)
    #expect(table.rows.map(\.model) == models)
    #expect(table.rows.allSatisfy { !$0.isPinned } && table.emptyText == nil)
}

@Test func tokenStatsFullSizeShowsNineRows() {
    let table = OpsTableFixture.table(.speed, full: true)
    #expect(table.rows.count == 9 && table.rows.last?.model == "glm-4.6")
    // Without a speed it sorts last, so only the filter brings it in.
    #expect(OpsTableFixture.table(.speed, full: true, pinned: "qwen3-coder").rows.map(\.model).suffix(2) == ["glm-4.6", "qwen3-coder"])
    #expect(OpsTokenStatsTable.headers == ["模型", "输出/秒", "首 Token", "平均时长"])
}

@Test func tokenStatsPinsTheFilteredModelInPlaceOrAtTheEnd() {
    let within = OpsTableFixture.table(pinned: "gpt-5")
    #expect(within.rows.count == 5 && within.rows.map(\.isPinned) == [false, true, false, false, false])
    let appended = OpsTableFixture.table(pinned: "glm-4.6")
    #expect(appended.rows.map(\.model) == ["claude-opus-4", "gpt-5", "deepseek-v3", "gemini-2.5-pro", "gpt-4.1-mini", "glm-4.6"])
    #expect(appended.rows.last?.isPinned == true && OpsTokenStatsTable.pinnedValue == "已筛选")
    #expect(OpsTableFixture.table(pinned: "unknown-model").rows.count == 5)
}

@Test func tokenStatsNumbersUseOneDecimalAndPercentileTimes() {
    let rows = Dictionary(uniqueKeysWithValues: OpsTableFixture.table(full: true).rows.map { ($0.model, $0) })
    #expect(rows["gpt-4.1-mini"]?.values == ["86.4", "410ms", "2.4s"])
    #expect(rows["claude-opus-4"]?.values == ["42.6", "1.8s", "14s"])
    #expect(rows["glm-4.6"]?.values == ["33.0", "1.5s", "7.4s"])
    // No speed, no first token, and the server's 0 for no duration.
    #expect(rows["qwen3-coder"]?.values == ["—", "—", "—"])
    #expect(rows["gpt-4.1-mini"]?.spokenLabel == "gpt-4.1-mini，输出每秒 86.4，首 Token 410ms，平均时长 2.4s")
    #expect(rows["qwen3-coder"]?.spokenLabel == "qwen3-coder，输出每秒 无数据，首 Token 无数据，平均时长 无数据")
}

@Test func tokenStatsFootnoteAndEmptyText() {
    #expect(OpsTableFixture.table().footnote == "统计窗口与所选范围一致。")
    let rolling = OpsTableFixture.stats(window: .rolling(.fifteenDays, coversRange: true))
    #expect(OpsTableFixture.table(group: "标准组", stats: rolling).footnote
        == "统计窗口近 15 天，截至现在：后端只有 30 分钟、1 小时、1 天、15 天、30 天这几种滚动窗口，这里取能盖住所选范围的最小一个。只列「标准组」用到的模型。")
    let empty = OpsTableFixture.stats([])
    let grouped = OpsTableFixture.table(group: "测试组", stats: empty)
    #expect(grouped.rows.isEmpty && grouped.emptyText == "这个分组在窗口内没有模型用量")
    #expect(grouped.footnote == "统计窗口与所选范围一致。只列「测试组」用到的模型。")
    #expect(OpsTableFixture.table(stats: empty).emptyText == "窗口内没有模型用量")
}

@Test func opsTilesReadTheSummaries() {
    let week = OpsChartFixture.range(.preset(.last7))
    let errors = OpsErrorTrendSummary(trend: OpsChartFixture.errorTrend(.hour, from: week.start, count: 154), overview: OpsChartFixture.overview,
                                      range: week)
    #expect(errors.errorRateText == "1.7%" && OpsErrorTrendSummary.tileCaption == "错误率 · SLA")
    #expect(errors.figures.map(\.label).contains(OpsErrorTrendSummary.tileCaption))
    #expect(errors.sketchValues == [72, 72, 72, 72, 72, 72, 30])
    let latency = OpsLatencySummary(histogram: OpsChartFixture.histogram(), overview: OpsChartFixture.overview)
    #expect(latency.sketchValues == [1_820, 3_640, 5_461, 4_187, 2_184, 912])
    #expect(latency.tileValue == "2.4s" && OpsLatencySummary.tileCaption == "P50 总耗时")
}
