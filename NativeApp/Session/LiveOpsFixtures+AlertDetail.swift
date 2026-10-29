import Foundation
import Sub2Core

// S1-12: `-ui-testing`'s alert detail. #41 and #40 already carry their rule snapshot and group name (LiveOpsFixtures.alertEvents);
// these are the detail's own arguments and the reads only it makes.
extension LiveOpsFixtures.Argument {
    /// S1-12: every `alert-events/:id` read answers 404 OPS_ALERT_EVENT_NOT_FOUND (这条告警不存在或已被清理).
    static let alertGone = "-ui-alert-gone"
    /// S1-12: the first `alert-events/:id` read finds ops monitoring turned off (404 OPS_DISABLED, setting_off); it stays off until
    /// the App turns it on, and the detail then reads the event.
    static let alertDetailOpsDisabled = "-ui-alert-detail-ops-disabled"
}

extension LiveOpsFixtures {
    static let alertGoneError = APIError.server(status: 404, reason: "OPS_ALERT_EVENT_NOT_FOUND")

    /// `-ui-without-capabilities ops.alert_event_details`: a server before it sends neither `rule` nor `group_name`, so the
    /// session fills them in from `alert-rules` and `groups/all` (S1D1-16).
    static func served(_ event: AlertEvent, _ options: Options) -> AlertEvent {
        options.withholdsAlertDetails ? event.replacingRule(nil).replacingGroupName(nil) : event
    }

    /// `status-summary?group_id`: the group as `groups/all` lists it, counted over the fallback's eleven accounts (标准组 #2: 1 of 2
    /// available, #7 in error); an id it does not list comes back without groups, as a deleted group does.
    static func groupStatusSummary(groupID: Int, base: Date) -> AccountStatusSummary {
        let counts = AccountListLayout.localCounts(accounts(base: base).filter { $0.groupIDs.contains(groupID) }, now: base)
        let rows = groups().filter { $0.id == groupID }.map {
            AccountStatusGroupSummary(groupID: $0.id, groupName: $0.name, platform: $0.platform, groupStatus: $0.status, counts: counts)
        }
        return AccountStatusSummary(collectedAt: base, totals: counts, groups: rows)
    }
}
