import Foundation

// S1-14, 10 §4.3–§4.5: the monitor overview's 服务器 section (贰), from the run's overview and the section's own four reads. Text,
// tones and rules are MonitorPresentation's (S1-02); this file decides what is missing, loading, failed or stale, and where the
// CPU / memory lines break. Nothing here reads the clock.

/// The section's own reads, in the order of its failure row and stale mark; the overview belongs to the run section.
public enum MonitorServerPart: String, CaseIterable, Hashable, Sendable {
    case systemMetrics, concurrency, logHealth, ingress
}

public struct MonitorServerInput: Sendable {
    /// The run section's overview (MonitorState.overview).
    public var overview: BlockDisplay<OpsOverview>
    public var history: BlockDisplay<SystemMetricsHistory>
    /// The phone's own points while the site has no history (or it is not read).
    public var localSamples: [SystemMetricsHistory.Point]
    public var concurrency: BlockDisplay<OpsConcurrency>
    public var logHealth: BlockDisplay<SystemLogHealth>
    public var ingress: BlockDisplay<MonitorPresentation.IngressRejectTally>
    /// Reads not sent: history without its capability (the local points instead), a route the site lacks (00 §5 item 3). They
    /// show “—”, never loading or failed.
    public var unavailable: Set<MonitorServerPart>
    public var heartbeatStatusSupported: Bool
    /// The server-corrected time and the server's zone.
    public var now: Date
    public var timeZone: TimeZone

    public init(overview: BlockDisplay<OpsOverview>, history: BlockDisplay<SystemMetricsHistory>, localSamples: [SystemMetricsHistory.Point],
                concurrency: BlockDisplay<OpsConcurrency>, logHealth: BlockDisplay<SystemLogHealth>,
                ingress: BlockDisplay<MonitorPresentation.IngressRejectTally>, unavailable: Set<MonitorServerPart>, heartbeatStatusSupported: Bool,
                now: Date, timeZone: TimeZone) {
        self.overview = overview; self.history = history; self.localSamples = localSamples; self.concurrency = concurrency
        self.logHealth = logHealth; self.ingress = ingress; self.unavailable = unavailable
        self.heartbeatStatusSupported = heartbeatStatusSupported; self.now = now; self.timeZone = timeZone
    }
}

public struct MonitorServerDisplay: Sendable, Equatable {
    public enum Meter: String, Sendable, CaseIterable {
        case cpu, memory
        public var title: String { self == .cpu ? "CPU" : "内存" }
        /// The line's name for VoiceOver.
        public var trendLabel: String { self == .cpu ? "CPU 趋势" : "内存趋势" }
    }
    public struct MeterDisplay: Sendable, Equatable {
        public let meter: Meter
        public let reading: MonitorPresentation.CapacityReading
        /// Empty: no line to draw.
        public let trend: [Double?]
        public let spokenTrend: String
        /// The tone in the reading's identifier (UI tests cannot see colours).
        public var toneKey: String {
            switch reading.tone {
            case .critical?: "critical"
            case .caution?: "caution"
            default: "normal"
            }
        }
    }
    public enum Jobs: Sendable, Equatable {
        /// The overview's first load: skeleton.
        case loading
        /// No overview to read them from: one 后台任务 row with “—”.
        case missing
        /// 还没有后台任务心跳.
        case empty
        case lines([MonitorPresentation.JobLine])
    }
    /// Reads that failed before any value, as one 加载失败 · 重试 row.
    public struct FailureRow: Sendable, Equatable {
        public let parts: [MonitorServerPart]
        public let title: String
        /// One read: its row goes under that read's figures; more: first in the section.
        public var anchor: MonitorServerPart? { parts.count == 1 ? parts.first : nil }
        public init(parts: [MonitorServerPart], title: String) { self.parts = parts; self.title = title }
    }

    public let isOverviewLoading: Bool
    public let cpu: MeterDisplay
    public let memory: MeterDisplay
    public let concurrency: MonitorPresentation.ConcurrencyReading
    public let qps: String
    public let sla: String
    public let jobs: Jobs
    public let ingest: MonitorPresentation.LogIngestLine
    public let loadingParts: Set<MonitorServerPart>
    public let failure: FailureRow?
    /// Reads whose refresh failed while an earlier value shows (10 §0.5), in part order.
    public let staleParts: [MonitorServerPart]
}

public enum MonitorServerPresentation {
    public static let title = "服务器"
    public static let meta = "仅管理员可见"
    public static let realtimeOffNote = "实时监控未开启"
    public static let noHeartbeats = "还没有后台任务心跳"
    public static let jobsPlaceholderTitle = "后台任务"
    public static let ingestTitle = "日志采集"
    /// The collector writes a sample a minute by default.
    public static let defaultSampleSeconds: TimeInterval = 60
    /// Two points further apart than this many sampling intervals have a hole between them.
    public static let gapFactor: Double = 2.5
    private static let collectorJobName = "ops_metrics_collector"

    public static func display(_ input: MonitorServerInput) -> MonitorServerDisplay {
        let overview = shown(input.overview)
        let jobRows = jobs(input, overview: overview)
        let attention = if case .lines(let lines) = jobRows { MonitorPresentation.attentionCount(lines) } else { 0 }
        let points = input.unavailable.contains(.systemMetrics) ? input.localSamples : shown(input.history)?.points ?? []
        let gap = maxGap(bucketSeconds: input.unavailable.contains(.systemMetrics) ? nil : shown(input.history)?.bucketSeconds,
                         heartbeats: overview?.jobHeartbeats ?? [])
        func meter(_ kind: MonitorServerDisplay.Meter, _ percent: Double?) -> MonitorServerDisplay.MeterDisplay {
            let trend = trendValues(points, meter: kind, maxGap: gap)
            return MonitorServerDisplay.MeterDisplay(meter: kind, reading: MonitorPresentation.capacity(percent), trend: trend,
                                                     spokenTrend: trendSpokenValue(trend))
        }
        let metrics = overview?.systemMetrics
        let concurrency = input.unavailable.contains(.concurrency) ? nil : shown(input.concurrency)
        let logs = input.unavailable.contains(.logHealth) ? nil : shown(input.logHealth)
        let ingress = input.unavailable.contains(.ingress) ? nil : shown(input.ingress)
        let readPhases = phases(input)
        return MonitorServerDisplay(
            isOverviewLoading: input.overview.homePhase == .placeholder, cpu: meter(.cpu, metrics?.cpuUsagePercent),
            memory: meter(.memory, metrics?.memoryUsagePercent),
            concurrency: MonitorPresentation.concurrency(concurrency, queueDepth: metrics?.concurrencyQueueDepth),
            qps: MonitorPresentation.qps(overview), sla: MonitorPresentation.sla(overview), jobs: jobRows,
            ingest: MonitorPresentation.logIngest(logs, rejections: ingress, attentionCount: attention),
            loadingParts: Set(readPhases.filter { $0.phase == .placeholder }.map(\.part)),
            failure: failureRow(readPhases.filter { $0.phase == .failed }.map(\.part)),
            staleParts: readPhases.filter { $0.phase == .value(updateFailed: true) }.map(\.part))
    }

    /// Oldest first, clamped to 0–100; a nil between two points further apart than `maxGap` (the server leaves out buckets
    /// without samples). Fewer than two values: no line.
    public static func trendValues(_ points: [SystemMetricsHistory.Point], meter: MonitorServerDisplay.Meter, maxGap: TimeInterval) -> [Double?] {
        var values: [Double?] = [], previous: Date?
        for point in points.sorted(by: { $0.createdAt < $1.createdAt }) {
            if let previous, point.createdAt.timeIntervalSince(previous) > maxGap { values.append(nil) }
            let value = meter == .cpu ? point.cpuUsagePercent : point.memoryUsagePercent
            values.append(value.flatMap { $0.isFinite ? min(max($0, 0), 100) : nil })
            previous = point.createdAt
        }
        return values.compactMap { $0 }.count >= 2 ? values : []
    }
    /// `gapFactor` × the longer of the bucket (60 when unknown, as for the local points) and the collector's interval.
    public static func maxGap(bucketSeconds: Int?, heartbeats: [OpsJobHeartbeat]) -> TimeInterval {
        func seconds(_ value: Int?) -> TimeInterval { value.flatMap { $0 > 0 ? TimeInterval($0) : nil } ?? defaultSampleSeconds }
        let collector = heartbeats.first { $0.jobName == collectorJobName }?.expectedIntervalSeconds
        return gapFactor * max(seconds(bucketSeconds), seconds(collector))
    }
    /// “最近 92.0%，最高 95.0%”, as the run's line reads; nothing at all reads 无数据.
    public static func trendSpokenValue(_ values: [Double?]) -> String {
        let known = values.compactMap { $0 }
        guard let latest = known.last, let peak = known.max() else { return DisplayFormat.missingSpoken }
        return "最近 " + DisplayFormat.percent(latest) + "，最高 " + DisplayFormat.percent(peak)
    }

    private static func jobs(_ input: MonitorServerInput, overview: OpsOverview?) -> MonitorServerDisplay.Jobs {
        guard let overview else { return input.overview.homePhase == .placeholder ? .loading : .missing }
        guard !overview.jobHeartbeats.isEmpty else { return .empty }
        return .lines(MonitorPresentation.jobLines(overview.jobHeartbeats, supportsStatus: input.heartbeatStatusSupported, now: input.now,
                                                   timeZone: input.timeZone))
    }
    /// The phase of each read that is sent.
    private static func phases(_ input: MonitorServerInput) -> [(part: MonitorServerPart, phase: HomeBlockPhase)] {
        MonitorServerPart.allCases.compactMap { part in
            guard !input.unavailable.contains(part) else { return nil }
            switch part {
            case .systemMetrics: return (part, input.history.homePhase)
            case .concurrency: return (part, input.concurrency.homePhase)
            case .logHealth: return (part, input.logHealth.homePhase)
            case .ingress: return (part, input.ingress.homePhase)
            }
        }
    }
    /// The history alone keeps the line's own words (趋势加载失败).
    private static func failureRow(_ parts: [MonitorServerPart]) -> MonitorServerDisplay.FailureRow? {
        guard !parts.isEmpty else { return nil }
        let title = parts == [.systemMetrics] ? MonitorTabPresentation.trendFailed : BlockStatusPresentation.loadFailed
        return MonitorServerDisplay.FailureRow(parts: parts, title: title)
    }
    private static func shown<Value: Sendable>(_ display: BlockDisplay<Value>) -> Value? {
        if case .value(let value, _, _, _) = display { value } else { nil }
    }
}
