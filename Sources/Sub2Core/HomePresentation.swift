import Foundation

/// Where the six cells' RPM / TPM came from (10 §1.2). Only `dashboard/stats`, the last fallback, counts TPM without cache tokens.
public enum HomeRatesSource: String, Sendable, CaseIterable {
    case home, dashboardRates, opsOverview, dashboardStats
    public var tpmExcludesCache: Bool { self == .dashboardStats }
}

/// The App maps it to `PerfMetric`.
public enum HomeRateMetric: String, Sendable, CaseIterable { case rpm, tpm }

/// `allCases` is the fixed cell order; `rawValue` names the cell's identifier.
public enum HomeTickerKind: String, Sendable, CaseIterable { case actualCost, requests, errorRate, profit, rpm, tpm }

/// Today's actual cost against yesterday at the same time.
public struct HomeChange: Sendable, Equatable {
    public enum Direction: Sendable, Equatable { case up, down, flat }
    public let direction: Direction
    /// "▲7.9%", "▼3.2%", "0.0%".
    public let text: String
    /// "比昨天同时上升 7.9%", "与昨天同时持平".
    public let spoken: String
}

public struct HomeTickerCell: Identifiable, Sendable, Equatable {
    public let kind: HomeTickerKind
    public let label: String
    /// `DisplayFormat.missing` when the value is unknown; the first-load skeleton is the view's (BlockDisplay.placeholder).
    public let value: String
    public let isMissing: Bool
    /// Only the actual-cost cell.
    public let change: HomeChange?
    /// "*" on TPM when it excludes cache tokens.
    public let footnoteMark: String?
    public let accessibilityLabel: String
    public let destination: HomeDestination
    public var id: HomeTickerKind { kind }
}

public enum HomeTodayKind: String, Sendable, CaseIterable { case accountCost, standardCost, profit, tokens, successRate }

public struct HomeValueCell: Identifiable, Sendable, Equatable {
    public let kind: HomeTodayKind
    public let label: String
    public let value: String
    public let isMissing: Bool
    public var id: HomeTodayKind { kind }
}

/// The subtitle's refresh state. `updated(at:)` must come from the same clock as the subtitle's `now`.
public enum HomeRefreshStatus: Sendable, Equatable {
    /// First load, nothing yet.
    case loading
    /// The last time every block succeeded.
    case updated(at: Date)
    /// A block or the whole reply failed.
    case partial
}

public struct HomeCalmFlag: Sendable, Equatable {
    /// 全部正常 / 无需处理.
    public let title: String
    /// "15 个账号可调度".
    public let detail: String
    public var text: String { "✓ " + title + " · " + detail }
}

public struct HomeRankingRow: Identifiable, Sendable, Equatable {
    public let accountID: Int
    public let name: String
    public let amount: String
    /// 0…1: this row ÷ the first.
    public let ratio: Double
    /// "{平台} · {requests} 次请求".
    public let detail: String
    public let destination: HomeDestination
    public var id: Int { accountID }
}

/// One part of the channel line; the view colours only caution and critical.
public struct HomeChannelPart: Sendable, Equatable {
    public let text: String
    public let tone: Tone
}

/// The overview's pure presentation (10 §1–§2). Every number and time goes through DisplayFormat (R10); `now` is the caller's
/// ServerClock time and `timeZone` the server's, except `sessionRenewalBanner`, which counts on the phone's clock (D03).
public enum HomePresentation {
    public static let todaySectionMeta = "00:00 起"
    public static let channelsDisabledText = "渠道监控未开启"
    public static let channelsFailedText = "渠道状态加载失败"

    // MARK: Six cells (10 §1.3.2)

    /// Fixed order; a missing value is "—", never 0.
    public static func tickerCells(stats: HomeStats?, rates: LiveRates?, ratesSource: HomeRatesSource) -> [HomeTickerCell] {
        // 00 §6.5: a rate the server marks unavailable is missing.
        let errorRate = rates?.errorsAvailable == false ? nil : rates?.errorRate
        return [
            tickerCell(.actualCost, "今日实际扣费", DisplayFormat.money(stats?.todayActualCost),
                       change: yesterdayChange(today: stats?.todayActualCost, yesterday: stats?.yesterdaySameTimeActualCost)),
            tickerCell(.requests, "请求", DisplayFormat.compact(stats?.todayRequests)),
            tickerCell(.errorRate, "错误率", DisplayFormat.ratioPercent(errorRate)),
            tickerCell(.profit, "利润", DisplayFormat.money(profit(actual: stats?.todayActualCost, account: stats?.todayAccountCost))),
            tickerCell(.rpm, "RPM", DisplayFormat.rpm(rates?.rpm)),
            tickerCell(.tpm, "TPM", DisplayFormat.compact(rates?.tpm), excludesCache: ratesSource.tpmExcludesCache)
        ]
    }

    /// today ÷ yesterday − 1 in Decimal, one decimal; nil when either is missing or yesterday is not above 0. The arrows are the
    /// cell's own glyphs (10 §1.3.2), the number is DisplayFormat's.
    public static func yesterdayChange(today: Decimal?, yesterday: Decimal?) -> HomeChange? {
        guard let today, let yesterday, !today.isNaN, !yesterday.isNaN, yesterday > 0 else { return nil }
        let percent = DisplayFormat.rounded((today / yesterday - 1) * 100, digits: 1)
        let number = DisplayFormat.number(abs(percent), minFraction: 1, maxFraction: 1) + "%"
        if percent == 0 { return HomeChange(direction: .flat, text: number, spoken: "与昨天同时持平") }
        return percent > 0 ? HomeChange(direction: .up, text: "▲" + number, spoken: "比昨天同时上升 " + number)
            : HomeChange(direction: .down, text: "▼" + number, spoken: "比昨天同时下降 " + number)
    }

    /// 利润 = actual − account cost, in Decimal; nil when either is missing.
    public static func profit(actual: Decimal?, account: Decimal?) -> Decimal? {
        guard let actual, let account else { return nil }
        return actual - account
    }

    private static func tickerCell(_ kind: HomeTickerKind, _ label: String, _ value: String, change: HomeChange? = nil,
                                   excludesCache: Bool = false) -> HomeTickerCell {
        let (destination, opens): (HomeDestination, String) = switch kind {
        case .rpm: (.performanceTrend(.rpm), "打开 RPM 趋势")
        case .tpm: (.performanceTrend(.tpm), "打开 TPM 趋势")
        case .actualCost, .requests, .errorRate, .profit: (.analytics, "打开统计分析")
        }
        let spoken = [label + " " + DisplayFormat.spoken(value), change?.spoken, excludesCache ? "不含缓存 Tokens" : nil].compactMap { $0 }
        return HomeTickerCell(kind: kind, label: label, value: value, isMissing: value == DisplayFormat.missing, change: change,
                              footnoteMark: excludesCache ? "*" : nil, accessibilityLabel: spoken.joined(separator: "，") + "。" + opens,
                              destination: destination)
    }

    // MARK: Calm layout (10 §2)

    /// 10 §2.2, R02. Only a current result counts: a failed block is never calm, even with an earlier value. S1-05 writes the
    /// home blocks only when a reply arrives (loaded / failed / disabled), so a retry does not flip the layout. Disabled alerts
    /// (monitoring off) do not block; a silenced firing event does. `pending` is the caller's same-site records, all three kinds.
    public static func isCalm(availability: BlockState<AccountStatusSummary>, alerts: BlockState<HomeAlerts>, pending: [any PendingMoneyWrite]) -> Bool {
        guard let summary = current(availability), summary.totals.error == 0, summary.totals.overloaded == 0,
              shortageGroups(summary).isEmpty, pending.isEmpty else { return false }
        if case .disabled = alerts { return true }
        guard let alerts = current(alerts) else { return false }
        return alerts.firingCount == 0 && !alerts.top.contains { $0.isFiring }
    }

    /// 10 §2.4: “无需处理” while accounts recover by themselves, otherwise “全部正常”; both followed by the schedulable count.
    public static func calmFlag(totals: AccountStateCounts, hasLimited: Bool) -> HomeCalmFlag {
        HomeCalmFlag(title: hasLimited ? "无需处理" : "全部正常", detail: DisplayFormat.grouped(totals.available) + " 个账号可调度")
    }

    /// 10 §2.4 按账号: the server's order (highest actual cost first), the first four above 0, bars relative to the first.
    public static func rankingRows(_ items: [AccountsRankingItem], platformName: (String) -> String = GroupPlatform.title) -> [HomeRankingRow] {
        let rows = items.filter { $0.actualCost > 0 }.prefix(4)
        guard let top = rows.first?.actualCost else { return [] }
        return rows.map { item in
            let ratio = NSDecimalNumber(decimal: item.actualCost / top).doubleValue
            let platform = nonBlank(item.platform).map(platformName)
            let name = nonBlank(item.accountName) ?? "账号 #\(item.accountID)"
            return HomeRankingRow(accountID: item.accountID, name: name, amount: DisplayFormat.money(item.actualCost), ratio: min(max(ratio, 0), 1),
                                  detail: [platform, DisplayFormat.grouped(item.requests) + " 次请求"].compactMap { $0 }.joined(separator: " · "),
                                  destination: .account(id: item.accountID))
        }
    }

    // MARK: Subtitle, today, channels, banner

    /// 10 §1.3.1: "10月16日 周五 · 刚刚更新" on the server's calendar, then "· 按 UTC+8" when the phone's offset differs.
    public static func subtitle(now: Date, status: HomeRefreshStatus, serverTimeZone: ServerTimeZone, deviceTimeZone: TimeZone) -> String {
        let day = serverTimeZone.calendar.dateComponents([.month, .day, .weekday], from: now)
        let weekday = day.weekday.flatMap { weekdays.indices.contains($0 - 1) ? weekdays[$0 - 1] : nil } ?? ""
        let suffix = serverTimeZone.overviewSuffix(device: deviceTimeZone, at: now).map { " " + $0 } ?? ""
        return "\(day.month ?? 0)月\(day.day ?? 0)日 \(weekday) · " + refreshPhrase(status, now: now, timeZone: serverTimeZone.timeZone) + suffix
    }

    /// The subtitle's freshness, shared with the monitor tab (S1-13): "正在加载…", "刚刚更新" and "N 分钟前更新" take “更新”
    /// directly; a clock time (an hour or more, 00 §6.2) reads "更新于 今天 08:00".
    public static func refreshPhrase(_ status: HomeRefreshStatus, now: Date, timeZone: TimeZone) -> String {
        switch status {
        case .loading: return "正在加载…"
        case .partial: return "部分数据未更新"
        case .updated(let at):
            let relative = DisplayFormat.relativeTime(at, now: now, timeZone: timeZone)
            return relative.last?.isNumber == true ? "更新于 " + relative : relative + "更新"
        }
    }

    /// 10 §1.3.4 three cells and the usage row. `todaySLA` is nil with monitoring off: "—", never 0 or 100%.
    public static func todayCells(stats: HomeStats?, todaySLA: Double?) -> [HomeValueCell] {
        let values: [(HomeTodayKind, String, String)] = [
            (.accountCost, "账号成本", DisplayFormat.money(stats?.todayAccountCost)),
            (.standardCost, "标准", DisplayFormat.money(stats?.todayCost)),
            (.profit, "利润", DisplayFormat.money(profit(actual: stats?.todayActualCost, account: stats?.todayAccountCost))),
            (.tokens, "Tokens", DisplayFormat.compact(stats?.todayTokens)),
            (.successRate, "成功率", DisplayFormat.ratioPercent(todaySLA))
        ]
        return values.map { HomeValueCell(kind: $0.0, label: $0.1, value: $0.2, isMissing: $0.2 == DisplayFormat.missing) }
    }

    /// Replaces `todaySectionMeta` while `stats_stale` (10 §1.3.1); `timeZone` is the server's.
    public static func statsFreshness(_ stats: HomeStats?, timeZone: TimeZone) -> String? {
        guard let stats, stats.statsStale, let updatedAt = stats.statsUpdatedAt else { return nil }
        return "统计更新于 " + DisplayFormat.clock(updatedAt, timeZone: timeZone)
    }

    /// 10 §1.3.5: "可用 3 · 性能下降 1 · 不可用 1 · 未知 1" without the zero counts.
    public static func channelSummaryLine(_ channels: HomeChannels) -> [HomeChannelPart] {
        let parts: [(String, Int, Tone)] = [
            ("可用", channels.healthy, .ok), ("性能下降", channels.warning, .caution), ("不可用", channels.critical, .critical),
            ("未知", channels.unknown, .neutral)
        ]
        return parts.filter { $0.1 > 0 }.map { HomeChannelPart(text: $0.0 + " " + DisplayFormat.grouped($0.1), tone: $0.2) }
    }

    /// 10 §2.4 渠道 title.
    public static func channelCountTitle(_ channels: HomeChannels) -> String { DisplayFormat.grouped(channels.total) + " 个渠道" }

    /// R18, 00 §1.4 step 5. `now` is the phone's clock: token expiry follows local time (D03), not ServerClock.
    public static func sessionRenewalBanner(expiresAt: Date?, now: Date) -> String {
        guard let expiresAt else { return "本次登录无法自动续期，到期后需要重新登录" }
        return "本次登录无法自动续期，约 " + DisplayFormat.minutesLeft(expiresAt.timeIntervalSince(now)) + "后需要重新登录"
    }

    // MARK: Internals

    /// Gregorian `weekday` − 1.
    private static let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// The value of a block whose last read succeeded.
    private static func current<Value: Sendable>(_ state: BlockState<Value>) -> Value? {
        switch state {
        case .loaded(let value, _): value
        case .loading(let previous, _): previous
        case .idle, .disabled, .failed: nil
        }
    }

    static func nonBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

