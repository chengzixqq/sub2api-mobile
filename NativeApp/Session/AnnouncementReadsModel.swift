import Foundation
import Observation
import Sub2Core

/// The 已读情况 page's reads (60 §18.2): the announcement for its title, the roster pages and the summary, or the UI-test
/// fixtures.
struct AnnouncementReadsSource: Sendable {
    let announcement: @Sendable (_ id: Int) async throws -> Announcement
    let page: @Sendable (_ id: Int, _ page: Int, _ query: AnnouncementReadStatusQuery) async throws -> Page<AnnouncementReadStatusRow>
    let summary: @Sendable (_ id: Int) async throws -> AnnouncementReadSummary

    static func live(_ client: APIClient) -> AnnouncementReadsSource {
        AnnouncementReadsSource(announcement: { try await client.announcement(id: $0, includeReadStats: false) },
                                page: { try await client.announcementReadStatus(id: $0, page: $1, query: $2) },
                                summary: { try await client.announcementReadSummary(id: $0) })
    }
}

/// The roster from page 1 on, one row per user; `total` is the filtered count behind “找到 N 位”.
struct AnnouncementReadsList: Equatable, Sendable {
    let rows: [AnnouncementReadStatusRow]
    let loadedPage: Int
    let hasMore: Bool
    let total: Int?

    init(first page: Page<AnnouncementReadStatusRow>) {
        self.init(rows: page.items, loadedPage: 1, hasMore: page.hasMore, total: page.total)
    }
    private init(rows: [AnnouncementReadStatusRow], loadedPage: Int, hasMore: Bool, total: Int?) {
        self.rows = rows; self.loadedPage = loadedPage; self.hasMore = hasMore; self.total = total
    }

    /// Page `number` after the loaded ones; a user already shown (the roster moved underneath) is not repeated.
    func appending(_ page: Page<AnnouncementReadStatusRow>, number: Int) -> AnnouncementReadsList {
        var seen = Set(rows.map(\.userID))
        let fresh = page.items.filter { seen.insert($0.userID).inserted }
        return AnnouncementReadsList(rows: rows + fresh, loadedPage: number, hasMore: page.hasMore, total: page.total ?? total)
    }
}

/// 60 §18: who can see one announcement and who has read it. On entry the title, the summary (with
/// `announcements.read_stats`) and page 1 are read together; pull reads all three again; search (300 ms debounce), the
/// read-state segment, 只看符合条件 and the sort read page 1 only; the bottom reads the next page. Never polls and does not
/// read again when shown again (60 §18.6). Read-only. Replies for an older query, load or session are dropped.
@MainActor @Observable
final class AnnouncementReadsModel {
    typealias Sort = AnnouncementReadStatusQuery.Sort
    typealias ReadState = AnnouncementReadStatusQuery.ReadState

    let announcementID: Int
    let supportsReadStats: Bool
    private(set) var query: AnnouncementReadStatusQuery
    /// The search field; the query takes it after the debounce.
    private(set) var searchText = ""
    private(set) var title: String?
    /// nil without the capability or when the last read failed: the bar falls back to the page's total.
    private(set) var summary: AnnouncementReadSummary?
    /// A failed refresh keeps the rows (00 §4.6).
    private(set) var state: BlockState<AnnouncementReadsList> = .idle
    /// The latest unfiltered page 1's `total`: the fallback bar's “共 N 位用户”.
    private(set) var unfilteredTotal: Int?
    /// 404 ANNOUNCEMENT_NOT_FOUND: the “已删除” page.
    private(set) var isGone = false
    private(set) var nextPage = AnnouncementNextPage.idle
    private(set) var refresh = BlockRefresh()

    @ObservationIgnored private let source: AnnouncementReadsSource
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Changes with every page-1 load and query change; a page carrying an older one is dropped.
    @ObservationIgnored private var ticket = UUID()
    @ObservationIgnored private var headerTicket = UUID()
    /// The title and summary have not been read yet, or leaving the page cancelled them.
    @ObservationIgnored private var needsHeader = true
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(announcementID: Int, supportsReadStats: Bool, source: AnnouncementReadsSource, isCurrent: @escaping @MainActor () -> Bool,
         debounce: Duration = .milliseconds(300), now: @escaping @MainActor () -> Date = { Date() }) {
        self.announcementID = announcementID; self.supportsReadStats = supportsReadStats; self.source = source
        self.isCurrent = isCurrent; self.debounce = debounce; self.now = now
        query = AnnouncementReadStatusQuery(supportsReadStats: supportsReadStats)
    }

    var rows: [AnnouncementReadStatusRow] { state.value?.rows ?? [] }
    var hasMore: Bool { state.value?.hasMore ?? false }
    var sorts: [Sort] { Sort.available(supportsReadStats: supportsReadStats) }
    /// “已读 412 · 符合条件 1,036 · 共 1,036 位用户 · 统计于 09:41”, or “第 1 页 · 共 1,036 位用户”.
    func summaryText(serverTimeZone: TimeZone) -> String {
        AnnouncementPresentation.readsSummaryBar(supportsReadStats ? summary : nil, total: unfilteredTotal, serverTimeZone: serverTimeZone)
    }
    /// “找到 N 位” while a search or filter is on.
    var foundText: String? { AnnouncementPresentation.readsResultCount(total: state.value?.total, isFiltered: query.isFiltered) }
    func throttleMessage() -> String? { refresh.throttleMessage(at: now()) }

    // MARK: - Reads

    /// Every appearance: the first read, or only what leaving cancelled; back from a user's page nothing is read again.
    func start() async {
        guard !isGone else { return }
        if state.value == nil, !state.isLoading { return await reload() }
        if needsHeader { await loadHeader() }
    }
    /// Entry and pull: the title, the summary and page 1 together.
    func reload() async {
        guard !isGone else { return }
        async let header: Void = loadHeader()
        await loadFirstPage()
        await header
    }
    /// The field's text; page 1 is read once it has stayed the same for the debounce.
    func searchChanged(_ text: String) {
        searchText = text
        searchTask?.cancel()
        let delay = debounce
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            await self?.applySearch()
        }
    }
    func applySearch() async {
        var next = query
        next.search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        await apply(next)
    }
    func setReadState(_ readState: ReadState) async {
        var next = query
        next.readState = readState
        await apply(next)
    }
    func setEligibleOnly(_ eligibleOnly: Bool) async {
        var next = query
        next.eligibleOnly = eligibleOnly
        await apply(next)
    }
    func setSort(_ sort: Sort) async {
        var next = query
        next.sort = sort
        await apply(next)
    }
    /// The last row appeared: the next page.
    func loadMoreIfNeeded(after userID: Int) async {
        guard nextPage == .idle, rows.last?.userID == userID else { return }
        await readNextPage()
    }
    func retryMore() async {
        guard nextPage == .failed else { return }
        nextPage = .idle
        await readNextPage()
    }

    // MARK: - Internals

    /// A new query starts from an empty list.
    private func apply(_ next: AnnouncementReadStatusQuery) async {
        guard next != query, !isGone else { return }
        query = next
        ticket = UUID()
        state = state.withReset(during: refresh, at: now())
        nextPage = .idle
        await loadFirstPage()
    }

    private func loadFirstPage() async {
        guard isCurrent(), refresh.allowsRequest(at: now()) else { return }
        let ticket = UUID()
        self.ticket = ticket
        nextPage = .idle
        state = state.withLoading()
        let source = self.source, id = announcementID, query = self.query
        let result = await Self.capture { try await source.page(id, 1, query) }
        guard ticket == self.ticket else { return }
        guard isCurrent(), !Task.isCancelled else { state = state.withCancelledLoad(); return }
        switch result {
        case .success(let page):
            state = .loaded(AnnouncementReadsList(first: page), at: now())
            if !query.isFiltered { unfilteredTotal = page.total }
            refresh = refresh.recordingSuccess()
        case .failure(let error) where error is CancellationError: state = state.withCancelledLoad()
        case .failure(let error) where AnnouncementWriteFailure.isGone(error): markGone()
        case .failure(let error):
            state = state.withFailure(error.localizedDescription)
            refresh = refresh.recordingFailure(error, at: now())
        }
    }

    /// The title, and the summary with the capability; a failed summary falls back to the page's total.
    private func loadHeader() async {
        guard isCurrent(), refresh.allowsRequest(at: now()) else { return }
        let ticket = UUID()
        headerTicket = ticket
        let source = self.source, id = announcementID
        async let counted = Self.summary(from: source, id: id, if: supportsReadStats)
        let titled = await Self.capture { try await source.announcement(id) }
        let summed = await counted
        guard ticket == headerTicket, isCurrent(), !Task.isCancelled else { return }
        if case .failure(let error) = titled, AnnouncementWriteFailure.isGone(error) { return markGone() }
        needsHeader = [titled.failure, summed?.failure].compactMap { $0 }.contains { $0 is CancellationError }
        if case .success(let announcement) = titled { title = announcement.title }
        switch summed {
        case .success(let value)?: summary = value
        case .failure(let error)? where !(error is CancellationError): summary = nil
        case .failure?, nil: break
        }
    }

    private func readNextPage() async {
        guard let list = state.value, list.hasMore, !state.isLoading, isCurrent() else { return }
        let ticket = self.ticket, number = list.loadedPage + 1
        let source = self.source, id = announcementID, query = self.query
        nextPage = .loading
        let result = await Self.capture { try await source.page(id, number, query) }
        guard ticket == self.ticket, isCurrent() else { return }
        switch result {
        case .success(let page):
            state = state.updatingValue { $0.appending(page, number: number) }
            nextPage = .idle
        case .failure(let error) where error is CancellationError: nextPage = .idle
        case .failure(let error) where AnnouncementWriteFailure.isGone(error): markGone()
        case .failure: nextPage = .failed
        }
    }

    private func markGone() {
        ticket = UUID(); headerTicket = UUID()
        isGone = true
        state = .idle
        summary = nil
        nextPage = .idle
        searchTask?.cancel()
    }
    private nonisolated static func summary(from source: AnnouncementReadsSource, id: Int,
                                            if wanted: Bool) async -> Result<AnnouncementReadSummary, any Error>? {
        wanted ? await capture { try await source.summary(id) } : nil
    }
    private nonisolated static func capture<Value: Sendable>(_ work: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}

private extension Result {
    var failure: Failure? { if case .failure(let error) = self { error } else { nil } }
}
