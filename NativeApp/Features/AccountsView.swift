import SwiftUI
import Sub2Core

/// 20 §1: the account tab, platform sections of three-line rows under the filter chips. Data and timers are AccountListModel
/// (S2-03), one per session: the tabs are rebuilt with the session. `initialGroupID` is the group page's transitional entry
/// (“查看与管理分组账号”, X32: removed in S5-13); it reads that group's accounts and pushes details itself.
struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: AccountListModel?
    /// 20 §1.4 row swipe; made with the store, whose rows it updates.
    @State private var actions: AccountActions?
    @State private var hasActivated = false
    /// The root disappeared with an empty stack: the tab was left, so the next appearance enters it again (20 §1.6).
    @State private var leftTab = false
    /// Moves “N 分钟前更新” forward.
    @State private var clockTick = Date()
    /// The transitional entry pushes details the way it was pushed itself; changing the path would pop the group page.
    @State private var openedAccountID: Int?
    private let initialGroupID: Int?

    init(initialGroupID: Int? = nil) { self.initialGroupID = initialGroupID }

    var body: some View {
        List {
            if let store { content(store) } else { AccountListSkeleton() }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle(AccountListChrome.title)
        .navigationSubtitle(subtitle)
        .navigationDestination(item: $openedAccountID) { AccountDestination(id: $0) }
        .refreshable { await store?.pullToRefresh() }
        .onAppear(perform: appeared)
        .onDisappear(perform: disappeared)
        .onChange(of: router.pendingIntent) { _, _ in applyIntent() }
        .onChange(of: model.foregroundRevision) { _, _ in Task { await store?.foregroundResumed() } }
        // A list that failed while compliance was pending reads again once it is accepted (00 §1.10).
        .onChange(of: model.securityPrompts.complianceRevision) { _, _ in Task { await store?.reload() } }
        .task(id: scenePhase == .active) { await tickClock() }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ store: AccountListModel) -> some View {
        switch store.list {
        case .idle, .loading(nil, _):
            AccountListSkeleton()
        case .failed(let reason, nil, _):
            AccountListFailurePage(reason: reason) { Task { await store.reload() } }
        case .disabled:
            AccountListFailurePage(reason: nil) { Task { await store.reload() } }
        default:
            chips(store)
            if case .failed = store.list { staleBanner(store) }
            if store.sections.isEmpty {
                AccountListEmptyCard()
            } else {
                let names = groupNames
                ForEach(store.sections) { platformSection(store, $0, names: names) }
            }
            footer(store)
        }
    }

    private func chips(_ store: AccountListModel) -> some View {
        let selected = store.platform.isEmpty ? nil : store.platform
        let summary = store.usableSummary
        let menu = AccountListChrome.platformMenu(summary: summary?.platforms, loaded: store.rows, selected: selected,
                                                  allCount: summary?.totals.total ?? (selected == nil ? store.counts?.all : nil), catalog: store.catalog)
        let counts = Dictionary(uniqueKeysWithValues: AccountListChip.allCases.compactMap { chip in store.chipCount(chip).map { (chip, $0) } })
        return AccountChipsBar(chip: store.chip, counts: counts, platform: selected,
                               platformName: selected.map { AccountNaming.platformName($0, catalog: store.catalog) }, menu: menu,
                               onChip: { chip in Task { await store.select(chip) } },
                               onPlatform: { platform in Task { await store.select(platform: platform ?? "") } })
            .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
    }

    private func staleBanner(_ store: AccountListModel) -> some View {
        StatusBanner(tone: .neutral, systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                     title: AccountListChrome.staleBanner(updatedAt: store.list.updatedAt, timeZone: serverZone)) {
            Button("重试") { Task { await store.reload() } }
                .buttonStyle(.borderless).frame(minHeight: 44).accessibilityIdentifier("accounts.banner.retry")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accounts.banner")
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
        .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
    }

    @ViewBuilder
    private func platformSection(_ store: AccountListModel, _ section: AccountPlatformSection, names: [Int: String]) -> some View {
        let collapsed = store.isCollapsed(section.platform)
        Section {
            AccountSectionHeader(title: AccountNaming.platformName(section.platform, catalog: store.catalog), section: section, isCollapsed: collapsed) {
                withAnimation(.snappy) { store.toggleCollapsed(section.platform) }
            }
            .accessibilityIdentifier("accounts.section.\(section.platform)")
            .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
            if !collapsed {
                ForEach(railRows(section.rows)) { row($0, store: store, names: names) }
            }
        }
    }

    private func row(_ entry: AccountRailRow, store: AccountListModel, names: [Int: String]) -> some View {
        Button { open(entry.account) } label: {
            AccountRow(account: entry.account,
                       today: AccountTodayCell(stats: store.todayStats(for: entry.id), unavailable: store.isTodayUnavailable(for: entry.id)),
                       context: AccountRowContext(omit: .platform), railPosition: entry.position, groupName: { names[$0] },
                       catalog: store.catalog, onCountdownElapsed: { Task { await store.countdownElapsed() } })
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("account.\(entry.id)")
        .accountScheduleSwipe(entry.account, actions: actions, now: serverNow, isReadOnly: session?.isReadOnlyToken ?? true)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Palette.surface)
        .listRowSeparatorTint(Palette.hairline)
    }

    @ViewBuilder
    private func footer(_ store: AccountListModel) -> some View {
        if store.isLoadingMore {
            HStack(spacing: 8) {
                ProgressView()
                Text(AccountListChrome.loadingMoreText).font(.footnote).foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("accounts.loading-more")
            .listRowSeparator(.hidden).listRowBackground(Palette.canvas)
        }
        if let note = store.overflowNote {
            Text(note).font(.footnote).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("accounts.cap-note")
                .listRowSeparator(.hidden).listRowBackground(Palette.canvas)
        }
    }

    /// 00 §8.1: adjacent rows that draw a capsule join into one rail within a section.
    private func railRows(_ rows: [UpstreamAccount]) -> [AccountRailRow] {
        let now = serverNow
        let positions = RailPosition.positions(of: rows) { AccountDisplayState($0, now: now).tone.drawsRail }
        return zip(rows, positions).map { AccountRailRow(account: $0, position: $1) }
    }

    // MARK: - Navigation, intents and lifecycle

    private func open(_ account: UpstreamAccount) {
        if initialGroupID == nil { router.push(.account(id: account.id)) } else { openedAccountID = account.id }
    }

    private func appeared() {
        let current = store ?? makeStore()
        current.setVisible(true)
        if !hasActivated || leftTab {
            hasActivated = true
            leftTab = false
            Task { await current.activate() }
        }
        applyIntent()
    }
    private func disappeared() {
        store?.setVisible(false)
        leftTab = initialGroupID == nil && router.path(for: .accounts).isEmpty
    }
    /// A pending intent picks the first query, so the list is read once.
    private func makeStore() -> AccountListModel {
        let selection = initialGroupID == nil ? takeSelection(fixture: true) : nil
        let made = AccountListModel(model: model, chip: selection?.chip ?? .all, platform: selection?.platform ?? "", groupID: initialGroupID)
        store = made
        // 20 §5.6: a write's account replaces its row, then the list is read again.
        actions = AccountActions(model: model, onChange: { [weak made] in made?.applyWrite($0) },
                                 onMissing: { [weak made] in made?.noteMissing(id: $0) })
        return made
    }
    /// 10 §0.7-4: the tab's root takes the intent once. `-ui-testing` may start the session with one (DemoData.AccountFixture.intent).
    private func applyIntent() {
        guard initialGroupID == nil, let store, let selection = takeSelection(fixture: false) else { return }
        Task { await store.select(selection.chip, platform: selection.platform ?? "") }
    }
    private func takeSelection(fixture: Bool) -> AccountsListSelection? {
        if let intent = router.takeIntent(for: .accounts) { return intent.accountsListSelection }
        guard fixture, model.isUITesting else { return nil }
        return DemoData.AccountFixture.launchIntent(arguments: ProcessInfo.processInfo.arguments)?.accountsListSelection
    }

    private func tickClock() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            clockTick = Date()
        }
    }

    private var subtitle: String {
        let site = model.activeProfile?.name ?? ""
        guard let store else { return site }
        _ = clockTick
        return AccountListChrome.subtitle(site: site, total: store.counts?.all, updatedAt: store.list.updatedAt,
                                          isRefreshing: store.list.isLoading && store.list.value != nil, now: serverNow, timeZone: serverZone)
    }
    /// C-10 names; a group the directory does not know falls back to the row's own name or “#id”.
    private var groupNames: [Int: String] {
        Dictionary((model.groupDirectory?.groups ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }
    private var serverNow: Date { session?.client.serverClock.now() ?? Date() }
    private var serverZone: TimeZone { session?.site.serverTimeZone.timeZone ?? .current }
}

private struct AccountRailRow: Identifiable {
    let account: UpstreamAccount
    let position: RailPosition?
    var id: Int { account.id }
}

/// 20 §1.2 / §1.4: 需处理 · 全部 · 受限 · 暂停·停用 and the 平台 ▾ menu; a picked platform leads the row as a removable token and the
/// row scrolls back to it.
private struct AccountChipsBar: View {
    let chip: AccountListChip
    let counts: [AccountListChip: Int]
    let platform: String?
    let platformName: String?
    let menu: [AccountListChrome.PlatformMenuItem]
    let onChip: @MainActor (AccountListChip) -> Void
    let onPlatform: @MainActor (String?) -> Void
    private static let tokenID = "token"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let platformName { token(platformName).id(Self.tokenID) }
                    ForEach(AccountListChip.allCases) { chipButton($0).id($0.rawValue) }
                    platformMenu
                }
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 2, trailing: 16))
            }
            .onChange(of: platform) { _, _ in
                withAnimation { proxy.scrollTo(platformName == nil ? AccountListChip.needs.rawValue : Self.tokenID, anchor: .leading) }
            }
        }
    }

    private func chipButton(_ item: AccountListChip) -> some View {
        let count = counts[item]
        return Button { onChip(item) } label: {
            AccountChipLabel(title: item.title, count: count, isOn: chip == item, alerts: item == .needs && (count ?? 0) > 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(item.title) \(DisplayFormat.grouped($0))" } ?? item.title)
        .accessibilityAddTraits(chip == item ? .isSelected : [])
        .accessibilityIdentifier("accounts.chip.\(item.rawValue)")
    }

    private func token(_ name: String) -> some View {
        Button { onPlatform(nil) } label: {
            AccountChipLabel(title: AccountListChrome.platformToken(name), count: nil, isOn: true, alerts: false, trailingSymbol: "xmark")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AccountListChrome.platformTokenSpoken(name))
        .accessibilityIdentifier("accounts.chip.platform-token")
    }

    /// Like the site menu: a toggle draws the check, the count is the item's second line.
    private var platformMenu: some View {
        Menu {
            ForEach(menu) { item in
                Toggle(isOn: Binding(get: { item.platform == platform }, set: { if $0 { onPlatform(item.platform) } })) {
                    Text(item.title)
                    if let detail = item.detail { Text(detail) }
                }
            }
        } label: {
            AccountChipLabel(title: "平台", count: nil, isOn: false, alerts: false, trailingSymbol: "chevron.down")
        }
        .accessibilityLabel("平台")
        .accessibilityIdentifier("accounts.chip.platform")
    }
}

/// Design `.chip`: 34pt capsule, sunken when off, accent wash and edge when on; 需处理 with accounts writes its number in red.
private struct AccountChipLabel: View {
    let title: String
    let count: Int?
    let isOn: Bool
    let alerts: Bool
    var trailingSymbol: String?
    @ScaledMetric(relativeTo: .subheadline) private var size = 14.5
    @ScaledMetric(relativeTo: .footnote) private var countSize = 13.5
    @ScaledMetric(relativeTo: .subheadline) private var height = 34.0

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: size))
            if let count {
                Text(DisplayFormat.grouped(count)).font(.system(size: countSize, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(isOn ? Palette.accent : alerts ? Tone.critical.ink : Palette.ink2)
            }
            if let trailingSymbol { Image(systemName: trailingSymbol).font(.system(size: countSize * 0.85, weight: .bold)) }
        }
        .lineLimit(1)
        .foregroundStyle(isOn ? Palette.accent : Palette.ink1)
        .padding(.horizontal, 13)
        .frame(height: height)
        .background(isOn ? Palette.accentWash : Palette.sunken, in: Capsule())
        .overlay { if isOn { Capsule().strokeBorder(Palette.accent, lineWidth: 1) } }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// 20 §1.3 platform header: “Anthropic 4”, the right-side flags, and a chevron; the whole header collapses the section.
/// Its numbers describe the whole platform whatever the chip.
private struct AccountSectionHeader: View {
    let title: String
    let section: AccountPlatformSection
    let isCollapsed: Bool
    let toggle: @MainActor () -> Void

    var body: some View {
        Button { toggle() } label: {
            HStack(spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1).lineLimit(1)
                Text(DisplayFormat.grouped(section.total)).font(.footnote.weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink3)
                Spacer(minLength: 4)
                ForEach(section.flags, id: \.text) { ToneBadge(text: $0.text, tone: $0.tone) }
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .frame(width: 24, height: 24)
            }
            .padding(EdgeInsets(top: 10, leading: 16, bottom: isCollapsed ? 10 : 6, trailing: 12))
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(section.spokenSummary)，\(isCollapsed ? "已收起" : "已展开")")
    }
}

/// 20 §1.5 first load: chip placeholders and three skeleton rows; no headers.
private struct AccountListSkeleton: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { _ in Capsule().fill(Palette.sunken).frame(width: 72, height: 34) }
        }
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
        .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in AccountRowSkeleton() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在读取账号")
        .accessibilityIdentifier("accounts.skeleton")
        .listRowInsets(EdgeInsets()).listRowBackground(Palette.surface)
    }
}

/// 20 §1.5: a list that failed before showing anything.
private struct AccountListFailurePage: View {
    let reason: String?
    let retry: @MainActor () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(AccountListChrome.failureTitle, systemImage: "exclamationmark.triangle")
        } description: {
            if let reason { Text(reason) }
        } actions: {
            Button("重试") { retry() }.buttonStyle(.bordered).accessibilityIdentifier("accounts.failure.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accounts.failure")
        .listRowSeparator(.hidden).listRowBackground(Palette.canvas)
    }
}

/// 20 §1.3: no account under the chip and platform.
private struct AccountListEmptyCard: View {
    var body: some View {
        Text(AccountListChrome.emptyText)
            .font(.subheadline).foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(EdgeInsets(top: 4, leading: 16, bottom: 16, trailing: 16))
            .accessibilityIdentifier("accounts.empty")
            .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
    }
}
