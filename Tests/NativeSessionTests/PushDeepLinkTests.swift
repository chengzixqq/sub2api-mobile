import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 00 §7.5: payload, site match, the page opened, and the target kept until that site's tabs take it (S6-23).

private let siteA = pushProfile("a"), siteB = pushProfile("b")

private func payload(_ type: String?, site: String? = siteA.id.uuidString.lowercased(), _ extra: [AnyHashable: Any] = [:]) -> [AnyHashable: Any] {
    var info: [AnyHashable: Any] = ["aps": ["alert": ["title": "[P1] 错误率", "body": "当前 12.3"], "sound": "default"]]
    if let type { info["type"] = type }
    if let site { info["site"] = site }
    return info.merging(extra) { _, new in new }
}

@Test func parseOpsAlertAcceptsIntAndNSNumber() {
    let fromInt = PushDeepLink.parse(payload("ops_alert.fired", ["alert_event_id": 881, "rule_id": 3]))
    #expect(fromInt.target == .alert(id: 881))
    #expect(fromInt.serverID == siteA.id)
    #expect(fromInt.type == "ops_alert.fired")
    let fromNumber = PushDeepLink.parse(payload("ops_alert.fired", ["alert_event_id": NSNumber(value: 881)]))
    #expect(fromNumber.target == .alert(id: 881))
    #expect(PushDeepLink.parse(payload("ops_alert.resolved", ["alert_event_id": NSNumber(value: 37)])).target == .alert(id: 37))
}

@Test func parseAccountEventsAndPushTest() {
    #expect(PushDeepLink.parse(payload("account.error", ["account_id": NSNumber(value: 5), "error_kind": "auth"])).target == .account(id: 5))
    let finished = PushDeepLink.parse(payload("account.test_finished", ["account_id": 5, "run_id": "tr_abc", "status": "success"]))
    #expect(finished.target == .accountTest(accountID: 5, runID: "tr_abc"))
    #expect(PushDeepLink.parse(payload("account.test_finished", ["account_id": 5])).target == .accountTest(accountID: 5, runID: nil))
    #expect(PushDeepLink.parse(payload("push.test")).target == .pushSettings)
}

@Test func unknownTypeOrBadIDOnlyOpensApp() {
    #expect(PushDeepLink.parse(payload("custom.event", ["alert_event_id": 1])).target == nil)
    #expect(PushDeepLink.parse(payload(nil, ["alert_event_id": 1])).target == nil)
    #expect(PushDeepLink.parse(payload("  ")).type == nil)
    #expect(PushDeepLink.parse(payload("ops_alert.fired")).target == nil)
    let bad: [Any] = [0, -3, 1.5, "881", NSNumber(value: true), NSNumber(value: 2.5)]
    for value in bad {
        #expect(PushDeepLink.parse(payload("ops_alert.fired", ["alert_event_id": value])).target == nil)
    }
    #expect(PushDeepLink.parse(payload("account.test_finished", ["run_id": "tr_abc"])).target == nil)
}

@Test func siteTagMustBeAProfileUUID() {
    #expect(PushDeepLink.parse(payload("push.test", site: siteA.id.uuidString.uppercased())).serverID == siteA.id)
    #expect(PushDeepLink.parse(payload("push.test", site: siteA.id.uuidString.lowercased())).serverID == siteA.id)
    #expect(PushDeepLink.parse(payload("push.test", site: "api.example.com")).serverID == nil)
    #expect(PushDeepLink.parse(payload("push.test", site: "")).serverID == nil)
    #expect(PushDeepLink.parse(payload("push.test", site: nil)).serverID == nil)
}

@Test func decisionCoversCurrentOtherAndUnknownSites() {
    let profiles = [siteA, siteB]
    let tapA = PushDeepLink.parse(payload("ops_alert.fired", ["alert_event_id": 41]))
    #expect(PushDeepLink.decision(for: tapA, activeServerID: siteA.id, profiles: profiles) == .current(serverID: siteA.id, target: .alert(id: 41)))
    #expect(PushDeepLink.decision(for: tapA, activeServerID: siteB.id, profiles: profiles) == .otherSite(siteA, target: .alert(id: 41)))
    #expect(PushDeepLink.decision(for: tapA, activeServerID: nil, profiles: profiles) == .otherSite(siteA, target: .alert(id: 41)))
    #expect(PushDeepLink.decision(for: tapA, activeServerID: siteB.id, profiles: [siteB]) == .openOnly)
    let hostTag = PushDeepLink.parse(payload("ops_alert.fired", site: "api.example.com", ["alert_event_id": 41]))
    #expect(PushDeepLink.decision(for: hostTag, activeServerID: siteA.id, profiles: profiles) == .openOnly)
    let unknown = PushDeepLink.parse(payload("custom.event"))
    #expect(PushDeepLink.decision(for: unknown, activeServerID: siteA.id, profiles: profiles) == .openOnly)
}

@Test func navigationTableFollowsSection7_5() {
    #expect(PushDeepLink.navigation(for: .alert(id: 41), showsTestResult: false) == PushNavigation(path: [.alert(id: 41)], sheet: nil))
    #expect(PushDeepLink.navigation(for: .account(id: 7), showsTestResult: false) == PushNavigation(path: [.account(id: 7)], sheet: nil))
    #expect(PushDeepLink.navigation(for: .accountTest(accountID: 5, runID: "tr_abc"), showsTestResult: true)
            == PushNavigation(path: [.account(id: 5)], sheet: .accountTest(id: 5)))
    #expect(PushDeepLink.navigation(for: .accountTest(accountID: 5, runID: nil), showsTestResult: false)
            == PushNavigation(path: [.account(id: 5)], sheet: nil))
    #expect(PushDeepLink.navigation(for: .pushSettings, showsTestResult: false)
            == PushNavigation(path: [.settings(focus: .interface), .push], sheet: nil))
}

@MainActor @Test func routerOpenGoesToOverviewAndReplacesItsStack() {
    let router = AppRouter(selectedTab: .users)
    router.setPath([.sessions], for: .today)
    router.setPath([.user(id: 1)], for: .users)
    router.open(PushNavigation(path: [.alert(id: 41)], sheet: nil))
    #expect(router.selectedTab == .today)
    #expect(router.path(for: .today) == [.alert(id: 41)])
    #expect(router.path(for: .users) == [.user(id: 1)])
    #expect(router.presentedSheet == nil)
    router.open(PushDeepLink.navigation(for: .accountTest(accountID: 5, runID: nil), showsTestResult: true))
    #expect(router.path(for: .today) == [.account(id: 5)])
    #expect(router.presentedSheet == .accountTest(id: 5))
}

@MainActor @Test func deliverPendingWaitsForTheOpenSheet() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let coordinator = makePushCoordinator(store.records)
    let navigator = PushStubNavigator(active: siteA.id, profiles: [siteA, siteB])
    await coordinator.openTap(PushDeepLink.parse(payload("ops_alert.fired", ["alert_event_id": 41])), navigator: navigator)
    let pending = coordinator.pendingTarget
    let router = AppRouter()
    router.present(.balanceKeypad(userID: 1, mode: .topup))
    #expect(!coordinator.deliverPending(to: router, activeServerID: siteA.id, showsTestResult: { _ in false }))
    #expect(coordinator.pendingTarget == pending)
    #expect(router.path(for: .today).isEmpty)
    router.presentedSheet = nil
    #expect(!coordinator.deliverPending(to: router, activeServerID: siteB.id, showsTestResult: { _ in false }))
    #expect(coordinator.deliverPending(to: router, activeServerID: siteA.id, showsTestResult: { _ in false }))
    #expect(coordinator.pendingTarget == nil)
    #expect(router.path(for: .today) == [.alert(id: 41)])
}

@MainActor @Test func deliverPendingShowsTestResultOnlyWhenTheSessionHasIt() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let coordinator = makePushCoordinator(store.records)
    let navigator = PushStubNavigator(active: siteA.id, profiles: [siteA])
    let finished = PushDeepLink.parse(payload("account.test_finished", ["account_id": 5, "run_id": "tr_abc"]))
    await coordinator.openTap(finished, navigator: navigator)
    var asked: [Int] = []
    let router = AppRouter()
    #expect(coordinator.deliverPending(to: router, activeServerID: siteA.id, showsTestResult: { asked.append($0); return false }))
    #expect(asked == [5])
    #expect(router.presentedSheet == nil)
    await coordinator.openTap(finished, navigator: navigator)
    #expect(coordinator.deliverPending(to: router, activeServerID: siteA.id, showsTestResult: { _ in true }))
    #expect(router.presentedSheet == .accountTest(id: 5))
}

@Test func foregroundRefreshOnlyForCurrentSite() {
    func refresh(_ type: String, site: UUID? = siteA.id, active: UUID? = siteA.id) -> PushForegroundRefresh? {
        PushDeepLink.foregroundRefresh(for: PushDeepLink.parse(payload(type, site: site?.uuidString, ["alert_event_id": 1, "account_id": 2])),
                                       activeServerID: active)
    }
    #expect(refresh("ops_alert.fired") == .alerts)
    #expect(refresh("ops_alert.resolved") == .alerts)
    #expect(refresh("account.error") == .accounts)
    #expect(refresh("account.test_finished") == .accounts)
    #expect(refresh("push.test") == nil)
    #expect(refresh("ops_alert.fired", site: siteB.id) == nil)
    #expect(refresh("ops_alert.fired", site: nil) == nil)
    #expect(refresh("ops_alert.fired", active: nil) == nil)
}

@MainActor @Test func foregroundRefreshIsMergedPerKind() {
    let store = PushTestDefaults(); defer { store.clear() }
    let clock = PushTestClock()
    let coordinator = makePushCoordinator(store.records, now: { clock.date })
    let error = PushDeepLink.parse(payload("account.error", ["account_id": 2]))
    let alert = PushDeepLink.parse(payload("ops_alert.fired", ["alert_event_id": 1]))
    let results = (0..<10).map { _ in coordinator.foregroundRefresh(for: error, activeServerID: siteA.id) }
    #expect(results.compactMap { $0 } == [.accounts])
    #expect(coordinator.foregroundRefresh(for: alert, activeServerID: siteA.id) == .alerts)
    clock.date += 4
    #expect(coordinator.foregroundRefresh(for: alert, activeServerID: siteA.id) == nil)
    clock.date += 2
    #expect(coordinator.foregroundRefresh(for: alert, activeServerID: siteA.id) == .alerts)
    #expect(coordinator.foregroundRefresh(for: error, activeServerID: siteA.id) == nil)
    clock.date += 25
    #expect(coordinator.foregroundRefresh(for: error, activeServerID: siteA.id) == .accounts)
    #expect(coordinator.foregroundRefresh(for: error, activeServerID: siteB.id) == nil)
}

@MainActor @Test func openTapCurrentSiteKeepsTargetWithoutSwitching() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let coordinator = makePushCoordinator(store.records)
    let navigator = PushStubNavigator(active: siteA.id, profiles: [siteA, siteB])
    await coordinator.openTap(PushDeepLink.parse(payload("ops_alert.fired", ["alert_event_id": 41])), navigator: navigator)
    #expect(navigator.opened.isEmpty)
    #expect(coordinator.pendingTarget?.serverID == siteA.id)
    #expect(coordinator.takeTarget(for: siteB.id) == nil)
    #expect(coordinator.pendingTarget != nil)
    #expect(coordinator.takeTarget(for: siteA.id) == .alert(id: 41))
    #expect(coordinator.takeTarget(for: siteA.id) == nil)
}

@MainActor @Test func openTapOtherSiteSwitchesThenKeepsTarget() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let coordinator = makePushCoordinator(store.records)
    let navigator = PushStubNavigator(active: siteA.id, profiles: [siteA, siteB])
    await coordinator.openTap(PushDeepLink.parse(payload("account.error", site: siteB.id.uuidString, ["account_id": 7])), navigator: navigator)
    #expect(navigator.opened == [siteB.id])
    #expect(coordinator.pendingTarget?.serverID == siteB.id)
    #expect(coordinator.takeTarget(for: siteB.id) == .account(id: 7))
}

@MainActor @Test func openTapCredentialClearedWaitsForLogin() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let coordinator = makePushCoordinator(store.records)
    let navigator = PushStubNavigator(active: siteA.id, profiles: [siteA, siteB], opening: .loginPage)
    await coordinator.openTap(PushDeepLink.parse(payload("push.test", site: siteB.id.uuidString)), navigator: navigator)
    #expect(navigator.opened == [siteB.id])
    #expect(coordinator.pendingTarget?.serverID == siteB.id)
    // Site A's tabs stay up under B's login page and take nothing.
    #expect(coordinator.takeTarget(for: siteA.id) == nil)
    #expect(coordinator.takeTarget(for: siteB.id) == .pushSettings)
}

@MainActor @Test func openTapFailedSwitchOrNoMatchDropsTarget() async {
    let store = PushTestDefaults(); defer { store.clear() }
    let coordinator = makePushCoordinator(store.records)
    let navigator = PushStubNavigator(active: siteA.id, profiles: [siteA, siteB], opening: .failed)
    await coordinator.openTap(PushDeepLink.parse(payload("account.error", site: siteB.id.uuidString, ["account_id": 7])), navigator: navigator)
    #expect(coordinator.pendingTarget == nil)
    let tap = PushDeepLink.parse(payload("ops_alert.fired", ["alert_event_id": 41]))
    await coordinator.openTap(tap, navigator: navigator)
    let first = coordinator.pendingTarget
    await coordinator.openTap(tap, navigator: navigator)
    #expect(first != nil && coordinator.pendingTarget != nil && first?.id != coordinator.pendingTarget?.id)
    await coordinator.openTap(PushDeepLink.parse(payload("ops_alert.fired", site: "api.example.com", ["alert_event_id": 41])), navigator: navigator)
    #expect(coordinator.pendingTarget == nil)
    #expect(navigator.opened == [siteB.id])
}

@Test func inboxKeepsTheLatestTokenAndTapUntilAttached() {
    var inbox = PushInbox()
    let older = Data([1, 2]), newer = Data([3, 4])
    let tap = PushTap(type: "push.test", siteTag: nil, target: .pushSettings)
    #expect(inbox.receive(.token(older)).isEmpty)
    #expect(inbox.receive(.tap(PushTap(type: "account.error", siteTag: nil, target: .account(id: 1)))).isEmpty)
    #expect(inbox.receive(.token(newer)).isEmpty)
    #expect(inbox.receive(.registrationFailed).isEmpty)
    #expect(inbox.receive(.registrationFailed).isEmpty)
    #expect(inbox.receive(.tap(tap)).isEmpty)
    #expect(!inbox.isAttached)
    #expect(inbox.attach() == [.token(newer), .registrationFailed, .tap(tap)])
    #expect(inbox.isAttached)
    #expect(inbox.attach().isEmpty)
    #expect(inbox.receive(.token(older)) == [.token(older)])
    #expect(inbox.receive(.tap(tap)) == [.tap(tap)])
}

@Test func inboxAttachedEmptyDeliversNothing() {
    var inbox = PushInbox()
    #expect(inbox.attach().isEmpty)
    #expect(inbox.receive(.registrationFailed) == [.registrationFailed])
}
