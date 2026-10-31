import SwiftUI
import Sub2Core

/// The sheets of the user page.
enum UserEditSheet: Identifiable, Hashable {
    case addExclusiveGroups
    case group(id: Int)
    case attribute(id: Int)
    /// S3-15: the edit page's group sheet swaps itself for 替换专属分组.
    case replaceGroup(id: Int)
    var id: Self { self }
}

/// 30 §5 (S3-10; the edit state is S3-11's UserEditScreen): pushed full screen without the tab bar. A fixed head above the form (identity
/// strip, the segments and their hint, folding while the form scrolls or a field has focus, design `useUeCompact`), the
/// segment's form, and the bottom bar “下一步 / 上一步 · 创建用户”. Leaving with something typed asks first.
struct UserEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var editor: UserEditorModel
    @State private var sheet: UserEditSheet?
    @State private var confirmsDiscard = false
    @State private var scrolled = false
    @State private var typing = false
    @FocusState private var focus: UserDraftField?

    init(mode: UserEditorModel.Mode, segment: UserEditSegment = .basic) {
        _editor = State(initialValue: UserEditorModel(mode: mode, segment: segment))
    }

    private var catalog: UserGroupCatalog { UserGroupCatalog(groups: model.groupDirectory?.groups ?? []) }
    private var compact: Bool { scrolled || typing }
    /// The system back (and its edge swipe) stays while there is nothing to lose.
    private var guardsLeaving: Bool { editor.hasContent || editor.isFrozen }
    private var confirmation: UserCreateConfirmation? {
        if case .confirming(let confirmation) = editor.phase { confirmation } else { nil }
    }

    var body: some View {
        if editor.isEditing { UserEditScreen(editor: editor) } else { createPage }
    }

    private var createPage: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                form
                    .onChange(of: editor.segment) { _, segment in
                        proxy.scrollTo(editor.notice == nil ? AnyHashable(Self.firstRow(of: segment)) : AnyHashable(Self.noticeRow), anchor: .top)
                    }
                    .onChange(of: editor.focusRequest) { _, request in
                        guard let request else { return }
                        // The page's own message sits right above the segment's first row: keep it in view with the row.
                        let target = editor.notice != nil && request.field == Self.firstRow(of: editor.segment)
                            ? AnyHashable(Self.noticeRow) : AnyHashable(request.field)
                        Task {
                            try? await Task.sleep(for: .milliseconds(80))
                            withAnimation { proxy.scrollTo(target, anchor: .top) }
                        }
                    }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        }
        .navigationTitle(UserEditCopy.newTitle)
        .navigationSubtitle(model.activeProfile?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(guardsLeaving)
        .toolbar {
            if guardsLeaving {
                ToolbarItem(placement: .topBarLeading) {
                    Button("返回", systemImage: "chevron.backward", action: leave).labelStyle(.iconOnly)
                        .disabled(editor.isFrozen).accessibilityIdentifier("user-edit.back")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .alert(confirmation?.title ?? "", isPresented: confirmationShown, presenting: confirmation) { shown in
            Button(shown.confirmTitle, role: shown.isDestructive ? .destructive : nil) { Task { await editor.confirm(model: model, router: router) } }
            Button("取消", role: .cancel) { editor.cancelConfirmation() }
        } message: { shown in Text(shown.message) }
        .alert(UserEditCopy.discardNewTitle, isPresented: $confirmsDiscard) {
            Button(UserEditCopy.discardNew, role: .destructive) { dismiss() }
            Button(UserEditCopy.keepEditing, role: .cancel) {}
        } message: { Text(UserEditCopy.discardNewMessage) }
        .sheet(item: $sheet) { sheetContent($0) }
        .task { await editor.loadDefinitions(model: model) }
        .task { await model.groupDirectory?.ensureLoaded() }
        .task(id: focus) { await followFocus() }
        .onAppear { editor.reopen() }
        .onDisappear { editor.close(); model.receipts.setBottomClearance(0) }
    }

    private var form: some View {
        Form {
            if let notice = editor.notice { noticeSection(notice) }
            switch editor.segment {
            case .basic:
                UserEditBasicSection(editor: editor, focus: $focus) { sheet = .attribute(id: $0) }
            case .access, .keys:
                UserEditAccessSection(editor: editor, catalog: catalog, groups: model.groupDirectory?.state.display ?? .placeholder,
                                      onRetryGroups: { Task { await model.groupDirectory?.refresh() } },
                                      onAddGroups: { sheet = .addExclusiveGroups }, onOpenGroup: { sheet = .group(id: $0) })
            }
        }
        .disabled(editor.isFrozen)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Double.self) {
            UserEditCopy.scrollOffset(contentOffset: Double($0.contentOffset.y), insetTop: Double($0.contentInsets.top))
        } action: { _, offset in
            let next = UserEditCopy.isScrolledCompact(offset: offset, wasCompact: scrolled)
            if next != scrolled { withAnimation(.snappy) { scrolled = next } }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                UserEditIdentityStripNew(name: editor.displayName, initial: editor.initial, tail: editor.identityTail)
                UserEditSegmentBar(segments: Self.createSegments, selection: Bindable(editor).segment,
                                   issues: Dictionary(uniqueKeysWithValues: Self.createSegments.map { ($0, editor.issueCount(in: $0)) }),
                                   isDisabled: editor.isFrozen)
            }
            if !compact {
                Text(UserEditCopy.createHint).font(.footnote).foregroundStyle(Palette.ink2)
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

    private var actionBar: some View {
        HStack(spacing: 12) {
            if editor.segment == .basic {
                Button { editor.segment = .access } label: {
                    HStack(spacing: 6) { Text(UserEditCopy.nextStep); Image(systemName: "arrow.right").accessibilityHidden(true) }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("user-edit.next")
            } else {
                Button { editor.segment = .basic } label: { Text(UserEditCopy.previousStep).frame(minWidth: 72, minHeight: 44) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("user-edit.previous")
                Button { Task { await editor.create(model: model, router: router) } } label: { createLabel.frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.borderedProminent)
                    .readOnlyGate(showsCaption: false)
                    .accessibilityIdentifier("user-edit.create")
            }
        }
        .disabled(editor.isFrozen)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { model.receipts.setBottomClearance($0 + 8) }
    }
    @ViewBuilder private var createLabel: some View {
        if editor.isFrozen {
            HStack(spacing: 8) { ProgressView(); Text(UserEditCopy.creating) }
        } else {
            Text(UserEditCopy.createButton)
        }
    }

    private func noticeSection(_ notice: UserEditNotice) -> some View {
        Section {
            StatusBanner(tone: .critical, systemImage: "exclamationmark.octagon", title: notice.text)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("user-edit.notice")
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if let details = notice.details { ErrorDetailsDisclosure(details: details) }
        }
        .id(Self.noticeRow)
    }

    @ViewBuilder private func sheetContent(_ sheet: UserEditSheet) -> some View {
        let catalog = self.catalog
        switch sheet {
        case .addExclusiveGroups:
            UserAddExclusiveGroupsSheet(options: catalog.exclusive.filter { !editor.draft.exclusiveGroupIDs.contains($0.id) },
                                        subscriptionNote: catalog.subscriptionNote, isCreate: true) { editor.addExclusiveGroups($0) }
        case .group(let id):
            if let group = (catalog.exclusive + catalog.publicGroups).first(where: { $0.id == id }) {
                let isExclusive = catalog.exclusiveIDs.contains(id)
                UserGroupSheet(group: group, isExclusive: isExclusive, context: .create, restrictsPublic: editor.draft.restrictPublicGroups,
                               allowed: editor.draft.allowsPublicGroup(id),
                               onDone: { allowed, _ in if !isExclusive { editor.setPublicGroup(id, allowed: allowed) } },
                               onRemove: removal(of: id, isExclusive: isExclusive))
            }
        case .attribute(let id):
            if let definition = editor.definitions.first(where: { $0.id == id }) {
                UserAttributeOptionSheet(definition: definition, value: editor.draft.attributes[id] ?? "") { editor.draft.attributes[id] = $0 }
            }
        case .replaceGroup:
            EmptyView()
        }
    }

    /// Only an exclusive group can be removed from its sheet.
    private func removal(of id: Int, isExclusive: Bool) -> (@MainActor () -> Void)? {
        guard isExclusive else { return nil }
        return { [editor] in editor.removeExclusiveGroup(id) }
    }
    private var confirmationShown: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { editor.cancelConfirmation() } })
    }
    private func leave() {
        guard !editor.isFrozen else { return }
        if editor.hasContent { confirmsDiscard = true } else { dismiss() }
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

    private static let noticeRow = "user-edit.notice.row"
    /// A new user has only the two saved segments (DECISIONS 第 3 轮 Q13).
    private static let createSegments: [UserEditSegment] = [.basic, .access]
    private static func firstRow(of segment: UserEditSegment) -> UserDraftField { segment == .basic ? .email : .role }
}

/// 30 §5.1 the new user's strip: a blank avatar until something is typed, the name, “用户 · 创建后启用”.
struct UserEditIdentityStripNew: View {
    let name: String
    let initial: String?
    let tail: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(initial == nil ? Palette.sunken : Palette.accentWash)
                .frame(width: 32, height: 32)
                .overlay { Text(initial ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent) }
                .accessibilityHidden(true)
            Text(name).font(.headline).foregroundStyle(Palette.ink1).lineLimit(1)
            Spacer(minLength: 8)
            Text(tail).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("user-edit.identity")
    }
}

/// The segments with their marks (design UeSegBar): a red “!” where the check found something, a dot where something
/// changed (edit only), read aloud as “基础，有 1 项要修改、已改 2 项” (S3D1-01, UserDraftSection.spoken).
struct UserEditSegmentBar: View {
    let segments: [UserEditSegment]
    @Binding var selection: UserEditSegment
    /// Issues to fix per segment; 0 or missing draws no mark.
    let issues: [UserEditSegment: Int]
    var changed: [UserEditSegment: Int] = [:]
    /// The third segment's “Key 与限额（N）” (S3-11).
    var keysTitle: String?
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments, id: \.self) { segment in
                let count = issues[segment] ?? 0, edits = changed[segment] ?? 0, selected = segment == selection
                Button { selection = segment } label: {
                    HStack(spacing: 4) {
                        Text(title(segment)).font(.subheadline.weight(selected ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
                        if count > 0 {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.critical).accessibilityHidden(true)
                        } else if edits > 0 {
                            Circle().fill(Palette.accent).frame(width: 6, height: 6).accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(selected ? Palette.ink1 : Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(selected ? Palette.segmentOn : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(spoken(segment, issues: count, changed: edits)))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("user-edit.segment.\(segment.rawValue)")
            }
        }
        .padding(4)
        .frame(minHeight: 44)
        .background(Palette.sunken, in: Capsule())
        .disabled(isDisabled)
    }

    private func title(_ segment: UserEditSegment) -> String {
        switch segment {
        case .basic: UserDraftSection.basic.title
        case .access: UserDraftSection.access.title
        case .keys: keysTitle ?? UserEditCopy.keysSegmentTitle(count: nil)
        }
    }
    private func spoken(_ segment: UserEditSegment, issues: Int, changed: Int) -> String {
        switch segment {
        case .basic: UserDraftSection.basic.spoken(issues: issues, changed: changed)
        case .access: UserDraftSection.access.spoken(issues: issues, changed: changed)
        case .keys: title(segment)
        }
    }
}
