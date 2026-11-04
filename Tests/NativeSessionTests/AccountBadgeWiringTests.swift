import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 20 §1.6, X16 (S2-23): LiveOpsStore's availability and the account tab's own 60-second read write one AccountErrorBadge, in
// device time, so the tab does not read again within a minute of the home page.

@MainActor private final class BadgeFetches {
    var calls = 0
    var count = 5
}

@MainActor @Test func liveOpsHomeWritesSharedBadgeInDeviceTime() async throws {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply(availability: .ok(errorSummary([4, 7, 9]))) }))
    let skewedServer = Date().addingTimeInterval(3_600)
    let harness = LiveOpsHarness(source, serverNow: skewedServer)
    let before = Date()
    await harness.store.refreshHome(noCache: false)
    #expect(harness.badge.errorCount == 3)
    let written = try #require(harness.badge.updatedAt)
    #expect(written >= before && written <= Date())
}

@MainActor @Test func refresherSkipsFetchWithinSixtySecondsAfterLiveOps() async throws {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply(availability: .ok(errorSummary([4, 7, 9]))) }))
    let harness = LiveOpsHarness(source)
    await harness.store.refreshHome(noCache: false)
    let written = try #require(harness.badge.updatedAt)
    let fetches = BadgeFetches()
    func refresher(at now: Date) -> AccountBadgeRefresher {
        AccountBadgeRefresher(badge: harness.badge, isActive: { true }, fetch: { fetches.calls += 1; return fetches.count }, now: { now })
    }
    await refresher(at: written.addingTimeInterval(30)).refreshIfNeeded()
    #expect(fetches.calls == 0 && harness.badge.errorCount == 3)
    await refresher(at: written.addingTimeInterval(61)).refreshIfNeeded()
    #expect(fetches.calls == 1 && harness.badge.errorCount == 5)
    // A late reply read before the newest one is dropped.
    harness.badge.update(errorCount: 2, at: written.addingTimeInterval(40))
    #expect(harness.badge.errorCount == 5)
}
