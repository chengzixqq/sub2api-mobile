import SwiftUI
import Sub2Core

/// 60 §2.3 “查看全部” (`.searchResults(kind:query:)`): one kind's search 20 a page on the search tab's own stack, with the rows and
/// destinations of the results. Page 1 on entering and on pull, the next page at the end; no polling (60 §2.6). A query the
/// search could not send shows the two-character hint and reads nothing (S6D2b-04).
struct SearchResultsListView: View {
    let kind: SearchResultKind
    let text: String
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var list: SearchResultsListModel?
    @State private var catalog = MetaCatalog.builtin
    @State private var hasNames = false

    init(kind: SearchResultKind, query: String) { self.kind = kind; text = query }

    var body: some View {
        content
            .navigationTitle(kind.title)
            .navigationSubtitle(list?.subtitle ?? query.map { GlobalSearchCopy.listSubtitle($0, total: nil) } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: session?.generation) { await start() }
            .task { await loadNames() }
    }

    private var query: GlobalSearchQuery? { GlobalSearchQuery(text) }

    @ViewBuilder private var content: some View {
        if query == nil {
            Text(GlobalSearchCopy.tooShort).font(.subheadline).foregroundStyle(Palette.ink3)
                .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("search.hint.short")
        } else if let list {
            switch list.state.display {
            case .placeholder, .disabled:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("search.list.loading")
            case .failed(let reason):
                FailureView(message: list.throttleMessage() ?? reason ?? "") { Task { await list.load() } }
                    .accessibilityElement(children: .contain).accessibilityIdentifier("search.list.failure")
            case .value(let snapshot, _, _, let updateFailed):
                rows(snapshot, list: list, updateFailed: updateFailed)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rows(_ snapshot: SearchResultsListSnapshot, list: SearchResultsListModel, updateFailed: Bool) -> some View {
        let context = rowContext(list.query), positions = context.railPositions(snapshot.hits)
        return List {
            if snapshot.hits.isEmpty {
                Text(list.emptyText).font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("search.list.empty")
            } else {
                Section {
                    ForEach(Array(snapshot.hits.enumerated()), id: \.element.id) { index, hit in
                        SearchHitLink(hit: hit, context: context, railPosition: positions[index])
                            .onAppear { if index == snapshot.hits.count - 1 { Task { await list.loadNextPage() } } }
                    }
                    footer(list, updateFailed: updateFailed)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await list.load() }
    }

    /// The next page loading or “加载失败 · 重试”; after a failed pull the rows stay and the same line reads page 1 again.
    @ViewBuilder private func footer(_ list: SearchResultsListModel, updateFailed: Bool) -> some View {
        if updateFailed {
            retryRow(id: "search.list.refresh.retry", throttle: list.throttleMessage()) { await list.load() }
        } else {
            switch list.nextPage {
            case .loading: ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("search.list.more.loading")
            case .failed: retryRow(id: "search.list.more.retry", throttle: nil) { await list.retryNextPage() }
            case .idle: EmptyView()
            }
        }
    }
    private func retryRow(id: String, throttle: String?, action: @escaping @MainActor () async -> Void) -> some View {
        Button(throttle ?? GlobalSearchCopy.nextPageFailure) { Task { await action() } }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(throttle != nil)
            .accessibilityIdentifier(id)
    }

    /// Page 1 once: back from a row's detail the pages stay; a read cancelled before it landed goes out again.
    private func start() async {
        guard let session, let query else { return }
        let current = list ?? makeList(session: session, query: query)
        list = current
        guard case .idle = current.state else { return }
        await current.load()
    }
    private func makeList(session: SessionContext, query: GlobalSearchQuery) -> SearchResultsListModel {
        let source = model.globalSearchSource(for: session), kind = self.kind
        return SearchResultsListModel(kind: kind, query: query, fetch: { try await source.listPage(kind, query: query, page: $0) })
    }
    /// X25 and C-10, once: the account tab's platform and group names.
    private func loadNames() async {
        guard !hasNames else { return }
        hasNames = true
        catalog = await model.metaCatalog()
        await model.groupDirectory?.ensureLoaded()
    }
    private func rowContext(_ query: GlobalSearchQuery) -> SearchRowContext {
        let names = Dictionary((model.groupDirectory?.groups ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return SearchRowContext(query: query, catalog: catalog, groupNames: names, now: session?.client.serverClock.now() ?? Date(),
                                timeZone: session?.site.serverTimeZone ?? .device, idPrefix: "search.list")
    }
}
