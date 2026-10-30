import SwiftUI
import Sub2Core

/// 10 §5 监控 · 渠道: the four counts, the collection-delay note and one row per group's channel, worst first; a row opens the
/// group (U07). The segment polls, so its status views leave a 429's end to the timer (S1D1-20). Off, empty and a vendor's 403
/// are empty states; the App has no switch for the channel monitor. Identifiers monitor.channels.*.
struct ChannelsSection: View {
    let store: LiveOpsStore

    var body: some View {
        switch store.channelSectionState {
        case .loading:
            Section { ChannelCountGrid(cells: ChannelSectionPresentation.countCells(nil), isLoading: true) }
                .listRowBackground(Color.clear)
            Section { ChannelSkeletonRows() } header: { header }
        case .disabled:
            notice(ChannelSectionPresentation.disabledTitle, detail: ChannelSectionPresentation.disabledDetail,
                   systemImage: "antenna.radiowaves.left.and.right.slash", id: "monitor.channels.disabled")
        case .forbidden:
            notice(MonitorTabPresentation.vendorPlaceholder, systemImage: "building.2", id: "monitor.channels.forbidden")
        case .empty:
            notice(ChannelSectionPresentation.emptyTitle, systemImage: "antenna.radiowaves.left.and.right", id: "monitor.channels.empty")
        case .failed:
            Section { ChannelCountGrid(cells: ChannelSectionPresentation.countCells(nil), isLoading: false) }
                .listRowBackground(Color.clear)
            Section {
                BlockFailureRow(title: ChannelSectionPresentation.failedTitle, error: store.channels.lastError, occurredAt: store.channels.lastErrorAt,
                                refresh: store.channels.refresh, id: "monitor.channels", resendsAfterWait: false, retry: retry)
            } header: { header }
        case .list:
            let items = store.channels.value?.items ?? []
            Section {
                ChannelCountGrid(cells: ChannelSectionPresentation.countCells(items), isLoading: false)
                if ChannelPresentation.showsCoverageHint(store.channels.value?.coverage) { ChannelCoverageRow() }
            }
            .listRowBackground(Color.clear)
            Section {
                ForEach(ChannelSectionPresentation.rows(items)) { row in ChannelLink(row: row) }
            } header: { header }
        }
    }

    private var header: some View {
        NumberedSectionHeader(title: ChannelSectionPresentation.sectionTitle, ordinal: ChannelSectionPresentation.sectionOrdinal,
                              meta: ChannelSectionPresentation.sectionMeta, id: "monitor.channels.header") {
            BlockStatusAccessory(store.channels, id: "monitor.channels", resendsAfterWait: false, retry: retry)
        }
    }

    private func retry() { Task { await store.refreshChannels(bypassCache: false) } }

    private func notice(_ title: String, detail: String? = nil, systemImage: String, id: String) -> some View {
        Section {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let detail { Text(detail) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(id)
        }
        .listRowBackground(Color.clear)
    }
}

/// The design's chan-summary: four cards side by side, two by two at accessibility sizes. A count above 0 takes its tone.
private struct ChannelCountGrid: View {
    let cells: [ChannelCountCell]
    let isLoading: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow { ForEach(row) { cell in tile(cell) } }
            }
        }
        .listRowInsets(EdgeInsets())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monitor.channels.summary")
    }

    private var rows: [[ChannelCountCell]] {
        let width = typeSize.isAccessibilitySize ? 2 : cells.count
        return stride(from: 0, to: cells.count, by: max(width, 1)).map { Array(cells[$0..<min($0 + width, cells.count)]) }
    }

    private func tile(_ cell: ChannelCountCell) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cell.value).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(color(cell))
            Text(cell.title).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 8))
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .redacted(reason: isLoading ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cell.title)
        .accessibilityValue(isLoading ? HomeInlineFigure.loadingValue : cell.spokenValue)
        .accessibilityIdentifier("monitor.channels.count." + cell.key)
    }

    private func color(_ cell: ChannelCountCell) -> Color {
        if let tone = cell.tone { return tone.ink }
        return cell.value == DisplayFormat.missing ? Palette.ink3 : Palette.ink1
    }
}

/// 10 §5.3: one neutral line above the list while collection lags.
private struct ChannelCoverageRow: View {
    var body: some View {
        Label(ChannelPresentation.coverageHint, systemImage: "clock.arrow.circlepath")
            .font(.footnote).foregroundStyle(Palette.ink2)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 4))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ChannelPresentation.coverageHint)
            .accessibilityIdentifier("monitor.channels.coverage")
    }
}

/// A row pushes its group onto this tab's stack as a value (U07, X39); VoiceOver reads the title and platform, then status and note.
private struct ChannelLink: View {
    let row: ChannelRowDisplay

    var body: some View {
        NavigationLink(value: AppRoute.group(id: row.groupID)) { ChannelRowContent(row: row) }
            .accessibilityLabel(row.spokenLabel)
            .accessibilityValue(row.spokenValue)
            .accessibilityHint("打开分组详情")
            .accessibilityIdentifier("monitor.channels.row.\(row.groupID)")
            .railRow(tone: row.tone, position: row.railPosition)
    }
}

private struct ChannelRowContent: View {
    let row: ChannelRowDisplay

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ChannelGlyph(status: row.status)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title.frame(maxWidth: .infinity, alignment: .leading)
                    trailing
                }
                ChannelStrip(cells: row.strip)
                Text(row.note).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(2)
            }
        }
        .railRowContent()
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
            if !row.platformName.isEmpty { Text(row.platformName).font(.footnote).foregroundStyle(Palette.ink3) }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch row.trailing {
        case .reliability(let text): Text(text).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink1).lineLimit(1)
        case .badge(let text, let tone): ToneBadge(text: text, tone: tone)
        }
    }
}

/// Design BaseGlyph for a channel: an 8pt dot when available, a 17pt symbol otherwise, in the status's tone.
private struct ChannelGlyph: View {
    let status: ChannelStatus
    @ScaledMetric(relativeTo: .body) private var symbolSize = 17.0
    @ScaledMetric(relativeTo: .body) private var dotSize = 8.0
    @ScaledMetric(relativeTo: .body) private var width = 22.0

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: status == .available ? dotSize : symbolSize, weight: .semibold))
            .foregroundStyle(status.tone.base)
            .frame(width: width, height: width)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch status {
        case .available: "circle.fill"
        case .degraded: "hourglass"
        case .unavailable: "exclamationmark.octagon"
        case .unknown: "minus"
        }
    }
}

/// The last 18 five-minute buckets (design strip18): filled in the bucket's tone, the track where nothing was measured. Not a
/// control, and VoiceOver skips it (the row's note says the same).
private struct ChannelStrip: View {
    let cells: [Tone?]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, tone in
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color(tone)).frame(height: 12)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func color(_ tone: Tone?) -> Color {
        switch tone {
        case .ok?: Palette.ok.opacity(0.55)
        case let other?: other.base
        case nil: Palette.sunken
        }
    }
}

/// Three rows while the first read is on its way; VoiceOver hears one “正在加载”.
private struct ChannelSkeletonRows: View {
    var body: some View {
        ForEach(0..<3, id: \.self) { index in
            VStack(alignment: .leading, spacing: 5) {
                Text("渠道名称 平台").font(.subheadline.weight(.semibold))
                ChannelStrip(cells: Array(repeating: nil, count: ChannelPresentation.stripLength))
                Text("可用率 —").font(.footnote)
            }
            .padding(.vertical, 6)
            .redacted(reason: .placeholder)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HomeInlineFigure.loadingValue)
            .accessibilityHidden(index > 0)
            .accessibilityIdentifier(index == 0 ? "monitor.channels.loading" : "")
        }
    }
}
