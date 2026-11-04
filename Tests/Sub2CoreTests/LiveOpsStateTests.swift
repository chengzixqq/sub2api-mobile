import Foundation
import Testing
@testable import Sub2Core

// S1-05: the home blocks LiveOpsStore keeps (10 §1.5), its ops evidence, error account alignment and the local alert edits.

private let received = Date(timeIntervalSince1970: 1_800_000_000)
private let earlier = received.addingTimeInterval(-60)

private func reply(stats: HomeSection<HomeStats> = .ok(HomeStats(todayRequests: 9)),
                   rates: HomeSection<LiveRates> = .ok(LiveRates(rpm: 4, opsMonitoringEnabled: true)),
                   hourly: HomeSection<HomeHourly> = .ok(HomeHourly(timezone: "Asia/Shanghai")),
                   ops: HomeSection<HomeOps> = .ok(HomeOps(healthScore: 94)), alerts: HomeSection<HomeAlerts> = .ok(HomeAlerts()),
                   availability: HomeSection<AccountStatusSummary> = .ok(AccountStatusSummary()),
                   channels: HomeSection<HomeChannels> = .ok(HomeChannels(total: 1, healthy: 1))) -> DashboardHome {
    // generated_at is an hour old, as in a 304 reuse: block times must come from `receivedAt`.
    DashboardHome(generatedAt: earlier.addingTimeInterval(-3_600), stats: stats, rates: rates, hourly: hourly, ops: ops, alerts: alerts,
                  availability: availability, channels: channels)
}
private func failed<Value>(_ reason: String) -> HomeSection<Value> { HomeSection(status: .error, reason: reason) }
private let timedOut = HomeSection<HomeHourly>(status: .timeout, reason: "SECTION_TIMEOUT")
private func event(_ id: Int, severity: String = "P1", status: String = "firing", minutesAgo: Double = 10) -> AlertEvent {
    AlertEvent(id: id, severity: severity, status: status, firedAt: received.addingTimeInterval(-minutesAgo * 60))
}

@Test func okSectionReplacesValueWithReceiptTime() {
    let blocks = HomeBlocks().merging(reply(), receivedAt: received)
    #expect(blocks.stats == .loaded(HomeStats(todayRequests: 9), at: received))
    #expect(blocks.ops.updatedAt == received && blocks.channels.value?.total == 1 && blocks.availability.value == AccountStatusSummary())
    #expect(blocks.lastFullSuccessAt == received && !blocks.hasFailedBlock)
    #expect(HomeBlocks().stats == .idle && HomeBlocks().lastFullSuccessAt == nil)
}

@Test func disabledSectionRecordsReason() {
    let previous = HomeBlocks().merging(reply(), receivedAt: earlier)
    let blocks = previous.merging(reply(ops: HomeSection(status: .disabled, reason: "OPS_DISABLED"),
                                        alerts: HomeSection(status: .disabled, reason: "OPS_DISABLED"),
                                        channels: HomeSection(status: .disabled, reason: "CHANNEL_MONITOR_DISABLED")), receivedAt: received)
    #expect(blocks.ops == .disabled(reason: "OPS_DISABLED") && blocks.alerts == .disabled(reason: "OPS_DISABLED"))
    #expect(blocks.channels == .disabled(reason: "CHANNEL_MONITOR_DISABLED") && blocks.channels.value == nil)
    #expect(blocks.lastFullSuccessAt == received && !blocks.hasFailedBlock)
}

@Test func errorAndTimeoutKeepPreviousValueAndMark() {
    let previous = HomeBlocks().merging(reply(), receivedAt: earlier)
    let blocks = previous.merging(reply(stats: failed("INTERNAL_ERROR"), hourly: timedOut), receivedAt: received)
    #expect(blocks.stats == .failed(reason: HomeBlockText.failed, previous: HomeStats(todayRequests: 9), at: earlier))
    #expect(blocks.hourly == .failed(reason: HomeBlockText.timedOut, previous: HomeHourly(timezone: "Asia/Shanghai"), at: earlier))
    let fresh = HomeBlocks().merging(reply(stats: failed("INTERNAL_ERROR"), hourly: timedOut), receivedAt: received)
    #expect(fresh.stats == .failed(reason: "加载失败", previous: nil, at: nil) && fresh.hourly == .failed(reason: "加载超时", previous: nil, at: nil))
    #expect(HomeBlockText.failed == "加载失败" && HomeBlockText.timedOut == "加载超时")
}

@Test func okWithoutDataCountsAsFailure() {
    let previous = HomeBlocks().merging(reply(), receivedAt: earlier)
    let blocks = previous.merging(reply(stats: HomeSection(status: .ok, data: nil)), receivedAt: received)
    #expect(blocks.stats == .failed(reason: HomeBlockText.failed, previous: HomeStats(todayRequests: 9), at: earlier))
    #expect(blocks.hasFailedBlock && blocks.lastFullSuccessAt == earlier)
}

@Test func oneSectionFailureLeavesOthersIndependent() {
    let previous = HomeBlocks().merging(reply(stats: .ok(HomeStats(todayRequests: 1))), receivedAt: earlier)
    let blocks = previous.merging(reply(stats: .ok(HomeStats(todayRequests: 2)), hourly: timedOut), receivedAt: received)
    #expect(blocks.hourly.failureReason == HomeBlockText.timedOut && blocks.hasFailedBlock)
    #expect(blocks.stats == .loaded(HomeStats(todayRequests: 2), at: received))
    #expect([blocks.rates.updatedAt, blocks.ops.updatedAt, blocks.alerts.updatedAt, blocks.availability.updatedAt, blocks.channels.updatedAt]
        .allSatisfy { $0 == received })
}

@Test func lastFullSuccessOnlyWithoutErrorOrTimeout() {
    let first = HomeBlocks().merging(reply(), receivedAt: earlier)
    #expect(first.merging(reply(channels: failed("INTERNAL_ERROR")), receivedAt: received).lastFullSuccessAt == earlier)
    #expect(first.merging(reply(hourly: timedOut), receivedAt: received).lastFullSuccessAt == earlier)
    #expect(first.merging(reply(ops: HomeSection(status: .disabled, reason: "OPS_DISABLED")), receivedAt: received).lastFullSuccessAt == received)
    #expect(HomeBlocks().merging(reply(hourly: timedOut), receivedAt: received).lastFullSuccessAt == nil)
}

@Test func opsDisabledEvidenceFromSectionsAndRates() {
    let off = HomeSection<HomeOps>(status: .disabled, reason: "OPS_DISABLED")
    #expect(reply(ops: off).opsDisabledEvidence == true)
    #expect(reply(alerts: HomeSection(status: .disabled, reason: "OPS_DISABLED")).opsDisabledEvidence == true)
    #expect(reply(rates: .ok(LiveRates(opsMonitoringEnabled: false))).opsDisabledEvidence == true)
    #expect(reply().opsDisabledEvidence == false)
    // An ops block the server answered with error or timeout means monitoring ran (S1D1-02).
    #expect(reply(rates: .missing, ops: failed("INTERNAL_ERROR"), alerts: .missing).opsDisabledEvidence == false)
    #expect(reply(rates: .missing, ops: HomeSection(status: .timeout, reason: "SECTION_TIMEOUT"), alerts: .missing).opsDisabledEvidence == false)
    // A block the client could not read says nothing.
    #expect(reply(rates: .ok(LiveRates()), ops: .missing, alerts: .missing).opsDisabledEvidence == nil)
}

@Test func errorAccountIDsAndAlignment() {
    let summary = AccountStatusSummary(accounts: [
        AccountStatusItem(id: 7, state: .error), AccountStatusItem(id: 11, state: .overloaded), AccountStatusItem(id: 9, state: .error),
        AccountStatusItem(id: 4, state: nil)])
    #expect(summary.errorAccountIDs == [7, 9])
    let fetched = [UpstreamAccount(id: 9, name: "b", platform: "openai", type: "apikey", errorSummary: "429"),
                   UpstreamAccount(id: 5, name: "gone", platform: "openai", type: "apikey"),
                   UpstreamAccount(id: 7, name: "a", platform: "openai", type: "apikey", errorSummary: "401")]
    #expect(summary.aligningStructuredErrors(fetched).map(\.id) == [7, 9])
    #expect(AccountStatusSummary().errorAccountIDs.isEmpty && AccountStatusSummary().aligningStructuredErrors(fetched).isEmpty)
}

@Test func alertCountsCountingAndRemovingFiring() {
    let silenced = event(3, severity: "p2").withSilence(AlertSilenceRef(id: 1))
    let counts = AlertCounts.counting([event(1), event(2, severity: " P1 "), silenced, event(4, status: "resolved"), event(5, severity: "P9")])
    #expect(counts.firing == 4 && counts.count(severity: "P1") == 2 && counts.count(severity: "P2") == 1 && counts.count(severity: "P9") == 1)
    #expect(counts.bySeverity["P0"] == 0 && counts.bySeverity["P3"] == 0)
    let fewer = counts.removingFiring(severity: "p1")
    #expect(fewer.firing == 3 && fewer.count(severity: "P1") == 1 && counts.firing == 4)
    let none = AlertCounts(firing: 0, bySeverity: [:]).removingFiring(severity: "P1")
    #expect(none.firing == 0 && none.count(severity: "P1") == 0)
}

@Test func homeAlertsRemovingAndMappingEvents() {
    let alerts = HomeAlerts(firingCount: 3, bySeverity: ["P0": 0, "P1": 2, "P2": 1, "P3": 0], top: [event(1), event(2, severity: "P2")])
    let resolved = alerts.removingFiring(event(1))
    #expect(resolved.top.map(\.id) == [2] && resolved.firingCount == 2 && resolved.count(severity: "P1") == 1)
    // An event beyond the five listed still leaves the counts.
    let unlisted = alerts.removingFiring(event(9, severity: "P2"))
    #expect(unlisted.top.count == 2 && unlisted.firingCount == 2 && unlisted.count(severity: "P2") == 0)
    #expect(HomeAlerts().removingFiring(event(1)).firingCount == 0 && HomeAlerts().removingFiring(event(1)).count(severity: "P1") == 0)
    let silence = AlertSilenceRef(id: 501)
    let mapped = alerts.mapEvents { $0.id == 2 ? $0.withSilence(silence) : $0 }
    #expect(mapped.top.map(\.silence) == [nil, silence] && mapped.firingCount == 3 && mapped.bySeverity == alerts.bySeverity)
}

@Test func recentAlertsKeepEndedEventsNewestFirst() {
    let recent = RecentAlerts(events: [event(3, status: "resolved", minutesAgo: 30), event(4, status: "firing", minutesAgo: 5),
                                       event(5, status: "manual_resolved", minutesAgo: 10), event(3, status: "resolved", minutesAgo: 30)])
    #expect(recent.events.map(\.id) == [5, 3] && recent.cursor == nil)
    let resolved = event(6, minutesAgo: 20).resolvedLocally(at: received)
    let upserted = recent.upserting(resolved)
    #expect(upserted.events.map(\.id) == [5, 6, 3] && upserted.events[1].status == AlertEvent.manualResolved)
    #expect(upserted.upserting(event(6, minutesAgo: 20)).events.map(\.id) == [5, 3])
    #expect(upserted.removing(eventID: 5).events.map(\.id) == [6, 3])
    let silence = AlertSilenceRef(id: 9)
    #expect(upserted.mapEvents { $0.withSilence(silence) }.events.allSatisfy { $0.silence == silence })
}

@Test func recentAlertsFirstPageCursor() {
    let raw = [event(8, status: "firing", minutesAgo: 1), event(7, status: "resolved", minutesAgo: 2)]
    let full = RecentAlerts.firstPage(raw, limit: 2)
    #expect(full.events.map(\.id) == [7] && full.cursor == raw[1].cursor && full.cursor != nil)
    #expect(RecentAlerts.firstPage(raw, limit: 50).cursor == nil)
    #expect(RecentAlerts.firstPage([], limit: 50) == RecentAlerts())
}
