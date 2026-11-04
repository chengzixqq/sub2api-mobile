import Foundation
import Sub2Core

/// 50 §1 `-ui-testing` (X44): the group pages' own fixture data — the list, today's charge, D02's shortage and the launch
/// arguments every group test shares — plus the four write entry points (S5D2a-11). The groups are DemoData.accountGroups (X11);
/// their four buckets are counted from the session's demo accounts on every read, so member writes and account actions stay in
/// step. One per session (`current(for:)`); later items extend it only in GroupFixtures+<topic>.swift.
@MainActor
final class GroupFixtures {
    enum Argument {
        /// The first `GET admin/groups` answers 502; later ones work.
        static let listFailure = "-ui-group-list-failure"
        /// The first `GET admin/groups` works; later ones answer 502.
        static let refreshFailure = "-ui-group-refresh-failure"
        /// Every usage-summary answers 502.
        static let usageFailure = "-ui-group-usage-failure"
        /// Every usage-summary answers only after `slowUsageDelay` (an aggregate that takes long).
        static let usageSlow = "-ui-group-usage-slow"
        /// The first usage-summary works; later ones answer 502 (the list keeps 今日, S5-高-3).
        static let usageFailureAfterFirst = "-ui-group-usage-failure-after-first"
        /// The list's first status-summary works; later ones answer 502 (the list keeps 可用偏低, S5-中-8).
        static let shortageFailureAfterFirst = "-ui-group-shortage-failure-after-first"
        /// The first usage-summary works, the second answers 502 and later ones fail only after `slowUsageDelay` (a retry that hangs).
        static let usageFailureThenSlow = "-ui-group-usage-failure-then-slow"
        /// The first usage-summary works, the second answers 429 (retry_after 60) and later ones work (00 §2.7.2).
        static let usageThrottledAfterFirst = "-ui-group-usage-throttled-after-first"
        /// The site has no group.
        static let empty = "-ui-group-empty"
        /// Followed by attention, normal or off: the list opened without a segment scrolls to that section (X39).
        static let segment = "-ui-group-segment"
    }

    /// DEMO.groups[].usage (today, yesterday, total); a group not listed spent nothing.
    static let usage: [Int: (today: Decimal, yesterday: Decimal, total: Decimal)] = [
        1: amounts("933.3", "2985.6", "186420.55"), 2: amounts("203.5", "498.2", "41310.08"), 3: amounts("38.6", "121.3", "9204.33"),
        4: amounts("0", "312.5", "22386.2"), 5: amounts("52.75", "171.4", "6630.4"), 6: amounts("10.8", "20.5", "912.6"),
        7: amounts("18.4", "38.7", "1288.1"), 8: amounts("27.15", "64.8", "2140.6"), 9: amounts("0", "0", "386.25")
    ]
    /// 标准组 has a group-availability alert rule at 60%, so its 1 of 2 reads 可用偏低; the others use the site default 50%.
    static let alertRuleGroupID = 2
    static let alertRuleRatio = 0.6
    /// Longer than the list page's 60-second refresh and any wait of a test that uses `-ui-group-usage-slow`.
    static let slowUsageDelay: Duration = .seconds(300)

    /// This session's groups without live counts; writes and later items' extensions change it.
    var groups: [AdminGroup]
    private(set) var listReads = 0
    private var usageReads = 0
    private var shortageReads = 0
    private let arguments: [String]
    private static var latest: (generation: UUID, fixtures: GroupFixtures)?
    private static let failure = APIError.server(status: 502, reason: nil)
    private static let throttled = APIError.server(status: 429, envelope: nil, retryAfter: 60)

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
        groups = arguments.contains(Argument.empty) ? [] : DemoData.accountGroups
    }
    /// Only the newest session's fixtures are kept.
    static func current(for generation: UUID, arguments: [String] = ProcessInfo.processInfo.arguments) -> GroupFixtures {
        if let latest, latest.generation == generation { return latest.fixtures }
        let fixtures = GroupFixtures(arguments: arguments)
        latest = (generation, fixtures)
        return fixtures
    }
    static func launchSegment(arguments: [String] = ProcessInfo.processInfo.arguments) -> GroupListSegment? {
        guard let index = arguments.firstIndex(of: Argument.segment), index + 1 < arguments.count else { return nil }
        return GroupListSegment(rawValue: arguments[index + 1])
    }

    /// `-ui-without-capabilities groups.account_buckets`: the groups come without error / idle, as from an older server.
    var withholdsAccountBuckets: Bool {
        UITestArguments.withheldCapabilities(arguments: arguments).contains(Capability.groupsAccountBuckets.rawValue)
    }
    /// The four buckets of `group`'s members (50 §0.2, S5-02's D02 → F04 counting).
    func counted(_ group: AdminGroup, accounts: [UpstreamAccount], now: Date) -> AdminGroup {
        let members = accounts.filter { $0.groupIDs.contains(group.id) }
        let counts = GroupAccountCounts.counting(members.map { AccountDisplayState($0, now: now) })
        var row = group
        row.accountCount = counts.accountCount; row.activeAccountCount = counts.activeAccountCount
        row.rateLimitedAccountCount = counts.rateLimitedAccountCount
        row.errorAccountCount = withholdsAccountBuckets ? nil : counts.errorAccountCount
        row.idleAccountCount = withholdsAccountBuckets ? nil : counts.idleAccountCount
        return row
    }
    /// Every group with live counts, in the server's order; the group directory reads this too.
    func list(accounts: [UpstreamAccount], now: Date) -> [AdminGroup] {
        groups.sorted(by: AdminGroup.displayOrder).map { counted($0, accounts: accounts, now: now) }
    }
    /// `GET admin/groups`, with the list's failure arguments.
    func readList(accounts: [UpstreamAccount], now: Date) throws -> [AdminGroup] {
        listReads += 1
        if arguments.contains(Argument.listFailure), listReads == 1 { throw Self.failure }
        if arguments.contains(Argument.refreshFailure), listReads > 1 { throw Self.failure }
        return list(accounts: accounts, now: now)
    }
    /// `GET admin/groups/:id`.
    func group(id: Int, accounts: [UpstreamAccount], now: Date) throws -> AdminGroup {
        guard let group = groups.first(where: { $0.id == id }) else { throw APIError.server(status: 404, reason: "GROUP_NOT_FOUND") }
        return counted(group, accounts: accounts, now: now)
    }
    /// `GET admin/groups/usage-summary`: a row for every group, as the backend's LEFT JOIN gives.
    func usageSummary() async throws -> [GroupUsageSummary] {
        usageReads += 1
        let read = usageReads
        if arguments.contains(Argument.usageSlow) { try await Task.sleep(for: Self.slowUsageDelay) }
        if arguments.contains(Argument.usageFailure) { throw Self.failure }
        if arguments.contains(Argument.usageFailureAfterFirst), read > 1 { throw Self.failure }
        if arguments.contains(Argument.usageFailureThenSlow), read > 1 {
            if read > 2 { try await Task.sleep(for: Self.slowUsageDelay) }
            throw Self.failure
        }
        if arguments.contains(Argument.usageThrottledAfterFirst), read == 2 { throw Self.throttled }
        return groups.map { group in
            let row = Self.usage[group.id] ?? (0, 0, 0)
            return GroupUsageSummary(groupID: group.id, todayCost: row.today, yesterdayCost: row.yesterday, totalCost: row.total)
        }
    }
    /// D02's `groups[].shortage`: 标准组 by its alert rule, the others by the site's default ratio.
    func shortages(accounts: [UpstreamAccount], now: Date) -> [Int: AccountStatusGroupSummary.Shortage] {
        Dictionary(uniqueKeysWithValues: list(accounts: accounts, now: now).map { ($0.id, Self.shortage($0)) })
    }
    /// The list's status-summary read, with its failure argument.
    func readShortages(accounts: [UpstreamAccount], now: Date) throws -> [Int: AccountStatusGroupSummary.Shortage] {
        shortageReads += 1
        if arguments.contains(Argument.shortageFailureAfterFirst), shortageReads > 1 { throw Self.failure }
        return shortages(accounts: accounts, now: now)
    }

    // MARK: 写入口（S5D2a-11）

    /// `POST admin/groups`: a new active group after the others; an exact name already used answers 409 GROUP_EXISTS.
    func createGroup(_ request: GroupCreateRequest, accounts: [UpstreamAccount], now: Date) throws -> AdminGroup {
        try request.validate()
        guard !groups.contains(where: { $0.name == request.name }) else { throw APIError.server(status: 409, reason: "GROUP_EXISTS") }
        let id = (groups.map(\.id).max() ?? 0) + 1
        let row = AdminGroup(id: id, name: request.name, description: request.description, platform: request.platform, status: "active",
                             rateMultiplier: request.rateMultiplier, isExclusive: request.isExclusive, subscriptionType: request.subscriptionType,
                             dailyLimitUSD: Self.value(request.dailyLimitUSD), weeklyLimitUSD: Self.value(request.weeklyLimitUSD),
                             monthlyLimitUSD: Self.value(request.monthlyLimitUSD), rpmLimit: request.rpmLimit, billingLocked: false, sortOrder: id,
                             claudeCodeOnly: false)
        groups.append(row)
        return counted(row, accounts: accounts, now: now)
    }
    /// `PUT admin/groups/:id`: only the fields sent change; a name another group has answers 409 GROUP_EXISTS.
    func updateGroup(id: Int, _ request: GroupUpdateRequest, accounts: [UpstreamAccount], now: Date) throws -> AdminGroup {
        try request.validate()
        guard let index = groups.firstIndex(where: { $0.id == id }) else { throw APIError.server(status: 404, reason: "GROUP_NOT_FOUND") }
        if let name = request.name, groups.contains(where: { $0.id != id && $0.name == name }) {
            throw APIError.server(status: 409, reason: "GROUP_EXISTS")
        }
        groups[index] = Self.applying(request, to: groups[index])
        return counted(groups[index], accounts: accounts, now: now)
    }
    func removeGroup(id: Int) { groups.removeAll { $0.id == id } }
    /// `GET admin/groups?search=&platform=`: the name or description contains the text, ignoring case, on that platform.
    func searchGroups(name: String, platform: String, accounts: [UpstreamAccount], now: Date) -> [AdminGroup] {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return list(accounts: accounts, now: now).filter { group in
            group.platform == platform && (needle.isEmpty || [group.name, group.description ?? ""].contains { $0.localizedCaseInsensitiveContains(needle) })
        }
    }

    private static func applying(_ request: GroupUpdateRequest, to group: AdminGroup) -> AdminGroup {
        var row = group
        if let name = request.name { row.name = name }
        if let description = request.description { row.description = description }
        if let rate = request.rateMultiplier { row.rateMultiplier = rate }
        if let exclusive = request.isExclusive { row.isExclusive = exclusive }
        if let status = request.status { row.status = status }
        if let type = request.subscriptionType { row.subscriptionType = type }
        if let rpm = request.rpmLimit { row.rpmLimit = rpm }
        if let limit = request.dailyLimitUSD { row.dailyLimitUSD = value(limit) }
        if let limit = request.weeklyLimitUSD { row.weeklyLimitUSD = value(limit) }
        if let limit = request.monthlyLimitUSD { row.monthlyLimitUSD = value(limit) }
        return row
    }
    private static func shortage(_ group: AdminGroup) -> AccountStatusGroupSummary.Shortage {
        let total = group.accountCount ?? 0, available = group.activeAccountCount ?? 0
        guard group.id == alertRuleGroupID else { return HomeFallback.shortage(available: available, total: total) }
        let share = total > 0 ? Double(available) / Double(total) : 0
        return .init(isShort: available == 0 || share < alertRuleRatio, source: "alert_rule", metricType: "group_available_ratio", comparison: "<",
                     threshold: alertRuleRatio * 100, current: share * 100)
    }
    private static func amounts(_ today: String, _ yesterday: String, _ total: String) -> (today: Decimal, yesterday: Decimal, total: Decimal) {
        (Decimal(string: today) ?? 0, Decimal(string: yesterday) ?? 0, Decimal(string: total) ?? 0)
    }
    private static func value(_ change: GroupLimitChange) -> Decimal? {
        switch change {
        case .unlimited: nil
        case .amount(let amount): amount
        }
    }
}

extension AppModel {
    /// The group directory's `-ui-testing` rows: this session's fixture groups with live counts (S5D2a-11).
    func fixtureGroupDirectory() -> [AdminGroup] {
        GroupFixtures.current(for: sessionGeneration).list(accounts: accountDemo.accounts, now: accountFixtureNow())
    }
}
