import Foundation

/// 50 §1.2–§1.6: GroupStore's pure rules (S5-04), so the store only runs requests and the page only draws.
public enum GroupStoreRules {
    /// 50 §1.6: the list, today's charge and the shortage again every 60 seconds while the page is shown.
    public static let refreshInterval: TimeInterval = 60
    /// 50 §2.2: the detail reuses the list's usage-summary within this long of its last successful read.
    public static let usageMaxAge: TimeInterval = 60

    /// 50 §1.2 按 group_id 合并: the first row of an id is kept; ids below 1 are dropped.
    public static func usageByGroup(_ rows: [GroupUsageSummary]) -> [Int: GroupUsageSummary] {
        rows.filter { $0.groupID > 0 }.reduce(into: [:]) { merged, row in
            if merged[row.groupID] == nil { merged[row.groupID] = row }
        }
    }
    /// D02's `groups[].shortage` by group id (50 §0.2 low).
    public static func shortages(in summary: AccountStatusSummary) -> [Int: AccountStatusGroupSummary.Shortage] {
        summary.groups.reduce(into: [:]) { found, group in
            if found[group.groupID] == nil { found[group.groupID] = group.shortage }
        }
    }
    /// 50 §0.1 F04: without `groups.account_buckets` the error counts come from the account list; with it, only when a group
    /// read lacks `error_account_count` (an older server answered). Before the list arrives that cannot be told yet.
    public static func needsErrorFallback(groups: [AdminGroup]?, hasAccountBuckets: Bool) -> Bool {
        guard hasAccountBuckets else { return true }
        return groups?.contains { $0.errorAccountCount == nil } ?? false
    }
    /// 50 §0.1 退路: `accounts?status=error&lite=1&page_size=1000`, one page. `error` is a single legacy status, so an older
    /// server gets it too.
    public static func errorAccountsQuery(supportsListQuery: Bool) -> AccountListQuery {
        AccountListQuery(statuses: [.error], pageSize: PageSize.maximum, supportsListQuery: supportsListQuery)
    }
    /// 50 §1.2: the site owner's usage-summary uses the server's own zone; a vendor passes the site's.
    public static func usageTimeZone(isVendor: Bool, siteZone: ServerTimeZone) -> ServerTimeZone? { isVendor ? siteZone : nil }
    public static func isFresh(_ loadedAt: Date?, now: Date, maxAge: TimeInterval) -> Bool {
        guard let loadedAt else { return false }
        return now.timeIntervalSince(loadedAt) < maxAge
    }
    /// Local writes made while a list read was out, laid over its result so a late read never undoes them; AdminGroup.displayOrder.
    public static func applying(_ edits: [GroupListEdit], to groups: [AdminGroup]) -> [AdminGroup] {
        edits.reduce(groups) { rows, edit in
            switch edit {
            case .upsert(let group): rows.filter { $0.id != group.id } + [group]
            case .remove(let id): rows.filter { $0.id != id }
            }
        }
        .sorted(by: AdminGroup.displayOrder)
    }
    /// 00 §4.6: counted from the last refresh, doubled after failures, the rest of a 429 wait first.
    public static func autoRefreshDelay(lastRefreshAt: Date?, refresh: BlockRefresh, now: Date) -> TimeInterval {
        UserListPresentation.autoRefreshDelay(lastRefreshAt: lastRefreshAt, refresh: refresh, now: now, base: refreshInterval)
    }
    /// S5-高-3 / S5-中-8: the last refresh failed while an earlier success still shows; not while a refresh is out.
    public static func isStale<Value>(_ state: BlockState<Value>) -> Bool {
        state.display.homePhase == .value(updateFailed: true)
    }
    /// The small text of the list's 更新失败 strip: what it shows from an earlier read, “今日”, “可用状态” or both; nil for neither.
    public static func staleItems(usageStale: Bool, shortagesStale: Bool) -> String? {
        let items = [(usageStale, "今日"), (shortagesStale, "可用状态")].filter(\.0).map(\.1)
        return items.isEmpty ? nil : items.joined(separator: "、")
    }
}

/// A local change to the group list: a written or optimistic row, or a removed id.
public enum GroupListEdit: Sendable, Equatable {
    case upsert(AdminGroup)
    case remove(Int)
}

/// 50 §1.3: a group row as VoiceOver reads it, parts joined by “，”; a missing 今日 reads “今日无数据” (DisplayFormat.missingSpoken).
public enum GroupRowSpeech {
    public enum Today: Sendable, Equatable { case hidden, missing, amount(Decimal) }

    public static func full(name: String, platformName: String, isExclusive: Bool, badge: String?, available: Int, total: Int,
                            breakdown: String?, billingLine: String?, today: Today) -> String {
        let availability = "可用 \(DisplayFormat.grouped(available)) / \(DisplayFormat.grouped(total))"
        let parts = [name, platformName, isExclusive ? GroupFormat.exclusiveText(true) : nil, badge, availability, breakdown, billingLine, todayText(today)]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，")
    }
    /// 60 §2 search results: “测试组，Gemini，已停用”.
    public static func compact(name: String, platformName: String, isInactive: Bool) -> String {
        ([name, platformName] + (isInactive ? [inactiveBadge] : [])).joined(separator: "，")
    }
    /// “已停用”, GroupHealth.off's badge, which does not depend on the buckets.
    public static var inactiveBadge: String { GroupHealth.off.badge(GroupBuckets(GroupAccountCounts())) ?? "" }
    private static func todayText(_ today: Today) -> String? {
        switch today {
        case .hidden: nil
        case .missing: "今日" + DisplayFormat.missingSpoken
        case .amount(let value): "今日 " + DisplayFormat.money(value)
        }
    }
}
