import Foundation
import Sub2Core

// S1-07: the fallback reads of `-ui-testing`, made from the default home fixture so the overview reads the same on either path
// (LiveOpsStoreFallbackTests compares them). Other home variants keep their own alerts and status summary here, but the stats,
// trend, groups and accounts are always those of the default one.
extension LiveOpsFixtures {
    /// The `-ui-without-capabilities` value of a site from before `dashboard.home`. UI tests copy this literal (they cannot import
    /// the App), and add `-ui-home-legacy` for the home request itself.
    static let homeLegacyWithheldCapabilities = "dashboard.home,dashboard.rates,dashboard.account_cost,accounts.status_summary,ops.alert_event_counts"

    /// The home's ops block as the overview of the last five minutes (230 requests: RPM 46, TPM 240K).
    static func fiveMinuteOverview(base: Date) -> OpsOverview {
        OpsOverview(startTime: base.addingTimeInterval(-300), endTime: base, healthScore: 94, sla: 0.992, errorRate: 0.008, requestCountTotal: 230,
                    tokenConsumed: 1_200_000, upstream429Count: 12, upstream529Count: 3)
    }
    /// `dashboard/stats` with today and the RPM / TPM of the home fixture.
    static func dashboardStats(_ base: Date) -> DashboardStats {
        let today = stats(base), live = rates(base: base, opsDisabled: false)
        return DashboardStats(todayRequests: today.todayRequests ?? 0, todayTokens: today.todayTokens ?? 0, todayCost: today.todayCost ?? 0, totalUsers: 0,
                              totalAccounts: 11, errorAccounts: 1, rpm: live.rpm ?? 0, tpm: live.tpm ?? 0, todayActualCost: today.todayActualCost,
                              todayAccountCost: today.todayAccountCost, rpmAvailable: true,
                              statsUpdatedAt: today.statsUpdatedAt.map(ServerTime.utcTimestamp), statsStale: false)
    }
    /// `dashboard/trend` by the hour for yesterday and today.
    static func hourlyTrend(_ base: Date) -> DashboardTrendReply {
        let hours = hourly(base)
        let points = (hours.yesterday + hours.today).map {
            TrendPoint(date: $0.date, requests: $0.requests, totalTokens: $0.totalTokens, cost: $0.actualCost, actualCost: $0.actualCost)
        }
        return DashboardTrendReply(points: points, timeZone: serverTimeZone.timeZone)
    }
    /// 昨日同时 as the one day bucket the explicit range returns.
    static func yesterdayTrend(_ base: Date, start: Date) -> DashboardTrendReply {
        let today = stats(base), cost = today.yesterdaySameTimeActualCost ?? 0
        let point = TrendPoint(date: serverTimeZone.dayString(start), requests: today.yesterdaySameTimeRequests ?? 0, totalTokens: 0, cost: cost,
                               actualCost: cost)
        return DashboardTrendReply(points: [point], timeZone: serverTimeZone.timeZone)
    }
    /// DemoData.accountGroups' names and member counts (X11), so only 企业专线 is short of accounts that need attention.
    static func groups() -> [AdminGroup] {
        let rows: [(id: Int, name: String, platform: String, status: String, members: Int, active: Int)] = [
            (1, "高级组", "anthropic", "active", 3, 3), (2, "标准组", "openai", "active", 2, 1), (3, "默认组", "deepseek", "active", 1, 1),
            (4, "企业专线", "openai", "active", 1, 0), (5, "Claude Code 组", "anthropic", "active", 2, 2), (6, "测试组", "gemini", "inactive", 1, 1),
            (7, "GLM 组", "zhipu", "active", 1, 1), (8, "Kimi 组", "kimi", "active", 1, 1), (9, "MiniMax 组", "minimax", "active", 1, 1),
            (10, "Antigravity 组", "antigravity", "active", 0, 0), (11, "Codex 专线", "openai", "active", 0, 0)]
        return rows.map {
            AdminGroup(id: $0.id, name: $0.name, platform: $0.platform, status: $0.status, accountCount: $0.members, activeAccountCount: $0.active)
        }
    }
    /// AccountDemoStore's eleven accounts (lite fields only) with the home fixture's windows: the same D02 buckets as
    /// `availability(.allOK)`.
    static func accounts(base: Date) -> [UpstreamAccount] {
        func window(_ seconds: TimeInterval) -> String { ServerTime.utcTimestamp(base.addingTimeInterval(seconds)) }
        func row(_ id: Int, _ name: String, _ platform: String, status: String = "active", schedulable: Bool = true, groups: [Int],
                 rateLimit: String? = nil, overload: String? = nil, temporary: String? = nil) -> UpstreamAccount {
            UpstreamAccount(id: id, name: name, platform: platform, type: "apikey", status: status, schedulable: schedulable, groupIDs: groups,
                            rateLimitResetAt: rateLimit, overloadUntil: overload, tempUnschedulableUntil: temporary)
        }
        return [row(LiveOpsFixtureIDs.rateLimitedAccount, "Claude-官方-03", "anthropic", groups: [1], rateLimit: window(2_700)),
                row(LiveOpsFixtureIDs.errorAccount, "OpenAI-备用-A", "openai", status: "error", schedulable: false, groups: [2, 4]),
                row(LiveOpsFixtureIDs.overloadedAccount, "GLM-直连-01", "zhipu", groups: [7], overload: window(1_800)),
                row(LiveOpsFixtureIDs.tempUnschedulableAccount, "MiniMax-01", "minimax", groups: [9], temporary: window(3_000)),
                row(5, "Gemini-测试-B", "gemini", schedulable: false, groups: [6]), row(1, "Claude-官方-01", "anthropic", groups: [1, 5]),
                row(2, "Claude-官方-02", "anthropic", groups: [1, 5]), row(4, "OpenAI-主力-01", "openai", groups: [2]),
                row(8, "DeepSeek-01", "deepseek", groups: [3]), row(9, "Kimi-01", "kimi", groups: [8]),
                row(10, "Grok-旧-01", "grok", status: "inactive", groups: [])]
    }
}

extension FixtureLiveOpsSource {
    func dashboardStats() -> DashboardStats { LiveOpsFixtures.dashboardStats(base) }
    func dashboardCostSnapshot() -> DashboardCostSnapshot {
        let today = LiveOpsFixtures.stats(base)
        return DashboardCostSnapshot(actual: today.todayActualCost ?? 0, account: today.todayAccountCost ?? 0)
    }
    func dashboardTrend() -> DashboardTrendReply { LiveOpsFixtures.hourlyTrend(base) }
    func dashboardTrend(start: Date, end: Date, granularity: TrendGranularity) -> DashboardTrendReply {
        LiveOpsFixtures.yesterdayTrend(base, start: start)
    }
    func allGroups(includeInactive: Bool) -> [AdminGroup] {
        includeInactive ? LiveOpsFixtures.groups() : LiveOpsFixtures.groups().filter { $0.status == "active" }
    }
    /// Only the fallback reads it: the first page holds all eleven, and filters are not applied.
    func managedAccounts(page: Int, query: AccountListQuery) -> AccountListPage {
        let accounts = LiveOpsFixtures.accounts(base: base)
        return AccountListPage(items: page == 1 ? accounts : [], total: accounts.count, page: page, pageSize: query.pageSize, pages: 1)
    }
}
