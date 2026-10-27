import SwiftUI
import UIKit
import Sub2Core

/// 60 §17 `.announcementEdit(id:)`. A new announcement opens at once; an existing one is read first (GET :id), so the form
/// starts from what the server holds. A failed read offers 重试, 取消 always closes.
struct AnnouncementEditLoader: View {
    let id: Int?
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: Announcement?
    @State private var failure: String?
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            if id == nil {
                AnnouncementEditSheet(original: nil)
            } else if let loaded {
                AnnouncementEditSheet(original: loaded)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Group {
            if let message = failure {
                FailureView(message: message) { retry() }
                    .accessibilityElement(children: .contain).accessibilityIdentifier("announcement.edit.failure")
            } else {
                ProgressView(AnnouncementEditCopy.loading).accessibilityIdentifier("announcement.edit.loading")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(AnnouncementEditRole.draft.sheetTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("announcement.edit.cancel") }
        }
        .task(id: attempt) { await load() }
        .onChange(of: model.foregroundRevision) { _, _ in retry() }
    }

    private func retry() {
        failure = nil
        attempt += 1
    }

    private func load() async {
        guard let id, loaded == nil, let session else { return }
        do {
            let announcement = try await model.announcementEditSource(for: session).load(id)
            guard session.generation == model.sessionGeneration, !Task.isCancelled else { return }
            loaded = announcement
        } catch {
            guard session.generation == model.sessionGeneration, !(error is CancellationError), !Task.isCancelled else { return }
            failure = AnnouncementWriteFailure.isGone(error) ? AnnouncementEditCopy.gone : error.localizedDescription
        }
    }
}

/// The form (60 §17.1, §17.3): 编辑 / 预览 on top, 取消 and 存草稿 / 保存 in the bar, 发布 / 重新发布 at the bottom (after the
/// 16.4 confirmation). AnnouncementEditFlow sends; a running save spins its button and locks the form. With unsaved changes
/// 取消 and a downward swipe ask “放弃修改？” first.
struct AnnouncementEditSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case edit, preview
        var id: Self { self }
        var title: String { self == .edit ? "编辑" : "预览" }
    }
    private enum Action { case trailing, primary }

    let original: Announcement?
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AnnouncementDraft
    @State private var baseline: AnnouncementDraft
    @State private var flow: AnnouncementEditFlow?
    @State private var flowGeneration: UUID?
    @State private var mode = Mode.edit
    @State private var selection: TextSelection?
    @State private var running: Action?
    @State private var confirmingPublish = false
    @State private var confirmingDiscard = false

    init(original: Announcement?) {
        self.original = original
        let start = original.map { AnnouncementDraft(announcement: $0, now: Date(), timeZone: .current) } ?? AnnouncementDraft(now: Date(), timeZone: .current)
        _draft = State(initialValue: start)
        _baseline = State(initialValue: start)
    }

    private var role: AnnouncementEditRole { AnnouncementEditRole(original: original) }
    private var hasChanges: Bool { draft.hasChanges(comparedTo: baseline) }
    private var isBusy: Bool { flow?.isBusy ?? false }
    private var canSave: Bool { (flow.map { !$0.locksForm } ?? false) && draft.isValid }

    var body: some View {
        content
            .navigationTitle(role.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .top, spacing: 0) { modePicker }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .interactiveDismissDisabled(isBusy || hasChanges)
            .background(AnnouncementDismissAttemptBridge { if hasChanges, !isBusy { confirmingDiscard = true } })
            .task(id: session?.generation) { prepare() }
            .task(id: session?.generation) { await model.groupDirectory?.ensureLoaded() }
            .onChange(of: flow?.exit) { _, exit in close(exit) }
    }

    @ViewBuilder private var content: some View {
        Group {
            switch mode {
            case .edit: form
            case .preview: preview
            }
        }
        .alert(AnnouncementEditCopy.discardTitle, isPresented: $confirmingDiscard) {
            Button(AnnouncementEditCopy.discardConfirm, role: .destructive) { dismiss() }
            Button(AnnouncementEditCopy.keepEditing, role: .cancel) {}
        }
    }

    private var form: some View {
        Form {
            AnnouncementContentSection(draft: $draft, selection: $selection)
            AnnouncementTargetSection(draft: $draft, options: groupOptions, lockedLines: lockedLines)
            AnnouncementNotifySection(draft: $draft)
            AnnouncementScheduleSection(draft: $draft)
        }
        .disabled(flow?.locksForm ?? false)
        .accessibilityIdentifier("announcement.edit.form")
    }

    private var preview: some View {
        ScrollView {
            AnnouncementPreviewCard(title: draft.title, content: draft.content, notifyMode: draft.notifyMode).padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("announcement.edit.preview")
    }

    private var modePicker: some View {
        Picker("编辑或预览", selection: $mode) {
            ForEach(Mode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("announcement.edit.mode")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { cancel() }.disabled(isBusy).accessibilityIdentifier("announcement.edit.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if isBusy, running == .trailing {
                ProgressView().accessibilityLabel(AnnouncementEditCopy.saving).accessibilityIdentifier("announcement.edit.saving")
            } else {
                Button(role.trailingTitle) { start(.trailing) }.disabled(!canSave).accessibilityIdentifier("announcement.edit.trailing")
            }
        }
    }

    @ViewBuilder private var bottomBar: some View {
        let showsStatus = flow.map { $0.phase != .editing } ?? false
        if showsStatus || role.primaryTitle != nil {
            VStack(spacing: 10) {
                if let flow, showsStatus { AnnouncementEditStatusBar(flow: flow, now: clockNow) }
                if let title = role.primaryTitle { primaryButton(title) }
            }
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    private func primaryButton(_ title: String) -> some View {
        Button { confirmingPublish = true } label: {
            ZStack {
                Text(title).opacity(isBusy && running == .primary ? 0 : 1)
                if isBusy, running == .primary { ProgressView() }
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canSave)
        .accessibilityLabel(title)
        .accessibilityIdentifier("announcement.edit.primary")
        .alert(publishConfirmation.title, isPresented: $confirmingPublish) {
            Button(title) { start(.primary) }
            Button("取消", role: .cancel) {}
        } message: {
            Text(publishConfirmation.message)
        }
    }

    // MARK: - Derived

    private var clockNow: Date { session?.client.serverClock.now() ?? Date() }
    private var groupOptions: [AnnouncementGroupOption] {
        AnnouncementDraft.subscriptionOptions(groups: model.groupDirectory?.groups ?? [], selected: draft.groupIDs)
    }
    private var lockedLines: [AnnouncementLockedLine] {
        draft.lockedTargeting.map { AnnouncementDraft.lockedLines($0, groupNames: groupName) } ?? []
    }
    /// 16.4 with the form's content: the trimmed title and the targeting it will have.
    private var publishConfirmation: AnnouncementPublishConfirmation {
        AnnouncementPresentation.publishConfirmation(title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                     targetText: AnnouncementPresentation.targetText(draft.effectiveTargeting, groupNames: groupName),
                                                     notifyMode: draft.notifyMode, startsAt: draft.startsAt, endsAt: draft.endsAt,
                                                     now: clockNow, timeZone: .current)
    }
    private func groupName(_ id: Int) -> String? { model.groupDirectory?.name(for: id) }

    // MARK: - Actions

    private func cancel() {
        if hasChanges { confirmingDiscard = true } else { dismiss() }
    }
    private func start(_ action: Action) {
        guard let flow else { return }
        running = action
        let snapshot = draft
        Task {
            switch action {
            case .trailing: await flow.saveTrailing(snapshot)
            case .primary: await flow.publish(snapshot)
            }
        }
    }
    /// 查看 of H07 opens the one found; anything saved closes with its receipt.
    private func close(_ exit: AnnouncementEditFlow.Exit?) {
        guard let exit else { return }
        if case .open(let id) = exit { router.push(.announcementDetail(id: id)) }
        dismiss()
    }
    /// One flow per session; results of an older one are dropped (C-0.2).
    private func prepare() {
        guard let session, session.generation == model.sessionGeneration, flowGeneration != session.generation else { return }
        let generation = session.generation
        flow = AnnouncementEditFlow(original: original, source: model.announcementEditSource(for: session),
                                    keyedCreate: session.has(.announcementsIdempotentCreate), receipts: model.receipts,
                                    isCurrent: { [weak model] in model?.sessionGeneration == generation },
                                    onChanged: { [weak model] in model?.announcementChanges.bump() },
                                    now: { session.client.serverClock.now() })
        flowGeneration = generation
    }
}

extension AppModel {
    /// The site, or under `-ui-testing` this session's AnnouncementDemoStore (shared with the list and the detail).
    func announcementEditSource(for session: SessionContext) -> AnnouncementEditSource {
        guard isUITesting else { return .live(session.client) }
        return .fixture(AnnouncementDemoStore.current(for: session.generation, base: session.client.serverClock.now()))
    }
}

/// 60 §17.4 “有未保存修改时下滑关闭先确认”: with interactiveDismissDisabled the sheet stays and UIKit tells the presentation's
/// delegate about the attempt. The proxy stands in for SwiftUI's delegate, forwards everything to it and reports the
/// attempt first. S6-26 merges the copies into one view (S6D1-16); should it not get installed, only 取消 asks.
fileprivate struct AnnouncementDismissAttemptBridge: UIViewControllerRepresentable {
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
