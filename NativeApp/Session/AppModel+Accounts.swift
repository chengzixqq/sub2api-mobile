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

// MARK: - 账号动作（S2-06）

/// C-16: every stage 2 account write takes the generation of the session the user acted in, and goes nowhere once that session
/// has ended. `-ui-testing` writes the session's AccountDemoStore; `-ui-account-write-fail` fails every write with a 500.
extension AppModel: AccountWriteSource {
    var accountWriteSession: AccountWriteSession? {
        guard let session = sessionContext else { return nil }
        return AccountWriteSession(generation: session.generation, idempotentWrites: session.has(.adminIdempotentWrites),
                                   recoverSchedulable: session.has(.accountsRecoverSchedulable), patch: session.has(.accountsPatch),
                                   isReadOnlyToken: session.isReadOnlyToken)
    }
    /// The site clock (20 §0.6).
    func serverNow() -> Date { client?.serverClock.now() ?? Date() }
    func accountWriteClient(_ generation: UUID) throws -> APIClient {
        guard generation == sessionGeneration else { throw CancellationError() }
        return try requireClient()
    }

    func recoverAccountState(id: Int, schedulable: Bool?, generation: UUID) async throws -> UpstreamAccount {
        if isUITesting { return try accountDemoWrite(generation) { try $0.recover(id: id, schedulable: schedulable) } }
        return try await accountWriteClient(generation).recoverAccountState(id: id, schedulable: schedulable)
    }
    func setAccountSchedulable(id: Int, enabled: Bool, idempotencyKey: UUID?, generation: UUID) async throws -> WriteOutcome<UpstreamAccount> {
        if isUITesting { return WriteOutcome(value: try accountDemoWrite(generation) { try $0.setSchedulable(id: id, enabled: enabled) }) }
        return try await accountWriteClient(generation).setSchedulable(id: id, enabled: enabled, idempotencyKey: idempotencyKey)
    }
    /// A read: no generation (S2D1-05).
    func accountWithVersion(id: Int) async throws -> VersionedAccount {
        if isUITesting { return try accountDemo.versioned(id: id) }
        return try await requireClient().accountWithVersion(id: id)
    }
    func patchAccount(id: Int, body: AccountPatchRequest, ifMatch: String, generation: UUID) async throws -> VersionedAccount {
        if isUITesting { return try accountDemoWrite(generation) { try $0.patch(id: id, body: body, ifMatch: ifMatch) } }
        return try await accountWriteClient(generation).patchAccount(id: id, body: body, ifMatch: ifMatch)
    }
    func fullUpdateAccount(id: Int, patch: AccountPatchRequest, base: UpstreamAccount?, idempotencyKey: UUID?,
                           generation: UUID) async throws -> UpstreamAccount {
        if isUITesting { return try accountDemoWrite(generation) { try $0.fullUpdate(id: id, patch: patch) } }
        return try await accountWriteClient(generation).fullUpdate(id: id, patch: patch, base: base, idempotencyKey: idempotencyKey)
    }

    private func accountDemoWrite<T>(_ generation: UUID, _ write: (AccountDemoStore) throws -> T) throws -> T {
        guard generation == sessionGeneration else { throw CancellationError() }
        if ProcessInfo.processInfo.arguments.contains(DemoData.AccountFixture.writeFail) { throw APIError.server(status: 500, reason: nil) }
        return try write(accountDemo)
    }
}
