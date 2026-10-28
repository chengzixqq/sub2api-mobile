import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// S1-07, 10 §1.2 逐接口退路: without `dashboard.home`, or when home answers 404 or the network fails, each block is read from its
// own endpoint and turned into the models of the home reply, so the page never knows which path a block came from.

/// One fallback block: a value, a feature switched off (its reason, as in a home block), or a failure.
public enum FallbackOutcome<Value: Sendable>: Sendable {
    case loaded(Value)
    case disabled(reason: String)
    case failed(any Error)

    public var value: Value? { if case .loaded(let value) = self { value } else { nil } }
    public var disabledReason: String? { if case .disabled(let reason) = self { reason } else { nil } }
}

/// What the rates block can be read from so far (10 §1.2 ① ② ③); nil is a read that has not come back.
public struct RatesInputs: Sendable {
    public var hasDashboardRates: Bool
    public var dashboardRates: Result<LiveRates, any Error>?
    public var opsOverview: Result<OpsOverview, any Error>?
    public var stats: Result<DashboardStats, any Error>?

    public init(hasDashboardRates: Bool, dashboardRates: Result<LiveRates, any Error>? = nil, opsOverview: Result<OpsOverview, any Error>? = nil,
                stats: Result<DashboardStats, any Error>? = nil) {
        self.hasDashboardRates = hasDashboardRates; self.dashboardRates = dashboardRates; self.opsOverview = opsOverview; self.stats = stats
    }
}

public enum RatesResolution: Sendable {
    case pending
    case resolved(FallbackOutcome<LiveRates>, source: HomeRatesSource)
}

/// 昨日同时 (appendix A S10): yesterday from 00:00 to `until`, on the server's calendar.
public struct YesterdaySameTime: Sendable, Equatable {
    public let actualCost: Decimal?
    public let requests: Int?
    public let until: Date

    public init(actualCost: Decimal?, requests: Int?, until: Date) { self.actualCost = actualCost; self.requests = requests; self.until = until }
}

/// `dashboard/trend` buckets; the first definition, S4-02 reuses it (S1D1-23).
public enum TrendGranularity: String, Sendable, CaseIterable { case hour, day }

public enum HomeFallback {
    /// home's `alerts.top`.
    public static let alertTopLimit = 5
    public static let ratesWindow = LiveRatesWindow.fiveMinutes
    /// The ops overview of the last five minutes (sent as start_time / end_time, X08).
    public static let opsWindow = "5m"
    /// Without it the server answers for 24h (appendix B L11).
    public static let channelRange = "90m"
    /// A site from before the channel monitor (a non-JSON 404).
    public static let unsupportedReason = "UNSUPPORTED"
    static let opsDisabledReason = "OPS_DISABLED"
    static let channelMonitorDisabledReason = "CHANNEL_MONITOR_DISABLED"

    // MARK: 触发与归类

    /// A 404 (JSON or not) or a network failure after the read retries. 5xx, 429 and the auth refusals only mark home failed
    /// (10 §1.5), so a struggling server is not sent ten reads instead of one.
    public static func shouldFallBack(afterHomeError error: any Error) -> Bool {
        if error is URLError { return true }
        guard let failure = error as? APIError else { return false }
        if failure.statusCode == 404 { return true }
        return failure.kind == .transport && failure.statusCode == nil && failure != .refreshDeferred
    }
    /// Home is gone on this site: the rest of the session skips it.
    public static func isMissingEndpoint(_ error: any Error) -> Bool { (error as? APIError)?.statusCode == 404 }
    /// 404 OPS_DISABLED and 403 CHANNEL_MONITOR_DISABLED, as a home block reports them.
    public static func disabledReason(_ error: any Error) -> String? {
        guard let failure = error as? APIError, let reason = failure.reason else { return nil }
        switch (failure.statusCode, reason) {
        case (404?, opsDisabledReason), (403?, channelMonitorDisabledReason): return reason
        default: return nil
        }
    }
    /// “加载超时” rather than “加载失败”.
    public static func isTimeout(_ error: any Error) -> Bool {
        if let failure = error as? URLError { return failure.code == .timedOut }
        guard let failure = error as? APIError else { return false }
        return failure.statusCode == 504 || failure == APIError.transport(URLError(.timedOut))
    }
    /// `unsupportedAsDisabled`: a non-JSON 404 means the feature does not exist yet (the channel monitor), not a failure.
    public static func outcome<Value: Sendable>(_ result: Result<Value, any Error>, unsupportedAsDisabled: Bool = false) -> FallbackOutcome<Value> {
        switch result {
        case .success(let value): return .loaded(value)
        case .failure(let error):
            if let reason = disabledReason(error) { return .disabled(reason: reason) }
            if unsupportedAsDisabled, isUnsupported(error) { return .disabled(reason: unsupportedReason) }
            return .failed(error)
        }
    }
    static func isUnsupported(_ error: any Error) -> Bool {
        guard let failure = error as? APIError else { return false }
        return failure.statusCode == 404 && failure.kind == .unsupported
    }

    // MARK: rates

    /// ②: per minute over the overview's own window; `request_count_total` counts errors and `token_consumed` cache tokens.
    public static func rates(fromOverview overview: OpsOverview) -> LiveRates {
        let seconds = windowSeconds(overview.startTime, overview.endTime)
        func perMinute(_ count: Int?) -> Double? {
            guard let count, let seconds else { return nil }
            return Double(count) * 60 / seconds
        }
        return LiveRates(rpm: perMinute(overview.requestCountTotal), tpm: perMinute(overview.tokenConsumed), errorRate: overview.errorRate,
                         upstream429Count: overview.upstream429Count, upstream529Count: overview.upstream529Count, opsMonitoringEnabled: true,
                         errorsAvailable: true, rpmIncludesErrors: true, startTime: overview.startTime, endTime: overview.endTime)
    }
    /// ③: successful requests only, and TPM without cache tokens (10 §1.3.2). `opsMonitoringEnabled` is nil when the site has no
    /// ops at all (a non-JSON 404), not “switched off”.
    public static func rates(fromStats stats: DashboardStats, opsMonitoringEnabled: Bool? = false) -> LiveRates {
        LiveRates(rpm: stats.availableRPM, tpm: stats.tpm, opsMonitoringEnabled: opsMonitoringEnabled, errorsAvailable: false, rpmIncludesErrors: false)
    }
    /// ① with `dashboard.rates`, ② when ① is missing (404), ③ when ② is switched off or missing; any other failure fails the block.
    public static func resolveRates(_ inputs: RatesInputs) -> RatesResolution {
        if inputs.hasDashboardRates {
            switch inputs.dashboardRates {
            case nil: return .pending
            case .success(let rates)?: return .resolved(.loaded(rates), source: .dashboardRates)
            case .failure(let error)? where !isMissingEndpoint(error): return .resolved(.failed(error), source: .dashboardRates)
            case .failure?: break
            }
        }
        switch inputs.opsOverview {
        case nil: return .pending
        case .success(let overview)?: return .resolved(.loaded(rates(fromOverview: overview)), source: .opsOverview)
        case .failure(let error)?:
            guard isMissingEndpoint(error), disabledReason(error) != nil || isUnsupported(error) else {
                return .resolved(.failed(error), source: .opsOverview)
            }
            switch inputs.stats {
            case nil: return .pending
            case .success(let stats)?:
                return .resolved(.loaded(rates(fromStats: stats, opsMonitoringEnabled: disabledReason(error) == nil ? nil : false)), source: .dashboardStats)
            case .failure(let failure)?: return .resolved(.failed(failure), source: .dashboardStats)
            }
        }
    }

    // MARK: stats

    /// The backend's GetYesterdaySameTime: yesterday 00:00 to one calendar day before the reference, which is now, or while the
    /// aggregate is stale `stats_updated_at` kept within today. nil when nothing is left, and then nothing is read.
    public static func yesterdayWindow(now: Date, zone: ServerTimeZone, statsUpdatedAt: Date?, statsStale: Bool) -> DateInterval? {
        let calendar = zone.calendar, today = calendar.startOfDay(for: now)
        let reference = statsStale ? min(max(statsUpdatedAt ?? now, today), now) : now
        guard let start = calendar.date(byAdding: .day, value: -1, to: today), let end = calendar.date(byAdding: .day, value: -1, to: reference),
              end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
    /// Every day bucket, summed (there is normally one).
    public static func yesterdaySameTime(_ reply: DashboardTrendReply, until: Date) -> YesterdaySameTime {
        guard !reply.points.isEmpty else { return YesterdaySameTime(actualCost: nil, requests: nil, until: until) }
        let costs = reply.points.compactMap(\.actualCost)
        return YesterdaySameTime(actualCost: costs.isEmpty ? nil : costs.reduce(0, +), requests: reply.points.reduce(0) { $0 + $1.requests }, until: until)
    }
    /// Today's actual cost and account cost come from one reply: the cost snapshot replaces both when stats lacks either.
    public static func homeStats(_ stats: DashboardStats, snapshot: DashboardCostSnapshot?, yesterday: YesterdaySameTime?) -> HomeStats {
        let incomplete = stats.todayActualCost == nil || stats.todayAccountCost == nil
        let pair = incomplete ? snapshot : nil
        return HomeStats(todayRequests: stats.todayRequests, todayTokens: stats.todayTokens, todayCost: stats.todayCost,
                         todayActualCost: pair?.actual ?? stats.todayActualCost, todayAccountCost: pair.map(\.account) ?? stats.todayAccountCost,
                         statsUpdatedAt: ServerTime.parseTimestamp(stats.statsUpdatedAt), statsStale: stats.statsStale ?? false,
                         yesterdaySameTimeActualCost: yesterday?.actualCost, yesterdaySameTimeRequests: yesterday?.requests,
                         yesterdaySameTimeUntil: yesterday?.until)
    }

    // MARK: hourly, ops, alerts, channels

    /// The buckets of today and yesterday by their `yyyy-MM-dd` prefix in the reply's zone, each in time order; others are dropped.
    /// `account_cost` is not in a trend point yet (S4-02).
    public static func hourly(_ reply: DashboardTrendReply, now: Date) -> HomeHourly {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX"); calendar.timeZone = reply.timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.locale = calendar.locale; formatter.timeZone = reply.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        func points(on day: Date) -> [HomeHourlyPoint] {
            let prefix = formatter.string(from: day)
            return reply.points.filter { $0.date.prefix(prefix.count) == prefix }.sorted { $0.date < $1.date }.map {
                HomeHourlyPoint(date: $0.date, requests: $0.requests, totalTokens: $0.totalTokens, actualCost: $0.actualCost ?? 0)
            }
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return HomeHourly(timezone: reply.timeZone.identifier, today: points(on: now), yesterday: points(on: yesterday))
    }
    public static func homeOps(_ overview: OpsOverview) -> HomeOps {
        HomeOps(healthScore: overview.healthScore, sla: overview.sla, errorRate: overview.errorRate, upstream429Count: overview.upstream429Count,
                upstream529Count: overview.upstream529Count, requestCountTotal: overview.requestCountTotal, tokenConsumed: overview.tokenConsumed)
    }
    /// The counts as given, and the newest five firing events (`fired_at DESC, id DESC`).
    public static func homeAlerts(counts: AlertCounts, firing: [AlertEvent]) -> HomeAlerts {
        let newest = firing.filter(\.isFiring).sorted { lhs, rhs in
            switch (lhs.cursor, rhs.cursor) {
            case let (left?, right?): right < left
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.id > rhs.id
            }
        }
        return HomeAlerts(firingCount: counts.firing, bySeverity: counts.bySeverity, top: Array(newest.prefix(alertTopLimit)))
    }
    /// The monitor's four counts (stale and unknown states are unknown).
    public static func homeChannels(_ overview: ChannelOverview) -> HomeChannels {
        let counts = ChannelPresentation.counts(overview.items)
        return HomeChannels(total: overview.items.count, healthy: counts.available, warning: counts.degraded, critical: counts.unavailable,
                            unknown: counts.unknown, coverageState: overview.coverage?.state, collectorState: overview.coverage?.collectorState)
    }
    /// S1D1-16: the rule and the group name a server without `ops.alert_event_details` leaves out; what the event has is kept.
    public static func fillingLegacyDetails(_ event: AlertEvent, rules: [Int: AlertEventRule], groupNames: [Int: String]) -> AlertEvent {
        var filled = event
        if filled.rule == nil, let id = filled.ruleID, let rule = rules[id] { filled = filled.replacingRule(rule) }
        if let group = filled.groupID, (filled.groupName ?? "").isEmpty, let name = groupNames[group] { filled = filled.replacingGroupName(name) }
        return filled
    }

    static func windowSeconds(_ start: Date?, _ end: Date?) -> Double? {
        guard let start, let end else { return nil }
        let seconds = end.timeIntervalSince(start)
        return seconds > 0 ? seconds : nil
    }
}

extension APIClient {
    /// 10 §1.2 昨日同时: an explicit range in UTC `Z` (`start_time` / `end_time`), bucketed in the server zone; the zone of the reply's
    /// `query.timezone` reads the buckets (usageAnalysisTrend, S4D1-12). A range that is empty or backwards is refused here, without a request.
    public func dashboardTrend(start: Date, end: Date, granularity: TrendGranularity) async throws -> DashboardTrendReply {
        guard start < end else { throw APIError(kind: .validation, message: "统计时间范围无效。") }
        return try await usageAnalysisTrend(AnalyticsQuery(start: start, end: end, granularity: granularity, timeZone: serverTimeZone()))
    }
}
