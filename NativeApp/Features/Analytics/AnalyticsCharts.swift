import Accessibility
import Charts
import SwiftUI
import Sub2Core

/// 40 §1.4 / §1.5 the money bar chart of 计费趋势 (and 利润明细, the chart pages): one grey bar per bucket on a continuous index axis
/// (HomeHourlyChart's way), the bucket still running or the selected one darker, the standard as a dotted line, ticks from the range
/// with 现在 / 今天 in a stronger grey, the amounts on the right. With a selection the whole plot is one tap and press-and-drag area
/// (`analyticsChartSelection`); no bar has its own target. A range without usage keeps the axes and says so. VoiceOver gets an
/// AXChartDescriptor and one label per bar. Identifier `<id>`, the empty text `<id>.empty`.
struct AnalyticsBarChart: View {
    private let series: AnalyticsBarSeries
    private let selection: Binding<AnalyticsChartSelection>?
    private let id: String
    private let chartTitle: String
    private let height: CGFloat
    private let emptyText: String

    /// `selection` nil: the chart takes no selection (the model page's trend).
    init(series: AnalyticsBarSeries, selection: Binding<AnalyticsChartSelection>?, id: String, chartTitle: String,
         height: CGFloat = 118, emptyText: String = "这个范围内没有用量") {
        self.series = series; self.selection = selection; self.id = id; self.chartTitle = chartTitle
        self.height = height; self.emptyText = emptyText
    }

    var body: some View {
        ZStack {
            plot
                .frame(height: height)
                .accessibilityChartDescriptor(AnalyticsBarChartDescriptor(series: series, title: chartTitle))
                .accessibilityIdentifier(id)
            if series.isEmpty {
                Text(emptyText).font(.footnote).foregroundStyle(Palette.ink2)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Palette.surface.opacity(0.9), in: Capsule())
                    .accessibilityIdentifier("\(id).empty")
            }
        }
    }

    private static let barHalfWidth = 0.36
    private static let lineStroke = StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [1.5, 3])

    private var xDomain: ClosedRange<Double> { -0.5...(Double(max(series.bars.count, 1)) - 0.5) }

    @ViewBuilder private var plot: some View {
        if let selection {
            chart.analyticsChartSelection(selection, xDomain: xDomain, bucketAt: series.bucketIndex(atX:))
        } else {
            chart
        }
    }

    private var chart: some View {
        let selected = selection?.wrappedValue.selected
        return Chart {
            ForEach(series.bars) { bar in barMark(bar, selected: selected) }
            ForEach(series.bars.filter { $0.plotLine != nil }) { bar in lineMark(bar) }
            if series.yDomain.lowerBound < 0 { zeroLine }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: series.yDomain)
        .chartXAxis { xAxis }
        .chartYAxis { yAxis }
        .chartLegend(.hidden)
    }

    // One function per mark keeps the builder cheap to type-check.

    private func barMark(_ bar: AnalyticsBarSeries.Bar, selected: Int?) -> some ChartContent {
        let index = Double(bar.id)
        return RectangleMark(xStart: .value("时段", index - Self.barHalfWidth), xEnd: .value("时段", index + Self.barHalfWidth),
                             yStart: .value(series.metricName, 0.0), yEnd: .value(series.metricName, bar.plotValue))
            .foregroundStyle(series.isEmphasized(bar.id, selected: selected) ? Palette.chartBarNow : Palette.chartBar)
            .cornerRadius(1.5)
            .accessibilityLabel(series.spokenLabel(bar.id))
    }
    private func lineMark(_ bar: AnalyticsBarSeries.Bar) -> some ChartContent {
        LineMark(x: .value("时段", Double(bar.id)), y: .value("标准", bar.plotLine ?? 0), series: .value("系列", "标准"))
            .foregroundStyle(Palette.chartCompare)
            .lineStyle(Self.lineStroke)
            .accessibilityHidden(true)
    }
    /// 40 §1.4 利润明细: once the axis holds a loss, a 1pt zero line the bars grow down from, never recoloured (S4-13b).
    private var zeroLine: some ChartContent {
        RuleMark(y: .value("零线", 0.0))
            .foregroundStyle(Palette.ink3)
            .lineStyle(StrokeStyle(lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var xAxis: some AxisContent {
        AxisMarks(values: series.ticks.map { Double($0.index) }) { value in
            if let tick = tick(at: value.as(Double.self)) {
                // Centred under its bar.
                AxisValueLabel(anchor: .top) {
                    Text(tick.label).font(.caption2).monospacedDigit().foregroundStyle(tick.isNow ? Palette.ink2 : Palette.ink3)
                }
            }
        }
    }
    private var yAxis: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(Palette.hairline)
            AxisValueLabel {
                if let amount = value.as(Double.self) {
                    Text(DisplayFormat.moneyCompact(Decimal(amount))).font(.caption2).monospacedDigit().foregroundStyle(Palette.ink3)
                }
            }
        }
    }
    private func tick(at position: Double?) -> AnalyticsAxisTick? {
        guard let position else { return nil }
        return series.ticks.first { Double($0.index) == position }
    }
}

extension View {
    /// 40 §1.5 整图点选 for an analytics chart (put it on the Chart) whose x is continuous over `xDomain`: `.chartXSelection` scrubs a
    /// touch held for a moment, folded by AnalyticsChartSelection (pressing the selected bucket again clears it); a quick tap, which
    /// `.chartXSelection` lets pass, is read by a simultaneous SpatialTapGesture as one press and release of its bucket (S4D2b-04 ⑤:
    /// `.chartGesture` would replace the scrubbing, a zero-distance drag would hold the page's scrolling). `bucketAt` takes an x to
    /// its bucket. S4-16's line and S4-17's stacked bars select the same way.
    func analyticsChartSelection(_ selection: Binding<AnalyticsChartSelection>, xDomain: ClosedRange<Double>,
                                 bucketAt: @escaping (Double) -> Int?) -> some View {
        modifier(AnalyticsChartSelecting(selection: selection, xDomain: xDomain, bucketAt: bucketAt))
    }
}

private struct AnalyticsChartSelecting: ViewModifier {
    /// A tap this soon after a press-and-drag let go ends that same touch.
    private static let tapAfterRelease: TimeInterval = 0.5

    @Binding var selection: AnalyticsChartSelection
    let xDomain: ClosedRange<Double>
    let bucketAt: (Double) -> Int?
    @State private var rawX: Double?
    /// The plot's frame in the chart's space, for a tap's x.
    @State private var plotFrame: CGRect = .zero
    @State private var releasedAt: Date?

    func body(content: Content) -> some View {
        content
            .chartXSelection(value: $rawX)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let frame = proxy.plotFrame.map { geometry[$0] } ?? .zero
                    Color.clear.allowsHitTesting(false)
                        .onAppear { plotFrame = frame }
                        .onChange(of: frame) { _, new in plotFrame = new }
                }
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { tapped(at: $0.location) })
            .onChange(of: rawX) { old, x in
                if old != nil, x == nil { releasedAt = Date() }
                selection = selection.receiving(x.flatMap(bucketAt))
            }
    }

    private func tapped(at location: CGPoint) {
        let afterPress = releasedAt.map { Date().timeIntervalSince($0) < Self.tapAfterRelease } ?? false
        guard rawX == nil, !afterPress, plotFrame.width > 0, (plotFrame.minX...plotFrame.maxX).contains(location.x) else { return }
        let fraction = Double((location.x - plotFrame.minX) / plotFrame.width)
        guard let index = bucketAt(xDomain.lowerBound + fraction * (xDomain.upperBound - xDomain.lowerBound)) else { return }
        selection = selection.receiving(index).receiving(nil)
    }
}

/// The chart for VoiceOver: one category per bucket (its spoken name) against the amount, one series.
struct AnalyticsBarChartDescriptor: AXChartDescriptorRepresentable {
    let series: AnalyticsBarSeries
    let title: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let names = series.bars.map(\.bucket.spokenLabel)
        let xAxis = AXCategoricalDataAxisDescriptor(title: "时段", categoryOrder: names)
        let yAxis = AXNumericDataAxisDescriptor(title: series.metricName, range: series.yDomain, gridlinePositions: []) { value in
            DisplayFormat.money(Decimal(value))
        }
        let points = series.bars.map { bar in
            AXDataPoint(x: bar.bucket.spokenLabel, y: bar.plotValue, label: DisplayFormat.spoken(DisplayFormat.money(bar.value)))
        }
        let data = AXDataSeriesDescriptor(name: series.metricName, isContinuous: false, dataPoints: points)
        return AXChartDescriptor(title: title, summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [data])
    }
}

/// The card header's key: a grey bar 实际, the dotted line 标准（点线）. One element for VoiceOver, identifier analytics.legend.
struct AnalyticsChartLegend: View {
    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(Palette.chartBar).frame(width: 6, height: 10)
            Text("实际")
            Path { path in
                path.move(to: CGPoint(x: 1, y: 1))
                path.addLine(to: CGPoint(x: 11, y: 1))
            }
            .stroke(Palette.chartCompare, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1.5, 3]))
            .frame(width: 12, height: 2)
            .padding(.leading, 6)
            Text("标准（点线）")
        }
        .font(.caption)
        .foregroundStyle(Palette.ink2)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("实际为灰柱，标准为点线")
        .accessibilityIdentifier("analytics.legend")
    }
}

// MARK: - 堆叠柱（S4-17）

/// 40 §2.3 the stacked bars (Token 使用趋势; S4-18's 错误趋势 takes no selection): one column per bucket on AnalyticsBarChart's index
/// axis, each layer bottom-up in `order` with a 1.5pt seam the card's surface shows through, an `outlined` layer drawn as a line
/// around its fill, ticks from the range, values on the right. With a selection the whole plot is one tap and press-and-drag area
/// (`analyticsChartSelection`) and the other columns fade. A range without any value keeps the axes and says so. VoiceOver gets
/// an AXChartDescriptor with a series per layer and a label per segment. Identifier `<id>`, the empty text `<id>.empty`.
struct AnalyticsStackedBars<Layer: Hashable & Sendable>: View {
    private let values: [[Layer: Double]]
    private let order: [Layer]
    private let ticks: [AnalyticsAxisTick]
    private let columnNames: [String]
    private let selection: Binding<AnalyticsChartSelection>?
    private let id: String
    private let chartTitle: String
    private let height: CGFloat
    private let emptyText: String?
    private let outlined: Set<Layer>
    private let style: (Layer) -> AnyShapeStyle
    private let layerName: (Layer) -> String
    private let format: @Sendable (Double) -> String
    @State private var plotSize: CGSize = .zero

    /// `values` one per column, `columnNames` how VoiceOver names each; `emptyText` nil while there is something to draw.
    init(values: [[Layer: Double]], order: [Layer], ticks: [AnalyticsAxisTick], columnNames: [String],
         selection: Binding<AnalyticsChartSelection>?, id: String, chartTitle: String, height: CGFloat, emptyText: String? = nil,
         outlined: Set<Layer> = [], style: @escaping (Layer) -> AnyShapeStyle, layerName: @escaping (Layer) -> String,
         format: @escaping @Sendable (Double) -> String) {
        self.values = values; self.order = order; self.ticks = ticks; self.columnNames = columnNames; self.selection = selection
        self.id = id; self.chartTitle = chartTitle; self.height = height; self.emptyText = emptyText; self.outlined = outlined
        self.style = style; self.layerName = layerName; self.format = format
    }

    var body: some View {
        let yMax = yMax
        ZStack {
            plot(yMax: yMax)
                .frame(height: height)
                .accessibilityChartDescriptor(AnalyticsStackedBarsDescriptor(values: values, order: order, columnNames: columnNames,
                                                                             title: chartTitle, yMax: yMax, layerName: layerName, format: format))
                .accessibilityIdentifier(id)
            if let emptyText {
                Text(emptyText).font(.footnote).foregroundStyle(Palette.ink2)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Palette.surface.opacity(0.9), in: Capsule())
                    .accessibilityIdentifier("\(id).empty")
            }
        }
    }

    private var xDomain: ClosedRange<Double> { -0.5...(Double(max(values.count, 1)) - 0.5) }
    /// The tallest column with a tenth of room; 0…1 with nothing to draw.
    private var yMax: Double {
        let top = values.map { column in order.reduce(0) { $0 + max(column[$1] ?? 0, 0) } }.max() ?? 0
        return top > 0 ? top * StackedBarsMetrics.headroom : 1
    }

    @ViewBuilder private func plot(yMax: Double) -> some View {
        if let selection {
            let count = values.count
            chart(yMax: yMax).analyticsChartSelection(selection, xDomain: xDomain) { x in StackedBarsMetrics.column(atX: x, count: count) }
        } else {
            chart(yMax: yMax)
        }
    }

    private func chart(yMax: Double) -> some View {
        // Points in the chart's units: the seam and the outline keep their width at any scale.
        let perPoint = CGSize(width: plotSize.width > 0 ? (xDomain.upperBound - xDomain.lowerBound) / plotSize.width : 0,
                              height: plotSize.height > 0 ? yMax / plotSize.height : 0)
        let stacks = AnalyticsSeries.stack(values, order: order, gap: StackedBarsMetrics.seam * perPoint.height)
        let pieces = stacks.indices.flatMap { column in
            stacks[column].map { StackPiece(column: column, segment: $0, value: values[column][$0.layer] ?? 0) }
        }
        let selected = selection?.wrappedValue.selected.flatMap { values.indices.contains($0) ? $0 : nil }
        let inset = CGSize(width: StackedBarsMetrics.outline * perPoint.width, height: StackedBarsMetrics.outline * perPoint.height)
        return Chart {
            ForEach(pieces) { piece in marks(piece, faded: selected.map { $0 != piece.column } ?? false, inset: inset) }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...yMax)
        .chartXAxis { xAxis }
        .chartYAxis { yAxis }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.onGeometryChange(for: CGSize.self) { $0.size } action: { plotSize = $0 }
        }
    }

    /// An outlined layer: the line colour over the whole segment, its fill `inset` inside (none when too thin to hold one).
    @ChartContentBuilder
    private func marks(_ piece: StackPiece<Layer>, faded: Bool, inset: CGSize) -> some ChartContent {
        let half = StackedBarsMetrics.barHalfWidth, x = Double(piece.column), segment = piece.segment
        let opacity = faded ? StackedBarsMetrics.fadedOpacity : 1
        let inner = outlined.contains(segment.layer) ? inset : .zero
        if outlined.contains(segment.layer) {
            rectangle(x - half, x + half, segment.lower, segment.upper)
                .foregroundStyle(Palette.ink2)
                .opacity(opacity)
                .accessibilityHidden(true)
        }
        if half - inner.width > 0, segment.upper - segment.lower > 2 * inner.height {
            rectangle(x - half + inner.width, x + half - inner.width, segment.lower + inner.height, segment.upper - inner.height)
                .foregroundStyle(style(segment.layer))
                .opacity(opacity)
                .accessibilityLabel(spokenLabel(piece))
                .accessibilityValue(format(piece.value))
        }
    }
    private func rectangle(_ xStart: Double, _ xEnd: Double, _ yStart: Double, _ yEnd: Double) -> RectangleMark {
        RectangleMark(xStart: .value("时段", xStart), xEnd: .value("时段", xEnd), yStart: .value("数量", yStart), yEnd: .value("数量", yEnd))
    }
    private func spokenLabel(_ piece: StackPiece<Layer>) -> String {
        (columnNames.indices.contains(piece.column) ? columnNames[piece.column] + "，" : "") + layerName(piece.segment.layer)
    }

    private var xAxis: some AxisContent {
        AxisMarks(values: ticks.map { Double($0.index) }) { value in
            if let tick = tick(at: value.as(Double.self)) {
                AxisValueLabel(anchor: .top) {
                    Text(tick.label).font(.caption2).monospacedDigit().foregroundStyle(tick.isNow ? Palette.ink2 : Palette.ink3)
                }
            }
        }
    }
    private var yAxis: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(Palette.hairline)
            AxisValueLabel {
                if let amount = value.as(Double.self) {
                    Text(format(amount)).font(.caption2).monospacedDigit().foregroundStyle(Palette.ink3)
                }
            }
        }
    }
    private func tick(at position: Double?) -> AnalyticsAxisTick? {
        guard let position else { return nil }
        return ticks.first { Double($0.index) == position }
    }
}

/// The stacked bars' measures (a generic type has no stored statics).
private enum StackedBarsMetrics {
    /// AnalyticsBarChart's bar width.
    static let barHalfWidth = 0.36
    static let seam = 1.5
    static let outline = 1.2
    static let fadedOpacity = 0.35
    static let headroom = 1.1

    /// The column under a continuous x: rounded and kept within the columns.
    static func column(atX x: Double, count: Int) -> Int? {
        guard count > 0, x.isFinite else { return nil }
        return Int(min(max(x.rounded(), 0), Double(count - 1)))
    }
}

private struct StackPiece<Layer: Hashable & Sendable>: Identifiable {
    let column: Int
    let segment: AnalyticsStackSegment<Layer>
    let value: Double
    var id: String { "\(column)-\(segment.lower)" }
}

/// The stacked bars for VoiceOver: one category per bucket against the value, one series per layer.
private struct AnalyticsStackedBarsDescriptor<Layer: Hashable & Sendable>: AXChartDescriptorRepresentable {
    let values: [[Layer: Double]]
    let order: [Layer]
    let columnNames: [String]
    let title: String
    let yMax: Double
    let layerName: (Layer) -> String
    let format: @Sendable (Double) -> String

    func makeChartDescriptor() -> AXChartDescriptor {
        let format = format
        let xAxis = AXCategoricalDataAxisDescriptor(title: "时段", categoryOrder: columnNames)
        let yAxis = AXNumericDataAxisDescriptor(title: title, range: 0...yMax, gridlinePositions: []) { format($0) }
        let series = order.map { layer in
            let points = zip(columnNames, values).map { name, column in
                AXDataPoint(x: name, y: column[layer] ?? 0, label: format(column[layer] ?? 0))
            }
            return AXDataSeriesDescriptor(name: layerName(layer), isContinuous: false, dataPoints: points)
        }
        return AXChartDescriptor(title: title, summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: series)
    }
}

/// 缓存读's stripes as a chart fill (40 §2.3): a 1.4pt line every 3pt over the background, the colours resolved in `environment`
/// (a view reading the environment rebuilds it for light or dark).
enum AnalyticsStripes {
    private static let tile = CGSize(width: 6, height: 3)
    private static let line: CGFloat = 1.4

    static func paint(ink: Color, background: Color, in environment: EnvironmentValues) -> ImagePaint {
        let ink = Color(ink.resolve(in: environment)), background = Color(background.resolve(in: environment))
        let tile = tile, line = line
        let image = Image(size: tile) { context in
            context.fill(Path(CGRect(origin: .zero, size: tile)), with: .color(background))
            context.fill(Path(CGRect(x: 0, y: 0, width: tile.width, height: line)), with: .color(ink))
        }
        return ImagePaint(image: image)
    }
}

// MARK: - 运行类（S4-18）

/// 40 §2.3 平均账号切换's line: switches per request at each bucket's start on a continuous time axis over the page range, broken
/// where a bucket had no request (a lone point is a dot), marks at the summary's ticks (现在 in a stronger grey), two decimals on the
/// right. It takes no selection (S4D2b-04 ⑧); VoiceOver gets an AXChartDescriptor and “今天 09:40，0.012 次/请求” per point.
/// Identifier `<id>`.
struct AnalyticsRatioLineChart: View {
    private let summary: OpsSwitchSummary
    private let range: AnalyticsRange
    private let id: String
    private let height: CGFloat

    private static let lineStroke = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
    private static let headroom = 1.15
    /// The axis of a range without switches.
    private static let floorMax = 0.01
    private static let dotSize: CGFloat = 16

    init(summary: OpsSwitchSummary, range: AnalyticsRange, id: String, height: CGFloat) {
        self.summary = summary; self.range = range; self.id = id; self.height = height
    }

    var body: some View {
        let yMax = max((summary.highest ?? 0) * Self.headroom, Self.floorMax)
        chart(yMax: yMax)
            .frame(height: height)
            .accessibilityChartDescriptor(AnalyticsRatioChartDescriptor(summary: summary, range: range, yMax: yMax))
            .accessibilityIdentifier(id)
    }

    private func chart(yMax: Double) -> some View {
        let ticks = OpsSwitchSummary.axisTicks(for: range)
        let lone = Set(Dictionary(grouping: summary.points, by: \.segment).filter { $0.value.count == 1 }.keys)
        return Chart {
            ForEach(summary.points) { point in line(point) }
            ForEach(summary.points.filter { lone.contains($0.segment) }) { point in dot(point) }
        }
        .chartXScale(domain: range.start...range.end)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: ticks.map(\.date)) { value in
                AxisGridLine().foregroundStyle(Palette.hairline)
                if let date = value.as(Date.self), let tick = ticks.first(where: { $0.date == date }) {
                    AxisValueLabel(anchor: .top) {
                        Text(tick.label).font(.caption2).monospacedDigit().foregroundStyle(tick.isNow ? Palette.ink2 : Palette.ink3)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel {
                    if let rate = value.as(Double.self) {
                        Text(OpsSwitchSummary.axisLabel(rate)).font(.caption2).monospacedDigit().foregroundStyle(Palette.ink3)
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }

    private func line(_ point: OpsSwitchSummary.Point) -> some ChartContent {
        LineMark(x: .value("时间", point.date), y: .value("次/请求", point.rate), series: .value("段", point.segment))
            .foregroundStyle(Palette.chartMain)
            .lineStyle(Self.lineStroke)
            .accessibilityLabel(OpsSwitchSummary.spokenPoint(point, range: range))
    }
    private func dot(_ point: OpsSwitchSummary.Point) -> some ChartContent {
        PointMark(x: .value("时间", point.date), y: .value("次/请求", point.rate))
            .foregroundStyle(Palette.chartMain)
            .symbolSize(Self.dotSize)
            .accessibilityHidden(true)
    }
}

/// The line for VoiceOver: one category per drawn bucket against its switches per request.
private struct AnalyticsRatioChartDescriptor: AXChartDescriptorRepresentable {
    let summary: OpsSwitchSummary
    let range: AnalyticsRange
    let yMax: Double

    func makeChartDescriptor() -> AXChartDescriptor {
        let range = range
        let names = summary.points.map { DisplayFormat.dayTime($0.date, now: range.now, timeZone: range.zone.timeZone) }
        let xAxis = AXCategoricalDataAxisDescriptor(title: "时间", categoryOrder: names)
        let yAxis = AXNumericDataAxisDescriptor(title: "次/请求", range: 0...yMax, gridlinePositions: []) { OpsSwitchSummary.perRequest($0) }
        let points = zip(names, summary.points).map { name, point in
            AXDataPoint(x: name, y: point.rate, label: OpsSwitchSummary.spokenPoint(point, range: range))
        }
        let series = AXDataSeriesDescriptor(name: AnalyticsChartKey.accountSwitch.title, isContinuous: true, dataPoints: points)
        return AXChartDescriptor(title: AnalyticsChartKey.accountSwitch.title, summary: summary.footnote, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
    }
}
