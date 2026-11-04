import Foundation

// 40 §6.3–§6.5 for the log page (S4-05 / S4-05b / S4-06) and the request rows of global search (S6-21). The cursor and the
// merge by id are IncrementalList's alone; the 40 §6.6 numbers are in LogListPolicy.swift.

// MARK: Rows

/// One log row's display values (40 §6.3). Build them with `rows(_:…)` when the records change, not in a view body.
public struct LogRowPresentation: Identifiable, Hashable, Sendable {
    public let id: Int
    /// nil is a usage record, as in RequestDetailPresentation.
    public let kind: ErrorLogKind?
    public let createdAt: Date?
    /// HH:mm on the site's clock.
    public let time: String
    /// 200 for usage; the status code, or for an upstream row the retry recovered the code it hit (“鉴权” / “恢复” without one).
    public let badge: String
    public let badgeTone: Tone
    public let model: String
    public let user: String
    public let account: String
    public let amount: String
    public let timing: String
    /// The status capsule; nil for usage rows and for upstream rows whose client got a success.
    public let capsule: Tone?

    public var userAndAccount: String { user + " · " + account }
    public var drawsRail: Bool { capsule != nil }
}

extension LogRowPresentation {
    public init(_ record: UsageRequestRecord, timeZone: ServerTimeZone) { self.init(record, timeZone: timeZone, parser: TimestampParser()) }
    public init(_ record: RequestErrorRecord, kind: ErrorLogKind, timeZone: ServerTimeZone) {
        self.init(record, kind: kind, timeZone: timeZone, parser: TimestampParser())
    }
    /// One timestamp parser for the whole batch; each row equals the single-record one.
    public static func rows(_ records: [UsageRequestRecord], timeZone: ServerTimeZone) -> [LogRowPresentation] {
        let parser = TimestampParser()
        return records.map { LogRowPresentation($0, timeZone: timeZone, parser: parser) }
    }
    public static func rows(_ records: [RequestErrorRecord], kind: ErrorLogKind, timeZone: ServerTimeZone) -> [LogRowPresentation] {
        let parser = TimestampParser()
        return records.map { LogRowPresentation($0, kind: kind, timeZone: timeZone, parser: parser) }
    }

    init(_ record: UsageRequestRecord, timeZone: ServerTimeZone, parser: TimestampParser) {
        let createdAt = parser.date(record.createdAt)
        self.init(id: record.id, kind: nil, createdAt: createdAt, time: DisplayFormat.clock(createdAt, timeZone: timeZone.timeZone),
                  badge: "200", badgeTone: .ok, model: shownText(record.model), user: shownText(record.userEmail),
                  account: shownText(record.accountName), amount: DisplayFormat.moneyLineItem(record.actualCost),
                  timing: DisplayFormat.firstTokenAndDuration(firstTokenMs: record.firstTokenMs, durationMs: record.durationMs), capsule: nil)
    }
    init(_ record: RequestErrorRecord, kind: ErrorLogKind, timeZone: ServerTimeZone, parser: TimestampParser) {
        let createdAt = parser.date(record.createdAt)
        let (badge, badgeTone) = Self.badge(kind == .upstream ? record.upstreamStatus : .code(record.statusCode))
        let recovered = kind == .upstream && record.statusCode < 400
        let tone = Tone.httpStatus(record.statusCode)
        self.init(id: record.id, kind: kind, createdAt: createdAt, time: DisplayFormat.clock(createdAt, timeZone: timeZone.timeZone),
                  badge: badge, badgeTone: badgeTone, model: shownText(record.model), user: shownText(record.userEmail),
                  account: shownText(record.accountName), amount: DisplayFormat.missing,
                  timing: DisplayFormat.firstTokenAndDuration(firstTokenMs: record.firstTokenMs, durationMs: record.durationMs),
                  capsule: !recovered && tone.drawsRail ? tone : nil)
    }

    /// codeTone of the badge's own code, so a retried 429 stays amber (40 §6.3); the recovered words are neutral as in the detail.
    private static func badge(_ status: UpstreamErrorStatus) -> (String, Tone) {
        switch status {
        case .code(let code): (RequestDetailPresentation.validCode(code).map(String.init) ?? DisplayFormat.missing, Tone.httpStatus(code))
        case .accountAuth: ("鉴权", .neutral)
        case .unknown: ("恢复", .neutral)
        }
    }
}

// MARK: Sections

/// The rows of one day on the site's calendar (40 §6.3). `id` is that day's yyyy-MM-dd, or “undated” for rows whose time
/// cannot be read.
public struct LogSection<Row: Identifiable & Sendable>: Identifiable, Sendable where Row.ID == Int {
    public let id: String
    /// 今天 / 昨天 / 10月14日, with the year outside `now`'s (2025年10月14日); “—” for the undated rows.
    public let title: String
    /// Newest id first.
    public let rows: [Row]
}

extension LogSection: Equatable where Row: Equatable {}

extension LogSection where Row == LogRowPresentation {
    /// The status rail joins neighbours within the section only.
    public var railPositions: [RailPosition?] { RailPosition.positions(of: rows) { $0.drawsRail } }
}

public enum LogSections {
    public static let headerTrailing = "金额 · 首字/耗时"
    static let undatedID = "undated"

    /// Each row goes to its own day, so ids a few seconds out of time order never split a day into two sections (40 §6.6).
    /// Days newest first and the undated rows last; `now` is the caller's server-corrected clock.
    public static func make<Row: Identifiable & Sendable>(_ rows: [Row], timeZone: ServerTimeZone, now: Date,
                                                           createdAt: (Row) -> Date?) -> [LogSection<Row>] where Row.ID == Int {
        let calendar = timeZone.calendar
        let groups = Dictionary(grouping: rows) { row in createdAt(row).map { SiteDay($0, calendar: calendar) } }
        let today = SiteDay(now, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now).map { SiteDay($0, calendar: calendar) }
        return groups.keys.sorted(by: newestFirst).map { day -> LogSection<Row> in
            let rows = (groups[day] ?? []).sorted { $0.id > $1.id }
            guard let day else { return LogSection(id: undatedID, title: DisplayFormat.missing, rows: rows) }
            return LogSection(id: day.id, title: day.title(today: today, yesterday: yesterday), rows: rows)
        }
    }
    public static func make(_ rows: [LogRowPresentation], timeZone: ServerTimeZone, now: Date) -> [LogSection<LogRowPresentation>] {
        make(rows, timeZone: timeZone, now: now) { $0.createdAt }
    }

    private static func newestFirst(_ lhs: SiteDay?, _ rhs: SiteDay?) -> Bool {
        guard let lhs else { return false }
        guard let rhs else { return true }
        return lhs > rhs
    }
}

private struct SiteDay: Hashable, Comparable {
    let year: Int, month: Int, day: Int

    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 0; month = parts.month ?? 0; day = parts.day ?? 0
    }
    var id: String { "\(year)-" + Self.twoDigits(month) + "-" + Self.twoDigits(day) }
    func title(today: SiteDay, yesterday: SiteDay?) -> String {
        if self == today { return "今天" }
        if self == yesterday { return "昨天" }
        return (year == today.year ? "" : "\(year)年") + "\(month)月\(day)日"
    }
    static func < (lhs: SiteDay, rhs: SiteDay) -> Bool { (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day) }
    private static func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }
}

// MARK: Time

/// The time capsule's menu (40 §6.3). A rolling preset ends at the `now` of each full load; a custom range is fixed.
public enum LogTimePreset: Hashable, Sendable {
    case lastHour, last24Hours, last7Days, last30Days
    case custom(start: Date, end: Date)

    public static let standard = LogTimePreset.last24Hours
    /// Menu order.
    public static let rollingPresets: [LogTimePreset] = [.lastHour, .last24Hours, .last7Days, .last30Days]

    /// nil unless start is before end and the range is at most 366 days.
    public static func validatedCustom(start: Date, end: Date) -> LogTimePreset? {
        guard start < end, end.timeIntervalSince(start) <= LogTimeWindow.maximumRange else { return nil }
        return .custom(start: start, end: end)
    }
    public var isRolling: Bool { span != nil }
    public var span: TimeInterval? {
        switch self {
        case .lastHour: 3_600
        case .last24Hours: 86_400
        case .last7Days: 7 * 86_400
        case .last30Days: 30 * 86_400
        case .custom: nil
        }
    }
    public var menuTitle: String {
        switch self {
        case .lastHour: "近 1 小时"
        case .last24Hours: "近 24 小时"
        case .last7Days: "近 7 天"
        case .last30Days: "近 30 天"
        case .custom: "自定义…"
        }
    }
    public func window(now: Date) -> LogTimeWindow {
        guard case .custom(let start, let end) = self else { return .range(now.addingTimeInterval(-(span ?? 0)), now) }
        return .range(start, end)
    }
    /// The capsule and the subtitle: the menu title, or a custom range as “10/14 09:00 – 10/15 18:00” in the site's zone.
    public func title(timeZone: ServerTimeZone, now: Date) -> String {
        guard case .custom(let start, let end) = self else { return menuTitle }
        return DisplayFormat.monthDayClock(start, timeZone: timeZone, now: now) + " – " + DisplayFormat.monthDayClock(end, timeZone: timeZone, now: now)
    }
    /// “<站点名> · 近 24 小时” (40 §6.1), plus the site time when the phone's offset differs. `device` is `TimeZone.current`.
    public func subtitle(siteName: String, timeZone: ServerTimeZone, device: TimeZone, now: Date) -> String {
        siteName + " · " + title(timeZone: timeZone, now: now) + (timeZone.siteTimeSuffix(device: device, at: now) ?? "")
    }
    /// 40 §6.5; `filtered` is `LogFilterChips.hasAppliedConditions`.
    public func emptyMessage(filtered: Bool) -> String {
        let scope = isRolling ? menuTitle + "内" : "所选时间内"
        return scope + (filtered ? "，这些条件下没有记录" : "没有记录")
    }
    /// Only error segments over a custom range starting more than 30 days ago (U35); the rolling 30 days never shows it.
    public func showsRetentionNotice(kind: ErrorLogKind?, now: Date) -> Bool {
        guard kind != nil, case .custom(let start, _) = self else { return false }
        return start < now.addingTimeInterval(-LogListPolicy.opsRetention)
    }
}

public enum LogListCopy {
    public static let retentionNotice = "运维错误日志默认只保留 30 天，更早的可能已清理"
    public static let errorModelSourceNote = "错误记录只能按请求模型筛选，这里显示全部模型"
    public static let legacyUpstreamNote = "上游错误不能按模型、用户筛选，这里显示全部"
    /// A site without `usage.model_source` sends no source (S4D2a-13).
    public static let usageModelSourceNote = "使用记录只能按请求模型筛选，这里显示全部模型"
}

// MARK: Conditions

/// An account, group or user condition; S4-05 maps LogsRoute's RouteObject onto it.
public struct LogFilterObject: Hashable, Sendable {
    public let id: Int
    public let name: String?
    public init(id: Int, name: String? = nil) { self.id = id; self.name = name }
    /// The name, or “#id” when it is missing or blank.
    var label: String { nonBlank(name) ?? "#\(id)" }
}

/// `allCases` is the 40 §6.3 chip order; `rawValue` names the chip's identifier.
public enum LogFilterKind: String, CaseIterable, Hashable, Sendable {
    case account, group, user, model
    public var label: String {
        switch self {
        case .account: "账号"
        case .group: "分组"
        case .user: "用户"
        case .model: "模型"
        }
    }
}

/// The page's object conditions; time and segment are kept apart. `LogConditions()` has none.
public struct LogConditions: Hashable, Sendable {
    public var account: LogFilterObject?
    public var group: LogFilterObject?
    public var user: LogFilterObject?
    public var model: String?
    public var modelSource: ModelSource

    public init(account: LogFilterObject? = nil, group: LogFilterObject? = nil, user: LogFilterObject? = nil, model: String? = nil,
                modelSource: ModelSource = .requested) {
        self.account = account; self.group = group; self.user = user; self.model = model; self.modelSource = modelSource
    }
    /// A blank model counts as none.
    public var isEmpty: Bool { account == nil && group == nil && user == nil && trimmedModel == nil }
    /// Removing the model also resets its source to requested.
    public func removing(_ kind: LogFilterKind) -> LogConditions {
        var copy = self
        switch kind {
        case .account: copy.account = nil
        case .group: copy.group = nil
        case .user: copy.user = nil
        case .model: copy.model = nil; copy.modelSource = .requested
        }
        return copy
    }
    var trimmedModel: String? { nonBlank(model) }
}

public struct LogFilterChip: Identifiable, Hashable, Sendable {
    public let kind: LogFilterKind
    /// The object's name (“#id” without one) or the model.
    public let value: String
    public let isMonospaced: Bool
    /// false greys the chip and keeps it out of the request (40 §6.4).
    public let isApplied: Bool
    public var id: LogFilterKind { kind }
    public var text: String { kind.label + "：" + value }
}

/// One segment's chips (40 §6.3–§6.4). `legacyServer` is `AdminMe.isLegacyServer`, `supportsModelSource` the site's
/// `usage.model_source`.
public struct LogFilterChips: Equatable, Sendable {
    public let conditions: LogConditions
    public let kind: ErrorLogKind?
    /// Only the conditions that are set, in `LogFilterKind.allCases` order.
    public let chips: [LogFilterChip]
    /// The line under the chips while one is greyed; at most one per segment.
    public let note: String?
    private let isLegacyUpstream: Bool
    private let sendsModelSource: Bool

    public init(_ conditions: LogConditions, kind: ErrorLogKind?, legacyServer: Bool, supportsModelSource: Bool) {
        let greyed = Self.greyed(conditions, kind: kind, legacyServer: legacyServer, supportsModelSource: supportsModelSource)
        let chips = LogFilterKind.allCases.compactMap { chip in
            Self.value(of: chip, in: conditions).map {
                LogFilterChip(kind: chip, value: $0, isMonospaced: chip == .model, isApplied: greyed?.kinds.contains(chip) != true)
            }
        }
        self.conditions = conditions; self.kind = kind; self.chips = chips
        note = chips.contains { !$0.isApplied } ? greyed?.note : nil
        isLegacyUpstream = kind == .upstream && legacyServer
        sendsModelSource = kind == nil && supportsModelSource
    }
    /// The empty state's “这些条件下” and “清除筛选” (40 §6.5).
    public var hasAppliedConditions: Bool { chips.contains { $0.isApplied } }
    /// The request's conditions without the greyed ones. No `key_view` here: the caller passes `maskedView` (S4D1-06).
    public func filter(time: LogTimeWindow, pageSize: Int = IncrementalPolicy.pageSize) -> RequestLogFilter {
        let applied = Set(chips.filter(\.isApplied).map(\.kind))
        let model = applied.contains(.model) ? conditions.trimmedModel : nil
        let filter = RequestLogFilter(time: time, accountID: applied.contains(.account) ? conditions.account?.id : nil,
                                      groupID: applied.contains(.group) ? conditions.group?.id : nil,
                                      userID: applied.contains(.user) ? conditions.user?.id : nil, model: model,
                                      modelSource: model != nil && sendsModelSource ? conditions.modelSource : nil, pageSize: pageSize)
        return isLegacyUpstream ? filter.upstreamErrorFilter() : filter
    }

    /// The error endpoints match the requested model only; a server without D03 filters upstream errors by time, account
    /// and group alone.
    private static func greyed(_ conditions: LogConditions, kind: ErrorLogKind?, legacyServer: Bool,
                               supportsModelSource: Bool) -> (kinds: Set<LogFilterKind>, note: String)? {
        if kind == .upstream, legacyServer { return ([.user, .model], LogListCopy.legacyUpstreamNote) }
        guard conditions.modelSource != .requested else { return nil }
        if kind != nil { return ([.model], LogListCopy.errorModelSourceNote) }
        return supportsModelSource ? nil : ([.model], LogListCopy.usageModelSourceNote)
    }
    private static func value(of kind: LogFilterKind, in conditions: LogConditions) -> String? {
        switch kind {
        case .account: conditions.account?.label
        case .group: conditions.group?.label
        case .user: conditions.user?.label
        case .model: conditions.trimmedModel
        }
    }
}

/// Blank and missing text reads “—” in a row (40 §6.3).
private func shownText(_ value: String?) -> String { nonBlank(value) ?? DisplayFormat.missing }
private func nonBlank(_ value: String?) -> String? {
    let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? nil : text
}
