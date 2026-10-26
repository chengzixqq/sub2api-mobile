import Foundation
import Observation
import Sub2Core

/// C-9, 10 §0.5: the session's home blocks, alert list and ops state, shared by the overview, the monitor tab, alert details and
/// the account tab (20 §1.2), so a resolve or silence shows everywhere at once. AppModel makes one in `publish` and drops it in
/// `endActiveSession`; a reply is written only while its session is current. S1-06, S1-07, S1-08 and S1-13 extend it in their
/// own files through the internal members below (S1D1-24).
@MainActor @Observable
final class LiveOpsStore {
    nonisolated static let pollInterval: TimeInterval = 60
    nonisolated static let alertListMaxAge: TimeInterval = 60
    nonisolated static let countdownRefreshGap: TimeInterval = 10
    /// 10 §6.2, 20 §1.2.
    nonisolated static let firingListLimit = 100
    /// 10 §0.2 without `ops.alert_event_counts`: one read is both the list and the count.
    nonisolated static let firingCountingLimit = 500
    nonisolated static let rankingLimit = 4
    nonisolated static let opsDisabledReason = "OPS_DISABLED"

    let generation: UUID
    let source: any LiveOpsSource
    let site: @MainActor () -> SiteSession?
    let isCurrent: @MainActor () -> Bool
    /// X16: AppModel's current badge, read when a new availability arrives.
    let errorBadge: @MainActor () -> AccountErrorBadge?
    let serverNow: @Sendable () -> Date
    /// The device clock for reuse windows and throttling; only elapsed time matters.
    let localNow: @MainActor () -> Date
    let sleep: @Sendable (Duration) async throws -> Void

    /// The dashboard/home request: its guard, 429 wait and backoff (S1D1-03). The blocks are in `home`.
    let homeRequest = LoadState<DashboardHome>()
    private(set) var home = HomeBlocks()
    /// 今日 SLA: the ops overview from the server's midnight (10 §1.2 附加请求).
    let todayOps = LoadState<OpsOverview>()
    let structuredErrorsRequest = LoadState<[UpstreamAccount]>()
    /// The calm layout's 按账号, read only while it shows (10 §2.3).
    let ranking = LoadState<[AccountsRankingItem]>()
    /// Firing events only; the monitor's 告警中 and the account tab's group headers share it (20 §1.2).
    let firing = LoadState<[AlertEvent]>()
    /// 最近结束: S1-16 loads it; `markResolved` moves an event in.
    let recent = LoadState<RecentAlerts>()
    /// The monitor's channel list (S1-15); the home page's channel counts are `home.channels`.
    let channels = LoadState<ChannelOverview>()
    /// No `dashboard.home`: S1-07's per-endpoint fallback takes over.
    private(set) var needsFallback = false
    private(set) var isCalmVisible = false
    private var countsValue: AlertCounts?
    /// What the latest reply said about ops monitoring (10 §7.2); nil until one says. Only the three entries below set it (S1D1-02).
    private var opsEvidence: Bool?
    @ObservationIgnored private var appliedHomeAt: Date?
    @ObservationIgnored private var structuredFetchedIDs: Set<Int>?
    @ObservationIgnored private var structuredPendingIDs: Set<Int>?
    @ObservationIgnored private var externalWritePending = false
    @ObservationIgnored private var lastCountdownRefreshAt: Date?
    @ObservationIgnored private var firingFetchedAt: Date?
    @ObservationIgnored private var rankingFetchedAt: Date?
    /// The read `setCalmVisible(true)` started.
    @ObservationIgnored private(set) var rankingTask: Task<Void, Never>?

    init(generation: UUID, source: any LiveOpsSource, site: @escaping @MainActor () -> SiteSession?, isCurrent: @escaping @MainActor () -> Bool,
         errorBadge: @escaping @MainActor () -> AccountErrorBadge? = { nil }, serverNow: @escaping @Sendable () -> Date,
         localNow: @escaping @MainActor () -> Date = { Date() },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.generation = generation; self.source = source; self.site = site; self.isCurrent = isCurrent; self.errorBadge = errorBadge
        self.serverNow = serverNow; self.localNow = localNow; self.sleep = sleep
    }

    var availability: AccountStatusSummary? { home.availability.value }
    var todaySLA: Double? { opsDisabled ? nil : todayOps.value?.sla }
    /// The structured fields of availability's error accounts, in its order.
    var structuredErrors: [UpstreamAccount] { availability?.aligningStructuredErrors(structuredErrorsRequest.value ?? []) ?? [] }
    var firingAlerts: [AlertEvent] { opsDisabled ? [] : firing.value ?? [] }
    var recentAlerts: [AlertEvent] { recent.value?.events ?? [] }
    /// Firing events by level, silenced ones included: home's alerts block, `alert-events/counts`, or the counted list.
    var alertCounts: AlertCounts? { opsDisabled ? nil : countsValue }
    /// The latest reply wins; before any, `/admin/me`'s `features.ops_monitoring_enabled`.
    var opsDisabled: Bool { opsEvidence ?? (site()?.me.features.opsMonitoringEnabled == false) }
    /// The local time of the last home reply without a failed block (S0-05).
    var lastFullSuccessAt: Date? { home.lastFullSuccessAt }
    var homeFailed: Bool { homeRequest.error != nil }
    /// The block's 429 wait and backoff; S1-07 answers per block while on the fallback.
    func homeRefresh(for key: HomeSectionKey) -> BlockRefresh { homeRequest.refresh }

    // MARK: - 首页（10 §1.2、§1.6）

    /// Home and the extra reads side by side. A pull passes `noCache`; so does the first refresh after another page wrote.
    func refreshHome(noCache: Bool) async {
        guard isCurrent(), let site = site() else { return }
        let wrote = takeExternalWrite()
        let skipsSLA = opsDisabled
        async let main: Void = refreshHomeBlocks(site: site, noCache: noCache || wrote)
        async let sla: Void = loadTodaySLA(zone: site.serverTimeZone, skipped: skipsSLA)
        async let rank: Void = refreshRanking()
        _ = await (main, sla, rank)
    }
    /// 00 §4.6: refresh, then wait 60 seconds (doubled after failures up to 300, or the rest of a 429 wait), for as long as the
    /// caller's task lives. A refresh already in flight, such as a pull, is left to finish.
    func homePolling() async {
        while !Task.isCancelled, isCurrent() {
            if !homeRequest.isLoading { await refreshHome(noCache: false) }
            do { try await self.sleep(.seconds(homeRequest.nextDelay(base: Self.pollInterval))) } catch { return }
        }
    }
    /// A countdown on the page reached zero: at most one refresh in ten seconds.
    func countdownElapsed() async {
        let now = localNow()
        if let last = lastCountdownRefreshAt, Self.isWithin(Self.countdownRefreshGap, since: last, now: now) { return }
        lastCountdownRefreshAt = now
        guard !homeRequest.isLoading else { return }
        await refreshHome(noCache: false)
    }
    /// 10 §1.4, X17: another page wrote; the next home read bypasses the server cache.
    func noteExternalWrite() { externalWritePending = true }

    /// The calm layout appeared or went away (S1-11). Shown again: one read at once unless the last is under a minute old.
    func setCalmVisible(_ visible: Bool) {
        guard visible != isCalmVisible else { return }
        isCalmVisible = visible
        guard visible else { rankingTask?.cancel(); ranking.cancel(); return }
        if ranking.value != nil, let fetched = rankingFetchedAt, Self.isWithin(Self.pollInterval, since: fetched, now: localNow()) { return }
        rankingTask = Task { [weak self] in await self?.refreshRanking() }
    }
    /// 10 §2.3: only while the calm layout shows and the site has `dashboard.accounts_ranking`.
    func refreshRanking() async {
        guard isCalmVisible, isCurrent(), let site = site(), site.has(.dashboardAccountsRanking) else { return }
        let source = source, zone = site.serverTimeZone, limit = Self.rankingLimit, before = ranking.updatedAt
        await ranking.load(isCurrent: isCurrent) { try await source.accountsRanking(limit: limit, timezone: zone) }
        if case .loaded(_, let at) = ranking.state, at != before { rankingFetchedAt = localNow() }
    }

    /// The only way other files (S1-07's fallback) write the blocks; nothing changes once the session did.
    func replaceHome(_ transform: (HomeBlocks) -> HomeBlocks) {
        guard isCurrent() else { return }
        home = transform(home)
    }
    func recordFullSuccess(at date: Date) {
        replaceHome { var next = $0; next.lastFullSuccessAt = date; return next }
    }
    /// After a new availability value: the account tab badge (X16) and the error accounts' structured fields, read again only
    /// when their ids changed (10 §1.6). S1-07's fallback calls it too.
    func applyAvailabilityFollowUps() async {
        guard isCurrent(), case .loaded(let summary, let at) = home.availability else { return }
        errorBadge()?.update(errorCount: summary.totals.error, at: at)
        await refreshStructuredErrors(summary)
    }

    private func refreshHomeBlocks(site: SiteSession, noCache: Bool) async {
        guard site.has(.dashboardHome) else { needsFallback = true; return }
        needsFallback = false
        let source = source, zone = site.serverTimeZone
        await homeRequest.load(isCurrent: isCurrent) { try await source.dashboardHome(timezone: zone, include: nil, noCache: noCache) }
        guard isCurrent(), case .loaded(let reply, let at) = homeRequest.state, at != appliedHomeAt else { return }
        appliedHomeAt = at
        await applyHome(reply, receivedAt: at)
    }
    /// A whole-home failure leaves every block as it was (10 §1.5); a newer reply applied meanwhile wins.
    private func applyHome(_ reply: DashboardHome, receivedAt at: Date) async {
        let top = reply.alerts.data?.top ?? []
        let normalized = top.isEmpty ? top : await normalizeReceivedAlerts(top)
        guard isCurrent(), appliedHomeAt == at else { return }
        var next = home.merging(reply, receivedAt: at)
        if reply.alerts.status == .ok {
            next.alerts = next.alerts.updatingValue { HomeAlerts(firingCount: $0.firingCount, bySeverity: $0.bySeverity, top: normalized) }
        }
        home = next
        if let alerts = reply.alerts.data { countsValue = AlertCounts(firing: alerts.firingCount, bySeverity: alerts.bySeverity) }
        switch reply.opsDisabledEvidence {
        case true?: await noteOpsDisabled()
        case false?: noteOpsAvailable()
        case nil: break
        }
        await applyAvailabilityFollowUps()
    }
    private func loadTodaySLA(zone: ServerTimeZone, skipped: Bool) async {
        let end = serverNow(), start = zone.calendar.startOfDay(for: end)
        guard !skipped, start < end else { todayOps.reset(); return }
        await todayOps.load(isCurrent: isCurrent, operation: controlled { try await $0.opsOverview(start: start, end: end) })
    }
    /// A failed read is tried again on the next refresh; a 429 wait holds it back.
    private func refreshStructuredErrors(_ summary: AccountStatusSummary) async {
        let wanted = Set(summary.errorAccountIDs)
        guard site()?.has(.accountsStructuredError) == true, summary.totals.error > 0, !wanted.isEmpty else {
            structuredFetchedIDs = nil
            return
        }
        guard wanted != structuredFetchedIDs, wanted != structuredPendingIDs else { return }
        structuredPendingIDs = wanted
        let source = source, before = structuredErrorsRequest.updatedAt
        await structuredErrorsRequest.load(isCurrent: isCurrent) { try await source.errorAccounts() }
        guard structuredPendingIDs == wanted else { return }
        structuredPendingIDs = nil
        if case .loaded(_, let at) = structuredErrorsRequest.state, at != before { structuredFetchedIDs = wanted }
    }
    /// Kept through a 429 wait, so the write still bypasses the cache once a request goes out.
    private func takeExternalWrite() -> Bool {
        guard externalWritePending, homeRequest.refresh.allowsRequest(at: Date()) else { return false }
        externalWritePending = false
        return true
    }

    // MARK: - 告警（10 §6.2、§7.1；20 §1.2）

    /// The one firing list. Read within `maxAge` seconds: reused as is (0 forces a read). Without `ops.alert_event_counts` one
    /// read of up to 500 is both the list and the count.
    func refreshFiringAlerts(maxAge: TimeInterval = LiveOpsStore.alertListMaxAge) async {
        guard isCurrent(), let site = site() else { return }
        guard !opsDisabled else { firing.reset(); return }
        if firing.value != nil, let fetched = firingFetchedAt, Self.isWithin(maxAge, since: fetched, now: localNow()) { return }
        if maxAge > 0, firing.isLoading { return }
        let exact = site.has(.opsAlertEventCounts)
        async let list: Void = loadFiring(limit: exact ? Self.firingListLimit : Self.firingCountingLimit, countsFromList: !exact)
        async let counts: Void = loadAlertCounts(skipped: !exact)
        _ = await (list, counts)
    }
    /// 20 §1.3 group header: firing events of a platform, ignoring case.
    func firingAlerts(platform: String) -> [AlertEvent] {
        let wanted = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        return firingAlerts.filter { $0.platform?.caseInsensitiveCompare(wanted) == .orderedSame }
    }
    /// 10 §1.4, §7.1 step 3: a confirmed manual resolve leaves the lists and the counts at once; S1-06 reads them again after.
    func markResolved(eventID: Int, at date: Date) {
        guard isCurrent(), let event = knownFiringEvent(eventID) else { return }
        firing.updateValue { $0.filter { $0.id != eventID } }
        home.alerts = home.alerts.updatingValue { $0.removingFiring(event) }
        countsValue = countsValue?.removingFiring(severity: event.severity)
        recent.updateValue { $0.upserting(event.resolvedLocally(at: date)) }
    }
    /// A new, changed or ended (nil) silence on every copy of the event; the counts keep it (a silenced event still fires).
    func applySilence(eventID: Int, _ silence: AlertSilenceRef?) {
        guard isCurrent() else { return }
        let update: (AlertEvent) -> AlertEvent = { $0.id == eventID ? $0.withSilence(silence) : $0 }
        firing.updateValue { $0.map(update) }
        home.alerts = home.alerts.updatingValue { $0.mapEvents(update) }
        recent.updateValue { $0.mapEvents(update) }
    }
    /// S1D1-16: every event read passes here; S1-07 fills in rules and group names for servers without `ops.alert_event_details`.
    func normalizeReceivedAlerts(_ events: [AlertEvent]) async -> [AlertEvent] { events }

    private func loadFiring(limit: Int, countsFromList: Bool) async {
        let fetch = controlled { try await $0.alertEvents(status: "firing", timeRange: nil, limit: limit, before: nil, groupID: nil, platform: nil) }
        let before = firing.updatedAt
        await firing.load(isCurrent: isCurrent) { [weak self] in
            let events = try await fetch()
            guard let self else { throw CancellationError() }
            return await self.normalizeReceivedAlerts(events).filter(\.isFiring)
        }
        guard case .loaded(let events, let at) = firing.state, at != before else { return }
        firingFetchedAt = localNow()
        if countsFromList { countsValue = AlertCounts.counting(events) }
    }
    /// A failed count read keeps the last counts; the list beside it reports the failure.
    private func loadAlertCounts(skipped: Bool) async {
        guard !skipped, let counts = try? await controlled({ try await $0.alertEventCounts() })(), isCurrent() else { return }
        countsValue = counts
    }
    private func knownFiringEvent(_ id: Int) -> AlertEvent? {
        ((firing.value ?? []) + (home.alerts.value?.top ?? [])).first { $0.id == id && $0.isFiring }
    }

    // MARK: - 运维监控开关（10 §7.2，S1D1-02：唯一入口，S1-08 只改函数体）

    func noteOpsDisabled() async { opsEvidence = true }
    func noteOpsAvailable() { opsEvidence = false }
    /// A gated read's result: success says on, 404 OPS_DISABLED says off, any other failure says nothing.
    func recordOpsResponse(_ error: (any Error)?) async {
        guard isCurrent() else { return }
        guard let error else { return noteOpsAvailable() }
        guard let failure = error as? APIError, failure.statusCode == 404, failure.reason == Self.opsDisabledReason else { return }
        await noteOpsDisabled()
    }
    /// Wraps a read that ops monitoring gates, reporting its outcome through `recordOpsResponse`.
    func controlled<T: Sendable>(_ call: @escaping @Sendable (any LiveOpsSource) async throws -> T) -> @MainActor @Sendable () async throws -> T {
        let source = source
        return { [weak self] in
            do {
                let value = try await call(source)
                await self?.recordOpsResponse(nil)
                return value
            } catch {
                await self?.recordOpsResponse(error)
                throw error
            }
        }
    }

    private static func isWithin(_ interval: TimeInterval, since start: Date, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(start)
        return elapsed >= 0 && elapsed < interval
    }
}
