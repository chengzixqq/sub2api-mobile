import Foundation

/// 20 §1.2 filter chips, in the chip row's order. needs / limited / paused share the raw values of the App's AccountsTabFilter.
public enum AccountListChip: String, CaseIterable, Sendable, Identifiable {
    case needs, all, limited, paused
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .needs: "需处理"
        case .all: "全部"
        case .limited: "受限"
        case .paused: "暂停·停用"
        }
    }
    /// The list's `status` values with `accounts.list_query`.
    public var statuses: Set<AccountStatusFilter> {
        switch self {
        case .needs: [.needsAttention]
        case .all: []
        case .limited: [.overloaded, .rateLimited, .tempUnschedulable]
        case .paused: [.unschedulable, .inactive]
        }
    }
    /// The chip's number from `data.counts` (progress table): needs_attention − error is the three timed buckets, which do not
    /// overlap. nil when a field it needs is missing.
    public func count(in counts: AccountListCounts) -> Int? {
        switch self {
        case .needs: counts.needsAttention
        case .all: counts.all
        case .limited: counts.needsAttention.flatMap { needs in counts.error.map { needs - $0 } }
        case .paused: counts.unschedulable.flatMap { paused in counts.inactive.map { paused + $0 } }
        }
    }
    /// The same chip derived locally by D02 (old servers, fixtures).
    public func includes(_ state: AccountScheduleState) -> Bool {
        switch self {
        case .needs: state.needsAttention
        case .all: true
        case .limited: state.isLimited
        case .paused: state == .paused || state == .inactive
        }
    }
}

/// One text on the right of a platform header (20 §1.3).
public struct AccountSectionFlag: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case stopped, needs, idle }
    public let kind: Kind
    /// “已停止调度 N” / “需处理 N” / “暂停 N · 停用 M”.
    public let text: String
    public let tone: Tone
    public init(kind: Kind, text: String, tone: Tone) { self.kind = kind; self.text = text; self.tone = tone }
}

public struct AccountPlatformSection: Sendable, Identifiable {
    /// The platform id; the page names it through AccountNaming and the catalog.
    public let platform: String
    /// By main group, then the server's order.
    public let rows: [UpstreamAccount]
    public let counts: AccountStateCounts
    /// Counted from the loaded rows: status-summary was unavailable or did not list the platform.
    public let countsAreLocal: Bool
    public let flags: [AccountSectionFlag]
    public let spokenSummary: String
    public var id: String { platform }
    public var total: Int { counts.total }
    public init(platform: String, rows: [UpstreamAccount], counts: AccountStateCounts, countsAreLocal: Bool, flags: [AccountSectionFlag],
                spokenSummary: String) {
        self.platform = platform; self.rows = rows; self.counts = counts; self.countsAreLocal = countsAreLocal
        self.flags = flags; self.spokenSummary = spokenSummary
    }
}

public struct AccountListSections: Sendable {
    public let sections: [AccountPlatformSection]
    /// The order to keep: the given one, then platforms seen for the first time; platforms gone from the rows stay in it.
    public let frozenOrder: [String]
    public init(sections: [AccountPlatformSection], frozenOrder: [String]) { self.sections = sections; self.frozenOrder = frozenOrder }
}

/// An account's place inside its platform: the known group with the lowest sort_order, then unknown groups, then none.
public enum AccountMainGroup: Comparable, Sendable {
    case known(sortOrder: Int, id: Int)
    case unknown
    case ungrouped
}

/// 20 §1.2–§1.3: the account list's query, platform sections, header texts and the 2,000-row note.
public enum AccountListLayout {
    public static let pageSize = AccountListQuery.defaultPageSize
    /// U15.
    public static let rowLimit = 2000

    /// Without `accounts.list_query` no new parameter goes out (00 §5): every row is read by name and the chip is applied locally.
    public static func listQuery(chip: AccountListChip, platform: String, groupID: Int?, supportsListQuery: Bool) -> AccountListQuery {
        AccountListQuery(platform: platform.trimmingCharacters(in: .whitespacesAndNewlines), group: groupID.map { .id($0) },
                         statuses: supportsListQuery ? chip.statuses : [], sort: supportsListQuery ? .urgency : .name, pageSize: pageSize,
                         includeCounts: supportsListQuery, supportsListQuery: supportsListQuery)
    }

    /// Header numbers describe the whole platform (status-summary), whatever the chip; a platform the summary lacks is counted
    /// from its loaded rows, which outside “全部” gives only the number of accounts (20 §1.2).
    public static func sections(rows: [UpstreamAccount], chip: AccountListChip, summary: AccountStatusSummary?, groups: [AdminGroup],
                                frozenOrder: [String]?, now: Date) -> AccountListSections {
        let byPlatform = Dictionary(grouping: rows, by: \.platform)
        let reported = Dictionary((summary?.platforms ?? []).map { ($0.platform, $0.counts) }, uniquingKeysWith: { first, _ in first })
        let counts = Dictionary(uniqueKeysWithValues: byPlatform.map { platform, platformRows in
            (platform, reported[platform] ?? localCounts(platformRows, now: now))
        })
        let order = platformOrder(counts, frozen: frozenOrder)
        let directory = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sections = order.visible.map { platform in
            let isLocal = reported[platform] == nil, platformCounts = counts[platform] ?? AccountStateCounts()
            let showsFlags = !isLocal || chip == .all
            return AccountPlatformSection(platform: platform, rows: groupedRows(byPlatform[platform] ?? [], groups: directory), counts: platformCounts,
                                          countsAreLocal: isLocal, flags: showsFlags ? flags(for: platformCounts) : [],
                                          spokenSummary: spokenSummary(for: platformCounts, showsFlags: showsFlags))
        }
        return AccountListSections(sections: sections, frozenOrder: order.frozen)
    }

    /// Without a frozen order: rank, then more needing attention, more accounts, platform id (the spec stops at the totals).
    public static func platformOrder(_ counts: [String: AccountStateCounts], frozen: [String]?) -> (visible: [String], frozen: [String]) {
        let ranked = counts.keys.sorted { lhs, rhs in
            let a = counts[lhs] ?? AccountStateCounts(), b = counts[rhs] ?? AccountStateCounts()
            return (platformRank(a), -a.needsAttention, -a.total, lhs) < (platformRank(b), -b.needsAttention, -b.total, rhs)
        }
        guard let frozen else { return (ranked, ranked) }
        let kept = Set(frozen), added = ranked.filter { !kept.contains($0) }
        return (frozen.filter { counts[$0] != nil } + added, frozen + added)
    }

    /// 0 error or overload, 1 other needing attention, 3 all paused or disabled, 2 the rest.
    public static func platformRank(_ counts: AccountStateCounts) -> Int {
        if counts.error + counts.overloaded > 0 { return 0 }
        if counts.needsAttention > 0 { return 1 }
        return counts.total > 0 && counts.paused + counts.inactive == counts.total ? 3 : 2
    }

    public static func localCounts(_ rows: [UpstreamAccount], now: Date) -> AccountStateCounts {
        var buckets = [AccountScheduleState: Int](), stopped = 0
        for row in rows {
            let display = AccountDisplayState(row, now: now)
            buckets[display.state, default: 0] += 1
            if display.isStopped { stopped += 1 }
        }
        return AccountStateCounts(total: rows.count, available: buckets[.available] ?? 0, error: buckets[.error] ?? 0,
                                  overloaded: buckets[.overloaded] ?? 0, rateLimited: buckets[.rateLimited] ?? 0,
                                  tempUnschedulable: buckets[.tempUnschedulable] ?? 0, paused: buckets[.paused] ?? 0,
                                  inactive: buckets[.inactive] ?? 0, stopped: stopped)
    }
    public static func localPlatformCounts(_ rows: [UpstreamAccount], now: Date) -> [String: AccountStateCounts] {
        Dictionary(grouping: rows, by: \.platform).mapValues { localCounts($0, now: now) }
    }

    /// sort_order as AdminGroup.displayOrder reads it (missing = 0), then id.
    public static func mainGroup(of account: UpstreamAccount, groups: [Int: AdminGroup]) -> AccountMainGroup {
        guard !account.groupIDs.isEmpty else { return .ungrouped }
        let known = account.groupIDs.compactMap { groups[$0] }.map { AccountMainGroup.known(sortOrder: $0.sortOrder ?? 0, id: $0.id) }
        return known.min() ?? .unknown
    }
    /// Stable by construction: the server's urgency order breaks every tie.
    public static func groupedRows(_ rows: [UpstreamAccount], groups: [Int: AdminGroup]) -> [UpstreamAccount] {
        rows.enumerated().map { (key: mainGroup(of: $0.element, groups: groups), index: $0.offset, row: $0.element) }
            .sorted { ($0.key, $0.index) < ($1.key, $1.index) }.map(\.row)
    }

    public static func flags(for counts: AccountStateCounts) -> [AccountSectionFlag] {
        if counts.needsAttention > 0 {
            let stopped = counts.stopped > 0
                ? [AccountSectionFlag(kind: .stopped, text: "\(AccountDisplayState.stoppedMark) \(DisplayFormat.grouped(counts.stopped))", tone: .neutral)] : []
            let tone: Tone = counts.error + counts.overloaded > 0 ? .critical : .caution
            return stopped + [AccountSectionFlag(kind: .needs, text: "需处理 \(DisplayFormat.grouped(counts.needsAttention))", tone: tone)]
        }
        guard let idle = idleText(counts) else { return [] }
        return [AccountSectionFlag(kind: .idle, text: idle, tone: .neutral)]
    }
    /// The header's VoiceOver text: “4 个，需处理 2，其中已停止调度 1” / “3 个，暂停 2 · 停用 1” / “5 个”.
    public static func spokenSummary(for counts: AccountStateCounts, showsFlags: Bool) -> String {
        let total = "\(DisplayFormat.grouped(counts.total)) 个"
        guard showsFlags else { return total }
        if counts.needsAttention > 0 {
            let stopped = counts.stopped > 0 ? "，其中\(AccountDisplayState.stoppedMark) \(DisplayFormat.grouped(counts.stopped))" : ""
            return "\(total)，需处理 \(DisplayFormat.grouped(counts.needsAttention))\(stopped)"
        }
        return idleText(counts).map { "\(total)，\($0)" } ?? total
    }
    /// “暂停 N · 停用 M” when every account is paused or disabled; a zero part is left out, as in the design's vaIdleText.
    private static func idleText(_ counts: AccountStateCounts) -> String? {
        guard counts.total > 0, counts.paused + counts.inactive == counts.total else { return nil }
        let parts = [(counts.paused, "暂停"), (counts.inactive, "停用")].filter { $0.0 > 0 }.map { "\($0.1) \(DisplayFormat.grouped($0.0))" }
        return parts.joined(separator: " · ")
    }

    /// Only when the 2,000-row cap left rows out (U15); pages cut short or rows that moved while read are not the cap's doing.
    public static func overflowNote(total: Int?, loaded: Int) -> String? {
        guard let total, loaded >= rowLimit, total > loaded else { return nil }
        return "还有 \(DisplayFormat.grouped(total - loaded)) 个账号未加载，用平台筛选缩小范围"
    }
}

extension AccountListQuery {
    /// 20 §0.5: a server that rejects the status values is read as an old one for the rest of the session, once. INVALID_GROUP_FILTER
    /// is not retried: dropping the group would turn a group's accounts into every account.
    public static func shouldFallBackToLegacy(after error: any Error) -> Bool {
        guard let error = error as? APIError else { return false }
        return error.statusCode == 400 && error.reason == "INVALID_ACCOUNT_STATUS_FILTER"
    }
}

/// Old servers (no `accounts.list_query`) and the UI fixtures derive the list here, by D02 (20 §0.2).
/// Where this differs from the server's predicates (account_list_status.go), the page follows D02, like its rows and headers, and
/// says nothing: `unschedulable` there also takes an overloaded account switched off (D02: 过载中) and leaves out an expired
/// auto-pause the background task has not switched off yet (D02: 暂停); `inactive` there is only `status=inactive` (D02 also
/// counts `disabled` and unknown values); `active` there ignores an overload window. Names compare as Swift strings, not by the
/// database collation.
public enum AccountListLocal {
    public static func matches(_ account: UpstreamAccount, query: AccountListQuery, now: Date) -> Bool {
        let search = AccountListQuery.searchValue(query.search)
        if !search.isEmpty, account.name.range(of: search, options: .caseInsensitive) == nil { return false }
        if !query.platform.isEmpty, account.platform != query.platform { return false }
        if !query.type.isEmpty, account.type != query.type { return false }
        switch query.group {
        case .id(let id)? where !account.groupIDs.contains(id): return false
        case .ungrouped? where !account.groupIDs.isEmpty: return false
        default: break
        }
        return query.statuses.isEmpty || matches(AccountDisplayState.scheduleState(AccountStateInput(account), now: now), statuses: query.statuses)
    }
    /// Empty matches everything; otherwise any one value.
    public static func matches(_ state: AccountScheduleState, statuses: Set<AccountStatusFilter>) -> Bool {
        statuses.isEmpty || statuses.contains { status in
            switch status {
            case .needsAttention: state.needsAttention
            case .error: state == .error
            case .overloaded: state == .overloaded
            case .rateLimited: state == .rateLimited
            case .tempUnschedulable: state == .tempUnschedulable
            case .unschedulable: state == .paused
            case .inactive: state == .inactive
            case .active, .schedulableNow: state == .available
            }
        }
    }
    public static func filter(_ rows: [UpstreamAccount], chip: AccountListChip, now: Date) -> [UpstreamAccount] {
        guard chip != .all else { return rows }
        return rows.filter { chip.includes(AccountDisplayState.scheduleState(AccountStateInput($0), now: now)) }
    }
    /// `data.counts` of the same rows.
    public static func counts(_ rows: [UpstreamAccount], now: Date) -> AccountListCounts {
        let c = AccountListLayout.localCounts(rows, now: now)
        return AccountListCounts(all: c.total, needsAttention: c.needsAttention, error: c.error, overloaded: c.overloaded, rateLimited: c.rateLimited,
                                 tempUnschedulable: c.tempUnschedulable, unschedulable: c.paused, inactive: c.inactive, schedulableNow: c.available)
    }
    /// The server's `sort_by=urgency` (accountUrgencyOrder): error, timed windows by their latest end, paused, other inactive,
    /// available; then name and id. Descending reverses every key.
    public static func urgencySorted(_ rows: [UpstreamAccount], now: Date, descending: Bool = false) -> [UpstreamAccount] {
        let keyed = rows.map { row -> (rank: Int, recovery: Date, row: UpstreamAccount) in
            let input = AccountStateInput(row)
            let state = AccountDisplayState.scheduleState(input, now: now)
            return (urgencyRank(state), recovery(input, now: now) ?? .distantPast, row)
        }
        let sorted = keyed.sorted { lhs, rhs in
            (lhs.rank, lhs.recovery, lhs.row.name, lhs.row.id) < (rhs.rank, rhs.recovery, rhs.row.name, rhs.row.id)
        }.map(\.row)
        return descending ? sorted.reversed() : sorted
    }
    static func urgencyRank(_ state: AccountScheduleState) -> Int {
        switch state {
        case .error: 0
        case .overloaded, .rateLimited, .tempUnschedulable: 1
        case .paused: 2
        case .inactive: 3
        case .available: 4
        }
    }
    /// GREATEST of the three windows; with one still running that is the latest end of those running.
    static func recovery(_ input: AccountStateInput, now: Date) -> Date? {
        let running = [input.overloadUntil, input.rateLimitResetAt, input.tempUnschedulableUntil].compactMap { $0 }.filter { $0 > now }
        return running.max()
    }
}
