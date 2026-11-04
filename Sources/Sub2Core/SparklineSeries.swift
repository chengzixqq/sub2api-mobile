import Foundation

/// A small line without axes (10 §4.3): a missing value breaks it, so the values split into runs of two or more points and
/// points standing alone; the height leaves some room above the highest value, or is fixed (S1-14's CPU / memory, 0–100).
public struct SparklineSeries: Sendable, Equatable {
    public struct Point: Sendable, Equatable, Identifiable {
        /// The position in the input, missing values counted.
        public let index: Int
        public let value: Double
        public var id: Int { index }
        public init(index: Int, value: Double) { self.index = index; self.value = value }
    }

    /// The input's length, missing values included: the width of the X axis.
    public let count: Int
    public let runs: [[Point]]
    public let isolated: [Point]
    public let upperBound: Double
    public var isEmpty: Bool { runs.isEmpty && isolated.isEmpty }

    public init(values: [Double?], fixedUpperBound: Double? = nil, headroom: Double = 1.15) {
        let pieces = Self.split(values)
        count = values.count
        runs = pieces.filter { $0.count > 1 }
        isolated = pieces.filter { $0.count == 1 }.flatMap { $0 }
        let peak = values.compactMap { $0 }.max() ?? 0
        upperBound = fixedUpperBound ?? (peak > 0 ? peak * headroom : 1)
    }

    /// The unbroken stretches of values, in order.
    private static func split(_ values: [Double?]) -> [[Point]] {
        var pieces: [[Point]] = [], current: [Point] = []
        for (index, value) in values.enumerated() {
            guard let value else {
                if !current.isEmpty { pieces.append(current); current = [] }
                continue
            }
            current.append(Point(index: index, value: value))
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
