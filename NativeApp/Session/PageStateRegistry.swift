import Foundation
import Observation

/// X21 / C-13: page state shared along one tab's navigation stack, such as the analytics session that `analytics` and the
/// pages it pushes use (40 §0.1) and a usage-record list its request detail updates in place (40 §7.4). Entries are kept
/// per tab and key; AppRouter drops those whose route left the tab's path, and AppModel makes a new registry with each
/// session, so a session change drops everything.
///
/// A page reads `router.selectedTab` when it first appears and keeps it in `@State`; it registers once in `onAppear` /
/// `task` through `state(_:tab:prunedBy:make:)` with a key from `PageStateKey`, keeps the instance in `@State` and never
/// calls `state` from `body`. It must be pushed as an `AppRoute`: a page pushed by a view-destination `NavigationLink` is
/// not in the path.
@MainActor @Observable
final class PageStateRegistry {
    private struct Entry: Hashable {
        let tab: MainTab
        let key: String
    }
    // Not observed: registering in `onAppear` and pruning while NavigationStack sets its path update no view.
    @ObservationIgnored private var states: [Entry: AnyObject] = [:]

    init() {}

    /// The instance for this tab and key, made on the first call. Another type under the same key replaces it. Pages use
    /// `state(_:tab:prunedBy:make:)`; this one is for the registry and its tests.
    func state<T: AnyObject>(_ key: String, tab: MainTab, make: () -> T) -> T {
        let entry = Entry(tab: tab, key: key)
        if let existing = states[entry] as? T { return existing }
        let made = make()
        states[entry] = made
        return made
    }
    /// The same, after letting `router` prune this registry when the page's route leaves the tab's stack.
    func state<T: AnyObject>(_ key: String, tab: MainTab, prunedBy router: AppRouter, make: () -> T) -> T {
        router.attach(self)
        return state(key, tab: tab, make: make)
    }
    func existing<T: AnyObject>(_ key: String, tab: MainTab, as type: T.Type = T.self) -> T? {
        states[Entry(tab: tab, key: key)] as? T
    }
    /// Every live instance of `type` in `tab`, ordered by key; a request detail finds the lists of its tab with it.
    func instances<T: AnyObject>(of type: T.Type, tab: MainTab) -> [T] {
        states.filter { $0.key.tab == tab }
            .sorted { $0.key.key < $1.key.key }
            .compactMap { $0.value as? T }
    }
    func release(_ key: String, tab: MainTab) {
        states[Entry(tab: tab, key: key)] = nil
    }
    /// Drops the entries of `tab` whose key is not in `keys`; other tabs are untouched.
    func prune(tab: MainTab, keeping keys: Set<String>) {
        states = states.filter { $0.key.tab != tab || keys.contains($0.key.key) }
    }
}

/// The only place the registry keys are spelled; a module that shares page state adds its key and routes here.
enum PageStateKey {
    /// 40 §0.1: `analytics` and the More / Chart / Rank / Model pages share one session.
    static let analyticsSession = "analytics.session"
    /// 40 §7.4: one list per filter. Object names are display only; the model goes last, so it cannot run into the rest.
    static func logs(_ route: LogsRoute) -> String {
        let objects = "a\(id(route.account)).g\(id(route.group)).u\(id(route.user))"
        let base = "logs.store.\(route.scope.rawValue).\(objects).\(route.modelSource.rawValue)"
        return route.model.map { "\(base)|m=\($0)" } ?? base
    }
    private static func id(_ object: RouteObject?) -> String { object.map { String($0.id) } ?? "-" }
}

extension AppRoute {
    /// The registry keys of the page this route shows; AppRouter keeps the entries whose route is still in the path.
    var pageStateKeys: Set<String> {
        switch self {
        case .analytics, .analyticsMore, .analyticsChart, .analyticsRank, .analyticsModel: [PageStateKey.analyticsSession]
        case .logs(let route): [PageStateKey.logs(route)]
        default: []
        }
    }
}
