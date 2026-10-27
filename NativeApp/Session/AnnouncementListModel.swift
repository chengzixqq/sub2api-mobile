import Foundation
import Observation
import Sub2Core

/// S6D1-01: the list's segments are statuses, nil being 全部; `.announcements(segment:)` carries the raw value.
enum AnnouncementSegments {
    static let order: [AnnouncementStatus?] = [nil, .active, .draft, .archived]
    /// nil, "", "all" and anything unknown open 全部.
    static func status(route: String?) -> AnnouncementStatus? { route.flatMap(AnnouncementStatus.init(rawValue:)) }
}

/// The list's two reads (60 §15.2): `client.announcements(page:query:)` and `announcementCounts()`, or the UI-test fixtures.
struct AnnouncementListSource: Sendable {
    let page: @Sendable (_ page: Int, _ query: AnnouncementListQuery) async throws -> Page<Announcement>
    let counts: @Sendable () async throws -> AnnouncementCounts

    static func live(_ client: APIClient) -> AnnouncementListSource {
        AnnouncementListSource(page: { try await client.announcements(page: $0, query: $1) }, counts: { try await client.announcementCounts() })
    }
}

/// 60 §15.6: the end of the list shows a spinner or “加载失败 · 重试”.
enum AnnouncementNextPage: Equatable, Sendable { case idle, loading, failed }

/// 60 §15: one list page. Page 1 and the four counts are read together; a segment switch reads page 1 only. It reads on first
/// appearance, when shown again after 60 seconds or after a write (`revision`), on pull, on returning to the foreground and after
/// compliance while visible; nothing during a 429 wait (00 §2.7.2). Replies for an older segment, load or session are dropped.
@MainActor @Observable
final class AnnouncementListModel {
    nonisolated static let staleInterval: TimeInterval = 60
    enum EmptyKind: Equatable, Sendable { case noAnnouncements, emptySegment }

    private(set) var status: AnnouncementStatus?
    let includeReadStats: Bool
    /// The rows from page 1 on; a failed refresh keeps them (00 §4.6).
    private(set) var state: BlockState<[Announcement]> = .idle
    /// A count that failed is nil, so its segment shows the name only; all four failing keeps the last counts.
    private(set) var counts: AnnouncementCounts?
    private(set) var firstPageTotal: Int?
    private(set) var hasMore = false
    private(set) var nextPage = AnnouncementNextPage.idle
    private(set) var refresh = BlockRefresh()

    @ObservationIgnored private let source: AnnouncementListSource
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Changes with every page-1 load and segment switch; a reply carrying an older one is dropped.
    @ObservationIgnored private var ticket = UUID()
    @ObservationIgnored private var countsTicket = UUID()
    @ObservationIgnored private var loadedPage = 0
    @ObservationIgnored private var appliedRevision: Int?
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var isStale = false

    init(source: AnnouncementListSource, status: AnnouncementStatus?, includeReadStats: Bool, isCurrent: @escaping @MainActor () -> Bool,
         now: @escaping @MainActor () -> Date = { Date() }) {
        self.source = source; self.status = status; self.includeReadStats = includeReadStats; self.isCurrent = isCurrent; self.now = now
    }

    var items: [Announcement] { state.value ?? [] }
    var loadedAt: Date? { state.updatedAt }
    func count(for status: AnnouncementStatus?) -> Int? { counts?.count(for: status) }
    /// “<站点名> · N 条”: every announcement, whatever the segment; without that count, 全部's own total.
    var subtitleCount: Int? { counts?.all ?? (status == nil ? firstPageTotal : nil) }
    /// 60 §15.5: 全部 empty or no announcement at all → “还没有公告”; another empty segment → “没有这类公告”.
    var emptyKind: EmptyKind? {
        guard let rows = state.value, rows.isEmpty else { return nil }
        return status == nil || counts?.all == 0 ? .noAnnouncements : .emptySegment
    }
    func throttleMessage() -> String? { refresh.throttleMessage(at: now()) }

    // MARK: - Visibility and signals

    /// First appearance, never loaded, shown again after 60 seconds, a write since (`revision`) or a pending invalidation.
    func appeared(revision: Int) async {
        isVisible = true
        let revisionMoved = appliedRevision.map { $0 != revision } ?? false
        appliedRevision = revision
        let isOld = loadedAt.map { now().timeIntervalSince($0) >= Self.staleInterval } ?? true
        guard state.value == nil || isOld || isStale || revisionMoved else { return }
        await reload()
    }
    func disappeared() { isVisible = false }
    /// A write in the detail or editor (C-34).
    func revisionChanged(_ revision: Int) async {
        appliedRevision = revision
        await invalidate()
    }
    /// Reads now while shown, otherwise on the next appearance (writes, compliance).
    func invalidate() async {
        guard isVisible else { isStale = true; return }
        await reload()
    }
    /// D18, 00 §4.6: back from the background, a shown list reads once.
    func foregroundResumed() async {
        guard isVisible else { return }
        await reload()
    }

    // MARK: - Reads

    /// Page 1 and the counts together.
    func reload() async { await loadFirstPage(withCounts: true) }
    /// A new segment starts from an empty list; the counts do not depend on it.
    func select(_ status: AnnouncementStatus?) async {
        guard status != self.status else { return }
        self.status = status
        ticket = UUID()
        state = state.withReset(during: refresh, at: now())
        firstPageTotal = nil; hasMore = false; loadedPage = 0; nextPage = .idle
        await loadFirstPage(withCounts: false)
    }
    /// The last row appeared: the next page, deduplicated by id.
    func loadMoreIfNeeded(after id: Int) async {
        guard nextPage == .idle, items.last?.id == id else { return }
        await readNextPage()
    }
    func retryMore() async {
        guard nextPage == .failed else { return }
        nextPage = .idle
        await readNextPage()
    }

    // MARK: - Internals

    private var query: AnnouncementListQuery { AnnouncementListQuery(status: status, includeReadStats: includeReadStats) }

    private func loadFirstPage(withCounts: Bool) async {
        guard isCurrent(), refresh.allowsRequest(at: now()) else { return }
        isStale = false
        let ticket = UUID(), countsTicket = withCounts ? UUID() : self.countsTicket
        self.ticket = ticket; self.countsTicket = countsTicket
        nextPage = .idle
        state = state.withLoading()
        let source = self.source, query = self.query
        async let counted = Self.counts(from: source, if: withCounts)
        show(await Self.capture { try await source.page(1, query) }, ticket: ticket)
        if case .success(let value)? = await counted, countsTicket == self.countsTicket, isCurrent() { counts = value }
    }
    /// The rows arrive without waiting for the counts.
    private func show(_ first: Result<Page<Announcement>, any Error>, ticket: UUID) {
        guard ticket == self.ticket else { return }
        guard isCurrent(), !Task.isCancelled else { state = state.withCancelledLoad(); return }
        switch first {
        case .success(let page):
            state = .loaded(page.items, at: now())
            firstPageTotal = page.total; hasMore = page.hasMore; loadedPage = 1
            refresh = refresh.recordingSuccess()
        case .failure(let error) where error is CancellationError:
            state = state.withCancelledLoad()
        case .failure(let error):
            state = state.withFailure(error.localizedDescription)
            refresh = refresh.recordingFailure(error, at: now())
        }
    }
    private func readNextPage() async {
        guard hasMore, loadedPage > 0, !state.isLoading, isCurrent() else { return }
        let ticket = self.ticket, page = loadedPage + 1
        nextPage = .loading
        do {
            let next = try await source.page(page, query)
            guard ticket == self.ticket, isCurrent() else { return }
            let known = Set(items.map(\.id))
            state = state.updatingValue { $0 + next.items.filter { !known.contains($0.id) } }
            loadedPage = page; hasMore = next.hasMore; nextPage = .idle
        } catch {
            guard ticket == self.ticket, isCurrent() else { return }
            nextPage = error is CancellationError ? .idle : .failed
        }
    }
    private nonisolated static func counts(from source: AnnouncementListSource, if wanted: Bool) async -> Result<AnnouncementCounts, any Error>? {
        wanted ? await capture(source.counts) : nil
    }
    private nonisolated static func capture<Value: Sendable>(_ work: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
