import Foundation
import Observation
import Sub2Core

/// 50 §4.2: one 添加账号 page's candidates — R19's account list for the group's platform (any platform for a composite group),
/// lite, urgency, 200 in one page, the search sent 300 ms after typing stops — with the group's members (opened on a group) or the
/// editor's drafts left out and schedulable ones first (GroupPickerPresentation). The picks keep their order across searches.
@MainActor @Observable
final class GroupAccountPickerModel {
    enum Target: Sendable, Equatable {
        /// Opened on a group: its platform and members come from the session's GroupStore, read once when the list has no row.
        case group(id: Int)
        /// Inside the group editor (S5-11): the draft's platform and members.
        case draft(platform: String, excluded: Set<Int>)
    }
    /// One read: the candidates, and how many accounts the platform has and how many of them may join.
    struct Read: Sendable {
        let search: String
        let rows: [UpstreamAccount]
        let platformTotal: Int
        let available: Int
    }
    nonisolated static let pageSize = 200
    nonisolated static let searchDelay: Duration = .milliseconds(300)

    let target: Target
    let candidates = LoadState<Read>()
    private(set) var selection: [UpstreamAccount] = []
    /// The last read without a search, which tells the three empty states apart (4.3).
    private(set) var unsearched: Read?
    var search = ""
    /// The group read here when the list had no row for it.
    private var fetchedGroup: AdminGroup?
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private let generation: UUID

    init(app: AppModel, target: Target) {
        self.app = app; self.target = target
        generation = app.sessionGeneration
    }

    /// Opened on a group: the list's row (its counts follow every write), else the one read here.
    var group: AdminGroup? {
        guard case .group(let id) = target else { return nil }
        return app?.groupStore?.group(id: id) ?? fetchedGroup
    }
    var platform: String? {
        switch target {
        case .group: group?.platform
        case .draft(let platform, _): platform
        }
    }
    /// The words for an empty list, from the last read without a search.
    var emptyText: String? {
        guard let read = candidates.value, read.rows.isEmpty, let platform else { return nil }
        let base = unsearched ?? read
        return GroupPickerPresentation.emptyText(platform: platform, platformTotal: base.platformTotal, available: base.available)
    }
    func isSelected(_ id: Int) -> Bool { selection.contains { $0.id == id } }
    func toggle(_ account: UpstreamAccount) {
        if isSelected(account.id) { selection.removeAll { $0.id == account.id } } else { selection.append(account) }
    }

    /// The first read at once, a search once typing has paused; a newer call cancels this one (the page's task).
    func load(debounced: Bool) async {
        if debounced, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do { try await Task.sleep(for: Self.searchDelay) } catch { return }
        }
        guard let app, isCurrent else { return }
        let text = search, target = target
        await candidates.load(isCurrent: { [weak self] in self?.isCurrent ?? false }) { [weak self] in
            guard let self else { throw CancellationError() }
            let platform = try await self.resolvePlatform()
            let query = AccountListQuery(search: text, platform: platform == "composite" ? "" : platform, sort: .urgency, pageSize: Self.pageSize,
                                         supportsListQuery: app.sessionContext?.has(.accountsListQuery) ?? false)
            let page = try await app.managedAccounts(page: 1, query: query)
            let memberOf: Int? = if case .group(let id) = target { id } else { nil }
            let excluded: Set<Int> = if case .draft(_, let excluded) = target { excluded } else { [] }
            let rows = GroupPickerPresentation.candidates(page.items, memberOf: memberOf, excluded: excluded, now: app.serverNow())
            // Accounts past the first page may join too.
            return Read(search: text, rows: rows, platformTotal: page.total, available: rows.count + max(0, page.total - page.items.count))
        }
        if let read = candidates.value, read.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { unsearched = read }
    }

    private var isCurrent: Bool { app?.sessionGeneration == generation }
    private func resolvePlatform() async throws -> String {
        if let platform { return platform }
        guard case .group(let id) = target, let store = app?.groupStore else { throw CancellationError() }
        let read = try await store.fetch(id: id)
        guard isCurrent else { throw CancellationError() }
        fetchedGroup = read
        return read.platform
    }
}
