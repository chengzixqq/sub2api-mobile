import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-05: the `-ui-testing` home fixtures (10 §1.7) read through the same pure functions the home page uses.

private let base = Date()
private let zone = LiveOpsFixtures.serverTimeZone

private func blocks(_ options: LiveOpsFixtures.Options) async throws -> (HomeBlocks, FixtureLiveOpsSource) {
    let source = FixtureLiveOpsSource(options: options, base: base)
    let home = try await source.dashboardHome(timezone: zone, include: nil, noCache: false)
    return (HomeBlocks().merging(home, receivedAt: base), source)
}
private func queue(_ blocks: HomeBlocks, _ source: FixtureLiveOpsSource) async throws -> [AttentionItem] {
    HomePresentation.attentionItems(alerts: blocks.alerts, availability: blocks.availability, structuredErrors: try await source.errorAccounts(),
                                    pending: [], now: base, timeZone: zone.timeZone)
}
private func isCalm(_ blocks: HomeBlocks) -> Bool { HomePresentation.isCalm(availability: blocks.availability, alerts: blocks.alerts, pending: []) }
private func refusedAsOpsDisabled(_ call: () async throws -> Void) async -> Bool {
    do { try await call(); return false } catch let error as APIError { return error.statusCode == 404 && error.reason == "OPS_DISABLED" } catch { return false }
}

@Test func allOKFixtureIsRegularWithExpectedQueue() async throws {
    let (home, source) = try await blocks(.init())
    #expect(!isCalm(home))
    let items = try await queue(home, source)
    #expect(items.map(\.id) == ["alert-41", "alert-40", "account-7", "account-11", "limited", "groups"])
    #expect(items[0].detail?.contains("已静默") == false && items[1].detail?.contains("已静默") == true)
    #expect(items[2].detail == "401 凭据已失效（invalid_api_key）" && items[3].kind == .overloadedAccount)
    #expect(items[4].title == "受限 2 个账号" && items[5].title == "可用不足 1 个分组")
    #expect(items[5].destination == .group(id: LiveOpsFixtureIDs.shortageGroup) && items[5].tone == .critical)
    #expect(zone.identifier == "Asia/Shanghai" && zone.rawUTCOffset == "+08:00" && home.hourly.value?.timezone == "Asia/Shanghai")
    #expect(home.alerts.value?.firingCount == 2 && home.alerts.value?.count(severity: "P1") == 1 && home.lastFullSuccessAt == base)
}

@Test func opsDisabledFixtureHasNoAlertRowsAndControlledEndpointsReturn404() async throws {
    let (home, source) = try await blocks(.init(opsDisabled: true))
    #expect(home.ops == .disabled(reason: "OPS_DISABLED") && home.alerts == .disabled(reason: "OPS_DISABLED"))
    let rates = try #require(home.rates.value)
    #expect(rates.opsMonitoringEnabled == false && rates.errorRate == nil && rates.upstream529Count == nil && rates.rpm != nil)
    #expect(await refusedAsOpsDisabled { _ = try await source.alertEvents(status: "firing", timeRange: nil, limit: 100, before: nil, groupID: nil, platform: nil) })
    #expect(await refusedAsOpsDisabled { _ = try await source.alertEventCounts() })
    #expect(await refusedAsOpsDisabled { _ = try await source.alertEvent(id: LiveOpsFixtureIDs.alertA) })
    #expect(await refusedAsOpsDisabled { _ = try await source.opsOverview(start: base.addingTimeInterval(-60), end: base) })
    #expect(try await source.opsMonitoringStatus().reason == .settingOff)
    #expect(try await queue(home, source).allSatisfy { ![.alert, .moreAlerts, .alertsFailed].contains($0.kind) })
}

@Test func availabilityErrorFixtureShowsRetryRowAndIsNotCalm() async throws {
    let (home, source) = try await blocks(.init(variant: .availabilityError))
    #expect(home.availability.failureReason == HomeBlockText.failed && !isCalm(home))
    #expect(try await queue(home, source).contains { $0.id == "retry-availability" })
    #expect(home.stats.value?.todayRequests != nil && home.rates.value?.rpm != nil)
}

@Test func hourlyTimeoutFixtureOnlyAffectsHourly() async throws {
    let options = LiveOpsFixtures.Options(variant: .hourlyTimeout)
    let timedOut = try await FixtureLiveOpsSource(options: options, base: base).dashboardHome(timezone: zone, include: nil, noCache: false)
    let regular = try await FixtureLiveOpsSource(options: .init(), base: base).dashboardHome(timezone: zone, include: nil, noCache: false)
    #expect(timedOut.hourly.status == .timeout && timedOut.hourly.reason == "SECTION_TIMEOUT" && timedOut.degradedSections() == [.hourly])
    #expect(timedOut.stats == regular.stats && timedOut.rates == regular.rates && timedOut.ops == regular.ops)
    #expect(timedOut.alerts == regular.alerts && timedOut.availability == regular.availability && timedOut.channels == regular.channels)
}

@Test func calmFixturesAreCalm() async throws {
    let (calm, calmSource) = try await blocks(.init(variant: .calm))
    let calmQueue = try await queue(calm, calmSource)
    #expect(isCalm(calm) && calmQueue.isEmpty)
    #expect(try await calmSource.alertEvents(status: "firing", timeRange: nil, limit: 100, before: nil, groupID: nil, platform: nil).isEmpty)
    let (limited, _) = try await blocks(.init(variant: .calmLimited))
    let summary = try #require(limited.availability.value)
    #expect(isCalm(limited) && HomePresentation.hasLimitedAccounts(summary) && HomePresentation.limitedItem(summary, now: base) != nil)
    let (closed, _) = try await blocks(.init(variant: .calm, opsDisabled: true))
    #expect(isCalm(closed) && closed.alerts == .disabled(reason: "OPS_DISABLED"))
    let ranking = try await FixtureLiveOpsSource(options: .init(variant: .calmLimited), base: base).accountsRanking(limit: 4, timezone: zone)
    #expect(HomePresentation.rankingRows(ranking).count == 2)
}

@Test func anthropicFiringEventExistsForAccountTab() async throws {
    let source = FixtureLiveOpsSource(options: .init(), base: base)
    let firing = try await source.alertEvents(status: "firing", timeRange: nil, limit: 100, before: nil, groupID: nil, platform: nil)
    #expect(firing.map(\.id) == [LiveOpsFixtureIDs.alertA, LiveOpsFixtureIDs.anthropicFiringEventID])
    let event = try #require(firing.first { $0.id == LiveOpsFixtures.anthropicFiringEventID })
    #expect(event.isFiring && event.platform == "anthropic" && event.silence?.id == 501 && event.severity == "P2")
    #expect(try await source.alertEvent(id: LiveOpsFixtures.anthropicFiringEventID) == event)
    var missing: APIError?
    do { _ = try await source.alertEvent(id: 999) } catch { missing = error as? APIError }
    #expect(missing?.statusCode == 404 && missing?.reason == "OPS_ALERT_EVENT_NOT_FOUND")
    let all = try await source.alertEvents(status: nil, timeRange: "24h", limit: 50, before: nil, groupID: nil, platform: nil)
    #expect(all.map(\.id) == [41, 40, 37, 35] && all.filter { !$0.isFiring }.map(\.status) == ["resolved", AlertEvent.manualResolved])
    let older = try await source.alertEvents(status: nil, timeRange: "24h", limit: 50, before: all[1].cursor, groupID: nil, platform: nil)
    #expect(older.map(\.id) == [37, 35])
    #expect(try await source.alertEventCounts() == AlertCounts(firing: 2, bySeverity: ["P1": 1, "P2": 1]))
}

@Test func optionsParseLaunchArguments() {
    typealias Options = LiveOpsFixtures.Options
    #expect(Options(arguments: []) == Options() && Options() == Options(variant: .allOK, opsDisabled: false))
    #expect(Options(arguments: ["-ui-home-availability-error"]).variant == .availabilityError)
    #expect(Options(arguments: ["-ui-home-availability-error", "-ui-home-hourly-timeout"]).variant == .hourlyTimeout)
    #expect(Options(arguments: ["-ui-home-hourly-timeout", "-ui-home-calm"]).variant == .calm)
    #expect(Options(arguments: ["-ui-home-calm", "-ui-home-calm-limited"]).variant == .calmLimited)
    #expect(Options(arguments: ["-ui-ops-disabled", "-ui-home-calm"]) == Options(variant: .calm, opsDisabled: true))
    #expect(Options(arguments: ["-ui-ops-disabled"]) == Options(opsDisabled: true))
}

@MainActor @Test func storeOverFixtureSourceShowsTheDemoSite() async {
    let source = FixtureLiveOpsSource(options: .init(), base: base)
    let harness = LiveOpsHarness(site: liveOpsSite(Capability.allCases))
    let store = LiveOpsStore(generation: UUID(), source: source, site: { harness.site }, isCurrent: { true }, errorBadge: { harness.badge },
                             serverNow: { base })
    await store.refreshHome(noCache: false)
    await store.refreshFiringAlerts()
    #expect(store.structuredErrors.map(\.id) == [LiveOpsFixtureIDs.errorAccount] && harness.badge.errorCount == 1)
    #expect(store.firingAlerts(platform: "Anthropic").map(\.id) == [LiveOpsFixtures.anthropicFiringEventID])
    #expect(store.todaySLA == 0.992 && !store.opsDisabled && store.alertCounts?.firing == 2)
}
