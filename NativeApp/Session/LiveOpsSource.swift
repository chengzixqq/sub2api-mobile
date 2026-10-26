import Foundation
import Sub2Core

/// 10 §7.1: AlertActions' requests (S1-03), unkeyed and never retried; AlertActions' tests may stand in for just these.
protocol AlertActionSource: Sendable {
    func alertEvent(id: Int) async throws -> AlertEvent
    func setAlertEventStatus(id: Int, status: String) async throws
    func createAlertSilence(ruleID: Int, platform: String?, groupID: Int?, until: Date) async throws -> AlertSilence
    func updateAlertSilence(id: Int, until: Date) async throws -> AlertSilence
    func deleteAlertSilence(id: Int) async throws
}

/// C-27, S1D1-05: the reads behind LiveOpsStore, named and typed as on APIClient (no default arguments here). S1-06, S1-07,
/// S1-08, S1-12, S1-13 and S1-17 add theirs; every new requirement also goes into ClientLiveOpsSource, FixtureLiveOpsSource
/// and the tests' StubLiveOpsSource in the same commit (S1D1-06).
protocol LiveOpsSource: AlertActionSource {
    func dashboardHome(timezone: ServerTimeZone, include: [HomeSectionKey]?, noCache: Bool) async throws -> DashboardHome
    func dashboardRates(window: LiveRatesWindow) async throws -> LiveRates
    func opsOverview(start: Date, end: Date) async throws -> OpsOverview
    func opsOverview(timeRange: String) async throws -> OpsOverview
    func errorAccounts() async throws -> [UpstreamAccount]
    func accountsRanking(limit: Int, timezone: ServerTimeZone) async throws -> [AccountsRankingItem]
    func accountStatusSummary(platform: String?, groupID: Int?, includeAccounts: Bool) async throws -> AccountStatusSummary
    func alertEvents(status: String?, timeRange: String?, limit: Int, before: AlertEventCursor?, groupID: Int?,
                     platform: String?) async throws -> [AlertEvent]
    func alertEventCounts() async throws -> AlertCounts
    func alertRules() async throws -> [AlertEventRule]
    func channelOverview(range: String, refresh: Bool) async throws -> ChannelOverview
    func opsMonitoringStatus() async throws -> OpsMonitoringStatus
}

/// The session's own client (D13): LiveOpsStore never makes an APIClient of its own.
struct ClientLiveOpsSource: LiveOpsSource {
    let client: APIClient

    func dashboardHome(timezone: ServerTimeZone, include: [HomeSectionKey]?, noCache: Bool) async throws -> DashboardHome {
        try await client.dashboardHome(timezone: timezone, include: include, noCache: noCache)
    }
    func dashboardRates(window: LiveRatesWindow) async throws -> LiveRates { try await client.dashboardRates(window: window) }
    func opsOverview(start: Date, end: Date) async throws -> OpsOverview { try await client.opsOverview(start: start, end: end) }
    func opsOverview(timeRange: String) async throws -> OpsOverview { try await client.opsOverview(timeRange: timeRange) }
    func errorAccounts() async throws -> [UpstreamAccount] { try await client.errorAccounts() }
    func accountsRanking(limit: Int, timezone: ServerTimeZone) async throws -> [AccountsRankingItem] {
        try await client.accountsRanking(limit: limit, timezone: timezone)
    }
    func accountStatusSummary(platform: String?, groupID: Int?, includeAccounts: Bool) async throws -> AccountStatusSummary {
        try await client.accountStatusSummary(platform: platform, groupID: groupID, includeAccounts: includeAccounts)
    }
    func alertEvents(status: String?, timeRange: String?, limit: Int, before: AlertEventCursor?, groupID: Int?,
                     platform: String?) async throws -> [AlertEvent] {
        try await client.alertEvents(status: status, timeRange: timeRange, limit: limit, before: before, groupID: groupID, platform: platform)
    }
    func alertEventCounts() async throws -> AlertCounts { try await client.alertEventCounts() }
    func alertEvent(id: Int) async throws -> AlertEvent { try await client.alertEvent(id: id) }
    func alertRules() async throws -> [AlertEventRule] { try await client.alertRules() }
    func channelOverview(range: String, refresh: Bool) async throws -> ChannelOverview {
        try await client.channelOverview(range: range, refresh: refresh)
    }
    func opsMonitoringStatus() async throws -> OpsMonitoringStatus { try await client.opsMonitoringStatus() }
    func setAlertEventStatus(id: Int, status: String) async throws { try await client.setAlertEventStatus(id: id, status: status) }
    func createAlertSilence(ruleID: Int, platform: String?, groupID: Int?, until: Date) async throws -> AlertSilence {
        try await client.createAlertSilence(ruleID: ruleID, platform: platform, groupID: groupID, until: until)
    }
    func updateAlertSilence(id: Int, until: Date) async throws -> AlertSilence { try await client.updateAlertSilence(id: id, until: until) }
    func deleteAlertSilence(id: Int) async throws { try await client.deleteAlertSilence(id: id) }
}
