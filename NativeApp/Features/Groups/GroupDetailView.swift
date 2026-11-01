import SwiftUI
import Sub2Core

/// 50 §2 `.group(id:)`: pushed by the group list, the home's 可用不足 row, the alert's scope, request details, the analytics
/// ranking, global search and a copy's 查看. It opens on the list's row when there is one. Status card and button row, then
/// 壹 · 成员账号; S5-07 adds the alert banner above the card and 贰 · 叁 · 肆 after the members. ⋯ and the button row go through
/// S5-05's GroupActions (a delete pops this page first).
struct GroupDetailView: View {
    @Environment(AppModel.self) private var model
    private let id: Int

    init(id: Int) { self.id = id }

    var body: some View { GroupDetailContent(app: model, id: id) }
}

/// The re-read at the soonest member window's end waits while the page may refresh (2.6).
private struct GroupCountdownWait: Hashable {
    let target: Date?
    let isOpen: Bool
}

private struct GroupDetailContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var detail: GroupDetailModel
    /// Made once the page shows, with the session's tabs (as the list does).
    @State private var actions: GroupActions?
    @State private var visible = false

    init(app: AppModel, id: Int) { _detail = State(initialValue: GroupDetailModel(app: app, groupID: id)) }

    var body: some View {
        // The tasks take the values of this pass, even if onAppear changes them before SwiftUI starts the task.
        let page = detail.page, isOpen = isRefreshOpen
        let wait = GroupCountdownWait(target: detail.memberSummary(now: serverNow).nextWindowEnd, isOpen: isOpen)
        content(page)
            .navigationTitle(title(page))
            .navigationSubtitle(subtitle(page))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .content = page, let group = detail.group, let actions {
                    ToolbarItem(placement: .topBarTrailing) { moreMenu(group, actions: actions) }
                }
            }
            .groupActionsHost(actions, leaving: leave)
            .task { if actions == nil { actions = GroupActions(model: model, router: router) } }
            .task { await detail.loadCatalog() }
            .task(id: isOpen) { if isOpen { await detail.poll() } }
            .task(id: wait) { await waitForCountdown(wait) }
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .onChange(of: model.foregroundRevision) { _, _ in Task { await detail.refresh(.foreground) } }
            .onChange(of: model.groupStore?.revision) { _, _ in detail.storeChanged(whileActionRuns: isActionRunning) }
            .onChange(of: isActionRunning) { _, running in if !running { detail.actionEnded() } }
    }

    // MARK: - Pages (50 §2.5)

    @ViewBuilder private func content(_ page: GroupDetailPageState) -> some View {
        switch page {
        case .deleted: GroupDeletedPage()
        case .failure(let message): GroupDetailFailurePage(message: message) { Task { await detail.refresh(.pull) } }
        case .skeleton, .content: list(page)
        }
    }

    private func list(_ page: GroupDetailPageState) -> some View {
        List {
            if case .content(let banner) = page, let group = detail.group, let buckets = detail.buckets, let health = detail.health {
                if let banner { Section { snapshotBanner(banner) }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                // 告警横幅（S5-07）：状态卡上方单独一段。
                Section { top(group, buckets: buckets, health: health) }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                GroupMembersSection(group: group, members: detail.members, today: detail.memberToday, summary: detail.memberSummary(now: serverNow),
                                    isLoadingMore: detail.isLoadingMoreMembers, loadMoreFailed: detail.loadMoreFailed, catalog: detail.catalog,
                                    groupName: groupName, onOpen: open, onRetry: { Task { await detail.retryMembers() } },
                                    onLoadMore: { Task { await detail.loadMoreMembers() } })
                // 贰 · 用量与容量、叁 · 记录与关联、肆 · 配置（S5-07）：成员分区之后。
            } else {
                Section { GroupStatusCardSkeleton() }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                Section { ForEach(0..<3, id: \.self) { _ in AccountRowSkeleton().listRowInsets(EdgeInsets()) } }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .refreshable { await detail.refresh(.pull) }
    }

    private func top(_ group: AdminGroup, buckets: GroupBuckets, health: GroupHealth) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupStatusCard(group: group, buckets: buckets, health: health, members: detail.members.value == nil ? nil : detail.memberSnapshots,
                            totalAPIKeys: detail.keyCounts.value?.totalAPIKeys)
            let buttons = permissions.buttonRow(for: group, health: health).filter { $0.action != .addAccounts }
            if !buttons.isEmpty {
                GroupDetailButtonRowView(buttons: buttons, isRunning: isActionRunning) { perform($0, on: group) }
            }
        }
        .padding(.vertical, 4)
    }

    private func snapshotBanner(_ text: String) -> some View {
        StatusBanner(tone: .neutral, systemImage: "exclamationmark.arrow.triangle.2.circlepath", title: text) {
            Button(BlockStatusPresentation.retryTitle) { Task { await detail.refresh(.pull) } }
                .buttonStyle(.borderless).frame(minHeight: 44).accessibilityIdentifier("group.detail.snapshot-banner.retry")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("group.detail.snapshot-banner")
    }

    // MARK: - Actions (50 §2.4)

    /// 50 §2.1 ⋯: S5-05's items by permission (添加账号 once S5-08 passes it), each greyed for a read-only token.
    private func moreMenu(_ group: AdminGroup, actions: GroupActions) -> some View {
        Menu {
            GroupActionMenuItems(group: group, actions: actions, permissions: permissions) { openEditor(group) }
        } label: {
            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("更多")
        .accessibilityIdentifier("group.more")
    }
    private func perform(_ action: GroupAction, on group: AdminGroup) {
        switch action {
        case .enable:
            guard let actions else { return }
            Task { await actions.enable(group) }
        case .edit: openEditor(group)
        default: break
        }
    }
    private func openEditor(_ group: AdminGroup) { router.present(.groupEdit(id: group.id)) }
    /// The row goes along, so the account's detail opens on it (20 §2.1).
    private func open(_ account: UpstreamAccount) { router.push(.account(id: account.id, preload: RoutePreload(account))) }
    /// 50 §0.5: a delete from here pops this page first; a page not on the router's stack closes itself.
    private func leave() {
        if !router.leaveGroup(id: detail.groupID) { dismiss() }
    }

    // MARK: - Refresh gates (50 §2.6)

    /// Foreground, visible, nothing over the page (the router's sheets, the actions' confirmations) and no action running.
    private var isRefreshOpen: Bool {
        guard visible, scenePhase == .active, !model.isSuspended, router.presentedSheet == nil, !detail.isDeleted, !isActionRunning else { return false }
        return actions?.disablePrompt == nil && actions?.deletePrompt == nil
    }
    private var isActionRunning: Bool { actions?.isRunning(detail.groupID) ?? false }
    private func waitForCountdown(_ wait: GroupCountdownWait) async {
        guard wait.isOpen, let target = wait.target else { return }
        let seconds = max(0, target.timeIntervalSince(serverNow)) + 0.5
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        await detail.countdownElapsed(target: target)
    }

    // MARK: - Words

    private var permissions: GroupPermissions { GroupPermissions(me: session?.site.me, isReadOnlyToken: session?.isReadOnlyToken ?? false) }
    private func title(_ page: GroupDetailPageState) -> String {
        if case .deleted = page { return GroupDetailCopy.deletedTitle }
        return detail.group?.name ?? GroupDetailCopy.deletedTitle
    }
    private func subtitle(_ page: GroupDetailPageState) -> String {
        guard case .content = page, let group = detail.group else { return "" }
        return GroupFormat.detailSubtitle(group, isSimpleMode: permissions.isSimpleMode, catalog: detail.catalog)
    }
    /// C-10 names; a group the directory does not know falls back to the row's own name or “#id”.
    private func groupName(_ id: Int) -> String? { model.groupDirectory?.name(for: id) }
    private var serverNow: Date { session?.client.serverClock.now() ?? Date() }
}

/// 50 §2.5 分组 404 (design GvGone): the whole page; the navigation keeps only 返回.
private struct GroupDeletedPage: View {
    var body: some View {
        Text(GroupErrorCopy.deleted)
            .font(.subheadline).foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
            .accessibilityIdentifier("group.detail.deleted")
    }
}

/// `GET :id` failed and the list had no row for it.
private struct GroupDetailFailurePage: View {
    let message: String
    let retry: @MainActor () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(GroupDetailCopy.loadFailedTitle, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(BlockStatusPresentation.retryTitle) { retry() }.buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("group.detail.retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("group.detail.failure")
    }
}
