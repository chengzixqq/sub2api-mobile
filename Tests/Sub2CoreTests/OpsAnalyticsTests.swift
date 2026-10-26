import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// MARK: - OpsQuery 与桶长（S4-10）

private enum OpsQueryFixture {
    static func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    static let start = utc("2026-10-16T00:41:00Z")
    static let end = utc("2026-10-16T01:41:00Z")
    static func query(groupID: Int? = nil, model: String? = nil, source: ModelSource? = nil) -> OpsQuery {
        OpsQuery(start: start, end: end, groupID: groupID, model: model, modelSource: source)
    }
    static func items(_ query: OpsQuery, supportsModelFilter: Bool) -> [String: String] {
        Dictionary(query.queryItems(supportsModelFilter: supportsModelFilter).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
    static func dates(_ starts: [Date]) -> [String] { starts.map(ServerTime.utcTimestamp) }
}

@Test func opsQuerySendsUTCWindowAndGroupWithoutModeOrTimezone() {
    #expect(OpsQueryFixture.query(groupID: 7).queryItems(supportsModelFilter: true) == [
        URLQueryItem(name: "start_time", value: "2026-10-16T00:41:00Z"), URLQueryItem(name: "end_time", value: "2026-10-16T01:41:00Z"),
        URLQueryItem(name: "group_id", value: "7")
    ])
    #expect(OpsQueryFixture.query().queryItems(supportsModelFilter: true).map(\.name) == ["start_time", "end_time"])
}

/// 40 §1.2, the ops row: only requested / upstream reach the server, and only on a site with `ops.dashboard_model_filter`.
private let modelMappingCases: [(ModelSource?, Bool, String?, String?)] = [
    (.requested, true, "claude-opus-4", "requested"), (.upstream, true, "claude-opus-4", "upstream"), (.mapping, true, nil, nil),
    (.requested, false, nil, nil), (.upstream, false, nil, nil), (.mapping, false, nil, nil),
    (nil, true, "claude-opus-4", "requested"), (nil, false, nil, nil)
]

@Test(arguments: modelMappingCases)
func opsQueryModelMappingFollowsSourceAndCapability(source: ModelSource?, supports: Bool, model: String?, modelSource: String?) {
    let query = OpsQueryFixture.query(groupID: 3, model: "claude-opus-4", source: source)
    let items = OpsQueryFixture.items(query, supportsModelFilter: supports)
    #expect(items["model"] == model)
    #expect(items["model_source"] == modelSource)
    #expect(items["group_id"] == "3")
    #expect(query.isSiteWide(supportsModelFilter: supports) == (model == nil))
}

@Test(arguments: [nil, "", "   "] as [String?])
func opsQueryWithoutModelNeverSendsModelSourceAndIsNotSiteWide(model: String?) {
    for source in [ModelSource.upstream, .mapping] {
        for supports in [true, false] {
            let query = OpsQueryFixture.query(model: model, source: source)
            let names = query.queryItems(supportsModelFilter: supports).map(\.name)
            #expect(!names.contains("model") && !names.contains("model_source"))
            #expect(!query.isSiteWide(supportsModelFilter: supports))
        }
    }
    #expect(!OpsQueryFixture.query(groupID: 3).isSiteWide(supportsModelFilter: false))
}

@Test func opsQueryTrimsModelName() async throws {
    #expect(OpsQueryFixture.items(OpsQueryFixture.query(model: " gpt-4.1 ", source: .requested), supportsModelFilter: true)["model"] == "gpt-4.1")
    let transport = ScriptedTransport { _ in okReply(#"{"bucket":"1m","points":[]}"#) }
    let client = APIClient(server: stubServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate)
    _ = try await client.dashboardPerformanceTrend(OpsQueryFixture.query(model: " claude+opus ", source: .upstream), supportsModelFilter: true)
    let sent = await transport.requests
    let url = try #require(sent.first?.url)
    let encoded = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
    #expect(encoded.contains("model=claude%2Bopus")); #expect(!encoded.contains("claude+opus"))
    #expect(encoded.contains("model_source=upstream"))
}

@Test(arguments: [(0.0, nil), (-60.0, nil), (3_600.0, 0), (3_600.0, -3)] as [(TimeInterval, Int?)])
func opsQueryValidateRejectsEmptyWindowAndNonPositiveGroup(span: TimeInterval, groupID: Int?) async throws {
    let start = OpsQueryFixture.start
    let invalid = OpsQuery(start: start, end: start.addingTimeInterval(span), groupID: groupID)
    let error = await thrownAPIError { try invalid.validate() }
    #expect(error?.kind == .validation)
    try OpsQueryFixture.query(groupID: 7).validate()
    try OpsQueryFixture.query().validate()
}

@Test(arguments: [1, 6, 24])
func opsQueryTrailingWindowFloorsEndToWholeMinute(hours: Int) {
    let utc = OpsQueryFixture.utc
    let minute = utc("2026-10-16T01:41:00Z")
    let query = OpsQuery.trailingWindow(hours: hours, endingAt: utc("2026-10-16T01:41:23Z"), groupID: 5, model: "gpt-4.1", modelSource: .upstream)
    #expect(query.end == minute)
    #expect(query.start == minute.addingTimeInterval(-Double(hours) * 3_600))
    #expect(query.groupID == 5 && query.model == "gpt-4.1" && query.modelSource == .upstream)
    let exact = OpsQuery.trailingWindow(hours: hours, endingAt: minute)
    #expect(exact == OpsQuery(start: minute.addingTimeInterval(-Double(hours) * 3_600), end: minute))
    #expect(OpsQuery.trailingWindow(hours: hours, endingAt: minute.addingTimeInterval(59.9)).end == minute)
}

@Test(arguments: [(3_600, .minute), (7_200, .minute), (7_201, .fiveMinutes), (21_600, .fiveMinutes), (86_400, .fiveMinutes),
                  (86_401, .hour), (2_592_000, .hour)] as [(TimeInterval, OpsBucket)])
func opsBucketForWindowFollowsBackendThresholds(window: TimeInterval, bucket: OpsBucket) {
    #expect(OpsBucket.forWindow(window) == bucket)
    #expect(OpsBucket.allCases.map(\.seconds) == [60, 300, 3_600])
    #expect(OpsBucket.allCases.map(\.label) == ["1 分钟", "5 分钟", "1 小时"])
}

@Test func opsBucketResolveKeepsKnownLabelsAndDerivesUnknownOnes() {
    #expect(OpsBucket.resolve("5m", window: 3_600) == .fiveMinutes)
    #expect(OpsBucket.resolve("1h", window: 3_600) == .hour)
    #expect(OpsBucket.resolve("10m", window: 21_600) == .fiveMinutes)
    #expect(OpsBucket.resolve(nil, window: 3_600) == .minute)
    #expect(OpsBucket.resolve("", window: 3 * 86_400) == .hour)
}

@Test func opsBucketStartsMatchTheBackendZeroFill() {
    let utc = OpsQueryFixture.utc
    let hour = OpsQueryFixture.dates(OpsBucket.minute.starts(from: utc("2026-10-16T00:41:00Z"), to: utc("2026-10-16T01:41:00Z")))
    #expect(hour.count == 60)
    #expect(hour.first == "2026-10-16T00:41:00Z" && hour.last == "2026-10-16T01:40:00Z")
    let sixHours = OpsBucket.fiveMinutes.starts(from: utc("2026-10-15T19:41:00Z"), to: utc("2026-10-16T01:41:00Z"))
    #expect(sixHours.count == 73)
    #expect(OpsQueryFixture.dates(sixHours).first == "2026-10-15T19:40:00Z" && OpsQueryFixture.dates(sixHours).last == "2026-10-16T01:40:00Z")
    #expect(Set(zip(sixHours, sixHours.dropFirst()).map { $1.timeIntervalSince($0) }) == [300])
    let onBoundary = OpsQueryFixture.dates(OpsBucket.fiveMinutes.starts(from: utc("2026-10-16T00:40:00Z"), to: utc("2026-10-16T01:40:00Z")))
    #expect(onBoundary.count == 12 && onBoundary.last == "2026-10-16T01:35:00Z")
    #expect(OpsQueryFixture.dates(OpsBucket.hour.starts(from: utc("2026-10-16T00:41:00Z"), to: utc("2026-10-16T03:41:00Z")))
            == ["2026-10-16T00:00:00Z", "2026-10-16T01:00:00Z", "2026-10-16T02:00:00Z", "2026-10-16T03:00:00Z"])
    #expect(OpsBucket.minute.starts(from: utc("2026-10-16T01:41:00Z"), to: utc("2026-10-16T01:41:00Z")).isEmpty)
    #expect(OpsBucket.minute.starts(from: utc("2026-10-16T01:42:00Z"), to: utc("2026-10-16T01:41:00Z")).isEmpty)
}

// MARK: - 四个运维图表（S4-11）

private enum OpsChartStubs {
    static func utc(_ text: String) -> Date { ServerTime.parseTimestamp(text)! }
    static let zone = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
    static let newYork = ServerTimeZone(identifier: "America/New_York", utcOffset: "-04:00")!
    static let kolkata = ServerTimeZone(identifier: "Asia/Kolkata", utcOffset: "+05:30")!
    /// Site time 2026-10-16 09:41; `today` and `lastSevenDays` are the presets' starts on that day.
    static let now = utc("2026-10-16T01:41:00Z")
    static let today = utc("2026-10-15T16:00:00Z")
    static let lastSevenDays = utc("2026-10-09T16:00:00Z")
    static let charts = ["latency-histogram", "error-trend", "error-distribution"]

    static func client(_ transport: ScriptedTransport, now: Date = OpsChartStubs.now, zone: ServerTimeZone = OpsChartStubs.zone) -> APIClient {
        APIClient(server: stubServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate,
                  serverTimeZone: zone, serverClock: ServerClock(localNow: { now }))
    }
    static func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
    static func sent(_ request: URLRequest?) -> [String: String] {
        let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
    /// The three page-range charts by path name; anything else reads the token stats with the custom-range capability.
    static func chart(_ name: String, _ client: APIClient, _ query: OpsQuery, supportsModelFilter: Bool = false) async throws {
        switch name {
        case "latency-histogram": _ = try await client.opsLatencyHistogram(query, supportsModelFilter: supportsModelFilter)
        case "error-trend": _ = try await client.opsErrorTrend(query, supportsModelFilter: supportsModelFilter)
        case "error-distribution": _ = try await client.opsErrorDistribution(query, supportsModelFilter: supportsModelFilter)
        default: _ = try await client.opsTokenStats(query, supportsCustomRange: true, supportsModelFilter: supportsModelFilter)
        }
    }
    /// One point every `step` seconds; by default point i has `2 + i` SLA errors and one business limit.
    static func points(from first: Date, count: Int, step: TimeInterval,
                       counts: (Int) -> OpsErrorCounts = { OpsErrorCounts(total: 3 + $0, sla: 2 + $0, businessLimited: 1) }) -> [OpsErrorTrend.Point] {
        (0..<count).map { OpsErrorTrend.Point(start: first.addingTimeInterval(Double($0) * step), counts: counts($0)) }
    }
    static func trend(_ bucket: OpsBucket, _ points: [OpsErrorTrend.Point]) -> OpsErrorTrend {
        OpsErrorTrend(bucket: bucket, points: points, windowStart: points.first?.start ?? now, windowEnd: points.last?.start ?? now)
    }
}

private func tokenRow(_ model: String, _ requests: Int, _ speed: Double?, _ firstToken: Double?, withFirstToken: Int = 0,
                      duration: Double? = nil) -> OpsTokenStats.Item {
    OpsTokenStats.Item(model: model, requestCount: requests, tokensPerSecond: speed, firstTokenMs: firstToken, durationMs: duration,
                       requestsWithFirstToken: withFirstToken)
}

@Test func latencyHistogramKeepsSixFixedRangesInOrder() throws {
    let histogram: OpsLatencyHistogram = try OpsChartStubs.decode("""
        {"buckets":[{"range":"2000ms+","count":5},{"range":"0-100ms","count":20},{"range":"5000ms+","count":99},\
        {"range":"200-500ms","count":80},{"range":"100-200ms","count":50},{"range":"500-1000ms","count":30},{"range":"0-100ms"}]}
        """)
    #expect(histogram.buckets.map(\.range) == OpsLatencyHistogram.BucketRange.allCases)
    #expect(histogram.buckets.map(\.count) == [20, 50, 80, 30, 0, 5])
    #expect(histogram.totalRequests == 185)
    #expect(OpsLatencyHistogram.BucketRange.allCases.map(\.label) == ["<100ms", "100–200", "200–500", "0.5–1s", "1–2s", "≥2s"])
    let missing: OpsLatencyHistogram = try OpsChartStubs.decode(#"{"total_requests":0,"buckets":null}"#)
    #expect(missing.buckets.map(\.count) == [0, 0, 0, 0, 0, 0] && missing.totalRequests == 0)
    let repeated = OpsLatencyHistogram(buckets: [.init(range: .to200, count: 3), .init(range: .to200, count: 4)])
    #expect(repeated.buckets.map(\.count) == [0, 7, 0, 0, 0, 0] && repeated.totalRequests == 7)
}

@Test func latencyHistogramSharesHeightsAndEmptyState() throws {
    let counts = [20, 50, 80, 30, 15, 5]
    let histogram = OpsLatencyHistogram(totalRequests: 200, buckets: zip(OpsLatencyHistogram.BucketRange.allCases, counts).map {
        OpsLatencyHistogram.Bucket(range: $0, count: $1)
    })
    #expect(histogram.share(histogram.buckets[1]) == 0.25)
    #expect(histogram.height(histogram.buckets[2]) == 1 && histogram.height(histogram.buckets[0]) == 0.25)
    #expect(!histogram.isEmpty)
    let empty: OpsLatencyHistogram = try OpsChartStubs.decode(#"{"total_requests":0,"buckets":[{"range":"0-100ms","count":0}]}"#)
    try #require(empty.buckets.count == 6)
    #expect(empty.isEmpty && empty.share(empty.buckets[0]) == nil && empty.height(empty.buckets[0]) == 0)
    #expect(throws: DecodingError.self) {
        try OpsChartStubs.decode(#"{"total_requests":5,"buckets":[{"range":"0-100ms","count":-1}]}"#, as: OpsLatencyHistogram.self)
    }
    #expect(throws: DecodingError.self) { try OpsChartStubs.decode(#"{"total_requests":-5}"#, as: OpsLatencyHistogram.self) }
}

@Test func errorTrendDecodesSixCountsAndDefaultsMissingOnes() throws {
    let utc = OpsChartStubs.utc
    let reply: OpsErrorTrend.Reply = try OpsChartStubs.decode("""
        {"bucket":"5m","points":[\
        {"bucket_start":"2026-10-16T00:05:00Z","error_count_total":4,"business_limited_count":1,"error_count_sla":3,\
        "upstream_error_count_excl_429_529":6,"upstream_429_count":7,"upstream_529_count":8},\
        {"bucket_start":"2026-10-16T00:00:00+08:00","error_count_total":2,"error_count_sla":2},\
        {"bucket_start":"2026-10-16T00:05:00Z","error_count_total":9,"business_limited_count":4,"error_count_sla":5}]}
        """)
    #expect(reply.bucket == "5m")
    #expect(reply.points.first?.counts == OpsErrorCounts(total: 4, sla: 3, businessLimited: 1, upstream429: 7, upstream529: 8, upstreamOther: 6))
    let trend = OpsErrorTrend(bucket: .fiveMinutes, points: reply.points, windowStart: OpsChartStubs.today, windowEnd: OpsChartStubs.now)
    #expect(trend.points.map(\.start) == [utc("2026-10-15T16:00:00Z"), utc("2026-10-16T00:05:00Z")])
    #expect(trend.points.map(\.counts) == [OpsErrorCounts(total: 2, sla: 2), OpsErrorCounts(total: 9, sla: 5, businessLimited: 4)])
    let empty: OpsErrorTrend.Reply = try OpsChartStubs.decode(#"{"bucket":null,"points":null}"#)
    #expect(empty.bucket == nil && empty.points.isEmpty)
    for bad in [#"{"bucket_start":"yesterday","error_count_total":1}"#, #"{"error_count_total":1}"#,
                #"{"bucket_start":"2026-10-16T00:00:00Z","error_count_sla":-1}"#, #"{"bucket_start":"2026-10-16T00:00:00Z","upstream_429_count":-2}"#] {
        #expect(throws: DecodingError.self) { try OpsChartStubs.decode(#"{"points":["# + bad + "]}", as: OpsErrorTrend.Reply.self) }
    }
}

@Test func errorTrendHourlyBarsInSiteZoneStackOnlySLAAndBusinessLimited() {
    let midnight = OpsChartStubs.today
    let trend = OpsChartStubs.trend(.fiveMinutes, OpsChartStubs.points(from: midnight, count: 24, step: 300))
    let bars = trend.bars(in: OpsChartStubs.zone)
    #expect(trend.grouping == .hour)
    #expect(bars.map(\.start) == [midnight, midnight.addingTimeInterval(3_600)])
    #expect(bars.map { $0.end.timeIntervalSince($0.start) } == [3_600, 3_600])
    #expect(bars.map(\.counts.total) == [102, 246])
    #expect(bars.allSatisfy { $0.counts.sla + $0.counts.businessLimited == $0.counts.total })
    #expect(trend.totals == OpsErrorCounts(total: 348, sla: 324, businessLimited: 24))
    #expect(bars.reduce(OpsErrorCounts.zero) { $0 + $1.counts } == trend.totals && !trend.isEmpty)
    // A half-hour offset: the site's hours begin at :30 UTC, so UTC hours would give three bars.
    let kolkataMidnight = OpsChartStubs.utc("2026-10-15T18:30:00Z")
    let kolkata = OpsChartStubs.trend(.fiveMinutes, OpsChartStubs.points(from: kolkataMidnight, count: 24, step: 300)).bars(in: OpsChartStubs.kolkata)
    #expect(kolkata.map(\.start) == [kolkataMidnight, kolkataMidnight.addingTimeInterval(3_600)])
    #expect(kolkata.map(\.counts.total) == [102, 246])
}

@Test func errorTrendDailyBarsSplitAtSiteMidnightNotUTC() {
    let utc = OpsChartStubs.utc
    let points = OpsChartStubs.points(from: utc("2026-10-14T14:00:00Z"), count: 52, step: 3_600) { _ in OpsErrorCounts(total: 1, sla: 1) }
    #expect(points.last?.start == utc("2026-10-16T17:00:00Z"))
    let trend = OpsChartStubs.trend(.hour, points)
    let bars = trend.bars(in: OpsChartStubs.zone)
    #expect(trend.grouping == .day)
    #expect(bars.map(\.start) == ["2026-10-13T16:00:00Z", "2026-10-14T16:00:00Z", "2026-10-15T16:00:00Z", "2026-10-16T16:00:00Z"].map(utc))
    #expect(bars.map(\.counts.total) == [2, 24, 24, 2])
    #expect(bars.allSatisfy { $0.end.timeIntervalSince($0.start) == 86_400 && $0.counts.sla + $0.counts.businessLimited == $0.counts.total })
}

@Test func errorTrendDayBarsFollowDaylightSavingCalendar() {
    let utc = OpsChartStubs.utc
    let firstOfNovember = utc("2026-11-01T04:00:00Z")
    let points = OpsChartStubs.points(from: firstOfNovember, count: 49, step: 3_600) { _ in OpsErrorCounts(total: 1, businessLimited: 1) }
    let bars = OpsChartStubs.trend(.hour, points).bars(in: OpsChartStubs.newYork)
    #expect(bars.map(\.start) == [firstOfNovember, utc("2026-11-02T05:00:00Z")])
    #expect(bars.map(\.counts.total) == [25, 24])
    #expect(bars.map { $0.end.timeIntervalSince($0.start) } == [90_000, 86_400])
}

@Test func errorTrendFiveMinuteBarsForMinuteBuckets() {
    let midnight = OpsChartStubs.today
    let trend = OpsChartStubs.trend(.minute, OpsChartStubs.points(from: midnight, count: 12, step: 60) { _ in OpsErrorCounts(total: 1, sla: 1) })
    let bars = trend.bars(in: OpsChartStubs.zone)
    #expect(trend.grouping == .fiveMinutes)
    #expect(bars.map(\.start) == [0, 300, 600].map { midnight.addingTimeInterval($0) })
    #expect(bars.map(\.counts.total) == [5, 5, 2])
    #expect(bars.allSatisfy { $0.end.timeIntervalSince($0.start) == 300 })
    #expect(OpsBucket.allCases.map(OpsErrorTrend.Grouping.init(bucket:)) == [.fiveMinutes, .hour, .day])
}

/// U34: the upstream counts include failures a retry recovered, so they are not part of `error_count_total`.
@Test func errorTrendUpstreamCountsStayOutsideTheBars() {
    let counts = OpsErrorCounts(total: 2, sla: 1, businessLimited: 1, upstream429: 5, upstream529: 1, upstreamOther: 3)
    let trend = OpsChartStubs.trend(.fiveMinutes, [OpsErrorTrend.Point(start: OpsChartStubs.today, counts: counts)])
    let bars = trend.bars(in: OpsChartStubs.zone)
    #expect(bars.map(\.counts.total) == [2] && bars.map { $0.counts.sla + $0.counts.businessLimited } == [2])
    #expect(trend.totals.upstream429 == 5 && trend.totals.upstream529 == 1 && trend.totals.upstreamOther == 3)
    let retriedOnly = OpsChartStubs.trend(.fiveMinutes, [OpsErrorTrend.Point(start: OpsChartStubs.today, counts: OpsErrorCounts(upstream429: 4))])
    #expect(retriedOnly.isEmpty && retriedOnly.totals.upstream429 == 4)
}

@Test func errorDistributionSortsSharesAndBarsRelativeToFirstRow() throws {
    let distribution: OpsErrorDistribution = try OpsChartStubs.decode("""
        {"total":100,"items":[{"status_code":500,"total":30,"sla":30,"business_limited":0},\
        {"status_code":429,"total":47,"sla":40,"business_limited":7},{"status_code":403,"total":23,"business_limited":23}]}
        """)
    let rows = distribution.items
    try #require(rows.count == 3)
    #expect(rows.map(\.statusCode) == [429, 500, 403] && rows[2].sla == 0)
    #expect(distribution.share(rows[0]) == 0.47)
    #expect(distribution.barLength(rows[0]) == .init(sla: 40.0 / 47, businessLimited: 7.0 / 47))
    #expect(distribution.barLength(rows[1]) == .init(sla: 30.0 / 47, businessLimited: 0))
    #expect(distribution.barLength(rows[2]) == .init(sla: 0, businessLimited: 23.0 / 47))
    #expect(distribution.leading?.statusCode == 429 && !distribution.isEmpty)
}

@Test func errorDistributionEmptyAndMissingTotal() throws {
    let empty: OpsErrorDistribution = try OpsChartStubs.decode(#"{"total":0,"items":[]}"#)
    #expect(empty.isEmpty && empty.leading == nil && empty.items.isEmpty)
    let bare: OpsErrorDistribution = try OpsChartStubs.decode(#"{"items":null}"#)
    #expect(bare.isEmpty && bare.total == 0)
    let untotalled: OpsErrorDistribution = try OpsChartStubs.decode("""
        {"items":[{"status_code":502,"total":5,"sla":5},{"status_code":500,"total":5,"sla":4,"business_limited":1},{"status_code":0,"total":2,"sla":2}]}
        """)
    #expect(untotalled.total == 12 && untotalled.items.map(\.statusCode) == [500, 502, 0])
    let zero = OpsErrorDistribution(total: 0, items: [OpsErrorDistribution.Item(statusCode: 500, total: 0, sla: 0, businessLimited: 0)])
    try #require(zero.items.count == 1)
    #expect(zero.share(zero.items[0]) == nil && zero.barLength(zero.items[0]) == .init(sla: 0, businessLimited: 0))
    #expect(throws: DecodingError.self) { try OpsChartStubs.decode(#"{"items":[{"status_code":500,"total":-1}]}"#, as: OpsErrorDistribution.self) }
    #expect(throws: DecodingError.self) { try OpsChartStubs.decode(#"{"items":[{"total":1}]}"#, as: OpsErrorDistribution.self) }
}

@Test func tokenStatsDecodesNullableAveragesAndUTCEcho() throws {
    let utc = OpsChartStubs.utc
    let reply: OpsTokenStats.Reply = try OpsChartStubs.decode("""
        {"time_range":"custom","start_time":"2026-10-15T16:00:00Z","end_time":"2026-10-16T01:41:00.123456789Z","items":[\
        {"model":"gpt-4.1","request_count":12,"avg_tokens_per_sec":null,"avg_first_token_ms":null,"total_output_tokens":900,"avg_duration_ms":1234},\
        {"model":"claude-opus-4","request_count":3,"avg_tokens_per_sec":41.25,"avg_first_token_ms":812.5,"avg_duration_ms":0,"requests_with_first_token":2}]}
        """)
    let stats = OpsTokenStats(reply: reply, window: .custom)
    #expect(stats.timeRange == "custom" && stats.window == .custom)
    #expect(stats.startTime == utc("2026-10-15T16:00:00Z") && stats.endTime == utc("2026-10-16T01:41:00.123Z"))
    #expect(stats.items == [
        OpsTokenStats.Item(model: "gpt-4.1", requestCount: 12, tokensPerSecond: nil, firstTokenMs: nil, totalOutputTokens: 900, durationMs: 1_234,
                           requestsWithFirstToken: 0),
        OpsTokenStats.Item(model: "claude-opus-4", requestCount: 3, tokensPerSecond: 41.25, firstTokenMs: 812.5, durationMs: 0, requestsWithFirstToken: 2)
    ])
    #expect(stats.total == 2)
    let truncatedReply: OpsTokenStats.Reply = try OpsChartStubs.decode(#"{"time_range":"30d","items":null,"total":37}"#)
    let truncated = OpsTokenStats(reply: truncatedReply, window: .tooLargeFallback)
    #expect(truncated.total == 37 && truncated.items.isEmpty && truncated.startTime == nil && truncated.timeRange == "30d")
    #expect(throws: DecodingError.self) { try OpsChartStubs.decode(#"{"items":[{"request_count":1}]}"#, as: OpsTokenStats.Reply.self) }
    #expect(throws: DecodingError.self) { try OpsChartStubs.decode(#"{"items":[{"model":"m","request_count":-1}]}"#, as: OpsTokenStats.Reply.self) }
}

@Test func tokenStatsSortsLocallyWithNullsLast() {
    let stats = OpsTokenStats(items: [tokenRow("a", 50, 40, 900), tokenRow("b", 30, nil, 500), tokenRow("c", 80, 40, nil), tokenRow("d", 10, 60, 700)],
                              window: .custom)
    #expect(stats.sorted(by: .requests).map(\.model) == ["c", "a", "b", "d"])
    #expect(stats.sorted(by: .speed).map(\.model) == ["d", "a", "c", "b"])
    #expect(stats.sorted(by: .firstToken).map(\.model) == ["b", "d", "a", "c"])
    #expect(OpsTokenStatsOrder.allCases.map(\.label) == ["按请求", "按速度", "按首 Token"])
    let ties = OpsTokenStats(items: [tokenRow("x", 5, nil, nil), tokenRow("y", 5, nil, nil), tokenRow("z", 9, nil, nil)], window: .custom)
    #expect(ties.sorted(by: .requests).map(\.model) == ["z", "x", "y"])
    #expect(ties.sorted(by: .speed).map(\.model) == ["x", "y", "z"] && ties.sorted(by: .firstToken).map(\.model) == ["x", "y", "z"])
}

@Test func tokenStatsVisibleRowsPinTheFilteredModel() {
    let stats = OpsTokenStats(items: (0..<12).map { tokenRow("m\($0)", 120 - $0 * 10, $0 == 3 ? 99 : Double($0), nil) }, window: .custom)
    #expect(stats.visibleRows(.requests, limit: 5, pinnedModel: "m7").map(\.model) == ["m0", "m1", "m2", "m3", "m4", "m7"])
    #expect(stats.visibleRows(.requests, limit: 5, pinnedModel: "m2").map(\.model) == ["m0", "m1", "m2", "m3", "m4"])
    #expect(stats.visibleRows(.requests, limit: 5, pinnedModel: "gpt-9").count == 5)
    #expect(stats.visibleRows(.requests, limit: 5, pinnedModel: nil).count == 5)
    #expect(stats.visibleRows(.speed, limit: 9, pinnedModel: "m0").map(\.model) == ["m3", "m11", "m10", "m9", "m8", "m7", "m6", "m5", "m4", "m0"])
    #expect(stats.fastest?.model == "m3")
    #expect(OpsTokenStats(items: [tokenRow("n", 1, nil, nil)], window: .custom).fastest == nil)
}

/// 40 §5.2: speed and duration weigh by request_count, the first token by requests_with_first_token.
@Test func tokenStatsMergesRowsByRequestAndFirstTokenWeights() throws {
    let merged = try #require(OpsTokenStats.merged([tokenRow("a", 100, 50, 800, withFirstToken: 80, duration: 2_000),
                                                    tokenRow("b", 300, 30, 1_200, withFirstToken: 20, duration: 1_000)]))
    let speed = try #require(merged.tokensPerSecond), firstToken = try #require(merged.firstTokenMs), duration = try #require(merged.durationMs)
    #expect(merged.requestCount == 400)
    #expect(abs(speed - 35) < 1e-9 && abs(firstToken - 880) < 1e-9 && abs(duration - 1_250) < 1e-9)
}

@Test func tokenStatsMergeSkipsNullsAndMatchesByName() {
    let partial = OpsTokenStats.merged([tokenRow("a", 100, nil, 800, withFirstToken: 80, duration: 2_000),
                                        tokenRow("b", 300, 30, nil, withFirstToken: 20, duration: 1_000),
                                        tokenRow("c", 0, 999, 1, duration: 999)])
    #expect(partial == OpsTokenSpeed(requestCount: 400, tokensPerSecond: 30, firstTokenMs: 800, durationMs: 1_250))
    #expect(OpsTokenStats.merged([tokenRow("a", 5, nil, nil), tokenRow("b", 7, nil, nil)])
            == OpsTokenSpeed(requestCount: 12, tokensPerSecond: nil, firstTokenMs: nil, durationMs: nil))
    #expect(OpsTokenStats.merged([tokenRow("a", 5, 10, 300)]) == OpsTokenSpeed(requestCount: 5, tokensPerSecond: 10, firstTokenMs: nil, durationMs: nil))
    #expect(OpsTokenStats.merged([]) == nil)
    let stats = OpsTokenStats(items: [tokenRow("claude-opus-4", 10, 20, 500, withFirstToken: 10, duration: 900), tokenRow("gpt-4.1", 5, 50, nil)],
                              window: .custom)
    #expect(stats.merged(matching: "claude-opus-4") == OpsTokenSpeed(requestCount: 10, tokensPerSecond: 20, firstTokenMs: 500, durationMs: 900))
    #expect(stats.merged(matching: "gpt-5") == nil)
}

@Test func tokenWindowUsesPageRangeWithCustomCapability() {
    let utc = OpsChartStubs.utc, now = OpsChartStubs.now
    func select(_ start: Date, _ end: Date = OpsChartStubs.now) -> OpsTokenStatsWindow {
        OpsTokenStatsWindow.select(start: start, end: end, now: now, zone: OpsChartStubs.zone, supportsCustomRange: true)
    }
    for start in [OpsChartStubs.today, OpsChartStubs.lastSevenDays, utc("2026-09-16T16:00:00Z")] { #expect(select(start) == .custom) }
    #expect(select(utc("2026-07-31T16:00:00Z"), utc("2026-08-31T16:00:00Z")) == .custom)
    let longest = now.addingTimeInterval(-(31 * 86_400 + 3_600))
    #expect(select(longest) == .custom)
    #expect(select(longest.addingTimeInterval(-1)) == .rolling(.thirtyDays, coversRange: false))
    #expect(OpsTokenStatsWindow.maxCustomSpan == 31 * 86_400 + 3_600)
}

/// (site now, range start, range end, window) in Asia/Shanghai without `ops.token_stats_custom_range`.
private let rollingWindowCases: [(String, String, String, OpsTokenStatsWindow)] = [
    ("2026-10-16T01:41:00Z", "2026-10-15T16:00:00Z", "2026-10-16T01:41:00Z", .rolling(.day, coversRange: true)),          // 今天
    ("2026-10-16T01:41:00Z", "2026-10-14T16:00:00Z", "2026-10-15T16:00:00Z", .rolling(.fifteenDays, coversRange: true)),  // 昨天
    ("2026-10-16T01:41:00Z", "2026-10-09T16:00:00Z", "2026-10-16T01:41:00Z", .rolling(.fifteenDays, coversRange: true)),  // 近 7 天
    ("2026-10-16T01:41:00Z", "2026-09-16T16:00:00Z", "2026-10-16T01:41:00Z", .rolling(.thirtyDays, coversRange: true)),   // 近 30 天
    ("2026-10-16T01:41:00Z", "2025-10-15T16:00:00Z", "2026-10-16T01:41:00Z", .rolling(.thirtyDays, coversRange: false)),  // 自选 366 天
    ("2026-10-15T16:00:00Z", "2026-09-30T16:00:00Z", "2026-10-15T16:00:00Z", .rolling(.fifteenDays, coversRange: true)),  // 恰好 15 天
    ("2026-10-15T16:00:01Z", "2026-09-30T16:00:00Z", "2026-10-15T16:00:01Z", .rolling(.thirtyDays, coversRange: true)),
    ("2026-10-31T01:41:00Z", "2026-09-30T16:00:00Z", "2026-10-31T01:41:00Z", .rolling(.thirtyDays, coversRange: false))   // 31 日看本月
]

@Test(arguments: rollingWindowCases)
func tokenWindowPicksSmallestCoveringRollingWindow(now: String, start: String, end: String, window: OpsTokenStatsWindow) {
    let utc = OpsChartStubs.utc
    #expect(OpsTokenStatsWindow.select(start: utc(start), end: utc(end), now: utc(now), zone: OpsChartStubs.zone, supportsCustomRange: false) == window)
}

@Test func tokenWindowMeasuresFromFirstDayMidnightInSiteZone() {
    let utc = OpsChartStubs.utc, now = OpsChartStubs.now
    func select(_ start: String, _ zone: ServerTimeZone) -> OpsTokenStatsWindow {
        OpsTokenStatsWindow.select(start: utc(start), end: now, now: now, zone: zone, supportsCustomRange: false)
    }
    // Site 10-15 10:00: 23 hours 41 minutes from the start itself, but 1 day 9 hours 41 minutes from that day's 00:00.
    #expect(select("2026-10-15T02:00:00Z", OpsChartStubs.zone) == .rolling(.fifteenDays, coversRange: true))
    #expect(select("2026-10-15T14:00:00Z", OpsChartStubs.zone) == .rolling(.fifteenDays, coversRange: true))
    #expect(select("2026-10-15T14:00:00Z", OpsChartStubs.newYork) == .rolling(.day, coversRange: true))
}

@Test func tokenWindowTitlesAndFootnotes() {
    let covering = OpsTokenStatsWindow.rolling(.fifteenDays, coversRange: true)
    let uncovered = "统计窗口近 30 天，截至现在：后端最长只到 30 天，盖不住所选范围，这里只是最近 30 天的速度。"
    #expect(OpsTokenStatsWindow.custom.title == nil && covering.title == "近 15 天")
    #expect(OpsTokenStatsWindow.rolling(.day, coversRange: true).title == "近 1 天" && OpsTokenStatsWindow.tooLargeFallback.title == "近 30 天")
    #expect(OpsTokenStatsWindow.tooLargeFallback == .rolling(.thirtyDays, coversRange: false))
    #expect(OpsTokenStatsWindow.Rolling.allCases.map(\.seconds) == [86_400, 1_296_000, 2_592_000])
    #expect(OpsTokenStatsWindow.custom.footnote() == "统计窗口与所选范围一致。")
    #expect(covering.footnote() == "统计窗口近 15 天，截至现在：后端只有 30 分钟、1 小时、1 天、15 天、30 天这几种滚动窗口，这里取能盖住所选范围的最小一个。")
    #expect(OpsTokenStatsWindow.rolling(.thirtyDays, coversRange: false).footnote() == uncovered)
    #expect(OpsTokenStatsWindow.tooLargeFallback.footnote(groupName: "标准组") == uncovered + "只列「标准组」用到的模型。")
    #expect(OpsTokenStatsWindow.custom.footnote(groupName: "") == "统计窗口与所选范围一致。")
}

@Test(arguments: ["latency-histogram", "error-trend", "error-distribution"])
func opsChartsSendPageRangeAndFiltersWithoutMode(chart: String) async throws {
    let transport = ScriptedTransport { _ in okReply("{}") }
    let client = OpsChartStubs.client(transport)
    let requested = OpsQuery(start: OpsChartStubs.today, end: OpsChartStubs.now, groupID: 7, model: "claude-opus-4", modelSource: .requested)
    var mapped = requested
    mapped.modelSource = .mapping
    try await OpsChartStubs.chart(chart, client, requested, supportsModelFilter: false)
    try await OpsChartStubs.chart(chart, client, requested, supportsModelFilter: true)
    try await OpsChartStubs.chart(chart, client, mapped, supportsModelFilter: true)
    let sent = await transport.requests
    try #require(sent.count == 3)
    let range = ["start_time": "2026-10-15T16:00:00Z", "end_time": "2026-10-16T01:41:00Z", "group_id": "7"]
    #expect(sent.allSatisfy { $0.url?.path == "/api/v1/admin/ops/dashboard/\(chart)" && $0.httpMethod == "GET" })
    #expect(sent.allSatisfy { $0.timeoutInterval == RequestTimeout.aggregate })
    #expect(OpsChartStubs.sent(sent[0]) == range)
    #expect(OpsChartStubs.sent(sent[1]) == range.merging(["model": "claude-opus-4", "model_source": "requested"]) { $1 })
    #expect(OpsChartStubs.sent(sent[2]) == range)
}

@Test func opsErrorTrendCarriesBucketAndRequestWindow() async throws {
    let now = OpsChartStubs.now
    let cases: [(String, TimeInterval, OpsBucket, OpsErrorTrend.Grouping)] = [
        (#"{"bucket":"5m","points":[{"bucket_start":"2026-10-16T01:00:00Z","error_count_total":3,"error_count_sla":3}]}"#, 3_600, .fiveMinutes, .hour),
        (#"{"bucket":"weird","points":[]}"#, 3 * 86_400, .hour, .day),
        (#"{"points":[]}"#, 3_600, .minute, .fiveMinutes)
    ]
    for (body, span, bucket, grouping) in cases {
        let transport = ScriptedTransport { _ in okReply(body) }
        let query = OpsQuery(start: now.addingTimeInterval(-span), end: now)
        let trend = try await OpsChartStubs.client(transport).opsErrorTrend(query, supportsModelFilter: false)
        #expect(trend.bucket == bucket && trend.grouping == grouping)
        #expect(trend.windowStart == query.start && trend.windowEnd == query.end)
    }
    let withPoint = cases[0].0
    let transport = ScriptedTransport { _ in okReply(withPoint) }
    let trend = try await OpsChartStubs.client(transport).opsErrorTrend(OpsQuery(start: now.addingTimeInterval(-3_600), end: now), supportsModelFilter: false)
    #expect(trend.totals == OpsErrorCounts(total: 3, sla: 3))
}

@Test func opsChartsRejectEmptyRangeAndSurfaceOpsDisabled() async throws {
    let now = OpsChartStubs.now
    let invalid = [OpsQuery(start: now, end: now), OpsQuery(start: OpsChartStubs.today, end: now, groupID: 0)]
    for chart in OpsChartStubs.charts + ["openai-token-stats"] {
        let idle = ScriptedTransport { _ in okReply("{}") }
        for query in invalid {
            let error = await thrownAPIError { try await OpsChartStubs.chart(chart, OpsChartStubs.client(idle), query) }
            #expect(error?.kind == .validation)
        }
        #expect(await idle.requests.isEmpty)
        let disabled = ScriptedTransport { _ in errorReply(404, reason: "OPS_DISABLED") }
        let error = await thrownAPIError {
            try await OpsChartStubs.chart(chart, OpsChartStubs.client(disabled), OpsQuery(start: OpsChartStubs.today, end: now))
        }
        #expect(error?.kind == .featureDisabled && error?.reason == "OPS_DISABLED" && error?.statusCode == 404)
        #expect(await disabled.requests.count == 1)
    }
}

/// 40 §2.2: the page range, `top_n=100` and `group_id`; no model by default, no paging, no mode.
@Test func tokenStatsSendsCustomRangeWithCapability() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"time_range":"custom","items":[],"total":0}"#) }
    let query = OpsQuery(start: OpsChartStubs.lastSevenDays, end: OpsChartStubs.now, groupID: 7, model: "claude-opus-4", modelSource: .requested)
    let stats = try await OpsChartStubs.client(transport).opsTokenStats(query, supportsCustomRange: true)
    let sent = await transport.requests
    try #require(sent.count == 1)
    #expect(sent[0].url?.path == "/api/v1/admin/ops/dashboard/openai-token-stats" && sent[0].httpMethod == "GET")
    #expect(sent[0].timeoutInterval == RequestTimeout.aggregate)
    #expect(OpsChartStubs.sent(sent[0]) == ["start_time": "2026-10-09T16:00:00Z", "end_time": "2026-10-16T01:41:00Z", "group_id": "7", "top_n": "100"])
    #expect(stats.window == .custom && stats.timeRange == "custom")
}

@Test func tokenStatsUsesRollingWindowWithoutCapability() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"time_range":"1d","items":[]}"#) }
    let client = OpsChartStubs.client(transport)
    let today = try await client.opsTokenStats(OpsQuery(start: OpsChartStubs.today, end: OpsChartStubs.now, groupID: 3), supportsCustomRange: false)
    let week = try await client.opsTokenStats(OpsQuery(start: OpsChartStubs.lastSevenDays, end: OpsChartStubs.now), supportsCustomRange: false)
    let sent = await transport.requests
    try #require(sent.count == 2)
    #expect(OpsChartStubs.sent(sent[0]) == ["group_id": "3", "time_range": "1d", "top_n": "100"])
    #expect(OpsChartStubs.sent(sent[1]) == ["time_range": "15d", "top_n": "100"])
    #expect(today.window == .rolling(.day, coversRange: true) && week.window == .rolling(.fifteenDays, coversRange: true))
}

/// 40 §2.5: one retry with `time_range=30d`, and the footnote says the window cannot cover the range.
@Test func tokenStatsRetriesOnceWithThirtyDaysAfterRangeTooLarge() async throws {
    let tooLarge = errorReply(400, reason: "OPS_TIME_RANGE_TOO_LARGE", extra: #","metadata":{"max_days":"31"}"#)
    let transport = ScriptedTransport(script: [.reply(tooLarge), .reply(okReply(#"{"time_range":"30d","items":[]}"#))])
    let query = OpsQuery(start: OpsChartStubs.lastSevenDays, end: OpsChartStubs.now, groupID: 7)
    let stats = try await OpsChartStubs.client(transport).opsTokenStats(query, supportsCustomRange: true)
    let sent = await transport.requests
    try #require(sent.count == 2)
    #expect(OpsChartStubs.sent(sent[0]) == ["start_time": "2026-10-09T16:00:00Z", "end_time": "2026-10-16T01:41:00Z", "group_id": "7", "top_n": "100"])
    #expect(OpsChartStubs.sent(sent[1]) == ["group_id": "7", "top_n": "100", "time_range": "30d"])
    #expect(stats.window == .tooLargeFallback && stats.window.footnote().contains("盖不住所选范围"))
}

@Test func tokenStatsDoesNotRetryOtherFailures() async {
    let tooLarge = errorReply(400, reason: "OPS_TIME_RANGE_TOO_LARGE")
    let query = OpsQuery(start: OpsChartStubs.lastSevenDays, end: OpsChartStubs.now)
    let cases: [(HTTPResponse, Bool, Int, String?)] = [
        (errorReply(400), true, 1, nil), (errorReply(400, reason: "VALIDATION_ERROR"), true, 1, "VALIDATION_ERROR"),
        (tooLarge, true, 2, "OPS_TIME_RANGE_TOO_LARGE"), (tooLarge, false, 1, "OPS_TIME_RANGE_TOO_LARGE")
    ]
    for (reply, supportsCustomRange, attempts, reason) in cases {
        let transport = ScriptedTransport(script: [.reply(reply)])
        let error = await thrownAPIError {
            _ = try await OpsChartStubs.client(transport).opsTokenStats(query, supportsCustomRange: supportsCustomRange)
        }
        #expect(error?.statusCode == 400 && error?.reason == reason)
        #expect(await transport.requests.count == attempts)
    }
}

@Test func tokenStatsSkipsCustomRangeBeyondThirtyOneDaysAndAnHour() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"time_range":"30d","items":[]}"#) }
    let query = OpsQuery(start: OpsChartStubs.now.addingTimeInterval(-40 * 86_400), end: OpsChartStubs.now)
    let stats = try await OpsChartStubs.client(transport).opsTokenStats(query, supportsCustomRange: true)
    let sent = await transport.requests
    try #require(sent.count == 1)
    #expect(OpsChartStubs.sent(sent[0]) == ["time_range": "30d", "top_n": "100"])
    #expect(stats.window == .rolling(.thirtyDays, coversRange: false))
}

/// 40 §5.2: the model page asks for ten rows and passes its model only with `ops.dashboard_model_filter`.
@Test func tokenStatsModelPagePassesModelAndTopN() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"items":[]}"#) }
    let client = OpsChartStubs.client(transport)
    let query = OpsQuery(start: OpsChartStubs.today, end: OpsChartStubs.now, model: "claude-opus-4", modelSource: .upstream)
    _ = try await client.opsTokenStats(query, topN: 10, supportsCustomRange: true, supportsModelFilter: true)
    _ = try await client.opsTokenStats(query, topN: 10, supportsCustomRange: true, supportsModelFilter: false)
    _ = try await client.opsTokenStats(query, topN: 500, supportsCustomRange: true)
    _ = try await client.opsTokenStats(query, topN: 0, supportsCustomRange: true)
    let sent = await transport.requests.map { OpsChartStubs.sent($0) }
    try #require(sent.count == 4)
    let range = ["start_time": "2026-10-15T16:00:00Z", "end_time": "2026-10-16T01:41:00Z"]
    #expect(sent[0] == range.merging(["model": "claude-opus-4", "model_source": "upstream", "top_n": "10"]) { $1 })
    #expect(sent[1] == range.merging(["top_n": "10"]) { $1 })
    #expect(sent.map { $0["top_n"] } == ["10", "10", "100", "1"])
}

/// U35: the start is earlier than the same moment 30 site days ago; the range itself is not cut.
@Test func retentionHintWhenRangeStartsBeforeThirtyDays() {
    let utc = OpsChartStubs.utc, now = utc("2026-10-31T01:41:00Z")
    func trimmed(_ start: Date) -> Bool { OpsRetention.mayBeTrimmed(rangeStart: start, now: now, zone: OpsChartStubs.zone) }
    #expect(trimmed(utc("2026-09-30T16:00:00Z")))   // 本月，起点 10-01 00:00
    #expect(!trimmed(utc("2026-10-01T16:00:00Z")))  // 近 30 天，起点 10-02 00:00
    let cutoff = utc("2026-10-01T01:41:00Z")
    #expect(!trimmed(cutoff) && trimmed(cutoff.addingTimeInterval(-1)))
    // Across the end of daylight saving the calendar month is 30 days and an hour.
    #expect(!OpsRetention.mayBeTrimmed(rangeStart: utc("2026-10-16T16:30:00Z"), now: utc("2026-11-15T17:00:00Z"), zone: OpsChartStubs.newYork))
    #expect(OpsRetention.hint == "运维日志默认只保留 30 天，更早的时段可能没有记录" && OpsRetention.defaultDays == 30)
}
