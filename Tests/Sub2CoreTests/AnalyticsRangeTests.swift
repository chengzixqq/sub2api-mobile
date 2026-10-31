import Foundation
import Testing
@testable import Sub2Core

private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func day(_ text: String) -> AnalyticsDay { AnalyticsDay(text)! }
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let newYork = ServerTimeZone(identifier: "America/New_York", utcOffset: nil)!
private let siteDevice = TimeZone(identifier: "Asia/Shanghai")!
/// 2026-10-16 09:41 in Shanghai, a Friday (40 §1.2's examples).
private let morning = utc("2026-10-16T01:41:00Z")
private func range(_ selection: AnalyticsRangeSelection, now: Date = morning, zone: ServerTimeZone = shanghai) -> AnalyticsRange {
    AnalyticsRange.resolve(selection, now: now, zone: zone)
}
private func custom(_ from: String, _ to: String) -> AnalyticsRangeSelection { .custom(from: day(from), to: day(to)) }
private struct TrendRow: Equatable, Sendable { let date: String; let value: Int }

// MARK: Presets, days and bounds

@Test func analyticsPresetsKeepStableKeysTitlesAndShortcuts() {
    #expect(AnalyticsPreset.allCases.map(\.rawValue) == ["today", "last7", "last30", "thisMonth", "last14", "lastMonth"])
    #expect(AnalyticsPreset.allCases.map(\.title) == ["今天", "近 7 天", "近 30 天", "本月", "近 14 天", "上月"])
    #expect(AnalyticsPreset.shortcuts == [.thisMonth, .last14, .lastMonth])
    #expect(AnalyticsRangeSegment.allCases.map(\.title) == ["今天", "7 天", "30 天", "自定义"])
    #expect(AnalyticsRangeSegment.allCases.map(\.preset) == [.today, .last7, .last30, nil])
    #expect(AnalyticsRangeSelection.preset(.last7).preset == .last7 && custom("2026-10-12", "2026-10-14").preset == nil)
}

@Test func analyticsDayRoundTripsAndValidatesCalendarDays() {
    #expect(AnalyticsDay("2026-10-16")?.description == "2026-10-16")
    #expect(AnalyticsDay(year: 2026, month: 3, day: 5)?.description == "2026-03-05")
    #expect(AnalyticsDay(day("2026-03-05").description) == day("2026-03-05"))
    #expect(AnalyticsDay("2028-02-29") != nil)
    for bad in ["2026-02-29", "2026-13-01", "2026-00-10", "2026-04-31", "2026-2-5", " 2026-10-16", "2026-10-16T00:00", "abcd-ef-gh", ""] {
        #expect(AnalyticsDay(bad) == nil, "\(bad)")
    }
    #expect(day("2026-10-16").adding(days: -366) == day("2025-10-15"))
    #expect(day("2026-02-28").adding(days: 1) == day("2026-03-01") && day("2028-02-28").adding(days: 1) == day("2028-02-29"))
    #expect(day("2025-10-15").days(to: day("2026-10-16")) == 366)
    #expect(day("2026-10-14") < day("2026-10-16") && day("2025-12-31") < day("2026-01-01"))
    #expect(day("2026-10-16").weekdayName == "周五" && day("2026-10-14").weekdayName == "周三")
    #expect(AnalyticsDay(containing: utc("2026-10-15T16:30:00Z"), in: shanghai) == day("2026-10-16"))
    #expect(day("2026-10-16").start(in: shanghai) == utc("2026-10-15T16:00:00Z"))
}

@Test func analyticsDayBoundsReachBack366Days() {
    let bounds = AnalyticsDayBounds(now: morning, zone: shanghai)
    #expect(AnalyticsDayBounds.maxDaysBack == 366)
    #expect(bounds.earliest == day("2025-10-15") && bounds.latest == day("2026-10-16"))
    #expect(bounds.contains(day("2025-10-15")) && bounds.contains(day("2026-10-16")))
    #expect(!bounds.contains(day("2025-10-14")) && !bounds.contains(day("2026-10-17")))
    #expect(bounds.clamp(day("2024-01-01")) == day("2025-10-15") && bounds.clamp(day("2027-01-01")) == day("2026-10-16"))
    #expect(bounds.clamp(day("2026-05-05")) == day("2026-05-05"))
}

// MARK: Range table (40 §1.2)

@Test func analyticsRangeTableGivesWindowsGranularityAndNames() {
    let today = range(.preset(.today))
    #expect(today.start == utc("2026-10-15T16:00:00Z") && today.end == morning)
    #expect(today.granularity == .hour && today.buckets.count == 10 && today.includesNow && today.name == "今天")
    let rows: [(AnalyticsPreset, String, Int, String)] = [
        (.last7, "2026-10-10", 7, "近 7 天"), (.last30, "2026-09-17", 30, "近 30 天"), (.last14, "2026-10-03", 14, "近 14 天"),
        (.thisMonth, "2026-10-01", 16, "本月")
    ]
    for (preset, first, count, name) in rows {
        let resolved = range(.preset(preset))
        #expect(resolved.firstDay == day(first) && resolved.lastDay == day("2026-10-16"), "\(preset)")
        #expect(resolved.start == day(first).start(in: shanghai) && resolved.end == morning && resolved.includesNow, "\(preset)")
        #expect(resolved.granularity == .day && resolved.buckets.count == count && resolved.dayCount == count, "\(preset)")
        #expect(resolved.name == name, "\(preset)")
    }
    let lastMonth = range(.preset(.lastMonth))
    #expect(lastMonth.start == utc("2026-08-31T16:00:00Z") && lastMonth.end == utc("2026-09-30T16:00:00Z"))
    #expect(lastMonth.granularity == .day && lastMonth.buckets.count == 30 && !lastMonth.includesNow && lastMonth.name == "上月")
    #expect(range(.preset(.lastMonth), now: utc("2026-03-10T01:41:00Z")).buckets.count == 28)
    #expect(range(.preset(.lastMonth), now: utc("2028-03-10T01:41:00Z")).buckets.count == 29)
    let firstOfMonth = range(.preset(.thisMonth), now: utc("2026-10-01T01:41:00Z"))
    #expect(firstOfMonth.granularity == .day && firstOfMonth.buckets.count == 1 && firstOfMonth.name == "本月")
}

@Test func analyticsCustomRangesEndAtTheNextMidnightOrNow() {
    let past = range(custom("2026-10-12", "2026-10-14"))
    #expect(past.start == utc("2026-10-11T16:00:00Z") && past.end == utc("2026-10-14T16:00:00Z"))
    #expect(past.granularity == .day && past.buckets.count == 3 && !past.includesNow && past.name == "自选 3 天")
    let live = range(custom("2026-10-14", "2026-10-16"))
    #expect(live.end == morning && live.includesNow && live.name == "自选 3 天")
    for (text, name) in [("2026-10-16", "今天"), ("2026-10-15", "昨天"), ("2026-10-14", "10月14日"), ("2025-12-01", "2025年12月1日")] {
        let single = range(custom(text, text))
        #expect(single.granularity == .hour && single.name == name, "\(text)")
    }
    let yesterday = range(custom("2026-10-15", "2026-10-15"))
    #expect(yesterday.buckets.count == 24 && yesterday.end == utc("2026-10-15T16:00:00Z") && !yesterday.includesNow)
    #expect(range(custom("2026-10-16", "2026-10-16")).end == morning)
}

@Test func analyticsCustomRangesAreOrderedAndClamped() {
    let reversed = range(custom("2026-10-14", "2026-10-12"))
    #expect(reversed.firstDay == day("2026-10-12") && reversed.lastDay == day("2026-10-14"))
    #expect(reversed.selection == custom("2026-10-12", "2026-10-14"))
    let wide = range(custom("2025-01-01", "2026-12-31"))
    #expect(wide.firstDay == day("2025-10-15") && wide.lastDay == day("2026-10-16") && wide.includesNow)
    #expect(wide.dayCount == 367 && wide.selection == custom("2025-10-15", "2026-10-16"))
}

@Test func analyticsSegmentsShowThePresetOrTheCustomDayCount() {
    #expect(range(.preset(.today)).segment == .today && range(.preset(.today)).segmentTitle == "今天")
    #expect(range(.preset(.last7)).segment == .last7 && range(.preset(.last30)).segmentTitle == "30 天")
    #expect(range(.preset(.lastMonth)).segment == .custom && range(.preset(.lastMonth)).segmentTitle == "上月")
    #expect(range(.preset(.last14)).segmentTitle == "近 14 天" && range(.preset(.thisMonth)).segmentTitle == "本月")
    #expect(range(custom("2026-10-12", "2026-10-14")).segment == .custom)
    #expect(range(custom("2026-10-12", "2026-10-14")).segmentTitle == "自选 3 天")
}

// MARK: Caption and comparison

@Test func analyticsCaptionsFollowTheSpecExamples() {
    #expect(range(.preset(.today)).caption(device: siteDevice) == "10月16日 周五 · 00:00 至 09:41 · 按小时")
    #expect(range(.preset(.last7)).caption(device: siteDevice) == "10月10日 – 16日（今天到 09:41）· 按天")
    #expect(range(.preset(.last30)).caption(device: siteDevice) == "9月17日 – 10月16日（今天到 09:41）· 按天")
    #expect(range(custom("2026-10-15", "2026-10-15")).caption(device: siteDevice) == "10月15日 周四 · 按小时")
    #expect(range(.preset(.lastMonth)).caption(device: siteDevice) == "9月1日 – 30日 · 按天")
    #expect(range(.preset(.thisMonth), now: utc("2026-10-01T01:41:00Z")).caption(device: siteDevice)
            == "10月1日 周四（今天到 09:41）· 按天")
    #expect(range(.preset(.last7), now: utc("2026-01-03T01:41:00Z")).caption(device: siteDevice)
            == "2025年12月28日 – 2026年1月3日（今天到 09:41）· 按天")
    #expect(range(.preset(.today)).caption(device: TimeZone(identifier: "America/New_York")!)
            == "10月16日 周五 · 00:00 至 09:41 · 按小时（站点时间 UTC+8）")
}

@Test func analyticsComparisonWindowsAndLabels() {
    let cases: [(AnalyticsRangeSelection, String, String, String)] = [
        (.preset(.today), "2026-10-14T16:00:00Z", "2026-10-15T01:41:00Z", "比昨天同时"),
        (.preset(.last7), "2026-10-02T16:00:00Z", "2026-10-09T01:41:00Z", "比前 7 天同期"),
        (.preset(.last30), "2026-08-17T16:00:00Z", "2026-09-16T01:41:00Z", "比前 30 天同期"),
        (.preset(.thisMonth), "2026-08-31T16:00:00Z", "2026-09-16T01:41:00Z", "比上月同期"),
        (.preset(.last14), "2026-09-18T16:00:00Z", "2026-10-02T01:41:00Z", "比前 14 天同期"),
        (.preset(.lastMonth), "2026-07-31T16:00:00Z", "2026-08-31T16:00:00Z", "比 8 月"),
        (custom("2026-10-12", "2026-10-14"), "2026-10-08T16:00:00Z", "2026-10-11T16:00:00Z", "比前 3 天"),
        (custom("2026-10-14", "2026-10-16"), "2026-10-10T16:00:00Z", "2026-10-13T01:41:00Z", "比前 3 天同期"),
        (custom("2026-10-15", "2026-10-15"), "2026-10-13T16:00:00Z", "2026-10-14T16:00:00Z", "比前一天"),
        (custom("2026-10-16", "2026-10-16"), "2026-10-14T16:00:00Z", "2026-10-15T01:41:00Z", "比昨天同时")
    ]
    for (selection, start, end, label) in cases {
        #expect(range(selection).comparison == AnalyticsComparison(start: utc(start), end: utc(end), label: label), "\(selection)")
    }
}

@Test func analyticsThisMonthComparisonTakesLastMonthsEndWhenTheDayIsMissing() {
    let march = range(.preset(.thisMonth), now: utc("2026-03-31T01:41:00Z")).comparison
    #expect(march.start == utc("2026-01-31T16:00:00Z") && march.end == utc("2026-02-28T01:41:00Z"))
    #expect(range(.preset(.thisMonth), now: utc("2028-03-31T01:41:00Z")).comparison.end == utc("2028-02-29T01:41:00Z"))
    let january = range(.preset(.lastMonth), now: utc("2027-02-10T01:41:00Z")).comparison
    #expect(january == AnalyticsComparison(start: utc("2026-11-30T16:00:00Z"), end: utc("2026-12-31T16:00:00Z"), label: "比 12 月"))
}

// MARK: Buckets, ticks and slots (40 §1.4, §0.2)

@Test func analyticsHourBucketsCarryBackendKeysAndNames() throws {
    let today = range(.preset(.today)).buckets
    #expect(today.map(\.index) == Array(0..<10))
    #expect(today[0].wireKey == "2026-10-16 00:00" && today[0].axisLabel == "0时")
    let eight = today[8]
    #expect(eight.wireKey == "2026-10-16 08:00" && eight.fullName == "10月16日 8:00–9:00" && eight.shortName == "8:00–9:00")
    #expect(eight.axisLabel == "8时" && eight.spokenLabel == "10月16日 8:00 到 9:00" && !eight.isCurrent)
    #expect(eight.start == utc("2026-10-16T00:00:00Z") && eight.end == utc("2026-10-16T01:00:00Z"))
    let current = today[9]
    #expect(current.isCurrent && current.start == utc("2026-10-16T01:00:00Z") && current.end == morning)
    #expect(current.fullName == "10月16日 9:00–9:41" && current.shortName == "9:00–9:41")
    #expect(current.spokenLabel == "10月16日 9:00 到 9:41")
    let late = try #require(range(custom("2026-10-15", "2026-10-15")).buckets.last)
    #expect(late.fullName == "10月15日 23:00–24:00" && late.shortName == "23:00–24:00" && late.end == utc("2026-10-15T16:00:00Z"))
    #expect(!late.isCurrent && late.wireKey == "2026-10-15 23:00")
}

@Test func analyticsDayBucketsCarryDatesWeekdaysAndSlashLabels() {
    let week = range(.preset(.last7)).buckets
    let wednesday = week[4]
    #expect(wednesday.wireKey == "2026-10-14" && wednesday.fullName == "10月14日 周三" && wednesday.shortName == "14日 周三")
    #expect(wednesday.axisLabel == "10/14" && wednesday.spokenLabel == "10月14日 周三" && !wednesday.isCurrent)
    #expect(wednesday.start == utc("2026-10-13T16:00:00Z") && wednesday.end == utc("2026-10-14T16:00:00Z"))
    #expect(week[6].isCurrent && week[6].end == morning && week[6].shortName == "16日 周五")
    #expect(range(.preset(.lastMonth)).buckets.allSatisfy { !$0.isCurrent })
}

@Test func analyticsAxisTickStrideFollowsTheBucketCount() {
    #expect([1, 8, 9, 12, 13, 24, 25, 31].map(AnalyticsRange.tickStride(count:)) == [1, 1, 3, 3, 6, 6, 7, 7])
}

@Test func analyticsAxisTicksCountDaysBackFromTheLastAndMarkToday() {
    let week = range(.preset(.last7)).axisTicks
    #expect(week.map(\.label) == ["10/10", "10/11", "10/12", "10/13", "10/14", "10/15", "今天"])
    #expect(week.map(\.isNow) == [false, false, false, false, false, false, true])
    let month = range(.preset(.last30)).axisTicks
    #expect(month.map(\.index) == [1, 8, 15, 22, 29] && month.map(\.label) == ["9/18", "9/25", "10/2", "10/9", "今天"])
    let september = range(.preset(.lastMonth)).axisTicks
    #expect(september.map(\.label) == ["9/2", "9/9", "9/16", "9/23", "9/30"] && september.allSatisfy { !$0.isNow })
}

@Test func analyticsAxisTicksCountHoursFromMidnightAndMoveTheLastToNow() {
    #expect(range(.preset(.today)).axisTicks.map(\.label) == ["0时", "3时", "6时", "现在"])
    let later = range(.preset(.today), now: utc("2026-10-16T02:05:00Z")).axisTicks
    #expect(later.map(\.index) == [0, 3, 6, 10] && later.map(\.label) == ["0时", "3时", "6时", "现在"])
    #expect(later.map(\.isNow) == [false, false, false, true])
    #expect(range(custom("2026-10-15", "2026-10-15")).axisTicks.map(\.label) == ["0时", "6时", "12时", "18时"])
}

@Test func analyticsSlotsFillMissingBucketsAndDropForeignRows() {
    let rows = [TrendRow(date: "2026-10-11", value: 1), TrendRow(date: "2026-10-16", value: 2), TrendRow(date: "2026-09-01", value: 9),
                TrendRow(date: "2026-10-16", value: 3)]
    let slots = range(.preset(.last7)).slots(rows, key: \.date)
    #expect(slots.map(\.bucket.wireKey) == ["2026-10-10", "2026-10-11", "2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16"])
    #expect(slots.map { $0.value?.value } == [nil, 1, nil, nil, nil, nil, 3])
    let hours = range(.preset(.today)).slots([TrendRow(date: "2026-10-16 08:00", value: 5)], key: \.date)
    #expect(hours.count == 10 && hours[8].value?.value == 5 && hours.filter { $0.value != nil }.count == 1)
}

// MARK: Site calendar edge cases

@Test func analyticsHoursFollowDaylightSavingInTheSiteZone() {
    let spring = range(custom("2026-03-08", "2026-03-08"), now: utc("2026-03-10T16:00:00Z"), zone: newYork)
    #expect(spring.buckets.count == 23 && spring.start == utc("2026-03-08T05:00:00Z") && spring.end == utc("2026-03-09T04:00:00Z"))
    #expect(spring.buckets[1].shortName == "1:00–3:00" && spring.buckets[1].wireKey == "2026-03-08 01:00")
    #expect(spring.buckets[2].shortName == "3:00–4:00" && spring.buckets[2].wireKey == "2026-03-08 03:00")
    #expect(spring.buckets[2].axisLabel == "3时")
    let fall = range(custom("2026-11-01", "2026-11-01"), now: utc("2026-11-03T17:00:00Z"), zone: newYork)
    #expect(fall.buckets.count == 24 && fall.start == utc("2026-11-01T04:00:00Z") && fall.end == utc("2026-11-02T05:00:00Z"))
    let repeated = fall.buckets[1]
    #expect(repeated.wireKey == "2026-11-01 01:00" && repeated.shortName == "1:00–2:00")
    #expect(repeated.end.timeIntervalSince(repeated.start) == 7_200)
    #expect(fall.buckets[23].shortName == "23:00–24:00")
    let week = range(.preset(.last7), now: utc("2026-03-10T16:00:00Z"), zone: newYork)
    #expect(week.buckets[4].start == utc("2026-03-08T05:00:00Z") && week.buckets[5].start == utc("2026-03-09T04:00:00Z"))
    #expect(week.buckets[4].end == week.buckets[5].start)
    let comparison = range(.preset(.today), now: utc("2026-11-02T14:30:00Z"), zone: newYork).comparison
    #expect(comparison.start == utc("2026-11-01T04:00:00Z") && comparison.end == utc("2026-11-01T14:30:00Z"))
}

@Test func analyticsRangeAtMidnightStillEndsAfterItStarts() {
    let midnight = utc("2026-10-15T16:00:00Z")
    let today = range(.preset(.today), now: midnight)
    #expect(today.start == midnight && today.end == midnight.addingTimeInterval(1) && today.buckets.count == 1)
    #expect(today.comparison.start == utc("2026-10-14T16:00:00Z") && today.comparison.end == utc("2026-10-14T16:00:01Z"))
}

// MARK: Custom range sheet

@Test func analyticsCustomDraftOpensOnThisMonthAndDescribesBothEnds() {
    let draft = AnalyticsCustomDraft(range: range(.preset(.today)))
    #expect(draft.from == day("2026-10-01") && draft.to == day("2026-10-16") && draft.dayCount == 16)
    #expect(draft.matchedShortcut == .thisMonth && draft.selection == .preset(.thisMonth))
    #expect(draft.startLine == "10月1日 周四 00:00" && draft.endLine == "10月16日 周五 现在（09:41）")
    #expect(draft.footnote == "共 16 天，按天统计（只选一天按小时）；按站点时区计算。")
    #expect(draft.bounds == AnalyticsDayBounds(now: morning, zone: shanghai))
    let reopened = AnalyticsCustomDraft(range: range(custom("2026-10-12", "2026-10-14")))
    #expect(reopened.from == day("2026-10-12") && reopened.to == day("2026-10-14") && reopened.matchedShortcut == nil)
    #expect(reopened.selection == custom("2026-10-12", "2026-10-14") && reopened.endLine == "10月14日 周三 24:00")
    let shortcut = AnalyticsCustomDraft(range: range(.preset(.lastMonth)))
    #expect(shortcut.from == day("2026-09-01") && shortcut.to == day("2026-09-30") && shortcut.matchedShortcut == .lastMonth)
}

@Test func analyticsCustomDraftAlignsClampsAndMatchesShortcuts() {
    let draft = AnalyticsCustomDraft(range: range(.preset(.last7)))
    let shorter = draft.settingTo(day("2026-10-05"))
    #expect(shorter.from == day("2026-10-01") && shorter.to == day("2026-10-05") && shorter.matchedShortcut == nil)
    #expect(shorter.endLine == "10月5日 周一 24:00" && shorter.selection == custom("2026-10-01", "2026-10-05"))
    let pushed = shorter.settingFrom(day("2026-10-08"))
    #expect(pushed.from == day("2026-10-08") && pushed.to == day("2026-10-08"))
    let pulled = draft.settingTo(day("2025-01-01"))
    #expect(pulled.from == day("2025-10-15") && pulled.to == day("2025-10-15"))
    let future = draft.settingFrom(day("2026-10-20"))
    #expect(future.from == day("2026-10-16") && future.to == day("2026-10-16"))
    #expect(future.matchedShortcut == nil && future.selection == custom("2026-10-16", "2026-10-16"))
    #expect(draft.settingFrom(day("2026-10-03")).matchedShortcut == .last14)
    let lastMonth = draft.applying(.lastMonth)
    #expect(lastMonth.from == day("2026-09-01") && lastMonth.to == day("2026-09-30") && lastMonth.selection == .preset(.lastMonth))
    #expect(lastMonth.endLine == "9月30日 周三 24:00" && lastMonth.dayCount == 30)
    #expect(draft.applying(.last14).matchedShortcut == .last14)
    let firstDay = AnalyticsCustomDraft(range: range(.preset(.today), now: utc("2026-10-01T01:41:00Z")))
    #expect(firstDay.from == firstDay.to && firstDay.matchedShortcut == nil && firstDay.selection == custom("2026-10-01", "2026-10-01"))
}

@Test func analyticsCustomDraftKeepsThePickedShortcutWhenThisMonthIsTheLast14Days() {
    // On the 14th 本月 and 近 14 天 both cover 10月1日–14日, but they compare with different windows.
    let fourteenth = utc("2026-10-14T01:41:00Z")
    let draft = AnalyticsCustomDraft(range: range(.preset(.today), now: fourteenth))
    #expect(draft.from == day("2026-10-01") && draft.to == day("2026-10-14") && draft.matchedShortcut == .thisMonth)
    let last14 = draft.applying(.last14)
    #expect(last14.from == day("2026-10-01") && last14.to == day("2026-10-14"))
    #expect(last14.matchedShortcut == .last14 && last14.selection == .preset(.last14))
    #expect(last14.settingFrom(day("2026-10-01")).selection == .preset(.last14))
    #expect(last14.settingFrom(day("2026-10-03")).matchedShortcut == nil)
    #expect(last14.applying(.thisMonth).selection == .preset(.thisMonth))
    #expect(AnalyticsCustomDraft(range: range(.preset(.last14), now: fourteenth)).matchedShortcut == .last14)
    #expect(AnalyticsCustomDraft(range: range(.preset(.thisMonth), now: fourteenth)).matchedShortcut == .thisMonth)
}
