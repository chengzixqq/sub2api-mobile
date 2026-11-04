import Foundation

/// 10 §1.3.4 每小时实际扣费 as the overview draws it (S1-09b): yesterday's 24 hours and today's up to the current hour, a missing
/// hour as 0, on the server's clock. Labels are the server's `YYYY-MM-DD HH:00` without a zone: a malformed one is dropped and a
/// repeated one (the hour a clock goes back) adds up. Amounts stay Decimal; `plotValue` is only for drawing.
public struct HomeHourlySeries: Sendable, Equatable {
    public struct Bar: Sendable, Equatable, Identifiable {
        public let hour: Int
        public let actualCost: Decimal
        /// Today's last bar, drawn darker.
        public let isCurrent: Bool
        public var id: Int { hour }
        public var plotValue: Double { NSDecimalNumber(decimal: actualCost).doubleValue }
    }
    public struct AxisLabel: Sendable, Equatable, Identifiable {
        public let hour: Int
        /// “6时” or “现在”.
        public let text: String
        public let isNow: Bool
        public var id: Int { isNow ? -1 : hour }
    }

    public static let fixedTicks = [0, 6, 12, 18]
    /// 10 §1.3.4: the chart's own failure row; the three cells under it stay.
    public static let failedText = "每小时数据加载失败"
    public static let accessibilityLabel = "每小时实际扣费，今天与昨天对比"
    static let headroom = 1.12
    private static let labelLength = "YYYY-MM-DD HH:00".count

    public let today: [Bar]
    public let yesterday: [Bar]
    /// The server's hour now, or the latest hour today already reported when the phone's clock is behind.
    public let currentHour: Int

    /// `timeZone` is the server's (00 §6.3), the one home was asked with; `now` its corrected clock.
    public init(_ hourly: HomeHourly, now: Date, timeZone: TimeZone) {
        let calendar = Self.calendar(timeZone)
        let todayCosts = Self.costsByHour(hourly.today, calendar: calendar)
        let yesterdayCosts = Self.costsByHour(hourly.yesterday, calendar: calendar)
        let current = max(calendar.component(.hour, from: now), todayCosts.keys.max() ?? 0)
        currentHour = current
        today = (0...current).map { Bar(hour: $0, actualCost: todayCosts[$0] ?? 0, isCurrent: $0 == current) }
        yesterday = (0..<24).map { Bar(hour: $0, actualCost: yesterdayCosts[$0] ?? 0, isCurrent: false) }
    }

    /// The highest bar or point × 1.12, leaving room above it; 1 when everything is 0.
    public var upperBound: Double {
        let top = (today + yesterday).map(\.plotValue).max() ?? 0
        return top > 0 ? top * Self.headroom : 1
    }

    /// 0时 6时 12时 18时 and 现在 (10 §1.3.4). A fixed label starts at its hour and runs about two hours to the right, 现在 is
    /// centred on its bar, so a fixed hour from one hour after 现在 to two hours before it is left out and the two never overlap.
    public var axisLabels: [AxisLabel] {
        Self.fixedTicks.filter { !(-1...2).contains(currentHour - $0) }.map { AxisLabel(hour: $0, text: "\($0)时", isNow: false) }
            + [AxisLabel(hour: currentHour, text: "现在", isNow: true)]
    }

    private static func costsByHour(_ points: [HomeHourlyPoint], calendar: Calendar) -> [Int: Decimal] {
        points.reduce(into: [:]) { costs, point in
            guard point.date.count == labelLength,
                  let date = DashboardPresentation.trendDate(point.date, timeZone: calendar.timeZone) else { return }
            costs[calendar.component(.hour, from: date), default: 0] += point.actualCost
        }
    }
    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
