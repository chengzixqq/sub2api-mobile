import Foundation
import Testing
@testable import Sub2Core

// S1-06: 10 §7.1 dialogs, receipts, error table and read-back checks.

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let utc = TimeZone(identifier: "UTC")!
private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private let now = at("2026-10-22T09:41:00+08:00")
private let errorRule = AlertEventRule(id: 11, name: "标准组错误率", metricType: "error_rate", comparison: ">", threshold: 5, windowMinutes: 5)
private func event(status: String = "firing", ruleID: Int? = 11, platform: String? = nil, groupID: Int? = 2, groupName: String? = "标准组",
                   silence: AlertSilenceRef? = nil, silenceSupported: Bool = true, rule: AlertEventRule? = errorRule) -> AlertEvent {
    AlertEvent(id: 41, ruleID: ruleID, severity: "P1", status: status, title: "P1: 标准组错误率", metricValue: 5.2, platform: platform,
               groupID: groupID, firedAt: now.addingTimeInterval(-720), silence: silence, silenceSupported: silenceSupported, rule: rule,
               groupName: groupName)
}
private let sentence = "静默期间，这条规则在标准组不再产生新的告警事件。当前这条仍需手动解决。"

@Test func availableActionsFollowStatusSilenceKeyAndRule() {
    let silenced = AlertSilenceRef(id: 9, until: now.addingTimeInterval(3_600))
    #expect(AlertActionCopy.availableActions(event: event(status: "resolved"), silenceRejected: false).isEmpty)
    #expect(AlertActionCopy.availableActions(event: event(status: AlertEvent.manualResolved), silenceRejected: false).isEmpty)
    #expect(AlertActionCopy.availableActions(event: event(), silenceRejected: false) == [.resolve, .silence])
    #expect(AlertActionCopy.availableActions(event: event(status: " Firing "), silenceRejected: false) == [.resolve, .silence])
    #expect(AlertActionCopy.availableActions(event: event(silence: silenced), silenceRejected: false) == [.resolve, .changeSilence])
    #expect(AlertActionCopy.availableActions(event: event(ruleID: nil), silenceRejected: false) == [.resolve])
    #expect(AlertActionCopy.availableActions(event: event(ruleID: 0), silenceRejected: false) == [.resolve])
    #expect(AlertActionCopy.availableActions(event: event(), silenceRejected: true) == [.resolve])
    #expect(AlertActionCopy.availableActions(event: event(silence: silenced), silenceRejected: true) == [.resolve])
    // S1D1-15: no `silence` key, so no silence at all (with or without a platform).
    #expect(AlertActionCopy.availableActions(event: event(silenceSupported: false), silenceRejected: false) == [.resolve])
    #expect(AlertActionCopy.availableActions(event: event(platform: "anthropic", groupID: nil, silenceSupported: false),
                                             silenceRejected: false) == [.resolve])
}

@Test func resolveDialogUsesAlertTitle() {
    let dialog = AlertActionCopy.dialog(.resolve, event: event(), now: now, timeZone: shanghai)
    #expect(dialog.style == .alert)
    #expect(dialog.title == "手动解决这条告警？")
    #expect(dialog.message == "「标准组错误率 5.2%」会标记为已手动解决。条件仍满足时，规则会再次触发。")
    #expect(dialog.options.map(\.title) == ["手动解决"] && dialog.options.map(\.choice) == [.resolve])
    #expect(dialog.options.map(\.id) == ["resolve"] && !dialog.options[0].isDestructive)
}

@Test func silenceDialogNamesScopeLikeDesign() {
    let group = AlertActionCopy.dialog(.silence, event: event(), now: now, timeZone: shanghai)
    #expect(group.style == .actionSheet && group.title == "静默这条规则多久？" && group.message == sentence)
    #expect(group.options.map(\.title) == ["静默 1 小时", "静默 24 小时", "静默 7 天"])
    #expect(group.options.map(\.id) == ["silence.1h", "silence.24h", "silence.7d"])
    #expect(group.options.map(\.choice) == [.silence(.hour), .silence(.day), .silence(.week)])
    #expect(group.options.allSatisfy { !$0.isDestructive })
    let unnamed = AlertActionCopy.dialog(.silence, event: event(groupID: 7, groupName: " "), now: now, timeZone: shanghai)
    #expect(unnamed.message == "静默期间，这条规则在分组 #7不再产生新的告警事件。当前这条仍需手动解决。")
    let platform = AlertActionCopy.dialog(.silence, event: event(platform: "anthropic", groupID: nil, groupName: nil), now: now, timeZone: shanghai)
    #expect(platform.message == "静默期间，这条规则在Anthropic 平台不再产生新的告警事件。当前这条仍需手动解决。")
    let site = AlertActionCopy.dialog(.silence, event: event(groupID: nil, groupName: nil), now: now, timeZone: shanghai)
    #expect(site.message == "静默期间，这条规则不再产生新的告警事件。当前这条仍需手动解决。")
    #expect(AlertActionCopy.silenceScope(event(platform: "openai", groupID: 2), platformName: { $0 }) == "标准组")
    #expect(AlertActionCopy.silenceScope(event(platform: "zhipu", groupID: nil, groupName: nil), platformName: { GroupPlatform.title($0) })
            == "智谱 GLM 平台")
}

@Test func changeDialogStartsWithCurrentUntilAndEndsWithDestructiveEnd() {
    let sameDay = event(silence: AlertSilenceRef(id: 9, until: at("2026-10-22T10:41:00+08:00")))
    let dialog = AlertActionCopy.dialog(.changeSilence, event: sameDay, now: now, timeZone: shanghai)
    #expect(dialog.style == .actionSheet && dialog.title == "改静默时长")
    #expect(dialog.message == "当前静默至 10:41\n" + sentence)
    #expect(dialog.options.map(\.title) == ["静默 1 小时", "静默 24 小时", "静默 7 天", "结束静默"])
    #expect(dialog.options.map(\.id) == ["silence.1h", "silence.24h", "silence.7d", "silence.end"])
    #expect(dialog.options.last?.choice == .endSilence && dialog.options.map(\.isDestructive) == [false, false, false, true])
    let nextDay = at("2026-10-23T09:41:00+08:00")
    let later = AlertActionCopy.dialog(.changeSilence, event: event(silence: AlertSilenceRef(id: 9, until: nextDay)), now: now, timeZone: shanghai)
    #expect(later.message.hasPrefix("当前静默至 " + AlertPresentation.silencedUntil(nextDay, now: now, timeZone: shanghai) + "\n"))
    #expect(later.message.hasPrefix("当前静默至 明天 09:41\n"))
    let unreadable = AlertActionCopy.dialog(.changeSilence, event: event(silence: AlertSilenceRef(id: 9)), now: now, timeZone: shanghai)
    #expect(unreadable.message == "当前已静默\n" + sentence)
}

@Test func silenceDurationsComputeUntilFromServerNow() {
    #expect(AlertSilenceDuration.allCases == [.hour, .day, .week])
    #expect(AlertSilenceDuration.allCases.map(\.seconds) == [3_600, 86_400, 604_800])
    #expect(AlertSilenceDuration.allCases.map(\.label) == ["1 小时", "24 小时", "7 天"])
    #expect(AlertSilenceDuration.allCases.map(\.rawValue) == ["1h", "24h", "7d"])
    #expect(AlertSilenceDuration.hour.until(from: now) == at("2026-10-22T10:41:00+08:00"))
    #expect(AlertSilenceDuration.week.until(from: now) == now.addingTimeInterval(604_800))
}

@Test func alertActionReceiptsMatchSpec() {
    #expect(AlertActionCopy.resolvedReceipt == "已手动解决")
    #expect(AlertSilenceDuration.allCases.map(AlertActionCopy.silencedReceipt) == ["已静默 1 小时", "已静默 24 小时", "已静默 7 天"])
    #expect(AlertActionCopy.changedReceipt(until: at("2026-10-22T10:41:00+08:00"), now: now, timeZone: shanghai) == "静默改为至 10:41")
    let week = at("2026-10-29T09:41:00+08:00")
    #expect(AlertActionCopy.changedReceipt(until: week, now: now, timeZone: shanghai)
            == "静默改为至 " + AlertPresentation.silencedUntil(week, now: now, timeZone: shanghai))
    #expect(AlertActionCopy.changedReceipt(until: week, now: now, timeZone: shanghai) == "静默改为至 10月29日 09:41")
    #expect(AlertActionCopy.endedReceipt == "已结束静默")
    #expect(AlertActionCopy.undoFailedReceipt("这条静默已不存在") == "撤销没有成功：这条静默已不存在")
    #expect(AlertActionCopy.unconfirmedReceipt == "结果未确认，请刷新核对后再操作")
    #expect(AlertActionCopy.notAppliedReceipt == "操作没有生效，可以重试" && AlertActionCopy.retryTitle == "重试")
}

@Test func untilWordingUsesServerTimeZone() {
    let late = at("2026-10-22T23:30:00+08:00")
    let until = AlertSilenceDuration.hour.until(from: late)
    #expect(AlertActionCopy.changedReceipt(until: until, now: late, timeZone: shanghai) == "静默改为至 明天 00:30")
    #expect(AlertActionCopy.changedReceipt(until: until, now: late, timeZone: utc) == "静默改为至 16:30")
    let silenced = event(silence: AlertSilenceRef(id: 9, until: until))
    #expect(AlertActionCopy.dialog(.changeSilence, event: silenced, now: late, timeZone: shanghai).message.hasPrefix("当前静默至 明天 00:30\n"))
    #expect(AlertActionCopy.dialog(.changeSilence, event: silenced, now: late, timeZone: utc).message.hasPrefix("当前静默至 16:30\n"))
}

private let errorTable: [(Int, String?, AlertWriteFailure, String)] = [
    (404, "OPS_DISABLED", .opsDisabled, "运维监控已关闭，无法处理告警"),
    (404, "OPS_ALERT_SILENCE_NOT_FOUND", .silenceMissing, "这条静默已不存在"),
    (404, "OPS_ALERT_EVENT_NOT_FOUND", .eventMissing, "这条告警不存在或已被清理"),
    (400, "INVALID_UNTIL", .invalidUntil, "静默时间无效（须在 30 天内）"),
    (400, "INVALID_RULE_ID", .ruleRejected, "规则已删除，无法静默"),
    (400, "INVALID_STATUS", .programError, "操作未完成（程序错误）"),
    (400, "INVALID_EVENT_ID", .programError, "操作未完成（程序错误）"),
    (400, "INVALID_SILENCE_ID", .programError, "操作未完成（程序错误）"),
    // The handler's own 400s (“Invalid until” and the like) carry no reason (response.BadRequest).
    (400, nil, .programError, "操作未完成（程序错误）"),
    (403, "ACCESS_TOKEN_READ_ONLY", .readOnly, "只读访问令牌不能处理告警")
]

@Test(arguments: errorTable.indices)
func alertWriteErrorTableMapsEveryRow(index: Int) {
    let (status, reason, failure, text) = errorTable[index]
    let error = APIError.server(status: status, reason: reason)
    #expect(AlertWriteFailure(error) == failure)
    #expect(AlertActionCopy.message(for: error) == text)
}

@Test func transportAndGatewayErrorsAreResultUnknownButSecurityRefusalsAreNot() {
    #expect(AlertWriteFailure(APIError(kind: .transport, message: "无法连接站点")) == .resultUnknown)
    for status in [502, 503, 504] { #expect(AlertWriteFailure(APIError.server(status: status, reason: nil)) == .resultUnknown) }
    #expect(AlertWriteFailure(APIError.server(status: 503, envelope: nil)) == .resultUnknown)
    #expect(AlertWriteFailure(APIError.server(status: 503, reason: "STEP_UP_UNAVAILABLE")) == .other)
    #expect(AlertWriteFailure(APIError.server(status: 423, reason: "COMPLIANCE_REQUIRED")) == .other)
    #expect(AlertWriteFailure(APIError.server(status: 500, reason: "INTERNAL_ERROR")) == .other)
    #expect(AlertWriteFailure(APIError(kind: .validation, message: "无效的告警状态。")) == .other)
    #expect(AlertActionCopy.message(for: APIError(kind: .transport, message: "无法连接站点")) == AlertActionCopy.unconfirmedReceipt)
}

@Test func otherAlertWriteErrorsFallBackToCatalogText() {
    let server = APIError.server(status: 500, reason: "INTERNAL_ERROR")
    #expect(AlertActionCopy.message(for: server) == "站点暂时不可用" && AlertActionCopy.message(for: server) == server.localizedDescription)
    let limited = APIError.server(status: 429, reason: "RATE_LIMITED")
    #expect(AlertActionCopy.message(for: limited) == limited.localizedDescription)
    let cleared = APIError.server(status: 423, reason: "COMPLIANCE_REQUIRED").withSecurityOutcome(.passed)
    #expect(AlertActionCopy.message(for: cleared) == "合规确认已完成，请重新确认后发送")
}

@Test func readBackConfirmsPerIntent() {
    let target = at("2026-10-22T10:41:00+08:00")
    #expect(!AlertActionCopy.readBackConfirms(.resolve, event: event()))
    #expect(AlertActionCopy.readBackConfirms(.resolve, event: event(status: "resolved")))
    #expect(AlertActionCopy.readBackConfirms(.resolve, event: event(status: AlertEvent.manualResolved)))
    #expect(!AlertActionCopy.readBackConfirms(.silence(.hour), event: event()))
    #expect(AlertActionCopy.readBackConfirms(.silence(.hour), event: event(silence: AlertSilenceRef(id: 3, until: target))))
    let change = AlertWriteIntent.changeSilence(until: target)
    #expect(AlertActionCopy.readBackConfirms(change, event: event(silence: AlertSilenceRef(id: 9, until: target.addingTimeInterval(0.9)))))
    #expect(!AlertActionCopy.readBackConfirms(change, event: event(silence: AlertSilenceRef(id: 9, until: target.addingTimeInterval(5)))))
    #expect(!AlertActionCopy.readBackConfirms(change, event: event()))
    #expect(AlertActionCopy.readBackConfirms(.endSilence, event: event()))
    #expect(!AlertActionCopy.readBackConfirms(.endSilence, event: event(silence: AlertSilenceRef(id: 9, until: target))))
}
