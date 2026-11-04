import Accessibility
import Charts
import SwiftUI
import Sub2Core

/// 40 §1.4 / §2.7 RPM / TPM 趋势's body (S4-16; S4-18's 更多图表 shows it too): 近 1 / 6 / 24 小时, the newest bucket (or the selected
/// one) as the big number beside RPM · TPM, peak and average, the line over its area with the selected bucket's rule and dot, the
/// notes, the last read's time and the way to 性能明细. The window and the metric are the site's, shared by every place showing the
/// chart. Ops monitoring off (admin/me, or a 404 OPS_DISABLED) turns it into OpsDisabledNotice. It reads through the page's loaders
/// (pull to refresh, the foreground) and on its own 30 seconds after each read while it shows and the App is active; leaving or the
/// background stops that. The session comes from `\.analyticsSession`. Identifiers analytics.perf.*.
struct PerfTrendBody: View {
    /// The chart's height: 128pt on a card, 170pt full screen (the design's AxPerfBody).
    enum Size: Sendable {
        case card, full
        var chartHeight: CGFloat { self == .card ? 128 : 170 }
    }

    private let filter: AnalyticsFilter?
    private let size: Size
    private let startMetric: PerfMetric?
    @Environment(AppModel.self) private var model
    @Environment(\.analyticsSession) private var session
    @State private var state: PerfTrendState?

    /// `startMetric`: route.metric, preferred to the remembered metric the first time and written back.
    init(filter: AnalyticsFilter?, size: Size, startMetric: PerfMetric? = nil) {
        self.filter = filter; self.size = size; self.startMetric = startMetric
    }

    var body: some View {
        Group {
            if let state, state.session === session {
                PerfTrendPanel(state: state, filter: filter, size: size)
            } else {
                AnalyticsCardPlaceholder(height: PerfTrendPanel.placeholderHeight(size), id: "analytics.perf")
            }
        }
        .onAppear(perform: prepare)
        .onChange(of: session.map { ObjectIdentifier($0) }) { _, _ in prepare() }
    }

    /// One state per session: another site's session starts from its own memory.
    private func prepare() {
        guard let session, state?.session !== session else { return }
        let model = model
        let hooks = PerfOpsHooks(isDisabled: { [weak model] in model?.analyticsOpsDisabled ?? false },
                                 record: { [weak model] error in await model?.recordAnalyticsOpsResponse(error) })
        state = PerfTrendState(session: session, memory: model.analyticsMemory, startMetric: startMetric, hooks: hooks,
                               fixture: { hours in try AnalyticsFixtures.perfTrend(hours: hours) })
    }
}

/// The reads and the 30-second loop hang here, so they go on behind the ops notice and bring the chart back once ops is on.
private struct PerfTrendPanel: View {
    @Bindable var state: PerfTrendState
    let filter: AnalyticsFilter?
    let size: PerfTrendBody.Size
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnScreen = false
    /// Scrolled out of the page; true until the scroll view says otherwise (and outside one).
    @State private var isScrollVisible = true
    @State private var showsDetails = false

    /// About the loaded body's height: the window bar, the big number, the chart and the notes.
    static func placeholderHeight(_ size: PerfTrendBody.Size) -> CGFloat { size.chartHeight + 200 }
    /// At most one read a second, whatever a read brought (one the session skipped, a site that went away).
    private static let readPause: Duration = .seconds(1)

    var body: some View {
        let polls = isOnScreen && isScrollVisible && scenePhase == .active
        let opsDisabled = state.isOpsDisabled
        Group {
            if state.showsOpsNotice {
                OpsDisabledNotice(style: .emptyState)
            } else {
                readings
            }
        }
        .analyticsCardLoading("perf", session: state.session, trigger: PerfPollKey(window: state.window, opsDisabled: opsDisabled),
                              followsLiveTick: false) { [state] refresh in await state.load(refresh: refresh) }
        .task(id: PerfPollKey(window: state.window, opsDisabled: opsDisabled, polls: polls)) { [state] in
            guard polls else { return }
            await Self.poll(state)
        }
        .onAppear { isOnScreen = true; state.appear() }
        .onDisappear { isOnScreen = false }
        .onScrollVisibilityChange(threshold: 0.01) { isScrollVisible = $0 }
        .onChange(of: filter) { _, _ in state.clearSelection() }
        .sheet(isPresented: $showsDetails) { PerfDetailsSheet(state: state, timeZone: zone) }
    }

    /// 40 §1.7: 30 seconds after the last read (a pull to refresh moves it on), the backoff after a failure, a 429's wait; stops for
    /// ops off, a 400 or a 403.
    private static func poll(_ state: PerfTrendState) async {
        while !Task.isCancelled {
            guard let wait = state.pollDelay(now: Date()) else { return }
            if wait > 0 {
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }
                continue
            }
            await state.load(refresh: true)
            do { try await Task.sleep(for: readPause) } catch { return }
        }
    }

    private var zone: TimeZone { state.session.timeZone.timeZone }
    private func retry() {
        let state = state
        Task { await state.load(refresh: true) }
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("性能时间范围", selection: Binding(get: { state.window }, set: { state.selectWindow($0) })) {
                ForEach(PerfWindow.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("analytics.perf.window")
            // The card polls on its own, so a 429's countdown does not send again when it ends (S1D1-20).
            AnalyticsCardBody(state.loadState, id: "analytics.perf", minHeight: Self.placeholderHeight(size) - 44, timeZone: zone,
                              resendsAfterWait: false, retry: retry) { _ in
                if let trend = state.trend {
                    loaded(trend)
                } else {
                    AnalyticsCardPlaceholder(height: Self.placeholderHeight(size) - 44, id: "analytics.perf")
                }
            }
        }
    }

    @ViewBuilder private func loaded(_ trend: PerformanceTrend) -> some View {
        let metric = state.performanceMetric, selected = state.selectedPoint
        hero(trend, metric: metric, selected: selected)
        Text(PerfTrendPresentation.subline(trend, metric: metric, selected: selected, windowTitle: state.window.title, timeZone: zone))
            .font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
            .accessibilityIdentifier("analytics.perf.subline")
        PerfTrendChart(trend: trend, metric: metric, selection: $state.chartSelection, height: size.chartHeight, timeZone: zone)
        Text(PerfTrendPresentation.explanation(trend, timeZone: zone))
            .font(.caption).foregroundStyle(Palette.ink3).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("analytics.perf.note")
        if let line = PerfTrendPresentation.updatedLine(state.loadState?.updatedAt, timeZone: zone) {
            Text(line).font(.caption).monospacedDigit().foregroundStyle(Palette.ink3).accessibilityIdentifier("analytics.perf.updated")
        }
        AnalyticsCardFoot(title: PerfTrendPresentation.detailsTitle, meta: PerfTrendPresentation.detailsMeta(trend),
                          id: "analytics.perf.foot") { showsDetails = true }
    }

    /// The big number with its label (one element), RPM · TPM beside it.
    private func hero(_ trend: PerformanceTrend, metric: PerformanceMetric, selected: PerformanceTrend.Point?) -> some View {
        let label = PerfTrendPresentation.headlineLabel(trend, metric: metric, selected: selected, timeZone: zone)
        let value = PerfTrendPresentation.headlineValue(trend, metric: metric, selected: selected)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.footnote).foregroundStyle(Palette.ink2).monospacedDigit().lineLimit(1)
                Text(value).font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .spokenValue(value)
            .accessibilityIdentifier("analytics.perf.amount")
            Spacer(minLength: 8)
            Picker("性能指标", selection: Binding(get: { state.metric }, set: { state.selectMetric($0) })) {
                ForEach(PerfMetric.allCases, id: \.self) { Text($0.performanceMetric.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("analytics.perf.metric")
        }
    }
}

/// The card's reads follow the window and the ops switch; its own loop also whether it shows.
private struct PerfPollKey: Hashable, Sendable {
    let window: PerfWindow
    let opsDisabled: Bool
    var polls = false
}

/// 40 §1.4 折线 + 面积 over the buckets' starts on a continuous time axis, the selected bucket's rule and dot, marks only at the site's
/// whole ticks, rates on the right. The whole plot takes the selection (`analyticsChartSelection`, nearest bucket). VoiceOver gets an
/// AXChartDescriptor and “09:40，RPM 46” per point. Identifier analytics.perf.chart, the empty text analytics.perf.empty.
private struct PerfTrendChart: View {
    let trend: PerformanceTrend
    let metric: PerformanceMetric
    @Binding var selection: AnalyticsChartSelection
    let height: CGFloat
    let timeZone: TimeZone

    private static let lineStroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
    /// Head room over the peak.
    private static let headroom = 1.15

    var body: some View {
        ZStack {
            plot
                .frame(height: height)
                .accessibilityChartDescriptor(PerfTrendChartDescriptor(trend: trend, metric: metric, timeZone: timeZone))
                .accessibilityIdentifier("analytics.perf.chart")
            if PerfTrendPresentation.isEmpty(trend) {
                Text(PerfTrendPresentation.emptyText).font(.footnote).foregroundStyle(Palette.ink2)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Palette.surface.opacity(0.9), in: Capsule())
                    .accessibilityIdentifier("analytics.perf.empty")
            }
        }
    }

    /// From the first bucket's start (it may begin before the window) to the window's end.
    private var xDomain: ClosedRange<Double> {
        let start = min(trend.points.first?.date ?? trend.windowStart, trend.windowStart)
        return start.timeIntervalSince1970...trend.windowEnd.timeIntervalSince1970
    }
    private var selected: PerformanceTrend.Point? {
        selection.selected.flatMap { trend.points.indices.contains($0) ? trend.points[$0] : nil }
    }

    private var plot: some View {
        let points = trend.points
        return Chart {
            ForEach(points) { point in
                area(point)
                line(point)
            }
            if let selected {
                rule(selected)
                dot(selected)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...max((trend.peak(metric) ?? 0) * Self.headroom, 1))
        .chartXAxis { xAxis }
        .chartYAxis { yAxis }
        .chartLegend(.hidden)
        .analyticsChartSelection($selection, xDomain: xDomain) { [trend] x in
            PerfTrendPresentation.nearestIndex(to: Date(timeIntervalSince1970: x), in: trend)
        }
    }

    // One function per mark keeps the builder cheap to type-check.

    private func rate(_ point: PerformanceTrend.Point) -> Double { trend.rate(point, metric: metric) }
    private func area(_ point: PerformanceTrend.Point) -> some ChartContent {
        AreaMark(x: .value("时间", point.date.timeIntervalSince1970), y: .value(metric.rawValue, rate(point)))
            .foregroundStyle(Palette.ink1.opacity(0.07))
            .accessibilityHidden(true)
    }
    private func line(_ point: PerformanceTrend.Point) -> some ChartContent {
        LineMark(x: .value("时间", point.date.timeIntervalSince1970), y: .value(metric.rawValue, rate(point)))
            .foregroundStyle(Palette.chartMain)
            .lineStyle(Self.lineStroke)
            .accessibilityLabel(PerfTrendPresentation.spokenPoint(point, in: trend, metric: metric, timeZone: timeZone))
    }
    private func rule(_ point: PerformanceTrend.Point) -> some ChartContent {
        RuleMark(x: .value("选中", point.date.timeIntervalSince1970))
            .foregroundStyle(Palette.ink3)
            .lineStyle(StrokeStyle(lineWidth: 1))
            .accessibilityHidden(true)
    }
    private func dot(_ point: PerformanceTrend.Point) -> some ChartContent {
        PointMark(x: .value("选中", point.date.timeIntervalSince1970), y: .value(metric.rawValue, rate(point)))
            .foregroundStyle(Palette.chartMain)
            .symbolSize(50)
            .accessibilityHidden(true)
    }

    private var xAxis: some AxisContent {
        AxisMarks(values: PerfTrendPresentation.axisTicks(trend, timeZone: timeZone).map(\.timeIntervalSince1970)) { value in
            AxisGridLine().foregroundStyle(Palette.hairline)
            AxisValueLabel {
                if let seconds = value.as(Double.self) {
                    Text(PerfTrendPresentation.axisLabel(Date(timeIntervalSince1970: seconds), timeZone: timeZone))
                        .font(.caption2).monospacedDigit().foregroundStyle(Palette.ink3)
                }
            }
        }
    }
    private var yAxis: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(Palette.hairline)
            AxisValueLabel {
                if let amount = value.as(Double.self) {
                    Text(metric.axisLabel(amount)).font(.caption2).monospacedDigit().foregroundStyle(Palette.ink3)
                }
            }
        }
    }
}

/// The line for VoiceOver: one category per bucket (“09:40”, “昨天 09:40”) against its rate.
private struct PerfTrendChartDescriptor: AXChartDescriptorRepresentable {
    let trend: PerformanceTrend
    let metric: PerformanceMetric
    let timeZone: TimeZone

    func makeChartDescriptor() -> AXChartDescriptor {
        let metric = metric
        let names = trend.points.map { PerfTrendPresentation.bucketLabel($0.date, windowEnd: trend.windowEnd, timeZone: timeZone) }
        let rates = trend.points.map { trend.rate($0, metric: metric) }
        let xAxis = AXCategoricalDataAxisDescriptor(title: "时间", categoryOrder: names)
        let yAxis = AXNumericDataAxisDescriptor(title: metric.rawValue, range: 0...max(rates.max() ?? 0, 1), gridlinePositions: []) { value in
            metric.format(value)
        }
        let points = trend.points.indices.map { index in
            AXDataPoint(x: names[index], y: rates[index],
                        label: PerfTrendPresentation.spokenPoint(trend.points[index], in: trend, metric: metric, timeZone: timeZone))
        }
        let data = AXDataSeriesDescriptor(name: metric.rawValue, isContinuous: true, dataPoints: points)
        return AXChartDescriptor(title: PerfTrendPresentation.cardTitle, summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [data])
    }
}
