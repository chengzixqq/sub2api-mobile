import Foundation
import Testing
@testable import Sub2Core

// 40 §1.4 RPM / TPM 趋势卡, S0-07 (the site's zone on the axis), S0-08 (the RPM format) and 40 §2.7's PerformanceTrendView row.

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
/// 2026-10-15 09:01:00 in Shanghai, the UI fixture's “now” floored to the minute.
private let nineOhOne = Date(timeIntervalSince1970: 1_792_026_060)

/// A time of 2026-10-15 in Shanghai (`daysBack` 1 for the day before).
private func at(_ hour: Int, _ minute: Int, _ second: Int = 0, daysBack: Int = 0) -> Date {
    nineOhOne.addingTimeInterval(Double((hour * 60 + minute - 541) * 60 + second - daysBack * 86_400))
}

/// A window of `hours` ending at `end` with every bucket the server fills; `rates(index)` is (RPM, TPM) for a bucket, whose
/// counts follow the seconds it covers.
private func makeTrend(hours: Int, end: Date = nineOhOne, rates: (Int) -> (Double, Double)) -> PerformanceTrend {
    let start = end.addingTimeInterval(-Double(hours) * 3_600)
    let bucket = OpsBucket.forWindow(end.timeIntervalSince(start))
    let shape = PerformanceTrend(bucket: bucket, windowStart: start, windowEnd: end, points: bucket.starts(from: start, to: end).map {
        PerformanceTrend.Point(date: $0, requestCount: 0, tokenConsumed: 0)
    })
    let points = shape.points.enumerated().map { index, point in
        let (rpm, tpm) = rates(index), covered = shape.coveredSeconds(point)
        return PerformanceTrend.Point(date: point.date, requestCount: Int((rpm * covered / 60).rounded()),
                                      tokenConsumed: Int((tpm * covered / 60).rounded()))
    }
    return PerformanceTrend(bucket: bucket, windowStart: start, windowEnd: end, points: points)
}
/// The App fixture's last hour: 44 / 220K a minute, 08:10 34 / 160K, 08:30 52 / 260K, the newest (09:00) 46 / 240K.
private func hourTrend() -> PerformanceTrend {
    makeTrend(hours: 1) { index in
        switch index {
        case 9: (34, 160_000)
        case 29: (52, 260_000)
        case 59: (46, 240_000)
        default: (44, 220_000)
        }
    }
}
/// 44 / 220K a minute, the newest bucket 46 / 240K; the first and last 5-minute buckets cover 240 and 60 seconds.
private func trailingTrend(hours: Int) -> PerformanceTrend {
    let count = hours * 12 + 1
    return makeTrend(hours: hours) { $0 == count - 1 ? (46, 240_000) : (44, 220_000) }
}
private func emptyTrend(hours: Int, end: Date) -> PerformanceTrend {
    PerformanceTrend(bucket: .forWindow(Double(hours) * 3_600), windowStart: end.addingTimeInterval(-Double(hours) * 3_600), windowEnd: end, points: [])
}
private func point(_ trend: PerformanceTrend, at date: Date) throws -> PerformanceTrend.Point {
    try #require(trend.points.first { $0.date == date })
}
private func localParts(_ dates: [Date], _ zone: TimeZone) -> [[Int]] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return dates.map { [calendar.component(.hour, from: $0), calendar.component(.minute, from: $0)] }
}
private func localDate(_ zone: TimeZone, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
}

@Test func perfCardHeaderMetaFollowsOpsSwitchAndSiteWideNote() {
    #expect(PerfTrendPresentation.cardTitle == "RPM / TPM 趋势")
    #expect(PerfTrendPresentation.cardMeta(opsDisabled: false) == "截至现在 · 运维监控")
    #expect(PerfTrendPresentation.cardMeta(opsDisabled: true) == "运维监控")
    #expect(OpsChartCopy.siteWideNote == "运行类图表不支持按这个模型筛选，这里显示全站")
}

@Test func perfHeadlineShowsNewestBucketOrSelectedPoint() throws {
    let trend = hourTrend()
    #expect(trend.points.count == 60)
    #expect(PerfTrendPresentation.headlineLabel(trend, metric: .rpm, selected: nil, timeZone: shanghai) == "RPM · 最新一桶 09:00")
    #expect(PerfTrendPresentation.headlineValue(trend, metric: .rpm, selected: nil) == "46")
    #expect(PerfTrendPresentation.headlineLabel(trend, metric: .tpm, selected: nil, timeZone: shanghai) == "TPM · 最新一桶 09:00")
    #expect(PerfTrendPresentation.headlineValue(trend, metric: .tpm, selected: nil) == "240K")
    let picked = try point(trend, at: at(8, 30))
    #expect(PerfTrendPresentation.headlineLabel(trend, metric: .rpm, selected: picked, timeZone: shanghai) == "RPM · 08:30")
    #expect(PerfTrendPresentation.headlineValue(trend, metric: .rpm, selected: picked) == "52")
    let day = trailingTrend(hours: 24)
    let yesterday = try point(day, at: at(9, 0, daysBack: 1))
    #expect(PerfTrendPresentation.headlineLabel(day, metric: .rpm, selected: yesterday, timeZone: shanghai) == "RPM · 昨天 09:00")
    let empty = emptyTrend(hours: 1, end: nineOhOne)
    #expect(PerfTrendPresentation.headlineLabel(empty, metric: .rpm, selected: nil, timeZone: shanghai) == "RPM · 最新一桶")
    #expect(PerfTrendPresentation.headlineValue(empty, metric: .rpm, selected: nil) == "—")
}

@Test func perfSublineShowsPeakAverageWindowOrSelection() throws {
    let trend = hourTrend()
    #expect(PerfTrendPresentation.subline(trend, metric: .rpm, selected: nil, windowTitle: "近 1 小时", timeZone: shanghai)
            == "峰值 52 · 平均 44 · 近 1 小时")
    #expect(PerfTrendPresentation.subline(trend, metric: .tpm, selected: nil, windowTitle: "近 1 小时", timeZone: shanghai)
            == "峰值 260K · 平均 220K · 近 1 小时")
    let picked = try point(trend, at: at(8, 30))
    #expect(PerfTrendPresentation.subline(trend, metric: .rpm, selected: picked, windowTitle: "近 1 小时", timeZone: shanghai)
            == "08:30 · RPM 52 · 再点一下取消")
    // The average is Σ counts × 60 ÷ Σ covered seconds (17,424 × 60 ÷ 21,600 = 48.4), not the mean of the 73 rates (49.4): the
    // partial first bucket weighs by the 240 seconds it covers.
    let skewed = makeTrend(hours: 6) { index in index == 0 ? (440, 220_000) : (44, 220_000) }
    #expect(PerfTrendPresentation.subline(skewed, metric: .rpm, selected: nil, windowTitle: "近 6 小时", timeZone: shanghai)
            == "峰值 440 · 平均 48 · 近 6 小时")
    let empty = emptyTrend(hours: 1, end: nineOhOne)
    #expect(PerfTrendPresentation.subline(empty, metric: .rpm, selected: nil, windowTitle: "近 1 小时", timeZone: shanghai)
            == "峰值 — · 平均 — · 近 1 小时")
}

/// One hour bucket cut to `seconds` of window: its rate is `requests` × 60 ÷ `seconds`.
private func oneBucket(requests: Int, tokens: Int = 0, seconds: TimeInterval) -> PerformanceTrend {
    let start = nineOhOne.addingTimeInterval(-seconds)
    return PerformanceTrend(bucket: .hour, windowStart: start, windowEnd: nineOhOne,
                            points: [PerformanceTrend.Point(date: start, requestCount: requests, tokenConsumed: tokens)])
}

@Test func perfRatesUseRPMFormatAndCompactTPM() throws {
    let trend = hourTrend()
    #expect(PerfTrendPresentation.rowRates(try point(trend, at: at(9, 0)), in: trend) == "RPM 46 · TPM 240K")
    // S0-08: one decimal below 10, whole numbers from 10 after rounding, never compact.
    for (requests, seconds, expected) in [(0, 600.0, "RPM 0 · TPM 0"), (4, 600, "RPM 0.4 · TPM 0"), (166, 1_000, "RPM 10 · TPM 0"),
                                          (464, 600, "RPM 46 · TPM 0"), (12_000, 600, "RPM 1,200 · TPM 0")] {
        let quiet = oneBucket(requests: requests, seconds: seconds)
        #expect(PerfTrendPresentation.rowRates(try #require(quiet.points.first), in: quiet) == expected)
        #expect(PerfTrendPresentation.headlineValue(quiet, metric: .rpm, selected: nil) == String(expected.dropFirst(4).prefix { $0 != " " }))
    }
}

@Test func perfEmptyWhenEveryBucketIsZero() {
    let zero = makeTrend(hours: 1) { _ in (0, 0) }
    #expect(PerfTrendPresentation.isEmpty(zero))
    #expect(PerfTrendPresentation.isEmpty(emptyTrend(hours: 1, end: nineOhOne)))
    #expect(!PerfTrendPresentation.isEmpty(makeTrend(hours: 1) { $0 == 30 ? (1, 0) : (0, 0) }))
    #expect(!PerfTrendPresentation.isEmpty(makeTrend(hours: 1) { $0 == 30 ? (0, 10) : (0, 0) }))
    #expect(PerfTrendPresentation.emptyText == "这个时间范围内没有请求")
}

@Test func perfAxisTicksAreWholeMarksInSiteTimeZone() throws {
    let hour = PerfTrendPresentation.axisTicks(emptyTrend(hours: 1, end: nineOhOne), timeZone: shanghai)
    #expect(localParts(hour, shanghai) == [[8, 15], [8, 30], [8, 45], [9, 0]])
    let six = PerfTrendPresentation.axisTicks(emptyTrend(hours: 6, end: nineOhOne), timeZone: shanghai)
    #expect(localParts(six, shanghai) == [[4, 0], [6, 0], [8, 0]])
    let day = PerfTrendPresentation.axisTicks(emptyTrend(hours: 24, end: nineOhOne), timeZone: shanghai)
    #expect(localParts(day, shanghai) == [[12, 0], [18, 0], [0, 0], [6, 0]])
    #expect(day == day.sorted())
    #expect(hour.map { PerfTrendPresentation.axisLabel($0, timeZone: shanghai) } == ["08:15", "08:30", "08:45", "09:00"])
    // Half-hour offsets keep the site's own whole hours.
    let kolkata = try #require(TimeZone(identifier: "Asia/Kolkata"))
    let india = PerfTrendPresentation.axisTicks(emptyTrend(hours: 6, end: try localDate(kolkata, 2026, 10, 15, 9, 1)), timeZone: kolkata)
    #expect(localParts(india, kolkata) == [[4, 0], [6, 0], [8, 0]])
    // The night daylight saving ends has a 25-hour day: the marks stay on the clock's 00:00 / 06:00 / 12:00 / 18:00.
    let newYork = try #require(TimeZone(identifier: "America/New_York"))
    let fallBack = PerfTrendPresentation.axisTicks(emptyTrend(hours: 24, end: try localDate(newYork, 2026, 11, 1, 12, 1)), timeZone: newYork)
    #expect(localParts(fallBack, newYork) == [[18, 0], [0, 0], [6, 0], [12, 0]])
}

@Test func perfExplanationNamesBucketAndWindowStart() {
    #expect(PerfTrendPresentation.explanation(hourTrend(), timeZone: shanghai)
            == "每桶 1 分钟，速率 = 数量 × 60 ÷ 这一桶实际覆盖的秒数；窗口从 08:01 到现在，首尾不满一桶的按覆盖时长折算。RPM 含成功请求和错误请求，TPM 为成功请求的含缓存 Tokens。")
    let six = PerfTrendPresentation.explanation(trailingTrend(hours: 6), timeZone: shanghai)
    #expect(six.hasPrefix("每桶 5 分钟，") && six.contains("窗口从 03:01 到现在"))
    #expect(PerfTrendPresentation.explanation(trailingTrend(hours: 24), timeZone: shanghai).contains("窗口从昨天 09:01 到现在"))
}

@Test func perfUpdatedLineUsesSiteClockWithSeconds() {
    #expect(PerfTrendPresentation.updatedLine(Date(timeIntervalSince1970: 1_792_028_460), timeZone: shanghai) == "更新于 09:41:00 · 前台每 30 秒刷新")
    #expect(PerfTrendPresentation.updatedLine(nil, timeZone: shanghai) == nil)
}

@Test func perfDetailsFooterAndNoteCountPoints() {
    #expect(PerfTrendPresentation.detailsTitle == "性能明细")
    #expect(PerfTrendPresentation.detailsMeta(hourTrend()) == "60 桶 · 最新在上")
    #expect(PerfTrendPresentation.detailsMeta(trailingTrend(hours: 6)) == "73 桶 · 最新在上")
    #expect(PerfTrendPresentation.detailsNote(hourTrend(), windowTitle: "近 1 小时") == "最新在上 · 近 1 小时 · 每桶 1 分钟。点一行，图上选中这个时间。")
    #expect(PerfTrendPresentation.detailsNote(trailingTrend(hours: 6), windowTitle: "近 6 小时") == "最新在上 · 近 6 小时 · 每桶 5 分钟。点一行，图上选中这个时间。")
}

@Test func perfRowTitleMarksPartialBuckets() throws {
    let hour = hourTrend()
    #expect(PerfTrendPresentation.rowTitle(try point(hour, at: at(8, 30)), in: hour, timeZone: shanghai) == "08:30")
    let six = trailingTrend(hours: 6)
    #expect(PerfTrendPresentation.rowTitle(try point(six, at: at(9, 0)), in: six, timeZone: shanghai) == "09:00 · 只覆盖 60 秒")
    #expect(PerfTrendPresentation.rowTitle(try point(six, at: at(3, 0)), in: six, timeZone: shanghai) == "03:00 · 只覆盖 240 秒")
    let day = trailingTrend(hours: 24)
    #expect(PerfTrendPresentation.rowTitle(try point(day, at: at(9, 0, daysBack: 1)), in: day, timeZone: shanghai) == "昨天 09:00 · 只覆盖 240 秒")
    // A window that is not floored (40 §1.4's example) leaves 23 seconds in its newest bucket.
    let unfloored = makeTrend(hours: 1, end: at(9, 41, 23)) { _ in (44, 220_000) }
    #expect(unfloored.points.count == 61)
    #expect(PerfTrendPresentation.rowTitle(try point(unfloored, at: at(9, 41)), in: unfloored, timeZone: shanghai) == "09:41 · 只覆盖 23 秒")
}

@Test func perfSpokenPointReadsTimeRateAndCoverage() throws {
    let hour = hourTrend()
    #expect(PerfTrendPresentation.spokenPoint(try point(hour, at: at(8, 30)), in: hour, metric: .rpm, timeZone: shanghai) == "08:30，RPM 52")
    let six = trailingTrend(hours: 6)
    let newest = try point(six, at: at(9, 0))
    #expect(PerfTrendPresentation.spokenPoint(newest, in: six, metric: .rpm, timeZone: shanghai) == "09:00，RPM 46，只覆盖 60 秒")
    #expect(PerfTrendPresentation.spokenPoint(newest, in: six, metric: .tpm, timeZone: shanghai) == "09:00，TPM 240K，只覆盖 60 秒")
}

@Test func perfNearestIndexAndWindowHours() {
    let hour = hourTrend()
    #expect(PerfTrendPresentation.nearestIndex(to: at(8, 30, 20), in: hour) == 29)
    #expect(PerfTrendPresentation.nearestIndex(to: at(8, 30, 40), in: hour) == 30)
    #expect(PerfTrendPresentation.nearestIndex(to: at(7, 0), in: hour) == 0)
    #expect(PerfTrendPresentation.nearestIndex(to: at(10, 0), in: hour) == 59)
    #expect(PerfTrendPresentation.nearestIndex(to: nineOhOne, in: emptyTrend(hours: 1, end: nineOhOne)) == nil)
    #expect([1, 6, 24].map { PerfTrendPresentation.windowHours(emptyTrend(hours: $0, end: nineOhOne)) } == [1, 6, 24])
}

@Test func perfPollingStopsOnlyForInvalidOrForbidden() {
    for status in [400, 403] { #expect(PerfTrendPresentation.stopsPolling(after: .server(status: status, reason: nil))) }
    #expect(PerfTrendPresentation.stopsPolling(after: APIError(kind: .validation, message: "范围无效")))
    let continuing: [APIError?] = [.server(status: 404, reason: "OPS_DISABLED"), .server(status: 429, reason: nil), .server(status: 500, reason: nil),
                                   APIError(kind: .transport, message: "超时"), nil]
    for error in continuing { #expect(!PerfTrendPresentation.stopsPolling(after: error)) }
    #expect(PerfTrendPresentation.pollDelay(since: nil, now: nineOhOne, interval: 30) == 0)
    #expect(PerfTrendPresentation.pollDelay(since: nineOhOne.addingTimeInterval(-31), now: nineOhOne, interval: 30) == 0)
    #expect(PerfTrendPresentation.pollDelay(since: nineOhOne.addingTimeInterval(-10), now: nineOhOne, interval: 30) == 20)
    #expect(PerfTrendPresentation.refreshInterval == 30)
}
