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

@Test func capsuleEndsKeep22FromTallRows() {
    // 00 §8.1: 2026-11-03 the user moved the ends from 10 to 22; a joined end stays at the row's edge.
    #expect(RailPosition.endInset == 22)
    #expect(RailPosition.single.insets(height: 80) == .init(top: 22, bottom: 22))
    #expect(RailPosition.top.insets(height: 80) == .init(top: 22, bottom: 0))
    #expect(RailPosition.bottom.insets(height: 80) == .init(top: 0, bottom: 22))
    #expect(RailPosition.middle.insets(height: 80) == .init(top: 0, bottom: 0))
}

@Test func capsuleInShortRowGivesUpInsetToKeepSixteen() {
    // The user list's single row (56) and a 44pt batch failure: a flat 22 would leave 12 and 0.
    #expect(RailPosition.minimumLength == 16)
    #expect(RailPosition.single.insets(height: 56) == .init(top: 20, bottom: 20))
    #expect(RailPosition.single.insets(height: 44) == .init(top: 14, bottom: 14))
    #expect(RailPosition.top.insets(height: 30) == .init(top: 14, bottom: 0))
    #expect(RailPosition.bottom.insets(height: 30) == .init(top: 0, bottom: 14))
    #expect(RailPosition.middle.insets(height: 30) == .init(top: 0, bottom: 0))
}

@Test func capsuleInsetsAtTheBoundaries() {
    #expect(RailPosition.single.insets(height: 60) == .init(top: 22, bottom: 22))
    #expect(RailPosition.single.insets(height: 59) == .init(top: 21.5, bottom: 21.5))
    #expect(RailPosition.top.insets(height: 38) == .init(top: 22, bottom: 0))
    #expect(RailPosition.bottom.insets(height: 37) == .init(top: 0, bottom: 21))
    #expect(RailPosition.single.insets(height: 16) == .init(top: 0, bottom: 0))
}

@Test func capsuleFillsRowsShorterThanTheFloor() {
    for position in RailPosition.allCases {
        #expect(position.insets(height: 12) == .init(top: 0, bottom: 0))
        #expect(position.insets(height: 0) == .init(top: 0, bottom: 0))
    }
}

@Test func capsuleIsNeverShorterThanTheFloorOrItsRow() {
    for position in RailPosition.allCases {
        for height in stride(from: 0.0, through: 120, by: 0.5) {
            let insets = position.insets(height: height)
            #expect(height - insets.top - insets.bottom >= min(height, RailPosition.minimumLength))
            #expect(insets.top <= RailPosition.endInset && insets.bottom <= RailPosition.endInset)
        }
    }
}
