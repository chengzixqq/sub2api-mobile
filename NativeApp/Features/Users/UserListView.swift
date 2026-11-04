import SwiftUI
import Sub2Core

/// 30 §1: the user tab's root. The list is the session's `model.userList` (S3D1-05); this view only draws it and decides when
/// to read: on appear when nothing is loaded, on entering the tab, on returning to the foreground, after compliance, on pull
/// and every 60 seconds while the tab is shown in the foreground (30 §1.6). Search is debounced by 300 ms (30 §1.4).
struct UsersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""
    @State private var visible = false

    /// U01 reserves vendor sign-in: their page says so and sends nothing (30 §1.1).
    private var isVendor: Bool { session?.site.me.user?.role == AdminUserRole.vendor.rawValue }
    private var shouldPoll: Bool { visible && scenePhase == .active && router.selectedTab == .users }

    var body: some View {
        content
            .navigationTitle("用户")
            .navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(UserListPresentation.subtitle(siteName: model.activeProfile?.name ?? "", total: isVendor ? nil : model.userList?.total))
            .toolbar {
                if !isVendor {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("新建用户", systemImage: "plus", action: openCreate).readOnlyGate(showsCaption: false)
                            .accessibilityIdentifier("users.create")
                    }
                }
            }
    }

    @ViewBuilder private var content: some View {
        if isVendor {
            ContentUnavailableView {
                Label("供应商账号不能管理用户", systemImage: "person.crop.circle.badge.xmark").accessibilityIdentifier("users.vendor")
            }
        } else if let list = model.userList {
            UserListContent(list: list, searchText: $searchText, onCreate: openCreate, onQuickTopup: openQuickTopup)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "邮箱、用户名或备注")
                .refreshable { await list.refresh() }
                .task { await list.loadIfNeeded() }
                .task(id: searchText) { await search(searchText, in: list) }
                .task(id: shouldPoll) { await poll(list) }
                .onAppear { visible = true }
                .onDisappear { visible = false }
                .onChange(of: router.selectedTab) { _, tab in enteredTab(tab, list: list) }
                // A read stopped by the background is read again on return (D18); a list refused while compliance was pending
                // reads again once it is accepted (00 §1.10).
                .onChange(of: model.foregroundRevision) { _, _ in Task { await list.refresh() } }
                .onChange(of: model.securityPrompts.complianceRevision) { _, _ in Task { await list.refresh() } }
        } else {
            ProgressView()
        }
    }

    /// 30 §5.1: + and the empty state push the new user page; a creation marks the list to read its first page on return.
    private func openCreate() { router.push(.userNew) }
    /// 30 §1.1: a user awaiting reconciliation opens the detail; any other opens the top-up keypad.
    private func openQuickTopup(_ entry: QuickTopupEntry) {
        if entry.isPending { router.push(.user(id: entry.id)) }
        else { router.present(.balanceKeypad(userID: entry.id, mode: .topup)) }
    }
    private func search(_ text: String, in list: UserListModel) async {
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        await list.search(text)
    }
    /// Checks again on waking: a refresh that ended during the sleep (the first load, entering the tab, the foreground, a pull)
    /// or a new failure moved the next one (30 §1.6, 00 §4.6).
    private func poll(_ list: UserListModel) async {
        guard shouldPoll else { return }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(max(1, list.nextAutoRefreshDelay(now: Date())))) } catch { return }
            if list.nextAutoRefreshDelay(now: Date()) <= 0 { await list.refresh() }
        }
    }
    /// Entering the tab reads again; coming back from a pushed page does not (30 §1.6).
    private func enteredTab(_ tab: MainTab, list: UserListModel) {
        guard tab == .users else { return }
        _ = router.takeIntent(for: .users)
        Task { await list.refresh() }
    }
}

private struct UserListContent: View {
    let list: UserListModel
    @Binding var searchText: String
    let onCreate: () -> Void
    let onQuickTopup: @MainActor (QuickTopupEntry) -> Void
    @Environment(\.sessionContext) private var session

    private static let rowInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16)
    private var isSearching: Bool { !list.query.isEmpty || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        let display = list.listState.display
        let entries = isSearching ? [] : list.quickTopupEntries
        List {
            if case .value(_, let at, _, true) = display { banner(updatedAt: at) }
            if case .value = display, !entries.isEmpty {
                Section {
                    QuickTopupStrip(entries: entries, onSelect: onQuickTopup)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            switch display {
            case .placeholder:
                Section { ForEach(0..<4, id: \.self) { _ in UserRowSkeleton().listRowInsets(Self.rowInsets) } }
            case .value(let snapshot, _, _, _) where !snapshot.rows.isEmpty:
                Section { rows(snapshot.rows); nextPageFooter } header: { UserListLegend() }
            default:
                EmptyView()
            }
        }
        .overlay { emptyOrFailed(display) }
    }

    @ViewBuilder private func rows(_ users: [AdminUser]) -> some View {
        let pending = list.pendingUserIDs
        let positions = RailPosition.positions(of: users) { pending.contains($0.id) }
        ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
            let row = UserRow(user: user, today: list.todayCell(for: user.id), mark: list.mark(for: user, pendingUserIDs: pending),
                              railPosition: positions[index])
            NavigationLink(value: AppRoute.user(id: user.id)) { row }
                .accessibilityLabel(Text(row.spokenLabel))
                .accessibilityIdentifier("user.\(user.id)")
                .listRowInsets(Self.rowInsets)
                .onAppear { if index == users.count - 1 { Task { await list.loadNextPage() } } }
        }
    }
    @ViewBuilder private var nextPageFooter: some View {
        switch list.nextPage {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("users.more.loading")
        case .failed:
            Button("加载更多失败 · 重试") { Task { await list.retryNextPage() } }
                .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("users.more.retry")
        case .idle:
            EmptyView()
        }
    }
    /// 30 §1.5 刷新失败、已有旧数据: the time of the data shown, in the site's clock and zone.
    private func banner(updatedAt: Date?) -> some View {
        let site = session?.site
        let title = UserListPresentation.staleBanner(updatedAt: updatedAt.map { $0.addingTimeInterval(site?.clockOffset ?? 0) },
                                                     timeZone: site?.serverTimeZone.timeZone ?? .current)
        return Section {
            StatusBanner(tone: .caution, systemImage: "exclamationmark.triangle", title: title, detail: list.refreshState.throttleMessage(at: Date())) {
                Button("重试") { Task { await list.refresh() } }.frame(minHeight: 44).accessibilityIdentifier("users.banner.retry")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("users.banner")
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }
    @ViewBuilder private func emptyOrFailed(_ display: BlockDisplay<UserListSnapshot>) -> some View {
        switch display {
        case .failed where list.failure == .forbidden:
            ContentUnavailableView {
                Label("当前身份不能管理用户", systemImage: "person.crop.circle.badge.exclamationmark").accessibilityIdentifier("users.forbidden")
            }
        case .failed(let reason):
            ContentUnavailableView {
                Label("加载用户失败", systemImage: "exclamationmark.triangle").accessibilityIdentifier("users.error")
            } description: { Text(reason ?? "") } actions: {
                Button("重试") { Task { await list.refresh() } }.buttonStyle(.borderedProminent).accessibilityIdentifier("users.error.retry")
            }
        case .value(let snapshot, _, _, _) where snapshot.rows.isEmpty && list.query.isEmpty:
            ContentUnavailableView {
                Label("还没有用户", systemImage: "person.2").accessibilityIdentifier("users.empty")
            } actions: {
                Button("新建用户", action: onCreate).buttonStyle(.borderedProminent).accessibilityIdentifier("users.empty.create").readOnlyGate()
            }
        case .value(let snapshot, _, _, _) where snapshot.rows.isEmpty:
            ContentUnavailableView {
                Label(UserListPresentation.noMatchText(query: list.query), systemImage: "magnifyingglass").accessibilityIdentifier("users.search.empty")
            } actions: {
                Button("清除搜索") { searchText = "" }.accessibilityIdentifier("users.search.clear")
            }
        default:
            EmptyView()
        }
    }
}

/// 30 §1.3 列表头: the three marks on the left, “余额 / 今日消费” on the right.
private struct UserListLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach([UserListMark.lowBalance, .pending, .disabled], id: \.self) { mark in
                HStack(spacing: 4) { UserListMarkGlyph(mark: mark); Text(mark.label) }
            }
            Spacer(minLength: 8)
            Text("余额 / 今日消费")
        }
        .font(.caption)
        .foregroundStyle(Palette.ink2)
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("users.legend")
    }
}
