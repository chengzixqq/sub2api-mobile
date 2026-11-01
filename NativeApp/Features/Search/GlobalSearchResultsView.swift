import SwiftUI
import Sub2Core

/// 60 §2: what the search box finds, block by block in GlobalSearchResults' order (S6D2b-01). A block lists its rows, then one
/// line “搜索中…” while a request is out, one line to resend only its failed requests (a countdown during a 429 wait, S6D2b-03),
/// “查看全部 N 个” above five and “只显示前 20 条” under requests. Under two characters only a hint shows and nothing is sent
/// (S6D2b-02). No refresh: the session keeps a query for 30 seconds (60 §2.6).
struct GlobalSearchResultsView: View {
    let search: GlobalSearchSession?
    let text: String
    let onClear: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismissSearch) private var dismissSearch
    @State private var catalog = MetaCatalog.builtin
    @State private var hasNames = false

    var body: some View {
        content
            .task {
                // X25 and C-10: the account tab's platform and group names, read once while the results show.
                guard !hasNames else { return }
                hasNames = true
                catalog = await model.metaCatalog()
                await model.groupDirectory?.ensureLoaded()
            }
    }

    @ViewBuilder private var content: some View {
        if GlobalSearchQuery(text) == nil {
            Text(GlobalSearchCopy.tooShort).font(.subheadline).foregroundStyle(Palette.ink3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 24)
                .accessibilityIdentifier("search.hint.short")
        } else if let search, let results = search.results {
            switch results.phase {
            case .results: list(results, search: search)
            case .empty: empty(results.plan.query)
            case .failed: failure(results, search: search)
            }
        } else {
            Color.clear
        }
    }

    private func list(_ results: GlobalSearchResults, search: GlobalSearchSession) -> some View {
        let context = rowContext(results.plan.query)
        return List {
            ForEach(results.visibleBlocks, id: \.self) { block in
                SearchResultsBlock(block: block, results: results, search: search, context: context)
            }
            if results.plan.showsVendorNote {
                Text(GlobalSearchCopy.vendorNote).font(.footnote).foregroundStyle(Palette.ink2)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("search.vendor-note")
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("search.results")
    }

    /// 60 §2.5 全部为空.
    private func empty(_ query: GlobalSearchQuery) -> some View {
        VStack(spacing: 6) {
            VStack(spacing: 6) {
                Text(DisplayFormat.missing).font(.system(size: 28, weight: .medium)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                Text(GlobalSearchCopy.noMatch(query)).font(.subheadline).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GlobalSearchCopy.noMatch(query))
            .accessibilityIdentifier("search.empty")
            Button(GlobalSearchCopy.clearSearch, action: clear)
                .frame(minHeight: 44)
                .accessibilityIdentifier("search.empty.clear")
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 60 §2.5 全部失败; during a 429 wait the countdown is the message and 重试 resends only what may go (S6D2b-03).
    private func failure(_ results: GlobalSearchResults, search: GlobalSearchSession) -> some View {
        let failed = results.failedSections, fallback = results.failureMessage ?? ""
        return Group {
            if search.isWaiting(failed) {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    FailureView(message: search.throttleMessage(failed, at: timeline.date) ?? fallback) { search.retryFailed() }
                }
            } else {
                FailureView(message: fallback) { search.retryFailed() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.failure")
    }

    private func rowContext(_ query: GlobalSearchQuery) -> SearchRowContext {
        let names = Dictionary((model.groupDirectory?.groups ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return SearchRowContext(query: query, catalog: catalog, groupNames: names, now: session?.client.serverClock.now() ?? Date(),
                                timeZone: session?.site.serverTimeZone ?? .device, idPrefix: "search")
    }
    /// “清除搜索”: back to the directory, the field put away.
    private func clear() {
        onClear()
        dismissSearch()
    }
}

/// One block of the results.
private struct SearchResultsBlock: View {
    let block: SearchBlock
    let results: GlobalSearchResults
    let search: GlobalSearchSession
    let context: SearchRowContext

    var body: some View {
        let summary = results.summary(of: block), hits = results.hits(of: block)
        let positions = context.railPositions(hits)
        Section {
            ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                SearchHitLink(hit: hit, context: context, railPosition: positions[index])
            }
            if summary.isSearching {
                Text(GlobalSearchCopy.searching).font(.subheadline).foregroundStyle(Palette.ink3)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("\(blockID).loading")
            }
            if !summary.failedSections.isEmpty { failedRow(summary.failedSections) }
            if let total = summary.viewAllTotal, let kind = block.kind {
                NavigationLink(value: AppRoute.searchResults(kind: kind, query: results.plan.query.text)) {
                    Text(GlobalSearchCopy.viewAll(total: total)).font(.subheadline).foregroundStyle(Palette.accent)
                }
                .accessibilityIdentifier("\(blockID).all")
            }
            if summary.showsFirstPageNote {
                Text(GlobalSearchCopy.firstPageOnly).font(.footnote).foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("\(blockID).capped")
            }
        } header: {
            NumberedSectionHeader(title: block.title, meta: summary.headerCount.map(DisplayFormat.grouped), id: blockID)
        }
    }

    private var blockID: String { "search.section.\(block.rawValue)" }

    /// “这一类暂时搜不到 · 重试” resends the block's failed requests at once; a 429 wait counts down instead.
    @ViewBuilder private func failedRow(_ failed: Set<SearchSection>) -> some View {
        if search.isWaiting(failed) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(search.throttleMessage(failed, at: timeline.date) ?? GlobalSearchCopy.sectionFailed)
                    .font(.subheadline).foregroundStyle(Palette.ink2).frame(minHeight: 44)
            }
            .accessibilityIdentifier("\(blockID).waiting")
        } else {
            Button(GlobalSearchCopy.sectionFailed) { search.retry(failed) }
                .font(.subheadline)
                .frame(minHeight: 44)
                .accessibilityIdentifier("\(blockID).retry")
        }
    }
}

extension GlobalSearchSession {
    /// A 429 wait is running for one of these.
    func isWaiting(_ sections: Set<SearchSection>) -> Bool { sections.contains { throttle(for: $0).notBefore != nil } }
    /// The first of these, in display order, still waiting.
    func throttleMessage(_ sections: Set<SearchSection>, at date: Date) -> String? {
        SearchSection.allCases.lazy.filter(sections.contains).compactMap { self.throttle(for: $0).throttleMessage(at: date) }.first
    }
}

extension AppModel {
    /// The site's search, or under `-ui-testing` the fixture site (SearchFixtures.swift).
    func globalSearchSource(for session: SessionContext) -> any GlobalSearchSource {
        guard isUITesting else { return ClientGlobalSearchSource(client: session.client) }
        return FixtureGlobalSearchSource(model: self, session: session)
    }
}
