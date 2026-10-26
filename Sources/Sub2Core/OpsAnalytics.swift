import Foundation

// MARK: - 运维图表共用的范围与筛选（40 §1.2，S4-10）

/// The range and filters of every `ops/dashboard/*` chart (40 §1.2). Whether the site may filter by model is passed by the
/// caller, so a value also serves as a cache key.
public struct OpsQuery: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var groupID: Int?
    public var model: String?
    public var modelSource: ModelSource?

    public init(start: Date, end: Date, groupID: Int? = nil, model: String? = nil, modelSource: ModelSource? = nil) {
        self.start = start; self.end = end; self.groupID = groupID; self.model = model; self.modelSource = modelSource
    }

    /// UTC `Z` range and `group_id`; `model` + `model_source` only with the capability and a requested / upstream source (the
    /// server answers 400 for mapping, even without a model). Never `mode` (unread by the server) or `timezone`.
    public func queryItems(supportsModelFilter: Bool) -> [URLQueryItem] {
        var items = ServerTime.timeRangeItems(start: start, end: end)
        if let groupID { items.append(URLQueryItem(name: "group_id", value: String(groupID))) }
        if let name = appliedModel(supportsModelFilter: supportsModelFilter) {
            items += [URLQueryItem(name: "model", value: name), URLQueryItem(name: "model_source", value: (modelSource ?? .requested).rawValue)]
        }
        return items
    }

    /// A model filter is set but cannot be sent (mapping or no capability): the card header says it shows the whole site.
    /// False without a model filter.
    public func isSiteWide(supportsModelFilter: Bool) -> Bool {
        trimmedModel != nil && appliedModel(supportsModelFilter: supportsModelFilter) == nil
    }

    /// The server answers both cases with a 400 without a reason; every ops request checks this before sending.
    public func validate() throws {
        guard start < end, (groupID ?? 1) > 0 else { throw APIError(kind: .validation, message: "请选择有效的时间范围与分组。") }
    }

    private var trimmedModel: String? {
        guard let name = model?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }
    private func appliedModel(supportsModelFilter: Bool) -> String? {
        supportsModelFilter && modelSource != .mapping ? trimmedModel : nil
    }
}

extension OpsQuery {
    /// 40 §1.4: the last `hours` ending at `now` floored to a whole minute. Pass `serverClock.now()` (S0-07).
    public static func trailingWindow(hours: Int, endingAt now: Date, groupID: Int? = nil, model: String? = nil,
                                      modelSource: ModelSource? = nil) -> OpsQuery {
        let end = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        return OpsQuery(start: end.addingTimeInterval(-Double(hours) * 3_600), end: end, groupID: groupID, model: model, modelSource: modelSource)
    }
}

// MARK: - 运维趋势的桶长（40 §1.4、§2.2）

/// The bucket of every ops trend; the server picks it from the window length.
public enum OpsBucket: String, CaseIterable, Sendable {
    case minute = "1m", fiveMinutes = "5m", hour = "1h"
    public var seconds: TimeInterval {
        switch self { case .minute: 60; case .fiveMinutes: 300; case .hour: 3_600 }
    }
    public var label: String {
        switch self { case .minute: "1 分钟"; case .fiveMinutes: "5 分钟"; case .hour: "1 小时" }
    }
    /// The server's pickThroughputBucketSeconds: up to 2 hours 60 seconds, up to 24 hours 300 seconds, longer 3600 seconds.
    public static func forWindow(_ window: TimeInterval) -> OpsBucket {
        if window <= 7_200 { return .minute }
        return window <= 86_400 ? .fiveMinutes : .hour
    }
    /// A known label wins; a missing or unknown one is derived from the window.
    public static func resolve(_ label: String?, window: TimeInterval) -> OpsBucket {
        label.flatMap(OpsBucket.init(rawValue:)) ?? forWindow(window)
    }
    /// Bucket starts on whole multiples of the UTC epoch, as the server fills empty buckets: the first may begin before `start`
    /// and the last end after `end`.
    public func starts(from start: Date, to end: Date) -> [Date] {
        guard start < end else { return [] }
        let first = (start.timeIntervalSince1970 / seconds).rounded(.down)
        let last = (end.timeIntervalSince1970 / seconds).rounded(.up) - 1
        return stride(from: first, through: last, by: 1).map { Date(timeIntervalSince1970: $0 * seconds) }
    }
}

// MARK: - 运维图表模型（40 §2.2、§2.3，S4-11）

/// `ops/dashboard/latency-histogram`: successful requests only, in six fixed buckets.
public struct OpsLatencyHistogram: Decodable, Sendable, Equatable {
    /// Not `Range`, which would shadow Swift.Range inside the type.
    public enum BucketRange: String, CaseIterable, Sendable {
        case under100 = "0-100ms", to200 = "100-200ms", to500 = "200-500ms", to1000 = "500-1000ms", to2000 = "1000-2000ms", over2000 = "2000ms+"
        /// 40 §2.3 column names.
        public var label: String {
            switch self {
            case .under100: "<100ms"
            case .to200: "100–200"
            case .to500: "200–500"
            case .to1000: "0.5–1s"
            case .to2000: "1–2s"
            case .over2000: "≥2s"
            }
        }
    }
    public struct Bucket: Sendable, Equatable, Identifiable {
        public let range: BucketRange
        public let count: Int
        public var id: BucketRange { range }
        public init(range: BucketRange, count: Int) { self.range = range; self.count = count }
    }

    public let totalRequests: Int
    /// Always six in `BucketRange.allCases` order: a missing range is 0, a repeated one is added up, an unknown one is dropped.
    public let buckets: [Bucket]

    /// `totalRequests` defaults to the sum of the counts, as the server computes it.
    public init(totalRequests: Int? = nil, buckets: [Bucket]) {
        let sums = Dictionary(buckets.map { ($0.range, $0.count) }, uniquingKeysWith: +)
        let fixed = BucketRange.allCases.map { Bucket(range: $0, count: sums[$0] ?? 0) }
        self.buckets = fixed
        self.totalRequests = totalRequests ?? fixed.reduce(0) { $0 + $1.count }
    }
    enum CodingKeys: String, CodingKey { case totalRequests = "total_requests", buckets }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let wire = try c.decodeIfPresent([WireBucket].self, forKey: .buckets) ?? []
        self.init(totalRequests: try c.optionalNonNegative(.totalRequests), buckets: wire.compactMap { bucket in
            bucket.range.flatMap(BucketRange.init(rawValue:)).map { Bucket(range: $0, count: bucket.count) }
        })
    }
    private struct WireBucket: Decodable {
        let range: String?
        let count: Int
        enum CodingKeys: CodingKey { case range, count }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            range = try? c.decodeIfPresent(String.self, forKey: .range)
            count = try c.nonNegative(.count)
        }
    }

    /// “这个范围内没有成功请求”.
    public var isEmpty: Bool { totalRequests == 0 }
    /// The percentage above a bar; nil without requests.
    public func share(_ bucket: Bucket) -> Double? {
        totalRequests > 0 ? Double(bucket.count) / Double(totalRequests) : nil
    }
    /// Bar height relative to the tallest bucket.
    public func height(_ bucket: Bucket) -> Double {
        let tallest = buckets.map(\.count).max() ?? 0
        return tallest > 0 ? Double(bucket.count) / Double(tallest) : 0
    }
}

/// The six counts of an error-trend point. `sla + businessLimited == total` holds for every point; the upstream counts also
/// include failures a retry recovered, so they are not part of `total` (U34).
public struct OpsErrorCounts: Sendable, Equatable {
    /// `error_count_total`
    public let total: Int
    /// `error_count_sla`
    public let sla: Int
    /// `business_limited_count`
    public let businessLimited: Int
    public let upstream429: Int
    public let upstream529: Int
    /// `upstream_error_count_excl_429_529`
    public let upstreamOther: Int
    public static let zero = OpsErrorCounts()

    public init(total: Int = 0, sla: Int = 0, businessLimited: Int = 0, upstream429: Int = 0, upstream529: Int = 0, upstreamOther: Int = 0) {
        self.total = total; self.sla = sla; self.businessLimited = businessLimited
        self.upstream429 = upstream429; self.upstream529 = upstream529; self.upstreamOther = upstreamOther
    }
    public static func + (lhs: OpsErrorCounts, rhs: OpsErrorCounts) -> OpsErrorCounts {
        OpsErrorCounts(total: lhs.total + rhs.total, sla: lhs.sla + rhs.sla, businessLimited: lhs.businessLimited + rhs.businessLimited,
                       upstream429: lhs.upstream429 + rhs.upstream429, upstream529: lhs.upstream529 + rhs.upstream529,
                       upstreamOther: lhs.upstreamOther + rhs.upstreamOther)
    }
}

/// `ops/dashboard/error-trend`. Bars stack only SLA errors and business limits; the upstream counts get a line of their own (U34).
public struct OpsErrorTrend: Sendable, Equatable {
    /// 40 §2.3: 60-second buckets add up per 5 minutes, 300-second ones per hour, 3600-second ones per site day.
    public enum Grouping: Sendable, Equatable {
        case fiveMinutes, hour, day
        public init(bucket: OpsBucket) {
            switch bucket {
            case .minute: self = .fiveMinutes
            case .fiveMinutes: self = .hour
            case .hour: self = .day
            }
        }
    }
    public struct Point: Decodable, Sendable, Equatable, Identifiable {
        public let start: Date
        public let counts: OpsErrorCounts
        public var id: Date { start }
        public init(start: Date, counts: OpsErrorCounts) { self.start = start; self.counts = counts }
        enum CodingKeys: String, CodingKey {
            case start = "bucket_start", total = "error_count_total", sla = "error_count_sla", businessLimited = "business_limited_count"
            case upstream429 = "upstream_429_count", upstream529 = "upstream_529_count", upstreamOther = "upstream_error_count_excl_429_529"
        }
        /// As PerformanceTrend: an unreadable `bucket_start` or a negative count fails; a missing count is 0.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let start = try c.optionalTimestamp(.start) else {
                throw DecodingError.dataCorruptedError(forKey: .start, in: c, debugDescription: "Invalid error-trend bucket_start")
            }
            let counts = OpsErrorCounts(total: try c.nonNegative(.total), sla: try c.nonNegative(.sla),
                                        businessLimited: try c.nonNegative(.businessLimited), upstream429: try c.nonNegative(.upstream429),
                                        upstream529: try c.nonNegative(.upstream529), upstreamOther: try c.nonNegative(.upstreamOther))
            self.init(start: start, counts: counts)
        }
    }
    public struct Bar: Sendable, Equatable, Identifiable {
        public let start: Date
        public let end: Date
        public let counts: OpsErrorCounts
        public var id: Date { start }
        public init(start: Date, end: Date, counts: OpsErrorCounts) { self.start = start; self.end = end; self.counts = counts }
    }
    /// The wire body; a missing or unknown `bucket` is resolved from the requested window.
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

    public let bucket: OpsBucket
    /// Oldest first; a repeated `bucket_start` keeps the last point.
    public let points: [Point]
    /// The requested window, written by the request.
    public let windowStart: Date
    public let windowEnd: Date

    public init(bucket: OpsBucket, points: [Point], windowStart: Date, windowEnd: Date) {
        let unique = Dictionary(points.map { ($0.start, $0) }, uniquingKeysWith: { _, last in last })
        self.bucket = bucket; self.points = unique.values.sorted { $0.start < $1.start }
        self.windowStart = windowStart; self.windowEnd = windowEnd
    }

    public var grouping: Grouping { Grouping(bucket: bucket) }
    /// The three numbers, the legend and the upstream line.
    public var totals: OpsErrorCounts { points.reduce(.zero) { $0 + $1.counts } }
    /// “这个范围内没有错误”.
    public var isEmpty: Bool { totals.total == 0 }
    /// Points added up per `grouping`, oldest first. Five minutes are whole multiples of the UTC epoch, which every zone offset in
    /// use (a multiple of 15 minutes) shares; hours and days follow the site calendar, so a daylight-saving day has 23 or 25 hours.
    public func bars(in zone: ServerTimeZone) -> [Bar] {
        let calendar = zone.calendar
        let groups = Dictionary(grouping: points) { interval(containing: $0.start, calendar: calendar) }
        return groups.map { interval, members in
            Bar(start: interval.start, end: interval.end, counts: members.reduce(.zero) { $0 + $1.counts })
        }.sorted { $0.start < $1.start }
    }
    private func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        switch grouping {
        case .fiveMinutes:
            let length = OpsBucket.fiveMinutes.seconds
            return DateInterval(start: Date(timeIntervalSince1970: (date.timeIntervalSince1970 / length).rounded(.down) * length), duration: length)
        case .hour: return calendar.dateInterval(of: .hour, for: date) ?? DateInterval(start: date, duration: OpsBucket.hour.seconds)
        case .day: return calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
        }
    }
}

/// `ops/dashboard/error-distribution`: at most 20 status codes, and `total` is the sum of those rows.
public struct OpsErrorDistribution: Decodable, Sendable, Equatable {
    public struct Item: Decodable, Sendable, Equatable, Identifiable {
        /// The upstream status, else the client status, else 0.
        public let statusCode: Int
        public let total: Int
        public let sla: Int
        public let businessLimited: Int
        public var id: Int { statusCode }
        public init(statusCode: Int, total: Int, sla: Int, businessLimited: Int) {
            self.statusCode = statusCode; self.total = total; self.sla = sla; self.businessLimited = businessLimited
        }
        enum CodingKeys: String, CodingKey { case statusCode = "status_code", total, sla, businessLimited = "business_limited" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(statusCode: try c.decode(Int.self, forKey: .statusCode), total: try c.nonNegative(.total), sla: try c.nonNegative(.sla),
                      businessLimited: try c.nonNegative(.businessLimited))
        }
    }
    /// The two parts of a row's bar as fractions of the first row's total.
    public struct BarLength: Sendable, Equatable {
        public let sla: Double
        public let businessLimited: Double
        public init(sla: Double, businessLimited: Double) { self.sla = sla; self.businessLimited = businessLimited }
    }

    public let total: Int
    /// Largest total first; equal totals by status code.
    public let items: [Item]

    /// `total` defaults to the sum of the rows, as the server computes it.
    public init(total: Int? = nil, items: [Item]) {
        self.items = items.sorted { $0.total != $1.total ? $0.total > $1.total : $0.statusCode < $1.statusCode }
        self.total = total ?? items.reduce(0) { $0 + $1.total }
    }
    enum CodingKeys: CodingKey { case total, items }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(total: try c.optionalNonNegative(.total), items: try c.decodeIfPresent([Item].self, forKey: .items) ?? [])
    }

    /// “这个范围内没有错误”.
    public var isEmpty: Bool { total == 0 }
    /// The first row, for the tile's “47% / 429 占错误”.
    public var leading: Item? { items.first }
    public func share(_ item: Item) -> Double? { total > 0 ? Double(item.total) / Double(total) : nil }
    public func barLength(_ item: Item) -> BarLength {
        guard let widest = items.first?.total, widest > 0 else { return BarLength(sla: 0, businessLimited: 0) }
        return BarLength(sla: Double(item.sla) / Double(widest), businessLimited: Double(item.businessLimited) / Double(widest))
    }
}

/// Token 请求统计's segments, sorted on the phone.
public enum OpsTokenStatsOrder: String, CaseIterable, Identifiable, Sendable {
    case requests, speed, firstToken
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .requests: "按请求"
        case .speed: "按速度"
        case .firstToken: "按首 Token"
        }
    }
    fileprivate var isAscending: Bool { self == .firstToken }
    fileprivate func value(of item: OpsTokenStats.Item) -> Double? {
        switch self {
        case .requests: Double(item.requestCount)
        case .speed: item.tokensPerSecond
        case .firstToken: item.firstTokenMs
        }
    }
}

/// Several rows added up into one speed (40 §5.2); a value is nil when no row has it.
public struct OpsTokenSpeed: Sendable, Equatable {
    public let requestCount: Int
    public let tokensPerSecond: Double?
    public let firstTokenMs: Double?
    public let durationMs: Double?
    public init(requestCount: Int, tokensPerSecond: Double?, firstTokenMs: Double?, durationMs: Double?) {
        self.requestCount = requestCount; self.tokensPerSecond = tokensPerSecond; self.firstTokenMs = firstTokenMs; self.durationMs = durationMs
    }
}

/// `ops/dashboard/openai-token-stats`, one row per `usage_logs.model` (the requested model).
public struct OpsTokenStats: Sendable, Equatable {
    public struct Item: Decodable, Sendable, Equatable, Identifiable {
        public let model: String
        public let requestCount: Int
        public let tokensPerSecond: Double?
        public let firstTokenMs: Double?
        public let totalOutputTokens: Int
        /// 0 when the server has no durations.
        public let durationMs: Double?
        public let requestsWithFirstToken: Int
        public var id: String { model }
        public init(model: String, requestCount: Int, tokensPerSecond: Double?, firstTokenMs: Double?, totalOutputTokens: Int = 0,
                    durationMs: Double?, requestsWithFirstToken: Int) {
            self.model = model; self.requestCount = requestCount; self.tokensPerSecond = tokensPerSecond; self.firstTokenMs = firstTokenMs
            self.totalOutputTokens = totalOutputTokens; self.durationMs = durationMs; self.requestsWithFirstToken = requestsWithFirstToken
        }
        enum CodingKeys: String, CodingKey {
            case model, requestCount = "request_count", tokensPerSecond = "avg_tokens_per_sec", firstTokenMs = "avg_first_token_ms"
            case totalOutputTokens = "total_output_tokens", durationMs = "avg_duration_ms", requestsWithFirstToken = "requests_with_first_token"
        }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(model: try c.decode(String.self, forKey: .model), requestCount: try c.nonNegative(.requestCount),
                      tokensPerSecond: try c.decodeIfPresent(Double.self, forKey: .tokensPerSecond),
                      firstTokenMs: try c.decodeIfPresent(Double.self, forKey: .firstTokenMs), totalOutputTokens: try c.nonNegative(.totalOutputTokens),
                      durationMs: try c.decodeIfPresent(Double.self, forKey: .durationMs),
                      requestsWithFirstToken: try c.nonNegative(.requestsWithFirstToken))
        }
    }
    struct Reply: Decodable, Sendable {
        let timeRange: String?
        let startTime: Date?
        let endTime: Date?
        let items: [Item]
        let total: Int?
        enum CodingKeys: String, CodingKey { case timeRange = "time_range", startTime = "start_time", endTime = "end_time", items, total }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            timeRange = try? c.decodeIfPresent(String.self, forKey: .timeRange)
            startTime = try c.optionalTimestamp(.startTime)
            endTime = try c.optionalTimestamp(.endTime)
            items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
            total = try c.optionalNonNegative(.total)
        }
    }
    /// 40 §2.2 asks for 100 rows, the model page for 10; the server accepts 1–100.
    static let topNRange = 1...100

    /// The server's echo: `custom`, `1d`, `15d` or `30d`.
    public let timeRange: String?
    /// The window the server used, echoed in UTC.
    public let startTime: Date?
    public let endTime: Date?
    /// Server order: most requests first, then by model name.
    public let items: [Item]
    /// Model rows before `top_n` cut them.
    public let total: Int
    /// The window actually sent; `tooLargeFallback` after the 400 retry.
    public let window: OpsTokenStatsWindow

    public init(timeRange: String? = nil, startTime: Date? = nil, endTime: Date? = nil, items: [Item], total: Int? = nil, window: OpsTokenStatsWindow) {
        self.timeRange = timeRange; self.startTime = startTime; self.endTime = endTime; self.items = items; self.total = total ?? items.count
        self.window = window
    }
    init(reply: Reply, window: OpsTokenStatsWindow) {
        self.init(timeRange: reply.timeRange, startTime: reply.startTime, endTime: reply.endTime, items: reply.items, total: reply.total,
                  window: window)
    }

    /// Request count and speed largest first, first token smallest first; nil last and ties in server order.
    public func sorted(by order: OpsTokenStatsOrder) -> [Item] {
        items.enumerated().sorted { lhs, rhs in
            Self.precedes(order.value(of: lhs.element), order.value(of: rhs.element), ascending: order.isAscending) ?? (lhs.offset < rhs.offset)
        }.map(\.element)
    }
    /// The first `limit` rows (5 on the card, 9 full screen); the filtered model's row follows when it is further down.
    public func visibleRows(_ order: OpsTokenStatsOrder, limit: Int, pinnedModel: String?) -> [Item] {
        let rows = Array(sorted(by: order).prefix(max(limit, 0)))
        guard let pinnedModel, !rows.contains(where: { $0.model == pinnedModel }),
              let pinned = items.first(where: { $0.model == pinnedModel }) else { return rows }
        return rows + [pinned]
    }
    /// The tile's “最快 · …”.
    public var fastest: Item? { sorted(by: .speed).first.flatMap { $0.tokensPerSecond == nil ? nil : $0 } }
    /// 40 §5.2: speed and duration weigh by request count, the first token by the requests that had one; a row without the value
    /// or the weight is left out. The server has no finer weight for the speed.
    public static func merged(_ items: [Item]) -> OpsTokenSpeed? {
        guard !items.isEmpty else { return nil }
        return OpsTokenSpeed(requestCount: items.reduce(0) { $0 + $1.requestCount },
                             tokensPerSecond: weightedMean(items.map { ($0.tokensPerSecond, $0.requestCount) }),
                             firstTokenMs: weightedMean(items.map { ($0.firstTokenMs, $0.requestsWithFirstToken) }),
                             durationMs: weightedMean(items.map { ($0.durationMs, $0.requestCount) }))
    }
    /// Without `ops.dashboard_model_filter` the model page looks for its own name among the rows.
    public func merged(matching model: String) -> OpsTokenSpeed? { Self.merged(items.filter { $0.model == model }) }

    private static func precedes(_ lhs: Double?, _ rhs: Double?, ascending: Bool) -> Bool? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): return lhs == rhs ? nil : (lhs < rhs) == ascending
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return nil
        }
    }
    private static func weightedMean(_ values: [(Double?, Int)]) -> Double? {
        let weighed: [(Double, Double)] = values.compactMap { value, weight in weight > 0 ? value.map { ($0 * Double(weight), Double(weight)) } : nil }
        let weight = weighed.reduce(0) { $0 + $1.1 }
        return weight > 0 ? weighed.reduce(0) { $0 + $1.0 } / weight : nil
    }
}

// MARK: Token 请求统计的窗口（40 §2.2、§2.5）

/// The page range with `ops.token_stats_custom_range`; otherwise the smallest rolling window covering the range's first site day
/// up to now.
public enum OpsTokenStatsWindow: Sendable, Equatable {
    public enum Rolling: String, CaseIterable, Sendable {
        case day = "1d", fifteenDays = "15d", thirtyDays = "30d"
        public var seconds: TimeInterval {
            switch self {
            case .day: 86_400
            case .fifteenDays: 1_296_000
            case .thirtyDays: 2_592_000
            }
        }
        /// The card header (the design's speed windows).
        public var title: String {
            switch self {
            case .day: "近 1 天"
            case .fifteenDays: "近 15 天"
            case .thirtyDays: "近 30 天"
            }
        }
    }
    case custom
    case rolling(Rolling, coversRange: Bool)

    /// The server's limit: a longer custom window is answered 400 `OPS_TIME_RANGE_TOO_LARGE` (`max_days` 31).
    public static let maxCustomSpan: TimeInterval = 31 * 86_400 + 3_600
    /// After that 400, and for a custom range over the limit.
    public static let tooLargeFallback = OpsTokenStatsWindow.rolling(.thirtyDays, coversRange: false)

    /// `now` is the server clock; the first day starts at 00:00 in `zone`.
    public static func select(start: Date, end: Date, now: Date, zone: ServerTimeZone, supportsCustomRange: Bool) -> OpsTokenStatsWindow {
        if supportsCustomRange { return end.timeIntervalSince(start) <= maxCustomSpan ? .custom : tooLargeFallback }
        let needed = now.timeIntervalSince(zone.calendar.startOfDay(for: start))
        guard let rolling = Rolling.allCases.first(where: { $0.seconds >= needed }) else { return tooLargeFallback }
        return .rolling(rolling, coversRange: true)
    }
    /// A custom window shows the range name instead.
    public var title: String? {
        guard case .rolling(let rolling, _) = self else { return nil }
        return rolling.title
    }
    /// 40 §2.3; under a group filter the sentence about its models follows.
    public func footnote(groupName: String? = nil) -> String {
        let window = switch self {
        case .custom: "统计窗口与所选范围一致。"
        case .rolling(let rolling, true):
            "统计窗口\(rolling.title)，截至现在：后端只有 30 分钟、1 小时、1 天、15 天、30 天这几种滚动窗口，这里取能盖住所选范围的最小一个。"
        case .rolling(let rolling, false): "统计窗口\(rolling.title)，截至现在：后端最长只到 30 天，盖不住所选范围，这里只是最近 30 天的速度。"
        }
        guard let groupName, !groupName.isEmpty else { return window }
        return window + "只列「\(groupName)」用到的模型。"
    }
    /// The server reads any start_time or end_time as a custom window, so a rolling one drops both.
    func queryItems(replacingRangeIn base: [URLQueryItem]) -> [URLQueryItem] {
        guard case .rolling(let rolling, _) = self else { return base }
        return base.filter { $0.name != "start_time" && $0.name != "end_time" } + [URLQueryItem(name: "time_range", value: rolling.rawValue)]
    }
}

/// U35: ops error logs are kept 30 days by default (`ops.cleanup.error_log_retention_days`, which the App cannot read).
public enum OpsRetention {
    public static let defaultDays = 30
    public static let hint = "运维日志默认只保留 30 天，更早的时段可能没有记录"
    /// The range starts before the same moment `defaultDays` site days ago. The range itself is not cut.
    public static func mayBeTrimmed(rangeStart: Date, now: Date, zone: ServerTimeZone) -> Bool {
        guard let cutoff = zone.calendar.date(byAdding: .day, value: -defaultDays, to: now) else { return false }
        return rangeStart < cutoff
    }
}

// MARK: - 四个运维图表的接口（40 §2.2，S4-11）

extension APIClient {
    /// The page range and filters go through OpsQuery, never `mode`. `supportsModelFilter` has no default, so a caller cannot drop
    /// the model filter silently; a 404 `OPS_DISABLED` is thrown unchanged.
    public func opsLatencyHistogram(_ query: OpsQuery, supportsModelFilter: Bool) async throws -> OpsLatencyHistogram {
        try await opsChart("latency-histogram", query, supportsModelFilter: supportsModelFilter)
    }
    public func opsErrorTrend(_ query: OpsQuery, supportsModelFilter: Bool) async throws -> OpsErrorTrend {
        let reply: OpsErrorTrend.Reply = try await opsChart("error-trend", query, supportsModelFilter: supportsModelFilter)
        return OpsErrorTrend(bucket: .resolve(reply.bucket, window: query.end.timeIntervalSince(query.start)), points: reply.points,
                             windowStart: query.start, windowEnd: query.end)
    }
    public func opsErrorDistribution(_ query: OpsQuery, supportsModelFilter: Bool) async throws -> OpsErrorDistribution {
        try await opsChart("error-distribution", query, supportsModelFilter: supportsModelFilter)
    }
    /// The window follows `OpsTokenStatsWindow.select` with the server clock and zone; a custom window answered 400
    /// `OPS_TIME_RANGE_TOO_LARGE` is asked once more as `time_range=30d`. No paging. `supportsModelFilter` defaults to false
    /// because the more-charts card sends no model (40 §2.2); only the model page (40 §5.2) passes `ops.dashboard_model_filter`.
    public func opsTokenStats(_ query: OpsQuery, topN: Int = 100, supportsCustomRange: Bool,
                              supportsModelFilter: Bool = false) async throws -> OpsTokenStats {
        try query.validate()
        let snapshot = currentGeneration()
        let window = OpsTokenStatsWindow.select(start: query.start, end: query.end, now: serverClock.now(), zone: serverTimeZone(),
                                                supportsCustomRange: supportsCustomRange)
        let limits = OpsTokenStats.topNRange
        let base = query.queryItems(supportsModelFilter: supportsModelFilter)
            + [URLQueryItem(name: "top_n", value: String(min(max(topN, limits.lowerBound), limits.upperBound)))]
        do {
            return try await tokenStats(base, window: window)
        } catch let error as APIError where window == .custom && error.statusCode == 400 && error.reason == "OPS_TIME_RANGE_TOO_LARGE" {
            try check(snapshot)
            return try await tokenStats(base, window: .tooLargeFallback)
        }
    }

    private func opsChart<T: Decodable & Sendable>(_ chart: String, _ query: OpsQuery, supportsModelFilter: Bool) async throws -> T {
        try query.validate()
        return try await request("admin/ops/dashboard/" + chart, query: query.queryItems(supportsModelFilter: supportsModelFilter),
                                 timeout: RequestTimeout.aggregate)
    }
    private func tokenStats(_ base: [URLQueryItem], window: OpsTokenStatsWindow) async throws -> OpsTokenStats {
        let reply: OpsTokenStats.Reply = try await request("admin/ops/dashboard/openai-token-stats",
                                                           query: window.queryItems(replacingRangeIn: base), timeout: RequestTimeout.aggregate)
        return OpsTokenStats(reply: reply, window: window)
    }
}

private extension KeyedDecodingContainer {
    /// Missing or null is nil; a negative count fails the decode.
    func optionalNonNegative(_ key: Key) throws -> Int? {
        guard let value = try decodeIfPresent(Int.self, forKey: key) else { return nil }
        guard value >= 0 else { throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Negative count") }
        return value
    }
    func nonNegative(_ key: Key) throws -> Int { try optionalNonNegative(key) ?? 0 }
}
