import Foundation
import Testing
@testable import NativeSessionSupport

@MainActor @Test func announcementSignalBumpCountsUp() {
    let signal = AnnouncementChangeSignal.signal(for: UUID())
    #expect(signal.revision == 0)
    signal.bump()
    signal.bump()
    #expect(signal.revision == 2)
}

@MainActor @Test func sameGenerationSharesOneAnnouncementSignal() {
    let generation = UUID()
    let first = AnnouncementChangeSignal.signal(for: generation)
    let second = AnnouncementChangeSignal.signal(for: generation)
    #expect(first === second)
    first.bump()
    #expect(second.revision == 1)
}

@MainActor @Test func newGenerationGetsAFreshSignalAndAnOldOneDoesNotReplaceIt() {
    let old = UUID(), new = UUID()
    let oldSignal = AnnouncementChangeSignal.signal(for: old)
    oldSignal.bump()
    let newSignal = AnnouncementChangeSignal.signal(for: new)
    #expect(newSignal !== oldSignal)
    #expect(newSignal.revision == 0)
    newSignal.bump()
    #expect(AnnouncementChangeSignal.signal(for: old) === oldSignal)
    #expect(AnnouncementChangeSignal.signal(for: new) === newSignal)
    #expect(newSignal.revision == 1)
}

@MainActor @Test func onlyTheLatestFourGenerationsAreKept() {
    let generations = (0..<5).map { _ in UUID() }
    let first = AnnouncementChangeSignal.signal(for: generations[0])
    let kept = generations.dropFirst().map { AnnouncementChangeSignal.signal(for: $0) }
    #expect(AnnouncementChangeSignal.signal(for: generations[4]) === kept[3])
    #expect(AnnouncementChangeSignal.signal(for: generations[1]) === kept[0])
    #expect(AnnouncementChangeSignal.signal(for: generations[0]) !== first)
}
