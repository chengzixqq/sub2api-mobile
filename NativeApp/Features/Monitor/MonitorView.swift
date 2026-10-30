import SwiftUI
import Sub2Core

/// 10 §4–§6 the monitor tab: 概况 / 渠道 / 告警 under the large title 监控, the subtitle following the segment. The segment chosen
/// stays for the session (U08, LiveOpsStore.monitor); a cross-tab intent is taken once (10 §0.7-4). The ··· menu refreshes and,
/// for the owner while monitoring is on, turns ops monitoring off after two confirmations (U10). 概况, 渠道 (S1-15) and 告警 (S1-16)
/// poll while they show and the App is active (D18: no scene-phase handler; the task restarts on the phase); 告警's row buttons ask
/// first through `.alertActions` (S1-06). Identifiers monitor.*.
struct MonitorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session

    var body: some View {
        Group {
            if let me = session?.site.me, MonitorTabPresentation.showsVendorPlaceholder(me) {
                ContentUnavailableView(MonitorTabPresentation.vendorPlaceholder, systemImage: "building.2")
                    .accessibilityIdentifier("monitor.vendor")
            } else if let store = model.liveOps {
                MonitorScreen(store: store)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(MainTab.monitor.title)
    }
}

private struct MonitorScreen: View {
    let store: LiveOpsStore
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var confirmsDisable = false
    @State private var alertRequest: AlertActionRequest?

    /// What starts and stops the shown segment's timers: the ops switch for 概况 and 告警, the channel monitor's for 渠道 (10 §5.2).
    private struct PollKey: Hashable {
        let segment: MonitorSegment
        let polls: Bool
        let opsDisabled: Bool
        let opsRevision: Int
        let channelMonitorEnabled: Bool?
    }
    private var pollKey: PollKey {
        let segment = store.monitor.segment
        let opsGated = segment != .channels
        return PollKey(segment: segment, polls: visible && router.selectedTab == .monitor && scenePhase == .active,
                       opsDisabled: opsGated && store.opsDisabled, opsRevision: opsGated ? store.opsRevision : 0,
                       channelMonitorEnabled: segment == .channels ? store.channelMonitorFeatureEnabled : nil)
    }

    var body: some View {
        let key = pollKey
        // Each minute “N 分钟前更新” is counted again.
        TimelineView(.everyMinute) { _ in
            page.navigationSubtitle(subtitle)
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { moreMenu } }
        .refreshable { await refresh() }
        .opsDisableConfirmation(isPresented: $confirmsDisable)
        .onAppear { visible = true; applyIntent() }
        .onDisappear { visible = false }
        .onChange(of: router.pendingIntent) { _, _ in applyIntent() }
        .task(id: key) {
            guard key.polls else { return }
            switch key.segment {
            case .overview: if !key.opsDisabled { await store.monitorOverviewPolling() }
            case .channels: await store.channelsPolling()
            case .alerts: if !key.opsDisabled { await store.monitorAlertsPolling() }
            }
        }
    }

    private var page: some View {
        List {
            Section { segmentPicker }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            switch store.monitor.segment {
            case .overview:
                MonitorOverviewSection(store: store) { store.monitor.segment = .alerts }
            case .channels:
                ChannelsSection(store: store)
            case .alerts:
                AlertsSection(store: store, request: $alertRequest)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .alertActions($alertRequest)
    }

    /// 10 §4.1: a segment with something to look at carries its count.
    private var segmentPicker: some View {
        @Bindable var monitor = store.monitor
        return Picker("监控分段", selection: $monitor.segment) {
            ForEach(MonitorSegment.allCases) { segment in
                Text(MonitorTabPresentation.segmentTitle(segment.title, count: store.monitorSegmentCount(segment))).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("monitor.segment")
    }

    private var subtitle: String {
        store.monitorSubtitle(for: store.monitor.segment, now: store.serverNow(), timeZone: session?.site.serverTimeZone.timeZone ?? .current)
    }

    /// U11-style ··· menu: 刷新, then 关闭运维监控… for the owner on a site with `ops.monitoring_status` while monitoring is on (U10).
    private var moreMenu: some View {
        Menu {
            Button { Task { await refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
            if offersDisable {
                Button(role: .destructive) { confirmsDisable = true } label: { Label("关闭运维监控…", systemImage: "waveform.path.ecg") }
                    .disabled(store.isTogglingOps)
                    .readOnlyGate(showsCaption: false)
            }
        } label: {
            Label("更多", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("monitor.more")
    }
    private var offersDisable: Bool {
        guard let me = session?.site.me else { return false }
        return OpsDisabledPresentation.offersDisable(isAdministrator: me.isAdministrator, route: store.opsWriteRoute, isOpsDisabled: store.opsDisabled)
    }

    /// A pull or 刷新 reads everything the segment shows, 渠道 past the server's cache (10 §5.6), 告警's 最近结束 from its first page
    /// (10 §6.6).
    private func refresh() async {
        switch store.monitor.segment {
        case .overview: await store.refreshMonitorOverview(force: true)
        case .alerts: await store.refreshMonitorAlerts(force: true)
        case .channels: await store.refreshChannels(bypassCache: true)
        }
    }

    /// 10 §0.7-4: the intent is taken once, so coming back to the tab keeps the segment chosen since.
    private func applyIntent() {
        if case .monitor(let target)? = router.takeIntent(for: .monitor) { store.monitor.segment = target }
    }
}
