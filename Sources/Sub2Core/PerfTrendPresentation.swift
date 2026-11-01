import Foundation

/// 40 §1.4 RPM / TPM 趋势 (PerfTrendBody, the card flow's and 更多图表's): the words and numbers of the card and of 性能明细. Times
/// read in the site's zone (S0-07); a bucket before the window end's day reads “昨天 09:00” (the design's), the axis only HH:mm.
public enum PerfTrendPresentation {
    public static let cardTitle = "RPM / TPM 趋势"
    public static let detailsTitle = "性能明细"
    public static let emptyText = "这个时间范围内没有请求"
    /// 40 §1.7: while the card shows and the App is active, 30 seconds after the last read.
    public static let refreshInterval: TimeInterval = 30

    /// “截至现在 · 运维监控”; with ops monitoring off only “运维监控” (the design's AxPerfCard).
    public static func cardMeta(opsDisabled: Bool) -> String { opsDisabled ? "运维监控" : "截至现在 · 运维监控" }

    /// “09:40”, or “昨天 09:40” before the day the window ends on.
    public static func bucketLabel(_ date: Date, windowEnd: Date, timeZone: TimeZone) -> String {
        let clock = DisplayFormat.clock(date, timeZone: timeZone)
        return calendar(timeZone).isDate(date, inSameDayAs: windowEnd) || date > windowEnd ? clock : "昨天 " + clock
    }

    // MARK: The big number and the line under it

    /// “RPM · 最新一桶 09:40”, selected “RPM · 09:12”.
    public static func headlineLabel(_ trend: PerformanceTrend, metric: PerformanceMetric, selected: PerformanceTrend.Point?,
                                     timeZone: TimeZone) -> String {
        if let selected { return metric.rawValue + " · " + label(selected, in: trend, timeZone: timeZone) }
        guard let newest = trend.points.last else { return metric.rawValue + " · 最新一桶" }
        return metric.rawValue + " · 最新一桶 " + label(newest, in: trend, timeZone: timeZone)
    }
    public static func headlineValue(_ trend: PerformanceTrend, metric: PerformanceMetric, selected: PerformanceTrend.Point?) -> String {
        guard let point = selected ?? trend.points.last else { return DisplayFormat.missing }
        return metric.format(trend.rate(point, metric: metric))
    }
    /// “峰值 52 · 平均 44 · 近 1 小时”, selected “09:12 · RPM 47 · 再点一下取消”.
    public static func subline(_ trend: PerformanceTrend, metric: PerformanceMetric, selected: PerformanceTrend.Point?,
                               windowTitle: String, timeZone: TimeZone) -> String {
        if let selected {
            return label(selected, in: trend, timeZone: timeZone) + " · " + metric.rawValue + " "
                + metric.format(trend.rate(selected, metric: metric)) + " · 再点一下取消"
        }
        return "峰值 \(formatted(trend.peak(metric), metric)) · 平均 \(formatted(trend.average(metric), metric)) · \(windowTitle)"
    }

    // MARK: The chart

    /// No points, or none with a request or a token.
    public static func isEmpty(_ trend: PerformanceTrend) -> Bool {
        trend.points.allSatisfy { $0.requestCount == 0 && $0.tokenConsumed == 0 }
    }
    /// The site's whole marks inside the window: every 15 minutes for an hour, 2 hours up to 6 hours, 6 hours beyond. Marks are
    /// the clock's, so a day with a daylight-saving change keeps 00:00 / 06:00 / 12:00 / 18:00.
    public static func axisTicks(_ trend: PerformanceTrend, timeZone: TimeZone) -> [Date] {
        let hours = windowHours(trend), step = hours <= 1 ? 15 : hours <= 6 ? 120 : 360
        let calendar = calendar(timeZone)
        var ticks: [Date] = []
        var day = calendar.startOfDay(for: trend.windowStart)
        while day <= trend.windowEnd {
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            for minute in stride(from: 0, to: 1_440, by: step) {
                var mark = parts
                mark.hour = minute / 60; mark.minute = minute % 60
                guard let tick = calendar.date(from: mark), tick >= trend.windowStart, tick <= trend.windowEnd,
                      !ticks.contains(tick) else { continue }
                ticks.append(tick)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return ticks
    }
    public static func axisLabel(_ date: Date, timeZone: TimeZone) -> String { DisplayFormat.clock(date, timeZone: timeZone) }
    /// 1, 6 or 24: which window a reply answers.
    public static func windowHours(_ trend: PerformanceTrend) -> Int {
        Int((trend.windowEnd.timeIntervalSince(trend.windowStart) / 3_600).rounded())
    }
    /// The point nearest to a position on the time axis (a touch outside the points falls on the first or last); nil without points.
    public static func nearestIndex(to date: Date, in trend: PerformanceTrend) -> Int? {
        trend.points.indices.min { abs(trend.points[$0].date.timeIntervalSince(date)) < abs(trend.points[$1].date.timeIntervalSince(date)) }
    }

    // MARK: The notes under the chart

    /// “每桶 1 分钟，速率 = …；窗口从 08:41 到现在，…。RPM 含成功请求和错误请求，TPM 为成功请求的含缓存 Tokens。”
    public static func explanation(_ trend: PerformanceTrend, timeZone: TimeZone) -> String {
        let start = bucketLabel(trend.windowStart, windowEnd: trend.windowEnd, timeZone: timeZone)
        let from = start.first?.isNumber == true ? "窗口从 " + start : "窗口从" + start
        return "每桶 \(trend.bucket.label)，速率 = 数量 × 60 ÷ 这一桶实际覆盖的秒数；\(from) 到现在，首尾不满一桶的按覆盖时长折算。"
            + "RPM 含成功请求和错误请求，TPM 为成功请求的含缓存 Tokens。"
    }
    /// “更新于 09:41:00 · 前台每 30 秒刷新”: the last success.
    public static func updatedLine(_ updatedAt: Date?, timeZone: TimeZone) -> String? {
        updatedAt.map { "更新于 " + DisplayFormat.clockWithSeconds($0, timeZone: timeZone) + " · 前台每 30 秒刷新" }
    }

    // MARK: 性能明细

    /// The card foot's “61 桶 · 最新在上”, the points it has.
    public static func detailsMeta(_ trend: PerformanceTrend) -> String { "\(trend.points.count) 桶 · 最新在上" }
    public static func detailsNote(_ trend: PerformanceTrend, windowTitle: String) -> String {
        "最新在上 · \(windowTitle) · 每桶 \(trend.bucket.label)。点一行，图上选中这个时间。"
    }
    /// “09:40”, or “09:40 · 只覆盖 23 秒” for a bucket the window cuts.
    public static func rowTitle(_ point: PerformanceTrend.Point, in trend: PerformanceTrend, timeZone: TimeZone) -> String {
        label(point, in: trend, timeZone: timeZone) + (coverage(point, in: trend).map { " · " + $0 } ?? "")
    }
    /// “RPM 46 · TPM 240K”.
    public static func rowRates(_ point: PerformanceTrend.Point, in trend: PerformanceTrend) -> String {
        PerformanceMetric.allCases.map { "\($0.rawValue) \($0.format(trend.rate(point, metric: $0)))" }.joined(separator: " · ")
    }
    /// 40 §1.5 a point for VoiceOver: “09:40，RPM 46，只覆盖 23 秒”.
    public static func spokenPoint(_ point: PerformanceTrend.Point, in trend: PerformanceTrend, metric: PerformanceMetric,
                                   timeZone: TimeZone) -> String {
        let rate = metric.rawValue + " " + metric.format(trend.rate(point, metric: metric))
        return ([label(point, in: trend, timeZone: timeZone), rate] + [coverage(point, in: trend)].compactMap { $0 }).joined(separator: "，")
    }

    // MARK: Polling (40 §1.6 / §1.7)

    /// A 400 (or the query's own check) and a 403 will not change by asking again. 404 OPS_DISABLED is the ops switch's call.
    public static func stopsPolling(after error: APIError?) -> Bool {
        error.map { !AnalyticsCardFailure(error: $0).allowsRetry } ?? false
    }
    /// The rest of `interval` since the last read; 0 when it is due or there was none.
    public static func pollDelay(since last: Date?, now: Date, interval: TimeInterval) -> TimeInterval {
        guard let last else { return 0 }
        return max(0, interval - now.timeIntervalSince(last))
    }

    private static func label(_ point: PerformanceTrend.Point, in trend: PerformanceTrend, timeZone: TimeZone) -> String {
        bucketLabel(point.date, windowEnd: trend.windowEnd, timeZone: timeZone)
    }
    private static func coverage(_ point: PerformanceTrend.Point, in trend: PerformanceTrend) -> String? {
        let covered = trend.coveredSeconds(point)
        guard covered < trend.bucket.seconds else { return nil }
        return "只覆盖 \(Int(covered.rounded())) 秒"
    }
    private static func formatted(_ value: Double?, _ metric: PerformanceMetric) -> String {
        value.map(metric.format) ?? DisplayFormat.missing
    }
    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// The ops charts' shared words.
public enum OpsChartCopy {
    /// 40 §1.2 参数映射: a model filter the ops charts cannot send (OpsQuery.isSiteWide); S4-18 and S4-19 reuse it.
    public static let siteWideNote = "运行类图表不支持按这个模型筛选，这里显示全站"
}
