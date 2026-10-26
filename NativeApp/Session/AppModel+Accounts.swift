import Foundation
import Sub2Core

// 20 章: the account tab's reads (D11). Later stage 2 items add their account wrappers and `-ui-testing` branches here.
extension AppModel {
    /// R19's one list read; `-ui-testing` filters the session's AccountDemoStore by group, platform, search, type and status.
    func managedAccounts(page: Int, query: AccountListQuery) async throws -> AccountListPage {
        if isUITesting { return try accountDemo.page(page, query: query, now: accountFixtureNow()) }
        return try await requireClient().managedAccounts(page: page, query: query)
    }
    /// Callers gate it with `accounts.status_summary` (an older Sub2 answers 400, not “unsupported”).
    func accountStatusSummary(platform: String? = nil, groupID: Int? = nil, includeAccounts: Bool = false) async throws -> AccountStatusSummary {
        if isUITesting {
            return try accountDemo.statusSummary(platform: platform, groupID: groupID, includeAccounts: includeAccounts, now: accountFixtureNow())
        }
        return try await requireClient().accountStatusSummary(platform: platform, groupID: groupID, includeAccounts: includeAccounts)
    }
    func accountTodayStatsBatch(ids: [Int], groupID: Int? = nil) async throws -> AccountTodayStatsBatch {
        if isUITesting { return accountDemo.todayStats(ids: ids) }
        return try await requireClient().accountTodayStatsBatch(ids: ids, groupID: groupID)
    }
    func accountRuntime(ids: [Int], includeWindowCost: Bool = false) async throws -> [Int: AccountRuntime] {
        if isUITesting { return accountDemo.runtime(ids: ids) }
        return try await requireClient().accountRuntime(ids: ids, includeWindowCost: includeWindowCost)
    }

    /// X25, S2D1-23: the one way to the platform catalog. Without `meta.catalog` nothing is sent and the built-in list is used;
    /// a failed read also falls back, with `failed` set so a page can offer “读取失败 · 重试”.
    func metaCatalogResult() async -> (catalog: MetaCatalog, failed: Bool) {
        guard !isUITesting, let session = sessionContext, session.has(.metaCatalog) else { return (.builtin, false) }
        do { return (try await session.client.metaCatalog(), false) }
        catch { return (.builtin, !(error is CancellationError)) }
    }
    func metaCatalog() async -> MetaCatalog { await metaCatalogResult().catalog }

    /// C-10: `groups/all` with every status; `-ui-testing` reads DemoData.accountGroups (502 with `-ui-account-groups-error`).
    func makeGroupDirectory(client: APIClient) -> GroupDirectory {
        guard isUITesting else { return GroupDirectory(load: { try await client.allGroups(platform: nil, includeInactive: true) }) }
        let fails = ProcessInfo.processInfo.arguments.contains(DemoData.AccountFixture.groupsError)
        return GroupDirectory(load: {
            if fails { throw APIError.server(status: 502, reason: nil) }
            return DemoData.accountGroups
        })
    }

    // MARK: 账号 Tab 徽标（20 §1.6）

    /// The badge loop of one session: AppModel starts it in `publish` and cancels it in `endActiveSession`.
    func runAccountBadgeRefresh(generation: UUID) async {
        let refresher = AccountBadgeRefresher(badge: accountBadge, isActive: { [weak self] in
            guard let self else { return false }
            return self.sessionGeneration == generation && !self.isSuspended
        }, fetch: { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.accountErrorCount()
        })
        await refresher.run()
    }
    /// status-summary's totals.error; without `accounts.status_summary`, dashboard/stats' error_accounts (20 §0.1).
    func accountErrorCount() async throws -> Int {
        let generation = sessionGeneration
        let count: Int
        if sessionContext?.has(.accountsStatusSummary) == true { count = try await accountStatusSummary().totals.error }
        else { count = try await dashboard().stats.errorAccounts }
        guard generation == sessionGeneration else { throw CancellationError() }
        return count
    }

    // MARK: 旧详情（S2-08 前）

    /// `-ui-testing` reads the session's demo accounts; an id they lack is the server's 404.
    func account(id: Int) async throws -> UpstreamAccount {
        if isUITesting {
            guard let account = accountDemo.account(id: id) else { throw APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND") }
            return account
        }
        return try await requireClient().account(id: id)
    }
    /// `-ui-testing` takes the id from the demo batch, which fails under `-ui-accounts-today-error`.
    func accountTodayStats(id: Int) async throws -> AccountTodayStats {
        if isUITesting {
            guard let stats = accountDemo.todayStats(ids: [id]).stats[id] else {
                throw APIError.server(status: 503, reason: "ACCOUNT_STATS_UNAVAILABLE")
            }
            return stats
        }
        return try await requireClient().accountTodayStats(id: id)
    }

    /// This session's fixture accounts.
    var accountDemo: AccountDemoStore { AccountDemoStore.current(for: sessionGeneration, base: accountFixtureNow()) }
    /// The site clock (20 §0.6) the fixtures derive states with.
    func accountFixtureNow() -> Date { sessionContext?.client.serverClock.now() ?? Date() }
}
