import Foundation
import Sub2Core

// S1-16: 监控 · 告警's fixture switches (10 §6). The default data already has two ended events (#37, #35, S1-05); these add a long
// last day for 加载更早 and a list that cannot be read.

/// They go with any home variant.
struct AlertsFixtureOptions: Equatable, Sendable {
    /// 60 more ended events within the last day (ids 3101–3160), so 最近结束 fills a page and offers 加载更早.
    static let historyArgument = "-ui-alerts-history"
    /// Every alert list answers 503 (the counts and single events still read), so 告警 shows 告警加载失败 · 重试.
    static let listFailsArgument = "-ui-alerts-list-fails"
    var history = false
    var listFails = false

    init(history: Bool = false, listFails: Bool = false) { self.history = history; self.listFails = listFails }
    init(arguments: [String]) {
        self.init(history: arguments.contains(Self.historyArgument), listFails: arguments.contains(Self.listFailsArgument))
    }
}

extension LiveOpsFixtures {
    static let historyEventIDs: ClosedRange<Int> = 3101...3160

    /// Server-wide error-rate alerts: the newest fired two hours before `base`, then one every 15 minutes (the oldest under 17
    /// hours ago); P2 resolved and P3 resolved by admin by turns, each over after 10 minutes.
    static func endedHistory(base: Date) -> [AlertEvent] {
        let rule = AlertEventRule(id: 15, name: "全站错误率", metricType: "error_rate", comparison: ">", threshold: 5, windowMinutes: 5)
        return historyEventIDs.enumerated().map { index, id in
            let firedAt = base.addingTimeInterval(-7_200 - Double(index) * 900)
            let manual = !index.isMultiple(of: 2)
            let severity = manual ? "P3" : "P2"
            return AlertEvent(id: id, ruleID: rule.id, severity: severity, status: manual ? AlertEvent.manualResolved : "resolved",
                              title: severity + ": 全站错误率", description: "error_rate 6 > 5", metricValue: 6, thresholdValue: 5, firedAt: firedAt,
                              resolvedAt: firedAt.addingTimeInterval(600), rule: rule, resolvedByUserName: manual ? "admin" : nil)
        }
    }
}
