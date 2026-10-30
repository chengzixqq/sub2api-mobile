import SwiftUI
import Sub2Core

/// 10 §3: one alert, pushed as `.alert(id:)` from the overview's alert rows (S1-10), the monitor's alerts (S1-16), the account tab's
/// alert sheet (S2-22) and later a push notification (stage 6). The status card with its buttons, then 壹 范围 and 贰 规则. The
/// session's copy shows at once (the card's skeleton without one); the event is read on entry, after a write, back in the foreground
/// and every 60 seconds while the page shows; a pull also reads 范围 again. AlertDetailModel decides what to send.
/// Identifiers alert.detail (the list), alert.detail.skeleton, alert.detail.notFound, alert.detail.back, alert.detail.scope.<row>,
/// alert.detail.rule.<key>; the card's are in AlertStatusCard.swift. The error-count row's failure is alert.detail.scope.errors.failure
/// with alert.detail.scope.errors.retry.
struct AlertDetailView: View {
    let id: Int
    @Environment(AppModel.self) private var model

    init(id: Int) { self.id = id }

    var body: some View {
        Group {
            if let store = model.liveOps {
                AlertDetailScreen(id: id, store: store).id(ObjectIdentifier(store))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(AlertScopePresentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AlertDetailScreen: View {
    let store: LiveOpsStore
    @State private var detail: AlertDetailModel
    @State private var request: AlertActionRequest?
    @State private var visible = false
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    private static let cardInsets = EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)

    init(id: Int, store: LiveOpsStore) {
        self.store = store
        _detail = State(initialValue: AlertDetailModel(eventID: id, store: store))
    }

    /// What reads the event again at once: a write to it on any page, the foreground, compliance passed, the ops switch (D18: no
    /// scene-phase handler here).
    private struct ReloadKey: Hashable {
        let revision, foreground, compliance, opsRevision: Int
        let opsDisabled: Bool
    }
    private var reloadKey: ReloadKey {
        ReloadKey(revision: store.alertRevision(id: detail.eventID), foreground: model.foregroundRevision,
                  compliance: model.securityPrompts.complianceRevision, opsRevision: store.opsRevision, opsDisabled: store.opsDisabled)
    }
    private var clock: Date { session?.client.serverClock.now() ?? Date() }
    private var timeZone: TimeZone { session?.site.serverTimeZone.timeZone ?? .current }

    var body: some View {
        let polls = visible && scenePhase == .active
        // Each minute “12 分钟前恢复” and the silence's day are counted again.
        TimelineView(.everyMinute) { _ in
            content.navigationSubtitle(subtitle)
        }
        .alertActions($request)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .task(id: reloadKey) { await detail.load(refreshScope: true) }
        .task(id: polls) {
            guard polls else { return }
            await detail.polling()
        }
        .onChange(of: detail.dismissRequested) { _, requested in if requested { dismiss() } }
    }

    private var subtitle: String {
        guard let event = detail.event else { return "" }
        return AlertScopePresentation.navigationSubtitle(event, groupScope: detail.groupLoad.value)
    }

    @ViewBuilder private var content: some View {
        switch detail.phase {
        case .notFound: notFound
        case .opsDisabled: OpsDisabledNotice(style: .emptyState, notesDataGap: true)
        case .loading, .ready, .failed: page
        }
    }

    /// 10 §3.5: 「返回」 leaves the page; the lists drop the event with their next read.
    private var notFound: some View {
        ContentUnavailableView {
            Label(AlertScopePresentation.notFoundText, systemImage: "bell.slash")
        } actions: {
            Button("返回") { dismiss() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("alert.detail.back")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alert.detail.notFound")
    }

    private var page: some View {
        let now = clock, zone = timeZone
        return List {
            Section { statusBlock(now: now, zone: zone) }
                .listRowBackground(Color.clear)
                .listRowInsets(Self.cardInsets)
            if let event = detail.event {
                AlertScopeSection(event: event, detail: detail) { open($0) }
                ruleSection(event, now: now, zone: zone)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await detail.load(refreshScope: true, pullToRefresh: true) }
        .accessibilityIdentifier("alert.detail")
    }

    /// The card with its buttons; without an event the card's skeleton, or 加载失败 · 重试 once the first read failed. The event is
    /// read every minute, so a 429 wait ends on that timer (S1D1-20).
    @ViewBuilder private func statusBlock(now: Date, zone: TimeZone) -> some View {
        if let event = detail.event {
            VStack(spacing: 12) {
                AlertStatusCard(event: event, now: now, timeZone: zone) {
                    BlockStatusAccessory(state: detail.eventState, refresh: detail.eventLoad.refresh, id: "alert.detail.event",
                                         resendsAfterWait: false) { reload() }
                }
                if AlertScopePresentation.showsActions(event) {
                    AlertDetailActions(actions: store.alertActions.availableActions(for: event), isRunning: store.alertActions.isRunning(event.id)) {
                        request = AlertActionRequest(event: event, kind: $0)
                    }
                }
            }
        } else if detail.phase == .failed {
            BlockFailureRow(detail.eventLoad, id: "alert.detail.event", resendsAfterWait: false) { reload() }
                .padding(.horizontal, 16)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            AlertStatusCard(event: AlertEvent(id: 0, severity: "P1", status: "firing", title: "P1: 告警规则", metricValue: 0, thresholdValue: 0), now: now,
                            timeZone: zone, isPlaceholder: true) { EmptyView() }
        }
    }

    private func ruleSection(_ event: AlertEvent, now: Date, zone: TimeZone) -> some View {
        let rows = AlertScopePresentation.ruleRows(event, latencyMetricsSupported: session?.has(.opsAlertLatencyMetrics) == true, now: now,
                                                   timeZone: zone)
        return Section {
            ForEach(rows, id: \.key) { row in
                LabeledContent(row.label) {
                    Text(row.value).monospacedDigit().foregroundStyle(Palette.ink1).multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("alert.detail.rule." + row.key.rawValue)
            }
        } header: {
            NumberedSectionHeader(title: "规则", ordinal: "贰")
        }
    }

    private func reload() { Task { await detail.load(refreshScope: false) } }
    /// 10 §3.1: the channel row opens 监控 · 渠道, the server and site-wide rows 监控 · 概况 (the group and error-count rows are
    /// NavigationLinks).
    private func open(_ destination: AlertScopeDestination) {
        switch destination {
        case .group, .logs: if let route = destination.pushedRoute { router.push(route) }
        case .monitorChannels: router.select(.monitor(segment: .channels))
        case .monitorOverview: router.select(.monitor(segment: .overview))
        }
    }
}

/// 壹 范围: the one row the event's dimension calls for, with its own 加载失败 · 重试 below it (10 §3.5), then a group's or a
/// site-wide error rule's 错误请求 / 上游错误 row (S1-17).
private struct AlertScopeSection: View {
    let event: AlertEvent
    let detail: AlertDetailModel
    let open: (AlertScopeDestination) -> Void

    var body: some View {
        Section {
            switch AlertScopePresentation.kind(event) {
            case .group(let groupID):
                row(AlertScopePresentation.groupRow(event, groupID: groupID, scope: detail.groupLoad.value), id: "group", systemImage: "person.2")
                if detail.groupLoad.value == nil, detail.groupLoad.error != nil {
                    BlockFailureRow(detail.groupLoad, id: "alert.detail.scope.group") { Task { await detail.retryGroup() } }
                }
            case .platform(let platform):
                let disabled = detail.channelMonitorDisabled
                row(AlertScopePresentation.channelRow(platform: platform, items: detail.channelLoad.value?.items, channelMonitorDisabled: disabled),
                    id: "channel", systemImage: "antenna.radiowaves.left.and.right")
                if detail.channelLoad.value == nil, detail.channelLoad.error != nil, !disabled {
                    BlockFailureRow(detail.channelLoad, id: "alert.detail.scope.channel") { Task { await detail.retryChannels() } }
                }
            case let kind:
                if let monitor = AlertScopePresentation.monitorRow(kind) {
                    row(monitor, id: kind == .server ? "server" : "site", systemImage: kind == .server ? "server.rack" : "globe")
                }
            }
            if let query = detail.errorCountQuery { errorCountRow(query) }
        } header: {
            NumberedSectionHeader(title: "范围", ordinal: "壹")
        }
    }

    /// Without a count yet, a failure is the row's own 加载失败 · 重试; a kept count says 更新失败 and still opens the logs.
    @ViewBuilder private func errorCountRow(_ query: AlertErrorCountQuery) -> some View {
        let load = detail.errorCountLoad
        if load.value == nil, load.error != nil {
            BlockFailureRow(title: AlertScopePresentation.errorCountFailureTitle(query.kind), error: load.lastError, occurredAt: load.lastErrorAt,
                            refresh: load.refresh, id: "alert.detail.scope.errors") { Task { await detail.retryErrorCount() } }
        } else {
            row(AlertScopePresentation.errorCountRow(query, event: event, groupScope: detail.groupLoad.value, count: load.value,
                                                     refreshFailed: load.error != nil),
                id: "errors", systemImage: "exclamationmark.octagon")
        }
    }

    /// The group and error-count rows push onto this tab's stack as values (X39); the monitor rows switch tabs; a deleted group
    /// opens nothing.
    @ViewBuilder private func row(_ row: AlertScopeRow, id: String, systemImage: String) -> some View {
        let identifier = "alert.detail.scope." + id
        if let route = row.destination?.pushedRoute {
            NavigationLink(value: route) { AlertScopeRowLabel(row: row, systemImage: systemImage) }
                .accessibilityIdentifier(identifier)
        } else if let destination = row.destination {
            Button { open(destination) } label: { AlertScopeRowLabel(row: row, systemImage: systemImage, showsChevron: true) }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier)
        } else {
            AlertScopeRowLabel(row: row, systemImage: systemImage).accessibilityIdentifier(identifier)
        }
    }
}

/// A 范围 row: icon, title with the trailing words (toned, or grey), and the detail under it.
private struct AlertScopeRowLabel: View {
    let row: AlertScopeRow
    let systemImage: String
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(Palette.ink3).frame(width: AttentionMetrics.iconWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let trailing = row.trailing {
                        Text(trailing).font(.subheadline).monospacedDigit().foregroundStyle(trailingColor)
                    }
                }
                if let detail = row.detail { Text(detail).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2) }
            }
            if showsChevron { AttentionChevron() }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var trailingColor: Color {
        if row.trailingIsSecondary { return Palette.ink3 }
        return row.trailingTone?.ink ?? Palette.ink1
    }
}
