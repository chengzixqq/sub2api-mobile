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
