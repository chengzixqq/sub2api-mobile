import Foundation
import Sub2Core

/// 50 §2 `-ui-testing` (S5-06, X44): the group detail's reads on the fixture site. The group comes through the session's
/// GroupStore (the same table the list and the actions write), the members through AccountDemoStore, D02 and the key counts from
/// the list's and the actions' tables. today-stats echoes `group_id` when the page sends one (it does so only with
/// `accounts.today_stats_group`) and then gives each member's share of this group (S5D2a-12).
extension GroupFixtures {
    enum DetailArgument {
        /// MiniMax 组 (9) is deleted elsewhere just before its detail reads it: `GET :id` answers 404 GROUP_NOT_FOUND.
        static let deleted = "-ui-group-deleted"
        /// Every member list read answers 502.
        static let memberFailure = "-ui-group-member-failure"
    }
    static let deletedGroupID = 9
    /// user_cost by group for members in more than one group: 高级组 adds up to its 933.30, Claude Code 组 to its 52.75.
    static let groupScopedToday: [Int: [Int: Decimal]] = [
        1: [1: decimal("380.98"), 2: decimal("359.7"), 3: decimal("192.62")],
        5: [1: decimal("28.4"), 2: decimal("24.35")]
    ]

    static func detailSource(_ app: AppModel, arguments: [String] = ProcessInfo.processInfo.arguments) -> GroupDetailSource {
        let live = GroupDetailSource.live(app)
        return GroupDetailSource(
            group: { [weak app] id in
                if arguments.contains(DetailArgument.deleted), id == deletedGroupID { app?.groupStore?.fixtures?.removeGroup(id: id) }
                return try await live.group(id)
            },
            members: { page, query in
                if arguments.contains(DetailArgument.memberFailure) { throw APIError.server(status: 502, reason: nil) }
                return try await live.members(page, query)
            },
            memberToday: { ids, groupID in echoing(try await live.memberToday(ids, nil), groupID: groupID) },
            shortage: { [weak app] id in
                guard let context = app?.groupStore?.fixtureContext else { throw CancellationError() }
                return context.fixtures.shortages(accounts: context.accounts, now: context.now)[id]
            },
            stats: { id in servedStats(groupID: id, arguments: arguments) },
            apiKeyCount: { id, _ in stats(groupID: id).totalAPIKeys },
            activeSubscriptionCount: { id in stats(groupID: id).subscriptionsActive })
    }

    /// The batch as a server with C17 answers a request that carried `groupID`.
    private static func echoing(_ batch: AccountTodayStatsBatch, groupID: Int?) -> AccountTodayStatsBatch {
        guard let groupID else { return batch }
        let shares = groupScopedToday[groupID] ?? [:]
        let stats = batch.stats.reduce(into: [Int: AccountTodayStats]()) { scoped, entry in
            let (id, figures) = entry
            scoped[id] = AccountTodayStats(requests: figures.requests, tokens: figures.tokens, cost: figures.cost,
                                           userCost: shares[id] ?? figures.userCost, standardCost: figures.standardCost)
        }
        return AccountTodayStatsBatch(stats: stats, failedIDs: batch.failedIDs, degraded: batch.degraded, groupID: groupID)
    }
    private static func decimal(_ text: String) -> Decimal { Decimal(string: text) ?? 0 }
}
