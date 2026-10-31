import Foundation
import Observation
import Sub2Core

/// The group a replace starts from: the key segment's row or the group sheet's “改用替换分组”.
struct ReplaceGroupSource: Identifiable, Hashable {
    let groupID: Int
    var id: Int { groupID }
}

/// What “确认替换” froze (R05): the number, the bytes and what the page knew then. The edit page keeps it until the result is
/// known (UserEditorModel.frozenReplace): a closed sheet or another target never sends a new number first (00 §2.5.4).
struct ReplaceGroupFrozen: Sendable {
    let key: UUID
    let request: ReplaceGroupRequest
    let before: ReplaceGroupSnapshot
}

/// One replace's 撤销, kept by its receipt (30 §8.4): the plan, the grant change to put back and the name the page lists.
struct ReplaceGroupUndoRun: Sendable {
    let plan: ReplaceGroupUndo
    let change: UserGroupsChange
    let name: String
    let userID: Int
    let generation: UUID
}

/// 30 §8.4 替换分组 (S3-15): confirm, send once with a number made at “确认替换” (R05; the executor resends the same bytes, R04),
/// then move the base, the draft and the cards and offer 撤销. A result nobody saw is read back from the user and the keys;
/// still unknown, the page keeps the number: the same target sends it again, any other replace of the user waits for a read
/// back that settles it (00 §2.5.4). The send and its read back hold the page's write gate (S3D1-11).
@MainActor @Observable
final class ReplaceGroupFlow {
    enum Phase: Equatable { case idle, sending, readingBack }

    let sourceGroupID: Int
    let userID: Int
    private(set) var phase = Phase.idle
    private(set) var target: Int?
    var asksConfirmation = false
    /// The sheet's red line: a refusal, a result nobody could confirm, or “保存” being out.
    private(set) var error: String?
    /// The replace went through (or the user is gone): the sheet closes.
    private(set) var finished = false

    @ObservationIgnored private weak var editor: UserEditorModel?
    @ObservationIgnored private weak var keys: UserKeysModel?

    /// A replace of this group still unknown comes back with its target and the red line.
    init(sourceGroupID: Int, editor: UserEditorModel, keys: UserKeysModel) {
        self.sourceGroupID = sourceGroupID; userID = keys.userID; self.editor = editor; self.keys = keys
        if let held = editor.frozenReplace, held.request.oldGroupID == sourceGroupID {
            target = held.request.newGroupID
            error = ReplaceGroupCopy.unconfirmed
        }
    }

    var isBusy: Bool { phase != .idle }
    func select(_ id: Int) {
        guard !isBusy else { return }
        target = id
        error = nil
    }
    func askConfirmation() { if target != nil, !isBusy { asksConfirmation = true } }

    /// The confirmation's “确认替换”.
    func confirm(model: AppModel) async {
        guard !isBusy, let target, let editor, let keys, let baseline = editor.baseline else { return }
        guard editor.beginImmediateWrite() else { error = UserEditCopy.immediateBlockedBySave; return }
        defer { editor.endImmediateWrite() }
        error = nil
        if let held = editor.frozenReplace, held.request.oldGroupID != sourceGroupID || held.request.newGroupID != target {
            guard await settle(held, model: model) else { return }
        }
        if editor.frozenReplace == nil {
            guard let request = try? ReplaceGroupRequest(oldGroupID: sourceGroupID, newGroupID: target) else { return }
            let before = ReplaceGroupSnapshot(allowedGroups: baseline.allowedGroups, keys: keys.keys, source: sourceGroupID, target: target)
            editor.frozenReplace = ReplaceGroupFrozen(key: UUID(), request: request, before: before)
        }
        guard let send = editor.frozenReplace else { return }
        phase = .sending
        let generation = model.sessionGeneration
        do {
            let outcome = try await model.replaceUserGroup(userID: userID, send.request, idempotencyKey: send.key)
            guard generation == model.sessionGeneration else { return }
            finish(outcome.value, sent: send, readBack: false, model: model)
        } catch {
            guard generation == model.sessionGeneration else { return }
            await fail(error, sent: send, model: model)
        }
    }

    // MARK: - 成功

    /// The base and the draft take the new group in any case (30 §8.4); the undo puts back only what the replace changed.
    private func finish(_ result: ReplaceGroupResult, sent frozen: ReplaceGroupFrozen, readBack: Bool, model: AppModel) {
        let (sent, before) = (frozen.request, frozen.before)
        let groups = model.groupDirectory?.groups ?? []
        let change = ReplaceGroupUndo.groupsChange(sent: sent, newlyGranted: result.newlyGranted(target: sent.newGroupID, before: before))
        let name = ReplaceGroupCopy.appliedName(source: UserKeyPresentation.groupName(sent.oldGroupID, groups: groups),
                                                target: UserKeyPresentation.groupName(sent.newGroupID, groups: groups))
        editor?.frozenReplace = nil
        editor?.applyImmediate(name, groupsChange: ReplaceGroupUndo.baseChange(sent: sent))
        Self.move(result.movedKeyIDs(before: before), to: sent.newGroupID, in: keys)
        model.userChanges?.bump(userID: userID)
        var undo: (@MainActor @Sendable () -> Void)?
        if let plan = ReplaceGroupUndo.plan(sent, result: result, before: before) {
            let run = ReplaceGroupUndoRun(plan: plan, change: change, name: name, userID: userID, generation: model.sessionGeneration)
            undo = { [model, weak editor = self.editor, weak keys = self.keys] in
                Task { await ReplaceGroupFlow.undo(run, model: model, editor: editor, keys: keys) }
            }
        }
        let text = readBack ? ReplaceGroupCopy.readbackApplied : ReplaceGroupCopy.receipt(migrated: result.migratedKeys)
        model.receipts.show(Receipt(text: text, systemImage: "arrow.triangle.swap", undo: undo))
        phase = .idle
        finished = true
        if let keys { Task { await keys.refreshAll() } }
    }

    // MARK: - 失败与读回

    private func fail(_ error: any Error, sent: ReplaceGroupFrozen, model: AppModel) async {
        guard let failure = ReplaceGroupFailure(error, phase: .replace) else { phase = .idle; return }
        if failure == .unconfirmed { return await readBack(sent, model: model) }
        editor?.frozenReplace = nil
        switch failure {
        case .pickAgain, .groupMissing:
            await model.groupDirectory?.refresh()
        case .userGone:
            editor?.editLoad = .missing
            model.userList?.remove(id: userID)
            model.receipts.show(Receipt(text: failure.message, systemImage: "person.crop.circle.badge.xmark", tone: .critical))
            finished = true
        default:
            break
        }
        self.error = failure.message
        phase = .idle
    }
    /// The executor gave up (R04): read back once; still unknown, the number stays with the page.
    private func readBack(_ sent: ReplaceGroupFrozen, model: AppModel) async {
        let generation = model.sessionGeneration
        let outcome = await check(sent, model: model)
        guard generation == model.sessionGeneration else { return }
        if case .applied(let result)? = outcome { return finish(result, sent: sent, readBack: true, model: model) }
        stillUnknown(outcome)
    }
    /// 00 §2.5.4: a replace of this user nobody saw the end of is read back before another goes out. true when it did not go
    /// through, so the new one follows; gone through, it finishes as read back and nothing new is sent.
    private func settle(_ held: ReplaceGroupFrozen, model: AppModel) async -> Bool {
        let generation = model.sessionGeneration
        let outcome = await check(held, model: model)
        guard generation == model.sessionGeneration else { return false }
        switch outcome {
        case .notApplied?:
            editor?.frozenReplace = nil
            return true
        case .applied(let result)?:
            finish(result, sent: held, readBack: true, model: model)
        default:
            stillUnknown(outcome)
        }
        return false
    }
    /// The server runs a replace in one transaction: the old group gone and the new one there means it went through. nil when
    /// the user or the keys could not be read; without E04 the result is made like an older reply (§0.6).
    private func check(_ sent: ReplaceGroupFrozen, model: AppModel) async -> ReplaceGroupReadback? {
        phase = .readingBack
        guard let read = try? await model.replaceGroupReadBack(userID: userID) else { return nil }
        return ReplaceGroupReadback.outcome(sent.request, before: sent.before, user: read.user, keys: read.keys,
                                            exactUndoSupported: model.userKeysContext?.adminKeyWrites == true)
    }
    private func stillUnknown(_ outcome: ReplaceGroupReadback?) {
        if outcome == .unclear, let keys { Task { await keys.refreshAll() } }
        error = ReplaceGroupCopy.unconfirmed
        phase = .idle
    }

    // MARK: - 撤销（30 §8.4）

    /// The receipt's 撤销, after the page has gone too (then without the gate). A reverse with exactly the moved keys, or the
    /// fresh allowed_groups through the one grant writer (S3D1-10); success shows nothing more.
    static func undo(_ run: ReplaceGroupUndoRun, model: AppModel, editor: UserEditorModel?, keys: UserKeysModel?) async {
        guard model.sessionGeneration == run.generation else { return }
        if let editor, !editor.beginImmediateWrite() {
            model.receipts.show(Receipt(text: UserEditCopy.immediateBlockedBySave, systemImage: "clock", tone: .caution))
            return
        }
        defer { editor?.endImmediateWrite() }
        do {
            switch run.plan {
            case .reverse(let request):
                _ = try await model.replaceUserGroup(userID: run.userID, request, idempotencyKey: UUID())
                guard model.sessionGeneration == run.generation else { return }
                move(request.keyIDs ?? [], to: request.newGroupID, in: keys)
            case .restoreAllowedGroups(let restoring, let revoking):
                let user = try await model.user(id: run.userID)
                guard model.sessionGeneration == run.generation else { return }
                if let list = ReplaceGroupUndo.allowedGroups(current: user.allowedGroups, restoring: restoring, revoking: revoking) {
                    _ = try await model.updateUserGroups(userID: run.userID, allowedGroups: list, restrictPublicGroups: user.restrictPublicGroups ?? false)
                    guard model.sessionGeneration == run.generation else { return }
                }
            }
            editor?.undoImmediate(run.name, groupsChange: run.change)
            model.userChanges?.bump(userID: run.userID)
            await keys?.refreshAll()
        } catch {
            guard model.sessionGeneration == run.generation, let failure = ReplaceGroupFailure(error, phase: .undo) else { return }
            await settleUndo(failure, run: run, model: model, editor: editor, keys: keys)
        }
    }
    private static func settleUndo(_ failure: ReplaceGroupFailure, run: ReplaceGroupUndoRun, model: AppModel, editor: UserEditorModel?,
                                   keys: UserKeysModel?) async {
        model.receipts.show(Receipt(text: failure.undoReceipt, systemImage: "exclamationmark.triangle", tone: failure == .unconfirmed ? .caution : .critical))
        switch failure {
        case .groupMissing, .pickAgain:
            await model.groupDirectory?.refresh()
        case .userGone:
            editor?.editLoad = .missing
            model.userList?.remove(id: run.userID)
        case .keysMoved, .unconfirmed:
            model.userChanges?.bump(userID: run.userID)
            await keys?.refreshAll()
        default:
            break
        }
    }
    /// The cards before the list is read again.
    private static func move(_ ids: [Int], to groupID: Int, in keys: UserKeysModel?) {
        guard let keys else { return }
        for key in keys.keys where ids.contains(key.id) { keys.replace(key.movedToGroup(groupID)) }
    }
}
