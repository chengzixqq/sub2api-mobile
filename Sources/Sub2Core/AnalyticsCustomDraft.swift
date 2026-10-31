import Foundation

/// 40 §1.2 自定义范围 sheet: two server days picked one at a time, kept within `AnalyticsDayBounds` (U36); when the start passes the
/// end the other end follows. Matching a shortcut selects it, except a single day, which always goes by the hour.
public struct AnalyticsCustomDraft: Equatable, Sendable {
    public let from: AnalyticsDay
    public let to: AnalyticsDay
    /// The date pickers' range.
    public let bounds: AnalyticsDayBounds
    private let now: Date
    private let zone: ServerTimeZone
    /// The shortcut picked last, or the range opened as; it wins a tie (on the 14th 本月 and 近 14 天 cover the same days).
    private let picked: AnalyticsPreset?

    /// A custom range (a shortcut included) opens as itself; 今天 / 7 天 / 30 天 open on 本月.
    public init(range: AnalyticsRange) {
        let days = range.segment == .custom
            ? (first: range.firstDay, last: range.lastDay) : AnalyticsPreset.thisMonth.days(today: range.today)
        self.init(from: days.first, to: days.last, bounds: AnalyticsDayBounds(today: range.today), now: range.now, zone: range.zone,
                  picked: range.selection.preset)
    }
    private init(from: AnalyticsDay, to: AnalyticsDay, bounds: AnalyticsDayBounds, now: Date, zone: ServerTimeZone,
                 picked: AnalyticsPreset?) {
        self.from = from; self.to = to; self.bounds = bounds; self.now = now; self.zone = zone; self.picked = picked
    }

    public func settingFrom(_ day: AnalyticsDay) -> AnalyticsCustomDraft {
        let from = bounds.clamp(day)
        return AnalyticsCustomDraft(from: from, to: max(from, to), bounds: bounds, now: now, zone: zone, picked: picked)
    }
    public func settingTo(_ day: AnalyticsDay) -> AnalyticsCustomDraft {
        let to = bounds.clamp(day)
        return AnalyticsCustomDraft(from: min(from, to), to: to, bounds: bounds, now: now, zone: zone, picked: picked)
    }
    public func applying(_ shortcut: AnalyticsPreset) -> AnalyticsCustomDraft {
        let days = shortcut.days(today: bounds.latest)
        return AnalyticsCustomDraft(from: bounds.clamp(days.first), to: bounds.clamp(days.last), bounds: bounds, now: now, zone: zone,
                                    picked: shortcut)
    }

    /// The capsule shown selected; never for a single day (本月 on the 1st would otherwise turn it into a range by the day). Of two
    /// shortcuts covering the same days the picked one wins, since they compare with different windows.
    public var matchedShortcut: AnalyticsPreset? {
        guard from != to else { return nil }
        let matches = AnalyticsPreset.shortcuts.filter {
            let days = $0.days(today: bounds.latest)
            return days.first == from && days.last == to
        }
        return matches.first { $0 == picked } ?? matches.first
    }
    /// What 应用 selects.
    public var selection: AnalyticsRangeSelection { matchedShortcut.map(AnalyticsRangeSelection.preset) ?? .custom(from: from, to: to) }
    public var dayCount: Int { from.days(to: to) + 1 }

    /// “10月1日 周四 00:00”.
    public var startLine: String { dayLine(from) + " " + DisplayFormat.clock(from.start(in: zone), timeZone: zone.timeZone) }
    /// “10月16日 周五 现在（09:41）”, “10月14日 周三 24:00”.
    public var endLine: String {
        dayLine(to) + (to == bounds.latest ? " 现在（\(DisplayFormat.clock(now, timeZone: zone.timeZone))）" : " 24:00")
    }
    public var footnote: String { "共 \(dayCount) 天，按天统计（只选一天按小时）；按站点时区计算。" }

    private func dayLine(_ day: AnalyticsDay) -> String { AnalyticsLabel.date(day, today: bounds.latest) + " " + day.weekdayName }
}
