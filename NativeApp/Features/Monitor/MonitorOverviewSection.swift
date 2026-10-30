import SwiftUI
import Sub2Core

/// 10 §4.3 监控 · 概况: 运行（壹, no window in the title) — 健康分 on the overview's gauge, 错误率 / 上游 429 / 529, the error-rate line
/// of the last 45 minutes and 告警中, which switches to the 告警 segment. With ops monitoring off the whole segment is the empty
/// state (§4.5, §7.2). The section polls, so its status views leave a 429's end to the timer (S1D1-20). Identifiers monitor.run.*.
struct MonitorOverviewSection: View {
    let store: LiveOpsStore
    /// 告警中: the page switches its own segment, without the router (10 §4.1).
    let showAlerts: @MainActor () -> Void

    var body: some View {
        if store.opsDisabled {
            Section { OpsDisabledNotice(style: .emptyState, notesDataGap: true) }
                .listRowBackground(Color.clear)
        } else {
            runSection
            // S1-14：服务器区 MonitorServerSection(store:) 接在这里。
        }
    }

    private var runSection: some View {
        let display = store.monitor.overview.state.display
        return Section {
            MonitorHealthRow(health: MonitorTabPresentation.health(display))
            ratesRow(isLoading: display == .placeholder)
            if case .failed = display {
                BlockFailureRow(store.monitor.overview, id: "monitor.run", resendsAfterWait: false, retry: retryRun)
            }
            trendRow
            alertsRow(store.monitorAlertsRow)
        } header: {
            NumberedSectionHeader(title: "运行", ordinal: "壹", id: "monitor.run.header") {
                BlockStatusAccessory(store.monitor.overview, id: "monitor.run", resendsAfterWait: false, retry: retryRun)
            }
        }
    }

    private func retryRun() { Task { await store.refreshMonitorBlock(.run, force: true) } }
    private func retryTrend() { Task { await store.refreshMonitorBlock(.errorTrend, force: true) } }

    private func ratesRow(isLoading: Bool) -> some View {
        let rates = MonitorTabPresentation.rates(store.monitor.overview.value)
        return HStack(spacing: 18) {
            HomeInlineFigure(label: "错误率", value: rates.errorRate, id: "monitor.run.errorRate", isLoading: isLoading)
            HomeInlineFigure(label: "上游 429", value: rates.upstream429, id: "monitor.run.upstream429", isLoading: isLoading)
            HomeInlineFigure(label: "529", spokenLabel: "上游 529", value: rates.upstream529, id: "monitor.run.upstream529", isLoading: isLoading)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
    }

    /// The line, or one “趋势加载失败 · 重试” row while it has never loaded; a failed refresh keeps the line it had.
    @ViewBuilder private var trendRow: some View {
        let load = store.monitor.errorTrend
        if case .failed = load.state.display {
            BlockFailureRow(title: MonitorTabPresentation.trendFailed, error: load.lastError, occurredAt: load.lastErrorAt, refresh: load.refresh,
                            id: "monitor.run.trend", resendsAfterWait: false, retry: retryTrend)
        } else {
            let points = load.value
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(MonitorTabPresentation.trendLabel).font(.footnote).foregroundStyle(Palette.ink2).accessibilityHidden(true)
                    Spacer(minLength: 8)
                    BlockStatusAccessory(load, id: "monitor.run.trend", resendsAfterWait: false, retry: retryTrend)
                }
                Sparkline(series: SparklineSeries(values: points ?? []))
                    .redacted(reason: points == nil ? .placeholder : [])
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(MonitorTabPresentation.trendLabel)
                    .accessibilityValue(points.map(MonitorTabPresentation.trendSpokenValue) ?? HomeInlineFigure.loadingValue)
                    .accessibilityIdentifier("monitor.run.trend")
            }
            .padding(.vertical, 4)
        }
    }

    /// The firing titles wrap to three lines; VoiceOver reads them all, and the 告警 segment lists them.
    private func alertsRow(_ row: MonitorAlertsRow) -> some View {
        Button(action: showAlerts) {
            HStack(spacing: 12) {
                Image(systemName: "bell").foregroundStyle(Palette.ink3).frame(width: AttentionMetrics.iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).foregroundStyle(Palette.ink1)
                    if let detail = row.detail {
                        Text(detail).font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(3)
                    }
                }
                Spacer(minLength: 8)
                AttentionChevron()
            }
            .railRowContent()
        }
        .buttonStyle(.plain)
        .railRow(tone: row.tone, position: .single)
        .accessibilityLabel(row.title)
        .accessibilityValue(row.detail ?? DisplayFormat.missingSpoken)
        .accessibilityHint("切到告警段")
        .accessibilityIdentifier("monitor.run.alerts")
    }
}

/// 健康分 on the overview's gauge, the same bands as the overview's 运行 (S1-18 may make one row of both).
private struct MonitorHealthRow: View {
    let health: HomeRunPresentation.Health

    var body: some View {
        HStack(spacing: 12) {
            Text("健康分").font(.subheadline).foregroundStyle(Palette.ink2)
            HealthScoreBar(reading: health.reading)
            Text(health.numberText).font(.title2.weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink1)
                .lineLimit(1).minimumScaleFactor(0.5)
            if let word = health.wordText {
                Text(word).font(.footnote.weight(.semibold)).foregroundStyle(health.tone?.ink ?? Palette.ink3).lineLimit(1)
            }
        }
        .frame(minHeight: 44)
        .redacted(reason: health == .loading ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("健康分")
        .accessibilityValue(health.spokenValue)
        .accessibilityIdentifier("monitor.run.health")
    }
}
