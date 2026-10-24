import Foundation

public enum DashboardTrendMetric: String, CaseIterable, Identifiable, Sendable {
    case actualCost, requests, tokens, performance

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .actualCost: "实际消费"
        case .requests: "请求数"
        case .tokens: "Tokens"
        case .performance: "性能指标"
        }
    }
    public var unit: String {
        switch self {
        case .actualCost: "USD"
        case .requests: "次"
        case .tokens: "Tokens"
        case .performance: "RPM / TPM"
        }
    }

    /// Consistent labels for chart bars, selection details, and hourly rows.
    /// Formatting never changes the original amount stored in the point.
    public func displayValue(_ point: TrendPoint) -> String {
        switch self {
        case .actualCost: DisplayFormat.money(point.actualCost)
        case .requests: DisplayFormat.grouped(point.requests)
        case .tokens: DisplayFormat.compact(point.totalTokens)
        case .performance: DisplayFormat.missing
        }
    }

    /// Y-axis ticks: low-traffic ticks such as 0.5 / 1 / 1.5 keep a decimal instead of rounding into duplicate labels.
    public func axisLabel(_ value: Double) -> String {
        switch self {
        case .actualCost: DisplayFormat.money(DisplayFormat.decimalValue(value))
        case .requests, .tokens, .performance:
            abs(value) >= 1_000 ? DisplayFormat.compact(value) : DisplayFormat.decimal(value, maxFractionDigits: 1)
        }
    }

    /// Raw values for data inspection and precision regression tests. Visible
    /// trend labels use displayValue instead of exposing every Decimal digit.
    public func exactValue(_ point: TrendPoint) -> String {
        switch self {
        case .actualCost:
            guard let amount = point.actualCost, !amount.isNaN else { return DisplayFormat.missing }
            return "$" + NSDecimalNumber(decimal: amount).stringValue
        case .requests: return String(point.requests)
        case .tokens: return String(point.totalTokens)
        case .performance: return DisplayFormat.missing
        }
    }

    /// Chart coordinates are approximate; use displayValue for visible labels.
    public func plotValue(_ point: TrendPoint) -> Double? {
        let value: Double
        switch self {
        case .actualCost:
            guard let amount = point.actualCost, !amount.isNaN else { return nil }
            value = NSDecimalNumber(decimal: amount).doubleValue
        case .requests: value = Double(point.requests)
        case .tokens: value = Double(point.totalTokens)
        case .performance: return nil
        }
        return value.isFinite ? value : nil
    }
}

public struct DashboardTrendSample: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let point: TrendPoint
}

public struct DashboardTrendSeries: Sendable {
    public let samples: [DashboardTrendSample]
    public let invalidDateCount: Int
    public let duplicateCount: Int
    public let isHourly: Bool
    /// The zone the buckets were read in; axis labels and the chart calendar use it too.
    public let timeZone: TimeZone
    /// Tables read newest first; the chart keeps chronological X coordinates.
    public var newestFirst: [DashboardTrendSample] { Array(samples.reversed()) }
}

/// `admin/dashboard/trend` points with the zone their offset-less buckets belong to (00 §6.4).
public struct DashboardTrendReply: Sendable {
    public let points: [TrendPoint]
    public let timeZone: TimeZone
    public init(points: [TrendPoint], timeZone: TimeZone) { self.points = points; self.timeZone = timeZone }
}

public enum DashboardTrend {
    public static func series(_ points: [TrendPoint], timeZone: TimeZone) -> DashboardTrendSeries {
        var buckets = [Date: DashboardTrendSample]()
        var invalidDateCount = 0
        var duplicateCount = 0
        for point in points {
            guard let date = DashboardPresentation.trendDate(point.date, timeZone: timeZone) else {
                invalidDateCount += 1
                continue
            }
            // The endpoint already aggregates each bucket. Keep the last copy
            // of a repeated bucket instead of adding the same consumption twice.
            if buckets.updateValue(DashboardTrendSample(date: date, point: point), forKey: date) != nil {
                duplicateCount += 1
            }
        }
        let samples = buckets.values.sorted { $0.date < $1.date }
        return DashboardTrendSeries(samples: samples, invalidDateCount: invalidDateCount, duplicateCount: duplicateCount,
                                    isHourly: samples.contains { $0.point.date.count == 16 }, timeZone: timeZone)
    }

    public static func clampedZoom(_ value: Double, maximum: Double = 8) -> Double {
        guard value.isFinite else { return 1 }
        let upperBound = maximum.isFinite ? max(1, maximum) : 8
        return min(upperBound, max(1, value))
    }
}
