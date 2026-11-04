import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-12: the alert detail's `-ui-testing` reads (LiveOpsFixtures+AlertDetail.swift), which AlertDetailUITests rely on.
// S1-17 adds the error counts and the site-wide variant at the end.

private let base = Date()
private func source(_ change: (inout LiveOpsFixtures.Options) -> Void = { _ in }) -> FixtureLiveOpsSource {
    var options = LiveOpsFixtures.Options()
    change(&options)
    return FixtureLiveOpsSource(options: options, base: base)
}

@Test func alertDetailArgumentsParse() {
    let options = LiveOpsFixtures.Options(arguments: ["-ui-alert-gone", "-ui-alert-detail-ops-disabled", "-ui-without-capabilities",
                                                      "dashboard.home,ops.alert_event_details"])
    #expect(options.alertGone && options.alertDetailOpsOff && options.withholdsAlertDetails && !options.alertDetailTurnedOpsOff)
    #expect(!LiveOpsFixtures.Options(arguments: ["-ui-without-capabilities", "dashboard.home"]).withholdsAlertDetails)
    #expect(!LiveOpsFixtures.Options(arguments: []).alertGone)
}

@Test func alertGoneAnswersNotFoundForEveryEvent() async {
    let gone = source { $0.alertGone = true }
    for id in [LiveOpsFixtureIDs.alertA, LiveOpsFixtureIDs.anthropicFiringEventID] {
        await #expect(throws: LiveOpsFixtures.alertGoneError) { try await gone.alertEvent(id: id) }
    }
}

@Test func theDetailFindsOpsTurnedOffOnceUntilTheAppTurnsItOn() async throws {
    let off = source { $0.alertDetailOpsOff = true }
    await #expect(throws: LiveOpsFixtures.opsDisabledError) { try await off.alertEvent(id: LiveOpsFixtureIDs.alertA) }
    #expect(await off.options.ops == .settingOff)
    await #expect(throws: LiveOpsFixtures.opsDisabledError) { try await off.alertEvent(id: LiveOpsFixtureIDs.alertA) }
    _ = try await off.setOpsMonitoring(enabled: true)
    #expect(try await off.alertEvent(id: LiveOpsFixtureIDs.alertA).id == LiveOpsFixtureIDs.alertA)
}

@Test func anOldServersEventsComeWithoutRuleOrGroupName() async throws {
    let old = source { $0.withholdsAlertDetails = true }
    let event = try await old.alertEvent(id: LiveOpsFixtureIDs.alertA)
    #expect(event.rule == nil && event.groupName == nil && event.ruleID == 11 && event.groupID == LiveOpsFixtureIDs.standardGroup)
    let listed = try await old.alertEvents(status: "firing", timeRange: nil, limit: 100, before: nil, groupID: nil, platform: nil)
    #expect(listed.count == 2 && listed.allSatisfy { $0.rule == nil && $0.groupName == nil })
    let home = try await old.dashboardHome(timezone: LiveOpsFixtures.serverTimeZone, include: nil, noCache: false)
    #expect(home.alerts.data?.top.allSatisfy { $0.rule == nil } == true)
    #expect(try await source().alertEvent(id: LiveOpsFixtureIDs.alertA).rule?.windowMinutes == 5)
}

@Test func aGroupsStatusSummaryHoldsOnlyThatGroup() async {
    let fixtures = source()
    let summary = await fixtures.accountStatusSummary(platform: nil, groupID: LiveOpsFixtureIDs.standardGroup, includeAccounts: false)
    let group = summary.groups.first
    #expect(summary.groups.count == 1 && group?.groupName == "标准组" && group?.platform == "openai")
    #expect(group?.counts.total == 2 && group?.counts.available == 1 && group?.counts.needsAttention == 1)
    #expect(await fixtures.accountStatusSummary(platform: nil, groupID: 999, includeAccounts: false).groups.isEmpty)
    #expect(await fixtures.accountStatusSummary(platform: nil, groupID: nil, includeAccounts: false).groups.map(\.groupID) == [LiveOpsFixtureIDs.shortageGroup])
}

// MARK: - 错误请求计数（S1-17）

private func countFilter(_ groupID: Int?) -> RequestLogFilter { RequestLogFilter(time: .rolling(.h24), groupID: groupID, pageSize: 1) }

@Test func fixtureErrorCountsFollowScopeKindAndSwitches() async throws {
    let fixtures = source()
    let standard = LiveOpsFixtureIDs.standardGroup
    #expect(try await fixtures.errorCount(filter: countFilter(standard), kind: .request) == 37)
    #expect(try await fixtures.errorCount(filter: countFilter(standard), kind: .upstream) == 9)
    #expect(try await fixtures.errorCount(filter: countFilter(nil), kind: .request) == 128)
    #expect(try await fixtures.errorCount(filter: countFilter(nil), kind: .upstream) == 41)
    #expect(try await fixtures.errorCount(filter: countFilter(LiveOpsFixtureIDs.shortageGroup), kind: .request) == 0)
    let off = source { $0.ops = .settingOff }
    await #expect(throws: LiveOpsFixtures.opsDisabledError) { try await off.errorCount(filter: countFilter(standard), kind: .request) }
    let failing = source { $0.errorCountFails = true }
    await #expect(throws: LiveOpsFixtures.errorCountError) { try await failing.errorCount(filter: countFilter(standard), kind: .request) }
    #expect(try await failing.errorCount(filter: countFilter(standard), kind: .request) == 37)
}

@Test func siteWideFixtureDropsOnlyAlertAsGroup() async throws {
    let options = LiveOpsFixtures.Options(arguments: ["-ui-alert-site-wide", "-ui-alert-error-count-fails"])
    #expect(options.alertSiteWide && options.errorCountFails && !options.errorCountFailed)
    let none = LiveOpsFixtures.Options(arguments: [])
    #expect(!none.alertSiteWide && !none.errorCountFails)
    let siteWide = source { $0.alertSiteWide = true }, plain = source()
    let alertA = try await siteWide.alertEvent(id: LiveOpsFixtureIDs.alertA)
    #expect(alertA.groupID == nil && alertA.groupName == nil && alertA.rule?.metricType == "error_rate" && alertA.platform == nil)
    #expect(AlertScopePresentation.kind(alertA) == .siteWide)
    let original = try await plain.alertEvent(id: LiveOpsFixtureIDs.alertA)
    #expect(alertA.cursor == original.cursor && alertA.title == original.title && alertA.silence == original.silence)
    let others = await siteWide.events.filter { $0.id != LiveOpsFixtureIDs.alertA }
    let plainOthers = await plain.events.filter { $0.id != LiveOpsFixtureIDs.alertA }
    #expect(others == plainOthers)
    let zone = LiveOpsFixtures.serverTimeZone
    let top = try await siteWide.dashboardHome(timezone: zone, include: nil, noCache: false).alerts.data?.top.map(\.id)
    let plainTop = try await plain.dashboardHome(timezone: zone, include: nil, noCache: false).alerts.data?.top.map(\.id)
    #expect(top != nil && top == plainTop)
}
