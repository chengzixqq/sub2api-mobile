import SwiftUI
import Sub2Core

// 40 §2.3 the 用量 bodies (S4-17: Token 使用趋势, 端点分布; S4-17b adds 用户用量趋势 and 请求类型), in 更多图表's list (`.card`) and on a
// chart page (`.full`). Both read what 计费趋势 reads, through the session (40 §2.2).

// MARK: - Token 使用趋势

/// 40 §2.3 Token 使用趋势: the four kinds as legend buttons with the range's totals or the selected bucket's (one tapped shows only
/// it, tapped again all of them), the stacked columns and the footnote; full size adds the table. It reads 计费趋势's trend.
/// Identifiers analytics.tokens.*.
struct TokenTrendBody: View {
    let size: BodySize
    @Environment(\.analyticsSession) private var session

    init(size: BodySize) { self.size = size }

    var body: some View {
        if let session { TokenTrendContent(session: session, size: size) }
    }

    static func load(_ session: AnalyticsSession, refresh: Bool) async { await session.loadBillingTrend(refresh: refresh) }
}

private struct TokenTrendContent: View {
    let session: AnalyticsSession
    let size: BodySize
    @Environment(\.self) private var environment
    @State private var selection = AnalyticsChartSelection()
    @State private var only: TokenKind?

    /// The legend, the chart and the footnote, until the trend answers.
    private var loadingHeight: CGFloat { size.chartHeight + 110 }

    var body: some View {
        let trend = session.state(.billingTrend, as: DashboardTrendReply.self)
        AnalyticsCardBody(trend, id: "analytics.tokens", minHeight: loadingHeight, timeZone: zone, retry: retry) { reply in
            loaded(AnalyticsSeries.tokenMixes(range: session.range, points: reply.points))
        }
        .analyticsCardLoading("body.tokens", session: session) { [session] refresh in await TokenTrendBody.load(session, refresh: refresh) }
        .onChange(of: session.scope) { _, _ in selection = AnalyticsChartSelection() }
    }

    private var zone: TimeZone { session.timeZone.timeZone }
    private func retry() {
        let session = session
        Task { await TokenTrendBody.load(session, refresh: true) }
    }

    private func loaded(_ mixes: [TokenMix]) -> some View {
        let range = session.range
        let selected = selection.selected.flatMap { mixes.indices.contains($0) ? mixes[$0] : nil }
        let stripes = AnalyticsStripes.paint(ink: Palette.ink2, background: Palette.surface, in: environment)
        return VStack(alignment: .leading, spacing: 10) {
            TokenLegend(values: selected ?? AnalyticsSeries.tokenTotal(mixes), only: only, stripes: stripes) { kind in
                only = only == kind ? nil : kind
                selection = AnalyticsChartSelection()
            }
            AnalyticsStackedBars(values: AnalyticsSeries.tokenColumns(mixes, only: only), order: AnalyticsSeries.tokenLayers(only: only),
                                 ticks: range.axisTicks, columnNames: range.buckets.map(\.spokenLabel), selection: $selection,
                                 id: "analytics.tokens.chart", chartTitle: AnalyticsChartKey.tokens.title, height: size.chartHeight,
                                 emptyText: AnalyticsSeries.hasTokens(mixes) ? nil : "这个范围内没有用量", outlined: TokenKindStyle.outlined,
                                 style: { TokenKindStyle.fill($0, stripes: stripes) }, layerName: \.title,
                                 format: { DisplayFormat.compact($0) })
            Text(AnalyticsSeries.tokenFootnote(range: range, mixes: mixes, selected: selection.selected, only: only))
                .font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("analytics.tokens.footnote")
            if size == .full {
                AnalyticsDetailTableView(AnalyticsSeries.tokenTable(range: range, mixes: mixes), highlighted: selection.selected, size: size,
                                         isExpanded: .constant(true), id: "analytics.tokens.table")
            }
        }
    }
}

/// The four legend buttons, at least 44pt high: the kind singled out reads as selected and the others fade. Identifiers
/// analytics.tokens.legend.<kind>.
private struct TokenLegend: View {
    let values: TokenMix
    let only: TokenKind?
    let stripes: ImagePaint
    let toggle: @MainActor (TokenKind) -> Void

    private static let fadedOpacity = 0.55

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) { ForEach(TokenKind.allCases, id: \.self) { button($0) } }
            Grid(alignment: .leading, horizontalSpacing: 2, verticalSpacing: 0) {
                GridRow { button(.input); button(.output) }
                GridRow { button(.cacheRead); button(.cacheWrite) }
            }
        }
    }

    private func button(_ kind: TokenKind) -> some View {
        let isOn = only == kind, value = DisplayFormat.compact(values[kind])
        return Button { toggle(kind) } label: {
            HStack(spacing: 5) {
                TokenKindSwatch(kind: kind, stripes: stripes)
                Text(kind.title).foregroundStyle(Palette.ink2)
                Text(value).fontWeight(.semibold).monospacedDigit().foregroundStyle(Palette.ink1)
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(isOn ? Palette.sunken : Color.clear, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(only == nil || isOn ? 1 : Self.fadedOpacity)
        .accessibilityLabel("\(kind.title) \(value)")
        .accessibilityHint(isOn ? "恢复全部" : "只看这一项")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("analytics.tokens.legend.\(kind.rawValue)")
    }
}

private struct TokenKindSwatch: View {
    let kind: TokenKind
    let stripes: ImagePaint

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(TokenKindStyle.fill(kind, stripes: stripes))
            .overlay {
                if kind == .cacheRead || TokenKindStyle.outlined.contains(kind) {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.ink2, lineWidth: 1)
                }
            }
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

/// 40 §2.3 the kinds' fills, three greys and an outline: 输入 the chart's ink, 输出 its grey, 缓存读 stripes, 缓存写 the surface within an
/// outline. The tiles' sketches draw the same.
enum TokenKindStyle {
    static let outlined: Set<TokenKind> = [.cacheWrite]

    static func fill(_ kind: TokenKind, stripes: ImagePaint) -> AnyShapeStyle {
        switch kind {
        case .input: AnyShapeStyle(Palette.chartMain)
        case .output: AnyShapeStyle(Palette.chartBar)
        case .cacheRead: AnyShapeStyle(stripes)
        case .cacheWrite: AnyShapeStyle(Palette.surface)
        }
    }
}

// MARK: - 端点分布

/// 40 §2.3 端点分布: 入站端点 · 上游端点, then every endpoint (a card shows them all, as the chart page does): the path monospaced, its
/// requests, the share bar with its percent and what was charged. It reads 计费趋势's totals. Identifiers analytics.endpoints.*.
struct EndpointShareBody: View {
    let size: BodySize
    @Environment(\.analyticsSession) private var session

    init(size: BodySize) { self.size = size }

    var body: some View {
        if let session { EndpointShareContent(session: session) }
    }

    static func load(_ session: AnalyticsSession, refresh: Bool) async { await session.loadBillingSummary(refresh: refresh) }
}

private struct EndpointShareContent: View {
    let session: AnalyticsSession
    @State private var side: EndpointSide = .inbound

    /// Three rows, until the totals answer.
    private static let loadingHeight: CGFloat = 200
    private static let emptyHeight: CGFloat = 88

    var body: some View {
        let summary = session.state(.billingSummary, as: AnalyticsSummary.self)
        VStack(alignment: .leading, spacing: 8) {
            Picker("端点", selection: $side) {
                ForEach(EndpointSide.allCases, id: \.self) { item in
                    Text(item.title).tag(item).accessibilityIdentifier("analytics.endpoints.side.\(item.rawValue)")
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("analytics.endpoints.side")
            AnalyticsCardBody(summary, id: "analytics.endpoints", minHeight: Self.loadingHeight, timeZone: zone, retry: retry) { summary in
                rows(AnalyticsSeries.endpointRows(summary, side: side))
            }
        }
        .analyticsCardLoading("body.endpoints", session: session) { [session] refresh in
            await EndpointShareBody.load(session, refresh: refresh)
        }
    }

    private var zone: TimeZone { session.timeZone.timeZone }
    private func retry() {
        let session = session
        Task { await EndpointShareBody.load(session, refresh: true) }
    }

    @ViewBuilder private func rows(_ rows: [AnalyticsShareRow]) -> some View {
        if rows.isEmpty {
            Text("这个范围内没有用量").font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: Self.emptyHeight)
                .accessibilityIdentifier("analytics.endpoints.empty")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    EndpointShareRow(row: row, id: "analytics.endpoints.row.\(index)")
                }
            }
        }
    }
}

/// One endpoint, read as one line: “/v1/messages，10,920 次请求，占 60.0%，实际 $612.40”.
private struct EndpointShareRow: View {
    let row: AnalyticsShareRow
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.name).font(.subheadline.monospaced()).foregroundStyle(Palette.ink1).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Text(row.requestsText).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink1).fixedSize()
            }
            HStack(spacing: 8) {
                RankShareTrack(share: row.share)
                Text(row.shareText).font(.caption).monospacedDigit().foregroundStyle(Palette.ink2).frame(minWidth: 44, alignment: .trailing)
            }
            Text(row.costLine).font(.caption).monospacedDigit().foregroundStyle(Palette.ink3)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenLabel)
        .accessibilityIdentifier(id)
    }
}
