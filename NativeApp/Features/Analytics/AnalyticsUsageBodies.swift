import SwiftUI
import Sub2Core

// 40 §2.3 the 用量 bodies (S4-17: Token 使用趋势, 端点分布; S4-17b adds 用户用量趋势 and 请求类型), in 更多图表's list (`.card`) and on a
// chart page (`.full`). S4-17's two read what 计费趋势 reads, S4-17b's their own requests, all through the session (40 §2.2).

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

// MARK: - 用户用量趋势与请求类型（S4-17b）

extension AnalyticsCardKey {
    /// UserUsageSeries, one per metric (a segment read once stays until the range or the filter changes). Only Tokens is read on
    /// 统计分析 (the tile), so only it counts toward “N 分钟前更新” (S4D2b-14).
    static func userTrend(_ metric: UserTrendMetric) -> AnalyticsCardKey {
        AnalyticsCardKey("more.userTrend.\(metric.rawValue)", showsInUpdateLine: metric == .tokens)
    }
    /// RequestTypeMix.
    static let requestTypes = AnalyticsCardKey("more.reqType", showsInUpdateLine: false)
}

/// The two charts' reads; a body and its tile share the key, so the card and the tile read once.
@MainActor enum UsageChartLoads {
    /// `users-trend` with `limit=12`; under a filter without `dashboard.users_trend_filtered_metric` no `metric` (only Tokens shows).
    static func userTrend(_ session: AnalyticsSession, metric: UserTrendMetric, supportsFilteredMetric: Bool, refresh: Bool = false) async {
        await session.load(.userTrend(metric), refresh: refresh, fixture: { try AnalyticsFixtures.userUsageSeries($0, metric: metric) }) { client, session in
            let range = session.range, query = session.query()
            let sent = UserUsageSeries.requestMetric(metric, isFiltered: session.filter != nil, supportsFilteredMetric: supportsFilteredMetric)
            let reply = try await client.usageAnalysisUsersTrend(query, metric: sent, limit: UserUsageSeries.limit)
            return UserUsageSeries(points: reply.points, range: range, metric: metric)
        }
    }
    /// `dashboard/request-types`, or without `dashboard.request_types` one `usage/stats` per type.
    static func requestTypes(_ session: AnalyticsSession, supportsRequestTypes: Bool, refresh: Bool = false) async {
        await session.load(.requestTypes, refresh: refresh, fixture: { _ in try AnalyticsFixtures.requestTypeMix(viaFallback: !supportsRequestTypes) }) {
            client, session in
            try await RequestTypeMix.load(session.query(), client: client, supportsRequestTypes: supportsRequestTypes)
        }
    }
}

/// 40 §2.3 用户用量趋势: Tokens · 实际扣费 (only Tokens under a filter the site cannot rank by cost), then the first five users (the
/// chart page twelve): rank, name, the user's line on its own scale and the total, a row opening the user; the footnote last.
/// Identifiers analytics.userTrend.*.
struct UserTrendBody: View {
    let size: BodySize
    @Environment(\.analyticsSession) private var session

    init(size: BodySize) { self.size = size }

    var body: some View {
        if let session { UserTrendContent(session: session, size: size) }
    }
}

private struct UserTrendContent: View {
    let session: AnalyticsSession
    let size: BodySize
    @Environment(\.sessionContext) private var context
    @State private var selected: UserTrendMetric = .tokens

    private static let rowHeight: CGFloat = 44

    private var rowCount: Int { size == .full ? UserUsageSeries.limit : UserUsageSeries.cardRowCount }

    var body: some View {
        let supports = context?.has(.dashboardUsersTrendFilteredMetric) ?? false
        let metrics = UserUsageSeries.metrics(isFiltered: session.filter != nil, supportsFilteredMetric: supports)
        let metric = metrics.contains(selected) ? selected : .tokens
        VStack(alignment: .leading, spacing: 8) {
            if metrics.count > 1 { picker(metrics) }
            AnalyticsCardBody(session.state(.userTrend(metric), as: UserUsageSeries.self), id: "analytics.userTrend",
                              minHeight: CGFloat(rowCount) * Self.rowHeight + 40, timeZone: session.timeZone.timeZone,
                              retry: { retry(metric, supports: supports) }) { series in
                loaded(series)
            }
        }
        .analyticsCardLoading("body.userTrend", session: session, trigger: metric) { [session] refresh in
            await UsageChartLoads.userTrend(session, metric: metric, supportsFilteredMetric: supports, refresh: refresh)
        }
    }

    private func picker(_ metrics: [UserTrendMetric]) -> some View {
        Picker("用户用量指标", selection: $selected) {
            ForEach(metrics, id: \.self) { metric in Text(metric.title).tag(metric) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("analytics.userTrend.metric")
    }

    private func retry(_ metric: UserTrendMetric, supports: Bool) {
        let session = session
        Task { await UsageChartLoads.userTrend(session, metric: metric, supportsFilteredMetric: supports, refresh: true) }
    }

    @ViewBuilder private func loaded(_ series: UserUsageSeries) -> some View {
        if series.isEmpty {
            Text("这个范围内没有用户用量").font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: 88)
                .accessibilityIdentifier("analytics.userTrend.empty")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(series.rows.prefix(rowCount).enumerated()), id: \.element.id) { index, _ in
                    UserTrendRow(series: series, index: index)
                }
            }
        }
        Text(UserUsageSeries.note(metric: series.metric, showsAll: size == .full))
            .font(.footnote).foregroundStyle(Palette.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("analytics.userTrend.note")
    }
}

/// One user, read as “第 1 名，Nova 工作室，12.4M Tokens”; a tap opens the user. Identifier analytics.userTrend.row.<userID>.
private struct UserTrendRow: View {
    let series: UserUsageSeries
    let index: Int

    private static let nameWidth: CGFloat = 100
    private static let sparklineHeight: CGFloat = 26

    var body: some View {
        let row = series.rows[index], isTop = index < 3
        NavigationLink(value: AppRoute.user(id: row.userID)) {
            HStack(spacing: 10) {
                Text("\(index + 1)").font(.callout.weight(isTop ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(isTop ? Palette.ink1 : Palette.ink3).frame(minWidth: 22)
                Text(row.name).font(.subheadline).foregroundStyle(Palette.ink1).lineLimit(1)
                    .frame(width: Self.nameWidth, alignment: .leading)
                AnalyticsSparklineShape(values: row.normalized)
                    .stroke(Palette.chartMain, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(maxWidth: .infinity).frame(height: Self.sparklineHeight)
                    .accessibilityHidden(true)
                Text(series.totalText(row)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
                    .lineLimit(1).fixedSize()
            }
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(series.spokenLabel(index))
        .accessibilityHint("打开用户详情")
        .accessibilityIdentifier("analytics.userTrend.row.\(row.userID)")
    }
}

/// A 0–1 series as a line across the frame, 1pt in from the top and the bottom; a single value is a dot in the middle. The rows'
/// lines and 用户用量's tile sketch.
struct AnalyticsSparklineShape: Shape {
    let values: [Double]

    private static let inset: CGFloat = 1
    private static let dot: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let height = max(0, rect.height - Self.inset * 2)
        let y = { (value: Double) in rect.maxY - Self.inset - height * CGFloat(min(1, max(0, value))) }
        var path = Path()
        guard values.count > 1 else {
            if let value = values.first {
                path.addEllipse(in: CGRect(x: rect.midX - Self.dot / 2, y: y(value) - Self.dot / 2, width: Self.dot, height: Self.dot))
            }
            return path
        }
        let step = rect.width / CGFloat(values.count - 1)
        path.addLines(values.enumerated().map { CGPoint(x: rect.minX + step * CGFloat($0.offset), y: y($0.element)) })
        return path
    }
}

/// 40 §2.3 请求类型: the bar of the types with requests, then the five in their fixed order: swatch (hollow at 0), name, requests and
/// share; without requests one line. The card and the chart page show the same. Identifiers analytics.reqType.*.
struct RequestTypeBody: View {
    let size: BodySize
    @Environment(\.analyticsSession) private var session

    init(size: BodySize) { self.size = size }

    var body: some View {
        if let session { RequestTypeContent(session: session) }
    }
}

private struct RequestTypeContent: View {
    let session: AnalyticsSession
    @Environment(\.sessionContext) private var context
    @Environment(\.self) private var environment

    /// The bar and five rows, until the types answer.
    private static let loadingHeight: CGFloat = 250

    var body: some View {
        let supports = context?.has(.dashboardRequestTypes) ?? false
        AnalyticsCardBody(session.state(.requestTypes, as: RequestTypeMix.self), id: "analytics.reqType", minHeight: Self.loadingHeight,
                          timeZone: session.timeZone.timeZone, retry: { retry(supports: supports) }) { mix in
            loaded(mix)
        }
        .analyticsCardLoading("body.reqType", session: session) { [session] refresh in
            await UsageChartLoads.requestTypes(session, supportsRequestTypes: supports, refresh: refresh)
        }
    }

    private func retry(supports: Bool) {
        let session = session
        Task { await UsageChartLoads.requestTypes(session, supportsRequestTypes: supports, refresh: true) }
    }

    @ViewBuilder private func loaded(_ mix: RequestTypeMix) -> some View {
        if mix.isEmpty {
            Text("这个范围内没有用量").font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: 88)
                .accessibilityIdentifier("analytics.reqType.empty")
        } else {
            let paints = RequestTypeStyle.Paints(environment)
            RequestTypeBar(mix: mix, paints: paints)
            VStack(spacing: 0) {
                ForEach(mix.rows) { row in RequestTypeRow(row: row, paints: paints) }
            }
        }
    }
}

/// 40 §2.3 the types' fills: Token 使用趋势's four (ink, grey, stripes, an outline) for 流式, 同步, WS and 安全策略, then Live in ink3
/// dots (the design has four, and no palette colour is added); stripes, the outline and the dots have an ink2 border.
private enum RequestTypeStyle {
    struct Paints {
        let stripes: ImagePaint
        let dots: ImagePaint

        init(_ environment: EnvironmentValues) {
            stripes = AnalyticsStripes.paint(ink: Palette.ink2, background: Palette.surface, in: environment)
            dots = RequestTypeStyle.dots(in: environment)
        }
    }

    private static let dotTile = CGSize(width: 3, height: 3)
    private static let dotSize: CGFloat = 1.6

    static func fill(_ type: UsageRequestType, paints: Paints) -> AnyShapeStyle {
        switch type {
        case .stream: TokenKindStyle.fill(.input, stripes: paints.stripes)
        case .sync: TokenKindStyle.fill(.output, stripes: paints.stripes)
        case .wsV2: TokenKindStyle.fill(.cacheRead, stripes: paints.stripes)
        case .cyber: TokenKindStyle.fill(.cacheWrite, stripes: paints.stripes)
        case .live: AnyShapeStyle(paints.dots)
        }
    }
    static func isOutlined(_ type: UsageRequestType) -> Bool { [.wsV2, .cyber, .live].contains(type) }

    /// A dot every 3pt over the surface, the colours resolved in `environment` (as AnalyticsStripes).
    private static func dots(in environment: EnvironmentValues) -> ImagePaint {
        let ink = Color(Palette.ink3.resolve(in: environment)), background = Color(Palette.surface.resolve(in: environment))
        let tile = dotTile, size = dotSize
        let image = Image(size: tile) { context in
            context.fill(Path(CGRect(origin: .zero, size: tile)), with: .color(background))
            context.fill(Path(ellipseIn: CGRect(x: (tile.width - size) / 2, y: (tile.height - size) / 2, width: size, height: size)), with: .color(ink))
        }
        return ImagePaint(image: image)
    }
}

/// The types with requests side by side, 2pt apart, each as wide as its share; read as one element, “流式 72.1%，同步 23.7%，…”.
/// Identifier analytics.reqType.bar.
private struct RequestTypeBar: View {
    let mix: RequestTypeMix
    let paints: RequestTypeStyle.Paints

    private static let height: CGFloat = 14
    private static let gap: CGFloat = 2

    var body: some View {
        let rows = mix.barRows
        GeometryReader { proxy in
            let width = max(0, proxy.size.width - Self.gap * CGFloat(max(0, rows.count - 1)))
            HStack(spacing: Self.gap) {
                ForEach(rows) { row in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(RequestTypeStyle.fill(row.type, paints: paints))
                        .overlay {
                            if RequestTypeStyle.isOutlined(row.type) { RoundedRectangle(cornerRadius: 1).strokeBorder(Palette.ink2, lineWidth: 1) }
                        }
                        .frame(width: width * (row.share ?? 0))
                }
            }
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .padding(.top, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mix.barSpokenLabel)
        .accessibilityIdentifier("analytics.reqType.bar")
    }
}

/// One type, read as “流式，13,120 次请求，占 72.1%”, one without requests valued 没有请求. Identifier analytics.reqType.row.<type>.
private struct RequestTypeRow: View {
    let row: RequestTypeMix.Row
    let paints: RequestTypeStyle.Paints

    var body: some View {
        VStack(spacing: 0) {
            Palette.hairline.frame(height: 1).accessibilityHidden(true)
            HStack(spacing: 10) {
                RequestTypeSwatch(type: row.type, isEmpty: row.isEmpty, paints: paints)
                Text(row.type.title).font(.subheadline).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                Text(row.requestsText).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
                Text(row.shareText).font(.caption).monospacedDigit().foregroundStyle(Palette.ink2).frame(minWidth: 54, alignment: .trailing)
            }
            .frame(minHeight: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenLabel)
        .accessibilityValue(row.isEmpty ? "没有请求" : "")
        .accessibilityIdentifier("analytics.reqType.row.\(row.type.rawValue)")
    }
}

/// 10pt: the type's fill, or a dashed hollow square without requests.
private struct RequestTypeSwatch: View {
    let type: UsageRequestType
    let isEmpty: Bool
    let paints: RequestTypeStyle.Paints

    private static let side: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        Group {
            if isEmpty {
                shape.strokeBorder(Palette.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [2, 1.5]))
            } else {
                shape.fill(RequestTypeStyle.fill(type, paints: paints))
                    .overlay { if RequestTypeStyle.isOutlined(type) { shape.strokeBorder(Palette.ink2, lineWidth: 1) } }
            }
        }
        .frame(width: Self.side, height: Self.side)
        .accessibilityHidden(true)
    }
}
