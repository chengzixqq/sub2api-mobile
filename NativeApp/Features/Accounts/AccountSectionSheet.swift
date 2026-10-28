import SwiftUI
import Sub2Core

/// An open edit sheet: its section, its own base and version (the page's refreshes never change them, 20 §2.6), and the save
/// flow it reports through (C-14).
struct AccountEditorRequest: Identifiable {
    let id = UUID()
    let section: AccountEditSection
    let base: AccountEditBase
    let flow: AccountPatchFlow
}

/// The pages a sheet pushes in its own stack (20 §3.1: no second sheet).
enum AccountEditPage: Hashable { case groups, expiry, customExpiry }

/// 20 §3.3–§3.5: one section's small form, 取消 on the left and 保存 on the right. 保存 is greyed without a change or while a
/// field is wrong (the error sits under it), and spins while AccountPatchFlow saves; the sheet then cannot be swiped away. With
/// changes, 取消 and a downward swipe ask “放弃未保存的改动？” first. The flow's questions and leftover states show here; a save
/// that went through closes the sheet. S2-12 fills in the models and advanced forms.
struct AccountSectionSheet: View {
    let request: AccountEditorRequest
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var base: AccountEditBase
    @State private var draft: AccountEditDraft
    @State private var path: [AccountEditPage] = []
    @State private var confirmingDiscard = false
    @State private var catalog: MetaCatalog = .builtin

    init(request: AccountEditorRequest) {
        self.request = request
        _base = State(initialValue: request.base)
        _draft = State(initialValue: AccountEditDraft(request.base.account))
    }

    private var flow: AccountPatchFlow { request.flow }
    private var form: AccountEditForm { AccountEditForm(section: request.section, base: base.account) }
    private var changed: [AccountEditField] { form.changedFields(draft) }
    private var isBusy: Bool { flow.isSaving }
    /// 没有保存成功 and 结果未确认 go on through their own buttons, with the fields locked until they settle.
    private var canSave: Bool { !flow.locksForm && form.change(draft, now: model.serverNow()) != nil }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                fields.disabled(flow.locksForm)
                if flow.phase != .idle, !isBusy {
                    Section { AccountPatchStatusRow(flow: flow) }
                }
            }
            .navigationTitle(request.section.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(for: AccountEditPage.self) { destination($0) }
            .accountPatchPrompts(flow)
        }
        .interactiveDismissDisabled(isBusy || !changed.isEmpty)
        .background(AccountSheetDismissBridge { if !changed.isEmpty, !isBusy { confirmingDiscard = true } })
        .alert(AccountEditCopy.discardTitle, isPresented: $confirmingDiscard) {
            Button(AccountEditCopy.discardConfirm, role: .destructive) { dismiss() }
            Button(AccountEditCopy.keepEditing, role: .cancel) {}
        } message: {
            Text(AccountEditCopy.discardMessage(changed.map(\.title)))
        }
        .onChange(of: flow.savedRevision) { _, _ in saved() }
        .onChange(of: flow.reloadRevision) { _, _ in reloaded() }
        .task { catalog = await model.metaCatalog() }
    }

    @ViewBuilder private var fields: some View {
        let errors = form.errors(draft, now: model.serverNow())
        switch request.section {
        case .basic: AccountBasicForm(draft: $draft, form: form, errors: errors, platformText: platformText)
        case .sched: AccountScheduleForm(draft: $draft, form: form, errors: errors, groupNames: draft.groupIDs.map(groupName))
        case .models, .adv: EmptyView()
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { cancel() }.disabled(isBusy).accessibilityIdentifier("account.edit.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if isBusy {
                ProgressView().accessibilityLabel("正在保存").accessibilityIdentifier("account.edit.saving")
            } else {
                Button("保存") { save() }.disabled(!canSave).accessibilityIdentifier("account.edit.save")
            }
        }
    }

    @ViewBuilder private func destination(_ page: AccountEditPage) -> some View {
        switch page {
        case .groups:
            AccountGroupPicker(selection: $draft.groupIDs, account: base.account, platformName: platformName)
        case .expiry:
            AccountExpiryPicker(expiresAt: $draft.expiresAt, now: model.serverNow(), serverTimeZone: session?.site.serverTimeZone ?? .device,
                                onCustom: { path.append(.customExpiry) }, onDone: { path.removeAll() })
        case .customExpiry:
            AccountExpiryCustomPage(expiresAt: $draft.expiresAt, now: model.serverNow(), onDone: { path.removeAll() })
        }
    }

    private var platformText: String {
        let account = base.account
        return platformName(account.platform) + " · " + AccountNaming.typeName(platform: account.platform, type: account.type)
    }
    private func platformName(_ platform: String) -> String { AccountNaming.platformName(platform, catalog: catalog) }
    private func groupName(_ id: Int) -> String {
        model.groupDirectory?.name(for: id) ?? base.account.groups.first { $0.id == id }?.name ?? "#\(id)"
    }

    private func cancel() {
        if changed.isEmpty { dismiss() } else { confirmingDiscard = true }
    }
    private func save() {
        guard let change = form.change(draft, now: model.serverNow()) else { return }
        let base = base
        Task { await flow.save(change, base: base) }
    }
    /// The groups' member counts moved with a group change.
    private func saved() {
        if changed.contains(.groups) { Task { await model.groupDirectory?.refresh() } }
        dismiss()
    }
    /// 重新载入: the server's copy replaces the base and the draft.
    private func reloaded() {
        guard let fresh = flow.reloadedBase else { return }
        base = fresh
        draft = AccountEditDraft(fresh.account)
    }
}

/// 20 §3.4 “有改动时下滑先确认”: with interactiveDismissDisabled the sheet stays and UIKit tells the presentation's delegate about
/// the attempt. The proxy stands in for SwiftUI's delegate, forwards everything to it and reports the attempt first (the
/// announcement sheet's bridge, S6-26 merges the copies, S6D1-16); should it not get installed, only 取消 asks.
private struct AccountSheetDismissBridge: UIViewControllerRepresentable {
    let onAttempt: @MainActor () -> Void

    func makeCoordinator() -> DismissAttemptProxy { DismissAttemptProxy(onAttempt: onAttempt) }
    func makeUIViewController(context: Context) -> Probe { Probe(proxy: context.coordinator) }
    /// Again after SwiftUI has finished this update, which may set its own delegate back.
    func updateUIViewController(_ probe: Probe, context: Context) {
        context.coordinator.onAttempt = onAttempt
        probe.install()
        Task { @MainActor in probe.install() }
    }

    final class Probe: UIViewController {
        private let proxy: DismissAttemptProxy
        init(proxy: DismissAttemptProxy) {
            self.proxy = proxy
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { nil }
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }
        /// Onto the presented controller at the top of this one's parents, once.
        func install() {
            var root: UIViewController = self
            while let parent = root.parent { root = parent }
            guard root.presentingViewController != nil, let presentation = root.presentationController, presentation.delegate !== proxy else { return }
            proxy.original = presentation.delegate
            presentation.delegate = proxy
        }
    }

    final class DismissAttemptProxy: NSObject, UIAdaptivePresentationControllerDelegate {
        var onAttempt: @MainActor () -> Void
        nonisolated(unsafe) weak var original: (any UIAdaptivePresentationControllerDelegate)?

        init(onAttempt: @escaping @MainActor () -> Void) { self.onAttempt = onAttempt }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            original?.presentationControllerShouldDismiss?(presentationController) ?? true
        }
        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
            original?.presentationControllerWillDismiss?(presentationController)
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            original?.presentationControllerDidDismiss?(presentationController)
        }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            onAttempt()
            original?.presentationControllerDidAttemptToDismiss?(presentationController)
        }
        /// Everything else (adaptive styles) goes to SwiftUI's delegate as if it were still the delegate.
        nonisolated override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }
        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }
    }
}
