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
    /// The blocks' wait and backoff come from S1-07's per-endpoint fallback: no `dashboard.home`, or home answered 404 or the
    /// network failed. Any other home failure hands them back to the home request.
    private(set) var isOnFallback = false
    private(set) var isCalmVisible = false
    private var countsValue: AlertCounts?
    /// The ops switch: the latest signal, its reason and a write on its way (10 §7.2). Only the three entries below and
    /// LiveOpsStore+OpsSwitch.swift write it (S1D1-02).
    var opsSwitch = OpsSwitchState()
    @ObservationIgnored private var appliedHomeAt: Date?
    @ObservationIgnored private var structuredFetchedIDs: Set<Int>?
    @ObservationIgnored private var structuredPendingIDs: Set<Int>?
    @ObservationIgnored private var externalWritePending = false
    @ObservationIgnored private var lastCountdownRefreshAt: Date?
    @ObservationIgnored private var firingFetchedAt: Date?
    @ObservationIgnored private var rankingFetchedAt: Date?
    /// The read `setCalmVisible(true)` started.
    @ObservationIgnored private(set) var rankingTask: Task<Void, Never>?
    /// C-6, S1-06: 手动解决 and 静默 for every page, writing through this store's lists; receipts go to AppModel's center.
    let alertActions: AlertActions
    /// AppModel's center, for the ops switch's receipts (S1-08).
    let receipts: ReceiptCenter

    init(generation: UUID, source: any LiveOpsSource, site: @escaping @MainActor () -> SiteSession?, isCurrent: @escaping @MainActor () -> Bool,
         errorBadge: @escaping @MainActor () -> AccountErrorBadge? = { nil }, serverNow: @escaping @Sendable () -> Date,
         localNow: @escaping @MainActor () -> Date = { Date() },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         receipts: ReceiptCenter = ReceiptCenter()) {
        self.generation = generation; self.source = source; self.site = site; self.isCurrent = isCurrent; self.errorBadge = errorBadge
        self.serverNow = serverNow; self.localNow = localNow; self.sleep = sleep; self.receipts = receipts
        alertActions = AlertActions(source: source, receipts: receipts, timeZone: { site()?.serverTimeZone.timeZone ?? .gmt }, now: serverNow)
        alertActions.host = self
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
    var opsDisabled: Bool { opsSwitch.isDisabled(snapshot: site()?.me.features.opsMonitoringEnabled == false) }
    /// The local time of the last home reply without a failed block (S0-05).
    var lastFullSuccessAt: Date? { home.lastFullSuccessAt }
    var homeFailed: Bool { homeRequest.error != nil }
    /// The block's 429 wait and backoff; on the fallback each block keeps its own (S1-07).
    func homeRefresh(for key: HomeSectionKey) -> BlockRefresh { isOnFallback ? fallbackStatus[key]?.refresh ?? BlockRefresh() : homeRequest.refresh }
    /// The error behind the block's failure row (S1-08): home's own, or the block's own on the fallback.
    func homeLastError(for key: HomeSectionKey) -> APIError? { isOnFallback ? fallbackStatus[key]?.lastError : homeRequest.lastError }

    // MARK: - 首页（10 §1.2、§1.6）

    /// Home and the extra reads side by side (a pull passes `noCache`); an extra read already in flight is left to finish.
    func refreshHome(noCache: Bool) async {
        guard isCurrent(), site() != nil else { return }
        if noCache { invalidateLegacyAlertLookups() }
        let skipsSLA = opsDisabled
        async let main: Void = refreshHomeBlocks(noCache: noCache)
        async let sla: Void = refreshTodaySLA(skipped: skipsSLA)
        async let rank: Void = refreshRanking()
        _ = await (main, sla, rank)
    }
    /// 00 §4.6, 10 §1.2: home, 今日 SLA and the calm ranking each keep their own timer for as long as the caller's task lives, so
    /// a slow read never holds back the others: refresh, then wait 60 seconds from its end (doubled after failures up to 300, or
    /// the rest of a 429 wait). A read already in flight, such as a pull, is left to finish.
    func homePolling() async {
        async let blocks: Void = pollHomeBlocks()
        async let sla: Void = pollTodaySLA()
        async let rank: Void = pollRanking()
        _ = await (blocks, sla, rank)
    }
    /// The home request's own timer; its follow-ups (the structured errors) wait with it.
    func pollHomeBlocks() async {
        await poll {
            if !isHomeLoading { await refreshHomeBlocks(noCache: false) }
            return nextHomeDelay()
        }
    }
    /// On the fallback, the shortest wait of its blocks (S1D1-03).
    func nextHomeDelay() -> TimeInterval { isOnFallback ? fallbackNextDelay() : homeRequest.nextDelay(base: Self.pollInterval) }
    /// A countdown on the page reached zero: at most one home read in ten seconds; the extra reads keep their own timers.
    func countdownElapsed() async {
        let now = localNow()
        if let last = lastCountdownRefreshAt, Self.isWithin(Self.countdownRefreshGap, since: last, now: now) { return }
        lastCountdownRefreshAt = now
        guard !isHomeLoading else { return }
        await refreshHomeBlocks(noCache: false)
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
    /// 10 §2.3: only while the calm layout shows and the site has `dashboard.accounts_ranking`; a read in flight is left to finish.
    func refreshRanking() async {
        guard isCalmVisible, !ranking.isLoading, isCurrent(), let site = site(), site.has(.dashboardAccountsRanking) else { return }
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

    /// The first read after another page wrote bypasses the cache too. 10 §1.2: without `dashboard.home`, or when home answers
    /// 404 (not asked again this session) or the network fails (home is tried again next time), the blocks come from the fallback.
    private func refreshHomeBlocks(noCache: Bool) async {
        guard isCurrent(), let site = site() else { return }
        let noCache = noCache || takeExternalWrite()
        guard site.has(.dashboardHome), !homeEndpointMissing else { return await startFallback(noCache: noCache) }
        let source = source, zone = site.serverTimeZone, failure = HomeFailure()
        await homeRequest.load(isCurrent: isCurrent) {
            do { return try await source.dashboardHome(timezone: zone, include: nil, noCache: noCache) } catch { failure.error = error; throw error }
        }
        if let error = failure.error, isCurrent(), !homeRequest.isLoading {
            if HomeFallback.shouldFallBack(afterHomeError: error) {
                if HomeFallback.isMissingEndpoint(error) { homeEndpointMissing = true }
                homeRequest.reset()
                return await startFallback(noCache: noCache)
            }
            // Any other failure home recorded (a 5xx, a 429): its own wait and backoff count again (00 §4.6); the blocks stay.
            if homeRequest.error != nil { isOnFallback = false }
        }
        guard isCurrent(), case .loaded(let reply, let at) = homeRequest.state, at != appliedHomeAt else { return }
        appliedHomeAt = at
        await applyHome(reply, receivedAt: at)
    }
    /// A whole-home failure leaves every block as it was (10 §1.5); a newer reply applied meanwhile wins.
    private func applyHome(_ reply: DashboardHome, receivedAt at: Date) async {
        let top = reply.alerts.data?.top ?? []
        let normalized = top.isEmpty ? top : await normalizeReceivedAlerts(top)
        guard isCurrent(), appliedHomeAt == at else { return }
        // A fallback round still on its way no longer lands.
        isOnFallback = false; ratesSource = .home; fallbackCycle = nil
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
    /// 今日 SLA from the server's midnight, none while ops monitoring is off; a read in flight is left to finish.
    private func refreshTodaySLA(skipped: Bool) async {
        guard !todayOps.isLoading, isCurrent(), let zone = site()?.serverTimeZone else { return }
        let end = serverNow(), start = zone.calendar.startOfDay(for: end)
        guard !skipped, start < end else { todayOps.reset(); return }
        await todayOps.load(isCurrent: isCurrent, operation: controlled { try await $0.opsOverview(start: start, end: end) })
    }
    private func pollTodaySLA() async {
        await poll { await refreshTodaySLA(skipped: opsDisabled); return todayOps.nextDelay(base: Self.pollInterval) }
    }
    /// Only on a site with `dashboard.accounts_ranking`; a tick reads only while the calm layout shows.
    private func pollRanking() async {
        guard site()?.has(.dashboardAccountsRanking) == true else { return }
        await poll { await refreshRanking(); return ranking.nextDelay(base: Self.pollInterval) }
    }
    /// One block's timer: `tick` refreshes and returns the wait, counted from the end of that refresh.
    private func poll(_ tick: @MainActor () async -> TimeInterval) async {
        while !Task.isCancelled, isCurrent() {
            let delay = await tick()
            do { try await sleep(.seconds(delay)) } catch { return }
        }
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
        dropFiring(event)
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
    /// S1D1-16: every event read passes here. Without `ops.alert_event_details` the server leaves out the rule and the group name;
    /// `alert-rules` and `groups/all` are read once a session (again after a pull) and fill in what they know. A failed read fills
    /// nothing and is tried again next time; the events themselves never fail.
    func normalizeReceivedAlerts(_ events: [AlertEvent]) async -> [AlertEvent] {
        guard site()?.has(.opsAlertEventDetails) == false else { return events }
        let rules = events.contains { $0.rule == nil && $0.ruleID != nil } ? await legacyAlertRules() : [:]
        let names = events.contains { $0.groupID != nil && ($0.groupName ?? "").isEmpty } ? await legacyGroupNames() : [:]
        guard !rules.isEmpty || !names.isEmpty else { return events }
        return events.map { HomeFallback.fillingLegacyDetails($0, rules: rules, groupNames: names) }
    }

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
    /// Off the firing list, home's alerts and the counts at once (10 §1.4).
    private func dropFiring(_ event: AlertEvent) {
        firing.updateValue { $0.filter { $0.id != event.id } }
        home.alerts = home.alerts.updatingValue { $0.removingFiring(event) }
        countsValue = countsValue?.removingFiring(severity: event.severity)
    }

    // MARK: - 运维监控开关（10 §7.2，S1D1-02：唯一入口，S1-08 只改函数体）

    /// Off, unless the App turned it on under 30 seconds ago; then why, once per off period (S1-08).
    func noteOpsDisabled() async {
        opsSwitch.note(disabled: true, at: localNow())
        await resolveOpsDisabledReasonIfNeeded()
    }
    /// On, unless the App turned it off under 30 seconds ago (other instances still answer meanwhile).
    func noteOpsAvailable() { opsSwitch.note(disabled: false, at: localNow()) }
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

    // MARK: - 逐接口退路（S1-07，10 §1.2；LiveOpsStore+Fallback.swift）

    /// Where the RPM / TPM shown came from; a home reply sets `.home`, only LiveOpsStore+Fallback.swift sets the rest (S1D1-23).
    var ratesSource: HomeRatesSource = .home
    var tpmExcludesCache: Bool { ratesSource.tpmExcludesCache }
    /// Each block's 429 wait, backoff and last error on the fallback; only LiveOpsStore+Fallback.swift writes it (S1D1-03).
    var fallbackStatus: [HomeSectionKey: FallbackBlockStatus] = [:]
    /// The fallback round whose answers may still land; only LiveOpsStore+Fallback.swift sets it, a home reply clears it.
    @ObservationIgnored var fallbackCycle: UUID?
    /// Home answered 404: the rest of this session reads the fallback (the store is made again for a new session).
    @ObservationIgnored private(set) var homeEndpointMissing = false
    @ObservationIgnored private var legacyRuleTable: [Int: AlertEventRule]?
    @ObservationIgnored private var legacyGroupNameTable: [Int: String]?
    /// A home read or a fallback round is on its way; polling and countdowns leave it to finish.
    var isHomeLoading: Bool { homeRequest.isLoading || fallbackCycle != nil }

    /// A pull reads the rules and group names of a server without `ops.alert_event_details` again (S1D1-16); S1-12 calls it too.
    func invalidateLegacyAlertLookups() { legacyRuleTable = nil; legacyGroupNameTable = nil }
    /// The fallback's alerts block, as `applyHome` takes home's.
    func recordAlertCounts(_ counts: AlertCounts) { countsValue = counts }

    private func startFallback(noCache: Bool) async {
        isOnFallback = true
        await refreshFallback(noCache: noCache)
    }
    private func legacyAlertRules() async -> [Int: AlertEventRule] {
        if let legacyRuleTable { return legacyRuleTable }
        guard let rules = try? await source.alertRules() else { return [:] }
        let table = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if isCurrent() { legacyRuleTable = table }
        return table
    }
    private func legacyGroupNames() async -> [Int: String] {
        if let legacyGroupNameTable { return legacyGroupNameTable }
        guard let groups = try? await source.allGroups(includeInactive: true) else { return [:] }
        let table = Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        if isCurrent() { legacyGroupNameTable = table }
        return table
    }

    private static func isWithin(_ interval: TimeInterval, since start: Date, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(start)
        return elapsed >= 0 && elapsed < interval
    }
}

/// The error of this call's home read, so a 404 or a network failure can send it to the fallback.
@MainActor private final class HomeFailure { var error: (any Error)? }

// MARK: - 告警写后的本地更新（S1-06，10 §7.1）

extension LiveOpsStore: AlertActionsHost {
    var isSessionCurrent: Bool { isCurrent() }
    /// The event as read back, normalized like every other event read (S1D1-16): a firing one replaces its copies; an ended one
    /// leaves the firing list, home's alerts and the counts for 最近结束.
    func upsertAlert(_ received: AlertEvent) async {
        let event = await normalizeReceivedAlerts([received]).first ?? received
        guard isCurrent() else { return }
        guard event.isFiring else {
            if let known = knownFiringEvent(event.id) { dropFiring(known) }
            recent.updateValue { $0.upserting(event) }
            return
        }
        let update: (AlertEvent) -> AlertEvent = { $0.id == event.id ? event : $0 }
        firing.updateValue { $0.map(update) }
        home.alerts = home.alerts.updatingValue { $0.mapEvents(update) }
        recent.updateValue { $0.removing(eventID: event.id) }
    }
    /// 404 OPS_ALERT_EVENT_NOT_FOUND: the event is gone from every list.
    func removeAlert(eventID: Int) {
        guard isCurrent() else { return }
        if let known = knownFiringEvent(eventID) { dropFiring(known) }
        recent.updateValue { $0.removing(eventID: eventID) }
    }
    /// BACKLOG D06: the firing list and the counts at once, and the next home read bypasses the cache (10 §1.4).
    func refreshAlertsAfterWrite() async {
        await refreshFiringAlerts(maxAge: 0)
        noteExternalWrite()
    }
}
