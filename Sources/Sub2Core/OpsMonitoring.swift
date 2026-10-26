import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - 运维概况（10 §4.2；40 §2.7 复用）
// Every field may be missing, null or of another type: that field alone becomes nil (00 §5 rule 2).

/// `qps` / `tps` of the overview.
public struct OpsRateSummary: Decodable, Sendable, Equatable {
    public let current: Double?
    public let peak: Double?
    public let avg: Double?
    public init(current: Double? = nil, peak: Double? = nil, avg: Double? = nil) { self.current = current; self.peak = peak; self.avg = avg }
    enum CodingKeys: String, CodingKey { case current, peak, avg }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(current: c.lenientValue(.current), peak: c.lenientValue(.peak), avg: c.lenientValue(.avg))
    }
}

/// `duration` / `ttft` of the overview, in milliseconds.
public struct OpsPercentiles: Decodable, Sendable, Equatable {
    public let p50Ms, p90Ms, p95Ms, p99Ms, avgMs, maxMs: Int?
    public init(p50Ms: Int? = nil, p90Ms: Int? = nil, p95Ms: Int? = nil, p99Ms: Int? = nil, avgMs: Int? = nil, maxMs: Int? = nil) {
        self.p50Ms = p50Ms; self.p90Ms = p90Ms; self.p95Ms = p95Ms; self.p99Ms = p99Ms; self.avgMs = avgMs; self.maxMs = maxMs
    }
    enum CodingKeys: String, CodingKey { case p50Ms = "p50_ms", p90Ms = "p90_ms", p95Ms = "p95_ms", p99Ms = "p99_ms", avgMs = "avg_ms", maxMs = "max_ms" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(p50Ms: c.lenientValue(.p50Ms), p90Ms: c.lenientValue(.p90Ms), p95Ms: c.lenientValue(.p95Ms), p99Ms: c.lenientValue(.p99Ms),
                  avgMs: c.lenientValue(.avgMs), maxMs: c.lenientValue(.maxMs))
    }
}

/// The newest site-wide system snapshot; percentages are already 0–100.
public struct OpsSystemMetricsSnapshot: Decodable, Sendable, Equatable {
    public let createdAt: Date?
    public let cpuUsagePercent: Double?
    public let memoryUsagePercent: Double?
    public let memoryUsedMB: Int?
    public let memoryTotalMB: Int?
    public let concurrencyQueueDepth: Int?
    public let goroutineCount: Int?
    public let dbOK: Bool?
    public let redisOK: Bool?
    public init(createdAt: Date? = nil, cpuUsagePercent: Double? = nil, memoryUsagePercent: Double? = nil, memoryUsedMB: Int? = nil,
                memoryTotalMB: Int? = nil, concurrencyQueueDepth: Int? = nil, goroutineCount: Int? = nil, dbOK: Bool? = nil, redisOK: Bool? = nil) {
        self.createdAt = createdAt; self.cpuUsagePercent = cpuUsagePercent; self.memoryUsagePercent = memoryUsagePercent
        self.memoryUsedMB = memoryUsedMB; self.memoryTotalMB = memoryTotalMB; self.concurrencyQueueDepth = concurrencyQueueDepth
        self.goroutineCount = goroutineCount; self.dbOK = dbOK; self.redisOK = redisOK
    }
    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at", cpuUsagePercent = "cpu_usage_percent", memoryUsagePercent = "memory_usage_percent"
        case memoryUsedMB = "memory_used_mb", memoryTotalMB = "memory_total_mb", concurrencyQueueDepth = "concurrency_queue_depth"
        case goroutineCount = "goroutine_count", dbOK = "db_ok", redisOK = "redis_ok"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(createdAt: c.optionalTimestamp(.createdAt), cpuUsagePercent: c.lenientValue(.cpuUsagePercent),
                      memoryUsagePercent: c.lenientValue(.memoryUsagePercent), memoryUsedMB: c.lenientValue(.memoryUsedMB),
                      memoryTotalMB: c.lenientValue(.memoryTotalMB), concurrencyQueueDepth: c.lenientValue(.concurrencyQueueDepth),
                      goroutineCount: c.lenientValue(.goroutineCount), dbOK: c.lenientValue(.dbOK), redisOK: c.lenientValue(.redisOK))
    }
}

/// One background job. `status` is the raw value (ok / failing / stale / unknown / disabled, `ops.job_heartbeat_status`);
/// MonitorPresentation maps it. A job that never ran is not listed.
public struct OpsJobHeartbeat: Decodable, Sendable, Equatable, Identifiable {
    public let jobName: String
    public let lastRunAt: Date?
    public let lastSuccessAt: Date?
    public let lastErrorAt: Date?
    public let lastError: String?
    public let lastDurationMs: Int?
    public let status: String?
    public let expectedIntervalSeconds: Int?
    /// UTC; for the cron job (`ops_cleanup`) the next planned run.
    public let nextExpectedAt: Date?
    public var id: String { jobName }
    public init(jobName: String, lastRunAt: Date? = nil, lastSuccessAt: Date? = nil, lastErrorAt: Date? = nil, lastError: String? = nil,
                lastDurationMs: Int? = nil, status: String? = nil, expectedIntervalSeconds: Int? = nil, nextExpectedAt: Date? = nil) {
        self.jobName = jobName; self.lastRunAt = lastRunAt; self.lastSuccessAt = lastSuccessAt; self.lastErrorAt = lastErrorAt
        self.lastError = lastError; self.lastDurationMs = lastDurationMs; self.status = status
        self.expectedIntervalSeconds = expectedIntervalSeconds; self.nextExpectedAt = nextExpectedAt
    }
    enum CodingKeys: String, CodingKey {
        case status, jobName = "job_name", lastRunAt = "last_run_at", lastSuccessAt = "last_success_at", lastErrorAt = "last_error_at"
        case lastError = "last_error", lastDurationMs = "last_duration_ms", expectedIntervalSeconds = "expected_interval_seconds"
        case nextExpectedAt = "next_expected_at"
    }
    /// A missing or blank `job_name` fails this element only; the list skips it.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = c.lenientString(.jobName)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .jobName, in: c, debugDescription: "Missing job_name")
        }
        try self.init(jobName: name, lastRunAt: c.optionalTimestamp(.lastRunAt), lastSuccessAt: c.optionalTimestamp(.lastSuccessAt),
                      lastErrorAt: c.optionalTimestamp(.lastErrorAt), lastError: c.lenientValue(.lastError),
                      lastDurationMs: c.lenientValue(.lastDurationMs), status: c.lenientValue(.status),
                      expectedIntervalSeconds: c.lenientValue(.expectedIntervalSeconds), nextExpectedAt: c.optionalTimestamp(.nextExpectedAt))
    }
}

/// `GET admin/ops/dashboard/overview` (10 §4.2, 40 §2.7). Rates are 0–1 ratios.
public struct OpsOverview: Decodable, Sendable, Equatable {
    public let startTime: Date?
    public let endTime: Date?
    public let platform: String?
    public let groupID: Int?
    /// 0–100.
    public let healthScore: Int?
    public let sla: Double?
    public let errorRate: Double?
    public let upstreamErrorRate: Double?
    public let successCount, errorCountTotal, businessLimitedCount, errorCountSLA, requestCountTotal, requestCountSLA: Int?
    public let tokenConsumed: Int?
    public let upstream429Count, upstream529Count, upstreamErrorCountExcl429529: Int?
    public let qps: OpsRateSummary?
    public let tps: OpsRateSummary?
    public let duration: OpsPercentiles?
    public let ttft: OpsPercentiles?
    public let systemMetrics: OpsSystemMetricsSnapshot?
    /// Null and unreadable entries are skipped.
    public let jobHeartbeats: [OpsJobHeartbeat]

    public init(startTime: Date? = nil, endTime: Date? = nil, platform: String? = nil, groupID: Int? = nil, healthScore: Int? = nil,
                sla: Double? = nil, errorRate: Double? = nil, upstreamErrorRate: Double? = nil, successCount: Int? = nil,
                errorCountTotal: Int? = nil, businessLimitedCount: Int? = nil, errorCountSLA: Int? = nil, requestCountTotal: Int? = nil,
                requestCountSLA: Int? = nil, tokenConsumed: Int? = nil, upstream429Count: Int? = nil, upstream529Count: Int? = nil,
                upstreamErrorCountExcl429529: Int? = nil, qps: OpsRateSummary? = nil, tps: OpsRateSummary? = nil, duration: OpsPercentiles? = nil,
                ttft: OpsPercentiles? = nil, systemMetrics: OpsSystemMetricsSnapshot? = nil, jobHeartbeats: [OpsJobHeartbeat] = []) {
        self.startTime = startTime; self.endTime = endTime; self.platform = platform; self.groupID = groupID; self.healthScore = healthScore
        self.sla = sla; self.errorRate = errorRate; self.upstreamErrorRate = upstreamErrorRate; self.successCount = successCount
        self.errorCountTotal = errorCountTotal; self.businessLimitedCount = businessLimitedCount; self.errorCountSLA = errorCountSLA
        self.requestCountTotal = requestCountTotal; self.requestCountSLA = requestCountSLA; self.tokenConsumed = tokenConsumed
        self.upstream429Count = upstream429Count; self.upstream529Count = upstream529Count
        self.upstreamErrorCountExcl429529 = upstreamErrorCountExcl429529; self.qps = qps; self.tps = tps; self.duration = duration
        self.ttft = ttft; self.systemMetrics = systemMetrics; self.jobHeartbeats = jobHeartbeats
    }
    enum CodingKeys: String, CodingKey {
        case platform, sla, qps, tps, duration, ttft
        case startTime = "start_time", endTime = "end_time", groupID = "group_id", healthScore = "health_score", errorRate = "error_rate"
        case upstreamErrorRate = "upstream_error_rate", successCount = "success_count", errorCountTotal = "error_count_total"
        case businessLimitedCount = "business_limited_count", errorCountSLA = "error_count_sla", requestCountTotal = "request_count_total"
        case requestCountSLA = "request_count_sla", tokenConsumed = "token_consumed", upstream429Count = "upstream_429_count"
        case upstream529Count = "upstream_529_count", upstreamErrorCountExcl429529 = "upstream_error_count_excl_429_529"
        case systemMetrics = "system_metrics", jobHeartbeats = "job_heartbeats"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(startTime: c.optionalTimestamp(.startTime), endTime: c.optionalTimestamp(.endTime), platform: c.lenientValue(.platform),
                      groupID: c.lenientValue(.groupID), healthScore: c.lenientValue(.healthScore), sla: c.lenientValue(.sla),
                      errorRate: c.lenientValue(.errorRate), upstreamErrorRate: c.lenientValue(.upstreamErrorRate),
                      successCount: c.lenientValue(.successCount), errorCountTotal: c.lenientValue(.errorCountTotal),
                      businessLimitedCount: c.lenientValue(.businessLimitedCount), errorCountSLA: c.lenientValue(.errorCountSLA),
                      requestCountTotal: c.lenientValue(.requestCountTotal), requestCountSLA: c.lenientValue(.requestCountSLA),
                      tokenConsumed: c.lenientValue(.tokenConsumed), upstream429Count: c.lenientValue(.upstream429Count),
                      upstream529Count: c.lenientValue(.upstream529Count),
                      upstreamErrorCountExcl429529: c.lenientValue(.upstreamErrorCountExcl429529), qps: c.lenientValue(.qps),
                      tps: c.lenientValue(.tps), duration: c.lenientValue(.duration), ttft: c.lenientValue(.ttft),
                      systemMetrics: c.lenientValue(.systemMetrics), jobHeartbeats: c.lossyList(OpsJobHeartbeat.self, .jobHeartbeats))
    }

    /// The window the server answered for (10 §1.2 fallback ② divides counts by it); nil unless positive.
    public var windowSeconds: TimeInterval? {
        guard let startTime, let endTime, endTime > startTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
}

// MARK: - 错误率小折线（10 §4.3，附录 A S16）

/// `GET admin/ops/dashboard/snapshot-v2`: the overview plus the throughput and error trends of the same window.
public struct OpsSnapshotV2: Sendable, Equatable {
    public struct ThroughputPoint: Decodable, Sendable, Equatable {
        public let bucketStart: Date
        public let requestCount: Int
        public init(bucketStart: Date, requestCount: Int) { self.bucketStart = bucketStart; self.requestCount = requestCount }
        enum CodingKeys: String, CodingKey { case bucketStart = "bucket_start", requestCount = "request_count" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(bucketStart: try c.requiredTimestamp(.bucketStart), requestCount: c.lenientValue(.requestCount) ?? 0)
        }
    }
    public struct ErrorPoint: Decodable, Sendable, Equatable {
        public let bucketStart: Date
        public let errorCountSLA: Int
        public let businessLimitedCount: Int
        public init(bucketStart: Date, errorCountSLA: Int, businessLimitedCount: Int) {
            self.bucketStart = bucketStart; self.errorCountSLA = errorCountSLA; self.businessLimitedCount = businessLimitedCount
        }
        enum CodingKeys: String, CodingKey {
            case bucketStart = "bucket_start", errorCountSLA = "error_count_sla", businessLimitedCount = "business_limited_count"
        }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(bucketStart: try c.requiredTimestamp(.bucketStart), errorCountSLA: c.lenientValue(.errorCountSLA) ?? 0,
                      businessLimitedCount: c.lenientValue(.businessLimitedCount) ?? 0)
        }
    }

    public let overview: OpsOverview?
    /// Points with an unreadable `bucket_start` are skipped; missing counts are 0.
    public let throughputPoints: [ThroughputPoint]
    public let errorPoints: [ErrorPoint]
    public let generatedAt: Date?
    /// The requested window, not read from the reply.
    public let windowStart: Date
    public let windowEnd: Date

    public init(overview: OpsOverview? = nil, throughputPoints: [ThroughputPoint] = [], errorPoints: [ErrorPoint] = [], generatedAt: Date? = nil,
                windowStart: Date, windowEnd: Date) {
        self.overview = overview; self.throughputPoints = throughputPoints; self.errorPoints = errorPoints; self.generatedAt = generatedAt
        self.windowStart = windowStart; self.windowEnd = windowEnd
    }
    init(reply: Reply, windowStart: Date, windowEnd: Date) {
        self.init(overview: reply.overview, throughputPoints: reply.throughputPoints, errorPoints: reply.errorPoints,
                  generatedAt: reply.generatedAt, windowStart: windowStart, windowEnd: windowEnd)
    }

    /// The wire body. A trend that is missing or not an object reads as no points.
    struct Reply: Decodable, Sendable {
        let overview: OpsOverview?
        let throughputPoints: [ThroughputPoint]
        let errorPoints: [ErrorPoint]
        let generatedAt: Date?
        enum CodingKeys: String, CodingKey { case overview, throughputTrend = "throughput_trend", errorTrend = "error_trend", generatedAt = "generated_at" }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            overview = c.lenientValue(.overview)
            throughputPoints = (c.lenientValue(.throughputTrend) as TrendPoints<ThroughputPoint>?)?.points ?? []
            errorPoints = (c.lenientValue(.errorTrend) as TrendPoints<ErrorPoint>?)?.points ?? []
            generatedAt = try c.optionalTimestamp(.generatedAt)
        }
    }
    private struct TrendPoints<Point: Decodable>: Decodable {
        let points: [Point]
        enum CodingKeys: String, CodingKey { case points }
        init(from decoder: any Decoder) throws { points = try decoder.container(keyedBy: CodingKeys.self).lossyList(Point.self, .points) }
    }
}

// MARK: - 服务器区（10 §4.2 后四行）

/// `GET admin/ops/concurrency`. Only the platform totals are kept: group and account loads cannot be added up.
public struct OpsConcurrency: Decodable, Sendable, Equatable {
    public struct PlatformLoad: Decodable, Sendable, Equatable {
        public let currentInUse: Int
        public let maxCapacity: Int
        public let waitingInQueue: Int
        public init(currentInUse: Int = 0, maxCapacity: Int = 0, waitingInQueue: Int = 0) {
            self.currentInUse = currentInUse; self.maxCapacity = maxCapacity; self.waitingInQueue = waitingInQueue
        }
        enum CodingKeys: String, CodingKey { case currentInUse = "current_in_use", maxCapacity = "max_capacity", waitingInQueue = "waiting_in_queue" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(currentInUse: c.lenientValue(.currentInUse) ?? 0, maxCapacity: c.lenientValue(.maxCapacity) ?? 0,
                      waitingInQueue: c.lenientValue(.waitingInQueue) ?? 0)
        }
    }
    /// false when realtime monitoring is off (not the same as ops monitoring off, appendix A S7); missing reads as true.
    public let enabled: Bool
    /// Keyed by platform; null entries are dropped.
    public let platforms: [String: PlatformLoad]
    public init(enabled: Bool = true, platforms: [String: PlatformLoad] = [:]) { self.enabled = enabled; self.platforms = platforms }
    enum CodingKeys: String, CodingKey { case enabled, platforms = "platform" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let loads: [String: Lossy<PlatformLoad>]? = c.lenientValue(.platforms)
        self.init(enabled: c.lenientValue(.enabled) ?? true, platforms: (loads ?? [:]).compactMapValues(\.value))
    }
}

/// `GET admin/ops/system-metrics/history` (`ops.system_metrics_history`). Bucket averages; no data is an empty list.
public struct SystemMetricsHistory: Decodable, Sendable, Equatable {
    /// Also the locally collected point when the site has no history (MonitorPresentation.appendingLocalSample).
    public struct Point: Decodable, Sendable, Equatable, Identifiable {
        public let createdAt: Date
        /// nil breaks the line.
        public let cpuUsagePercent: Double?
        public let memoryUsagePercent: Double?
        public var id: Date { createdAt }
        public init(createdAt: Date, cpuUsagePercent: Double? = nil, memoryUsagePercent: Double? = nil) {
            self.createdAt = createdAt; self.cpuUsagePercent = cpuUsagePercent; self.memoryUsagePercent = memoryUsagePercent
        }
        enum CodingKeys: String, CodingKey { case createdAt = "created_at", cpuUsagePercent = "cpu_usage_percent", memoryUsagePercent = "memory_usage_percent" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(createdAt: try c.requiredTimestamp(.createdAt), cpuUsagePercent: c.lenientValue(.cpuUsagePercent),
                      memoryUsagePercent: c.lenientValue(.memoryUsagePercent))
        }
    }
    /// The server answers 400 INVALID_MAX_POINTS outside this range.
    public static let maxPointsRange = 1...1_440
    public let startTime: Date?
    public let endTime: Date?
    public let bucketSeconds: Int?
    public let points: [Point]
    public init(startTime: Date? = nil, endTime: Date? = nil, bucketSeconds: Int? = nil, points: [Point] = []) {
        self.startTime = startTime; self.endTime = endTime; self.bucketSeconds = bucketSeconds; self.points = points
    }
    enum CodingKeys: String, CodingKey { case points, startTime = "start_time", endTime = "end_time", bucketSeconds = "bucket_seconds" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(startTime: c.optionalTimestamp(.startTime), endTime: c.optionalTimestamp(.endTime), bucketSeconds: c.lenientValue(.bucketSeconds),
                      points: c.lossyList(Point.self, .points))
    }
}

/// `GET admin/ops/system-logs/health`. The counters are uint64 on the server; one beyond Int is nil instead of failing the reply.
public struct SystemLogHealth: Decodable, Sendable, Equatable {
    public let avgWriteDelayMs: Int?
    public let queueDepth: Int?
    public let queueCapacity: Int?
    /// "" while healthy.
    public let lastError: String?
    public let writeFailedCount: Int?
    public let droppedCount: Int?
    public init(avgWriteDelayMs: Int? = nil, queueDepth: Int? = nil, queueCapacity: Int? = nil, lastError: String? = nil,
                writeFailedCount: Int? = nil, droppedCount: Int? = nil) {
        self.avgWriteDelayMs = avgWriteDelayMs; self.queueDepth = queueDepth; self.queueCapacity = queueCapacity; self.lastError = lastError
        self.writeFailedCount = writeFailedCount; self.droppedCount = droppedCount
    }
    enum CodingKeys: String, CodingKey {
        case avgWriteDelayMs = "avg_write_delay_ms", queueDepth = "queue_depth", queueCapacity = "queue_capacity", lastError = "last_error"
        case writeFailedCount = "write_failed_count", droppedCount = "dropped_count"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(avgWriteDelayMs: c.lenientValue(.avgWriteDelayMs), queueDepth: c.lenientValue(.queueDepth), queueCapacity: c.lenientValue(.queueCapacity),
                  lastError: c.lenientValue(.lastError), writeFailedCount: c.lenientValue(.writeFailedCount), droppedCount: c.lenientValue(.droppedCount))
    }
    public var hasError: Bool { lastError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
}

/// `GET admin/ops/ingress-rejections`. `request_count_total` and `by_reason` need `ops.ingress_reject_totals`; `total` counts rows.
public struct IngressRejectList: Decodable, Sendable, Equatable {
    public struct Item: Decodable, Sendable, Equatable {
        public let requestCount: Int
        public init(requestCount: Int) { self.requestCount = requestCount }
        enum CodingKeys: String, CodingKey { case requestCount = "request_count" }
        public init(from decoder: any Decoder) throws {
            self.init(requestCount: try decoder.container(keyedBy: CodingKeys.self).lenientValue(.requestCount) ?? 0)
        }
    }
    public struct ReasonCount: Decodable, Sendable, Equatable {
        public let reason: String
        public let requestCount: Int
        public init(reason: String, requestCount: Int) { self.reason = reason; self.requestCount = requestCount }
        enum CodingKeys: String, CodingKey { case reason, requestCount = "request_count" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let reason: String = c.lenientValue(.reason) else {
                throw DecodingError.dataCorruptedError(forKey: .reason, in: c, debugDescription: "Missing reason")
            }
            self.init(reason: reason, requestCount: c.lenientValue(.requestCount) ?? 0)
        }
    }
    /// The server caps `page_size` at 200.
    public static let pageSizeRange = 1...200
    public let items: [Item]
    public let total: Int?
    public let page: Int?
    public let pageSize: Int?
    /// nil on a server without `ops.ingress_reject_totals`.
    public let requestCountTotal: Int?
    public let byReason: [ReasonCount]
    public init(items: [Item] = [], total: Int? = nil, page: Int? = nil, pageSize: Int? = nil, requestCountTotal: Int? = nil, byReason: [ReasonCount] = []) {
        self.items = items; self.total = total; self.page = page; self.pageSize = pageSize; self.requestCountTotal = requestCountTotal
        self.byReason = byReason
    }
    enum CodingKeys: String, CodingKey { case items, total, page, pageSize = "page_size", requestCountTotal = "request_count_total", byReason = "by_reason" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(items: c.lossyList(Item.self, .items), total: c.lenientValue(.total), page: c.lenientValue(.page), pageSize: c.lenientValue(.pageSize),
                  requestCountTotal: c.lenientValue(.requestCountTotal), byReason: c.lossyList(ReasonCount.self, .byReason))
    }
}

// MARK: - 运维监控开关（10 §7.2）

/// Why ops monitoring is off (`disabled_reason`, `/admin/me` `ops_monitoring_disabled_reason`). The only definition (S1D1-01).
public enum OpsDisabledReason: String, Sendable, Equatable, CaseIterable {
    case settingOff = "setting_off", configOff = "config_off", unknown
    /// nil, empty or unrecognised (after trimming) is `.unknown`.
    public init(rawReason: String?) {
        self = Self(rawValue: rawReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? .unknown
    }
}

/// `GET` / `PUT admin/ops/monitoring-status` (`ops.monitoring_status`); readable while monitoring is off.
public struct OpsMonitoringStatus: Decodable, Sendable, Equatable {
    public let configEnabled: Bool?
    public let monitoringEnabled: Bool?
    public let realtimeMonitoringEnabled: Bool?
    public let effective: Bool?
    /// The raw value; null while monitoring is on.
    public let disabledReason: String?
    public var reason: OpsDisabledReason { OpsDisabledReason(rawReason: disabledReason) }
    public init(configEnabled: Bool? = nil, monitoringEnabled: Bool? = nil, realtimeMonitoringEnabled: Bool? = nil, effective: Bool? = nil,
                disabledReason: String? = nil) {
        self.configEnabled = configEnabled; self.monitoringEnabled = monitoringEnabled; self.realtimeMonitoringEnabled = realtimeMonitoringEnabled
        self.effective = effective; self.disabledReason = disabledReason
    }
    enum CodingKeys: String, CodingKey {
        case effective, configEnabled = "config_enabled", monitoringEnabled = "monitoring_enabled"
        case realtimeMonitoringEnabled = "realtime_monitoring_enabled", disabledReason = "disabled_reason"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(configEnabled: c.lenientValue(.configEnabled), monitoringEnabled: c.lenientValue(.monitoringEnabled),
                  realtimeMonitoringEnabled: c.lenientValue(.realtimeMonitoringEnabled), effective: c.lenientValue(.effective),
                  disabledReason: c.lenientValue(.disabledReason))
    }
}

/// Which endpoint turns monitoring on or off; the only rule (S1D1-07, security). A server with `/admin/me` keeps the settings
/// an `admin/settings` PUT leaves out (0b5903d45, v0.1.166, predates `/admin/me`); an older one would reset them, so it gets none.
public enum OpsMonitoringWriteRoute: Sendable, Equatable {
    case monitoringStatus, legacySettings, unavailable
    public static func resolve(me: AdminMe) -> OpsMonitoringWriteRoute {
        if me.has(.opsMonitoringStatus) { return .monitoringStatus }
        return me.isLegacyServer ? .unavailable : .legacySettings
    }
    /// Fixed bytes so no other site setting can ever ride along.
    static let legacyEnableBody = Data(#"{"ops_monitoring_enabled":true}"#.utf8)
}

private extension KeyedDecodingContainer {
    /// A point without a readable time cannot be placed: it fails so the list skips it.
    func requiredTimestamp(_ key: Key) throws -> Date {
        guard let date = try optionalTimestamp(key) else { throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid timestamp") }
        return date
    }
}
