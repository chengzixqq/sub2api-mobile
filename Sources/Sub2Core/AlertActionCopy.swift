import Foundation

// S1-06: 10 §7.1 copy and rules for 手动解决 and 静默, shared by the alert detail, the monitor rows and the account tab's alert sheet.

/// C-6: what a page offers on a firing event; ending a silence is a choice inside 改静默时长.
public enum AlertActionKind: String, CaseIterable, Sendable {
    case resolve, silence, changeSilence
}

/// 10 §7.1: the same three durations as Web.
public enum AlertSilenceDuration: String, CaseIterable, Sendable {
    case hour = "1h", day = "24h", week = "7d"

    public var seconds: TimeInterval {
        switch self {
        case .hour: 3_600
        case .day: 86_400
        case .week: 604_800
        }
    }
    public var label: String {
        switch self {
        case .hour: "1 小时"
        case .day: "24 小时"
        case .week: "7 天"
        }
    }
    /// `now` is the server-corrected clock, so a slow phone never sends a time already past.
    public func until(from now: Date) -> Date { now.addingTimeInterval(seconds) }
}

/// 10 §0.7-8: an alert (手动解决) or an action sheet (静默, 改静默时长). 取消 is the view's.
public struct AlertActionDialog: Equatable, Sendable {
    public enum Style: Equatable, Sendable { case alert, actionSheet }
    public enum Choice: Hashable, Sendable { case resolve, silence(AlertSilenceDuration), endSilence }
    public struct Option: Equatable, Sendable, Identifiable {
        public let choice: Choice
        public let title: String
        public let isDestructive: Bool
        /// The button's accessibility identifier after `alertActions.`.
        public var id: String {
            switch choice {
            case .resolve: "resolve"
            case .silence(let duration): "silence." + duration.rawValue
            case .endSilence: "silence.end"
            }
        }
    }
    public let style: Style
    public let title: String
    public let message: String
    public let options: [Option]
}

/// What a write meant to change, for the read-back after an answer that never came (00 §2.4).
public enum AlertWriteIntent: Equatable, Sendable {
    case resolve, silence(AlertSilenceDuration), changeSilence(until: Date), endSilence
}

/// 10 §7.1 error table. The handler's own 400s (“Invalid until” and the like) have no reason, so they are program errors too.
/// `resultUnknown`: no answer (transport) or a gateway's 502 / 503 / 504, which the event read back decides.
public enum AlertWriteFailure: Equatable, Sendable {
    case opsDisabled, silenceMissing, eventMissing, invalidUntil, ruleRejected, programError, readOnly, resultUnknown, other

    public init(_ error: APIError) {
        switch (error.statusCode, error.reason) {
        case (404?, "OPS_DISABLED"?): self = .opsDisabled
        case (404?, "OPS_ALERT_SILENCE_NOT_FOUND"?): self = .silenceMissing
        case (404?, "OPS_ALERT_EVENT_NOT_FOUND"?): self = .eventMissing
        case (400?, "INVALID_UNTIL"?): self = .invalidUntil
        case (400?, "INVALID_RULE_ID"?): self = .ruleRejected
        case (400?, .none), (400?, "INVALID_STATUS"?), (400?, "INVALID_EVENT_ID"?), (400?, "INVALID_SILENCE_ID"?): self = .programError
        case (403?, "ACCESS_TOKEN_READ_ONLY"?): self = .readOnly
        case (.none, _): self = error.kind == .transport ? .resultUnknown : .other
        case (let status?, _): self = [502, 503, 504].contains(status) && SecurityInterruption(error) == nil ? .resultUnknown : .other
        }
    }
}

public enum AlertActionCopy {
    public static let resolvedReceipt = "已手动解决"
    public static let endedReceipt = "已结束静默"
    /// 00 §2.4: the read-back failed too.
    public static let unconfirmedReceipt = "结果未确认，请刷新核对后再操作"
    /// The read-back shows the write did not land; doing it again is safe.
    public static let notAppliedReceipt = "操作没有生效，可以重试"
    public static let retryTitle = "重试"

    /// Only firing events have actions. No silence without the `silence` key (S1D1-15: those servers have no silence table),
    /// without a rule id, or after the server refused this rule (400 INVALID_RULE_ID).
    public static func availableActions(event: AlertEvent, silenceRejected: Bool) -> [AlertActionKind] {
        guard event.isFiring else { return [] }
        guard event.silenceSupported, (event.ruleID ?? 0) > 0, !silenceRejected else { return [.resolve] }
        return [.resolve, event.silence == nil ? .silence : .changeSilence]
    }

    /// Design `vtSilenceScope`: the group's name (“分组 #7” without one), else “{平台} 平台”; nil for a server-wide rule.
    public static func silenceScope(_ event: AlertEvent, platformName: (String) -> String) -> String? {
        if let groupID = event.groupID, groupID > 0 {
            let name = event.groupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "分组 #\(groupID)" : name
        }
        guard let platform = event.platform?.trimmingCharacters(in: .whitespacesAndNewlines), !platform.isEmpty else { return nil }
        return platformName(platform) + " 平台"
    }

    public static func dialog(_ kind: AlertActionKind, event: AlertEvent, now: Date, timeZone: TimeZone,
                              platformName: (String) -> String = { GroupPlatform.title($0.lowercased()) }) -> AlertActionDialog {
        let durations = AlertSilenceDuration.allCases.map {
            AlertActionDialog.Option(choice: .silence($0), title: "静默 " + $0.label, isDestructive: false)
        }
        let explanation = "静默期间，这条规则" + (silenceScope(event, platformName: platformName).map { "在" + $0 } ?? "")
            + "不再产生新的告警事件。当前这条仍需手动解决。"
        switch kind {
        case .resolve:
            return AlertActionDialog(style: .alert, title: "手动解决这条告警？",
                                     message: "「\(AlertPresentation.title(event))」会标记为已手动解决。条件仍满足时，规则会再次触发。",
                                     options: [AlertActionDialog.Option(choice: .resolve, title: "手动解决", isDestructive: false)])
        case .silence:
            return AlertActionDialog(style: .actionSheet, title: "静默这条规则多久？", message: explanation, options: durations)
        case .changeSilence:
            let current = event.silence?.until.map { "当前静默至 " + AlertPresentation.silencedUntil($0, now: now, timeZone: timeZone) } ?? "当前已静默"
            return AlertActionDialog(style: .actionSheet, title: "改静默时长", message: current + "\n" + explanation,
                                     options: durations + [AlertActionDialog.Option(choice: .endSilence, title: "结束静默", isDestructive: true)])
        }
    }

    public static func silencedReceipt(_ duration: AlertSilenceDuration) -> String { "已静默 " + duration.label }
    /// “静默改为至 10:41”, the time in the server's zone.
    public static func changedReceipt(until: Date, now: Date, timeZone: TimeZone) -> String {
        "静默改为至 " + AlertPresentation.silencedUntil(until, now: now, timeZone: timeZone)
    }
    /// 20 章的写法：“撤销没有成功：{原因}”.
    public static func undoFailedReceipt(_ reason: String) -> String { "撤销没有成功：" + reason }

    /// 10 §7.1 table; anything else is the catalog's text (00 §3.4: never the server's message).
    public static func message(for error: APIError) -> String {
        switch AlertWriteFailure(error) {
        case .opsDisabled: "运维监控已关闭，无法处理告警"
        case .silenceMissing: "这条静默已不存在"
        case .eventMissing: "这条告警不存在或已被清理"
        case .invalidUntil: "静默时间无效（须在 30 天内）"
        case .ruleRejected: "规则已删除，无法静默"
        case .programError: "操作未完成（程序错误）"
        case .readOnly: "只读访问令牌不能处理告警"
        case .resultUnknown: unconfirmedReceipt
        case .other: error.localizedDescription
        }
    }

    /// 10 §7.1, 00 §2.4: whether the event read back shows the write landed. A changed silence counts within a second of the
    /// requested time (the server stores what it parsed from RFC3339 seconds).
    public static func readBackConfirms(_ intent: AlertWriteIntent, event: AlertEvent) -> Bool {
        switch intent {
        case .resolve: !event.isFiring
        case .silence: event.silence != nil
        case .changeSilence(let until): event.silence?.until.map { abs($0.timeIntervalSince(until)) <= 1 } ?? false
        case .endSilence: event.silence == nil
        }
    }
}
