import Foundation
import Testing
@testable import NativeSessionSupport

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor @Test func newBadgeShowsZeroAndNeedsRefresh() {
    let badge = AccountErrorBadge()
    #expect(badge.errorCount == 0 && badge.updatedAt == nil)
    #expect(badge.needsRefresh(now: t0))
}

@MainActor @Test func updateSkipsRefreshForSixtySeconds() {
    let badge = AccountErrorBadge()
    badge.update(errorCount: 3, at: t0)
    #expect(badge.errorCount == 3 && badge.updatedAt == t0)
    #expect(!badge.needsRefresh(now: t0.addingTimeInterval(59)))
    #expect(badge.needsRefresh(now: t0.addingTimeInterval(60)))
    #expect(AccountErrorBadge.refreshInterval == 60)
}

/// The list and LiveOpsStore both write it; a result sampled before the shown one arrives late and is dropped.
@MainActor @Test func olderResultDoesNotReplaceNewerCount() {
    let badge = AccountErrorBadge()
    badge.update(errorCount: 5, at: t0.addingTimeInterval(10))
    badge.update(errorCount: 3, at: t0)
    #expect(badge.errorCount == 5 && badge.updatedAt == t0.addingTimeInterval(10))
    badge.update(errorCount: 0, at: t0.addingTimeInterval(10))
    #expect(badge.errorCount == 0)
}

@MainActor @Test func negativeCountAndClockGoingBackwards() {
    let badge = AccountErrorBadge()
    badge.update(errorCount: -1, at: t0)
    #expect(badge.errorCount == 0)
    #expect(badge.needsRefresh(now: t0.addingTimeInterval(-1)))
    // An hour back is the device clock moving, not a late reply: the new count is taken.
    badge.update(errorCount: 4, at: t0.addingTimeInterval(-3_600))
    #expect(badge.errorCount == 4 && badge.updatedAt == t0.addingTimeInterval(-3_600))
}
