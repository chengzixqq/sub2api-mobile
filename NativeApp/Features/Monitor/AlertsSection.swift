import SwiftUI
import Sub2Core

/// 10 §6 监控 · 告警: 告警中（壹） and 最近结束（贰）, each with its count. Firing rows sit on the status rail with their small buttons;
/// ended rows are plain, with 加载更早 after them while there are older ones. A row opens its alert on this tab's stack; a button asks
/// first through the page's `.alertActions`. Ops monitoring off makes the segment the empty state (§6.5, §7.2). The segment polls,
/// so its status views leave a 429's end to the timer (S1D1-20); 加载更早 keeps its own. Identifiers monitor.alerts.*.
struct AlertsSection: View {
    let store: LiveOpsStore
    @Binding var request: AlertActionRequest?
    @Environment(AppRouter.self) private var router

    var body: some View {
        if store.opsDisabled {
            Section { OpsDisabledNotice(style: .emptyState, notesDataGap: true) }
                .listRowBackground(Color.clear)
        } else {
            switch store.monitorAlertsLayout {
            case .loading:
                Section { AlertsNote(text: MonitorAlertsPresentation.loadingText, id: "monitor.alerts.loading") }
            case .failed:
                Section { listFailure }
            case .sections:
                firingSection
                endedSection
            }
        }
    }

    // MARK: 告警中

    private var firingSection: some View {
        Section {
            switch store.firing.state.display {
            case .placeholder, .disabled:
                AlertsNote(text: MonitorAlertsPresentation.loadingText, id: "monitor.alerts.firing.loading")
            case .failed:
                BlockFailureRow(store.firing, id: "monitor.alerts.firing", resendsAfterWait: false, retry: retryFiring)
            case .value:
                firingRows
            }
        } header: {
            NumberedSectionHeader(title: MonitorAlertsPresentation.firingTitle, ordinal: MonitorAlertsPresentation.firingOrdinal,
                                  meta: MonitorAlertsPresentation.meta(store.monitorFiringCount), id: "monitor.alerts.firing") {
                BlockStatusAccessory(store.firing, id: "monitor.alerts.firing", resendsAfterWait: false, retry: retryFiring)
            }
        }
    }

    @ViewBuilder private var firingRows: some View {
        let rows = store.monitorFiringRows
        if rows.isEmpty {
            AlertsNote(text: MonitorAlertsPresentation.emptyText, id: "monitor.alerts.firing.empty")
        } else {
            ForEach(Array(zip(rows, MonitorAlertsPresentation.railPositions(rows))), id: \.0.id) { event, position in
                AlertRow(event: event, context: .monitor, railPosition: position, showsActions: true,
                         onAction: { request = AlertActionRequest(event: event, kind: $0) }, onOpen: { open(event) })
            }
        }
        if let note = store.monitorFiringTruncationNote {
            AlertsNote(text: note, id: "monitor.alerts.truncated", isFootnote: true)
        }
    }

    // MARK: 最近结束

    private var endedSection: some View {
        Section {
            switch store.recent.state.display {
            case .placeholder, .disabled:
                AlertsNote(text: MonitorAlertsPresentation.loadingText, id: "monitor.alerts.ended.loading")
            case .failed:
                BlockFailureRow(store.recent, id: "monitor.alerts.ended", resendsAfterWait: false, retry: retryEnded)
            case .value(let recent, _, _, _):
                if recent.events.isEmpty {
                    AlertsNote(text: MonitorAlertsPresentation.emptyText, id: "monitor.alerts.ended.empty")
                } else {
                    ForEach(recent.events) { event in
                        AlertRow(event: event, context: .monitor, railPosition: nil, onOpen: { open(event) })
                    }
                }
                endedFooter
            }
        } header: {
            NumberedSectionHeader(title: MonitorAlertsPresentation.endedTitle, ordinal: MonitorAlertsPresentation.endedOrdinal,
                                  meta: MonitorAlertsPresentation.meta(store.recent.value?.events.count), id: "monitor.alerts.ended") {
                BlockStatusAccessory(store.recent, id: "monitor.alerts.ended", resendsAfterWait: false, retry: retryEnded)
            }
        }
    }

    /// 加载更早, its spinner, or its own failure row (it is asked for, not polled, so a 429's end sends it again).
    @ViewBuilder private var endedFooter: some View {
        switch store.monitorEndedFooter {
        case .none:
            EmptyView()
        case .loadEarlier:
            Button(action: loadEarlier) {
                Text(MonitorAlertsPresentation.loadEarlierTitle).font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("monitor.alerts.loadEarlier")
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel(MonitorAlertsPresentation.loadingText)
                .accessibilityIdentifier("monitor.alerts.earlier.loading")
        case .failed:
            BlockFailureRow(store.monitor.alertsEarlier, id: "monitor.alerts.earlier", retry: loadEarlier)
        }
    }

    // MARK: 失败与动作

    /// Neither list has anything to show and one failed: one 告警加载失败 · 重试 for both, which reads both again.
    @ViewBuilder private var listFailure: some View {
        if store.recent.error != nil {
            listFailureRow(store.recent)
        } else {
            listFailureRow(store.firing)
        }
    }
    private func listFailureRow<Value: Sendable>(_ load: LoadState<Value>) -> some View {
        BlockFailureRow(title: MonitorAlertsPresentation.listFailedTitle, error: load.lastError, occurredAt: load.lastErrorAt, refresh: load.refresh,
                        id: "monitor.alerts", resendsAfterWait: false, retry: retryAll)
    }

    private func open(_ event: AlertEvent) { router.push(.alert(id: event.id)) }
    private func retryAll() { Task { await store.refreshMonitorAlerts(force: true) } }
    private func retryFiring() { Task { await store.refreshFiringAlerts(maxAge: 0) } }
    private func retryEnded() { Task { await store.refreshRecentAlerts(reset: false, replacing: true) } }
    private func loadEarlier() { Task { await store.loadEarlierAlerts() } }
}

/// One line of the segment: 正在加载…, 没有告警, or the note under a cut list.
private struct AlertsNote: View {
    let text: String
    let id: String
    var isFootnote = false

    var body: some View {
        Text(text).font(isFootnote ? .footnote : .subheadline).foregroundStyle(Palette.ink3)
            .frame(maxWidth: .infinity, minHeight: isFootnote ? nil : 44, alignment: .leading)
            .accessibilityIdentifier(id)
    }
}
