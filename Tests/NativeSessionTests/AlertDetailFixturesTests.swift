import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-12: the alert detail's `-ui-testing` reads (LiveOpsFixtures+AlertDetail.swift), which AlertDetailUITests rely on.

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
