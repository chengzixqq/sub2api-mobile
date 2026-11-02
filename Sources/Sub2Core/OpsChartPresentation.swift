import Foundation

// 40 §2.3 the 运行 charts' words and numbers (S4-18: 平均账号切换, 请求时长分布, 错误趋势; S4-18b appends 错误分布 and Token 请求统计 at
// the end). Times are the site's (S0-07); the page range is AnalyticsRange.

// MARK: - 卡头提示（40 §2.1、§2.5）

extension OpsChartCopy {
    /// The lines under an ops card's header, the whole-site note first: then U35's hint for a chart reading the error logs
    /// (平均账号切换, 错误趋势, 错误分布) when the range starts more than 30 days back.
    public static func headerNotes(siteWide: Bool, readsErrorLogs: Bool, range: AnalyticsRange) -> [String] {
        let trimmed = readsErrorLogs && OpsRetention.mayBeTrimmed(rangeStart: range.start, now: range.now, zone: range.zone)
        return [siteWide ? siteWideNote : nil, trimmed ? OpsRetention.hint : nil].compactMap { $0 }
    }
}

// MARK: - 平均账号切换

/// A mark on a time axis: “3时”, “10/14”, or 现在 at the range's end.
public struct OpsAxisTick: Hashable, Sendable {
    public let date: Date
    public let label: String
    public let isNow: Bool

    public init(date: Date, label: String, isNow: Bool) { self.date = date; self.label = label; self.isNow = isNow }
}

/// 40 §2.3 平均账号切换 over `throughput-trend` in the page range: 切换次数, the average and the highest switches per request, and the
/// line of switches per request, broken where a bucket had no request.
public struct OpsSwitchSummary: Sendable, Equatable {
    public struct Point: Sendable, Equatable, Identifiable {
        /// The bucket's start.
        public let date: Date
        /// switch_count ÷ request_count.
        public let rate: Double
        /// Points either side of a bucket without requests (or one the server left out) belong to different segments.
        public let segment: Int
        public var id: Date { date }

        public init(date: Date, rate: Double, segment: Int) { self.date = date; self.rate = rate; self.segment = segment }
    }

    public static let spanLimitText = "平均账号切换只支持 31 天以内的范围"
    /// Today's marks in the last 15% of the window give way to 现在 (the design's).
    private static let nowClearance = 0.85
    private static let ticksOnSeveralDays = 4.0

    public let bucket: OpsBucket
    /// Σswitch_count, buckets without requests included.
    public let switches: Int
    public let requests: Int
    /// The buckets with requests, oldest first.
    public let points: [Point]

    public init(_ trend: PerformanceTrend) {
        bucket = trend.bucket
        switches = trend.points.reduce(0) { $0 + $1.switchCount }
        requests = trend.points.reduce(0) { $0 + $1.requestCount }
        points = Self.segmented(trend)
    }

    /// S4D1-10: the page range up to PerformanceTrend.maximumSpan; a longer one sends nothing and says so.
    public static func supports(start: Date, end: Date) -> Bool { end.timeIntervalSince(start) <= PerformanceTrend.maximumSpan }

    /// Σswitch_count ÷ Σrequest_count; nil without requests.
    public var average: Double? { requests > 0 ? Double(switches) / Double(requests) : nil }
    public var highest: Double? { points.map(\.rate).max() }
    public var switchesText: String { DisplayFormat.grouped(switches) }
    /// Also the tile's value (S4-18b).
    public var averageText: String { Self.perRequest(average) }
    public var highestText: String { Self.perRequest(highest) }
    public var figures: [AnalyticsFigure] {
        [AnalyticsFigure("switches", label: "切换次数", value: switchesText), AnalyticsFigure("average", label: "平均 · 次/请求", value: averageText),
         AnalyticsFigure("highest", label: "最高 · 次/请求", value: highestText)]
    }
    public var footnote: String {
        let grain = switch bucket {
        case .minute: "曲线每分钟一点。"
        case .fiveMinutes: "曲线每 5 分钟一点。"
        case .hour: "曲线每小时一点。"
        }
        return grain + "请求因限流、过载或错误换到另一个账号，记一次切换。"
    }

    /// Three decimals, “—” without a value.
    public static func perRequest(_ value: Double?) -> String { DisplayFormat.decimal(value, minFractionDigits: 3, maxFractionDigits: 3) }
    /// The y axis: two decimals.
    public static func axisLabel(_ value: Double) -> String { DisplayFormat.decimal(value, minFractionDigits: 2, maxFractionDigits: 2) }
    /// VoiceOver: “今天 09:40，0.012 次/请求”.
    public static func spokenPoint(_ point: Point, range: AnalyticsRange) -> String {
        DisplayFormat.dayTime(point.date, now: range.now, timeZone: range.zone.timeZone) + "，" + perRequest(point.rate) + " 次/请求"
    }

    /// 40 §2.3: a single day every 3 hours (today, ending at 现在, the marks in its last 15% left out) or 6 hours (a past day) on the
    /// site's clock, “N时”; several days the starts of about four days, counted back from the last.
    public static func axisTicks(for range: AnalyticsRange) -> [OpsAxisTick] {
        guard range.granularity == .hour else { return dayTicks(range) }
        let calendar = range.zone.calendar, day = range.firstDay
        let marks = stride(from: 0, to: 24, by: range.includesNow ? 3 : 6).compactMap { hour -> OpsAxisTick? in
            guard let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour)),
                  date >= range.start, date < range.end else { return nil }
            return OpsAxisTick(date: date, label: "\(calendar.component(.hour, from: date))时", isNow: false)
        }
        guard range.includesNow else { return marks }
        let cutoff = range.start.addingTimeInterval(range.end.timeIntervalSince(range.start) * nowClearance)
        return marks.filter { $0.date < cutoff } + [OpsAxisTick(date: range.end, label: "现在", isNow: true)]
    }

    private static func dayTicks(_ range: AnalyticsRange) -> [OpsAxisTick] {
        let buckets = range.buckets
        let step = max(1, Int((Double(buckets.count) / ticksOnSeveralDays).rounded(.up)))
        return buckets.indices.filter { (buckets.count - 1 - $0) % step == 0 }.map { index in
            OpsAxisTick(date: buckets[index].start, label: buckets[index].axisLabel, isNow: false)
        }
    }

    private static func segmented(_ trend: PerformanceTrend) -> [Point] {
        var points: [Point] = []
        var segment = 0, broken = false, previous: Date?
        for point in trend.points {
            if let previous, point.date.timeIntervalSince(previous) > trend.bucket.seconds { broken = true }
            previous = point.date
            guard point.requestCount > 0 else { broken = true; continue }
            if broken, !points.isEmpty { segment += 1 }
            broken = false
            points.append(Point(date: point.date, rate: Double(point.switchCount) / Double(point.requestCount), segment: segment))
        }
        return points
    }
}

// MARK: - 请求时长分布

/// 40 §2.3 请求时长分布: the six columns of successful requests with their whole shares, and the percentile table from the overview.
public struct OpsLatencySummary: Sendable, Equatable {
    public struct Column: Sendable, Equatable, Identifiable {
        public let range: OpsLatencyHistogram.BucketRange
        public let count: Int
        /// Relative to the tallest column.
        public let height: Double
        /// count ÷ total_requests, no decimals.
        public let shareText: String
        public var label: String { range.label }
        public var id: OpsLatencyHistogram.BucketRange { range }
        /// “<100ms，10%，1,820 次”.
        public var spokenLabel: String { label + "，" + shareText + "，" + DisplayFormat.grouped(count) + " 次" }
    }
    /// 总耗时 (`duration`) or 首字 (`ttft`), one value per header.
    public struct Row: Sendable, Equatable, Identifiable {
        public let key: String
        public let title: String
        public let values: [String]
        public var id: String { key }

        /// “P50 2.4s，P90 5.1s，…”, a missing value read as 无数据.
        public func spokenValue(headers: [String]) -> String {
            zip(headers, values).map { $0 + " " + DisplayFormat.spoken($1) }.joined(separator: "，")
        }
    }

    public static let emptyText = "这个范围内没有成功请求"
    public static let tileCaption = "P50 总耗时"
    private static let cardHeaders = ["P50", "P90", "P95", "P99"]
    private static let fullHeaders = cardHeaders + ["平均", "最长"]

    public let columns: [Column]
    public let totalRequests: Int
    public let overview: OpsOverview?

    public init(histogram: OpsLatencyHistogram, overview: OpsOverview?) {
        columns = histogram.buckets.map { bucket in
            Column(range: bucket.range, count: bucket.count, height: histogram.height(bucket),
                   shareText: DisplayFormat.wholePercent(histogram.share(bucket)))
        }
        totalRequests = histogram.totalRequests
        self.overview = overview
    }

    /// A card shows P50 P90 P95 P99; full size adds 平均 and 最长.
    public static func headers(full: Bool) -> [String] { full ? fullHeaders : cardHeaders }
    public var isEmpty: Bool { totalRequests == 0 }
    /// “成功请求 18,204 次的总耗时分布”; nil without requests.
    public var footnote: String? { isEmpty ? nil : "成功请求 " + DisplayFormat.grouped(totalRequests) + " 次的总耗时分布" }
    /// “—” for every cell without requests, without the overview, or for a null field.
    public func rows(full: Bool) -> [Row] {
        let count = Self.headers(full: full).count
        func values(_ percentiles: OpsPercentiles?) -> [String] {
            let all = [percentiles?.p50Ms, percentiles?.p90Ms, percentiles?.p95Ms, percentiles?.p99Ms, percentiles?.avgMs, percentiles?.maxMs]
            return all.prefix(count).map { isEmpty ? DisplayFormat.missing : DisplayFormat.duration($0, style: .percentile) }
        }
        return [Row(key: "duration", title: "总耗时", values: values(overview?.duration)), Row(key: "ttft", title: "首字", values: values(overview?.ttft))]
    }
    /// The tile's “2.4s” (S4-18b).
    public var tileValue: String { isEmpty ? DisplayFormat.missing : DisplayFormat.duration(overview?.duration?.p50Ms, style: .percentile) }
}

// MARK: - 错误趋势

/// The two layers of 错误趋势's bars (U34: the upstream counts get a line of their own).
public enum OpsErrorLayer: String, CaseIterable, Hashable, Sendable {
    case sla, businessLimited

    public var title: String { self == .sla ? "SLA 错误" : "业务限制" }
}

/// 40 §2.3 错误趋势 over `error-trend` and the overview: 错误 / 错误率 · SLA / SLA 口径, two-layer bars over the whole range (60-second
/// buckets per 5 minutes, 300-second ones per hour, 3600-second ones per site day, or per hour on a single day such as a 25-hour one),
/// the legend, the upstream line and the footnote.
public struct OpsErrorTrendSummary: Sendable, Equatable {
    public struct Bar: Sendable, Equatable, Identifiable {
        public let index: Int
        public let start: Date
        public let end: Date
        /// “9时”, “10/14”, “09:05”.
        public let label: String
        /// VoiceOver's name of the bar: “10月16日 9:00 到 9:41”, “10月14日 周三”, “09:05 到 09:10”.
        public let spokenName: String
        public let sla: Int
        public let businessLimited: Int
        public var id: Int { index }
        public var total: Int { sla + businessLimited }
    }

    public static let emptyText = "这个范围内没有错误"
    private static let rateNote = "错误率 = SLA 口径错误 ÷（成功 + SLA 口径错误），不算业务限制（用户自己的余额、额度、频率限制）。"

    public let totals: OpsErrorCounts
    /// Every bar of the range, without errors too, so the axis stays.
    public let bars: [Bar]
    public let ticks: [AnalyticsAxisTick]
    /// The overview's `error_rate`; “—” without it, or when the overview counted no SLA request (the server then answers 0).
    public let errorRateText: String
    public let footnote: String

    public init(trend: OpsErrorTrend, overview: OpsOverview?, range: AnalyticsRange) {
        let unit = BarUnit(bucket: trend.bucket, range: range)
        let slots = unit.slots(range)
        let sums = Self.sums(trend.points, into: slots.map(\.start))
        totals = trend.totals
        bars = slots.indices.map { index in
            Bar(index: index, start: slots[index].start, end: slots[index].end, label: slots[index].label, spokenName: slots[index].spokenName,
                sla: sums[index].sla, businessLimited: sums[index].businessLimited)
        }
        ticks = Self.ticks(slots.map(\.label), daily: unit == .day, includesNow: range.includesNow)
        let rate = overview?.requestCountSLA == 0 ? nil : overview?.errorRate
        errorRateText = DisplayFormat.ratioPercent(rate)
        footnote = unit.footnote(bucket: trend.bucket) + Self.rateNote
    }

    public var isEmpty: Bool { totals.total == 0 }
    public var figures: [AnalyticsFigure] {
        [AnalyticsFigure("errors", label: "错误", value: DisplayFormat.grouped(totals.total)),
         AnalyticsFigure("rate", label: "错误率 · SLA", value: errorRateText),
         AnalyticsFigure("sla", label: "SLA 口径", value: DisplayFormat.grouped(totals.sla))]
    }
    public var legendSLA: String { OpsErrorLayer.sla.title + " " + DisplayFormat.grouped(totals.sla) }
    public var legendBusinessLimited: String { OpsErrorLayer.businessLimited.title + " " + DisplayFormat.grouped(totals.businessLimited) }
    public var upstreamLine: String {
        "上游失败（含重试成功）：429 " + DisplayFormat.grouped(totals.upstream429) + " · 529 " + DisplayFormat.grouped(totals.upstream529)
            + " · 其他 " + DisplayFormat.grouped(totals.upstreamOther)
    }
    /// The bars as stacked layers.
    public var columns: [[OpsErrorLayer: Double]] {
        bars.map { [.sla: Double($0.sla), .businessLimited: Double($0.businessLimited)] }
    }

    /// Points oldest first into the slots starting at `starts`: each in the last slot starting at or before it, one before the
    /// first slot (a bucket the range cuts) in the first.
    private static func sums(_ points: [OpsErrorTrend.Point], into starts: [Date]) -> [OpsErrorCounts] {
        guard !starts.isEmpty else { return [] }
        var sums = Array(repeating: OpsErrorCounts.zero, count: starts.count)
        var slot = 0
        for point in points {
            while slot + 1 < starts.count, starts[slot + 1] <= point.start { slot += 1 }
            sums[slot] = sums[slot] + point.counts
        }
        return sums
    }

    /// AnalyticsRange.axisTicks' rule over these bars: days counted back from the last, the others from the first; with the range
    /// reaching now the last tick moves onto the last bar, 现在 (今天 for a day).
    private static func ticks(_ labels: [String], daily: Bool, includesNow: Bool) -> [AnalyticsAxisTick] {
        let count = labels.count, step = AnalyticsRange.tickStride(count: count)
        let indices = (0..<count).filter { daily ? (count - 1 - $0) % step == 0 : $0 % step == 0 }
        let moved = includesNow && !indices.isEmpty && indices.last != count - 1 ? Array(indices.dropLast()) + [count - 1] : indices
        return moved.map { index in
            let isNow = includesNow && index == count - 1
            return AnalyticsAxisTick(index: index, label: isNow ? (daily ? "今天" : "现在") : labels[index], isNow: isNow)
        }
    }
}

/// What one bar of 错误趋势 adds up.
private enum BarUnit: Equatable {
    case fiveMinutes, hour, day

    struct Slot {
        let start: Date
        let end: Date
        let label: String
        let spokenName: String
    }

    /// A 3600-second bucket on a single day stays by the hour (BACKLOG 359: a 25-hour day is not one bar).
    init(bucket: OpsBucket, range: AnalyticsRange) {
        switch bucket {
        case .minute: self = .fiveMinutes
        case .fiveMinutes: self = .hour
        case .hour: self = range.granularity == .hour ? .hour : .day
        }
    }

    func footnote(bucket: OpsBucket) -> String {
        switch (bucket, self) {
        case (.minute, _): "后端每分钟一桶，这里按 5 分钟合计。"
        case (.fiveMinutes, _): "后端每 5 分钟一桶，这里按小时合计。"
        case (.hour, .day): "后端每小时一桶，这里按天合计。"
        case (.hour, _): "后端每小时一桶。"
        }
    }

    /// The range's own buckets by the hour or the day; 本月 on the 1st (a day shorter than 24 hours) gets its hours.
    func slots(_ range: AnalyticsRange) -> [Slot] {
        switch self {
        case .fiveMinutes: return fiveMinuteSlots(range)
        case .hour where range.granularity == .day:
            let hours = AnalyticsBuckets.hours(of: range.firstDay, start: range.start, end: range.end, includesNow: range.includesNow,
                                               today: range.today, zone: range.zone)
            return hours.map(Self.slot)
        case .hour, .day: return range.buckets.map(Self.slot)
        }
    }

    private static func slot(_ bucket: AnalyticsBucket) -> Slot {
        Slot(start: bucket.start, end: bucket.end, label: bucket.axisLabel, spokenName: bucket.spokenLabel)
    }

    /// Whole multiples of 300 seconds since the epoch, which every zone offset in use shares, “09:05”.
    private func fiveMinuteSlots(_ range: AnalyticsRange) -> [Slot] {
        let length = OpsBucket.fiveMinutes.seconds, zone = range.zone.timeZone
        let first = (range.start.timeIntervalSince1970 / length).rounded(.down) * length
        return stride(from: first, to: range.end.timeIntervalSince1970, by: length).map { seconds in
            let start = Date(timeIntervalSince1970: seconds), end = min(start.addingTimeInterval(length), range.end)
            let label = DisplayFormat.clock(start, timeZone: zone)
            return Slot(start: start, end: end, label: label, spokenName: label + " 到 " + DisplayFormat.clock(end, timeZone: zone))
        }
    }
}
