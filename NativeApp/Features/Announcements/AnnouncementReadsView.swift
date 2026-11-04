import SwiftUI
import Sub2Core

/// 60 §18: who can see an announcement and who has read it. “已读情况” with the announcement's title as subtitle; the summary
/// bar, the search field, with `announcements.read_stats` 全部 / 已读 / 未读 and 只看符合条件, the sort menu, then one row per
/// user (a row opens the user). Read-only; nothing polls. AnnouncementReadsModel decides what to read; this view reports
/// appearing, pulls, the field and the filters.
struct AnnouncementReadsView: View {
    let announcementID: Int
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var reads: AnnouncementReadsModel?
    @State private var readsGeneration: UUID?

    var body: some View {
        content
            .navigationTitle(AnnouncementPresentation.readsTitle)
            .navigationSubtitle(reads?.title.map(AnnouncementPresentation.displayTitle) ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: session?.generation) { await appeared() }
            .task(id: reads?.refresh.notBefore) { await retryAfterWait() }
    }

    @ViewBuilder private var content: some View {
        if let reads {
            if reads.isGone {
                ContentUnavailableView(AnnouncementDetailPresentation.gone, systemImage: "trash")
                    .accessibilityElement(children: .combine).accessibilityIdentifier("announcementReads.gone")
            } else {
                AnnouncementReadsContent(reads: reads)
            }
        } else {
            ProgressView(AnnouncementReadsText.loading).frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("announcementReads.loading")
        }
    }

    /// A new session gets a new model; shown again (back from a user) it reads only what leaving cancelled.
    private func appeared() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        if readsGeneration != session.generation {
            let generation = session.generation
            reads = AnnouncementReadsModel(announcementID: announcementID, supportsReadStats: session.has(.announcementsReadStats),
                                           source: model.announcementReadsSource(for: session),
                                           isCurrent: { [weak model] in model?.sessionGeneration == generation })
            readsGeneration = generation
        }
        await reads?.start()
    }
    /// “请求过于频繁，N 秒后自动重试”: once the wait is over the page reads again (00 §2.7.2).
    private func retryAfterWait() async {
        guard let reads, let notBefore = reads.refresh.notBefore else { return }
        let wait = notBefore.timeIntervalSinceNow
        if wait > 0 { do { try await Task.sleep(for: .seconds(wait)) } catch { return } }
        await reads.reload()
    }
}

/// S6-19's own wording; everything else is AnnouncementPresentation's (S6D1-18).
private enum AnnouncementReadsText {
    static let loading = "正在加载…", noMatch = "没有匹配的用户", loadMoreFailed = "加载失败 · 重试", refreshFailed = "刷新失败 · 重试"
    static let readStateLabel = "已读状态", sortLabel = "排序"
}

private struct AnnouncementReadsContent: View {
    let reads: AnnouncementReadsModel
    @Environment(\.sessionContext) private var session

    var body: some View {
        List {
            Section {
                Text(reads.summaryText(serverTimeZone: zone)).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("announcementReads.summary")
                if reads.supportsReadStats { filters }
            }
            Section {
                rowsBody
            } header: {
                resultHeader
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: Binding(get: { reads.searchText }, set: { reads.searchChanged($0) }),
                    placement: .navigationBarDrawer(displayMode: .always), prompt: AnnouncementPresentation.readsSearchPrompt)
        .refreshable { await reads.reload() }
        .accessibilityIdentifier("announcementReads.list")
    }

    private var zone: TimeZone { session?.site.serverTimeZone.timeZone ?? .current }

    // MARK: Filters and sort

    @ViewBuilder private var filters: some View {
        Picker(AnnouncementReadsText.readStateLabel, selection: Binding(get: { reads.query.readState },
                                                                         set: { state in Task { await reads.setReadState(state) } })) {
            ForEach(AnnouncementReadStatusQuery.ReadState.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("announcementReads.state")
        Toggle(AnnouncementPresentation.eligibleOnlyTitle, isOn: Binding(get: { reads.query.eligibleOnly },
                                                                          set: { isOn in Task { await reads.setEligibleOnly(isOn) } }))
            .frame(minHeight: 44)
            .accessibilityIdentifier("announcementReads.eligibleOnly")
    }

    /// “找到 N 位” while searching or filtering, and the sort menu on the right.
    private var resultHeader: some View {
        HStack(spacing: 8) {
            if let found = reads.foundText {
                Text(found).monospacedDigit().accessibilityIdentifier("announcementReads.found")
            }
            Spacer(minLength: 8)
            sortMenu
        }
        .textCase(nil)
    }

    /// Like the account platform menu: a toggle draws the check, the direction is the item's second line.
    private var sortMenu: some View {
        let current = reads.query.effectiveSort
        return Menu {
            ForEach(reads.sorts, id: \.self) { sort in
                Toggle(isOn: Binding(get: { sort == current }, set: { if $0 { Task { await reads.setSort(sort) } } })) {
                    Text(sort.title)
                    Text(sort.detail)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down").accessibilityHidden(true)
                Text(current.title)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(AnnouncementReadsText.sortLabel + "：" + current.title)
        .accessibilityIdentifier("announcementReads.sort")
    }

    // MARK: Rows and states

    @ViewBuilder private var rowsBody: some View {
        switch reads.state.display {
        case .placeholder:
            ProgressView(AnnouncementReadsText.loading).frame(maxWidth: .infinity, minHeight: 120).listRowBackground(Color.clear)
                .accessibilityIdentifier("announcementReads.loading")
        case .failed(let reason):
            FailureView(message: reads.throttleMessage() ?? reason ?? "", retry: retry).listRowBackground(Color.clear)
                .accessibilityElement(children: .contain).accessibilityIdentifier("announcementReads.failure")
        case .value(let list, _, _, let updateFailed):
            if updateFailed { refreshFailedBanner }
            if list.rows.isEmpty {
                ContentUnavailableView(AnnouncementReadsText.noMatch, systemImage: "person.crop.circle.badge.questionmark")
                    .accessibilityElement(children: .combine).accessibilityIdentifier("announcementReads.empty")
                    .listRowBackground(Color.clear)
            } else {
                rows(list.rows)
                if list.hasMore { nextPageFooter }
            }
        case .disabled:
            EmptyView()
        }
    }

    @ViewBuilder private func rows(_ rows: [AnnouncementReadStatusRow]) -> some View {
        let now = session?.client.serverClock.now() ?? Date()
        ForEach(rows) { item in
            let row = AnnouncementReadRow(row: item, now: now, serverTimeZone: zone)
            NavigationLink(value: AppRoute.user(id: item.userID)) { row }
                .accessibilityLabel(Text(row.spokenLabel))
                .accessibilityIdentifier("announcementReads.row.\(item.userID)")
                .onAppear { Task { await reads.loadMoreIfNeeded(after: item.userID) } }
        }
    }

    /// 60 §18.3: a spinner and “滚到底自动加载下一页”, or “加载失败 · 重试”.
    @ViewBuilder private var nextPageFooter: some View {
        if reads.nextPage == .failed {
            Button(AnnouncementReadsText.loadMoreFailed) { Task { await reads.retryMore() } }
                .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("announcementReads.more.retry")
        } else {
            HStack(spacing: 8) {
                ProgressView()
                Text(AnnouncementPresentation.loadingMoreText).font(.footnote).foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("announcementReads.more")
            .listRowBackground(Color.clear)
        }
    }

    /// 00 §4.6: a failed refresh keeps the rows; tapping reads again (not during a 429 wait).
    private var refreshFailedBanner: some View {
        let detail = reads.throttleMessage()
        return Button { Task { await reads.reload() } } label: {
            StatusBanner(tone: .caution, systemImage: "exclamationmark.triangle", title: AnnouncementReadsText.refreshFailed, detail: detail)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(reads.state.isLoading || detail != nil)
        .accessibilityLabel([AnnouncementReadsText.refreshFailed, detail].compactMap { $0 }.joined(separator: "，"))
        .accessibilityIdentifier("announcementReads.refresh.retry")
        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
    }

    /// No retry during a 429 wait; the page reads again on its own when it ends.
    private var retry: (() -> Void)? {
        guard reads.throttleMessage() == nil else { return nil }
        return { Task { await reads.reload() } }
    }
}

extension AppModel {
    /// The site's roster, or under `-ui-testing` this session's AnnouncementDemoStore (shared with the list and the detail).
    func announcementReadsSource(for session: SessionContext) -> AnnouncementReadsSource {
        guard isUITesting else { return .live(session.client) }
        return .fixture(AnnouncementDemoStore.current(for: session.generation, base: session.client.serverClock.now()))
    }
}
