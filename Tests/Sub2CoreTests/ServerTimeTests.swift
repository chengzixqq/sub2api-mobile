import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let utcZone = ServerTimeZone(identifier: "UTC", utcOffset: "+00:00")!
private func zone(_ identifier: String) -> TimeZone { TimeZone(identifier: identifier)! }
private func query(_ request: URLRequest?) -> [String: String] {
    guard let url = request?.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
private func timeClient(_ transport: ScriptedTransport, zone: ServerTimeZone = .device, clock: ServerClock = ServerClock(),
                        identity: ConditionalCache.Identity? = nil) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate,
              cacheIdentity: identity, serverTimeZone: zone, serverClock: clock)
}
private let emptyTrend = okReply(#"{"trend":[]}"#)

// MARK: Server time zone (00 §6.3)

@Test func serverTimeZoneResolvesFromAdminMeThenPublicSettings() throws {
    let me = AdminMe(server: .init(serverTimezone: "Asia/Shanghai", serverUTCOffset: "+08:00"))
    let settings = try JSONDecoder().decode(PublicSettings.self, from: Data(#"{"server_timezone":"UTC","server_utc_offset":"+00:00"}"#.utf8))
    #expect(ServerTimeZone.resolve(me: me, publicSettings: settings)?.identifier == "Asia/Shanghai")
    #expect(ServerTimeZone.resolve(me: AdminMe(), publicSettings: settings)?.identifier == "UTC")
    #expect(ServerTimeZone.resolve(me: nil, publicSettings: settings)?.identifier == "UTC")
    #expect(ServerTimeZone.resolve(me: AdminMe(), publicSettings: nil) == nil)
    #expect(ServerTimeZone.resolve(me: nil, publicSettings: nil) == nil)
    #expect(ServerTimeZone.resolve(me: me, publicSettings: nil)?.timeZone.identifier == "Asia/Shanghai")
}

@Test func unknownIdentifierFallsBackToUTCOffsetButIsSentVerbatim() throws {
    let local = try #require(ServerTimeZone(identifier: "Local", utcOffset: "+05:30"))
    #expect(local.identifier == "Local")
    #expect(local.timeZone.secondsFromGMT(for: utc("2026-10-18T01:41:00Z")) == 19_800)
    #expect(local.dayQueryItems(from: utc("2026-10-18T01:41:00Z"), to: utc("2026-10-18T01:41:00Z")).last == URLQueryItem(name: "timezone", value: "Local"))
    #expect(ServerTimeZone(identifier: "Invalid/Zone", utcOffset: "bad") == nil)
    #expect(ServerTimeZone(identifier: "Local", utcOffset: nil) == nil)
    #expect(ServerTimeZone(identifier: nil, utcOffset: "+08:00") == nil)
    #expect(ServerTimeZone(identifier: "  ", utcOffset: "+08:00") == nil)
}

@Test(arguments: [("+08:00", 28_800), ("-03:30", -12_600), ("+00:00", 0), ("+14:00", 50_400), ("+05:45", 20_700)])
func utcOffsetParsing(raw: String, seconds: Int) {
    #expect(ServerTimeZone.parseUTCOffset(raw) == seconds)
}

@Test(arguments: ["+8", "Z", "abc", "", "+08:60", "+19:00", "08:00", "+0800"])
func utcOffsetRejectsMalformed(raw: String) {
    #expect(ServerTimeZone.parseUTCOffset(raw) == nil)
    #expect(ServerTimeZone.parseUTCOffset(nil) == nil)
}

@Test(arguments: [("Asia/Shanghai", "UTC+8"), ("Asia/Kolkata", "UTC+5:30"), ("America/Sao_Paulo", "UTC\u{2212}3"), ("UTC", "UTC+0"),
                  ("Asia/Kathmandu", "UTC+5:45")])
func offsetLabelFormats(identifier: String, label: String) throws {
    let site = try #require(ServerTimeZone(identifier: identifier, utcOffset: nil))
    #expect(site.offsetLabel(at: utc("2026-10-18T01:41:00Z")) == label)
}

@Test func zoneHintsOnlyWhenDeviceOffsetDiffers() {
    let at = utc("2026-10-18T01:41:00Z")
    let newYork = zone("America/New_York")
    #expect(shanghai.differsFromDevice(newYork, at: at))
    #expect(shanghai.overviewSuffix(device: newYork, at: at) == "· 按 UTC+8")
    #expect(shanghai.siteTimeSuffix(device: newYork, at: at) == "（站点时间 UTC+8）")
    #expect(shanghai.settingsNote(device: newYork, at: at) == "时间按服务器时区（UTC+8）显示")
    for device in [zone("Asia/Shanghai"), zone("Asia/Singapore")] {
        #expect(!shanghai.differsFromDevice(device, at: at))
        #expect(shanghai.overviewSuffix(device: device, at: at) == nil)
        #expect(shanghai.siteTimeSuffix(device: device, at: at) == nil)
        #expect(shanghai.settingsNote(device: device, at: at) == nil)
    }
}

@Test func dayQueryItemsUseServerCalendar() {
    let at = utc("2026-10-17T17:30:00Z")
    #expect(shanghai.dayQueryItems(from: at, to: at) == [URLQueryItem(name: "start_date", value: "2026-10-18"),
                                                        URLQueryItem(name: "end_date", value: "2026-10-18"),
                                                        URLQueryItem(name: "timezone", value: "Asia/Shanghai")])
    #expect(utcZone.dayQueryItems(from: at, to: at).first == URLQueryItem(name: "start_date", value: "2026-10-17"))
    #expect(shanghai.dayString(at).utf8.allSatisfy { $0 < 128 })
    #expect(shanghai.calendar.timeZone == zone("Asia/Shanghai"))
    #expect(shanghai.calendar.identifier == .gregorian)
}

@Test func lastDaysAndMonthToDateFollowServerDayBoundary() {
    let now = utc("2026-10-31T16:30:00Z")
    #expect(shanghai.monthToDateQueryItems(now: now).prefix(2) == [URLQueryItem(name: "start_date", value: "2026-11-01"),
                                                                     URLQueryItem(name: "end_date", value: "2026-11-01")])
    #expect(shanghai.lastDaysQueryItems(1, now: now).prefix(2) == [URLQueryItem(name: "start_date", value: "2026-10-31"),
                                                                     URLQueryItem(name: "end_date", value: "2026-11-01")])
    #expect(utcZone.monthToDateQueryItems(now: now).prefix(2) == [URLQueryItem(name: "start_date", value: "2026-10-01"),
                                                                    URLQueryItem(name: "end_date", value: "2026-10-31")])
}

// MARK: Encoding and parsing (00 §2.8, §6.4)

@Test func utcTimestampNeverCarriesOffset() {
    let date = utc("2026-10-18T01:41:00Z").addingTimeInterval(0.25)
    #expect(ServerTime.utcTimestamp(date) == "2026-10-18T01:41:00Z")
    let items = ServerTime.timeRangeItems(start: date, end: date.addingTimeInterval(3_600))
    #expect(items.map(\.name) == ["start_time", "end_time"])
    #expect(items.allSatisfy { $0.value?.hasSuffix("Z") == true && $0.value?.contains("+") == false })
}

@Test(arguments: ["2026-10-18T09:41:00+08:00", "2026-10-18T01:41:00Z", "2026-10-18T09:41:00.123+08:00",
                  "2026-10-18T09:41:00.123456789+08:00", "2026-10-17T20:41:00-05:00", "2026-10-18T01:41:00.5Z",
                  "2026-10-18T01:41:00.123456Z"])
func parseTimestampAcceptsRFC3339Variants(raw: String) throws {
    let parsed = try #require(ServerTime.parseTimestamp(raw))
    #expect(abs(parsed.timeIntervalSince(utc("2026-10-18T01:41:00Z"))) < 0.6)
}

@Test func parseTimestampKeepsMilliseconds() throws {
    let parsed = try #require(ServerTime.parseTimestamp("2026-10-18T09:41:00.123456789+08:00"))
    #expect(abs(parsed.timeIntervalSince(utc("2026-10-18T01:41:00Z")) - 0.123) < 0.001)
}

@Test func parseTimestampRejectsInvalid() {
    for raw in [nil, "", "2026-10-18 09:41:00", "garbage", "2026-10-18"] { #expect(ServerTime.parseTimestamp(raw) == nil) }
}

private struct TimeFields: Decodable {
    let expiresAt: Date?
    let createdAt: Date?
    enum CodingKeys: String, CodingKey { case expiresAt = "expires_at", createdAt = "created_at" }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expiresAt = try c.optionalUnixTime(.expiresAt); createdAt = try c.optionalTimestamp(.createdAt)
    }
}

@Test func unixSecondsAndLenientContainerDecoding() throws {
    #expect(ServerTime.date(unixSeconds: 1_792_026_000) == Date(timeIntervalSince1970: 1_792_026_000))
    for value: Int64? in [nil, 0, -1] { #expect(ServerTime.date(unixSeconds: value) == nil) }
    let full = try JSONDecoder().decode(TimeFields.self, from: Data(#"{"expires_at":1792026000,"created_at":"2026-10-18T09:41:00+08:00"}"#.utf8))
    #expect(full.expiresAt == Date(timeIntervalSince1970: 1_792_026_000))
    #expect(full.createdAt == utc("2026-10-18T01:41:00Z"))
    for json in [#"{"expires_at":null,"created_at":null}"#, "{}", #"{"expires_at":"bad","created_at":"bad"}"#, #"{"expires_at":0,"created_at":17}"#] {
        let empty = try JSONDecoder().decode(TimeFields.self, from: Data(json.utf8))
        #expect(empty.expiresAt == nil); #expect(empty.createdAt == nil)
    }
}

@Test func httpDateHeaderParses() {
    #expect(ServerTime.parseHTTPDate("Sun, 18 Oct 2026 01:41:00 GMT") == utc("2026-10-18T01:41:00Z"))
    for raw in [nil, "", "bad", "D1"] { #expect(ServerTime.parseHTTPDate(raw) == nil) }
}

@Test func queryMetadataDecodesLeniently() throws {
    let full = try JSONDecoder().decode(QueryMetadata.self, from: Data(#"{"timezone":"Asia/Shanghai","start_time":"2026-10-17T16:00:00Z","end_time":"bad","generated_at":"2026-10-18T09:41:00.5+08:00"}"#.utf8))
    #expect(full.timezone == "Asia/Shanghai"); #expect(full.startTime == utc("2026-10-17T16:00:00Z")); #expect(full.endTime == nil)
    #expect(full.generatedAt != nil)
    let empty = try JSONDecoder().decode(QueryMetadata.self, from: Data("{}".utf8))
    #expect(empty.timezone == nil); #expect(empty.startTime == nil)
}

// MARK: Clock offset (00 §6.3)

@Test func clockAppliesDateHeaderOffset() {
    let local = utc("2026-10-18T01:41:00Z")
    let clock = ServerClock(localNow: { local })
    #expect(clock.offset == 0); #expect(clock.now() == local); #expect(clock.localNow() == local)
    clock.recordDateHeader("Sun, 18 Oct 2026 01:41:30 GMT", receivedAt: local)
    #expect(clock.offset == 30); #expect(clock.now() == local.addingTimeInterval(30))
    clock.recordDateHeader("bad", receivedAt: local)
    clock.recordDateHeader(nil, receivedAt: local)
    #expect(clock.offset == 30)
    #expect(ServerClock(offset: -5, localNow: { local }).now() == local.addingTimeInterval(-5))
}

@Test func sampledAtSampleGivesBlockBaseline() {
    let local = utc("2026-10-18T01:41:00Z"), sampled = utc("2026-10-18T01:40:50Z")
    let clock = ServerClock(localNow: { local })
    let sample = clock.record(sampledAt: sampled, receivedAt: local)
    #expect(sample.offset == -10)
    #expect(sample.serverNow(localNow: local.addingTimeInterval(10)) == sampled.addingTimeInterval(10))
    #expect(clock.offset == -10)
}

@Test func bucketTimeZonePrefersResponseQueryTimezone() throws {
    #expect(ServerTime.bucketTimeZone(reported: "UTC", requested: shanghai) == zone("UTC"))
    for reported in [nil, "", "Invalid/Zone"] { #expect(ServerTime.bucketTimeZone(reported: reported, requested: shanghai) == zone("Asia/Shanghai")) }
    let local = try #require(ServerTimeZone(identifier: "Local", utcOffset: "+05:30"))
    #expect(ServerTime.bucketTimeZone(reported: "Local", requested: local).secondsFromGMT() == 19_800)
    #expect(DashboardPresentation.trendDate("2026-10-15 08:00", timeZone: zone("Asia/Shanghai")) == utc("2026-10-15T00:00:00Z"))
}

// MARK: APIClient wiring

@Test func apiClientDatesUseInjectedServerZoneAndClock() async throws {
    let transport = ScriptedTransport { _ in emptyTrend }
    let clock = ServerClock(offset: 3_600, localNow: { utc("2026-10-31T15:50:00Z") })
    let client = timeClient(transport, zone: shanghai, clock: clock)
    _ = try await client.dashboardTrend()
    _ = try? await client.userUsage(id: 7)
    _ = try? await client.dashboardCostSnapshot()
    let trend = query(await transport.requests(path: "/dashboard/trend").first)
    #expect(trend["start_date"] == "2026-10-31"); #expect(trend["end_date"] == "2026-11-01"); #expect(trend["timezone"] == "Asia/Shanghai")
    let usage = query(await transport.requests(path: "/usage/stats").first)
    #expect(usage["start_date"] == "2026-11-01"); #expect(usage["end_date"] == "2026-11-01"); #expect(usage["timezone"] == "Asia/Shanghai")
    let cost = query(await transport.requests(path: "/snapshot-v2").first)
    #expect(cost["start_date"] == "2026-11-01"); #expect(cost["end_date"] == "2026-11-01")
    #expect(await client.serverTimeZone() == shanghai)
    #expect(client.serverClock === clock)
}

@Test func setServerTimeZoneChangesSubsequentDayBoundaries() async throws {
    let transport = ScriptedTransport { _ in emptyTrend }
    let client = timeClient(transport, zone: shanghai, clock: ServerClock(offset: 3_600, localNow: { utc("2026-10-31T15:50:00Z") }))
    await client.setServerTimeZone(utcZone)
    _ = try await client.dashboardTrend()
    _ = try? await client.userUsage(id: 7)
    let trend = query(await transport.requests(path: "/dashboard/trend").first)
    #expect(trend["start_date"] == "2026-10-30"); #expect(trend["end_date"] == "2026-10-31"); #expect(trend["timezone"] == "UTC")
    let usage = query(await transport.requests(path: "/usage/stats").first)
    #expect(usage["start_date"] == "2026-10-01"); #expect(usage["end_date"] == "2026-10-31")
}

@Test func apiClientDefaultsToDeviceZoneUntilConfigured() async throws {
    let transport = ScriptedTransport { _ in emptyTrend }
    let client = timeClient(transport)
    _ = try await client.dashboardTrend()
    #expect(query(await transport.requests.first)["timezone"] == TimeZone.current.identifier)
    #expect(await client.serverTimeZone().identifier == TimeZone.current.identifier)
}

@Test func meResponseUpdatesServerZone() async throws {
    let transport = ScriptedTransport { request in
        if request.url?.path == "/api/v1/admin/me" {
            return okReply(#"{"auth_method":"admin_api_key","server":{"server_timezone":"America/New_York","server_utc_offset":"-04:00"}}"#)
        }
        return emptyTrend
    }
    let client = timeClient(transport, zone: shanghai)
    _ = try await client.me()
    #expect(await client.serverTimeZone().identifier == "America/New_York")
    _ = try await client.dashboardTrend()
    #expect(query(await transport.requests(path: "/dashboard/trend").first)["timezone"] == "America/New_York")
}

@Test func meWithoutTimeZoneKeepsTheConfiguredZone() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"auth_method":"admin_api_key","server":{}}"#) }
    let client = timeClient(transport, zone: shanghai)
    _ = try await client.me()
    #expect(await client.serverTimeZone() == shanghai)
}

@Test func apiClientRecordsDateHeaderFromEveryResponseIncludingErrors() async throws {
    let local = utc("2026-10-18T01:41:00Z")
    let ahead = ["date": "Sun, 18 Oct 2026 01:43:00 GMT"]
    let transport = ScriptedTransport(script: [
        .reply(okReply(stubUserJSON, headers: ahead)),
        .reply(HTTPResponse(statusCode: 404, headers: ["date": "Sun, 18 Oct 2026 01:42:00 GMT"], data: Data("404 page not found".utf8))),
        .reply(errorReply(401, reason: "INVALID_API_KEY", headers: ahead)),
        .reply(okReply(stubUserJSON))
    ])
    let clock = ServerClock(localNow: { local })
    let client = timeClient(transport, clock: clock)
    _ = try await client.user(id: 7)
    #expect(clock.offset == 120)
    _ = await thrownAPIError { _ = try await client.user(id: 7) }
    #expect(clock.offset == 60)
    _ = await thrownAPIError { _ = try await client.user(id: 7) }
    #expect(clock.offset == 120)
    _ = try await client.user(id: 7)
    #expect(clock.offset == 120)
}

@Test func refreshResponsesAlsoUpdateTheClock() async throws {
    let local = utc("2026-10-18T01:41:00Z")
    let transport = ScriptedTransport { request in
        isRefresh(request) ? okReply(stubRefreshJSON, headers: ["date": "Sun, 18 Oct 2026 01:41:45 GMT"]) : okReply(stubUserJSON)
    }
    let clock = ServerClock(localNow: { local })
    let client = APIClient(server: stubServer(), credential: stubTokens(expiresAt: Date().addingTimeInterval(-60)), transport: transport,
                           requestClock: .immediate, serverClock: clock)
    _ = try await client.user(id: 7)
    #expect(clock.offset == 45)
}

@Test func timeQueryNeverContainsPlusOffset() async throws {
    let transport = ScriptedTransport { _ in okReply("{}") }
    let client = timeClient(transport, zone: shanghai)
    let end = utc("2026-10-18T01:41:00Z")
    _ = try? await client.dashboardPerformanceTrend(start: end.addingTimeInterval(-3_600), end: end)
    _ = try? await client.usageAnalysis(AnalyticsQuery(start: end.addingTimeInterval(-86_400), end: end, timeZone: "Asia/Shanghai"))
    _ = try? await client.requestRecords(page: 1, filter: RequestLogFilter(time: .range(end.addingTimeInterval(-86_400), end)), maskedView: false)
    let requests = await transport.requests
    #expect(requests.count == 3)
    for request in requests {
        let raw = try #require(request.url?.query)
        #expect(!raw.contains("+08:00")); #expect(!raw.contains("%2B08"))
        let items = query(request)
        #expect(items["start_time"]?.hasSuffix("Z") == true); #expect(items["end_time"]?.hasSuffix("Z") == true)
    }
    #expect(query(requests.first)["end_time"] == "2026-10-18T01:41:00Z")
}

@Test func plusSignInQueryValueIsPercentEncodedAndCacheKeysAgree() async throws {
    let etag = "\"p1\""
    let page = "{\"items\":[\(stubUserJSON)],\"total\":1,\"page\":1,\"page_size\":20,\"pages\":1}"
    let transport = ScriptedTransport { request in
        sentHeader(request, "If-None-Match") == etag ? HTTPResponse(statusCode: 304, headers: ["etag": etag], data: Data())
            : okReply(page, headers: ["etag": etag])
    }
    let client = timeClient(transport, identity: ConditionalCache.Identity(userID: 1, authMethod: "admin_api_key"))
    _ = try await client.users(query: UserListQuery(search: "a+b@example.invalid"))
    let cached = try await client.users(query: UserListQuery(search: "a+b@example.invalid"))
    #expect(cached.items.count == 1)
    let requests = await transport.requests
    #expect(requests.map { sentHeader($0, "If-None-Match") } == [nil, etag])
    for request in requests {
        let url = try #require(request.url)
        let encoded = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
        #expect(encoded.contains("a%2Bb")); #expect(!encoded.contains("a+b"))
        #expect(query(request)["search"] == "a+b@example.invalid")
    }
    let built = try await client.endpointURL("admin/users", query: [URLQueryItem(name: "search", value: "1+1")])
    #expect(built.absoluteString.hasSuffix("?search=1%2B1"))
}

@Test func dashboardTrendParsesBucketsInResponseOrRequestZone() async throws {
    let bucket = #"{"date":"2026-10-15 08:00","requests":1,"total_tokens":2,"cost":"0.1","actual_cost":"0.05"}"#
    let reported = ScriptedTransport { _ in okReply(#"{"trend":[\#(bucket)],"query":{"timezone":"Asia/Shanghai","generated_at":"2026-10-15T09:00:00+08:00"}}"#) }
    let reply = try await timeClient(reported, zone: utcZone).dashboardTrend()
    #expect(reply.timeZone == zone("Asia/Shanghai"))
    let series = DashboardTrend.series(reply.points, timeZone: reply.timeZone)
    #expect(series.samples.first?.date == utc("2026-10-15T00:00:00Z"))
    #expect(series.timeZone == zone("Asia/Shanghai"))
    let silent = ScriptedTransport { _ in okReply(#"{"trend":[\#(bucket)],"query":"unexpected"}"#) }
    let fallback = try await timeClient(silent, zone: utcZone).dashboardTrend()
    #expect(fallback.timeZone == zone("UTC")); #expect(fallback.points.count == 1)
}
