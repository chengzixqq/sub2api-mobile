import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

private final class PageProbe {}
private final class OtherProbe {}

private let session = PageStateKey.analyticsSession
private let usageLogs = LogsRoute(account: RouteObject(id: 3), group: RouteObject(id: 5), user: RouteObject(id: 7), model: "gpt")

@MainActor @Test func sameTabAndKeyReturnsTheSameInstanceAndMakesOnce() {
    let registry = PageStateRegistry(), router = AppRouter()
    var makes = 0
    let first = registry.state("k", tab: .search, prunedBy: router) { makes += 1; return PageProbe() }
    let second = registry.state("k", tab: .search, prunedBy: router) { makes += 1; return PageProbe() }
    let third = registry.state("k", tab: .search, prunedBy: router) { makes += 1; return PageProbe() }
    #expect(first === second && second === third)
    #expect(makes == 1)
}

@MainActor @Test func tabsAndKeysAreIsolated() {
    let registry = PageStateRegistry(), router = AppRouter()
    let today = registry.state("k", tab: .today, prunedBy: router) { PageProbe() }
    let search = registry.state("k", tab: .search, prunedBy: router) { PageProbe() }
    let other = registry.state("j", tab: .search, prunedBy: router) { PageProbe() }
    #expect(today !== search && search !== other)
    registry.release("k", tab: .search, in: router)
    #expect(registry.existing("k", tab: .search, in: router, as: PageProbe.self) == nil)
    #expect(registry.existing("k", tab: .today, in: router, as: PageProbe.self) === today)
    #expect(registry.existing("j", tab: .search, in: router, as: PageProbe.self) === other)
}

@MainActor @Test func releaseMakesTheNextCallBuildAgain() {
    let registry = PageStateRegistry(), router = AppRouter()
    var makes = 0
    let first = registry.state("k", tab: .users, prunedBy: router) { makes += 1; return PageProbe() }
    registry.release("k", tab: .users, in: router)
    #expect(registry.existing("k", tab: .users, in: router, as: PageProbe.self) == nil)
    let again = registry.state("k", tab: .users, prunedBy: router) { makes += 1; return PageProbe() }
    #expect(makes == 2)
    #expect(again !== first)
}

@MainActor @Test func pruneKeepsListedKeysOfThatTabOnly() {
    let registry = PageStateRegistry(), router = AppRouter()
    let kept = registry.state("a", tab: .search, prunedBy: router) { PageProbe() }
    _ = registry.state("b", tab: .search, prunedBy: router) { PageProbe() }
    let today = registry.state("a", tab: .today, prunedBy: router) { PageProbe() }
    registry.prune(tab: .search, keeping: ["a"], in: router)
    #expect(registry.existing("a", tab: .search, in: router, as: PageProbe.self) === kept)
    #expect(registry.existing("b", tab: .search, in: router, as: PageProbe.self) == nil)
    #expect(registry.existing("a", tab: .today, in: router, as: PageProbe.self) === today)
}

@MainActor @Test func existingNeverMakes() {
    let registry = PageStateRegistry(), router = AppRouter()
    #expect(registry.existing("k", tab: .monitor, in: router, as: PageProbe.self) == nil)
    #expect(registry.instances(of: PageProbe.self, tab: .monitor, in: router).isEmpty)
    let probe = registry.state("k", tab: .monitor, prunedBy: router) { PageProbe() }
    let found: PageProbe? = registry.existing("k", tab: .monitor, in: router)
    #expect(found === probe)
    #expect(registry.existing("k", tab: .monitor, in: router, as: OtherProbe.self) == nil)
}

@MainActor @Test func instancesListOneTypeInOneTab() {
    let registry = PageStateRegistry(), router = AppRouter()
    let second = registry.state("b", tab: .search, prunedBy: router) { PageProbe() }
    let first = registry.state("a", tab: .search, prunedBy: router) { PageProbe() }
    _ = registry.state("c", tab: .search, prunedBy: router) { OtherProbe() }
    _ = registry.state("a", tab: .today, prunedBy: router) { PageProbe() }
    let found = registry.instances(of: PageProbe.self, tab: .search, in: router)
    #expect(found.elementsEqual([first, second]) { $0 === $1 })
    #expect(registry.instances(of: OtherProbe.self, tab: .today, in: router).isEmpty)
}

@MainActor @Test func sameKeyWithAnotherTypeIsReplaced() {
    let registry = PageStateRegistry(), router = AppRouter()
    _ = registry.state("k", tab: .accounts, prunedBy: router) { PageProbe() }
    var makes = 0
    let other = registry.state("k", tab: .accounts, prunedBy: router) { makes += 1; return OtherProbe() }
    #expect(makes == 1)
    #expect(registry.existing("k", tab: .accounts, in: router, as: OtherProbe.self) === other)
    #expect(registry.existing("k", tab: .accounts, in: router, as: PageProbe.self) == nil)
}

@MainActor @Test func routeKeysFollowTheContract() {
    #expect(session == "analytics.session")
    let analytics: [AppRoute] = [
        .analytics(), .analyticsMore(), .analyticsChart(.tokens), .analyticsRank(.model), .analyticsModel(model: "gpt"),
    ]
    #expect(analytics.allSatisfy { $0.pageStateKeys == [session] })
    #expect(AppRoute.logs(usageLogs).pageStateKeys == [PageStateKey.logs(usageLogs)])
    let others: [AppRoute] = [
        .request(.usageRequestID("req")), .account(id: 1), .groups(), .settings(), .user(id: 2), .alert(id: 3),
    ]
    #expect(others.allSatisfy { $0.pageStateKeys.isEmpty })
}

@Test func logsKeyIgnoresObjectNames() {
    let named = LogsRoute(
        account: RouteObject(id: 3, name: "A"), group: RouteObject(id: 5, name: "G"), user: RouteObject(id: 7, name: "U"), model: "gpt"
    )
    #expect(PageStateKey.logs(named) == PageStateKey.logs(usageLogs))
    #expect(PageStateKey.logs(usageLogs).hasPrefix("logs.store."))
}

@Test(arguments: [
    LogsRoute(scope: .errors, account: RouteObject(id: 3), group: RouteObject(id: 5), user: RouteObject(id: 7), model: "gpt"),
    LogsRoute(account: RouteObject(id: 4), group: RouteObject(id: 5), user: RouteObject(id: 7), model: "gpt"),
    LogsRoute(group: RouteObject(id: 5), user: RouteObject(id: 7), model: "gpt"),
    LogsRoute(account: RouteObject(id: 3), group: RouteObject(id: 6), user: RouteObject(id: 7), model: "gpt"),
    LogsRoute(account: RouteObject(id: 3), group: RouteObject(id: 5), user: RouteObject(id: 8), model: "gpt"),
    LogsRoute(account: RouteObject(id: 3), group: RouteObject(id: 5), user: RouteObject(id: 7), model: "gpt-4"),
    LogsRoute(account: RouteObject(id: 3), group: RouteObject(id: 5), user: RouteObject(id: 7)),
    LogsRoute(account: RouteObject(id: 3), group: RouteObject(id: 5), user: RouteObject(id: 7), model: "gpt", modelSource: .upstream),
])
func logsKeySeparatesConditions(_ other: LogsRoute) {
    #expect(PageStateKey.logs(other) != PageStateKey.logs(usageLogs))
}

@Test func logsKeysNeverCollideAcrossObjectsOrEmptyModel() {
    let routes = [
        LogsRoute(), LogsRoute(account: RouteObject(id: 3)), LogsRoute(group: RouteObject(id: 3)),
        LogsRoute(user: RouteObject(id: 3)), LogsRoute(model: ""), LogsRoute(model: "-"), LogsRoute(modelSource: .mapping),
    ]
    #expect(Set(routes.map(PageStateKey.logs)).count == routes.count)
}

@MainActor @Test func poppingReleasesStateWhoseRoutesLeftTheStack() {
    let router = AppRouter(selectedTab: .search)
    let registry = PageStateRegistry()
    router.setPath([.analytics(), .analyticsChart(.tokens)], for: .search)
    let probe = registry.state(session, tab: .search, prunedBy: router) { PageProbe() }
    router.setPath([.analytics()], for: .search)
    #expect(registry.existing(session, tab: .search, in: router, as: PageProbe.self) === probe)
    router.setPath([], for: .search)
    #expect(registry.existing(session, tab: .search, in: router, as: PageProbe.self) == nil)
}

@MainActor @Test func analyticsSessionIsReleasedWithoutAnyOtherPageAttaching() {
    let router = AppRouter(selectedTab: .search)
    let registry = PageStateRegistry()
    var makes = 0
    router.setPath([.analytics(), .analyticsChart(.tokens)], for: .search)
    let first = registry.state(session, tab: .search, prunedBy: router) { makes += 1; return PageProbe() }
    router.setPath([], for: .search)
    #expect(registry.existing(session, tab: .search, in: router, as: PageProbe.self) == nil)
    router.push(.analytics())
    let again = registry.state(session, tab: .search, prunedBy: router) { makes += 1; return PageProbe() }
    #expect(makes == 2)
    #expect(again !== first)
}

@MainActor @Test func logsStoreSurvivesUntilItsListLeaves() {
    let router = AppRouter(selectedTab: .today)
    let registry = PageStateRegistry()
    let key = PageStateKey.logs(usageLogs)
    router.setPath([.logs(usageLogs), .request(.usageRequestID("req"))], for: .today)
    let store = registry.state(key, tab: .today, prunedBy: router) { PageProbe() }
    router.setPath([.logs(usageLogs)], for: .today)
    #expect(registry.existing(key, tab: .today, in: router, as: PageProbe.self) === store)
    router.setPath([], for: .today)
    #expect(registry.existing(key, tab: .today, in: router, as: PageProbe.self) == nil)
}

@MainActor @Test func pushNeverPrunes() {
    let router = AppRouter(selectedTab: .search)
    let registry = PageStateRegistry()
    router.push(.groups())
    // No route in the path holds this key, so any prune would drop it.
    let orphan = registry.state("orphan", tab: .search, prunedBy: router) { PageProbe() }
    router.push(.analytics())
    router.push(.account(id: 1))
    #expect(registry.existing("orphan", tab: .search, in: router, as: PageProbe.self) === orphan)
    router.setPath(router.path(for: .search) + [.user(id: 2)], for: .search)
    router.setPath(router.path(for: .search), for: .search)
    #expect(registry.existing("orphan", tab: .search, in: router, as: PageProbe.self) === orphan)
    router.setPath([.groups()], for: .search)
    #expect(registry.existing("orphan", tab: .search, in: router, as: PageProbe.self) == nil)
}

@MainActor @Test func sameLengthReplacementPrunesTheReplacedRoute() {
    let router = AppRouter(selectedTab: .search)
    let registry = PageStateRegistry()
    let errors = LogsRoute(scope: .errors)
    router.setPath([.logs(usageLogs)], for: .search)
    _ = registry.state(PageStateKey.logs(usageLogs), tab: .search, prunedBy: router) { PageProbe() }
    router.setPath([.logs(errors)], for: .search)
    #expect(registry.existing(PageStateKey.logs(usageLogs), tab: .search, in: router, as: PageProbe.self) == nil)
}

@MainActor @Test func popToRootAndSelectReleaseOnlyThatTab() {
    let router = AppRouter()
    let registry = PageStateRegistry()
    let logsKey = PageStateKey.logs(usageLogs)
    router.setPath([.analytics()], for: .today)
    router.setPath([.logs(usageLogs)], for: .search)
    let today = registry.state(session, tab: .today, prunedBy: router) { PageProbe() }
    let search = registry.state(logsKey, tab: .search, prunedBy: router) { PageProbe() }
    router.select(.monitor())
    #expect(router.selectedTab == .monitor && router.pendingIntent == .monitor())
    #expect(registry.existing(session, tab: .today, in: router, as: PageProbe.self) === today)
    #expect(registry.existing(logsKey, tab: .search, in: router, as: PageProbe.self) === search)
    router.popToRoot(.search)
    #expect(router.path(for: .search).isEmpty)
    #expect(registry.existing(logsKey, tab: .search, in: router, as: PageProbe.self) == nil)
    #expect(registry.existing(session, tab: .today, in: router, as: PageProbe.self) === today)
    router.select(.today)
    #expect(router.selectedTab == .today && router.pendingIntent == .today && router.path(for: .today).isEmpty)
    #expect(registry.existing(session, tab: .today, in: router, as: PageProbe.self) == nil)
}

@MainActor @Test func routerWithoutRegistryKeepsItsPaths() {
    let router = AppRouter()
    router.setPath([.analytics(), .analyticsChart(.tokens)], for: .today)
    router.setPath([.analytics()], for: .today)
    router.popToRoot(.search)
    router.select(.users)
    #expect(router.path(for: .today) == [.analytics()] && router.selectedTab == .users)
}

@MainActor @Test func replacingTheSessionRegistryDropsEverything() {
    let router = AppRouter(selectedTab: .search)
    router.setPath([.analytics()], for: .search)
    var registry: PageStateRegistry? = PageStateRegistry()
    weak let oldRegistry = registry
    var makes = 0
    weak let oldProbe = registry?.state(session, tab: .search, prunedBy: router) { makes += 1; return PageProbe() }
    #expect(oldRegistry != nil && oldProbe != nil)
    // AppModel makes a new registry with each session.
    registry = PageStateRegistry()
    #expect(oldRegistry == nil)
    #expect(oldProbe == nil)
    router.setPath([], for: .search)
    router.setPath([.analytics()], for: .search)
    let fresh = registry?.state(session, tab: .search, prunedBy: router) { makes += 1; return PageProbe() }
    #expect(makes == 2 && fresh != nil)
    router.setPath([], for: .search)
    #expect(registry?.existing(session, tab: .search, in: router, as: PageProbe.self) == nil)
}

// iPad windows each have their own MainTabs and AppRouter but share the session's registry.
@MainActor @Test func windowsOnTheSameTabDoNotShareState() {
    let registry = PageStateRegistry()
    let windowA = AppRouter(selectedTab: .today), windowB = AppRouter(selectedTab: .today)
    windowA.setPath([.analytics()], for: .today)
    windowB.setPath([.analytics()], for: .today)
    let a = registry.state(session, tab: .today, prunedBy: windowA) { PageProbe() }
    let b = registry.state(session, tab: .today, prunedBy: windowB) { PageProbe() }
    #expect(a !== b)
    #expect(registry.existing(session, tab: .today, in: windowA, as: PageProbe.self) === a)
    #expect(registry.existing(session, tab: .today, in: windowB, as: PageProbe.self) === b)
    #expect(registry.instances(of: PageProbe.self, tab: .today, in: windowA).elementsEqual([a]) { $0 === $1 })
}

@MainActor @Test func oneWindowLeavingItsStackKeepsTheOtherWindowsState() {
    let registry = PageStateRegistry()
    let windowA = AppRouter(selectedTab: .search), windowB = AppRouter(selectedTab: .search)
    let key = PageStateKey.logs(usageLogs)
    windowA.setPath([.logs(usageLogs)], for: .search)
    windowB.setPath([.logs(usageLogs)], for: .search)
    _ = registry.state(key, tab: .search, prunedBy: windowA) { PageProbe() }
    let store = registry.state(key, tab: .search, prunedBy: windowB) { PageProbe() }
    windowA.setPath([], for: .search)
    #expect(registry.existing(key, tab: .search, in: windowA, as: PageProbe.self) == nil)
    #expect(registry.instances(of: PageProbe.self, tab: .search, in: windowB).elementsEqual([store]) { $0 === $1 })
    windowA.select(.search)
    registry.release(key, tab: .search, in: windowA)
    #expect(registry.existing(key, tab: .search, in: windowB, as: PageProbe.self) === store)
    windowB.setPath([], for: .search)
    #expect(registry.instances(of: PageProbe.self, tab: .search, in: windowB).isEmpty)
}

@MainActor @Test func aClosedWindowsStateGoesWithItsRouter() {
    let registry = PageStateRegistry()
    var closed: AppRouter? = AppRouter(selectedTab: .today)
    closed?.setPath([.analytics()], for: .today)
    weak let closedProbe = closed.map { registry.state(session, tab: .today, prunedBy: $0) { PageProbe() } }
    #expect(closedProbe != nil)
    closed = nil
    let open = AppRouter(selectedTab: .today)
    open.setPath([.analytics()], for: .today)
    var makes = 0
    let fresh = registry.state(session, tab: .today, prunedBy: open) { makes += 1; return PageProbe() }
    #expect(makes == 1 && closedProbe == nil)
    #expect(registry.instances(of: PageProbe.self, tab: .today, in: open).elementsEqual([fresh]) { $0 === $1 })
}
