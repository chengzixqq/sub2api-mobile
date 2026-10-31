import SwiftUI
import UIKit
import Sub2Core

/// `.proxyEdit(id:)` (60 §14.1): no id adds; an id edits, or renews an expired proxy. The row comes from the session's catalog,
/// otherwise it is read first (GET :id); a failed read offers 重试, a deleted proxy says so, 取消 always closes.
struct ProxyEditDestination: View {
    let id: Int?
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: AdminProxy?
    @State private var failure: String?
    @State private var isGone = false
    @State private var attempt = 0

    private var clock: Date { session?.client.serverClock.now() ?? Date() }

    var body: some View {
        NavigationStack {
            if id == nil {
                ProxyEditSheet(proxy: nil, now: clock)
            } else if let loaded {
                ProxyEditSheet(proxy: loaded, now: clock)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Group {
            if isGone {
                ContentUnavailableView(ProxyEditCopy.gone, systemImage: "trash")
                    .accessibilityElement(children: .combine).accessibilityIdentifier("proxyEdit.gone")
            } else if let failure {
                FailureView(message: failure) { retry() }
                    .accessibilityElement(children: .contain).accessibilityIdentifier("proxyEdit.failure")
            } else {
                ProgressView(ProxyEditCopy.loading).accessibilityIdentifier("proxyEdit.loading")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.sheetBackground)
        .navigationTitle(ProxyEditMode.edit.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("proxyEdit.cancel") }
        }
        .task(id: attempt) { await load() }
    }

    private func retry() {
        failure = nil
        attempt += 1
    }

    private func load() async {
        guard let id, loaded == nil, let session, session.generation == model.sessionGeneration else { return }
        if let row = model.proxyStore?.proxy(id: id), model.proxyStore?.generation == session.generation {
            loaded = row
            return
        }
        do {
            let row = try await model.proxyEditSource(for: session).proxy(id: id)
            guard session.generation == model.sessionGeneration, !Task.isCancelled else { return }
            loaded = row
        } catch {
            guard session.generation == model.sessionGeneration, !(error is CancellationError), !Task.isCancelled else { return }
            if ProxyDetailFailure.isGone(error) { isGone = true } else { failure = error.localizedDescription }
        }
    }
}

/// The form of 60 §14.3 in the mode's order, 取消 on the left and 添加 / 保存 / 续期 on the right (greyed while the form does not
/// pass). While a write runs the button spins and the form waits; with unsaved changes 取消 and a downward swipe ask “放弃修改？”,
/// with the result open (00 §2.5.4) “结果未确认” instead. ProxyEditFlow sends and closes the sheet when done.
struct ProxyEditSheet: View {
    let proxy: AdminProxy?
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    /// Taken once when the sheet opens, so a catalog refresh behind it never resets what is typed.
    @State private var draft: ProxyEditDraft
    @State private var flow: ProxyEditFlow?
    @State private var flowGeneration: UUID?
    @State private var confirmingDiscard = false
    @State private var confirmingLater = false

    init(proxy: AdminProxy?, now: Date) {
        self.proxy = proxy
        _draft = State(initialValue: proxy.map { ProxyEditDraft(editing: $0, now: now) } ?? .adding())
    }

    private var clock: Date { session?.client.serverClock.now() ?? Date() }
    private var zone: ServerTimeZone { session?.site.serverTimeZone ?? .device }
    private var isBusy: Bool { flow?.isBusy ?? false }
    private var isUnconfirmed: Bool { flow?.isUnconfirmed ?? false }
    private var store: ProxyStore? { model.proxyStore.flatMap { $0.generation == session?.generation ? $0 : nil } }
    private var backups: [ProxyBackupCandidate] { ProxyBackupCandidate.make(from: store?.proxies ?? [], excluding: proxy?.id, now: clock) }
    private var canSubmit: Bool { flow.map { !$0.locksForm } == true && draft.isSubmittable(backups: backups, now: clock) }

    var body: some View {
        ProxyEditForm(draft: $draft, backups: backups, zone: zone, flow: flow, isLocked: flow?.locksForm ?? false)
            .navigationTitle(draft.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isBusy || isUnconfirmed || draft.hasUnsavedChanges)
            .background(ProxyDismissAttemptBridge { if !isBusy { cancel() } })
            .alert(ProxyEditCopy.discardTitle, isPresented: $confirmingDiscard) {
                Button(ProxyEditCopy.discardConfirm, role: .destructive) { dismiss() }
                Button(ProxyEditCopy.keepEditing, role: .cancel) {}
            }
            .alert(ProxyEditCopy.unconfirmedCloseTitle, isPresented: $confirmingLater) {
                Button(ProxyEditCopy.checkLater, role: .destructive) { checkLater() }
                Button(ProxyEditCopy.keepChecking, role: .cancel) {}
            } message: {
                Text(ProxyEditCopy.unconfirmedCloseMessage(adding: proxy == nil))
            }
            .task(id: session?.generation) {
                prepare()
                await store?.ensureFresh()
            }
            .onChange(of: flow?.isFinished) { _, finished in if finished == true { dismiss() } }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消", action: cancel).disabled(isBusy).accessibilityIdentifier("proxyEdit.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if isBusy {
                ProgressView().accessibilityLabel(ProxyEditCopy.saving).accessibilityIdentifier("proxyEdit.saving")
            } else {
                Button(draft.submitTitle, action: submit)
                    .disabled(!canSubmit)
                    .readOnlyGate(showsCaption: false)
                    .accessibilityIdentifier("proxyEdit.submit")
            }
        }
    }

    private func cancel() {
        if isUnconfirmed { confirmingLater = true } else if draft.hasUnsavedChanges { confirmingDiscard = true } else { dismiss() }
    }
    /// 稍后核对 (00 §2.5.4): closes without the key; the catalog reads again.
    private func checkLater() {
        flow?.checkLater()
        dismiss()
    }
    /// Not tied to the view: the sheet cannot be closed while the write runs, and it closes itself when done.
    private func submit() {
        guard let flow, canSubmit else { return }
        let snapshot = draft
        Task { await flow.submit(snapshot) }
    }
    /// One flow per session; answers of an older one are dropped.
    private func prepare() {
        guard let session, session.generation == model.sessionGeneration, flowGeneration != session.generation else { return }
        let generation = session.generation
        flow = ProxyEditFlow(original: proxy, source: model.proxyEditSource(for: session), store: store, receipts: model.receipts,
                             generation: generation, isCurrent: { [weak model] in model?.sessionGeneration == generation },
                             now: { session.client.serverClock.now() })
        flowGeneration = generation
    }
}

extension AppModel {
    /// The site, or under `-ui-testing` this session's FixtureProxySource, which the catalog and the detail share (S6D1-12).
    func proxyEditSource(for session: SessionContext) -> any ProxyEditSource {
        let store = proxyStore.flatMap { $0.generation == session.generation ? $0 : nil }
        return (store?.source as? any ProxyEditSource) ?? ClientProxySource(client: session.client)
    }
}

/// 60 §14.4 “有未保存修改时下滑关闭先确认”: with interactiveDismissDisabled the sheet stays and UIKit tells the presentation's
/// delegate about the attempt. The proxy stands in for SwiftUI's delegate, forwards everything to it and reports the attempt
/// first. A copy of AnnouncementEditSheet's; S6-26 merges them into one view (S6D1-16). Should it not get installed, only 取消
/// asks.
fileprivate struct ProxyDismissAttemptBridge: UIViewControllerRepresentable {
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
