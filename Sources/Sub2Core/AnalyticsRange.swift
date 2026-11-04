import Foundation

/// 40 §1.2 range presets. `rawValue` is the stable key S4-12 keeps per site; a remembered preset is recomputed from today on entry.
public enum AnalyticsPreset: String, CaseIterable, Hashable, Sendable {
    case today, last7, last30, thisMonth, last14, lastMonth

    /// Also the range name (“实际扣费 · 近 7 天”).
    public var title: String {
        switch self {
        case .today: "今天"
        case .last7: "近 7 天"
        case .last30: "近 30 天"
        case .thisMonth: "本月"
        case .last14: "近 14 天"
        case .lastMonth: "上月"
        }
    }
    /// The custom range sheet's capsules.
    public static let shortcuts: [AnalyticsPreset] = [.thisMonth, .last14, .lastMonth]

    /// The server days this preset covers when `today` is today.
    func days(today: AnalyticsDay) -> (first: AnalyticsDay, last: AnalyticsDay) {
        switch self {
        case .today: return (today, today)
        case .last7: return (today.adding(days: -6), today)
        case .last30: return (today.adding(days: -29), today)
        case .last14: return (today.adding(days: -13), today)
        case .thisMonth: return (today.firstOfMonth(offset: 0), today)
        case .lastMonth:
            let first = today.firstOfMonth(offset: -1)
            return (first, first.lastOfMonth)
        }
    }
}

/// The range bar's segmented control: 今天 · 7 天 · 30 天 · 自定义.
public enum AnalyticsRangeSegment: String, CaseIterable, Hashable, Sendable {
    case today, last7, last30, custom

    public var title: String {
        switch self {
        case .today: "今天"
        case .last7: "7 天"
        case .last30: "30 天"
        case .custom: "自定义"
        }
    }
    /// What tapping the segment selects; 自定义 opens the sheet instead.
    public var preset: AnalyticsPreset? {
        switch self {
        case .today: .today
        case .last7: .last7
        case .last30: .last30
        case .custom: nil
        }
    }
}

public enum AnalyticsRangeSelection: Hashable, Sendable {
    case preset(AnalyticsPreset)
    /// Whole server days, both ends included; `AnalyticsRange.resolve` orders them and keeps them within `AnalyticsDayBounds`.
    case custom(from: AnalyticsDay, to: AnalyticsDay)

    public var preset: AnalyticsPreset? {
        if case .preset(let preset) = self { return preset }
        return nil
    }
}

/// U36: the backend has no site opening date, so a custom range reaches back 366 days and no further than today.
public struct AnalyticsDayBounds: Equatable, Sendable {
    public static let maxDaysBack = 366
    public let earliest: AnalyticsDay
    public let latest: AnalyticsDay

    /// `now` is the caller's `ServerClock.now()`.
    public init(now: Date, zone: ServerTimeZone) { self.init(today: AnalyticsDay(containing: now, in: zone)) }
    public init(today: AnalyticsDay) {
        latest = today
        earliest = today.adding(days: -Self.maxDaysBack)
    }
    public func contains(_ day: AnalyticsDay) -> Bool { earliest <= day && day <= latest }
    public func clamp(_ day: AnalyticsDay) -> AnalyticsDay { min(max(day, earliest), latest) }
}

/// The window an increase or decrease is measured against, and how the line names it (“比昨天同时”).
public struct AnalyticsComparison: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let label: String
}

/// One bucket of a range, present whether or not the backend returned a row for it.
public struct AnalyticsBucket: Hashable, Identifiable, Sendable {
    public let index: Int
    public let start: Date
    /// The next bucket's start; `now` for the bucket still running.
    public let end: Date
    /// The backend's `date` for this bucket: “2026-10-16 09:00” by the hour, “2026-10-16” by the day.
    public let wireKey: String
    /// The current hour or today, drawn darker.
    public let isCurrent: Bool
    /// The selected bar's label: “10月16日 8:00–9:00”, “10月16日 9:00–9:41” for the current hour, “10月14日 周三”.
    public let fullName: String
    /// The detail table's 时段: “8:00–9:00”, “16日 周五”.
    public let shortName: String
    /// “8时”, “10/14”.
    public let axisLabel: String
    /// VoiceOver: “10月16日 9:00 到 9:41”, “10月14日 周三”.
    public let spokenLabel: String
    public var id: Int { index }
}

public struct AnalyticsAxisTick: Hashable, Sendable {
    public let index: Int
    /// The bucket's `axisLabel`, or 现在 / 今天 on the bucket still running.
    public let label: String
    public let isNow: Bool
}

/// A bucket with the reply row that falls in it; nil means the backend left it out (count it as 0).
public struct AnalyticsSlot<Value: Sendable>: Sendable {
    public let bucket: AnalyticsBucket
    public let value: Value?
}

extension AnalyticsSlot: Equatable where Value: Equatable {}

/// One resolved range (40 §1.2, §1.4): the window every analytics request sends, its buckets and the labels shown for it. Calendar
/// math is on the site's calendar only (40 §0.2, R20), never by adding 86,400 seconds; `now` is the caller's `ServerClock.now()`.
/// Cache by selection and filter, not by the range: `now` differs on every refresh.
public struct AnalyticsRange: Equatable, Sendable {
    /// A custom selection comes back ordered and within `AnalyticsDayBounds`.
    public let selection: AnalyticsRangeSelection
    public let zone: ServerTimeZone
    public let now: Date
    public let today: AnalyticsDay
    public let firstDay: AnalyticsDay
    public let lastDay: AnalyticsDay
    /// `start_time` (inclusive) and `end_time` (exclusive). A range reaching today ends now, or one second after the start at
    /// midnight exactly: the backend refuses an empty range.
    public let start: Date
    public let end: Date
    public let includesNow: Bool
    /// Only a single day goes by the hour (今天 and a custom single day); 本月 on the 1st stays by the day.
    public let granularity: AnalyticsGranularity
    public let buckets: [AnalyticsBucket]

    public static func resolve(_ selection: AnalyticsRangeSelection, now: Date, zone: ServerTimeZone) -> AnalyticsRange {
        let bounds = AnalyticsDayBounds(now: now, zone: zone), today = bounds.latest
        let span = days(of: selection, bounds: bounds)
        let includesNow = span.last == today
        let hourly = span.selection.preset == .today || (span.selection.preset == nil && span.first == span.last)
        let start = span.first.start(in: zone)
        let end = includesNow ? (now > start ? now : start.addingTimeInterval(1)) : span.last.adding(days: 1).start(in: zone)
        let buckets = hourly
            ? AnalyticsBuckets.hours(of: span.first, start: start, end: end, includesNow: includesNow, today: today, zone: zone)
            : AnalyticsBuckets.days(from: span.first, through: span.last, end: end, includesNow: includesNow, today: today, zone: zone)
        return AnalyticsRange(selection: span.selection, zone: zone, now: now, today: today, firstDay: span.first, lastDay: span.last,
                              start: start, end: end, includesNow: includesNow, granularity: hourly ? .hour : .day, buckets: buckets)
    }

    private static func days(of selection: AnalyticsRangeSelection, bounds: AnalyticsDayBounds)
        -> (selection: AnalyticsRangeSelection, first: AnalyticsDay, last: AnalyticsDay) {
        switch selection {
        case .preset(let preset):
            let days = preset.days(today: bounds.latest)
            return (selection, days.first, days.last)
        case .custom(let from, let to):
            let first = bounds.clamp(min(from, to)), last = bounds.clamp(max(from, to))
            return (.custom(from: first, to: last), first, last)
        }
    }

    public var dayCount: Int { firstDay.days(to: lastDay) + 1 }

    /// 范围名: 今天 · 近 7 天 · 本月 · 上月 · 自选 3 天, and 今天 / 昨天 / 10月14日 for a custom single day.
    public var name: String {
        if let preset = selection.preset { return preset.title }
        guard dayCount == 1 else { return "自选 \(dayCount) 天" }
        if firstDay == today { return "今天" }
        if firstDay == today.adding(days: -1) { return "昨天" }
        return AnalyticsLabel.date(firstDay, today: today)
    }

    public var segment: AnalyticsRangeSegment {
        switch selection.preset {
        case .some(.today): .today
        case .some(.last7): .last7
        case .some(.last30): .last30
        default: .custom
        }
    }

    /// A preset off the bar (本月 / 近 14 天 / 上月) or “自选 N 天” takes the place of 自定义.
    public var segmentTitle: String {
        guard segment == .custom else { return segment.title }
        return selection.preset?.title ?? "自选 \(dayCount) 天"
    }

    /// 说明行: “10月16日 周五 · 00:00 至 09:41 · 按小时”, “10月10日 – 16日（今天到 09:41）· 按天”, “10月15日 周四 · 按小时”;
    /// a phone in another zone gets “（站点时间 UTC+8）” at the end (40 §0.2).
    public func caption(device: TimeZone) -> String {
        captionBody + (zone.siteTimeSuffix(device: device, at: now) ?? "")
    }

    private var captionBody: String {
        let until = DisplayFormat.clock(end, timeZone: zone.timeZone)
        let singleDay = AnalyticsLabel.date(firstDay, today: today) + " " + firstDay.weekdayName
        if granularity == .hour {
            guard includesNow else { return singleDay + " · 按小时" }
            return singleDay + " · " + DisplayFormat.clock(start, timeZone: zone.timeZone) + " 至 " + until + " · 按小时"
        }
        let days = dayCount == 1 ? singleDay : AnalyticsLabel.span(firstDay, lastDay, today: today)
        return days + (includesNow ? "（今天到 \(until)）· 按天" : " · 按天")
    }

    /// 40 §1.2 对比窗口: the same length right before, up to the same wall-clock time when the range reaches now; 本月 against last month
    /// to the same day (its last day when it has no such day); 上月 against the whole month before.
    public var comparison: AnalyticsComparison {
        switch selection {
        case .preset(.thisMonth):
            let first = firstDay.firstOfMonth(offset: -1), last = first.lastOfMonth
            let day = AnalyticsDay(year: first.year, month: first.month, day: min(lastDay.day, last.day)) ?? last
            return AnalyticsComparison(start: first.start(in: zone), end: sameTime(as: end, on: day), label: "比上月同期")
        case .preset(.lastMonth):
            let first = firstDay.firstOfMonth(offset: -1)
            return AnalyticsComparison(start: first.start(in: zone), end: firstDay.start(in: zone), label: "比 \(first.month) 月")
        default:
            let days = dayCount
            let until = includesNow ? sameTime(as: end, on: lastDay.adding(days: -days)) : firstDay.start(in: zone)
            return AnalyticsComparison(start: firstDay.adding(days: -days).start(in: zone), end: until, label: shiftLabel)
        }
    }

    private var shiftLabel: String {
        if dayCount == 1 { return includesNow ? "比昨天同时" : "比前一天" }
        return includesNow ? "比前 \(dayCount) 天同期" : "比前 \(dayCount) 天"
    }

    /// The same wall-clock time on another server day (同一时刻), whatever daylight saving does in between.
    private func sameTime(as instant: Date, on day: AnalyticsDay) -> Date {
        let calendar = zone.calendar
        var parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: instant)
        parts.year = day.year; parts.month = day.month; parts.day = day.day
        return calendar.date(from: parts) ?? day.start(in: zone)
    }

    /// 40 §1.4 横轴: every bucket up to 8, every 3rd up to 12, every 6th up to 24, every 7th beyond.
    public static func tickStride(count: Int) -> Int {
        switch count {
        case ...8: 1
        case ...12: 3
        case ...24: 6
        default: 7
        }
    }

    /// Days are counted back from the last one; hours from midnight, and a range reaching now moves its last tick onto the current
    /// hour so 现在 is always labelled. The bucket still running reads 现在 (an hour) or 今天 (a day).
    public var axisTicks: [AnalyticsAxisTick] {
        let count = buckets.count, step = Self.tickStride(count: count)
        var indices = (0..<count).filter { granularity == .day ? (count - 1 - $0) % step == 0 : $0 % step == 0 }
        if includesNow, let last = indices.indices.last, indices[last] != count - 1 { indices[last] = count - 1 }
        return indices.map { index in
            let isNow = includesNow && index == count - 1
            let label = isNow ? (granularity == .hour ? "现在" : "今天") : buckets[index].axisLabel
            return AnalyticsAxisTick(index: index, label: label, isNow: isNow)
        }
    }

    /// Every bucket with its reply row (40 §0.2: trend and users-trend leave empty buckets out). `key` reads the row's `date`; a row
    /// outside the range is dropped and a repeated key keeps the later row.
    public func slots<Value: Sendable>(_ values: [Value], key: (Value) -> String) -> [AnalyticsSlot<Value>] {
        let rows = Dictionary(values.map { (key($0), $0) }, uniquingKeysWith: { _, later in later })
        return buckets.map { AnalyticsSlot(bucket: $0, value: rows[$0.wireKey]) }
    }
}

/// A calendar day on the site's calendar, as `start_date` / `end_date` write it (yyyy-MM-dd). Day arithmetic is on the civil calendar,
/// so it never depends on a zone; `start(in:)` places the day in one.
public struct AnalyticsDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), (1...Self.length(ofMonth: month, year: year)).contains(day) else {
            return nil
        }
        self.init(valid: year, month: month, day: day)
    }
    /// Strict yyyy-MM-dd, as `description` writes it (the remembered custom range, S4-12).
    public init?(_ text: String) {
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }
    public init(containing date: Date, in zone: ServerTimeZone) {
        let parts = zone.calendar.dateComponents([.year, .month, .day], from: date)
        self.init(valid: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }
    private init(valid year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    public var description: String { Self.pad(year, 4) + "-" + Self.pad(month, 2) + "-" + Self.pad(day, 2) }
    public static func < (lhs: AnalyticsDay, rhs: AnalyticsDay) -> Bool { (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day) }

    public func adding(days: Int) -> AnalyticsDay {
        guard days != 0, let date = Self.civil.date(byAdding: .day, value: days, to: civilDate) else { return self }
        let parts = Self.civil.dateComponents([.year, .month, .day], from: date)
        return AnalyticsDay(valid: parts.year ?? year, month: parts.month ?? month, day: parts.day ?? day)
    }
    public func days(to other: AnalyticsDay) -> Int { Self.civil.dateComponents([.day], from: civilDate, to: other.civilDate).day ?? 0 }
    /// The day's first instant in `zone` (its midnight, or the first hour that exists when a clock skips midnight).
    public func start(in zone: ServerTimeZone) -> Date {
        let calendar = zone.calendar
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? civilDate
        return calendar.startOfDay(for: noon)
    }
    /// 周一 … 周日.
    public var weekdayName: String { Self.weekdays[Self.civil.component(.weekday, from: civilDate) - 1] }

    /// The 1st of the month `offset` months away.
    func firstOfMonth(offset: Int) -> AnalyticsDay {
        let index = year * 12 + month - 1 + offset
        return AnalyticsDay(valid: index / 12, month: index % 12 + 1, day: 1)
    }
    var lastOfMonth: AnalyticsDay { AnalyticsDay(valid: year, month: month, day: Self.length(ofMonth: month, year: year)) }

    private var civilDate: Date { Self.civil.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast }
    private static let civil: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX"); calendar.timeZone = .gmt
        return calendar
    }()
    /// Gregorian `weekday` − 1.
    private static let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    private static func length(ofMonth month: Int, year: Int) -> Int {
        switch month {
        case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}

/// Chinese date labels of a range; a day outside today's year carries its year.
enum AnalyticsLabel {
    /// “10月14日”, “2025年12月1日”.
    static func date(_ day: AnalyticsDay, today: AnalyticsDay) -> String {
        (day.year == today.year ? "" : "\(day.year)年") + "\(day.month)月\(day.day)日"
    }
    /// “10月10日 – 16日”, “9月17日 – 10月16日”, “2025年12月28日 – 2026年1月3日”.
    static func span(_ first: AnalyticsDay, _ last: AnalyticsDay, today: AnalyticsDay) -> String {
        let withYear = first.year != today.year || last.year != today.year
        let head = (withYear ? "\(first.year)年" : "") + "\(first.month)月\(first.day)日"
        let tail: String
        if last.year != first.year {
            tail = "\(last.year)年\(last.month)月\(last.day)日"
        } else if last.month != first.month {
            tail = "\(last.month)月\(last.day)日"
        } else {
            tail = "\(last.day)日"
        }
        return head + " – " + tail
    }
    /// “9:41”: bucket names write the hour without a leading zero (40 §1.4).
    static func hourMinute(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.minute ?? 0
        return "\(parts.hour ?? 0):" + (minute < 10 ? "0\(minute)" : "\(minute)")
    }
}

/// The full bucket list of a range, built on the site's calendar.
enum AnalyticsBuckets {
    /// One server day by the hour. Steps are real hours keyed like the backend's `YYYY-MM-DD HH:00`: the hour a clock goes back repeats
    /// its key and becomes one two-hour bucket, the hour it skips is missing (23 buckets, “1:00–3:00”).
    static func hours(of day: AnalyticsDay, start: Date, end: Date, includesNow: Bool, today: AnalyticsDay,
                      zone: ServerTimeZone) -> [AnalyticsBucket] {
        let calendar = zone.calendar
        var starts: [(date: Date, key: String)] = []
        var cursor = start
        while cursor < end {
            let key = hourKey(cursor, calendar: calendar)
            if starts.last?.key != key { starts.append((cursor, key)) }
            cursor = cursor.addingTimeInterval(3_600)
        }
        let date = AnalyticsLabel.date(day, today: today), stop = min(cursor, end)
        return starts.indices.map { index in
            let isLast = index == starts.count - 1
            let from = starts[index].date, until = isLast ? stop : starts[index + 1].date
            let opening = AnalyticsLabel.hourMinute(from, calendar: calendar)
            // The bucket ending at the next midnight ends at 24:00, not 0:00.
            let closing = calendar.isDate(until, inSameDayAs: from) ? AnalyticsLabel.hourMinute(until, calendar: calendar) : "24:00"
            let span = opening + "–" + closing
            return AnalyticsBucket(index: index, start: from, end: until, wireKey: starts[index].key, isCurrent: includesNow && isLast,
                                   fullName: date + " " + span, shortName: span, axisLabel: "\(calendar.component(.hour, from: from))时",
                                   spokenLabel: date + " " + opening + " 到 " + closing)
        }
    }

    static func days(from first: AnalyticsDay, through last: AnalyticsDay, end: Date, includesNow: Bool, today: AnalyticsDay,
                     zone: ServerTimeZone) -> [AnalyticsBucket] {
        (0...max(0, first.days(to: last))).map { index in
            let day = first.adding(days: index)
            let isCurrent = includesNow && day == last
            let name = AnalyticsLabel.date(day, today: today) + " " + day.weekdayName
            return AnalyticsBucket(index: index, start: day.start(in: zone), end: isCurrent ? end : day.adding(days: 1).start(in: zone),
                                   wireKey: day.description, isCurrent: isCurrent, fullName: name,
                                   shortName: "\(day.day)日 " + day.weekdayName, axisLabel: "\(day.month)/\(day.day)", spokenLabel: name)
        }
    }

    private static func hourKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let day = AnalyticsDay(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)?.description ?? ""
        let hour = parts.hour ?? 0
        return day + " " + (hour < 10 ? "0\(hour)" : "\(hour)") + ":00"
    }
}
