import Foundation

// S1-07, 10 §1.2 availability: `accounts/status-summary` cut to the home block's shape, or, on a site without it, the D02 buckets
// counted here from `groups/all` and the first 1,000 accounts.
extension HomeFallback {
    /// home's availability lists at most this many accounts, abnormal ones only.
    public static let abnormalAccountLimit = 100
    /// The server's page size limit; a larger value would silently fall back to 20.
    public static let localAccountPageSize = 1_000
    /// The backend's default `group_shortage_min_ratio`.
    public static let defaultShortageRatio = 0.5
    static let abnormalStates: Set<AccountScheduleState> = [.error, .overloaded, .rateLimited, .tempUnschedulable]
    static let timedStates: Set<AccountScheduleState> = [.overloaded, .rateLimited, .tempUnschedulable]

    /// status-summary lists every account; home keeps only the abnormal ones, at most 100, and says when there were more.
    public static func homeAvailability(_ summary: AccountStatusSummary) -> AccountStatusSummary {
        let abnormal = summary.accounts.filter { $0.state.map(abnormalStates.contains) ?? false }
        return AccountStatusSummary(collectedAt: summary.collectedAt, totals: summary.totals, platforms: summary.platforms, groups: summary.groups,
                                    accounts: Array(abnormal.prefix(abnormalAccountLimit)),
                                    accountsTruncated: summary.accountsTruncated || abnormal.count > abnormalAccountLimit)
    }
    /// Each account in its D02 bucket (AccountDisplayState, S0-17), once in the totals and once in each of its groups. A group's
    /// total and available are its own `account_count` / `active_account_count` (the same predicate as D02 available, and not
    /// capped at 1,000 accounts; missing is 0); its other buckets are counted here. Groups that are active or still have accounts
    /// are kept, by id. An incomplete account list marks the accounts truncated.
    public static func localAvailability(groups: [AdminGroup], accounts: [UpstreamAccount], accountsComplete: Bool, now: Date) -> AccountStatusSummary {
        let tiered = accounts.map { account in
            let input = AccountStateInput(account)
            return TieredAccount(account: account, input: input, state: AccountDisplayState.scheduleState(input, now: now))
        }
        let summaries = groups.sorted { $0.id < $1.id }.compactMap { group in
            groupSummary(group, members: tiered.filter { $0.account.groupIDs.contains(group.id) })
        }
        let abnormal = tiered.filter { abnormalStates.contains($0.state) }
        return AccountStatusSummary(collectedAt: now, totals: counts(tiered), groups: summaries, accounts: abnormal.prefix(abnormalAccountLimit).map(\.item),
                                    accountsTruncated: abnormal.count > abnormalAccountLimit || !accountsComplete)
    }
    /// The backend's default rule: short when nothing is available or less than `ratio` of the group is.
    public static func shortage(available: Int, total: Int, ratio: Double = defaultShortageRatio) -> AccountStatusGroupSummary.Shortage {
        .init(isShort: available == 0 || Double(available) < Double(total) * ratio, source: "default", threshold: ratio,
              current: total > 0 ? Double(available) / Double(total) : 0)
    }

    private static func groupSummary(_ group: AdminGroup, members: [TieredAccount]) -> AccountStatusGroupSummary? {
        let total = group.accountCount ?? 0, available = group.activeAccountCount ?? 0
        guard group.status == "active" || total > 0 || !members.isEmpty else { return nil }
        let local = counts(members)
        let counts = AccountStateCounts(total: total, available: available, error: local.error, overloaded: local.overloaded, rateLimited: local.rateLimited,
                                        tempUnschedulable: local.tempUnschedulable, paused: local.paused, inactive: local.inactive, stopped: local.stopped)
        return AccountStatusGroupSummary(groupID: group.id, groupName: group.name, platform: group.platform, groupStatus: group.status, counts: counts,
                                         shortage: shortage(available: available, total: total))
    }
    private static func counts(_ accounts: [TieredAccount]) -> AccountStateCounts {
        func count(_ state: AccountScheduleState) -> Int { accounts.filter { $0.state == state }.count }
        return AccountStateCounts(total: accounts.count, available: count(.available), error: count(.error), overloaded: count(.overloaded),
                                  rateLimited: count(.rateLimited), tempUnschedulable: count(.tempUnschedulable), paused: count(.paused),
                                  inactive: count(.inactive), stopped: accounts.filter(\.isStopped).count)
    }
}

/// One account with its D02 bucket.
private struct TieredAccount {
    let account: UpstreamAccount
    let input: AccountStateInput
    let state: AccountScheduleState
    /// Timed out of scheduling and also switched off: counted in both (account_status_summary.go:84-121).
    var isStopped: Bool { HomeFallback.timedStates.contains(state) && !account.schedulable }
    var item: AccountStatusItem {
        AccountStatusItem(id: account.id, name: account.name, platform: account.platform, groupIDs: account.groupIDs, state: state, stopped: isStopped,
                          status: account.status, schedulable: account.schedulable, rateLimitResetAt: input.rateLimitResetAt,
                          overloadUntil: input.overloadUntil, tempUnschedulableUntil: input.tempUnschedulableUntil,
                          tempUnschedulableReason: input.tempUnschedulableReason, expiresAt: input.expiresAt, modelRateLimits: input.modelRateLimits)
    }
}
