import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func trendPoint(_ date: String = "2026-10-15 08:00", requests: Int = 12,
                        tokens: Int = 9_876_543_210, actual: String? = "12.345678910123456789") -> TrendPoint {
    TrendPoint(date: date, requests: requests, totalTokens: tokens, cost: Decimal(string: "99.99")!,
               actualCost: actual.flatMap { Decimal(string: $0) })
}

@Test func trendMetricsKeepActualSpendDistinctFromStandardPrice() {
    let point = trendPoint()
    #expect(DashboardTrendMetric.allCases.first == .actualCost)
    #expect(DashboardTrendMetric.actualCost.label == "实际消费")
    #expect(DashboardTrendMetric.actualCost.unit == "USD")
    #expect(DashboardTrendMetric.requests.label == "请求数")
    #expect(DashboardTrendMetric.actualCost.exactValue(point) == "$12.345678910123456789")
    #expect(DashboardTrendMetric.actualCost.displayValue(point) == "$12.35")
    #expect(DashboardTrendMetric.actualCost.plotValue(point) != 99.99)
    #expect(DashboardTrendMetric.requests.exactValue(point) == "12")
    #expect(DashboardTrendMetric.requests.displayValue(point) == "12")
    #expect(DashboardTrendMetric.tokens.exactValue(point) == "9876543210")
    #expect(DashboardTrendMetric.tokens.displayValue(point) == "9.88B")
}

@Test func trendMissingActualSpendStaysUnavailableAndOtherMetricsStillWork() throws {
    let inputs = [
        #"{"date":"2026-10-15 08:00","requests":12,"total_tokens":340,"cost":"99.99"}"#,
        #"{"date":"2026-10-15 08:00","requests":12,"total_tokens":340,"cost":"99.99","actual_cost":null}"#
    ]
    for input in inputs {
        let point = try JSONDecoder().decode(TrendPoint.self, from: Data(input.utf8))
        #expect(point.actualCost == nil)
        #expect(DashboardTrendMetric.actualCost.exactValue(point) == "不可用")
        #expect(DashboardTrendMetric.actualCost.displayValue(point) == "不可用")
        #expect(DashboardTrendMetric.actualCost.plotValue(point) == nil)
        #expect(DashboardTrendMetric.requests.plotValue(point) == 12)
        #expect(DashboardTrendMetric.tokens.plotValue(point) == 340)
    }
    let oldInitializer = TrendPoint(date: "2026-10-15", requests: 1, totalTokens: 2, cost: 99)
    #expect(oldInitializer.actualCost == nil)
    let invalid = TrendPoint(date: "2026-10-15", requests: 1, totalTokens: 2, cost: 99, actualCost: .nan)
    #expect(DashboardTrendMetric.actualCost.exactValue(invalid) == "不可用")
    #expect(DashboardTrendMetric.actualCost.displayValue(invalid) == "不可用")
    #expect(DashboardTrendMetric.actualCost.plotValue(invalid) == nil)
}

@Test(arguments: ["0", "0.0000000000000000000000000001", "12345678901234567890.12345678"])
func trendSelectedAmountPreservesDecimalPrecision(raw: String) throws {
    let input = "{\"date\":\"2026-10-15 08:00\",\"requests\":1,\"total_tokens\":2,\"cost\":99.99,\"actual_cost\":\"\(raw)\"}"
    let point = try JSONDecoder().decode(TrendPoint.self, from: Data(input.utf8))
    #expect(point.actualCost == Decimal(string: raw))
    #expect(DashboardTrendMetric.actualCost.exactValue(point) == "$" + raw)
    #expect(try #require(DashboardTrendMetric.actualCost.plotValue(point)).isFinite)
}

@Test func trendSelectedCountsRemainExactBeyondDoubleIntegerPrecision() throws {
    let point = trendPoint(requests: 9_007_199_254_740_993, tokens: Int.max)
    #expect(DashboardTrendMetric.requests.exactValue(point) == "9007199254740993")
    #expect(DashboardTrendMetric.requests.displayValue(point) == "9007199254740993")
    #expect(DashboardTrendMetric.tokens.exactValue(point) == String(Int.max))
    let coordinate = try #require(DashboardTrendMetric.requests.plotValue(point))
    #expect(DashboardTrendMetric.requests.exactValue(point) != String(format: "%.0f", coordinate))
}

@Test(arguments: [
    ("0", "$0.00"), ("0.0000000000000000000000000001", "$0.00"),
    ("0.0049999999999999999999999999", "$0.00"), ("0.005", "$0.01"),
    ("1.0049999999999999999999999999", "$1.00"), ("1.005", "$1.01"),
    ("12.345678910123456789", "$12.35"), ("1000", "$1000.00"),
    ("12345678901234567890.125", "$12345678901234567890.13")
])
func trendAmountDisplayRoundsToCentsWithoutChangingSource(raw: String, expected: String) {
    let point = trendPoint(actual: raw)
    #expect(DashboardTrendMetric.actualCost.displayValue(point) == expected)
    #expect(point.actualCost == Decimal(string: raw))
    #expect(DashboardTrendMetric.actualCost.exactValue(point) == "$" + raw)
}

@Test(arguments: [
    (0, "0"), (999, "999"), (1_000, "1.00K"), (1_234, "1.23K"),
    (1_000_000, "1.00M"), (1_234_567, "1.23M"),
    (1_000_000_000, "1.00B"), (9_876_543_210, "9.88B")
])
func trendTokenDisplayUsesCompactUnitsAndRetainsRawCount(tokens: Int, expected: String) {
    let point = trendPoint(tokens: tokens)
    #expect(DashboardTrendMetric.tokens.displayValue(point) == expected)
    #expect(point.totalTokens == tokens)
    #expect(DashboardTrendMetric.tokens.exactValue(point) == String(tokens))
}

@Test func trendSortsBucketsAndKeepsLastDuplicateWithoutDoubleCounting() throws {
    let timezone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let series = DashboardTrend.series([
        trendPoint("2026-10-15 02:00", requests: 20),
        trendPoint("2026-10-14 23:00", requests: 5),
        trendPoint("2026-10-15 02:00", requests: 8, actual: "1.23456789"),
        trendPoint("2026-02-30 01:00"), trendPoint("2")
    ], timeZone: timezone)
    #expect(series.samples.map(\.point.date) == ["2026-10-14 23:00", "2026-10-15 02:00"])
    #expect(series.samples.map(\.point.requests) == [5, 8])
    #expect(series.newestFirst.map(\.point.date) == ["2026-10-15 02:00", "2026-10-14 23:00"])
    #expect(series.newestFirst.map(\.point.requests) == [8, 5])
    #expect(series.samples.last?.point.actualCost == Decimal(string: "1.23456789"))
    #expect(series.samples.last!.date.timeIntervalSince(series.samples.first!.date) == 3 * 3_600)
    #expect(Set(series.samples.map(\.id)).count == series.samples.count)
    #expect(series.invalidDateCount == 2)
    #expect(series.duplicateCount == 1)
    #expect(series.isHourly)
}

@Test func trendHandlesEmptyDailyAndUnparseableData() throws {
    let empty = DashboardTrend.series([])
    #expect(empty.samples.isEmpty)
    #expect(empty.invalidDateCount == 0)
    #expect(empty.duplicateCount == 0)
    #expect(!empty.isHourly)
    let invalid = DashboardTrend.series([trendPoint("invalid")])
    #expect(invalid.samples.isEmpty)
    #expect(invalid.invalidDateCount == 1)
    let utc = try #require(TimeZone(secondsFromGMT: 0))
    let daily = DashboardTrend.series([trendPoint("2026-10-15"), trendPoint("2026-10-14")], timeZone: utc)
    #expect(!daily.isHourly)
    #expect(daily.samples.map(\.point.date) == ["2026-10-14", "2026-10-15"])
}

@Test(arguments: [(-4.0, 1.0), (1.0, 1.0), (2.5, 2.5), (8.0, 8.0), (40.0, 8.0)])
func trendZoomStaysWithinUsefulLimits(input: Double, expected: Double) {
    #expect(DashboardTrend.clampedZoom(input) == expected)
}

@Test func trendZoomRecoversFromNonfiniteGestures() {
    #expect(DashboardTrend.clampedZoom(.nan) == 1)
    #expect(DashboardTrend.clampedZoom(.infinity) == 1)
    #expect(DashboardTrend.clampedZoom(-.infinity) == 1)
}

@Test func trendZoomAllowsTheChartsCustomMaximum() {
    #expect(DashboardTrend.clampedZoom(9, maximum: 12) == 9)
    #expect(DashboardTrend.clampedZoom(20, maximum: 12) == 12)
    #expect(DashboardTrend.clampedZoom(0.5, maximum: 12) == 1)
    #expect(DashboardTrend.clampedZoom(2, maximum: 0) == 1)
    #expect(DashboardTrend.clampedZoom(20, maximum: .nan) == 8)
}

private actor TrendWireTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> HTTPResponse {
        guard request.url?.path == "/api/v1/admin/dashboard/trend" else { throw URLError(.unsupportedURL) }
        return HTTPResponse(statusCode: 200, data: Data(#"{"code":0,"data":{"trend":[{"date":"2026-10-15 08:00","requests":12,"total_tokens":9876543210,"cost":99.99,"actual_cost":12.34567891}]}}"#.utf8))
    }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw URLError(.unsupportedURL) }
}

@Test func trendEndpointDeliversActualSpendForTheDefaultMetric() async throws {
    let profile = ServerProfile(name: "Fixture", baseURL: URL(string: "https://trend.example.invalid")!, authentication: .adminKey)
    let client = APIClient(server: profile, credential: .adminKey("fixture"), transport: TrendWireTransport())
    let points = try await client.dashboardTrend()
    let point = try #require(points.first)
    #expect(points.count == 1)
    #expect(point.actualCost == Decimal(string: "12.34567891"))
    #expect(DashboardTrendMetric.actualCost.exactValue(point) == "$12.34567891")
}
