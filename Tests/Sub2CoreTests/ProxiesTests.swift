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
