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

// MARK: S1-03 counts, silences, cursor and local copies

private func decodeCounts(_ json: String) throws -> AlertCounts { try JSONDecoder().decode(AlertCounts.self, from: Data(json.utf8)) }
private func decodeSilence(_ json: String) throws -> AlertSilence { try JSONDecoder().decode(AlertSilence.self, from: Data(json.utf8)) }
private let zeroSeverities = ["P0": 0, "P1": 0, "P2": 0, "P3": 0]

@Test func alertCountsDecodeFiringAndEverySeverity() throws {
    let counts = try decodeCounts(#"{"firing":3,"by_severity":{"P0":1,"P1":2,"P2":0,"P3":0}}"#)
    #expect(counts.firing == 3)
    #expect(counts.count(severity: "P1") == 2 && counts.count(severity: " p1 ") == 2)
    #expect(counts.count(severity: "P4") == 0 && counts.count(severity: nil) == 0)
    #expect(counts.bySeverity == ["P0": 1, "P1": 2, "P2": 0, "P3": 0])
    #expect(AlertCounts.severities == ["P0", "P1", "P2", "P3"])
}

@Test func alertCountsFillMissingSeveritiesAndFiring() throws {
    let partial = try decodeCounts(#"{"by_severity":{"P2":4}}"#)
    #expect(partial.bySeverity == ["P0": 0, "P1": 0, "P2": 4, "P3": 0])
    #expect(partial.firing == 4)
    for json in [#"{}"#, #"{"by_severity":null}"#, #"{"firing":null,"by_severity":"x"}"#] {
        let empty = try decodeCounts(json)
        #expect(empty.firing == 0 && empty.bySeverity == zeroSeverities)
    }
    let built = AlertCounts(firing: nil, bySeverity: [" p0 ": 1, "P4": 2])
    #expect(built.bySeverity == ["P0": 1, "P1": 0, "P2": 0, "P3": 0, "P4": 2])
    #expect(built.firing == 3 && built.count(severity: "p4") == 2)
    #expect(AlertCounts(firing: 9, bySeverity: ["P1": 1]).firing == 9)
    #expect(AlertCounts() == AlertCounts(firing: 0, bySeverity: zeroSeverities))
}

@Test func alertSilenceDecodesBackendObject() throws {
    let silence = try decodeSilence(#"""
    {"id":9,"rule_id":41,"platform":"openai","group_id":12,"region":null,"until":"2026-10-22T02:41:00Z","reason":"",
     "created_by":1,"created_at":"2026-10-22T01:41:00Z","created_by_name":"admin"}
    """#)
    let until = try #require(ServerTime.parseTimestamp("2026-10-22T02:41:00Z"))
    #expect(silence == AlertSilence(id: 9, ruleID: 41, platform: "openai", groupID: 12, until: until))
    #expect(silence.ref == AlertSilenceRef(id: 9, until: until))
}

@Test func alertSilenceWithoutGroupOrPlatform() throws {
    let unscoped = try decodeSilence(#"{"id":4,"rule_id":2,"platform":"","until":"later"}"#)
    #expect(unscoped.groupID == nil && unscoped.platform == nil && unscoped.until == nil && unscoped.ruleID == 2)
    #expect(try decodeSilence(#"{"id":4,"platform":"  ","group_id":null}"#).platform == nil)
    #expect(AlertSilence(id: 1, platform: " openai ").platform == "openai")
    #expect(AlertSilence(id: 1, platform: " ").platform == nil)
    #expect(throws: (any Error).self) { try decodeSilence(#"{"rule_id":2}"#) }
}

@Test func alertEventCursorKeepsServerFraction() throws {
    let event = try decodeEvent(fullEvent)
    #expect(event.cursor?.firedAt == "2026-10-22T01:29:03.123456Z" && event.cursor?.id == 42)
    #expect(AlertEventCursor(serverFiredAt: "2026-10-22T01:29:03Z", id: 1)?.firedAt == "2026-10-22T01:29:03Z")
    #expect(AlertEventCursor(serverFiredAt: "2026-10-22T01:29:03.123456789Z", id: 1)?.firedAt == "2026-10-22T01:29:03.123456789Z")
    #expect(AlertEventCursor(serverFiredAt: "2026-10-21T22:59:03.5-03:30", id: 1)?.firedAt == "2026-10-22T02:29:03.5Z")
    #expect(AlertEventCursor(serverFiredAt: "garbage", id: 1) == nil)
    #expect(AlertEventCursor(serverFiredAt: nil, id: 1) == nil)
    #expect(AlertEventCursor(serverFiredAt: "2026-10-22T01:29:03Z", id: 0) == nil)
    #expect(try decodeEvent(#"{"id":5}"#).cursor == nil)
    #expect(try decodeEvent(#"{"id":5,"fired_at":"garbage"}"#).cursor == nil)
}

@Test func alertEventCursorFromDateUsesMilliseconds() throws {
    #expect(AlertEventCursor(firedAt: Date(timeIntervalSince1970: 1_800_000_000.25), id: 3).firedAt == "2027-01-15T08:00:00.250Z")
    let fired = Date(timeIntervalSince1970: 1_800_000_000)
    let built = AlertEvent(id: 3, status: "firing", firedAt: fired)
    #expect(built.cursor == AlertEventCursor(firedAt: fired, id: 3))
    #expect(built.cursor?.firedAt == "2027-01-15T08:00:00.000Z")
    #expect(AlertEvent(id: 3).cursor == nil)
    let given = AlertEventCursor(serverFiredAt: "2027-01-15T08:00:00.123456Z", id: 3)
    #expect(AlertEvent(id: 3, firedAt: fired, cursor: given).cursor == given)
}

@Test func alertEventCursorOrderComparesFractionThenID() throws {
    func cursor(_ raw: String, _ id: Int) throws -> AlertEventCursor { try #require(AlertEventCursor(serverFiredAt: raw, id: id)) }
    let whole = try cursor("2026-10-22T01:29:03Z", 9)
    let half = try cursor("2026-10-22T01:29:03.5Z", 1)
    let micro = try cursor("2026-10-22T01:29:03.500001Z", 1)
    let nextSecond = try cursor("2026-10-22T01:29:04Z", 1)
    #expect(whole < half && half < micro && micro < nextSecond)
    #expect(try cursor("2026-10-22T01:29:03.123456Z", 76) < cursor("2026-10-22T09:29:03.123456+08:00", 77))
    #expect(try !(cursor("2026-10-22T01:29:03.50Z", 1) < cursor("2026-10-22T01:29:03.5Z", 1)))
    #expect(try cursor("2026-10-21T23:59:59.9Z", 99) < cursor("2026-10-22T00:00:00Z", 1))
    #expect([nextSecond, whole, micro, half].sorted() == [whole, half, micro, nextSecond])
}

@Test func resolvedLocallyReturnsNewValueAndKeepsOriginal() throws {
    let original = try decodeEvent(fullEvent)
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    let resolved = original.resolvedLocally(at: at)
    #expect(resolved.status == "manual_resolved" && resolved.resolvedAt == at && !resolved.isFiring)
    #expect(resolved.silence == original.silence && resolved.rule == original.rule && resolved.cursor == original.cursor)
    #expect(resolved.silenceSupported && resolved.platform == "openai" && resolved.groupID == 12 && resolved.groupName == "标准组")
    #expect(resolved.id == original.id && resolved.title == original.title && resolved.firedAt == original.firedAt)
    #expect(original.status == "firing" && original.resolvedAt == nil)
}

@Test func withSilenceReplacesOrClearsWithoutTouchingSupportFlag() throws {
    let original = try decodeEvent(fullEvent)
    let until = Date(timeIntervalSince1970: 1_800_003_600)
    let replaced = original.withSilence(AlertSilenceRef(id: 5, until: until))
    #expect(replaced.silence == AlertSilenceRef(id: 5, until: until) && replaced.silenceSupported)
    let cleared = original.withSilence(nil)
    #expect(cleared.silence == nil && cleared.silenceSupported && cleared.cursor == original.cursor)
    #expect(original.silence?.id == 3)
    #expect(cleared.withSilence(original.silence) == original)
    let legacy = try decodeEvent(#"{"id":1,"status":"firing","fired_at":"2026-10-22T01:29:03Z"}"#)
    #expect(!legacy.withSilence(AlertSilenceRef(id: 5, until: until)).silenceSupported)
}

@Test func replacingRuleKeepsServerCursor() throws {
    let original = try decodeEvent(fullEvent)
    let stripped = original.replacingRule(nil)
    #expect(stripped.rule == nil && stripped.cursor?.firedAt == "2026-10-22T01:29:03.123456Z")
    #expect(stripped.replacingRule(original.rule) == original)
}

@Test func replacingGroupNameKeepsEverythingElse() throws {
    let original = try decodeEvent(fullEvent)
    let renamed = original.replacingGroupName(" 高级组 ")
    #expect(renamed.groupName == "高级组" && renamed.cursor == original.cursor && renamed.rule == original.rule)
    #expect(original.replacingGroupName("  ").groupName == nil && original.replacingGroupName(nil).groupName == nil)
    #expect(renamed.replacingGroupName("标准组") == original)
    #expect(original.groupName == "标准组")
}
