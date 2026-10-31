import Foundation
import Testing
@testable import Sub2Core

// 10 §1.3.4 每小时实际扣费 (S1-09b).

private let shanghai = HomeTestData.shanghai
/// 13:30 in Shanghai, 22:30 the day before in Los Angeles.
private let now = ServerTime.parseTimestamp("2026-10-16T05:30:00Z")!
private func decimal(_ raw: String) -> Decimal { HomeTestData.decimal(raw) }
private func point(_ date: String, _ cost: String) -> HomeHourlyPoint { HomeHourlyPoint(date: date, actualCost: decimal(cost)) }
private func series(today: [HomeHourlyPoint] = [], yesterday: [HomeHourlyPoint] = [], at time: Date = now,
                    in zone: TimeZone = shanghai) -> HomeHourlySeries {
    HomeHourlySeries(HomeHourly(today: today, yesterday: yesterday), now: time, timeZone: zone)
}

@Test func yesterdayHasTwentyFourHoursWithMissingHoursAsZero() {
    let value = series(yesterday: [point("2026-10-15 03:00", "1.25"), point("2026-10-15 17:00", "0.40")])
    #expect(value.yesterday.map(\.hour) == Array(0...23))
    #expect(value.yesterday[3].actualCost == decimal("1.25"))
    #expect(value.yesterday[17].actualCost == decimal("0.40"))
    #expect(value.yesterday.filter { ![3, 17].contains($0.hour) }.allSatisfy { $0.actualCost == 0 })
}

@Test func todayEndsAtTheCurrentServerHour() {
    let inShanghai = series(today: [point("2026-10-16 02:00", "3")])
    #expect(inShanghai.currentHour == 13)
    #expect(inShanghai.today.map(\.hour) == Array(0...13))
    #expect(inShanghai.today[2].actualCost == 3)
    // The same instant on a server in Los Angeles: the phone's zone never counts.
    let inLosAngeles = series(in: TimeZone(identifier: "America/Los_Angeles")!)
    #expect(inLosAngeles.currentHour == 22)
    #expect(inLosAngeles.today.map(\.hour) == Array(0...22))
}

@Test func todayExtendsToTheLatestReportedHourWhenTheClockLags() {
    let value = series(today: [point("2026-10-16 14:00", "2.50")])
    #expect(value.currentHour == 14)
    #expect(value.today.count == 15)
    #expect(value.today.last?.actualCost == decimal("2.50"))
}

@Test func onlyTheCurrentHourBarIsHighlighted() {
    let value = series(today: [point("2026-10-16 13:00", "1"), point("2026-10-16 12:00", "2")], yesterday: [point("2026-10-15 13:00", "1")])
    #expect(value.today.filter(\.isCurrent).map(\.hour) == [13])
    #expect(value.yesterday.allSatisfy { !$0.isCurrent })
}

@Test func repeatedHourLabelsAddUpAndMalformedLabelsAreIgnored() {
    let value = series(today: [point("2026-10-16 01:00", "0.30"), point("2026-10-16 01:00", "0.20"), point("2026-10-16 1:00", "9"),
                               point("2026-10-16 01:30", "9"), point("bad", "9"), point("", "9"), point("2026-10-16", "9")])
    #expect(value.today[1].actualCost == decimal("0.50"))
    #expect(value.today.filter { $0.hour != 1 }.allSatisfy { $0.actualCost == 0 })
    #expect(value.currentHour == 13)
}

@Test func missingActualCostCountsAsZeroAndPlotValueKeepsDecimal() throws {
    let wire = #"{"today":[{"date":"2026-10-16 04:00"},{"date":"2026-10-16 05:00","actual_cost":"0.10000001"}]}"#
    let hourly = try JSONDecoder().decode(HomeHourly.self, from: Data(wire.utf8))
    let value = HomeHourlySeries(hourly, now: now, timeZone: shanghai)
    #expect(value.today[4].actualCost == 0)
    #expect(value.today[5].actualCost == decimal("0.10000001"))
    #expect(abs(value.today[5].plotValue - 0.10000001) < 1e-12)
}

@Test func axisShowsFixedHoursAndNowWithoutCollisions() {
    func labels(at hour: Int) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let time = calendar.date(bySettingHour: hour, minute: 20, second: 0, of: now)!
        return series(at: time).axisLabels.map { $0.isNow ? "现在@\($0.hour)" : $0.text }
    }
    #expect(labels(at: 3) == ["0时", "6时", "12时", "18时", "现在@3"])
    #expect(labels(at: 13) == ["0时", "6时", "18时", "现在@13"])
    #expect(labels(at: 0) == ["6时", "12时", "18时", "现在@0"])
    // A fixed label runs right from its hour: two hours after it is still too close, two hours before it is not.
    #expect(labels(at: 2) == ["6时", "12时", "18时", "现在@2"])
    #expect(labels(at: 14) == ["0时", "6时", "18时", "现在@14"])
    #expect(labels(at: 4) == ["0时", "6时", "12时", "18时", "现在@4"])
    #expect(labels(at: 5) == ["0时", "12时", "18时", "现在@5"])
    #expect(labels(at: 23) == ["0时", "6时", "12时", "18时", "现在@23"])
    #expect(HomeHourlySeries.fixedTicks == [0, 6, 12, 18])
    #expect(series().axisLabels.filter(\.isNow).map(\.text) == ["现在"])
}

@Test func upperBoundLeavesHeadroomAndNeverCollapses() {
    let value = series(today: [point("2026-10-16 03:00", "2.0")], yesterday: [point("2026-10-15 09:00", "2.5")])
    #expect(abs(value.upperBound - 2.8) < 1e-9)
    #expect(series().upperBound == 1)
    #expect(series(today: [point("2026-10-16 03:00", "0")]).upperBound == 1)
}
