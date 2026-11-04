import Foundation
import Testing
@testable import Sub2Core

// S4D2b-07: the whole-number shares of the analytics tiles (S4-17…S4-19), one format for all of them.

@Test(arguments: [(0.5404, "54%"), (0.6, "60%"), (0.995, "100%"), (0.0049, "0%"), (0, "0%"), (1, "100%")])
func wholePercentRoundsARatioToAWholePercentage(ratio: Double, expected: String) {
    #expect(DisplayFormat.wholePercent(ratio) == expected)
}

@Test(arguments: [nil, Double.nan, Double.infinity])
func wholePercentOfNothingIsMissing(ratio: Double?) {
    #expect(DisplayFormat.wholePercent(ratio) == "—")
}
