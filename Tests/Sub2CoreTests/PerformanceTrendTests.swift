import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

@Test(arguments: [("1m", 1.0, 600.0), ("5m", 0.2, 120.0), ("1h", 1.0 / 60, 10.0)])
func throughputUsesCountsAndBucketInsteadOfRoundedRates(bucket: String, rpm: Double, tpm: Double) throws {
    let wire = "{\"bucket\":\"\(bucket)\",\"points\":[{\"bucket_start\":\"2026-10-15T00:00:00Z\",\"request_count\":1,\"token_consumed\":600,\"qps\":0,\"tps\":0}]}"
    let trend = try JSONDecoder().decode(PerformanceTrend.self, from: Data(wire.utf8))
    let point = try #require(trend.points.first)
    #expect(abs(trend.rate(point, metric: .rpm) - rpm) < 0.00000001)
    #expect(abs(trend.rate(point, metric: .tpm) - tpm) < 0.00000001)
}

@Test func throughputSortsUTCOffsetsDeduplicatesAndHasNewestFirstDetails() throws {
    let wire = #"{"bucket":"5m","points":[{"bucket_start":"2026-10-15T08:05:00+08:00","request_count":2,"token_consumed":100},{"bucket_start":"2026-10-15T00:00:00.000Z","request_count":1,"token_consumed":50},{"bucket_start":"2026-10-15T00:05:00Z","request_count":3,"token_consumed":200}]}"#
    let trend = try JSONDecoder().decode(PerformanceTrend.self, from: Data(wire.utf8))
    #expect(trend.points.map(\.requestCount) == [1, 3])
    #expect(trend.newestFirst.map(\.requestCount) == [3, 1])
    #expect(trend.points.last!.date.timeIntervalSince(trend.points.first!.date) == 300)
}

@Test(arguments: [
    #"{"bucket":"unknown","points":[]}"#,
    #"{"bucket":"1m","points":[{"bucket_start":"yesterday","request_count":1,"token_consumed":2}]}"#,
    #"{"bucket":"1m","points":[{"bucket_start":"2026-10-15T00:00:00Z","request_count":-1,"token_consumed":2}]}"#
])
func throughputRejectsInvalidHistory(wire: String) {
    #expect(throws: (any Error).self) { try JSONDecoder().decode(PerformanceTrend.self, from: Data(wire.utf8)) }
}

private actor PerformanceTransport: HTTPTransport {
    private(set) var query: [String: String] = [:]
    func data(for request: URLRequest) async throws -> HTTPResponse {
        #expect(request.url?.path == "/api/v1/admin/ops/dashboard/throughput-trend")
        #expect(request.httpMethod == "GET")
        query = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        return HTTPResponse(statusCode: 200, data: Data(#"{"code":0,"data":{"bucket":"1m","points":[]}}"#.utf8))
    }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw URLError(.unsupportedURL) }
}

@Test func throughputRequestsARealHistoricalWindow() async throws {
    let profile = ServerProfile(name: "Fixture", baseURL: URL(string: "https://performance.example.invalid")!, authentication: .adminKey)
    let transport = PerformanceTransport()
    let client = APIClient(server: profile, credential: .adminKey("fixture"), transport: transport)
    let start = Date(timeIntervalSince1970: 1_792_022_400)
    let end = start.addingTimeInterval(3_600)
    _ = try await client.dashboardPerformanceTrend(start: start, end: end)
    let query = await transport.query
    #expect(query["start_time"] == "2026-10-15T00:00:00Z")
    #expect(query["end_time"] == "2026-10-15T01:00:00Z")
    #expect(query["mode"] == "auto")
}

@Test func performanceMetricFormatFollowsDisplayFormat() {
    #expect(PerformanceMetric.rpm.format(0.4) == "0.4")
    #expect(PerformanceMetric.rpm.format(69) == "69")
    #expect(PerformanceMetric.rpm.format(1_234) == "1,234")
    #expect(PerformanceMetric.tpm.format(690_000) == "690K")
    #expect(PerformanceMetric.tpm.format(987_654) == "987.7K")
}

/// Axis ticks of a quiet site sit below 1: they keep two decimals so neighbouring ticks never share a label (like
/// DashboardTrendMetric.axisLabel); rates and the selected value keep `format`.
@Test func performanceAxisLabelsKeepSmallTicksDistinct() {
    #expect(PerformanceMetric.rpm.axisLabel(0) == "0")
    #expect(PerformanceMetric.rpm.axisLabel(0.05) == "0.05"); #expect(PerformanceMetric.rpm.axisLabel(0.15) == "0.15")
    #expect(PerformanceMetric.rpm.axisLabel(0.2) == "0.2"); #expect(PerformanceMetric.rpm.axisLabel(12) == "12")
    #expect(PerformanceMetric.tpm.axisLabel(0.5) == "0.5"); #expect(PerformanceMetric.tpm.axisLabel(1.5) == "1.5")
    #expect(PerformanceMetric.tpm.axisLabel(999) == "999"); #expect(PerformanceMetric.tpm.axisLabel(1_500) == "1.5K")
    #expect(PerformanceMetric.rpm.axisLabel(1_234) == "1,234")
    #expect(PerformanceMetric.rpm.format(0.05) == "0.1")
}
