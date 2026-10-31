import Foundation
import SwiftUI
import Sub2Core
import UIKit

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
        // S2-19: `-ui-account-new-catalog-error` is the failed read.
        if isUITesting { return (.builtin, ProcessInfo.processInfo.arguments.contains(DemoData.AccountFixture.newCatalogError)) }
        guard let session = sessionContext, session.has(.metaCatalog) else { return (.builtin, false) }
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

    // MARK: 按 id 读取（旧编辑页；详情的今日、5 小时窗口与上游错误，S2-09）

    /// `-ui-testing` reads the session's demo accounts; an id they lack is the server's 404.
    func account(id: Int) async throws -> UpstreamAccount {
        if isUITesting {
            guard let account = accountDemo.account(id: id) else { throw APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND") }
            return account
        }
        return try await requireClient().account(id: id)
    }
    /// `-ui-testing` reads the demo table, which fails under `-ui-accounts-today-error` (and once with 429 under
    /// `-ui-account-today-throttled`).
    func accountTodayStats(id: Int) async throws -> AccountTodayStats {
        if isUITesting { return try accountDemo.todayStats(id: id) }
        return try await requireClient().accountTodayStats(id: id)
    }
    /// 20 §2.2 5 小时窗口; callers ask only for AccountUsageWindow.applies accounts.
    func accountPassiveUsage(id: Int) async throws -> AccountUsageWindow {
        if isUITesting { return accountDemo.passiveUsage(id: id) }
        return try await requireClient().accountPassiveUsage(id: id)
    }
    /// 20 §2.2 上游错误: one `upstream-errors` read of page size 1 for the count and the newest row (X08); 404 OPS_DISABLED
    /// comes back as `.opsDisabled`, not as a failure.
    func accountUpstreamErrors(id: Int) async throws -> AccountUpstreamErrors {
        do {
            if isUITesting { return AccountUpstreamErrors(page: try accountDemo.upstreamErrorPage(id: id)) }
            let filter = AccountDetailPresentation.upstreamErrorFilter(accountID: id)
            return AccountUpstreamErrors(page: try await requireClient().errorRecords(page: 1, filter: filter, kind: .upstream))
        } catch let error where AccountUpstreamErrors.isOpsDisabled(error) {
            return .opsDisabled
        }
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
        try await recordingAccountWrite(generation) {
            if isUITesting { return try accountDemoWrite(generation) { try $0.recover(id: id, schedulable: schedulable) } }
            return try await accountWriteClient(generation).recoverAccountState(id: id, schedulable: schedulable)
        }
    }
    func setAccountSchedulable(id: Int, enabled: Bool, idempotencyKey: UUID?, generation: UUID) async throws -> WriteOutcome<UpstreamAccount> {
        try await recordingAccountWrite(generation) {
            if isUITesting { return WriteOutcome(value: try accountDemoWrite(generation) { try $0.setSchedulable(id: id, enabled: enabled) }) }
            return try await accountWriteClient(generation).setSchedulable(id: id, enabled: enabled, idempotencyKey: idempotencyKey)
        }
    }
    /// A read: no generation (S2D1-05).
    func accountWithVersion(id: Int) async throws -> VersionedAccount {
        if isUITesting {
            if let delay = accountDemo.detailReadDelay { try await Task.sleep(for: delay) }
            return try accountDemo.versioned(id: id)
        }
        return try await requireClient().accountWithVersion(id: id)
    }
    func patchAccount(id: Int, body: AccountPatchRequest, ifMatch: String, generation: UUID) async throws -> VersionedAccount {
        try await recordingAccountWrite(generation) {
            if isUITesting {
                let arguments = ProcessInfo.processInfo.arguments
                return try accountDemoWrite(generation) { try $0.patch(id: id, request: body, ifMatch: ifMatch, arguments: arguments) }
            }
            return try await accountWriteClient(generation).patchAccount(id: id, body: body, ifMatch: ifMatch)
        }
    }
    func fullUpdateAccount(id: Int, patch: AccountPatchRequest, base: UpstreamAccount?, idempotencyKey: UUID?,
                           generation: UUID) async throws -> UpstreamAccount {
        try await recordingAccountWrite(generation) {
            if isUITesting {
                let arguments = ProcessInfo.processInfo.arguments
                return try accountDemoWrite(generation) { try $0.fullUpdate(id: id, patch: patch, base: base, arguments: arguments) }
            }
            return try await accountWriteClient(generation).fullUpdate(id: id, patch: patch, base: base, idempotencyKey: idempotencyKey)
        }
    }

    /// 20 §8.2, one request of a batch (S2-07); `-ui-testing` writes AccountDemoStore.bulkSetSchedulable.
    func setAccountsSchedulable(ids: [Int], enabled: Bool, idempotencyKey: UUID?, onEvent: KeyedWriteEventHandler? = nil,
                                generation: UUID) async throws -> WriteOutcome<AccountBulkReply> {
        try await recordingAccountWrite(generation) {
            if isUITesting { return WriteOutcome(value: try accountDemoWrite(generation) { try $0.bulkSetSchedulable(ids: ids, enabled: enabled) }) }
            return try await accountWriteClient(generation).setAccountsSchedulable(ids: ids, enabled: enabled, idempotencyKey: idempotencyKey, onEvent: onEvent)
        }
    }

    private func accountDemoWrite<T>(_ generation: UUID, _ write: (AccountDemoStore) throws -> T) throws -> T {
        guard generation == sessionGeneration else { throw CancellationError() }
        if ProcessInfo.processInfo.arguments.contains(DemoData.AccountFixture.writeFail) { throw APIError.server(status: 500, reason: nil) }
        return try write(accountDemo)
    }
}

// MARK: - S2-10 内联编辑

/// C-14: the save flow's pre-check; `-ui-testing` asks the session's AccountDemoStore by the backend's rule.
extension AppModel: AccountPatchSource {
    var hasMixedChannelDetails: Bool { sessionContext?.has(.accountsMixedChannelDetails) == true }
    func checkMixedChannel(platform: String, groupIDs: [Int], accountID: Int?, generation: UUID) async throws -> MixedChannelCheck {
        if isUITesting {
            let arguments = ProcessInfo.processInfo.arguments
            return try accountDemoWrite(generation) { $0.mixedChannelCheck(platform: platform, groupIDs: groupIDs, accountID: accountID, arguments: arguments) }
        }
        return try await accountWriteClient(generation).checkMixedChannel(platform: platform, groupIDs: groupIDs, accountID: accountID)
    }
}

// MARK: - S2-11 代理、恢复原代理、删除、在 Web 中编辑

extension AppModel: AccountDetailWriteSource {
    /// R19, S2D1-14: the App's one `proxies/all` read (active proxies, newest first); `-ui-testing` reads the session's demo proxies.
    func allProxies(withCount: Bool = true) async throws -> [AdminProxy] {
        if isUITesting { return try accountDemo.activeProxies() }
        return try await requireClient().allProxies(withCount: withCount)
    }
    func revertAccountProxyFallback(id: Int, generation: UUID) async throws {
        try await recordingAccountWrite(generation) {
            if isUITesting { return try accountDemoWrite(generation) { try $0.revertProxyFallback(id: id) } }
            try await accountWriteClient(generation).revertAccountProxyFallback(id: id)
        }
    }
    func deleteAccount(id: Int, generation: UUID) async throws -> DeleteResult {
        try await recordingAccountWrite(generation) {
            if isUITesting { return try accountDemoWrite(generation) { $0.delete(id: id) } }
            return try await accountWriteClient(generation).deleteAccount(id: id)
        }
    }
}

extension AppModel {
    /// C19 for this site: the edit dialog with `web.accounts_edit_deep_link`, else the account list.
    func accountWebLink(id: Int, name: String?) -> AccountWebLink? {
        guard let root = activeProfile?.baseURL else { return nil }
        return AccountWebLink.make(siteRoot: root, accountID: id, name: name, supportsDeepLink: sessionContext?.has(.webAccountsEditDeepLink) == true)
    }
    /// S2D1-23: the App's one “在 Web 中编辑” (S2-12, S2-16, S2-17 and S2-21 call it too). The system browser keeps the Web
    /// login; the list's fallback puts the name on the clipboard first (this device only). `-ui-testing` stays in the App and
    /// only shows the receipt.
    func openAccountInWeb(id: Int, name: String?, using openURL: OpenURLAction) {
        guard let link = accountWebLink(id: id, name: name) else { return }
        if let copied = link.copiedName { SensitivePasteboard.copy(copied) }
        let opened = Receipt(text: link.receipt, systemImage: "safari", tone: .neutral)
        guard !isUITesting else { receipts.show(opened); return }
        let receipts = receipts
        openURL(link.url) { accepted in
            receipts.show(accepted ? opened : Receipt(text: AccountWebLink.openFailedReceipt, systemImage: "exclamationmark.triangle", tone: .caution))
        }
    }
    func openAccountInWeb(_ account: UpstreamAccount, using openURL: OpenURLAction) {
        openAccountInWeb(id: account.id, name: account.name, using: openURL)
    }
}

// MARK: - S2-12 模型与高级

extension AppModel {
    /// 20 §3.2 添加模型, R19 / S2D1-14's one wrapper (S2-14 reuses it): `GET :id/models`; `-ui-testing` reads the session's demo
    /// store (502 with `-ui-account-models-error`).
    func accountModels(id: Int) async throws -> [AccountModelOption] {
        if isUITesting { return try accountDemo.models(id: id) }
        return try await requireClient().accountModels(id: id)
    }
}

// MARK: - S2-14 测试连接

/// 20 §4: starting a test is a write and carries the session's generation (S2D1-05); `-ui-testing` replays the session's
/// AccountDemoStore (DemoData+AccountTests.swift).
extension AppModel: AccountTestSource {
    var accountTestSession: AccountTestSession? {
        guard let session = sessionContext else { return nil }
        return AccountTestSession(generation: session.generation, supportsTestResult: session.has(.accountsTestResult),
                                  supportsTestRuns: session.has(.accountsTestRuns), isReadOnlyToken: session.isReadOnlyToken)
    }
    func testAccountStream(id: Int, model: String?, generation: UUID) async throws -> AsyncThrowingStream<AccountTestEvent, any Error> {
        if isUITesting {
            guard generation == sessionGeneration else { throw CancellationError() }
            return try accountDemo.testStream(id: id, model: model, now: accountFixtureNow())
        }
        let expectsTestResult = sessionContext?.has(.accountsTestResult) == true
        return try await accountWriteClient(generation).testAccount(id: id, model: model, expectsTestResult: expectsTestResult)
    }
    func startAccountTestRun(id: Int, model: String?, generation: UUID) async throws -> AccountTestRunStart {
        if isUITesting {
            guard generation == sessionGeneration else { throw CancellationError() }
            return try accountDemo.startTestRun(id: id, model: model, now: accountFixtureNow())
        }
        return try await accountWriteClient(generation).startTestRun(accountID: id, modelID: model)
    }
    func latestAccountTestRun(id: Int) async throws -> AccountTestRun? {
        if isUITesting { return accountDemo.latestTestRun(id: id, now: accountFixtureNow()) }
        return try await requireClient().latestTestRun(accountID: id)
    }
    func accountTestRun(runID: String) async throws -> AccountTestRun {
        if isUITesting { return try accountDemo.testRun(runID: runID, now: accountFixtureNow()) }
        return try await requireClient().testRun(runID: runID)
    }

    /// One per session (`publish`); its “启用调度” goes through AccountActions and the App's receipts. A finished test may have
    /// changed the account (one that passes is recovered): home reads past the cache next time and the list reads again (S2-23).
    func makeAccountTestCenter(generation: UUID) -> AccountTestCenter {
        AccountTestCenter(generation: generation, source: self, receipts: receipts,
                          makeScheduling: { [unowned self] onChange in AccountActions(model: self, onChange: onChange) },
                          background: isUITesting ? .none : .application,
                          onFinished: { [weak self] _ in
                              self?.noteAccountWrite()
                              self?.accountListSignal.bump()
                          })
    }
}

// MARK: - S2-16 凭据

/// 20 §6.4 刷新令牌 carries the session's generation (S2D1-05); `-ui-testing` refreshes the session's AccountDemoStore
/// (DemoData+AccountCredentials.swift), which fails under `-ui-account-refresh-fail`.
extension AppModel: AccountRefreshSource {
    var siteTimeZone: TimeZone { siteSession?.serverTimeZone.timeZone ?? .current }
    func refreshAccount(id: Int, idempotencyKey: UUID?, generation: UUID) async throws -> AccountRefreshResult {
        try await recordingAccountWrite(generation) {
            if isUITesting {
                let arguments = ProcessInfo.processInfo.arguments
                return try accountDemoWrite(generation) { try $0.refreshToken(id: id, now: accountFixtureNow(), arguments: arguments) }
            }
            return try await accountWriteClient(generation).refreshAccount(id: id, idempotencyKey: idempotencyKey).value
        }
    }
}

// MARK: - S2-17 重新授权

/// R19, S2D1-03: the App's one set of OAuth wrappers (S2-19 reuses them). Each is a write: it carries the generation of the
/// session the user tapped in and goes nowhere once that session has ended. `-ui-testing` authorizes against the session's
/// AccountDemoStore (DemoData+AccountReauth.swift).
extension AppModel: AccountReauthorizeSource {
    var oauthSession: AccountOAuthSession? {
        guard let session = sessionContext else { return nil }
        return AccountOAuthSession(generation: session.generation, reauthorizeEndpoint: session.has(.accountsReauthorize),
                                   errorReasons: session.has(.accountsOAuthErrorReasons), isReadOnlyToken: session.isReadOnlyToken)
    }
    func generateOAuthLink(_ request: OAuthLinkRequest, generation: UUID) async throws -> OAuthLink {
        if isUITesting { return try accountDemoWrite(generation) { $0.authLink(request) } }
        return try await accountWriteClient(generation).generateAuthURL(request)
    }
    func exchangeOAuthCode(_ link: OAuthLink, code: OAuthCode, proxyID: Int?, generation: UUID) async throws -> OAuthTokenInfo {
        if isUITesting { return try accountDemoWrite(generation) { try $0.exchange(link, code: code) } }
        return try await accountWriteClient(generation).exchangeCode(link, code: code, proxyID: proxyID)
    }
    func reauthorizeAccount(id: Int, request: AccountReauthorizeRequest, generation: UUID) async throws -> UpstreamAccount {
        try await recordingAccountWrite(generation) {
            if isUITesting {
                let arguments = ProcessInfo.processInfo.arguments
                return try accountDemoWrite(generation) { try $0.reauthorize(id: id, request: request, now: accountFixtureNow(), arguments: arguments) }
            }
            return try await accountWriteClient(generation).reauthorize(accountID: id, request: request)
        }
    }
    func applyOAuthCredentials(accountID: Int, type: OAuthAuthKind, credentials: [String: JSONValue], extra: [String: JSONValue]?,
                               generation: UUID) async throws -> UpstreamAccount {
        try await recordingAccountWrite(generation) {
            if isUITesting { return try accountDemoWrite(generation) { try $0.applyOAuth(id: accountID, type: type, now: accountFixtureNow()) } }
            return try await accountWriteClient(generation).applyOAuthCredentials(accountID: accountID, type: type, credentials: credentials, extra: extra)
        }
    }
}

// MARK: - S2-19 新建账号

/// 20 §7.4: the create is a write and carries the generation of the session the admin tapped in (S2D1-05); serverNow,
/// checkMixedChannel and setAccountSchedulable are the ones above. `-ui-testing` creates in the session's AccountDemoStore
/// (DemoData+AccountNew.swift), which `writeFail` leaves alone.
extension AppModel: AccountCreateSource {
    var accountCreateSession: AccountCreateSession? {
        guard let session = sessionContext else { return nil }
        return AccountCreateSession(generation: session.generation, idempotentWrites: session.has(.adminIdempotentWrites),
                                    mixedChannelDetails: session.has(.accountsMixedChannelDetails), isReadOnlyToken: session.isReadOnlyToken)
    }
    func createAccount(_ request: AccountCreateRequest, idempotencyKey: UUID?, onEvent: KeyedWriteEventHandler?,
                       generation: UUID) async throws -> WriteOutcome<UpstreamAccount> {
        try await recordingAccountWrite(generation) {
            if isUITesting {
                guard generation == sessionGeneration else { throw CancellationError() }
                let arguments = ProcessInfo.processInfo.arguments
                return WriteOutcome(value: try accountDemo.create(request, key: idempotencyKey, now: accountFixtureNow(), arguments: arguments))
            }
            return try await accountWriteClient(generation).createAccount(request, idempotencyKey: idempotencyKey, onEvent: onEvent)
        }
    }
    /// A read: no generation (S2D1-05).
    func findCreatedAccount(name: String, platform: String, notBefore: Date) async throws -> UpstreamAccount? {
        if isUITesting, ProcessInfo.processInfo.arguments.contains(DemoData.AccountFixture.createCheckFail) {
            throw APIError(kind: .transport, message: "网络连接已中断")
        }
        let page = try await managedAccounts(page: 1, query: AccountCreateReconciliation.query(name: name, platform: platform))
        return AccountCreateReconciliation.match(page.items, name: name, platform: platform, notBefore: notBefore)
    }
}

// MARK: - S2-20 新建账号的测试与启用调度

/// The run after a new account's test reads and switches through S2-06's members above.
extension AppModel: AccountNewScheduleWriter {}

extension AccountTestBackgroundActivity {
    /// 20 §4.4: the stream asks for background time, so a test keeps running for a while after the App leaves the screen.
    static let application = AccountTestBackgroundActivity(begin: { onExpire in
        let task = UIApplication.shared.beginBackgroundTask(withName: "account-test") { MainActor.assumeIsolated { onExpire() } }
        return task == .invalid ? nil : task.rawValue
    }, end: { UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: $0)) })
}

// MARK: - S2-21 定时测试

extension AppModel {
    /// 20 §9.2, read only: the account's plans and the primary plan's newest results. `-ui-testing` reads the session's demo
    /// store (DemoData+ScheduledTests.swift), which fails under `-ui-scheduled-tests-error`.
    func accountScheduledTests(accountID: Int, resultLimit: Int) async throws -> AccountScheduledTestsSnapshot {
        if isUITesting {
            return try accountDemo.scheduledTests(accountID: accountID, resultLimit: resultLimit, arguments: ProcessInfo.processInfo.arguments)
        }
        return try await requireClient().accountScheduledTests(accountID: accountID, resultLimit: resultLimit)
    }
}

// MARK: - 首页刷新接线（S2-23）

extension AppModel {
    /// 10 §1.4, X17: an account write ran or may have run, so the home page reads past the server cache the next time it shows.
    func noteAccountWrite() { liveOps?.noteExternalWrite() }

    /// The shell of every account write wrapper above; `generation` is the wrapper's own, the session the user acted in.
    func recordingAccountWrite<T: Sendable>(_ generation: UUID, _ operation: @MainActor () async throws -> T) async throws -> T {
        try await AccountWriteMark.run(generation: generation, isCurrent: { $0 == sessionGeneration }, mark: { noteAccountWrite() }, operation)
    }
}
