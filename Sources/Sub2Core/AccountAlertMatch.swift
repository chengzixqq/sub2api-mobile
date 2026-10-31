import Foundation

/// 20 §1.3: a platform header's alert, the firing event it stands for and its words.
public struct AccountAlertBadge: Equatable, Sendable {
    public let event: AlertEvent
    /// “P2 告警”, or “P2 已静默” while a silence covers the event.
    public let text: String
    /// 10 §0.6 alertTone; a silenced event still fires, so it keeps its colour.
    public let tone: Tone
    public let isSilenced: Bool
    /// Design useVaAlert: “P2 告警：{标题}[，已静默至 HH:MM]，打开处置”.
    public let accessibilityLabel: String
}

/// 20 §1.4: the 告警 sheet's event card and its two facts.
public struct AccountAlertSheetContent: Equatable, Sendable {
    public let title: String
    /// “P2” / “P2 已静默”.
    public let level: String
    public let tone: Tone
    /// Scope · rule, the rule's description as received without one.
    public let detail: String
    /// 维度.
    public let scope: String
    /// 状态.
    public let status: String
}

/// S2-22: the account tab's view of LiveOpsStore's one firing list (10 §0.5). The platform's events come from
/// `LiveOpsStore.firingAlerts(platform:)`; this picks the one a header shows and writes the header and the sheet. Words, times
/// and colours are AlertPresentation's; `now` is the server-corrected clock and `timeZone` the server's.
public enum AccountAlertMatch {
    public static let note = "告警只精确到分组或平台，不指向具体账号；先看本组需处理的账号。"
    public static let sheetTitle = "告警"
    public static let showNeedsTitle = "只看需处理的账号"
    public static let detailLinkTitle = "告警详情"

    /// 20 §1.2 / §1.5: the list counts once read (a refresh keeps it showing); unread, failed, disabled or with ops monitoring
    /// off, no header shows an alert and nothing is said. `lastReadFailed`: the last answer was a failure and no read succeeded
    /// since, so the old list a retry carries (or a cancelled retry restores) stays hidden (S2D1-17).
    public static func isListUsable(_ state: BlockState<[AlertEvent]>, lastReadFailed: Bool, opsDisabled: Bool) -> Bool {
        guard !opsDisabled, !lastReadFailed else { return false }
        switch state {
        case .loaded: return true
        case .loading(let previous, _): return previous != nil
        case .idle, .disabled, .failed: return false
        }
    }

    /// P0 0 … P3 3, ignoring case and spaces; any other level after P3.
    public static func severityRank(_ severity: String) -> Int {
        let levels = ["P0", "P1", "P2", "P3"]
        return levels.firstIndex(of: severity.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) ?? levels.count
    }

    /// 20 §1.3: of the firing events, the highest level, then the newest fired_at (a missing one last), then the larger id, as the
    /// server orders its list.
    public static func primaryEvent(in events: [AlertEvent]) -> AlertEvent? {
        events.filter(\.isFiring).min { lhs, rhs in
            let left = severityRank(lhs.severity), right = severityRank(rhs.severity)
            if left != right { return left < right }
            if lhs.firedAt != rhs.firedAt { return (lhs.firedAt ?? .distantPast) > (rhs.firedAt ?? .distantPast) }
            return lhs.id > rhs.id
        }
    }

    /// nil when no event of the platform fires (20 §1.3: then nothing shows).
    public static func badge(for events: [AlertEvent], now: Date, timeZone: TimeZone) -> AccountAlertBadge? {
        guard let event = primaryEvent(in: events) else { return nil }
        let severity = level(event)
        let silenced = event.silence != nil
        let spokenSilence = event.silence.map { "，" + silenceWords($0, now: now, timeZone: timeZone) } ?? ""
        return AccountAlertBadge(event: event, text: words(severity, silenced ? "已静默" : "告警"), tone: tone(event), isSilenced: silenced,
                                 accessibilityLabel: words(severity, "告警：") + AlertPresentation.title(event) + spokenSilence + "，打开处置")
    }

    public static func sheetContent(_ event: AlertEvent, now: Date, timeZone: TimeZone, platformName: (String) -> String,
                                    latencyMetricsSupported: Bool) -> AccountAlertSheetContent {
        AccountAlertSheetContent(title: AlertPresentation.title(event), level: event.silence == nil ? level(event) : words(level(event), "已静默"),
                                 tone: tone(event),
                                 detail: AlertPresentation.detailLine(event, platformName: platformName, latencyMetricsSupported: latencyMetricsSupported),
                                 scope: AlertPresentation.scopeText(event, platformName: platformName),
                                 status: statusText(event, now: now, timeZone: timeZone))
    }

    /// “告警中”, or “告警中 · 已静默至 10:41” (“明天 09:41” and so on across days); “告警中 · 已静默” without a readable end.
    public static func statusText(_ event: AlertEvent, now: Date, timeZone: TimeZone) -> String {
        let firing = AlertPresentation.statusWord("firing")
        return event.silence.map { firing + " · " + silenceWords($0, now: now, timeZone: timeZone) } ?? firing
    }

    /// A write the sheet started went through once the store shows it: the event left the firing list or ended, or its silence
    /// changed. A failed write changes nothing locally (10 §7.1).
    public static func actionTookEffect(before: AlertEvent, after: AlertEvent?) -> Bool {
        guard let after, after.isFiring else { return true }
        return after.silence != before.silence
    }

    private static func level(_ event: AlertEvent) -> String { event.severity.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func tone(_ event: AlertEvent) -> Tone { AlertPresentation.tone(event) ?? .caution }
    private static func words(_ severity: String, _ tail: String) -> String { severity.isEmpty ? tail : severity + " " + tail }
    private static func silenceWords(_ silence: AlertSilenceRef, now: Date, timeZone: TimeZone) -> String {
        silence.until.map { "已静默至 " + AlertPresentation.silencedUntil($0, now: now, timeZone: timeZone) } ?? "已静默"
    }
}
