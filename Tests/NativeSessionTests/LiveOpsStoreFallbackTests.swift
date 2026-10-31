import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-07: LiveOpsStore's per-endpoint fallback (10 §1.2): without dashboard.home, or when home answers 404 or the network fails,
// each block reads its own endpoint and lands on its own.

/// 2026-10-15 01:46:40 in Shanghai: the server's day began at 2026-10-14 16:00:00 UTC.
private let base = Date(timeIntervalSince1970: 1_792_000_000)
private let dayStart = Date(timeIntervalSince1970: 1_791_993_600)
private let gateway404 = APIError.server(status: 404, envelope: nil)
private let serverFailure = APIError.server(status: 500, reason: nil)
private let offline = APIError(kind: .transport, message: "无法连接站点")
private let rule = AlertEventRule(id: 11, name: "标准组错误率")

private func legacyStats(requests: Int = 100, actual: Decimal? = 12, account: Decimal? = 5, rpmAvailable: Bool? = nil, updatedAt: String? = nil,
                         stale: Bool? = nil) -> DashboardStats {
    DashboardStats(todayRequests: requests, todayTokens: 2_000, todayCost: 15, totalUsers: 1, totalAccounts: 2, errorAccounts: 1, rpm: 9, tpm: 90,
                   todayActualCost: actual, todayAccountCost: account, rpmAvailable: rpmAvailable, statsUpdatedAt: updatedAt, statsStale: stale)
}
/// #7 newest, listed newest first as the server does; they carry their rule, so no legacy lookup runs.
private let firingSet: [AlertEvent] = (1...7).reversed().map {
    AlertEvent(id: $0, ruleID: 11, severity: ["P0", "P1", "P1", "P2", "P3", "P3", "P1"][$0 - 1], status: "firing",
               firedAt: base.addingTimeInterval(TimeInterval(-60 * (8 - $0))), rule: rule)
}
private let erroredAccount = UpstreamAccount(id: 7, name: "OpenAI-备用-A", platform: "openai", type: "apikey", status: "error", schedulable: false,
                                             groupIDs: [1])
private let healthyAccount = UpstreamAccount(id: 4, name: "OpenAI-主力-01", platform: "openai", type: "apikey", groupIDs: [1])

/// Every legacy endpoint answers; home itself is gone (a non-JSON 404).
private func everyEndpoint(_ change: (inout StubLiveOpsSource.Handlers) -> Void = { _ in }) -> StubLiveOpsSource {
    var handlers = StubLiveOpsSource.Handlers()
    handlers.home = { _ in throw gateway404 }
    handlers.stats = { legacyStats() }
    handlers.costSnapshot = { DashboardCostSnapshot(actual: 13, account: 6) }
    handlers.trend = {
        DashboardTrendReply(points: [TrendPoint(date: "2026-10-15 01:00", requests: 10, totalTokens: 100, cost: 2, actualCost: 1),
                                     TrendPoint(date: "2026-10-14 23:00", requests: 8, totalTokens: 80, cost: 2, actualCost: 1)], timeZone: liveOpsZone.timeZone)
    }
    handlers.trendRange = { _, _, _ in
        DashboardTrendReply(points: [TrendPoint(date: "2026-10-14", requests: 80, totalTokens: 0, cost: 11, actualCost: 9)], timeZone: liveOpsZone.timeZone)
    }
    handlers.rates = { LiveRates(rpm: 50, tpm: 500) }
    handlers.overview = { start, end in
        OpsOverview(startTime: start, endTime: end, healthScore: 94, sla: 0.99, errorRate: 0.01, requestCountTotal: 230, tokenConsumed: 1_200_000)
    }
    handlers.alertEvents = { _, limit in Array(firingSet.prefix(limit)) }
    handlers.alertCounts = { AlertCounts(firing: 9, bySeverity: ["P1": 9]) }
    handlers.summary = {
        AccountStatusSummary(totals: AccountStateCounts(total: 2, available: 1, error: 1),
                             accounts: [AccountStatusItem(id: 4, state: .available), AccountStatusItem(id: 7, state: .error, status: "error")])
    }
    handlers.allGroups = { [AdminGroup(id: 1, name: "标准组", accountCount: 2, activeAccountCount: 1)] }
    handlers.accounts = { page, query in AccountListPage(items: [erroredAccount, healthyAccount], total: 2, page: page, pageSize: query.pageSize, pages: 1) }
    handlers.channels = {
        ChannelOverview(items: [ChannelItem(groupID: 1, currentStatus: ChannelCurrentStatus(state: "healthy")),
                                ChannelItem(groupID: 2, currentStatus: ChannelCurrentStatus(state: "warning"))])
    }
    handlers.errorAccounts = { [] }
    change(&handlers)
    return StubLiveOpsSource(handlers)
}
@MainActor private func fallbackHarness(_ source: StubLiveOpsSource, _ capabilities: [Capability] = []) -> LiveOpsHarness {
    LiveOpsHarness(source, site: liveOpsSite(capabilities), serverNow: base)
}
@MainActor private func blocksLoaded(_ home: HomeBlocks) -> Bool {
    [home.stats.updatedAt, home.rates.updatedAt, home.hourly.updatedAt, home.ops.updatedAt, home.alerts.updatedAt, home.availability.updatedAt,
     home.channels.updatedAt].allSatisfy { $0 != nil } && !home.hasFailedBlock
}
private func isFallbackRead(_ call: StubLiveOpsSource.Call) -> Bool {
    switch call {
    case .stats, .costSnapshot, .trend, .trendRange, .rates, .overviewRange, .alertEvents, .alertCounts, .summary, .allGroups, .accounts, .channels: true
    default: false
    }
}

// MARK: 触发

@MainActor @Test func withoutHomeCapabilityLoadsAllBlocksFromLegacyEndpoints() async {
    let source = everyEndpoint()
    let harness = fallbackHarness(source)
    let store = harness.store
    await store.refreshHome(noCache: false)
    let calls = await source.calls
    #expect(await source.homeCalls.isEmpty)
    #expect(calls.filter { $0 == .stats }.count == 1 && calls.filter { $0 == .costSnapshot }.count == 1 && calls.filter { $0 == .trend }.count == 1)
    #expect(calls.contains(.trendRange(start: dayStart.addingTimeInterval(-86_400), end: base.addingTimeInterval(-86_400), granularity: .day)))
    #expect(calls.filter { $0 == .overviewRange("5m") }.count == 1 && calls.contains(.alertEvents(status: "firing", limit: 500)))
    #expect(calls.contains(.allGroups(includeInactive: true)) && calls.contains(.accounts(page: 1, pageSize: 1_000)))
    #expect(calls.contains(.channels(range: "90m", refresh: false)))
    #expect(!calls.contains(.rates(.fiveMinutes)) && !calls.contains(.summary) && !calls.contains(.alertCounts))
    #expect(blocksLoaded(store.home) && store.isOnFallback && store.lastFullSuccessAt == harness.context.localNow)
    #expect(store.ratesSource == .opsOverview && store.home.rates.value?.rpm == 46 && store.home.rates.value?.tpm == 240_000 && !store.tpmExcludesCache)
    #expect(store.home.stats.value?.yesterdaySameTimeActualCost == 9 && store.home.hourly.value?.today.count == 1 && store.home.hourly.value?.yesterday.count == 1)
    #expect(store.home.ops.value?.healthScore == 94 && store.home.channels.value == HomeChannels(total: 2, healthy: 1, warning: 1))
    #expect(store.availability?.totals == AccountStateCounts(total: 2, available: 1, error: 1) && store.availability?.accounts.map(\.id) == [7])
    #expect(harness.badge.errorCount == 1)
}

@MainActor @Test func home404FallsBackAndSkipsHomeForRestOfSession() async {
    let source = everyEndpoint()
    let store = fallbackHarness(source, [.dashboardHome]).store
    await store.refreshHome(noCache: false)
    #expect(await source.homeCalls == [false])
    #expect(blocksLoaded(store.home) && store.isOnFallback && !store.homeFailed)
    await store.refreshHome(noCache: true)
    let homeCalls = await source.homeCalls, statsReads = await source.count { $0 == .stats }
    #expect(homeCalls == [false] && statsReads == 2)
}

@MainActor @Test func homeTransportFailureFallsBackButRetriesHomeNextTime() async {
    let tally = Tally()
    let source = everyEndpoint { $0.home = { _ in if tally.next() == 1 { throw offline }; return homeReply() } }
    let store = fallbackHarness(source, [.dashboardHome]).store
    await store.refreshHome(noCache: false)
    #expect(store.isOnFallback && store.ratesSource == .opsOverview && !store.homeFailed && blocksLoaded(store.home))
    await store.refreshHome(noCache: false)
    let homeCalls = await source.homeCalls, statsReads = await source.count { $0 == .stats }
    #expect(homeCalls == [false, false] && statsReads == 1)
    #expect(!store.isOnFallback && store.ratesSource == .home && store.home.rates.value == LiveRates(rpm: 1))
}

@MainActor @Test func homeServerErrorKeepsHomeFailureWithoutFallback() async {
    for failure in [serverFailure, APIError.server(status: 429, reason: "RATE_LIMITED")] {
        let source = everyEndpoint { $0.home = { _ in throw failure } }
        let store = fallbackHarness(source, [.dashboardHome]).store
        await store.refreshHome(noCache: false)
        #expect(store.homeFailed && !store.isOnFallback && store.home == HomeBlocks())
        #expect(await source.count(isFallbackRead) == 0)
    }
}

@MainActor @Test func homeErrorAfterTransportFallbackUsesHomesOwnWaitAndBackoff() async {
    for failure in [serverFailure, APIError.server(status: 429, envelope: nil, retryAfter: 120)] {
        let tally = Tally()
        let source = everyEndpoint { $0.home = { _ in if tally.next() == 1 { throw offline }; throw failure } }
        let store = fallbackHarness(source, [.dashboardHome]).store
        await store.refreshHome(noCache: false)
        #expect(store.isOnFallback && store.nextHomeDelay() == 60)
        await store.refreshHome(noCache: false)
        let statsReads = await source.count { $0 == .stats }
        #expect(store.homeFailed && !store.isOnFallback && blocksLoaded(store.home) && statsReads == 1)
        #expect(store.homeRefresh(for: .channels) == store.homeRequest.refresh && store.homeRequest.refresh.consecutiveFailures == 2)
        let expected: TimeInterval = failure.statusCode == 429 ? 120 : 240
        #expect(abs(store.nextHomeDelay() - expected) <= 1)
    }
}

// MARK: rates 三级

@MainActor @Test func ratesUseDashboardRatesAndRequestOverviewOnce() async {
    let source = everyEndpoint()
    let store = fallbackHarness(source, [.dashboardRates]).store
    await store.refreshHome(noCache: false)
    #expect(store.home.rates.value == LiveRates(rpm: 50, tpm: 500) && store.ratesSource == .dashboardRates && !store.tpmExcludesCache)
    let calls = await source.calls
    #expect(calls.filter { $0 == .rates(.fiveMinutes) }.count == 1 && calls.filter { $0 == .overviewRange("5m") }.count == 1)
    #expect(store.home.ops.value?.healthScore == 94)
}

@MainActor @Test func opsDisabledMovesRatesToStatsAndMarksOpsAndAlertsDisabled() async {
    let source = everyEndpoint {
        $0.overview = { _, _ in throw opsDisabledError }
        $0.alertEvents = { _, _ in throw opsDisabledError }
        $0.stats = { legacyStats(rpmAvailable: false) }
    }
    let store = fallbackHarness(source).store
    await store.refreshHome(noCache: false)
    #expect(store.home.ops == .disabled(reason: "OPS_DISABLED") && store.home.alerts == .disabled(reason: "OPS_DISABLED") && store.opsDisabled)
    #expect(store.ratesSource == .dashboardStats && store.tpmExcludesCache)
    #expect(store.home.rates.value?.rpm == nil && store.home.rates.value?.tpm == 90 && store.home.rates.value?.opsMonitoringEnabled == false)
    #expect(await source.count { $0 == .stats } == 1 && store.lastFullSuccessAt != nil)
}

@MainActor @Test func failedRatesKeepTheLastSourceAndValue() async {
    let tally = Tally()
    let source = everyEndpoint { $0.rates = { if tally.next() > 1 { throw serverFailure }; return LiveRates(rpm: 50) } }
    let store = fallbackHarness(source, [.dashboardRates]).store
    await store.refreshHome(noCache: false)
    await store.refreshHome(noCache: false)
    #expect(store.home.rates.value?.rpm == 50 && store.home.rates.failureReason == HomeBlockText.failed && store.ratesSource == .dashboardRates)
    #expect(store.homeRefresh(for: .rates).consecutiveFailures == 1 && store.homeRefresh(for: .ops).consecutiveFailures == 0)
}

// MARK: 区块独立

@MainActor @Test func channelMonitorDisabledOrMissingMarksChannelsDisabled() async {
    for (failure, reason) in [(APIError.server(status: 403, reason: "CHANNEL_MONITOR_DISABLED"), "CHANNEL_MONITOR_DISABLED"), (gateway404, "UNSUPPORTED")] {
        let source = everyEndpoint { $0.channels = { throw failure } }
        let store = fallbackHarness(source).store
        await store.refreshHome(noCache: false)
        #expect(store.home.channels == .disabled(reason: reason) && store.home.stats.value != nil && store.home.ops.value != nil)
        #expect(store.lastFullSuccessAt != nil)
    }
}

@MainActor @Test func failingBlockKeepsPreviousValueAndOthersLoad() async {
    let tally = Tally()
    let source = everyEndpoint {
        $0.trend = {
            if tally.next() > 1 { throw serverFailure }
            return DashboardTrendReply(points: [TrendPoint(date: "2026-10-15 01:00", requests: 10, totalTokens: 100, cost: 2, actualCost: 1)],
                                       timeZone: liveOpsZone.timeZone)
        }
    }
    let harness = fallbackHarness(source)
    let store = harness.store
    await store.refreshHome(noCache: false)
    let first = store.lastFullSuccessAt
    harness.advance(by: 60)
    await store.refreshHome(noCache: false)
    #expect(first != nil && store.lastFullSuccessAt == first)
    #expect(store.home.hourly.failureReason == HomeBlockText.failed && store.home.hourly.value?.today.count == 1)
    #expect(store.home.stats.updatedAt == harness.context.localNow && store.home.channels.updatedAt == harness.context.localNow)
    #expect(store.home.ops.failureReason == nil && store.home.availability.failureReason == nil && store.home.rates.failureReason == nil)
    #expect(store.homeRefresh(for: .hourly).consecutiveFailures == 1 && store.homeRefresh(for: .stats).consecutiveFailures == 0)
}

/// `lookup` holds a follow-up read; the channels answer only once it started and still land before it ends (00 §4.6).
@MainActor private func channelsLand(whileHeldBy lookup: SessionGate, channels: SessionGate, _ source: StubLiveOpsSource,
                                     _ capabilities: [Capability]) async -> LiveOpsStore {
    let store = fallbackHarness(source, capabilities).store
    let round = Task { await store.refreshHome(noCache: false) }
    await waitUntil { let held = await lookup.arrived; let asked = await channels.arrived; return held && asked }
    await channels.open()
    await waitUntil { store.home.channels.value != nil }
    #expect(store.home.channels.value == HomeChannels(total: 2, healthy: 1, warning: 1))
    await lookup.open()
    await round.value
    return store
}

@MainActor @Test func slowFollowUpReadsDoNotHoldBackOtherBlocks() async {
    let structured = SessionGate(), structuredChannels = SessionGate()
    let summarized = everyEndpoint {
        let answer = $0.channels!
        $0.errorAccounts = { await structured.wait(); return [structuredAccount(7)] }
        $0.channels = { await structuredChannels.wait(); return try await answer() }
    }
    let first = await channelsLand(whileHeldBy: structured, channels: structuredChannels, summarized, [.accountsStatusSummary, .accountsStructuredError])
    #expect(first.structuredErrors.map(\.id) == [7] && blocksLoaded(first.home))
    let rules = SessionGate(), ruleChannels = SessionGate()
    let bare = AlertEvent(id: 41, ruleID: 11, severity: "P1", status: "firing", firedAt: base.addingTimeInterval(-60))
    let legacy = everyEndpoint {
        let answer = $0.channels!
        $0.alertEvents = { _, _ in [bare] }
        $0.alertRules = { await rules.wait(); return [rule] }
        $0.channels = { await ruleChannels.wait(); return try await answer() }
    }
    let second = await channelsLand(whileHeldBy: rules, channels: ruleChannels, legacy, [])
    #expect(second.home.alerts.value?.top.map(\.rule) == [rule] && second.alertCounts?.firing == 1 && blocksLoaded(second.home))
}

@MainActor @Test func timedOutBlockSaysTimedOut() async {
    let source = everyEndpoint { $0.channels = { throw APIError.server(status: 504, reason: nil) } }
    let store = fallbackHarness(source).store
    await store.refreshHome(noCache: false)
    #expect(store.home.channels.failureReason == HomeBlockText.timedOut && store.home.stats.failureReason == nil)
}

@MainActor @Test func costSnapshotUsedOnlyAsPair() async {
    let partial = everyEndpoint { $0.stats = { legacyStats(actual: 12, account: nil) } }
    let paired = fallbackHarness(partial).store
    await paired.refreshHome(noCache: false)
    #expect(paired.home.stats.value?.todayActualCost == 13 && paired.home.stats.value?.todayAccountCost == 6)
    let failing = everyEndpoint {
        $0.stats = { legacyStats(actual: 12, account: nil) }
        $0.costSnapshot = { throw APIError.server(status: 503, reason: nil) }
    }
    let alone = fallbackHarness(failing).store
    await alone.refreshHome(noCache: false)
    #expect(alone.home.stats.value?.todayActualCost == 12 && alone.home.stats.value?.todayAccountCost == nil && alone.home.stats.failureReason == nil)
    let modern = everyEndpoint()
    await fallbackHarness(modern, [.dashboardAccountCost]).store.refreshHome(noCache: false)
    #expect(await modern.count { $0 == .costSnapshot } == 0)
}

@MainActor @Test func alertsUseCountsWhenSupportedOtherwiseCountList() async {
    let exact = everyEndpoint()
    let counted = fallbackHarness(exact, [.opsAlertEventCounts]).store
    await counted.refreshHome(noCache: false)
    let exactCalls = await exact.calls
    #expect(exactCalls.contains(.alertCounts) && exactCalls.contains(.alertEvents(status: "firing", limit: 5)))
    #expect(counted.home.alerts.value?.firingCount == 9 && counted.home.alerts.value?.top.map(\.id) == [7, 6, 5, 4, 3])
    #expect(counted.alertCounts?.firing == 9)
    let listed = everyEndpoint()
    let store = fallbackHarness(listed).store
    await store.refreshHome(noCache: false)
    let listedCalls = await listed.calls
    #expect(!listedCalls.contains(.alertCounts) && listedCalls.contains(.alertEvents(status: "firing", limit: 500)))
    let alerts = store.home.alerts.value
    #expect(alerts?.firingCount == 7 && alerts?.count(severity: "P1") == 3 && alerts?.count(severity: "P3") == 2 && alerts?.top.count == 5)
}

@MainActor @Test func availabilityUsesStatusSummaryOrLocalTiering() async {
    let summarized = everyEndpoint()
    let harness = fallbackHarness(summarized, [.accountsStatusSummary])
    await harness.store.refreshHome(noCache: false)
    let calls = await summarized.calls
    #expect(calls.contains(.summary) && !calls.contains(.accounts(page: 1, pageSize: 1_000)) && !calls.contains(.allGroups(includeInactive: true)))
    #expect(harness.store.availability?.accounts.map(\.id) == [7] && harness.badge.errorCount == 1)
    let noGroups = everyEndpoint { $0.allGroups = { throw serverFailure } }
    let local = fallbackHarness(noGroups).store
    await local.refreshHome(noCache: false)
    #expect(local.home.availability.failureReason == HomeBlockText.failed && local.home.stats.failureReason == nil)
    #expect(local.lastFullSuccessAt == nil)
}

@MainActor @Test func staleStatsMoveYesterdayCutoff() async {
    // 01:00 on the 15th in Shanghai.
    let updated = Date(timeIntervalSince1970: 1_791_997_200)
    let stale = everyEndpoint { $0.stats = { legacyStats(updatedAt: ServerTime.utcTimestamp(updated), stale: true) } }
    let store = fallbackHarness(stale).store
    await store.refreshHome(noCache: false)
    #expect(await stale.calls.contains(.trendRange(start: dayStart.addingTimeInterval(-86_400), end: updated.addingTimeInterval(-86_400), granularity: .day)))
    let stats = store.home.stats.value
    #expect(stats?.statsStale == true && stats?.statsUpdatedAt == updated && stats?.yesterdaySameTimeActualCost == 9)
    #expect(stats?.yesterdaySameTimeUntil == updated.addingTimeInterval(-86_400))
    let failing = everyEndpoint { $0.trendRange = { _, _, _ in throw serverFailure } }
    let without = fallbackHarness(failing).store
    await without.refreshHome(noCache: false)
    #expect(without.home.stats.value?.todayRequests == 100 && without.home.stats.value?.yesterdaySameTimeActualCost == nil)
    #expect(without.home.stats.failureReason == nil)
}

// MARK: 轮次与节奏

@MainActor @Test func lateCycleResultsAreDiscarded() async {
    let gate = SessionGate(), tally = Tally()
    let source = everyEndpoint {
        $0.stats = {
            guard tally.next() == 1 else { return legacyStats(requests: 200) }
            await gate.wait()
            return legacyStats(requests: 100)
        }
    }
    let store = fallbackHarness(source).store
    let first = Task { await store.refreshHome(noCache: false) }
    await waitUntil { await gate.arrived }
    await store.refreshHome(noCache: true)
    #expect(store.home.stats.value?.todayRequests == 200)
    await gate.open()
    await first.value
    #expect(store.home.stats.value?.todayRequests == 200)
}

@MainActor @Test func blockInRateLimitWaitIsNotRequested() async {
    let tally = Tally()
    let source = everyEndpoint {
        $0.channels = {
            if tally.next() == 1 { throw APIError.server(status: 429, reason: "RATE_LIMITED") }
            return ChannelOverview()
        }
    }
    let harness = fallbackHarness(source)
    let store = harness.store
    await store.refreshHome(noCache: false)
    #expect(store.home.channels.failureReason == HomeBlockText.failed)
    #expect(store.homeRefresh(for: .channels).notBefore == harness.context.localNow.addingTimeInterval(30))
    harness.advance(by: 10)
    #expect(store.nextHomeDelay() == 20)
    await store.refreshHome(noCache: false)
    let calls = await source.calls
    #expect(calls.filter { $0 == .channels(range: "90m", refresh: false) }.count == 1 && calls.filter { $0 == .stats }.count == 2)
    #expect(store.home.channels.failureReason == HomeBlockText.failed && store.lastFullSuccessAt == nil)
    harness.advance(by: 20)
    await store.refreshHome(noCache: false)
    #expect(store.home.channels.failureReason == nil && store.lastFullSuccessAt != nil && store.nextHomeDelay() == 60)
}

@MainActor @Test func fallbackPollingWaitsForTheShortestBlockDelay() async {
    let source = everyEndpoint { $0.trend = { throw serverFailure } }
    let harness = LiveOpsHarness(source, site: liveOpsSite([]), serverNow: base, sleeper: PollSleeper(stopAfter: 1))
    await harness.store.pollHomeBlocks()
    #expect(await harness.sleeper.seconds == [60])
    #expect(harness.store.homeRefresh(for: .hourly).consecutiveFailures == 1)
}

// MARK: 旧服务端事件（S1D1-16）

@MainActor @Test func legacyEventsGetRuleAndGroupNameOncePerSession() async {
    let bare = AlertEvent(id: 41, ruleID: 11, severity: "P1", status: "firing", groupID: 2, firedAt: base.addingTimeInterval(-60))
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }, alertEvents: { _, _ in [bare] }, alertCounts: { AlertCounts(firing: 1) },
                                         alertRules: { [rule] }))
    await source.update { $0.allGroups = { [AdminGroup(id: 2, name: "标准组")] } }
    let store = LiveOpsHarness(source).store
    await store.refreshFiringAlerts(maxAge: 0)
    await store.refreshFiringAlerts(maxAge: 0)
    #expect(store.firingAlerts.first?.rule == rule && store.firingAlerts.first?.groupName == "标准组")
    var calls = await source.calls
    #expect(calls.filter { $0 == .alertRules }.count == 1 && calls.filter { $0 == .allGroups(includeInactive: true) }.count == 1)
    await store.refreshHome(noCache: true)
    await store.refreshFiringAlerts(maxAge: 0)
    calls = await source.calls
    #expect(calls.filter { $0 == .alertRules }.count == 2 && calls.filter { $0 == .allGroups(includeInactive: true) }.count == 2)
    let detailed = StubLiveOpsSource(.init(alertEvents: { _, _ in [bare] }, alertCounts: { AlertCounts(firing: 1) }, alertRules: { [rule] }))
    let modern = LiveOpsHarness(detailed, site: liveOpsSite(liveOpsCapabilities + [.opsAlertEventDetails])).store
    await modern.refreshFiringAlerts(maxAge: 0)
    let lookups = await detailed.count { $0 == .alertRules }
    #expect(modern.firingAlerts == [bare] && lookups == 0)
}

// MARK: 夹具

@MainActor @Test func legacyFixtureMatchesDefaultHomeFixture() async {
    let site = liveOpsSite(Capability.allCases)
    func store(_ arguments: [String], site: SiteSession) async -> LiveOpsStore {
        let source = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: arguments), base: base)
        let store = LiveOpsStore(generation: UUID(), source: source, site: { site }, isCurrent: { true }, serverNow: { base })
        await store.refreshHome(noCache: false)
        return store
    }
    let main = await store([], site: site), legacy = await store([LiveOpsFixtures.Argument.homeLegacy], site: site)
    #expect(!main.isOnFallback && legacy.isOnFallback && legacy.ratesSource == .dashboardRates && blocksLoaded(legacy.home))
    #expect(legacy.home.stats.value?.todayActualCost == main.home.stats.value?.todayActualCost)
    #expect(legacy.home.stats.value?.todayRequests == main.home.stats.value?.todayRequests)
    #expect(legacy.home.stats.value?.yesterdaySameTimeActualCost == main.home.stats.value?.yesterdaySameTimeActualCost)
    #expect(legacy.home.rates.value?.rpm == main.home.rates.value?.rpm && legacy.home.hourly.value?.today.count == main.home.hourly.value?.today.count)
    #expect(legacy.home.ops.value == main.home.ops.value && legacy.home.channels.value == main.home.channels.value)
    #expect(legacy.home.alerts.value == main.home.alerts.value && legacy.availability == main.availability)
    let withheld = UITestArguments.withheldCapabilities(arguments: [UITestArguments.withoutCapabilities, LiveOpsFixtures.homeLegacyWithheldCapabilities])
    let oldSite = liveOpsSite(Capability.allCases.filter { !withheld.contains($0.rawValue) })
    let old = await store([LiveOpsFixtures.Argument.homeLegacy], site: oldSite)
    #expect(withheld == Set([Capability.dashboardHome, .dashboardRates, .dashboardAccountCost, .accountsStatusSummary, .opsAlertEventCounts].map(\.rawValue)))
    #expect(old.ratesSource == .opsOverview && old.home.rates.value?.rpm == main.home.rates.value?.rpm && blocksLoaded(old.home))
    #expect(old.home.rates.value?.tpm == main.home.rates.value?.tpm && old.availability?.totals == main.availability?.totals)
    #expect(old.home.alerts.value?.firingCount == main.home.alerts.value?.firingCount)
    let shortage = { (store: LiveOpsStore) in store.availability.map(HomePresentation.shortageGroups)?.map(\.groupID) }
    #expect(shortage(old) == shortage(main) && shortage(main) == [LiveOpsFixtureIDs.shortageGroup])
}
