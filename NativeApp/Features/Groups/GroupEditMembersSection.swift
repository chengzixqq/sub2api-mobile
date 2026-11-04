import SwiftUI
import Sub2Core

/// 50 §3.2 编辑的初值: the members, read once when the sheet opens with the detail's query (R19, GroupMemberList: 100 a page, every
/// page up to 2,000 members). The answers of another session are dropped.
@MainActor @Observable
final class GroupEditMembersLoad {
    let state = LoadState<GroupMemberList>()
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let groupID: Int
    @ObservationIgnored private let generation: UUID

    init(model: AppModel, groupID: Int) {
        self.model = model; self.groupID = groupID
        generation = model.sessionGeneration
    }

    func load() async {
        guard let model, isCurrent else { return }
        let query = GroupMemberList.query(groupID: groupID, supportsListQuery: model.sessionContext?.has(.accountsListQuery) ?? false)
        let now = model.serverNow()
        await state.load(isCurrent: { [weak self] in self?.isCurrent ?? false }) { [weak model] in
            guard let model else { throw CancellationError() }
            let first = try await model.managedAccounts(page: 1, query: query)
            var list = GroupMemberList(pages: [first], serverSorted: query.supportsListQuery, now: now)
            while list.hasMore {
                let next = try await model.managedAccounts(page: list.pagesRead + 1, query: query)
                list = list.appending(next, now: now)
            }
            return list
        }
    }
    private var isCurrent: Bool { model?.sessionGeneration == generation }
}

/// 50 §3.3 成员账号 N (design GvEditSheet): each member with “−”, its state glyph and name, and on the right 新加入 / 可调度 / its
/// badge counting down; 将移出：A、B; “添加 <平台> 账号…” to the picker inside the sheet; the footnote, and 0.4.4's notice on a
/// server that takes members one by one. An edit waits for its members (a spinner, or 成员加载失败 · 重试) and adds nothing until then.
/// A greyed members entry greys “添加” and “−”; S5-中-12's reason sits beside the title.
struct GroupEditMembersSection: View {
    @Binding var draft: GroupEditDraft
    /// The edit's read; nil for a new group.
    let load: LoadState<GroupMemberList>?
    let catalog: MetaCatalog?
    let showsLegacyNote: Bool
    /// GroupMemberDraftCopy.membersEntry is `.enabled`.
    let isEditable: Bool
    /// GroupPermissions.membersBatchUnsupportedNote when simple mode cannot take members in one batch.
    let batchUnsupportedNote: String?
    let onAdd: @MainActor () -> Void
    let onRetry: @MainActor () -> Void
    @Environment(\.sessionContext) private var session

    private var members: GroupMemberDraft { draft.members }

    var body: some View {
        Section {
            if members.isLoaded {
                ForEach(members.rows) { row in
                    GroupEditMemberRow(row: row, isEditable: isEditable) { draft.members = draft.members.removing(row.id) }
                }
                if let line = GroupMemberDraftCopy.removedLine(members.removedNames) {
                    Text(line).font(.footnote).foregroundStyle(Palette.ink2)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .accessibilityIdentifier("group-edit.members.removed")
                }
            } else {
                pendingRow
            }
            addRow
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(GroupMemberDraftCopy.sectionTitle(count: members.isLoaded ? members.count : draft.original?.accountCount ?? 0))
                    .accessibilityIdentifier("group-edit.members.header")
                if let batchUnsupportedNote {
                    Spacer(minLength: 8)
                    Text(batchUnsupportedNote).foregroundStyle(Palette.ink2).multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("group-edit.members.note.batch")
                }
            }
        } footer: {
            footer
        }
    }

    @ViewBuilder private var pendingRow: some View {
        switch load?.state.display {
        case .failed?, .disabled?:
            if let load {
                BlockFailureRow(title: GroupDetailCopy.membersLoadFailed, error: load.lastError, occurredAt: load.lastErrorAt, refresh: load.refresh,
                                id: "group-edit.members", resendsAfterWait: false, retry: onRetry)
            }
        default:
            ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("group-edit.members.loading")
        }
    }
    private var addRow: some View {
        Button(action: onAdd) {
            Label(GroupMemberDraftCopy.addRowTitle(platform: draft.platform, catalog: catalog), systemImage: "plus")
                .font(.body.weight(.semibold)).foregroundStyle(Palette.accent)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!members.isLoaded || !isEditable)
        .opacity(members.isLoaded && isEditable ? 1 : 0.4)
        .accessibilityIdentifier("group-edit.members.add")
        .readOnlyGate()
    }
    @ViewBuilder private var footer: some View {
        let note = draft.membersFootnote(now: serverNow)
        if note != nil || showsLegacyNote {
            VStack(alignment: .leading, spacing: 6) {
                if let note {
                    Text(note.text).foregroundStyle(note.isCritical ? Palette.criticalInk : Palette.ink3).accessibilityIdentifier("group-edit.members.footnote")
                }
                if showsLegacyNote {
                    Text(GroupMembersLegacyExecutor.notice).foregroundStyle(Palette.ink3).accessibilityIdentifier("group-edit.members.legacy")
                }
            }
        }
    }
    private var serverNow: Date { session?.client.serverClock.now() ?? Date() }
}

/// One member: “−” (44pt) takes it out, then the glyph, the name and what it is on the right; a window redraws every second.
private struct GroupEditMemberRow: View {
    let row: GroupMemberDraft.Row
    let isEditable: Bool
    let onRemove: @MainActor () -> Void
    @Environment(\.sessionContext) private var session

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill").font(.title3).foregroundStyle(Palette.critical)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!isEditable)
            .opacity(isEditable ? 1 : 0.4)
            .accessibilityLabel(GroupMemberDraftCopy.removeLabel(name: row.account.name))
            .accessibilityIdentifier("group-edit.member.\(row.id).remove")
            .readOnlyGate(showsCaption: false)
            if !row.isNew, row.display(now: serverNow).countdownTarget != nil {
                TimelineView(.periodic(from: .now, by: 1)) { _ in content(now: serverNow) }
            } else {
                content(now: serverNow)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("group-edit.member.\(row.id)")
    }

    private func content(now: Date) -> some View {
        let display = row.display(now: now)
        return HStack(spacing: 8) {
            GroupAccountStateGlyph(state: display.state)
            Text(row.account.name).foregroundStyle(Palette.ink1).lineLimit(1)
            Spacer(minLength: 8)
            trailing(now: now)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.stateText(row.trailing(now: now), now: now))
                .accessibilityIdentifier("group-edit.member.\(row.id).state")
        }
    }
    @ViewBuilder private func trailing(now: Date) -> some View {
        switch row.trailing(now: now) {
        case .newlyAdded:
            Text(GroupMemberDraftCopy.newTag).font(.footnote.weight(.semibold)).foregroundStyle(Palette.accent)
                .padding(.horizontal, 7).frame(minHeight: 22)
                .background(Palette.accentWash, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .schedulable:
            Text(GroupPickerPresentation.schedulableText).font(.footnote.weight(.semibold)).foregroundStyle(Tone.ok.ink)
        case .badge(let display):
            AccountStatusBadge(state: display, now: now)
        }
    }
    private static func stateText(_ trailing: GroupMemberDraft.Trailing, now: Date) -> String {
        switch trailing {
        case .newlyAdded: GroupMemberDraftCopy.newTag
        case .schedulable: GroupPickerPresentation.schedulableText
        case .badge(let display): AccountRowPresentation.badgeText(display, now: now) ?? display.label
        }
    }
    private var serverNow: Date { session?.client.serverClock.now() ?? Date() }
}
