import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-05: LiveOpsStore, the session's home, alert and ops state (10 §0.5, §1.2–§1.6, §6.2, §7.2; 20 §1.2, §1.6).

private let internalError = HomeSection<HomeStats>(status: .error, reason: "INTERNAL_ERROR")
private let serverFailure = APIError.server(status: 500, reason: nil)
private func isAlertList(_ call: StubLiveOpsSource.Call) -> Bool { if case .alertEvents = call { true } else { false } }
private func isRanking(_ call: StubLiveOpsSource.Call) -> Bool { if case .ranking = call { true } else { false } }
private func isOverview(_ call: StubLiveOpsSource.Call) -> Bool { if case .overview = call { true } else { false } }

@MainActor @Test func refreshHomeAppliesEachSectionIndependently() async {
    let reply = homeReply(stats: .ok(HomeStats(todayRequests: 5)), hourly: HomeSection(status: .timeout, reason: "SECTION_TIMEOUT"),
                          ops: HomeSection(status: .disabled, reason: "OPS_DISABLED"), availability: .ok(errorSummary([])),
                          channels: HomeSection(status: .error, reason: "INTERNAL_ERROR"))
    let store = LiveOpsHarness(StubLiveOpsSource(.init(home: { _ in reply }))).store
    await store.refreshHome(noCache: false)
    #expect(store.home.stats.value?.todayRequests == 5 && store.home.hourly.failureReason == HomeBlockText.timedOut)
    #expect(store.home.ops == .disabled(reason: "OPS_DISABLED") && store.home.channels.failureReason == HomeBlockText.failed)
    #expect(store.availability == errorSummary([]) && store.home.hasFailedBlock && !store.homeFailed)
}

@MainActor @Test func failedSectionKeepsPreviousValue() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply(stats: .ok(HomeStats(todayRequests: 1)), rates: .ok(LiveRates(rpm: 1))) }))
    let store = LiveOpsHarness(source).store
    await store.refreshHome(noCache: false)
    await source.update { $0.home = { _ in homeReply(stats: internalError, rates: .ok(LiveRates(rpm: 2))) } }
    await store.refreshHome(noCache: false)
    #expect(store.home.stats.value?.todayRequests == 1 && store.home.stats.failureReason == HomeBlockText.failed)
    #expect(store.home.rates.value?.rpm == 2 && store.home.rates.failureReason == nil)
}

/// A 5xx keeps every block (S1-07 sends only a 404 or a network failure to the fallback).
@MainActor @Test func wholeHomeFailureOnlyMarksFailure() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }))
    let store = LiveOpsHarness(source).store
    await store.refreshHome(noCache: false)
    let before = store.home
    await source.update { $0.home = { _ in throw serverFailure } }
    await store.refreshHome(noCache: false)
    #expect(store.home == before && store.homeFailed && !store.isOnFallback && store.lastFullSuccessAt == before.lastFullSuccessAt)
}

@MainActor @Test func lateOlderReplyDoesNotOverwriteNewer() async {
    let gate = SessionGate()
    let source = StubLiveOpsSource(.init(home: { noCache in
        if noCache { return homeReply(stats: .ok(HomeStats(todayRequests: 2))) }
        await gate.wait()
        return homeReply(stats: .ok(HomeStats(todayRequests: 1)))
    }))
    let store = LiveOpsHarness(source).store
    let first = Task { await store.refreshHome(noCache: false) }
    await waitUntil { await gate.arrived }
    await store.refreshHome(noCache: true)
    #expect(store.home.stats.value?.todayRequests == 2)
    await gate.open()
    await first.value
    #expect(store.home.stats.value?.todayRequests == 2)
}

@MainActor @Test func repliesAfterSessionChangeAreDropped() async {
    let gate = SessionGate()
    let alerts = HomeAlerts(firingCount: 1, bySeverity: ["P1": 1], top: [firingEvent(1)])
    let source = StubLiveOpsSource(.init(home: { _ in
        await gate.wait()
        return homeReply(alerts: .ok(alerts), availability: .ok(errorSummary([7])))
    }, errorAccounts: { [structuredAccount(7)] }, alertEvents: { _, _ in [firingEvent(1)] }))
    let harness = LiveOpsHarness(source)
    let store = harness.store
    let refresh = Task { await store.refreshHome(noCache: false) }
    await waitUntil { await gate.arrived }
    harness.isCurrent = false
    await gate.open()
    await refresh.value
    await store.refreshFiringAlerts(maxAge: 0)
    #expect(store.home == HomeBlocks() && store.alertCounts == nil && store.structuredErrors.isEmpty && store.firingAlerts.isEmpty)
    #expect(harness.badge.updatedAt == nil)
    #expect(await source.count { $0 == .errorAccounts || isAlertList($0) } == 0)
}

@MainActor @Test func structuredErrorsFetchedOnlyWithCapabilityAndErrorAccounts() async {
    let handlers = StubLiveOpsSource.Handlers(home: { _ in homeReply(availability: .ok(errorSummary([9, 7]))) },
                                              errorAccounts: { [structuredAccount(7), structuredAccount(9), structuredAccount(5)] })
    let source = StubLiveOpsSource(handlers)
    let store = LiveOpsHarness(source).store
    await store.refreshHome(noCache: false)
    #expect(store.structuredErrors.map(\.id) == [9, 7])
    #expect(await source.count { $0 == .errorAccounts } == 1)

    let withoutCapability = StubLiveOpsSource(handlers)
    let legacy = LiveOpsHarness(withoutCapability, site: liveOpsSite([.dashboardHome])).store
    await legacy.refreshHome(noCache: false)
    #expect(legacy.structuredErrors.isEmpty && legacy.availability?.totals.error == 2)
    #expect(await withoutCapability.count { $0 == .errorAccounts } == 0)

    var calm = handlers
    calm.home = { _ in homeReply(availability: .ok(AccountStatusSummary())) }
    let healthy = StubLiveOpsSource(calm)
    await LiveOpsHarness(healthy).store.refreshHome(noCache: false)
    #expect(await healthy.count { $0 == .errorAccounts } == 0)
}

@MainActor @Test func structuredErrorsRefetchedOnlyWhenErrorIDsChange() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply(availability: .ok(errorSummary([7]))) }, errorAccounts: { [structuredAccount(7)] }))
    let store = LiveOpsHarness(source).store
    await store.refreshHome(noCache: false)
    await store.refreshHome(noCache: false)
    #expect(await source.count { $0 == .errorAccounts } == 1)
    await source.update { $0.home = { _ in homeReply(availability: .ok(errorSummary([7, 9]))) } }
    await store.refreshHome(noCache: false)
    #expect(await source.count { $0 == .errorAccounts } == 2)
    await source.update {
        $0.home = { _ in homeReply(availability: .ok(errorSummary([7]))) }
        $0.errorAccounts = { throw APIError.server(status: 500, reason: nil) }
    }
    await store.refreshHome(noCache: false)
    await store.refreshHome(noCache: false)
    #expect(await source.count { $0 == .errorAccounts } == 4)
    #expect(store.structuredErrors.map(\.id) == [7])
}

@MainActor @Test func rankingRequestedOnlyWhileCalmIsVisible() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }, ranking: { [AccountsRankingItem(accountID: 1, actualCost: 5)] }))
    let harness = LiveOpsHarness(source)
    let store = harness.store
    await store.refreshHome(noCache: false)
    await store.refreshRanking()
    #expect(await source.count(isRanking) == 0)
    store.setCalmVisible(true)
    await store.rankingTask?.value
    #expect(await source.calls.filter(isRanking) == [.ranking(limit: 4, timezone: "Asia/Shanghai")])
    #expect(store.ranking.value?.map(\.accountID) == [1])
    await store.refreshHome(noCache: false)
    store.setCalmVisible(true)
    #expect(await source.count(isRanking) == 2)
    // Shown again within a minute of the last read: no new request; later: one at once.
    store.setCalmVisible(false)
    store.setCalmVisible(true)
    await store.rankingTask?.value
    #expect(await source.count(isRanking) == 2)
    store.setCalmVisible(false)
    await store.refreshHome(noCache: false)
    #expect(await source.count(isRanking) == 2)
    harness.advance(by: 61)
    store.setCalmVisible(true)
    await store.rankingTask?.value
    #expect(await source.count(isRanking) == 3)

    let legacySource = StubLiveOpsSource(.init(home: { _ in homeReply() }, ranking: { [] }))
    let legacy = LiveOpsHarness(legacySource, site: liveOpsSite([.dashboardHome])).store
    legacy.setCalmVisible(true)
    await legacy.rankingTask?.value
    await legacy.refreshHome(noCache: false)
    #expect(await legacySource.count(isRanking) == 0)
}

@MainActor @Test func firingListReusedWithinSixtySeconds() async {
    let resolved = AlertEvent(id: 2, severity: "P2", status: "resolved")
    let source = StubLiveOpsSource(.init(alertEvents: { _, _ in [firingEvent(1), resolved] }, alertCounts: { AlertCounts(firing: 1) }))
    let harness = LiveOpsHarness(source)
    let store = harness.store
    await store.refreshFiringAlerts()
    harness.advance(by: 30)
    await store.refreshFiringAlerts()
    #expect(await source.calls.filter(isAlertList) == [.alertEvents(status: "firing", limit: 100)])
    #expect(store.firingAlerts.map(\.id) == [1])
    harness.advance(by: 31)
    await store.refreshFiringAlerts()
    #expect(await source.count(isAlertList) == 2)
    await store.refreshFiringAlerts(maxAge: 0)
    #expect(await source.count(isAlertList) == 3)
}

@MainActor @Test func alertCountsExactWithCapabilityOtherwiseCounted() async {
    let exact = StubLiveOpsSource(.init(alertEvents: { _, _ in [firingEvent(1)] }, alertCounts: { AlertCounts(firing: 7, bySeverity: ["P0": 7]) }))
    let store = LiveOpsHarness(exact).store
    await store.refreshFiringAlerts()
    #expect(store.alertCounts?.firing == 7 && store.alertCounts?.count(severity: "P0") == 7)

    let listed = [firingEvent(1, severity: "P2"), firingEvent(2, severity: "p2")]
    let counted = StubLiveOpsSource(.init(alertEvents: { _, _ in listed }))
    let legacy = LiveOpsHarness(counted, site: liveOpsSite([.dashboardHome])).store
    await legacy.refreshFiringAlerts()
    #expect(await counted.calls.filter(isAlertList) == [.alertEvents(status: "firing", limit: 500)])
    #expect(await counted.count { $0 == .alertCounts } == 0)
    #expect(legacy.alertCounts == AlertCounts.counting(listed) && legacy.alertCounts?.count(severity: "P2") == 2)

    let top = [firingEvent(3), firingEvent(4), firingEvent(5, severity: "P3")]
    let fromHome = StubLiveOpsSource(.init(home: { _ in
        homeReply(alerts: .ok(HomeAlerts(firingCount: 3, bySeverity: ["P0": 0, "P1": 2, "P2": 0, "P3": 1], top: top)))
    }))
    let homeStore = LiveOpsHarness(fromHome).store
    await homeStore.refreshHome(noCache: false)
    #expect(homeStore.alertCounts == AlertCounts(firing: 3, bySeverity: ["P1": 2, "P3": 1]))
}

@MainActor @Test func firingAlertsForPlatformIgnoresCase() async {
    let source = StubLiveOpsSource(.init(alertEvents: { _, _ in
        [firingEvent(1, platform: "anthropic"), firingEvent(2, platform: "openai"),
         AlertEvent(id: 3, severity: "P1", status: "resolved", platform: "anthropic")]
    }, alertCounts: { AlertCounts(firing: 2) }))
    let store = LiveOpsHarness(source).store
    await store.refreshFiringAlerts()
    #expect(store.firingAlerts(platform: "Anthropic").map(\.id) == [1])
    #expect(store.firingAlerts(platform: "gemini").isEmpty)
}

/// Home lists #1 (P1) and #2 (P2); the alert list and the exact counts say the same.
@MainActor private func storeWithTwoFiring() async -> LiveOpsStore {
    let pair = [firingEvent(1, severity: "P1"), firingEvent(2, severity: "P2")]
    let source = StubLiveOpsSource(.init(home: { _ in
        homeReply(alerts: .ok(HomeAlerts(firingCount: 2, bySeverity: ["P0": 0, "P1": 1, "P2": 1, "P3": 0], top: pair)))
    }, alertEvents: { _, _ in pair }, alertCounts: { AlertCounts(firing: 2, bySeverity: ["P1": 1, "P2": 1]) }))
    let store = LiveOpsHarness(source).store
    await store.refreshHome(noCache: false)
    await store.refreshFiringAlerts()
    return store
}

@MainActor @Test func markResolvedRemovesRowAndKeepsCountsConsistent() async {
    let store = await storeWithTwoFiring()
    await store.recent.load(isCurrent: { true }) { RecentAlerts(events: [AlertEvent(id: 9, status: "resolved", firedAt: Date().addingTimeInterval(-7_200))]) }
    let at = Date()
    store.markResolved(eventID: 1, at: at)
    #expect(store.firingAlerts.map(\.id) == [2])
    let alerts = store.home.alerts.value
    #expect(alerts?.top.map(\.id) == [2] && alerts?.firingCount == 1 && alerts?.count(severity: "P1") == 0 && alerts?.count(severity: "P2") == 1)
    #expect(store.alertCounts?.firing == 1 && store.alertCounts?.count(severity: "P1") == 0)
    #expect(store.recentAlerts.map(\.id) == [1, 9])
    #expect(store.recentAlerts.first?.status == AlertEvent.manualResolved && store.recentAlerts.first?.resolvedAt == at)
    store.markResolved(eventID: 1, at: at)
    #expect(store.alertCounts?.firing == 1 && store.home.alerts.value?.firingCount == 1)
}

@MainActor @Test func applySilenceReplacesEventEverywhere() async {
    let store = await storeWithTwoFiring()
    let silence = AlertSilenceRef(id: 501, until: Date().addingTimeInterval(3_600))
    store.applySilence(eventID: 2, silence)
    #expect(store.firingAlerts.first { $0.id == 2 }?.silence == silence && store.firingAlerts.first { $0.id == 1 }?.silence == nil)
    #expect(store.home.alerts.value?.top.first { $0.id == 2 }?.silence == silence)
    #expect(store.alertCounts?.firing == 2 && store.home.alerts.value?.firingCount == 2)
    store.applySilence(eventID: 2, nil)
    #expect(store.firingAlerts.first { $0.id == 2 }?.silence == nil && store.home.alerts.value?.top.first { $0.id == 2 }?.silence == nil)
}

@MainActor @Test func rateLimitedHomeDefersNextRequest() async {
    let source = StubLiveOpsSource(.init(home: { _ in throw APIError.server(status: 429, envelope: nil, retryAfter: 30) }))
    let harness = LiveOpsHarness(source, sleeper: PollSleeper(stopAfter: 1))
    let store = harness.store
    await store.refreshHome(noCache: false)
    await store.refreshHome(noCache: true)
    await store.pollHomeBlocks()
    #expect(await source.homeCalls == [false])
    let waits = await harness.sleeper.seconds
    #expect(waits.count == 1 && waits[0] >= 29 && waits[0] <= 30)
}

@MainActor @Test func pollingBacksOffSixtyToThreeHundred() async {
    let tally = Tally()
    let source = StubLiveOpsSource(.init(home: { _ in
        guard tally.next() == 1 else { throw APIError.server(status: 500, reason: nil) }
        return homeReply()
    }))
    let harness = LiveOpsHarness(source, sleeper: PollSleeper(stopAfter: 4))
    await harness.store.pollHomeBlocks()
    #expect(await harness.sleeper.seconds == [60, 120, 240, 300])
    #expect(await source.homeCalls.count == 4)
}

@MainActor @Test func pollingSkipsTickWhileRefreshIsInFlight() async {
    let gate = SessionGate()
    let source = StubLiveOpsSource(.init(home: { noCache in
        if noCache { await gate.wait() }
        return homeReply()
    }))
    let harness = LiveOpsHarness(source, sleeper: PollSleeper(stopAfter: 1))
    let store = harness.store
    let pull = Task { await store.refreshHome(noCache: true) }
    await waitUntil { await gate.arrived }
    await store.pollHomeBlocks()
    #expect(await source.homeCalls == [true])
    await gate.open()
    await pull.value
    #expect(store.home.stats.value != nil)
}

@MainActor @Test func countdownElapsedRefreshesAtMostOncePerTenSeconds() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }))
    let harness = LiveOpsHarness(source)
    await harness.store.countdownElapsed()
    harness.advance(by: 5)
    await harness.store.countdownElapsed()
    #expect(await source.homeCalls == [false])
    harness.advance(by: 6)
    await harness.store.countdownElapsed()
    #expect(await source.homeCalls == [false, false])
}

@MainActor @Test func externalWriteMakesNextRefreshBypassCache() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }))
    let harness = LiveOpsHarness(source, sleeper: PollSleeper(stopAfter: 1))
    let store = harness.store
    store.noteExternalWrite()
    await store.refreshHome(noCache: false)
    await store.refreshHome(noCache: false)
    store.noteExternalWrite()
    await store.pollHomeBlocks()
    #expect(await source.homeCalls == [true, false, true])
}

/// S1-07 reads the blocks endpoint by endpoint (LiveOpsStoreFallbackTests); home is never asked.
@MainActor @Test func withoutHomeCapabilityMarksFallback() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }))
    let store = LiveOpsHarness(source, site: liveOpsSite([.accountsStructuredError])).store
    await store.refreshHome(noCache: false)
    #expect(store.isOnFallback && store.home.stats.failureReason == HomeBlockText.failed)
    #expect(await source.homeCalls.isEmpty)
}

@MainActor @Test func todaySLAUsesServerMidnightAndSkipsWhenOpsDisabled() async {
    // 2026-10-15 01:46:40 in Shanghai; the server's day began at 2026-10-14 16:00:00 UTC.
    let serverNow = Date(timeIntervalSince1970: 1_792_000_000)
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }, overview: { _, _ in OpsOverview(sla: 0.992) }))
    let store = LiveOpsHarness(source, serverNow: serverNow).store
    await store.refreshHome(noCache: false)
    #expect(await source.calls.filter(isOverview) == [.overview(start: Date(timeIntervalSince1970: 1_791_993_600), end: serverNow)])
    #expect(store.todaySLA == 0.992)
    await store.noteOpsDisabled()
    #expect(store.todaySLA == nil)
    await store.refreshHome(noCache: false)
    #expect(await source.count(isOverview) == 1)
}

@MainActor @Test func opsDisabledFollowsLatestEvidence() async {
    #expect(LiveOpsHarness(site: liveOpsSite(opsEnabled: false)).store.opsDisabled)
    #expect(!LiveOpsHarness(site: liveOpsSite(opsEnabled: nil)).store.opsDisabled)
    let source = StubLiveOpsSource(.init(home: { _ in homeReply(ops: HomeSection(status: .disabled, reason: "OPS_DISABLED")) }))
    let store = LiveOpsHarness(source).store
    #expect(!store.opsDisabled)
    await store.refreshHome(noCache: false)
    #expect(store.opsDisabled)
    await store.recordOpsResponse(nil)
    #expect(!store.opsDisabled)
    await store.recordOpsResponse(opsDisabledError)
    #expect(store.opsDisabled)
    await store.recordOpsResponse(serverFailure)
    #expect(store.opsDisabled)
    await source.update { $0.home = { _ in homeReply() } }
    await store.refreshHome(noCache: false)
    #expect(!store.opsDisabled)
}

@MainActor @Test func firingRefreshWhileOpsDisabledClearsWithoutRequest() async {
    let source = StubLiveOpsSource(.init(alertEvents: { _, _ in [firingEvent(1)] }, alertCounts: { AlertCounts(firing: 1) }))
    let store = LiveOpsHarness(source).store
    await store.refreshFiringAlerts()
    #expect(store.firingAlerts.map(\.id) == [1])
    await store.noteOpsDisabled()
    #expect(store.firingAlerts.isEmpty && store.firingAlerts(platform: "anthropic").isEmpty)
    await store.refreshFiringAlerts(maxAge: 0)
    #expect(await source.count(isAlertList) == 1)

    let refused = StubLiveOpsSource(.init(alertEvents: { _, _ in throw opsDisabledError }, alertCounts: { throw opsDisabledError }))
    let closed = LiveOpsHarness(refused).store
    await closed.refreshFiringAlerts()
    #expect(closed.opsDisabled && closed.firingAlerts.isEmpty)
}

@MainActor @Test func availabilityUpdatesAccountErrorBadge() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply(availability: .ok(errorSummary([7, 9]))) }, errorAccounts: { [] }))
    let harness = LiveOpsHarness(source)
    await harness.store.refreshHome(noCache: false)
    #expect(harness.badge.errorCount == 2)
    let readAt = harness.badge.updatedAt
    await source.update { $0.home = { _ in homeReply(availability: HomeSection(status: .error, reason: "INTERNAL_ERROR")) } }
    await harness.store.refreshHome(noCache: false)
    #expect(harness.badge.errorCount == 2 && harness.badge.updatedAt == readAt)
    await source.update { $0.home = { _ in homeReply(availability: .ok(errorSummary([]))) } }
    await harness.store.refreshHome(noCache: false)
    #expect(harness.badge.errorCount == 0)
}

/// 00 §4.6, 10 §1.2: home keeps its own 60-second timer while a slow 今日 SLA is still on its way, and that read is not sent again.
@MainActor @Test func homePollingKeepsItsOwnPaceWhileTodaySLAIsSlow() async {
    let gate = SessionGate()
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }, overview: { _, _ in
        await gate.wait()
        return OpsOverview(sla: 0.99)
    }))
    let harness = LiveOpsHarness(source, site: liveOpsSite([.dashboardHome]), sleeper: PollSleeper(parks: true))
    let store = harness.store
    let polling = Task { await store.homePolling() }
    await waitUntil {
        let arrived = await gate.arrived, parked = await harness.sleeper.parkedCount
        return arrived && parked == 1
    }
    await harness.sleeper.releaseAll()
    await waitUntil {
        let parked = await harness.sleeper.parkedCount, calls = await source.homeCalls.count
        return parked == 1 && calls == 2
    }
    #expect(await source.homeCalls == [false, false])
    #expect(await harness.sleeper.seconds == [60, 60])
    #expect(await source.count(isOverview) == 1)
    #expect(store.todayOps.isLoading)
    await gate.open()
    await waitUntil { store.todaySLA != nil }
    #expect(store.todaySLA == 0.99)
    await harness.sleeper.stop()
    await polling.value
}

/// 10 §1.6: a countdown reads home only; neither it nor a pull cancels and resends an extra read still in flight.
@MainActor @Test func countdownAndPullLeaveSlowExtraReadsInFlight() async {
    let gate = SessionGate()
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }, overview: { _, _ in
        await gate.wait()
        return OpsOverview(sla: 0.99)
    }, ranking: {
        await gate.wait()
        return [AccountsRankingItem(accountID: 1, actualCost: 5)]
    }))
    let harness = LiveOpsHarness(source)
    let store = harness.store
    store.setCalmVisible(true)
    let first = Task { await store.refreshHome(noCache: false) }
    await waitUntil { store.home.stats.value != nil && store.todayOps.isLoading && store.ranking.isLoading }
    let countdown = Task { await store.countdownElapsed() }
    await waitUntil { await source.homeCalls.count == 2 && !store.homeRequest.isLoading }
    let pull = Task { await store.refreshHome(noCache: true) }
    await waitUntil { await source.homeCalls.count == 3 && !store.homeRequest.isLoading }
    #expect(await source.homeCalls == [false, false, true])
    #expect(await source.count(isOverview) == 1)
    #expect(await source.count(isRanking) == 1)
    #expect(store.todayOps.isLoading && store.ranking.isLoading)
    await gate.open()
    await first.value
    await countdown.value
    await pull.value
    await store.rankingTask?.value
    #expect(store.todaySLA == 0.99 && store.ranking.value?.map(\.accountID) == [1])
}

/// 00 §4.6: each timer backs off on its own failures; the ranking's reads only once the calm layout shows.
@MainActor @Test func homePollingBacksOffEachReadOnItsOwn() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }, overview: { _, _ in throw serverFailure }, ranking: { [] }))
    let harness = LiveOpsHarness(source, sleeper: PollSleeper(parks: true))
    let store = harness.store
    let polling = Task { await store.homePolling() }
    await waitUntil { await harness.sleeper.parkedCount == 3 }
    #expect(await harness.sleeper.seconds.sorted() == [60, 60, 120])
    #expect(await source.count(isRanking) == 0)
    store.setCalmVisible(true)
    await store.rankingTask?.value
    await harness.sleeper.releaseAll()
    await waitUntil { await harness.sleeper.parkedCount == 3 }
    #expect(await harness.sleeper.seconds.sorted() == [60, 60, 60, 60, 120, 240])
    #expect(await source.homeCalls.count == 2)
    #expect(await source.count(isOverview) == 2)
    #expect(await source.count(isRanking) == 2)
    await harness.sleeper.stop()
    await polling.value
}
