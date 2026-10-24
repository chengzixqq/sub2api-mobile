import Foundation
import Testing
@testable import Sub2Core

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let utc = TimeZone(identifier: "UTC")!
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private let now = at("2026-10-22T09:41:00+08:00")
private let errorRule = AlertEventRule(id: 7, name: "标准组错误率", metricType: "error_rate", comparison: ">", threshold: 5, windowMinutes: 5)
private func rule(_ metricType: String, _ comparison: String = ">", threshold: Double? = 5, window: Int = 5, deleted: Bool = false) -> AlertEventRule {
    AlertEventRule(id: 7, name: "规则", metricType: metricType, comparison: comparison, threshold: threshold, windowMinutes: window, deleted: deleted)
}
private func firing(rule: AlertEventRule? = errorRule, severity: String = "P1", metricValue: Double? = 5.2, thresholdValue: Double? = nil,
                    firedAt: Date? = at("2026-10-22T09:29:00+08:00"), silence: AlertSilenceRef? = nil) -> AlertEvent {
    AlertEvent(id: 1, ruleID: 7, severity: severity, status: "firing", title: "\(severity): 标准组错误率", description: "error_rate > 5.00 (current 5.20) over last 5m (overall)",
               metricValue: metricValue, thresholdValue: thresholdValue, groupID: 12, firedAt: firedAt, silence: silence, rule: rule, groupName: "标准组")
}

// 10 §6.3, in the order of backend `validOpsAlertMetricTypes` (handler/admin/ops_alerts_handler.go).
private let metricTable: [(String, String, AlertMetricUnit)] = [
    ("success_rate", "成功率", .percent), ("error_rate", "错误率", .percent), ("upstream_error_rate", "上游错误率", .percent),
    ("p95_latency_ms", "P95 延迟", .milliseconds), ("p99_latency_ms", "P99 延迟", .milliseconds), ("cpu_usage_percent", "CPU", .percent),
    ("memory_usage_percent", "内存", .percent), ("concurrency_queue_depth", "排队", .count), ("group_available_accounts", "可用账号", .count),
    ("group_available_ratio", "可用比例", .percent), ("group_rate_limit_ratio", "限流比例", .percent), ("account_rate_limited_count", "限流账号", .count),
    ("account_error_count", "错误账号", .count), ("account_error_ratio", "错误账号比例", .percent),
    ("account_temp_unscheduled_count", "临时不可调度账号", .count), ("overload_account_count", "过载账号", .count),
    ("proxy_expired_count", "已过期代理", .count), ("proxy_expiring_soon_count", "即将过期代理", .count)
]

@Test(arguments: metricTable)
func metricCatalogMatchesBackendWhitelist(type: String, name: String, unit: AlertMetricUnit) {
    let metric = AlertMetric.named(type)
    #expect(metric.type == type)
    #expect(metric.name == name)
    #expect(metric.unit == unit)
    #expect(metric.isKnown)
    #expect(metric.isServer == ["cpu_usage_percent", "memory_usage_percent", "concurrency_queue_depth"].contains(type))
    #expect(metric.isLatency == ["p95_latency_ms", "p99_latency_ms"].contains(type))
}

@Test func metricCatalogHasEighteenRowsInBackendOrder() {
    #expect(AlertMetric.catalog.map(\.type) == metricTable.map(\.0))
    // The backend limits exactly these eight to 0–100 (isPercentOrRateMetric).
    #expect(AlertMetric.catalog.filter { $0.unit == .percent }.count == 8)
}

@Test func unknownMetricKeepsItsRawName() {
    let metric = AlertMetric.named("foo_metric")
    #expect(metric.name == "foo_metric")
    #expect(metric.unit == .unknown)
    #expect(!metric.isKnown && !metric.isServer && !metric.isLatency)
    #expect(AlertMetric.named(nil).unit == .unknown)
}

@Test func valueFormatsByUnit() {
    let cases: [(Double?, AlertMetricUnit, String)] = [
        (5, .percent, "5.0%"), (5.2, .percent, "5.2%"), (5.25, .percent, "5.3%"), (99.95, .percent, "100.0%"), (0, .percent, "0.0%"),
        (850, .milliseconds, "850ms"), (2_000, .milliseconds, "2,000ms"), (1_234.6, .milliseconds, "1,235ms"), (1_234.5, .milliseconds, "1,235ms"),
        (2, .count, "2 个"), (1_200, .count, "1,200 个"), (2.6, .count, "3 个"),
        (5.2, .unknown, "5.20"), (1_234.5, .unknown, "1,234.50"), (0, .unknown, "0.00"),
        (nil, .percent, "—"), (nil, .milliseconds, "—"), (nil, .count, "—"), (nil, .unknown, "—"), (.nan, .count, "—"), (.infinity, .milliseconds, "—")
    ]
    for (value, unit, expected) in cases {
        #expect(AlertPresentation.value(value, unit: unit) == expected, "\(String(describing: value)) \(unit)")
    }
}

@Test func thresholdPrefersRuleThenEventValue() {
    let ruled = firing(thresholdValue: 7)
    #expect(AlertPresentation.threshold(ruled) == 5)
    #expect(AlertPresentation.thresholdText(ruled) == "5.0%")
    let ruleWithoutThreshold = firing(rule: rule("error_rate", threshold: nil), thresholdValue: 7)
    #expect(AlertPresentation.threshold(ruleWithoutThreshold) == 7)
    #expect(AlertPresentation.thresholdText(ruleWithoutThreshold) == "7.0%")
    // A deleted rule without a snapshot: the event's own value in the unknown unit.
    let orphan = firing(rule: nil, thresholdValue: 5)
    #expect(AlertPresentation.threshold(orphan) == 5)
    #expect(AlertPresentation.thresholdText(orphan) == "5.00")
    #expect(AlertPresentation.threshold(firing(rule: nil)) == nil)
    #expect(AlertPresentation.thresholdText(firing(rule: nil)) == nil)
}

@Test(arguments: [(">", ">"), ("<", "<"), (">=", "≥"), ("<=", "≤"), ("==", "="), ("!=", "≠"), ("~", "~"), ("", "")])
func operatorSymbolsMapAllBackendOperators(raw: String, symbol: String) {
    #expect(AlertPresentation.operatorSymbol(raw) == symbol)
}

@Test func titleUsesRuleNameAndStripsSeverityPrefixWithoutRule() {
    #expect(AlertPresentation.title(firing()) == "标准组错误率 5.2%")
    #expect(AlertPresentation.title(firing(metricValue: nil)) == "标准组错误率")
    #expect(AlertPresentation.title(firing(rule: nil)) == "标准组错误率 5.20")
    #expect(AlertPresentation.title(firing(rule: nil, metricValue: nil)) == "标准组错误率")
    let count = AlertEventRule(id: 3, name: "可用账号不足", metricType: "group_available_accounts", comparison: "<", threshold: 3)
    #expect(AlertPresentation.title(firing(rule: count, metricValue: 1)) == "可用账号不足 1 个")
    let unprefixed = AlertEvent(id: 2, status: "firing", title: "自定义告警")
    #expect(AlertPresentation.title(unprefixed) == "自定义告警")
    let spaced = AlertEvent(id: 3, severity: "P0", status: "firing", title: "P0:  名称  ")
    #expect(AlertPresentation.title(spaced) == "名称")
    let blankName = AlertEvent(id: 4, severity: "P2", status: "firing", title: "P2: 内存过高", rule: AlertEventRule(id: 1, name: "  ", metricType: "memory_usage_percent"))
    #expect(AlertPresentation.title(blankName) == "内存过高")
}

@Test func scopeTextFollowsDimensionPriority() {
    let platformName: (String) -> String = { GroupPlatform.title($0) }
    let grouped = AlertEvent(id: 1, platform: "openai", groupID: 12, rule: errorRule, groupName: "标准组")
    #expect(AlertPresentation.scopeText(grouped, platformName: platformName) == "分组 · 标准组")
    let unnamed = AlertEvent(id: 1, groupID: 12, rule: errorRule)
    #expect(AlertPresentation.scopeText(unnamed, platformName: platformName) == "分组 · #12")
    let platform = AlertEvent(id: 1, platform: "openai", rule: errorRule)
    #expect(AlertPresentation.scopeText(platform, platformName: platformName) == "平台 · OpenAI")
    let server = AlertEvent(id: 1, rule: rule("memory_usage_percent"))
    #expect(AlertPresentation.scopeText(server, platformName: platformName) == "服务器")
    let queue = AlertEvent(id: 1, rule: rule("concurrency_queue_depth"))
    #expect(AlertPresentation.scopeText(queue, platformName: platformName) == "服务器")
    #expect(AlertPresentation.scopeText(AlertEvent(id: 1, rule: errorRule), platformName: platformName) == "全站")
    #expect(AlertPresentation.scopeText(AlertEvent(id: 1), platformName: platformName) == "全站")
    let blank = AlertEvent(id: 1, platform: "  ", groupID: 0, rule: errorRule)
    #expect(AlertPresentation.scopeText(blank, platformName: platformName) == "全站")
}

@Test func ruleTextAppendsWindowAndFallsBackToDescription() {
    #expect(AlertPresentation.ruleText(firing(), latencyMetricsSupported: true) == "错误率 > 5.0%（5 分钟）")
    #expect(AlertPresentation.ruleText(firing(rule: rule("error_rate", window: 0)), latencyMetricsSupported: true) == "错误率 > 5.0%")
    #expect(AlertPresentation.ruleText(firing(rule: rule("success_rate", "<=", threshold: 99.5)), latencyMetricsSupported: true) == "成功率 ≤ 99.5%（5 分钟）")
    #expect(AlertPresentation.ruleText(firing(rule: rule("group_available_accounts", "<", threshold: 3, window: 0)), latencyMetricsSupported: true)
        == "可用账号 < 3 个")
    #expect(AlertPresentation.ruleText(firing(rule: nil), latencyMetricsSupported: true) == "error_rate > 5.00 (current 5.20) over last 5m (overall)")
    let platformName: (String) -> String = { GroupPlatform.title($0) }
    #expect(AlertPresentation.detailLine(firing(), platformName: platformName, latencyMetricsSupported: true) == "分组 · 标准组 · 错误率 > 5.0%（5 分钟）")
    #expect(AlertPresentation.detailLine(firing(rule: nil), platformName: platformName, latencyMetricsSupported: true)
        == "分组 · 标准组 · error_rate > 5.00 (current 5.20) over last 5m (overall)")
    let bare = AlertEvent(id: 1, status: "firing")
    #expect(AlertPresentation.detailLine(bare, platformName: platformName, latencyMetricsSupported: true) == "全站")
}

@Test func unsupportedMetricsAreMarked() {
    let unknown = firing(rule: rule("foo_metric", window: 0))
    #expect(AlertPresentation.ruleText(unknown, latencyMetricsSupported: true) == "foo_metric > 5.00（不受支持，不会触发）")
    #expect(AlertPresentation.isUnsupported(unknown, latencyMetricsSupported: true))
    let latency = firing(rule: rule("p95_latency_ms", threshold: 2_000))
    #expect(AlertPresentation.ruleText(latency, latencyMetricsSupported: false) == "P95 延迟 > 2,000ms（5 分钟）（不受支持，不会触发）")
    #expect(AlertPresentation.isUnsupported(latency, latencyMetricsSupported: false))
    #expect(AlertPresentation.ruleText(latency, latencyMetricsSupported: true) == "P95 延迟 > 2,000ms（5 分钟）")
    #expect(!AlertPresentation.isUnsupported(latency, latencyMetricsSupported: true))
    #expect(!AlertPresentation.isUnsupported(firing(), latencyMetricsSupported: false))
    #expect(!AlertPresentation.isUnsupported(firing(rule: nil), latencyMetricsSupported: false))
}

@Test func conditionTextForDetailRuleSection() {
    #expect(AlertPresentation.conditionText(firing(), latencyMetricsSupported: true) == "错误率 > 5.0%")
    #expect(AlertPresentation.conditionText(firing(rule: rule("error_rate", deleted: true)), latencyMetricsSupported: true) == "错误率 > 5.0%（规则已删除）")
    #expect(AlertPresentation.conditionText(firing(rule: rule("p99_latency_ms", threshold: 3_000, deleted: true)), latencyMetricsSupported: false)
        == "P99 延迟 > 3,000ms（规则已删除）（不受支持，不会触发）")
    #expect(AlertPresentation.conditionText(firing(rule: nil), latencyMetricsSupported: true) == "error_rate > 5.00 (current 5.20) over last 5m (overall)")
}

@Test func statusWordsAndBadge() {
    #expect(AlertPresentation.statusWord("firing") == "告警中")
    #expect(AlertPresentation.statusWord("resolved") == "已恢复")
    #expect(AlertPresentation.statusWord("manual_resolved") == "已手动解决")
    #expect(AlertPresentation.statusWord("weird") == "weird")
    #expect(AlertPresentation.badge(firing()) == "P1 · 告警中")
    #expect(AlertPresentation.badge(AlertEvent(id: 1, severity: "P2", status: "manual_resolved")) == "P2 · 已手动解决")
}

@Test func homeSubtitleCombinesThresholdTimeAndSilence() {
    #expect(AlertPresentation.homeSubtitle(firing(), now: now, timeZone: shanghai) == "阈值 5.0% · 12 分钟前触发")
    let silenced = firing(silence: AlertSilenceRef(id: 3, until: at("2026-10-22T10:41:00+08:00")))
    #expect(AlertPresentation.homeSubtitle(silenced, now: now, timeZone: shanghai) == "阈值 5.0% · 12 分钟前触发 · 已静默")
    #expect(AlertPresentation.homeSubtitle(firing(rule: nil), now: now, timeZone: shanghai) == "12 分钟前触发")
    let early = firing(firedAt: at("2026-10-22T06:41:00+08:00"))
    #expect(AlertPresentation.homeSubtitle(early, now: now, timeZone: shanghai) == "阈值 5.0% · 今天 06:41 触发")
    let fresh = firing(firedAt: now.addingTimeInterval(-30))
    #expect(AlertPresentation.homeSubtitle(fresh, now: now, timeZone: shanghai) == "阈值 5.0% · 刚刚触发")
    #expect(AlertPresentation.homeSubtitle(firing(firedAt: nil), now: now, timeZone: shanghai) == "阈值 5.0%")
}

@Test func sinceTextByStatus() {
    func ended(_ status: String, at resolvedAt: Date?, by name: String? = nil) -> AlertEvent {
        AlertEvent(id: 1, severity: "P1", status: status, firedAt: at("2026-10-21T20:00:00+08:00"), resolvedAt: resolvedAt, resolvedByUserName: name)
    }
    #expect(AlertPresentation.sinceText(firing(), now: now, timeZone: shanghai) == "12 分钟前")
    #expect(AlertPresentation.sinceText(ended("resolved", at: at("2026-10-22T08:29:00+08:00")), now: now, timeZone: shanghai) == "今天 08:29 恢复")
    #expect(AlertPresentation.sinceText(ended("resolved", at: now.addingTimeInterval(-1_200)), now: now, timeZone: shanghai) == "20 分钟前恢复")
    #expect(AlertPresentation.sinceText(ended("resolved", at: now.addingTimeInterval(-20)), now: now, timeZone: shanghai) == "刚刚恢复")
    let yesterday = at("2026-10-21T22:10:00+08:00")
    #expect(AlertPresentation.sinceText(ended("manual_resolved", at: yesterday, by: "admin"), now: now, timeZone: shanghai) == "昨天 22:10 · 由 admin 手动解决")
    #expect(AlertPresentation.sinceText(ended("manual_resolved", at: yesterday), now: now, timeZone: shanghai) == "昨天 22:10 · 已手动解决")
    #expect(AlertPresentation.sinceText(ended("manual_resolved", at: yesterday, by: " "), now: now, timeZone: shanghai) == "昨天 22:10 · 已手动解决")
    #expect(AlertPresentation.sinceText(ended("resolved", at: nil), now: now, timeZone: shanghai) == "已恢复")
    #expect(AlertPresentation.sinceText(ended("manual_resolved", at: nil), now: now, timeZone: shanghai) == "已手动解决")
    #expect(AlertPresentation.sinceText(ended("manual_resolved", at: nil, by: "admin"), now: now, timeZone: shanghai) == "由 admin 手动解决")
    #expect(AlertPresentation.sinceText(firing(firedAt: nil), now: now, timeZone: shanghai) == "—")
}

@Test func silenceLineUsesServerTimeZoneDayBoundaries() {
    #expect(AlertPresentation.silencedUntil(at("2026-10-22T10:41:00+08:00"), now: now, timeZone: shanghai) == "10:41")
    #expect(AlertPresentation.silencedUntil(at("2026-10-23T09:41:00+08:00"), now: now, timeZone: shanghai) == "明天 09:41")
    #expect(AlertPresentation.silencedUntil(at("2026-10-24T09:41:00+08:00"), now: now, timeZone: shanghai) == "10月24日 09:41")
    // 2026-10-22 23:30 UTC is still today in UTC but tomorrow morning in Shanghai.
    let late = at("2026-10-22T23:30:00Z")
    #expect(AlertPresentation.silencedUntil(late, now: now, timeZone: utc) == "23:30")
    #expect(AlertPresentation.silencedUntil(late, now: now, timeZone: shanghai) == "明天 07:30")

    let silenced = firing(silence: AlertSilenceRef(id: 3, until: at("2026-10-22T10:41:00+08:00")))
    #expect(AlertPresentation.silenceLine(silenced, now: now, timeZone: shanghai) == "⌛ 已静默至 10:41")
    let tomorrow = firing(silence: AlertSilenceRef(id: 3, until: at("2026-10-23T09:41:00+08:00")))
    #expect(AlertPresentation.silenceLine(tomorrow, now: now, timeZone: shanghai) == "⌛ 已静默至 明天 09:41")
    #expect(AlertPresentation.silenceLine(firing(silence: AlertSilenceRef(id: 3, until: nil)), now: now, timeZone: shanghai) == "⌛ 已静默")
    #expect(AlertPresentation.silenceLine(firing(), now: now, timeZone: shanghai) == nil)
    let resolved = AlertEvent(id: 1, status: "resolved", silence: AlertSilenceRef(id: 3, until: at("2026-10-22T10:41:00+08:00")))
    #expect(AlertPresentation.silenceLine(resolved, now: now, timeZone: shanghai) == nil)
}

@Test func toneFollowsAlertTone() {
    #expect(AlertPresentation.tone(firing(severity: "P0")) == .critical)
    #expect(AlertPresentation.tone(firing(severity: "P1")) == .caution)
    #expect(AlertPresentation.tone(firing(severity: "P2")) == .caution)
    #expect(AlertPresentation.tone(firing(severity: "P3")) == .neutral)
    #expect(AlertPresentation.tone(AlertEvent(id: 1, severity: "P0", status: "resolved")) == nil)
    #expect(AlertPresentation.tone(AlertEvent(id: 1, severity: "P0", status: "manual_resolved")) == nil)
    #expect(firing().isFiring)
    #expect(!AlertEvent(id: 1, status: "resolved").isFiring)
}
