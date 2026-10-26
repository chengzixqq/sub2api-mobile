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
        func window(_ seconds: TimeInterval) -> String { ServerTime.utcTimestamp(base.addingTimeInterval(seconds + windowShift)) }
        let claudeLimits: [String: Any] = ["model_rate_limits": ["claude-opus-4": ["rate_limit_reset_at": window(720)],
                                                                 "claude-sonnet-4-5": ["rate_limit_reset_at": window(300)]]]
        let rows: [[String: Any]] = [
            demoAccount(3, "Claude-官方-03", "anthropic", "oauth", groups: [1], concurrency: (0, 4), priority: 1, proxy: 1, fields: [
                "rate_limit_reset_at": window(277), "current_rpm": 1, "base_rpm": 60, "active_sessions": 0, "max_sessions": 3,
                "expires_at": Int(base.timeIntervalSince1970) + 36 * 86_400, "extra": claudeLimits]),
            demoAccount(7, "OpenAI-备用-A", "openai", "apikey", status: "error", schedulable: false, groups: [2, 4], concurrency: (0, 4), priority: 2,
                        proxy: 2, fields: ["error_message": "401 凭据已失效（invalid_api_key）", "error_summary": "401 凭据已失效（invalid_api_key）",
                                           "error_kind": "auth", "error_status_code": 401, "error_at": ServerTime.utcTimestamp(base.addingTimeInterval(-60))]),
            demoAccount(11, "GLM-直连-01", "zhipu", "apikey", groups: [7], concurrency: (0, 6), priority: 3, fields: ["overload_until": window(72)]),
            demoAccount(12, "MiniMax-01", "minimax", "apikey", groups: [9], concurrency: (0, 4), priority: 3, fields: [
                "temp_unschedulable_until": window(1_380), "temp_unschedulable_reason": temporaryReason(base: base, until: window(1_380))]),
            demoAccount(5, "Gemini-测试-B", "gemini", "apikey", schedulable: false, groups: [6], concurrency: (0, 2), priority: 5, proxy: 3),
            demoAccount(1, "Claude-官方-01", "anthropic", "oauth", groups: [1, 5], concurrency: (2, 4), priority: 1, proxy: 1, fields: [
                "current_rpm": 14, "base_rpm": 60, "active_sessions": 2, "max_sessions": 3]),
            demoAccount(2, "Claude-官方-02", "anthropic", "oauth", groups: [1, 5], concurrency: (3, 4), priority: 1, proxy: 1, fields: [
                "current_rpm": 12, "base_rpm": 60, "active_sessions": 3, "max_sessions": 3]),
            demoAccount(4, "OpenAI-主力-01", "openai", "apikey", groups: [2], concurrency: (2, 8), priority: 1, proxy: 2, fields: [
                "quota_daily_used": 96.3, "quota_daily_limit": 150]),
            demoAccount(8, "DeepSeek-01", "deepseek", "apikey", groups: [3], concurrency: (0, 8), priority: 2, proxy: 4),
            demoAccount(9, "Kimi-01", "kimi", "apikey", groups: [8], concurrency: (1, 4), priority: 2, proxy: 4),
            demoAccount(10, "Grok-旧-01", "grok", "apikey", status: "inactive", groups: [], concurrency: (0, 2), priority: 9)
        ]
        // try! only here: a wire key that no longer decodes stops the first UI test instead of showing a wrong list.
        return rows.map { try! JSONDecoder().decode(UpstreamAccount.self, from: JSONSerialization.data(withJSONObject: $0)) }
    }

    /// The design's proxies the demo accounts use (id → name, status).
    private static let demoProxies: [Int: (name: String, status: String)] = [1: ("hk-02", "active"), 2: ("sg-01", "active"),
                                                                             3: ("jp-tokyo-1", "expired"), 4: ("hk-01", "active")]

    private static func demoAccount(_ id: Int, _ name: String, _ platform: String, _ type: String, status: String = "active", schedulable: Bool = true,
                                    groups: [Int], concurrency: (Int, Int), priority: Int, proxy: Int? = nil,
                                    fields: [String: Any] = [:]) -> [String: Any] {
        let names = Dictionary(uniqueKeysWithValues: accountGroups.map { ($0.id, $0.name) })
        var json: [String: Any] = [
            "id": id, "name": name, "platform": platform, "type": type, "status": status, "schedulable": schedulable, "priority": priority,
            "group_ids": groups, "groups": groups.map { ["id": $0, "name": names[$0] ?? ""] as [String: Any] }, "current_concurrency": concurrency.0,
            "concurrency": concurrency.1, "concurrency_available": true, "created_at": "2026-08-01T00:00:00Z", "updated_at": "2026-10-15T00:00:00Z"
        ]
        if let proxy, let entry = demoProxies[proxy] {
            json["proxy_id"] = proxy
            json["proxy"] = ["id": proxy, "name": entry.name, "status": entry.status] as [String: Any]
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
    private static var latest: (generation: UUID, store: AccountDemoStore)?
    private static let failure = APIError.server(status: 502, reason: nil)

    init(base: Date, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.base = base; self.arguments = arguments
        accounts = arguments.contains(DemoData.AccountFixture.empty)
            ? [] : DemoData.demoAccounts(base: base, longWindows: arguments.contains(DemoData.AccountFixture.longWindows))
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
