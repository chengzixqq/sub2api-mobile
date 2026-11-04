import Observation
import Synchronization
import Testing
@testable import NativeSessionSupport

/// Set from Observation's change handler, which may run on any thread.
private final class ChangeFlag: Sendable {
    private let value = Mutex(false)
    func set() { value.withLock { $0 = true } }
    var isSet: Bool { value.withLock { $0 } }
}

@MainActor @Test func everyUserStartsAtRevisionZero() {
    let signal = UserChangeSignal()
    #expect(signal.revisions.isEmpty && signal.balanceRevisions.isEmpty)
    #expect(signal.revision(userID: 42) == 0)
    #expect(signal.balanceRevision(userID: 42) == 0)
}

@MainActor @Test func bumpCountsUpForThatUserOnly() {
    let signal = UserChangeSignal()
    signal.bump(userID: 1)
    signal.bump(userID: 1)
    signal.bump(userID: 2)
    #expect(signal.revision(userID: 1) == 2)
    #expect(signal.revision(userID: 2) == 1)
    #expect(signal.revision(userID: 3) == 0)
    #expect(signal.revisions == [1: 2, 2: 1])
}

@MainActor @Test func bumpLeavesBalanceRevisionAlone() {
    let signal = UserChangeSignal()
    signal.bump(userID: 1)
    #expect(signal.revision(userID: 1) == 1)
    #expect(signal.balanceRevision(userID: 1) == 0)
    #expect(signal.balanceRevisions.isEmpty)
}

@MainActor @Test func bumpBalanceRaisesBothCounters() {
    let signal = UserChangeSignal()
    signal.bump(userID: 1)
    signal.bumpBalance(userID: 1)
    #expect(signal.revision(userID: 1) == 2)
    #expect(signal.balanceRevision(userID: 1) == 1)
    signal.bumpBalance(userID: 1)
    #expect(signal.revision(userID: 1) == 3)
    #expect(signal.balanceRevision(userID: 1) == 2)
}

@MainActor @Test func bothCountersAreKeptPerUser() {
    let signal = UserChangeSignal()
    signal.bumpBalance(userID: 7)
    signal.bump(userID: 8)
    #expect(signal.revision(userID: 7) == 1 && signal.balanceRevision(userID: 7) == 1)
    #expect(signal.revision(userID: 8) == 1 && signal.balanceRevision(userID: 8) == 0)
    #expect(signal.revision(userID: 9) == 0 && signal.balanceRevision(userID: 9) == 0)
    #expect(signal.balanceRevisions == [7: 1])
}

@MainActor @Test func readingARevisionIsTrackedAndBumpNotifies() {
    let signal = UserChangeSignal()
    let profile = ChangeFlag(), balance = ChangeFlag()
    withObservationTracking { _ = signal.revision(userID: 1) } onChange: { profile.set() }
    withObservationTracking { _ = signal.balanceRevision(userID: 1) } onChange: { balance.set() }
    signal.bump(userID: 1)
    #expect(profile.isSet)
    #expect(balance.isSet == false)
    signal.bumpBalance(userID: 1)
    #expect(balance.isSet)
}

@MainActor @Test func aNewSignalStartsOver() {
    // publish builds a new signal for every session, so a switch never carries the old site's counts.
    let old = UserChangeSignal()
    old.bump(userID: 1)
    old.bumpBalance(userID: 1)
    let fresh = UserChangeSignal()
    #expect(fresh.revision(userID: 1) == 0 && fresh.balanceRevision(userID: 1) == 0)
    #expect(old.revision(userID: 1) == 2)
}
