import Foundation
import Observation

/// 10 §0.7-2 / §0.7-4: the selected tab, one stack per tab, the sheet over the tabs and the pending cross-tab intent.
/// The stacks are route arrays rather than `NavigationPath`, so they can be read and tested; `NavigationStack(path:)`
/// takes them through `path(for:)` / `setPath(_:for:)`. MainTabs owns one and is rebuilt with each session.
@MainActor @Observable
final class AppRouter {
    var selectedTab: MainTab
    /// Another sheet, or none, starts without unsaved input and without a switch waiting.
    var presentedSheet: AppSheet? {
        didSet {
            guard presentedSheet != oldValue else { return }
            sheetHasUnsavedInput = false
            pendingSelect = nil
        }
    }
    /// S2-中-27: the sheet's form holds input that closing it would lose; the sheet keeps it (TabSwitchGuard).
    var sheetHasUnsavedInput = false
    /// A switch held until the sheet has asked: 放弃 goes on (`confirmPendingSelect`), staying drops it (`cancelPendingSelect`).
    private(set) var pendingSelect: TabIntent?
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
    /// A sheet with unsaved input is asked first: the switch waits in `pendingSelect` (S2-中-27).
    func select(_ intent: TabIntent) {
        if presentedSheet != nil, sheetHasUnsavedInput {
            pendingSelect = intent
            return
        }
        switchTab(to: intent)
    }
    /// 放弃 of the sheet's question: the switch that waited goes ahead and closes the sheet. False when none waits.
    @discardableResult func confirmPendingSelect() -> Bool {
        guard let intent = pendingSelect else { return false }
        pendingSelect = nil
        sheetHasUnsavedInput = false
        switchTab(to: intent)
        return true
    }
    /// 继续填写 / 继续编辑: the sheet stays and so does the tab.
    func cancelPendingSelect() { pendingSelect = nil }
    /// The root of `tab` takes its intent once; another tab's intent stays for that tab.
    func takeIntent(for tab: MainTab) -> TabIntent? {
        guard let intent = pendingIntent, intent.tab == tab else { return nil }
        pendingIntent = nil
        return intent
    }

    private func switchTab(to intent: TabIntent) {
        presentedSheet = nil
        replacePath([], for: intent.tab)
        pendingIntent = intent
        selectedTab = intent.tab
    }
    /// A path that only grows keeps every page; a pop, a return to root or a replacement prunes once by the routes left.
    private func replacePath(_ path: [AppRoute], for tab: MainTab) {
        let old = paths[tab] ?? []
        paths[tab] = path
        guard !path.starts(with: old) else { return }
        pageStates?.prune(tab: tab, keeping: path.reduce(into: Set()) { $0.formUnion($1.pageStateKeys) }, in: self)
    }
}
