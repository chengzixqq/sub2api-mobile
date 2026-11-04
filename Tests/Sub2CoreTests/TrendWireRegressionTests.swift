import Foundation
import Testing
@testable import Sub2Core

// Uses the original public TrendPoint API so the exact test can run against
// baseline, modified, and restored sources without depending on new helpers.
private struct TrendActualCostProjection: Decodable {
    let actual_cost: Decimal?
}

@Test func trendWireRegressionPreservesActualSpendInsteadOfStandardPrice() throws {
    let input = #"{"date":"2026-10-15 08:00","requests":12,"total_tokens":9876543210,"cost":"99.99","actual_cost":"12.345678910123456789"}"#
    let point = try JSONDecoder().decode(TrendPoint.self, from: Data(input.utf8))
    let output = try JSONEncoder().encode(point)
    let projection = try JSONDecoder().decode(TrendActualCostProjection.self, from: output)
    #expect(projection.actual_cost == Decimal(string: "12.345678910123456789"))
    #expect(point.cost == Decimal(string: "99.99"))
    let actual = projection.actual_cost.map { NSDecimalNumber(decimal: $0).stringValue } ?? "unavailable"
    print("TREND_REGRESSION actual=\(actual) standard=\(NSDecimalNumber(decimal: point.cost).stringValue)")
}
