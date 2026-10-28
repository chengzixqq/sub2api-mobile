import Foundation
import Observation
import OSLog
import Sub2Core

/// `.redeem(open:query:status:type:reconcile:)` read once (S6D1-05): the strings become a filter, unknown values open 全部.
struct RedeemRouteState: Equatable, Sendable {
    let open: Int?
    let filter: RedeemListFilter
    /// From the overview's pending row: the banner's 核对 is the primary button (60 §8.1).
    let reconcile: Bool

    init(open: Int? = nil, filter: RedeemListFilter = RedeemListFilter(), reconcile: Bool = false) {
        self.open = open; self.filter = filter; self.reconcile = reconcile
    }
    init(_ route: AppRoute) {
        guard case .redeem(let open, let query, let status, let type, let reconcile) = route else { self.init(); return }
        self.init(open: open, filter: RedeemListFilter(route: query, status: status, type: type), reconcile: reconcile)
    }
}

/// The list's three reads (60 §8.2): `client.redeemCodes`, `redeemCodeStats` and `redeemCode(id:)`, or the UI-test fixtures.
struct RedeemCodesSource: Sendable {
    let list: @Sendable (_ page: Int, _ query: RedeemCodeListQuery) async throws -> Page<AdminRedeemCode>
    let stats: @Sendable (_ query: RedeemCodeListQuery) async throws -> RedeemCodeStats
    let code: @Sendable (_ id: Int) async throws -> AdminRedeemCode

    static func live(_ client: APIClient) -> RedeemCodesSource {
        RedeemCodesSource(list: { try await client.redeemCodes(page: $0, query: $1) }, stats: { try await client.redeemCodeStats(query: $0) },
                          code: { try await client.redeemCode(id: $0) })
    }
}

/// 60 §8: one redeem list page. Page 1 with the counts on first appearance, when shown again after 60 seconds, on pull, after
/// an outside change (`noteExternalChange`) and back in the foreground after 60 seconds or a failure; the bottom reads the next
/// page. Replies for an older filter, load or session are dropped. The writes of S6-05…S6-09 call the entry points below.
@MainActor @Observable
final class RedeemCodesModel {
    enum NextPage: Equatable, Sendable { case idle, loading, failed }

    /// The session this list belongs to (S6-05's RedeemCodeWritesHost).
    let generation: UUID
    let supportsStats: Bool
    /// `.redeem(reconcile: true)`: the banner's 核对 is the primary button.
    let highlightsBanner: Bool
    private(set) var filter: RedeemListFilter
    /// The search field; `applySearch()` takes it after the page's 300 ms debounce.
    var searchText: String
    private(set) var state: BlockState<RedeemListPage> = .idle
    /// nil: counts failed, not read or no capability, so the chips show names only.
    private(set) var stats: RedeemCodeStats?
    /// The subtitle's “N 个”.
    private(set) var siteTotal: Int?
    /// `.redeem(open:)` read by id when the loaded pages do not hold it.
    private(set) var located: AdminRedeemCode?
    private(set) var openID: Int?
    /// Changes whenever a card should be scrolled fully into view.
    private(set) var revealRequest = RevealRequest(id: nil)
    private(set) var nextPage = NextPage.idle
    private(set) var refresh = BlockRefresh()

    struct RevealRequest: Equatable { let id: Int?; var token = UUID() }

    @ObservationIgnored private let source: RedeemCodesSource
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var ticket = UUID()
    @ObservationIgnored private var statsTicket = UUID()
    @ObservationIgnored private var filterBeforeBatch: RedeemListFilter?
    @ObservationIgnored private var pendingOpen: Int?
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var needsReload = false
    @ObservationIgnored private var automaticReads = 0
    private static weak var current: RedeemCodesModel?
    private static let log = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "redeem")

    init(session: SessionContext, source: RedeemCodesSource, route: RedeemRouteState, receipts: ReceiptCenter,
         isCurrent: @escaping @MainActor () -> Bool, now: @escaping @MainActor () -> Date = { Date() }) {
        generation = session.generation; supportsStats = session.has(.redeemCodesStats); highlightsBanner = route.reconcile
        filter = route.filter; searchText = route.filter.search; pendingOpen = route.open
        self.source = source; self.receipts = receipts; self.isCurrent = isCurrent; self.now = now
    }

    var codes: [AdminRedeemCode] { state.value?.codes ?? [] }
    var pinned: AdminRedeemCode? { RedeemListLayout.pinned(located, in: codes) }
    /// The batch chip's “N 个”: the server's total for the batch query.
    var batchTotal: Int? { filter.batch == nil ? nil : state.value?.serverTotal }
    var empty: RedeemListEmpty? { RedeemListEmpty.resolve(page: state.value, filter: filter, siteTotal: siteTotal) }
    /// “加载更多” at the end, where reaching the last card cannot read on.
    var offersLoadMore: Bool {
        guard nextPage == .idle, !state.isLoading, let page = state.value else { return false }
        return RedeemListPolicy.offersLoadMore(page, query: filter.listQuery(supportsStats: supportsStats))
    }
    func throttleMessage() -> String? { refresh.throttleMessage(at: now()) }

    // MARK: - Visibility and signals

    /// C-34: a generate, reconcile or compensation sheet changed the codes. The shown list reads again now, a covered one when
    /// it appears next.
    static func noteExternalChange() {
        guard let current else { return }
        Task { await current.markNeedsReload() }
    }
    func markNeedsReload() async {
        guard isVisible, isCurrent() else { needsReload = true; return }
        await reloadFirstPageAndStats()
    }
    /// Every appearance; the newest shown list is the one `noteExternalChange()` reaches.
    func appeared() async {
        isVisible = true
        Self.current = self
        guard needsReload || RedeemListPolicy.isStale(lastLoadedAt: state.updatedAt, now: now()) else { return await locatePending() }
        await reloadFirstPageAndStats()
    }
    func disappeared() { isVisible = false }
    /// Back from the background: after 60 seconds, a failure or a read the background stopped.
    func foregroundResumed() async {
        guard isVisible else { return }
        let failed = state.failureReason != nil || nextPage == .failed
        guard needsReload || failed || RedeemListPolicy.isStale(lastLoadedAt: state.updatedAt, now: now()) else { return }
        await reloadFirstPageAndStats()
    }
    func pullToRefresh() async { await reloadFirstPageAndStats() }

    // MARK: - Entry points for S6-05…S6-09

    /// Page 1, the chips' counts and the subtitle's total; then the route's code if it is not open yet (its first page failed or
    /// waited out a 429).
    func reloadFirstPageAndStats() async {
        async let counted: Void = readStats(includingTotal: true)
        await loadFirstPage()
        await counted
        await locatePending()
    }
    /// After a write: GET :id keeps the list's user and group; a code gone (404) leaves the list.
    func refreshCard(id: Int) async {
        guard isCurrent() else { return }
        let source = self.source
        let result = await Self.capture { try await source.code(id) }
        guard isCurrent() else { return }
        switch result {
        case .success(let fresh): replaceLocally(fresh)
        case .failure(let error) where RedeemListFailure(error) == .notFound: removeLocally(id: id)
        case .failure(let error): note(error)
        }
    }
    func refreshStats() async { await readStats(includingTotal: true) }
    func replaceLocally(_ code: AdminRedeemCode) {
        let previous = codes.first { $0.id == code.id } ?? (located?.id == code.id ? located : nil)
        let merged = code.keepingRelations(of: previous)
        state = state.updatingValue { $0.replacing(merged) }
        if located?.id == code.id { located = merged }
    }
    func removeLocally(id: Int) {
        state = state.updatingValue { $0.removing(id: id) }
        if located?.id == id { located = nil }
        if openID == id { openID = nil }
    }

    // MARK: - Filters

    func select(status: RedeemCodeStatus?) async {
        guard filter.batch == nil, status != filter.status else { return }
        filter.status = status
        resetForNewFilter()
        await loadFirstPage()
    }
    func select(type: RedeemCodeType?) async {
        guard filter.batch == nil, type != filter.type else { return }
        filter.type = type
        await reloadForNewFilter()
    }
    /// Typing during “查看同一批” leaves the batch for the filter it replaced.
    func applySearch() async {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != filter.trimmedSearch else { return }
        var next = filterBeforeBatch ?? filter
        next.search = text; next.batch = nil
        filterBeforeBatch = nil
        filter = next
        await reloadForNewFilter()
    }
    /// U49: only the batch, until its chip is removed; the opened card stays open.
    func showBatch(of code: AdminRedeemCode) async {
        guard let batchID = code.batchID, filter.batch?.batchID != batchID else { return }
        if filter.batch == nil { filterBeforeBatch = filter }
        filter = filter.showingBatch(batchID)
        searchText = ""
        resetForNewFilter(keepingOpen: code.id)
        await loadFirstPage()
    }
    func clearBatch() async {
        guard filter.batch != nil else { return }
        filter = filterBeforeBatch ?? RedeemListFilter()
        filterBeforeBatch = nil
        searchText = filter.search
        await reloadForNewFilter()
    }

    // MARK: - Cards and pages

    /// One card open at a time (60 §8.4).
    func toggle(_ id: Int) {
        openID = openID == id ? nil : id
        if openID != nil { revealRequest = RevealRequest(id: id) }
    }
    func loadMoreIfNeeded(after id: Int) async {
        guard codes.last?.id == id else { return }
        await loadMore()
    }
    /// The last card reached the screen, or “加载更多”.
    func loadMore() async {
        guard nextPage == .idle else { return }
        automaticReads = 0
        await readNextPage()
    }
    func retryMore() async {
        guard nextPage == .failed else { return }
        nextPage = .idle; automaticReads = 0
        await readNextPage()
    }

    // MARK: - Internals

    private func reloadForNewFilter() async {
        resetForNewFilter()
        async let counted: Void = readStats(includingTotal: false)
        await loadFirstPage()
        await counted
    }
    /// A new filter starts from an empty list; a located code belongs to the list it was opened in.
    private func resetForNewFilter(keepingOpen id: Int? = nil) {
        ticket = UUID()
        state = state.withReset(during: refresh, at: now())
        nextPage = .idle; located = nil; pendingOpen = nil; openID = id
    }
    private func loadFirstPage() async {
        guard isCurrent(), refresh.allowsRequest(at: now()) else { return }
        needsReload = false
        let ticket = UUID(), query = filter.listQuery(supportsStats: supportsStats), source = self.source
        self.ticket = ticket
        nextPage = .idle; automaticReads = 0
        state = state.withLoading()
        let result = await Self.capture { try await source.list(1, query) }
        guard ticket == self.ticket else { return }
        guard isCurrent(), !Task.isCancelled else { return cancelLoad() }
        switch result {
        case .success(let page):
            state = .loaded(RedeemListPage.empty.merging(page, query: query), at: now())
            refresh = refresh.recordingSuccess()
            if let id = openID, !codes.contains(where: { $0.id == id }), located?.id != id { openID = nil }
            await continueIfShort(page, query: query)
        case .failure(let error) where error is CancellationError:
            cancelLoad()
        case .failure(let error):
            note(error)
            state = state.withFailure(error.localizedDescription)
            refresh = refresh.recordingFailure(error, at: now())
        }
    }
    /// The old rows stay and the next appearance reads again.
    private func cancelLoad() {
        state = state.withCancelledLoad()
        needsReload = true
    }
    private func readNextPage() async {
        guard let loaded = state.value, loaded.hasMore, !state.isLoading, nextPage != .loading, isCurrent() else { return }
        let ticket = self.ticket, query = filter.listQuery(supportsStats: supportsStats), number = loaded.nextServerPage, source = self.source
        nextPage = .loading
        let result = await Self.capture { try await source.list(number, query) }
        guard ticket == self.ticket, isCurrent() else { return }
        switch result {
        case .success(let page):
            state = state.updatingValue { $0.merging(page, query: query) }
            nextPage = .idle
            await continueIfShort(page, query: query)
        case .failure(let error):
            if !(error is CancellationError) { note(error) }
            nextPage = error is CancellationError ? .idle : .failed
        }
    }
    /// An old server's page thinned by admin rows reads on, a few pages at most.
    private func continueIfShort(_ page: Page<AdminRedeemCode>, query: RedeemCodeListQuery) async {
        guard RedeemListPolicy.continuesAutomatically(after: page, query: query, automaticReads: automaticReads) else { return }
        automaticReads += 1
        await readNextPage()
    }
    /// The chips follow the search and the type; the subtitle's total only on entry, pull and after changes elsewhere.
    private func readStats(includingTotal: Bool) async {
        guard isCurrent(), refresh.allowsRequest(at: now()) else { return }
        let ticket = UUID(), source = self.source
        statsTicket = ticket
        let chipsQuery = filter.statsQuery(supportsStats: supportsStats)
        let totalQuery = includingTotal ? RedeemListFilter.totalQuery(supportsStats: supportsStats) : nil
        let chips = await Self.stats(chipsQuery, from: source)
        let total = totalQuery == nil || totalQuery == chipsQuery ? chips : await Self.stats(totalQuery, from: source)
        guard ticket == statsTicket, isCurrent() else { return }
        if chips.map({ !Self.isCancellation($0) }) ?? true { stats = chips.flatMap { try? $0.get() } }
        if includingTotal, total.map({ !Self.isCancellation($0) }) ?? true { siteTotal = total.flatMap { try? $0.get() }?.total }
    }
    /// `.redeem(open:)` once the first page is in: a loaded code opens in place, another is read by id and shown on top. A
    /// deleted one says so; any other failure stays quiet and the next pull tries again.
    private func locatePending() async {
        guard let id = pendingOpen, state.value != nil, isCurrent() else { return }
        if codes.contains(where: { $0.id == id }) { return open(id) }
        let source = self.source
        let result = await Self.capture { try await source.code(id) }
        guard pendingOpen == id, isCurrent() else { return }
        switch result {
        case .success(let code):
            located = code
            open(id)
        case .failure(let error) where RedeemListFailure(error) == .notFound:
            pendingOpen = nil
            receipts.show(Receipt(text: RedeemListText.locatedGone, systemImage: "trash", tone: .neutral))
        case .failure(let error):
            note(error)
        }
    }
    private func open(_ id: Int) {
        pendingOpen = nil
        openID = id
        revealRequest = RevealRequest(id: id)
    }
    /// 60 §8.5: the three parameter refusals are the App's own mistake; the reason is logged, never the code or the search.
    private func note(_ error: any Error) {
        guard case .parameter(let reason) = RedeemListFailure(error) else { return }
        Self.log.error("redeem list query refused: \(reason, privacy: .public)")
    }

    private nonisolated static func stats(_ query: RedeemCodeListQuery?, from source: RedeemCodesSource) async -> Result<RedeemCodeStats, any Error>? {
        guard let query else { return nil }
        return await capture { try await source.stats(query) }
    }
    private nonisolated static func isCancellation(_ result: Result<RedeemCodeStats, any Error>) -> Bool {
        if case .failure(let error) = result { error is CancellationError } else { false }
    }
    private nonisolated static func capture<Value: Sendable>(_ work: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}

extension AppModel {
    /// The site's codes, or under `-ui-testing` this session's RedeemDemoStore.
    func redeemCodesSource(for session: SessionContext) -> RedeemCodesSource {
        guard isUITesting else { return .live(session.client) }
        return .fixture(RedeemDemoStore.current(for: session.generation, base: session.client.serverClock.now()))
    }
}
