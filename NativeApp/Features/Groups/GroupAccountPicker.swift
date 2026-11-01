import SwiftUI
import Sub2Core

/// 50 §4 添加账号 (design GvPickSheet / GvPickList): one view for both ways in. `.submit` is the sheet `.groupPick` (GroupDestinations
/// wraps it in a NavigationStack): “添加到「分组名」”, 取消, and a dock whose 加入 k 个账号 writes through GroupMemberWriter, then
/// closes; a refusal stays on the sheet in red. `.draft` is pushed inside the group editor (S5-11): “添加账号” and 添加 N, which only
/// hands the picks to the draft. Loaded once, again for each search; no polling, no pull (4.6).
struct GroupAccountPicker: View {
    enum Mode {
        case submit(groupID: Int)
        case draft(platform: String, excluded: Set<Int>, onAdd: @MainActor ([UpstreamAccount]) -> Void)
    }
    @Environment(AppModel.self) private var model
    private let mode: Mode

    init(mode: Mode) { self.mode = mode }

    var body: some View { GroupAccountPickerContent(app: model, mode: mode) }
}

private struct GroupAccountPickerContent: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var picker: GroupAccountPickerModel
    @State private var writer: GroupMemberWriter?
    /// A refusal of the last 加入 (GroupErrorCopy's words): the sheet stays so the picks are not lost.
    @State private var refusal: String?
    private let mode: GroupAccountPicker.Mode

    init(app: AppModel, mode: GroupAccountPicker.Mode) {
        self.mode = mode
        let target: GroupAccountPickerModel.Target = switch mode {
        case .submit(let groupID): .group(id: groupID)
        case .draft(let platform, let excluded, _): .draft(platform: platform, excluded: excluded)
        }
        _picker = State(initialValue: GroupAccountPickerModel(app: app, target: target))
    }

    var body: some View {
        list
            .searchable(text: Bindable(picker).search, placement: .navigationBarDrawer(displayMode: .always), prompt: searchPrompt)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { if isSubmitMode { dock } }
            .interactiveDismissDisabled(isSubmitting)
            .task(id: picker.search) { await picker.load(debounced: true) }
            .task { if writer == nil { writer = GroupMemberWriter(model: model, router: router) } }
    }

    // MARK: - List (4.3)

    private var list: some View {
        List {
            switch picker.candidates.state.display {
            case .placeholder:
                Section { ForEach(0..<3, id: \.self) { _ in AccountRowSkeleton().listRowInsets(EdgeInsets()) } }
            case .failed, .disabled:
                Section {
                    BlockFailureRow(title: GroupPickerPresentation.failedTitle, error: picker.candidates.lastError, occurredAt: picker.candidates.lastErrorAt,
                                    refresh: picker.candidates.refresh, id: "group.pick.load", resendsAfterWait: false) { Task { await picker.load(debounced: false) } }
                }
            case .value(let read, _, _, _):
                if read.rows.isEmpty {
                    Section {
                        Text(picker.emptyText ?? GroupPickerPresentation.noMatch).font(.subheadline).foregroundStyle(Palette.ink2)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityIdentifier("group.pick.empty")
                    }
                } else {
                    Section { ForEach(read.rows, id: \.id) { row($0) } } header: { Text(sectionTitle) }
                }
            }
            Section {} footer: { notes }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("group.pick")
    }

    private func row(_ account: UpstreamAccount) -> some View {
        let isOn = picker.isSelected(account.id)
        return Button { picker.toggle(account) } label: {
            TimelineView(.periodic(from: .now, by: 1)) { _ in GroupPickRow(account: account, isOn: isOn, now: serverNow, groupName: groupName) }
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .accessibilityLabel(Text(GroupPickRow.spokenLabel(account, now: serverNow, groupName: groupName)))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("group.pick.\(account.id)")
    }
    /// 4.3 底部说明, and 0.4.4's notice on a server that takes members one by one.
    @ViewBuilder private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let platform = picker.platform {
                Text(GroupPickerPresentation.footnote(platform: platform, catalog: model.groupStore?.catalog))
                    .accessibilityIdentifier("group.pick.note")
            }
            if isSubmitMode, writer?.fellBackToLegacy == true {
                Text(GroupErrorCopy.resolve(.server(status: 500, reason: GroupMemberReason.repositoryUnsupported), context: .members).message)
                    .accessibilityIdentifier("group.pick.unsupported")
            }
            if isSubmitMode, showsLegacyNotice {
                Text(GroupMembersLegacyExecutor.notice).accessibilityIdentifier("group.pick.legacy")
            }
        }
        .font(.footnote).foregroundStyle(Palette.ink3)
    }

    // MARK: - Dock and toolbar (4.3, 4.4)

    private var dock: some View {
        let content = picker.group.map { GroupPickerPresentation.dock(selected: picker.selection, group: $0, now: serverNow) } ?? .empty
        return VStack(alignment: .leading, spacing: 8) {
            if let refusal {
                Text(refusal).font(.footnote).foregroundStyle(Tone.critical.ink).accessibilityIdentifier("group.pick.error")
            }
            Text(content.preview).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink1)
                .accessibilityIdentifier("group.pick.preview")
            Button(action: submit) {
                Group {
                    if isSubmitting { ProgressView() } else { Text(content.buttonTitle) }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .disabled(!content.isEnabled || isSubmitting)
            .accessibilityIdentifier("group.pick.submit")
            .readOnlyGate()
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .background(.bar)
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        switch mode {
        case .submit:
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }.disabled(isSubmitting).accessibilityIdentifier("group.pick.cancel")
            }
        case .draft(_, _, let onAdd):
            ToolbarItem(placement: .confirmationAction) {
                Button(GroupPickerPresentation.draftAddTitle(count: picker.selection.count)) {
                    onAdd(picker.selection)
                    dismiss()
                }
                .disabled(picker.selection.isEmpty)
                .accessibilityIdentifier("group.pick.add")
            }
        }
    }

    /// 0.4.3: the receipt follows the sheet; a refusal keeps it open with the picks.
    private func submit() {
        guard let writer, let group = picker.group, !picker.selection.isEmpty else { return }
        refusal = nil
        let picks = picker.selection
        Task {
            switch await writer.add(picks, to: GroupMemberTarget(group)) {
            case .rejected(let text): refusal = text
            case .ignored: break
            case .result, .groupGone, .unconfirmed: dismiss()
            }
        }
    }

    // MARK: - Words

    private var isSubmitMode: Bool { if case .submit = mode { true } else { false } }
    private var isSubmitting: Bool { writer?.isSubmitting == true }
    /// 0.4.4 without `groups.member_batch` (or after GROUP_REPOSITORY_UNSUPPORTED this session); never in simple mode, where the
    /// fallback does not run.
    private var showsLegacyNotice: Bool {
        guard let write = model.groupMemberWriteSession else { return false }
        return !write.usesBatch && write.allowsLegacy
    }
    private var title: String {
        guard isSubmitMode else { return GroupPickerPresentation.draftTitle }
        return GroupPickerPresentation.title(groupName: picker.group?.name ?? "")
    }
    private var searchPrompt: String {
        GroupPickerPresentation.searchPrompt(platform: picker.platform ?? "composite", catalog: model.groupStore?.catalog)
    }
    private var sectionTitle: String {
        GroupPickerPresentation.sectionTitle(platform: picker.platform ?? "composite", catalog: model.groupStore?.catalog)
    }
    /// The session's group directory (C-10), then the name the row embedded, then “#id”.
    private func groupName(_ id: Int) -> String? { model.groupDirectory?.name(for: id) }
    private var serverNow: Date { session?.client.serverClock.now() ?? Date() }
}

/// 4.3 行: the selection ring, the name with “可调度” or the state badge (counting down), then the stopped mark, type and groups.
private struct GroupPickRow: View {
    let account: UpstreamAccount
    let isOn: Bool
    let now: Date
    let groupName: (Int) -> String?

    var body: some View {
        let display = AccountDisplayState(account, now: now)
        let second = GroupPickerPresentation.secondLine(account, now: now, directory: groupName)
        let status = GroupPickerPresentation.statusText(display)
        HStack(spacing: 12) {
            AccountSelectionRing(isOn: isOn)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(account.name).font(.body.weight(.semibold)).foregroundStyle(Palette.ink1).lineLimit(1)
                    Spacer(minLength: 0)
                    if let status {
                        Text(status).font(.footnote.weight(.semibold)).foregroundStyle(Tone.ok.ink)
                    } else {
                        AccountStatusBadge(state: display, now: now)
                    }
                }
                Text(second).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(2)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    /// The badge is hidden from VoiceOver, so the state is said in words.
    static func spokenLabel(_ account: UpstreamAccount, now: Date, groupName: (Int) -> String?) -> String {
        let display = AccountDisplayState(account, now: now)
        let status = GroupPickerPresentation.statusText(display) ?? display.label
        return [account.name, status, GroupPickerPresentation.secondLine(account, now: now, directory: groupName)].joined(separator: "，")
    }
}
