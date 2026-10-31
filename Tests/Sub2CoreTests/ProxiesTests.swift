import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let utc = ServerTimeZone(identifier: "UTC", utcOffset: "+00:00")!
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
/// 2026-10-16 12:00 in Shanghai.
private let noon = at("2026-10-16T12:00:00+08:00")

private let fullProxyJSON = #"""
{"id":1,"name":"hk-02","protocol":"socks5","host":"203.0.113.24","port":1080,"username":"edge","password":"s3cret","status":"active",
 "created_at":"2026-07-14T08:00:00Z","updated_at":"2026-10-01T08:00:00Z","expires_at":"2026-10-22T09:00:00+08:00","fallback_mode":"proxy",
 "backup_proxy_id":2,"expiry_warn_days":7,"account_count":3,"fallback_account_count":2,"latency_ms":182,"latency_status":"success",
 "latency_message":"ok","latency_checked_at":1792900000,"ip_address":"203.0.113.24","country":"Hong Kong","country_code":"HK",
 "region":"Hong Kong","city":"Central","quality_status":"good","quality_score":92,"quality_grade":"A","quality_summary":"stable",
 "quality_checked":1792900100}
"""#

private func decodeProxy(_ json: String) throws -> AdminProxy { try JSONDecoder().decode(AdminProxy.self, from: Data(json.utf8)) }
private func proxyClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}

@Test func decodesEveryListField() throws {
    let proxy = try decodeProxy(fullProxyJSON)
    #expect(proxy.id == 1 && proxy.name == "hk-02" && proxy.scheme == "socks5" && proxy.host == "203.0.113.24" && proxy.port == 1080)
    #expect(proxy.username == "edge" && proxy.password == "s3cret" && proxy.status == "active")
    #expect(proxy.createdAt == at("2026-07-14T08:00:00Z") && proxy.updatedAt == at("2026-10-01T08:00:00Z"))
    #expect(proxy.expiresAt == at("2026-10-22T01:00:00Z"))
    #expect(proxy.fallbackMode == "proxy" && proxy.backupProxyID == 2 && proxy.expiryWarnDays == 7)
    #expect(proxy.accountCount == 3 && proxy.hasAccountCountKey && proxy.fallbackAccountCount == 2)
    #expect(proxy.latencyMs == 182 && proxy.latencyStatus == "success" && proxy.latencyMessage == "ok")
    #expect(proxy.latencyCheckedAt == Date(timeIntervalSince1970: 1_792_900_000))
    #expect(proxy.ipAddress == "203.0.113.24" && proxy.country == "Hong Kong" && proxy.countryCode == "HK" && proxy.region == "Hong Kong")
    #expect(proxy.city == "Central" && proxy.qualityStatus == "good" && proxy.qualityScore == 92 && proxy.qualityGrade == "A")
    #expect(proxy.qualitySummary == "stable" && proxy.qualityChecked == Date(timeIntervalSince1970: 1_792_900_100))
    #expect(proxy.isActive)
}

@Test func decodesWithOnlyID() throws {
    let proxy = try decodeProxy(#"{"id":9,"expires_at":null}"#)
    #expect(proxy.id == 9 && proxy.name.isEmpty && proxy.scheme.isEmpty && proxy.host.isEmpty)
    #expect(proxy.port == nil && proxy.password == nil && proxy.status == nil && proxy.expiresAt == nil && proxy.accountCount == nil)
    #expect(!proxy.hasAccountCountKey && proxy.isActive)
    #expect(throws: (any Error).self) { try decodeProxy(#"{"name":"no-id"}"#) }
    // A field of an odd type reads as absent instead of failing the whole list.
    #expect(try decodeProxy(#"{"id":3,"port":"1080","account_count":"x"}"#).port == nil)
}

@Test func passwordNeverInDescriptions() throws {
    let proxy = try decodeProxy(fullProxyJSON)
    var dumped = ""
    dump(proxy, to: &dumped)
    for text in [String(describing: proxy), String(reflecting: proxy), "\(proxy)", dumped] {
        #expect(!text.contains("s3cret"), "\(text)")
        #expect(text.contains("<redacted>"), "\(text)")
    }
    #expect(proxy.password == "s3cret")
    let bare = AdminProxy(id: 2, name: "sg-01")
    #expect(String(describing: bare).contains("password: nil"))
}

@Test func allProxiesRequestsActiveListWithCount() async throws {
    let body = #"[{"id":4,"name":"hk-01","account_count":2},{"id":1,"name":"hk-02","account_count":3}]"#
    let transport = ScriptedTransport(script: [.reply(okReply(body, headers: ["ETag": "\"p-1\""]))])
    let client = proxyClient(transport)
    let first = try await client.allProxies(withCount: true)
    _ = try await client.allProxies(withCount: true)
    _ = try await client.allProxies(withCount: false)
    #expect(first.map(\.id) == [4, 1] && first.map(\.accountCount) == [2, 3])
    let requests = await transport.requests
    #expect(requests.count == 3)
    for request in requests {
        #expect(request.httpMethod == "GET" && request.url?.path == "/api/v1/admin/proxies/all")
        #expect(sentHeader(request, "If-None-Match") == nil)
    }
    #expect(requests[0].url?.query == "with_count=true" && requests[1].url?.query == "with_count=true")
    #expect(requests[2].url?.query == nil)
}

@Test(arguments: [
    ("expired", "2026-10-13T10:00:00+08:00", 7, ProxyExpiryWord(kind: .lapsed, text: "10/13 已过期", tone: .critical)),
    ("active", nil, 7, ProxyExpiryWord(kind: .never, text: "永不过期", tone: nil)),
    ("inactive", "2026-10-19T10:00:00+08:00", 7, ProxyExpiryWord(kind: .idle, text: "10/19 到期", tone: nil)),
    ("inactive", nil, 3, ProxyExpiryWord(kind: .never, text: "永不过期", tone: nil)),
    ("active", "2026-10-15T10:00:00+08:00", 7, ProxyExpiryWord(kind: .soon, text: "已到期 · 等待处理", tone: .caution)),
    ("active", "2026-10-16T20:00:00+08:00", 7, ProxyExpiryWord(kind: .soon, text: "今天到期", tone: .caution)),
    ("active", "2026-10-22T09:00:00+08:00", 7, ProxyExpiryWord(kind: .soon, text: "6 天后到期", tone: .caution)),
    ("active", "2026-10-23T09:00:00+08:00", 7, ProxyExpiryWord(kind: .soon, text: "7 天后到期", tone: .caution)),
    ("active", "2026-10-24T09:00:00+08:00", 7, ProxyExpiryWord(kind: .ok, text: "剩余 8 天", tone: nil)),
    ("active", "2026-10-17T09:00:00+08:00", nil, ProxyExpiryWord(kind: .ok, text: "剩余 1 天", tone: nil)),
    (nil, "2026-10-17T09:00:00+08:00", 1, ProxyExpiryWord(kind: .soon, text: "1 天后到期", tone: .caution))
] as [(String?, String?, Int?, ProxyExpiryWord)])
func proxyExpiryTable(status: String?, expires: String?, warnDays: Int?, expected: ProxyExpiryWord) {
    let word = ProxyExpiry.describe(status: status, expiresAt: expires.map(at), warnDays: warnDays, now: noon, timeZone: shanghai)
    #expect(word == expected)
    #expect(word.isSoon == (expected.kind == .soon))
}

@Test func proxyExpiryCountsServerCalendarDays() {
    let expires = at("2026-10-17T01:00:00+08:00"), late = at("2026-10-16T23:00:00+08:00")
    #expect(ProxyExpiry.days(until: expires, now: late, timeZone: shanghai) == 1)
    #expect(ProxyExpiry.describe(status: "active", expiresAt: expires, warnDays: 7, now: late, timeZone: shanghai).text == "1 天后到期")
    #expect(ProxyExpiry.days(until: expires, now: late, timeZone: utc) == 0)
    #expect(ProxyExpiry.describe(status: "active", expiresAt: expires, warnDays: 7, now: late, timeZone: utc).text == "今天到期")
    let lapsed = at("2026-10-12T16:30:00Z")
    #expect(ProxyExpiry.describe(status: "expired", expiresAt: lapsed, warnDays: nil, now: noon, timeZone: shanghai).text == "10/13 已过期")
    #expect(ProxyExpiry.describe(status: "expired", expiresAt: lapsed, warnDays: nil, now: noon, timeZone: utc).text == "10/12 已过期")
}

@Test func accountProxyUsesSameRules() throws {
    let admin = try decodeProxy(fullProxyJSON)
    let account = AccountProxy(id: 1, name: "hk-02", status: "active", expiresAt: "2026-10-22T09:00:00+08:00", scheme: "socks5",
                               host: "203.0.113.24", port: 1080, expiryWarnDays: 7)
    #expect(ProxyExpiry.describe(account, now: noon, timeZone: shanghai) == ProxyExpiry.describe(admin, now: noon, timeZone: shanghai))
    #expect(ProxyExpiry.describe(account, now: noon, timeZone: shanghai).text == "6 天后到期")
}

@Test func addressAndRegionText() throws {
    #expect(try decodeProxy(fullProxyJSON).address == "socks5://203.0.113.24:1080")
    #expect(AdminProxy(id: 2, name: "sg-01", scheme: "http", host: "198.51.100.7").address == "http://198.51.100.7")
    let singapore = Locale(identifier: "zh_CN").localizedString(forRegionCode: "SG")!
    #expect(AdminProxy(id: 2, name: "sg-01", countryCode: "SG", city: "Jurong").regionText == singapore + " · Jurong")
    #expect(AdminProxy(id: 2, name: "sg-01", countryCode: "SG").regionText == singapore)
    #expect(AdminProxy(id: 2, name: "sg-01", city: "Jurong").regionText == "Jurong")
    #expect(AdminProxy(id: 2, name: "sg-01", countryCode: " ", city: "").regionText == nil)
}

// MARK: - S6-10: results, queries, writes and the rest of the proxy endpoints

private func decoded<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }
private func bodyText(_ request: URLRequest?) -> String? { request?.httpBody.map { String(decoding: $0, as: UTF8.self) } }
private func queryValues(_ request: URLRequest?) -> [String: String] {
    let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
private func message(of error: any Error) -> String? { (error as? APIError)?.errorDescription }
private let checkedAt = Date(timeIntervalSince1970: 1_792_123_200)
private let createKey = UUID(uuidString: "3B241101-E2BB-4255-8CAF-4136C566A962")!
private let hkCreate = ProxyCreateRequest(name: "hk-02", scheme: "socks5", host: "203.0.113.24", port: 1080, username: "relay", password: "fixture-pass",
                                          expiresAt: Date(timeIntervalSince1970: 1_792_108_800.9), fallbackMode: .proxy, backupProxyID: 2, expiryWarnDays: 7)
private let hkCreateBody = #"{"backup_proxy_id":2,"expires_at":1792108800,"expiry_warn_days":7,"fallback_mode":"proxy","host":"203.0.113.24","name":"hk-02","password":"fixture-pass","port":1080,"protocol":"socks5","username":"relay"}"#

@Test func proxyTestResultDecodesSuccessAndFailure() throws {
    let success = try decoded(ProxyTestResult.self, #"""
    {"success":true,"message":"Proxy is accessible","latency_ms":182,"ip_address":"203.0.113.24","city":"Central","region":"Hong Kong",
     "country":"Hong Kong","country_code":"HK","checked_at":1792123200}
    """#)
    #expect(success == ProxyTestResult(success: true, message: "Proxy is accessible", latencyMs: 182, ipAddress: "203.0.113.24", city: "Central",
                                       region: "Hong Kong", country: "Hong Kong", countryCode: "HK", checkedAt: checkedAt))
    let failed = try decoded(ProxyTestResult.self, #"{"success":false,"message":"proxy connection failed","checked_at":1792123200}"#)
    #expect(!failed.success && failed.latencyMs == nil && failed.ipAddress == nil)
    #expect(failed.message == "proxy connection failed" && failed.checkedAt == checkedAt)
    #expect(try decoded(ProxyTestResult.self, "{}") == ProxyTestResult(success: false))
    #expect(try decoded(ProxyTestResult.self, #"{"success":"yes","latency_ms":"182"}"#) == ProxyTestResult(success: false))
}

@Test func qualityResultDecodesItemsAndBaseConnectivity() throws {
    let result = try decoded(ProxyQualityResult.self, #"""
    {"proxy_id":1,"score":92,"grade":"A","summary":"5 项检测通过","exit_ip":"203.0.113.24","country":"Hong Kong","country_code":"HK",
     "base_latency_ms":180,"passed_count":5,"warn_count":0,"failed_count":0,"challenge_count":0,"checked_at":1792123200,
     "items":[{"target":"base_connectivity","status":"pass","latency_ms":180},{"target":"openai","status":"pass","http_status":401,"latency_ms":210,"cf_ray":"8f"},
              {"target":"anthropic","status":"pass","http_status":401},{"target":"gemini","status":"pass"},{"target":"sora","status":"pass","message":"ok"}]}
    """#)
    #expect(result.proxyID == 1 && result.score == 92 && result.grade == "A" && result.summary == "5 项检测通过")
    #expect(result.exitIP == "203.0.113.24" && result.country == "Hong Kong" && result.countryCode == "HK" && result.baseLatencyMs == 180)
    #expect(result.passedCount == 5 && result.warnCount == 0 && result.failedCount == 0 && result.challengeCount == 0)
    #expect(result.checkedAt == checkedAt && result.items.count == 5)
    #expect(result.items[1] == ProxyQualityItem(target: "openai", status: "pass", httpStatus: 401, latencyMs: 210))
    #expect(result.baseConnectivityPassed && result.overallStatus == "healthy")

    let baseFailed = ProxyQualityResult(score: 0, grade: "F", failedCount: 1, items: [ProxyQualityItem(target: "base_connectivity", status: "fail")])
    #expect(!baseFailed.baseConnectivityPassed && baseFailed.overallStatus == "failed")
    #expect(!ProxyQualityResult(passedCount: 1, items: [ProxyQualityItem(target: "openai", status: "pass")]).baseConnectivityPassed)
    #expect(ProxyQualityResult(passedCount: 3, warnCount: 1, failedCount: 1, challengeCount: 1).overallStatus == "challenge")
    #expect(ProxyQualityResult(passedCount: 3, warnCount: 1, failedCount: 1).overallStatus == "failed")
    #expect(ProxyQualityResult(passedCount: 3, warnCount: 1).overallStatus == "warn")
    #expect(ProxyQualityResult().overallStatus == "failed")

    let empty = try decoded(ProxyQualityResult.self, "{}")
    #expect(empty.items.isEmpty && empty.passedCount == 0 && empty.challengeCount == 0 && empty.score == nil && empty.checkedAt == nil)
}

@Test func accountRefsFallbackAccountsAndRevertResultDecode() throws {
    let refs = try decoded([ProxyAccountRef].self, #"[{"id":3,"name":"Claude-官方-01","platform":"anthropic","type":"oauth","notes":"主力"},{"id":4}]"#)
    #expect(refs == [ProxyAccountRef(id: 3, name: "Claude-官方-01", platform: "anthropic", type: "oauth", notes: "主力"),
                     ProxyAccountRef(id: 4, name: "", platform: "", type: "", notes: nil)])
    let moved = try decoded([ProxyFallbackAccount].self, #"""
    [{"id":5,"name":"OpenAI-备用-A","platform":"openai","type":"apikey","current_proxy_id":null,"current_proxy_name":null},
     {"id":6,"name":"Kimi-01","platform":"moonshot","type":"apikey","current_proxy_id":2,"current_proxy_name":"sg-01"}]
    """#)
    #expect(moved[0].isDirect && moved[0].currentProxyName == nil && moved[0].notes == nil)
    #expect(!moved[1].isDirect && moved[1].currentProxyID == 2 && moved[1].currentProxyName == "sg-01" && moved[1].platform == "moonshot")

    let revert = try decoded(ProxyFallbackRevertResult.self, #"""
    {"reverted_ids":[3],"skipped":[{"id":5,"code":"ACCOUNT_NOT_IN_FALLBACK","message":"account is not in fallback"}],
     "failed":[{"id":9,"code":"ACCOUNT_NOT_FOUND","message":"upstream https://fixture.example.invalid said no"}]}
    """#)
    #expect(revert == ProxyFallbackRevertResult(revertedIDs: [3], skipped: [.init(id: 5, code: "ACCOUNT_NOT_IN_FALLBACK")],
                                                failed: [.init(id: 9, code: "ACCOUNT_NOT_FOUND")]))
    #expect(Mirror(reflecting: revert.failed[0]).children.compactMap(\.label).sorted() == ["code", "id"])
    #expect(ProxyFallbackRevertResult.skippedCodes.contains(revert.skipped[0].code))
    #expect(try decoded(ProxyFallbackRevertResult.self, "{}") == ProxyFallbackRevertResult())
}

@Test func listQueryEncodesPagingSortAndSearch() throws {
    func values(_ query: ProxyListQuery, page: Int = 1) throws -> [String: String] {
        Dictionary(try query.queryItems(page: page).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
    #expect(try values(ProxyListQuery()) == ["page": "1", "page_size": "200", "sort_by": "id", "sort_order": "desc"])
    #expect(try values(ProxyListQuery(search: "  hk-02 \n", pageSize: 100, sort: .name, ascending: true), page: 2)
            == ["page": "2", "page_size": "100", "sort_by": "name", "sort_order": "asc", "search": "hk-02"])
    #expect(try values(ProxyListQuery(search: " \n "))["search"] == nil)
    let cut = try values(ProxyListQuery(search: String(repeating: "代", count: 34)))["search"]
    #expect(cut == String(repeating: "代", count: 33) && cut?.utf8.count == 99)
    #expect(ProxyListQuery.Sort.scheme.rawValue == "protocol" && ProxyListQuery.Sort.accountCount.rawValue == "account_count")
    #expect(ProxyListQuery.Sort.createdAt.rawValue == "created_at")
    #expect(throws: APIError.self) { try ProxyListQuery().queryItems(page: 0) }
    #expect(throws: APIError.self) { try ProxyListQuery(pageSize: 0).queryItems(page: 1) }
    #expect(throws: APIError.self) { try ProxyListQuery(pageSize: 1_001).queryItems(page: 1) }
}

@Test func proxiesIsPlainReadWithoutConditionalCache() async throws {
    let body = #"{"items":[{"id":7,"name":"hk-02","account_count":3},{"id":6,"name":"sg-01","account_count":0}],"total":3,"page":1,"page_size":2,"pages":2}"#
    let transport = ScriptedTransport(script: [.reply(errorReply(502)), .reply(okReply(body, headers: ["ETag": "\"p-1\""]))])
    let client = proxyClient(transport)
    let page = try await client.proxies(page: 1, query: ProxyListQuery(pageSize: 2))
    _ = try await client.proxies(page: 1, query: ProxyListQuery(pageSize: 2))
    #expect(page.items.map(\.id) == [7, 6] && page.items.map(\.accountCount) == [3, 0] && page.total == 3 && page.hasMore)
    let requests = await transport.requests
    #expect(requests.count == 3)
    for request in requests {
        #expect(request.httpMethod == "GET" && request.url?.path == "/api/v1/admin/proxies")
        #expect(sentHeader(request, "If-None-Match") == nil && request.timeoutInterval == 20)
        #expect(queryValues(request)["page_size"] == "2")
    }
}

@Test func proxyDetailUsesSingleRequestWhenCountsPresent() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(#"{"id":7,"name":"hk-02","account_count":3,"fallback_account_count":2,"latency_checked_at":1792900000}"#))])
    let proxy = try await proxyClient(transport).proxy(id: 7)
    #expect(proxy.accountCount == 3 && proxy.fallbackAccountCount == 2 && proxy.latencyCheckedAt == Date(timeIntervalSince1970: 1_792_900_000))
    let requests = await transport.requests
    #expect(requests.count == 1 && requests.first?.url?.path == "/api/v1/admin/proxies/7" && requests.first?.httpMethod == "GET")

    let missing = ScriptedTransport(script: [.reply(errorReply(404, reason: "PROXY_NOT_FOUND"))])
    do {
        _ = try await proxyClient(missing).proxy(id: 7)
        Issue.record("a missing proxy must throw")
    } catch let error as APIError {
        #expect(error.statusCode == 404 && error.reason == ProxyReason.notFound)
    }
    #expect(await missing.requests.count == 1)
    await #expect(throws: APIError.self) { try await proxyClient(missing).proxy(id: 0) }
}

@Test func proxyDetailFallsBackToNameSearchOnOldServer() async throws {
    let oldDetail = okReply(#"{"id":7,"name":"hk-02","protocol":"socks5"}"#)
    func client(list: HTTPResponse, detail: HTTPResponse? = nil) -> (APIClient, ScriptedTransport) {
        let detail = detail ?? oldDetail
        let transport = ScriptedTransport { request in request.url?.path == "/api/v1/admin/proxies/7" ? detail : list }
        return (proxyClient(transport), transport)
    }
    let found = okReply(#"{"items":[{"id":9,"name":"hk-02-b","account_count":1},{"id":7,"name":"hk-02","account_count":3}],"total":2,"page":1,"page_size":100,"pages":1}"#)
    let (first, firstTransport) = client(list: found)
    let proxy = try await first.proxy(id: 7)
    #expect(proxy.id == 7 && proxy.accountCount == 3 && proxy.hasAccountCountKey)
    let requests = await firstTransport.requests
    try #require(requests.count == 2)
    #expect(requests[1].url?.path == "/api/v1/admin/proxies")
    #expect(queryValues(requests[1])["search"] == "hk-02" && queryValues(requests[1])["page"] == "1" && queryValues(requests[1])["page_size"] == "100")

    let other = okReply(#"{"items":[{"id":9,"name":"hk-02-b","account_count":1}],"total":1,"page":1,"page_size":100,"pages":1}"#)
    let (second, _) = client(list: other)
    let unmatched = try await second.proxy(id: 7)
    #expect(unmatched.accountCount == nil && !unmatched.hasAccountCountKey && unmatched.scheme == "socks5")

    let (third, thirdTransport) = client(list: errorReply(502))
    #expect(try await third.proxy(id: 7).accountCount == nil)
    #expect(await thirdTransport.requests(path: "/admin/proxies").count == 3)

    let (fourth, fourthTransport) = client(list: found, detail: okReply(#"{"id":7,"name":"  "}"#))
    #expect(try await fourth.proxy(id: 7).accountCount == nil)
    #expect(await fourthTransport.requests.count == 1)
}

@Test func createBodyIsSortedAndCarriesKey() async throws {
    #expect(String(decoding: try hkCreate.requestBody(), as: UTF8.self) == hkCreateBody)
    let plain = ProxyCreateRequest(name: " sg-01 ", host: "198.51.100.7", port: 443, username: "  ", password: "")
    #expect(String(decoding: try plain.requestBody(), as: UTF8.self)
            == #"{"expiry_warn_days":7,"fallback_mode":"none","host":"198.51.100.7","name":"sg-01","port":443,"protocol":"socks5"}"#)

    let transport = ScriptedTransport(script: [.reply(okReply(#"{"id":11,"name":"hk-02","protocol":"socks5"}"#))])
    let outcome = try await proxyClient(transport).createProxy(hkCreate, idempotencyKey: createKey)
    #expect(outcome.value.id == 11)
    let request = await transport.requests.first
    #expect(request?.httpMethod == "POST" && request?.url?.path == "/api/v1/admin/proxies" && request?.timeoutInterval == 35)
    #expect(sentHeader(request, "Idempotency-Key") == createKey.uuidString.lowercased())
    #expect(sentHeader(request, "X-Request-ID") == createKey.uuidString.lowercased())
    #expect(bodyText(request) == hkCreateBody)
}

@Test func createRetriesTransportFailureWithSameKeyThenUnconfirmed() async throws {
    let lost = ScriptedTransport(script: [.fail(URLError(.timedOut))])
    do {
        _ = try await proxyClient(lost).createProxy(hkCreate, idempotencyKey: createKey)
        Issue.record("an unanswered create must stay unconfirmed")
    } catch let failure as KeyedWriteFailure {
        #expect(failure.disposition == .unconfirmed(.transport, retryNotBefore: nil) && failure.key == createKey.uuidString.lowercased())
    }
    let attempts = await lost.requests
    #expect(attempts.count == 3)
    #expect(Set(attempts.compactMap { bodyText($0) }) == [hkCreateBody])
    #expect(Set(attempts.compactMap { sentHeader($0, "Idempotency-Key") }) == [createKey.uuidString.lowercased()])

    let recovered = ScriptedTransport(script: [.fail(URLError(.networkConnectionLost)), .reply(okReply(#"{"id":12,"name":"hk-02"}"#))])
    #expect(try await proxyClient(recovered).createProxy(hkCreate, idempotencyKey: createKey).value.id == 12)
    #expect(await recovered.requests.count == 2)

    let conflict = ScriptedTransport(script: [.reply(errorReply(409, reason: "IDEMPOTENCY_KEY_CONFLICT"))])
    do {
        _ = try await proxyClient(conflict).createProxy(hkCreate, idempotencyKey: createKey)
        Issue.record("a key conflict must ask for a new key")
    } catch let failure as KeyedWriteFailure {
        #expect(failure.disposition == .needsNewKey(.keyConflict))
    }
}

@Test func createValidationRejectsBeforeSending() async throws {
    func failure(_ request: ProxyCreateRequest) -> String? {
        do { try request.validate(); return nil } catch { return message(of: error) }
    }
    #expect(failure(hkCreate) == nil)
    #expect(failure(ProxyCreateRequest(name: "  ", host: "203.0.113.24", port: 1080)) == "请输入代理名称")
    #expect(failure(ProxyCreateRequest(name: "hk-02", host: " ", port: 1080)) == "请输入主机地址")
    #expect(failure(ProxyCreateRequest(name: "hk-02", host: "203.0.113.24", port: 0)) == "端口必须在 1-65535 之间")
    #expect(failure(ProxyCreateRequest(name: "hk-02", host: "203.0.113.24", port: 65_536)) == "端口必须在 1-65535 之间")
    #expect(failure(ProxyCreateRequest(name: "hk-02", host: "203.0.113.24", port: 1080, fallbackMode: .proxy)) == "选了备用代理回退，请选择一个备用代理")
    let invalid = "代理信息不符合要求。"
    #expect(failure(ProxyCreateRequest(name: "hk-02", scheme: "ftp", host: "203.0.113.24", port: 1080)) == invalid)
    #expect(failure(ProxyCreateRequest(name: "hk-02", host: "203.0.113.24", port: 1080, expiryWarnDays: -1)) == invalid)
    #expect(failure(ProxyCreateRequest(name: String(repeating: "a", count: 101), host: "203.0.113.24", port: 1080)) == invalid)
    #expect(failure(ProxyCreateRequest(name: "hk-02", host: "203.0.113.24", port: 1080, password: String(repeating: "密", count: 34))) == invalid)
    #expect(failure(ProxyCreateRequest(name: "hk-02", host: "203.0.113.24", port: 1080, backupProxyID: 0)) == invalid)
    #expect(failure(ProxyCreateRequest(name: "hk-02", host: "203.0.113.24", port: 1080, expiresAt: Date(timeIntervalSince1970: 0))) == invalid)

    let transport = ScriptedTransport(script: [.reply(okReply(#"{"id":1}"#))])
    await #expect(throws: APIError.self) {
        try await proxyClient(transport).createProxy(ProxyCreateRequest(name: "", host: "203.0.113.24", port: 1080), idempotencyKey: createKey)
    }
    #expect(await transport.requests.isEmpty)
}

@Test func updateBodyDistinguishesOmittedNullAndValue() async throws {
    func body(_ update: ProxyUpdateRequest, id: Int = 7) throws -> String { String(decoding: try update.requestBody(proxyID: id), as: UTF8.self) }
    func failure(_ update: ProxyUpdateRequest, id: Int = 7) -> String? {
        do { try update.validate(proxyID: id); return nil } catch { return message(of: error) }
    }
    #expect(try body(ProxyUpdateRequest(status: .inactive)) == #"{"status":"inactive"}"#)
    #expect(try body(ProxyUpdateRequest(expiresAt: .clear)) == #"{"expires_at":null}"#)
    #expect(try body(ProxyUpdateRequest(expiresAt: .set(Date(timeIntervalSince1970: 1_792_108_800.5)))) == #"{"expires_at":1792108800}"#)
    #expect(try body(ProxyUpdateRequest(backupProxyID: .clear)) == #"{"backup_proxy_id":null}"#)
    #expect(try body(ProxyUpdateRequest(backupProxyID: .set(2))) == #"{"backup_proxy_id":2}"#)
    #expect(try body(ProxyUpdateRequest(username: "")) == #"{"username":""}"#)
    #expect(try body(ProxyUpdateRequest(username: " relay ", password: " fixture-pass ")) == #"{"password":"fixture-pass","username":"relay"}"#)
    #expect(try body(ProxyUpdateRequest(name: " hk-03 ", port: 1081, status: .active, fallbackMode: .direct, backupProxyID: .clear, expiryWarnDays: 3))
            == #"{"backup_proxy_id":null,"expiry_warn_days":3,"fallback_mode":"direct","name":"hk-03","port":1081,"status":"active"}"#)
    #expect(!ProxyUpdateRequest().hasChanges && ProxyUpdateRequest(expiresAt: .clear).hasChanges)
    #expect(failure(ProxyUpdateRequest()) == "没有要保存的修改。")
    #expect(failure(ProxyUpdateRequest(backupProxyID: .set(7))) == "备用代理不能是它自己")
    #expect(failure(ProxyUpdateRequest(fallbackMode: .proxy, backupProxyID: .clear)) == "选了备用代理回退，请选择一个备用代理")
    #expect(failure(ProxyUpdateRequest(name: "  ")) == "请输入代理名称")
    #expect(failure(ProxyUpdateRequest(host: "")) == "请输入主机地址")
    #expect(failure(ProxyUpdateRequest(port: 0)) == "端口必须在 1-65535 之间")
    #expect(failure(ProxyUpdateRequest(scheme: "ftp")) == "代理信息不符合要求。")
    #expect(failure(ProxyUpdateRequest(expiryWarnDays: -1)) == "代理信息不符合要求。")
    #expect(failure(ProxyUpdateRequest(backupProxyID: .set(0))) == "代理信息不符合要求。")

    let transport = ScriptedTransport(script: [.reply(okReply(#"{"id":7}"#))])
    await #expect(throws: APIError.self) { try await proxyClient(transport).updateProxy(id: 7, ProxyUpdateRequest(backupProxyID: .set(7))) }
    #expect(await transport.requests.isEmpty)
}

@Test func updateIsSentOnceAndReadBackMatchesOnlySentKeys() async throws {
    let lost = ScriptedTransport(script: [.fail(URLError(.timedOut))])
    await #expect(throws: (any Error).self) { try await proxyClient(lost).updateProxy(id: 7, ProxyUpdateRequest(status: .inactive)) }
    let sent = await lost.requests
    #expect(sent.count == 1 && sent.first?.httpMethod == "PUT" && sent.first?.url?.path == "/api/v1/admin/proxies/7")
    #expect(sent.first?.timeoutInterval == 30 && sentHeader(sent.first, "Idempotency-Key") == nil && bodyText(sent.first) == #"{"status":"inactive"}"#)
    let saved = ScriptedTransport(script: [.reply(okReply(#"{"id":7,"name":"hk-02","status":"inactive"}"#))])
    #expect(try await proxyClient(saved).updateProxy(id: 7, ProxyUpdateRequest(status: .inactive)).status == "inactive")

    let expires = Date(timeIntervalSince1970: 1_792_108_800)
    let stored = AdminProxy(id: 7, name: "renamed-by-someone", scheme: "socks5", host: "203.0.113.24", port: 1080, username: "relay",
                            password: "fixture-pass", status: "inactive", expiresAt: expires, fallbackMode: "direct", expiryWarnDays: 3)
    #expect(ProxyUpdateRequest(status: .inactive).matches(stored))
    #expect(!ProxyUpdateRequest(status: .active).matches(stored))
    #expect(ProxyUpdateRequest(name: " renamed-by-someone ").matches(stored) && !ProxyUpdateRequest(name: "hk-02").matches(stored))
    #expect(ProxyUpdateRequest(expiresAt: .set(expires.addingTimeInterval(0.6))).matches(stored))
    #expect(!ProxyUpdateRequest(expiresAt: .set(expires.addingTimeInterval(1))).matches(stored))
    #expect(!ProxyUpdateRequest(expiresAt: .clear).matches(stored) && ProxyUpdateRequest(expiresAt: .clear).matches(AdminProxy(id: 7, name: "x")))
    #expect(ProxyUpdateRequest(password: "fixture-pass").matches(stored) && !ProxyUpdateRequest(password: "other").matches(stored))
    #expect(ProxyUpdateRequest(username: "").matches(AdminProxy(id: 7, name: "x")) && !ProxyUpdateRequest(username: "").matches(stored))
    #expect(ProxyUpdateRequest(fallbackMode: .direct, backupProxyID: .clear, expiryWarnDays: 3).matches(stored))
    #expect(!ProxyUpdateRequest(backupProxyID: .set(2)).matches(stored))
    #expect(ProxyUpdateRequest(scheme: "socks5", host: "203.0.113.24", port: 1080).matches(stored))

    #expect(!ProxyUpdateRequest(status: .inactive, expiresAt: .clear, fallbackMode: ProxyFallbackMode.none, expiryWarnDays: 1).touchesNetwork)
    for update in [ProxyUpdateRequest(scheme: "http"), ProxyUpdateRequest(host: "203.0.113.9"), ProxyUpdateRequest(port: 3128),
                   ProxyUpdateRequest(username: ""), ProxyUpdateRequest(password: "fixture-pass")] {
        #expect(update.touchesNetwork)
    }
}

@Test func deleteMapsNotFoundAndKeepsInUseMetadata() async throws {
    func delete(_ reply: HTTPResponse) async -> (result: Result<DeleteResult, any Error>, requests: [URLRequest]) {
        let transport = ScriptedTransport(script: [.reply(reply)])
        let result: Result<DeleteResult, any Error>
        do { result = .success(try await proxyClient(transport).deleteProxy(id: 7)) } catch { result = .failure(error) }
        return (result, await transport.requests)
    }
    func inUseCount(_ result: Result<DeleteResult, any Error>) -> Int? {
        guard case .failure(let error as APIError) = result, error.reason == ProxyReason.inUse else { return nil }
        return ProxyReason.fallbackAccountCount(in: error)
    }
    let deleted = await delete(okReply(#"{"message":"Proxy deleted successfully"}"#))
    #expect(try deleted.result.get() == .deleted)
    #expect(deleted.requests.count == 1 && deleted.requests.first?.httpMethod == "DELETE" && deleted.requests.first?.url?.path == "/api/v1/admin/proxies/7")
    #expect(try await delete(errorReply(404, reason: "PROXY_NOT_FOUND")).result.get() == .alreadyGone)

    let busy = await delete(errorReply(409, reason: "PROXY_IN_USE"))
    #expect(busy.requests.count == 1)
    guard case .failure(let busyError as APIError) = busy.result else { Issue.record("409 must throw"); return }
    #expect(busyError.statusCode == 409 && ProxyReason.fallbackAccountCount(in: busyError) == nil)
    #expect(inUseCount(await delete(errorReply(409, reason: "PROXY_IN_USE", extra: #","metadata":{"fallback_account_count":"2"}"#)).result) == 2)
    #expect(inUseCount(await delete(errorReply(409, reason: "PROXY_IN_USE", extra: #","metadata":{"fallback_account_count":"0"}"#)).result) == nil)
    #expect(inUseCount(await delete(errorReply(409, reason: "PROXY_IN_USE", extra: #","metadata":{"fallback_account_count":"x"}"#)).result) == nil)

    let page = await delete(HTTPResponse(statusCode: 404, headers: [:], data: Data("404 page not found".utf8)))
    guard case .failure(let pageError as APIError) = page.result else { Issue.record("a non-JSON 404 must throw"); return }
    #expect(pageError.statusCode == 404 && page.requests.count == 1)
}

@Test func testAndQualityCheckAreSinglePostsWithoutRetry() async throws {
    let gateway = ScriptedTransport(script: [.reply(errorReply(502))])
    await #expect(throws: APIError.self) { try await proxyClient(gateway).testProxy(id: 7) }
    let tested = await gateway.requests
    try #require(tested.count == 1)
    #expect(tested[0].httpMethod == "POST" && tested[0].url?.path == "/api/v1/admin/proxies/7/test")
    #expect((tested[0].httpBody ?? Data()).isEmpty && sentHeader(tested[0], "Idempotency-Key") == nil)
    let failedProbe = ScriptedTransport(script: [.reply(okReply(#"{"success":false,"message":"proxy connection failed","checked_at":1792123200}"#))])
    let result = try await proxyClient(failedProbe).testProxy(id: 7)
    #expect(!result.success && result.checkedAt == checkedAt)

    let slow = ScriptedTransport(script: [.fail(URLError(.timedOut))])
    await #expect(throws: (any Error).self) { try await proxyClient(slow).checkProxyQuality(id: 7) }
    let checked = await slow.requests
    try #require(checked.count == 1)
    #expect(checked[0].httpMethod == "POST" && checked[0].url?.path == "/api/v1/admin/proxies/7/quality-check")
    #expect(checked[0].timeoutInterval == ProxyRequestTimeout.qualityCheck && ProxyRequestTimeout.qualityCheck == 95)
    let graded = ScriptedTransport(script: [.reply(okReply(#"{"proxy_id":7,"score":92,"grade":"A","passed_count":5,"checked_at":1792123200,"items":[]}"#))])
    #expect(try await proxyClient(graded).checkProxyQuality(id: 7).score == 92)

    let unused = ScriptedTransport(script: [.reply(okReply("{}"))])
    await #expect(throws: APIError.self) { try await proxyClient(unused).testProxy(id: 0) }
    await #expect(throws: APIError.self) { try await proxyClient(unused).checkProxyQuality(id: -1) }
    #expect(await unused.requests.isEmpty)
}

@Test func accountListsAndRevertRequests() async throws {
    let transport = ScriptedTransport { request in
        switch request.url?.path ?? "" {
        case "/api/v1/admin/proxies/7/accounts": okReply(#"[{"id":3,"name":"Claude-官方-01","platform":"anthropic","type":"oauth"},{"name":"no-id"}]"#)
        case "/api/v1/admin/proxies/7/fallback-accounts": okReply(#"[{"id":5,"name":"OpenAI-备用-A","platform":"openai","type":"apikey","current_proxy_id":null}]"#)
        default: okReply(#"{"reverted_ids":[5,3],"skipped":[],"failed":[]}"#)
        }
    }
    let client = proxyClient(transport)
    #expect(try await client.proxyAccounts(id: 7).map(\.id) == [3])
    #expect(try await client.proxyFallbackAccounts(id: 7).map(\.isDirect) == [true])
    #expect(try await client.revertProxyFallback(id: 7, accountIDs: []).revertedIDs == [5, 3])
    _ = try await client.revertProxyFallback(id: 7, accountIDs: [5, 5, 3])
    let requests = await transport.requests
    try #require(requests.count == 4)
    #expect(requests[0].httpMethod == "GET" && requests[1].httpMethod == "GET")
    #expect(requests[2].httpMethod == "POST" && requests[2].url?.path == "/api/v1/admin/proxies/7/fallback-accounts/revert")
    #expect(bodyText(requests[2]) == "{}" && bodyText(requests[3]) == #"{"account_ids":[5,3]}"#)
    #expect(sentHeader(requests[2], "Idempotency-Key") == nil)

    await #expect(throws: APIError.self) { try await client.revertProxyFallback(id: 7, accountIDs: Array(1...501)) }
    await #expect(throws: APIError.self) { try await client.revertProxyFallback(id: 7, accountIDs: [3, 0]) }
    await #expect(throws: APIError.self) { try await client.revertProxyFallback(id: 0, accountIDs: []) }
    #expect(await transport.requests.count == 4)
    _ = try await client.revertProxyFallback(id: 7, accountIDs: Array(1...500) + [500])
    #expect(await transport.requests.count == 5)

    let unavailable = ScriptedTransport(script: [.reply(errorReply(409, reason: "PROXY_FALLBACK_ORIGIN_UNAVAILABLE"))])
    do {
        _ = try await proxyClient(unavailable).revertProxyFallback(id: 7, accountIDs: [])
        Issue.record("409 must throw")
    } catch let error as APIError {
        #expect(error.reason == ProxyReason.fallbackOriginUnavailable)
    }
    let lost = ScriptedTransport(script: [.fail(URLError(.timedOut))])
    await #expect(throws: (any Error).self) { try await proxyClient(lost).revertProxyFallback(id: 7, accountIDs: [5]) }
    #expect(await lost.requests.count == 1)
}

@Test func applyingResultsAndMergingConfiguration() throws {
    let proxy = try decodeProxy(fullProxyJSON)
    let tested = proxy.applying(ProxyTestResult(success: true, message: "ok", latencyMs: 176, ipAddress: "203.0.113.25", city: "Kowloon",
                                                region: "Kowloon", country: "Hong Kong", countryCode: "HK", checkedAt: checkedAt))
    #expect(tested.latencyStatus == "success" && tested.latencyMs == 176 && tested.latencyMessage == "ok" && tested.latencyCheckedAt == checkedAt)
    #expect(tested.ipAddress == "203.0.113.25" && tested.city == "Kowloon" && tested.region == "Kowloon" && tested.countryCode == "HK")
    #expect(tested.qualityScore == 92 && tested.qualityGrade == "A" && tested.accountCount == 3 && tested.name == "hk-02" && tested.password == "s3cret")

    let failed = proxy.applying(ProxyTestResult(success: false, message: "proxy connection failed", checkedAt: checkedAt))
    #expect(failed.latencyStatus == "failed" && failed.latencyMs == nil && failed.latencyMessage == "proxy connection failed")
    #expect(failed.ipAddress == nil && failed.country == nil && failed.countryCode == nil && failed.region == nil && failed.city == nil)
    #expect(failed.latencyCheckedAt == checkedAt && failed.qualityGrade == "A" && failed.fallbackAccountCount == 2)

    let graded = proxy.applying(ProxyQualityResult(score: 64, grade: "C", summary: "2 项警告", passedCount: 3, warnCount: 2, checkedAt: checkedAt))
    #expect(graded.qualityScore == 64 && graded.qualityGrade == "C" && graded.qualitySummary == "2 项警告" && graded.qualityStatus == "warn")
    #expect(graded.qualityChecked == checkedAt && graded.latencyMs == 182 && graded.ipAddress == "203.0.113.24")

    let saved = AdminProxy(id: 1, name: "hk-02b", scheme: "socks5", host: "203.0.113.24", port: 1080, username: "edge", password: "s3cret",
                           status: "inactive", expiresAt: nil, fallbackMode: "direct", expiryWarnDays: 3)
    let merged = proxy.mergingConfiguration(from: saved)
    #expect(merged.name == "hk-02b" && merged.status == "inactive" && merged.expiresAt == nil && merged.fallbackMode == "direct")
    #expect(merged.backupProxyID == nil && merged.expiryWarnDays == 3 && merged.createdAt == proxy.createdAt)
    #expect(merged.accountCount == 3 && merged.hasAccountCountKey && merged.fallbackAccountCount == 2)
    #expect(merged.latencyMs == 182 && merged.ipAddress == "203.0.113.24" && merged.qualityGrade == "A")

    let moved = proxy.mergingConfiguration(from: AdminProxy(id: 1, name: "hk-02", scheme: "socks5", host: "203.0.113.99", port: 1080,
                                                             username: "edge", password: "s3cret", status: "active"))
    #expect(moved.host == "203.0.113.99" && moved.latencyMs == nil && moved.latencyStatus == nil && moved.latencyCheckedAt == nil)
    #expect(moved.ipAddress == nil && moved.countryCode == nil && moved.city == nil && moved.qualityGrade == "A" && moved.accountCount == 3)
}

@Test func writeRequestDescriptionsRedactPassword() throws {
    let update = ProxyUpdateRequest(name: "hk-02", password: "fixture-pass", status: .active)
    for value in [hkCreate as Any, update as Any] {
        var dumped = ""
        dump(value, to: &dumped)
        for text in [String(describing: value), String(reflecting: value), "\(value)", dumped] {
            #expect(!text.contains("fixture-pass"), "\(text)")
            #expect(text.contains("<redacted>"), "\(text)")
        }
    }
    #expect(String(describing: update).contains("status") && String(describing: hkCreate).contains("hk-02"))
    #expect(String(decoding: try update.requestBody(proxyID: 7), as: UTF8.self).contains("fixture-pass"))
    #expect(try hkCreate.requestBody() == Data(hkCreateBody.utf8))
}
