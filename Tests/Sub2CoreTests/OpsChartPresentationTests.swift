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
