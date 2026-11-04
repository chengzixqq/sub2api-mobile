import Foundation
import Testing
@testable import NativeSessionSupport

@Test func onlyBackgroundSuspendsAndOnlyActiveResumes() {
    var lifecycle = SessionLifecycle()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(lifecycle.transition(to: .active, now: now, lastProbe: now) == .none)
    #expect(lifecycle.transition(to: .inactive, now: now, lastProbe: now) == .none)
    #expect(!lifecycle.isSuspended)
    #expect(lifecycle.transition(to: .background, now: now, lastProbe: now) == .suspend)
    #expect(lifecycle.transition(to: .background, now: now, lastProbe: now) == .none)
    #expect(lifecycle.transition(to: .inactive, now: now, lastProbe: now) == .none)
    #expect(lifecycle.isSuspended); #expect(lifecycle.foregroundRevision == 0)
    #expect(lifecycle.transition(to: .active, now: now, lastProbe: now) == .resume(reprobe: false))
    #expect(!lifecycle.isSuspended); #expect(lifecycle.foregroundRevision == 1)
    #expect(lifecycle.transition(to: .active, now: now, lastProbe: now) == .none)
    #expect(lifecycle.foregroundRevision == 1)
}

@Test(arguments: [(299.0, false), (300.0, false), (301.0, true)])
func returningAfterFiveMinutesProbesAgain(elapsed: TimeInterval, reprobe: Bool) {
    var lifecycle = SessionLifecycle()
    let probed = Date(timeIntervalSince1970: 1_800_000_000)
    _ = lifecycle.transition(to: .background, now: probed, lastProbe: probed)
    #expect(lifecycle.transition(to: .active, now: probed.addingTimeInterval(elapsed), lastProbe: probed) == .resume(reprobe: reprobe))
}

@Test func withoutAConnectedSiteNothingIsProbed() {
    var lifecycle = SessionLifecycle()
    let now = Date()
    _ = lifecycle.transition(to: .background, now: now, lastProbe: nil)
    #expect(lifecycle.transition(to: .active, now: now.addingTimeInterval(3_600), lastProbe: nil) == .resume(reprobe: false))
}
