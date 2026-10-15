import Foundation

public enum DashboardTrendMetric: String, CaseIterable, Identifiable, Sendable {
    case actualCost, requests, tokens

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .actualCost: "实际消费"
        case .requests: "请求数"
        case .tokens: "Tokens"
        }
    }
    public var unit: String {
        switch self {
        case .actualCost: "USD"
        case .requests: "次"
        case .tokens: "Tokens"
        }
    }

    /// Complete values for selection details. Money never passes through Double
    /// or the compact overview formatter, and missing actual spend stays missing.
    public func exactValue(_ point: TrendPoint) -> String {
        switch self {
        case .actualCost:
            guard let amount = point.actualCost, !amount.isNaN else { return "不可用" }
            return "$" + NSDecimalNumber(decimal: amount).stringValue
        case .requests: return String(point.requests)
        case .tokens: return String(point.totalTokens)
        }
    }

    /// Chart coordinates are approximate; use exactValue for displayed details.
    public func plotValue(_ point: TrendPoint) -> Double? {
        let value: Double
        switch self {
        case .actualCost:
            guard let amount = point.actualCost, !amount.isNaN else { return nil }
            value = NSDecimalNumber(decimal: amount).doubleValue
        case .requests: value = Double(point.requests)
        case .tokens: value = Double(point.totalTokens)
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
}

public enum DashboardTrend {
    public static func series(_ points: [TrendPoint], timeZone: TimeZone = .current) -> DashboardTrendSeries {
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
        return DashboardTrendSeries(samples: samples, invalidDateCount: invalidDateCount,
                                    duplicateCount: duplicateCount, isHourly: samples.contains { $0.point.date.count == 16 })
    }

    public static func clampedZoom(_ value: Double, maximum: Double = 8) -> Double {
        guard value.isFinite else { return 1 }
        let upperBound = maximum.isFinite ? max(1, maximum) : 8
        return min(upperBound, max(1, value))
    }
}
