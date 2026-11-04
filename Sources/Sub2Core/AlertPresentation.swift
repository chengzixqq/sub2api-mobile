import Foundation

/// 10 §6.3 units. Percentages already are percentages (not 0–1 ratios).
public enum AlertMetricUnit: Sendable, Equatable {
    case percent, milliseconds, count, unknown
}

/// One row of 10 §6.3, the same 18 metrics as backend `validOpsAlertMetricTypes` and in its order.
public struct AlertMetric: Sendable, Equatable {
    public let type: String
    public let name: String
    public let unit: AlertMetricUnit

    public var isKnown: Bool { unit != .unknown }
    /// Needs `ops.alert_latency_metrics` to fire (D07).
    public var isLatency: Bool { type == "p95_latency_ms" || type == "p99_latency_ms" }
    /// Whole-server metrics: an event without dimensions is scoped to "服务器" rather than "全站".
    public var isServer: Bool { ["cpu_usage_percent", "memory_usage_percent", "concurrency_queue_depth"].contains(type) }

    public static let catalog: [AlertMetric] = [
        .init("success_rate", "成功率", .percent), .init("error_rate", "错误率", .percent), .init("upstream_error_rate", "上游错误率", .percent),
        .init("p95_latency_ms", "P95 延迟", .milliseconds), .init("p99_latency_ms", "P99 延迟", .milliseconds),
        .init("cpu_usage_percent", "CPU", .percent), .init("memory_usage_percent", "内存", .percent), .init("concurrency_queue_depth", "排队", .count),
        .init("group_available_accounts", "可用账号", .count), .init("group_available_ratio", "可用比例", .percent),
        .init("group_rate_limit_ratio", "限流比例", .percent), .init("account_rate_limited_count", "限流账号", .count),
        .init("account_error_count", "错误账号", .count), .init("account_error_ratio", "错误账号比例", .percent),
        .init("account_temp_unscheduled_count", "临时不可调度账号", .count), .init("overload_account_count", "过载账号", .count),
        .init("proxy_expired_count", "已过期代理", .count), .init("proxy_expiring_soon_count", "即将过期代理", .count)
    ]

    /// An unknown type keeps its raw name in the unknown unit; nil (no rule) is the unknown unit with an empty name.
    public static func named(_ metricType: String?) -> AlertMetric {
        let type = metricType ?? ""
        return catalog.first { $0.type == type } ?? AlertMetric(type, type, .unknown)
    }

    private init(_ type: String, _ name: String, _ unit: AlertMetricUnit) { self.type = type; self.name = name; self.unit = unit }
}

/// 10 §6.3 copy shared by the home alert rows, the monitor list, the alert detail and the account group header. Every number
/// and time goes through DisplayFormat (R10, D21); `now` is the caller's server-corrected clock and `timeZone` the server's.
public enum AlertPresentation {
    /// D21: % with one decimal (DisplayFormat.percent), ms and counts as rounded grouped integers ("2,000ms", "3 个"),
    /// unknown metrics with two decimals.
    public static func value(_ value: Double?, unit: AlertMetricUnit) -> String {
        guard let value, value.isFinite else { return DisplayFormat.missing }
        switch unit {
        case .percent: return DisplayFormat.percent(value)
        case .milliseconds: return DisplayFormat.decimal(value, maxFractionDigits: 0) + "ms"
        case .count: return DisplayFormat.decimal(value, maxFractionDigits: 0) + " 个"
        case .unknown: return DisplayFormat.decimal(value, minFractionDigits: 2, maxFractionDigits: 2)
        }
    }

    /// The event has no metric type of its own; without a rule the unit is unknown.
    public static func metric(_ event: AlertEvent) -> AlertMetric { AlertMetric.named(event.rule?.metricType) }

    /// 10 §0.4: `rule.threshold ?? threshold_value`.
    public static func threshold(_ event: AlertEvent) -> Double? { event.rule?.threshold ?? event.thresholdValue }

    public static func thresholdText(_ event: AlertEvent) -> String? {
        threshold(event).map { value($0, unit: metric(event).unit) }
    }

    public static func operatorSymbol(_ op: String) -> String {
        switch op {
        case ">=": "≥"
        case "<=": "≤"
        case "==": "="
        case "!=": "≠"
        default: op
        }
    }

    /// "标准组错误率 5.2%": the rule name, or the event title without its "P1: " prefix, then the metric value when present.
    public static func title(_ event: AlertEvent) -> String {
        let ruleName = event.rule?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = ruleName.flatMap { $0.isEmpty ? nil : $0 } ?? strippedTitle(event.title)
        guard let metricValue = event.metricValue else { return name }
        return [name, value(metricValue, unit: metric(event).unit)].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func scopeText(_ event: AlertEvent, platformName: (String) -> String) -> String {
        if let groupID = event.groupID, groupID > 0 {
            let name = event.groupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "分组 · " + (name.isEmpty ? "#\(groupID)" : name)
        }
        if let platform = event.platform?.trimmingCharacters(in: .whitespacesAndNewlines), !platform.isEmpty {
            return "平台 · " + platformName(platform)
        }
        return metric(event).isServer ? "服务器" : "全站"
    }

    /// "错误率 > 5.0%（5 分钟）"; without a rule (or a rule without an operator) the `description` as received.
    public static func ruleText(_ event: AlertEvent, latencyMetricsSupported: Bool) -> String {
        guard let rule = describedRule(event) else { return event.description }
        let window = rule.windowMinutes > 0 ? "（\(rule.windowMinutes) 分钟）" : ""
        return condition(event, rule) + window + unsupportedMark(event, latencyMetricsSupported)
    }

    /// The monitor row's second line: scope · rule.
    public static func detailLine(_ event: AlertEvent, platformName: (String) -> String, latencyMetricsSupported: Bool) -> String {
        let rule = ruleText(event, latencyMetricsSupported: latencyMetricsSupported)
        let scope = scopeText(event, platformName: platformName)
        return rule.isEmpty ? scope : scope + " · " + rule
    }

    /// The detail page's 条件 row: no window (it has its own row), marked when the rule was deleted.
    public static func conditionText(_ event: AlertEvent, latencyMetricsSupported: Bool) -> String {
        guard let rule = describedRule(event) else { return event.description }
        return condition(event, rule) + (rule.deleted ? "（规则已删除）" : "") + unsupportedMark(event, latencyMetricsSupported)
    }

    /// A metric this server does not evaluate: not in the catalog, or p95 / p99 without `ops.alert_latency_metrics`.
    public static func isUnsupported(_ event: AlertEvent, latencyMetricsSupported: Bool) -> Bool {
        guard describedRule(event) != nil else { return false }
        let metric = metric(event)
        return !metric.isKnown || (metric.isLatency && !latencyMetricsSupported)
    }

    public static func statusWord(_ status: String) -> String {
        switch normalized(status) {
        case "firing": "告警中"
        case "resolved": "已恢复"
        case "manual_resolved": "已手动解决"
        default: status
        }
    }

    /// "P1 · 告警中".
    public static func badge(_ event: AlertEvent) -> String {
        [event.severity, statusWord(event.status)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 10 §1.3.3: "阈值 5.0% · 12 分钟前触发 · 已静默".
    public static func homeSubtitle(_ event: AlertEvent, now: Date, timeZone: TimeZone) -> String {
        let fired = event.firedAt.map { withVerb(DisplayFormat.relativeTime($0, now: now, timeZone: timeZone), "触发") }
        let parts: [String?] = [thresholdText(event).map { "阈值 " + $0 }, fired, event.silence == nil ? nil : "已静默"]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// Firing: "12 分钟前"; resolved: "今天 08:29 恢复"; manual_resolved: "昨天 22:10 · 由 admin 手动解决".
    public static func sinceText(_ event: AlertEvent, now: Date, timeZone: TimeZone) -> String {
        let resolvedAt = event.resolvedAt.map { DisplayFormat.relativeTime($0, now: now, timeZone: timeZone) }
        switch normalized(event.status) {
        case "firing":
            return DisplayFormat.relativeTime(event.firedAt, now: now, timeZone: timeZone)
        case "resolved":
            return resolvedAt.map { withVerb($0, "恢复") } ?? statusWord(event.status)
        case "manual_resolved":
            let resolver = event.resolvedByUserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tail = resolver.isEmpty ? statusWord(event.status) : "由 \(resolver) 手动解决"
            return resolvedAt.map { $0 + " · " + tail } ?? tail
        default:
            return statusWord(event.status)
        }
    }

    /// "10:41" the same server day, "明天 09:41" the next, "10月24日 09:41" otherwise.
    public static func silencedUntil(_ until: Date, now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = DisplayFormat.clock(until, timeZone: timeZone)
        if calendar.isDate(until, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(until, inSameDayAs: tomorrow) {
            return "明天 " + time
        }
        let day = calendar.dateComponents([.month, .day], from: until)
        return "\(day.month ?? 0)月\(day.day ?? 0)日 " + time
    }

    /// Only firing events show their silence.
    public static func silenceLine(_ event: AlertEvent, now: Date, timeZone: TimeZone) -> String? {
        guard event.isFiring, let silence = event.silence else { return nil }
        guard let until = silence.until else { return "⌛ 已静默" }
        return "⌛ 已静默至 " + silencedUntil(until, now: now, timeZone: timeZone)
    }

    /// 10 §0.6 `alertTone`: only firing events are coloured.
    public static func tone(_ event: AlertEvent) -> Tone? { Tone.alert(severity: event.severity, status: event.status) }

    // MARK: Internals

    private static func describedRule(_ event: AlertEvent) -> AlertEventRule? {
        guard let rule = event.rule, !rule.comparison.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return rule
    }

    private static func condition(_ event: AlertEvent, _ rule: AlertEventRule) -> String {
        let metric = metric(event)
        return [metric.name, operatorSymbol(rule.comparison), value(threshold(event), unit: metric.unit)]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func unsupportedMark(_ event: AlertEvent, _ latencyMetricsSupported: Bool) -> String {
        isUnsupported(event, latencyMetricsSupported: latencyMetricsSupported) ? "（不受支持，不会触发）" : ""
    }

    /// "刚刚" / "12 分钟前" take the verb directly ("12 分钟前触发"); a clock time takes a space ("今天 09:29 触发").
    private static func withVerb(_ time: String, _ verb: String) -> String {
        time.last?.isNumber == true ? time + " " + verb : time + verb
    }

    private static func strippedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefix = trimmed.range(of: #"^P\d+\s*:"#, options: .regularExpression) else { return trimmed }
        return trimmed[prefix.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ status: String) -> String { status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}
