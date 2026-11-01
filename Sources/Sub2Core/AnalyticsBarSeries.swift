import Foundation

/// 40 §1.4 / §1.5: the money bars of 计费趋势, 利润明细 and their chart pages, one per bucket of the range, in its order. The caller
/// gives 0 for a bucket the backend left out and nil for a row whose amount is missing; a nil bar is drawn flat and read as 无数据.
public struct AnalyticsBarSeries: Equatable, Sendable {
    public struct Bar: Identifiable, Equatable, Sendable {
        public let bucket: AnalyticsBucket
        public let value: Decimal?
        /// The dotted standard line; nil draws no point.
        public let line: Decimal?
        public var id: Int { bucket.index }
        public var plotValue: Double { value.map(AnalyticsBarSeries.double) ?? 0 }
        public var plotLine: Double? { line.map(AnalyticsBarSeries.double) }
    }

    public let bars: [Bar]
    public let ticks: [AnalyticsAxisTick]
    /// “实际扣费”, “利润”: read after each bucket.
    public let metricName: String
    /// “这个范围内没有用量”: by default every value is 0 or missing; 利润明细 passes its own rule (no charge in the range).
    public let isEmpty: Bool
    /// Always holds 0, with a tenth of room past the largest bar or line point either way; 0…1 when there is nothing to draw.
    public let yDomain: ClosedRange<Double>

    /// `values` and `line` follow `range.buckets`; a shorter list reads as missing for the rest.
    public init(range: AnalyticsRange, values: [Decimal?], line: [Decimal?]? = nil, metricName: String, isEmpty: Bool? = nil) {
        bars = range.buckets.map { bucket in
            Bar(bucket: bucket, value: Self.element(values, bucket.index),
                line: line.flatMap { Self.element($0, bucket.index) })
        }
        ticks = range.axisTicks
        self.metricName = metricName
        self.isEmpty = isEmpty ?? bars.allSatisfy { ($0.value ?? 0) == 0 }
        yDomain = Self.domain(bars.flatMap { [$0.value, $0.line].compactMap { $0 } })
    }

    /// “10月16日 9:00 到 9:41，实际扣费 $229.00”; a missing amount reads 无数据.
    public func spokenLabel(_ index: Int) -> String {
        guard bars.indices.contains(index) else { return metricName }
        let bar = bars[index]
        return bar.bucket.spokenLabel + "，" + metricName + " " + DisplayFormat.spoken(DisplayFormat.money(bar.value))
    }

    /// The bucket under a continuous x (bars sit on their index): rounded and kept within the bars.
    public func bucketIndex(atX x: Double) -> Int? {
        guard !bars.isEmpty, x.isFinite else { return nil }
        return Int(min(max(x.rounded(), 0), Double(bars.count - 1)))
    }

    /// Only the selected bar is drawn darker; without a selection, the bucket still running.
    public func isEmphasized(_ index: Int, selected: Int?) -> Bool {
        guard bars.indices.contains(index) else { return false }
        if let selected, bars.indices.contains(selected) { return index == selected }
        return bars[index].bucket.isCurrent
    }

    private static let headroom = Decimal(string: "1.1")!

    private static func element(_ list: [Decimal?], _ index: Int) -> Decimal? { list.indices.contains(index) ? list[index] : nil }
    private static func domain(_ values: [Decimal]) -> ClosedRange<Double> {
        let lower = min(0, values.min() ?? 0) * headroom, upper = max(0, values.max() ?? 0) * headroom
        guard lower != upper else { return 0...1 }
        return double(lower)...double(upper)
    }
    static func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
}

/// 40 §1.5 整图点选 over one gesture (press → drag → release; `.chartXSelection` goes back to nil on release): the press selects its
/// bucket; pressing the bucket already selected and letting go without leaving it clears the selection; dragging moves it.
public struct AnalyticsChartSelection: Equatable, Sendable {
    public private(set) var selected: Int?
    /// During a gesture: whether letting go clears (it began on the selected bucket and has not left it).
    private var clearsOnRelease: Bool?

    public init(selected: Int? = nil) { self.selected = selected }

    /// `index`: the bucket under the gesture; nil when it ends.
    public func receiving(_ index: Int?) -> AnalyticsChartSelection {
        var next = self
        switch (index, clearsOnRelease) {
        case (nil, let clears):
            if clears == true { next.selected = nil }
            next.clearsOnRelease = nil
        case (let index?, nil):
            next.clearsOnRelease = index == selected
            next.selected = index
        case (let index?, _?):
            guard index != selected else { return self }
            next.selected = index
            next.clearsOnRelease = false
        }
        return next
    }
}
