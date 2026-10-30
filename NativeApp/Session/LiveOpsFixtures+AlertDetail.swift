import Foundation
import Sub2Core

// S1-12: `-ui-testing`'s alert detail. #41 and #40 already carry their rule snapshot and group name (LiveOpsFixtures.alertEvents);
// these are the detail's own arguments and the reads only it makes. S1-17's error counts are at the end.
extension LiveOpsFixtures.Argument {
    /// S1-12: every `alert-events/:id` read answers 404 OPS_ALERT_EVENT_NOT_FOUND (这条告警不存在或已被清理).
    static let alertGone = "-ui-alert-gone"
    /// S1-12: the first `alert-events/:id` read finds ops monitoring turned off (404 OPS_DISABLED, setting_off); it stays off until
    /// the App turns it on, and the detail then reads the event.
    static let alertDetailOpsDisabled = "-ui-alert-detail-ops-disabled"
    /// S1-17: #41 without its group, a site-wide error-rate rule, so its detail counts the whole site's failed requests.
    static let alertSiteWide = "-ui-alert-site-wide"
    /// S1-17: the first error count answers 500 INTERNAL_ERROR (错误请求 · 加载失败 · 重试); 「重试」 then counts.
    static let errorCountFails = "-ui-alert-error-count-fails"
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

// MARK: - S1-17 错误请求计数

extension LiveOpsFixtures {
    static let errorCountError = APIError.server(status: 500, reason: "INTERNAL_ERROR")
    /// 近 24 小时 by group (标准组 #2, #41's) and site-wide; other groups have none.
    static let standardGroupErrorCounts: [ErrorLogKind: Int] = [.request: 37, .upstream: 9]
    static let siteErrorCounts: [ErrorLogKind: Int] = [.request: 128, .upstream: 41]

    static func errorCount(groupID: Int?, kind: ErrorLogKind) -> Int {
        guard let groupID else { return siteErrorCounts[kind] ?? 0 }
        return groupID == LiveOpsFixtureIDs.standardGroup ? standardGroupErrorCounts[kind] ?? 0 : 0
    }
    /// `-ui-alert-site-wide`: #41 without its group and group name; every other field (the cursor, so the order) stays.
    static func detailVariant(_ events: [AlertEvent], _ options: Options) -> [AlertEvent] {
        guard options.alertSiteWide else { return events }
        return events.map { event in
            guard event.id == LiveOpsFixtureIDs.alertA else { return event }
            return AlertEvent(id: event.id, ruleID: event.ruleID, severity: event.severity, status: event.status, title: event.title,
                              description: event.description, metricValue: event.metricValue, thresholdValue: event.thresholdValue,
                              platform: event.platform, firedAt: event.firedAt, resolvedAt: event.resolvedAt, silence: event.silence,
                              silenceSupported: event.silenceSupported, rule: event.rule, resolvedByUserName: event.resolvedByUserName,
                              cursor: event.cursor)
        }
    }
}
