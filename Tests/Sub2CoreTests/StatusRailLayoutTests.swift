import Foundation
import Testing
@testable import Sub2Core

@Test func railJoinsAdjacentRailRowsWhateverTheirTone() {
    #expect(RailPosition.positions(drawsRail: [true, true, true]) == [.top, .middle, .bottom])
    // 00 §8.1: neighbours of different colours still form one rail.
    #expect(RailPosition.positions(of: [Tone.caution, .critical, .model], drawsRail: \.drawsRail) == [.top, .middle, .bottom])
}

@Test func railSingleRowHasRoundedEnds() {
    #expect(RailPosition.positions(drawsRail: [true]) == [.single])
    #expect(RailPosition.single.capsTop && RailPosition.single.capsBottom)
}

@Test func railBreaksAtRowsWithoutCapsule() {
    #expect(RailPosition.positions(drawsRail: [true, false, true, true, false, false, true]) == [.single, nil, .top, .bottom, nil, nil, .single])
}

@Test func railSkipsOkNeutralAndMissingTone() {
    let tones: [Tone?] = [.ok, .caution, .neutral, .critical, .critical, nil]
    #expect(RailPosition.positions(of: tones, drawsRail: { $0?.drawsRail == true }) == [nil, .single, nil, .top, .bottom, nil])
}

@Test func railEmptyListAndCapsOnlyAtSegmentEnds() {
    #expect(RailPosition.positions(drawsRail: []).isEmpty)
    #expect(RailPosition.top.capsTop && !RailPosition.top.capsBottom)
    #expect(!RailPosition.middle.capsTop && !RailPosition.middle.capsBottom)
    #expect(!RailPosition.bottom.capsTop && RailPosition.bottom.capsBottom)
}
