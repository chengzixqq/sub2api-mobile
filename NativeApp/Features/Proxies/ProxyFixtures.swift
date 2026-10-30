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
    /// S6-12: `-ui-proxy-accounts-error-once` failed its first `:id/accounts` read.
    private var accountsFailureServed = false
    /// S6-13: the accounts a revert moved back onto each proxy, listed by `:id/accounts` after the fixed ones.
    private var restored: [Int: [ProxyAccountRef]] = [:]
    /// S6-14: the add answered for each key (the same key answers the same proxy).
    private var createdByKey: [UUID: AdminProxy] = [:]

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
    /// S6-13: a revert's accounts join the proxy's `:id/accounts`.
    func restore(_ accounts: [ProxyAccountRef], to proxyID: Int) { restored[proxyID, default: []] += accounts }
}

// MARK: - S6-12 详情

extension DemoData {
    /// The detail's launch arguments, read on each call (FixtureProxySource's stored options are the list's).
    struct ProxyDetailFixtureOptions: Sendable, Equatable {
        /// Every `GET :id` answers 404 PROXY_NOT_FOUND.
        static let notFoundArgument = "-ui-proxy-not-found"
        static let accountsErrorArgument = "-ui-proxy-accounts-error"
        /// Only the session's first `GET :id/accounts` fails with 502.
        static let accountsErrorOnceArgument = "-ui-proxy-accounts-error-once"
        /// 质量检测 answers with the base probe failed (78, B).
        static let qualityErrorArgument = "-ui-proxy-quality-error"
        /// The first delete of a proxy nothing uses answers 409 PROXY_IN_USE without metadata: an account took it meanwhile.
        static let deleteConflictArgument = "-ui-proxy-delete-conflict"
        /// `GET :id` takes `slowDelay`, so the card's placeholder can be seen.
        static let slowDetailArgument = "-ui-proxy-slow-detail"
        static let slowDelay: Duration = .seconds(2)
        static let qualityDelay: Duration = .seconds(5)
        var notFound, accountsError, accountsErrorOnce, qualityError, deleteConflict, slowDetail: Bool

        init(arguments: [String] = ProcessInfo.processInfo.arguments) {
            notFound = arguments.contains(Self.notFoundArgument)
            accountsError = arguments.contains(Self.accountsErrorArgument)
            accountsErrorOnce = arguments.contains(Self.accountsErrorOnceArgument)
            qualityError = arguments.contains(Self.qualityErrorArgument)
            deleteConflict = arguments.contains(Self.deleteConflictArgument)
            slowDetail = arguments.contains(Self.slowDetailArgument)
        }
    }

    /// `GET :id/accounts` per proxy, on the account fixtures' ids (DemoData+Accounts) so a row opens its account.
    static func proxyAccountFixtures() -> [Int: [ProxyAccountRef]] {
        func account(_ id: Int, _ name: String, _ platform: String, _ type: String) -> ProxyAccountRef {
            ProxyAccountRef(id: id, name: name, platform: platform, type: type)
        }
        return [
            1: [account(1, "Claude-官方-01", "anthropic", "oauth"), account(2, "Claude-官方-02", "anthropic", "oauth"),
                account(3, "Claude-官方-03", "anthropic", "oauth")],
            2: [account(4, "OpenAI-主力-01", "openai", "apikey"), account(7, "OpenAI-备用-A", "openai", "apikey")],
            3: [account(5, "Gemini-测试-B", "gemini", "apikey")],
            4: [account(8, "DeepSeek-01", "deepseek", "apikey")],
            8: [account(11, "GLM-直连-01", "zhipu", "apikey")]
        ]
    }
}

extension FixtureProxySource: ProxyDetailSource {
    private static let notFound = APIError.server(status: 404, reason: ProxyReason.notFound)
    private static let inUse = APIError.server(status: 409, reason: ProxyReason.inUse)

    /// `GET :id` returns the row as saved, with every probe and write of this session. S6-13 adds the accounts still moved off it.
    func proxy(id: Int) async throws -> AdminProxy {
        let detail = DemoData.ProxyDetailFixtureOptions()
        if detail.slowDetail { try await Task.sleep(for: DemoData.ProxyDetailFixtureOptions.slowDelay) }
        guard !detail.notFound, let row = storedProxy(id: id) else { throw Self.notFound }
        return row
    }
    func proxyAccounts(id: Int) async throws -> [ProxyAccountRef] {
        guard storedProxy(id: id) != nil else { throw Self.notFound }
        let detail = DemoData.ProxyDetailFixtureOptions()
        if detail.accountsError { throw Self.failure }
        if detail.accountsErrorOnce, !accountsFailureServed {
            accountsFailureServed = true
            throw Self.failure
        }
        return (DemoData.proxyAccountFixtures()[id] ?? []) + (restored[id] ?? [])
    }
    /// Five seconds later, so a UI test sees “检测中…”: 92 (A) with the base probe passed, or 78 (B) with it failed; the
    /// snapshot is saved either way.
    func checkProxyQuality(id: Int) async throws -> ProxyQualityResult {
        try await Task.sleep(for: DemoData.ProxyDetailFixtureOptions.qualityDelay)
        guard let row = storedProxy(id: id) else { throw Self.notFound }
        let failed = DemoData.ProxyDetailFixtureOptions().qualityError
        let base = ProxyQualityItem(target: ProxyQualityResult.baseConnectivityTarget, status: failed ? "fail" : "pass", latencyMs: failed ? nil : 180)
        let result = ProxyQualityResult(proxyID: id, score: failed ? 78 : 92, grade: failed ? "B" : "A", summary: failed ? "基础连通失败" : "全部通过",
                                        exitIP: row.ipAddress, countryCode: row.countryCode, passedCount: failed ? 3 : 4, failedCount: failed ? 1 : 0,
                                        checkedAt: now(), items: [base])
        replace(row.applying(result))
        return result
    }
    /// `PUT :id`: every key sent (S6-14's `applyEdit`); answers the plain dto.AdminProxy, without counts or probes.
    func updateProxy(id: Int, _ request: ProxyUpdateRequest) async throws -> AdminProxy {
        guard let row = storedProxy(id: id) else { throw Self.notFound }
        return try applyEdit(request, to: row)
    }
    /// `DELETE :id`: 409 PROXY_IN_USE while accounts use it, with `fallback_account_count` while accounts were moved off it.
    func deleteProxy(id: Int) async throws -> DeleteResult {
        guard let row = storedProxy(id: id) else { return .alreadyGone }
        let accounts = row.accountCount ?? 0
        if accounts == 0, DemoData.ProxyDetailFixtureOptions().deleteConflict {
            replace(row.fixtureCounting(accounts: 1))
            throw Self.inUse
        }
        if accounts > 0 { throw Self.inUse }
        if let moved = row.fallbackAccountCount, moved > 0 {
            throw APIError.server(status: 409, envelope: ErrorEnvelope(reason: ProxyReason.inUse, metadata: ["fallback_account_count": String(moved)]))
        }
        remove(id: id)
        return .deleted
    }
}

private extension AdminProxy {
    /// The same row with another account count.
    func fixtureCounting(accounts: Int) -> AdminProxy {
        AdminProxy(id: id, name: name, scheme: scheme, host: host, port: port, username: username, password: password, status: status,
                   createdAt: createdAt, updatedAt: updatedAt, expiresAt: expiresAt, fallbackMode: fallbackMode, backupProxyID: backupProxyID,
                   expiryWarnDays: expiryWarnDays, accountCount: accounts, hasAccountCountKey: true, fallbackAccountCount: fallbackAccountCount,
                   latencyMs: latencyMs, latencyStatus: latencyStatus, latencyMessage: latencyMessage, latencyCheckedAt: latencyCheckedAt,
                   ipAddress: ipAddress, country: country, countryCode: countryCode, region: region, city: city, qualityStatus: qualityStatus,
                   qualityScore: qualityScore, qualityGrade: qualityGrade, qualitySummary: qualitySummary, qualityChecked: qualityChecked)
    }
}

// MARK: - S6-13 被改走的账号

extension DemoData {
    /// The fallback page's launch arguments.
    enum ProxyFallbackFixtureArgument {
        /// The first account sent was restored by someone else meanwhile: skipped with ACCOUNT_NOT_IN_FALLBACK.
        static let skipped = "-ui-proxy-fallback-skipped"
        /// The last account sent fails with an empty code (the server's unclassified error) and stays moved off.
        static let failed = "-ui-proxy-fallback-failed"
        /// Every revert answers 409 PROXY_FALLBACK_ORIGIN_UNAVAILABLE.
        static let originUnavailable = "-ui-proxy-fallback-origin-unavailable"
        /// Every list read answers 503.
        static let listError = "-ui-proxy-fallback-list-error"
    }

    /// This session's FixtureProxySource and moved accounts. A revert writes the remaining and the using counts onto the proxy's
    /// row and adds the accounts no longer moved off to its `:id/accounts`, so the list and the detail read them, and restores the
    /// account fixtures' own fallen-back account (Kimi-01) as well.
    @MainActor static func proxyFallbackEndpoints(model: AppModel) -> ProxyFallbackEndpoints {
        let generation = model.sessionGeneration
        let source = proxySource(for: generation, base: model.accountFixtureNow())
        let moved = ProxyFallbackDemoStore.current(for: generation)
        let arguments = ProcessInfo.processInfo.arguments
        let notFound = APIError.server(status: 404, reason: ProxyReason.notFound)
        return ProxyFallbackEndpoints(
            accounts: { @MainActor id in
                if arguments.contains(ProxyFallbackFixtureArgument.listError) { throw APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE") }
                guard await source.storedProxy(id: id) != nil else { throw notFound }
                return moved.accounts(proxyID: id)
            },
            proxy: { try await source.proxy(id: $0) },
            revert: { @MainActor id, accountIDs in
                guard let origin = await source.storedProxy(id: id) else { throw notFound }
                if arguments.contains(ProxyFallbackFixtureArgument.originUnavailable)
                    || !ProxyFallbackPresentation.canRevert(origin, now: model.accountFixtureNow()) {
                    throw APIError.server(status: 409, reason: ProxyReason.fallbackOriginUnavailable)
                }
                let before = moved.accounts(proxyID: id)
                let result = moved.revert(proxyID: id, accountIDs: accountIDs, arguments: arguments)
                let left = moved.accounts(proxyID: id)
                let back = before.filter { account in !left.contains { $0.id == account.id } }
                await source.restore(back.map { ProxyAccountRef(id: $0.id, name: $0.name, platform: $0.platform, type: $0.type) }, to: id)
                await source.replace(origin.fixtureMoving(left.count, using: (origin.accountCount ?? 0) + back.count))
                for account in result.revertedIDs + result.skipped.map(\.id) { try? model.accountDemo.revertProxyFallback(id: account) }
                return result
            })
    }
}

/// The accounts each fixture proxy's expiry moved off it, on the account fixtures' ids: hk-01 (4) ← Kimi-01 (now on hk-02, as
/// DemoData+Accounts has it) and MiniMax-01 (direct); us-east-2 (7) ← GLM-直连-01 and Grok-旧-01 (both direct). One per session.
@MainActor
final class ProxyFallbackDemoStore {
    private var moved: [Int: [ProxyFallbackAccount]]
    private static var latest: (generation: UUID, store: ProxyFallbackDemoStore)?

    static func current(for generation: UUID) -> ProxyFallbackDemoStore {
        if let latest, latest.generation == generation { return latest.store }
        let store = ProxyFallbackDemoStore()
        latest = (generation, store)
        return store
    }

    init() {
        func account(_ id: Int, _ name: String, _ platform: String, on current: (Int, String)? = nil) -> ProxyFallbackAccount {
            ProxyFallbackAccount(id: id, name: name, platform: platform, type: "apikey", currentProxyID: current?.0, currentProxyName: current?.1)
        }
        moved = [4: [account(9, "Kimi-01", "kimi", on: (1, "hk-02")), account(12, "MiniMax-01", "minimax")],
                 7: [account(11, "GLM-直连-01", "zhipu"), account(10, "Grok-旧-01", "grok")]]
    }

    /// Newest id first, as the server's ORDER BY a.id DESC.
    func accounts(proxyID: Int) -> [ProxyFallbackAccount] { (moved[proxyID] ?? []).sorted { $0.id > $1.id } }

    /// As the backend, account by account: no ids → all of them by id; an id not moved off this proxy is skipped.
    func revert(proxyID: Int, accountIDs: [Int], arguments: [String]) -> ProxyFallbackRevertResult {
        let listed = Set((moved[proxyID] ?? []).map(\.id))
        var seen = Set<Int>()
        let targets = accountIDs.isEmpty ? listed.sorted() : accountIDs.filter { seen.insert($0).inserted }
        var reverted: [Int] = [], skipped: [ProxyFallbackRevertResult.Item] = [], failed: [ProxyFallbackRevertResult.Item] = []
        for (index, id) in targets.enumerated() {
            if !listed.contains(id) {
                skipped.append(.init(id: id, code: "ACCOUNT_NOT_FALLBACK_OF_PROXY"))
            } else if index == 0, arguments.contains(DemoData.ProxyFallbackFixtureArgument.skipped) {
                skipped.append(.init(id: id, code: AccountWriteReason.notInFallback))
                remove(id, from: proxyID)
            } else if index == targets.count - 1, arguments.contains(DemoData.ProxyFallbackFixtureArgument.failed) {
                failed.append(.init(id: id, code: ""))
            } else {
                reverted.append(id)
                remove(id, from: proxyID)
            }
        }
        return ProxyFallbackRevertResult(revertedIDs: reverted, skipped: skipped, failed: failed)
    }

    private func remove(_ id: Int, from proxyID: Int) { moved[proxyID]?.removeAll { $0.id == id } }
}

private extension AdminProxy {
    /// The same row with other `fallback_account_count` and `account_count`.
    func fixtureMoving(_ count: Int, using accounts: Int) -> AdminProxy {
        AdminProxy(id: id, name: name, scheme: scheme, host: host, port: port, username: username, password: password, status: status,
                   createdAt: createdAt, updatedAt: updatedAt, expiresAt: expiresAt, fallbackMode: fallbackMode, backupProxyID: backupProxyID,
                   expiryWarnDays: expiryWarnDays, accountCount: accounts, hasAccountCountKey: true, fallbackAccountCount: count,
                   latencyMs: latencyMs, latencyStatus: latencyStatus, latencyMessage: latencyMessage, latencyCheckedAt: latencyCheckedAt,
                   ipAddress: ipAddress, country: country, countryCode: countryCode, region: region, city: city, qualityStatus: qualityStatus,
                   qualityScore: qualityScore, qualityGrade: qualityGrade, qualitySummary: qualitySummary, qualityChecked: qualityChecked)
    }
}

// MARK: - S6-14 添加、编辑与续期

extension DemoData {
    /// The editor's launch argument.
    enum ProxyEditFixtureArgument {
        /// An add or an edit that sends a backup answers 404 PROXY_NOT_FOUND: the backup was deleted meanwhile.
        static let backupGone = "-ui-proxy-backup-gone"
    }
    /// The server's probe of a new address lands this long after the write (the add reads it 3 seconds later, the detail 5).
    static let proxyEditProbeDelay: Duration = .seconds(2)
}

extension FixtureProxySource: ProxyEditSource {
    /// `POST admin/proxies`: the next id, active, with nothing on it; the same key answers the same proxy (a replay). The probe
    /// lands `proxyEditProbeDelay` later (158ms).
    func createProxy(_ request: ProxyCreateRequest, idempotencyKey: UUID, onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<AdminProxy> {
        if let done = createdByKey[idempotencyKey] { return WriteOutcome(value: done, replayed: true) }
        if request.backupProxyID != nil, ProcessInfo.processInfo.arguments.contains(DemoData.ProxyEditFixtureArgument.backupGone) { throw Self.notFound }
        _ = try request.requestBody()
        let id = (rows.map(\.id).max() ?? 0) + 1
        let reply = AdminProxy(id: id, name: request.name, scheme: request.scheme, host: request.host, port: request.port,
                               username: ProxyWriteFixture.nonEmpty(request.username), password: ProxyWriteFixture.nonEmpty(request.password),
                               status: ProxyStatusChange.active.rawValue, createdAt: now(), updatedAt: now(), expiresAt: request.expiresAt,
                               fallbackMode: request.fallbackMode.rawValue, backupProxyID: request.backupProxyID, expiryWarnDays: request.expiryWarnDays)
        createdByKey[idempotencyKey] = reply
        replace(reply.fixtureCounting(accounts: 0))
        probeLater(id)
        return WriteOutcome(value: reply)
    }

    /// Applies every key sent, as UpdateProxy merges them; a changed address drops the probe and probes again (H04).
    fileprivate func applyEdit(_ request: ProxyUpdateRequest, to row: AdminProxy) throws -> AdminProxy {
        if case .set? = request.backupProxyID, ProcessInfo.processInfo.arguments.contains(DemoData.ProxyEditFixtureArgument.backupGone) {
            throw Self.notFound
        }
        _ = try request.requestBody(proxyID: row.id)
        let reply = row.fixtureEdited(by: request)
        replace(row.mergingConfiguration(from: reply))
        if request.touchesNetwork { probeLater(row.id) }
        return reply
    }

    private func probeLater(_ id: Int) {
        Task {
            try? await Task.sleep(for: DemoData.proxyEditProbeDelay)
            self.landProbe(id)
        }
    }
    private func landProbe(_ id: Int) {
        guard let row = storedProxy(id: id) else { return }
        replace(row.applying(ProxyTestResult(success: true, message: "Proxy is accessible", latencyMs: 158, ipAddress: row.host, checkedAt: now())))
    }
}

private enum ProxyWriteFixture {
    static func nonEmpty(_ text: String) -> String? { text.isEmpty ? nil : text }
}

private extension AdminProxy {
    /// The configuration a PUT answers: this row with the request's keys, without counts or probes.
    func fixtureEdited(by request: ProxyUpdateRequest) -> AdminProxy {
        let expires: Date? = switch request.expiresAt {
        case nil: expiresAt
        case .clear?: nil
        case .set(let date)?: date
        }
        let backup: Int? = switch request.backupProxyID {
        case nil: backupProxyID
        case .clear?: nil
        case .set(let id)?: id
        }
        return AdminProxy(id: id, name: request.name ?? name, scheme: request.scheme ?? scheme, host: request.host ?? host, port: request.port ?? port,
                          username: request.username ?? username, password: request.password ?? password,
                          status: request.status?.rawValue ?? status, createdAt: createdAt, updatedAt: Date(), expiresAt: expires,
                          fallbackMode: request.fallbackMode?.rawValue ?? fallbackMode, backupProxyID: backup,
                          expiryWarnDays: request.expiryWarnDays ?? expiryWarnDays)
    }
}
