import Foundation

/// 10 §1.3.5 and §4.3: the monitor overview and server section. Numbers go through DisplayFormat (R10) and colours are Tone;
/// callers pass the server-corrected `now` and the server's time zone, so nothing here reads the clock.
public enum MonitorPresentation {
    // MARK: Health score (1.3.5, shared by the home run section and the monitor overview)

    public struct HealthReading: Sendable, Equatable {
        public let value: String
        /// nil when there is no score; “运维监控未开启” is the page's to write.
        public let word: String?
        public let tone: Tone?
        /// 0…1 along the gauge.
        public let fraction: Double?
        public init(value: String, word: String?, tone: Tone?, fraction: Double?) {
            self.value = value; self.word = word; self.tone = tone; self.fraction = fraction
        }
    }
    /// ≥ 90 良好, ≥ 60 风险, below 60 异常.
    public static func health(_ score: Int?) -> HealthReading {
        guard let score else { return HealthReading(value: DisplayFormat.missing, word: nil, tone: nil, fraction: nil) }
        let (word, tone): (String, Tone) = score >= 90 ? ("良好", .ok) : score >= 60 ? ("风险", .caution) : ("异常", .critical)
        return HealthReading(value: DisplayFormat.grouped(score), word: word, tone: tone, fraction: unit(Double(score) / 100))
    }

    // MARK: Error-rate line (4.3)

    public struct ErrorRatePoint: Sendable, Equatable, Identifiable {
        public let start: Date
        /// 0–1 (DisplayFormat.ratioPercent); nil when nothing counts toward it, which breaks the line.
        public let rate: Double?
        public var id: Date { start }
        public init(start: Date, rate: Double?) { self.start = start; self.rate = rate }
    }
    public static let errorRateWindow: TimeInterval = 2_700
    public static let errorRatePointSeconds: TimeInterval = 300
    public static let errorRatePointCount = 9
    private static let errorRateBucketSeconds: TimeInterval = 60

    /// Always nine five-minute points anchored at `windowEnd`: one-minute buckets of either trend land by `bucket_start`, a
    /// partial first or last bucket joins the first or last point, buckets outside the window are dropped. Each point is
    /// Σ error_count_sla ÷ Σ (request_count − business_limited_count).
    public static func errorRateSeries(_ snapshot: OpsSnapshotV2) -> [ErrorRatePoint] {
        let origin = snapshot.windowEnd.addingTimeInterval(-errorRateWindow)
        func slot(_ start: Date) -> Int? {
            guard start < snapshot.windowEnd, start.addingTimeInterval(errorRateBucketSeconds) > origin else { return nil }
            return min(max(Int((start.timeIntervalSince(origin) / errorRatePointSeconds).rounded(.down)), 0), errorRatePointCount - 1)
        }
        var requests = Array(repeating: 0, count: errorRatePointCount), limited = requests, errors = requests
        for point in snapshot.throughputPoints { if let index = slot(point.bucketStart) { requests[index] += point.requestCount } }
        for point in snapshot.errorPoints {
            guard let index = slot(point.bucketStart) else { continue }
            errors[index] += point.errorCountSLA; limited[index] += point.businessLimitedCount
        }
        return (0..<errorRatePointCount).map { index in
            let counted = requests[index] - limited[index]
            return ErrorRatePoint(start: origin.addingTimeInterval(Double(index) * errorRatePointSeconds),
                                  rate: counted > 0 ? Double(errors[index]) / Double(counted) : nil)
        }
    }

    // MARK: Server section (4.3)

    public struct CapacityReading: Sendable, Equatable {
        public let text: String
        public let fraction: Double?
        public let tone: Tone?
        public init(text: String, fraction: Double?, tone: Tone?) { self.text = text; self.fraction = fraction; self.tone = tone }
    }
    /// CPU and memory bars: ≥ 90 critical, ≥ 75 caution.
    public static func capacityTone(_ percent: Double?) -> Tone? {
        guard let percent else { return nil }
        if percent >= 90 { return .critical }
        return percent >= 75 ? .caution : nil
    }
    /// The value already is a percentage; one decimal as every percentage (00 §6.2).
    public static func capacity(_ percent: Double?) -> CapacityReading {
        let value = percent.flatMap { $0.isFinite ? $0 : nil }
        return CapacityReading(text: DisplayFormat.percent(value), fraction: value.map { unit($0 / 100) }, tone: capacityTone(value))
    }

    public struct ConcurrencyReading: Sendable, Equatable {
        /// “8/50”.
        public let inUse: String
        public let queue: String
        /// Realtime monitoring is off (“实时监控未开启”), not ops monitoring (appendix A S7).
        public let isRealtimeOff: Bool
        public init(inUse: String, queue: String, isRealtimeOff: Bool) { self.inUse = inUse; self.queue = queue; self.isRealtimeOff = isRealtimeOff }
    }
    /// Platform sums; without them (realtime off or the read failed) the queue falls back to the overview's `queueDepth`.
    public static func concurrency(_ value: OpsConcurrency?, queueDepth: Int?) -> ConcurrencyReading {
        guard let value, value.enabled else {
            return ConcurrencyReading(inUse: DisplayFormat.missing, queue: DisplayFormat.grouped(queueDepth), isRealtimeOff: value != nil)
        }
        let loads = Array(value.platforms.values)
        func total(_ part: (OpsConcurrency.PlatformLoad) -> Int) -> Int { loads.reduce(0) { $0 + part($1) } }
        return ConcurrencyReading(inUse: DisplayFormat.grouped(total(\.currentInUse)) + "/" + DisplayFormat.grouped(total(\.maxCapacity)),
                                  queue: DisplayFormat.grouped(total(\.waitingInQueue)), isRealtimeOff: false)
    }
    /// The server already keeps one decimal: “0.8”.
    public static func qps(_ overview: OpsOverview?) -> String {
        DisplayFormat.decimal(overview?.qps?.current, minFractionDigits: 1, maxFractionDigits: 1)
    }
    public static func sla(_ overview: OpsOverview?) -> String { DisplayFormat.ratioPercent(overview?.sla) }

    // MARK: Ingress rejections and the log-ingest row (4.3)

    public enum IngressRejectTally: Sendable, Equatable { case exact(Int), atLeast(Int) }
    /// Without `ops.ingress_reject_totals` the rows of at most three pages are added up.
    public static let ingressFallbackPageLimit = 3
    public static let ingressFallbackPageSize = IngressRejectList.pageSizeRange.upperBound

    /// The first page's `request_count_total` when the server sent it; otherwise the sum of the pages read, “at least” while
    /// rows remain unread.
    public static func ingressRejectTally(_ pages: [IngressRejectList]) -> IngressRejectTally? {
        guard let first = pages.first else { return nil }
        if let total = first.requestCountTotal { return .exact(total) }
        let sum = pages.reduce(0) { sum, page in page.items.reduce(sum) { $0 + $1.requestCount } }
        return hasUnreadRows(pages) ? .atLeast(sum) : .exact(sum)
    }
    public static func needsMoreIngressPages(_ pages: [IngressRejectList]) -> Bool {
        guard let first = pages.first, first.requestCountTotal == nil else { return false }
        return pages.count < ingressFallbackPageLimit && hasUnreadRows(pages)
    }
    /// From `total` (rows) when present, else whether the last page came back full.
    private static func hasUnreadRows(_ pages: [IngressRejectList]) -> Bool {
        guard let last = pages.last else { return false }
        if let total = last.total ?? pages.first?.total { return pages.reduce(0) { $0 + $1.items.count } < total }
        return last.items.count >= max(last.pageSize ?? ingressFallbackPageSize, 1)
    }

    public struct LogIngestLine: Sendable, Equatable {
        /// nil while the health read failed; false when the sink reports an error.
        public let isHealthy: Bool?
        public let trailing: String
        public let detail: String
        public init(isHealthy: Bool?, trailing: String, detail: String) { self.isHealthy = isHealthy; self.trailing = trailing; self.detail = detail }
    }
    /// Right side “延迟 850ms” / “延迟 2.0s” (R10); detail “入口拒绝 3 次（1 小时）· 1 个任务需留意”.
    public static func logIngest(_ health: SystemLogHealth?, rejections: IngressRejectTally?, attentionCount: Int) -> LogIngestLine {
        let delay = health?.avgWriteDelayMs.map { "延迟 " + DisplayFormat.duration($0, style: .millis) }
        let attention = attentionCount > 0 ? "· \(DisplayFormat.grouped(attentionCount)) 个任务需留意" : nil
        let detail: String
        switch rejections {
        case .exact(let count)?: detail = "入口拒绝 \(DisplayFormat.grouped(count)) 次（1 小时）" + (attention ?? "")
        case .atLeast(let count)?: detail = "入口拒绝 ≥ \(DisplayFormat.grouped(count)) 次（1 小时）" + (attention ?? "")
        case nil: detail = "入口拒绝 " + DisplayFormat.missing + (attention.map { " " + $0 } ?? "")
        }
        return LogIngestLine(isHealthy: health.map { !$0.hasError }, trailing: delay ?? DisplayFormat.missing, detail: detail)
    }

    // MARK: Local CPU / memory points (4.3, without `ops.system_metrics_history`)

    public static let localSampleLimit = 60
    /// The overview's snapshot as one more point: the same `createdAt` replaces the last point, an older one is ignored, and
    /// only the newest 60 are kept. Always a new array.
    public static func appendingLocalSample(_ samples: [SystemMetricsHistory.Point], from snapshot: OpsSystemMetricsSnapshot?) -> [SystemMetricsHistory.Point] {
        guard let snapshot, let createdAt = snapshot.createdAt else { return samples }
        let point = SystemMetricsHistory.Point(createdAt: createdAt, cpuUsagePercent: snapshot.cpuUsagePercent, memoryUsagePercent: snapshot.memoryUsagePercent)
        guard let last = samples.last else { return [point] }
        guard createdAt >= last.createdAt else { return samples }
        let kept = createdAt == last.createdAt ? samples.dropLast() : samples[...]
        return Array((kept + [point]).suffix(localSampleLimit))
    }

    static func unit(_ value: Double) -> Double { min(max(value, 0), 1) }
}

// MARK: - 任务行（10 §4.3 任务行表与本地判定）

extension MonitorPresentation {
    public enum JobState: String, Sendable, CaseIterable {
        case ok, failing, stale, disabled, unknown
        public var tone: Tone? {
            switch self {
            case .ok: .ok
            case .failing, .stale: .caution
            case .disabled, .unknown: nil
            }
        }
        /// Counted in “N 个任务需留意”.
        public var needsAttention: Bool { self == .failing || self == .stale }
    }

    public struct JobLine: Sendable, Equatable, Identifiable {
        /// The raw `job_name`.
        public let id: String
        public let title: String
        public let state: JobState
        public let trailing: String
        /// failing / stale write the right side in the caution colour.
        public let trailingIsCaution: Bool
        public let detail: String?
        public var tone: Tone? { state.tone }
        public init(id: String, title: String, state: JobState, trailing: String, trailingIsCaution: Bool, detail: String?) {
            self.id = id; self.title = title; self.state = state; self.trailing = trailing; self.trailingIsCaution = trailingIsCaution; self.detail = detail
        }
    }

    private struct KnownJob: Sendable {
        let name: String
        let title: String
        /// Without the status capability, no success for longer than this is stale; nil jobs are only judged failing.
        let localStaleAfter: TimeInterval?
    }
    private static let knownJobs = [
        KnownJob(name: "ops_metrics_collector", title: "指标采集", localStaleAfter: 180),
        KnownJob(name: "ops_alert_evaluator", title: "告警评估", localStaleAfter: 180),
        KnownJob(name: "ops_preaggregation_hourly", title: "预聚合（小时）", localStaleAfter: 1_800),
        KnownJob(name: "ops_preaggregation_daily", title: "预聚合（天）", localStaleAfter: 10_800),
        KnownJob(name: "ops_cleanup", title: "清理", localStaleAfter: nil),
        KnownJob(name: "ops_scheduled_reports", title: "定时报告", localStaleAfter: nil)
    ]
    /// Display order; jobs that never ran are not listed by the server.
    public static let knownJobNames = knownJobs.map(\.name)
    /// Runs on a cron schedule, so a stale one is described by its planned time.
    private static let cronJobName = "ops_cleanup"

    /// Unknown jobs keep their raw name.
    public static func jobTitle(_ jobName: String) -> String { knownJobs.first { $0.name == jobName }?.title ?? jobName }
    /// Known jobs in table order, then unknown ones by name.
    public static func sortedHeartbeats(_ heartbeats: [OpsJobHeartbeat]) -> [OpsJobHeartbeat] {
        func rank(_ beat: OpsJobHeartbeat) -> Int { knownJobNames.firstIndex(of: beat.jobName) ?? knownJobNames.count }
        return heartbeats.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.jobName < $1.jobName }
    }

    /// With `ops.job_heartbeat_status` the reported status (an unknown value is unknown); otherwise the local rules.
    public static func jobState(_ heartbeat: OpsJobHeartbeat, supportsStatus: Bool, now: Date) -> JobState {
        guard supportsStatus else { return localState(heartbeat, now: now) }
        return JobState(rawValue: heartbeat.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "") ?? .unknown
    }
    /// Stale wins over failing, as on the server (D08); no success and no error is unknown.
    private static func localState(_ heartbeat: OpsJobHeartbeat, now: Date) -> JobState {
        if let success = heartbeat.lastSuccessAt, let limit = localStaleAfter(heartbeat.jobName), now.timeIntervalSince(success) > limit { return .stale }
        if let error = heartbeat.lastErrorAt, heartbeat.lastSuccessAt.map({ error > $0 }) ?? true { return .failing }
        return heartbeat.lastSuccessAt == nil ? .unknown : .ok
    }
    private static func localStaleAfter(_ jobName: String) -> TimeInterval? { knownJobs.first { $0.name == jobName }?.localStaleAfter }

    public static func jobLines(_ heartbeats: [OpsJobHeartbeat], supportsStatus: Bool, now: Date, timeZone: TimeZone) -> [JobLine] {
        sortedHeartbeats(heartbeats).map { beat in
            let state = jobState(beat, supportsStatus: supportsStatus, now: now)
            return JobLine(id: beat.jobName, title: jobTitle(beat.jobName), state: state,
                           trailing: trailing(beat, state: state, now: now, timeZone: timeZone), trailingIsCaution: state.needsAttention,
                           detail: detail(beat, state: state, supportsStatus: supportsStatus, now: now, timeZone: timeZone))
        }
    }
    public static func attentionCount(_ lines: [JobLine]) -> Int { lines.filter(\.state.needsAttention).count }

    private static func trailing(_ beat: OpsJobHeartbeat, state: JobState, now: Date, timeZone: TimeZone) -> String {
        switch state {
        case .disabled: return "已关闭"
        case .unknown: return DisplayFormat.missing
        case .ok, .failing, .stale:
            guard let success = beat.lastSuccessAt else { return "从未成功" }
            let time = DisplayFormat.relativeTime(success, now: now, timeZone: timeZone)
            return state == .ok ? time : "最近成功 " + time
        }
    }
    /// Missing values leave the line out rather than inventing text.
    private static func detail(_ beat: OpsJobHeartbeat, state: JobState, supportsStatus: Bool, now: Date, timeZone: TimeZone) -> String? {
        switch state {
        case .failing: return firstLine(beat.lastError).map { "最近一次失败：" + $0 }
        case .stale:
            guard supportsStatus else { return localStaleAfter(beat.jobName).map(overdue) }
            if beat.jobName == cronJobName { return beat.nextExpectedAt.map { "按计划应在 \(scheduleTime($0, now: now, timeZone: timeZone)) 前完成" } }
            return beat.expectedIntervalSeconds.flatMap { $0 > 0 ? overdue(TimeInterval($0) * 2) : nil }
        case .ok, .disabled, .unknown: return nil
        }
    }
    private static func overdue(_ seconds: TimeInterval) -> String { "超过 \(DisplayFormat.minutesLeft(seconds))没有成功，需要看一下" }
    private static func firstLine(_ text: String?) -> String? {
        let line = text?.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isNewline).first
        let trimmed = line.map { $0.trimmingCharacters(in: .whitespaces) }
        return trimmed?.isEmpty == false ? trimmed : nil
    }
    /// 今天 / 昨天 / 明天 / M月d日 + HH:MM on the server's calendar.
    private static func scheduleTime(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let clock = DisplayFormat.clock(date, timeZone: timeZone)
        switch calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day {
        case 0: return "今天 " + clock
        case -1: return "昨天 " + clock
        case 1: return "明天 " + clock
        default:
            let day = calendar.dateComponents([.month, .day], from: date)
            return "\(day.month ?? 0)月\(day.day ?? 0)日 " + clock
        }
    }
}
