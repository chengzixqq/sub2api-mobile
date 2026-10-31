import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let newYork = ServerTimeZone(identifier: "America/New_York", utcOffset: "-04:00")!
private let homeOwner = ConditionalCache.Identity(userID: 1, authMethod: "admin_api_key")
private let minimalHome = #"{"generated_at":"2026-10-23T02:04:05Z","stats":{"status":"ok","data":{"today_requests":5}}}"#
private let ratesJSON = #"{"window_seconds":300,"start_time":"2026-10-23T01:59:05Z","end_time":"2026-10-23T02:04:05Z","rpm":46.2,"tpm":240000,"error_rate":0.0086,"upstream_429_count":3,"upstream_529_count":0,"ops_monitoring_enabled":true,"errors_available":true,"rpm_includes_errors":true}"#

/// The client's own zone is New York, so a request carrying Shanghai can only have come from the argument.
private func homeClient(_ transport: ScriptedTransport, identity: ConditionalCache.Identity? = nil) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate,
              cacheIdentity: identity, serverTimeZone: newYork)
}
private func sentQuery(_ request: URLRequest?) -> [String: String] {
    let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
/// Answers like writeConditionalETag: 200 with the ETag until the request sends it back, then an empty 304.
private func revalidating(_ json: String, etag: String = "\"h1\"") -> ScriptedTransport {
    ScriptedTransport { request in
        sentHeader(request, "If-None-Match") == etag ? HTTPResponse(statusCode: 304, headers: ["etag": etag], data: Data())
            : okReply(json, headers: ["etag": etag])
    }
}
private func validators(_ transport: ScriptedTransport) async -> [String?] { await transport.requests.map { sentHeader($0, "If-None-Match") } }

@Test func homeSendsServerZoneIdentifierWithoutIncludeOrNocache() async throws {
    let transport = ScriptedTransport { _ in okReply(minimalHome) }
    let home = try await homeClient(transport).dashboardHome(timezone: shanghai)
    let sent = await transport.requests
    #expect(sent.count == 1 && sent[0].httpMethod == "GET" && sent[0].url?.path == "/api/v1/admin/dashboard/home")
    #expect(sentQuery(sent.first) == ["timezone": "Asia/Shanghai"])
    #expect(sent[0].timeoutInterval == RequestTimeout.home && RequestTimeout.home == 15)
    #expect(home.stats.status == .ok && home.stats.data?.todayRequests == 5 && home.rates == .missing)
}

@Test func homeSendsBackendLocalZoneVerbatim() async throws {
    let transport = ScriptedTransport { _ in okReply(minimalHome) }
    let client = homeClient(transport)
    _ = try await client.dashboardHome(timezone: try #require(ServerTimeZone(identifier: "Local", utcOffset: "+05:30")))
    _ = try await client.dashboardHome(timezone: try #require(ServerTimeZone(identifier: "Asia/Kolkata", utcOffset: nil)))
    #expect(await transport.requests.map { sentQuery($0)["timezone"] } == ["Local", "Asia/Kolkata"])
}

@Test func homeNoCacheAddsNocacheOne() async throws {
    let transport = ScriptedTransport { _ in okReply(minimalHome) }
    let client = homeClient(transport)
    _ = try await client.dashboardHome(timezone: shanghai, noCache: true)
    _ = try await client.dashboardHome(timezone: shanghai, noCache: false)
    let sent = await transport.requests
    #expect(sentQuery(sent[0]) == ["timezone": "Asia/Shanghai", "nocache": "1"])
    #expect(sentQuery(sent[1]) == ["timezone": "Asia/Shanghai"])
}

@Test func homeIncludeIsOrderedAndDeduplicated() async throws {
    let transport = ScriptedTransport { _ in okReply(minimalHome) }
    let client = homeClient(transport)
    _ = try await client.dashboardHome(timezone: shanghai, include: [.alerts, .stats, .alerts])
    _ = try await client.dashboardHome(timezone: shanghai, include: [])
    _ = try await client.dashboardHome(timezone: shanghai, include: nil)
    #expect(await transport.requests.map { sentQuery($0)["include"] } == ["stats,alerts", nil, nil])
}

@Test func invalidTimezoneResendsOnceWithoutTimezone() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(400, reason: "INVALID_TIMEZONE")), .reply(okReply(minimalHome))])
    let home = try await homeClient(transport).dashboardHome(timezone: shanghai, include: [.stats], noCache: true)
    let sent = await transport.requests
    #expect(sent.count == 2 && home.stats.data?.todayRequests == 5)
    #expect(sentQuery(sent[0]) == ["timezone": "Asia/Shanghai", "include": "stats", "nocache": "1"])
    #expect(sentQuery(sent[1]) == ["include": "stats", "nocache": "1"])
}

@Test func invalidTimezoneIsResentOnlyOnce() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(400, reason: "INVALID_TIMEZONE"))])
    let error = await thrownAPIError { _ = try await homeClient(transport).dashboardHome(timezone: shanghai) }
    #expect(error?.statusCode == 400 && error?.reason == "INVALID_TIMEZONE")
    #expect(await transport.requests.count == 2)
}

@Test func invalidIncludeResendsOnceWithoutInclude() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(400, reason: "INVALID_INCLUDE")), .reply(okReply(minimalHome))])
    _ = try await homeClient(transport).dashboardHome(timezone: shanghai, include: [.stats])
    let sent = await transport.requests
    #expect(sent.count == 2 && sentQuery(sent[1]) == ["timezone": "Asia/Shanghai"])

    let unasked = ScriptedTransport(script: [.reply(errorReply(400, reason: "INVALID_INCLUDE")), .reply(okReply(minimalHome))])
    let error = await thrownAPIError { _ = try await homeClient(unasked).dashboardHome(timezone: shanghai) }
    #expect(error?.statusCode == 400 && error?.reason == "INVALID_INCLUDE")
    #expect(await unasked.requests.count == 1)
}

@Test func bothParameterErrorsResendEachOnce() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(400, reason: "INVALID_TIMEZONE")), .reply(errorReply(400, reason: "INVALID_INCLUDE")),
                                               .reply(okReply(minimalHome))])
    _ = try await homeClient(transport).dashboardHome(timezone: shanghai, include: [.stats])
    let sent = await transport.requests
    #expect(sent.count == 3 && sentQuery(sent[1]) == ["include": "stats"] && sentQuery(sent[2]).isEmpty)

    let stubborn = ScriptedTransport(script: [.reply(errorReply(400, reason: "INVALID_TIMEZONE")), .reply(errorReply(400, reason: "INVALID_INCLUDE")),
                                              .reply(errorReply(400, reason: "INVALID_TIMEZONE"))])
    let error = await thrownAPIError { _ = try await homeClient(stubborn).dashboardHome(timezone: shanghai, include: [.stats]) }
    #expect(error?.reason == "INVALID_TIMEZONE")
    #expect(await stubborn.requests.count == 3)
}

private let otherRefusals: [(Int, String?)] = [(400, "INVALID_GROUP_FILTER"), (400, nil), (403, "FORBIDDEN")]

@Test(arguments: otherRefusals)
func otherBadRequestsAreNotResent(status: Int, reason: String?) async throws {
    let transport = ScriptedTransport { _ in errorReply(status, reason: reason) }
    let error = await thrownAPIError { _ = try await homeClient(transport).dashboardHome(timezone: shanghai, include: [.stats]) }
    #expect(error?.statusCode == status && error?.reason == reason)
    #expect(await transport.requests.count == 1)
}

@Test func homeNotModifiedReturnsCachedModel() async throws {
    let transport = revalidating(minimalHome)
    let client = homeClient(transport, identity: homeOwner)
    let first = try await client.dashboardHome(timezone: shanghai)
    let second = try await client.dashboardHome(timezone: shanghai)
    #expect(second == first && second.generatedAt == ServerTime.parseTimestamp("2026-10-23T02:04:05Z"))
    #expect(await validators(transport) == [nil, "\"h1\""])
}

@Test func homeNoCacheUsesItsOwnConditionalKey() async throws {
    let transport = revalidating(minimalHome)
    let client = homeClient(transport, identity: homeOwner)
    _ = try await client.dashboardHome(timezone: shanghai)
    _ = try await client.dashboardHome(timezone: shanghai, noCache: true)
    _ = try await client.dashboardHome(timezone: shanghai, noCache: true)
    #expect(await validators(transport) == [nil, nil, "\"h1\""])
}

@Test func ratesRequestUsesWindowAndPlainReadTimeout() async throws {
    let transport = ScriptedTransport { _ in okReply(ratesJSON, headers: ["etag": "\"r1\""]) }
    let client = homeClient(transport, identity: homeOwner)
    let rates = try await client.dashboardRates()
    _ = try await client.dashboardRates(window: .oneMinute)
    let sent = await transport.requests
    #expect(sent.count == 2 && sent[0].httpMethod == "GET" && sent[0].url?.path == "/api/v1/admin/dashboard/rates")
    #expect(sent.map { sentQuery($0) } == [["window": "5m"], ["window": "1m"]])
    #expect(sent[0].timeoutInterval == RequestTimeout.read && RequestTimeout.read == 20)
    #expect(await validators(transport) == [nil, nil])
    #expect(rates.rpm == 46.2 && rates.tpm == 240_000 && rates.errorRate == 0.0086 && rates.startTime == ServerTime.parseTimestamp("2026-10-23T01:59:05Z"))
    #expect(LiveRatesWindow.allCases.map(\.rawValue) == ["1m", "5m", "15m"])
}

// S1-05: the error accounts' structured fields (10 §1.2 附加请求), read through R19's one account list query.

private let errorAccountsPage = #"{"items":[{"id":7,"name":"OpenAI-备用-A","platform":"openai","type":"apikey","status":"error","schedulable":false,"error_message":"raw upstream text","error_at":"2026-10-23T02:03:05Z","error_status_code":401,"error_kind":"auth","error_summary":"401 凭据已失效（invalid_api_key）"},{"id":9,"name":"Kimi-01","platform":"kimi","type":"apikey","status":"error","schedulable":false}],"total":230,"page":1,"page_size":100,"pages":3}"#

@Test func errorAccountsSendsErrorStatusLitePageSize100OnFirstPage() async throws {
    let transport = ScriptedTransport { _ in okReply(errorAccountsPage) }
    _ = try await homeClient(transport).errorAccounts()
    let sent = await transport.requests
    #expect(sent.count == 1 && sent[0].httpMethod == "GET" && sent[0].url?.path == "/api/v1/admin/accounts")
    let query = sentQuery(sent.first)
    #expect(query["page"] == "1" && query["page_size"] == "100" && query["status"] == "error" && query["lite"] == "1")
    #expect(query["include_counts"] == nil && query["sort_by"] != "urgency")
}

@Test func errorAccountsDecodesStructuredErrorFieldsAndReturnsFirstPageItems() async throws {
    let transport = ScriptedTransport { _ in okReply(errorAccountsPage) }
    let accounts = try await homeClient(transport).errorAccounts()
    #expect(accounts.map(\.id) == [7, 9])
    #expect(await transport.requests.count == 1)
    let first = try #require(accounts.first)
    #expect(first.errorAt == "2026-10-23T02:03:05Z" && first.errorStatusCode == 401 && first.errorKind == "auth")
    #expect(first.errorSummary == "401 凭据已失效（invalid_api_key）" && accounts[1].errorSummary == nil)
}

@Test func errorAccountsReusesConditionalCacheOn304() async throws {
    let transport = revalidating(errorAccountsPage, etag: "\"a1\"")
    let client = homeClient(transport, identity: homeOwner)
    let first = try await client.errorAccounts()
    let second = try await client.errorAccounts()
    #expect(second.map(\.id) == first.map(\.id) && second.first?.errorSummary == first.first?.errorSummary)
    #expect(await validators(transport) == [nil, "\"a1\""])
}
