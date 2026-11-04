import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let siteA = UUID(uuidString: "0A000000-0000-4000-8000-000000000001")!
private let siteB = UUID(uuidString: "0B000000-0000-4000-8000-000000000002")!
private let owner = ConditionalCache.Identity(userID: 1, authMethod: "jwt")
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let cachedBody = Data(#"{"code":0,"data":{"items":[]}}"#.utf8)
private let usersURL = "https://cache.example.invalid/api/v1/admin/users?page=1&page_size=20"

private func cacheKey(_ url: String = usersURL, site: UUID = siteA, identity: ConditionalCache.Identity = owner,
                      method: String = "GET", body: Data? = nil) -> ConditionalCache.Key {
    ConditionalCache.Key(siteID: site, identity: identity, method: method, url: URL(string: url)!, body: body)
}
private func canonical(_ query: String, path: String = "/api/v1/admin/accounts") -> String {
    ConditionalCache.canonicalURL(URL(string: "https://cache.example.invalid" + path + query)!)
}

@Test(arguments: [
    ("GET", "admin/accounts", true), ("GET", "admin/users", true), ("GET", "admin/groups", true), ("GET", "admin/dashboard/stats", true),
    ("GET", "admin/dashboard/home", true), ("GET", "admin/dashboard/snapshot-v2", true), ("GET", "admin/ops/dashboard/snapshot-v2", true),
    ("GET", "admin/meta/catalog", true), ("POST", "admin/accounts/today-stats/batch", true), ("get", "admin/users", true),
    ("post", "admin/accounts/today-stats/batch", true),
    ("GET", "admin/accounts/9", false), ("GET", "admin/groups/all", false), ("GET", "admin/accounts/today-stats/batch", false),
    ("POST", "admin/accounts", false), ("POST", "admin/users", false), ("POST", "admin/groups", false),
    ("POST", "admin/accounts/runtime/batch", false), ("GET", "admin/accounts/status-summary", false), ("GET", "admin/dashboard/rates", false),
    ("GET", "admin/usage", false), ("PUT", "admin/users", false), ("GET", "admin/me", false)
] as [(String, String, Bool)])
func conditionalEndpointsMatchSpecList(method: String, path: String, supported: Bool) {
    #expect(ConditionalCache.supports(method: method, path: path) == supported)
}

@Test func canonicalURLSortsQueryKeepsEncodingAndDuplicates() {
    let ordered = canonical("?search=a%26b%20%E4%B8%AD&page=1&page_size=20")
    #expect(ordered == canonical("?page_size=20&page=1&search=a%26b%20%E4%B8%AD"))
    #expect(ordered.contains("search=a%26b%20%E4%B8%AD"))
    #expect(canonical("?status=a&status=b") == canonical("?status=b&status=a"))
    #expect(canonical("?status=a&status=a") != canonical("?status=a"))
    #expect(canonical("?page=1") != canonical("?page=2"))
    #expect(canonical("?page=1") != canonical("?page=1", path: "/api/v1/admin/users"))
    #expect(canonical("") == "https://cache.example.invalid/api/v1/admin/accounts")
}

@Test func keyDistinguishesSiteIdentityMethodURLAndBody() {
    let ids = Data(#"{"account_ids":[1,2]}"#.utf8)
    let batchURL = "https://cache.example.invalid/api/v1/admin/accounts/today-stats/batch"
    let base = cacheKey(batchURL, method: "POST", body: ids)
    let same = cacheKey(batchURL, method: "post", body: Data(#"{"account_ids":[1,2]}"#.utf8))
    #expect(base == same); #expect(base.hashValue == same.hashValue)
    let variants = [
        cacheKey(batchURL, site: siteB, method: "POST", body: ids),
        cacheKey(batchURL, identity: .init(userID: 2, authMethod: "jwt"), method: "POST", body: ids),
        cacheKey(batchURL, identity: .init(userID: 1, authMethod: "admin_api_key"), method: "POST", body: ids),
        cacheKey(batchURL, identity: .init(userID: nil, authMethod: "jwt"), method: "POST", body: ids),
        cacheKey(batchURL, method: "GET"),
        cacheKey(batchURL + "?group_id=3", method: "POST", body: ids),
        cacheKey(batchURL, method: "POST", body: Data(#"{"account_ids":[1,3]}"#.utf8))
    ]
    for (index, variant) in variants.enumerated() { #expect(variant != base, "variant \(index)") }
    #expect(cacheKey(method: "GET", body: Data("ignored".utf8)) == cacheKey())
    #expect(cacheKey(usersURL) == cacheKey("https://cache.example.invalid/api/v1/admin/users?page_size=20&page=1"))
}

@Test func idleEntryIsDroppedAfterTenMinutesWithoutUse() async {
    let cache = ConditionalCache()
    let key = cacheKey()
    await cache.store(key, etag: "\"a\"", body: cachedBody, headers: ["date": "D1"], now: t0)
    let hit = await cache.entry(for: key, now: t0.addingTimeInterval(600))
    #expect(hit?.etag == "\"a\""); #expect(hit?.body == cachedBody); #expect(hit?.headers == ["date": "D1"])
    #expect(await cache.entry(for: key, now: t0.addingTimeInterval(1_200.5)) == nil)
    #expect(await cache.count == 0)
}

@Test func useResetsIdleTimer() async {
    let cache = ConditionalCache()
    let key = cacheKey()
    await cache.store(key, etag: "\"a\"", body: cachedBody, headers: [:], now: t0)
    #expect(await cache.entry(for: key, now: t0.addingTimeInterval(500)) != nil)
    #expect(await cache.entry(for: key, now: t0.addingTimeInterval(1_000)) != nil)
    #expect(await cache.entry(for: key, now: t0.addingTimeInterval(1_601)) == nil)
}

@Test func revalidationRefreshesReceivedAtAndAdoptsNewETag() async {
    let cache = ConditionalCache()
    let key = cacheKey()
    await cache.store(key, etag: "\"a\"", body: cachedBody, headers: [:], now: t0)
    let t1 = t0.addingTimeInterval(30), t2 = t0.addingTimeInterval(60)
    await cache.revalidated(key, sentETag: "\"a\"", newETag: "\"b\"", now: t1)
    let adopted = await cache.entry(for: key, now: t1)
    #expect(adopted?.etag == "\"b\""); #expect(adopted?.receivedAt == t1); #expect(adopted?.body == cachedBody)
    await cache.revalidated(key, sentETag: "\"b\"", newETag: nil, now: t2)
    let kept = await cache.entry(for: key, now: t2)
    #expect(kept?.etag == "\"b\""); #expect(kept?.receivedAt == t2)
}

@Test func staleRevalidationKeepsNewerEntry() async {
    let cache = ConditionalCache()
    let key = cacheKey()
    let newer = Data(#"{"code":0,"data":{"items":[1]}}"#.utf8)
    await cache.store(key, etag: "\"e1\"", body: cachedBody, headers: [:], now: t0)
    await cache.store(key, etag: "\"e2\"", body: newer, headers: [:], now: t0)
    await cache.revalidated(key, sentETag: "\"e1\"", newETag: "\"e1\"", now: t0.addingTimeInterval(10))
    let entry = await cache.entry(for: key, now: t0.addingTimeInterval(10))
    #expect(entry?.etag == "\"e2\""); #expect(entry?.body == newer); #expect(entry?.receivedAt == t0)
}

@Test func revalidationDoesNotResurrectRemovedEntry() async {
    let cache = ConditionalCache()
    let key = cacheKey()
    await cache.store(key, etag: "\"a\"", body: cachedBody, headers: [:], now: t0)
    await cache.remove(key)
    await cache.revalidated(key, sentETag: "\"a\"", newETag: "\"a\"", now: t0)
    #expect(await cache.count == 0)
    await cache.store(key, etag: "\"a\"", body: cachedBody, headers: [:], now: t0)
    await cache.clear()
    await cache.revalidated(key, sentETag: "\"a\"", newETag: "\"a\"", now: t0)
    #expect(await cache.count == 0)
}

@Test func clearBySiteKeepsOtherSitesAndClearAllEmpties() async {
    let cache = ConditionalCache()
    for site in [siteA, siteB] {
        await cache.store(cacheKey(site: site), etag: "\"u\"", body: cachedBody, headers: [:], now: t0)
        await cache.store(cacheKey("https://cache.example.invalid/api/v1/admin/groups?page=1", site: site), etag: "\"g\"", body: cachedBody,
                          headers: [:], now: t0)
    }
    await cache.clear(siteID: siteA)
    #expect(await cache.count == 2)
    #expect(await cache.entry(for: cacheKey(site: siteB), now: t0) != nil)
    #expect(await cache.entry(for: cacheKey(site: siteA), now: t0) == nil)
    await cache.clear()
    #expect(await cache.count == 0)
}

@Test func storePurgesIdleEntries() async {
    let cache = ConditionalCache()
    for page in 1...3 {
        await cache.store(cacheKey("https://cache.example.invalid/api/v1/admin/users?page=\(page)"), etag: "\"p\(page)\"", body: cachedBody,
                          headers: [:], now: t0)
    }
    await cache.store(cacheKey("https://cache.example.invalid/api/v1/admin/groups"), etag: "\"g\"", body: cachedBody, headers: [:],
                      now: t0.addingTimeInterval(700))
    #expect(await cache.count == 1)
    let short = ConditionalCache(maxIdle: 5)
    await short.store(cacheKey(), etag: "\"a\"", body: cachedBody, headers: [:], now: t0)
    #expect(await short.entry(for: cacheKey(), now: t0.addingTimeInterval(6)) == nil)
}
