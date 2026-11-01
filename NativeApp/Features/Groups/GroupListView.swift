import SwiftUI
import Sub2Core

/// 50 §1 (`.groups(segment:)`): every group of the session's GroupStore in three sections, searched locally. The view only
/// decides when to read: on appear unless the list is fresh, on pull, every 60 seconds while it is shown in the foreground, on
/// returning to the foreground (D18) and after compliance. A segment scrolls to its section once the first list arrives (X39).
struct GroupListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""
    @State private var visible = false
    /// 50 §0.5's actions of the rows (S5-05); made once the page shows, with the session's tabs.
    @State private var actions: GroupActions?
    private let segment: GroupListSegment?

    init(segment: GroupListSegment? = nil) { self.segment = segment }

    private var permissions: GroupPermissions { GroupPermissions(me: session?.site.me, isReadOnlyToken: session?.isReadOnlyToken ?? false) }
    private var shouldPoll: Bool { visible && scenePhase == .active }
    /// Under `-ui-testing` a list opened without a segment takes `-ui-group-segment`'s.
    private var targetSegment: GroupListSegment? { segment ?? (model.isUITesting ? GroupFixtures.launchSegment() : nil) }
    /// “<站点名> · 5 个分组无可用账号”; only the site before the first list arrives.
    private var subtitle: String {
        let site = model.activeProfile?.name ?? ""
        guard let store = model.groupStore, store.list.value != nil else { return site }
        return GroupListSections.subtitle(siteName: site, rows: store.rows)
    }

    var body: some View {
        content
            .groupActionsHost(actions)
            .task { if actions == nil { actions = GroupActions(model: model, router: router) } }
            .navigationTitle("分组")
            .navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(subtitle)
            .toolbar {
                if permissions.canCreate.isShown {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("新建分组", systemImage: "plus", action: openCreate).readOnlyGate(showsCaption: false)
                            .accessibilityIdentifier("groups.create")
                    }
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let store = model.groupStore {
            GroupListContent(store: store, permissions: permissions, query: searchText, segment: targetSegment, actions: actions,
                             onCreate: openCreate, onEdit: openEdit)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: GroupListSections.searchPrompt)
                .refreshable { await store.refreshAll() }
                .task { await store.loadIfNeeded() }
                .task(id: shouldPoll) { await poll(store) }
                .onAppear { visible = true }
                .onDisappear { visible = false }
                .onChange(of: model.foregroundRevision) { _, _ in Task { await store.refreshAll() } }
                .onChange(of: model.securityPrompts.complianceRevision) { _, _ in Task { await store.refreshAll() } }
        } else {
            ProgressView()
        }
    }

    /// 50 §1.4: + and the empty state's 新建分组 open the group editor (S5-10 replaces the old one behind it).
    private func openCreate() { router.present(.groupEdit(id: nil)) }
    private func openEdit(_ id: Int) { router.present(.groupEdit(id: id)) }
    /// Checks again on waking: a refresh that ended during the sleep or a new failure moved the next one (00 §4.6); a list read
    /// already out (the pull, the foreground) is not followed by another.
    private func poll(_ store: GroupStore) async {
        guard shouldPoll else { return }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(max(1, store.nextAutoRefreshDelay(now: Date())))) } catch { return }
            if store.nextAutoRefreshDelay(now: Date()) <= 0, !store.list.isLoading { await store.refreshAll() }
        }
    }
}

private struct GroupListContent: View {
    let store: GroupStore
    let permissions: GroupPermissions
    let query: String
    let segment: GroupListSegment?
    let actions: GroupActions?
    let onCreate: () -> Void
    let onEdit: (Int) -> Void
    @State private var scrolledToSegment = false

    private static let rowInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16)
    private static func rowID(_ id: Int) -> String { "group.row.\(id)" }
    private var sections: [GroupListSection] { GroupListSections.sections(store.rows, query: query, catalog: store.catalog) }

    var body: some View {
        let display = store.list.display, sections = self.sections
        ScrollViewReader { proxy in
            List {
                if case .value(_, _, _, true) = display { refreshStrip }
                switch display {
                case .placeholder:
                    Section { ForEach(0..<3, id: \.self) { _ in GroupRowSkeleton().listRowInsets(Self.rowInsets) } }
                case .failed:
                    Section {
                        BlockFailureRow(state: store.list, error: store.listError, occurredAt: store.listErrorAt, refresh: store.listRefresh,
                                        id: "groups.list", resendsAfterWait: false, retry: retry)
                    }
                case .value where !sections.isEmpty:
                    ForEach(sections) { section in
                        Section { rows(section) } header: { GroupSectionHeader(section: section) }
                    }
                    Section {} footer: {
                        Text(GroupListSections.footnote).font(.footnote).foregroundStyle(Palette.ink3).accessibilityIdentifier("groups.footnote")
                    }
                default:
                    EmptyView()
                }
            }
            .overlay { emptyOrNoMatch(display, sections: sections) }
            .task(id: store.revision) { await scrollToSegment(proxy) }
        }
    }

    @ViewBuilder private func rows(_ section: GroupListSection) -> some View {
        let positions = RailPosition.positions(of: section.rows) { $0.health.tone.drawsRail }
        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, item in
            let row = GroupRow(group: item.group, usage: store.todaySummary(for: item.id), buckets: item.buckets, health: item.health,
                               railPosition: positions[index], showsBillingLine: permissions.showsBillingRow, catalog: store.catalog)
            NavigationLink(value: AppRoute.group(id: item.id)) { row }
                .accessibilityLabel(Text(row.spokenLabel))
                .accessibilityIdentifier(Self.rowID(item.id))
                .listRowInsets(Self.rowInsets)
                .id(Self.rowID(item.id))
                .groupActionSwipe(item.group, actions: actions, permissions: permissions) { onEdit(item.id) }
                .contextMenu {
                    if let actions { GroupActionMenuItems(group: item.group, actions: actions, permissions: permissions) { onEdit(item.id) } }
                }
        }
    }
    /// 50 §1.5 有缓存时刷新失败: the rows stay under one thin line; during a 429 wait it counts down instead.
    private var refreshStrip: some View {
        let now = Date()
        return Section {
            Button(action: retry) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tone.caution.base).accessibilityHidden(true)
                    Text(store.listRefresh.throttleMessage(at: now) ?? "刷新失败 · 重试").font(.footnote).foregroundStyle(Palette.ink1)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.listRefresh.allowsRequest(at: now))
            .accessibilityIdentifier("groups.refresh.retry")
            .listRowBackground(Tone.caution.wash)
        }
    }
    @ViewBuilder private func emptyOrNoMatch(_ display: BlockDisplay<[AdminGroup]>, sections: [GroupListSection]) -> some View {
        if case .value(let groups, _, _, _) = display, groups.isEmpty {
            ContentUnavailableView {
                Label(GroupListSections.empty, systemImage: GroupHealth.ok.systemImage).accessibilityIdentifier("groups.empty")
            } actions: {
                if permissions.canCreate.isShown {
                    Button("新建分组", action: onCreate).buttonStyle(.borderedProminent).accessibilityIdentifier("groups.empty.create").readOnlyGate()
                }
            }
        } else if case .value = display, sections.isEmpty {
            ContentUnavailableView {
                Label(GroupListSections.noMatches, systemImage: "magnifyingglass").accessibilityIdentifier("groups.search.empty")
            }
        }
    }
    private func retry() { Task { await store.refreshAll() } }
    /// Once, when the first list is shown: the section's first row a little below the top, so its header shows too.
    private func scrollToSegment(_ proxy: ScrollViewProxy) async {
        guard !scrolledToSegment, let segment, store.list.value != nil else { return }
        scrolledToSegment = true
        guard let first = sections.first(where: { $0.kind.rawValue == segment.rawValue })?.rows.first else { return }
        // The list lays its rows out first.
        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        proxy.scrollTo(Self.rowID(first.id), anchor: UnitPoint(x: 0.5, y: 0.4))
    }
}

/// 50 §1.3 段头 “需处理 6”.
private struct GroupSectionHeader: View {
    let section: GroupListSection

    var body: some View {
        HStack(spacing: 6) {
            Text(section.kind.title)
            Text(DisplayFormat.grouped(section.rows.count)).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.header)
        .accessibilityIdentifier("groups.section.\(section.kind.rawValue)")
    }
}
