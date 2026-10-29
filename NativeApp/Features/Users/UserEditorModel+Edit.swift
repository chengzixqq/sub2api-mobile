import Foundation
import Sub2Core

/// 30 §6 (S3-11): the edit state's reads, its marks and leaving. Stored state is in UserEditorModel.swift; saving is in
/// UserEditorModel+Save.swift.
extension UserEditorModel {
    var isEditing: Bool { editingUserID != nil }
    var editingUserID: Int? { if case .edit(let id) = mode { id } else { nil } }
    /// Form order (UserAccessDraft.changedFields); the attributes count once their values are in.
    var changedFields: [UserDraftField] {
        baseline.map { draft.changedFields(from: $0, catalog: catalog, definitions: definitions) } ?? []
    }
    var hasUnsavedChanges: Bool { !changedFields.isEmpty }
    var isSaving: Bool { saveProgress != nil }
    /// S3D1-11: never while an immediate write is out.
    var canSave: Bool {
        UserEditPolicy.canSave(hasChanges: hasUnsavedChanges, saving: isSaving, immediateInFlight: immediateWritesInFlight)
    }
    var segmentMarks: [UserEditSegmentMark] { UserEditSegmentMark.marks(changed: changedFields, issues: issues, showsIssues: showsIssues) }
    var statusLine: String { UserEditStatusLine.text(segmentMarks) }
    /// The third segment's “（N）”: every key the user has, deleted ones aside; nil while unknown.
    var keyCount: Int? { boundKeys?.filter { !$0.isTombstone }.count }
    func boundKeyCount(groupID: Int) -> Int { UserEditSaveReceipt.boundKeyCount(groupID: groupID, keys: boundKeys ?? []) }
    var editDisplayName: String { stripUser?.displayName ?? "" }
    /// The role the page opened with: an administrator cannot be disabled or deleted (U30).
    var isOriginalAdmin: Bool { baseline?.role == .admin }
    var addedExclusiveGroups: Set<Int> { baseline.map { draft.addedExclusiveGroups(from: $0, catalog: catalog) } ?? [] }
    var removedExclusiveGroups: Set<Int> { baseline.map { draft.removedExclusiveGroups(from: $0, catalog: catalog) } ?? [] }
    /// The exclusive section's “已改 N 项”: added, removed, and rate changes of the kept ones.
    var exclusiveChangeCount: Int {
        guard let baseline else { return 0 }
        let removed = removedExclusiveGroups
        let rates = draft.groupRateChanges(from: baseline, catalog: catalog).keys.filter { catalog.exclusiveIDs.contains($0) && !removed.contains($0) }
        return addedExclusiveGroups.count + removed.count + rates.count
    }

    // MARK: - 读取（30 §6.2）

    /// The profile and the group directory together; the base is made once (30 §6.6). Keys and attributes load on their own.
    func loadForEdit(model: AppModel) async {
        guard let id = editingUserID, baseline == nil else { return }
        let generation = model.sessionGeneration
        editLoad = .loading
        if entryBalanceRevision == nil { entryBalanceRevision = model.userChanges?.balanceRevision(userID: id) ?? 0 }
        async let groups: Void = ensureGroups(model)
        let result: Result<AdminUser, any Error>
        do { result = .success(try await model.user(id: id)) } catch { result = .failure(error) }
        await groups
        guard generation == model.sessionGeneration, !isClosed else { return }
        switch result {
        case .success(let user):
            stripUser = user
            isSelf = UserDetailPresentation.isSelf(user, meID: model.currentAdminUserID)
            startEditing(user, catalog: UserGroupCatalog(groups: model.groupDirectory?.groups ?? []))
            editLoad = .loaded
        case .failure(let error):
            settleLoadFailure(error, userID: id, model: model)
        }
    }
    /// The identity strip only (a balance write, a pull): the base and the draft stay (30 §6.6).
    func reloadStrip(model: AppModel) async {
        guard let id = editingUserID, editLoad == .loaded else { return }
        let generation = model.sessionGeneration
        do {
            let user = try await model.user(id: id)
            guard generation == model.sessionGeneration else { return }
            stripUser = user
            model.userList?.replace(user)
        } catch {
            guard generation == model.sessionGeneration, (error as? APIError)?.isUserNotFound == true else { return }
            settleLoadFailure(error, userID: id, model: model)
        }
    }

    // MARK: - 离开（30 §6.4）

    /// What already took effect: the immediate writes, and “余额” once a balance write succeeded since the page opened.
    func appliedForLeave(balanceRevision: Int) -> [String] {
        applied + (balanceRevision > (entryBalanceRevision ?? balanceRevision) ? [UserEditCopy.appliedBalance] : [])
    }
    /// true: nothing unsaved, leave at once. Otherwise the confirmation opens.
    func requestLeave(balanceRevision: Int) -> Bool {
        guard !isSaving else { return false }
        guard hasUnsavedChanges else { return true }
        dialog = .leave(message: UserEditCopy.leaveMessage(changed: changedFields, applied: appliedForLeave(balanceRevision: balanceRevision)))
        return false
    }

    // MARK: - 表单操作（编辑态）

    func setRate(_ rate: Decimal?, for groupID: Int) {
        if let rate { draft.groupRates[groupID] = rate } else { draft.groupRates.removeValue(forKey: groupID) }
    }
    func setStatus(active: Bool) {
        guard !isOriginalAdmin else { return }
        draft.status = active ? "active" : "disabled"
    }

    // MARK: - ⋯ 删除用户（30 §6.4，同 §2.4）

    /// The shared confirmation with S3-05's words (S3D1-24); an administrator cannot be deleted.
    func prepareDelete(model: AppModel, siteName: String) {
        guard let user = stripUser, !isOriginalAdmin, user.role != AdminUserRole.admin.rawValue else { return }
        deleteRequest = DeleteRequest(objectNoun: "用户", displayName: user.displayName, siteName: siteName,
                                      siteLine: UserDetailPresentation.deleteSiteLine(siteName: siteName),
                                      consequences: UserDetailPresentation.deleteConsequences(keyCount: keyCount),
                                      expectedText: UserDetailPresentation.deleteExpectedText(user)) { [weak self] in
            await self?.delete(model: model)
        }
    }
    /// Already gone counts as deleted; the pages leave once the confirmation has closed.
    private func delete(model: AppModel) async {
        guard let id = editingUserID, let user = stripUser else { return }
        let generation = model.sessionGeneration
        do {
            _ = try await model.deleteUser(id: id)
            guard generation == model.sessionGeneration else { return }
            didDelete = true
            model.userList?.remove(id: id)
            model.receipts.show(Receipt(text: DeleteConfirmationCopy.deletedReceipt(objectNoun: "用户", displayName: user.displayName), systemImage: "trash"))
        } catch {
            guard generation == model.sessionGeneration, !(error is CancellationError) else { return }
            model.receipts.show(Receipt(text: UserDetailPresentation.statusFailure(error).text, systemImage: "exclamationmark.triangle", tone: .critical))
        }
    }

    private func ensureGroups(_ model: AppModel) async { await model.groupDirectory?.ensureLoaded() }
    /// 404 says the user is gone (and leaves the list); a cancelled read waits for the next appearance.
    private func settleLoadFailure(_ error: any Error, userID: Int, model: AppModel) {
        if error is CancellationError { return }
        if (error as? APIError)?.isUserNotFound == true {
            editLoad = .missing
            model.userList?.remove(id: userID)
        } else {
            editLoad = .failed(error.localizedDescription)
        }
    }
}
