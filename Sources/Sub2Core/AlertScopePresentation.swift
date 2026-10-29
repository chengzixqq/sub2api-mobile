import Foundation

// S1-12, 10 §3: the alert detail's rows. Numbers, times and words come from AlertPresentation, DisplayFormat and
// ChannelPresentation (R10, D21); this file only puts the detail together. S1-17 adds the error-count row at the end.

/// 10 §3.3 范围: the event's dimension, in AlertPresentation.scopeText's order.
public enum AlertScopeKind: Equatable, Sendable {
    case group(id: Int), platform(String), server, siteWide
}

/// Where a 范围 row leads; the App maps it to `.group(id:)` or 监控 · 渠道 / 概况 (10 §3.1).
public enum AlertScopeDestination: Equatable, Sendable {
    case group(id: Int), monitorChannels, monitorOverview
}

/// A group-scoped event's group: the session's availability, `status-summary?group_id`, or without that capability the D02 count
/// of `groups/all`; `deleted` only when that reply came back without it.
public enum AlertGroupScope: Equatable, Sendable {
    case found(AccountStatusGroupSummary), deleted
}

/// One 范围 row. `trailingIsSecondary` greys the trailing words; a row without a destination opens nothing.
public struct AlertScopeRow: Equatable, Sendable {
    public let title: String
    public let trailing: String?
    public let trailingTone: Tone?
    public let trailingIsSecondary: Bool
    public let detail: String?
    public let destination: AlertScopeDestination?

    public init(title: String, trailing: String? = nil, trailingTone: Tone? = nil, trailingIsSecondary: Bool = false, detail: String? = nil,
                destination: AlertScopeDestination?) {
        self.title = title; self.trailing = trailing; self.trailingTone = trailingTone; self.trailingIsSecondary = trailingIsSecondary
        self.detail = detail; self.destination = destination
    }
}

/// One 规则 row; `key` names its accessibility identifier (alert.detail.rule.<key>).
public struct AlertRuleRow: Equatable, Sendable {
    public enum Key: String, Sendable { case condition, window, severity, fired, ended }
    public let key: Key
    public let value: String

    public init(key: Key, value: String) { self.key = key; self.value = value }
    public var label: String {
        switch key {
        case .condition: "条件"
        case .window: "窗口"
        case .severity: "级别"
        case .fired: "触发"
        case .ended: "结束"
        }
    }
}

/// 10 §3.5: what a failed `GET alert-events/:id` means for the page.
public enum AlertDetailFailure: Equatable, Sendable {
    case notFound, opsDisabled, invalidID, other
}

public enum AlertScopePresentation {
    public static let navigationTitle = "告警"
    public static let notFoundText = "这条告警不存在或已被清理"
    public static let groupDeletedText = "分组已删除"
    public static let monitorOverviewText = "监控 · 概况"

    /// The event's or the group's raw platform as GroupPlatform names it.
    public static func platformName(_ platform: String) -> String { GroupPlatform.title(platform.lowercased()) }

    public static func kind(_ event: AlertEvent) -> AlertScopeKind {
        if let groupID = event.groupID, groupID > 0 { return .group(id: groupID) }
        let platform = trimmed(event.platform ?? "")
        if !platform.isEmpty { return .platform(platform) }
        return AlertPresentation.metric(event).isServer ? .server : .siteWide
    }

    /// “P1 · 分组 · 标准组”; an old server's event without the group name takes the one `status-summary` gave.
    public static func navigationSubtitle(_ event: AlertEvent, groupScope: AlertGroupScope?) -> String {
        let named = trimmed(event.groupName ?? "").isEmpty ? event.replacingGroupName(foundName(groupScope)) : event
        return [trimmed(event.severity), AlertPresentation.scopeText(named, platformName: platformName)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// “P1 · 09:29 触发” on the server's day it fired, “P1 · 昨天 22:10 触发” otherwise; without fired_at only the level.
    public static func cause(_ event: AlertEvent, now: Date, timeZone: TimeZone) -> String {
        let fired = event.firedAt.map { date in
            let calendar = calendar(timeZone)
            let time = calendar.isDate(date, inSameDayAs: now) ? DisplayFormat.clock(date, timeZone: timeZone)
                : DisplayFormat.dayTime(date, now: now, timeZone: timeZone)
            return time + " 触发"
        }
        return [trimmed(event.severity), fired ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The rule's name; without a rule (or with a blank name) the title without its “P1: ”.
    public static func ruleName(_ event: AlertEvent) -> String {
        let name = trimmed(event.rule?.name ?? "")
        guard name.isEmpty else { return name }
        let title = trimmed(event.title)
        guard let prefix = title.range(of: #"^P\d+\s*:"#, options: .regularExpression) else { return title }
        return trimmed(String(title[prefix.upperBound...]))
    }

    /// The big figure in the rule's unit (the unknown unit without a rule); “—” when missing.
    public static func metricText(_ event: AlertEvent) -> String {
        AlertPresentation.value(event.metricValue, unit: AlertPresentation.metric(event).unit)
    }

    /// “阈值 5.0% · 近 5 分钟”: the threshold as AlertPresentation reads it and the rule's own window; nil with neither.
    public static func thresholdLine(_ event: AlertEvent) -> String? {
        let window = event.rule.flatMap { $0.windowMinutes > 0 ? "近 \($0.windowMinutes) 分钟" : nil }
        let parts = [AlertPresentation.thresholdText(event).map { "阈值 " + $0 }, window].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Only while firing (AlertPresentation.silenceLine).
    public static func silenceNote(_ event: AlertEvent, now: Date, timeZone: TimeZone) -> String? {
        AlertPresentation.silenceLine(event, now: now, timeZone: timeZone)
    }

    /// How an event that no longer fires ended, as the monitor's rows say it (“12 分钟前恢复”, “昨天 22:10 · 由 admin 手动解决”).
    public static func endNote(_ event: AlertEvent, now: Date, timeZone: TimeZone) -> String? {
        event.isFiring ? nil : AlertPresentation.sinceText(event, now: now, timeZone: timeZone)
    }

    /// The button row shows only while firing; which buttons is AlertActions' call.
    public static func showsActions(_ event: AlertEvent) -> Bool { event.isFiring }

    /// 分组行. `scope` nil: not read yet, the row still opens the group.
    public static func groupRow(_ event: AlertEvent, groupID: Int, scope: AlertGroupScope?) -> AlertScopeRow {
        let own = trimmed(event.groupName ?? "")
        let title = own.isEmpty ? foundName(scope) ?? "分组 #\(groupID)" : own
        switch scope {
        case nil:
            return AlertScopeRow(title: title, destination: .group(id: groupID))
        case .deleted?:
            return AlertScopeRow(title: title, trailing: groupDeletedText, trailingIsSecondary: true, destination: nil)
        case .found(let group)?:
            let affected = group.counts.needsAttention
            let words = affected > 0 ? "\(affected) 个账号受影响" : "账号都可调度"
            let platform = trimmed(group.platform)
            return AlertScopeRow(title: title, trailing: "\(group.counts.available)/\(group.counts.total) 可用",
                                 detail: platform.isEmpty ? words : platformName(platform) + " · " + words, destination: .group(id: groupID))
        }
    }

    /// 渠道行: the platform's worst channel, coloured unless 可用, and ChannelPresentation's note. `items` nil: not read yet.
    public static func channelRow(platform: String, items: [ChannelItem]?, channelMonitorDisabled: Bool) -> AlertScopeRow {
        let title = platformName(platform) + " 渠道"
        if channelMonitorDisabled { return AlertScopeRow(title: title, detail: HomePresentation.channelsDisabledText, destination: .monitorChannels) }
        guard let items else { return AlertScopeRow(title: title, destination: .monitorChannels) }
        let summary = ChannelPresentation.platformSummary(items, platform: platform)
        let worst = summary?.worst
        return AlertScopeRow(title: title, trailing: worst?.label, trailingTone: worst.flatMap { $0 == .available ? nil : $0.tone },
                             detail: ChannelPresentation.platformNote(summary), destination: .monitorChannels)
    }

    /// 服务器 / 全站行, both leading to 监控 · 概况; the group and platform kinds have their own rows.
    public static func monitorRow(_ kind: AlertScopeKind) -> AlertScopeRow? {
        let title: String
        switch kind {
        case .server: title = "服务器"
        case .siteWide: title = "全站"
        case .group, .platform: return nil
        }
        return AlertScopeRow(title: title, trailing: monitorOverviewText, trailingIsSecondary: true, destination: .monitorOverview)
    }

    /// 规则 as a key-value table; 结束 only once the event no longer fires.
    public static func ruleRows(_ event: AlertEvent, latencyMetricsSupported: Bool, now: Date, timeZone: TimeZone) -> [AlertRuleRow] {
        let condition = AlertPresentation.conditionText(event, latencyMetricsSupported: latencyMetricsSupported)
        let window = event.rule.flatMap { $0.windowMinutes > 0 ? "\($0.windowMinutes) 分钟" : nil }
        let rows = [AlertRuleRow(key: .condition, value: orMissing(condition)), AlertRuleRow(key: .window, value: window ?? DisplayFormat.missing),
                    AlertRuleRow(key: .severity, value: orMissing(event.severity)),
                    AlertRuleRow(key: .fired, value: DisplayFormat.dayTime(event.firedAt, now: now, timeZone: timeZone))]
        guard !event.isFiring else { return rows }
        return rows + [AlertRuleRow(key: .ended, value: DisplayFormat.dayTime(event.resolvedAt, now: now, timeZone: timeZone))]
    }

    /// 10 §3.5. The handler's “Invalid event ID” has no reason; an id the client would not send fails before the request.
    public static func failure(_ error: APIError?) -> AlertDetailFailure {
        guard let error else { return .other }
        switch (error.statusCode, error.reason) {
        case (404?, "OPS_ALERT_EVENT_NOT_FOUND"?): return .notFound
        case (404?, "OPS_DISABLED"?): return .opsDisabled
        case (400?, .none), (400?, "INVALID_EVENT_ID"?): return .invalidID
        case (.none, _) where error.kind == .validation: return .invalidID
        default: return .other
        }
    }

    /// 403 CHANNEL_MONITOR_DISABLED: the channel row says 渠道监控未开启 instead of failing.
    public static func isChannelMonitorDisabled(_ error: APIError?) -> Bool {
        error?.statusCode == 403 && error?.reason == HomeFallback.channelMonitorDisabledReason
    }

    // MARK: Internals

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func orMissing(_ text: String) -> String {
        let value = trimmed(text)
        return value.isEmpty ? DisplayFormat.missing : value
    }
    private static func foundName(_ scope: AlertGroupScope?) -> String? {
        guard case .found(let group)? = scope else { return nil }
        let name = trimmed(group.groupName)
        return name.isEmpty ? nil : name
    }
    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
