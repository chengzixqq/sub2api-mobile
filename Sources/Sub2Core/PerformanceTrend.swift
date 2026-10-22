import Foundation

public struct PerformanceTrend: Decodable, Sendable {
    public enum Bucket: String, Decodable, Sendable {
        case minute = "1m", fiveMinutes = "5m", hour = "1h"
        public var seconds: Double {
            switch self { case .minute: 60; case .fiveMinutes: 300; case .hour: 3_600 }
        }
        public var label: String {
            switch self { case .minute: "1 分钟"; case .fiveMinutes: "5 分钟"; case .hour: "1 小时" }
        }
    }
    public struct Point: Decodable, Identifiable, Sendable {
        public let date: Date
        public let requestCount: Int
        public let tokenConsumed: Int
        public var id: Date { date }
        public init(date: Date, requestCount: Int, tokenConsumed: Int) {
            self.date = date; self.requestCount = requestCount; self.tokenConsumed = tokenConsumed
        }
        enum CodingKeys: String, CodingKey {
            case date = "bucket_start", requestCount = "request_count", tokenConsumed = "token_consumed"
        }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try c.decode(String.self, forKey: .date)
            guard let date = ServerTime.parseTimestamp(raw) else {
                throw DecodingError.dataCorruptedError(forKey: .date, in: c, debugDescription: "Invalid throughput bucket_start")
            }
            self.date = date
            requestCount = try c.decode(Int.self, forKey: .requestCount)
            tokenConsumed = try c.decode(Int.self, forKey: .tokenConsumed)
            guard requestCount >= 0, tokenConsumed >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .requestCount, in: c, debugDescription: "Negative throughput count")
            }
        }
    }
    public let bucket: Bucket
    public let points: [Point]
    public init(bucket: Bucket, points: [Point]) {
        self.bucket = bucket
        // The endpoint already aggregates buckets; retain the last duplicate.
        var unique: [Date: Point] = [:]
        for point in points { unique[point.date] = point }
        self.points = unique.values.sorted { $0.date < $1.date }
    }
    enum CodingKeys: CodingKey { case bucket, points }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(bucket: try c.decode(Bucket.self, forKey: .bucket), points: try c.decode([Point].self, forKey: .points))
    }
    public var newestFirst: [Point] { Array(points.reversed()) }
    public func rate(_ point: Point, metric: PerformanceMetric) -> Double {
        // qps/tps are rounded by the server. Counts preserve low-volume precision.
        Double(metric == .rpm ? point.requestCount : point.tokenConsumed) * 60 / bucket.seconds
    }
}

public enum PerformanceMetric: String, CaseIterable, Identifiable, Sendable {
    case rpm = "RPM", tpm = "TPM"
    public var id: String { rawValue }
    public var label: String { self == .rpm ? "每分钟请求" : "每分钟 Tokens" }
    /// Rates, details and axis ticks share one format: RPM keeps a decimal below 10, TPM is compact (00 §6.2).
    public func format(_ value: Double) -> String { self == .rpm ? DisplayFormat.rpm(value) : DisplayFormat.compact(value) }
}
