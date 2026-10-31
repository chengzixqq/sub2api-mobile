import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-16: 监控 · 告警's fixture switches (LiveOpsFixtures+Alerts.swift).

/// 16:00 in Shanghai, so #35 (yesterday 21:52) is within the last day too.
private let base = Date(timeIntervalSince1970: 1_800_000_000)

/// `-ui-alerts-history`: 60 more ended events of the last day; paging by the last event's cursor finds every one once.
@Test func historyPagesByCursorWithoutGapsOrDuplicates() async throws {
    let source = FixtureLiveOpsSource(options: .init(arguments: [AlertsFixtureOptions.historyArgument]), base: base)
    var pages: [[AlertEvent]] = []
    var before: AlertEventCursor?
    while pages.count < 5 {
        let page = try await source.alertEvents(status: nil, timeRange: "24h", limit: 50, before: before, groupID: nil, platform: nil)
        pages.append(page)
        before = page.last?.cursor
        if page.count < 50 { break }
    }
    let ids = pages.flatMap { $0 }.map(\.id)
    #expect(pages.map(\.count) == [50, 14] && Set(ids).count == ids.count)
    #expect(Set(ids) == Set([41, 40, 37, 35] + Array(LiveOpsFixtures.historyEventIDs)))
    #expect(pages.last?.contains { $0.id == LiveOpsFixtures.historyEventIDs.upperBound } == true)
    #expect(pages[0] == LiveOpsFixtures.newestFirst(pages[0]))
    let history = await source.events.filter { LiveOpsFixtures.historyEventIDs.contains($0.id) }
    #expect(history.count == 60 && history.allSatisfy { event in !event.isFiring && event.firedAt.map { base.timeIntervalSince($0) < 86_400 } == true })
    #expect(Set(history.map(\.status)) == ["resolved", AlertEvent.manualResolved])
    #expect(history.filter { $0.status == AlertEvent.manualResolved }.allSatisfy { $0.resolvedByUserName == "admin" })
    let plain = FixtureLiveOpsSource(options: .init(), base: base)
    #expect(await plain.events.allSatisfy { !LiveOpsFixtures.historyEventIDs.contains($0.id) })
}

/// `-ui-alerts-list-fails`: only the lists answer 503; the counts and one event still read.
@Test func listFailsArgumentOnlyFailsLists() async throws {
    let source = FixtureLiveOpsSource(options: .init(arguments: [AlertsFixtureOptions.listFailsArgument]), base: base)
    var failure: APIError?
    do { _ = try await source.alertEvents(status: nil, timeRange: "24h", limit: 50, before: nil, groupID: nil, platform: nil) } catch {
        failure = error as? APIError
    }
    #expect(failure?.statusCode == 503)
    #expect(try await source.alertEventCounts().firing == 2)
    #expect(try await source.alertEvent(id: LiveOpsFixtureIDs.alertA).isFiring)
}

@Test func alertsOptionsParseArguments() {
    #expect(AlertsFixtureOptions(arguments: []) == AlertsFixtureOptions())
    #expect(AlertsFixtureOptions(arguments: ["-ui-alerts-history"]) == AlertsFixtureOptions(history: true))
    #expect(AlertsFixtureOptions(arguments: ["-ui-alerts-list-fails"]) == AlertsFixtureOptions(listFails: true))
    #expect(LiveOpsFixtures.Options(arguments: ["-ui-alerts-history", "-ui-alerts-list-fails"]).alerts
            == AlertsFixtureOptions(history: true, listFails: true))
    #expect(LiveOpsFixtures.Options(arguments: ["-ui-home-calm"]).alerts == AlertsFixtureOptions())
}
