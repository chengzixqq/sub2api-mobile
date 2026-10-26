import Foundation
import Observation

/// 10 §0.7-2 / §0.7-4: the selected tab, one stack per tab, the sheet over the tabs and the pending cross-tab intent.
/// The stacks are route arrays rather than `NavigationPath`, so they can be read and tested; `NavigationStack(path:)`
/// takes them through `path(for:)` / `setPath(_:for:)`. MainTabs owns one and is rebuilt with each session.
@MainActor @Observable
final class AppRouter {
    var selectedTab: MainTab
    var presentedSheet: AppSheet?
    private(set) var paths: [MainTab: [AppRoute]] = [:]
    private(set) var pendingIntent: TabIntent?
    /// The session's page state (PageStateRegistry.swift); AppModel owns it.
    @ObservationIgnored private weak var pageStates: PageStateRegistry?

    init(selectedTab: MainTab = .today) { self.selectedTab = selectedTab }

    func path(for tab: MainTab) -> [AppRoute] { paths[tab] ?? [] }
    func setPath(_ path: [AppRoute], for tab: MainTab) { replacePath(path, for: tab) }
    /// Onto the current tab's stack.
    func push(_ route: AppRoute) { paths[selectedTab, default: []].append(route) }
    func popToRoot(_ tab: MainTab) { replacePath([], for: tab) }
    func present(_ sheet: AppSheet) { presentedSheet = sheet }
    /// Called when a page registers its state, so state whose route leaves a stack is dropped from then on.
    func attach(_ pageStates: PageStateRegistry) { self.pageStates = pageStates }

    /// Closes the sheet, returns the target tab to its root, records the intent, then switches. Pages pushed by a
    /// view-destination `NavigationLink` are not in the path and stay until those pages move to `AppRoute`.
    func select(_ intent: TabIntent) {
        presentedSheet = nil
        replacePath([], for: intent.tab)
        pendingIntent = intent
        selectedTab = intent.tab
    }
    /// The root of `tab` takes its intent once; another tab's intent stays for that tab.
    func takeIntent(for tab: MainTab) -> TabIntent? {
        guard let intent = pendingIntent, intent.tab == tab else { return nil }
        pendingIntent = nil
        return intent
    }

    /// A path that only grows keeps every page; a pop, a return to root or a replacement prunes once by the routes left.
    private func replacePath(_ path: [AppRoute], for tab: MainTab) {
        let old = paths[tab] ?? []
        paths[tab] = path
        guard !path.starts(with: old) else { return }
        pageStates?.prune(tab: tab, keeping: path.reduce(into: Set()) { $0.formUnion($1.pageStateKeys) }, in: self)
    }
}
