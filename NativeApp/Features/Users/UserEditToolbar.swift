import SwiftUI
import Sub2Core

extension View {
    /// 30 §6.1 the edit page's navigation bar: its own back (asking before unsaved changes go; the system back and its edge
    /// swipe are hidden while there is something to lose), ⋯ (复制邮箱, 删除用户…) and “保存”, with the page's confirmations.
    func userEditToolbar(_ editor: UserEditorModel) -> some View {
        modifier(UserEditToolbarModifier(editor: editor))
    }
}

private struct UserEditToolbarModifier: ViewModifier {
    @Bindable var editor: UserEditorModel
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    private var guardsLeaving: Bool { editor.hasUnsavedChanges || editor.isSaving }
    private var balanceRevision: Int { editor.editingUserID.map { model.userChanges?.balanceRevision(userID: $0) ?? 0 } ?? 0 }

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(guardsLeaving)
            .toolbar {
                if guardsLeaving {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("返回", systemImage: "chevron.backward") { if editor.requestLeave(balanceRevision: balanceRevision) { dismiss() } }
                            .labelStyle(.iconOnly)
                            .disabled(editor.isSaving)
                            .accessibilityIdentifier("user-edit.back")
                    }
                }
                if editor.editLoad == .loaded {
                    ToolbarItem(placement: .topBarTrailing) { moreMenu }
                    ToolbarItem(placement: .topBarTrailing) { saveButton }
                }
            }
            .alert(editor.dialog?.title ?? "", isPresented: dialogShown, presenting: editor.dialog) { dialog in
                switch dialog {
                case .leave:
                    Button(UserEditCopy.leaveDiscard, role: .destructive) { editor.close(); dismiss() }
                    Button(UserEditCopy.keepEditing, role: .cancel) {}
                case .promote:
                    Button(UserEditCopy.promoteConfirm) { Task { await editor.confirmPromotion(model: model, router: router) } }
                    Button("取消", role: .cancel) {}
                }
            } message: { dialog in Text(dialog.message) }
            .confirmDelete($editor.deleteRequest)
            // 30 §6.4: deleted, the user's editor and detail leave once the confirmation has closed.
            .onChange(of: editor.deleteRequest == nil) { _, closed in
                guard closed, editor.didDelete, let id = editor.editingUserID else { return }
                editor.close()
                let tab = router.selectedTab
                router.setPath(UserEditNavigation.removingUserPages(router.path(for: tab), userID: id), for: tab)
            }
    }

    /// The system menu shows no identifiers, so tests find its items by their words.
    private var moreMenu: some View {
        Menu {
            Button(UserEditCopy.copyEmail, systemImage: "doc.on.doc") { copyEmail() }
            if editor.isOriginalAdmin {
                Button(role: .destructive) {} label: {
                    Text(UserEditCopy.deleteUser)
                    Text(UserEditCopy.adminCannotDelete)
                }
                .disabled(true)
            } else {
                Button(UserEditCopy.deleteUser, systemImage: "trash", role: .destructive) {
                    editor.prepareDelete(model: model, siteName: model.activeProfile?.name ?? "")
                }
                .disabled(editor.isSaving)
                .readOnlyGate(showsCaption: false)
            }
        } label: {
            Label("更多操作", systemImage: "ellipsis").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier("user-edit.more")
    }
    private var saveButton: some View {
        Button { Task { await editor.save(model: model, router: router) } } label: {
            if editor.isSaving { ProgressView().accessibilityLabel(Text(UserEditCopy.saving)) } else { Text(UserEditCopy.saveButton) }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!editor.canSave)
        .readOnlyGate(showsCaption: false)
        .accessibilityIdentifier("user-edit.save")
    }
    private var dialogShown: Binding<Bool> {
        Binding(get: { editor.dialog != nil }, set: { if !$0 { editor.dialog = nil } })
    }
    private func copyEmail() {
        guard let email = editor.stripUser?.email else { return }
        UIPasteboard.general.string = email
        model.receipts.show(Receipt(text: UserEditCopy.copiedEmail, systemImage: "doc.on.doc"))
    }
}
