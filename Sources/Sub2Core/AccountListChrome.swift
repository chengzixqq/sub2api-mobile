import Foundation

/// 20 §1.1–§1.5: the account list's navigation subtitle, stale-data banner, platform menu and fixed texts.
public enum AccountListChrome {
    public static let title = "账号"
    public static let emptyText = "没有符合条件的账号"
    public static let failureTitle = "读取账号失败"
    public static let loadingMoreText = "正在加载更多账号…"
    public static let refreshingText = "正在刷新…"
    public static let allPlatformsTitle = "全部平台"

    /// “{站点名} · {counts.all} 个 · {刚刚更新 / N 分钟前更新}”; later than an hour “今天 07:41 更新”, while refreshing “正在刷新…”.
    /// A part without data is left out. `now` and `updatedAt` are site clock times, shown in the server's time zone.
    public static func subtitle(site: String, total: Int?, updatedAt: Date?, isRefreshing: Bool, now: Date, timeZone: TimeZone) -> String {
        var parts = [site]
        if let total { parts.append("\(DisplayFormat.grouped(total)) 个") }
        if isRefreshing { parts.append(refreshingText) }
        else if let updatedAt { parts.append(freshness(updatedAt, now: now, timeZone: timeZone)) }
        return parts.joined(separator: " · ")
    }

    /// “读取失败，显示的是 09:41 的数据”, the time in the server's time zone; “读取失败” when nothing was ever read.
    public static func staleBanner(updatedAt: Date?, timeZone: TimeZone) -> String {
        guard let updatedAt else { return "读取失败" }
        return "读取失败，显示的是 \(DisplayFormat.clock(updatedAt, timeZone: timeZone)) 的数据"
    }

    public static func platformToken(_ name: String) -> String { "平台：\(name)" }
    public static func platformTokenSpoken(_ name: String) -> String { "移除平台筛选 \(name)" }

    /// One entry of the 平台 ▾ menu; `platform` nil is 全部平台.
    public struct PlatformMenuItem: Sendable, Equatable, Identifiable {
        public let platform: String?
        public let title: String
        public let total: Int?
        public var id: String { platform ?? "" }
        /// “4 个”, nil without a number.
        public var detail: String? { total.map { "\(DisplayFormat.grouped($0)) 个" } }
        public init(platform: String?, title: String, total: Int?) { self.platform = platform; self.title = title; self.total = total }
    }

    /// 全部平台, then the site's platforms by status-summary total (more first, then by name, design vaDimValues); without a summary
    /// the loaded rows are counted. A selected platform missing from both stays in the menu without a number.
    public static func platformMenu(summary: [AccountStatusPlatformSummary]?, loaded: [UpstreamAccount], selected: String?, allCount: Int?,
                                    catalog: MetaCatalog?) -> [PlatformMenuItem] {
        let totals: [String: Int] = if let summary {
            Dictionary(summary.filter { $0.counts.total > 0 }.map { ($0.platform, $0.counts.total) }, uniquingKeysWith: { first, _ in first })
        } else {
            Dictionary(grouping: loaded.filter { !$0.platform.isEmpty }, by: \.platform).mapValues(\.count)
        }
        let locale = Locale(identifier: "zh-Hans-CN")
        var items = totals.map { PlatformMenuItem(platform: $0.key, title: AccountNaming.platformName($0.key, catalog: catalog), total: $0.value) }
            .sorted { lhs, rhs in
                if lhs.total != rhs.total { return (lhs.total ?? 0) > (rhs.total ?? 0) }
                let order = lhs.title.compare(rhs.title, locale: locale)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
        if let selected, !selected.isEmpty, totals[selected] == nil {
            items.append(PlatformMenuItem(platform: selected, title: AccountNaming.platformName(selected, catalog: catalog), total: nil))
        }
        return [PlatformMenuItem(platform: nil, title: allPlatformsTitle, total: allCount)] + items
    }

    /// “刚刚更新”, “5 分钟前更新”, “今天 07:41 更新”: a time ends in a digit and takes a space before 更新.
    private static func freshness(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        let relative = DisplayFormat.relativeTime(date, now: now, timeZone: timeZone)
        return relative.last?.isNumber == true ? "\(relative) 更新" : "\(relative)更新"
    }
}
