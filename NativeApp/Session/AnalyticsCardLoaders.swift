import Foundation

/// 40 §1.7: one analytics page's card reads, so the page can read them all again. Each card (or tile, or chart body) registers when
/// it first reads and stays registered while the page lives; scrolled away it only turns invisible, so pull to refresh, the return
/// to the foreground and a range or filter change read every loaded card, and the 60-second tick only the ones on screen. The page
/// holds it in its @State and hands it down through `EnvironmentValues.analyticsCardLoaders`.
@MainActor final class AnalyticsCardLoaders {
    /// Captures the session and values only (never a view), and checks by itself whether the card would read now.
    typealias Load = @MainActor @Sendable (_ refresh: Bool) async -> Void

    private struct Entry {
        let followsLiveTick: Bool
        let load: Load
    }

    private var entries: [String: Entry] = [:]
    private var hidden: Set<String> = []
    /// In the order the cards first registered.
    private(set) var registeredIDs: [String] = []

    init() {}

    /// The same id again replaces its read and keeps its place and visibility. RPM / TPM, which keeps its own pace, passes
    /// `followsLiveTick: false`.
    func register(_ id: String, followsLiveTick: Bool = true, load: @escaping Load) {
        if entries[id] == nil { registeredIDs.append(id) }
        entries[id] = Entry(followsLiveTick: followsLiveTick, load: load)
    }
    func unregister(_ id: String) {
        entries[id] = nil
        hidden.remove(id)
        registeredIDs.removeAll { $0 == id }
    }
    /// A card counts as visible until it says otherwise.
    func setVisible(_ id: String, _ isVisible: Bool) {
        if isVisible { hidden.remove(id) } else { hidden.insert(id) }
    }

    /// Pull to refresh, the foreground and a choice change: every registered card at once; returns when all have finished.
    func reloadAll(refresh: Bool) async {
        await run(registeredIDs, refresh: refresh)
    }
    /// The 60-second refresh of a range reaching now: the visible cards that follow it, read past their value.
    func tick() async {
        await run(registeredIDs.filter { entries[$0]?.followsLiveTick == true && !hidden.contains($0) }, refresh: true)
    }

    private func run(_ ids: [String], refresh: Bool) async {
        let loads = ids.compactMap { entries[$0]?.load }
        guard !loads.isEmpty else { return }
        await withDiscardingTaskGroup { group in
            for load in loads { group.addTask { await load(refresh) } }
        }
    }
}
