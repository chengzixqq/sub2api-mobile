import Foundation
import Testing
@testable import Sub2Core

private func amount(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private func instant(_ raw: String) throws -> Date {
    guard let date = ServerTime.parseTimestamp(raw) else { throw CocoaError(.formatting) }
    return date
}

@Test func moneyUsesGroupingFixedDigitsAndUnicodeMinus() {
    let cases: [(String, Int, String)] = [
        ("1284.5", 2, "$1,284.50"), ("0.0124", 4, "$0.0124"), ("1.3", 2, "$1.30"), ("0.0123", 4, "$0.0123"), ("0.012", 3, "$0.012"),
        ("-12.5", 2, "\u{2212}$12.50"), ("-0.004", 2, "$0.00"), ("0", 2, "$0.00"), ("0.005", 2, "$0.01"), ("1.005", 2, "$1.01"),
        ("-1.005", 2, "\u{2212}$1.01"), ("999.995", 2, "$1,000.00"), ("-1234567.891", 2, "\u{2212}$1,234,567.89"),
        ("12345678901234567890.125", 2, "$12,345,678,901,234,567,890.13")
    ]
    for (raw, digits, expected) in cases {
        let value = amount(raw)
        let text = DisplayFormat.money(value, digits: digits)
        #expect(text == expected, "\(raw)")
        #expect(!text.contains("-") && !text.hasPrefix("+"), "\(raw)")
        #expect(value == amount(raw))
    }
}

@Test func moneySmallShowsBelowOneCentOnlyForPositiveTinyValues() {
    #expect(DisplayFormat.money(amount("0.004"), small: true) == "< $0.01")
    #expect(DisplayFormat.money(amount("0.0099"), small: true) == "< $0.01")
    #expect(DisplayFormat.money(0, small: true) == "$0.00")
    #expect(DisplayFormat.money(amount("-0.004"), small: true) == "$0.00")
    #expect(DisplayFormat.money(amount("0.01"), small: true) == "$0.01")
    #expect(DisplayFormat.money(amount("0.004")) == "$0.00")
    #expect(DisplayFormat.money(nil) == "—")
    #expect(DisplayFormat.money(.nan) == "—")
}

@Test(arguments: [
    ("45080", "$45.08K"), ("45085", "$45.09K"), ("1284.5", "$1.28K"), ("1000", "$1.00K"), ("1234.56", "$1.23K"),
    ("12.34", "$12.34"), ("999.994", "$999.99"), ("999.994999999999999999999999", "$999.99"), ("999.995", "$1.00K"),
    ("-45085", "\u{2212}$45.09K"), ("1005000", "$1,005.00K"), ("999999.99999999999999999999", "$1,000.00K"),
    ("1000000000", "$1,000,000.00K"), ("-0.004", "$0.00"), ("12345678901234567890.125", "$12,345,678,901,234,567.89K")
])
func moneyCompactUsesThousandsUnitWithTwoDigits(raw: String, expected: String) {
    let value = amount(raw)
    #expect(DisplayFormat.moneyCompact(value) == expected)
    #expect(value == amount(raw))
}

@Test func moneyCompactKeepsMissingValues() {
    #expect(DisplayFormat.moneyCompact(nil) == "—")
    #expect(DisplayFormat.moneyCompact(.nan) == "—")
}

@Test(arguments: [
    ("0.0124", "$0.0124"), ("0.35", "$0.3500"), ("0.12", "$0.1200"), ("1.3", "$1.30"), ("0.99995", "$1.00"),
    ("0", "$0.00"), ("0.00004", "$0.00"), ("-0.35", "\u{2212}$0.3500"), ("-1.3", "\u{2212}$1.30"), ("1234.5", "$1,234.50")
])
func moneyLineItemUsesFourDigitsBelowOneDollar(raw: String, expected: String) {
    #expect(DisplayFormat.moneyLineItem(amount(raw)) == expected)
}

@Test func moneyExactEchoesEnteredAmountWithoutRounding() {
    #expect(DisplayFormat.moneyExact(amount("12.5")) == "$12.50")
    #expect(DisplayFormat.moneyExact(amount("20")) == "$20.00")
    #expect(DisplayFormat.moneyExact(amount("0.12345678")) == "$0.12345678")
    #expect(DisplayFormat.moneyExact(amount("0.005")) == "$0.005")
    #expect(DisplayFormat.moneyExact(amount("1234.5")) == "$1,234.50")
    #expect(DisplayFormat.moneyExact(amount("-3")) == "\u{2212}$3.00")
    #expect(DisplayFormat.moneyExact(0) == "$0.00")
    #expect(DisplayFormat.moneyLineItem(nil) == "—")
    #expect(DisplayFormat.moneyExact(nil) == "—")
}

@Test(arguments: [
    (0, "0"), (999, "999"), (1_284, "1,284"), (1_000_000, "1,000,000"), (9_007_199_254_740_993, "9,007,199,254,740,993"),
    (-1_284, "\u{2212}1,284"), (Int.min, "\u{2212}9,223,372,036,854,775,808"), (Int.max, "9,223,372,036,854,775,807")
])
func groupedInsertsThousandsSeparatorsExactly(value: Int, expected: String) {
    #expect(DisplayFormat.grouped(value) == expected)
}

@Test(arguments: [
    (0, "0"), (999, "999"), (1_000, "1K"), (1_050, "1.1K"), (18_204, "18.2K"), (240_000, "240K"), (999_949, "999.9K"),
    (999_950, "1M"), (1_000_000, "1M"), (1_234_567, "1.2M"), (96_400_000, "96.4M"), (9_876_543_210, "9.9B"),
    (1_000_000_000_000, "1000B"), (-1_500, "\u{2212}1.5K")
])
func compactUsesOneDecimalAndDropsTrailingZero(value: Int, expected: String) {
    #expect(DisplayFormat.compact(value) == expected)
}

@Test func compactRoundsFractionsBelowOneThousandAndRejectsMissing() {
    #expect(DisplayFormat.compact(22.5) == "23")
    #expect(DisplayFormat.compact(0.4) == "0")
    #expect(DisplayFormat.compact(999.6) == "1K")
    #expect(DisplayFormat.compact(987_654.0) == "987.7K")
    #expect(DisplayFormat.compact(1.0e20) == "100000000000B")
    #expect(DisplayFormat.compact(Double.nan) == "—")
    #expect(DisplayFormat.compact(Double.infinity) == "—")
    #expect(DisplayFormat.compact(Double?.none) == "—")
    #expect(DisplayFormat.compact(Int?.none) == "—")
    #expect(DisplayFormat.grouped(nil) == "—")
}

@Test(arguments: [
    (0.0, "0"), (0.4, "0.4"), (0.04, "0.0"), (2.0, "2.0"), (9.94, "9.9"), (9.96, "10"), (10.0, "10"), (46.4, "46"),
    (46.5, "47"), (1_234.0, "1,234")
])
func rpmKeepsOneDecimalOnlyBelowTen(value: Double, expected: String) {
    #expect(DisplayFormat.rpm(value) == expected)
}

@Test func rpmRejectsMissingNegativeAndNonFinite() {
    for value in [Double?.none, -1, .nan, .infinity] { #expect(DisplayFormat.rpm(value) == "—") }
}

@Test(arguments: [
    (0.0086, "0.9%"), (0.992, "99.2%"), (0.008, "0.8%"), (0.017, "1.7%"), (0.0045, "0.5%"), (0.01, "1.0%"),
    (0.0, "0.0%"), (1.0, "100.0%")
])
func ratioPercentMultipliesByHundredWithOneDecimal(value: Double, expected: String) {
    #expect(DisplayFormat.ratioPercent(value) == expected)
}

@Test func percentAndChangeDoNotMultiplyAndUseArrows() {
    #expect(DisplayFormat.ratioPercent(nil) == "—")
    #expect(DisplayFormat.percent(5.2) == "5.2%")
    #expect(DisplayFormat.percent(38.5) == "38.5%")
    #expect(DisplayFormat.percent(12.34) == "12.3%")
    #expect(DisplayFormat.percent(5) == "5.0%")
    #expect(DisplayFormat.percent(1_234.5) == "1,234.5%")
    #expect(DisplayFormat.percent(nil) == "—")
    let changes: [(Double?, String)] = [
        (0.123, "↑ 12.3%"), (-0.032, "↓ 3.2%"), (1.5, "↑ 150.0%"), (0.0004, "0.0%"), (-0.0004, "0.0%"), (0, "0.0%"),
        (nil, "—"), (.infinity, "—"), (.nan, "—")
    ]
    for (ratio, expected) in changes {
        let text = DisplayFormat.change(ratio)
        #expect(text == expected, "\(String(describing: ratio))")
        #expect(!text.contains("+") && !text.contains("-"))
    }
}

@Test func decimalTrimsTrailingZerosAndGroups() {
    #expect(DisplayFormat.decimal(1.25, maxFractionDigits: 2) == "1.25")
    #expect(DisplayFormat.decimal(2.5, maxFractionDigits: 2) == "2.5")
    #expect(DisplayFormat.decimal(4, maxFractionDigits: 2) == "4")
    #expect(DisplayFormat.decimal(0.2, maxFractionDigits: 2) == "0.2")
    #expect(DisplayFormat.decimal(1_234.567, maxFractionDigits: 2) == "1,234.57")
    #expect(DisplayFormat.decimal(-1.5, maxFractionDigits: 2) == "\u{2212}1.5")
    #expect(DisplayFormat.decimal(-0.001, maxFractionDigits: 2) == "0")
    #expect(DisplayFormat.decimal(0.5, maxFractionDigits: 1) == "0.5")
    #expect(DisplayFormat.decimal(5, minFractionDigits: 2, maxFractionDigits: 2) == "5.00")
    #expect(DisplayFormat.decimal(5.2, minFractionDigits: 2, maxFractionDigits: 2) == "5.20")
    #expect(DisplayFormat.decimal(5.256, minFractionDigits: 1, maxFractionDigits: 2) == "5.26")
    #expect(DisplayFormat.decimal(5, minFractionDigits: 1, maxFractionDigits: 2) == "5.0")
    #expect(DisplayFormat.decimal(nil, maxFractionDigits: 2) == "—")
    #expect(DisplayFormat.decimal(.nan, maxFractionDigits: 2) == "—")
}

@Test(arguments: [
    (600.0, "0.6s"), (42_100.0, "42.1s"), (182_000.0, "182s"), (99_940.0, "99.9s"), (99_960.0, "100s"),
    (1_250.0, "1.3s"), (0.0, "0.0s"), (3_600_000.0, "3,600s")
])
func durationListUsesSecondsWithOneDecimal(milliseconds: Double, expected: String) {
    #expect(DisplayFormat.duration(milliseconds, style: .list) == expected)
}

@Test(arguments: [
    (820.0, "820ms"), (820.4, "820ms"), (999.4, "999ms"), (999.6, "1.0s"), (2_400.0, "2.4s"), (9_960.0, "10s"),
    (42_000.0, "42s"), (0.0, "0ms")
])
func durationPercentileSwitchesAtOneAndTenSeconds(milliseconds: Double, expected: String) {
    #expect(DisplayFormat.duration(milliseconds, style: .percentile) == expected)
}

@Test func durationMillisReadingsUseIntegerMilliseconds() {
    #expect(DisplayFormat.duration(182.0, style: .millis) == "182ms")
    #expect(DisplayFormat.duration(850.0, style: .millis) == "850ms")
    #expect(DisplayFormat.duration(2_000.0, style: .millis) == "2.0s")
    #expect(DisplayFormat.duration(12_345.0, style: .millis) == "12s")
    #expect(DisplayFormat.duration(182, style: .millis) == "182ms")
    #expect(DisplayFormat.duration(1_250, style: .list) == "1.3s")
}

@Test func durationRejectsMissingNegativeAndNonFinite() {
    for style in [DisplayFormat.DurationStyle.list, .percentile, .millis] {
        #expect(DisplayFormat.duration(Double?.none, style: style) == "—")
        #expect(DisplayFormat.duration(Int?.none, style: style) == "—")
        #expect(DisplayFormat.duration(-1, style: style) == "—")
        #expect(DisplayFormat.duration(Double.nan, style: style) == "—")
        #expect(DisplayFormat.duration(Double.infinity, style: style) == "—")
    }
}

@Test func relativeTimeUsesGivenTimeZoneForDayBoundaries() throws {
    let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let utc = try #require(TimeZone(identifier: "UTC"))
    let now = try instant("2026-10-16T01:41:00Z") // 09:41 in Shanghai
    let yesterdayNight = try instant("2026-10-15T14:10:00Z")
    let earlier = try instant("2026-10-14T06:20:00Z")
    let lateUTCEvening = try instant("2026-10-15T23:30:00Z")
    func text(_ date: Date?, in zone: TimeZone? = nil) -> String {
        DisplayFormat.relativeTime(date, now: now, timeZone: zone ?? shanghai)
    }
    #expect(text(now.addingTimeInterval(-30)) == "刚刚")
    #expect(text(now.addingTimeInterval(30)) == "刚刚")
    #expect(text(now.addingTimeInterval(-60)) == "1 分钟前")
    #expect(text(now.addingTimeInterval(-720)) == "12 分钟前")
    #expect(text(now.addingTimeInterval(-3_599)) == "59 分钟前")
    #expect(text(now.addingTimeInterval(-3_660)) == "今天 08:40")
    #expect(text(now.addingTimeInterval(7_200)) == "今天 11:41")
    #expect(text(yesterdayNight) == "昨天 22:10")
    #expect(text(earlier) == "10月14日 14:20")
    #expect(text(lateUTCEvening) == "今天 07:30")
    #expect(text(lateUTCEvening, in: utc) == "昨天 23:30")
    #expect(text(nil) == "—")
}

@Test func clockUsesGivenTimeZone() throws {
    let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let utc = try #require(TimeZone(identifier: "UTC"))
    let date = try instant("2026-10-16T02:04:00Z")
    #expect(DisplayFormat.clock(date, timeZone: shanghai) == "10:04")
    #expect(DisplayFormat.clock(date, timeZone: utc) == "02:04")
    #expect(DisplayFormat.clock(nil, timeZone: utc) == "—")
}

@Test func countdownRecomputesFromAbsoluteTime() throws {
    let cases: [(TimeInterval?, String)] = [
        (277, "4:37"), (59.2, "1:00"), (0, "0:00"), (-5, "0:00"), (3_600, "1:00:00"), (3_725, "1:02:05"),
        (nil, "—"), (.infinity, "—"), (.nan, "—")
    ]
    for (seconds, expected) in cases { #expect(DisplayFormat.countdown(seconds) == expected, "\(String(describing: seconds))") }
    let now = try instant("2026-10-16T02:04:00Z")
    #expect(DisplayFormat.countdown(until: now.addingTimeInterval(277), now: now) == "4:37")
    #expect(DisplayFormat.countdown(until: now.addingTimeInterval(-10), now: now) == "0:00")
    #expect(DisplayFormat.countdown(until: nil, now: now) == "—")
}

@Test func minutesLeftRoundsUpToWholeMinutes() {
    let cases: [(TimeInterval?, String)] = [
        (720, "12 分钟"), (721, "13 分钟"), (30, "1 分钟"), (0, "1 分钟"), (3_540, "59 分钟"), (3_600, "1 小时"),
        (3_900, "1 小时 5 分钟"), (7_200, "2 小时"), (nil, "—"), (.nan, "—")
    ]
    for (seconds, expected) in cases { #expect(DisplayFormat.minutesLeft(seconds) == expected, "\(String(describing: seconds))") }
}

@Test func zeroIsNotMissing() {
    #expect(DisplayFormat.missing == "—")
    let zeros = [
        DisplayFormat.money(0), DisplayFormat.moneyCompact(0), DisplayFormat.moneyLineItem(0), DisplayFormat.grouped(0),
        DisplayFormat.compact(0), DisplayFormat.rpm(0), DisplayFormat.ratioPercent(0), DisplayFormat.percent(0),
        DisplayFormat.duration(0, style: .millis), DisplayFormat.decimal(0, maxFractionDigits: 2)
    ]
    #expect(zeros == ["$0.00", "$0.00", "$0.00", "0", "0", "0", "0.0%", "0.0%", "0ms", "0"])
    #expect(!zeros.contains(DisplayFormat.missing))
}
