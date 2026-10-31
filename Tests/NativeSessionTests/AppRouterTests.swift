import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

@MainActor @Test func mainTabsKeepDecidedOrderTitlesAndIcons() {
    #expect(MainTab.allCases == [.today, .accounts, .users, .monitor, .search])
    #expect(MainTab.allCases.map(\.title) == ["概览", "账号", "用户", "监控", "搜索"])
    #expect(MainTab.allCases.map(\.systemImage) == ["house", "server.rack", "person.2", "waveform.path.ecg", "magnifyingglass"])
    let router = AppRouter()
    #expect(router.selectedTab == .today)
    #expect(router.pendingIntent == nil)
    #expect(router.presentedSheet == nil)
    #expect(MainTab.allCases.allSatisfy { router.path(for: $0).isEmpty })
}

@MainActor @Test func pushAppendsToSelectedTabStackOnly() {
    let router = AppRouter()
    router.selectedTab = .search
    router.push(.groups())
    router.push(.group(id: 3))
    #expect(router.path(for: .search) == [.groups(), .group(id: 3)])
    #expect(MainTab.allCases.filter { $0 != .search }.allSatisfy { router.path(for: $0).isEmpty })
}

@MainActor @Test func setPathAndPopToRootAffectOnlyThatTab() {
    let router = AppRouter()
    router.setPath([.user(id: 1)], for: .users)
    router.setPath([.alert(id: 2)], for: .today)
    router.popToRoot(.users)
    #expect(router.path(for: .users).isEmpty)
    #expect(router.path(for: .today) == [.alert(id: 2)])
}

@MainActor @Test func selectResetsTargetStackSwitchesTabAndRecordsIntent() {
    let router = AppRouter()
    router.setPath([.alert(id: 1)], for: .monitor)
    router.setPath([.groups()], for: .search)
    router.selectedTab = .search
    router.select(.monitor(segment: .alerts))
    #expect(router.selectedTab == .monitor)
    #expect(router.path(for: .monitor).isEmpty)
    #expect(router.path(for: .search) == [.groups()])
    #expect(router.pendingIntent == .monitor(segment: .alerts))
}

@MainActor @Test func takeIntentIsOneShotAndScopedToItsTab() {
    let router = AppRouter()
    router.select(.monitor(segment: .channels))
    #expect(router.takeIntent(for: .accounts) == nil)
    #expect(router.pendingIntent == .monitor(segment: .channels))
    #expect(router.takeIntent(for: .monitor) == .monitor(segment: .channels))
    #expect(router.takeIntent(for: .monitor) == nil)
    #expect(router.pendingIntent == nil)
}

@MainActor @Test func newerIntentReplacesPendingIntent() {
    let router = AppRouter()
    router.select(.accounts(filter: .limited))
    router.select(.monitor(segment: .overview))
    #expect(router.takeIntent(for: .accounts) == nil)
    #expect(router.takeIntent(for: .monitor) == .monitor(segment: .overview))
}

@MainActor @Test func presentReplacesSheetAndSelectDismissesIt() {
    let router = AppRouter()
    router.present(.addSite)
    router.present(.accountTest(id: 7))
    #expect(router.presentedSheet == .accountTest(id: 7))
    router.select(.today)
    #expect(router.presentedSheet == nil)
    #expect(router.selectedTab == .today)
}

@Test func tabIntentMapsToItsTab() {
    let intents: [TabIntent] = [.today, .accounts(), .users, .monitor(), .search]
    #expect(intents.map(\.tab) == MainTab.allCases)
    #expect(TabIntent.accounts() == .accounts(filter: nil, platform: nil))
    #expect(TabIntent.monitor() == .monitor(segment: .overview))
    #expect(MonitorSegment.allCases.map(\.title) == ["概况", "渠道", "告警"])
}

@Test func routeDefaultsFollowSpec() {
    #expect(AppRoute.analytics() == .analytics(range: .today, focus: nil, metric: nil))
    #expect(AppRoute.settings() == .settings(focus: .interface))
    #expect(AppRoute.redeem() == .redeem(open: nil, query: nil, status: nil, type: nil, reconcile: false))
    #expect(AppRoute.groups() == .groups(segment: nil))
    #expect(AppRoute.account(id: 4) == .account(id: 4, focus: nil, preload: nil))
    #expect(AppRoute.userEdit(id: 4) == .userEdit(id: 4, segment: .basic))
    #expect(AppRoute.analyticsModel(model: "gpt-x") == .analyticsModel(model: "gpt-x", source: .requested))
    let logs = LogsRoute()
    #expect(logs.scope == .usage)
    #expect(logs.modelSource == .requested)
    #expect(logs.account == nil && logs.group == nil && logs.user == nil && logs.model == nil)
    // 40 §0.1 chart keys: “switch” is a keyword in Swift, so the case is accountSwitch with the route's spelling.
    #expect(AnalyticsChartKey.accountSwitch.rawValue == "switch")
}

@Test func routePreloadComparesByIdentity() throws {
    let json = Data(#"{"id":7,"request_id":"req-7","created_at":"2026-10-16T08:12:00Z","model":"m","user_id":1,"account_id":2,"api_key_id":3}"#.utf8)
    let record = try JSONDecoder().decode(UsageRequestRecord.self, from: json)
    let preload = RoutePreload(record)
    let first = AppRoute.request(.usage(preload)), second = AppRoute.request(.usage(preload))
    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
    #expect(AppRoute.request(.usage(RoutePreload(record))) != AppRoute.request(.usage(RoutePreload(record))))
    #expect(Set([first, second]).count == 1)
    #expect(preload.value.id == 7)
}

@Test func appSheetIdentityIsItsValue() {
    #expect(AppSheet.groupEdit(id: nil).id == .groupEdit(id: nil))
    #expect(AppSheet.redeemGrant(userID: 5, pendingID: nil) != .redeemGrant(userID: 5, pendingID: UUID()))
}

@Test func everyRouteAndSheetHasPlaceholderTitle() {
    let routes: [AppRoute] = [
        .alert(id: 1), .account(id: 1), .accountScheduledTests(accountID: 1), .user(id: 1), .userLedger(userID: 1), .userNew,
        .userEdit(id: 1), .analytics(), .analyticsMore(), .analyticsChart(.tokens), .analyticsRank(.model), .analyticsModel(model: "gpt-x"),
        .logs(LogsRoute()), .request(.usageRequestID("req")), .groups(), .group(id: 1), .groupBatch(groupID: 1, name: "g"),
        .groupKeys(groupID: 1), .groupSubscriptions(groupID: 1), .searchResults(kind: .users, query: "a"), .settings(), .sessions,
        .accessTokens, .push, .pushTarget(id: 1), .redeem(), .proxies(), .proxyDetail(id: 1), .proxyFallbackAccounts(proxyID: 1),
        .announcements(), .announcementDetail(id: 1), .announcementReads(announcementID: 1)
    ]
    #expect(routes.count == 32)
    #expect(routes.allSatisfy { !$0.placeholderTitle.isEmpty })
    #expect(AppRoute.analyticsModel(model: "gpt-x").placeholderTitle == "gpt-x")
    #expect(AppRoute.searchResults(kind: .proxies, query: "a").placeholderTitle == "代理")
    #expect(AppRoute.logs(LogsRoute()).placeholderTitle == "使用记录")
    let sheets: [AppSheet] = [
        .addSite, .accountNew, .accountTest(id: 1), .balanceKeypad(userID: 1, mode: .topup), .groupEdit(id: nil), .groupPick(groupID: 1),
        .redeemEdit(id: 1), .redeemGenerate, .redeemReconcile(batchID: UUID()), .redeemGrant(userID: 1, pendingID: nil), .proxyEdit(id: nil),
        .announcementEdit(id: nil)
    ]
    #expect(sheets.allSatisfy { !$0.placeholderTitle.isEmpty })
    #expect(AppSheet.addSite.placeholderTitle == "添加站点")
    #expect(AppSheet.accountTest(id: 1).placeholderTitle == "测试连接")
}

/// S2-08: the list pushes its row with the route; the route compares by the preload's instance, never by the account.
@MainActor @Test func accountRoutePreloadComparesByIdentity() {
    let preload = RoutePreload(UpstreamAccount(id: 7, name: "a", platform: "openai", type: "apikey"))
    let first = AppRoute.account(id: 7, preload: preload), second = AppRoute.account(id: 7, preload: preload)
    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
    #expect(Set([first, second]).count == 1)
    #expect(AppRoute.account(id: 7, preload: RoutePreload(preload.value)) != first)
    #expect(first != AppRoute.account(id: 7))
    #expect(preload.value.id == 7)
    let router = AppRouter()
    router.selectedTab = .accounts
    router.push(first)
    guard case .account(_, _, let pushed)? = router.path(for: .accounts).last else { Issue.record("no account route"); return }
    #expect(pushed?.value.name == "a")
}
