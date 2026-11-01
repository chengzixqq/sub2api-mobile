import Foundation
import Testing
@testable import Sub2Core

// 40 §1.4 / §1.5: the money bars of the analytics cards and the whole-chart selection (S4-13).

private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
/// 2026-10-16 09:41 in Shanghai, a Friday: today has 10 hourly buckets, the last one running.
private let morning = utc("2026-10-16T01:41:00Z")
private let today = AnalyticsRange.resolve(.preset(.today), now: morning, zone: shanghai)
private let week = AnalyticsRange.resolve(.preset(.last7), now: morning, zone: shanghai)
private let pastWeek = AnalyticsRange.resolve(.custom(from: AnalyticsDay("2026-10-05")!, to: AnalyticsDay("2026-10-11")!), now: morning, zone: shanghai)

private func series(_ range: AnalyticsRange, _ values: [Decimal?], line: [Decimal?]? = nil, isEmpty: Bool? = nil) -> AnalyticsBarSeries {
    AnalyticsBarSeries(range: range, values: values, line: line, metricName: "实际扣费", isEmpty: isEmpty)
}

@Test func missingBucketsAreZeroAndMissingAmountsStayMissing() {
    var values: [Decimal?] = (1...10).map { Decimal($0) }
    values[2] = 0
    values[4] = nil
    let bars = series(today, values, line: (1...10).map { Decimal($0 * 2) }).bars
    #expect(today.buckets.count == 10)
    #expect(bars.map(\.bucket) == today.buckets)
    #expect(bars[2].value == 0 && bars[2].plotValue == 0)
    #expect(bars[4].value == nil && bars[4].plotValue == 0)
    #expect(bars[9].plotValue == 10)
    #expect(bars.map(\.plotLine) == (1...10).map { Double($0 * 2) })
    #expect(bars.map(\.id) == Array(0..<10))
    // Shorter lists read as missing; no line at all draws none.
    let short = series(today, [1]).bars
    #expect(short.count == 10 && short[0].value == 1 && short[1].value == nil && short[0].plotLine == nil)
}

@Test func spokenLabelReadsBucketThenMetricAndAmount() {
    var hourly = [Decimal?](repeating: 0, count: 10)
    hourly[9] = 229
    hourly[3] = nil
    let todaySeries = series(today, hourly)
    #expect(todaySeries.spokenLabel(9) == "10月16日 9:00 到 9:41，实际扣费 $229.00")
    #expect(todaySeries.spokenLabel(3) == "10月16日 3:00 到 4:00，实际扣费 无数据")
    var daily = [Decimal?](repeating: 0, count: 7)
    daily[4] = Decimal(string: "1201.76")
    #expect(series(week, daily).spokenLabel(4) == "10月14日 周三，实际扣费 $1,201.76")
    let profit = AnalyticsBarSeries(range: week, values: [-12.3], metricName: "利润")
    #expect(profit.spokenLabel(0) == "10月10日 周六，利润 \u{2212}$12.30")
    #expect(profit.metricName == "利润")
}

@Test func emptyWhenEveryValueIsZeroUnlessTheCallerSays() {
    let zeros = series(week, [Decimal?](repeating: 0, count: 7))
    #expect(zeros.isEmpty)
    #expect(series(week, [nil, 0, nil]).isEmpty)
    #expect(!series(week, [0, 0, 3]).isEmpty)
    // 利润明细 decides by the actual charge: a range all at a loss is not empty, a range with no charge is.
    let kept = series(week, [Decimal?](repeating: 0, count: 7), isEmpty: false)
    #expect(!kept.isEmpty)
    #expect(series(week, [-5, -2], isEmpty: true).isEmpty)
}

@Test func yDomainHoldsZeroAndRoomForNegativeBars() {
    #expect(series(week, [10, 20], line: [25]).yDomain == 0...27.5)
    #expect(series(week, [-5, 10]).yDomain == -5.5...11)
    #expect(series(week, [-5, -2]).yDomain == -5.5...0)
    let zeros = series(week, [Decimal?](repeating: 0, count: 7))
    #expect(zeros.yDomain == 0...1)
    #expect(series(week, []).yDomain == 0...1)
}

@Test func emphasisGoesToTheSelectionElseTheRunningBucket() {
    let running = series(today, [])
    #expect((0..<10).filter { running.isEmphasized($0, selected: nil) } == [9])
    #expect((0..<10).filter { running.isEmphasized($0, selected: 2) } == [2])
    // A selection past the bars counts as none.
    #expect((0..<10).filter { running.isEmphasized($0, selected: 42) } == [9])
    let past = series(pastWeek, [])
    #expect((0..<7).filter { past.isEmphasized($0, selected: nil) }.isEmpty)
    #expect((0..<7).filter { past.isEmphasized($0, selected: 6) } == [6])
}

@Test func bucketIndexAtXRoundsAndClamps() {
    let running = series(today, [])
    #expect(running.bucketIndex(atX: 1.4) == 1)
    #expect(running.bucketIndex(atX: 1.6) == 2)
    #expect(running.bucketIndex(atX: -3) == 0)
    #expect(running.bucketIndex(atX: 99) == 9)
    #expect(running.bucketIndex(atX: .nan) == nil)
    #expect(running.bucketIndex(atX: .infinity) == nil)
}

@Test func ticksAreTheRangeTicks() {
    #expect(series(today, []).ticks == today.axisTicks)
    #expect(series(week, []).ticks == week.axisTicks)
    #expect(series(today, []).ticks.last == AnalyticsAxisTick(index: 9, label: "现在", isNow: true))
    #expect(series(week, []).ticks.last == AnalyticsAxisTick(index: 6, label: "今天", isNow: true))
}

// MARK: 整图点选

@Test func pressSelectsAndReleaseKeepsIt() {
    let pressed = AnalyticsChartSelection().receiving(2)
    #expect(pressed.selected == 2)
    #expect(pressed.receiving(nil).selected == 2)
    #expect(pressed.receiving(nil) == AnalyticsChartSelection(selected: 2))
    #expect(AnalyticsChartSelection().receiving(nil).selected == nil)
}

@Test func pressOnTheSelectedBucketClearsOnRelease() {
    let pressed = AnalyticsChartSelection(selected: 2).receiving(2)
    #expect(pressed.selected == 2)
    let moved = pressed.receiving(2)
    #expect(moved.selected == 2)
    #expect(moved.receiving(nil).selected == nil)
    // Pressing another bucket moves the selection there and keeps it.
    #expect(AnalyticsChartSelection(selected: 2).receiving(5).receiving(nil).selected == 5)
}

@Test func dragFromTheSelectedBucketMovesInsteadOfClearing() {
    let dragged = AnalyticsChartSelection(selected: 2).receiving(2).receiving(4)
    #expect(dragged.selected == 4)
    let released = dragged.receiving(nil)
    #expect(released.selected == 4)
    // Back onto the selected bucket during the same drag does not clear either.
    #expect(AnalyticsChartSelection(selected: 2).receiving(2).receiving(4).receiving(2).receiving(nil).selected == 2)
    #expect(released.receiving(4).receiving(nil).selected == nil)
}
