import Foundation
import Observation
import Sub2Core

/// 30 §1.4: reading the pages after the first; the end of the list shows a spinner or “加载更多失败 · 重试”.
enum UserListNextPage: Equatable, Sendable { case idle, loading, failed }

/// 30 §1: the user tab's list, kept for the session on AppModel (S3D1-05) so the detail, keypad, reconciliation and editor
/// pages write back through `model.userList?`. The page calls `loadIfNeeded` on appear and `refresh` on entering the tab, on
/// returning to the foreground, after compliance and every 60 seconds. Requests go through AppModel's wrappers (fixtures
/// included); a reply for an older session or an earlier search is dropped.
@MainActor @Observable
final class UserListModel {
    let generation: UUID
    /// No value + loading = skeleton; value + failed = the stale banner; failed alone = the error page.
    private(set) var listState: BlockState<UserListSnapshot> = .idle
    /// The last list failure, kept apart because 403 FORBIDDEN has its own page.
    private(set) var failure: UserListFailure?
    private(set) var nextPage = UserListNextPage.idle
    /// The trimmed search the rows belong to.
    private(set) var query = ""
    /// Today's spend by user id, for ids of batches that answered.
    private(set) var todayCosts: [Int: Decimal] = [:]
    /// nil: no strip (no capability, a search, a failed read).
    private(set) var quickTopup: QuickTopupReply?
    /// settings/public, read once per session; until then only the users' own thresholds mark low balances.
    private(set) var lowBalanceGlobal: UserLowBalanceGlobal?
    private(set) var refreshState = BlockRefresh()
    private(set) var lastRefreshAt: Date?

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var needsRefresh = false
    /// Changes with every search, so replies for the previous one are dropped.
    @ObservationIgnored private var searchTicket = UUID()
    @ObservationIgnored private var firstPageTask: Task<Void, Never>?
    @ObservationIgnored private var readingGlobal = false

    init(app: AppModel, generation: UUID) {
        self.app = app
        self.generation = generation
    }

    var rows: [AdminUser] { listState.value?.rows ?? [] }
    var total: Int? { listState.value?.total }
    var hasMore: Bool { listState.value?.hasMore ?? false }
    /// Balance records of this phone at the connected address (X34), one noun per user.
    var pendingNouns: [Int: String] {
        guard let app else { return [:] }
        return UserListPresentation.pendingNouns(app.pendingBalances, serverIDs: app.sameAddressServerIDs())
    }
    var pendingUserIDs: Set<Int> { Set(pendingNouns.keys) }
    var quickTopupEntries: [QuickTopupEntry] {
        guard let quickTopup, query.isEmpty else { return [] }
        return UserListPresentation.quickTopupEntries(recent: quickTopup.recent, lowBalance: quickTopup.lowBalance, pendingNouns: pendingNouns)
    }
    var isReadOnlyToken: Bool { app?.siteSession?.isReadOnlyToken ?? false }

    func todayCell(for userID: Int) -> UserTodayCell {
        UserListPresentation.todayCell(userID: userID, costs: todayCosts, isReadOnlyToken: isReadOnlyToken)
    }
    /// Pass `pendingUserIDs` read once when marking many rows.
    func mark(for user: AdminUser, pendingUserIDs: Set<Int>? = nil) -> UserListMark? {
        UserPresentation.listMark(user: user, hasPendingBalance: (pendingUserIDs ?? self.pendingUserIDs).contains(user.id),
                                 global: lowBalanceGlobal ?? .off)
    }
    func nextAutoRefreshDelay(now: Date) -> TimeInterval {
        UserListPresentation.autoRefreshDelay(lastRefreshAt: lastRefreshAt, refresh: refreshState, now: now)
    }

    // MARK: - Reads

    /// Back from a pushed page: nothing unless the list was never read or a write asked for it.
    func loadIfNeeded() async {
        guard listState.value == nil || needsRefresh else { return }
        await refresh()
    }
    /// The first page, the strip and today's spend of the loaded rows (30 §1.6). A refresh already running is awaited instead of
    /// repeated, so the pull spinner lasts until it ends; during a 429 wait nothing is sent.
    func refresh() async {
        if let running = firstPageTask { await running.value; return }
        guard isLive, refreshState.allowsRequest(at: Date()) else { return }
        needsRefresh = false
        let ticket = searchTicket
        let task = Task { [weak self] in
            guard let self else { return }
            await self.readFirstPage(ticket: ticket)
        }
        firstPageTask = task
        await task.value
        if firstPageTask == task { firstPageTask = nil }
    }
    /// A new search starts from page 1 with an empty list; a non-empty one hides the strip (30 §1.4).
    func search(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != query else { return }
        query = trimmed
        searchTicket = UUID()
        firstPageTask?.cancel()
        firstPageTask = nil
        listState = listState.withReset(during: refreshState, at: Date())
        if listState.failureReason == nil { failure = nil }
        nextPage = .idle
        if !trimmed.isEmpty { quickTopup = nil }
        await refresh()
    }
    /// The last row appeared: the next page, deduplicated by id, then today's spend of its new rows only.
    func loadNextPage() async {
        guard let app, isLive, nextPage == .idle, let snapshot = listState.value, snapshot.hasMore else { return }
        let ticket = searchTicket
        nextPage = .loading
        do {
            let next = try await app.users(query: UserListQuery(search: query, page: snapshot.page + 1))
            guard isCurrent(ticket) else { return }
            let known = Set(rows.map(\.id))
            listState = listState.updatingValue { $0.appending(next) }
            nextPage = .idle
            await readTodayCosts(for: next.items.map(\.id).filter { !known.contains($0) }, ticket: ticket)
        } catch {
            guard isCurrent(ticket) else { return }
            nextPage = error is CancellationError ? .idle : .failed
        }
    }
    func retryNextPage() async {
        guard nextPage == .failed else { return }
        nextPage = .idle
        await loadNextPage()
    }
    /// Hidden without `users.quick_topup`, during a search and after a failed read; never an error (30 §1.5).
    func refreshQuickTopup() async {
        guard let app, isLive else { return }
        guard query.isEmpty, app.siteSession?.has(.usersQuickTopup) == true else { quickTopup = nil; return }
        let ticket = searchTicket
        do {
            let reply = try await app.quickTopup()
            guard isCurrent(ticket) else { return }
            quickTopup = reply
        } catch {
            guard isCurrent(ticket), !(error is CancellationError) else { return }
            quickTopup = nil
        }
    }
    /// At most one successful read per session; a failure is silent and read again with the next refresh.
    func ensureLowBalanceGlobal() async {
        guard let app, isLive, lowBalanceGlobal == nil, !readingGlobal else { return }
        readingGlobal = true
        defer { readingGlobal = false }
        guard let global = try? await app.userListLowBalanceGlobal(), isLive else { return }
        lowBalanceGlobal = global
    }

    // MARK: - Writes from other pages

    /// The detail's latest copy of a row (30 §1.6); a user not loaded is not inserted.
    func replace(_ user: AdminUser) { listState = listState.updatingValue { $0.replacing(user) } }
    func remove(id: Int) {
        listState = listState.updatingValue { $0.removing(id: id) }
        quickTopup = quickTopup?.removing(id: id)
    }
    /// A balance write's confirmed result (30 §1.4); the strip's amount moves too.
    func updateBalance(id: Int, balance: Decimal) {
        listState = listState.updatingValue { $0.updatingBalance(id: id, balance: balance) }
        quickTopup = quickTopup?.updatingBalance(id: id, balance: balance)
    }
    /// The next appearance reads the first page again (a new user, a result whose balance is not known).
    func setNeedsRefresh() { needsRefresh = true }

    // MARK: - Internals

    private var isLive: Bool { app?.sessionGeneration == generation }
    private func isCurrent(_ ticket: UUID) -> Bool { isLive && ticket == searchTicket }

    private func readFirstPage(ticket: UUID) async {
        guard let app else { return }
        listState = listState.withLoading()
        async let strip: Void = refreshQuickTopup()
        async let global: Void = ensureLowBalanceGlobal()
        do {
            let first = try await app.users(query: UserListQuery(search: query, page: 1))
            if isCurrent(ticket) {
                show(first)
                await readTodayCosts(for: rows.map(\.id), ticket: ticket)
            }
        } catch {
            if isCurrent(ticket) { record(error) }
        }
        _ = await (strip, global)
    }
    private func show(_ first: Page<AdminUser>) {
        let now = Date()
        listState = .loaded(listState.value.map { $0.mergingFirstPage(first) } ?? UserListSnapshot(firstPage: first), at: now)
        failure = nil
        refreshState = refreshState.recordingSuccess()
        lastRefreshAt = now
    }
    /// A read the background or a new search stopped returns to the last value; others keep it with the failure (30 §1.5).
    private func record(_ error: any Error) {
        guard !(error is CancellationError) else { listState = listState.withCancelledLoad(); return }
        let now = Date()
        failure = UserListFailure(error)
        listState = listState.withFailure(error.localizedDescription)
        refreshState = refreshState.recordingFailure(error, at: now)
        lastRefreshAt = now
    }
    /// One request per batch, so a failed batch clears only its ids (“今日 —”); a read-only token sends none (R14).
    private func readTodayCosts(for ids: [Int], ticket: UUID) async {
        guard let app else { return }
        for batch in UserListPresentation.usageBatches(ids) {
            guard !isReadOnlyToken else { return }
            do {
                let reply = try await app.usersTodayUsage(ids: batch)
                guard isCurrent(ticket) else { return }
                todayCosts = UserListPresentation.mergingTodayCosts(reply, requested: batch, into: todayCosts)
            } catch {
                guard isCurrent(ticket), !(error is CancellationError) else { return }
                todayCosts = UserListPresentation.clearingTodayCosts(batch, from: todayCosts)
            }
        }
    }
}
