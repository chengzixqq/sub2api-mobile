import Charts
import SwiftUI
import Sub2Core

/// 10 §4.3 small line: no axes, no grid, no selection. A missing value breaks the line and a point standing alone is a dot; with
/// nothing to draw it keeps its height. S1-13's error rate draws the area under it; S1-14's CPU and memory reuse it with a fixed
/// 0–100. The caller names it for VoiceOver.
struct Sparkline: View {
    let series: SparklineSeries
    var showsArea = true
    var tint: Color = Palette.chartMain
    var height: CGFloat = 40

    private static let stroke = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)

    var body: some View {
        Group {
            if series.isEmpty { Color.clear } else { chart }
        }
        .frame(height: height)
    }

    private var chart: some View {
        Chart {
            ForEach(Array(series.runs.enumerated()), id: \.offset) { run in
                ForEach(run.element) { point in
                    if showsArea { area(point, run: run.offset) }
                    line(point, run: run.offset)
                }
            }
            ForEach(series.isolated) { point in dot(point) }
        }
        .chartXScale(domain: 0...Double(max(series.count - 1, 1)))
        .chartYScale(domain: 0...series.upperBound)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .allowsHitTesting(false)
    }

    // One function per mark keeps the builder cheap to type-check. Each run is its own series, so a gap stays open.

    private func area(_ point: SparklineSeries.Point, run: Int) -> some ChartContent {
        AreaMark(x: .value("点", Double(point.index)), yStart: .value("值", 0.0), yEnd: .value("值", point.value), series: .value("段", run))
            .foregroundStyle(tint.opacity(0.12))
    }
    private func line(_ point: SparklineSeries.Point, run: Int) -> some ChartContent {
        LineMark(x: .value("点", Double(point.index)), y: .value("值", point.value), series: .value("段", run))
            .foregroundStyle(tint)
            .lineStyle(Self.stroke)
    }
    private func dot(_ point: SparklineSeries.Point) -> some ChartContent {
        PointMark(x: .value("点", Double(point.index)), y: .value("值", point.value))
            .foregroundStyle(tint)
            .symbolSize(14)
    }
}
