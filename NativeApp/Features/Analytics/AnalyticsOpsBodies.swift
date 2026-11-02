import SwiftUI
import Sub2Core

// 40 §2.3 the 运行 bodies (S4-18: RPM / TPM in the topic, 平均账号切换, 请求时长分布, 错误趋势; S4-18b adds 错误分布 and Token 请求统计), in
// 更多图表's list (`.card`) and at full size (`.full`, which 40 §3.1 opens nowhere yet). They read the page range through `loadOps`:
// nothing goes out while ops monitoring is off, and a 404 OPS_DISABLED turns the whole topic into its notice (S4D2b-06). Each card
// says under its header when it shows the whole site and, for those reading the error logs, that they keep 30 days (U35).

// MARK: - 读取

extension AnalyticsCardKey {
    /// PerformanceTrend over the page range; only 更多图表 shows it, so it stays out of “N 分钟前更新” (S4D2b-14).
    static let opsSwitch = AnalyticsCardKey("ops.switch", showsInUpdateLine: false)
    /// OpsLatencyHistogram.
    static let opsLatency = AnalyticsCardKey("ops.latency")
    /// OpsErrorTrend.
    static let opsErrorTrend = AnalyticsCardKey("ops.errTrend")
    /// OpsOverview, read once for 请求时长分布 and 错误趋势 (40 §2.2).
    static let opsOverview = AnalyticsCardKey("ops.overview")
}

/// The ops charts' reads over the page range; the bodies and S4-18b's tiles share them.
@MainActor enum OpsChartLoads {
    /// Nothing over PerformanceTrend.maximumSpan (S4D1-10): the card says so instead.
    static func accountSwitch(_ session: AnalyticsSession, model: AppModel, refresh: Bool = false) async {
        guard OpsSwitchSummary.supports(start: session.range.start, end: session.range.end) else { return }
        await session.loadOps(.opsSwitch, refresh: refresh, model: model, fixture: { try AnalyticsFixtures.opsThroughput($0.opsRangeQuery) }) {
            client, session in
            try await client.dashboardPerformanceTrend(session.opsRangeQuery, supportsModelFilter: session.supportsOpsModelFilter)
        }
    }
    static func latency(_ session: AnalyticsSession, model: AppModel, refresh: Bool = false) async {
        await session.loadOps(.opsLatency, refresh: refresh, model: model, fixture: { try AnalyticsFixtures.opsLatencyHistogram($0.opsRangeQuery) }) {
            client, session in
            try await client.opsLatencyHistogram(session.opsRangeQuery, supportsModelFilter: session.supportsOpsModelFilter)
        }
    }
    static func errorTrend(_ session: AnalyticsSession, model: AppModel, refresh: Bool = false) async {
        await session.loadOps(.opsErrorTrend, refresh: refresh, model: model, fixture: { try AnalyticsFixtures.opsErrorTrend($0.opsRangeQuery) }) {
            client, session in
            try await client.opsErrorTrend(session.opsRangeQuery, supportsModelFilter: session.supportsOpsModelFilter)
        }
    }
    /// One read for both charts: the session waits for a read already out.
    static func overview(_ session: AnalyticsSession, model: AppModel, refresh: Bool = false) async {
        await session.loadOps(.opsOverview, refresh: refresh, model: model, fixture: { try AnalyticsFixtures.opsOverview($0.opsRangeQuery) }) {
            client, session in
            try await client.opsOverview(session.opsRangeQuery, supportsModelFilter: session.supportsOpsModelFilter)
        }
    }
}

// MARK: - 卡头提示

/// 40 §2.1 / §2.5 the lines under an ops card's header: the whole site when the model filter cannot reach the ops charts, then the
/// 30-day retention of the error logs. Identifiers analytics.ops.<chart>.notes.siteWide / .retention.
struct AnalyticsOpsHeaderNotes: View {
    let chart: AnalyticsChartKey
    let readsErrorLogs: Bool
    let session: AnalyticsSession

    var body: some View {
        let notes = OpsChartCopy.headerNotes(siteWide: session.opsIsSiteWide, readsErrorLogs: readsErrorLogs, range: session.range)
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(notes, id: \.self) { note in
                    let isSiteWide = note == OpsChartCopy.siteWideNote
                    Label(note, systemImage: isSiteWide ? "line.3.horizontal.decrease" : "clock")
                        .font(.caption).foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("analytics.ops.\(chart.rawValue).notes.\(isSiteWide ? "siteWide" : "retention")")
                }
            }
        }
    }
}

// MARK: - RPM / TPM 趋势

/// 40 §2.3 RPM / TPM 趋势 in 更多图表: PerfTrendBody with its own window whatever the page range, under the whole-site note.
struct OpsPerfBody: View {
    let size: BodySize
    @Environment(\.analyticsSession) private var session

    init(size: BodySize) { self.size = size }

    var body: some View {
        if let session {
            VStack(alignment: .leading, spacing: 8) {
                AnalyticsOpsHeaderNotes(chart: .perf, readsErrorLogs: false, session: session)
                PerfTrendBody(filter: session.filter, size: size == .full ? .full : .card)
            }
        }
    }
}

// MARK: - 平均账号切换

/// 40 §2.3 平均账号切换: 切换次数 / 平均 · 次/请求 / 最高 · 次/请求, the line of switches per request and the footnote by bucket; a range
/// over 31 days and an hour reads nothing and says so (S4D1-10). Identifiers analytics.ops.switch.*.
struct OpsSwitchBody: View {
    let size: BodySize
    @Environment(\.analyticsSession) private var session

    init(size: BodySize) { self.size = size }

    var body: some View {
        if let session { OpsSwitchContent(session: session, size: size) }
    }
}

private struct OpsSwitchContent: View {
    let session: AnalyticsSession
    let size: BodySize
    @Environment(AppModel.self) private var model

    private var chartHeight: CGFloat { size == .full ? 150 : 96 }

    var body: some View {
        let range = session.range
        VStack(alignment: .leading, spacing: 10) {
            AnalyticsOpsHeaderNotes(chart: .accountSwitch, readsErrorLogs: true, session: session)
            if OpsSwitchSummary.supports(start: range.start, end: range.end) {
                AnalyticsCardBody(session.state(.opsSwitch, as: PerformanceTrend.self), id: "analytics.ops.switch", minHeight: chartHeight + 90,
                                  timeZone: session.timeZone.timeZone, retry: retry) { trend in
                    loaded(OpsSwitchSummary(trend), range: range)
                }
            } else {
                Text(OpsSwitchSummary.spanLimitText).font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .accessibilityIdentifier("analytics.ops.switch.spanLimit")
            }
        }
        .analyticsCardLoading("body.\(AnalyticsChartKey.accountSwitch.rawValue)", session: session) { [session, model] refresh in
            await OpsChartLoads.accountSwitch(session, model: model, refresh: refresh)
        }
    }

    private func retry() {
        let session = session, model = model
        Task { await OpsChartLoads.accountSwitch(session, model: model, refresh: true) }
    }

    @ViewBuilder private func loaded(_ summary: OpsSwitchSummary, range: AnalyticsRange) -> some View {
        AnalyticsFigureRow(summary.figures, id: "analytics.ops.switch")
        AnalyticsRatioLineChart(summary: summary, range: range, id: "analytics.ops.switch.chart", height: chartHeight)
        OpsFootnote(text: summary.footnote, id: "analytics.ops.switch.footnote")
    }
}

// MARK: - 请求时长分布

/// 40 §2.3 请求时长分布: six columns of successful requests with their shares, “成功请求 N 次的总耗时分布”, and 总耗时 / 首字 at P50–P99 (full
/// size adds 平均 and 最长) from the overview 错误趋势 shares; the overview's own failure has its own line. Identifiers analytics.ops.latency.*.
struct OpsLatencyBody: View {
    let size: BodySize
    @Environment(\.analyticsSession) private var session

    init(size: BodySize) { self.size = size }

    var body: some View {
        if let session { OpsLatencyContent(session: session, size: size) }
    }

    static func load(_ session: AnalyticsSession, model: AppModel, refresh: Bool) async {
        async let histogram: Void = OpsChartLoads.latency(session, model: model, refresh: refresh)
        async let overview: Void = OpsChartLoads.overview(session, model: model, refresh: refresh)
        _ = await (histogram, overview)
    }
}

private struct OpsLatencyContent: View {
    let session: AnalyticsSession
    let size: BodySize
    @Environment(AppModel.self) private var model

    private var barsHeight: CGFloat { size == .full ? 110 : 72 }

    var body: some View {
        let overview = session.state(.opsOverview, as: OpsOverview.self)
        VStack(alignment: .leading, spacing: 10) {
            AnalyticsOpsHeaderNotes(chart: .latency, readsErrorLogs: false, session: session)
            AnalyticsCardBody(session.state(.opsLatency, as: OpsLatencyHistogram.self), id: "analytics.ops.latency", minHeight: barsHeight + 130,
                              timeZone: zone, retry: retry) { histogram in
                loaded(OpsLatencySummary(histogram: histogram, overview: overview?.value), overview: overview)
            }
        }
        .analyticsCardLoading("body.\(AnalyticsChartKey.latency.rawValue)", session: session) { [session, model] refresh in
            await OpsLatencyBody.load(session, model: model, refresh: refresh)
        }
    }

    private var zone: TimeZone { session.timeZone.timeZone }
    private func retry() {
        let session = session, model = model
        Task { await OpsLatencyBody.load(session, model: model, refresh: true) }
    }
    private func retryOverview() {
        let session = session, model = model
        Task { await OpsChartLoads.overview(session, model: model, refresh: true) }
    }

    @ViewBuilder private func loaded(_ summary: OpsLatencySummary, overview: LoadState<OpsOverview>?) -> some View {
        if summary.isEmpty {
            Text(OpsLatencySummary.emptyText).font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: barsHeight)
                .accessibilityIdentifier("analytics.ops.latency.empty")
        } else {
            OpsLatencyColumns(columns: summary.columns, height: barsHeight)
            if let footnote = summary.footnote { OpsFootnote(text: footnote, id: "analytics.ops.latency.footnote") }
        }
        OpsPercentileTable(summary: summary, full: size == .full)
        AnalyticsCardStatusRow(overview, id: "analytics.ops.latency.overview", timeZone: zone, retry: retryOverview)
    }
}

/// The six columns side by side: the share over the bar, the name under it; each read as “<100ms，10%，1,820 次”. Identifiers
/// analytics.ops.latency.column.<0…5>.
private struct OpsLatencyColumns: View {
    let columns: [OpsLatencySummary.Column]
    let height: CGFloat

    /// A column with requests stays visible however small.
    private static let minimumBar: CGFloat = 2

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                VStack(spacing: 4) {
                    Text(column.shareText).font(.caption2.weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink2)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.chartBar)
                        .frame(height: column.count > 0 ? max(Self.minimumBar, height * column.height) : 0)
                        .frame(height: height, alignment: .bottom)
                    Text(column.label).font(.caption2).monospacedDigit().foregroundStyle(Palette.ink3).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(column.spokenLabel)
                .accessibilityIdentifier("analytics.ops.latency.column.\(index)")
            }
        }
    }
}

/// 总耗时 and 首字 under P50 … P99 (平均, 最长 at full size), “—” without a value. Each row is one element, its value read as “P50 2.4s，
/// P90 5.1s，…”. Identifiers analytics.ops.latency.row.duration / .ttft.
private struct OpsPercentileTable: View {
    let summary: OpsLatencySummary
    let full: Bool

    private static let titleWidth: CGFloat = 52

    var body: some View {
        let headers = OpsLatencySummary.headers(full: full)
        VStack(spacing: 6) {
            cells(title: "", headers)
                .font(.caption).foregroundStyle(Palette.ink3)
                .accessibilityHidden(true)
            ForEach(summary.rows(full: full)) { row in
                cells(title: row.title, row.values)
                    .font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink1)
                    .frame(minHeight: 28)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.title)
                    .accessibilityValue(row.spokenValue(headers: headers))
                    .accessibilityIdentifier("analytics.ops.latency.row.\(row.key)")
            }
        }
        .padding(.top, 4)
    }

    private func cells(title: String, _ values: [String]) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(Palette.ink2).frame(width: Self.titleWidth, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

// MARK: - 错误趋势

/// 40 §2.3 错误趋势: 错误 / 错误率 · SLA / SLA 口径, the bars of SLA errors (red) under business limits (grey) with no selection, the legend,
/// the upstream failures retries recovered included (U34) and the footnote by bucket. 错误率 comes from the overview 请求时长分布 shares;
/// its failure has its own line. Identifiers analytics.ops.errTrend.*.
struct OpsErrorTrendBody: View {
    let size: BodySize
    @Environment(\.analyticsSession) private var session

    init(size: BodySize) { self.size = size }

    var body: some View {
        if let session { OpsErrorTrendContent(session: session, size: size) }
    }

    static func load(_ session: AnalyticsSession, model: AppModel, refresh: Bool) async {
        async let trend: Void = OpsChartLoads.errorTrend(session, model: model, refresh: refresh)
        async let overview: Void = OpsChartLoads.overview(session, model: model, refresh: refresh)
        _ = await (trend, overview)
    }
}

private struct OpsErrorTrendContent: View {
    let session: AnalyticsSession
    let size: BodySize
    @Environment(AppModel.self) private var model

    private var chartHeight: CGFloat { size == .full ? 150 : 100 }

    var body: some View {
        let overview = session.state(.opsOverview, as: OpsOverview.self), range = session.range
        VStack(alignment: .leading, spacing: 10) {
            AnalyticsOpsHeaderNotes(chart: .errTrend, readsErrorLogs: true, session: session)
            AnalyticsCardBody(session.state(.opsErrorTrend, as: OpsErrorTrend.self), id: "analytics.ops.errTrend", minHeight: chartHeight + 140,
                              timeZone: zone, retry: retry) { trend in
                loaded(OpsErrorTrendSummary(trend: trend, overview: overview?.value, range: range), overview: overview)
            }
        }
        .analyticsCardLoading("body.\(AnalyticsChartKey.errTrend.rawValue)", session: session) { [session, model] refresh in
            await OpsErrorTrendBody.load(session, model: model, refresh: refresh)
        }
    }

    private var zone: TimeZone { session.timeZone.timeZone }
    private func retry() {
        let session = session, model = model
        Task { await OpsErrorTrendBody.load(session, model: model, refresh: true) }
    }
    private func retryOverview() {
        let session = session, model = model
        Task { await OpsChartLoads.overview(session, model: model, refresh: true) }
    }

    @ViewBuilder private func loaded(_ summary: OpsErrorTrendSummary, overview: LoadState<OpsOverview>?) -> some View {
        AnalyticsFigureRow(summary.figures, id: "analytics.ops.errTrend")
        AnalyticsCardStatusRow(overview, id: "analytics.ops.errTrend.overview", timeZone: zone, retry: retryOverview)
        AnalyticsStackedBars(values: summary.columns, order: OpsErrorLayer.allCases, ticks: summary.ticks,
                             columnNames: summary.bars.map(\.spokenName), selection: nil, id: "analytics.ops.errTrend.chart",
                             chartTitle: AnalyticsChartKey.errTrend.title, height: chartHeight,
                             emptyText: summary.isEmpty ? OpsErrorTrendSummary.emptyText : nil, style: OpsErrorStyle.fill,
                             layerName: \.title, format: { DisplayFormat.grouped(Int($0.rounded())) })
        OpsErrorLegend(summary: summary)
        Text(summary.upstreamLine).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("analytics.ops.errTrend.upstream")
        OpsFootnote(text: summary.footnote, id: "analytics.ops.errTrend.footnote")
    }
}

/// SLA errors in the critical red, business limits (the user's own balance, quota or rate) in the neutral grey.
private enum OpsErrorStyle {
    static func fill(_ layer: OpsErrorLayer) -> AnyShapeStyle {
        layer == .sla ? AnyShapeStyle(Tone.critical.base) : AnyShapeStyle(Palette.neutral)
    }
}

/// “■ SLA 错误 317 · ■ 业务限制 80”, read as one line. Identifier analytics.ops.errTrend.legend.
private struct OpsErrorLegend: View {
    let summary: OpsErrorTrendSummary

    var body: some View {
        HStack(spacing: 12) {
            item(.sla, summary.legendSLA)
            item(.businessLimited, summary.legendBusinessLimited)
            Spacer(minLength: 0)
        }
        .font(.caption).monospacedDigit().foregroundStyle(Palette.ink2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.legendSLA + "，" + summary.legendBusinessLimited)
        .accessibilityIdentifier("analytics.ops.errTrend.legend")
    }

    private func item(_ layer: OpsErrorLayer, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(OpsErrorStyle.fill(layer)).frame(width: 10, height: 10)
            Text(text)
        }
    }
}

/// A chart's note under it.
private struct OpsFootnote: View {
    let text: String
    let id: String

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Palette.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(id)
    }
}
