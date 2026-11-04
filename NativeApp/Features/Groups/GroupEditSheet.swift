import SwiftUI
import Sub2Core

/// `.groupEdit(id:)` (50 §3.1): no id creates; an id edits that group, taken from the session's GroupStore or read first. A failed
/// read offers 重试, a deleted group says so and leaves the list, 取消 always closes.
struct GroupEditDestination: View {
    let id: Int?
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: AdminGroup?
    @State private var failure: String?
    @State private var isGone = false
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            if id == nil {
                GroupEditSheet(original: nil)
            } else if let loaded {
                GroupEditSheet(original: loaded)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Group {
            if isGone {
                ContentUnavailableView(GroupErrorCopy.deleted, systemImage: "trash")
                    .accessibilityElement(children: .combine).accessibilityIdentifier("group-edit.gone")
            } else if let failure {
                FailureView(message: failure) { retry() }
                    .accessibilityElement(children: .contain).accessibilityIdentifier("group-edit.failure")
            } else {
                ProgressView(GroupEditCopy.loading).accessibilityIdentifier("group-edit.loading")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.sheetBackground)
        .navigationTitle(GroupEditCopy.title(isNew: false))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("group-edit.cancel") }
        }
        .task(id: attempt) { await load() }
    }

    private func retry() {
        failure = nil
        attempt += 1
    }
    private func load() async {
        guard let id, loaded == nil, let session, session.generation == model.sessionGeneration, let store = model.groupStore,
              store.generation == session.generation else { return }
        if let row = store.group(id: id) {
            loaded = row
            return
        }
        do {
            let row = try await store.fetch(id: id)
            guard session.generation == model.sessionGeneration, !Task.isCancelled else { return }
            loaded = row
        } catch {
            guard session.generation == model.sessionGeneration, !Task.isCancelled else { return }
            switch GroupWriteDisposition.of(error) {
            case .cancelled: return
            case .gone:
                store.remove(id: id)
                isGone = true
            default: failure = GroupErrorCopy.message(for: error, context: .read)
            }
        }
    }
}

/// 50 §3.3–§3.5: the form, 取消 on the left and 创建 / 保存 on the right (greyed until the form passes and has something to send,
/// a spinner while it writes). With unsaved changes 取消 and a downward swipe ask “放弃修改？”; with the result open (00 §2.5.4)
/// “结果未确认” instead; a write or its result keeps the sheet up. GroupEditFlow writes and closes the sheet when done. S5-11: the
/// members section, its 添加账号 page pushed inside the sheet (GroupAccountPicker `.draft`, back to 新建分组 / 编辑分组), and an
/// edit's members read when it opens.
struct GroupEditSheet: View {
    let original: AdminGroup?
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    /// Taken once when the sheet opens, so a list refresh behind it never resets what is typed.
    @State private var draft: GroupEditDraft
    @State private var flow: GroupEditFlow?
    @State private var flowGeneration: UUID?
    @State private var catalog: MetaCatalog?
    @State private var confirmingDiscard = false
    @State private var confirmingLater = false
    @State private var membersLoad: GroupEditMembersLoad?
    @State private var addingAccounts = false

    init(original: AdminGroup?) {
        self.original = original
        _draft = State(initialValue: original.map(GroupEditDraft.init(editing:)) ?? .creating())
    }

    private var store: GroupStore? { model.groupStore.flatMap { $0.generation == session?.generation ? $0 : nil } }
    private var permissions: GroupPermissions { GroupPermissions(session: session, store: store) }
    private var editable: Set<GroupPermissions.Field> { permissions.editableFields(in: original) }
    private var takenNames: Set<String> {
        GroupEditDraft.takenNames(in: store?.groups ?? [], excluding: original?.id).union(flow?.rejectedNames ?? [])
    }
    private var isBusy: Bool { flow?.isBusy ?? false }
    private var isUnconfirmed: Bool { flow?.isUnconfirmed ?? false }
    private var canSubmit: Bool { flow.map { !$0.locksForm } == true && draft.isSubmittable(takenNames: takenNames, editable: editable) }
    /// 50 §0.7: hidden for a vendor and simple mode's composite group.
    private var membersEntry: GroupPermissions.Entry { GroupMemberDraftCopy.membersEntry(permissions, group: original) }
    /// 0.4.4 without `groups.member_batch` (or after GROUP_REPOSITORY_UNSUPPORTED); never in simple mode, where it does not run.
    private var showsLegacyNote: Bool { model.groupMemberWriteSession.map { !$0.usesBatch && $0.allowsLegacy } ?? false }
    private var serverNow: Date { session?.client.serverClock.now() ?? Date() }

    var body: some View {
        GroupEditForm(draft: $draft, permissions: permissions, platforms: GroupEditDraft.platformOptions(catalog: catalog), catalog: catalog,
                      issues: draft.issues(takenNames: takenNames), flow: flow, isLocked: flow?.locksForm ?? false, members: membersSection)
            .navigationDestination(isPresented: $addingAccounts) {
                GroupAccountPicker(mode: .draft(platform: draft.platform, excluded: draft.members.excludedIDs, onAdd: { draft.members = draft.members.adding($0) }))
                    .interactiveDismissDisabled(draft.hasUnsavedChanges)
            }
            .navigationTitle(GroupEditCopy.title(isNew: original == nil))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isBusy || isUnconfirmed || draft.hasUnsavedChanges)
            .onDismissAttempt { if !isBusy { cancel() } }
            .guardsTabSwitch(hasUnsavedInput: draft.hasUnsavedChanges && !isBusy) { cancel() }
            .alert(flow?.prompt?.confirmation.title ?? "", isPresented: promptShown, presenting: flow?.prompt) { prompt in
                Button(prompt.confirmation.confirmTitle, role: prompt.confirmation.isDestructive ? .destructive : nil) { flow?.confirm() }
                Button(GroupConfirmation.cancelTitle, role: .cancel) { flow?.cancelConfirmation() }
            } message: { prompt in
                Text(prompt.confirmation.message)
            }
            .alert(GroupEditCopy.discardTitle, isPresented: $confirmingDiscard) {
                Button(GroupEditCopy.discardConfirm, role: .destructive) { leave() }
                Button(GroupEditCopy.keepEditing, role: .cancel) { router.cancelPendingSelect() }
            }
            .alert(GroupEditCopy.unconfirmedCloseTitle, isPresented: $confirmingLater) {
                Button(GroupEditCopy.checkLater, role: .destructive) { checkLater() }
                Button(GroupEditCopy.keepChecking, role: .cancel) { router.cancelPendingSelect() }
            } message: {
                Text(GroupEditCopy.unconfirmedCloseMessage(isNew: original == nil, hasMemberChanges: flow?.hasMemberChangesPending ?? false))
            }
            .task(id: session?.generation) {
                prepare()
                catalog = await model.metaCatalog()
                await store?.loadIfNeeded()
            }
            .task(id: session?.generation) { await loadMembers() }
            .onChange(of: draft) { _, _ in flow?.draftChanged() }
            .onChange(of: flow?.isFinished) { _, finished in if finished == true { dismiss() } }
            .onChange(of: model.sessionGeneration) { _, _ in dismiss() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消", action: cancel).disabled(isBusy).accessibilityIdentifier("group-edit.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if isBusy {
                ProgressView().accessibilityLabel(GroupEditCopy.saving).accessibilityIdentifier("group-edit.saving")
            } else {
                Button(GroupEditCopy.submitTitle(isNew: original == nil), action: submit)
                    .disabled(!canSubmit)
                    .readOnlyGate(showsCaption: false)
                    .accessibilityIdentifier("group-edit.submit")
            }
        }
    }

    /// Only the confirmation's own buttons change the flow, so closing the alert never leaves a prompt behind.
    private var promptShown: Binding<Bool> { Binding(get: { flow?.prompt != nil }, set: { _ in }) }

    /// Also a tab switch's question (S2-中-27): the same answers, 放弃 / 稍后核对 going on to that tab.
    private func cancel() {
        if flow?.phase == .failed(.gone) { return leave() }
        if isUnconfirmed { confirmingLater = true } else if draft.hasUnsavedChanges { confirmingDiscard = true } else { leave() }
    }
    /// 稍后核对 (00 §2.5.4): closes without the number; the list reads again.
    private func checkLater() {
        flow?.checkLater()
        leave()
    }
    /// Closes the sheet, or with a tab switch waiting goes on to that tab, which closes it too.
    private func leave() {
        if !router.confirmPendingSelect() { dismiss() }
    }
    /// Not tied to the view: the sheet cannot close while the write runs, and it closes itself when done.
    private func submit() {
        guard let flow, canSubmit else { return }
        let snapshot = draft
        let context = GroupEditContext(editable: editable, knownGroupIDs: Set(store?.groups.map(\.id) ?? []), catalog: catalog, now: serverNow)
        Task { await flow.submit(snapshot, context: context) }
    }
    /// One flow per session; answers of an older one are dropped.
    private func prepare() {
        guard let session, session.generation == model.sessionGeneration, flowGeneration != session.generation else { return }
        flow = GroupEditFlow(model: model, router: router, original: original)
        flowGeneration = session.generation
    }

    // MARK: - 成员账号（S5-11）

    @ViewBuilder private var membersSection: some View {
        if membersEntry.isShown {
            GroupEditMembersSection(draft: $draft, load: membersLoad?.state, catalog: catalog, showsLegacyNote: showsLegacyNote,
                                    isEditable: membersEntry.isEnabled,
                                    batchUnsupportedNote: permissions.membersBatchUnsupported ? GroupPermissions.membersBatchUnsupportedNote : nil,
                                    onAdd: { addingAccounts = true }, onRetry: { Task { await loadMembers() } })
        }
    }
    /// An edit's members, once; a failure keeps 成员加载失败 · 重试 and the fields can still be saved.
    private func loadMembers() async {
        guard let original, membersEntry.isShown, !draft.members.isLoaded, session?.generation == model.sessionGeneration else { return }
        let load = membersLoad ?? GroupEditMembersLoad(model: model, groupID: original.id)
        membersLoad = load
        await load.load()
        if let list = load.state.value { draft.membersLoaded(list.rows) }
    }
}

extension GroupEditFlow {
    /// Writes through AppGroupEditSource into the session's GroupStore and the members through GroupMemberWriter; receipts on the
    /// App's center, 查看 on the current tab (S5D2a-08).
    convenience init(model: AppModel, router: AppRouter, original: AdminGroup?) {
        self.init(original: original, source: AppGroupEditSource(model: model), store: { [weak model] in model?.groupStore }, receipts: model.receipts,
                  memberWriter: GroupMemberWriter(model: model, router: router), openResults: { [weak router] in router?.showGroupBatch($0) })
    }
}
