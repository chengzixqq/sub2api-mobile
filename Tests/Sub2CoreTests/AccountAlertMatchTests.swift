import Foundation
import Testing
@testable import Sub2Core

// S2-22: 20 §1.3 the platform header's alert and §1.4 the 告警 sheet.

private typealias Match = AccountAlertMatch
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private let now = at("2026-10-22T09:41:00+08:00")
private let upstreamRule = AlertEventRule(id: 12, name: "Anthropic 上游错误率", metricType: "upstream_error_rate", comparison: ">", threshold: 5,
                                          windowMinutes: 10)
private func alert(_ id: Int, severity: String = "P2", status: String = "firing", firedAt: Date? = at("2026-10-22T09:15:00+08:00"),
                   silence: AlertSilenceRef? = nil, rule: AlertEventRule? = upstreamRule, groupID: Int? = nil, groupName: String? = nil) -> AlertEvent {
    AlertEvent(id: id, ruleID: 12, severity: severity, status: status, title: "\(severity): Anthropic 上游错误率", description: "upstream_error_rate 6.1 > 5",
               metricValue: 6.1, thresholdValue: 5, platform: "anthropic", groupID: groupID, firedAt: firedAt, silence: silence, rule: rule,
               groupName: groupName)
}
private let sameDay = AlertSilenceRef(id: 501, until: at("2026-10-22T10:41:00+08:00"))
private let nextDay = AlertSilenceRef(id: 501, until: at("2026-10-23T09:41:00+08:00"))
private func platformName(_ id: String) -> String { id == "anthropic" ? "Anthropic" : id }

/// 20 §1.2 / §1.5: the shared list counts only once read (a refresh keeps it); failed, unread, disabled or ops off shows nothing.
@Test func listUsableOnlyWhenReadAndOpsOn() {
    let events = [alert(40)]
    #expect(Match.isListUsable(.loaded(events, at: now), lastReadFailed: false, opsDisabled: false))
    #expect(Match.isListUsable(.loading(previous: events, at: now), lastReadFailed: false, opsDisabled: false))
    #expect(!Match.isListUsable(.loading(previous: nil, at: nil), lastReadFailed: false, opsDisabled: false))
    #expect(!Match.isListUsable(.failed(reason: "站点暂时不可用", previous: events, at: now), lastReadFailed: true, opsDisabled: false))
    #expect(!Match.isListUsable(.failed(reason: nil, previous: nil, at: nil), lastReadFailed: true, opsDisabled: false))
    #expect(!Match.isListUsable(BlockState<[AlertEvent]>.idle, lastReadFailed: false, opsDisabled: false))
    #expect(!Match.isListUsable(BlockState<[AlertEvent]>.disabled(reason: "OPS_DISABLED"), lastReadFailed: false, opsDisabled: false))
    #expect(!Match.isListUsable(.loaded(events, at: now), lastReadFailed: false, opsDisabled: true))
}

/// S2D1-17: after a failed read the retry carries the old list (`withLoading`) and a cancelled retry restores it as loaded
/// (`withCancelledLoad`); neither shows it until a read succeeds.
@Test func oldListAfterFailedReadStaysUnusable() {
    let failed = BlockState<[AlertEvent]>.loaded([alert(40)], at: now).withFailure("站点暂时不可用")
    let retrying = failed.withLoading()
    #expect(retrying == .loading(previous: [alert(40)], at: now))
    #expect(!Match.isListUsable(retrying, lastReadFailed: true, opsDisabled: false))
    #expect(retrying.withCancelledLoad() == .loaded([alert(40)], at: now))
    #expect(!Match.isListUsable(retrying.withCancelledLoad(), lastReadFailed: true, opsDisabled: false))
}

@Test func severityRankIgnoresCaseAndSpacesAndPutsUnknownLast() {
    #expect(Match.severityRank("P0") == 0 && Match.severityRank("p1") == 1 && Match.severityRank(" P2") == 2 && Match.severityRank(" P3 ") == 3)
    #expect(Match.severityRank("S1") == 4 && Match.severityRank("") == 4 && Match.severityRank("P4") == 4)
}

/// 20 §1.3: the highest level (P0 → P3) wins, then the newest fired_at; equal times take the larger id, as the server orders them.
@Test func primaryEventPrefersLevelThenNewestThenLargerID() {
    let olderP1 = alert(1, severity: "P1", firedAt: at("2026-10-22T08:00:00+08:00"))
    let newerP2 = alert(2, severity: "P2", firedAt: at("2026-10-22T09:30:00+08:00"))
    #expect(Match.primaryEvent(in: [newerP2, olderP1])?.id == 1)
    #expect(Match.primaryEvent(in: [olderP1, alert(3, severity: "P0", firedAt: nil), alert(4, severity: "P3")])?.id == 3)
    let early = alert(5, severity: "P1", firedAt: at("2026-10-22T08:00:00+08:00")), late = alert(6, severity: "P1", firedAt: at("2026-10-22T09:00:00+08:00"))
    #expect(Match.primaryEvent(in: [early, late])?.id == 6)
    let twin = alert(7, severity: "P1", firedAt: at("2026-10-22T09:00:00+08:00"))
    #expect(Match.primaryEvent(in: [twin, late])?.id == 7)
    #expect(Match.primaryEvent(in: [alert(8, severity: "P1", firedAt: nil), early])?.id == 5)
    #expect(Match.primaryEvent(in: [alert(9, severity: "S1"), alert(10, severity: "P3", firedAt: at("2026-10-21T09:00:00+08:00"))])?.id == 10)
}

/// Only a firing event makes a badge; an empty list none.
@Test func primaryEventSkipsEventsNoLongerFiring() {
    #expect(Match.primaryEvent(in: []) == nil)
    #expect(Match.primaryEvent(in: [alert(1, status: "resolved"), alert(2, status: AlertEvent.manualResolved)]) == nil)
    #expect(Match.primaryEvent(in: [alert(1, severity: "P0", status: "resolved"), alert(2, status: " Firing ")])?.id == 2)
    #expect(Match.badge(for: [], now: now, timeZone: shanghai) == nil)
}

/// 20 §1.3: “P2 告警” / “P2 已静默”; a silenced event still fires, so its colour stays (10 §0.6 alertTone).
@Test func badgeTextKeepsToneWhenSilenced() {
    let open = Match.badge(for: [alert(40)], now: now, timeZone: shanghai)
    #expect(open?.text == "P2 告警" && open?.tone == .caution && open?.isSilenced == false && open?.event.id == 40)
    let silenced = Match.badge(for: [alert(40, silence: sameDay)], now: now, timeZone: shanghai)
    #expect(silenced?.text == "P2 已静默" && silenced?.tone == .caution && silenced?.isSilenced == true)
    #expect(Match.badge(for: [alert(1, severity: "P0")], now: now, timeZone: shanghai)?.tone == .critical)
    #expect(Match.badge(for: [alert(1, severity: "P3")], now: now, timeZone: shanghai)?.tone == .neutral)
    #expect(Match.badge(for: [alert(1, severity: " p1 ")], now: now, timeZone: shanghai)?.text == "p1 告警")
}

/// Design useVaAlert: “P2 告警：{标题}[，已静默至 HH:MM]，打开处置”; the time in the server's zone, “明天” across midnight.
@Test func badgeAccessibilityLabelFollowsDesign() {
    let title = AlertPresentation.title(alert(40))
    #expect(title == "Anthropic 上游错误率 6.1%")
    #expect(Match.badge(for: [alert(40)], now: now, timeZone: shanghai)?.accessibilityLabel == "P2 告警：\(title)，打开处置")
    #expect(Match.badge(for: [alert(40, silence: sameDay)], now: now, timeZone: shanghai)?.accessibilityLabel == "P2 告警：\(title)，已静默至 10:41，打开处置")
    #expect(Match.badge(for: [alert(40, silence: nextDay)], now: now, timeZone: shanghai)?.accessibilityLabel == "P2 告警：\(title)，已静默至 明天 09:41，打开处置")
    #expect(Match.badge(for: [alert(40, silence: AlertSilenceRef(id: 501))], now: now, timeZone: shanghai)?.accessibilityLabel == "P2 告警：\(title)，已静默，打开处置")
}

/// 20 §1.4 状态: “告警中”, or “告警中 · 已静默至 HH:MM” (the day too when it is not today).
@Test func statusTextShowsSilenceUntil() {
    #expect(Match.statusText(alert(40), now: now, timeZone: shanghai) == "告警中")
    #expect(Match.statusText(alert(40, silence: sameDay), now: now, timeZone: shanghai) == "告警中 · 已静默至 10:41")
    #expect(Match.statusText(alert(40, silence: nextDay), now: now, timeZone: shanghai) == "告警中 · 已静默至 明天 09:41")
    #expect(Match.statusText(alert(40, silence: AlertSilenceRef(id: 501)), now: now, timeZone: shanghai) == "告警中 · 已静默")
}

/// 20 §1.4 event card and 维度: AlertPresentation's title, scope and rule; the description as received without a rule.
@Test func sheetContentUsesAlertPresentation() {
    let platform = Match.sheetContent(alert(40), now: now, timeZone: shanghai, platformName: platformName, latencyMetricsSupported: true)
    #expect(platform.title == "Anthropic 上游错误率 6.1%" && platform.level == "P2" && platform.tone == .caution)
    #expect(platform.scope == "平台 · Anthropic")
    #expect(platform.detail == "平台 · Anthropic · 上游错误率 > 5.0%（10 分钟）")
    #expect(platform.status == "告警中")
    let silenced = Match.sheetContent(alert(40, silence: nextDay), now: now, timeZone: shanghai, platformName: platformName, latencyMetricsSupported: true)
    #expect(silenced.level == "P2 已静默" && silenced.tone == .caution && silenced.status == "告警中 · 已静默至 明天 09:41")
    let grouped = Match.sheetContent(alert(41, severity: "P1", groupID: 2, groupName: "标准组"), now: now, timeZone: shanghai,
                                     platformName: platformName, latencyMetricsSupported: true)
    #expect(grouped.scope == "分组 · 标准组" && grouped.level == "P1")
    let bare = Match.sheetContent(alert(40, rule: nil), now: now, timeZone: shanghai, platformName: platformName, latencyMetricsSupported: true)
    #expect(bare.detail == "平台 · Anthropic · upstream_error_rate 6.1 > 5")
    #expect(bare.title == AlertPresentation.title(alert(40, rule: nil)))
}

/// A write this sheet started closes it once the store shows it: the event left the firing list, ended, or its silence changed.
/// A failure changes nothing (10 §7.1), so the sheet stays.
@Test func actionTookEffectComparesWithTheStore() {
    let before = alert(40, silence: sameDay)
    #expect(Match.actionTookEffect(before: before, after: nil))
    #expect(Match.actionTookEffect(before: before, after: before.resolvedLocally(at: now)))
    #expect(Match.actionTookEffect(before: before, after: before.withSilence(nextDay)))
    #expect(Match.actionTookEffect(before: before, after: before.withSilence(nil)))
    #expect(Match.actionTookEffect(before: alert(40), after: alert(40, silence: sameDay)))
    #expect(!Match.actionTookEffect(before: before, after: before))
}

@Test func sheetCopyMatchesSpec() {
    #expect(Match.note == "告警只精确到分组或平台，不指向具体账号；先看本组需处理的账号。")
    #expect(Match.sheetTitle == "告警" && Match.showNeedsTitle == "只看需处理的账号" && Match.detailLinkTitle == "告警详情")
}
