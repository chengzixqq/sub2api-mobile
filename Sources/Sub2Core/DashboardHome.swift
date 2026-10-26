import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(os)
import os
#endif

/// The seven `dashboard/home` sections in the backend's order (`dashboardHomeSections`).
public enum HomeSectionKey: String, CaseIterable, Sendable {
    case stats, rates, hourly, ops, alerts, availability, channels

    /// `include=`: the backend's order without repeats. nil or empty sends nothing, which means all seven.
    static func includeValue(_ keys: [HomeSectionKey]?) -> String? {
        guard let keys, !keys.isEmpty else { return nil }
        return allCases.filter { keys.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}

public enum HomeSectionStatus: String, Sendable, Equatable, CaseIterable {
    case ok, disabled, error, timeout
    /// 10 §1.7: a missing or unknown status reads as error.
    public init(wire: String?) { self = wire.flatMap(Self.init(rawValue:)) ?? .error }
}

/// One `{status, error?, data?}` block. `data` is kept only when ok; a block that is missing, not an object, or whose data
/// cannot be read is `.missing` (error without a reason), so one bad block never fails the whole reply.
public struct HomeSection<Value: Sendable>: Sendable {
    public let status: HomeSectionStatus
    /// The block's JSON `error` (OPS_DISABLED, CHANNEL_MONITOR_DISABLED, SECTION_TIMEOUT, INTERNAL_ERROR…): for decisions and
    /// diagnostics only, never shown. nil when the client found the block missing or unreadable.
    public let reason: String?
    /// Non-nil only when `status == .ok`.
    public let data: Value?

    /// ok without data becomes error; any other status drops the data, ok drops the reason.
    public init(status: HomeSectionStatus, reason: String? = nil, data: Value? = nil) {
        let readable = status == .ok ? data : nil
        self.status = status == .ok && readable == nil ? .error : status
        self.reason = status == .ok ? nil : reason
        self.data = readable
    }
    public static func ok(_ data: Value) -> HomeSection<Value> { HomeSection(status: .ok, data: data) }
    public static var missing: HomeSection<Value> { HomeSection(status: .error) }
}

extension HomeSection: Equatable where Value: Equatable {}

private enum HomeSectionField: String, CodingKey { case status, error, data }

extension HomeSection: Decodable where Value: Decodable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: HomeSectionField.self)
        let status = HomeSectionStatus(wire: try? c.decodeIfPresent(String.self, forKey: .status))
        let reason = (try? c.decodeIfPresent(String.self, forKey: .error)).flatMap { $0.isEmpty ? nil : $0 }
        let data = status == .ok ? (try? c.decodeIfPresent(Value.self, forKey: .data)) : nil
        self.init(status: status, reason: reason, data: data)
    }
}

/// Today in the server's time zone (10 §1.2 `stats`). Money is Decimal and never passes through Double.
public struct HomeStats: Decodable, Sendable, Equatable {
    public let todayRequests: Int?
    /// Includes cache tokens.
    public let todayTokens: Int?
    /// Standard price.
    public let todayCost: Decimal?
    public let todayActualCost: Decimal?
    public let todayAccountCost: Decimal?
    public let statsUpdatedAt: Date?
    public let statsStale: Bool
    /// The yesterday comparison is null when the server could not compute it.
    public let yesterdaySameTimeActualCost: Decimal?
    public let yesterdaySameTimeRequests: Int?
    public let yesterdaySameTimeAccountCost: Decimal?
    public let yesterdaySameTimeUntil: Date?

    public init(todayRequests: Int? = nil, todayTokens: Int? = nil, todayCost: Decimal? = nil, todayActualCost: Decimal? = nil,
                todayAccountCost: Decimal? = nil, statsUpdatedAt: Date? = nil, statsStale: Bool = false, yesterdaySameTimeActualCost: Decimal? = nil,
                yesterdaySameTimeRequests: Int? = nil, yesterdaySameTimeAccountCost: Decimal? = nil, yesterdaySameTimeUntil: Date? = nil) {
        self.todayRequests = todayRequests; self.todayTokens = todayTokens; self.todayCost = todayCost; self.todayActualCost = todayActualCost
        self.todayAccountCost = todayAccountCost; self.statsUpdatedAt = statsUpdatedAt; self.statsStale = statsStale
        self.yesterdaySameTimeActualCost = yesterdaySameTimeActualCost; self.yesterdaySameTimeRequests = yesterdaySameTimeRequests
        self.yesterdaySameTimeAccountCost = yesterdaySameTimeAccountCost; self.yesterdaySameTimeUntil = yesterdaySameTimeUntil
    }
    enum CodingKeys: String, CodingKey {
        case todayRequests = "today_requests", todayTokens = "today_tokens", todayCost = "today_cost", todayActualCost = "today_actual_cost"
        case todayAccountCost = "today_account_cost", statsUpdatedAt = "stats_updated_at", statsStale = "stats_stale"
        case yesterdaySameTimeActualCost = "yesterday_same_time_actual_cost", yesterdaySameTimeRequests = "yesterday_same_time_requests"
        case yesterdaySameTimeAccountCost = "yesterday_same_time_account_cost", yesterdaySameTimeUntil = "yesterday_same_time_until"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(todayRequests: c.decodeIfPresent(Int.self, forKey: .todayRequests), todayTokens: c.decodeIfPresent(Int.self, forKey: .todayTokens),
                      todayCost: c.optionalDecimal(.todayCost), todayActualCost: c.optionalDecimal(.todayActualCost),
                      todayAccountCost: c.optionalDecimal(.todayAccountCost), statsUpdatedAt: c.optionalTimestamp(.statsUpdatedAt),
                      statsStale: c.decodeIfPresent(Bool.self, forKey: .statsStale) ?? false,
                      yesterdaySameTimeActualCost: c.optionalDecimal(.yesterdaySameTimeActualCost),
                      yesterdaySameTimeRequests: c.decodeIfPresent(Int.self, forKey: .yesterdaySameTimeRequests),
                      yesterdaySameTimeAccountCost: c.optionalDecimal(.yesterdaySameTimeAccountCost),
                      yesterdaySameTimeUntil: c.optionalTimestamp(.yesterdaySameTimeUntil))
    }
}

/// `OpsLiveRates`: the `rates` block and `dashboard/rates`. With monitoring off the error fields are null; the three flags are nil
/// when missing, which must not be read as “off”. `startTime` / `endTime` are stale in a 304 reuse.
public struct LiveRates: Decodable, Sendable, Equatable {
    public let rpm: Double?
    /// Includes cache tokens.
    public let tpm: Double?
    /// 0–1.
    public let errorRate: Double?
    public let upstream429Count: Int?
    public let upstream529Count: Int?
    public let opsMonitoringEnabled: Bool?
    public let errorsAvailable: Bool?
    public let rpmIncludesErrors: Bool?
    public let startTime: Date?
    public let endTime: Date?

    public init(rpm: Double? = nil, tpm: Double? = nil, errorRate: Double? = nil, upstream429Count: Int? = nil, upstream529Count: Int? = nil,
                opsMonitoringEnabled: Bool? = nil, errorsAvailable: Bool? = nil, rpmIncludesErrors: Bool? = nil, startTime: Date? = nil,
                endTime: Date? = nil) {
        self.rpm = rpm; self.tpm = tpm; self.errorRate = errorRate; self.upstream429Count = upstream429Count
        self.upstream529Count = upstream529Count; self.opsMonitoringEnabled = opsMonitoringEnabled; self.errorsAvailable = errorsAvailable
        self.rpmIncludesErrors = rpmIncludesErrors; self.startTime = startTime; self.endTime = endTime
    }
    enum CodingKeys: String, CodingKey {
        case rpm, tpm
        case errorRate = "error_rate", upstream429Count = "upstream_429_count", upstream529Count = "upstream_529_count"
        case opsMonitoringEnabled = "ops_monitoring_enabled", errorsAvailable = "errors_available", rpmIncludesErrors = "rpm_includes_errors"
        case startTime = "start_time", endTime = "end_time"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) throws -> Bool? { try c.decodeIfPresent(Bool.self, forKey: key) }
        try self.init(rpm: c.decodeIfPresent(Double.self, forKey: .rpm), tpm: c.decodeIfPresent(Double.self, forKey: .tpm),
                      errorRate: c.decodeIfPresent(Double.self, forKey: .errorRate),
                      upstream429Count: c.decodeIfPresent(Int.self, forKey: .upstream429Count),
                      upstream529Count: c.decodeIfPresent(Int.self, forKey: .upstream529Count), opsMonitoringEnabled: flag(.opsMonitoringEnabled),
                      errorsAvailable: flag(.errorsAvailable), rpmIncludesErrors: flag(.rpmIncludesErrors),
                      startTime: c.optionalTimestamp(.startTime), endTime: c.optionalTimestamp(.endTime))
    }
}

/// `dashboard/rates?window=`: the backend accepts only these.
public enum LiveRatesWindow: String, CaseIterable, Sendable {
    case oneMinute = "1m", fiveMinutes = "5m", fifteenMinutes = "15m"
}

/// One hour bucket. `date` is the server's `YYYY-MM-DD HH:00` label without a zone; the page reads it in `HomeHourly.timezone`.
public struct HomeHourlyPoint: Decodable, Sendable, Equatable, Identifiable {
    public let date: String
    public let requests: Int
    public let totalTokens: Int
    public let actualCost: Decimal
    /// Omitted by the backend when unknown.
    public let accountCost: Decimal?
    public var id: String { date }

    public init(date: String, requests: Int = 0, totalTokens: Int = 0, actualCost: Decimal = 0, accountCost: Decimal? = nil) {
        self.date = date; self.requests = requests; self.totalTokens = totalTokens; self.actualCost = actualCost; self.accountCost = accountCost
    }
    enum CodingKeys: String, CodingKey { case date, requests; case totalTokens = "total_tokens", actualCost = "actual_cost", accountCost = "account_cost" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(date: c.decode(String.self, forKey: .date), requests: c.decodeIfPresent(Int.self, forKey: .requests) ?? 0,
                      totalTokens: c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0, actualCost: c.optionalDecimal(.actualCost) ?? 0,
                      accountCost: c.optionalDecimal(.accountCost))
    }
}

/// Hours without usage are absent from both lists.
public struct HomeHourly: Decodable, Sendable, Equatable {
    public let timezone: String?
    public let today: [HomeHourlyPoint]
    public let yesterday: [HomeHourlyPoint]

    public init(timezone: String? = nil, today: [HomeHourlyPoint] = [], yesterday: [HomeHourlyPoint] = []) {
        self.timezone = timezone; self.today = today; self.yesterday = yesterday
    }
    enum CodingKeys: String, CodingKey { case timezone, today, yesterday }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(timezone: c.decodeIfPresent(String.self, forKey: .timezone), today: c.decodeIfPresent([HomeHourlyPoint].self, forKey: .today) ?? [],
                      yesterday: c.decodeIfPresent([HomeHourlyPoint].self, forKey: .yesterday) ?? [])
    }
}

/// The last five minutes of the ops overview.
public struct HomeOps: Decodable, Sendable, Equatable {
    /// 0–100.
    public let healthScore: Int?
    /// 0–1.
    public let sla: Double?
    /// 0–1.
    public let errorRate: Double?
    public let upstream429Count: Int?
    public let upstream529Count: Int?
    public let requestCountTotal: Int?
    public let tokenConsumed: Int?

    public init(healthScore: Int? = nil, sla: Double? = nil, errorRate: Double? = nil, upstream429Count: Int? = nil, upstream529Count: Int? = nil,
                requestCountTotal: Int? = nil, tokenConsumed: Int? = nil) {
        self.healthScore = healthScore; self.sla = sla; self.errorRate = errorRate; self.upstream429Count = upstream429Count
        self.upstream529Count = upstream529Count; self.requestCountTotal = requestCountTotal; self.tokenConsumed = tokenConsumed
    }
    enum CodingKeys: String, CodingKey {
        case sla
        case healthScore = "health_score", errorRate = "error_rate", upstream429Count = "upstream_429_count", upstream529Count = "upstream_529_count"
        case requestCountTotal = "request_count_total", tokenConsumed = "token_consumed"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) throws -> Int? { try c.decodeIfPresent(Int.self, forKey: key) }
        try self.init(healthScore: count(.healthScore), sla: c.decodeIfPresent(Double.self, forKey: .sla),
                      errorRate: c.decodeIfPresent(Double.self, forKey: .errorRate), upstream429Count: count(.upstream429Count),
                      upstream529Count: count(.upstream529Count), requestCountTotal: count(.requestCountTotal), tokenConsumed: count(.tokenConsumed))
    }
}

/// Firing events, silenced ones included. One unreadable `top` event fails the block.
public struct HomeAlerts: Decodable, Sendable, Equatable {
    /// `top.count` when missing, so a listed event is never counted as calm.
    public let firingCount: Int
    /// The backend always sends P0–P3 (possibly 0) and may add other levels.
    public let bySeverity: [String: Int]
    /// The newest firing events (at most five), full `OpsAlertEvent`s.
    public let top: [AlertEvent]

    public init(firingCount: Int = 0, bySeverity: [String: Int] = [:], top: [AlertEvent] = []) {
        self.firingCount = firingCount; self.bySeverity = bySeverity; self.top = top
    }
    public func count(severity: String) -> Int { bySeverity[severity] ?? 0 }
    enum CodingKeys: String, CodingKey { case top; case firingCount = "firing_count", bySeverity = "by_severity" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let top = try c.decodeIfPresent([AlertEvent].self, forKey: .top) ?? []
        try self.init(firingCount: c.decodeIfPresent(Int.self, forKey: .firingCount) ?? top.count,
                      bySeverity: c.decodeIfPresent([String: Int].self, forKey: .bySeverity) ?? [:], top: top)
    }
}

/// Channel monitor rows by current state; stale and unknown states are already in `unknown`.
public struct HomeChannels: Decodable, Sendable, Equatable {
    public let total: Int
    public let healthy: Int
    public let warning: Int
    public let critical: Int
    public let unknown: Int
    public let coverageState: String?
    public let collectorState: String?

    public init(total: Int = 0, healthy: Int = 0, warning: Int = 0, critical: Int = 0, unknown: Int = 0, coverageState: String? = nil,
                collectorState: String? = nil) {
        self.total = total; self.healthy = healthy; self.warning = warning; self.critical = critical; self.unknown = unknown
        self.coverageState = coverageState; self.collectorState = collectorState
    }
    enum CodingKeys: String, CodingKey {
        case total, healthy, warning, critical, unknown
        case coverageState = "coverage_state", collectorState = "collector_state"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) throws -> Int { try c.decodeIfPresent(Int.self, forKey: key) ?? 0 }
        try self.init(total: count(.total), healthy: count(.healthy), warning: count(.warning), critical: count(.critical), unknown: count(.unknown),
                      coverageState: c.decodeIfPresent(String.self, forKey: .coverageState),
                      collectorState: c.decodeIfPresent(String.self, forKey: .collectorState))
    }
}

/// `GET admin/dashboard/home` (10 §1.2). A block the reply leaves out reads as error, so with `include` read only the blocks you
/// asked for (`degradedSections(among:)`). `generatedAt` is the old value in a 304 reuse: “更新于” uses the local receive time.
public struct DashboardHome: Decodable, Sendable, Equatable {
    public let generatedAt: Date?
    public let stats: HomeSection<HomeStats>
    public let rates: HomeSection<LiveRates>
    public let hourly: HomeSection<HomeHourly>
    public let ops: HomeSection<HomeOps>
    public let alerts: HomeSection<HomeAlerts>
    /// S0-17's summary: no `platforms`, with `accounts_truncated`.
    public let availability: HomeSection<AccountStatusSummary>
    public let channels: HomeSection<HomeChannels>

    public init(generatedAt: Date? = nil, stats: HomeSection<HomeStats> = .missing, rates: HomeSection<LiveRates> = .missing,
                hourly: HomeSection<HomeHourly> = .missing, ops: HomeSection<HomeOps> = .missing, alerts: HomeSection<HomeAlerts> = .missing,
                availability: HomeSection<AccountStatusSummary> = .missing, channels: HomeSection<HomeChannels> = .missing) {
        self.generatedAt = generatedAt; self.stats = stats; self.rates = rates; self.hourly = hourly; self.ops = ops; self.alerts = alerts
        self.availability = availability; self.channels = channels
    }
    enum CodingKeys: String, CodingKey {
        case stats, rates, hourly, ops, alerts, availability, channels
        case generatedAt = "generated_at"
    }
    /// Only a reply that is not an object fails; every block decodes on its own.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(generatedAt: c.optionalTimestamp(.generatedAt), stats: Self.section(c, .stats), rates: Self.section(c, .rates),
                      hourly: Self.section(c, .hourly), ops: Self.section(c, .ops), alerts: Self.section(c, .alerts),
                      availability: Self.section(c, .availability), channels: Self.section(c, .channels))
    }
    private static func section<Value: Decodable & Sendable>(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> HomeSection<Value> {
        (try? c.decodeIfPresent(HomeSection<Value>.self, forKey: key)) ?? .missing
    }

    public func status(of key: HomeSectionKey) -> HomeSectionStatus {
        switch key {
        case .stats: stats.status
        case .rates: rates.status
        case .hourly: hourly.status
        case .ops: ops.status
        case .alerts: alerts.status
        case .availability: availability.status
        case .channels: channels.status
        }
    }
    /// Blocks that failed or timed out, in `keys` order; disabled does not count (the backend's `Degraded()`).
    public func degradedSections(among keys: [HomeSectionKey] = HomeSectionKey.allCases) -> [HomeSectionKey] {
        keys.filter { [HomeSectionStatus.error, .timeout].contains(status(of: $0)) }
    }
}

/// A parameter the site refused is dropped and the read sent once more (10 §1.5, S1D1-25). Only the path and the reason are
/// logged, never the zone or the query.
enum DashboardLog {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "dashboard")
    #endif
    static func resending(_ path: String, without parameter: String, reason: String) {
        #if canImport(os)
        logger.notice("\(path, privacy: .public) 400 \(reason, privacy: .public): resent without \(parameter, privacy: .public)")
        #endif
    }
}

extension APIClient {
    /// 10 §1.2: `timezone` is the server zone's raw identifier (it only buckets `hourly`). ETag / 304 are handled by the
    /// conditional cache (R08); `noCache` adds `nocache=1`, which also gets its own cache entry. 10 §1.5: a 400 INVALID_TIMEZONE
    /// or INVALID_INCLUDE drops that parameter and sends once more.
    public func dashboardHome(timezone: ServerTimeZone, include: [HomeSectionKey]? = nil, noCache: Bool = false) async throws -> DashboardHome {
        let path = "admin/dashboard/home"
        var zone: String? = timezone.identifier, sections = HomeSectionKey.includeValue(include)
        // Each resend drops one parameter for good, so there are at most three attempts.
        while true {
            do {
                return try await request(path, query: Self.homeQuery(zone: zone, include: sections, noCache: noCache), timeout: RequestTimeout.home)
            } catch let error as APIError where error.statusCode == 400 {
                switch error.reason {
                case "INVALID_TIMEZONE"? where zone != nil:
                    DashboardLog.resending(path, without: "timezone", reason: "INVALID_TIMEZONE"); zone = nil
                case "INVALID_INCLUDE"? where sections != nil:
                    DashboardLog.resending(path, without: "include", reason: "INVALID_INCLUDE"); sections = nil
                default: throw error
                }
            }
        }
    }
    private static func homeQuery(zone: String?, include: String?, noCache: Bool) -> [URLQueryItem] {
        var items = [URLQueryItem]()
        if let zone { items.append(URLQueryItem(name: "timezone", value: zone)) }
        if let include { items.append(URLQueryItem(name: "include", value: include)) }
        if noCache { items.append(URLQueryItem(name: "nocache", value: "1")) }
        return items
    }

    /// The fallback for the `rates` block. No ETag; an ordinary read (00 §2.3 has no row for it).
    public func dashboardRates(window: LiveRatesWindow = .fiveMinutes) async throws -> LiveRates {
        try await request("admin/dashboard/rates", query: [URLQueryItem(name: "window", value: window.rawValue)], timeout: RequestTimeout.read)
    }
}
