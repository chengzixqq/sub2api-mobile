import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `GET admin/channel-monitor-v2/overview` (10 §5.2). Every field may be missing or malformed; an unreadable item or bucket is
/// skipped instead of failing the page.
public struct ChannelOverview: Decodable, Sendable, Equatable {
    /// What the server accepts; without `range` it answers for 24h (appendix B L11), so a range is always sent.
    public static let ranges: Set<String> = ["90m", "24h", "7d", "30d"]
    public let refreshIntervalSeconds: Int?
    public let coverage: ChannelCoverage?
    public let items: [ChannelItem]

    public init(refreshIntervalSeconds: Int? = nil, coverage: ChannelCoverage? = nil, items: [ChannelItem] = []) {
        self.refreshIntervalSeconds = refreshIntervalSeconds; self.coverage = coverage; self.items = items
    }
    enum CodingKeys: String, CodingKey { case coverage, items; case refreshIntervalSeconds = "refresh_interval_seconds" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(refreshIntervalSeconds: c.lenientValue(.refreshIntervalSeconds), coverage: c.lenientValue(.coverage),
                  items: c.lossyList(ChannelItem.self, .items))
    }
}

public struct ChannelCoverage: Decodable, Sendable, Equatable {
    public let state: String?
    public let collectorState: String?

    public init(state: String? = nil, collectorState: String? = nil) { self.state = state; self.collectorState = collectorState }
    enum CodingKeys: String, CodingKey { case state; case collectorState = "collector_state" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(state: c.lenientValue(.state), collectorState: c.lenientValue(.collectorState))
    }
}

/// One group's channel. `groupID` is 0 when the server left it out.
public struct ChannelItem: Identifiable, Decodable, Sendable, Equatable {
    public let platform: String
    public let groupID: Int
    public let groupName: String?
    public let currentStatus: ChannelCurrentStatus?
    public let metrics: ChannelMetrics?
    public let buckets: [ChannelBucket]
    public var id: Int { groupID }

    public init(platform: String = "", groupID: Int = 0, groupName: String? = nil, currentStatus: ChannelCurrentStatus? = nil,
                metrics: ChannelMetrics? = nil, buckets: [ChannelBucket] = []) {
        self.platform = platform; self.groupID = groupID; self.groupName = groupName; self.currentStatus = currentStatus
        self.metrics = metrics; self.buckets = buckets
    }
    enum CodingKeys: String, CodingKey {
        case platform, metrics, buckets
        case groupID = "group_id", groupName = "group_name", currentStatus = "current_status"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(platform: c.lenientString(.platform), groupID: c.lenientValue(.groupID) ?? 0, groupName: c.lenientValue(.groupName),
                  currentStatus: c.lenientValue(.currentStatus), metrics: c.lenientValue(.metrics), buckets: c.lossyList(ChannelBucket.self, .buckets))
    }
}

/// `state`: healthy / warning / critical / unknown / stale; `reason` such as recent_traffic, no_samples, collection_unavailable.
public struct ChannelCurrentStatus: Decodable, Sendable, Equatable {
    public let state: String?
    public let reason: String?
    public let updatedAt: Date?

    public init(state: String? = nil, reason: String? = nil, updatedAt: Date? = nil) { self.state = state; self.reason = reason; self.updatedAt = updatedAt }
    enum CodingKeys: String, CodingKey { case state, reason; case updatedAt = "updated_at" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(state: c.lenientValue(.state), reason: c.lenientValue(.reason), updatedAt: try? c.optionalTimestamp(.updatedAt))
    }
}

/// Rates are 0–1 ratios; `channelErrors` already counts the unknown requests.
public struct ChannelMetrics: Decodable, Sendable, Equatable {
    public let reliabilityRate: Double?
    public let successRate: Double?
    public let requestCount: Int?
    public let channelErrors: Int?
    public let successRequests: Int?
    /// no_samples / insufficient / sufficient.
    public let sampleState: String?
    public let ttft: ChannelLatency?

    public init(reliabilityRate: Double? = nil, successRate: Double? = nil, requestCount: Int? = nil, channelErrors: Int? = nil,
                successRequests: Int? = nil, sampleState: String? = nil, ttft: ChannelLatency? = nil) {
        self.reliabilityRate = reliabilityRate; self.successRate = successRate; self.requestCount = requestCount; self.channelErrors = channelErrors
        self.successRequests = successRequests; self.sampleState = sampleState; self.ttft = ttft
    }
    enum CodingKeys: String, CodingKey {
        case ttft
        case reliabilityRate = "reliability_rate", successRate = "success_rate", requestCount = "request_count", channelErrors = "channel_errors"
        case successRequests = "success_requests", sampleState = "sample_state"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(reliabilityRate: c.lenientValue(.reliabilityRate), successRate: c.lenientValue(.successRate), requestCount: c.lenientValue(.requestCount),
                  channelErrors: c.lenientValue(.channelErrors), successRequests: c.lenientValue(.successRequests),
                  sampleState: c.lenientValue(.sampleState), ttft: c.lenientValue(.ttft))
    }
}

public struct ChannelLatency: Decodable, Sendable, Equatable {
    public let p50Ms: Double?

    public init(p50Ms: Double? = nil) { self.p50Ms = p50Ms }
    enum CodingKeys: String, CodingKey { case p50Ms = "p50_ms" }
    public init(from decoder: any Decoder) throws { self.init(p50Ms: try decoder.container(keyedBy: CodingKeys.self).lenientValue(.p50Ms)) }
}

/// A 5-minute bucket; `reliability` is `health.reliability`.
public struct ChannelBucket: Decodable, Sendable, Equatable {
    public let bucketStart: Date?
    public let reliability: String?
    public let metrics: ChannelMetrics?

    public init(bucketStart: Date? = nil, reliability: String? = nil, metrics: ChannelMetrics? = nil) {
        self.bucketStart = bucketStart; self.reliability = reliability; self.metrics = metrics
    }
    enum CodingKeys: String, CodingKey { case health, metrics; case bucketStart = "bucket_start" }
    enum HealthKeys: String, CodingKey { case reliability }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let health = try? c.nestedContainer(keyedBy: HealthKeys.self, forKey: .health)
        self.init(bucketStart: try? c.optionalTimestamp(.bucketStart), reliability: health?.lenientValue(.reliability),
                  metrics: c.lenientValue(.metrics))
    }
}

extension APIClient {
    /// 10 §5.2: behind the channel-monitor feature switch only (403 CHANNEL_MONITOR_DISABLED), not the ops one; no ETag.
    /// `refresh` asks the server to recompute (pull to refresh).
    public func channelOverview(range: String = "90m", refresh: Bool = false) async throws -> ChannelOverview {
        let range = range.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ChannelOverview.ranges.contains(range) else { throw APIError(kind: .validation, message: "无效的时间范围。") }
        let query = [URLQueryItem(name: "range", value: range)] + (refresh ? [URLQueryItem(name: "refresh", value: "true")] : [])
        return try await request("admin/channel-monitor-v2/overview", query: query)
    }
}

/// 10 §5.3 status words. Declaration order is the list order and “worst first”: critical, warning, then stale / unknown /
/// anything else, then healthy.
public enum ChannelStatus: Sendable, Equatable, Comparable, CaseIterable {
    case unavailable, degraded, unknown, available

    public init(state: String?) {
        switch state?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "healthy": self = .available
        case "warning": self = .degraded
        case "critical": self = .unavailable
        default: self = .unknown
        }
    }
    public var label: String {
        switch self {
        case .unavailable: "不可用"
        case .degraded: "性能下降"
        case .unknown: "未知"
        case .available: "可用"
        }
    }
    public var tone: Tone {
        switch self {
        case .unavailable: .critical
        case .degraded: .caution
        case .unknown: .neutral
        case .available: .ok
        }
    }
}

/// The four tiles of 10 §5.3; also the home fallback's channel counts.
public struct ChannelCounts: Sendable, Equatable {
    public let available: Int
    public let degraded: Int
    public let unavailable: Int
    public let unknown: Int
    public var total: Int { available + degraded + unavailable + unknown }

    public init(available: Int = 0, degraded: Int = 0, unavailable: Int = 0, unknown: Int = 0) {
        self.available = available; self.degraded = degraded; self.unavailable = unavailable; self.unknown = unknown
    }
}

/// One platform's channels, for the alert detail's platform row (10 §3.3).
public struct ChannelPlatformSummary: Sendable, Equatable {
    public let worst: ChannelStatus
    public let channelCount: Int
    public let lowestReliability: Double?

    public init(worst: ChannelStatus, channelCount: Int, lowestReliability: Double?) {
        self.worst = worst; self.channelCount = channelCount; self.lowestReliability = lowestReliability
    }
}

/// 10 §5.3 field → display rules, shared by the monitor channels segment, the home fallback and the alert detail.
public enum ChannelPresentation {
    public static let stripLength = 18
    public static let coverageHint = "渠道数据采集延迟，显示的可能不是最新状态"
    public static let defaultRefreshInterval: TimeInterval = 60
    /// The server's own bounds for `refresh_interval_seconds`.
    public static let refreshBounds: ClosedRange<Int> = 30...300

    public static func status(_ item: ChannelItem) -> ChannelStatus { ChannelStatus(state: item.currentStatus?.state) }
    public static func counts(_ items: [ChannelItem]) -> ChannelCounts {
        let statuses = items.map(status)
        func count(_ wanted: ChannelStatus) -> Int { statuses.filter { $0 == wanted }.count }
        return ChannelCounts(available: count(.available), degraded: count(.degraded), unavailable: count(.unavailable), unknown: count(.unknown))
    }
    /// Worst first; within a status by title (case-insensitive, digits as numbers), then by group id.
    public static func sorted(_ items: [ChannelItem]) -> [ChannelItem] {
        items.map { (item: $0, status: status($0), title: title($0)) }.sorted { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status < rhs.status }
            let order = lhs.title.compare(rhs.title, options: [.caseInsensitive, .numeric])
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.item.groupID < rhs.item.groupID
        }.map(\.item)
    }
    public static func title(_ item: ChannelItem) -> String {
        let name = item.groupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "分组 #\(item.groupID)" : name
    }
    public static func reliabilityText(_ item: ChannelItem) -> String { DisplayFormat.ratioPercent(item.metrics?.reliabilityRate) }
    /// channel_errors ÷ (success_requests + channel_errors); without those counts, 1 − reliability_rate.
    public static func errorRate(_ metrics: ChannelMetrics?) -> Double? {
        guard let metrics else { return nil }
        if let errors = metrics.channelErrors, let successes = metrics.successRequests, errors + successes > 0 {
            return Double(errors) / Double(errors + successes)
        }
        return metrics.reliabilityRate.map { 1 - $0 }
    }
    /// The latest 18 buckets, oldest on the left and padded with empty cells there; only healthy / warning / critical are filled.
    public static func strip(_ buckets: [ChannelBucket]) -> [Tone?] {
        let cells = buckets.enumerated().sorted { lhs, rhs in
            switch (lhs.element.bucketStart, rhs.element.bucketStart) {
            case let (left?, right?) where left != right: return left < right
            case (nil, _?): return true
            case (_?, nil): return false
            default: return lhs.offset < rhs.offset
            }
        }.suffix(stripLength).map { cell($0.element) }
        return Array(repeating: nil, count: stripLength - cells.count) + cells
    }
    /// The row's second line. Collection and staleness problems come first, then the measured state, then the sample notes.
    public static func note(_ item: ChannelItem) -> String {
        let reason = normalized(item.currentStatus?.reason), sample = normalized(item.metrics?.sampleState)
        if reason == "collection_unavailable" { return "采集不可用" }
        if normalized(item.currentStatus?.state) == "stale" { return "数据已过期" }
        switch status(item) {
        case .available, .degraded: return reliabilityNote(item)
        case .unavailable: return "错误率 \(DisplayFormat.ratioPercent(errorRate(item.metrics))) · \(firstTokenNote(item))"
        case .unknown: break
        }
        if sample == "no_samples" || reason == "no_samples" { return "无样本" }
        if sample == "insufficient" || reason == "insufficient_samples" { return "样本不足" }
        return reliabilityNote(item)
    }
    public static func showsCoverageHint(_ coverage: ChannelCoverage?) -> Bool {
        guard let coverage else { return false }
        let collector = normalized(coverage.collectorState)
        return (collector != nil && collector != "healthy") || normalized(coverage.state) == "stale"
    }
    /// Channels whose platform matches ignoring case and spaces; nil when there are none.
    public static func platformSummary(_ items: [ChannelItem], platform: String) -> ChannelPlatformSummary? {
        guard let wanted = normalized(platform) else { return nil }
        let matching = items.filter { normalized($0.platform) == wanted }
        guard let worst = matching.map(status).min() else { return nil }
        return ChannelPlatformSummary(worst: worst, channelCount: matching.count, lowestReliability: matching.compactMap { $0.metrics?.reliabilityRate }.min())
    }
    public static func platformNote(_ summary: ChannelPlatformSummary?) -> String {
        guard let summary else { return "没有这个平台的渠道探测" }
        return "\(summary.channelCount) 个分组渠道 · 最低可用率 \(DisplayFormat.ratioPercent(summary.lowestReliability))"
    }
    /// Polling interval: missing or non-positive is 60 seconds, otherwise clamped to 30–300.
    public static func refreshInterval(_ seconds: Int?) -> TimeInterval {
        guard let seconds, seconds > 0 else { return defaultRefreshInterval }
        return TimeInterval(min(max(seconds, refreshBounds.lowerBound), refreshBounds.upperBound))
    }

    private static func cell(_ bucket: ChannelBucket) -> Tone? {
        let status = ChannelStatus(state: bucket.reliability)
        return status == .unknown ? nil : status.tone
    }
    private static func reliabilityNote(_ item: ChannelItem) -> String { "可用率 \(reliabilityText(item)) · \(firstTokenNote(item))" }
    /// Millisecond reading (R10, 00 §6.2): 850ms, 1.4s.
    private static func firstTokenNote(_ item: ChannelItem) -> String { "首字 \(DisplayFormat.duration(item.metrics?.ttft?.p50Ms, style: .millis))" }
    private static func normalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text?.isEmpty == false ? text : nil
    }
}

extension KeyedDecodingContainer {
    /// Missing, null or of another type is nil. Shared with OpsMonitoring.swift.
    func lenientValue<Value: Decodable>(_ key: Key) -> Value? { try? decodeIfPresent(Value.self, forKey: key) }
}
