import Foundation
import Testing
@testable import Sub2Core

private let originalOverview = #"{"today_requests":12,"today_tokens":340,"today_cost":"99.99","total_users":8,"total_accounts":3,"error_accounts":1,"rpm":2.5,"tpm":22.5}"#

private func overview(adding fields: String = "") throws -> DashboardStats {
    let json = fields.isEmpty ? originalOverview : String(originalOverview.dropLast()) + "," + fields + "}"
    return try JSONDecoder().decode(DashboardStats.self, from: Data(json.utf8))
}

@Test func overviewPreservesDistinctDecimalCostsAndFullTokenAggregate() throws {
    let stats = try overview(adding: #""today_actual_cost":"0.12345678","today_account_cost":0.00000001,"total_actual_cost":"12.34567890","total_account_cost":"4.56789123","total_tokens":9876543210,"average_duration_ms":1250.25"#)
    #expect(stats.todayCost == Decimal(string: "99.99"))
    #expect(stats.todayActualCost == Decimal(string: "0.12345678"))
    #expect(stats.todayAccountCost == Decimal(string: "0.00000001"))
    #expect(stats.totalActualCost == Decimal(string: "12.34567890"))
    #expect(stats.totalAccountCost == Decimal(string: "4.56789123"))
    #expect(stats.totalTokens == 9_876_543_210)
    #expect(stats.averageDurationMs == 1250.25)
}

@Test func missingOverviewCostsRemainUnavailableInsteadOfUsingStandardCost() throws {
    let missing = try overview()
    let null = try overview(adding: #""today_actual_cost":null,"today_account_cost":null,"total_actual_cost":null,"total_account_cost":null,"total_tokens":null,"average_duration_ms":null"#)
    for stats in [missing, null] {
        #expect(stats.todayCost == Decimal(string: "99.99"))
        #expect(stats.todayActualCost == nil); #expect(stats.todayAccountCost == nil)
        #expect(stats.totalActualCost == nil); #expect(stats.totalAccountCost == nil)
        #expect(stats.totalTokens == nil); #expect(stats.averageDurationMs == nil)
        #expect(DisplayFormat.money(stats.todayActualCost) == "—")
        #expect(DisplayFormat.moneyCompact(stats.todayAccountCost) == "—")
        #expect(DisplayFormat.compact(stats.totalTokens) == "—")
        #expect(DisplayFormat.duration(stats.averageDurationMs, style: .list) == "—")
    }
    #expect(throws: (any Error).self) { try overview(adding: #""today_actual_cost":"invalid""#) }
}

@Test func overviewTotalRequestsPreservesExactIntegerAndOptionalCompatibility() throws {
    let stats = try overview(adding: #""total_requests":9007199254740993"#)
    #expect(stats.totalRequests == 9_007_199_254_740_993)
    let roundTrip = try JSONDecoder().decode(DashboardStats.self, from: JSONEncoder().encode(stats))
    #expect(roundTrip.totalRequests == stats.totalRequests)
    #expect(try overview().totalRequests == nil)
    #expect(try overview(adding: #""total_requests":null"#).totalRequests == nil)
    #expect(throws: (any Error).self) { try overview(adding: #""total_requests":"invalid""#) }
}

@Test func overviewTrendDatesKeepDayHourAndRequestedTimezone() throws {
    let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let first = try #require(DashboardPresentation.trendDate("2026-10-14 22:00", timeZone: shanghai))
    let second = try #require(DashboardPresentation.trendDate("2026-10-15 00:00", timeZone: shanghai))
    #expect(second.timeIntervalSince(first) == 7_200)
    #expect(DashboardPresentation.trendAxisLabel(first, hourly: true, timeZone: shanghai) == "10/14 22:00")
    #expect(DashboardPresentation.trendAxisLabel(second, hourly: true, timeZone: shanghai) == "10/15 00:00")
    let day = try #require(DashboardPresentation.trendDate("2026-10-15", timeZone: shanghai))
    #expect(DashboardPresentation.trendAxisLabel(day, hourly: false, timeZone: shanghai) == "10/15")
    let utc = try #require(TimeZone(secondsFromGMT: 0))
    let utcDate = try #require(DashboardPresentation.trendDate("2026-10-15 00:00", timeZone: utc))
    #expect(utcDate.timeIntervalSince(second) == 8 * 3_600)
    #expect(DashboardPresentation.trendDate("2026-02-30", timeZone: shanghai) == nil)
    #expect(DashboardPresentation.trendDate("2026-10-15 08:30", timeZone: shanghai) == nil)
    #expect(DashboardPresentation.trendDate("2", timeZone: shanghai) == nil)
}
