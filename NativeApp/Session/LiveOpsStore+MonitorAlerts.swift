import Foundation
import Observation
import os
import Sub2Core

// S1-16, 10 §6: 监控 · 告警. 告警中 is the session's one firing list (S1-05; the overview and the account tab read it too, and a
// read under a minute old is reused); 最近结束 is the last day's events without the firing ones, paged back by 加载更早. While the
// segment shows both are read every 60 seconds, backing off after failures (00 §4.6); a pull starts 最近结束 over; a write reads
// both again (LiveOpsStore.refreshAlertsAfterWrite). Every read is ops-gated and goes through `controlled(_:)` (S1D1-02).

extension LiveOpsStore {
    // MARK: - 读取与轮询（10 §6.2、§6.6）

    /// A pull or ··· 刷新 (`force`): both lists at once, 最近结束 from its first page again, asked even while the switch says off
    /// (as 概况's pull), so a 200 can turn it back on. A poll reuses a firing list under a minute old and merges 最近结束.
    func refreshMonitorAlerts(force: Bool) async {
        guard isCurrent(), site() != nil, force || !opsDisabled else { return }
        let wasOn = !opsDisabled, answered = MonitorBlockLoad(recent).answeredAt
        async let firing: Void = refreshFiringAlerts(maxAge: force ? 0 : Self.alertListMaxAge)
        async let ended: Void = refreshRecentAlerts(reset: force)
        _ = await (firing, ended)
        guard isCurrent(), MonitorBlockLoad(recent).answeredAt != answered else { return }
        monitor.markAlertsSettled(MonitorSettle(at: localNow(), opsOn: wasOn && !opsDisabled))
    }
    /// While the caller's task lives (告警 showing, the App active): read, then wait 60 seconds from the end of the read, longer
    /// after failures or through a 429 wait of either list. Back under ten seconds after the last answer waits out the rest first;
    /// the loop ends once ops monitoring is off or the session ended.
    func monitorAlertsPolling() async {
        guard !opsDisabled else { return }
        if let wait = alertsReentryWait() {
            do { try await sleep(.seconds(wait)) } catch { return }
        }
        while !Task.isCancelled, isCurrent(), !opsDisabled {
            await refreshMonitorAlerts(force: false)
            guard !opsDisabled else { return }
            let delay = max(recent.nextDelay(base: Self.pollInterval), firing.nextDelay(base: Self.pollInterval))
            do { try await sleep(.seconds(delay)) } catch { return }
        }
    }
    /// 最近结束's first page. `reset` (a pull, a refused cursor) drops the older pages and a 加载更早 on its way, and replaces a
    /// read on its way; `replacing` (after a write) only replaces it. A poll leaves one on its way to finish and merges its answer.
    func refreshRecentAlerts(reset: Bool, replacing: Bool = false) async {
        guard isCurrent(), site() != nil, reset || !opsDisabled else { return }
        if reset { monitor.alertsEarlier.reset() } else if !replacing, recent.isAwaitingAnswer { return }
        let fetch = controlled {
            try await $0.alertEvents(status: nil, timeRange: RecentAlerts.timeRange, limit: RecentAlerts.pageLimit, before: nil, groupID: nil,
                                     platform: nil)
        }
        await recent.load(isCurrent: isCurrent) { [weak self] in
            let raw = try await fetch()
            guard let self else { throw CancellationError() }
            let events = await self.normalizeReceivedAlerts(raw)
            guard !reset, let loaded = self.recent.value else { return RecentAlerts.firstPage(events, limit: RecentAlerts.pageLimit) }
            return loaded.mergingFirstPage(events)
        }
    }
    /// After a write: 最近结束 again once it was ever read, replacing a poll on its way.
    func refreshLoadedRecentAlerts() async {
        guard recent.value != nil else { return }
        await refreshRecentAlerts(reset: false, replacing: true)
    }
    /// 加载更早: the page before the cursor; nothing at the end, while one is on its way or while ops monitoring is off. The page
    /// lands only if the list still ends at that cursor. A reasonless 400 (10 §6.5) is logged and the first page read again.
    func loadEarlierAlerts() async {
        let earlier = monitor.alertsEarlier
        guard isCurrent(), site() != nil, !opsDisabled, let cursor = recent.value?.cursor, !earlier.isAwaitingAnswer else { return }
        let before = earlier.updatedAt
        let fetch = controlled {
            try await $0.alertEvents(status: nil, timeRange: RecentAlerts.timeRange, limit: RecentAlerts.pageLimit, before: cursor, groupID: nil,
                                     platform: nil)
        }
        await earlier.load(isCurrent: isCurrent) { [weak self] in
            let raw = try await fetch()
            guard let self else { throw CancellationError() }
            return await self.normalizeReceivedAlerts(raw)
        }
        guard isCurrent() else { return }
        if case .loaded(let page, let at) = earlier.state, at != before {
            recent.updateValue { $0.appendingEarlier(page, expectedCursor: cursor) }
        } else if earlier.error != nil, RecentAlerts.isCursorRejection(earlier.lastError) {
            Self.alertsLog.error("GET ops/alert-events 400 cursor refused, request \(earlier.lastError?.requestID ?? "-", privacy: .public)")
            earlier.reset()
            await refreshRecentAlerts(reset: true)
        }
    }

    // MARK: - 展示（10 §6.3、§6.5）

    var monitorAlertsLayout: MonitorAlertsPresentation.Layout {
        MonitorAlertsPresentation.layout(firing: firing.state.display, ended: recent.state.display)
    }
    /// 告警中's rows: an event already in 最近结束 has ended.
    var monitorFiringRows: [AlertEvent] { MonitorAlertsPresentation.visibleFiring(firingAlerts, ended: recentAlerts) }
    var monitorEndedFooter: MonitorAlertsPresentation.EndedFooter {
        let earlier = monitor.alertsEarlier
        return MonitorAlertsPresentation.endedFooter(hasMore: recent.value?.hasMore ?? false, isLoading: earlier.isLoading,
                                                     failed: earlier.error != nil)
    }
    /// Under 告警中 when more fire than its list holds.
    var monitorFiringTruncationNote: String? {
        let limit = site()?.has(.opsAlertEventCounts) == true ? Self.firingListLimit : Self.firingCountingLimit
        return MonitorAlertsPresentation.truncationNote(listCount: firingAlerts.count, listLimit: limit, total: monitorFiringCount)
    }

    /// The rest of `monitorReentryGap` since the lists last answered; nil once it passed, or when monitoring was off through it.
    private func alertsReentryWait() -> TimeInterval? {
        guard let settled = monitor.alertsSettledAt, settled.opsOn else { return nil }
        let elapsed = localNow().timeIntervalSince(settled.at)
        guard elapsed >= 0, elapsed < Self.monitorReentryGap else { return nil }
        return Self.monitorReentryGap - elapsed
    }
    private static let alertsLog = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "monitor.alerts")
}
