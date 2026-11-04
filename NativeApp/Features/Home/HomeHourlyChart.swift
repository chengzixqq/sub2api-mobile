import Charts
import SwiftUI
import Sub2Core

/// 10 §1.3.4 每小时实际扣费: today up to the current hour over yesterday's dotted 24 hours, labelled only 0时 6时 12时 18时 and 现在.
/// No Y axis, no grid and no selection; VoiceOver reads it as one element. The regular layout draws today as bars, S1-11's calm
/// layout as a line with the area under it. Identifier `home.today.chart`.
struct HomeHourlyChart: View {
    enum Style: Sendable { case bars, line }

    let series: HomeHourlySeries
    var style: Style = .bars
    var height: CGFloat = 104

    var body: some View {
        VStack(spacing: 4) {
            plot.frame(height: height)
            HomeHourlyAxis(labels: series.axisLabels)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeHourlySeries.accessibilityLabel)
        .accessibilityIdentifier("home.today.chart")
    }

    private static let compareStroke = StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [1.5, 3])
    private static let todayStroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
    private static let barHalfWidth = 0.32

    private var plot: some View {
        Chart {
            if style == .bars {
                ForEach(series.today) { bar in todayBar(bar) }
            } else {
                ForEach(series.today) { bar in
                    todayArea(bar)
                    todayLine(bar)
                }
                if let now = series.today.last { nowPoint(now) }
            }
            ForEach(series.yesterday) { bar in yesterdayLine(bar) }
        }
        .chartXScale(domain: -0.5...23.5)
        .chartYScale(domain: 0...series.upperBound)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .allowsHitTesting(false)
    }

    // One function per mark keeps the builder cheap to type-check.

    /// A bar 0.64 hours wide on the continuous hour axis, from 0 up to the amount: a rectangle with both ends on each axis.
    private func todayBar(_ bar: HomeHourlySeries.Bar) -> some ChartContent {
        let hour = Double(bar.hour)
        let color: Color = bar.isCurrent ? Palette.chartBarNow : Palette.chartBar
        return RectangleMark(xStart: .value("小时", hour - Self.barHalfWidth), xEnd: .value("小时", hour + Self.barHalfWidth),
                             yStart: .value("实际扣费", 0.0), yEnd: .value("实际扣费", bar.plotValue))
            .foregroundStyle(color)
            .cornerRadius(1.5)
    }
    private func todayArea(_ bar: HomeHourlySeries.Bar) -> some ChartContent {
        AreaMark(x: .value("小时", Double(bar.hour)), y: .value("实际扣费", bar.plotValue))
            .foregroundStyle(Palette.ink1.opacity(0.07))
    }
    private func todayLine(_ bar: HomeHourlySeries.Bar) -> some ChartContent {
        LineMark(x: .value("小时", Double(bar.hour)), y: .value("实际扣费", bar.plotValue), series: .value("日", "今天"))
            .foregroundStyle(Palette.chartMain)
            .lineStyle(Self.todayStroke)
    }
    private func nowPoint(_ bar: HomeHourlySeries.Bar) -> some ChartContent {
        PointMark(x: .value("小时", Double(bar.hour)), y: .value("实际扣费", bar.plotValue))
            .foregroundStyle(Palette.chartMain)
            .symbolSize(50)
    }
    private func yesterdayLine(_ bar: HomeHourlySeries.Bar) -> some ChartContent {
        LineMark(x: .value("小时", Double(bar.hour)), y: .value("实际扣费", bar.plotValue), series: .value("日", "昨天"))
            .foregroundStyle(Palette.chartCompare)
            .lineStyle(Self.compareStroke)
    }
}

/// The hour labels under the plot: a fixed hour starts at its slot, 现在 centres on its bar; both stay inside the plot's width.
private struct HomeHourlyAxis: View {
    let labels: [HomeHourlySeries.AxisLabel]

    var body: some View {
        // The hidden line gives the row its height at any text size; the labels are placed over it.
        Text("现在").font(.caption2).hidden()
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .topLeading) {
                        // Pins the stack's leading edge to the plot's, whatever label comes first.
                        Color.clear.frame(width: width, height: 0)
                        ForEach(labels) { label in
                            Text(label.text).font(.caption2).monospacedDigit()
                                .foregroundStyle(label.isNow ? Palette.ink2 : Palette.ink3)
                                .fixedSize()
                                .alignmentGuide(.leading) { size in -Self.leading(label, labelWidth: size.width, in: width) }
                        }
                    }
                }
            }
            .accessibilityHidden(true)
    }

    nonisolated private static func leading(_ label: HomeHourlySeries.AxisLabel, labelWidth: CGFloat, in width: CGFloat) -> CGFloat {
        let slot = width / 24, hour = CGFloat(label.hour)
        let start: CGFloat = label.isNow ? (hour + 0.5) * slot - labelWidth / 2 : hour * slot
        return min(max(start, 0), max(width - labelWidth, 0))
    }
}

/// 今天 drawn like its mark (a bar, or the calm layout's solid line), 昨天 the same dotted line as the plot. Hidden from VoiceOver:
/// the chart's label already says what is compared.
struct HomeHourlyLegend: View {
    let style: HomeHourlyChart.Style

    var body: some View {
        HStack(spacing: 5) {
            todayKey
            Text("今天")
            yesterdayKey.padding(.leading, 6)
            Text("昨天")
        }
        .font(.caption)
        .foregroundStyle(Palette.ink2)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var todayKey: some View {
        switch style {
        case .bars: RoundedRectangle(cornerRadius: 1).fill(Palette.chartBarNow).frame(width: 6, height: 10)
        case .line: Capsule().fill(Palette.chartMain).frame(width: 12, height: 2)
        }
    }
    private var yesterdayKey: some View {
        Path { path in
            path.move(to: CGPoint(x: 1, y: 1))
            path.addLine(to: CGPoint(x: 11, y: 1))
        }
        .stroke(Palette.chartCompare, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1.5, 3]))
        .frame(width: 12, height: 2)
    }
}
