import Foundation
import Testing
@testable import Sub2Core

// S1-13: a small line's runs, lone points and height (10 §4.3: missing values break the line; S1-14 reuses it for CPU / memory).

private func points(_ pairs: [(Int, Double)]) -> [SparklineSeries.Point] { pairs.map { SparklineSeries.Point(index: $0.0, value: $0.1) } }

@Test func splitsRunsAtGaps() {
    let series = SparklineSeries(values: [1, 2, nil, 3, 4, 5])
    #expect(series.count == 6)
    #expect(series.runs == [points([(0, 1), (1, 2)]), points([(3, 3), (4, 4), (5, 5)])])
    #expect(series.isolated.isEmpty && !series.isEmpty)
}

@Test func singlePointsBecomeIsolated() {
    let series = SparklineSeries(values: [nil, 1, nil, 2, 3])
    #expect(series.runs == [points([(3, 2), (4, 3)])])
    #expect(series.isolated == points([(1, 1)]))
    #expect(SparklineSeries(values: [7]).isolated == points([(0, 7)]))
}

@Test func allMissingIsEmpty() {
    let missing = SparklineSeries(values: [nil, nil])
    #expect(missing.count == 2 && missing.runs.isEmpty && missing.isolated.isEmpty && missing.isEmpty)
    #expect(missing.upperBound == 1)
    #expect(SparklineSeries(values: []).count == 0)
}

@Test func upperBoundAddsHeadroomOrUsesFixed() {
    #expect(abs(SparklineSeries(values: [0.01, 0.02]).upperBound - 0.023) < 1e-12)
    #expect(SparklineSeries(values: [0, 0, nil]).upperBound == 1)
    #expect(SparklineSeries(values: [38, 61], fixedUpperBound: 100).upperBound == 100)
    #expect(SparklineSeries(values: [2], headroom: 1.5).upperBound == 3)
}
