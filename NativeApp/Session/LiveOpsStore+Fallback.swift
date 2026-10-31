import Foundation
import Sub2Core

// S1-07, 10 §1.2 逐接口退路: the blocks read their own endpoints at once and each lands as its answer arrives, on its own. One
// ops overview read feeds the ops block and RPM / TPM ②, one dashboard/stats read the stats block and ③. A block in its 429 wait is
// neither read nor changed; a newer round or a home reply drops the late answers of an older round (S1D1-03).

/// One block's 429 wait, failure backoff and last error on the fallback.
struct FallbackBlockStatus: Sendable, Equatable {
    var refresh = BlockRefresh()
    var lastError: APIError?
}

/// One read as it came back.
enum FallbackPiece: Sendable {
    case stats(Result<DashboardStats, any Error>, snapshot: DashboardCostSnapshot?)
    case yesterday(YesterdaySameTime?)
    case dashboardRates(Result<LiveRates, any Error>)
    case overview(Result<OpsOverview, any Error>)
    case hourly(Result<DashboardTrendReply, any Error>)
    case alerts(counts: Result<AlertCounts, any Error>?, firing: Result<[AlertEvent], any Error>)
    case availability(Result<AccountStatusSummary, any Error>)
    case channels(Result<ChannelOverview, any Error>)
    /// The alerts block once the legacy rule and group-name lookups ended (S1D1-16).
    case normalizedAlerts(HomeAlerts)
    /// The availability follow-ups ended; nothing to write.
    case followedUp
}

typealias FallbackRead = @Sendable () async -> FallbackPiece

extension LiveOpsStore {
    /// One round: a full success only when every block loaded or was switched off.
    func refreshFallback(noCache: Bool) async {
        guard isCurrent(), let site = site() else { return }
        var round = FallbackRound(site: site, allowed: allowedBlocks())
        fallbackCycle = round.cycle
        let reads = round.reads(source, noCache: noCache, now: serverNow())
        await withTaskGroup(of: FallbackPiece.self) { group in
            for read in reads { group.addTask { await read() } }
            while let piece = await group.next() {
                guard isLanding(round), !Task.isCancelled else { continue }
                if let next = await land(piece, round: &round) { group.addTask { await next() } }
            }
        }
        guard fallbackCycle == round.cycle else { return }
        fallbackCycle = nil
        guard isCurrent(), !Task.isCancelled, round.succeeded == Set(HomeSectionKey.allCases) else { return }
        recordFullSuccess(at: localNow())
    }
    /// The polling wait on the fallback: the shortest of the blocks' (S1D1-03).
    func fallbackNextDelay() -> TimeInterval {
        let now = localNow()
        let delays = HomeSectionKey.allCases.map { (fallbackStatus[$0]?.refresh ?? BlockRefresh()).nextDelay(base: Self.pollInterval, at: now) }
        return delays.min() ?? Self.pollInterval
    }

    /// Writes one answer; returns the read it calls for next: yesterday's comparison once today's stats are in, and the alerts'
    /// legacy lookups and availability's follow-ups, which run beside the other reads so no block waits for them (00 §4.6).
    private func land(_ piece: FallbackPiece, round: inout FallbackRound) async -> FallbackRead? {
        switch piece {
        case .stats(let result, let snapshot):
            round.rates.stats = result
            landRates(&round)
            return landStats(result, snapshot: snapshot, round: &round)
        case .yesterday(let yesterday):
            guard let pending = round.pendingStats else { break }
            write(.stats, \.stats, .loaded(HomeFallback.homeStats(pending.stats, snapshot: pending.snapshot, yesterday: yesterday)), round: &round)
        case .dashboardRates(let result):
            round.rates.dashboardRates = result
            landRates(&round)
        case .overview(let result):
            await recordOpsResponse(result.error)
            write(.ops, \.ops, HomeFallback.outcome(result.map(HomeFallback.homeOps)), round: &round)
            round.rates.opsOverview = result
            landRates(&round)
        case .hourly(let result):
            let now = serverNow()
            write(.hourly, \.hourly, HomeFallback.outcome(result.map { HomeFallback.hourly($0, now: now) }), round: &round)
        case .alerts(let counts, let firing):
            return await landAlerts(counts: counts, firing: firing, round: &round)
        case .normalizedAlerts(let alerts):
            writeAlerts(alerts, round: &round)
        case .availability(let result):
            write(.availability, \.availability, HomeFallback.outcome(result), round: &round)
            guard isLanding(round) else { break }
            return { [weak self] in await self?.applyAvailabilityFollowUps(); return .followedUp }
        case .channels(let result):
            write(.channels, \.channels, HomeFallback.outcome(result.map(HomeFallback.homeChannels), unsupportedAsDisabled: true), round: &round)
        case .followedUp:
            break
        }
        return nil
    }
    /// Today's figures wait for yesterday's comparison when there is a range to read.
    private func landStats(_ result: Result<DashboardStats, any Error>, snapshot: DashboardCostSnapshot?, round: inout FallbackRound) -> FallbackRead? {
        guard case .success(let stats) = result else {
            write(.stats, \.stats, HomeFallback.outcome(result.map { HomeFallback.homeStats($0, snapshot: nil, yesterday: nil) }), round: &round)
            return nil
        }
        guard let window = HomeFallback.yesterdayWindow(now: serverNow(), zone: round.zone, statsUpdatedAt: ServerTime.parseTimestamp(stats.statsUpdatedAt),
                                                        statsStale: stats.statsStale ?? false) else {
            write(.stats, \.stats, .loaded(HomeFallback.homeStats(stats, snapshot: snapshot, yesterday: nil)), round: &round)
            return nil
        }
        round.pendingStats = (stats, snapshot)
        let source = source
        return { await FallbackFetch.yesterday(source, window: window) }
    }
    /// Once the level is known; the shown source changes only with a new value, so a failure keeps the old value and its source.
    private func landRates(_ round: inout FallbackRound) {
        guard round.allowed.contains(.rates), !round.ratesLanded,
              case .resolved(let outcome, let origin) = HomeFallback.resolveRates(round.rates) else { return }
        round.ratesLanded = true
        write(.rates, \.rates, outcome, round: &round)
        if outcome.value != nil, isLanding(round) { ratesSource = origin }
    }
    /// With `ops.alert_event_counts` the counts come from there, otherwise from the list of up to 500. The newest events land once
    /// `normalizeReceivedAlerts` filled them in.
    private func landAlerts(counts: Result<AlertCounts, any Error>?, firing: Result<[AlertEvent], any Error>,
                            round: inout FallbackRound) async -> FallbackRead? {
        if let counts { await recordOpsResponse(counts.error) }
        await recordOpsResponse(firing.error)
        let read = firing.flatMap { events in
            (counts ?? .success(AlertCounts.counting(events))).map { HomeFallback.homeAlerts(counts: $0, firing: events) }
        }
        guard case .success(let alerts) = read else {
            write(.alerts, \.alerts, HomeFallback.outcome(read), round: &round)
            return nil
        }
        guard !alerts.top.isEmpty else {
            writeAlerts(alerts, round: &round)
            return nil
        }
        return { [weak self] in
            let top = await self?.normalizeReceivedAlerts(alerts.top) ?? alerts.top
            return .normalizedAlerts(HomeAlerts(firingCount: alerts.firingCount, bySeverity: alerts.bySeverity, top: top))
        }
    }
    private func writeAlerts(_ alerts: HomeAlerts, round: inout FallbackRound) {
        write(.alerts, \.alerts, .loaded(alerts), round: &round)
        if isLanding(round) { recordAlertCounts(AlertCounts(firing: alerts.firingCount, bySeverity: alerts.bySeverity)) }
    }
    /// A value or a switched-off block clears the block's backoff; a failure keeps the value, says 加载失败 or 加载超时 and backs off.
    private func write<Value: Sendable>(_ key: HomeSectionKey, _ path: WritableKeyPath<HomeBlocks, BlockState<Value>>, _ outcome: FallbackOutcome<Value>,
                                         round: inout FallbackRound) {
        guard isLanding(round) else { return }
        switch outcome {
        case .loaded(let value):
            let now = localNow()
            replaceHome { $0.replacing(path, with: .loaded(value, at: now)) }
        case .disabled(let reason):
            replaceHome { $0.replacing(path, with: .disabled(reason: reason)) }
        case .failed(let error):
            guard !(error is CancellationError) else { return }
            let reason = HomeFallback.isTimeout(error) ? HomeBlockText.timedOut : HomeBlockText.failed, now = localNow()
            replaceHome { $0.replacing(path, with: $0[keyPath: path].withFailure(reason)) }
            let status = fallbackStatus[key] ?? FallbackBlockStatus()
            fallbackStatus[key] = FallbackBlockStatus(refresh: status.refresh.recordingFailure(error, at: now), lastError: error as? APIError)
            return
        }
        if fallbackStatus[key] != nil { fallbackStatus[key] = nil }
        round.succeeded.insert(key)
    }
    private func isLanding(_ round: FallbackRound) -> Bool { fallbackCycle == round.cycle && isCurrent() }
    /// Blocks out of their 429 wait.
    private func allowedBlocks() -> Set<HomeSectionKey> {
        let now = localNow()
        return Set(HomeSectionKey.allCases.filter { fallbackStatus[$0]?.refresh.allowsRequest(at: now) ?? true })
    }
}

/// One round's bookkeeping on the main actor.
struct FallbackRound {
    let cycle = UUID()
    let allowed: Set<HomeSectionKey>
    let zone: ServerTimeZone
    /// 00 §5: only a site without `dashboard.account_cost` is asked for the cost snapshot.
    let readsCostSnapshot: Bool
    let readsAlertCounts: Bool
    let readsStatusSummary: Bool
    var rates: RatesInputs
    var ratesLanded = false
    var pendingStats: (stats: DashboardStats, snapshot: DashboardCostSnapshot?)?
    var succeeded: Set<HomeSectionKey> = []

    init(site: SiteSession, allowed: Set<HomeSectionKey>) {
        self.allowed = allowed; zone = site.serverTimeZone
        readsCostSnapshot = !site.has(.dashboardAccountCost); readsAlertCounts = site.has(.opsAlertEventCounts)
        readsStatusSummary = site.has(.accountsStatusSummary); rates = RatesInputs(hasDashboardRates: site.has(.dashboardRates))
    }
    /// The reads of the blocks out of their 429 wait; dashboard/rates only with `dashboard.rates`.
    func reads(_ source: any LiveOpsSource, noCache: Bool, now: Date) -> [FallbackRead] {
        let snapshot = readsCostSnapshot, counts = readsAlertCounts, summary = readsStatusSummary
        let blocks: [(key: HomeSectionKey, read: FallbackRead)] = [
            (.stats, { await FallbackFetch.stats(source, withCostSnapshot: snapshot) }),
            (.rates, { .dashboardRates(await FallbackFetch.capture { try await source.dashboardRates(window: HomeFallback.ratesWindow) }) }),
            (.ops, { .overview(await FallbackFetch.capture { try await source.opsOverview(timeRange: HomeFallback.opsWindow) }) }),
            (.hourly, { .hourly(await FallbackFetch.capture { try await source.dashboardTrend() }) }),
            (.alerts, { await FallbackFetch.alerts(source, withCounts: counts) }),
            (.availability, { await FallbackFetch.availability(source, withStatusSummary: summary, now: now) }),
            (.channels, { .channels(await FallbackFetch.capture { try await source.channelOverview(range: HomeFallback.channelRange, refresh: noCache) }) })
        ]
        return blocks.filter { allowed.contains($0.key) && ($0.key != .rates || rates.hasDashboardRates) }.map(\.read)
    }
}

/// The reads, off the main actor: they hold only the source and values.
enum FallbackFetch {
    static func capture<T: Sendable>(_ body: () async throws -> T) async -> Result<T, any Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }
    /// dashboard/stats with the cost snapshot beside it.
    static func stats(_ source: any LiveOpsSource, withCostSnapshot: Bool) async -> FallbackPiece {
        async let snapshot = costSnapshot(source, wanted: withCostSnapshot)
        let stats = await capture { try await source.dashboardStats() }
        return .stats(stats, snapshot: await snapshot)
    }
    /// A failed comparison only leaves 昨日同时 empty.
    static func yesterday(_ source: any LiveOpsSource, window: DateInterval) async -> FallbackPiece {
        let reply = try? await source.dashboardTrend(start: window.start, end: window.end, granularity: .day)
        return .yesterday(reply.map { HomeFallback.yesterdaySameTime($0, until: window.end) })
    }
    /// The counts and the newest five, or up to 500 to count.
    static func alerts(_ source: any LiveOpsSource, withCounts: Bool) async -> FallbackPiece {
        guard withCounts else { return .alerts(counts: nil, firing: await firingEvents(source, limit: LiveOpsStore.firingCountingLimit)) }
        async let counts = capture { try await source.alertEventCounts() }
        let firing = await firingEvents(source, limit: HomeFallback.alertTopLimit)
        return .alerts(counts: await counts, firing: firing)
    }
    /// status-summary, or the D02 buckets of `groups/all` and the first page of accounts; either read failing fails the block.
    static func availability(_ source: any LiveOpsSource, withStatusSummary: Bool, now: Date) async -> FallbackPiece {
        guard !withStatusSummary else {
            return .availability(await capture {
                HomeFallback.homeAvailability(try await source.accountStatusSummary(platform: nil, groupID: nil, includeAccounts: true))
            })
        }
        return .availability(await localAvailability(source, now: now))
    }
    /// D02 without `accounts.status_summary` (10 §0.2): `groups/all` and the first page of accounts, counted here; either read
    /// failing fails it. The alert detail's group row reads it too on such a site (S1-12).
    static func localAvailability(_ source: any LiveOpsSource, now: Date) async -> Result<AccountStatusSummary, any Error> {
        async let groups = capture { try await source.allGroups(includeInactive: true) }
        let query = AccountListQuery(pageSize: HomeFallback.localAccountPageSize)
        let page = await capture { try await source.managedAccounts(page: 1, query: query) }
        return (await groups).flatMap { groups in
            page.map { HomeFallback.localAvailability(groups: groups, accounts: $0.items, accountsComplete: $0.total <= $0.items.count, now: now) }
        }
    }

    private static func costSnapshot(_ source: any LiveOpsSource, wanted: Bool) async -> DashboardCostSnapshot? {
        guard wanted else { return nil }
        return try? await source.dashboardCostSnapshot()
    }
    private static func firingEvents(_ source: any LiveOpsSource, limit: Int) async -> Result<[AlertEvent], any Error> {
        await capture { try await source.alertEvents(status: "firing", timeRange: nil, limit: limit, before: nil, groupID: nil, platform: nil) }
    }
}

private extension HomeBlocks {
    func replacing<Value: Sendable>(_ path: WritableKeyPath<HomeBlocks, BlockState<Value>>, with state: BlockState<Value>) -> HomeBlocks {
        var next = self
        next[keyPath: path] = state
        return next
    }
}

private extension Result {
    var error: Failure? { if case .failure(let error) = self { error } else { nil } }
}
