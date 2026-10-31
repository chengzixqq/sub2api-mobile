import SwiftUI
import Sub2Core

/// 30 §7 the edit page's third segment, Key 与限额 (S3-12): the notice, the API Key section with its cards, and the footnote.
/// Everything here takes effect at once. S3-14 (平台限额) and S3-15 (替换分组) add their sections at the marks below.
struct UserKeysSegment: View {
    let model: UserKeysModel
    let editor: UserEditorModel
    /// Hung on the page (`userKeyPrompts`): inside the form they would go with a row scrolled away.
    let prompts: UserKeyPrompts
    /// The page's ScrollViewReader: a card whose head left the screen when another closed is brought back.
    let scrollTo: @MainActor (String) -> Void
    @Environment(AppModel.self) private var app

    private var context: UserKeysContext? { model.context }
    private var groups: [AdminGroup] { app.groupDirectory?.groups ?? [] }

    var body: some View {
        noticeSection
        if let context { keysSection(context) }
        // MARK: S3-14 平台限额
        if let quota = prompts.quota {
            PlatformQuotaSection(store: quota, hasActiveSubscription: hasActiveSubscription) { prompts.quotaSheet = $0 }
        }
        // MARK: S3-15 替换分组
    }

    private var noticeSection: some View {
        Section {
            Text("\(Text(UserKeyPresentation.noticeLead).bold())\(UserKeyPresentation.noticeTail)")
                .font(.subheadline).foregroundStyle(Palette.ink1)
                .accessibilityIdentifier("keys.notice")
                .task { await model.enterSegment() }
                .task { await prompts.enterQuota(userID: model.userID, app: app, editor: editor) }
        }
    }
    /// 30 §8.2 有效订阅提示, from the subscriptions the key segment reads.
    private var hasActiveSubscription: Bool {
        PlatformQuotaPresentation.hasActiveSubscription(model.subscriptions, now: context?.now() ?? Date())
    }

    private func keysSection(_ context: UserKeysContext) -> some View {
        Section {
            switch model.phase {
            case .loading:
                ForEach(0..<2, id: \.self) { _ in UserKeyCardSkeleton() }
                    .accessibilityIdentifier("keys.skeleton")
            case .failed:
                Button { Task { await model.retryList() } } label: {
                    Label(UserKeyPresentation.listFailed + " · 重试", systemImage: "arrow.clockwise").frame(minHeight: 44)
                }
                .accessibilityIdentifier("keys.list.retry")
            case .loaded:
                if model.keys.isEmpty { emptyRow(context) }
                ForEach(model.keys) { card($0, context: context) }
            }
            if context.adminKeyWrites { newKeyRow } else { newKeyGap }
        } header: {
            NumberedSectionHeader(title: UserKeyPresentation.sectionTitle,
                                  meta: model.phase == .loaded ? UserKeyPresentation.sectionMeta(model.keys, now: context.now(), simpleMode: context.simpleMode) : nil,
                                  id: "keys.header")
        } footer: {
            Text(UserKeyPresentation.footnote).accessibilityIdentifier("keys.footnote")
        }
    }

    private func card(_ key: AdminAPIKey, context: UserKeysContext) -> some View {
        UserKeyCard(key: key, isExpanded: model.expandedID == key.id, isBusy: model.inFlight.contains(key.id), today: model.todayCost(for: key.id),
                    context: context, access: editor.keyAccess, groups: groups, canChangeGroup: editor.canStartImmediateWrite,
                    onToggle: { toggle(key.id) }, onChangeGroup: { prompts.groupKey = key }, onReset: { prompts.resetKey = key },
                    onSetStatus: { status in Task { await model.setStatus(key, to: status) } }, onGap: { prompts.gap = $0 },
                    reveal: prompts.manage.revealAvailability(model: app), onEdit: { prompts.manage.beginEdit(key) },
                    onReveal: { Task { await prompts.manage.reveal(key, keys: model, model: app) } },
                    onDelete: { requestDelete(key) })
            .id("keys.card.\(key.id)")
    }

    private func emptyRow(_ context: UserKeysContext) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(UserKeyPresentation.emptyTitle).font(.body.weight(.semibold)).foregroundStyle(Palette.ink1)
            Text(UserKeyPresentation.emptyDetail(adminKeyWrites: context.adminKeyWrites)).font(.footnote).foregroundStyle(Palette.ink2)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("keys.empty")
    }

    /// E01 (S3-13): “＋ 新建 Key” at the end of the list.
    private var newKeyRow: some View {
        Button { prompts.manage.beginCreate(userID: model.userID) } label: {
            Label(UserKeyPresentation.newKey, systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("keys.new")
        .readOnlyGate()
    }
    private func requestDelete(_ key: AdminAPIKey) {
        prompts.manage.requestDelete(key, siteName: app.activeProfile?.name ?? "", userDisplayName: editor.stripUser?.displayName ?? "",
                                     keys: model, model: app)
    }

    /// E01 missing: the design's dashed row instead of “＋ 新建 Key”.
    private var newKeyGap: some View {
        Button { prompts.gap = UserKeyPresentation.newKey } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").accessibilityHidden(true)
                Text(UserKeyPresentation.newKey)
                Spacer(minLength: 8)
                Text(UserKeyPresentation.gapTag).font(.caption).foregroundStyle(Palette.ink3)
            }
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.ink3, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(UserKeyPresentation.newKey)，\(UserKeyPresentation.gapTag)，点按查看说明"))
        .accessibilityIdentifier("keys.new.gap")
    }

    /// One card open at a time; closing a card above can push the opened one's head off screen, so it is brought back.
    private func toggle(_ id: Int) {
        let previous = model.expandedID
        let opened = withAnimation(.snappy) { model.toggleExpanded(id) }
        guard opened, let previous, let from = model.keys.firstIndex(where: { $0.id == previous }),
              let to = model.keys.firstIndex(where: { $0.id == id }), from < to else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation { scrollTo("keys.card.\(id)") }
        }
    }
}

/// The segment's sheet and questions, opened by its cards.
@MainActor @Observable
final class UserKeyPrompts {
    var groupKey: AdminAPIKey?
    var resetKey: AdminAPIKey?
    /// What the server lacks (keyGap).
    var gap: String?
    /// S3-13: 新建 / 编辑 Key, the full key and 删除 Key, hung on the page with the rest.
    let manage = UserKeyManageModel()
    /// S3-14: the platform quota section's store, made on the first visit to the segment and kept for the page, and its sheets.
    private(set) var quota: PlatformQuotaStore?
    var quotaSheet: PlatformQuotaSheetRoute?

    /// Writes are named in the page's leave confirmation; USER_NOT_FOUND turns the page into “用户不存在”.
    func enterQuota(userID: Int, app: AppModel, editor: UserEditorModel) async {
        if quota == nil {
            let hooks = PlatformQuotaHooks(onApplied: { [weak editor] in editor?.applyImmediate($0) },
                                           onUndone: { [weak editor] in editor?.undoImmediate($0) },
                                           onUserGone: { [weak editor] in editor?.editLoad = .missing })
            quota = PlatformQuotaStore(userID: userID, source: app, receipts: app.receipts, hooks: hooks)
        }
        await quota?.enterSegment()
    }
}

extension View {
    /// 换分组, 重置速率限制's confirmation and keyGap, and S3-13's key form, full key and delete confirmation, hung on the
    /// edit page above its form.
    func userKeyPrompts(_ prompts: UserKeyPrompts, model: UserKeysModel?, editor: UserEditorModel) -> some View {
        modifier(UserKeyPromptsModifier(prompts: prompts, manage: prompts.manage, model: model, editor: editor))
    }
}

private struct UserKeyPromptsModifier: ViewModifier {
    @Bindable var prompts: UserKeyPrompts
    @Bindable var manage: UserKeyManageModel
    let model: UserKeysModel?
    let editor: UserEditorModel
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content
            .sheet(item: $prompts.groupKey) { key in
                UserKeyGroupSheet(keyName: key.displayName, options: options(for: key)) { target in
                    Task { await model?.changeGroup(key, to: target) }
                }
            }
            .alert(prompts.resetKey.map { UserKeyPresentation.resetConfirmationTitle(keyName: $0.displayName) } ?? "", isPresented: resetShown,
                   presenting: prompts.resetKey) { key in
                Button(UserKeyPresentation.resetConfirm, role: .destructive) { Task { await model?.resetRateLimit(key) } }
                Button("取消", role: .cancel) {}
            } message: { _ in Text(UserKeyPresentation.resetConfirmationMessage) }
            .alert(prompts.gap.map(UserKeyPresentation.gapTitle) ?? "", isPresented: gapShown) {
                Button(UserKeyPresentation.gapDismiss, role: .cancel) {}
            } message: { Text(UserKeyPresentation.gapMessage) }
            // S3-13: the full key opens only once the form has gone (`formDismissed`).
            .sheet(item: $manage.form, onDismiss: { manage.formDismissed() }) { formSheet($0) }
            .sheet(item: $manage.revealed, onDismiss: { manage.secretDismissed() }) { UserKeyRevealSheet(secret: $0) }
            .confirmDelete($manage.deleteRequest)
            // S3-14: 添加平台限额 and the platform's sheet; picking a platform replaces the picker with its sheet.
            .sheet(item: $prompts.quotaSheet) { quotaSheet($0) }
    }

    @ViewBuilder private func quotaSheet(_ route: PlatformQuotaSheetRoute) -> some View {
        if let store = prompts.quota {
            switch route {
            case .picker:
                PlatformQuotaPickerSheet(store: store) { prompts.quotaSheet = .edit($0) }
            case .edit(let platform):
                PlatformQuotaEditSheet(store: store, platform: platform, userName: editor.stripUser?.displayName ?? "",
                                       hasActiveSubscription: PlatformQuotaPresentation.hasActiveSubscription(model?.subscriptions ?? [],
                                                                                                              now: model?.context?.now() ?? Date()))
            }
        }
    }

    @ViewBuilder private func formSheet(_ form: UserKeyFormModel) -> some View {
        if let model {
            UserKeyFormSheet(model: form, groupOptions: { options(currentGroupID: $0) }, zone: model.context?.serverTimeZone ?? .device,
                             immediateWritesAllowed: editor.canStartImmediateWrite) { [manage, app] in
                await manage.submit($0, keys: model, model: app)
            }
        }
    }

    private func options(for key: AdminAPIKey) -> [UserKeyGroupOption] { options(currentGroupID: key.groupID) }
    private func options(currentGroupID: Int?) -> [UserKeyGroupOption] {
        UserKeyPresentation.groupOptions(groups: app.groupDirectory?.groups ?? [], access: editor.keyAccess, subscriptions: model?.subscriptions ?? [],
                                         currentGroupID: currentGroupID, now: model?.context?.now() ?? Date())
    }
    private var resetShown: Binding<Bool> { Binding(get: { prompts.resetKey != nil }, set: { if !$0 { prompts.resetKey = nil } }) }
    private var gapShown: Binding<Bool> { Binding(get: { prompts.gap != nil }, set: { if !$0 { prompts.gap = nil } }) }
}
