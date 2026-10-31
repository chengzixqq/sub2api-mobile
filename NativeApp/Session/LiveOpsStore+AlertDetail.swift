import Foundation
import Sub2Core

// S1-12, 10 §3.2: the alert detail's reads on top of the session's lists. The detail's copy of its event lives in LiveOpsStore
// (`alertDetails`), so a resolve or silence from any page shows there at once.

extension LiveOpsStore {
    /// 10 §3.2 平台范围: the channel list without the monitor's own.
    nonisolated static let alertChannelRange = "90m"

    /// The first screen: the detail's own copy, then home's alerts, the firing list and 最近结束.
    func alert(id: Int) -> AlertEvent? {
        if let shown = alertDetails[id] { return shown }
        let lists = [home.alerts.value?.top ?? [], firing.value ?? [], recentAlerts]
        return lists.lazy.compactMap { list in list.first { $0.id == id } }.first
    }
    /// How many local writes changed the event (0 before any).
    func alertRevision(id: Int) -> Int { alertRevisions[id] ?? 0 }

    /// `GET alert-events/:id` through the ops switch's entries (S1D1-02), normalized like every event read (S1D1-16), then kept
    /// as the detail's copy and placed in the lists.
    func fetchAlert(id: Int) async throws -> AlertEvent {
        let received = try await controlled { try await $0.alertEvent(id: id) }()
        let event = await normalizeReceivedAlerts([received]).first ?? received
        storeAlert(event)
        return event
    }
    /// The session's availability when it lists the group, otherwise `status-summary?group_id`, or on a site without
    /// `accounts.status_summary` (where that path is `accounts/:id`) the D02 count of `groups/all` and the accounts (10 §0.2);
    /// neither is gated by ops monitoring. A reply without the group means it was deleted.
    func alertGroupScope(groupID: Int) async throws -> AlertGroupScope {
        if let group = availability?.groups.first(where: { $0.groupID == groupID }) { return .found(group) }
        let summary: AccountStatusSummary
        if site()?.has(.accountsStatusSummary) == true {
            summary = try await source.accountStatusSummary(platform: nil, groupID: groupID, includeAccounts: false)
        } else {
            summary = try await FallbackFetch.localAvailability(source, now: serverNow()).get()
        }
        return summary.groups.first { $0.groupID == groupID }.map(AlertGroupScope.found) ?? .deleted
    }
    /// The monitor's channel list when it was read, unless a pull asks past it; otherwise the last 90 minutes.
    func alertChannelScope(bypassCache: Bool) async throws -> ChannelOverview {
        if !bypassCache, let overview = channels.value { return overview }
        return try await source.channelOverview(range: Self.alertChannelRange, refresh: false)
    }
    /// S1-17, 10 §3.2 错误请求条数 through the ops switch's entries (S1D1-02): the log page's own count (R19).
    func alertErrorCount(_ query: AlertErrorCountQuery) async throws -> Int {
        let filter = query.filter, kind = query.kind
        return try await controlled { try await $0.errorCount(filter: filter, kind: kind) }()
    }
}
