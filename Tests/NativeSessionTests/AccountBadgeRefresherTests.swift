import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor private final class Probe {
    var now = t0
    var active = true
    var calls = 0
    var results: [Result<Int, any Error>] = []
    var sleeps: [Duration] = []
    let sleepsBeforeCancel = 1

    func refresher(for badge: AccountErrorBadge) -> AccountBadgeRefresher {
        AccountBadgeRefresher(badge: badge, isActive: { self.active }, fetch: {
            self.calls += 1
            return try (self.results.isEmpty ? .success(0) : self.results.removeFirst()).get()
        }, now: { self.now }, sleep: { duration in
            self.sleeps.append(duration)
            if self.sleeps.count > self.sleepsBeforeCancel { throw CancellationError() }
            self.now = self.now.addingTimeInterval(TimeInterval(duration.components.seconds))
        })
    }
}

@MainActor @Test func refreshesStaleBadgeWhenActive() async {
    let probe = Probe(), badge = AccountErrorBadge()
    probe.results = [.success(3)]
    await probe.refresher(for: badge).refreshIfNeeded()
    #expect(probe.calls == 1 && badge.errorCount == 3 && badge.updatedAt == t0)
}

@MainActor @Test func skipsWithinSixtySeconds() async {
    let probe = Probe(), badge = AccountErrorBadge()
    badge.update(errorCount: 1, at: t0)
    let refresher = probe.refresher(for: badge)
    probe.now = t0.addingTimeInterval(30)
    await refresher.refreshIfNeeded()
    #expect(probe.calls == 0 && badge.errorCount == 1)
    probe.now = t0.addingTimeInterval(61)
    probe.results = [.success(2)]
    await refresher.refreshIfNeeded()
    #expect(probe.calls == 1 && badge.errorCount == 2)
}

@MainActor @Test func skipsWhileSuspended() async {
    let probe = Probe(), badge = AccountErrorBadge()
    probe.active = false
    await probe.refresher(for: badge).refreshIfNeeded()
    #expect(probe.calls == 0 && badge.errorCount == 0 && badge.updatedAt == nil)
}

@MainActor @Test func keepsPreviousCountOnFailure() async {
    let probe = Probe(), badge = AccountErrorBadge()
    badge.update(errorCount: 2, at: t0)
    probe.now = t0.addingTimeInterval(120)
    probe.results = [.failure(APIError.server(status: 502, reason: nil)), .success(5)]
    let refresher = probe.refresher(for: badge)
    await refresher.refreshIfNeeded()
    #expect(probe.calls == 1 && badge.errorCount == 2 && badge.updatedAt == t0)
    await refresher.refreshIfNeeded()
    #expect(probe.calls == 2 && badge.errorCount == 5)
}

@MainActor @Test func runRefreshesImmediatelyThenEverySixtySecondsUntilCancelled() async {
    let probe = Probe(), badge = AccountErrorBadge()
    probe.results = [.success(1), .success(4)]
    let refresher = probe.refresher(for: badge)
    // The injected sleep moves the clock by the interval, so the second round is due; the second sleep is cancelled.
    await refresher.run()
    #expect(probe.sleeps == [.seconds(60), .seconds(60)])
    #expect(probe.calls == 2 && badge.errorCount == 4 && badge.updatedAt == t0.addingTimeInterval(60))
    #expect(AccountBadgeRefresher.interval == .seconds(60))
}
