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

    /// 用户用量 and 请求类型 come with S4-17b, 错误趋势 and 请求时长分布 with S4-18b; each replaces its own case.
    @ViewBuilder private func tile(_ chart: AnalyticsChartKey, session: AnalyticsSession) -> some View {
        switch chart {
        case .tokens: AnalyticsTokenTile(session: session)
        case .endpoints: AnalyticsEndpointTile(session: session)
        default: AnalyticsMoreTile(chart: chart, model: .placeholder)
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

    /// A tile a later item fills: “—” / “稍后提供”, no sketch.
    static let placeholder = AnalyticsTileModel(text: AnalyticsTileText(value: DisplayFormat.missing, label: "稍后提供"), sketch: nil)
    static let failed = AnalyticsTileModel(text: AnalyticsTileText(value: DisplayFormat.missing, label: "加载失败"), sketch: nil)

    /// The tile over a session read: its value made into a tile, a failure without one, else nil (loading).
    @MainActor static func of<Value: Sendable>(_ load: LoadState<Value>?, _ make: (Value) -> AnalyticsTileModel) -> AnalyticsTileModel? {
        if let value = load?.value { return make(value) }
        return load?.error != nil ? failed : nil
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

// MARK: - 缩略图

/// A tile's sketch (S4-17b and S4-18b add their kinds): Token 使用趋势's columns, a share list's bars.
enum AnalyticsSketch: Equatable, Sendable {
    case tokenStacks([TokenMix])
    /// The first five, longest first.
    case hbars([Double])
}

/// A sketch 34pt high, not read: the columns in TokenKindStyle's fills with a 1pt seam, or up to five bars from the left.
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
        for (index, value) in shown.enumerated() {
            let width = max(3, size.width * value / top)
            context.fill(Path(roundedRect: CGRect(x: 0, y: CGFloat(index) * pitch, width: width, height: thickness), cornerRadius: 1),
                         with: .color(Palette.chartBar))
        }
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
