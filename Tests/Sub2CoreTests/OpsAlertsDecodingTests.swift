import Foundation
import Testing
@testable import Sub2Core

private func decodeEvent(_ json: String) throws -> AlertEvent {
    try JSONDecoder().decode(AlertEvent.self, from: Data(json.utf8))
}

private let fullEvent = #"""
{"id":42,"rule_id":7,"severity":"P1","status":"firing","title":"P1: 标准组错误率",
 "description":"error_rate > 5.00 (current 5.20) over last 5m (group 12)","metric_value":5.2,"threshold_value":5,
 "dimensions":{"platform":"openai","group_id":12},"fired_at":"2026-10-22T09:29:03.123456+08:00","resolved_at":null,
 "email_sent":false,"created_at":"2026-10-22T09:29:03Z",
 "silence":{"id":3,"until":"2026-10-22T02:41:00Z"},
 "rule":{"id":7,"name":"标准组错误率","metric_type":"error_rate","operator":">","threshold":5,"window_minutes":5,"sustained_minutes":2,"deleted":false},
 "group_name":"标准组","resolved_by_user_id":null,"resolved_by_user_name":null}
"""#

@Test func alertEventDecodesNewServerShape() throws {
    let event = try decodeEvent(fullEvent)
    #expect(event.id == 42)
    #expect(event.ruleID == 7)
    #expect(event.severity == "P1")
    #expect(event.status == "firing")
    #expect(event.isFiring)
    #expect(event.title == "P1: 标准组错误率")
    #expect(event.description.hasPrefix("error_rate > 5.00"))
    #expect(event.metricValue == 5.2)
    #expect(event.thresholdValue == 5)
    #expect(event.platform == "openai")
    #expect(event.groupID == 12)
    let fired = try #require(event.firedAt)
    #expect(abs(fired.timeIntervalSince1970 - 1_792_632_543.123) <= 0.001)
    #expect(event.resolvedAt == nil)
    #expect(event.silence == AlertSilenceRef(id: 3, until: ServerTime.parseTimestamp("2026-10-22T10:41:00+08:00")))
    #expect(event.silenceSupported)
    #expect(event.rule == AlertEventRule(id: 7, name: "标准组错误率", metricType: "error_rate", comparison: ">", threshold: 5,
                                         windowMinutes: 5, sustainedMinutes: 2, deleted: false))
    #expect(event.groupName == "标准组")
    #expect(event.resolvedByUserName == nil)
}

@Test func silenceKeyPresenceIsRecorded() throws {
    let nullSilence = try decodeEvent(#"{"id":1,"severity":"P2","status":"firing","title":"P2: 内存","silence":null}"#)
    #expect(nullSilence.silence == nil)
    #expect(nullSilence.silenceSupported)
    let oldServer = try decodeEvent(#"{"id":1,"severity":"P2","status":"firing","title":"P2: 内存"}"#)
    #expect(oldServer.silence == nil)
    #expect(!oldServer.silenceSupported)
    // A malformed silence still means the server knows the key; the until that cannot be read is nil.
    let odd = try decodeEvent(#"{"id":1,"status":"firing","silence":{"id":9,"until":"soon"}}"#)
    #expect(odd.silence == AlertSilenceRef(id: 9, until: nil))
    #expect(odd.silenceSupported)
}

@Test func optionalFieldsMayBeMissing() throws {
    let bare = try decodeEvent(#"{"id":5}"#)
    #expect(bare.ruleID == nil)
    #expect(bare.severity == "" && bare.status == "" && bare.title == "" && bare.description == "")
    #expect(bare.metricValue == nil && bare.thresholdValue == nil)
    #expect(bare.platform == nil && bare.groupID == nil)
    #expect(bare.firedAt == nil && bare.resolvedAt == nil)
    #expect(bare.rule == nil && bare.groupName == nil && bare.resolvedByUserName == nil)
    let nulls = try decodeEvent(#"{"id":5,"rule_id":null,"rule":null,"group_name":null,"dimensions":null,"metric_value":null,"fired_at":"garbage"}"#)
    #expect(nulls.rule == nil && nulls.groupName == nil && nulls.firedAt == nil && nulls.metricValue == nil)
    let blankDimensions = try decodeEvent(#"{"id":5,"dimensions":{"platform":"  ","group_id":0,"region":"x"}}"#)
    #expect(blankDimensions.platform == nil)
    #expect(blankDimensions.groupID == nil)
    let wrongTypes = try decodeEvent(#"{"id":5,"severity":1,"metric_value":"5.2","dimensions":{"group_id":"12"},"rule":{"id":"x"}}"#)
    #expect(wrongTypes.severity == "" && wrongTypes.metricValue == nil && wrongTypes.groupID == nil && wrongTypes.rule == nil)
    #expect(throws: (any Error).self) { try decodeEvent(#"{"severity":"P1"}"#) }
}

@Test func resolvedEventKeepsResolverAndTime() throws {
    let event = try decodeEvent(#"""
    {"id":8,"rule_id":2,"severity":"P2","status":"manual_resolved","title":"P2: 内存","fired_at":"2026-10-21T20:00:00Z",
     "resolved_at":"2026-10-21T14:10:00.5Z","silence":null,"rule":null,"group_name":null,"resolved_by_user_id":1,"resolved_by_user_name":"admin"}
    """#)
    #expect(!event.isFiring)
    #expect(event.resolvedByUserName == "admin")
    let resolved = try #require(event.resolvedAt)
    #expect(abs(resolved.timeIntervalSince1970 - (ServerTime.parseTimestamp("2026-10-21T14:10:00Z")!.timeIntervalSince1970 + 0.5)) <= 0.001)
}

@Test func alertRulesItemDecodesAsEventRuleAndCanBeAttached() throws {
    let item = #"""
    {"id":7,"name":"标准组错误率","description":"","enabled":true,"severity":"P1","metric_type":"error_rate","operator":">=",
     "threshold":5.5,"window_minutes":10,"sustained_minutes":3,"cooldown_minutes":10,"notify_email":false,"filters":{"group_id":12},
     "created_at":"2026-10-01T00:00:00Z","updated_at":"2026-10-01T00:00:00Z"}
    """#
    let rule = try JSONDecoder().decode(AlertEventRule.self, from: Data(item.utf8))
    #expect(rule == AlertEventRule(id: 7, name: "标准组错误率", metricType: "error_rate", comparison: ">=", threshold: 5.5,
                                   windowMinutes: 10, sustainedMinutes: 3, deleted: false))
    let original = try decodeEvent(#"{"id":1,"rule_id":7,"severity":"P1","status":"firing","title":"P1: 标准组错误率","rule":null}"#)
    let attached = original.replacingRule(rule)
    #expect(attached.rule == rule)
    #expect(attached.id == original.id && attached.title == original.title && attached.silenceSupported == original.silenceSupported)
    #expect(original.rule == nil)
    #expect(attached.replacingRule(nil).rule == nil)
}

@Test func alertRuleToleratesMissingNumbers() throws {
    let rule = try JSONDecoder().decode(AlertEventRule.self, from: Data(#"{"id":3,"name":"x","deleted":true}"#.utf8))
    #expect(rule.metricType == "" && rule.comparison == "" && rule.threshold == nil)
    #expect(rule.windowMinutes == 0 && rule.sustainedMinutes == 0 && rule.deleted)
}
