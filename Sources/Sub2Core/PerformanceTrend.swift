import Foundation

/// `ops/dashboard/throughput-trend` (40 §1.4). Rates divide by the seconds each bucket covers inside the requested window, so
/// the partial first and last buckets keep their real level.
public struct PerformanceTrend: Sendable, Equatable {
    public typealias Bucket = OpsBucket
    /// Last month plus a daylight-saving hour (S4D1-10); the server itself has no limit.
    public static let maximumSpan: TimeInterval = 31 * 86_400 + 3_600

    public struct Point: Decodable, Identifiable, Sendable, Equatable {
        public let date: Date
        public let requestCount: Int
        public let tokenConsumed: Int
        /// Failovers in this bucket (40 §2.2 平均账号切换).
        public let switchCount: Int
        public var id: Date { date }
        public init(date: Date, requestCount: Int, tokenConsumed: Int, switchCount: Int = 0) {
            self.date = date; self.requestCount = requestCount; self.tokenConsumed = tokenConsumed; self.switchCount = switchCount
        }
        enum CodingKeys: String, CodingKey {
            case date = "bucket_start", requestCount = "request_count", tokenConsumed = "token_consumed", switchCount = "switch_count"
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
            switchCount = try c.decodeIfPresent(Int.self, forKey: .switchCount) ?? 0
            guard requestCount >= 0, tokenConsumed >= 0, switchCount >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .requestCount, in: c, debugDescription: "Negative throughput count")
            }
        }
    }

    /// The wire body; a missing or unknown `bucket` is derived from the window instead of failing.
    struct Reply: Decodable, Sendable {
        let bucket: String?
        let points: [Point]
        enum CodingKeys: CodingKey { case bucket, points }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            bucket = try? c.decodeIfPresent(String.self, forKey: .bucket)
            points = try c.decodeIfPresent([Point].self, forKey: .points) ?? []
        }
    }

    public let bucket: Bucket
    /// The requested window; buckets are cut to it.
    public let windowStart: Date
    public let windowEnd: Date
    /// Unique and oldest first; points without coverage inside the window are dropped.
    public let points: [Point]

    public init(bucket: Bucket, windowStart: Date, windowEnd: Date, points: [Point]) {
        self.bucket = bucket; self.windowStart = windowStart; self.windowEnd = windowEnd
        // The endpoint already aggregates buckets; retain the last duplicate.
        var unique: [Date: Point] = [:]
        for point in points { unique[point.date] = point }
        self.points = unique.values
            .filter { Self.coverage(of: $0.date, bucket: bucket, start: windowStart, end: windowEnd) > 0 }
            .sorted { $0.date < $1.date }
    }
    init(reply: Reply, windowStart: Date, windowEnd: Date) {
        self.init(bucket: .resolve(reply.bucket, window: windowEnd.timeIntervalSince(windowStart)), windowStart: windowStart,
                  windowEnd: windowEnd, points: reply.points)
    }

    public var newestFirst: [Point] { Array(points.reversed()) }
    /// min(bucket start + bucket seconds, window end) − max(bucket start, window start).
    public func coveredSeconds(_ point: Point) -> TimeInterval {
        Self.coverage(of: point.date, bucket: bucket, start: windowStart, end: windowEnd)
    }
    /// qps/tps are rounded by the server. Counts preserve low-volume precision.
    public func rate(_ point: Point, metric: PerformanceMetric) -> Double {
        Double(metric.amount(point)) * 60 / coveredSeconds(point)
    }
    public func peak(_ metric: PerformanceMetric) -> Double? { points.map { rate($0, metric: metric) }.max() }
    /// Σ amounts × 60 ÷ Σ covered seconds, not the mean of the bucket rates.
    public func average(_ metric: PerformanceMetric) -> Double? {
        guard !points.isEmpty else { return nil }
        let amount = points.reduce(0) { $0 + metric.amount($1) }
        let seconds = points.reduce(0) { $0 + coveredSeconds($1) }
        return Double(amount) * 60 / seconds
    }

    private static func coverage(of date: Date, bucket: Bucket, start: Date, end: Date) -> TimeInterval {
        min(date.addingTimeInterval(bucket.seconds), end).timeIntervalSince(max(date, start))
    }
}

public enum PerformanceMetric: String, CaseIterable, Identifiable, Sendable {
    case rpm = "RPM", tpm = "TPM"
    public var id: String { rawValue }
    public var label: String { self == .rpm ? "每分钟请求" : "每分钟 Tokens" }
    /// Rates, details and the selected value: RPM keeps a decimal below 10, TPM is compact (00 §6.2).
    public func format(_ value: Double) -> String { self == .rpm ? DisplayFormat.rpm(value) : DisplayFormat.compact(value) }
    /// Y-axis ticks: below 1,000 two decimals at most, so a quiet site's 0.05 steps never share a label (as DashboardTrendMetric.axisLabel).
    public func axisLabel(_ value: Double) -> String {
        abs(value) >= 1_000 ? format(value) : DisplayFormat.decimal(value, maxFractionDigits: 2)
    }
    fileprivate func amount(_ point: PerformanceTrend.Point) -> Int { self == .rpm ? point.requestCount : point.tokenConsumed }
}

extension APIClient {
    /// 40 §1.4: no `mode`; group and model follow OpsQuery. `supportsModelFilter` has no default, so a caller cannot drop the
    /// model filter silently. A 404 `OPS_DISABLED` is thrown unchanged.
    public func dashboardPerformanceTrend(_ query: OpsQuery, supportsModelFilter: Bool) async throws -> PerformanceTrend {
        try query.validate()
        guard query.end.timeIntervalSince(query.start) <= PerformanceTrend.maximumSpan else {
            throw APIError(kind: .validation, message: "请选择 31 天以内的性能趋势范围。")
        }
        let snapshot = currentGeneration()
        let reply: PerformanceTrend.Reply = try await request("admin/ops/dashboard/throughput-trend",
                                                             query: query.queryItems(supportsModelFilter: supportsModelFilter),
                                                             timeout: RequestTimeout.aggregate)
        try check(snapshot)
        return PerformanceTrend(reply: reply, windowStart: query.start, windowEnd: query.end)
    }
}
