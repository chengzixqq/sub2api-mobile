import Foundation
import Sub2Core

// X05: the proxy chapter's UI-test data. S6-12…S6-14 add their write fixtures at the end of this file, on the same
// FixtureProxySource instance (S6D1-12).

// MARK: - S6-11 列表

extension DemoData {
    struct ProxyFixtureOptions: Sendable, Equatable {
        static let emptyArgument = "-ui-proxies-empty"
        /// Nothing expired is still in use and kr-seoul-1 answers (140ms): the banner names hk-02 alone, 链接失败 is empty.
        static let soonOnlyArgument = "-ui-proxies-soon-only"
        /// Every list read fails with 502.
        static let listErrorArgument = "-ui-proxies-error"
        /// Pages of four; the first read of page 2 fails with 502.
        static let secondPageErrorArgument = "-ui-proxies-page2-error"
        /// Probing hk-01 (4) fails with 502.
        static let testHTTPErrorArgument = "-ui-proxies-test-http-error"
        /// The first list read answers 429 with retry_after `throttleSeconds`.
        static let throttledArgument = "-ui-proxies-throttled"
        static let throttleSeconds = 6
        var isEmpty, soonOnly, listError, secondPageError, testHTTPError, throttled: Bool

        init(arguments: [String]) {
            isEmpty = arguments.contains(Self.emptyArgument)
            soonOnly = arguments.contains(Self.soonOnlyArgument)
            listError = arguments.contains(Self.listErrorArgument)
            secondPageError = arguments.contains(Self.secondPageErrorArgument)
            testHTTPError = arguments.contains(Self.testHTTPErrorArgument)
            throttled = arguments.contains(Self.throttledArgument)
        }
    }

    /// The account fixtures' seven proxies (`proxyRows`) plus kr-seoul-1, newest id first, with 60 §12.3's counts and last
    /// probes: hk-02 6 days from expiry with 3 accounts (182ms), sg-01 (96ms), jp-tokyo-1 expired with 1 account and a failed
    /// probe, hk-01 (311ms, 2 accounts moved off), us-west-3 and de-fra-1 (stopped) never probed, us-east-2 expired with nothing
    /// on it, kr-seoul-1 failing with 407. Dates follow the server clock at `base`.
    static func proxyFixtures(base: Date, options: ProxyFixtureOptions) -> [AdminProxy] {
        guard !options.isEmpty else { return [] }
        let checked = Int(base.timeIntervalSince1970) - 7_200
        func probe(_ ms: Int, exit: String) -> [String: Any] {
            ["latency_status": "success", "latency_ms": ms, "latency_message": "Proxy is accessible", "latency_checked_at": checked, "ip_address": exit]
        }
        // A failed probe keeps no exit or place, as the server's snapshot.
        func failed(_ message: String) -> [String: Any] {
            ["latency_status": "failed", "latency_message": message, "latency_checked_at": checked, "country_code": NSNull(), "city": NSNull()]
        }
        func with(_ fields: [String: Any], _ more: [String: Any] = [:]) -> [String: Any] { fields.merging(more) { $1 } }
        let untested: [String: Any] = ["country_code": NSNull(), "city": NSNull()]
        let overlays: [Int: [String: Any]] = [
            1: with(["account_count": 3, "fallback_mode": "proxy", "backup_proxy_id": 2], probe(182, exit: "203.0.113.24")),
            2: with(["account_count": 2], probe(96, exit: "198.51.100.7")),
            3: with(["account_count": options.soonOnly ? 0 : 1], failed("dial tcp 198.51.100.30:1080: i/o timeout")),
            4: with(["account_count": 1, "fallback_mode": "proxy", "backup_proxy_id": 1, "fallback_account_count": 2], probe(311, exit: "203.0.113.9")),
            5: untested,
            6: untested,
            7: with(["fallback_account_count": 2], untested),
            8: with(["account_count": 1], options.soonOnly ? probe(140, exit: "203.0.113.77") : failed(proxyAuthFailure))
        ]
        // try! only here: a wire key that no longer decodes stops the first UI test instead of showing a wrong list.
        return (proxyRows(base: base) + [seoulRow(base: base)]).map { row in
            let wire = with(with(row, ["account_count": 0, "fallback_account_count": 0]), overlays[row["id"] as? Int ?? 0] ?? [:])
            return try! JSONDecoder().decode(AdminProxy.self, from: JSONSerialization.data(withJSONObject: wire))
        }
        .sorted { $0.id > $1.id }
    }

    /// The fixed answer of `POST :id/test`: 1 → 176ms, 2 → 101ms, 3 → i/o timeout, 4 → 296ms, 5 → 244ms, 6 → 213ms, 7 and 8 → 407
    /// (8 → 140ms with `soonOnly`). nil for an unknown id.
    static func proxyProbe(id: Int, options: ProxyFixtureOptions, checkedAt: Date) -> ProxyTestResult? {
        func reached(_ ms: Int, _ exit: String, _ code: String, city: String? = nil) -> ProxyTestResult {
            ProxyTestResult(success: true, message: "Proxy is accessible", latencyMs: ms, ipAddress: exit, city: city, countryCode: code, checkedAt: checkedAt)
        }
        switch id {
        case 1: return reached(176, "203.0.113.24", "HK")
        case 2: return reached(101, "198.51.100.7", "SG")
        case 3: return ProxyTestResult(success: false, message: "dial tcp 198.51.100.30:1080: i/o timeout", checkedAt: checkedAt)
        case 4: return reached(296, "203.0.113.9", "HK")
        case 5: return reached(244, "203.0.113.140", "US", city: "Fremont")
        case 6: return reached(213, "198.51.100.61", "DE")
        case 7: return ProxyTestResult(success: false, message: proxyAuthFailure, checkedAt: checkedAt)
        case 8: return options.soonOnly ? reached(140, "203.0.113.77", "KR") : ProxyTestResult(success: false, message: proxyAuthFailure, checkedAt: checkedAt)
        default: return nil
        }
    }

    /// Only the newest session's source is kept; the list, the detail and the editor of one session share it (S6D1-12).
    @MainActor static func proxySource(for generation: UUID, base: Date, arguments: [String] = ProcessInfo.processInfo.arguments) -> FixtureProxySource {
        if let cached = proxyFixtureCache, cached.generation == generation { return cached.source }
        let options = ProxyFixtureOptions(arguments: arguments)
        let source = FixtureProxySource(proxies: proxyFixtures(base: base, options: options), options: options)
        proxyFixtureCache = (generation, source)
        return source
    }

    @MainActor private static var proxyFixtureCache: (generation: UUID, source: FixtureProxySource)?
    private static let proxyAuthFailure = "proxy CONNECT: 407 Proxy Authentication Required"

    private static func seoulRow(base: Date) -> [String: Any] {
        func day(_ days: Double) -> String { ServerTime.utcTimestamp(base.addingTimeInterval(days * 86_400)) }
        return ["id": 8, "name": "kr-seoul-1", "protocol": "socks5", "host": "203.0.113.77", "port": 1080, "status": "active",
                "created_at": day(-20), "expires_at": day(200), "expiry_warn_days": 7, "username": "fixture", "password": "fixture-proxy-secret",
                "fallback_mode": "direct", "country_code": "KR"]
    }
}

/// The fixture site's proxies for one session. Like the backend it saves every probe's snapshot (H01), so the next list read
/// shows it; nothing goes to the network.
actor FixtureProxySource: ProxySource {
    /// Long enough for a UI test to see “测试中” on the first four rows.
    static let testDelay: Duration = .milliseconds(2500)
    static let splitPageSize = 4
    private static let failure = APIError.server(status: 502, reason: nil)
    private var rows: [AdminProxy]
    private let options: DemoData.ProxyFixtureOptions
    private let now: @Sendable () -> Date
    private var secondPageFailed = false
    private var throttleServed = false

    init(proxies: [AdminProxy], options: DemoData.ProxyFixtureOptions, now: @escaping @Sendable () -> Date = { Date() }) {
        rows = proxies; self.options = options; self.now = now
    }

    /// `GET admin/proxies`: id descending, `search` on the name or host ignoring case.
    func proxies(page: Int, query: ProxyListQuery) async throws -> Page<AdminProxy> {
        _ = try query.queryItems(page: page)
        if options.listError { throw Self.failure }
        if options.throttled, !throttleServed {
            throttleServed = true
            throw APIError.server(status: 429, envelope: nil, retryAfter: DemoData.ProxyFixtureOptions.throttleSeconds)
        }
        if options.secondPageError, page == 2, !secondPageFailed {
            secondPageFailed = true
            throw Self.failure
        }
        let size = options.secondPageError ? min(query.pageSize, Self.splitPageSize) : query.pageSize
        let term = query.search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = rows.sorted { $0.id > $1.id }
            .filter { term.isEmpty || $0.name.lowercased().contains(term) || $0.host.lowercased().contains(term) }
        let shown = matched.dropFirst((page - 1) * size).prefix(size)
        return Page(items: Array(shown), total: matched.count, page: page, pageSize: size, pages: max(1, (matched.count + size - 1) / size))
    }
    /// `POST :id/test` after `testDelay`: 404 PROXY_NOT_FOUND for an unknown id; the probe's result is saved on the row.
    func testProxy(id: Int) async throws -> ProxyTestResult {
        try await Task.sleep(for: Self.testDelay)
        guard let row = storedProxy(id: id) else { throw APIError.server(status: 404, reason: ProxyReason.notFound) }
        if options.testHTTPError, id == 4 { throw Self.failure }
        guard let result = DemoData.proxyProbe(id: id, options: options, checkedAt: now()) else { throw Self.failure }
        replace(row.applying(result))
        return result
    }

    /// The write fixtures' helpers (S6-12…S6-14).
    func storedProxy(id: Int) -> AdminProxy? { rows.first { $0.id == id } }
    /// Replaces the row with this id, or adds it.
    func replace(_ proxy: AdminProxy) {
        if let index = rows.firstIndex(where: { $0.id == proxy.id }) { rows[index] = proxy } else { rows.append(proxy) }
    }
    func remove(id: Int) { rows.removeAll { $0.id == id } }
}
