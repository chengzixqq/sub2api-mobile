import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-16: 监控 · 告警's reads (10 §6.2, §6.5, §6.6): 告警中 is the shared firing list (20 §1.2), 最近结束 pages back through the
// last day; the segment polls while it shows.

private typealias Request = StubLiveOpsSource.AlertEventsRequest
private let serverFailure = APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")
private let start = Date()
private func alert(_ id: Int, _ status: String = "resolved", minutesAgo: Double, severity: String = "P2") -> AlertEvent {
    AlertEvent(id: id, ruleID: id, severity: severity, status: status, firedAt: start.addingTimeInterval(-minutesAgo * 60))
}
/// `count` ended events from `firstID` down, a minute apart from `minutesAgo` on.
private func ended(from firstID: Int, count: Int, minutesAgo: Double) -> [AlertEvent] {
    (0..<count).map { alert(firstID - $0, minutesAgo: minutesAgo + Double($0)) }
}
private let firingPair = [alert(41, "firing", minutesAgo: 12, severity: "P1"), alert(40, "firing", minutesAgo: 26)]
private func isFiringRead(_ request: Request) -> Bool { request.status == "firing" }
private func isEndedRead(_ request: Request) -> Bool { request.status == nil }

/// 告警中 answers `firingPair`; 最近结束 answers `ended`.
@MainActor private func alertsHarness(site: SiteSession = liveOpsSite(), sleeper: PollSleeper = PollSleeper(),
                                      ended: @escaping @Sendable (Request) async throws -> [AlertEvent]) -> LiveOpsHarness {
    let source = StubLiveOpsSource(.init(alertCounts: { AlertCounts.counting(firingPair) }, alertEventPages: { request in
        request.status == "firing" ? firingPair : try await ended(request)
    }))
    return LiveOpsHarness(source, site: site, sleeper: sleeper)
}
@MainActor private func endedRequests(_ harness: LiveOpsHarness) async -> [Request] {
    await harness.source.alertEventRequests.filter(isEndedRead)
}

/// Holds the answers that wait on it until `open()`.
private actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}

/// 10 §6.2: with `ops.alert_event_counts` 告警中 reads 100 and the counts; 最近结束 reads the last day, 50 at a time, without a cursor.
@MainActor @Test func refreshSendsFiringCountsAndEndedRequests() async {
    let harness = alertsHarness { _ in [alert(37, minutesAgo: 82)] }
    await harness.store.refreshMonitorAlerts(force: true)
    let requests = await harness.source.alertEventRequests
    #expect(requests.filter(isFiringRead) == [Request(status: "firing", timeRange: nil, limit: 100, before: nil)])
    #expect(requests.filter(isEndedRead) == [Request(status: nil, timeRange: "24h", limit: 50, before: nil)])
    #expect(await harness.source.count { $0 == .alertCounts } == 1)
    #expect(harness.store.recentAlerts.map(\.id) == [37] && harness.store.monitorFiringRows.map(\.id) == [41, 40])

    let legacy = alertsHarness(site: liveOpsSite([.dashboardHome])) { _ in [] }
    await legacy.store.refreshMonitorAlerts(force: true)
    #expect(await legacy.source.alertEventRequests.filter(isFiringRead).map(\.limit) == [500])
    #expect(await legacy.source.count { $0 == .alertCounts } == 0)
}

/// 最近结束 filters firing events out (10 §6.2); an event already ended there leaves 告警中 too.
@MainActor @Test func endedRowsExcludeFiringAndFiringRowsDropEnded() async {
    let harness = alertsHarness { _ in [alert(41, "firing", minutesAgo: 12), alert(40, minutesAgo: 26), alert(37, minutesAgo: 82)] }
    await harness.store.refreshMonitorAlerts(force: true)
    #expect(harness.store.recentAlerts.map(\.id) == [40, 37])
    #expect(harness.store.firingAlerts.map(\.id) == [41, 40] && harness.store.monitorFiringRows.map(\.id) == [41])
}

/// 20 §1.2 / §1.6: the firing list another page read under a minute ago is reused; a pull reads both again.
@MainActor @Test func firingListReusedWithinSixtySecondsWhenNotForced() async {
    let harness = alertsHarness { _ in [] }
    await harness.store.refreshFiringAlerts()
    harness.advance(by: 30)
    await harness.store.refreshMonitorAlerts(force: false)
    var requests = await harness.source.alertEventRequests
    #expect(requests.filter(isFiringRead).count == 1 && requests.filter(isEndedRead).count == 1)
    await harness.store.refreshMonitorAlerts(force: true)
    requests = await harness.source.alertEventRequests
    #expect(requests.filter(isFiringRead).count == 2 && requests.filter(isEndedRead).count == 2)
}

/// 10 §6.2 更早: the cursor is the page's last event as sent (a firing one here), so the next page starts after it.
@MainActor @Test func loadEarlierSendsCursorOfLastRawEventAndAppends() async throws {
    let first = ended(from: 500, count: 49, minutesAgo: 30) + [alert(451, "firing", minutesAgo: 80)]
    let older = ended(from: 450, count: 7, minutesAgo: 81)
    let harness = alertsHarness { $0.before == nil ? first : older }
    let store = harness.store
    await store.refreshMonitorAlerts(force: true)
    #expect(store.recentAlerts.count == 49 && store.monitorEndedFooter == .loadEarlier)
    await store.loadEarlierAlerts()
    let last = try #require(await endedRequests(harness).last)
    #expect(last == Request(status: nil, timeRange: "24h", limit: 50, before: first.last?.cursor) && last.before != nil)
    #expect(store.recentAlerts.map(\.id) == Array((452...500).reversed()) + Array((444...450).reversed()))
    #expect(store.monitorEndedFooter == .none)
}

/// 10 §6.5 last row: a reasonless 400 to 加载更早 drops the cursor and reads the first page again.
@MainActor @Test func cursorRejectedReloadsFirstPageWithoutCursor() async {
    let first = ended(from: 500, count: 50, minutesAgo: 30)
    let fresh = ended(from: 510, count: 50, minutesAgo: 1)
    let reads = Tally()
    let harness = alertsHarness { request in
        if request.before != nil { throw APIError.server(status: 400, reason: nil) }
        return reads.next() == 1 ? first : fresh
    }
    let store = harness.store
    await store.refreshMonitorAlerts(force: true)
    await store.loadEarlierAlerts()
    #expect(await endedRequests(harness).map { $0.before == nil } == [true, false, true])
    #expect(store.recentAlerts == RecentAlerts.firstPage(fresh, limit: 50).events)
    #expect(store.monitor.alertsEarlier.error == nil && store.monitorEndedFooter == .loadEarlier)
}

/// Any other failure of 加载更早 stays on its own row, which retries; the loaded rows stay.
@MainActor @Test func earlierFailureOffersRetry() async {
    let first = ended(from: 500, count: 50, minutesAgo: 30)
    let harness = alertsHarness { request in
        if request.before != nil { throw serverFailure }
        return first
    }
    let store = harness.store
    await store.refreshMonitorAlerts(force: true)
    await store.loadEarlierAlerts()
    #expect(store.monitorEndedFooter == .failed && store.recentAlerts.count == 50)
    #expect(await endedRequests(harness).count == 2)
}

/// A poll merges its first page and keeps what 加载更早 added; a pull starts over from the first page.
@MainActor @Test func pollingMergesWhilePullToRefreshResets() async {
    let first = ended(from: 500, count: 50, minutesAgo: 30)
    let older = ended(from: 450, count: 50, minutesAgo: 80)
    let harness = alertsHarness { $0.before == nil ? first : older }
    let store = harness.store
    await store.refreshMonitorAlerts(force: true)
    await store.loadEarlierAlerts()
    let cursor = store.recent.value?.cursor
    #expect(store.recentAlerts.count == 100 && cursor == older.last?.cursor)
    await store.refreshMonitorAlerts(force: false)
    #expect(store.recentAlerts.count == 100 && store.recent.value?.cursor == cursor)
    await store.refreshMonitorAlerts(force: true)
    #expect(store.recentAlerts.map(\.id) == first.map(\.id) && store.recent.value?.cursor == first.last?.cursor)
}

/// More than a page fired and ended while the segment was away: the poll starts over from its page and 加载更早 reads the gap.
@MainActor @Test func pollAfterGapStartsOverFromItsPage() async {
    let old = ended(from: 300, count: 20, minutesAgo: 600)
    let fresh = ended(from: 400, count: 50, minutesAgo: 1)
    let reads = Tally()
    let harness = alertsHarness { request in
        guard request.before == nil else { return ended(from: 350, count: 10, minutesAgo: 51) }
        return reads.next() == 1 ? old : fresh
    }
    let store = harness.store
    await store.refreshMonitorAlerts(force: true)
    #expect(store.monitorEndedFooter == .none)
    await store.refreshMonitorAlerts(force: false)
    #expect(store.recentAlerts.map(\.id) == fresh.map(\.id) && store.monitorEndedFooter == .loadEarlier)
    await store.loadEarlierAlerts()
    #expect(await endedRequests(harness).last?.before == fresh.last?.cursor)
    #expect(store.recentAlerts.map(\.id) == Array((341...400).reversed()))
}

/// A pull while 加载更早 is on its way: that page never lands.
@MainActor @Test func pullDropsEarlierPageStillOnItsWay() async {
    let gate = Gate()
    let first = ended(from: 500, count: 50, minutesAgo: 30)
    let harness = alertsHarness { request in
        guard request.before != nil else { return first }
        await gate.wait()
        return ended(from: 450, count: 10, minutesAgo: 80)
    }
    let store = harness.store
    await store.refreshMonitorAlerts(force: true)
    let earlier = Task { await store.loadEarlierAlerts() }
    await waitUntil { await endedRequests(harness).count == 2 }
    #expect(store.monitorEndedFooter == .loading)
    await store.refreshMonitorAlerts(force: true)
    await gate.open()
    await earlier.value
    #expect(store.recentAlerts.map(\.id) == first.map(\.id) && store.monitorEndedFooter == .loadEarlier)
}

/// 10 §6.6, 00 §4.6: 60 seconds after a good read, doubling to 300 while 最近结束 fails; a cancelled wait ends the loop.
@MainActor @Test func pollingSleepsSixtySecondsAndBacksOff() async {
    let calm = alertsHarness(sleeper: PollSleeper(stopAfter: 1)) { _ in [] }
    await calm.store.monitorAlertsPolling()
    #expect(await calm.sleeper.seconds == [60])
    let failing = alertsHarness(sleeper: PollSleeper(stopAfter: 3)) { _ in throw serverFailure }
    await failing.store.monitorAlertsPolling()
    #expect(await failing.sleeper.seconds == [120, 240, 300])
    #expect(await endedRequests(failing).count == 3)
}

/// Back on the segment under ten seconds after its last answer: the rest of the ten seconds first, nothing read before.
@MainActor @Test func alertsPollingWaitsOutReentryGap() async {
    let harness = alertsHarness(sleeper: PollSleeper(stopAfter: 1)) { _ in [] }
    await harness.store.refreshMonitorAlerts(force: false)
    harness.advance(by: 4)
    await harness.store.monitorAlertsPolling()
    #expect(await harness.sleeper.seconds == [6])
    #expect(await endedRequests(harness).count == 1)
}

/// 10 §6.5 first row: 404 OPS_DISABLED turns the switch off and ends the polling; a poll then reads nothing.
@MainActor @Test func opsDisabledReplyStopsPolling() async {
    let source = StubLiveOpsSource(.init(alertEvents: { _, _ in throw opsDisabledError }, alertCounts: { throw opsDisabledError }))
    let harness = LiveOpsHarness(source)
    await harness.store.monitorAlertsPolling()
    #expect(harness.store.opsDisabled)
    #expect(await harness.sleeper.seconds.isEmpty)
    let sent = await source.alertEventRequests.count
    await harness.store.refreshMonitorAlerts(force: false)
    #expect(await source.alertEventRequests.count == sent)
}

/// Like 概况's pull, a pull asks 最近结束 even while the switch says off, so a 200 turns it back on (10 §7.2).
@MainActor @Test func pullAsksEvenWhileSwitchSaysOff() async {
    let harness = alertsHarness(site: liveOpsSite(opsEnabled: false)) { _ in [alert(37, minutesAgo: 82)] }
    #expect(harness.store.opsDisabled)
    await harness.store.refreshMonitorAlerts(force: false)
    #expect(await harness.source.alertEventRequests.isEmpty)
    await harness.store.refreshMonitorAlerts(force: true)
    #expect(await harness.source.alertEventRequests.map(\.status) == [nil])
    #expect(!harness.store.opsDisabled && harness.store.recentAlerts.map(\.id) == [37])
}

/// 10 §6.5: a failed refresh keeps the rows and marks them; the sections stay.
@MainActor @Test func failedRefreshKeepsRowsAndMarksFailure() async {
    let replies = Tally()
    let harness = alertsHarness { _ in
        guard replies.next() == 1 else { throw serverFailure }
        return [alert(37, minutesAgo: 82)]
    }
    let store = harness.store
    await store.refreshMonitorAlerts(force: false)
    await store.refreshMonitorAlerts(force: false)
    #expect(store.recentAlerts.map(\.id) == [37] && store.recent.error != nil)
    #expect(store.monitorAlertsLayout == .sections)
}

/// 10 §7.1 step 3: a manual resolve moves the row from 告警中 into 最近结束 at its fire time.
@MainActor @Test func manualResolveMovesEventIntoEndedInOrder() async {
    let harness = alertsHarness { _ in [alert(50, minutesAgo: 5), alert(37, minutesAgo: 82)] }
    let store = harness.store
    await store.refreshMonitorAlerts(force: true)
    store.markResolved(eventID: 41, at: start)
    #expect(store.firingAlerts.map(\.id) == [40] && store.monitorFiringRows.map(\.id) == [40])
    #expect(store.recentAlerts.map(\.id) == [50, 41, 37] && store.recentAlerts[1].status == AlertEvent.manualResolved)
}

/// 10 §6.6: after a write 最近结束 is read again too, once it was ever read.
@MainActor @Test func writeRefreshReloadsEndedOnlyWhenLoaded() async {
    let harness = alertsHarness { _ in [alert(37, minutesAgo: 82)] }
    let store = harness.store
    await store.refreshAlertsAfterWrite()
    #expect(await endedRequests(harness).isEmpty)
    await store.refreshMonitorAlerts(force: true)
    await store.refreshAlertsAfterWrite()
    #expect(await endedRequests(harness).count == 2 && store.recentAlerts.map(\.id) == [37])
}

@MainActor @Test func lateEndedReplyAfterSessionChangeIsDropped() async {
    let gate = Gate()
    let harness = alertsHarness { _ in
        await gate.wait()
        return [alert(37, minutesAgo: 82)]
    }
    let refresh = Task { await harness.store.refreshRecentAlerts(reset: true) }
    await waitUntil { await endedRequests(harness).count == 1 }
    harness.isCurrent = false
    await gate.open()
    await refresh.value
    #expect(harness.store.recent.value == nil)
}
