import Foundation
import Observation
import Sub2Core

// 60 §2.3 “查看全部” (S6-21): `.searchResults(kind:query:)` reads one kind's search 20 a page through the search's own source.

extension GlobalSearchSource {
    /// S6D2b-04: the fan-out's request for this kind with 20 a page (accounts stay lite).
    func listPage(_ kind: SearchResultKind, query: GlobalSearchQuery, page: Int) async throws -> SearchHitPage {
        let answer = try await hits(for: kind.request(query, page: page))
        return SearchHitPage(hits: answer.hits, total: answer.total, page: page, hasMore: answer.hasMore)
    }
}

extension SearchHit {
    /// 60 §2.1: pushed on the search tab's own stack. Accounts and request rows carry the row, so the detail shows it first.
    var route: AppRoute {
        switch self {
        case .account(let row): .account(id: row.id, preload: RoutePreload(row))
        case .user(let row): .user(id: row.id)
        case .group(let row): .group(id: row.id)
        case .proxy(let row): .proxyDetail(id: row.id)
        case .usage(let row): .request(.usage(RoutePreload(row)))
        case .error(let row): .request(.error(id: row.id, kind: .request, initial: RoutePreload(row)))
        }
    }
}

/// 60 §2.3 / §2.6: page 1 on appearance and on pull, the next page when the last row shows. A failed refresh keeps the rows;
/// nothing is read during a 429 wait (00 §2.7.2); a page that lands after a newer page 1 was asked for is dropped. No polling.
@MainActor @Observable
final class SearchResultsListModel {
    enum NextPage: Equatable, Sendable { case idle, loading, failed }

    let kind: SearchResultKind
    let query: GlobalSearchQuery
    private(set) var state: BlockState<SearchResultsListSnapshot> = .idle
    private(set) var nextPage = NextPage.idle
    private(set) var refresh = BlockRefresh()

    @ObservationIgnored private let fetch: @Sendable (Int) async throws -> SearchHitPage
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Changes with every page-1 read; a reply carrying an older one is dropped.
    @ObservationIgnored private var ticket = UUID()

    init(kind: SearchResultKind, query: GlobalSearchQuery, fetch: @escaping @Sendable (Int) async throws -> SearchHitPage,
         now: @escaping @MainActor () -> Date = { Date() }) {
        self.kind = kind; self.query = query; self.fetch = fetch; self.now = now
    }

    var hits: [SearchHit] { state.value?.hits ?? [] }
    /// “搜索“q” · N 个”; only “搜索“q”” before the total is known.
    var subtitle: String { GlobalSearchCopy.listSubtitle(query, total: state.value?.total) }
    var emptyText: String { GlobalSearchCopy.listEmpty(kind, query: query) }
    func throttleMessage() -> String? { refresh.throttleMessage(at: now()) }

    /// Page 1, replacing the rows when it lands.
    func load() async {
        guard refresh.allowsRequest(at: now()) else { return }
        let ticket = UUID()
        self.ticket = ticket
        nextPage = .idle
        state = state.withLoading()
        let result = await Self.capture(fetch, page: 1)
        guard ticket == self.ticket else { return }
        switch result {
        case .success(let first):
            state = .loaded(SearchResultsListSnapshot(first), at: now())
            refresh = refresh.recordingSuccess()
        case .failure(let error) where error is CancellationError:
            state = state.withCancelledLoad()
        case .failure(let error):
            state = state.withFailure(error.localizedDescription)
            refresh = refresh.recordingFailure(error, at: now())
        }
    }
    /// The last row appeared.
    func loadNextPage() async {
        guard nextPage == .idle else { return }
        await readNextPage()
    }
    /// “加载失败 · 重试” under the rows.
    func retryNextPage() async {
        guard nextPage == .failed else { return }
        await readNextPage()
    }

    private func readNextPage() async {
        guard case .loaded(let snapshot, _) = state, let page = snapshot.nextPage else { return }
        let ticket = self.ticket
        nextPage = .loading
        let result = await Self.capture(fetch, page: page)
        guard ticket == self.ticket else { return }
        switch result {
        case .success(let next):
            state = state.updatingValue { $0.appending(next) }
            nextPage = .idle
        case .failure(let error):
            nextPage = error is CancellationError ? .idle : .failed
        }
    }
    private nonisolated static func capture(_ fetch: @Sendable (Int) async throws -> SearchHitPage, page: Int) async -> Result<SearchHitPage, any Error> {
        do { return .success(try await fetch(page)) } catch { return .failure(error) }
    }
}
