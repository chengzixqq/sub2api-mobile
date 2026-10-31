import Foundation

/// 10 §4.1–§4.3 (S1-13): the monitor tab's segment titles, subtitles and counts, and the overview's run section. The health
/// bands, the rates' formats and the refresh phrase are the overview's (HomeRunPresentation, HomePresentation), so both pages
/// read the same; numbers go through DisplayFormat (R10).
public enum MonitorTabPresentation {
    public static let vendorPlaceholder = "代运营工作区没有运维监控权限"
    public static let trendLabel = "错误率 · 近 45 分钟"
    public static let trendFailed = "趋势加载失败"
    public static let noAlerts = "没有告警"
    /// 10 §4.2's `time_range=5m`; APIClient sends it as start_time / end_time (X08).
    public static let overviewTimeRange = "5m"
    private static let overviewTitle = "运行与服务器"
    private static let channelsTitle = "渠道 · 近 90 分钟"
    private static let alertsTitle = "告警"

    /// The overview's own check (10 §0.1); first-version vendors cannot sign in (U01), so this only guards.
    public static func showsVendorPlaceholder(_ me: AdminMe) -> Bool { me.workspace != nil }

    /// “告警 2”: a segment with something to look at carries its count; 0 or unknown shows the title alone (10 §4.1).
    public static func segmentTitle(_ title: String, count: Int?) -> String {
        guard let count, count > 0 else { return title }
        return title + " " + DisplayFormat.grouped(count)
    }

    // MARK: Subtitles (10 §4.1)

    /// nil while ops monitoring is off: the section's name alone.
    public static func overviewSubtitle(_ status: HomeRefreshStatus?, now: Date, timeZone: TimeZone) -> String {
        guard let status else { return overviewTitle }
        return overviewTitle + " · " + HomePresentation.refreshPhrase(status, now: now, timeZone: timeZone)
    }
    /// Until the channel list was read (S1-15) only the window.
    public static func channelsSubtitle(updatedAt: Date?, now: Date, timeZone: TimeZone) -> String {
        guard let updatedAt else { return channelsTitle }
        return channelsTitle + " · " + HomePresentation.refreshPhrase(.updated(at: updatedAt), now: now, timeZone: timeZone)
    }
    /// “告警 · 0 条进行中” as in the design; the count unknown or ops monitoring off: “告警”.
    public static func alertsSubtitle(firingCount: Int?) -> String {
        guard let firingCount else { return alertsTitle }
        return alertsTitle + " · " + DisplayFormat.grouped(firingCount) + " 条进行中"
    }
    /// A failed block (with or without its earlier value) is 部分数据未更新; a block still without a value 正在加载…; otherwise the
    /// oldest of the blocks' last successes.
    public static func refreshStatus(_ blocks: [MonitorBlockSnapshot]) -> HomeRefreshStatus {
        if blocks.contains(where: \.failed) { return .partial }
        let times = blocks.compactMap { $0.hasValue ? $0.updatedAt : nil }
        guard !blocks.isEmpty, times.count == blocks.count, let oldest = times.min() else { return .loading }
        return .updated(at: oldest)
    }

    // MARK: Counts (10 §4.1)

    /// critical + warning: the channel list once read (S1-15), otherwise the overview's channel block.
    public static func channelsAttentionCount(items: [ChannelItem]?, home: HomeChannels?) -> Int? {
        if let items {
            let counts = ChannelPresentation.counts(items)
            return counts.degraded + counts.unavailable
        }
        return home.map { $0.warning + $0.critical }
    }
    /// The firing list while it is not cut off at `listLimit` (it follows local resolves at once); otherwise the exact count.
    public static func firingCount(listCount: Int?, listLimit: Int, counts: AlertCounts?) -> Int? {
        if let listCount, listCount < listLimit { return listCount }
        return counts?.firing ?? listCount
    }

    // MARK: Run section (10 §4.3)

    /// “告警中 N 条” with the titles joined by “、”; counted before the list arrived it has no detail yet, never “没有告警”.
    public static func alertsRow(firingCount: Int?, titles: [String]) -> MonitorAlertsRow {
        guard let firingCount else { return MonitorAlertsRow(title: "告警中 " + DisplayFormat.missing, detail: nil, tone: nil) }
        let title = "告警中 " + DisplayFormat.grouped(firingCount) + " 条"
        guard firingCount > 0 else { return MonitorAlertsRow(title: title, detail: noAlerts, tone: nil) }
        return MonitorAlertsRow(title: title, detail: titles.isEmpty ? nil : titles.joined(separator: "、"), tone: .caution)
    }
    /// The overview's 健康分 row, from `ops/dashboard/overview` instead of home's ops block.
    public static func health(_ overview: BlockDisplay<OpsOverview>) -> HomeRunPresentation.Health {
        let ops: BlockDisplay<HomeOps> = switch overview {
        case .placeholder: .placeholder
        case .failed(let reason): .failed(reason: reason)
        case .disabled(let reason): .disabled(reason: reason)
        case .value(let value, let at, let isRefreshing, let updateFailed):
            .value(HomeOps(healthScore: value.healthScore, sla: value.sla, errorRate: value.errorRate, upstream429Count: value.upstream429Count,
                           upstream529Count: value.upstream529Count), at: at, isRefreshing: isRefreshing, updateFailed: updateFailed)
        }
        return HomeRunPresentation.health(ops, opsDisabled: false)
    }
    /// 错误率 / 上游 429 / 529 as the overview's run section writes them.
    public static func rates(_ overview: OpsOverview?) -> HomeRunPresentation.RunRates {
        HomeRunPresentation.rates(overview.map { LiveRates(errorRate: $0.errorRate, upstream429Count: $0.upstream429Count, upstream529Count: $0.upstream529Count) })
    }
    /// The last 45 minutes up to the server's last whole minute: exactly 45 full buckets, and one window per minute, so
    /// snapshot-v2's cache and ETag can answer a repeat.
    public static func errorTrendWindow(now: Date) -> (start: Date, end: Date) {
        let end = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        return (end.addingTimeInterval(-MonitorPresentation.errorRateWindow), end)
    }
    /// “最近 0.9%，最高 1.2%”: the last point with a value and the highest; none at all reads 无数据.
    public static func trendSpokenValue(_ points: [Double?]) -> String {
        let values = points.compactMap { $0 }
        guard let latest = values.last, let peak = values.max() else { return DisplayFormat.missingSpoken }
        return "最近 " + DisplayFormat.ratioPercent(latest) + "，最高 " + DisplayFormat.ratioPercent(peak)
    }
}

/// 10 §4.3 告警中 row.
public struct MonitorAlertsRow: Sendable, Equatable {
    public let title: String
    /// The firing titles joined by “、”, “没有告警”, or nil while unknown.
    public let detail: String?
    /// Caution while anything fires.
    public let tone: Tone?
    public init(title: String, detail: String?, tone: Tone?) { self.title = title; self.detail = detail; self.tone = tone }
}

/// One overview block as the subtitle's refresh status sees it, whatever its value type.
public struct MonitorBlockSnapshot: Sendable, Equatable {
    public let hasValue: Bool
    public let failed: Bool
    public let updatedAt: Date?
    public init(hasValue: Bool, failed: Bool, updatedAt: Date?) { self.hasValue = hasValue; self.failed = failed; self.updatedAt = updatedAt }
    public init<Value: Sendable>(_ state: BlockState<Value>) {
        let failed = if case .failed = state { true } else { false }
        self.init(hasValue: state.value != nil, failed: failed, updatedAt: state.updatedAt)
    }
}
