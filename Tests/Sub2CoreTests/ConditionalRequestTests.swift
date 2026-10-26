import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let cacheOwner = identity(1, "admin_api_key")
private let usersPageJSON = "{\"items\":[\(stubUserJSON)],\"total\":1,\"page\":1,\"page_size\":20,\"pages\":1}"
private let cachedAccountJSON = #"{"id":9,"name":"测试账号","platform":"anthropic","type":"oauth","status":"active","schedulable":true,"error_message":null,"concurrency":5}"#
private let cachedGroupJSON = #"{"id":10,"name":"标准分组","description":"按量使用","platform":"openai","status":"active","rate_multiplier":"1.23456789","daily_limit_usd":"25.00000001","weekly_limit_usd":null,"is_exclusive":false,"subscription_type":"standard","rpm_limit":60,"account_count":12,"active_account_count":10,"billing_locked":false,"model_routing":{"private":[2]},"profit_control_enabled":true}"#
private let cachedStatsJSON = #"{"today_requests":12,"today_tokens":340,"today_cost":"0.12345678","today_actual_cost":"12.34567891","today_account_cost":"4.56789123","total_users":8,"total_accounts":3,"error_accounts":1,"rpm":2.5,"tpm":22.5}"#
private let todayStatsJSON = #"{"stats":{"1":{"requests":3,"tokens":30,"cost":"0.1"},"2":{"requests":5,"tokens":50,"cost":"0.2"}}}"#

private struct Marker: Decodable, Sendable { let marker: String }
private func identity(_ userID: Int?, _ method: String) -> ConditionalCache.Identity { ConditionalCache.Identity(userID: userID, authMethod: method) }

private func cachingClient(_ transport: ScriptedTransport, credential: Credential = .adminKey("fixture"),
                           identity: ConditionalCache.Identity? = cacheOwner, cache: ConditionalCache = ConditionalCache(),
                           server: ServerProfile = stubServer()) -> APIClient {
    APIClient(server: server, credential: credential, transport: transport, requestClock: .immediate, cacheIdentity: identity, conditionalCache: cache)
}
private func notModified(_ etag: String, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(statusCode: 304, headers: headers.merging(["etag": etag]) { _, tag in tag }, data: Data())
}
/// Answers like the backend's writeConditionalETag: 200 with the ETag until the request sends it back, then an empty 304.
private func revalidatingTransport(_ json: String, etag: String = "\"v1\"") -> ScriptedTransport {
    ScriptedTransport { request in sentHeader(request, "If-None-Match") == etag ? notModified(etag) : okReply(json, headers: ["etag": etag]) }
}
private func validators(_ transport: ScriptedTransport) async -> [String?] {
    await transport.requests.filter { !isRefresh($0) }.map { sentHeader($0, "If-None-Match") }
}
private func usersPage(_ client: APIClient) async throws -> Page<AdminUser> { try await client.users(query: UserListQuery()) }

@Test func usersListRevalidatesAndReturnsCachedPageOn304() async throws {
    let transport = ScriptedTransport(script: [
        .reply(okReply(usersPageJSON, headers: ["etag": "\"u1\"", "date": "D1", "x-request-id": "r1", "content-type": "application/json"])),
        .reply(notModified("\"u1\"", headers: ["date": "D2", "x-request-id": "r2"])),
        .reply(notModified("\"u1\"", headers: ["date": "D3", "x-request-id": "r3"]))
    ])
    let client = cachingClient(transport)
    let first = try await usersPage(client)
    let second = try await usersPage(client)
    #expect(second.items.map(\.id) == first.items.map(\.id)); #expect(second.total == 1)
    let query = try UserListQuery().queryItems()
    let response: APIResponse<Page<AdminUser>> = try await client.requestWithHeaders("admin/users", query: query)
    #expect(response.status == 304); #expect(response.value.items.first?.email == "admin@example.invalid")
    #expect(response.header("date") == "D3"); #expect(response.requestID == "r3"); #expect(response.header("etag") == "\"u1\"")
    #expect(response.header("content-type") == "application/json")
    #expect(await validators(transport) == [nil, "\"u1\"", "\"u1\""])
}

@Test(arguments: ["admin/accounts", "admin/users", "admin/groups", "admin/dashboard/stats", "admin/dashboard/home", "admin/dashboard/snapshot-v2",
                  "admin/ops/dashboard/snapshot-v2", "admin/meta/catalog"])
func everyListedReadRevalidatesTransparently(path: String) async throws {
    let transport = revalidatingTransport(#"{"marker":"cached"}"#)
    let client = cachingClient(transport)
    let first: APIResponse<Marker> = try await client.requestWithHeaders(path)
    let second: APIResponse<Marker> = try await client.requestWithHeaders(path)
    #expect(first.status == 200); #expect(second.status == 304); #expect(second.value.marker == "cached")
    #expect(await validators(transport) == [nil, "\"v1\""])
}

@Test func existingListMethodsReturnModelsOn304() async throws {
    let transport = ScriptedTransport { request in
        let path = request.url?.path ?? ""
        let json = switch path {
        case "/api/v1/admin/accounts": "{\"items\":[\(cachedAccountJSON)],\"total\":1,\"page\":1,\"page_size\":20}"
        case "/api/v1/admin/users": usersPageJSON
        case "/api/v1/admin/groups": "{\"items\":[\(cachedGroupJSON)],\"total\":1,\"page\":1,\"page_size\":20}"
        case "/api/v1/admin/dashboard/snapshot-v2": "{\"stats\":\(cachedStatsJSON)}"
        default: cachedStatsJSON
        }
        let etag = "\"\(path)\""
        return sentHeader(request, "If-None-Match") == etag ? notModified(etag) : okReply(json, headers: ["etag": etag])
    }
    let client = cachingClient(transport)
    for _ in 0..<2 {
        #expect(try await client.accounts(page: 1, search: "", status: nil, platform: nil).items.first?.id == 9)
        #expect(try await client.managedAccounts(page: 1, query: AccountListQuery()).items.first?.id == 9)
        #expect(try await usersPage(client).items.first?.id == 7)
        #expect(try await client.groups(page: 1).items.first?.id == 10)
        #expect(try await client.dashboard().stats.todayRequests == 12)
        #expect(try await client.dashboardCostSnapshot().actual == Decimal(string: "12.34567891"))
    }
    let sent = await validators(transport)
    #expect(sent.count == 12)
    #expect(sent.prefix(6).allSatisfy { $0 == nil }); #expect(sent.suffix(6).allSatisfy { $0 != nil })
}

@Test func todayStatsBatchKeyFollowsNormalizedBody() async throws {
    let transport = ScriptedTransport { request in
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        guard body == #"{"account_ids":[1,2]}"# else { return okReply(#"{"stats":{}}"#) }
        return sentHeader(request, "If-None-Match") == "\"t1\"" ? notModified("\"t1\"") : okReply(todayStatsJSON, headers: ["etag": "\"t1\""])
    }
    let client = cachingClient(transport)
    let first = try await client.accountTodayStats(ids: [2, 1, 1])
    let second = try await client.accountTodayStats(ids: [1, 2])
    _ = try await client.accountTodayStats(ids: [3])
    #expect(first.keys.sorted() == [1, 2]); #expect(second.keys.sorted() == [1, 2]); #expect(second[2]?.requests == 5)
    let requests = await transport.requests
    #expect(requests.allSatisfy { $0.httpMethod == "POST" }); #expect(requests[0].httpBody == requests[1].httpBody)
    #expect(await validators(transport) == [nil, "\"t1\"", nil])
}

@Test func successWithoutETagDropsEntry() async throws {
    let cache = ConditionalCache()
    let transport = ScriptedTransport(script: [.reply(okReply(usersPageJSON, headers: ["etag": "\"u1\""])), .reply(okReply(usersPageJSON))])
    let client = cachingClient(transport, cache: cache)
    _ = try await usersPage(client)
    #expect(await cache.count == 1)
    _ = try await usersPage(client)
    #expect(await cache.count == 0)
    _ = try await usersPage(client)
    #expect(await validators(transport) == [nil, "\"u1\"", nil])
}

@Test func accountDetailETagIsExposedButNeverCached() async throws {
    let cache = ConditionalCache()
    let version = ["etag": "\"cv-12\""]
    let transport = ScriptedTransport(script: [.reply(okReply(cachedAccountJSON, headers: version)), .reply(okReply(cachedAccountJSON, headers: version)),
                                               .reply(notModified("\"cv-12\""))])
    let client = cachingClient(transport, cache: cache)
    #expect(try await client.account(id: 9).id == 9)
    let detail: APIResponse<UpstreamAccount> = try await client.requestWithHeaders("admin/accounts/9")
    #expect(detail.status == 200); #expect(detail.header("etag") == "\"cv-12\"")
    #expect(await cache.count == 0)
    let error = try #require(await thrownAPIError { _ = try await client.account(id: 9) })
    #expect(error.kind == .response)
    #expect(await validators(transport) == [nil, nil, nil])
}

@Test(arguments: ["admin/groups/all", "admin/accounts/status-summary", "admin/dashboard/rates"])
func unlistedEndpointsNeverSendIfNoneMatch(path: String) async throws {
    let cache = ConditionalCache()
    let transport = revalidatingTransport(#"{"marker":"fresh"}"#)
    let client = cachingClient(transport, cache: cache)
    let _: Marker = try await client.request(path)
    let _: Marker = try await client.request(path)
    #expect(await validators(transport) == [nil, nil]); #expect(await cache.count == 0)
}

@Test func noIdentityMeansUnconditionalRequests() async throws {
    let cache = ConditionalCache()
    let transport = revalidatingTransport(usersPageJSON)
    let client = cachingClient(transport, identity: nil, cache: cache)
    _ = try await usersPage(client)
    _ = try await usersPage(client)
    #expect(await validators(transport) == [nil, nil]); #expect(await cache.count == 0)
    #expect(await client.conditionalCacheIdentity() == nil)
}

@Test func sharedCacheSeparatesIdentityAndSite() async throws {
    let cache = ConditionalCache()
    let transport = revalidatingTransport(usersPageJSON)
    let site = stubServer(), otherSite = stubServer()
    let first = cachingClient(transport, identity: identity(1, "jwt"), cache: cache, server: site)
    let clients = [
        cachingClient(transport, identity: identity(2, "jwt"), cache: cache, server: site),
        cachingClient(transport, identity: identity(1, "jwt"), cache: cache, server: otherSite),
        cachingClient(transport, identity: identity(1, "admin_api_key"), cache: cache, server: site)
    ]
    _ = try await usersPage(first)
    for client in clients { _ = try await usersPage(client) }
    _ = try await usersPage(first)
    #expect(await validators(transport) == [nil, nil, nil, nil, "\"v1\""])
    #expect(await cache.count == 4)
}

@Test func final401ClearsSiteCache() async throws {
    let cache = ConditionalCache()
    let transport = ScriptedTransport(script: [.reply(okReply(usersPageJSON, headers: ["etag": "\"u1\""])), .reply(errorReply(401, reason: "INVALID_ADMIN_KEY")),
                                               .reply(okReply(usersPageJSON, headers: ["etag": "\"u1\""]))])
    let client = cachingClient(transport, cache: cache)
    _ = try await usersPage(client)
    let error = try #require(await thrownAPIError { _ = try await usersPage(client) })
    #expect(error.statusCode == 401); #expect(await cache.count == 0)
    _ = try await usersPage(client)
    #expect(await validators(transport) == [nil, "\"u1\"", nil])
}

@Test func refreshedTokenExpiredKeepsValidatorAndCache() async throws {
    let cache = ConditionalCache()
    let transport = ScriptedTransport { request in
        if isRefresh(request) { return okReply(stubRefreshJSON) }
        let validator = sentHeader(request, "If-None-Match")
        if sentHeader(request, "Authorization") == "Bearer old-access", validator != nil { return errorReply(401, reason: "TOKEN_EXPIRED") }
        return validator == "\"u1\"" ? notModified("\"u1\"") : okReply(usersPageJSON, headers: ["etag": "\"u1\""])
    }
    let client = cachingClient(transport, credential: stubTokens(), identity: identity(7, "jwt"), cache: cache)
    let first = try await usersPage(client)
    let second = try await usersPage(client)
    _ = try await usersPage(client)
    #expect(second.items.map(\.id) == first.items.map(\.id))
    #expect(await transport.requests.filter(isRefresh).count == 1)
    #expect(await validators(transport) == [nil, "\"u1\"", "\"u1\"", "\"u1\""])
    #expect(await cache.count == 1)
}

@Test func readRetryResendsSameValidator() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(usersPageJSON, headers: ["etag": "\"u1\""])), .reply(errorReply(503)),
                                               .reply(notModified("\"u1\""))])
    let client = cachingClient(transport)
    let first = try await usersPage(client)
    let second = try await usersPage(client)
    #expect(second.items.map(\.id) == first.items.map(\.id))
    #expect(await validators(transport) == [nil, "\"u1\"", "\"u1\""])
}

@Test func notModifiedWithoutCachedEntryIsRejected() async throws {
    let cache = ConditionalCache()
    let transport = ScriptedTransport(script: [.reply(notModified("\"u1\""))])
    let client = cachingClient(transport, cache: cache)
    let error = try #require(await thrownAPIError { _ = try await usersPage(client) })
    #expect(error.kind == .response); #expect(await transport.requests.count == 1); #expect(await cache.count == 0)
}

@Test func lateNotModifiedAfterCancelAllIsDropped() async throws {
    let cache = ConditionalCache()
    let arrived = OpenGate(), release = OpenGate()
    let calls = CallCounter()
    let transport = ScriptedTransport { _ in
        guard calls.next() > 1 else { return okReply(usersPageJSON, headers: ["etag": "\"u1\""]) }
        await arrived.open(); await release.wait()
        return notModified("\"u1\"")
    }
    let client = cachingClient(transport, cache: cache)
    _ = try await usersPage(client)
    let read = Task { try await usersPage(client) }
    await arrived.wait()
    await client.cancelAll()
    await release.open()
    await #expect(throws: CancellationError.self) { _ = try await read.value }
    #expect(await cache.count == 1)
}

@Test func cancelAllKeepsCacheButLogoutAndClearEmptyIt() async throws {
    let cache = ConditionalCache()
    let transport = revalidatingTransport(usersPageJSON)
    let client = cachingClient(transport, cache: cache)
    _ = try await usersPage(client)
    await client.cancelAll()
    #expect(await cache.count == 1)
    _ = try await usersPage(client)
    #expect(await validators(transport) == [nil, "\"v1\""])
    await client.clearConditionalCache()
    #expect(await cache.count == 0)
    _ = try await usersPage(client)
    try await client.logout()
    #expect(await cache.count == 0); #expect(await client.conditionalCacheIdentity() == nil)

    let offline = ScriptedTransport { request in
        if request.url?.path == "/api/v1/auth/logout" { throw URLError(.notConnectedToInternet) }
        return okReply(usersPageJSON, headers: ["etag": "\"v1\""])
    }
    let session = cachingClient(offline, credential: stubTokens(), identity: identity(7, "jwt"), cache: cache)
    _ = try await usersPage(session)
    #expect(await cache.count == 1)
    await #expect(throws: (any Error).self) { try await session.logout() }
    #expect(await cache.count == 0)
}

@Test func meSetsIdentityAndIdentityChangeClears() async throws {
    let cache = ConditionalCache()
    let usersTransport = revalidatingTransport(usersPageJSON)
    let transport = ScriptedTransport { request in
        if request.url?.path == "/api/v1/admin/me" { return okReply(#"{"auth_method":"jwt","user":{"id":7,"role":"admin"},"workspace":null}"#) }
        return try await usersTransport.data(for: request)
    }
    let client = cachingClient(transport, credential: stubTokens(), identity: nil, cache: cache)
    _ = try await client.me()
    #expect(await client.conditionalCacheIdentity() == identity(7, "jwt"))
    _ = try await usersPage(client)
    _ = try await usersPage(client)
    #expect(await validators(usersTransport) == [nil, "\"v1\""]); #expect(await cache.count == 1)
    await client.setConditionalCacheIdentity(identity(7, "jwt"))
    #expect(await cache.count == 1)
    await client.setConditionalCacheIdentity(identity(8, "jwt"))
    #expect(await cache.count == 0)
}

@Test func legacyAdminKeyMeSetsMachineIdentity() async throws {
    let transport = ScriptedTransport { request in
        switch request.url?.path ?? "" {
        case "/api/v1/admin/me": HTTPResponse(statusCode: 404, headers: ["content-type": "text/plain"], data: Data("404 page not found".utf8))
        case "/api/v1/admin/compliance": okReply(#"{"required":false,"version":"2026-06"}"#)
        default: okReply("{}")
        }
    }
    let client = cachingClient(transport, identity: nil)
    #expect(try await client.me().isLegacyServer)
    #expect(await client.conditionalCacheIdentity() == identity(nil, "admin_api_key"))
}

@Test func identityFallsBackToCredentialKind() {
    let unknown = AdminMe()
    #expect(ConditionalCache.Identity(me: unknown, credential: .adminKey("k")) == identity(nil, "admin_api_key"))
    #expect(ConditionalCache.Identity(me: unknown, credential: .accessToken("sat_k")) == identity(nil, "admin_access_token"))
    #expect(ConditionalCache.Identity(me: unknown, credential: stubTokens()) == identity(nil, "jwt"))
    #expect(ConditionalCache.Identity(me: unknown, credential: nil) == nil)
    let reported = AdminMe(authMethod: .adminAccessToken, user: .init(id: 3))
    #expect(ConditionalCache.Identity(me: reported, credential: stubTokens()) == identity(3, "admin_access_token"))
    #expect(AdminAuthMethod.resolved(reported: nil, credential: stubTokens()) == .jwt)
    #expect(AdminAuthMethod.resolved(reported: .other("future"), credential: .adminKey("k")) == .other("future"))
    #expect(AdminAuthMethod.resolved(reported: nil, credential: nil) == nil)
}

/// Both cache steps suspend on the cache actor; a cancelAll meanwhile turns the request into CancellationError (S0-04's
/// contract), so a stale 401 never reaches the page and no new attempt starts on an ended session.
@Test func conditionalCacheStepsEndWithTheGeneration() async throws {
    let client = cachingClient(ScriptedTransport { _ in okReply(usersPageJSON) })
    let current = await client.currentGeneration()
    let unauthorized = errorReply(401, reason: "INVALID_ADMIN_KEY")
    #expect(try await client.resolveConditional(unauthorized, plan: nil, generation: current).statusCode == 401)
    #expect(try await client.conditionalPlan(path: "admin/users", method: "GET", query: [], body: nil, authenticated: true, generation: current) != nil)
    await client.cancelAll()
    await #expect(throws: CancellationError.self) { _ = try await client.resolveConditional(unauthorized, plan: nil, generation: current) }
    await #expect(throws: CancellationError.self) {
        _ = try await client.conditionalPlan(path: "admin/users", method: "GET", query: [], body: nil, authenticated: true, generation: current)
    }
}

/// R08: the account list page keeps no ETag of its own; a 304 brings back the cached counts, and later pages ask for none (R09).
@Test func accountListPageKeepsCountsOn304AndLaterPagesOmitCounts() async throws {
    let page = "{\"items\":[\(cachedAccountJSON)],\"total\":600,\"page\":1,\"page_size\":500,\"pages\":2,\"counts\":{\"all\":600,\"error\":1}}"
    let transport = revalidatingTransport(page, etag: "\"a1\"")
    let client = cachingClient(transport)
    let query = AccountListQuery(includeCounts: true, supportsListQuery: true)
    let first = try await client.managedAccounts(page: 1, query: query)
    let second = try await client.managedAccounts(page: 1, query: query)
    #expect(second.items.map(\.id) == first.items.map(\.id) && second.counts == first.counts)
    #expect(second.counts == AccountListCounts(all: 600, error: 1) && second.hasMore)
    #expect(await validators(transport) == [nil, "\"a1\""])
    _ = try await client.managedAccounts(page: 2, query: query)
    let later = try #require(await transport.requests.last?.url)
    #expect(!later.absoluteString.contains("include_counts") && later.absoluteString.contains("page=2"))
}

/// R08: users(query:) gets ETag revalidation from the cache with its full query; another page is another key, and users-usage
/// is never conditional.
@Test func usersQueryRevalidatesTransparentlyWithFullQuery() async throws {
    let transport = ScriptedTransport { request in
        if request.url?.path == "/api/v1/admin/dashboard/users-usage" { return okReply(#"{"stats":{}}"#, headers: ["etag": "\"s1\""]) }
        return sentHeader(request, "If-None-Match") == "\"u1\"" ? notModified("\"u1\"") : okReply(usersPageJSON, headers: ["etag": "\"u1\""])
    }
    let client = cachingClient(transport)
    let query = UserListQuery(search: "admin", page: 1)
    let first = try await client.users(query: query)
    let second = try await client.users(query: query)
    #expect(second.items.map(\.id) == first.items.map(\.id) && second.total == 1)
    _ = try await client.users(query: UserListQuery(search: "admin", page: 2))
    _ = try await client.usersTodayUsage(ids: [7])
    _ = try await client.usersTodayUsage(ids: [7])
    #expect(await validators(transport) == [nil, "\"u1\"", nil, nil, nil])
}
