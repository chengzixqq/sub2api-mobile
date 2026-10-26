import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func stamp(_ seconds: TimeInterval) -> String { ServerTime.utcTimestamp(now.addingTimeInterval(seconds)) }

/// Accounts are decoded from wire JSON, like the list reply.
private func row(_ id: Int, name: String? = nil, platform: String = "anthropic", type: String = "apikey", status: String = "active",
                 schedulable: Bool = true, groups: [Int] = [], extra fields: [String: Any] = [:]) throws -> UpstreamAccount {
    var json: [String: Any] = ["id": id, "name": name ?? "账号-\(id)", "platform": platform, "type": type, "status": status,
                               "schedulable": schedulable, "group_ids": groups]
    json.merge(fields) { _, new in new }
    return try JSONDecoder().decode(UpstreamAccount.self, from: JSONSerialization.data(withJSONObject: json))
}

/// One row per D02 state, plus a stopped rate limit (2) and an expired auto-pause (6); 7 is the historical `disabled`.
private func eightStates() throws -> [UpstreamAccount] {
    [try row(1, status: "error", schedulable: false),
     try row(2, schedulable: false, extra: ["rate_limit_reset_at": stamp(300)]),
     try row(3, extra: ["overload_until": stamp(60)]),
     try row(4, extra: ["temp_unschedulable_until": stamp(600)]),
     try row(5, schedulable: false),
     try row(6, extra: ["auto_pause_on_expired": true, "expires_at": Int(now.timeIntervalSince1970) - 100]),
     try row(7, status: "disabled"),
     try row(8)]
}

private func items(_ chip: AccountListChip, supports: Bool, page: Int = 1, platform: String = "", group: Int? = nil) throws -> [String: String] {
    let query = AccountListLayout.listQuery(chip: chip, platform: platform, groupID: group, supportsListQuery: supports)
    return Dictionary(uniqueKeysWithValues: try query.queryItems(page: page).map { ($0.name, $0.value ?? "") })
}

// MARK: - Chips (20 §1.2)

@Test func chipMapsToStatusFiltersAndTitles() {
    #expect(AccountListChip.allCases.map(\.rawValue) == ["needs", "all", "limited", "paused"])
    #expect(AccountListChip.allCases.map(\.title) == ["需处理", "全部", "受限", "暂停·停用"])
    #expect(AccountListChip.needs.statuses == [.needsAttention])
    #expect(AccountListChip.all.statuses.isEmpty)
    #expect(AccountListChip.limited.statuses == [.overloaded, .rateLimited, .tempUnschedulable])
    #expect(AccountListChip.paused.statuses == [.unschedulable, .inactive])
}

@Test func chipCountsFollowProgressTableFormulas() {
    let counts = AccountListCounts(all: 11, needsAttention: 4, error: 1, overloaded: 1, rateLimited: 1, tempUnschedulable: 1,
                                   unschedulable: 1, inactive: 1, schedulableNow: 5)
    #expect(AccountListChip.allCases.map { $0.count(in: counts) } == [4, 11, 3, 2])
    let partial = AccountListCounts(all: 11, needsAttention: 4)
    #expect(AccountListChip.allCases.map { $0.count(in: partial) } == [4, 11, nil, nil])
    #expect(AccountListChip.allCases.map { $0.count(in: AccountListCounts()) } == [nil, nil, nil, nil])
}

@Test(arguments: AccountScheduleState.allCases)
func chipIncludesLocalStates(_ state: AccountScheduleState) {
    let limited: Set<AccountScheduleState> = [.overloaded, .rateLimited, .tempUnschedulable]
    #expect(AccountListChip.needs.includes(state) == (limited.contains(state) || state == .error))
    #expect(AccountListChip.all.includes(state))
    #expect(AccountListChip.limited.includes(state) == limited.contains(state))
    #expect(AccountListChip.paused.includes(state) == (state == .paused || state == .inactive))
}

@Test func listQuerySendsNewParametersOnlyWithListQueryCapability() throws {
    let needs = try items(.needs, supports: true)
    #expect(needs["status"] == "needs_attention" && needs["sort_by"] == "urgency" && needs["sort_order"] == "asc")
    #expect(needs["include_counts"] == "1" && needs["page_size"] == "500" && needs["lite"] == "1")
    #expect(try items(.limited, supports: true)["status"] == "overloaded,rate_limited,temp_unschedulable")
    #expect(try items(.paused, supports: true)["status"] == "unschedulable,inactive")
    #expect(try items(.all, supports: true)["status"] == nil)
    #expect(try items(.needs, supports: true, page: 2)["include_counts"] == nil)
    let legacy = try items(.limited, supports: false)
    #expect(legacy["status"] == nil && legacy["include_counts"] == nil && legacy["sort_by"] == "name" && legacy["page_size"] == "500")
    #expect(try items(.all, supports: true, platform: "  anthropic ")["platform"] == "anthropic")
    #expect(try items(.all, supports: true, platform: "   ")["platform"] == nil)
    #expect(try items(.all, supports: true, group: 5)["group"] == "5")
    let query = AccountListLayout.listQuery(chip: .paused, platform: " openai ", groupID: nil, supportsListQuery: false)
    #expect(query.platform == "openai" && query.statuses.isEmpty && !query.supportsListQuery && query.sort == .name && !query.includeCounts)
}

@Test func onlyAnInvalidStatusFilterFallsBackToTheLegacyList() {
    #expect(AccountListQuery.shouldFallBackToLegacy(after: APIError.server(status: 400, reason: "INVALID_ACCOUNT_STATUS_FILTER")))
    #expect(!AccountListQuery.shouldFallBackToLegacy(after: APIError.server(status: 400, reason: "INVALID_GROUP_FILTER")))
    #expect(!AccountListQuery.shouldFallBackToLegacy(after: APIError.server(status: 502, reason: nil)))
    #expect(!AccountListQuery.shouldFallBackToLegacy(after: CancellationError()))
}

// MARK: - Sections (20 §1.3)

@Test(arguments: [
    (AccountStateCounts(total: 3, available: 2, error: 1), 0),
    (AccountStateCounts(total: 2, available: 1, overloaded: 1), 0),
    (AccountStateCounts(total: 2, available: 1, rateLimited: 1), 1),
    (AccountStateCounts(total: 2, available: 1, tempUnschedulable: 1), 1),
    (AccountStateCounts(total: 5, available: 5), 2),
    (AccountStateCounts(total: 3, paused: 2, inactive: 1), 3),
    (AccountStateCounts(total: 3, available: 2, paused: 1), 2),
    (AccountStateCounts(), 2)
])
func platformRankFollowsSectionOrderTable(_ counts: AccountStateCounts, _ rank: Int) {
    #expect(AccountListLayout.platformRank(counts) == rank)
}

@Test func platformOrderBreaksTiesByNeedsThenTotalThenID() {
    let order = AccountListLayout.platformOrder([
        "kimi": AccountStateCounts(total: 2, available: 1, rateLimited: 1),
        "openai": AccountStateCounts(total: 4, available: 2, rateLimited: 2),
        "gemini": AccountStateCounts(total: 5, available: 4, tempUnschedulable: 1),
        "deepseek": AccountStateCounts(total: 2, available: 1, rateLimited: 1),
        "grok": AccountStateCounts(total: 1, inactive: 1),
        "zhipu": AccountStateCounts(total: 9, available: 9)
    ], frozen: nil)
    #expect(order.visible == ["openai", "gemini", "deepseek", "kimi", "zhipu", "grok"])
    #expect(order.frozen == order.visible)
}

@Test func frozenOrderKeepsSectionsAndAppendsNewPlatforms() {
    let order = AccountListLayout.platformOrder([
        "anthropic": AccountStateCounts(total: 1, available: 1),
        "openai": AccountStateCounts(total: 1, available: 1),
        "zhipu": AccountStateCounts(total: 1, error: 1),
        "kimi": AccountStateCounts(total: 2, available: 2)
    ], frozen: ["openai", "anthropic", "gemini"])
    #expect(order.visible == ["openai", "anthropic", "zhipu", "kimi"])
    #expect(order.frozen == ["openai", "anthropic", "gemini", "zhipu", "kimi"])
}

@Test func nilFrozenOrderRanksAgain() throws {
    let rows = [try row(1, platform: "openai"), try row(2, platform: "zhipu", status: "error", schedulable: false)]
    let result = AccountListLayout.sections(rows: rows, chip: .all, summary: nil, groups: [], frozenOrder: nil, now: now)
    #expect(result.sections.map(\.platform) == ["zhipu", "openai"])
    let kept = AccountListLayout.sections(rows: rows, chip: .all, summary: nil, groups: [], frozenOrder: ["openai"], now: now)
    #expect(kept.sections.map(\.platform) == ["openai", "zhipu"])
}

@Test func summaryCountsDescribeWholePlatformUnderAnyChip() throws {
    let rows = [try row(1, extra: ["rate_limit_reset_at": stamp(60)]), try row(2, status: "error", schedulable: false)]
    let summary = AccountStatusSummary(platforms: [
        AccountStatusPlatformSummary(platform: "anthropic", counts: AccountStateCounts(total: 4, available: 2, error: 1, rateLimited: 1))
    ])
    let result = AccountListLayout.sections(rows: rows, chip: .needs, summary: summary, groups: [], frozenOrder: nil, now: now)
    let section = try #require(result.sections.first)
    #expect(section.platform == "anthropic" && section.id == "anthropic" && section.total == 4 && !section.countsAreLocal)
    #expect(section.flags.map(\.text) == ["需处理 2"] && section.flags.map(\.tone) == [.critical])
    #expect(section.rows.map(\.id) == [1, 2])
    #expect(section.spokenSummary == "4 个，需处理 2")
}

@Test func platformMissingFromSummaryFallsBackToLocalCounts() throws {
    let rows = [try row(1), try row(2, platform: "kimi", extra: ["overload_until": stamp(30)])]
    let summary = AccountStatusSummary(platforms: [AccountStatusPlatformSummary(platform: "anthropic", counts: AccountStateCounts(total: 9, available: 9))])
    let result = AccountListLayout.sections(rows: rows, chip: .all, summary: summary, groups: [], frozenOrder: nil, now: now)
    let kimi = try #require(result.sections.first { $0.platform == "kimi" })
    #expect(kimi.countsAreLocal && kimi.counts == AccountStateCounts(total: 1, overloaded: 1))
    #expect(result.sections.map(\.platform) == ["kimi", "anthropic"])
    #expect(result.frozenOrder == ["kimi", "anthropic"])
}

@Test func localCountsShowOnlyTotalOutsideAllChip() throws {
    let rows = [try row(1, extra: ["rate_limit_reset_at": stamp(60)]), try row(2, extra: ["overload_until": stamp(60)])]
    let limited = try #require(AccountListLayout.sections(rows: rows, chip: .limited, summary: nil, groups: [], frozenOrder: nil, now: now).sections.first)
    #expect(limited.countsAreLocal && limited.flags.isEmpty && limited.spokenSummary == "2 个")
    let all = try #require(AccountListLayout.sections(rows: rows, chip: .all, summary: nil, groups: [], frozenOrder: nil, now: now).sections.first)
    #expect(all.flags.map(\.text) == ["需处理 2"] && all.flags.map(\.tone) == [.critical])
    #expect(all.spokenSummary == "2 个，需处理 2")
}

@Test(arguments: [
    (AccountStateCounts(total: 4, available: 2, error: 1, rateLimited: 1, stopped: 1), ["已停止调度 1", "需处理 2"], [Tone.neutral, .critical]),
    (AccountStateCounts(total: 3, available: 1, rateLimited: 2), ["需处理 2"], [.caution]),
    (AccountStateCounts(total: 2, available: 1, overloaded: 1), ["需处理 1"], [.critical]),
    (AccountStateCounts(total: 3, paused: 2, inactive: 1), ["暂停 2 · 停用 1"], [.neutral]),
    (AccountStateCounts(total: 1, inactive: 1), ["停用 1"], [.neutral]),
    (AccountStateCounts(total: 12_000, paused: 12_000), ["暂停 12,000"], [.neutral]),
    (AccountStateCounts(total: 3, available: 2, paused: 1), [], []),
    (AccountStateCounts(), [], [])
])
func headerFlagsFollowRightSideTable(_ counts: AccountStateCounts, _ texts: [String], _ tones: [Tone]) {
    let flags = AccountListLayout.flags(for: counts)
    #expect(flags.map(\.text) == texts)
    #expect(flags.map(\.tone) == tones)
}

@Test func headerFlagKindsName() {
    let kinds = AccountListLayout.flags(for: AccountStateCounts(total: 2, error: 1, rateLimited: 1, stopped: 1)).map(\.kind)
    #expect(kinds == [.stopped, .needs])
    #expect(AccountListLayout.flags(for: AccountStateCounts(total: 1, paused: 1)).map(\.kind) == [.idle])
}

@Test func spokenSummaryJoinsTotalNeedsAndStopped() {
    let stopped = AccountStateCounts(total: 4, available: 2, error: 1, rateLimited: 1, stopped: 1)
    #expect(AccountListLayout.spokenSummary(for: stopped, showsFlags: true) == "4 个，需处理 2，其中已停止调度 1")
    #expect(AccountListLayout.spokenSummary(for: AccountStateCounts(total: 3, paused: 2, inactive: 1), showsFlags: true) == "3 个，暂停 2 · 停用 1")
    #expect(AccountListLayout.spokenSummary(for: AccountStateCounts(total: 5, available: 5), showsFlags: true) == "5 个")
    #expect(AccountListLayout.spokenSummary(for: stopped, showsFlags: false) == "4 个")
}

@Test func rowsClusterByMainGroupThenKeepServerOrder() throws {
    let groups = [1: AdminGroup(id: 1, name: "高级组", sortOrder: 1), 2: AdminGroup(id: 2, name: "标准组", sortOrder: 2),
                  5: AdminGroup(id: 5, name: "Claude Code 组", sortOrder: 5)]
    let rows = [try row(1, groups: [5]), try row(2, groups: [5, 1]), try row(3), try row(4, groups: [99]), try row(5, groups: [1]),
                try row(6, groups: [2, 99])]
    #expect(AccountListLayout.groupedRows(rows, groups: groups).map(\.id) == [2, 5, 6, 1, 4, 3])
    #expect(AccountListLayout.mainGroup(of: rows[1], groups: groups) == .known(sortOrder: 1, id: 1))
    #expect(AccountListLayout.mainGroup(of: rows[3], groups: groups) == .unknown)
    #expect(AccountListLayout.mainGroup(of: rows[2], groups: groups) == .ungrouped)
    #expect(AccountMainGroup.known(sortOrder: 99, id: 99) < .unknown && AccountMainGroup.unknown < .ungrouped)
}

/// A missing sort_order counts as 0, like the backend and AdminGroup.displayOrder; ties go by id.
@Test func mainGroupWithoutSortOrderCountsAsZeroThenID() throws {
    let groups = [7: AdminGroup(id: 7, name: "无序号", sortOrder: nil), 3: AdminGroup(id: 3, name: "零", sortOrder: 0),
                  2: AdminGroup(id: 2, name: "一", sortOrder: 1)]
    #expect(AccountListLayout.mainGroup(of: try row(1, groups: [7, 3]), groups: groups) == .known(sortOrder: 0, id: 3))
    #expect(AccountListLayout.mainGroup(of: try row(2, groups: [2, 7]), groups: groups) == .known(sortOrder: 0, id: 7))
}

@Test func localCountsUseDisplayStateIncludingStoppedAndExpiredPause() throws {
    #expect(AccountListLayout.localCounts(try eightStates(), now: now)
            == AccountStateCounts(total: 8, available: 1, error: 1, overloaded: 1, rateLimited: 1, tempUnschedulable: 1, paused: 2, inactive: 1, stopped: 1))
    let byPlatform = AccountListLayout.localPlatformCounts([try row(1), try row(2, platform: "kimi", schedulable: false)], now: now)
    #expect(byPlatform == ["anthropic": AccountStateCounts(total: 1, available: 1), "kimi": AccountStateCounts(total: 1, paused: 1)])
}

@Test func sectionsRederiveTimedStatesWithNow() throws {
    let rows = [try row(1, extra: ["overload_until": stamp(60)])]
    let before = AccountListLayout.sections(rows: rows, chip: .all, summary: nil, groups: [], frozenOrder: nil, now: now)
    let after = AccountListLayout.sections(rows: rows, chip: .all, summary: nil, groups: [], frozenOrder: nil, now: now.addingTimeInterval(61))
    #expect(before.sections.first?.counts.overloaded == 1)
    #expect(after.sections.first?.counts == AccountStateCounts(total: 1, available: 1))
}

@Test func overflowNoteOnlyWhenRowsWereLeftOut() {
    #expect(AccountListLayout.pageSize == 500 && AccountListLayout.rowLimit == 2000)
    #expect(AccountListLayout.overflowNote(total: 2350, loaded: 2000) == "还有 350 个账号未加载，用平台筛选缩小范围")
    #expect(AccountListLayout.overflowNote(total: 12_350, loaded: 2000) == "还有 10,350 个账号未加载，用平台筛选缩小范围")
    #expect(AccountListLayout.overflowNote(total: 2000, loaded: 2000) == nil)
    #expect(AccountListLayout.overflowNote(total: nil, loaded: 0) == nil)
}

// MARK: - Old servers and fixtures (20 §1.2 本地推导)

@Test func legacyFilterAndCountsUseDisplayState() throws {
    let rows = try eightStates()
    #expect(AccountListLocal.counts(rows, now: now) == AccountListCounts(all: 8, needsAttention: 4, error: 1, overloaded: 1, rateLimited: 1,
                                                                         tempUnschedulable: 1, unschedulable: 2, inactive: 1, schedulableNow: 1))
    #expect(AccountListLocal.filter(rows, chip: .limited, now: now).map(\.id) == [2, 3, 4])
    #expect(AccountListLocal.filter(rows, chip: .paused, now: now).map(\.id) == [5, 6, 7])
    #expect(AccountListLocal.filter(rows, chip: .needs, now: now).map(\.id) == [1, 2, 3, 4])
    #expect(AccountListLocal.filter(rows, chip: .all, now: now).count == 8)
}

@Test func legacyUrgencyOrderMatchesServerRank() throws {
    let rows = [try row(1, name: "a"), try row(2, name: "a", status: "inactive"), try row(3, name: "a", schedulable: false),
                try row(4, name: "a", extra: ["temp_unschedulable_until": stamp(600)]), try row(5, name: "a", extra: ["rate_limit_reset_at": stamp(300)]),
                try row(6, name: "a", extra: ["overload_until": stamp(60)]), try row(7, name: "b", status: "error"),
                try row(8, name: "a", extra: ["overload_until": stamp(60), "rate_limit_reset_at": stamp(900)]),
                try row(9, name: "a", status: "error"), try row(10, name: "a", status: "error")]
    let sorted = AccountListLocal.urgencySorted(rows, now: now).map(\.id)
    #expect(sorted == [9, 10, 7, 6, 5, 4, 8, 3, 2, 1])
    #expect(AccountListLocal.urgencySorted(rows, now: now, descending: true).map(\.id) == sorted.reversed())
}

@Test func localMatchesQueryForFixtureAndLegacy() throws {
    let claude = try row(1, name: "Claude-官方-01", type: "oauth", groups: [1, 5])
    let openai = try row(2, name: "OpenAI-备用-A", platform: "openai", status: "error", groups: [2])
    let grok = try row(3, name: "Grok-旧-01", platform: "grok", status: "inactive")
    let paused = try row(4, name: "Gemini-测试-B", platform: "gemini", schedulable: false, groups: [6])
    let rows = [claude, openai, grok, paused]
    func ids(_ query: AccountListQuery) -> [Int] { rows.filter { AccountListLocal.matches($0, query: query, now: now) }.map(\.id) }
    #expect(ids(AccountListQuery(search: " claude ")) == [1])
    #expect(ids(AccountListQuery(platform: "openai")) == [2])
    #expect(ids(AccountListQuery(type: "oauth")) == [1])
    #expect(ids(AccountListQuery(group: .id(1))) == [1])
    #expect(ids(AccountListQuery(group: .ungrouped)) == [3])
    #expect(ids(AccountListQuery(statuses: [.error, .inactive])) == [2, 3])
    #expect(ids(AccountListQuery(statuses: [.unschedulable])) == [4])
    #expect(ids(AccountListQuery(statuses: [.schedulableNow])) == [1])
    #expect(ids(AccountListQuery(statuses: [.active])) == [1])
    #expect(ids(AccountListQuery(statuses: [.needsAttention])) == [2])
    #expect(ids(AccountListQuery()) == [1, 2, 3, 4])
}
