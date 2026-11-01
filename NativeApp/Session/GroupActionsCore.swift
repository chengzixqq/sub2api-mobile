import Foundation
import Observation
import Sub2Core

/// What a group action reads of the session at the user's tap; a result that arrives for another session is dropped.
struct GroupWriteSession: Sendable, Equatable {
    let generation: UUID
    let serverID: UUID
    let siteName: String
    /// admin.idempotent_writes: 停用 / 启用 / 删除 carry an Idempotency-Key; 复制 always does (the server requires one).
    let idempotentWrites: Bool
    let isReadOnlyToken: Bool
    /// GroupPermissions.showsStats: groups/:id/stats is refused for a vendor and in simple mode.
    let readsStats: Bool
    let isSimpleMode: Bool
}

/// The group reads and writes the actions use (AppGroupActionSource). A write refuses an operation made for another site or
/// session, as APIClient does.
@MainActor protocol GroupActionSource: AnyObject {
    var groupWriteSession: GroupWriteSession? { get }
    /// APIClient.userWriteIdentity(); CancellationError without a session.
    func groupWriteIdentity() async throws -> UUID
    func fetchGroupStats(id: Int) async throws -> GroupStats?
    func fetchGroup(id: Int) async throws -> AdminGroup
    func sendGroupUpdate(_ operation: GroupWriteOperation, request: GroupUpdateRequest) async throws -> WriteOutcome<AdminGroup>
    func sendGroupDelete(_ operation: GroupWriteOperation) async throws -> WriteOutcome<GroupDeleteResult>
    func sendGroupDuplicate(_ operation: GroupWriteOperation) async throws -> WriteOutcome<AdminGroup>
}

/// The session's GroupStore as the actions write it.
@MainActor protocol GroupActionStore: AnyObject {
    /// Only the list; returns the row before, for `rollback`.
    @discardableResult func applyOptimistic(_ group: AdminGroup) -> AdminGroup?
    func rollback(_ previous: AdminGroup)
    /// The list and the group directory.
    func upsert(_ group: AdminGroup)
    func remove(id: Int)
    /// 50 §1.6: the list's three requests again in the background, and after a copy or a delete the group directory too.
    func refreshAfterWrite(directory: Bool)
}

/// 停用分组…'s confirmation; N was read when it opened (50 §0.5).
struct GroupDisablePrompt: Identifiable, Equatable, Sendable {
    let id: UUID
    let group: AdminGroup
    let confirmation: GroupConfirmation
    let generation: UUID
}

/// 删除分组…: the consequence lines read when it opened; the host turns it into a DeleteRequest.
struct GroupDeletePrompt: Identifiable, Equatable, Sendable {
    let id: UUID
    let group: AdminGroup
    let siteName: String
    let consequences: [String]
    let generation: UUID
}

enum GroupActionOutcome: Equatable, Sendable { case succeeded, notApplied, unconfirmed, reconfirm, gone, failed, ignored }

/// 50 §0.5: 停用 / 启用 / 复制 / 删除 of the list's swipes and long press and the detail's ⋯ and button row. Pages call only
/// `requestDisable`, `enable`, `duplicate` and `requestDelete`; `groupActionsHost` draws the two confirmations and calls
/// `confirmDisable` / `performDelete` (S5D2a-05). A number is made at the last confirmation (R05) and kept through its retries;
/// a result that may have run is read back once and never sent again on its own (S5D2a-06). Each ends in one receipt.
@MainActor @Observable
final class GroupActions {
    /// 50 §0.5 reads N when the confirmation opens; past this wait the number is left out.
    nonisolated static let statsWait: Duration = .seconds(2)
    /// Groups with an action running or a confirmation's stats being read; another tap on them is ignored.
    private(set) var inFlight: Set<Int> = []
    var disablePrompt: GroupDisablePrompt?
    var deletePrompt: GroupDeletePrompt?
    @ObservationIgnored let source: any GroupActionSource
    /// The session's store, looked up at each write.
    @ObservationIgnored let store: @MainActor () -> (any GroupActionStore)?
    @ObservationIgnored let receipts: ReceiptCenter
    @ObservationIgnored let openGroup: @MainActor (Int) -> Void
    @ObservationIgnored let makeKey: @MainActor () -> UUID
    /// Holds a same-number retry until the device time KeyedWriteFlow gave (00 §2.5.3).
    @ObservationIgnored private let waitUntil: @MainActor (Date) async throws -> Void
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let statsWait: Duration

    init(source: any GroupActionSource, store: @escaping @MainActor () -> (any GroupActionStore)?, receipts: ReceiptCenter,
         openGroup: @escaping @MainActor (Int) -> Void, makeKey: @escaping @MainActor () -> UUID = { UUID() },
         waitUntil: @escaping @MainActor (Date) async throws -> Void = AccountActions.sleep(until:),
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         statsWait: Duration = GroupActions.statsWait) {
        self.source = source; self.store = store; self.receipts = receipts; self.openGroup = openGroup; self.makeKey = makeKey
        self.waitUntil = waitUntil; self.sleep = sleep; self.statsWait = statsWait
    }

    func isRunning(_ groupID: Int) -> Bool { inFlight.contains(groupID) }

    // MARK: - Entries

    /// 停用分组…: reads N (at most `statsWait`), then asks. No number yet.
    func requestDisable(_ group: AdminGroup) async {
        _ = await run(group.id) { session in
            let stats = await statsWithin(group.id, session: session)
            guard isCurrent(session) else { return .ignored }
            let confirmation = GroupCopy.disableConfirmation(name: group.name, siteName: session.siteName, activeAPIKeys: stats?.activeAPIKeys)
            disablePrompt = GroupDisablePrompt(id: UUID(), group: group, confirmation: confirmation, generation: session.generation)
            return .succeeded
        }
    }
    /// 启用分组: not confirmed (it can be undone); the number is made at the tap.
    @discardableResult func enable(_ group: AdminGroup) async -> GroupActionOutcome {
        await run(group.id) { await startStatus(group, target: "active", isUndo: false, session: $0) }
    }
    /// 复制分组: not confirmed; always keyed.
    @discardableResult func duplicate(_ group: AdminGroup) async -> GroupActionOutcome {
        await run(group.id) { await startDuplicate(group, session: $0) }
    }
    /// 删除分组…: reads the consequences the same way (S5D2a-03), then asks. No number yet.
    func requestDelete(_ group: AdminGroup) async {
        _ = await run(group.id) { session in
            let stats = await statsWithin(group.id, session: session)
            guard isCurrent(session) else { return .ignored }
            let lines = GroupCopy.deleteConsequences(stats: stats, group: group, isSimpleMode: session.isSimpleMode)
            deletePrompt = GroupDeletePrompt(id: UUID(), group: group, siteName: session.siteName, consequences: lines, generation: session.generation)
            return .succeeded
        }
    }
    /// The alert's 停用分组; pages must not call it. The number is made now (R05).
    @discardableResult func confirmDisable(_ prompt: GroupDisablePrompt) async -> GroupActionOutcome {
        if disablePrompt?.id == prompt.id { disablePrompt = nil }
        return await run(prompt.group.id, generation: prompt.generation) {
            await startStatus(prompt.group, target: "inactive", isUndo: false, session: $0)
        }
    }
    /// DeleteRequest.perform, after the typed name or Face ID; pages must not call it. `leaving` runs first (the detail pops,
    /// the list passes nil), then the number is made and the DELETE goes out.
    @discardableResult func performDelete(_ prompt: GroupDeletePrompt, leaving: (@MainActor () -> Void)?) async -> GroupActionOutcome {
        if deletePrompt?.id == prompt.id { deletePrompt = nil }
        return await run(prompt.group.id, generation: prompt.generation) { session in
            leaving?()
            return await startDelete(prompt.group, session: session, pageStays: leaving == nil)
        }
    }

    // MARK: - Running

    /// Nothing without a session, for another session's prompt, or while the group is busy; a read-only token gets the catalog's
    /// words and sends nothing (00 §2.6.3).
    private func run(_ id: Int, generation: UUID? = nil, _ body: (GroupWriteSession) async -> GroupActionOutcome) async -> GroupActionOutcome {
        guard !inFlight.contains(id), let session = source.groupWriteSession, generation.map({ $0 == session.generation }) ?? true else {
            return .ignored
        }
        guard !session.isReadOnlyToken else { show(GroupActionCopy.readOnly); return .failed }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        return await body(session)
    }
    /// A receipt's button: only in the session the receipt belongs to and not before `notBefore`, the group busy meanwhile.
    /// The receipt holds these actions, so its button still works after the page that made them has closed.
    func relaunch(_ id: Int, _ session: GroupWriteSession, notBefore: Date? = nil,
                  _ body: @escaping @MainActor @Sendable (GroupActions) async -> GroupActionOutcome) {
        guard !inFlight.contains(id), isCurrent(session) else { return }
        inFlight.insert(id)
        Task {
            defer { self.inFlight.remove(id) }
            if let notBefore { do { try await self.waitUntil(notBefore) } catch { return } }
            guard self.isCurrent(session) else { return }
            _ = await body(self)
        }
    }
    func isCurrent(_ session: GroupWriteSession) -> Bool { source.groupWriteSession?.generation == session.generation }
    /// The identity a new operation carries; nil once the session changed.
    func identity(_ session: GroupWriteSession) async -> UUID? {
        guard let identity = try? await source.groupWriteIdentity(), isCurrent(session) else { return nil }
        return identity
    }
    /// At most `statsWait`: a failure, a slow read and an older server (nil) all leave the numbers out.
    private func statsWithin(_ id: Int, session: GroupWriteSession) async -> GroupStats? {
        guard session.readsStats else { return nil }
        let sleep = self.sleep, wait = statsWait
        return await withTaskGroup(of: GroupStats?.self) { group in
            group.addTask { await self.readStats(id) }
            group.addTask { try? await sleep(wait); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
    private func readStats(_ id: Int) async -> GroupStats? { try? await source.fetchGroupStats(id: id) }
    /// nil when the session changed meanwhile.
    func readBack(_ id: Int, session: GroupWriteSession) async -> Result<AdminGroup, any Error>? {
        do {
            let fresh = try await source.fetchGroup(id: id)
            return isCurrent(session) ? .success(fresh) : nil
        } catch {
            return isCurrent(session) ? .failure(error) : nil
        }
    }
    /// 50 §0.8: the group was deleted meanwhile; it leaves the list and the directory.
    func gone(_ id: Int, kind: GroupActionKind, store: (any GroupActionStore)?) -> GroupActionOutcome {
        store?.remove(id: id)
        show(GroupActionCopy.failed(kind, reason: GroupErrorCopy.deleted))
        return .gone
    }
    func show(_ copy: GroupReceiptCopy, action: (@MainActor @Sendable () -> Void)? = nil) {
        let button = copy.button.flatMap { kind in action.map { ReceiptAction(title: kind.title, perform: $0) } }
        receipts.show(Receipt(text: copy.text, systemImage: copy.systemImage, tone: copy.tone, action: button))
    }

    // MARK: - 停用 / 启用

    /// One status write: a retry keeps its operation (number and bytes); an undo or a plain retry is a new one.
    private struct StatusChange: Sendable {
        /// The group as it was before this write.
        let group: AdminGroup
        let target: String
        let isUndo: Bool
        let operation: GroupWriteOperation
        var kind: GroupActionKind { isUndo ? .undo : target == "active" ? .enable : .disable }
        var request: GroupUpdateRequest { GroupUpdateRequest(status: target) }
    }

    private func startStatus(_ group: AdminGroup, target: String, isUndo: Bool, session: GroupWriteSession) async -> GroupActionOutcome {
        guard let identity = await identity(session),
              let operation = try? GroupWriteOperation.update(groupID: group.id, GroupUpdateRequest(status: target), serverID: session.serverID,
                                                              identity: identity, sendsIdempotencyKey: session.idempotentWrites, id: makeKey())
        else { return .ignored }
        return await sendStatus(StatusChange(group: group, target: target, isUndo: isUndo, operation: operation), session: session)
    }
    /// The row changes first (50 §0.5) and goes back unless the server took the write or may have.
    private func sendStatus(_ change: StatusChange, session: GroupWriteSession) async -> GroupActionOutcome {
        let store = self.store()
        var shown = change.group
        shown.status = change.target
        let previous = store?.applyOptimistic(shown) ?? change.group
        do {
            let reply = try await source.sendGroupUpdate(change.operation, request: change.request).value
            guard isCurrent(session) else { store?.rollback(previous); return .ignored }
            return statusWritten(reply, change, store: store, session: session)
        } catch {
            guard isCurrent(session) else { store?.rollback(previous); return .ignored }
            switch GroupWriteDisposition.of(error) {
            case .cancelled: store?.rollback(previous); return .ignored
            case .gone: return gone(change.group.id, kind: change.kind, store: store)
            case .rejected(let reason):
                store?.rollback(previous)
                show(GroupActionCopy.failed(change.kind, reason: reason))
                return .failed
            case .reconfirm:
                store?.rollback(previous)
                show(GroupActionCopy.reconfirm(change.kind), action: actAgain(change, session))
                return .reconfirm
            case .unconfirmed(let notBefore): return await verifyStatus(change, previous: previous, notBefore: notBefore, session: session)
            }
        }
    }
    /// The server's group, which may come back unchanged (simple mode, a vendor without group_ops); an undo that went through
    /// says nothing more, the row shows it.
    private func statusWritten(_ group: AdminGroup, _ change: StatusChange, store: (any GroupActionStore)?,
                               session: GroupWriteSession) -> GroupActionOutcome {
        store?.upsert(group)
        store?.refreshAfterWrite(directory: false)
        guard group.status == change.target else { show(GroupActionCopy.notAccepted(change.kind)); return .notApplied }
        guard !change.isUndo else { return .succeeded }
        let back = change.group.status
        show(GroupActionCopy.statusChanged(name: group.name, active: change.target == "active")) {
            self.relaunch(group.id, session) { await $0.startStatus(group, target: back, isUndo: true, session: session) }
        }
        return .succeeded
    }
    /// Done when `status` reads the target; 404 is gone; a failed read offers 核对, which reads once more and sends nothing.
    private func verifyStatus(_ change: StatusChange, previous: AdminGroup, notBefore: Date?, session: GroupWriteSession) async -> GroupActionOutcome {
        let store = self.store(), id = change.group.id
        switch await readBack(id, session: session) {
        case nil:
            store?.rollback(previous)
            return .ignored
        case .success(let fresh)?:
            if fresh.status == change.target { return statusWritten(fresh, change, store: store, session: session) }
            store?.upsert(fresh)
            return notConfirmed(change, notBefore: notBefore, session: session)
        case .failure(let error)?:
            switch GroupWriteDisposition.of(error) {
            case .gone: return gone(id, kind: change.kind, store: store)
            case .cancelled: store?.rollback(previous); return .ignored
            default:
                store?.rollback(previous)
                store?.refreshAfterWrite(directory: false)
                show(GroupActionCopy.checkFailed(change.kind)) {
                    self.relaunch(id, session) { await $0.verifyStatus(change, previous: previous, notBefore: notBefore, session: session) }
                }
                return .unconfirmed
            }
        }
    }
    /// The read-back shows the write did not happen: a keyed one goes again under its number, not before the cooldown of 503
    /// IDEMPOTENCY_STORE_UNAVAILABLE (00 §2.5.3); an unkeyed one under a new request id (00 §2.4), as `actAgain` sends it.
    private func notConfirmed(_ change: StatusChange, notBefore: Date?, session: GroupWriteSession) -> GroupActionOutcome {
        guard change.operation.sendsIdempotencyKey else {
            show(GroupActionCopy.notApplied(change.kind), action: actAgain(change, session))
            return .notApplied
        }
        show(notBefore == nil ? GroupActionCopy.unconfirmedRetry(change.kind) : GroupActionCopy.storeUnavailable(change.kind)) {
            self.relaunch(change.group.id, session, notBefore: notBefore) { await $0.sendStatus(change, session: session) }
        }
        return .unconfirmed
    }
    /// A new number for what ran nothing (KEY_CONFLICT and the like, or an unkeyed write the read-back shows): 停用 asks again,
    /// since the number is made at its confirmation (R05); 启用 and 撤销 go at once.
    private func actAgain(_ change: StatusChange, _ session: GroupWriteSession) -> @MainActor @Sendable () -> Void {
        guard change.kind != .disable else { return { Task { await self.requestDisable(change.group) } } }
        return {
            self.relaunch(change.group.id, session) { await $0.startStatus(change.group, target: change.target, isUndo: change.isUndo, session: session) }
        }
    }
}
