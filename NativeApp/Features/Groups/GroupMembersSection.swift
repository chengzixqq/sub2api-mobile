import SwiftUI
import Sub2Core

/// 50 §2.3 壹 · 成员账号 (design GvDetailRows): the account tab's row with this group left out of its second line (“另属 X、Y”),
/// unavailable first, 今日 on the right, then the U38 footnote. The members read on their own: a failed first read says
/// “成员加载失败 · 重试” while the status card keeps the group's counts (2.5); a failed refresh keeps the rows under the header's
/// 更新失败. Rows end in a tail that reads the next page (S5-08 adds the swipes and the 添加 row here).
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
        if list.rows.isEmpty {
            Text(GroupDetailCopy.membersEmpty).font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("group.members.empty")
        } else {
            let now = serverNow
            let positions = RailPosition.positions(of: list.rows) { AccountDisplayState($0, now: now).tone.drawsRail }
            ForEach(Array(list.rows.enumerated()), id: \.element.id) { index, account in
                memberRow(account, rail: positions[index])
                    .onAppear { if index == list.rows.count - 1, list.hasMore { onLoadMore() } }
            }
            tail
        }
    }
    /// S5-08 hangs the member's swipes and long press on this row.
    private func memberRow(_ account: UpstreamAccount, rail: RailPosition?) -> some View {
        Button { onOpen(account) } label: {
            AccountRow(account: account, today: today.value?.cell(for: account.id) ?? AccountTodayCell(stats: nil, unavailable: false),
                       context: AccountRowContext(omit: .group, home: group.name), railPosition: rail, groupName: groupName, catalog: catalog)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("group.member.\(account.id)")
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
    /// U38: once today-stats has answered, and only when some row shows 今日 (design GvMemberNote).
    @ViewBuilder private var footnote: some View {
        if let list = members.value, !list.rows.isEmpty, summary.showsTodayFootnote, let scope = today.value?.scope {
            Text(GroupCopy.membersTodayFootnote(isGroupScoped: scope == .group)).font(.footnote).foregroundStyle(Palette.ink3)
                .accessibilityIdentifier("group.members.footnote")
        }
    }
    private var serverNow: Date { session?.client.serverClock.now() ?? Date() }
}
