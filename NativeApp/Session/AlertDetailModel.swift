import Foundation
import Observation
import Sub2Core

/// 10 §3: one alert's page. The event shows from the session's lists at once, then `GET alert-events/:id` corrects it; while the
/// page shows it is read every 60 seconds. 范围 reads only the row the event's dimension needs, and each row fails on its own
/// (§3.5). What shows is LiveOpsStore's copy, so a write from this page or any other shows here at once.
@MainActor @Observable
final class AlertDetailModel {
    enum Phase: Equatable, Sendable { case loading, ready, notFound, opsDisabled, failed }
    nonisolated static let pollInterval: TimeInterval = 60

    let eventID: Int
    private(set) var phase: Phase = .loading
    /// 400 Invalid event ID is a program error: the page goes back (10 §3.5).
    private(set) var dismissRequested = false
    let eventLoad = LoadState<AlertEvent>()
    let groupLoad = LoadState<AlertGroupScope>()
    let channelLoad = LoadState<ChannelOverview>()
    /// S1-17: 错误请求 / 上游错误 · 近 24 小时 N 条, read with 范围 and never polled.
    let errorCountLoad = LoadState<Int>()
    @ObservationIgnored private let store: LiveOpsStore
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    /// The latest event read; an older one that ends later changes nothing.
    @ObservationIgnored private var readTicket = UUID()

    init(eventID: Int, store: LiveOpsStore, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.eventID = eventID; self.store = store; self.sleep = sleep
    }

    /// None once the server said the event is gone or ops monitoring is off.
    var event: AlertEvent? {
        guard phase != .notFound, phase != .opsDisabled else { return nil }
        return store.alert(id: eventID)
    }
    var scopeKind: AlertScopeKind? { event.map(AlertScopePresentation.kind) }
    /// The status card's block state with the shown copy as its value, so S1-08's accessory says 正在刷新 or 更新失败 beside it.
    var eventState: BlockState<AlertEvent> {
        guard let shown = event else { return eventLoad.state }
        let at = eventLoad.updatedAt ?? Date()
        switch eventLoad.state {
        case .loading: return .loading(previous: shown, at: at)
        case .failed(let reason, _, _): return .failed(reason: reason, previous: shown, at: at)
        case .idle, .loaded, .disabled: return .loaded(shown, at: at)
        }
    }
    /// 403 CHANNEL_MONITOR_DISABLED: the channel row says 渠道监控未开启 rather than 加载失败.
    var channelMonitorDisabled: Bool { AlertScopePresentation.isChannelMonitorDisabled(channelLoad.lastError) }
    /// The error-count row of a group's or a site-wide error rule (10 §3.3); nil for every other event.
    var errorCountQuery: AlertErrorCountQuery? { event.flatMap(AlertScopePresentation.errorCountQuery) }

    /// Entry, a pull (which also reads an old server's rules and group names again), a write, the foreground, compliance passed
    /// or ops monitoring back on. Polling passes `refreshScope: false` and reads only the event. The error count waits for the
    /// event, so a gone event or ops monitoring found off sends none and an old server's rule is filled in first.
    func load(refreshScope: Bool, pullToRefresh: Bool = false) async {
        guard store.isCurrent() else { return }
        if pullToRefresh { store.invalidateLegacyAlertLookups() }
        let shown = event
        async let read: Void = readEvent()
        if refreshScope, let shown { await readScope(of: shown, bypassChannelCache: pullToRefresh) }
        await read
        guard refreshScope else { return }
        async let count: Void = readErrorCount()
        if shown == nil, let fresh = event { await readScope(of: fresh, bypassChannelCache: pullToRefresh) }
        await count
    }
    /// The group row's 重试.
    func retryGroup() async {
        guard case .group(let id)? = scopeKind else { return }
        await readGroup(id)
    }
    /// The channel row's 重试, past the monitor's list.
    func retryChannels() async {
        guard case .platform? = scopeKind else { return }
        await readChannels(bypassCache: true)
    }
    /// The error-count row's 重试: only the count.
    func retryErrorCount() async { await readErrorCount() }
    /// 10 §3.6 while the page shows and the App is active: the event every 60 seconds from the end of the last read (longer after
    /// failures, or the rest of a 429 wait, S1D1-20), until the task is cancelled or the event is gone.
    func polling() async {
        while !Task.isCancelled, store.isCurrent(), phase != .notFound {
            do { try await sleep(.seconds(eventLoad.nextDelay(base: Self.pollInterval))) } catch { return }
            await load(refreshScope: false)
        }
    }

    // MARK: 读取

    private func readEvent() async {
        let store = store, id = eventID, before = eventLoad.updatedAt, ticket = UUID(), failure = ReadFailure()
        readTicket = ticket
        await eventLoad.load(isCurrent: store.isCurrent) {
            do { return try await store.fetchAlert(id: id) } catch { failure.error = error; throw error }
        }
        guard ticket == readTicket, store.isCurrent(), !Task.isCancelled else { return }
        if case .loaded(_, let at) = eventLoad.state, at != before {
            phase = .ready
            return
        }
        guard let error = failure.error, !(error is CancellationError) else { return }
        settle(after: error)
    }
    /// 10 §3.5. Any other failure keeps what shows (更新失败 beside it), or says 加载失败 when nothing does.
    private func settle(after error: any Error) {
        switch AlertScopePresentation.failure(error as? APIError) {
        case .notFound: phase = .notFound
        case .opsDisabled: phase = .opsDisabled
        case .invalidID: dismissRequested = true
        case .other:
            guard phase == .loading || phase == .failed else { return }
            phase = store.alert(id: eventID) == nil ? .failed : .ready
        }
    }
    private func readScope(of event: AlertEvent, bypassChannelCache: Bool) async {
        switch AlertScopePresentation.kind(event) {
        case .group(let id): await readGroup(id)
        case .platform: await readChannels(bypassCache: bypassChannelCache)
        case .server, .siteWide: break
        }
    }
    private func readGroup(_ groupID: Int) async {
        let store = store
        await groupLoad.load(isCurrent: store.isCurrent) { try await store.alertGroupScope(groupID: groupID) }
    }
    private func readChannels(bypassCache: Bool) async {
        let store = store
        await channelLoad.load(isCurrent: store.isCurrent) { try await store.alertChannelScope(bypassCache: bypassCache) }
    }
    /// Only while ops monitoring is on (10 §3.2) and the page stays.
    private func readErrorCount() async {
        guard let query = errorCountQuery, !dismissRequested, !store.opsDisabled else { return }
        let store = store
        await errorCountLoad.load(isCurrent: store.isCurrent) { try await store.alertErrorCount(query) }
    }
}

extension AlertScopeDestination {
    /// The rows that push onto this tab's stack (X39): the group, and the error logs by the event's group (10 §3.1); the monitor
    /// rows switch tabs instead.
    var pushedRoute: AppRoute? {
        switch self {
        case .group(let id): .group(id: id)
        case .logs(let kind, let groupID, let groupName):
            .logs(LogsRoute(scope: kind == .upstream ? .upstream : .errors, group: groupID.map { RouteObject(id: $0, name: groupName) }))
        case .monitorChannels, .monitorOverview: nil
        }
    }
}

/// The error of one event read, which LoadState keeps only as text.
@MainActor private final class ReadFailure { var error: (any Error)? }
