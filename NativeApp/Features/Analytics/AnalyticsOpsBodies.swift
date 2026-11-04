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

// MARK: - 错误分布、Token 请求统计（S4-18b）

extension AnalyticsCardKey {
    /// OpsErrorDistribution; only 更多图表 shows it (S4D2b-14).
    static let opsErrorDistribution = AnalyticsCardKey("ops.errorDistribution", showsInUpdateLine: false)
    /// OpsTokenStats. Its request sends no model, yet a model filter change reads it again with the other cards.
    static let opsTokenStats = AnalyticsCardKey("ops.tokenStats", showsInUpdateLine: false)
}

extension OpsChartLoads {
    static func errorDistribution(_ session: AnalyticsSession, model: AppModel, refresh: Bool = false) async {
        await session.loadOps(.opsErrorDistribution, refresh: refresh, model: model,
                              fixture: { try AnalyticsFixtures.opsErrorDistribution($0.opsRangeQuery) }) { client, session in
            try await client.opsErrorDistribution(session.opsRangeQuery, supportsModelFilter: session.supportsOpsModelFilter)
        }
    }
    /// 40 §2.2: no model; the window and the retry over 30 days after a 400 are the client's.
    static func tokenStats(_ session: AnalyticsSession, model: AppModel, supportsCustomRange: Bool, refresh: Bool = false) async {
        await session.loadOps(.opsTokenStats, refresh: refresh, model: model, fixture: { session in
            try AnalyticsFixtures.opsTokenStats(session.opsRangeQuery, now: session.now, zone: session.timeZone, supportsCustomRange: supportsCustomRange)
        }) { client, session in
            try await client.opsTokenStats(session.opsRangeQuery, supportsCustomRange: supportsCustomRange)
        }
    }
}

/// 40 §2.3 错误分布: a row per status code (the server's 20 at most, all of them on a card too): the code's badge, the bar of its SLA
/// errors in the code's tone and of its business limits in grey against the first row, the count and the share; the legend under
/// them, and U35's retention hint under the header. Identifiers analytics.errDist.row.<code>, .legend, .empty.
struct OpsErrorDistributionBody: View {
    let size: BodySize
    @Environment(\.analyticsSession) private var session

    init(size: BodySize) { self.size = size }

    var body: some View {
        if let session { OpsErrorDistributionContent(session: session) }
    }
}

private struct OpsErrorDistributionContent: View {
    let session: AnalyticsSession
    @Environment(AppModel.self) private var model

    /// Six rows and the legend, until the reply.
    private static let loadingHeight: CGFloat = 270
    private static let emptyHeight: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AnalyticsOpsHeaderNotes(chart: .errDist, readsErrorLogs: true, session: session)
            AnalyticsCardBody(session.state(.opsErrorDistribution, as: OpsErrorDistribution.self), id: "analytics.errDist",
                              minHeight: Self.loadingHeight, timeZone: session.timeZone.timeZone, retry: retry) { distribution in
                loaded(OpsErrorDistributionSummary(distribution))
            }
        }
        .analyticsCardLoading("body.\(AnalyticsChartKey.errDist.rawValue)", session: session) { [session, model] refresh in
            await OpsChartLoads.errorDistribution(session, model: model, refresh: refresh)
        }
    }

    private func retry() {
        let session = session, model = model
        Task { await OpsChartLoads.errorDistribution(session, model: model, refresh: true) }
    }

    @ViewBuilder private func loaded(_ summary: OpsErrorDistributionSummary) -> some View {
        if summary.isEmpty {
            Text(OpsErrorDistributionSummary.emptyText).font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: Self.emptyHeight)
                .accessibilityIdentifier("analytics.errDist.empty")
        } else {
            VStack(spacing: 0) {
                ForEach(summary.rows) { row in OpsErrorDistributionRow(row: row) }
            }
            OpsErrorDistributionLegend()
        }
    }
}

/// “429 ▬▬▬▬ 160 40%”, read as one line.
private struct OpsErrorDistributionRow: View {
    let row: OpsErrorDistributionSummary.Row

    private static let badgeWidth: CGFloat = 44
    private static let countWidth: CGFloat = 48
    private static let shareWidth: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            ToneBadge(text: row.codeText, tone: row.tone).frame(minWidth: Self.badgeWidth, alignment: .leading)
            OpsErrorDistributionBar(length: row.bar, tone: row.tone)
            Text(row.countText).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
                .lineLimit(1).frame(minWidth: Self.countWidth, alignment: .trailing)
            Text(row.shareText).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                .lineLimit(1).frame(minWidth: Self.shareWidth, alignment: .trailing)
        }
        .frame(minHeight: 44)
        .overlay(alignment: .top) { Palette.hairline.frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenLabel)
        .accessibilityIdentifier("analytics.errDist.row.\(row.statusCode)")
    }
}

/// The SLA part in the code's tone, the business limits in grey, on the track.
private struct OpsErrorDistributionBar: View {
    let length: OpsErrorDistribution.BarLength
    let tone: Tone

    private static let height: CGFloat = 8
    private static let gap: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: Self.gap) {
                if length.sla > 0 { Rectangle().fill(tone.base).frame(width: proxy.size.width * length.sla) }
                if length.businessLimited > 0 { Rectangle().fill(Tone.neutral.base).frame(width: proxy.size.width * length.businessLimited) }
            }
        }
        .frame(height: Self.height)
        .background(Palette.sunken)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .accessibilityHidden(true)
    }
}

/// “■ 429 限流 ■ 其他错误（含 504、529）■ 业务限制（不计 SLA）”, wrapping, read as one line.
private struct OpsErrorDistributionLegend: View {
    var body: some View {
        ListFieldFlow(spacing: 12) {
            ForEach(OpsErrorDistributionSummary.legend) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(item.tone.base).frame(width: 10, height: 10)
                    Text(item.title)
                }
            }
        }
        .font(.caption).foregroundStyle(Palette.ink2)
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(OpsErrorDistributionSummary.legendSpoken)
        .accessibilityIdentifier("analytics.errDist.legend")
    }
}

/// 40 §2.3 Token 请求统计: 按请求 · 按速度 · 按首 Token (sorted here, this chart only), the table of the first 5 models (9 at full size)
/// with the filtered model's row lit or added at the end, and the window's footnote. Identifiers analytics.tokenStats.order,
/// .row.<n> (the filtered one valued 已筛选), .footnote, .empty.
struct OpsTokenStatsBody: View {
    let size: BodySize
    @Environment(\.analyticsSession) private var session

    init(size: BodySize) { self.size = size }

    var body: some View {
        if let session { OpsTokenStatsContent(session: session, size: size) }
    }

    /// The card header's window: the one read, else the one the client will send (the range's name for a custom window).
    static func windowTitle(_ session: AnalyticsSession, supportsCustomRange: Bool) -> String {
        let range = session.range
        let window = session.state(.opsTokenStats, as: OpsTokenStats.self)?.value?.window
            ?? OpsTokenStatsWindow.select(start: range.start, end: range.end, now: range.now, zone: session.timeZone,
                                          supportsCustomRange: supportsCustomRange)
        return AnalyticsModelPresentation.speedMeta(window, rangeName: range.name)
    }
}

private struct OpsTokenStatsContent: View {
    let session: AnalyticsSession
    let size: BodySize
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var context
    @State private var order: OpsTokenStatsOrder = .requests

    /// Five rows, until the reply.
    private static let loadingHeight: CGFloat = 240
    private static let emptyHeight: CGFloat = 88

    var body: some View {
        let supports = supportsCustomRange
        VStack(alignment: .leading, spacing: 10) {
            AnalyticsOpsHeaderNotes(chart: .tokenSpeed, readsErrorLogs: false, session: session)
            Picker("排序", selection: $order) {
                ForEach(OpsTokenStatsOrder.allCases) { item in Text(item.label).tag(item) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("analytics.tokenStats.order")
            AnalyticsCardBody(session.state(.opsTokenStats, as: OpsTokenStats.self), id: "analytics.tokenStats", minHeight: Self.loadingHeight,
                              timeZone: session.timeZone.timeZone, retry: retry) { stats in
                loaded(OpsTokenStatsTable(stats, order: order, full: size == .full, pinnedModel: pinnedModel, groupName: groupName))
            }
        }
        .analyticsCardLoading("body.\(AnalyticsChartKey.tokenSpeed.rawValue)", session: session, trigger: supports) { [session, model] refresh in
            await OpsChartLoads.tokenStats(session, model: model, supportsCustomRange: supports, refresh: refresh)
        }
    }

    private var supportsCustomRange: Bool { context?.has(.opsTokenStatsCustomRange) ?? false }
    private var pinnedModel: String? {
        guard case .model(let name)? = session.filter else { return nil }
        return name
    }
    private var groupName: String? { session.filter?.kind == .group ? session.filterName : nil }

    private func retry() {
        let session = session, model = model, supports = supportsCustomRange
        Task { await OpsChartLoads.tokenStats(session, model: model, supportsCustomRange: supports, refresh: true) }
    }

    @ViewBuilder private func loaded(_ table: OpsTokenStatsTable) -> some View {
        if let empty = table.emptyText {
            Text(empty).font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: Self.emptyHeight)
                .accessibilityIdentifier("analytics.tokenStats.empty")
        } else {
            VStack(spacing: 0) {
                OpsTokenStatsColumns(model: Text(OpsTokenStatsTable.headers[0]), values: OpsTokenStatsTable.headers.dropFirst().map { Text($0) })
                    .font(.caption.weight(.medium)).foregroundStyle(Palette.ink3)
                    .frame(minHeight: 30)
                    .accessibilityHidden(true)
                ForEach(Array(table.rows.enumerated()), id: \.element.id) { index, row in OpsTokenStatsRow(row: row, index: index) }
            }
        }
        OpsFootnote(text: table.footnote, id: "analytics.tokenStats.footnote")
    }
}

/// A model (monospaced, cut in the middle), then 输出/秒, 首 Token, 平均时长; the filtered model's row on the accent wash.
private struct OpsTokenStatsRow: View {
    let row: OpsTokenStatsTable.Row
    let index: Int

    var body: some View {
        VStack(spacing: 0) {
            Palette.hairline.frame(height: 1)
            OpsTokenStatsColumns(model: Text(row.model).font(.footnote.monospaced()), values: row.values.map { Text($0) })
                .font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink1)
                .frame(minHeight: 40)
                .background(row.isPinned ? Palette.accentWash : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenLabel)
        .accessibilityValue(row.isPinned ? OpsTokenStatsTable.pinnedValue : "")
        .accessibilityIdentifier("analytics.tokenStats.row.\(index)")
    }
}

private struct OpsTokenStatsColumns: View {
    let model: Text
    let values: [Text]

    private static let valueWidth: CGFloat = 58

    var body: some View {
        HStack(spacing: 6) {
            model.lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(values.indices, id: \.self) { index in
                values[index].lineLimit(1).minimumScaleFactor(0.7).frame(width: Self.valueWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, 6)
    }
}
