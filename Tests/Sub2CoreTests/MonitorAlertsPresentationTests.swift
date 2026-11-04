import Foundation
import Testing
@testable import Sub2Core

// S1-16: 监控 · 告警's words, row order and layout (10 §6.3, §6.5).

private typealias Presentation = MonitorAlertsPresentation
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func event(_ id: Int, severity: String = "P1", status: String = "firing") -> AlertEvent {
    AlertEvent(id: id, severity: severity, status: status, firedAt: now.addingTimeInterval(-Double(id) * 60))
}

@Test func sectionCopyMatchesSpec() {
    #expect([Presentation.firingTitle, Presentation.firingOrdinal, Presentation.endedTitle, Presentation.endedOrdinal] == ["告警中", "壹", "最近结束", "贰"])
    #expect(Presentation.emptyText == "没有告警" && Presentation.listFailedTitle == "告警加载失败")
    #expect(Presentation.loadEarlierTitle == "加载更早" && Presentation.loadingText == "正在加载…")
    #expect(Presentation.meta(2) == "2 条" && Presentation.meta(0) == "0 条" && Presentation.meta(1_200) == "1,200 条" && Presentation.meta(nil) == nil)
}

/// 10 §6.3 底行右: the silence button first, 手动解决 (primary) last; “改静默…” in a row, “改静默时长…” at full size (10 §3.3).
@Test func actionTitlesAndOrder() {
    #expect(Presentation.actionTitle(.silence, compact: true) == "静默…" && Presentation.actionTitle(.silence, compact: false) == "静默…")
    #expect(Presentation.actionTitle(.changeSilence, compact: true) == "改静默…")
    #expect(Presentation.actionTitle(.changeSilence, compact: false) == "改静默时长…")
    #expect(Presentation.actionTitle(.resolve, compact: true) == "手动解决")
    #expect(Presentation.orderedActions([.resolve, .silence]) == [.silence, .resolve])
    #expect(Presentation.orderedActions([.resolve, .changeSilence]) == [.changeSilence, .resolve])
    #expect(Presentation.orderedActions([.resolve]) == [.resolve] && Presentation.orderedActions([]).isEmpty)
    #expect(Presentation.spokenAction(.resolve, title: "标准组错误率 5.2%") == "手动解决 标准组错误率 5.2%")
    #expect(Presentation.spokenAction(.silence, title: "标准组错误率 5.2%") == "静默 标准组错误率 5.2%")
    #expect(Presentation.spokenAction(.changeSilence, title: "标准组错误率 5.2%") == "改静默 标准组错误率 5.2%")
}

/// The firing list may be up to a minute older than 最近结束 (20 §1.2): an event already ended there no longer fires.
@Test func visibleFiringDropsEventsAlreadyEnded() {
    let firing = [event(41), event(40, severity: "P2"), event(39, status: "resolved")]
    let ended = [event(41, status: AlertEvent.manualResolved), event(30, status: "resolved")]
    #expect(Presentation.visibleFiring(firing, ended: ended).map(\.id) == [40])
    #expect(Presentation.visibleFiring(firing, ended: []).map(\.id) == [41, 40])
}

/// 10 §6.3, §0.6: firing rows join one rail, P3 (neutral) draws none; ended rows never do.
@Test func railPositionsOnlyForFiringTones() {
    let rows = [event(1, severity: "P0"), event(2, severity: "P1"), event(3, severity: "P3"), event(4, severity: "P2")]
    #expect(Presentation.railPositions(rows) == [.top, .bottom, nil, .single])
    #expect(Presentation.railPositions([event(5, status: "resolved"), event(6, status: AlertEvent.manualResolved)]) == [nil, nil])
}

private let someFiring = BlockDisplay<[AlertEvent]>.value([], at: now, isRefreshing: false, updateFailed: false)
private let staleEnded = BlockDisplay<RecentAlerts>.value(RecentAlerts(), at: now, isRefreshing: false, updateFailed: true)

/// 10 §6.5: any value shows both sections (a failed refresh keeps it); a failure before any value is one 告警加载失败 row.
@Test(arguments: [
    (BlockDisplay<[AlertEvent]>.placeholder, BlockDisplay<RecentAlerts>.placeholder, MonitorAlertsPresentation.Layout.loading),
    (.failed(reason: "x"), .failed(reason: "y"), .failed),
    (.failed(reason: "x"), .placeholder, .failed),
    (.placeholder, .failed(reason: "y"), .failed),
    (someFiring, .failed(reason: "y"), .sections),
    (.failed(reason: "x"), staleEnded, .sections),
    (.placeholder, staleEnded, .sections),
])
func layoutFollowsBlockDisplays(firing: BlockDisplay<[AlertEvent]>, ended: BlockDisplay<RecentAlerts>, layout: MonitorAlertsPresentation.Layout) {
    #expect(Presentation.layout(firing: firing, ended: ended) == layout)
}

@Test(arguments: [(false, false, false, MonitorAlertsPresentation.EndedFooter.none), (false, true, true, .none),
                  (true, true, false, .loading), (true, false, true, .failed), (true, true, true, .loading), (true, false, false, .loadEarlier)])
func endedFooterStates(hasMore: Bool, isLoading: Bool, failed: Bool, footer: MonitorAlertsPresentation.EndedFooter) {
    #expect(Presentation.endedFooter(hasMore: hasMore, isLoading: isLoading, failed: failed) == footer)
}

/// More fire than the list holds (100 with `ops.alert_event_counts`): one line says only the newest show.
@Test func truncationNoteOnlyWhenListIsCut() {
    #expect(Presentation.truncationNote(listCount: 100, listLimit: 100, total: 120) == "只显示最新 100 条")
    #expect(Presentation.truncationNote(listCount: 100, listLimit: 100, total: 100) == nil)
    #expect(Presentation.truncationNote(listCount: 30, listLimit: 100, total: 120) == nil)
    #expect(Presentation.truncationNote(listCount: 100, listLimit: 100, total: nil) == nil)
}
