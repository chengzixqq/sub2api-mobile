import Foundation
import Testing
@testable import Sub2Core

// S1-12: 10 §3.3 the alert detail's status card, 范围 and 规则, and §3.5's failures (AlertScopePresentation). S1-17 appends its
// error-count tests at the end.

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let utc = TimeZone(identifier: "UTC")!
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private let now = at("2026-10-22T10:00:00+08:00")
private let errorRule = AlertEventRule(id: 11, name: "标准组错误率", metricType: "error_rate", comparison: ">", threshold: 5, windowMinutes: 5)

private func rule(_ metricType: String, name: String = "规则", threshold: Double? = 5, window: Int = 5, deleted: Bool = false) -> AlertEventRule {
    AlertEventRule(id: 11, name: name, metricType: metricType, comparison: ">", threshold: threshold, windowMinutes: window, deleted: deleted)
}
private func event(severity: String = "P1", status: String = "firing", title: String = "P1: 标准组错误率", metricValue: Double? = 5.2,
                   thresholdValue: Double? = 5, platform: String? = nil, groupID: Int? = 12, firedAt: Date? = at("2026-10-22T09:29:00+08:00"),
                   resolvedAt: Date? = nil, silence: AlertSilenceRef? = nil, rule: AlertEventRule? = errorRule, groupName: String? = "标准组",
                   resolvedBy: String? = nil) -> AlertEvent {
    AlertEvent(id: 41, ruleID: 11, severity: severity, status: status, title: title, description: "error_rate 5.2 > 5", metricValue: metricValue,
               thresholdValue: thresholdValue, platform: platform, groupID: groupID, firedAt: firedAt, resolvedAt: resolvedAt, silence: silence,
               rule: rule, groupName: groupName, resolvedByUserName: resolvedBy)
}
private func found(total: Int = 5, available: Int = 2, error: Int = 1, rateLimited: Int = 1, paused: Int = 1, platform: String = "anthropic",
                   name: String = "标准组") -> AlertGroupScope {
    .found(AccountStatusGroupSummary(groupID: 12, groupName: name, platform: platform,
                                     counts: AccountStateCounts(total: total, available: available, error: error, rateLimited: rateLimited, paused: paused)))
}
private func channel(_ platform: String, _ groupID: Int, _ state: String, _ reliability: Double) -> ChannelItem {
    ChannelItem(platform: platform, groupID: groupID, groupName: "组 \(groupID)", currentStatus: ChannelCurrentStatus(state: state),
                metrics: ChannelMetrics(reliabilityRate: reliability))
}

// MARK: 范围类型与导航副标题

@Test func scopeKindFollowsDimensionPriority() {
    let cases: [(AlertEvent, AlertScopeKind, String)] = [
        (event(platform: "anthropic"), .group(id: 12), "分组"),
        (event(platform: "anthropic", groupID: nil), .platform("anthropic"), "平台"),
        (event(platform: "  ", groupID: nil), .siteWide, "全站"),
        (event(groupID: 0), .siteWide, "全站"),
        (event(groupID: nil, rule: rule("cpu_usage_percent")), .server, "服务器"),
        (event(groupID: nil, rule: rule("memory_usage_percent")), .server, "服务器"),
        (event(groupID: nil, rule: rule("concurrency_queue_depth")), .server, "服务器"),
        (event(groupID: nil), .siteWide, "全站"),
        (event(groupID: nil, rule: nil), .siteWide, "全站")
    ]
    for (alert, kind, prefix) in cases {
        #expect(AlertScopePresentation.kind(alert) == kind)
        #expect(AlertPresentation.scopeText(alert, platformName: AlertScopePresentation.platformName).hasPrefix(prefix))
    }
}

@Test func navigationSubtitleCombinesSeverityAndScope() {
    #expect(AlertScopePresentation.navigationSubtitle(event(), groupScope: nil) == "P1 · 分组 · 标准组")
    #expect(AlertScopePresentation.navigationSubtitle(event(groupName: nil), groupScope: found()) == "P1 · 分组 · 标准组")
    #expect(AlertScopePresentation.navigationSubtitle(event(groupName: nil), groupScope: .deleted) == "P1 · 分组 · #12")
    #expect(AlertScopePresentation.navigationSubtitle(event(groupName: " "), groupScope: found(name: "")) == "P1 · 分组 · #12")
    #expect(AlertScopePresentation.navigationSubtitle(event(severity: "P2", platform: "anthropic", groupID: nil), groupScope: nil) == "P2 · 平台 · Anthropic")
    #expect(AlertScopePresentation.navigationSubtitle(event(severity: "P3", groupID: nil, rule: rule("cpu_usage_percent")), groupScope: nil) == "P3 · 服务器")
    #expect(AlertScopePresentation.navigationSubtitle(event(groupID: nil), groupScope: nil) == "P1 · 全站")
}

// MARK: 状态卡

@Test func causeShowsTheTimeTodayAndTheDayOtherwise() {
    #expect(AlertScopePresentation.cause(event(), now: now, timeZone: shanghai) == "P1 · 09:29 触发")
    #expect(AlertScopePresentation.cause(event(firedAt: at("2026-10-21T22:10:00+08:00")), now: now, timeZone: shanghai) == "P1 · 昨天 22:10 触发")
    #expect(AlertScopePresentation.cause(event(firedAt: at("2026-10-19T08:00:00+08:00")), now: now, timeZone: shanghai) == "P1 · 10月19日 08:00 触发")
    #expect(AlertScopePresentation.cause(event(firedAt: nil), now: now, timeZone: shanghai) == "P1")
    let early = event(firedAt: at("2026-10-22T01:30:00+08:00"))
    #expect(AlertScopePresentation.cause(early, now: now, timeZone: shanghai) == "P1 · 01:30 触发")
    #expect(AlertScopePresentation.cause(early, now: now, timeZone: utc) == "P1 · 昨天 17:30 触发")
}

@Test func ruleNamePrefersTheRuleThenTheTitleWithoutItsLevel() {
    #expect(AlertScopePresentation.ruleName(event()) == "标准组错误率")
    #expect(AlertScopePresentation.ruleName(event(rule: nil)) == "标准组错误率")
    #expect(AlertScopePresentation.ruleName(event(title: "内存告警", rule: nil)) == "内存告警")
    #expect(AlertScopePresentation.ruleName(event(title: "P2:Anthropic 上游错误率", rule: rule("upstream_error_rate", name: "  "))) == "Anthropic 上游错误率")
}

@Test func metricTextFollowsTheRuleUnit() {
    #expect(AlertScopePresentation.metricText(event()) == "5.2%")
    #expect(AlertScopePresentation.metricText(event(metricValue: 5)) == "5.0%")
    #expect(AlertScopePresentation.metricText(event(metricValue: 2_000, rule: rule("p95_latency_ms"))) == "2,000ms")
    #expect(AlertScopePresentation.metricText(event(metricValue: 2, rule: rule("account_error_count"))) == "2 个")
    #expect(AlertScopePresentation.metricText(event(rule: nil)) == "5.20")
    #expect(AlertScopePresentation.metricText(event(metricValue: nil)) == DisplayFormat.missing)
}

@Test func thresholdLineCombinesThresholdAndTheRuleWindow() {
    #expect(AlertScopePresentation.thresholdLine(event()) == "阈值 5.0% · 近 5 分钟")
    #expect(AlertScopePresentation.thresholdLine(event(rule: rule("error_rate", window: 0))) == "阈值 5.0%")
    #expect(AlertScopePresentation.thresholdLine(event(thresholdValue: 7)) == "阈值 5.0% · 近 5 分钟")
    #expect(AlertScopePresentation.thresholdLine(event(rule: nil)) == "阈值 5.00")
    #expect(AlertScopePresentation.thresholdLine(event(thresholdValue: nil, rule: nil)) == nil)
    #expect(AlertScopePresentation.thresholdLine(event(thresholdValue: nil, rule: rule("error_rate", threshold: nil))) == "近 5 分钟")
}

@Test func silenceNoteOnlyForFiringSilencedEvents() {
    func note(_ until: String, status: String = "firing") -> String? {
        AlertScopePresentation.silenceNote(event(status: status, silence: AlertSilenceRef(id: 501, until: at(until))), now: now, timeZone: shanghai)
    }
    #expect(note("2026-10-22T10:41:00+08:00") == "⌛ 已静默至 10:41")
    #expect(note("2026-10-23T09:41:00+08:00") == "⌛ 已静默至 明天 09:41")
    #expect(note("2026-10-24T09:41:00+08:00") == "⌛ 已静默至 10月24日 09:41")
    #expect(note("2026-10-22T10:41:00+08:00", status: "resolved") == nil)
    #expect(AlertScopePresentation.silenceNote(event(), now: now, timeZone: shanghai) == nil)
}

@Test func endNoteSaysHowTheAlertEnded() {
    func note(_ alert: AlertEvent) -> String? { AlertScopePresentation.endNote(alert, now: now, timeZone: shanghai) }
    #expect(note(event(status: "resolved", resolvedAt: at("2026-10-22T08:29:00+08:00"))) == "今天 08:29 恢复")
    #expect(note(event(status: "resolved", resolvedAt: at("2026-10-22T09:48:00+08:00"))) == "12 分钟前恢复")
    let yesterday = at("2026-10-21T22:10:00+08:00")
    #expect(note(event(status: "manual_resolved", resolvedAt: yesterday, resolvedBy: "admin")) == "昨天 22:10 · 由 admin 手动解决")
    let anonymous = event(status: "manual_resolved", resolvedAt: yesterday)
    #expect(note(anonymous) == "昨天 22:10 · 已手动解决")
    #expect(note(anonymous) == AlertPresentation.sinceText(anonymous, now: now, timeZone: shanghai))
    #expect(note(event()) == nil)
}

@Test func actionsShowOnlyWhileFiring() {
    #expect(AlertScopePresentation.showsActions(event()))
    for status in ["resolved", "manual_resolved", "acknowledged"] { #expect(!AlertScopePresentation.showsActions(event(status: status))) }
}

// MARK: 范围

@Test func groupRowShowsAvailabilityAndAffectedAccounts() {
    #expect(AlertScopePresentation.groupRow(event(), groupID: 12, scope: found())
        == AlertScopeRow(title: "标准组", trailing: "2/5 可用", detail: "Anthropic · 2 个账号受影响", destination: .group(id: 12)))
    #expect(AlertScopePresentation.groupRow(event(), groupID: 12, scope: found(total: 3, available: 2, error: 0, rateLimited: 0)).detail
        == "Anthropic · 账号都可调度")
    #expect(AlertScopePresentation.groupRow(event(), groupID: 12, scope: found(platform: "")).detail == "2 个账号受影响")
}

@Test func groupRowMarksADeletedGroupAndAPendingLookup() {
    #expect(AlertScopePresentation.groupRow(event(), groupID: 12, scope: .deleted)
        == AlertScopeRow(title: "标准组", trailing: "分组已删除", trailingIsSecondary: true, destination: nil))
    #expect(AlertScopePresentation.groupRow(event(), groupID: 12, scope: nil) == AlertScopeRow(title: "标准组", destination: .group(id: 12)))
    #expect(AlertScopePresentation.groupRow(event(groupName: nil), groupID: 12, scope: found(name: "高级组")).title == "高级组")
    #expect(AlertScopePresentation.groupRow(event(groupName: nil), groupID: 12, scope: found(name: "")).title == "分组 #12")
    #expect(AlertScopePresentation.groupRow(event(groupName: nil), groupID: 12, scope: nil).title == "分组 #12")
}

@Test func channelRowSummarisesThePlatformsWorstChannel() {
    let items = [channel("anthropic", 1, "healthy", 0.99), channel("anthropic", 5, "warning", 0.975), channel("openai", 2, "critical", 0.5)]
    let row = AlertScopeRow(title: "Anthropic 渠道", trailing: "性能下降", trailingTone: .caution, detail: "2 个分组渠道 · 最低可用率 97.5%",
                            destination: .monitorChannels)
    #expect(AlertScopePresentation.channelRow(platform: "anthropic", items: items, channelMonitorDisabled: false) == row)
    #expect(AlertScopePresentation.channelRow(platform: "Anthropic", items: items, channelMonitorDisabled: false) == row)
    let healthy = AlertScopePresentation.channelRow(platform: "anthropic", items: Array(items.prefix(1)), channelMonitorDisabled: false)
    #expect(healthy.trailing == "可用" && healthy.trailingTone == nil)
    let absent = AlertScopePresentation.channelRow(platform: "gemini", items: items, channelMonitorDisabled: false)
    #expect(absent == AlertScopeRow(title: "Gemini 渠道", detail: "没有这个平台的渠道探测", destination: .monitorChannels))
    #expect(AlertScopePresentation.channelRow(platform: "anthropic", items: nil, channelMonitorDisabled: false)
        == AlertScopeRow(title: "Anthropic 渠道", destination: .monitorChannels))
    #expect(AlertScopePresentation.channelRow(platform: "anthropic", items: nil, channelMonitorDisabled: true)
        == AlertScopeRow(title: "Anthropic 渠道", detail: "渠道监控未开启", destination: .monitorChannels))
}

@Test func monitorRowsForServerAndSiteWide() {
    #expect(AlertScopePresentation.monitorRow(.server)
        == AlertScopeRow(title: "服务器", trailing: "监控 · 概况", trailingIsSecondary: true, destination: .monitorOverview))
    #expect(AlertScopePresentation.monitorRow(.siteWide)
        == AlertScopeRow(title: "全站", trailing: "监控 · 概况", trailingIsSecondary: true, destination: .monitorOverview))
    #expect(AlertScopePresentation.monitorRow(.group(id: 12)) == nil)
    #expect(AlertScopePresentation.monitorRow(.platform("anthropic")) == nil)
}

// MARK: 规则

@Test func ruleRowsMatchTheDetailTable() {
    func rows(_ alert: AlertEvent, latency: Bool = false) -> [AlertRuleRow] {
        AlertScopePresentation.ruleRows(alert, latencyMetricsSupported: latency, now: now, timeZone: shanghai)
    }
    func value(_ alert: AlertEvent, _ key: AlertRuleRow.Key, latency: Bool = false) -> String? {
        rows(alert, latency: latency).first { $0.key == key }?.value
    }
    #expect(rows(event()) == [AlertRuleRow(key: .condition, value: "错误率 > 5.0%"), AlertRuleRow(key: .window, value: "5 分钟"),
                              AlertRuleRow(key: .severity, value: "P1"), AlertRuleRow(key: .fired, value: "今天 09:29")])
    #expect(rows(event()).map(\.label) == ["条件", "窗口", "级别", "触发"])
    #expect(value(event(rule: rule("error_rate", deleted: true)), .condition) == "错误率 > 5.0%（规则已删除）")
    let latency = event(metricValue: 2_000, rule: rule("p95_latency_ms", threshold: 1_500))
    #expect(value(latency, .condition)?.hasSuffix("（不受支持，不会触发）") == true)
    #expect(value(latency, .condition, latency: true) == "P95 延迟 > 1,500ms")
    #expect(value(event(rule: rule("foo_metric")), .condition)?.hasSuffix("（不受支持，不会触发）") == true)
    #expect(value(event(rule: nil), .condition) == "error_rate 5.2 > 5")
    #expect(value(event(rule: nil), .window) == DisplayFormat.missing)
    #expect(value(event(rule: rule("error_rate", window: 0)), .window) == DisplayFormat.missing)
    #expect(value(event(severity: " "), .severity) == DisplayFormat.missing)
    let ended = rows(event(status: "resolved", resolvedAt: at("2026-10-22T08:29:00+08:00")))
    #expect(ended.last == AlertRuleRow(key: .ended, value: "今天 08:29") && ended.last?.label == "结束")
    #expect(value(event(status: "resolved"), .ended) == DisplayFormat.missing)
}

// MARK: 错误

@Test func failureClassificationFollowsReasons() {
    #expect(AlertScopePresentation.failure(.server(status: 404, reason: "OPS_ALERT_EVENT_NOT_FOUND")) == .notFound)
    #expect(AlertScopePresentation.failure(.server(status: 404, reason: "OPS_DISABLED")) == .opsDisabled)
    #expect(AlertScopePresentation.failure(.server(status: 400, reason: nil)) == .invalidID)
    #expect(AlertScopePresentation.failure(.server(status: 400, reason: "INVALID_EVENT_ID")) == .invalidID)
    #expect(AlertScopePresentation.failure(APIError(kind: .validation, message: "无效的对象编号。")) == .invalidID)
    let others: [APIError?] = [.server(status: 400, reason: "INVALID_STATUS"), .server(status: 500, reason: nil),
                               .server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"), APIError(kind: .transport, message: "无法连接站点"), nil]
    for error in others { #expect(AlertScopePresentation.failure(error) == .other) }
}

@Test func channelMonitorDisabledIsItsOwnState() {
    #expect(AlertScopePresentation.isChannelMonitorDisabled(.server(status: 403, reason: "CHANNEL_MONITOR_DISABLED")))
    #expect(!AlertScopePresentation.isChannelMonitorDisabled(.server(status: 403, reason: "FORBIDDEN")))
    #expect(!AlertScopePresentation.isChannelMonitorDisabled(nil))
}
