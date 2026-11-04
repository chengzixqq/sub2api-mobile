import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-13: the `-ui-testing` monitor overview reads (LiveOpsFixtures+Monitor.swift).

private func utc(_ text: String) -> Date { ServerTime.parseTimestamp(text)! }
private let start = utc("2026-10-16T01:15:00Z"), end = utc("2026-10-16T02:00:00Z")
private func refused(_ call: () async throws -> Void) async -> APIError? {
    do { try await call(); return nil } catch { return error as? APIError }
}

/// Like the server: one bucket a minute from floor(start) to the minute before end, so whole minutes give 45 and a half
/// minute 46; five empty minutes break the line once.
@Test func snapshotFixtureHasFortyFiveBucketsAndOneGap() {
    let snapshot = LiveOpsFixtures.opsSnapshotV2(start: start, end: end)
    #expect(snapshot.throughputPoints.count == 45 && snapshot.errorPoints.count == 45)
    #expect(snapshot.throughputPoints.map(\.bucketStart) == (0..<45).map { start.addingTimeInterval(Double($0) * 60) })
    #expect(snapshot.errorPoints.map(\.bucketStart) == snapshot.throughputPoints.map(\.bucketStart))
    #expect(snapshot.windowStart == start && snapshot.windowEnd == end)
    let rates = MonitorPresentation.errorRateSeries(snapshot).map(\.rate)
    #expect(rates.count == 9)
    #expect(rates.filter { $0 == nil }.count == 1 && rates[4] == nil)
    #expect(rates.compactMap { $0 }.allSatisfy { (0.008...0.017).contains($0) })
    let shifted = LiveOpsFixtures.opsSnapshotV2(start: start.addingTimeInterval(30), end: end.addingTimeInterval(30))
    #expect(shifted.throughputPoints.count == 46)
}

@Test func monitorFailureArgumentsParse() {
    #expect(MonitorFixtureOptions(arguments: ["-ui-monitor-overview-fails"]) == MonitorFixtureOptions(overviewFails: true))
    #expect(MonitorFixtureOptions(arguments: ["-ui-monitor-trend-fails"]) == MonitorFixtureOptions(trendFails: true))
    #expect(MonitorFixtureOptions(arguments: ["-ui-monitor-trend-fails", "-ui-monitor-overview-fails"])
            == MonitorFixtureOptions(overviewFails: true, trendFails: true))
    #expect(MonitorFixtureOptions(arguments: ["-ui-testing"]) == MonitorFixtureOptions())
    #expect(LiveOpsFixtures.Options(arguments: ["-ui-testing", "-ui-monitor-trend-fails"]).monitor == MonitorFixtureOptions(trendFails: true))
    #expect(LiveOpsFixtures.Options().monitor == MonitorFixtureOptions())
}

@Test func fixtureSourceHonoursOpsSwitchAndFailures() async throws {
    let off = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: ["-ui-ops-disabled"]))
    #expect(await refused { _ = try await off.opsSnapshotV2(start: start, end: end) } == LiveOpsFixtures.opsDisabledError)
    #expect(await refused { _ = try await off.opsOverview(timeRange: "5m") } == LiveOpsFixtures.opsDisabledError)

    let switched = FixtureLiveOpsSource(options: LiveOpsFixtures.Options())
    #expect(try await switched.opsSnapshotV2(start: start, end: end).throughputPoints.count == 45)
    _ = try await switched.setOpsMonitoring(enabled: false)
    #expect(await refused { _ = try await switched.opsSnapshotV2(start: start, end: end) } == LiveOpsFixtures.opsDisabledError)

    let overviewFails = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: ["-ui-monitor-overview-fails"]))
    #expect(await refused { _ = try await overviewFails.opsOverview(timeRange: "5m") } == FixtureLiveOpsSource.unreachableError)
    #expect(try await overviewFails.opsSnapshotV2(start: start, end: end).errorPoints.count == 45)

    let trendFails = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: ["-ui-monitor-trend-fails"]))
    #expect(await refused { _ = try await trendFails.opsSnapshotV2(start: start, end: end) } == FixtureLiveOpsSource.unreachableError)
    #expect(try await trendFails.opsOverview(timeRange: "5m").healthScore == 94)
}
