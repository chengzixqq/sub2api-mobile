import Foundation

/// `admin/dashboard/trend` points with the zone their offset-less buckets belong to (00 §6.4).
public struct DashboardTrendReply: Sendable {
    public let points: [TrendPoint]
    public let timeZone: TimeZone
    public init(points: [TrendPoint], timeZone: TimeZone) { self.points = points; self.timeZone = timeZone }
}
