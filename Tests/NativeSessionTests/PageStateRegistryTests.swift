import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

private final class PageProbe {}
private final class OtherProbe {}

private let session = PageStateKey.analyticsSession
private let usageLogs = LogsRoute(account: RouteObject(id: 3), group: RouteObject(id: 5), user: RouteObject(id: 7), model: "gpt")

@MainActor @Test func sameTabAndKeyReturnsTheSameInstanceAndMakesOnce() {
    let registry = PageStateRegistry()
    var makes = 0
    let first = registry.state("k", tab: .search) { makes += 1; return PageProbe() }
    let second = registry.state("k", tab: .search) { makes += 1; return PageProbe() }
    let third = registry.state("k", tab: .search) { makes += 1; return PageProbe() }
    #expect(first === second && second === third)
    #expect(makes == 1)
}

@MainActor @Test func tabsAndKeysAreIsolated() {
    let registry = PageStateRegistry()
    let today = registry.state("k", tab: .today) { PageProbe() }
    let search = registry.state("k", tab: .search) { PageProbe() }
    let other = registry.state("j", tab: .search) { PageProbe() }
    #expect(today !== search && search !== other)
    registry.release("k", tab: .search)
    #expect(registry.existing("k", tab: .search, as: PageProbe.self) == nil)
    #expect(registry.existing("k", tab: .today, as: PageProbe.self) === today)
    #expect(registry.existing("j", tab: .search, as: PageProbe.self) === other)
}

@MainActor @Test func releaseMakesTheNextCallBuildAgain() {
    let registry = PageStateRegistry()
    var makes = 0
    let first = registry.state("k", tab: .users) { makes += 1; return PageProbe() }
    registry.release("k", tab: .users)
    #expect(registry.existing("k", tab: .users, as: PageProbe.self) == nil)
    let again = registry.state("k", tab: .users) { makes += 1; return PageProbe() }
    #expect(makes == 2)
    #expect(again !== first)
}

@MainActor @Test func pruneKeepsListedKeysOfThatTabOnly() {
    let registry = PageStateRegistry()
    let kept = registry.state("a", tab: .search) { PageProbe() }
    _ = registry.state("b", tab: .search) { PageProbe() }
    let today = registry.state("a", tab: .today) { PageProbe() }
    registry.prune(tab: .search, keeping: ["a"])
    #expect(registry.existing("a", tab: .search, as: PageProbe.self) === kept)
    #expect(registry.existing("b", tab: .search, as: PageProbe.self) == nil)
    #expect(registry.existing("a", tab: .today, as: PageProbe.self) === today)
}

@MainActor @Test func existingNeverMakes() {
    let registry = PageStateRegistry()
    #expect(registry.existing("k", tab: .monitor, as: PageProbe.self) == nil)
    #expect(registry.instances(of: PageProbe.self, tab: .monitor).isEmpty)
    let probe = registry.state("k", tab: .monitor) { PageProbe() }
    let found: PageProbe? = registry.existing("k", tab: .monitor)
    #expect(found === probe)
    #expect(registry.existing("k", tab: .monitor, as: OtherProbe.self) == nil)
}

@MainActor @Test func instancesListOneTypeInOneTab() {
    let registry = PageStateRegistry()
    let second = registry.state("b", tab: .search) { PageProbe() }
    let first = registry.state("a", tab: .search) { PageProbe() }
    _ = registry.state("c", tab: .search) { OtherProbe() }
    _ = registry.state("a", tab: .today) { PageProbe() }
    let found = registry.instances(of: PageProbe.self, tab: .search)
    #expect(found.elementsEqual([first, second]) { $0 === $1 })
    #expect(registry.instances(of: OtherProbe.self, tab: .today).isEmpty)
}

@MainActor @Test func sameKeyWithAnotherTypeIsReplaced() {
    let registry = PageStateRegistry()
    _ = registry.state("k", tab: .accounts) { PageProbe() }
    var makes = 0
    let other = registry.state("k", tab: .accounts) { makes += 1; return OtherProbe() }
    #expect(makes == 1)
    #expect(registry.existing("k", tab: .accounts, as: OtherProbe.self) === other)
    #expect(registry.existing("k", tab: .accounts, as: PageProbe.self) == nil)
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
    #expect(registry.existing(session, tab: .search, as: PageProbe.self) === probe)
    router.setPath([], for: .search)
    #expect(registry.existing(session, tab: .search, as: PageProbe.self) == nil)
}

@MainActor @Test func analyticsSessionIsReleasedWithoutAnyOtherPageAttaching() {
    let router = AppRouter(selectedTab: .search)
    let registry = PageStateRegistry()
    var makes = 0
    router.setPath([.analytics(), .analyticsChart(.tokens)], for: .search)
    let first = registry.state(session, tab: .search, prunedBy: router) { makes += 1; return PageProbe() }
    router.setPath([], for: .search)
    #expect(registry.existing(session, tab: .search, as: PageProbe.self) == nil)
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
    #expect(registry.existing(key, tab: .today, as: PageProbe.self) === store)
    router.setPath([], for: .today)
    #expect(registry.existing(key, tab: .today, as: PageProbe.self) == nil)
}

@MainActor @Test func pushNeverPrunes() {
    let router = AppRouter(selectedTab: .search)
    let registry = PageStateRegistry()
    router.push(.groups())
    // No route in the path holds this key, so any prune would drop it.
    let orphan = registry.state("orphan", tab: .search, prunedBy: router) { PageProbe() }
    router.push(.analytics())
    router.push(.account(id: 1))
    #expect(registry.existing("orphan", tab: .search, as: PageProbe.self) === orphan)
    router.setPath(router.path(for: .search) + [.user(id: 2)], for: .search)
    router.setPath(router.path(for: .search), for: .search)
    #expect(registry.existing("orphan", tab: .search, as: PageProbe.self) === orphan)
    router.setPath([.groups()], for: .search)
    #expect(registry.existing("orphan", tab: .search, as: PageProbe.self) == nil)
}

@MainActor @Test func sameLengthReplacementPrunesTheReplacedRoute() {
    let router = AppRouter(selectedTab: .search)
    let registry = PageStateRegistry()
    let errors = LogsRoute(scope: .errors)
    router.setPath([.logs(usageLogs)], for: .search)
    _ = registry.state(PageStateKey.logs(usageLogs), tab: .search, prunedBy: router) { PageProbe() }
    router.setPath([.logs(errors)], for: .search)
    #expect(registry.existing(PageStateKey.logs(usageLogs), tab: .search, as: PageProbe.self) == nil)
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
    #expect(registry.existing(session, tab: .today, as: PageProbe.self) === today)
    #expect(registry.existing(logsKey, tab: .search, as: PageProbe.self) === search)
    router.popToRoot(.search)
    #expect(router.path(for: .search).isEmpty)
    #expect(registry.existing(logsKey, tab: .search, as: PageProbe.self) == nil)
    #expect(registry.existing(session, tab: .today, as: PageProbe.self) === today)
    router.select(.today)
    #expect(router.selectedTab == .today && router.pendingIntent == .today && router.path(for: .today).isEmpty)
    #expect(registry.existing(session, tab: .today, as: PageProbe.self) == nil)
}

@MainActor @Test func routerWithoutRegistryAndUnattachedRegistryAreUntouched() {
    let router = AppRouter()
    router.setPath([.analytics()], for: .today)
    router.setPath([], for: .today)
    router.popToRoot(.search)
    router.select(.users)
    let registry = PageStateRegistry()
    let probe = registry.state(session, tab: .today) { PageProbe() }
    router.setPath([.analytics()], for: .today)
    router.setPath([], for: .today)
    #expect(registry.existing(session, tab: .today, as: PageProbe.self) === probe)
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
    #expect(registry?.existing(session, tab: .search, as: PageProbe.self) == nil)
}
