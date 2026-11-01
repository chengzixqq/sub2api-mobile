import SwiftUI
import Sub2Core

/// 50 §2.3 壹 · 成员账号 (design GvDetailRows): the account tab's row with this group left out of its second line (“另属 X、Y”),
/// unavailable first, 今日 on the right, then the U38 footnote. The members read on their own: a failed first read says
/// “成员加载失败 · 重试” while the status card keeps the group's counts (2.5); a failed refresh keeps the rows under the header's
/// 更新失败. Rows end in a tail that reads the next page. S5-08: each row's swipe and long press (2.4), a row swiped out stays
/// hidden while its removal is out, and a vendor reads U37's footnote.
struct GroupMembersSection: View {
    let group: AdminGroup
    let members: LoadState<GroupMemberList>
    let today: LoadState<GroupMemberToday>
    let summary: GroupMemberSummary
    let isLoadingMore: Bool
    let loadMoreFailed: Bool
    let catalog: MetaCatalog
    let groupName: (Int) -> String?
    let onOpen: (UpstreamAccount) -> Void
    let onRetry: @MainActor () -> Void
    let onLoadMore: @MainActor () -> Void
    let memberActions: GroupMemberActions?
    let permissions: GroupPermissions
    let hidden: Set<Int>
    @Environment(\.sessionContext) private var session

    var body: some View {
        Section {
            switch members.state.display {
            case .placeholder:
                ForEach(0..<3, id: \.self) { _ in AccountRowSkeleton().listRowInsets(EdgeInsets()).listRowBackground(Palette.surface) }
            case .value(let list, _, _, _):
                rows(list)
            case .failed, .disabled:
                BlockFailureRow(title: GroupDetailCopy.membersLoadFailed, error: members.lastError, occurredAt: members.lastErrorAt,
                                refresh: members.refresh, id: "group.members", resendsAfterWait: false, retry: onRetry)
            }
        } header: {
            NumberedSectionHeader(title: GroupDetailCopy.membersTitle, ordinal: GroupDetailCopy.membersOrdinal,
                                  meta: GroupCopy.membersMeta(count: group.accountCount ?? 0), id: "group.members.header") {
                BlockStatusAccessory(members, id: "group.members", resendsAfterWait: false, retry: onRetry)
            }
        } footer: {
            footnote
        }
    }

    @ViewBuilder private func rows(_ list: GroupMemberList) -> some View {
        let rows = list.rows.filter { !hidden.contains($0.id) }
        if rows.isEmpty {
            Text(GroupDetailCopy.membersEmpty).font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("group.members.empty")
        } else {
            let now = serverNow
            let positions = RailPosition.positions(of: rows) { AccountDisplayState($0, now: now).tone.drawsRail }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, account in
                memberRow(account, rail: positions[index], now: now)
                    .onAppear { if index == rows.count - 1, list.hasMore { onLoadMore() } }
            }
            tail
        }
    }
    private func memberRow(_ account: UpstreamAccount, rail: RailPosition?, now: Date) -> some View {
        Button { onOpen(account) } label: {
            AccountRow(account: account, today: today.value?.cell(for: account.id) ?? AccountTodayCell(stats: nil, unavailable: false),
                       context: AccountRowContext(omit: .group, home: group.name), railPosition: rail, groupName: groupName, catalog: catalog)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("group.member.\(account.id)")
        .groupMemberRowActions(account, group: group, actions: memberActions, membersEntry: permissions.canEditMembers(group),
                               isReadOnly: permissions.isReadOnlyToken, now: now)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Palette.surface)
        .listRowSeparatorTint(Palette.hairline)
    }
    @ViewBuilder private var tail: some View {
        if isLoadingMore {
            ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("group.members.loading-more")
        } else if loadMoreFailed {
            Button(action: onLoadMore) {
                Text("\(BlockStatusPresentation.loadFailed) · \(BlockStatusPresentation.retryTitle)").font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("group.members.more.failure")
        }
    }
    /// U38: once today-stats has answered, and only when some row shows 今日 (design GvMemberNote); U37: a vendor changes
    /// memberships in the account detail.
    @ViewBuilder private var footnote: some View {
        let todayNote = todayFootnote, vendorNote = permissions.membersFootnote
        if todayNote != nil || vendorNote != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let todayNote {
                    Text(todayNote).font(.footnote).foregroundStyle(Palette.ink3).accessibilityIdentifier("group.members.footnote")
                }
                if let vendorNote {
                    Text(vendorNote).font(.footnote).foregroundStyle(Palette.ink3).accessibilityIdentifier("group.members.note")
                }
            }
        }
    }
    private var todayFootnote: String? {
        guard let list = members.value, !list.rows.isEmpty, summary.showsTodayFootnote, let scope = today.value?.scope else { return nil }
        return GroupCopy.membersTodayFootnote(isGroupScoped: scope == .group)
    }
    private var serverNow: Date { session?.client.serverClock.now() ?? Date() }
}
