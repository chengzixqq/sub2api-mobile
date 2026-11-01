import Foundation
import Sub2Core

/// 复制 and 删除 of GroupActions (50 §0.5); the entries and the shared running parts are in GroupActionsCore.swift.
extension GroupActions {
    // MARK: - 复制

    private struct Duplication: Sendable {
        let source: AdminGroup
        let operation: GroupWriteOperation
    }

    /// Called by `duplicate`; pages must not call it.
    func startDuplicate(_ group: AdminGroup, session: GroupWriteSession) async -> GroupActionOutcome {
        guard let identity = await identity(session),
              let operation = try? GroupWriteOperation.duplicate(sourceGroupID: group.id, serverID: session.serverID, identity: identity, id: makeKey())
        else { return .ignored }
        return await sendDuplicate(Duplication(source: group, operation: operation), session: session)
    }
    /// A recovered or replayed copy is a copy. There is nothing to read back, so a result that may have run reads the list and
    /// the directory again and offers the same number (S5D2a-06).
    private func sendDuplicate(_ duplication: Duplication, session: GroupWriteSession) async -> GroupActionOutcome {
        let store = self.store(), id = duplication.source.id
        do {
            let made = try await source.sendGroupDuplicate(duplication.operation).value
            guard isCurrent(session) else { return .ignored }
            store?.upsert(made)
            store?.refreshAfterWrite(directory: true)
            show(GroupActionCopy.duplicated(newName: made.name, memberCount: made.accountCount ?? 0)) { self.openGroup(made.id) }
            return .succeeded
        } catch {
            guard isCurrent(session) else { return .ignored }
            switch GroupWriteDisposition.of(error) {
            case .cancelled: return .ignored
            case .gone: return gone(id, kind: .duplicate, store: store)
            case .rejected(let reason):
                show(GroupActionCopy.failed(.duplicate, reason: reason))
                return .failed
            case .reconfirm:
                show(GroupActionCopy.reconfirm(.duplicate)) {
                    self.relaunch(id, session) { await $0.startDuplicate(duplication.source, session: session) }
                }
                return .reconfirm
            case .unconfirmed(let notBefore):
                store?.refreshAfterWrite(directory: true)
                show(notBefore == nil ? GroupActionCopy.duplicateUnconfirmed : GroupActionCopy.storeUnavailable(.duplicate)) {
                    self.relaunch(id, session, notBefore: notBefore) { await $0.sendDuplicate(duplication, session: session) }
                }
                return .unconfirmed
            }
        }
    }

    // MARK: - 删除

    private struct Deletion: Sendable {
        let group: AdminGroup
        let operation: GroupWriteOperation
    }

    /// Called by `performDelete`; pages must not call it.
    func startDelete(_ group: AdminGroup, session: GroupWriteSession) async -> GroupActionOutcome {
        guard let identity = await identity(session),
              let operation = try? GroupWriteOperation.delete(groupID: group.id, serverID: session.serverID, identity: identity,
                                                              sendsIdempotencyKey: session.idempotentWrites, id: makeKey())
        else { return .ignored }
        return await sendDelete(Deletion(group: group, operation: operation), session: session)
    }
    /// Deleted and already gone end alike (Core maps 404); 409 GROUP_NOT_EMPTY keeps the group.
    private func sendDelete(_ deletion: Deletion, session: GroupWriteSession) async -> GroupActionOutcome {
        do {
            _ = try await source.sendGroupDelete(deletion.operation)
            guard isCurrent(session) else { return .ignored }
            return deleted(deletion.group)
        } catch {
            guard isCurrent(session) else { return .ignored }
            switch GroupWriteDisposition.of(error) {
            case .cancelled: return .ignored
            case .gone: return deleted(deletion.group)
            case .rejected(let reason):
                show(GroupActionCopy.failed(.delete, reason: reason))
                return .failed
            case .reconfirm:
                show(GroupActionCopy.reconfirm(.delete)) { Task { await self.requestDelete(deletion.group) } }
                return .reconfirm
            case .unconfirmed(let notBefore): return await verifyDelete(deletion, notBefore: notBefore, session: session)
            }
        }
    }
    /// 50 §0.5: out of the list and the group directory, both read again.
    private func deleted(_ group: AdminGroup) -> GroupActionOutcome {
        let store = self.store()
        store?.remove(id: group.id)
        store?.refreshAfterWrite(directory: true)
        receipts.show(Receipt(text: DeleteConfirmationCopy.deletedReceipt(objectNoun: GroupCopy.objectNoun, displayName: group.name),
                              systemImage: "trash"))
        return .succeeded
    }
    /// 404 on the read-back is deleted; a group still there offers the same number, or without keys a new request id.
    private func verifyDelete(_ deletion: Deletion, notBefore: Date?, session: GroupWriteSession) async -> GroupActionOutcome {
        let id = deletion.group.id
        switch await readBack(id, session: session) {
        case nil: return .ignored
        case .success(let fresh)?:
            store()?.upsert(fresh)
            guard deletion.operation.sendsIdempotencyKey else {
                show(GroupActionCopy.notApplied(.delete)) { self.relaunch(id, session) { await $0.startDelete(fresh, session: session) } }
                return .notApplied
            }
            show(notBefore == nil ? GroupActionCopy.unconfirmedRetry(.delete) : GroupActionCopy.storeUnavailable(.delete)) {
                self.relaunch(id, session, notBefore: notBefore) { await $0.sendDelete(deletion, session: session) }
            }
            return .unconfirmed
        case .failure(let error)?:
            switch GroupWriteDisposition.of(error) {
            case .gone: return deleted(deletion.group)
            case .cancelled: return .ignored
            default:
                store()?.refreshAfterWrite(directory: true)
                show(GroupActionCopy.checkFailed(.delete)) {
                    self.relaunch(id, session) { await $0.verifyDelete(deletion, notBefore: notBefore, session: session) }
                }
                return .unconfirmed
            }
        }
    }
}
