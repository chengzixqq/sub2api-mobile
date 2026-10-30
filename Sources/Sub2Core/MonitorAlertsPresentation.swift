import Foundation

/// 10 §6.3 / §6.5 (S1-16): 监控 · 告警's words, row order and layout. 告警中 and 最近结束 come from two reads (the shared firing
/// list and the last day's events), so each section keeps its own state; the rows are AlertRow's.
public enum MonitorAlertsPresentation {
    public static let firingTitle = "告警中"
    public static let firingOrdinal = "壹"
    public static let endedTitle = "最近结束"
    public static let endedOrdinal = "贰"
    public static let emptyText = MonitorTabPresentation.noAlerts
    public static let loadingText = "正在加载…"
    public static let listFailedTitle = "告警加载失败"
    public static let loadEarlierTitle = "加载更早"

    /// Neither section has anything to show yet; one has failed with nothing to show; or both sections.
    public enum Layout: Sendable, Equatable { case loading, failed, sections }
    /// The end of 最近结束.
    public enum EndedFooter: Sendable, Equatable { case none, loadEarlier, loading, failed }

    /// “N 条”; nil while the count is unknown.
    public static func meta(_ count: Int?) -> String? { count.map { DisplayFormat.grouped($0) + " 条" } }

    /// A row's small buttons say 改静默… (10 §6.3); the detail and the account tab's sheet say 改静默时长… (10 §3.3, 20 §1.4).
    public static func actionTitle(_ kind: AlertActionKind, compact: Bool) -> String {
        switch kind {
        case .resolve: "手动解决"
        case .silence: "静默…"
        case .changeSilence: compact ? "改静默…" : "改静默时长…"
        }
    }
    /// VoiceOver names the alert, since a list has many 手动解决.
    public static func spokenAction(_ kind: AlertActionKind, title: String) -> String {
        let verb = switch kind {
        case .resolve: "手动解决"
        case .silence: "静默"
        case .changeSilence: "改静默"
        }
        return verb + " " + title
    }
    /// The silence button first, 手动解决 (primary) last.
    public static func orderedActions(_ kinds: [AlertActionKind]) -> [AlertActionKind] {
        kinds.filter { $0 != .resolve } + kinds.filter { $0 == .resolve }
    }
    /// Firing events not already ended in 最近结束: the firing list may be up to a minute older (20 §1.2), and an event never
    /// fires again once ended.
    public static func visibleFiring(_ firing: [AlertEvent], ended: [AlertEvent]) -> [AlertEvent] {
        let endedIDs = Set(ended.map(\.id))
        return firing.filter { $0.isFiring && !endedIDs.contains($0.id) }
    }
    /// Firing rows join one rail; P3 and ended rows draw none (10 §0.6).
    public static func railPositions(_ rows: [AlertEvent]) -> [RailPosition?] {
        RailPosition.positions(of: rows) { AlertPresentation.tone($0)?.drawsRail == true }
    }
    /// Any value shows both sections, a failed refresh keeping it (10 §6.5); without one, a failure is the whole segment's.
    public static func layout<Firing: Sendable, Ended: Sendable>(firing: BlockDisplay<Firing>, ended: BlockDisplay<Ended>) -> Layout {
        if hasValue(firing) || hasValue(ended) { return .sections }
        return isFailed(firing) || isFailed(ended) ? .failed : .loading
    }
    public static func endedFooter(hasMore: Bool, isLoading: Bool, failed: Bool) -> EndedFooter {
        guard hasMore else { return .none }
        if isLoading { return .loading }
        return failed ? .failed : .loadEarlier
    }
    /// More fire than the list holds: “只显示最新 100 条” under 告警中.
    public static func truncationNote(listCount: Int, listLimit: Int, total: Int?) -> String? {
        guard listCount >= listLimit, let total, total > listCount else { return nil }
        return "只显示最新 " + DisplayFormat.grouped(listCount) + " 条"
    }

    private static func hasValue<Value: Sendable>(_ display: BlockDisplay<Value>) -> Bool {
        if case .value = display { true } else { false }
    }
    private static func isFailed<Value: Sendable>(_ display: BlockDisplay<Value>) -> Bool {
        if case .failed = display { true } else { false }
    }
}
