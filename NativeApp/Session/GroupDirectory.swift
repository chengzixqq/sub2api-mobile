import Foundation
import Observation
import Sub2Core

/// C-10 (X11): the session's group names and order, shared by every page that shows a group (20 §1.2 `groups/all` with
/// `include_inactive`). Session state (C-0.2): AppModel makes it in `publish` and drops it in `endActiveSession`. One request at a
/// time; writers call `upsert` / `remove`, and an edit made while a read is out is laid over its result.
@MainActor @Observable
final class GroupDirectory {
    private(set) var state: BlockState<[AdminGroup]> = .idle
    /// 429 wait and failure backoff (D23).
    private(set) var refreshState = BlockRefresh()
    /// sort_order, then id (AdminGroup.displayOrder).
    var groups: [AdminGroup] { state.value ?? [] }

    @ObservationIgnored private let load: @Sendable () async throws -> [AdminGroup]
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var pendingEdits: [Edit] = []
    private enum Edit { case upsert(AdminGroup), remove(Int) }

    init(load: @escaping @Sendable () async throws -> [AdminGroup], now: @escaping @MainActor () -> Date = { Date() }) {
        self.load = load; self.now = now
    }

    /// First use in the session: loads unless there is a value; a read already out is shared.
    func ensureLoaded() async {
        if let inFlight { await inFlight.value; return }
        guard state.value == nil else { return }
        await start()?.value
    }
    /// Reads again unless a read is already out, which is shared instead.
    func refresh() async {
        if let inFlight { await inFlight.value; return }
        await start()?.value
    }

    func group(id: Int) -> AdminGroup? { groups.first { $0.id == id } }
    /// nil when unknown: the caller writes “#id”.
    func name(for id: Int) -> String? { group(id: id)?.name }
    /// After a write (rename, disable, copy) the shown list changes at once.
    func upsert(_ group: AdminGroup) { apply(.upsert(group)) }
    func remove(id: Int) { apply(.remove(id)) }

    nonisolated static func sorted(_ groups: [AdminGroup]) -> [AdminGroup] { groups.sorted(by: AdminGroup.displayOrder) }

    private func start() -> Task<Void, Never>? {
        guard refreshState.allowsRequest(at: now()) else { return nil }
        pendingEdits = []
        state = state.withLoading()
        let load = self.load
        let task = Task { [weak self] in
            let result: Result<[AdminGroup], any Error>
            do { result = .success(try await load()) } catch { result = .failure(error) }
            self?.finish(result)
        }
        inFlight = task
        return task
    }
    private func finish(_ result: Result<[AdminGroup], any Error>) {
        inFlight = nil
        switch result {
        case .success(let loaded):
            state = .loaded(Self.sorted(pendingEdits.reduce(loaded, Self.applying)), at: now())
            refreshState = refreshState.recordingSuccess()
        case .failure(let error) where error is CancellationError:
            state = state.withCancelledLoad()
        case .failure(let error):
            state = state.withFailure(error.localizedDescription)
            refreshState = refreshState.recordingFailure(error, at: now())
        }
        pendingEdits = []
    }
    private func apply(_ edit: Edit) {
        if inFlight != nil { pendingEdits.append(edit) }
        state = state.updatingValue { Self.sorted(Self.applying($0, edit)) }
    }
    private nonisolated static func applying(_ groups: [AdminGroup], _ edit: Edit) -> [AdminGroup] {
        switch edit {
        case .upsert(let group): groups.filter { $0.id != group.id } + [group]
        case .remove(let id): groups.filter { $0.id != id }
        }
    }
}
