import Foundation

// 50 §2 分组详情 (S5-06): the page's blocks, refresh table and states, the member list with its today figures, and the key
// counts. The status card's words, the buttons and the menu are S5-02's (GroupCopy, GroupPermissions).

/// 50 §2.2 区块. S5-07 loads capacity, usage, todayUsage, alert and errorCounts.
public enum GroupDetailBlock: String, CaseIterable, Sendable {
    case group, members, memberToday, shortage, stats, capacity, usage, todayUsage, alert, errorCounts
}

public enum GroupDetailTrigger: Sendable, Equatable {
    case enter, pull, poll, foreground, afterWrite
    /// S5-08: a member write's counts are in; the group, members, their today and capacity again.
    case membersWritten
    /// A member's window ended (2.6): the group's counts and the members once.
    case countdown
    /// Back from the alert the banner opened.
    case alertReturn
}

/// 50 §2.6 刷新策略.
public enum GroupDetailRefreshPlan {
    public static let interval: TimeInterval = 60

    /// Entering, pulling, the return to the foreground (in-flight reads were cancelled in the background, D18) and a write read
    /// every block. The 60-second refresh leaves out stats, the usage figures and the 24-hour counts, except a block whose first
    /// read never answered (`unread`: the page covered it meanwhile).
    public static func blocks(for trigger: GroupDetailTrigger, unread: Set<GroupDetailBlock> = []) -> Set<GroupDetailBlock> {
        switch trigger {
        case .enter, .pull, .foreground, .afterWrite: Set(GroupDetailBlock.allCases)
        case .poll: Set<GroupDetailBlock>([.group, .members, .memberToday, .shortage, .capacity, .alert]).union(unread)
        case .membersWritten: [.group, .members, .memberToday, .capacity]
        case .countdown: [.group, .members, .memberToday]
        case .alertReturn: [.alert]
        }
    }
    /// Counted from the end of the last refresh (00 §4.6); never refreshed → now; a clock that went back waits a whole interval.
    public static func delay(sinceLastRefresh elapsed: TimeInterval?) -> TimeInterval {
        guard let elapsed else { return 0 }
        guard elapsed >= 0 else { return interval }
        return max(0, interval - elapsed)
    }
}

/// 50 §2.5. The group comes from the server or, until it answers, from the list's row.
public enum GroupDetailPageState: Sendable, Equatable {
    case skeleton
    case content(banner: String?)
    case failure(message: String)
    /// 404 GROUP_NOT_FOUND / RESOURCE_NOT_FOUND: the whole page says so and the navigation keeps only 返回.
    case deleted

    /// A failed read while only the list's row is shown adds the snapshot banner; once the server answered, a later failure
    /// shows nothing (the next round tries again).
    public static func resolve(hasGroup: Bool, loadedFromServer: Bool, failure: String?, deleted: Bool) -> GroupDetailPageState {
        if deleted { return .deleted }
        if hasGroup { return .content(banner: !loadedFromServer && failure != nil ? GroupDetailCopy.snapshotBanner : nil) }
        if let failure { return .failure(message: failure) }
        return .skeleton
    }
}

public enum GroupDetailCopy {
    /// The 404 page's title (design GvGone).
    public static let deletedTitle = "分组"
    public static let loadFailedTitle = "读取分组失败"
    public static let snapshotBanner = "读取最新数据失败，显示的是列表里的快照"
    public static let membersTitle = "成员账号"
    public static let membersOrdinal = ChineseOrdinal.text(1)
    /// BlockFailureRow adds “ · 重试”.
    public static let membersLoadFailed = "成员加载失败"
    /// Until S5-08's “添加 … 账号” row, and where members cannot be changed.
    public static let membersEmpty = "没有成员账号"
}

/// 50 §2.2 without `accounts.list_query`: 错误 → 过载 → 限流 → 临时不可调度 → 暂停 → 停用 → 正常, then name and id. A window that has
/// ended counts as the state it leaves behind.
public enum GroupMemberOrder {
    public static func sorted(_ rows: [UpstreamAccount], now: Date) -> [UpstreamAccount] {
        rows.map { (rank: rank(AccountDisplayState.scheduleState(AccountStateInput($0), now: now)), row: $0) }
            .sorted { ($0.rank, $0.row.name, $0.row.id) < ($1.rank, $1.row.name, $1.row.id) }
            .map(\.row)
    }
    private static func rank(_ state: AccountScheduleState) -> Int {
        switch state {
        case .error: 0
        case .overloaded: 1
        case .rateLimited: 2
        case .tempUnschedulable: 3
        case .paused: 4
        case .inactive: 5
        case .available: 6
        }
    }
}

/// 50 §2.2 成员: `group=<id>&lite=1&sort_by=urgency`, 100 a page, more as the page scrolls to the end. A refresh reads the pages
/// already shown again and replaces them at once; a repeated id keeps its first row.
public struct GroupMemberList: Sendable {
    public static let pageSize = 100
    /// 2,000 members; past that the page stops asking (the cap the account tab's group filter has too).
    public static let maxPages = 20
    public let rows: [UpstreamAccount]
    /// The server's `total` at the last page read.
    public let total: Int
    public let pagesRead: Int
    /// The server's `pages` at the last page read.
    public let serverPages: Int
    /// The server sorted by urgency (`accounts.list_query`); otherwise every merge sorts again (GroupMemberOrder).
    public let serverSorted: Bool

    public var hasMore: Bool { pagesRead < serverPages && pagesRead < Self.maxPages }
    /// Every member is here, so the F04 fallback can count the errors among them.
    public var isComplete: Bool { rows.count >= total }

    /// R19's one account query; an older server gets `sort_by=name` and the merge sorts.
    public static func query(groupID: Int, supportsListQuery: Bool) -> AccountListQuery {
        AccountListQuery(group: .id(groupID), sort: .urgency, pageSize: pageSize, supportsListQuery: supportsListQuery)
    }
    /// 2.3 the member rows' group names: this group by the page's own row, so “另属” leaves it out even before the session's
    /// directory has loaded (a lite row embeds no names); the others through the directory (C-10), then the row's name or “#id”.
    public static func groupName(_ id: Int, home: AdminGroup, directory: (Int) -> String?) -> String? {
        id == home.id ? home.name : directory(id)
    }
    public init(pages: [AccountListPage], serverSorted: Bool, now: Date) {
        self = GroupMemberList(rows: [], total: 0, pagesRead: 0, serverPages: 0, serverSorted: serverSorted).merging(pages, now: now)
    }
    public func appending(_ page: AccountListPage, now: Date) -> GroupMemberList { merging([page], now: now) }

    private init(rows: [UpstreamAccount], total: Int, pagesRead: Int, serverPages: Int, serverSorted: Bool) {
        self.rows = rows; self.total = total; self.pagesRead = pagesRead; self.serverPages = serverPages; self.serverSorted = serverSorted
    }
    private func merging(_ pages: [AccountListPage], now: Date) -> GroupMemberList {
        var seen = Set(rows.map(\.id)), combined = rows
        for page in pages { combined += page.items.filter { seen.insert($0.id).inserted } }
        return GroupMemberList(rows: serverSorted ? combined : GroupMemberOrder.sorted(combined, now: now), total: pages.last?.total ?? total,
                               pagesRead: pagesRead + pages.count, serverPages: pages.last?.pages ?? serverPages, serverSorted: serverSorted)
    }
}

/// U38: whose today the member rows show.
public enum GroupMemberTodayScope: Sendable, Equatable {
    /// today-stats echoed this group's id: only this group's requests (by the key's group).
    case group
    /// Each account's whole today, on an older server or without `accounts.today_stats_group`.
    case site
}

/// 50 §2.2 成员今日: `user_cost` by account; a failed id or one the reply left out reads “—”.
public struct GroupMemberToday: Sendable {
    public let stats: [Int: AccountTodayStats]
    public let failedIDs: Set<Int>
    /// From the last batch that answered anything; nil until one has (no footnote yet).
    public let scope: GroupMemberTodayScope?
    public static let empty = GroupMemberToday(stats: [:], failedIDs: [], scope: nil)

    private init(stats: [Int: AccountTodayStats], failedIDs: Set<Int>, scope: GroupMemberTodayScope?) {
        self.stats = stats; self.failedIDs = failedIDs; self.scope = scope
    }
    /// The requested ids take the batch's figures; a batch in which everything failed (503 for the whole group) keeps the scope.
    public func merging(_ batch: AccountTodayStatsBatch, requested: [Int], groupID: Int) -> GroupMemberToday {
        let asked = Set(requested)
        var merged = stats.filter { !asked.contains($0.key) }
        for (id, value) in batch.stats where asked.contains(id) { merged[id] = value }
        let answered = !batch.stats.isEmpty || !asked.isSubset(of: batch.failedIDs)
        return GroupMemberToday(stats: merged, failedIDs: failedIDs.subtracting(asked).union(batch.failedIDs.intersection(asked)),
                                scope: answered ? (batch.groupID == groupID ? .group : .site) : scope)
    }
    public func cell(for accountID: Int) -> AccountTodayCell {
        AccountTodayCell(stats: stats[accountID], unavailable: failedIDs.contains(accountID))
    }
}

/// 50 §2.2 Key 与订阅数: groups/:id/stats, or on an older server (F02, no `subscriptions_total`) the two page totals; nil is “—”.
public struct GroupKeyCounts: Sendable, Equatable {
    public let totalAPIKeys: Int?
    public let activeAPIKeys: Int?
    public let subscriptionsTotal: Int?
    public let subscriptionsActive: Int?

    public init(totalAPIKeys: Int?, activeAPIKeys: Int?, subscriptionsTotal: Int?, subscriptionsActive: Int?) {
        self.totalAPIKeys = totalAPIKeys; self.activeAPIKeys = activeAPIKeys
        self.subscriptionsTotal = subscriptionsTotal; self.subscriptionsActive = subscriptionsActive
    }
    public init(_ stats: GroupStats) {
        self.init(totalAPIKeys: stats.totalAPIKeys, activeAPIKeys: stats.activeAPIKeys, subscriptionsTotal: stats.subscriptionsTotal,
                  subscriptionsActive: stats.subscriptionsActive)
    }
    /// `groupAPIKeyCount` and, for a subscription group, `activeSubscriptionCount`; each nil when it failed or was not read.
    public init(fallbackTotalAPIKeys: Int?, activeSubscriptions: Int?) {
        self.init(totalAPIKeys: fallbackTotalAPIKeys, activeAPIKeys: nil, subscriptionsTotal: nil, subscriptionsActive: activeSubscriptions)
    }
    /// stats, else the fallback. Whether the group bills by subscription is asked only then: a page entered from elsewhere learns
    /// it from its own first read, which runs alongside. Still unknown reads the count anyway (its row shows for subscription groups).
    public static func read(stats: @Sendable () async throws -> GroupStats?, apiKeyCount: @Sendable () async throws -> Int,
                            activeSubscriptions: @Sendable () async throws -> Int,
                            isSubscription: @Sendable () async -> Bool?) async throws -> GroupKeyCounts {
        if let stats = try await stats() { return GroupKeyCounts(stats) }
        let keys = try? await apiKeyCount()
        var subscriptions: Int?
        if await isSubscription() != false { subscriptions = try? await activeSubscriptions() }
        return GroupKeyCounts(fallbackTotalAPIKeys: keys, activeSubscriptions: subscriptions)
    }
}

/// What the page takes from the members besides S5-02's words (stopped note, earliest recovery).
public struct GroupMemberSummary: Sendable, Equatable {
    /// The soonest end of any member's running window: the page reads the members and the group's counts once then (2.6).
    public let nextWindowEnd: Date?
    /// At least one row shows 今日 (not 错误, no countdown), as the design's GvMemberNote; no members, no footnote.
    public let showsTodayFootnote: Bool

    public init(members: [GroupMemberSnapshot], now: Date) {
        nextWindowEnd = members.flatMap { [$0.input.overloadUntil, $0.input.rateLimitResetAt, $0.input.tempUnschedulableUntil] }
            .compactMap { $0 }.filter { $0 > now }.min()
        showsTodayFootnote = members.contains { member in
            let display = AccountDisplayState(member.input, now: now)
            return display.state != .error && display.countdownTarget == nil
        }
    }
}

extension AdminGroup {
    /// S5-08: a member write's `counts` over the group (all five, a missing F04 pair included); everything else stays.
    public func applyingCounts(_ counts: GroupAccountCounts) -> AdminGroup {
        var group = self
        group.accountCount = counts.accountCount; group.activeAccountCount = counts.activeAccountCount
        group.rateLimitedAccountCount = counts.rateLimitedAccountCount
        group.errorAccountCount = counts.errorAccountCount; group.idleAccountCount = counts.idleAccountCount
        return group
    }
    /// S5D2a-10: the two differ at most in the five counts.
    public func matchesIgnoringCounts(_ other: AdminGroup) -> Bool { withoutCounts == other.withoutCounts }

    private var withoutCounts: AdminGroup {
        var group = self
        group.accountCount = nil; group.activeAccountCount = nil; group.rateLimitedAccountCount = nil
        group.errorAccountCount = nil; group.idleAccountCount = nil
        return group
    }
}
