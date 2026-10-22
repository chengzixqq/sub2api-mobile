import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 00 §4.2 in-memory ETag cache. Entries keep the raw success body, so a 304 goes through the normal decoding and pages
/// only ever see models (R08). Account detail's "cv-N" is a PATCH If-Match version and is never stored (20 §2.2).
public actor ConditionalCache {
    public static let maxIdle: TimeInterval = 600
    static let conditionalReads: Set<String> = [
        "admin/accounts", "admin/users", "admin/groups", "admin/dashboard/stats", "admin/dashboard/home", "admin/dashboard/snapshot-v2",
        "admin/ops/dashboard/snapshot-v2", "admin/meta/catalog"
    ]
    static let conditionalBatches: Set<String> = ["admin/accounts/today-stats/batch"]

    /// `user.id` + `auth_method`; Admin Key on an old server has no user and is `(nil, "admin_api_key")`.
    public struct Identity: Hashable, Sendable {
        public let userID: Int?
        public let authMethod: String
        public init(userID: Int?, authMethod: String) { self.userID = userID; self.authMethod = authMethod }
    }
    /// Site + identity + method + canonical URL; POST also keys on the exact body bytes (in place of a hash).
    struct Key: Hashable, Sendable {
        let siteID: UUID
        let identity: Identity
        let method: String
        let url: String
        let body: Data?
        init(siteID: UUID, identity: Identity, method: String, url: URL, body: Data?) {
            self.siteID = siteID; self.identity = identity; self.method = method.uppercased()
            self.url = ConditionalCache.canonicalURL(url); self.body = self.method == "POST" ? body : nil
        }
    }
    struct Entry: Sendable, Equatable {
        let etag: String
        let body: Data
        let headers: [String: String]
        let receivedAt: Date
        let lastUsedAt: Date
    }

    private let maxIdle: TimeInterval
    private var entries: [Key: Entry] = [:]
    public init(maxIdle: TimeInterval = ConditionalCache.maxIdle) { self.maxIdle = maxIdle }

    var count: Int { entries.count }
    public func clear() { entries.removeAll() }
    public func clear(siteID: UUID) { entries = entries.filter { $0.key.siteID != siteID } }
    /// A hit counts as use; an entry idle for more than `maxIdle` is dropped instead.
    func entry(for key: Key, now: Date) -> Entry? {
        guard let found = entries[key] else { return nil }
        guard now.timeIntervalSince(found.lastUsedAt) <= maxIdle else { entries[key] = nil; return nil }
        let used = Entry(etag: found.etag, body: found.body, headers: found.headers, receivedAt: found.receivedAt, lastUsedAt: now)
        entries[key] = used
        return used
    }
    func store(_ key: Key, etag: String, body: Data, headers: [String: String], now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.lastUsedAt) <= maxIdle }
        entries[key] = Entry(etag: etag, body: body, headers: headers, receivedAt: now, lastUsedAt: now)
    }
    /// Only the entry whose ETag was sent is refreshed: a newer store or a removal in the meantime wins.
    func revalidated(_ key: Key, sentETag: String, newETag: String?, now: Date) {
        guard let found = entries[key], found.etag == sentETag else { return }
        entries[key] = Entry(etag: newETag ?? found.etag, body: found.body, headers: found.headers, receivedAt: now, lastUsedAt: now)
    }
    func remove(_ key: Key) { entries[key] = nil }

    /// The 00 §4.2 list, matched on the client's path exactly: `admin/accounts/:id` and `admin/groups/all` are not in it.
    static func supports(method: String, path: String) -> Bool {
        switch method.uppercased() {
        case "GET": conditionalReads.contains(path)
        case "POST": conditionalBatches.contains(path)
        default: false
        }
    }
    /// Query items sorted by name, then a missing value before any value; percent-encoding and repeated names are kept as sent.
    static func canonicalURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems else { return url.absoluteString }
        components.percentEncodedQueryItems = items.sorted {
            ($0.name, $0.value == nil ? 0 : 1, $0.value ?? "") < ($1.name, $1.value == nil ? 0 : 1, $1.value ?? "")
        }
        return components.string ?? url.absoluteString
    }
}

extension ConditionalCache.Identity {
    public init?(me: AdminMe, credential: Credential?) {
        guard let method = AdminAuthMethod.resolved(reported: me.authMethod, credential: credential) else { return nil }
        self.init(userID: me.user?.id, authMethod: method.rawValue)
    }
}

/// What one request looked up before sending; the captured entry answers its 304 even if the cache changes meanwhile.
struct ConditionalPlan: Sendable {
    let key: ConditionalCache.Key
    let cached: ConditionalCache.Entry?
    var validatorHeaders: [String: String] { cached.map { ["If-None-Match": $0.etag] } ?? [:] }
}

extension APIClient {
    /// nil when unauthenticated, while the identity is unknown, or for endpoints outside 00 §4.2.
    func conditionalPlan(path: String, method: String, query: [URLQueryItem], body: Data?, authenticated: Bool) async throws -> ConditionalPlan? {
        guard authenticated, let identity = cacheIdentity, ConditionalCache.supports(method: method, path: path) else { return nil }
        let key = ConditionalCache.Key(siteID: server.id, identity: identity, method: method, url: try endpointURL(path, query: query), body: body)
        return ConditionalPlan(key: key, cached: await conditionalCache.entry(for: key, now: requestClock.now()))
    }
    /// A 304 becomes the cached success body under the fresh headers; one the cache cannot answer is a contract error.
    /// A final 401 (after any token resend) empties this site's entries.
    func resolveConditional(_ response: HTTPResponse, plan: ConditionalPlan?) async throws -> HTTPResponse {
        if response.statusCode == 401 { await conditionalCache.clear(siteID: server.id) }
        guard response.statusCode == 304 else { return response }
        guard let plan, let cached = plan.cached else { throw APIError.invalidResponse }
        await conditionalCache.revalidated(plan.key, sentETag: cached.etag, newETag: Self.etag(response), now: requestClock.now())
        return HTTPResponse(statusCode: 200, headers: cached.headers.merging(response.headers) { _, fresh in fresh }, data: cached.body)
    }
    /// After a decoded 2xx: keep it under its ETag, or forget the key when the reply has none (today-stats with failed ids).
    func recordConditional(_ response: HTTPResponse, plan: ConditionalPlan?) async {
        guard let plan, (200..<300).contains(response.statusCode) else { return }
        if let etag = Self.etag(response) {
            await conditionalCache.store(plan.key, etag: etag, body: response.data, headers: response.headers, now: requestClock.now())
        } else {
            await conditionalCache.remove(plan.key)
        }
    }
    private static func etag(_ response: HTTPResponse) -> String? {
        guard let value = response.header("ETag")?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}
