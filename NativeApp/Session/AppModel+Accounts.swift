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

    /// This session's fixture accounts.
    var accountDemo: AccountDemoStore { AccountDemoStore.current(for: sessionGeneration, base: accountFixtureNow()) }
    /// The site clock (20 §0.6) the fixtures derive states with.
    func accountFixtureNow() -> Date { sessionContext?.client.serverClock.now() ?? Date() }
}
