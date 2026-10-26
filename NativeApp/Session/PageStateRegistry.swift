import Foundation
import Observation

/// X21 / C-13: page state shared along one tab's navigation stack, such as the analytics session that `analytics` and the
/// pages it pushes use (40 §0.1) and a usage-record list its request detail updates in place (40 §7.4). Entries are kept
/// per window, tab and key: every iPad window has its own MainTabs and AppRouter, so a window never shares or prunes
/// another's state. AppRouter drops the entries whose route left the tab's path, those of a closed window go with its
/// router, and AppModel makes a new registry with each session, so a session change drops everything.
///
/// A page reads `router.selectedTab` when it first appears and keeps it in `@State`; it registers once in `onAppear` /
/// `task` through `state(_:tab:prunedBy:make:)` with a key from `PageStateKey`, keeps the instance in `@State` and never
/// calls `state` from `body`. It must be pushed as an `AppRoute`: a page pushed by a view-destination `NavigationLink` is
/// not in the path.
@MainActor @Observable
final class PageStateRegistry {
    private struct Entry: Hashable {
        let router: ObjectIdentifier
        let tab: MainTab
        let key: String
    }
    /// The router is weak and compared on every read, so a closed window's entries are never found under a new router at
    /// the same address.
    private struct Slot {
        weak var router: AppRouter?
        let value: AnyObject
    }
    // Not observed: registering in `onAppear` and pruning while NavigationStack sets its path update no view.
    @ObservationIgnored private var states: [Entry: Slot] = [:]

    init() {}

    /// The instance for this window's tab and key, made on the first call; another type under the same key replaces it.
    /// `router` prunes it once the page's route leaves the tab's stack.
    func state<T: AnyObject>(_ key: String, tab: MainTab, prunedBy router: AppRouter, make: () -> T) -> T {
        router.attach(self)
        states = states.filter { $0.value.router != nil }
        if let existing = existing(key, tab: tab, in: router, as: T.self) { return existing }
        let made = make()
        states[Entry(router: ObjectIdentifier(router), tab: tab, key: key)] = Slot(router: router, value: made)
        return made
    }
    func existing<T: AnyObject>(_ key: String, tab: MainTab, in router: AppRouter, as type: T.Type = T.self) -> T? {
        let slot = states[Entry(router: ObjectIdentifier(router), tab: tab, key: key)]
        return slot?.router === router ? slot?.value as? T : nil
    }
    /// Every live instance of `type` in this window's `tab`, ordered by key; a request detail finds the lists of its tab with it.
    func instances<T: AnyObject>(of type: T.Type, tab: MainTab, in router: AppRouter) -> [T] {
        states.filter { $0.key.tab == tab && $0.value.router === router }
            .sorted { $0.key.key < $1.key.key }
            .compactMap { $0.value.value as? T }
    }
    func release(_ key: String, tab: MainTab, in router: AppRouter) {
        states[Entry(router: ObjectIdentifier(router), tab: tab, key: key)] = nil
    }
    /// Drops the entries of this window's `tab` whose key is not in `keys`; other tabs and windows are untouched.
    func prune(tab: MainTab, keeping keys: Set<String>, in router: AppRouter) {
        states = states.filter { entry, slot in
            guard let owner = slot.router else { return false }
            return owner !== router || entry.tab != tab || keys.contains(entry.key)
        }
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
