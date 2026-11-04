import Foundation
import Observation
import os
import Sub2Core

/// 50 §6–§7 reads as closures (S5-12): live goes to APIClient with the masked view fixed when made, `-ui-testing` to
/// GroupFixtures+Records; `group` reads through GroupStore.fetch so the list row stays current (S5D2a-10).
struct GroupRecordsSource: Sendable {
    var group: @MainActor @Sendable (_ id: Int) async throws -> AdminGroup
    var keys: @MainActor @Sendable (_ groupID: Int, _ page: Int) async throws -> Page<AdminAPIKey>
    var keysToday: @MainActor @Sendable (_ ids: [Int]) async throws -> [Int: Decimal]
    var subscriptions: @MainActor @Sendable (_ groupID: Int, _ page: Int) async throws -> Page<AdminUserSubscription>
    var stats: @MainActor @Sendable (_ groupID: Int) async throws -> GroupStats?
    var activeSubscriptionCount: @MainActor @Sendable (_ groupID: Int) async throws -> Int

    static func live(client: APIClient, maskedView: Bool, group: @escaping @MainActor @Sendable (_ id: Int) async throws -> AdminGroup) -> GroupRecordsSource {
        GroupRecordsSource(group: group,
                           keys: { try await client.groupAPIKeys(id: $0, page: $1, maskedView: maskedView) },
                           keysToday: { try await client.apiKeysTodayUsage(ids: $0) },
                           subscriptions: { try await client.groupSubscriptions(id: $0, page: $1) },
                           stats: { try await client.groupStats(id: $0) },
                           activeSubscriptionCount: { try await client.activeSubscriptionCount(groupID: $0) })
    }
}

enum GroupRecordsNextPage: Equatable, Sendable { case idle, loading, failed }
enum GroupRecordsPage: Equatable, Sendable { case skeleton, failure, deleted, content }

private let recordsLog = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "groups")

/// Page 1 on entry, pull and 重试; the next page when the footer shows; never polls (50 §6.6, §7.6). Replies for an older load or
/// an ended session are dropped. A 400 is logged with the path template and shown as the list failure; nothing sends it again
/// by itself (50 §6.5), and a failed refresh keeps the rows (00 §4.6).
@MainActor @Observable
final class GroupRecordsPager<Row: Decodable & Identifiable & Sendable> where Row.ID == Int {
    private(set) var state: BlockState<GroupRecordsFeed<Row>> = .idle
    private(set) var lastError: APIError?
    private(set) var nextPage: GroupRecordsNextPage = .idle
    private(set) var refresh = BlockRefresh()

    @ObservationIgnored private let pathTemplate: String
    @ObservationIgnored private let read: @MainActor @Sendable (_ page: Int) async throws -> Page<Row>
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Changes with every page-1 load; a page carrying an older one is dropped.
    @ObservationIgnored private var ticket = UUID()

    init(pathTemplate: String, read: @escaping @MainActor @Sendable (_ page: Int) async throws -> Page<Row>,
         isCurrent: @escaping @MainActor () -> Bool, now: @escaping @MainActor () -> Date) {
        self.pathTemplate = pathTemplate; self.read = read; self.isCurrent = isCurrent; self.now = now
    }

    var feed: GroupRecordsFeed<Row>? { state.value }
    var rows: [Row] { feed?.rows ?? [] }
    /// Never answered, or leaving and the background cancelled it; a failure waits for 重试 or a pull.
    var needsFirstRead: Bool { if case .idle = state { true } else { false } }

    /// Page 1; nil when nothing was read (a 429 wait, another session), it failed, was cancelled or was superseded.
    @discardableResult func reload() async -> [Row]? {
        guard isCurrent(), refresh.allowsRequest(at: now()) else { return nil }
        let ticket = UUID()
        self.ticket = ticket
        nextPage = .idle
        state = state.withLoading()
        do {
            let page = try await read(1)
            guard ticket == self.ticket else { return nil }
            guard isCurrent(), !Task.isCancelled else { state = state.withCancelledLoad(); return nil }
            let feed = GroupRecordsFeed(first: page)
            state = .loaded(feed, at: now())
            lastError = nil
            refresh = refresh.recordingSuccess()
            return feed.rows
        } catch {
            guard ticket == self.ticket else { return nil }
            guard isCurrent(), !(error is CancellationError) else { state = state.withCancelledLoad(); return nil }
            let failure = error as? APIError
            note(failure, page: 1)
            lastError = failure
            state = state.withFailure(GroupRecordsCopy.failureTitle(failure))
            refresh = refresh.recordingFailure(error, at: now())
            return nil
        }
    }
    /// The next page while there is one, nothing is being read and the last attempt did not fail; returns the rows it added.
    @discardableResult func loadMore() async -> [Row]? {
        guard isCurrent(), let feed, feed.hasMore, nextPage == .idle, !state.isLoading else { return nil }
        let ticket = self.ticket, number = feed.nextPage
        nextPage = .loading
        do {
            let page = try await read(number)
            guard ticket == self.ticket, isCurrent(), let current = self.feed else { return nil }
            let next = current.appending(page)
            state = state.updatingValue { _ in next }
            nextPage = .idle
            return Array(next.rows.dropFirst(current.rows.count))
        } catch {
            guard ticket == self.ticket, isCurrent() else { return nil }
            if error is CancellationError { nextPage = .idle; return nil }
            note(error as? APIError, page: number)
            nextPage = .failed
            return nil
        }
    }
    /// 加载失败 · 重试 under the rows.
    @discardableResult func retryMore() async -> [Row]? {
        guard nextPage == .failed else { return nil }
        nextPage = .idle
        return await loadMore()
    }

    private func note(_ error: APIError?, page: Int) {
        guard let error, GroupRecordsCopy.isParameterError(error) else { return }
        recordsLog.error("GET \(self.pathTemplate, privacy: .public) page \(page, privacy: .public) \(error.statusCode ?? 0, privacy: .public) \(error.reason ?? "-", privacy: .public) \(error.requestID ?? "-", privacy: .public)")
    }
}

/// 50 §6: one group's keys. Each page's today spend is read right after it arrives, in a Task this model owns (not the footer's
/// `.task`, which the arriving page would cancel); a read-only token never asks (R14) and every row says 今日 —. A failed read
/// keeps an amount shown before, marked 更新失败, until a read works (S5-高-3).
@MainActor @Observable
final class GroupKeysModel {
    let groupID: Int
    let pager: GroupRecordsPager<AdminAPIKey>
    /// The list's row or the directory's until read.
    private(set) var group: AdminGroup?
    private(set) var isDeleted = false
    private(set) var todayByID: [Int: GroupKeyToday] = [:]
    /// The today reads' failures and 429 wait (00 §2.7.2): the strip counts the wait down and 重试 waits it out.
    private(set) var todayRefresh = BlockRefresh()
    /// Observed: while a stale row is read again the strip stays, spinning.
    private var todayInFlight: Set<Int> = []

    @ObservationIgnored private let source: GroupRecordsSource
    @ObservationIgnored private let isReadOnlyToken: @MainActor () -> Bool
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var needsGroup: Bool
    @ObservationIgnored private var todayTicket = UUID()
    @ObservationIgnored private var todayTasks: [Task<Void, Never>] = []

    init(groupID: Int, snapshot: AdminGroup?, source: GroupRecordsSource, isReadOnlyToken: @escaping @MainActor () -> Bool,
         isCurrent: @escaping @MainActor () -> Bool, now: @escaping @MainActor () -> Date = { Date() }) {
        self.groupID = groupID; group = snapshot; needsGroup = snapshot == nil
        self.source = source; self.isReadOnlyToken = isReadOnlyToken; self.isCurrent = isCurrent; self.now = now
        pager = GroupRecordsPager(pathTemplate: "admin/groups/:id/api-keys", read: { page in try await source.keys(groupID, page) },
                                  isCurrent: isCurrent, now: now)
    }

    var page: GroupRecordsPage {
        if isDeleted { return .deleted }
        if pager.feed != nil { return .content }
        if case .failed = pager.state { return .failure }
        return .skeleton
    }
    var subtitle: String { GroupRecordsCopy.keysSubtitle(groupName: group?.name, total: pager.feed?.total) }
    func today(for keyID: Int) -> GroupKeyToday { isReadOnlyToken() ? .missing : todayByID[keyID] ?? .pending }
    /// S5-高-3: some row shows an amount kept through a failed read.
    var hasStaleToday: Bool { !isReadOnlyToken() && todayByID.values.contains(where: \.isStale) }
    /// A stale row's today is being read again.
    var isRetryingToday: Bool { todayByID.contains { $0.value.isStale && todayInFlight.contains($0.key) } }

    /// Every appearance and the foreground: page 1 when it was never read, the group when unknown, today for keys still pending.
    func start() async {
        guard !isDeleted, isCurrent() else { return }
        async let groupDone: Void = readGroup(force: false)
        if pager.needsFirstRead { await readFirstPage() } else { readToday(pendingIDs) }
        await groupDone
    }
    /// Pull and 重试: page 1 and the group together.
    func reload() async {
        guard !isDeleted, isCurrent() else { return }
        async let groupDone: Void = readGroup(force: true)
        await readFirstPage()
        await groupDone
    }
    func loadMore() async {
        guard !isDeleted, let added = await pager.loadMore() else { return }
        readToday(added.map(\.id))
    }
    func retryMore() async {
        guard !isDeleted, let added = await pager.retryMore() else { return }
        readToday(added.map(\.id))
    }
    /// 今日金额更新失败 · 重试: today again for the rows without a fresh amount, once a 429 wait is over.
    func retryToday() {
        guard todayRefresh.allowsRequest(at: now()) else { return }
        readToday(pager.rows.map(\.id).filter { todayByID[$0]?.isAmount != true && !todayInFlight.contains($0) })
    }
    /// Waits for the today reads this model started (tests).
    func settleTodayReads() async {
        while !todayTasks.isEmpty {
            let tasks = todayTasks
            todayTasks.removeAll()
            for task in tasks { await task.value }
        }
    }

    private var pendingIDs: [Int] { pager.rows.map(\.id).filter { todayByID[$0] == nil && !todayInFlight.contains($0) } }

    /// S5D2a-15: amounts of keys still on page 1 stay until the new read answers, marked stale if it fails (S5-高-3).
    private func readFirstPage() async {
        todayTicket = UUID()
        todayInFlight = []
        guard let rows = await pager.reload() else { return }
        let ids = Set(rows.map(\.id))
        todayByID = todayByID.filter { ids.contains($0.key) && $0.value.lastAmount != nil }
        readToday(rows.map(\.id))
    }
    private func readToday(_ ids: [Int]) {
        guard !ids.isEmpty, !isDeleted, isCurrent(), !isReadOnlyToken() else { return }
        let ticket = todayTicket, source = source
        todayInFlight.formUnion(ids)
        todayTasks.append(Task { [weak self] in
            let result: Result<[Int: Decimal], any Error>
            do { result = .success(try await source.keysToday(ids)) } catch { result = .failure(error) }
            self?.applyToday(result, ids: ids, ticket: ticket)
        })
    }
    /// A failure keeps an earlier amount marked stale and marks the rest 今日 —; a cancelled read stays as it was for the next start.
    private func applyToday(_ result: Result<[Int: Decimal], any Error>, ids: [Int], ticket: UUID) {
        guard ticket == todayTicket else { return }
        todayInFlight.subtract(ids)
        guard isCurrent(), !isDeleted else { return }
        switch result {
        case .success(let reply):
            for id in ids { todayByID[id] = .resolve(id: id, reply: reply) }
            todayRefresh = todayRefresh.recordingSuccess()
        case .failure(let error) where error is CancellationError: break
        case .failure(let error):
            for id in ids { todayByID[id] = (todayByID[id] ?? .pending).afterFailure }
            todayRefresh = todayRefresh.recordingFailure(error, at: now())
        }
    }
    private func readGroup(force: Bool) async {
        guard force || needsGroup, !isDeleted, isCurrent() else { return }
        do {
            let read = try await source.group(groupID)
            guard isCurrent() else { return }
            group = read
            needsGroup = false
        } catch {
            guard isCurrent(), !(error is CancellationError) else { return }
            needsGroup = false
            if let error = error as? APIError, GroupErrorCopy.resolve(error, context: .read).action == .treatAsDeleted { isDeleted = true }
        }
    }
}

/// 50 §7: one group's subscriptions. The limits come from the group (snapshot or read), the active count from groups/:id/stats
/// (subscriptions_active), on an older server from activeSubscriptionCount(groupID:); without either only the name shows.
@MainActor @Observable
final class GroupSubscriptionsModel {
    let groupID: Int
    let pager: GroupRecordsPager<AdminUserSubscription>
    private(set) var group: AdminGroup?
    /// The group read failed with no snapshot to show.
    private(set) var groupError: APIError?
    private(set) var isDeleted = false
    private(set) var activeCount: Int?
    /// S5-高-3: the count shown is an earlier read's, since the last one failed; a read that works clears it.
    private(set) var activeCountStale = false
    /// When the count shown was read (更新于 on its strip).
    private(set) var countUpdatedAt: Date?
    /// The count's failures and 429 wait (00 §2.7.2).
    private(set) var countRefresh = BlockRefresh()
    private var countReadsInFlight = 0

    @ObservationIgnored private let source: GroupRecordsSource
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var needsGroup: Bool
    @ObservationIgnored private var needsCount = true

    init(groupID: Int, snapshot: AdminGroup?, source: GroupRecordsSource, isCurrent: @escaping @MainActor () -> Bool,
         now: @escaping @MainActor () -> Date = { Date() }) {
        self.groupID = groupID; group = snapshot; needsGroup = snapshot == nil; self.source = source; self.isCurrent = isCurrent
        self.now = now
        pager = GroupRecordsPager(pathTemplate: "admin/groups/:id/subscriptions", read: { page in try await source.subscriptions(groupID, page) },
                                  isCurrent: isCurrent, now: now)
    }

    var page: GroupRecordsPage {
        if isDeleted { return .deleted }
        if group == nil, groupError != nil { return .failure }
        if pager.feed != nil, group != nil { return .content }
        if case .failed = pager.state { return .failure }
        return .skeleton
    }
    var failureError: APIError? { pager.lastError ?? groupError }
    var subtitle: String { GroupRecordsCopy.subscriptionsSubtitle(groupName: group?.name, active: activeCount) }
    /// The count is being read: a stale strip stays, spinning.
    var isReadingCount: Bool { countReadsInFlight > 0 }

    /// Entry: page 1, the active count and (without a snapshot) the group, side by side; shown again only what never answered.
    func start() async {
        guard !isDeleted, isCurrent() else { return }
        async let groupDone: Void = readGroup(force: false)
        async let countDone: Void = readActiveCount(force: false)
        if pager.needsFirstRead { await pager.reload() }
        _ = await (groupDone, countDone)
    }
    /// Pull and 重试: all three again; a failed group read keeps the one shown.
    func reload() async {
        guard !isDeleted, isCurrent() else { return }
        async let groupDone: Void = readGroup(force: true)
        async let countDone: Void = readActiveCount(force: true)
        await pager.reload()
        _ = await (groupDone, countDone)
    }
    func loadMore() async { if !isDeleted { await pager.loadMore() } }
    func retryMore() async { if !isDeleted { await pager.retryMore() } }
    /// 生效中计数更新失败 · 重试: the count alone, once a 429 wait is over.
    func retryActiveCount() async { await readActiveCount(force: true) }

    private func readGroup(force: Bool) async {
        guard force || needsGroup, !isDeleted, isCurrent() else { return }
        do {
            let read = try await source.group(groupID)
            guard isCurrent() else { return }
            group = read; groupError = nil; needsGroup = false
        } catch {
            guard isCurrent(), !(error is CancellationError) else { return }
            needsGroup = false
            let failure = error as? APIError
            if let failure, GroupErrorCopy.resolve(failure, context: .read).action == .treatAsDeleted { isDeleted = true; return }
            groupError = failure ?? APIError(kind: .response, message: BlockStatusPresentation.loadFailed)
        }
    }
    /// A failed read keeps the count shown, marked stale (S5D2a-15, S5-高-3); stats failing is not an older server, so it does not
    /// fall back. Nothing is sent during a 429 wait.
    private func readActiveCount(force: Bool) async {
        guard force || needsCount, !isDeleted, isCurrent(), countRefresh.allowsRequest(at: now()) else { return }
        let source = source, id = groupID
        countReadsInFlight += 1
        defer { countReadsInFlight -= 1 }
        do {
            let count: Int
            if let stats = try await source.stats(id) { count = stats.subscriptionsActive } else { count = try await source.activeSubscriptionCount(id) }
            guard isCurrent() else { return }
            activeCount = count; needsCount = false; activeCountStale = false
            countUpdatedAt = now(); countRefresh = countRefresh.recordingSuccess()
        } catch {
            guard isCurrent(), !(error is CancellationError) else { return }
            needsCount = false
            countRefresh = countRefresh.recordingFailure(error, at: now())
            activeCountStale = activeCount != nil
        }
    }
}
