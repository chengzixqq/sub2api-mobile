import SwiftUI
import Sub2Core

/// 30 §6 (S3-11): the edit user page, `UserEditView(mode: .edit(userID:))`. A fixed head (identity strip, the three segments
/// with their marks and the status line; folded while the form scrolls or a field has focus), the segment's form, and the
/// navigation bar's ⋯ and “保存” (UserEditToolbar). The base is read once and never overwritten by later reads (30 §6.6).
struct UserEditScreen: View {
    @Bindable var editor: UserEditorModel
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: UserEditSheet?
    @State private var rpmRefresh = 0
    /// 30 §3.4 for the strip's capsule: R03's question first, then S3-07's check (S3-08, S3-07).
    @State private var balanceEntry: BalanceKeypadEntry?
    @State private var reconcileFlow = BalanceReconcileFlow()
    @State private var scrolled = false
    @State private var typing = false
    @FocusState private var focus: UserDraftField?

    private var catalog: UserGroupCatalog { UserGroupCatalog(groups: model.groupDirectory?.groups ?? []) }
    private var compact: Bool { scrolled || typing }
    private var revision: Int { editor.editingUserID.map { model.userChanges?.revision(userID: $0) ?? 0 } ?? 0 }

    var body: some View {
        content
            .navigationTitle(UserEditCopy.editTitle)
            .navigationSubtitle(model.activeProfile?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .userEditToolbar(editor)
            .sheet(item: $sheet) { sheetContent($0) }
            .balanceReconcileFlow(reconcileFlow)
            .balanceKeypadEntry($balanceEntry) { [reconcileFlow, model, editor] op in
                Task { await reconcileFlow.reconcile(op, model: model, balance: editor.stripUser?.balance) }
            }
            .task { await editor.loadForEdit(model: model) }
            .task { if editor.definitionsState != .loaded { await editor.loadDefinitions(model: model) } }
            .task { await editor.loadBoundKeys(model: model) }
            .task(id: focus) { await followFocus() }
            .onChange(of: catalog) { _, next in editor.adoptCatalog(next) }
            // A balance written from the strip, a key's group change: the strip reads the user again; the form stays.
            .onChange(of: revision) { _, _ in Task { await editor.reloadStrip(model: model) } }
            .onAppear { editor.reopen() }
            .onDisappear { editor.close() }
    }

    @ViewBuilder private var content: some View {
        switch editor.editLoad {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("user-edit.loading")
        case .failed(let reason):
            ContentUnavailableView {
                Label(UserEditCopy.loadFailed, systemImage: "exclamationmark.triangle").accessibilityIdentifier("user-edit.load-error")
            } description: { Text(reason ?? "") } actions: {
                Button("重试") { Task { await editor.loadForEdit(model: model) } }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("user-edit.retry")
            }
        case .missing:
            ContentUnavailableView {
                Label(UserEditCopy.userGone, systemImage: "person.crop.circle.badge.xmark").accessibilityIdentifier("user-edit.not-found")
            } actions: {
                Button("返回") { dismiss() }.frame(minHeight: 44).accessibilityIdentifier("user-edit.not-found.back")
            }
        case .loaded:
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    // 30 §6.1: another segment starts at its top, with the head unfolded.
                    form
                        .id(editor.segment)
                        .onChange(of: editor.segment) { _, _ in withAnimation(.snappy) { scrolled = false } }
                        .onChange(of: editor.focusRequest) { _, request in
                            guard let request else { return }
                            Task {
                                try? await Task.sleep(for: .milliseconds(80))
                                withAnimation { proxy.scrollTo(request.field, anchor: .top) }
                            }
                        }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if let user = editor.stripUser {
                    UserEditIdentityStrip(user: user, isSelf: editor.isSelf, isPending: model.hasPendingBanner(userID: user.id), compact: compact) {
                        balanceEntry = BalanceKeypadEntry.open(userID: user.id, mode: .topup, model: model, router: router)
                    }
                }
                UserEditSegmentBar(segments: UserEditSegment.allCases, selection: $editor.segment, issues: marks(\.issues), changed: marks(\.changed),
                                   keysTitle: UserEditCopy.keysSegmentTitle(count: editor.keyCount), isDisabled: editor.isFrozen)
            }
            // 30 §6.1: folded, the marks stay on the segments only.
            if !compact {
                Text(editor.statusLine).font(.footnote).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("user-edit.hint")
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
    private func marks(_ count: KeyPath<UserEditSegmentMark, Int>) -> [UserEditSegment: Int] {
        Dictionary(editor.segmentMarks.map { (UserEditSegment($0.section), $0[keyPath: count]) }, uniquingKeysWith: +)
    }

    private var form: some View {
        Form {
            switch editor.segment {
            case .basic:
                UserEditBasicSection(editor: editor, focus: $focus) { sheet = .attribute(id: $0) }
            case .access:
                UserEditAccessSection(editor: editor, catalog: catalog, groups: model.groupDirectory?.state.display ?? .placeholder,
                                      onRetryGroups: { Task { await model.groupDirectory?.refresh() } },
                                      onAddGroups: { sheet = .addExclusiveGroups }, onOpenGroup: { sheet = .group(id: $0) },
                                      rpmRefreshToken: rpmRefresh)
            case .keys:
                UserEditKeysSlot(editor: editor)
            }
        }
        .disabled(editor.isFrozen)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            rpmRefresh += 1
            await editor.reloadStrip(model: model)
        }
        .onScrollGeometryChange(for: Double.self) {
            UserEditCopy.scrollOffset(contentOffset: Double($0.contentOffset.y), insetTop: Double($0.contentInsets.top))
        } action: { _, offset in
            let next = UserEditCopy.isScrolledCompact(offset: offset, wasCompact: scrolled)
            if next != scrolled { withAnimation(.snappy) { scrolled = next } }
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: UserEditSheet) -> some View {
        let catalog = self.catalog
        switch sheet {
        case .addExclusiveGroups:
            UserAddExclusiveGroupsSheet(options: catalog.exclusive.filter { !editor.draft.exclusiveGroupIDs.contains($0.id) },
                                        subscriptionNote: catalog.subscriptionNote, isCreate: false) { editor.addExclusiveGroups($0) }
        case .group(let id):
            if let group = (catalog.exclusive + catalog.publicGroups).first(where: { $0.id == id }) {
                let isExclusive = catalog.exclusiveIDs.contains(id)
                UserGroupSheet(group: group, isExclusive: isExclusive, context: .edit, restrictsPublic: editor.draft.restrictPublicGroups,
                               allowed: editor.draft.allowsPublicGroup(id), rate: editor.draft.groupRates[id],
                               boundKeys: editor.boundKeyCount(groupID: id),
                               onDone: { [editor] allowed, rate in
                                   if !isExclusive { editor.setPublicGroup(id, allowed: allowed) }
                                   editor.setRate(rate, for: id)
                               },
                               onRemove: removal(of: id, isExclusive: isExclusive))
            }
        case .attribute(let id):
            if let definition = editor.definitions.first(where: { $0.id == id }) {
                UserAttributeOptionSheet(definition: definition, value: editor.draft.attributes[id] ?? "") { editor.draft.attributes[id] = $0 }
            }
        }
    }

    /// Only an exclusive group can be removed from its sheet.
    private func removal(of id: Int, isExclusive: Bool) -> (@MainActor () -> Void)? {
        guard isExclusive else { return nil }
        return { [editor] in editor.removeExclusiveGroup(id) }
    }
    /// Folds at once on focus; unfolds 300ms after the last field lost it, so the tap that moved focus lands first.
    private func followFocus() async {
        if focus != nil {
            withAnimation(.snappy) { typing = true }
            return
        }
        try? await Task.sleep(for: UserEditCopy.unfoldDelay)
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) { typing = focus != nil }
    }
}

/// The third segment, “Key 与限额”, until S3-12 puts the key cards here (30 §7).
struct UserEditKeysSlot: View {
    let editor: UserEditorModel

    var body: some View {
        Section {
            Text(UserEditCopy.keysPlaceholder).foregroundStyle(Palette.ink2).frame(minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("user-edit.keys.placeholder")
        }
    }
}
