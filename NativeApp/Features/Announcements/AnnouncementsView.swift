import SwiftUI
import Sub2Core

/// 60 §15: the announcement list. “公告” with “<站点名> · N 条”, compose on the right (hidden for a read-only token, C-1), the four
/// segments and the rows; a row pushes its detail. No swipe actions, no writes, no polling. AnnouncementListModel decides when
/// to read; this view reports appearing, the segment, pulls, the foreground, compliance and `model.announcementChanges`.
struct AnnouncementsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @State private var list: AnnouncementListModel?
    @State private var listGeneration: UUID?
    @State private var selection: AnnouncementStatus?

    init(status: AnnouncementStatus?) { _selection = State(initialValue: status) }

    private var canCompose: Bool { session.map { !$0.isReadOnlyToken } ?? false }

    var body: some View {
        content
            .navigationTitle("公告")
            .navigationSubtitle(AnnouncementPresentation.navigationSubtitle(siteName: model.activeProfile?.name ?? "", count: list?.subtitleCount))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canCompose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("新建公告", systemImage: "square.and.pencil", action: compose).accessibilityIdentifier("announcements.compose")
                    }
                }
            }
            .task(id: session?.generation) { await appeared() }
            .task(id: session?.generation) { await model.groupDirectory?.ensureLoaded() }
            .task(id: list?.refresh.notBefore) { await retryAfterWait() }
            .onDisappear { list?.disappeared() }
            .onChange(of: selection) { _, status in Task { await list?.select(status) } }
            .onChange(of: model.announcementChanges.revision) { _, revision in Task { await list?.revisionChanged(revision) } }
            // A read stopped by the background is read again on return (D18); a list refused while compliance was pending reads
            // again once it is accepted (00 §1.10).
            .onChange(of: model.foregroundRevision) { _, _ in Task { await list?.foregroundResumed() } }
            .onChange(of: model.securityPrompts.complianceRevision) { _, _ in Task { await list?.invalidate() } }
    }

    @ViewBuilder private var content: some View {
        if let list {
            AnnouncementListContent(list: list, selection: $selection, canCompose: canCompose, onCompose: compose)
        } else {
            ProgressView("正在读取公告…").frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("announcements.loading")
        }
    }

    private func compose() { router.present(.announcementEdit(id: nil)) }

    /// A new session gets a new list; then it reads unless what it shows is recent (60 §15.6).
    private func appeared() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        if listGeneration != session.generation {
            let generation = session.generation
            list = AnnouncementListModel(source: model.announcementListSource(for: session), status: selection,
                                         includeReadStats: session.has(.announcementsReadStats),
                                         isCurrent: { [weak model] in model?.sessionGeneration == generation })
            listGeneration = generation
        }
        await list?.appeared(revision: model.announcementChanges.revision)
    }
    /// “请求过于频繁，N 秒后自动重试”: once the wait is over, a shown list reads again (00 §2.7.2).
    private func retryAfterWait() async {
        guard let list, let notBefore = list.refresh.notBefore else { return }
        let wait = notBefore.timeIntervalSinceNow
        if wait > 0 { do { try await Task.sleep(for: .seconds(wait)) } catch { return } }
        await list.invalidate()
    }
}

private struct AnnouncementListContent: View {
    let list: AnnouncementListModel
    @Binding var selection: AnnouncementStatus?
    let canCompose: Bool
    let onCompose: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session

    var body: some View {
        let display = list.state.display
        List {
            Section { segments.listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)).listRowBackground(Color.clear) }
            if case .value(_, _, _, true) = display { refreshFailedBanner }
            switch display {
            case .placeholder:
                ProgressView("正在读取公告…").frame(maxWidth: .infinity, minHeight: 120).listRowBackground(Color.clear)
                    .accessibilityIdentifier("announcements.loading")
            case .failed(let reason):
                FailureView(message: list.throttleMessage() ?? reason ?? "", retry: retry).listRowBackground(Color.clear)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("announcements.failure")
            case .value(let rows, _, _, _) where rows.isEmpty:
                emptyState
            case .value(let rows, _, _, _):
                Section { self.rows(rows); nextPageFooter }
            case .disabled:
                EmptyView()
            }
        }
        .refreshable { await list.reload() }
        .accessibilityIdentifier("announcements.list")
    }

    private var segments: some View {
        Picker("公告分段", selection: $selection) {
            ForEach(AnnouncementSegments.order, id: \.self) { status in
                Text(AnnouncementPresentation.segmentTitle(status, counts: list.counts)).tag(status)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("announcements.segment")
    }

    @ViewBuilder private func rows(_ items: [Announcement]) -> some View {
        let now = session?.client.serverClock.now() ?? Date()
        let zone = session?.site.serverTimeZone.timeZone ?? .current
        let supportsReadStats = session?.has(.announcementsReadStats) ?? false
        let names = Dictionary((model.groupDirectory?.groups ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        ForEach(items) { item in
            let row = AnnouncementRow(announcement: item, now: now, serverTimeZone: zone, supportsReadStats: supportsReadStats, groupNames: names)
            NavigationLink(value: AppRoute.announcementDetail(id: item.id)) { row }
                .accessibilityLabel(Text(row.spokenLabel))
                .accessibilityIdentifier("announcement.row.\(item.id)")
                .onAppear { Task { await list.loadMoreIfNeeded(after: item.id) } }
        }
    }

    @ViewBuilder private var nextPageFooter: some View {
        switch list.nextPage {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("announcements.more.loading")
        case .failed:
            Button("加载失败 · 重试") { Task { await list.retryMore() } }
                .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("announcements.more.retry")
        case .idle:
            EmptyView()
        }
    }

    /// 00 §4.6: a failed refresh keeps the rows; tapping reads again (not during a 429 wait).
    private var refreshFailedBanner: some View {
        let detail = list.throttleMessage()
        return Section {
            Button { Task { await list.reload() } } label: {
                StatusBanner(tone: .caution, systemImage: "exclamationmark.triangle", title: "刷新失败 · 重试", detail: detail)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(list.state.isLoading || detail != nil)
            .accessibilityLabel(["刷新失败 · 重试", detail].compactMap { $0 }.joined(separator: "，"))
            .accessibilityIdentifier("announcements.refresh.retry")
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }

    /// 60 §15.5: no announcement at all offers 新建公告 (not to a read-only token); an empty segment only says so.
    @ViewBuilder private var emptyState: some View {
        if list.emptyKind == .noAnnouncements {
            ContentUnavailableView {
                Label("还没有公告", systemImage: "megaphone").accessibilityIdentifier("announcements.empty")
            } actions: {
                if canCompose {
                    Button("新建公告", action: onCompose).buttonStyle(.borderedProminent).frame(minHeight: 44)
                        .accessibilityIdentifier("announcements.empty.create")
                }
            }
            .listRowBackground(Color.clear)
        } else {
            ContentUnavailableView("没有这类公告", systemImage: "tray")
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("announcements.segment.empty")
                .listRowBackground(Color.clear)
        }
    }

    /// No retry during a 429 wait; the page reads again on its own when it ends.
    private var retry: (() -> Void)? {
        guard list.throttleMessage() == nil else { return nil }
        return { Task { await list.reload() } }
    }
}

extension AppModel {
    /// C-34: the only way to the announcement module's reload signal. Writers call `bump()`, the list and the detail watch
    /// `revision`; a new session (switch, sign-out) gets a new signal.
    var announcementChanges: AnnouncementChangeSignal { AnnouncementChangeSignal.signal(for: sessionGeneration) }

    /// The site's announcements, or under `-ui-testing` this session's AnnouncementDemoStore.
    func announcementListSource(for session: SessionContext) -> AnnouncementListSource {
        guard isUITesting else { return .live(session.client) }
        return .fixture(AnnouncementDemoStore.current(for: session.generation, base: session.client.serverClock.now()))
    }
}
