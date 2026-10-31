import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
/// Each point is `(bucket_start, request_count, token_consumed)`; the rounded qps / tps are always 0 to prove they are unused.
private func throughputJSON(bucket: String?, points: [(String, Int, Int)]) -> String {
    let rows = points.map { "{\"bucket_start\":\"\($0.0)\",\"request_count\":\($0.1),\"token_consumed\":\($0.2),\"qps\":0,\"tps\":0}" }
    return "{" + (bucket.map { "\"bucket\":\"\($0)\"," } ?? "") + "\"points\":[\(rows.joined(separator: ","))]}"
}
private func decodeTrend(_ json: String, from start: String, to end: String) throws -> PerformanceTrend {
    let reply = try JSONDecoder().decode(PerformanceTrend.Reply.self, from: Data(json.utf8))
    return PerformanceTrend(reply: reply, windowStart: utc(start), windowEnd: utc(end))
}
/// Consecutive wire timestamps every `step` seconds, written without help from OpsBucket.
private func wireStarts(from first: String, count: Int, step: TimeInterval) -> [String] {
    (0..<count).map { ServerTime.utcTimestamp(utc(first).addingTimeInterval(Double($0) * step)) }
}
private func trendClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate)
}
private func queryDictionary(_ request: URLRequest?) -> [String: String] {
    guard let url = request?.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
private func approx(_ value: Double?, _ expected: Double) -> Bool { value.map { abs($0 - expected) < 0.00000001 } ?? false }

// MARK: - 覆盖秒数口径（40 §1.4）

@Test(arguments: [("1m", 1.0, 600.0), ("5m", 0.2, 120.0), ("1h", 1.0 / 60, 10.0)])
func throughputFullBucketsUseCountsInsteadOfRoundedRates(bucket: String, rpm: Double, tpm: Double) throws {
    let seconds = try #require(OpsBucket(rawValue: bucket)).seconds
    let end = ServerTime.utcTimestamp(utc("2026-10-15T00:00:00Z").addingTimeInterval(seconds))
    let trend = try decodeTrend(throughputJSON(bucket: bucket, points: [("2026-10-15T00:00:00Z", 1, 600)]), from: "2026-10-15T00:00:00Z", to: end)
    let point = try #require(trend.points.first)
    #expect(trend.coveredSeconds(point) == seconds)
    #expect(approx(trend.rate(point, metric: .rpm), rpm))
    #expect(approx(trend.rate(point, metric: .tpm), tpm))
}

@Test func throughputOneMinutePartialBucketsDivideByCoveredSeconds() throws {
    let starts = wireStarts(from: "2026-10-16T00:41:00Z", count: 61, step: 60)
    let trend = try decodeTrend(throughputJSON(bucket: "1m", points: starts.map { ($0, 1, 600) }), from: "2026-10-16T00:41:30Z", to: "2026-10-16T01:41:30Z")
    #expect(trend.points.count == 61)
    let first = trend.points[0], middle = trend.points[30], last = trend.points[60]
    #expect(trend.coveredSeconds(first) == 30 && trend.coveredSeconds(middle) == 60 && trend.coveredSeconds(last) == 30)
    #expect(approx(trend.rate(first, metric: .rpm), 2)); #expect(approx(trend.rate(first, metric: .tpm), 1_200))
    #expect(approx(trend.rate(middle, metric: .rpm), 1)); #expect(approx(trend.rate(middle, metric: .tpm), 600))
    #expect(approx(trend.rate(last, metric: .rpm), 2)); #expect(approx(trend.rate(last, metric: .tpm), 1_200))
}

@Test func throughputFiveMinutePartialBucketsDivideByCoveredSeconds() throws {
    let starts = wireStarts(from: "2026-10-15T19:40:00Z", count: 73, step: 300)
    let trend = try decodeTrend(throughputJSON(bucket: "5m", points: starts.map { ($0, 4, 400) }), from: "2026-10-15T19:41:00Z", to: "2026-10-16T01:41:00Z")
    #expect(trend.points.count == 73)
    let first = trend.points[0], middle = trend.points[36], last = trend.points[72]
    #expect(trend.coveredSeconds(first) == 240 && trend.coveredSeconds(middle) == 300 && trend.coveredSeconds(last) == 60)
    #expect(approx(trend.rate(first, metric: .rpm), 1.0))
    #expect(approx(trend.rate(middle, metric: .rpm), 0.8))
    #expect(approx(trend.rate(last, metric: .rpm), 4.0))
    #expect(approx(trend.rate(last, metric: .tpm), 400))
}

@Test func throughputDropsPointsWithoutCoverage() throws {
    let json = throughputJSON(bucket: "1m", points: [
        ("2026-10-16T00:00:00Z", 2, 20), ("2026-10-16T00:30:00Z", 3, 30), ("2026-10-16T01:00:00Z", 100, 1_000),
        ("2026-10-15T23:59:00Z", 100, 1_000), ("2026-10-16T01:05:00Z", 100, 1_000)
    ])
    let trend = try decodeTrend(json, from: "2026-10-16T00:00:00Z", to: "2026-10-16T01:00:00Z")
    #expect(trend.points.map(\.requestCount) == [2, 3])
    #expect(trend.newestFirst.map(\.requestCount) == [3, 2])
    #expect(approx(trend.peak(.rpm), 3))
    #expect(approx(trend.average(.rpm), 2.5))
    #expect(approx(trend.average(.tpm), 25))
}

@Test func throughputPeakAndAverageUseCoveredSeconds() throws {
    let json = throughputJSON(bucket: "5m", points: [("2026-10-16T03:40:00Z", 4, 400), ("2026-10-16T03:45:00Z", 10, 1_000), ("2026-10-16T03:50:00Z", 3, 300)])
    let trend = try decodeTrend(json, from: "2026-10-16T03:41:00Z", to: "2026-10-16T03:51:00Z")
    #expect(trend.points.map(trend.coveredSeconds) == [240, 300, 60])
    #expect(approx(trend.peak(.rpm), 3.0))
    #expect(approx(trend.average(.rpm), 1.7))
    #expect(approx(trend.peak(.tpm), 300))
    #expect(approx(trend.average(.tpm), 170))
}

@Test func throughputPeakAndAverageAreNilWithoutPoints() throws {
    let empty = PerformanceTrend(bucket: .minute, windowStart: utc("2026-10-16T00:00:00Z"), windowEnd: utc("2026-10-16T01:00:00Z"), points: [])
    #expect(empty.peak(.rpm) == nil && empty.average(.tpm) == nil)
    let outside = try decodeTrend(throughputJSON(bucket: "1m", points: [("2026-10-16T02:00:00Z", 5, 50)]), from: "2026-10-16T00:00:00Z", to: "2026-10-16T01:00:00Z")
    #expect(outside.points.isEmpty && outside.peak(.rpm) == nil && outside.average(.rpm) == nil)
    let quiet = try decodeTrend(throughputJSON(bucket: "1m", points: wireStarts(from: "2026-10-16T00:00:00Z", count: 60, step: 60).map { ($0, 0, 0) }),
                                from: "2026-10-16T00:00:00Z", to: "2026-10-16T01:00:00Z")
    #expect(quiet.peak(.rpm) == 0 && quiet.average(.rpm) == 0 && quiet.average(.tpm) == 0)
}

@Test(arguments: [#""bucket":"unknown","#, "", #""bucket":null,"#, #""bucket":5,"#])
func throughputUnknownBucketFallsBackToWindowLength(bucketField: String) throws {
    for (end, bucket) in [("2026-10-16T01:00:00Z", OpsBucket.minute), ("2026-10-16T06:00:00Z", .fiveMinutes), ("2026-10-19T00:00:00Z", .hour)] {
        let json = "{\(bucketField)\"points\":[{\"bucket_start\":\"2026-10-16T00:00:00Z\",\"request_count\":60,\"token_consumed\":600}]}"
        let trend = try decodeTrend(json, from: "2026-10-16T00:00:00Z", to: end)
        #expect(trend.bucket == bucket)
        let point = try #require(trend.points.first)
        #expect(approx(trend.rate(point, metric: .rpm), 3_600 / bucket.seconds))
    }
}

@Test func throughputDecodesSwitchCountDefaultingToZero() throws {
    let json = #"{"bucket":"1m","points":[{"bucket_start":"2026-10-16T00:00:00Z","request_count":1,"token_consumed":2,"switch_count":3},{"bucket_start":"2026-10-16T00:01:00Z","request_count":1,"token_consumed":2},{"bucket_start":"2026-10-16T00:02:00Z","request_count":1,"token_consumed":2,"switch_count":null}]}"#
    let trend = try decodeTrend(json, from: "2026-10-16T00:00:00Z", to: "2026-10-16T00:03:00Z")
    #expect(trend.points.map(\.switchCount) == [3, 0, 0])
    #expect(PerformanceTrend.Point(date: utc("2026-10-16T00:00:00Z"), requestCount: 1, tokenConsumed: 2).switchCount == 0)
}

@Test func throughputSortsUTCOffsetsDeduplicatesAndHasNewestFirstDetails() throws {
    let wire = #"{"bucket":"5m","points":[{"bucket_start":"2026-10-15T08:05:00+08:00","request_count":2,"token_consumed":100},{"bucket_start":"2026-10-15T00:00:00.000Z","request_count":1,"token_consumed":50},{"bucket_start":"2026-10-15T00:05:00Z","request_count":3,"token_consumed":200}]}"#
    let trend = try decodeTrend(wire, from: "2026-10-15T00:00:00Z", to: "2026-10-15T00:10:00Z")
    #expect(trend.points.map(\.requestCount) == [1, 3])
    #expect(trend.newestFirst.map(\.requestCount) == [3, 1])
    #expect(trend.points.last!.date.timeIntervalSince(trend.points.first!.date) == 300)
}

@Test(arguments: [
    #"{"bucket":"1m","points":[{"bucket_start":"yesterday","request_count":1,"token_consumed":2}]}"#,
    #"{"bucket":"1m","points":[{"bucket_start":"2026-10-15T00:00:00Z","request_count":-1,"token_consumed":2}]}"#,
    #"{"bucket":"1m","points":[{"bucket_start":"2026-10-15T00:00:00Z","request_count":1,"token_consumed":2,"switch_count":-1}]}"#
])
func throughputRejectsInvalidHistory(wire: String) {
    #expect(throws: (any Error).self) { try JSONDecoder().decode(PerformanceTrend.Reply.self, from: Data(wire.utf8)) }
}

// MARK: - 请求（40 §1.2、§1.4）

private let filteredQuery = OpsQuery(start: utc("2026-10-15T00:00:00Z"), end: utc("2026-10-15T01:00:00Z"), groupID: 3,
                                     model: "claude-opus-4", modelSource: .upstream)

@Test func throughputRequestOmitsModeAndCarriesWindowAndFilters() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"bucket":"1m","points":[]}"#) }
    let trend = try await trendClient(transport).dashboardPerformanceTrend(filteredQuery, supportsModelFilter: true)
    let sent = await transport.requests
    #expect(sent.count == 1)
    let request = try #require(sent.first)
    #expect(request.httpMethod == "GET" && request.url?.path == "/api/v1/admin/ops/dashboard/throughput-trend")
    #expect(request.timeoutInterval == RequestTimeout.aggregate)
    #expect(queryDictionary(request) == ["start_time": "2026-10-15T00:00:00Z", "end_time": "2026-10-15T01:00:00Z", "group_id": "3",
                                         "model": "claude-opus-4", "model_source": "upstream"])
    #expect(trend.windowStart == filteredQuery.start && trend.windowEnd == filteredQuery.end && trend.bucket == .minute)
}

@Test func throughputRequestDropsModelWithoutCapabilityOrForMapping() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"bucket":"1m","points":[]}"#) }
    let client = trendClient(transport)
    _ = try await client.dashboardPerformanceTrend(filteredQuery, supportsModelFilter: false)
    var mapping = filteredQuery
    mapping.modelSource = .mapping
    _ = try await client.dashboardPerformanceTrend(mapping, supportsModelFilter: true)
    let sent = await transport.requests
    #expect(sent.count == 2)
    for request in sent {
        #expect(queryDictionary(request) == ["start_time": "2026-10-15T00:00:00Z", "end_time": "2026-10-15T01:00:00Z", "group_id": "3"])
    }
}

@Test func throughputPassesOpsDisabledThrough() async throws {
    let transport = ScriptedTransport { _ in errorReply(404, reason: "OPS_DISABLED") }
    let error = await thrownAPIError { _ = try await trendClient(transport).dashboardPerformanceTrend(filteredQuery, supportsModelFilter: true) }
    #expect(error?.reason == "OPS_DISABLED" && error?.kind == .featureDisabled)
}

@Test(arguments: [(PerformanceTrend.maximumSpan + 1, nil), (0, nil), (3_600, 0)] as [(TimeInterval, Int?)])
func throughputRejectsInvalidWindowsBeforeSending(span: TimeInterval, groupID: Int?) async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"bucket":"1h","points":[]}"#) }
    let start = utc("2026-09-01T00:00:00Z")
    let query = OpsQuery(start: start, end: start.addingTimeInterval(span), groupID: groupID)
    let error = await thrownAPIError { _ = try await trendClient(transport).dashboardPerformanceTrend(query, supportsModelFilter: true) }
    #expect(error?.kind == .validation)
    #expect(await transport.requests.isEmpty)
}

/// S4D1-10: last month plus a daylight-saving hour still fits; the server itself has no limit.
@Test func throughputAcceptsThirtyOneDaysAndAnHour() async throws {
    #expect(PerformanceTrend.maximumSpan == 31 * 86_400 + 3_600)
    let transport = ScriptedTransport { _ in okReply(#"{"bucket":"1h","points":[]}"#) }
    let start = utc("2026-09-01T00:00:00Z")
    let trend = try await trendClient(transport).dashboardPerformanceTrend(OpsQuery(start: start, end: start.addingTimeInterval(PerformanceTrend.maximumSpan)),
                                                                           supportsModelFilter: false)
    #expect(trend.bucket == .hour)
    #expect(await transport.requests.count == 1)
}

// MARK: - 数值格式

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
