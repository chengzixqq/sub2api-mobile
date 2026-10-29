import Foundation
import Sub2Core

/// The edit page's confirmations (30 §6.4).
enum UserEditDialog: Identifiable, Equatable {
    case leave(message: String)
    case promote(title: String, message: String)
    var id: String {
        switch self {
        case .leave: "leave"
        case .promote: "promote"
        }
    }
    var title: String {
        switch self {
        case .leave: UserEditCopy.leaveTitle
        case .promote(let title, _): title
        }
    }
    var message: String {
        switch self {
        case .leave(let message), .promote(_, let message): message
        }
    }
}

/// Checking (the administrator count, the step-up) or sending; the form is frozen either way.
enum UserSaveProgress: Equatable { case checking, sending }

/// R05: the number made at a confirmed save, sent again only for that same draft over that same base; after an unknown
/// result it is read back before anything else. It holds the password's bytes, so only in memory.
struct KeptUserUpdate {
    let operation: PendingUserUpdateOperation
    let draft: UserAccessDraft
    let baseline: UserBaseline
    let readsBackFirst: Bool
}

/// What one save sent, for its receipt and for moving the base.
private struct SentEdit {
    let draft: UserAccessDraft
    let baseline: UserBaseline
    let request: UserUpdateRequest?
    let changedCount: Int
    let lost: UserEditSaveReceipt.Lost?
}

/// 30 §6.4 保存 (S3-11): the check, the last-administrator check, the step-up and confirmation of a promotion, then the
/// submission (UserUpdateSubmission), whose number is made at that moment (R05).
extension UserEditorModel {
    /// Steps 1–4. Nothing is sent while an immediate write is out (S3D1-11).
    func save(model: AppModel, router: AppRouter) async {
        guard let baseline, canSave else { return }
        showsIssues = true
        let local = draft.issues(against: baseline, definitions: definitions)
        if let first = local.first {
            model.receipts.show(Receipt(text: UserAccessDraft.pendingIssuesMessage(local.count), systemImage: "exclamationmark.circle", tone: .caution))
            jump(to: first.field)
            return
        }
        saveProgress = .checking
        switch UserRoleChange(from: baseline.role, to: draft.role) {
        case .promote:
            await askToPromote(model: model)
        case .demote:
            if await allowsDemotion(model: model) { await submit(model: model, router: router) } else { saveProgress = nil }
        case .none, .other:
            await submit(model: model, router: router)
        }
    }
    /// The confirmation's “设为管理员并保存”: the number is made now.
    func confirmPromotion(model: AppModel, router: AppRouter) async {
        guard baseline != nil, saveProgress == nil else { return }
        saveProgress = .checking
        await submit(model: model, router: router)
    }

    /// U30: the server refuses the last administrator's demotion with a 500 without reason, so the count is read first. A
    /// failed count sends anyway and leaves it to the server.
    private func allowsDemotion(model: AppModel) async -> Bool {
        let generation = model.sessionGeneration, role = draft.role
        let total: Int
        do { total = try await model.adminCount() } catch { return generation == model.sessionGeneration && !isClosed }
        guard generation == model.sessionGeneration, !isClosed else { return false }
        guard UserRoleChange.blocksDemotion(adminTotal: total) else { return true }
        lastAdminRole = role
        jump(to: .role)
        model.receipts.show(Receipt(text: UserEditCopy.lastAdminReceipt, systemImage: "xmark.octagon", tone: .critical))
        return false
    }
    /// 30 §0.4 then step 3: the first sentence only when a code was asked for.
    private func askToPromote(model: AppModel) async {
        let verified = model.siteSession?.me.security.stepUpEnabled == true
        let resolution = await model.ensureStepUp(purpose: UserEditCopy.promotePurpose)
        saveProgress = nil
        guard !isClosed else { return }
        switch resolution {
        case .passed: dialog = promoteDialog(verified: verified)
        case .cancelled: break
        case .blocked(let text): model.receipts.show(Receipt(text: text, systemImage: "lock", tone: .caution))
        }
    }
    private func promoteDialog(verified: Bool) -> UserEditDialog {
        .promote(title: UserEditCopy.promoteTitle(name: editDisplayName), message: UserEditCopy.promoteMessage(changed: changedFields, verified: verified))
    }

    private func submit(model: AppModel, router: AppRouter) async {
        guard let id = editingUserID, let base = baseline else { saveProgress = nil; return }
        let sent = draft
        let kept = keptUpdate.flatMap { $0.draft == sent && $0.baseline == base ? $0 : nil }
        keptUpdate = kept
        if kept != nil, let holdUntil, Date() < holdUntil {
            saveProgress = nil
            model.receipts.show(Receipt(text: UserCreateFailure.storeUnavailable, systemImage: "clock", tone: .caution))
            return
        }
        let request = sent.updateRequest(from: base, catalog: catalog)
        let lost = UserEditSaveReceipt.lost(removedGroups: sent.removedExclusiveGroups(from: base, catalog: catalog), keys: boundKeys ?? []) { [catalog] id in
            catalog.exclusive.first { $0.id == id }?.name ?? "分组 #\(id)"
        }
        let edit = SentEdit(draft: sent, baseline: base, request: request, changedCount: changedFields.count, lost: lost)
        saveProgress = .sending
        let submission = UserUpdateSubmission(effects: model.userEditEffects(isPageAlive: { [weak self] in self?.isClosed == false }))
        let outcome = await submission.run(userID: id, request: request, attributes: sent.attributeChanges(from: base, definitions: definitions),
                                           reusing: kept?.operation, readsBackFirst: kept?.readsBackFirst == true)
        saveProgress = nil
        await finish(outcome, edit: edit, model: model, router: router)
    }
    private func finish(_ outcome: UserUpdateSubmission.Outcome, edit: SentEdit, model: AppModel, router: AppRouter) async {
        switch outcome {
        case .saved(let user, true):
            saved(user, edit: edit, model: model, router: router)
        case .saved(let user, false):
            attributesFailed(user, edit: edit, model: model)
        case .differs(let user, let failure):
            keptUpdate = nil
            stripUser = user
            model.userList?.replace(user)
            model.receipts.show(Receipt(text: failure?.receipt ?? UserEditCopy.readbackMismatch, systemImage: "exclamationmark.triangle", tone: .critical))
        case .undetermined:
            keptUpdate = nil
            model.receipts.show(Receipt(text: UserEditCopy.readbackUndetermined, systemImage: "exclamationmark.triangle", tone: .caution))
        case .unconfirmed(let operation):
            keptUpdate = KeptUserUpdate(operation: operation, draft: edit.draft, baseline: edit.baseline, readsBackFirst: true)
            model.receipts.show(Receipt(text: UserEditCopy.unconfirmed, systemImage: "exclamationmark.triangle", tone: .caution))
        case .failed(let failure, let operation):
            await refused(failure, operation: operation, edit: edit, model: model, router: router)
        case .stale:
            break
        }
    }
    /// Step 6: the receipt, the list's row, the detail reads again, and back to the page below.
    private func saved(_ user: AdminUser?, edit: SentEdit, model: AppModel, router: AppRouter) {
        guard let id = editingUserID else { return }
        keptUpdate = nil
        if let user { model.userList?.replace(user) }
        model.userChanges?.bump(userID: id)
        let text = UserEditSaveReceipt.text(changedCount: edit.changedCount, lost: edit.lost)
        model.receipts.show(edit.lost == nil ? Receipt(text: text, systemImage: "checkmark.circle", tone: .ok)
                                             : Receipt(text: text, systemImage: "clock.badge.exclamationmark", tone: .caution))
        close()
        let tab = router.selectedTab
        router.setPath(UserEditNavigation.closingEditor(router.path(for: tab), userID: id), for: tab)
    }
    /// Step 7: the profile is saved and the page stays with the attributes still marked as changed.
    private func attributesFailed(_ user: AdminUser?, edit: SentEdit, model: AppModel) {
        keptUpdate = nil
        guard let user, let id = editingUserID else {
            model.receipts.show(Receipt(text: UserEditCopy.attributesOnlyFailed, systemImage: "exclamationmark.triangle", tone: .critical))
            return
        }
        settleSaved(edit.request)
        stripUser = user
        model.userList?.replace(user)
        model.userChanges?.bump(userID: id)
        model.receipts.show(Receipt(text: UserEditCopy.attributesFailed, systemImage: "exclamationmark.triangle", tone: .caution))
    }
    /// 30 §6.5: the row marked, the receipt, the number kept or dropped; a cleared prompt confirms again with the same number.
    private func refused(_ failure: UserSaveFailure, operation: PendingUserUpdateOperation?, edit: SentEdit, model: AppModel,
                         router: AppRouter) async {
        keptUpdate = operation.map { KeptUserUpdate(operation: $0, draft: edit.draft, baseline: edit.baseline, readsBackFirst: false) }
        if case .storeUnavailable(let notBefore) = failure { holdUntil = notBefore }
        switch failure {
        case .emailTaken:
            serverMarks = UserServerMarks([UserDraftIssue(field: .email, message: UserEditCopy.emailTakenField)], sent: edit.draft)
            showsIssues = true
            jump(to: .email)
        case .notFound:
            if let id = editingUserID {
                model.userList?.remove(id: id)
                close()
                let tab = router.selectedTab
                router.setPath(UserEditNavigation.removingUserPages(router.path(for: tab), userID: id), for: tab)
            }
        case .reconfirm:
            guard !isClosed else { return }
            if UserRoleChange(from: edit.baseline.role, to: edit.draft.role) == .promote { dialog = promoteDialog(verified: true) }
            else {
                saveProgress = .checking
                await submit(model: model, router: router)
            }
            return
        default:
            break
        }
        guard let text = failure.receipt else { return }
        switch failure {
        case .security: model.receipts.show(Receipt(text: text, systemImage: "lock", tone: .caution))
        case .storeUnavailable: model.receipts.show(Receipt(text: text, systemImage: "clock", tone: .caution))
        default: model.receipts.show(Receipt(text: text, systemImage: "xmark.octagon", tone: .critical))
        }
    }
}
