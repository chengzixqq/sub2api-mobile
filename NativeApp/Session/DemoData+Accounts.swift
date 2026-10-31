import Foundation
import Sub2Core

// Stage 2 fixtures (20 章, X11, S2D1-14): the account tab's demo site. Built through `AccountDemoStore`, one per session.
extension DemoData {
    /// Every stage 2 `-ui-*` launch argument (S2D1-14); later items add their members here.
    enum AccountFixture {
        /// The site has no accounts.
        static let empty = "-ui-accounts-empty"
        /// Every list read fails.
        static let listError = "-ui-accounts-list-error"
        /// The first list read works and later ones fail (“读取失败，显示的是 HH:MM 的数据”).
        static let refreshError = "-ui-accounts-refresh-error"
        /// today-stats answers 503 ACCOUNT_STATS_UNAVAILABLE: every account reads “—”.
        static let todayError = "-ui-accounts-today-error"
        static let summaryError = "-ui-accounts-summary-error"
        static let groupsError = "-ui-account-groups-error"
        /// Every timed window an hour longer, for tests that need 过载中 (72 seconds in the design) to hold.
        static let longWindows = "-ui-accounts-long-windows"
        /// The account tab's first appearance takes the next argument as an intent from another tab (10 §0.7-4): “limited”,
        /// “limited:anthropic”, or “all:kimi” for a platform alone. Nothing reaches the tab while S1-10's overview rows are missing.
        static let intent = "-ui-accounts-intent"
        /// Every account write through AppModel+Accounts answers 500 (“站点暂时不可用”); reads still work.
        static let writeFail = "-ui-account-write-fail"
        /// bulk-update fails each account in error one by one (S2-07).
        static let bulkPartial = "-ui-accounts-bulk-partial"
        /// bulk-update answers 500 as a whole (S2-07).
        static let bulkFail = "-ui-accounts-bulk-fail"
        /// `GET :id` fails like a lost site (S2-08): the detail keeps the list's snapshot, or shows its failure page by id.
        static let detailError = "-ui-account-detail-error"
        /// `GET :id` answers 404 ACCOUNT_NOT_FOUND for every account while the list still has them (S2-08).
        static let removed = "-ui-account-removed"
        /// `GET :id` answers eight seconds late, so something covering the detail meanwhile cancels it (S2-08).
        static let slowDetail = "-ui-account-detail-slow"
        /// OpenAI-主力-01 and OpenAI-备用-A also belong to group 10, which the group page's old fixture lists (GroupsView), so its
        /// transitional “查看与管理分组账号” has rows (S2-08).
        static let groupTransition = "-ui-account-group-transition"
        /// The detail's first `GET :id/today-stats` answers 429 with retry_after 8 (S2-09); later reads work.
        static let todayThrottled = "-ui-account-today-throttled"
        /// Before each account's first PATCH another administrator changes its notes to `otherAdminNotes`, so that PATCH meets
        /// 412 ACCOUNT_VERSION_CONFLICT (S2-10).
        static let patchConflict = "-ui-account-patch-conflict"
        static let otherAdminNotes = "另一位管理员改了备注"
        /// Any write whose groups include 1 (高级组) meets the mixed-channel risk, on top of the members' own rule (S2D1-14).
        static let mixedChannel = "-ui-account-mixed-channel"
        /// The session's first PATCH is lost on the way: nothing is written and the reply never comes (S2-10).
        static let patchTimeout = "-ui-account-patch-timeout"
        /// `GET :id` reads like a server older than credential redaction: a secret in the clear and no ETag (S2D1-09). Tests
        /// add `-ui-without-capabilities accounts.patch`, as such a site has no PATCH.
        static let legacyServer = "-ui-account-legacy-server"
        /// DeepSeek-01 expired an hour ago with auto_pause_on_expired, so it reads “暂停（已过期）” (S2D1-20).
        static let expired = "-ui-account-expired"
        /// 恢复原代理 meets 400 ACCOUNT_NOT_IN_FALLBACK: another administrator has just reverted the account (S2-11).
        static let revertNotInFallback = "-ui-account-revert-not-in-fallback"
        /// 恢复原代理 meets 409 PROXY_FALLBACK_ORIGIN_UNAVAILABLE (S2-11).
        static let revertOriginUnavailable = "-ui-account-revert-origin-unavailable"
        /// `proxies/all` answers 502 (S2-11).
        static let proxiesError = "-ui-account-proxies-error"
        /// OpenAI-备用-A is a Bedrock account, so its credential error offers “在 Web 中更换凭据” (S2-11).
        static let bedrockError = "-ui-account-bedrock-error"
        /// Before each account's first PATCH another administrator moves it onto us-west-3, so a proxy pick meets 412 and
        /// “账号已被其他人修改” (S2-11).
        static let proxyConflict = "-ui-account-proxy-conflict"
        static let otherAdminProxyID = 5
        /// `GET :id/models` answers 502 (S2-12; S2-14 reuses it).
        static let modelsError = "-ui-account-models-error"
        /// `POST :id/refresh` answers 500 (S2-16).
        static let refreshFail = "-ui-account-refresh-fail"
        /// Claude-官方-02's token was refused (401) and the failure stopped it (S2-17).
        static let tokenError = "-ui-account-token-error"
        /// Claude-官方-02 is stopped (inactive) with its switch on (S2-17).
        static let tokenInactive = "-ui-account-token-inactive"
        /// Each authorization session's first save answers 500 REAUTH_PERSIST_FAILED; 重试保存 then works (S2-17).
        static let reauthPersistFail = "-ui-account-reauth-persist-fail"
        /// reauthorize answers 400 REAUTH_UNSUPPORTED (shadow_account) (S2-17).
        static let reauthUnsupported = "-ui-account-reauth-unsupported"

        static func launchIntent(arguments: [String]) -> TabIntent? {
            guard let index = arguments.firstIndex(of: intent), index + 1 < arguments.count else { return nil }
            let value = arguments[index + 1]
            guard !value.isEmpty, !value.hasPrefix("-") else { return nil }
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            let platform = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
            return .accounts(filter: AccountsTabFilter(rawValue: parts[0]), platform: platform)
        }
    }

    /// The design's DEMO.groups and 11 Codex 专线 (S3D1-15): the App's only group fixture (X11). Member counts follow the demo
    /// accounts; S5-04 only adds the fields S5-01 brings.
    static let accountGroups: [AdminGroup] = [
        demoGroup(1, "高级组", "anthropic", rate: "0.8", members: 3, active: 3, rateLimited: 1),
        demoGroup(2, "标准组", "openai", rate: "0.8", rpm: 600, members: 2, active: 1),
        demoGroup(3, "默认组", "deepseek", rate: "0.8", members: 1, active: 1),
        demoGroup(4, "企业专线", "openai", rate: "1.2", exclusive: true, subscription: "subscription", rpm: 120, limits: (20, 100, 300), members: 1, active: 0),
        demoGroup(5, "Claude Code 组", "anthropic", rate: "0.8", exclusive: true, rpm: 60, members: 2, active: 2),
        demoGroup(6, "测试组", "gemini", rate: "0.6", status: "inactive", members: 1, active: 1),
        demoGroup(7, "GLM 组", "zhipu", rate: "0.8", members: 1, active: 1),
        demoGroup(8, "Kimi 组", "kimi", rate: "0.8", members: 1, active: 1),
        demoGroup(9, "MiniMax 组", "minimax", rate: "0.6", members: 1, active: 1),
        demoGroup(10, "Antigravity 组", "antigravity", rate: "1.0", members: 0, active: 0),
        demoGroup(11, "Codex 专线", "openai", rate: "1.0", exclusive: true, members: 0, active: 0)
    ]

    private static func demoGroup(_ id: Int, _ name: String, _ platform: String, rate: String, status: String = "active", exclusive: Bool = false,
                                  subscription: String = "standard", rpm: Int = 0, limits: (Decimal, Decimal, Decimal)? = nil, members: Int,
                                  active: Int, rateLimited: Int = 0) -> AdminGroup {
        AdminGroup(id: id, name: name, description: "", platform: platform, status: status, rateMultiplier: Decimal(string: rate), isExclusive: exclusive,
                   subscriptionType: subscription, dailyLimitUSD: limits?.0, weeklyLimitUSD: limits?.1, monthlyLimitUSD: limits?.2, rpmLimit: rpm,
                   accountCount: members, activeAccountCount: active, rateLimitedAccountCount: rateLimited, billingLocked: false,
                   createdAt: "2026-07-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z", sortOrder: id)
    }

    /// The design's DEMO.accounts (ids 1–5, 7–12), decoded from the backend's wire keys. Windows are offsets from `base`, the
    /// site clock when the session started.
    static func demoAccounts(base: Date, longWindows: Bool) -> [UpstreamAccount] {
        let windowShift: TimeInterval = longWindows ? 3_600 : 0
        let proxies = Dictionary(uniqueKeysWithValues: proxyRows(base: base).map { ($0["id"] as? Int ?? 0, accountProxyWire($0)) })
        func window(_ seconds: TimeInterval) -> String { ServerTime.utcTimestamp(base.addingTimeInterval(seconds + windowShift)) }
        let claudeLimits: [String: Any] = ["model_rate_limits": ["claude-opus-4": ["rate_limit_reset_at": window(720)],
                                                                 "claude-sonnet-4-5": ["rate_limit_reset_at": window(300)]]]
        let rows: [[String: Any]] = [
            demoAccount(3, "Claude-官方-03", "anthropic", "oauth", groups: [1], concurrency: (0, 4), priority: 1, proxy: proxies[1], fields: [
                "rate_limit_reset_at": window(277), "current_rpm": 1, "scheduling_rpm": 1, "base_rpm": 60, "active_sessions": 0, "max_sessions": 3,
                "session_idle_timeout_minutes": 5,
                "expires_at": Int(base.timeIntervalSince1970) + 36 * 86_400, "extra": claudeLimits,
                "credentials": ["model_mapping": ["claude-opus-4-1": "claude-opus-4", "claude-opus-4": "claude-opus-4",
                                                  "claude-sonnet-4-5": "claude-sonnet-4-5", "claude-3-5-sonnet-*": "claude-sonnet-4-5"]]]),
            demoAccount(7, "OpenAI-备用-A", "openai", "apikey", status: "error", schedulable: false, groups: [2, 4], concurrency: (0, 4), priority: 2,
                        proxy: proxies[2], fields: ["error_message": "401 凭据已失效（invalid_api_key）", "error_summary": "401 凭据已失效（invalid_api_key）",
                                           "error_kind": "auth", "error_status_code": 401, "error_at": ServerTime.utcTimestamp(base.addingTimeInterval(-60)),
                                           "credentials": ["model_mapping": ["gpt-5": "gpt-5"]], "extra": ["openai_passthrough": true]]),
            demoAccount(11, "GLM-直连-01", "zhipu", "apikey", groups: [7], concurrency: (0, 6), priority: 3, fields: ["overload_until": window(72),
                "credentials": ["account_mode": "coding", "api_protocol": "anthropic", "base_url": "https://open.bigmodel.cn/api/anthropic"]]),
            demoAccount(12, "MiniMax-01", "minimax", "apikey", groups: [9], concurrency: (0, 4), priority: 3, fields: [
                "temp_unschedulable_until": window(1_380), "temp_unschedulable_reason": temporaryReason(base: base, until: window(1_380)),
                "credentials": ["base_url": "https://minimax-relay.example.invalid/v1"]]),
            demoAccount(5, "Gemini-测试-B", "gemini", "apikey", schedulable: false, groups: [6], concurrency: (0, 2), priority: 5, proxy: proxies[3]),
            demoAccount(1, "Claude-官方-01", "anthropic", "oauth", groups: [1, 5], concurrency: (2, 4), priority: 1, proxy: proxies[1], fields: [
                "current_rpm": 14, "scheduling_rpm": 14, "base_rpm": 60, "active_sessions": 2, "max_sessions": 3, "session_idle_timeout_minutes": 5,
                "credentials": ["intercept_warmup_requests": true],
                "extra": ["window_cost_limit": 50, "max_sessions": 3, "base_rpm": 60, "enable_tls_fingerprint": true]]),
            demoAccount(2, "Claude-官方-02", "anthropic", "oauth", groups: [1, 5], concurrency: (3, 4), priority: 1, proxy: proxies[1], fields: [
                "current_rpm": 12, "scheduling_rpm": 12, "base_rpm": 60, "active_sessions": 3, "max_sessions": 3, "session_idle_timeout_minutes": 5]),
            demoAccount(4, "OpenAI-主力-01", "openai", "apikey", groups: [2], concurrency: (2, 8), priority: 1, proxy: proxies[2], fields: [
                "quota_daily_used": 96.3, "quota_daily_limit": 150,
                "credentials": ["model_mapping": ["gpt-5": "gpt-5", "gpt-5-mini": "gpt-5-mini", "gpt-4o": "gpt-4o"]]]),
            demoAccount(8, "DeepSeek-01", "deepseek", "apikey", groups: [3], concurrency: (0, 8), priority: 2, proxy: proxies[4]),
            demoAccount(9, "Kimi-01", "kimi", "apikey", groups: [8], concurrency: (1, 4), priority: 2, proxy: proxies[1], fields: [
                "proxy_fallback_origin_id": 4, "proxy_fallback_origin_name": "hk-01",
                "credentials": ["api_protocol": "anthropic", "base_url": "https://api.moonshot.cn/anthropic"]]),
            demoAccount(10, "Grok-旧-01", "grok", "apikey", status: "inactive", groups: [], concurrency: (0, 2), priority: 9)
        ]
        // try! only here: a wire key that no longer decodes stops the first UI test instead of showing a wrong list.
        return rows.map { try! JSONDecoder().decode(UpstreamAccount.self, from: JSONSerialization.data(withJSONObject: credentialFields($0, base: base))) }
    }

    private static func demoAccount(_ id: Int, _ name: String, _ platform: String, _ type: String, status: String = "active", schedulable: Bool = true,
                                    groups: [Int], concurrency: (Int, Int), priority: Int, proxy: [String: Any]? = nil,
                                    fields: [String: Any] = [:]) -> [String: Any] {
        let names = Dictionary(uniqueKeysWithValues: accountGroups.map { ($0.id, $0.name) })
        var json: [String: Any] = [
            "id": id, "name": name, "platform": platform, "type": type, "status": status, "schedulable": schedulable, "priority": priority,
            "group_ids": groups, "groups": groups.map { ["id": $0, "name": names[$0] ?? ""] as [String: Any] }, "current_concurrency": concurrency.0,
            "concurrency": concurrency.1, "concurrency_available": true, "created_at": "2026-08-01T00:00:00Z", "updated_at": "2026-10-15T00:00:00Z"
        ]
        if let proxy {
            json["proxy_id"] = proxy["id"]
            json["proxy"] = proxy
        }
        return json.merging(fields) { _, new in new }
    }

    /// `TempUnschedState` of MiniMax-01: rule #1 matched an upstream 529 (AccountDisplayState reads “上游 529 · 规则 #1”).
    private static func temporaryReason(base: Date, until: String) -> String {
        let untilUnix = Int((ServerTime.parseTimestamp(until) ?? base).timeIntervalSince1970)
        let state: [String: Any] = ["until_unix": untilUnix, "triggered_at_unix": Int(base.timeIntervalSince1970) - 1_320, "status_code": 529,
                                    "matched_keyword": "overloaded", "rule_index": 0, "error_message": "upstream overloaded", "trigger_count": 1]
        let data = (try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The design's DEMO.proxies on the backend's wire keys (60 §12.2), dates as offsets from `base`: hk-02 runs out in 6 days,
    /// jp-tokyo-1 and us-east-2 have expired, de-fra-1 is stopped. Addresses and passwords are made up.
    static func proxyRows(base: Date) -> [[String: Any]] {
        func day(_ days: Double) -> String { ServerTime.utcTimestamp(base.addingTimeInterval(days * 86_400)) }
        func row(_ id: Int, _ name: String, _ scheme: String, _ host: String, _ port: Int, status: String = "active", expires: Double?,
                 created: Double, warn: Int = 7, country: String? = nil, city: String? = nil) -> [String: Any] {
            var json: [String: Any] = ["id": id, "name": name, "protocol": scheme, "host": host, "port": port, "status": status,
                                       "created_at": day(created), "expires_at": expires.map(day) ?? NSNull(), "expiry_warn_days": warn,
                                       "username": "fixture", "password": "fixture-proxy-secret", "fallback_mode": "direct"]
            if let country { json["country_code"] = country }
            if let city { json["city"] = city }
            return json
        }
        return [
            row(1, "hk-02", "socks5", "203.0.113.24", 1080, expires: 6, created: -94, country: "HK"),
            row(2, "sg-01", "https", "198.51.100.7", 443, expires: 136, created: -55, country: "SG"),
            row(3, "jp-tokyo-1", "socks5h", "198.51.100.30", 1080, status: "expired", expires: -3, created: -180, country: "JP", city: "Tokyo"),
            row(4, "hk-01", "http", "203.0.113.9", 3128, expires: 45, created: -147, country: "HK"),
            row(5, "us-west-3", "http", "203.0.113.140", 8080, expires: nil, created: -52, country: "US", city: "Fremont"),
            row(6, "de-fra-1", "socks5", "198.51.100.61", 1080, status: "inactive", expires: 3, created: -40, warn: 3, country: "DE"),
            row(7, "us-east-2", "http", "198.51.100.77", 8080, status: "expired", expires: -5, created: -120, country: "US")
        ]
    }
    /// `proxies/all?with_count=true`'s rows, `account_count` from the given counts.
    static func accountProxies(base: Date, accountCounts: [Int: Int] = [:]) -> [AdminProxy] {
        // try! only here: a wire key that no longer decodes stops the first UI test instead of showing a wrong picker.
        proxyRows(base: base).map { row in
            var counted = row
            counted["account_count"] = accountCounts[row["id"] as? Int ?? 0] ?? 0
            return try! JSONDecoder().decode(AdminProxy.self, from: JSONSerialization.data(withJSONObject: counted))
        }
    }
    /// The account DTO's `proxy` (dto.Proxy): no login, no counts.
    static func accountProxyWire(_ row: [String: Any]) -> [String: Any] {
        row.filter { ["id", "name", "protocol", "host", "port", "status", "expires_at", "expiry_warn_days"].contains($0.key) }
    }

    /// DEMO.accounts' today figures: user_cost = todayCost, cost = todayAccountCost, standard_cost = todayStd.
    static let accountToday: [Int: AccountTodayStats] = [
        3: today(2_302, 14_220_000, account: "76.42", user: "192.62", standard: "240.78"),
        7: today(0, 0, account: "0", user: "0", standard: "0"),
        11: today(290, 1_400_000, account: "8.38", user: "18.4", standard: "23.0"),
        12: today(0, 0, account: "0", user: "0", standard: "0"),
        5: today(152, 900_000, account: "4.8", user: "10.8", standard: "18.0"),
        1: today(4_418, 27_270_000, account: "162.42", user: "409.38", standard: "511.73"),
        2: today(4_050, 25_010_000, account: "152.36", user: "384.05", standard: "480.06"),
        4: today(5_500, 20_700_000, account: "82.4", user: "203.5", standard: "254.38"),
        8: today(980, 4_600_000, account: "14.1", user: "38.6", standard: "48.25"),
        9: today(512, 2_300_000, account: "11.2", user: "27.15", standard: "33.94"),
        10: today(0, 0, account: "0", user: "0", standard: "0")
    ]
    private static func today(_ requests: Int, _ tokens: Int, account: String, user: String, standard: String) -> AccountTodayStats {
        AccountTodayStats(requests: requests, tokens: tokens, cost: Decimal(string: account)!, userCost: Decimal(string: user),
                          standardCost: Decimal(string: standard))
    }
}

/// The fixture site's accounts for one session (`current(for:)`), so a later item's write fixture changes them for that session
/// only. Lists, counts and sorting go through AccountListLocal, the same derivation an old server gets.
@MainActor
final class AccountDemoStore {
    let base: Date
    private(set) var accounts: [UpstreamAccount]
    private let arguments: [String]
    private var listReads = 0
    private var todayThrottleServed = false
    /// S2-17: the authorization sessions this session's links opened (DemoData+AccountReauth).
    var oauthSessions = AccountOAuthFixtureState()
    /// S2-19: creates this session has received (DemoData+AccountNew).
    var createAttempts = 0
    /// S2-20: the accounts this session created, how often each one's credentials were saved since, and the stops that failed.
    var createdIDs: Set<Int> = []
    var credentialRevisions: [Int: Int] = [:]
    var pauseFailures = 0
    private static var latest: (generation: UUID, store: AccountDemoStore)?
    private static let failure = APIError.server(status: 502, reason: nil)

    init(base: Date, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.base = base; self.arguments = arguments
        let demo = arguments.contains(DemoData.AccountFixture.empty)
            ? [] : DemoData.demoAccounts(base: base, longWindows: arguments.contains(DemoData.AccountFixture.longWindows))
        let grouped = arguments.contains(DemoData.AccountFixture.groupTransition) ? Self.joiningGroupTen(demo) : demo
        let expiring = arguments.contains(DemoData.AccountFixture.expired) ? Self.expiringDeepSeek(grouped, base: base) : grouped
        let backup = arguments.contains(DemoData.AccountFixture.bedrockError) ? Self.bedrockBackup(expiring) : expiring
        accounts = Self.tokenFixtures(backup, base: base, arguments: arguments)
    }
    private static func joiningGroupTen(_ rows: [UpstreamAccount]) -> [UpstreamAccount] {
        rows.map { row in
            guard [4, 7].contains(row.id) else { return row }
            var member = row
            member.groupIDs.append(10)
            return member
        }
    }
    /// Only the newest session's store is kept.
    static func current(for generation: UUID, base: @autoclosure () -> Date) -> AccountDemoStore {
        if let latest, latest.generation == generation { return latest.store }
        let store = AccountDemoStore(base: base())
        latest = (generation, store)
        return store
    }

    /// `GET admin/accounts`: filters and sorts like the server; counts only on page 1 with include_counts, under every filter but status.
    func page(_ page: Int, query: AccountListQuery, now: Date) throws -> AccountListPage {
        _ = try query.queryItems(page: page)
        if arguments.contains(DemoData.AccountFixture.listError) { throw Self.failure }
        if page == 1 { listReads += 1 }
        if arguments.contains(DemoData.AccountFixture.refreshError), listReads > 1 { throw Self.failure }
        var sent = query
        if query.needsLocalStatusFilter { sent.statuses = [] }
        let matched = accounts.filter { AccountListLocal.matches($0, query: sent, now: now) }
        let ordered = sent.sort == .urgency && sent.supportsListQuery
            ? AccountListLocal.urgencySorted(matched, now: now, descending: sent.descending) : Self.byName(matched, descending: sent.descending)
        let size = PageSize.clamped(sent.pageSize)
        var unfiltered = sent
        unfiltered.statuses = []
        let counts = page == 1 && sent.includeCounts && sent.supportsListQuery
            ? AccountListLocal.counts(accounts.filter { AccountListLocal.matches($0, query: unfiltered, now: now) }, now: now) : nil
        return AccountListPage(items: Array(ordered.dropFirst((page - 1) * size).prefix(size)), total: ordered.count, page: page, pageSize: size,
                               pages: max(1, (ordered.count + size - 1) / size), counts: counts)
    }

    /// `GET admin/accounts/status-summary`.
    func statusSummary(platform: String?, groupID: Int?, includeAccounts: Bool, now: Date) throws -> AccountStatusSummary {
        if arguments.contains(DemoData.AccountFixture.summaryError) { throw Self.failure }
        let platformID = platform?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rows = accounts.filter { (platformID.isEmpty || $0.platform == platformID) && (groupID.map($0.groupIDs.contains) ?? true) }
        let platforms = AccountListLayout.localPlatformCounts(rows, now: now).sorted { $0.key < $1.key }
            .map { AccountStatusPlatformSummary(platform: $0.key, counts: $0.value) }
        let groups = DemoData.accountGroups
            .filter { group in (platformID.isEmpty || group.platform == platformID) && (groupID.map { $0 == group.id } ?? true) }
            .map { group in
                AccountStatusGroupSummary(groupID: group.id, groupName: group.name, platform: group.platform, groupStatus: group.status,
                                          counts: AccountListLayout.localCounts(rows.filter { $0.groupIDs.contains(group.id) }, now: now))
            }
        return AccountStatusSummary(collectedAt: now, totals: AccountListLayout.localCounts(rows, now: now), platforms: platforms, groups: groups,
                                    accounts: includeAccounts ? rows.map { Self.statusItem($0, now: now) } : [])
    }

    /// `POST today-stats/batch`; with `todayError` every id fails, as a 503 does.
    func todayStats(ids: [Int]) -> AccountTodayStatsBatch {
        let requested = Set(ids.filter { $0 > 0 })
        if arguments.contains(DemoData.AccountFixture.todayError) { return AccountTodayStatsBatch(failedIDs: requested) }
        let known = Set(accounts.map(\.id))
        return AccountTodayStatsBatch(stats: DemoData.accountToday.filter { requested.contains($0.key) && known.contains($0.key) })
    }

    /// `POST runtime/batch`: deleted ids are left out.
    func runtime(ids: [Int]) -> [Int: AccountRuntime] {
        let requested = Set(ids)
        return Dictionary(uniqueKeysWithValues: accounts.filter { requested.contains($0.id) }.map { ($0.id, Self.runtime($0)) })
    }

    func account(id: Int) -> UpstreamAccount? { accounts.first { $0.id == id } }
    func replace(_ account: UpstreamAccount) { accounts = accounts.map { $0.id == account.id ? account : $0 } }
    func remove(id: Int) { accounts = accounts.filter { $0.id != id } }
    func insert(_ account: UpstreamAccount) { accounts.append(account) }

    // MARK: 写（S2-06）

    /// `config_version` by id (“cv-N”, from 1); PATCH and PUT move it on.
    private var versions: [Int: Int] = [:]
    /// Accounts whose `patchConflict` / `proxyConflict` edit already happened, and whether `patchTimeout` has lost its PATCH (S2-10).
    private var conflictServed: Set<Int> = []
    private var timeoutServed = false

    /// `POST :id/schedulable`.
    func setSchedulable(id: Int, enabled: Bool) throws -> UpstreamAccount {
        var account = try existing(id)
        if !enabled, arguments.contains(DemoData.AccountFixture.newPauseFail), createdIDs.contains(id), pauseFailures == 0 {
            pauseFailures += 1
            throw APIError(kind: .transport, message: "网络连接已中断")
        }
        account.schedulable = enabled
        replace(account)
        return account
    }
    /// `POST :id/recover-state`: an error goes back to active, every window and model limit is cleared; true / false set the switch.
    func recover(id: Int, schedulable: Bool?) throws -> UpstreamAccount {
        var account = try existing(id)
        if account.status == "error" {
            account.status = "active"
            account.errorMessage = nil; account.errorSummary = nil; account.errorKind = nil; account.errorStatusCode = nil; account.errorAt = nil
        }
        account.rateLimitResetAt = nil; account.overloadUntil = nil; account.tempUnschedulableUntil = nil; account.tempUnschedulableReason = nil
        if let fields = account.extra?.raw.objectValue {
            account.extra = try? AccountExtra(raw: .object(fields.filter { $0.key != "model_rate_limits" }))
        }
        if let schedulable { account.schedulable = schedulable }
        replace(account)
        return account
    }
    /// `GET :id` with its ETag; `detailError` and `removed` fail it (S2-08), `legacyServer` answers like an old server (S2-10).
    func versioned(id: Int) throws -> VersionedAccount {
        if arguments.contains(DemoData.AccountFixture.removed) { throw APIError.server(status: 404, reason: AccountWriteReason.notFound) }
        if arguments.contains(DemoData.AccountFixture.detailError) { throw Self.failure }
        if arguments.contains(DemoData.AccountFixture.legacyServer) { return VersionedAccount(account: Self.inTheClear(try existing(id)), etag: nil) }
        return VersionedAccount(account: try existing(id), etag: etag(id))
    }
    /// `slowDetail`'s wait before `GET :id` answers; cancelling the read ends it.
    var detailReadDelay: Duration? { arguments.contains(DemoData.AccountFixture.slowDetail) ? .seconds(8) : nil }
    /// `PATCH :id` (S2-10): If-Match must name the current version (412 ACCOUNT_VERSION_CONFLICT with current_etag), changed
    /// groups meet the mixed-channel rule (409), and every key takes effect.
    func patch(id: Int, request: AccountPatchRequest, ifMatch: String, arguments: [String]) throws -> VersionedAccount {
        _ = try request.requestBody()
        var account = try existing(id)
        if arguments.contains(DemoData.AccountFixture.patchConflict), conflictServed.insert(id).inserted {
            account.notes = DemoData.AccountFixture.otherAdminNotes
            replace(account)
            bump(id)
        }
        if arguments.contains(DemoData.AccountFixture.proxyConflict), conflictServed.insert(id).inserted {
            account.proxyID = DemoData.AccountFixture.otherAdminProxyID
            account.proxy = proxyObject(id: DemoData.AccountFixture.otherAdminProxyID)
            replace(account)
            bump(id)
        }
        if arguments.contains(DemoData.AccountFixture.patchTimeout), !timeoutServed {
            timeoutServed = true
            throw APIError(kind: .transport, message: "连接超时，请检查网络后重试。")
        }
        guard ifMatch == etag(id) else {
            let metadata = ["current_etag": etag(id), "current_config_version": String(versions[id] ?? 1)]
            throw APIError.server(status: 412, envelope: ErrorEnvelope(reason: AccountWriteReason.versionConflict, metadata: metadata))
        }
        try refuseMixedChannel(request, account: account, arguments: arguments)
        let updated = withProxyObject(Self.applying(request, to: account), changed: request.proxyID != nil)
        replace(updated)
        bump(id)
        if createdIDs.contains(id), !request.credentialsPatch.isEmpty { credentialRevisions[id, default: 0] += 1 }
        return VersionedAccount(account: updated, etag: etag(id))
    }
    /// `PUT :id`, the fallback without `accounts.patch`: the body the client would build, then the same rules as PATCH.
    func fullUpdate(id: Int, patch: AccountPatchRequest, base: UpstreamAccount?, arguments: [String]) throws -> UpstreamAccount {
        _ = try patch.fullUpdateBody(base: base)
        let account = try existing(id)
        try refuseMixedChannel(patch, account: account, arguments: arguments)
        let updated = withProxyObject(Self.applying(patch, to: account), changed: patch.proxyID != nil)
        replace(updated)
        bump(id)
        return updated
    }

    /// `POST bulk-update {account_ids, schedulable}` (S2-07): ids the site does not have are left out of the reply, as a vendor's
    /// out-of-scope ids are; with `bulkPartial` an account in error fails on its own and keeps its switch.
    func bulkSetSchedulable(ids: [Int], enabled: Bool) throws -> AccountBulkReply {
        if arguments.contains(DemoData.AccountFixture.bulkFail) { throw APIError.server(status: 500, reason: nil) }
        let refuses = arguments.contains(DemoData.AccountFixture.bulkPartial)
        var items: [AccountBulkReply.Item] = []
        for id in ids {
            guard var account = account(id: id) else { continue }
            if refuses, account.status == "error" {
                items.append(AccountBulkReply.Item(accountID: id, success: false, error: "fixture"))
                continue
            }
            account.schedulable = enabled
            replace(account)
            items.append(AccountBulkReply.Item(accountID: id, success: true))
        }
        let succeeded = items.filter(\.success).map(\.accountID), failed = items.filter { !$0.success }.map(\.accountID)
        return AccountBulkReply(success: succeeded.count, failed: failed.count, successIDs: succeeded, failedIDs: failed, results: items)
    }

    private func existing(_ id: Int) throws -> UpstreamAccount {
        guard let account = account(id: id) else { throw APIError.server(status: 404, reason: AccountWriteReason.notFound) }
        return account
    }
    private func etag(_ id: Int) -> String { "\"cv-\(versions[id] ?? 1)\"" }
    func bump(_ id: Int) { versions[id] = (versions[id] ?? 1) + 1 }

    private static func byName(_ rows: [UpstreamAccount], descending: Bool) -> [UpstreamAccount] {
        let sorted = rows.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        return descending ? sorted.reversed() : sorted
    }
    private static func statusItem(_ account: UpstreamAccount, now: Date) -> AccountStatusItem {
        let input = AccountStateInput(account), display = AccountDisplayState(input, now: now)
        return AccountStatusItem(id: account.id, name: account.name, platform: account.platform, groupIDs: account.groupIDs, state: display.state,
                                 stopped: display.isStopped, status: account.status, schedulable: account.schedulable,
                                 rateLimitResetAt: input.rateLimitResetAt, overloadUntil: input.overloadUntil,
                                 tempUnschedulableUntil: input.tempUnschedulableUntil, tempUnschedulableReason: account.tempUnschedulableReason,
                                 expiresAt: input.expiresAt, modelRateLimits: display.modelRateLimits)
    }
    private static func runtime(_ account: UpstreamAccount) -> AccountRuntime {
        let input = AccountStateInput(account)
        return AccountRuntime(status: account.status, schedulable: account.schedulable, currentConcurrency: account.currentConcurrency,
                              probeConcurrency: account.probeConcurrency, concurrencyAvailable: account.concurrencyAvailable,
                              currentRPM: account.currentRPM, schedulingRPM: account.schedulingRPM, activeSessions: account.activeSessions,
                              rateLimitResetAt: input.rateLimitResetAt, overloadUntil: input.overloadUntil,
                              tempUnschedulableUntil: input.tempUnschedulableUntil)
    }
}

// MARK: - 详情三节（S2-09）

extension AccountDemoStore {
    /// `GET :id/today-stats` from DemoData.accountToday: 503 under `todayError`; under `todayThrottled` the first read is a 429 with
    /// retry_after 8.
    func todayStats(id: Int) throws -> AccountTodayStats {
        if arguments.contains(DemoData.AccountFixture.todayThrottled), !todayThrottleServed {
            todayThrottleServed = true
            throw APIError.server(status: 429, envelope: nil, retryAfter: 8)
        }
        guard let stats = todayStats(ids: [id]).stats[id] else { throw APIError.server(status: 503, reason: "ACCOUNT_STATS_UNAVAILABLE") }
        return stats
    }
    /// `GET :id/usage?source=passive`: Claude-官方-01 at 42%, Claude-官方-03 full (the design's window5h 1.0), Claude-官方-02 without
    /// a session window yet.
    func passiveUsage(id: Int) -> AccountUsageWindow {
        switch id {
        case 1: AccountUsageWindow(fiveHour: .init(utilization: 42, resetsAt: base.addingTimeInterval(7_980), remainingSeconds: 7_980))
        case 3: AccountUsageWindow(fiveHour: .init(utilization: 100, resetsAt: base.addingTimeInterval(1_980), remainingSeconds: 1_980))
        default: AccountUsageWindow(fiveHour: nil)
        }
    }
    /// `upstream-errors?account_id&time_range=24h&page_size=1`: OpenAI-备用-A has 3 (the newest a 401 at its `error_at`),
    /// Claude-官方-03 2 (the newest recovered after a 429), the others none. The ops switch of `-ui-ops-disabled` /
    /// `-ui-ops-config-off` (OpsFixtureSwitch) answers 404 OPS_DISABLED.
    func upstreamErrorPage(id: Int) throws -> Page<RequestErrorRecord> {
        if OpsFixtureSwitch.from(arguments: arguments) != .on { throw LiveOpsFixtures.opsDisabledError }
        let newest: [String: Any]?, total: Int
        switch id {
        case 7:
            newest = Self.upstreamRow(9_701, platform: "openai", status: 401, message: "Upstream authentication failed",
                                      at: account(id: 7)?.errorAt ?? ServerTime.utcTimestamp(base.addingTimeInterval(-60)))
            total = 3
        case 3:
            newest = Self.upstreamRow(9_703, platform: "anthropic", status: 200, message: "Recovered upstream error 429: rate limited",
                                      at: ServerTime.utcTimestamp(base.addingTimeInterval(-300)))
            total = 2
        default:
            newest = nil; total = 0
        }
        // try! only here: a row that no longer decodes stops the first UI test instead of showing a wrong count.
        let items = newest.map { [try! JSONDecoder().decode(RequestErrorRecord.self, from: JSONSerialization.data(withJSONObject: $0))] } ?? []
        return Page(items: items, total: total, page: 1, pageSize: 1, pages: max(1, total))
    }

    private static func upstreamRow(_ id: Int, platform: String, status: Int, message: String, at createdAt: String) -> [String: Any] {
        ["id": id, "created_at": createdAt, "request_id": "req-upstream-\(id)", "phase": "upstream", "type": "upstream_error", "status_code": status,
         "platform": platform, "model": "demo-model", "resolved": false, "message": message]
    }
}

// MARK: - S2-10 内联编辑

extension AccountDemoStore {
    /// S2D1-14, the backend's checkMixedChannelRisk: only Anthropic and Antigravity accounts; a group is at risk when another
    /// member (not this account) is of the other one. `mixedChannel` also puts every request naming group 1 at risk.
    func mixedChannelCheck(platform: String, groupIDs: [Int], accountID: Int?, arguments: [String]) -> MixedChannelCheck {
        guard let mine = Self.mixedPlatform(platform) else { return MixedChannelCheck(hasRisk: false) }
        let other = mine == "Anthropic" ? "Antigravity" : "Anthropic"
        let forced = arguments.contains(DemoData.AccountFixture.mixedChannel)
        let risky = groupIDs.first { id in
            (forced && id == 1) || accounts.contains { $0.id != accountID && $0.groupIDs.contains(id) && Self.mixedPlatform($0.platform) == other }
        }
        guard let risky else { return MixedChannelCheck(hasRisk: false) }
        let name = DemoData.accountGroups.first { $0.id == risky }?.name ?? "#\(risky)"
        return MixedChannelCheck(hasRisk: true, details: .init(groupID: risky, groupName: name, currentPlatform: mine, otherPlatform: other))
    }

    /// 409 MIXED_CHANNEL_WARNING for changed groups not yet confirmed.
    fileprivate func refuseMixedChannel(_ request: AccountPatchRequest, account: UpstreamAccount, arguments: [String]) throws {
        guard let groups = request.groupIDs, request.confirmMixedChannelRisk != true else { return }
        if let conflict = mixedChannelConflict(platform: account.platform, groupIDs: groups, accountID: account.id, arguments: arguments) { throw conflict }
    }
    /// The 409 these groups get (PATCH, PUT and S2-19's create); without accounts.mixed_channel_details it has no metadata, as an
    /// older server's.
    func mixedChannelConflict(platform: String, groupIDs: [Int], accountID: Int?, arguments: [String]) -> APIError? {
        let check = mixedChannelCheck(platform: platform, groupIDs: groupIDs, accountID: accountID, arguments: arguments)
        guard check.hasRisk, let details = check.details else { return nil }
        let detailed = !DemoData.withheldCapabilities(arguments: arguments).contains(Capability.accountsMixedChannelDetails.rawValue)
        let metadata = ["group_id": String(details.groupID ?? 0), "group_name": details.groupName,
                        "current_platform": details.currentPlatform, "other_platform": details.otherPlatform]
        return APIError.server(status: 409, envelope: ErrorEnvelope(reason: AccountWriteReason.mixedChannelWarning, metadata: detailed ? metadata : nil))
    }

    /// Every key of 20 §3.2 the edit sheets send: ≤ 0 clears the load factor and the expiry, "" the notes; groups take their
    /// fixture names; `extra_patch` merges into extra and the quota limits show on the account as the DTO flattens them.
    fileprivate static func applying(_ request: AccountPatchRequest, to account: UpstreamAccount) -> UpstreamAccount {
        var updated = account
        if let name = request.name { updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let notes = request.notes { updated.notes = notes.isEmpty ? nil : notes }
        if let status = request.status { updated.status = status.rawValue }
        if let value = request.concurrency { updated.concurrency = value }
        if let value = request.priority { updated.priority = value }
        if let value = request.rateMultiplier { updated.rateMultiplier = value }
        if let value = request.loadFactor { updated.loadFactor = value > 0 ? value : nil }
        // 0 is 无代理; like the server, a manual change keeps the fallback mark (only revert and the expiry sweep write it).
        if let value = request.proxyID { updated.proxyID = value > 0 ? value : nil }
        if let ids = request.groupIDs {
            updated.groupIDs = ids
            updated.groups = ids.map { id in .init(id: id, name: DemoData.accountGroups.first { $0.id == id }?.name ?? "#\(id)") }
        }
        if let value = request.expiresAt { updated.expiresAt = value > 0 ? value : nil }
        if let value = request.autoPauseOnExpired { updated.autoPauseOnExpired = value }
        // S2-12: the probe switch is stored in extra; credentials_patch merges like extra_patch (secrets are never read back).
        var extraPatch = request.extraPatch
        if let probe = request.upstreamBillingProbeEnabled { extraPatch["upstream_billing_probe_enabled"] = .set(.bool(probe)) }
        // Like the server, the probe going off takes the rate sync with it.
        if let sync = request.upstreamBillingProbeEnabled == false ? false : request.upstreamBillingRateSyncEnabled {
            extraPatch["upstream_billing_rate_sync_enabled"] = .set(.bool(sync))
        }
        if !request.credentialsPatch.isEmpty {
            let fields = merging(updated.credentials?.objectValue ?? [:], request.credentialsPatch.filter { !AccountCredentialKeys.isSensitive($0.key) })
            updated.credentials = .object(fields)
            // S2-16: a new secret only shows as has_<key>, like the server's credentials_status.
            let secrets = request.credentialsPatch.keys.filter(AccountCredentialKeys.isSensitive).map { ("has_" + $0, true) }
            if !secrets.isEmpty { updated.credentialsStatus = (updated.credentialsStatus ?? [:]).merging(secrets) { _, new in new } }
        }
        return extraPatch.isEmpty ? updated : withExtra(extraPatch, on: updated)
    }
    private static func merging(_ fields: [String: JSONValue], _ patch: [String: JSONPatchValue]) -> [String: JSONValue] {
        var fields = fields
        for (key, change) in patch {
            if case .set(let value) = change, !change.isDeletion { fields[key] = value } else { fields[key] = nil }
        }
        return fields
    }
    private static func withExtra(_ patch: [String: JSONPatchValue], on account: UpstreamAccount) -> UpstreamAccount {
        var updated = account
        let fields = merging(account.extra?.raw.objectValue ?? [:], patch)
        updated.extra = try? AccountExtra(raw: .object(fields))
        // The DTO's top-level copies of the 高级 limits (S2-12), which 容量 reads.
        if patch["base_rpm"] != nil { updated.baseRPM = fields["base_rpm"]?.intValue.flatMap { $0 > 0 ? $0 : nil } }
        if patch["max_sessions"] != nil { updated.maxSessions = fields["max_sessions"]?.intValue.flatMap { $0 > 0 ? $0 : nil } }
        if patch["window_cost_limit"] != nil { updated.windowCostLimit = fields["window_cost_limit"]?.decimalValue.flatMap { $0 > 0 ? $0 : nil } }
        for quota in AccountQuota.allCases where patch[quota.extraKey] != nil {
            let limit = fields[quota.extraKey]?.decimalValue
            switch quota {
            case .daily: updated.quotaDailyLimit = limit
            case .weekly: updated.quotaWeeklyLimit = limit
            case .total: updated.quotaLimit = limit
            }
        }
        return updated
    }
    private static func mixedPlatform(_ platform: String) -> String? {
        switch platform.lowercased() {
        case "anthropic", "claude": "Anthropic"
        case "antigravity": "Antigravity"
        default: nil
        }
    }
    /// The account as a server before credential redaction sends it: a key in the clear, which the decoder drops and marks.
    fileprivate static func inTheClear(_ account: UpstreamAccount) -> UpstreamAccount {
        guard let data = try? JSONEncoder().encode(account),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return account }
        json["credentials"] = ["api_key": "legacy-fixture-key", "base_url": "https://api.example.invalid"]
        guard let raw = try? JSONSerialization.data(withJSONObject: json),
              let decoded = try? JSONDecoder().decode(UpstreamAccount.self, from: raw) else { return account }
        return decoded
    }
    fileprivate static func expiringDeepSeek(_ rows: [UpstreamAccount], base: Date) -> [UpstreamAccount] {
        rows.map { row in
            guard row.id == 8 else { return row }
            var expired = row
            expired.expiresAt = Int64(base.timeIntervalSince1970) - 3_600
            expired.autoPauseOnExpired = true
            return expired
        }
    }
}

// MARK: - S2-11 代理、恢复原代理、删除

extension AccountDemoStore {
    /// `GET proxies/all?with_count=true`: the active proxies newest first, counted over this session's accounts.
    func activeProxies() throws -> [AdminProxy] {
        if arguments.contains(DemoData.AccountFixture.proxiesError) { throw Self.failure }
        let counts = Dictionary(grouping: accounts.compactMap(\.proxyID), by: { $0 }).mapValues(\.count)
        return DemoData.accountProxies(base: base, accountCounts: counts).filter(\.isActive)
            .sorted { ($0.createdAt ?? .distantPast, $0.id) > ($1.createdAt ?? .distantPast, $1.id) }
    }
    /// The account DTO's `proxy` for an id.
    func proxyObject(id: Int) -> AccountProxy? {
        guard let row = DemoData.proxyRows(base: base).first(where: { $0["id"] as? Int == id }),
              let data = try? JSONSerialization.data(withJSONObject: DemoData.accountProxyWire(row)) else { return nil }
        return try? JSONDecoder().decode(AccountProxy.self, from: data)
    }
    /// `POST :id/revert-proxy-fallback`: back on the original proxy unless it is gone, stopped or expired (409); 400 when the
    /// account is not fallen back. `revertNotInFallback` lets another administrator revert it first.
    func revertProxyFallback(id: Int) throws {
        let account = try existing(id)
        if arguments.contains(DemoData.AccountFixture.revertNotInFallback), let origin = account.proxyFallbackOriginID {
            replace(Self.reverted(account, to: origin, proxy: proxyObject(id: origin)))
            bump(id)
            throw APIError.server(status: 400, reason: AccountWriteReason.notInFallback)
        }
        guard let origin = account.proxyFallbackOriginID else { throw APIError.server(status: 400, reason: AccountWriteReason.notInFallback) }
        let usable = DemoData.accountProxies(base: base).first { $0.id == origin }.map { $0.isActive && ($0.expiresAt.map { $0 > base } ?? true) }
        if arguments.contains(DemoData.AccountFixture.revertOriginUnavailable) || usable != true {
            throw APIError.server(status: 409, reason: AccountWriteReason.fallbackOriginUnavailable)
        }
        replace(Self.reverted(account, to: origin, proxy: proxyObject(id: origin)))
        bump(id)
    }
    /// `DELETE :id`: an id already gone is the server's idempotent success.
    func delete(id: Int) -> DeleteResult {
        guard account(id: id) != nil else { return .alreadyGone }
        remove(id: id)
        return .deleted
    }

    fileprivate func withProxyObject(_ account: UpstreamAccount, changed: Bool) -> UpstreamAccount {
        guard changed else { return account }
        var updated = account
        updated.proxy = account.proxyID.flatMap(proxyObject(id:))
        return updated
    }
    private static func reverted(_ account: UpstreamAccount, to origin: Int, proxy: AccountProxy?) -> UpstreamAccount {
        var updated = account
        updated.proxyID = origin
        updated.proxy = proxy
        updated.proxyFallbackOriginID = nil
        updated.proxyFallbackOriginName = nil
        return updated
    }
    fileprivate static func bedrockBackup(_ rows: [UpstreamAccount]) -> [UpstreamAccount] {
        rows.map { row in
            guard row.id == 7 else { return row }
            var bedrock = row
            bedrock.type = "bedrock"
            return bedrock
        }
    }
}

// MARK: - S2-12 模型

extension DemoData {
    /// `GET :id/models` by platform (design AE_MODELS): Anthropic with display names as claude.DefaultModels sends them, the
    /// others ids only, which the list shows as they are.
    static let accountModelOptions: [String: [AccountModelOption]] = [
        "anthropic": [.init(id: "claude-opus-4-1", displayName: "Claude Opus 4.1"), .init(id: "claude-opus-4", displayName: "Claude Opus 4"),
                      .init(id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5"), .init(id: "claude-sonnet-4", displayName: "Claude Sonnet 4"),
                      .init(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5")],
        "openai": ["gpt-5", "gpt-5-mini", "gpt-4.1", "gpt-4o", "o4-mini"].map { AccountModelOption(id: $0) },
        "gemini": ["gemini-2.5-pro", "gemini-2.5-flash"].map { AccountModelOption(id: $0) },
        "zhipu": ["glm-4.6", "glm-4.5", "glm-4.5-air"].map { AccountModelOption(id: $0) },
        "minimax": ["MiniMax-M2"].map { AccountModelOption(id: $0) },
        "deepseek": ["deepseek-chat", "deepseek-reasoner"].map { AccountModelOption(id: $0) },
        "kimi": ["kimi-k2-0905-preview", "kimi-k2-turbo-preview"].map { AccountModelOption(id: $0) },
        "grok": ["grok-4", "grok-3-mini"].map { AccountModelOption(id: $0) }
    ]
}

extension AccountDemoStore {
    /// `GET :id/models`: the account's platform list; 404 for an id the site does not have, 502 under `modelsError`.
    func models(id: Int) throws -> [AccountModelOption] {
        if arguments.contains(DemoData.AccountFixture.modelsError) { throw Self.failure }
        guard let account = account(id: id) else { throw APIError.server(status: 404, reason: AccountWriteReason.notFound) }
        return DemoData.accountModelOptions[account.platform] ?? []
    }
}
