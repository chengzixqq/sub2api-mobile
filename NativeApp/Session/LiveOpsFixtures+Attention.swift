import Foundation
import Sub2Core

// S1-10: the 待处理 variants of `-ui-testing`'s home. They change only home's own blocks; the account tab keeps AccountDemoStore's
// states, and the fallback reads keep the default (LiveOpsFixtures+Fallback.swift).
extension LiveOpsFixtures {
    /// R12: the error text the server would echo; no row may show it.
    static let sentinelErrorMessage = "SENTINEL-ERROR-MESSAGE"
    static let errorWithoutStructuredFieldsID = 10

    /// `accounts?status=error&lite=1`'s row for #10: an error from before C02, so no error_at or error_summary.
    static let errorWithoutStructuredFields = UpstreamAccount(id: errorWithoutStructuredFieldsID, name: "Grok-旧-01", platform: "grok", type: "apikey",
                                                              status: "error", schedulable: false, errorMessage: sentinelErrorMessage, groupIDs: [3])

    /// The default availability, then `-ui-home-attention-extra` (#11 and #12 stopped, #10 in error) and `-ui-home-test-recovers`
    /// once its account test closed (#7 back to available). The calm variants have no error account and stay as they are.
    static func attentionAvailability(_ summary: AccountStatusSummary, _ options: Options) -> AccountStatusSummary {
        guard summary.accounts.contains(where: { $0.id == LiveOpsFixtureIDs.errorAccount }) else { return summary }
        var accounts = summary.accounts
        var counts = (available: summary.totals.available, error: summary.totals.error, stopped: summary.totals.stopped)
        if options.attentionExtra {
            let grok = AccountStatusItem(id: errorWithoutStructuredFieldsID, name: "Grok-旧-01", platform: "grok", groupIDs: [3], state: .error,
                                         status: "error", schedulable: false)
            let stopping = [LiveOpsFixtureIDs.overloadedAccount, LiveOpsFixtureIDs.tempUnschedulableAccount]
            accounts = accounts.flatMap { item -> [AccountStatusItem] in
                let row = stopping.contains(item.id) ? stopped(item) : item
                return item.id == LiveOpsFixtureIDs.errorAccount ? [row, grok] : [row]
            }
            counts = (counts.available - 1, counts.error + 1, counts.stopped + stopping.count)
        }
        if options.errorAccountRecovered {
            accounts.removeAll { $0.id == LiveOpsFixtureIDs.errorAccount }
            counts = (counts.available + 1, counts.error - 1, counts.stopped)
        }
        let totals = summary.totals
        return AccountStatusSummary(collectedAt: summary.collectedAt,
                                    totals: AccountStateCounts(total: totals.total, available: counts.available, error: counts.error,
                                                               overloaded: totals.overloaded, rateLimited: totals.rateLimited,
                                                               tempUnschedulable: totals.tempUnschedulable, paused: totals.paused,
                                                               inactive: totals.inactive, stopped: counts.stopped),
                                    platforms: summary.platforms, groups: summary.groups, accounts: accounts, accountsTruncated: summary.accountsTruncated)
    }

    /// `-ui-home-alerts-overflow`: five more firing events, two of them older than #40, so home's newest five are #42, #41, #43, #44
    /// and #40, and #45 (P2) and #46 are counted only.
    static func overflowAlerts(base: Date) -> [AlertEvent] {
        let rows: [(id: Int, severity: String, minutes: Double, group: Int, name: String)] = [
            (42, "P2", 5, 3, "默认组"), (43, "P3", 15, 6, "测试组"), (44, "P3", 20, 8, "Kimi 组"), (45, "P2", 40, 9, "MiniMax 组"),
            (46, "P3", 50, 5, "Claude Code 组")]
        return rows.map { row in
            AlertEvent(id: row.id, ruleID: 100 + row.group, severity: row.severity, status: "firing", title: "\(row.severity): \(row.name)错误率",
                       description: "error_rate 6 > 5", metricValue: 6, thresholdValue: 5, groupID: row.group,
                       firedAt: base.addingTimeInterval(-row.minutes * 60),
                       rule: AlertEventRule(id: 100 + row.group, name: row.name + "错误率", metricType: "error_rate", comparison: ">", threshold: 5,
                                            windowMinutes: 5),
                       groupName: row.name)
        }
    }

    /// 已停止调度 on a timed state: scheduling off (account_status_summary.go `stopped`).
    private static func stopped(_ item: AccountStatusItem) -> AccountStatusItem {
        AccountStatusItem(id: item.id, name: item.name, platform: item.platform, groupIDs: item.groupIDs, state: item.state, stopped: true,
                          status: item.status, schedulable: false, rateLimitResetAt: item.rateLimitResetAt, overloadUntil: item.overloadUntil,
                          tempUnschedulableUntil: item.tempUnschedulableUntil, tempUnschedulableReason: item.tempUnschedulableReason,
                          expiresAt: item.expiresAt, modelRateLimits: item.modelRateLimits)
    }
}
