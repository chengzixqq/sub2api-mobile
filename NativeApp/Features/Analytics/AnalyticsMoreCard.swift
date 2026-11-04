import SwiftUI
import Sub2Core

/// 40 §1.4 更多图表卡's slot in the card flow (X44): “更多图表” with “12 张” (6 with ops off), four tiles that open 更多图表 on their
/// chart, and “全部图表 · 计费 2 · 用量 4 · 运行 6 ›” to its top. The session comes from `\.analyticsSession`; each tile reads through
/// `.analyticsCardLoading`. Identifiers analytics.moreCard.*.
struct AnalyticsMoreCard: View {
    @Environment(\.analyticsSession) private var session
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    private static let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        if let session {
            let opsEnabled = !model.analyticsOpsDisabled
            AnalyticsCard(title: "更多图表", id: "analytics.moreCard") {
                Text(AnalyticsChartCatalog.cardMeta(opsEnabled: opsEnabled)).font(.caption).monospacedDigit().foregroundStyle(Palette.ink3)
                    .accessibilityIdentifier("analytics.moreCard.count")
            } content: {
                LazyVGrid(columns: Self.columns, spacing: 10) {
                    ForEach(AnalyticsChartCatalog.tileCharts(opsEnabled: opsEnabled), id: \.self) { chart in tile(chart, session: session) }
                }
                AnalyticsCardFoot(title: "全部图表", meta: AnalyticsChartCatalog.footerMeta(opsEnabled: opsEnabled),
                                  id: "analytics.moreCard.foot") { router.push(.analyticsMore()) }
            }
        }
    }

    /// The six charts AnalyticsChartCatalog.tileCharts gives; the others have no tile.
    @ViewBuilder private func tile(_ chart: AnalyticsChartKey, session: AnalyticsSession) -> some View {
        switch chart {
        case .tokens: AnalyticsTokenTile(session: session)
        case .userTrend: AnalyticsUserTrendTile(session: session)
        case .endpoints: AnalyticsEndpointTile(session: session)
        case .reqType: AnalyticsRequestTypeTile(session: session)
        case .errTrend: AnalyticsErrorTrendTile(session: session)
        case .latency: AnalyticsLatencyTile(session: session)
        default: EmptyView()
        }
    }
}

// MARK: - 磁贴

/// What a tile shows; nil while its read has no answer yet.
struct AnalyticsTileModel: Equatable {
    let text: AnalyticsTileText
    let sketch: AnalyticsSketch?
    /// “全站” before the label: an ops chart the model filter cannot reach (S4-18b).
    var isSiteWide = false

    static let failed = AnalyticsTileModel(text: AnalyticsTileText(value: DisplayFormat.missing, label: "加载失败"), sketch: nil)
    /// A 404 OPS_DISABLED while ops monitoring still counts as on (LiveOpsStore's 30 seconds after turning it on, 40 §1.6).
    static let opsDisabled = AnalyticsTileModel(text: AnalyticsTileText(value: DisplayFormat.missing, label: OpsDisabledPresentation.title),
                                                sketch: nil)

    /// The tile over a session read: its value made into a tile, a failure without one, else nil (loading).
    @MainActor static func of<Value: Sendable>(_ load: LoadState<Value>?, _ make: (Value) -> AnalyticsTileModel) -> AnalyticsTileModel? {
        if let value = load?.value { return make(value) }
        return load?.error != nil ? failed : nil
    }
    /// An ops tile over two reads (S4-18b): 运维监控未开启 after a 404 OPS_DISABLED, nil until both have answered, a failure when
    /// either has nothing to show.
    @MainActor static func ops<First: Sendable, Second: Sendable>(_ first: LoadState<First>?, _ second: LoadState<Second>?,
                                                                _ make: (First, Second) -> AnalyticsTileModel) -> AnalyticsTileModel? {
        let errors = [first?.lastError, second?.lastError].compactMap { $0 }
        if errors.contains(where: { AccountUpstreamErrors.isOpsDisabled($0) }) { return opsDisabled }
        if let first = first?.value, let second = second?.value { return make(first, second) }
        let failedWithout = (first?.value == nil && first?.error != nil) || (second?.value == nil && second?.error != nil)
        return failedWithout ? failed : nil
    }
}

/// A tile: the chart's name, the big value with its unit, the line under it and the sketch; a tap opens 更多图表 on the chart. Read as
/// one button, “Token 使用趋势，96.4M Tokens，缓存读占 54%”. Identifier analytics.moreCard.tile.<chart>.
struct AnalyticsMoreTile: View {
    let chart: AnalyticsChartKey
    let model: AnalyticsTileModel?

    private static let valueHeight: CGFloat = 26

    var body: some View {
        NavigationLink(value: AppRoute.analyticsMore(chart: chart)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(chart.title).font(.caption).foregroundStyle(Palette.ink2).lineLimit(1)
                value.frame(height: Self.valueHeight, alignment: .leading)
                label
                if let sketch = model?.sketch {
                    AnalyticsSketchView(sketch)
                } else {
                    Color.clear.frame(height: AnalyticsSketchView.height)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("打开更多图表")
        .accessibilityIdentifier("analytics.moreCard.tile.\(chart.rawValue)")
    }

    @ViewBuilder private var value: some View {
        if let text = model?.text {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(text.value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
                if let unit = text.unit { Text(unit).font(.caption).foregroundStyle(Palette.ink2) }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
        } else {
            ProgressView()
        }
    }
    private var label: some View {
        HStack(spacing: 4) {
            if model?.isSiteWide == true {
                Text("全站").font(.caption2.weight(.semibold)).foregroundStyle(Palette.ink2)
                    .padding(.horizontal, 4).background(Palette.neutralWash, in: RoundedRectangle(cornerRadius: 3))
            }
            Text(model?.text.label ?? " ").font(.caption2).foregroundStyle(Palette.ink3).lineLimit(1).truncationMode(.middle)
        }
    }
    private var spokenLabel: String {
        guard let text = model?.text else { return chart.title + "，" + HomeInlineFigure.loadingValue }
        let value = DisplayFormat.spoken(text.value) + (text.unit.map { " " + $0 } ?? "")
        return [chart.title, value, (model?.isSiteWide == true ? "全站 " : "") + text.label].joined(separator: "，")
    }
}

/// Token 使用趋势's tile over 计费趋势's trend: “96.4M” Tokens / “缓存读占 54%” and the columns in small.
private struct AnalyticsTokenTile: View {
    let session: AnalyticsSession

    var body: some View {
        let range = session.range
        AnalyticsMoreTile(chart: .tokens, model: .of(session.state(.billingTrend, as: DashboardTrendReply.self)) { reply in
            let mixes = AnalyticsSeries.tokenMixes(range: range, points: reply.points)
            return AnalyticsTileModel(text: AnalyticsSeries.tokenTile(AnalyticsSeries.tokenTotal(mixes)), sketch: .tokenStacks(mixes))
        })
        .analyticsCardLoading("moreCard.tile.tokens", session: session) { [session] refresh in await session.loadBillingTrend(refresh: refresh) }
    }
}

/// 端点分布's tile over 计费趋势's totals: “60%” / “/v1/messages 占请求” and the first five inbound endpoints in small.
private struct AnalyticsEndpointTile: View {
    let session: AnalyticsSession

    var body: some View {
        AnalyticsMoreTile(chart: .endpoints, model: .of(session.state(.billingSummary, as: AnalyticsSummary.self)) { summary in
            let rows = AnalyticsSeries.endpointRows(summary, side: .inbound)
            return AnalyticsTileModel(text: AnalyticsSeries.endpointTile(summary), sketch: rows.isEmpty ? nil : .hbars(rows.map { Double($0.requests) }))
        })
        .analyticsCardLoading("moreCard.tile.endpoints", session: session) { [session] refresh in
            await session.loadBillingSummary(refresh: refresh)
        }
    }
}

/// 用户用量趋势's tile over its Tokens segment (the card's read): “12.4M” Tokens / “第 1 · Nova 工作室” and that user's line.
private struct AnalyticsUserTrendTile: View {
    let session: AnalyticsSession
    @Environment(\.sessionContext) private var context

    var body: some View {
        let supports = context?.has(.dashboardUsersTrendFilteredMetric) ?? false
        AnalyticsMoreTile(chart: .userTrend, model: .of(session.state(.userTrend(.tokens), as: UserUsageSeries.self)) { series in
            AnalyticsTileModel(text: series.tile, sketch: series.rows.first.map { AnalyticsSketch.line($0.normalized) })
        })
        .analyticsCardLoading("moreCard.tile.userTrend", session: session) { [session] refresh in
            await UsageChartLoads.userTrend(session, metric: .tokens, supportsFilteredMetric: supports, refresh: refresh)
        }
    }
}

/// 请求类型's tile, with ops off only (the card's read): “72%” / “流式占请求” and the five types' requests in small.
private struct AnalyticsRequestTypeTile: View {
    let session: AnalyticsSession
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var context

    var body: some View {
        let supports = context?.has(.dashboardRequestTypes) ?? false
        AnalyticsMoreTile(chart: .reqType, model: .of(session.state(.requestTypes, as: RequestTypeMix.self)) { mix in
            AnalyticsTileModel(text: mix.tile, sketch: mix.isEmpty ? nil : .hbars(mix.rows.map { Double($0.requests) }))
        })
        .analyticsCardLoading("moreCard.tile.reqType", session: session) { [session, model] refresh in
            // Still registered once ops is back on and the tile has gone: it reads nothing then (S4D2b-02 ②).
            guard model.analyticsOpsDisabled else { return }
            await UsageChartLoads.requestTypes(session, supportsRequestTypes: supports, refresh: refresh)
        }
    }
}

/// 错误趋势's tile over the overview and the trend, as its card reads them (S4-18b): “1.7%” / “错误率 · SLA” and the bars in red.
private struct AnalyticsErrorTrendTile: View {
    let session: AnalyticsSession
    @Environment(AppModel.self) private var model

    var body: some View {
        let range = session.range, siteWide = session.opsIsSiteWide
        let overview = session.state(.opsOverview, as: OpsOverview.self), trend = session.state(.opsErrorTrend, as: OpsErrorTrend.self)
        AnalyticsMoreTile(chart: .errTrend, model: .ops(overview, trend) { overview, trend in
            let summary = OpsErrorTrendSummary(trend: trend, overview: overview, range: range)
            return AnalyticsTileModel(text: AnalyticsTileText(value: summary.errorRateText, label: OpsErrorTrendSummary.tileCaption),
                                      sketch: .columns(summary.sketchValues, isError: true), isSiteWide: siteWide)
        })
        .analyticsCardLoading("moreCard.tile.errTrend", session: session) { [session, model] refresh in
            await OpsErrorTrendBody.load(session, model: model, refresh: refresh)
        }
    }
}

/// 请求时长分布's tile over the histogram and the overview, as its card reads them (S4-18b): “2.4s” / “P50 总耗时” and the six columns.
private struct AnalyticsLatencyTile: View {
    let session: AnalyticsSession
    @Environment(AppModel.self) private var model

    var body: some View {
        let siteWide = session.opsIsSiteWide
        let histogram = session.state(.opsLatency, as: OpsLatencyHistogram.self), overview = session.state(.opsOverview, as: OpsOverview.self)
        AnalyticsMoreTile(chart: .latency, model: .ops(histogram, overview) { histogram, overview in
            let summary = OpsLatencySummary(histogram: histogram, overview: overview)
            return AnalyticsTileModel(text: AnalyticsTileText(value: summary.tileValue, label: OpsLatencySummary.tileCaption),
                                      sketch: summary.isEmpty ? nil : .columns(summary.sketchValues, isError: false), isSiteWide: siteWide)
        })
        .analyticsCardLoading("moreCard.tile.latency", session: session) { [session, model] refresh in
            await OpsLatencyBody.load(session, model: model, refresh: refresh)
        }
    }
}

// MARK: - 缩略图

/// A tile's sketch: Token 使用趋势's columns, a share list's bars, a 0–1 line (用户用量's first user), or columns (错误趋势's in red).
enum AnalyticsSketch: Equatable, Sendable {
    case tokenStacks([TokenMix])
    /// The first five, in the order given; one at 0 has no bar.
    case hbars([Double])
    case line([Double])
    /// From 0 to a little above the tallest.
    case columns([Double], isError: Bool)
}

/// A sketch 34pt high, not read: the columns in TokenKindStyle's fills with a 1pt seam, up to five bars from the left, or a line.
struct AnalyticsSketchView: View {
    static let height: CGFloat = 34

    private let sketch: AnalyticsSketch

    init(_ sketch: AnalyticsSketch) { self.sketch = sketch }

    var body: some View {
        let sketch = sketch
        Canvas { context, size in
            switch sketch {
            case .tokenStacks(let mixes): SketchDrawing.stacks(mixes, in: &context, size: size)
            case .hbars(let values): SketchDrawing.bars(values, in: &context, size: size)
            case .line(let values): SketchDrawing.line(values, in: &context, size: size)
            case .columns(let values, let isError): SketchDrawing.columns(values, isError: isError, in: &context, size: size)
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}

private enum SketchDrawing {
    static let seam: CGFloat = 1
    static let stripePitch: CGFloat = 3
    static let stripeLine: CGFloat = 1.4
    static let barRows = 5
    static let lineWidth: CGFloat = 1.5
    /// The design's: 5% above the tallest column, the red softened toward the surface.
    static let columnHeadroom = 1.05
    static let errorOpacity = 0.7

    static func stacks(_ mixes: [TokenMix], in context: inout GraphicsContext, size: CGSize) {
        let columns = AnalyticsSeries.tokenColumns(mixes, only: nil)
        let top = columns.map { $0.values.reduce(0, +) }.max() ?? 0
        guard top > 0 else { return }
        let scale = size.height / top, slot = size.width / CGFloat(columns.count)
        let stacks = AnalyticsSeries.stack(columns, order: TokenKind.allCases, gap: seam / scale)
        for (index, segments) in stacks.enumerated() {
            for segment in segments {
                let rect = CGRect(x: CGFloat(index) * slot + slot * 0.15, y: size.height - segment.upper * scale,
                                  width: slot * 0.7, height: (segment.upper - segment.lower) * scale)
                fill(rect, kind: segment.layer, in: &context)
            }
        }
    }

    static func bars(_ values: [Double], in context: inout GraphicsContext, size: CGSize) {
        let shown = Array(values.prefix(barRows)), top = shown.max() ?? 0
        guard top > 0 else { return }
        let pitch = size.height / CGFloat(barRows), thickness = pitch * 0.6
        for (index, value) in shown.enumerated() where value > 0 {
            let width = max(3, size.width * value / top)
            context.fill(Path(roundedRect: CGRect(x: 0, y: CGFloat(index) * pitch, width: width, height: thickness), cornerRadius: 1),
                         with: .color(Palette.chartBar))
        }
    }

    static func columns(_ values: [Double], isError: Bool, in context: inout GraphicsContext, size: CGSize) {
        let top = (values.max() ?? 0) * columnHeadroom
        guard top > 0 else { return }
        let slot = size.width / CGFloat(values.count), color = isError ? Palette.critical.opacity(errorOpacity) : Palette.chartBar
        for (index, value) in values.enumerated() where value > 0 {
            let height = size.height * value / top
            context.fill(Path(CGRect(x: CGFloat(index) * slot + slot * 0.15, y: size.height - height, width: slot * 0.7, height: height)),
                         with: .color(color))
        }
    }

    static func line(_ values: [Double], in context: inout GraphicsContext, size: CGSize) {
        let path = AnalyticsSparklineShape(values: values).path(in: CGRect(origin: .zero, size: size))
        context.stroke(path, with: .color(Palette.chartMain), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    private static func fill(_ rect: CGRect, kind: TokenKind, in context: inout GraphicsContext) {
        let path = Path(rect)
        switch kind {
        case .input: context.fill(path, with: .color(Palette.chartMain))
        case .output: context.fill(path, with: .color(Palette.chartBar))
        case .cacheRead:
            context.drawLayer { layer in
                layer.clip(to: path)
                layer.fill(path, with: .color(Palette.surface))
                for y in stride(from: rect.minY, to: rect.maxY, by: stripePitch) {
                    layer.fill(Path(CGRect(x: rect.minX, y: y, width: rect.width, height: stripeLine)), with: .color(Palette.ink2))
                }
            }
        case .cacheWrite:
            context.fill(path, with: .color(Palette.surface))
            context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(Palette.ink2), lineWidth: 1)
        }
    }
}
