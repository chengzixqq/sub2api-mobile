import SwiftUI
import Sub2Core

/// 40 §6 使用记录: the route's scope and conditions come in; LogsStore, registered for this tab and route (C-13), decides what to
/// read. This view draws the segments, the capsules, the day sections and the states, and reports appearing, the foreground and
/// the ops switch. A row pushes `.request` with its record. `pushesInPlace` is the old group page's entry only (LegacyLogsEntry):
/// changing the path would pop that page, so the detail is pushed by the view and the store is not registered.
struct LogsView: View {
    static let title = "使用记录"
    static let loadingText = "正在读取记录…"
    static let keptRowsNote = "保留上次成功加载的记录"

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    private let route: LogsRoute
    /// X20：S4-20 删除 LegacyLogsEntry 时一并删除。
    private let pushesInPlace: Bool
    @State private var tab: MainTab?
    @State private var store: LogsStore?
    /// X20：S4-20 删除 LegacyLogsEntry 时一并删除。
    @State private var openedRequest: RequestRoute?
    @State private var pickingRange = false

    init(route: LogsRoute, pushesInPlace: Bool = false) { self.route = route; self.pushesInPlace = pushesInPlace }

    var body: some View {
        content
            .navigationTitle(Self.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(subtitle)
            // X20：S4-20 删除 LegacyLogsEntry 时一并删除。
            .navigationDestination(item: $openedRequest) { LogRouteDestination(route: .request($0)) }
            .sheet(isPresented: $pickingRange) { if let store { customRange(store) } }
            .onAppear(perform: appear)
            .onChange(of: model.sessionGeneration) { _, _ in appear() }
            .onDisappear { store?.disappeared() }
            // A read stopped by the background is read again on return (D18).
            .onChange(of: model.foregroundRevision) { _, _ in Task { await store?.foregroundResumed() } }
            .onChange(of: model.liveOps?.opsRevision) { _, _ in Task { await store?.opsAvailabilityChanged() } }
    }

    @ViewBuilder private var content: some View {
        if let store {
            LogsList(store: store, onOpen: open, onPickRange: { pickingRange = true })
        } else {
            ProgressView(Self.loadingText).frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("logs.loading")
        }
    }
    private var subtitle: String {
        let site = model.activeProfile?.name ?? ""
        return store?.subtitle(siteName: site, device: .current) ?? site
    }

    /// The read is not the view's task: a push may make the page disappear and appear again while page 1 is on its way, and
    /// cancelling it then would leave the list unread (D18 reads again on the foreground only).
    private func appear() {
        register()
        let store = store
        Task { await store?.appeared() }
    }
    /// Once per page and session (S0-11): the store found or made for this tab and route, kept in @State.
    private func register() {
        guard let session else { return }
        if let store, !store.isStale(currentGeneration: session.generation) { return }
        let model = model, route = route
        let make = { LogsStore(model: model, context: session, route: route) }
        guard !pushesInPlace, let pageStates = model.pageStates else { store = make(); return }
        let tab = self.tab ?? router.selectedTab
        self.tab = tab
        store = pageStates.state(PageStateKey.logs(route), tab: tab, prunedBy: router, make: make)
    }
    private func open(_ request: RequestRoute) {
        if pushesInPlace { openedRequest = request } else { router.push(.request(request)) }
    }
    private func customRange(_ store: LogsStore) -> some View {
        let now = store.serverNow()
        return LogCustomRangeSheet(initial: Self.bounds(store.currentWindow(), now: now), timeZone: store.timeZone, now: now) { preset in
            Task { await store.setTime(preset) }
        }
    }
    private static func bounds(_ window: LogTimeWindow, now: Date) -> (start: Date, end: Date) {
        guard case .range(let start, let end) = window else { return (now.addingTimeInterval(-86_400), now) }
        return (start, end)
    }
}

private struct LogsList: View {
    let store: LogsStore
    let onOpen: @MainActor (RequestRoute) -> Void
    let onPickRange: @MainActor () -> Void

    private static let controlInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)

    var body: some View {
        List {
            Section {
                segments
                capsules
            }
            if store.showsOpsNotice {
                OpsDisabledNotice(style: .emptyState, notesDataGap: true)
                    .frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
            } else {
                rows
                footer
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .refreshable { await store.reload() }
    }

    private var segments: some View {
        Picker("记录类型", selection: Binding(get: { store.scope }, set: { scope in Task { await store.select(scope) } })) {
            ForEach(LogScope.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("logs.mode")
        .listRowInsets(Self.controlInsets).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
    }
    /// 40 §6.3: the time menu, then the conditions as they apply (S4-05b makes them removable).
    private var capsules: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                LogTimeMenu(title: store.timeTitle(), selection: store.time,
                            onPick: { preset in Task { await store.setTime(preset) } }, onCustom: onPickRange)
                ForEach(store.chips.chips) { chip in
                    LogChipLabel(chip.isMonospaced ? chip.kind.label + "：" : chip.text, monospacedValue: chip.isMonospaced ? chip.value : nil,
                                 isOn: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(chip.text)
                        .accessibilityIdentifier("logs.chip.\(chip.kind.rawValue)")
                }
                // S4-07：“+ 筛选”接在这里。
            }
            .padding(.horizontal, 16)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0)).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
    }

    @ViewBuilder private var rows: some View {
        if store.isFirstLoading {
            ProgressView(LogsView.loadingText).frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("logs.loading").listRowSeparator(.hidden).listRowBackground(Palette.canvas)
        } else if let message = store.emptyMessage {
            LogsEmptyState(message: message).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
        } else {
            let lastID = store.sections.last?.rows.last?.id
            ForEach(store.sections) { section in
                Section {
                    sectionRows(section, lastID: lastID)
                } header: {
                    NumberedSectionHeader(title: section.title, meta: LogSections.headerTrailing, id: "logs.section.\(section.id)")
                }
            }
        }
    }
    /// 00 §8.1: neighbouring rows with a capsule join into one rail within a day.
    private func sectionRows(_ section: LogSection<LogRowPresentation>, lastID: Int?) -> some View {
        let positions = section.railPositions
        return ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
            rowButton(row, position: positions[index])
                .onAppear { if row.id == lastID { Task { await store.loadMoreIfNeeded(after: row.id) } } }
        }
    }
    private func rowButton(_ row: LogRowPresentation, position: RailPosition?) -> some View {
        let content = LogRow(row, railPosition: position)
        return Button { if let request = store.requestRoute(for: row) { onOpen(request) } } label: {
            HStack(spacing: 8) {
                content
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
            }
            .padding(.trailing, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(content.spokenLabel))
        .accessibilityIdentifier("logs.row.\(store.scope.rawValue).\(row.id)")
        .listRowInsets(EdgeInsets())
        .listRowBackground(Palette.surface)
        .listRowSeparatorTint(Palette.hairline)
    }

    /// The next page loading, or “加载失败 · 重试” at the end; the rows already shown stay (40 §6.5).
    @ViewBuilder private var footer: some View {
        if store.isLoadingMore || store.failure != nil {
            Section {
                if store.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("logs.more.loading")
                }
                if let failure = store.failure {
                    BlockFailureRow(error: failure.error, occurredAt: failure.occurredAt, refresh: store.refresh, id: "logs.list") {
                        Task { await store.retry() }
                    }
                    if store.hasRows {
                        Text(LogsView.keptRowsNote).font(.footnote).foregroundStyle(Palette.ink3).accessibilityIdentifier("logs.list.kept")
                    }
                }
            }
            .listRowInsets(Self.controlInsets).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
        }
    }
}

/// 40 §6.5: a large “—” over the sentence. S4-05b adds “清除筛选” under it.
private struct LogsEmptyState: View {
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Text(DisplayFormat.missing).font(.system(size: 28, weight: .medium)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
            Text(message).font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityIdentifier("logs.empty")
    }
}
