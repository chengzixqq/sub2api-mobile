import SwiftUI
import Sub2Core

/// 10 §4.3 监控 · 概况: 服务器（贰, “仅管理员可见”）under 运行, for the site owner only. CPU / 内存 with their bars and the last
/// hour's lines, 并发 · 排队 · QPS · SLA, a row per background job and 日志采集 with the rejections of the last hour; nothing opens
/// anything (U09). A read that failed before any value gets 加载失败 · 重试 under its row, several share one row at the top; a
/// failed refresh marks the title. The section polls with the run, so its status views leave a 429's end to the timer
/// (S1D1-20). Tones live in the readings' identifiers (monitor.server.cpu.critical …) for the UI tests. Identifiers
/// monitor.server.*.
struct MonitorServerSection: View {
    let store: LiveOpsStore

    var body: some View {
        let display = store.monitorServerDisplay(now: store.serverNow())
        let failure = display.failure
        return Section {
            if let failure, failure.anchor == nil { failureRow(failure) }
            ServerMetersRow(cpu: display.cpu, memory: display.memory, isLoading: display.isOverviewLoading)
            if let failure, failure.anchor == .systemMetrics { failureRow(failure) }
            ServerFiguresRow(concurrency: display.concurrency, qps: display.qps, sla: display.sla,
                             concurrencyLoading: display.loadingParts.contains(.concurrency), overviewLoading: display.isOverviewLoading)
            if let failure, failure.anchor == .concurrency { failureRow(failure) }
            jobRows(display.jobs)
            ServerIngestRow(line: display.ingest, isLoading: !display.loadingParts.isDisjoint(with: [.logHealth, .ingress]))
                .railRow(tone: nil, position: nil)
            if let failure, failure.anchor == .logHealth || failure.anchor == .ingress { failureRow(failure) }
        } header: {
            NumberedSectionHeader(title: MonitorServerPresentation.title, ordinal: ChineseOrdinal.text(2), meta: MonitorServerPresentation.meta,
                                  id: "monitor.server.header") {
                staleAccessory(display.staleParts)
            }
        }
    }

    private func retry(_ parts: [MonitorServerPart]) { Task { await store.refreshMonitorServerParts(parts) } }

    /// One row for every read that failed without a value; its details are the first one's.
    @ViewBuilder private func failureRow(_ failure: MonitorServerDisplay.FailureRow) -> some View {
        if let first = failure.parts.first {
            let block = store.monitorBlockFailure(first)
            BlockFailureRow(title: failure.title, error: block.error, occurredAt: block.occurredAt, refresh: block.refresh, id: "monitor.server.load",
                            resendsAfterWait: false) { retry(failure.parts) }
        }
    }

    /// 更新失败 (or a 429's countdown) of the first stale read; tapping reads every stale one again.
    @ViewBuilder private func staleAccessory(_ parts: [MonitorServerPart]) -> some View {
        let reload: @MainActor () -> Void = { retry(parts) }
        switch parts.first {
        case .systemMetrics?: BlockStatusAccessory(store.monitor.systemMetrics, id: "monitor.server", resendsAfterWait: false, retry: reload)
        case .concurrency?: BlockStatusAccessory(store.monitor.concurrency, id: "monitor.server", resendsAfterWait: false, retry: reload)
        case .logHealth?: BlockStatusAccessory(store.monitor.logHealth, id: "monitor.server", resendsAfterWait: false, retry: reload)
        case .ingress?: BlockStatusAccessory(store.monitor.ingress, id: "monitor.server", resendsAfterWait: false, retry: reload)
        case nil: EmptyView()
        }
    }

    /// The jobs join one status rail where they need attention (00 §8.1); none of them is a button.
    @ViewBuilder private func jobRows(_ jobs: MonitorServerDisplay.Jobs) -> some View {
        switch jobs {
        case .loading:
            ServerPlainRow(title: MonitorServerPresentation.jobsPlaceholderTitle, trailing: DisplayFormat.missing, id: "monitor.server.jobs.loading")
                .redacted(reason: .placeholder)
                .railRow(tone: nil, position: nil)
        case .missing:
            ServerPlainRow(title: MonitorServerPresentation.jobsPlaceholderTitle, trailing: DisplayFormat.missing, id: "monitor.server.jobs.missing")
                .railRow(tone: nil, position: nil)
        case .empty:
            ServerPlainRow(title: MonitorServerPresentation.noHeartbeats, trailing: nil, id: "monitor.server.jobs.empty")
                .railRow(tone: nil, position: nil)
        case .lines(let lines):
            let positions = RailPosition.positions(of: lines) { $0.tone?.drawsRail == true }
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                ServerJobRow(line: line).railRow(tone: line.tone, position: positions[index])
            }
        }
    }
}

/// CPU and 内存 side by side; one above the other at accessibility sizes.
private struct ServerMetersRow: View {
    let cpu: MonitorServerDisplay.MeterDisplay
    let memory: MonitorServerDisplay.MeterDisplay
    let isLoading: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
        layout {
            UsageMeter(meter: cpu, isLoading: isLoading)
            UsageMeter(meter: memory, isLoading: isLoading)
        }
        .padding(.vertical, 6)
    }
}

/// The design's mo-meter: the name and the percentage, the bar, then the last hour's line on 0–100 (none with fewer than two points).
private struct UsageMeter: View {
    static let trendHeight: CGFloat = 22
    let meter: MonitorServerDisplay.MeterDisplay
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(meter.meter.title).font(.subheadline).foregroundStyle(Palette.ink2)
                Spacer(minLength: 4)
                Text(meter.reading.text).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .redacted(reason: isLoading ? .placeholder : [])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(meter.meter.title)
            .accessibilityValue(isLoading ? HomeInlineFigure.loadingValue : DisplayFormat.spoken(meter.reading.text))
            .accessibilityIdentifier("monitor.server.\(meter.meter.rawValue).\(meter.toneKey)")
            MeterBar(fraction: meter.reading.fraction, tone: meter.reading.tone)
            trend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var trend: some View {
        if meter.trend.isEmpty {
            Color.clear.frame(height: Self.trendHeight).accessibilityHidden(true)
        } else {
            Sparkline(series: SparklineSeries(values: meter.trend, fixedUpperBound: 100), showsArea: false, tint: Palette.ink2, height: Self.trendHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(meter.meter.trendLabel)
                .accessibilityValue(meter.spokenTrend)
                .accessibilityIdentifier("monitor.server.\(meter.meter.rawValue).trend")
        }
    }
}

/// A capacity bar on the track colour, in the reading's tone (critical from 90%, caution from 75%). Not C-7's CapacityBar (S2-09).
private struct MeterBar: View {
    let fraction: Double?
    let tone: Tone?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.sunken)
                Capsule().fill(tone?.base ?? Palette.ink2).frame(width: proxy.size.width * min(max(fraction ?? 0, 0), 1))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// 并发 · 排队 · QPS · SLA on one line, two by two when it does not fit. With realtime monitoring off 并发 is “—” with a note beside it
/// (appendix A S7: not ops monitoring).
private struct ServerFiguresRow: View {
    let concurrency: MonitorPresentation.ConcurrencyReading
    let qps: String
    let sla: String
    let concurrencyLoading: Bool
    let overviewLoading: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                inUse; queue; qpsFigure; slaFigure
                Spacer(minLength: 0)
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow { inUse; queue }
                GridRow { qpsFigure; slaFigure }
            }
        }
        .frame(minHeight: 44)
    }

    private var inUse: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            HomeInlineFigure(label: "并发", value: concurrency.inUse, id: "monitor.server.concurrency", isLoading: concurrencyLoading)
            if concurrency.isRealtimeOff {
                Text(MonitorServerPresentation.realtimeOffNote).font(.footnote).foregroundStyle(Palette.ink3).lineLimit(1)
                    .accessibilityIdentifier("monitor.server.realtimeOff")
            }
        }
    }
    private var queue: some View {
        HomeInlineFigure(label: "排队", value: concurrency.queue, id: "monitor.server.queue", isLoading: concurrencyLoading)
    }
    private var qpsFigure: some View { HomeInlineFigure(label: "QPS", value: qps, id: "monitor.server.qps", isLoading: overviewLoading) }
    private var slaFigure: some View { HomeInlineFigure(label: "SLA", value: sla, id: "monitor.server.sla", isLoading: overviewLoading) }
}

/// One background job: its mark, name and last success, and the failure or the overdue note on one line. One VoiceOver element.
private struct ServerJobRow: View {
    let line: MonitorPresentation.JobLine

    var body: some View {
        HStack(spacing: 12) {
            glyph.frame(width: AttentionMetrics.iconWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.title).foregroundStyle(Palette.ink1).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(line.trailing).font(.subheadline).monospacedDigit()
                        .foregroundStyle(line.trailingIsCaution ? Tone.caution.ink : Palette.ink2).lineLimit(1)
                }
                if let detail = line.detail {
                    Text(detail).font(.footnote).foregroundStyle(Palette.ink3).lineLimit(1).truncationMode(.tail)
                }
            }
        }
        .railRowContent()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([line.title, DisplayFormat.spoken(line.trailing), line.detail].compactMap { $0 }.joined(separator: "，"))
        .accessibilityIdentifier("monitor.server.job.\(line.id)")
    }

    @ViewBuilder private var glyph: some View {
        switch line.state {
        case .ok: Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(Palette.ok)
        case .failing, .stale: Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Tone.caution.base)
        case .disabled: Image(systemName: "minus").foregroundStyle(Palette.ink3)
        case .unknown: Image(systemName: "questionmark").foregroundStyle(Palette.ink3)
        }
    }
}

/// 日志采集: healthy, an error, or unknown while its read failed; the write delay on the right and the last hour's rejections
/// with the jobs that need attention below. One VoiceOver element.
private struct ServerIngestRow: View {
    let line: MonitorPresentation.LogIngestLine
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            glyph.frame(width: AttentionMetrics.iconWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MonitorServerPresentation.ingestTitle).foregroundStyle(Palette.ink1)
                    Spacer(minLength: 8)
                    Text(line.trailing).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1)
                }
                Text(line.detail).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink3)
            }
        }
        .railRowContent()
        .redacted(reason: isLoading ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([MonitorServerPresentation.ingestTitle, DisplayFormat.spoken(line.trailing), line.detail].joined(separator: "，"))
        .accessibilityIdentifier("monitor.server.ingest")
    }

    @ViewBuilder private var glyph: some View {
        switch line.isHealthy {
        case true?: Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(Palette.ok)
        case false?: Image(systemName: "exclamationmark.octagon").foregroundStyle(Tone.critical.base)
        case nil: Image(systemName: "circle.dashed").foregroundStyle(Palette.ink3)
        }
    }
}

/// The jobs' row while there are none to list: 后台任务 with “—”, or 还没有后台任务心跳.
private struct ServerPlainRow: View {
    let title: String
    let trailing: String?
    let id: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(trailing == nil ? Palette.ink3 : Palette.ink1)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(Palette.ink2) }
        }
        .railRowContent()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(trailing.map(DisplayFormat.spoken) ?? "")
        .accessibilityIdentifier(id)
    }
}
