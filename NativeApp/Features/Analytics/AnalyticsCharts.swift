import Accessibility
import Charts
import SwiftUI
import Sub2Core

/// 40 §1.4 / §1.5 the money bar chart of 计费趋势 (and 利润明细, the chart pages): one grey bar per bucket on a continuous index axis
/// (HomeHourlyChart's way), the bucket still running or the selected one darker, the standard as a dotted line, ticks from the range
/// with 现在 / 今天 in a stronger grey, the amounts on the right. With a selection the whole plot is one tap and press-and-drag area
/// (`.chartXSelection`, folded by AnalyticsChartSelection: pressing the selected bar again clears it); no bar has its own target.
/// `.chartXSelection` only answers a touch held for a moment, so a quick tap is read by a simultaneous SpatialTapGesture as one
/// press and release of its bucket (S4D2b-04 ⑤; `.chartGesture` would replace the drag, and a zero-distance drag would hold the
/// page's scrolling). A range without usage keeps the axes and says so. VoiceOver gets an AXChartDescriptor and one label per bar.
/// Identifier `<id>`, the empty text `<id>.empty`.
struct AnalyticsBarChart: View {
    private let series: AnalyticsBarSeries
    private let selection: Binding<AnalyticsChartSelection>?
    private let id: String
    private let chartTitle: String
    private let height: CGFloat
    private let emptyText: String
    @State private var rawX: Double?
    /// The plot's frame in the chart's space, for a tap's bucket.
    @State private var plotFrame: CGRect = .zero
    /// When the last press-and-drag let go: the tap that ends the same touch is not a second press.
    @State private var releasedAt: Date?

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
    /// A tap this soon after a press-and-drag let go belongs to that touch.
    private static let tapAfterRelease: TimeInterval = 0.5
    private static let lineStroke = StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [1.5, 3])

    @ViewBuilder private var plot: some View {
        if let selection {
            chart.chartXSelection(value: $rawX)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        let frame = proxy.plotFrame.map { geometry[$0] } ?? .zero
                        Color.clear.allowsHitTesting(false)
                            .onAppear { plotFrame = frame }
                            .onChange(of: frame) { _, new in plotFrame = new }
                    }
                }
                .simultaneousGesture(SpatialTapGesture().onEnded { tapped(at: $0.location, selection: selection) })
                .onChange(of: rawX) { old, x in
                    if old != nil, x == nil { releasedAt = Date() }
                    selection.wrappedValue = selection.wrappedValue.receiving(x.flatMap(series.bucketIndex(atX:)))
                }
        } else {
            chart
        }
    }

    /// A quick tap the press-and-drag did not see: its bucket pressed and let go at once.
    private func tapped(at location: CGPoint, selection: Binding<AnalyticsChartSelection>) {
        let afterPress = releasedAt.map { Date().timeIntervalSince($0) < Self.tapAfterRelease } ?? false
        guard rawX == nil, !afterPress, plotFrame.width > 0, (plotFrame.minX...plotFrame.maxX).contains(location.x) else { return }
        let x = Double((location.x - plotFrame.minX) / plotFrame.width) * Double(series.bars.count) - 0.5
        guard let index = series.bucketIndex(atX: x) else { return }
        selection.wrappedValue = selection.wrappedValue.receiving(index).receiving(nil)
    }

    private var chart: some View {
        let selected = selection?.wrappedValue.selected
        return Chart {
            ForEach(series.bars) { bar in barMark(bar, selected: selected) }
            ForEach(series.bars.filter { $0.plotLine != nil }) { bar in lineMark(bar) }
        }
        .chartXScale(domain: -0.5...(Double(max(series.bars.count, 1)) - 0.5))
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

    private var xAxis: some AxisContent {
        AxisMarks(values: series.ticks.map { Double($0.index) }) { value in
            if let tick = tick(at: value.as(Double.self)) {
                AxisValueLabel {
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
