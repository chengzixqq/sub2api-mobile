import SwiftUI
import Charts
import Sub2Core

// S1-09: stage 1's stand-in for `.analytics(focus: .perf, metric:)`, where the overview's RPM and TPM cells lead. The old overview's
// trend chart, moved here unchanged (its dashboard.trend.* identifiers too), opens on 性能指标 with the cell's metric; S4-13
// removes this page, LegacyTrendUITests and the focus split in AnalyticsDestinations (X20).

/// The page around the chart: it loads `dashboard/trend` itself, every 30 seconds while it shows and the App is active (D18: the
/// task restarts on the phase; there is no scene-phase handler). Identifier legacy.trend.
struct LegacyTrendPage: View {
    let metric: PerfMetric?
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var trend = LoadState<DashboardTrendReply>()
    @State private var visible = false
    private var polling: Bool { visible && scenePhase == .active }

    var body: some View {
        // The closure uses its own copy, even when onAppear changed visibility before the first task started.
        let shouldPoll = polling
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Performance has its own endpoint and stays reachable while the usage trend is slow or fails.
                DashboardTrendChart(reply: trend.value, initialMetric: .performance, performanceMetric: PerformanceMetric(metric ?? .rpm))
                if let error = trend.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Palette.criticalInk).accessibilityIdentifier("dashboard.trend.error")
                }
                if trend.isLoading { ProgressView("正在加载趋势…").accessibilityIdentifier("dashboard.trend.loading") }
                Button(trend.value == nil ? "重试趋势" : "刷新趋势") { Task { await loadTrend() } }
                    .frame(minHeight: 44).accessibilityIdentifier("dashboard.trend.load").disabled(trend.isLoading)
                if let date = trend.updatedAt {
                    Text("更新于 \(date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(Palette.ink2)
                }
            }
            .padding().frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .background(Palette.canvas)
        .accessibilityIdentifier("legacy.trend")
        .navigationTitle("用量与性能趋势")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadTrend() }
        .onAppear { visible = true }
        .onDisappear { visible = false; trend.cancel() }
        .task(id: shouldPoll) {
            guard shouldPoll else { return }
            while !Task.isCancelled {
                if !trend.isLoading { await loadTrend() }
                do { try await Task.sleep(for: .seconds(trend.nextDelay(base: 30))) } catch { return }
            }
        }
    }

    private func loadTrend() async {
        guard !trend.isLoading, let generation = session?.generation else { return }
        await trend.load(isCurrent: { polling && generation == model.sessionGeneration }) { try await model.dashboardTrend() }
    }
}

fileprivate extension PerformanceMetric {
    init(_ metric: PerfMetric) {
        switch metric {
        case .rpm: self = .rpm
        case .tpm: self = .tpm
        }
    }
}

/// Interpolate the scale so bar widths grow smoothly from the anchored edge;
/// gestures continue to update the same scale without a separate animation.
nonisolated private struct AnimatedTrendViewport: AnimatableModifier {
    let span: TimeInterval
    var zoom: Double
    var animatableData: Double {
        get { zoom }
        set { zoom = newValue }
    }
    @MainActor func body(content: Content) -> some View {
        content.chartXVisibleDomain(length: span / max(1, zoom))
    }
}

/// Native iOS 17 chart scrolling and selection keep horizontal panning separate
/// from a tap; magnification and the buttons change the same visible time window.
private struct DashboardTrendChart: View {
    let series: DashboardTrendSeries
    /// Gregorian in the series zone, so Charts bins hours and days on the server's calendar.
    private let calendar: Calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var metric: DashboardTrendMetric
    private let performanceMetric: PerformanceMetric
    @State private var zoom = 1.0
    @State private var gestureStartZoom: Double?
    @State private var scrollDate: Date
    @State private var selectedDate: Date?
    @State private var showingDetails = false

    /// Buckets are read, binned and labelled in the reply's server zone (00 §6.4), not the phone's. The page opens on
    /// `initialMetric`; its fourth tab starts on `performanceMetric`.
    init(reply: DashboardTrendReply?, initialMetric: DashboardTrendMetric = .actualCost, performanceMetric: PerformanceMetric = .rpm) {
        _metric = State(initialValue: initialMetric)
        self.performanceMetric = performanceMetric
        // Without a reply there are no points, so the zone only has to be valid.
        let parsed = DashboardTrend.series(reply?.points ?? [], timeZone: reply?.timeZone ?? .gmt)
        series = parsed
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = parsed.timeZone
        self.calendar = calendar
        _scrollDate = State(initialValue: parsed.samples.first?.date ?? .now)
    }

    private var bucketSeconds: TimeInterval { series.isHourly ? 3_600 : 86_400 }
    private var firstDate: Date { series.samples.first?.date ?? .now }
    private var endDate: Date { (series.samples.last?.date ?? firstDate).addingTimeInterval(bucketSeconds) }
    private var span: TimeInterval { max(bucketSeconds, endDate.timeIntervalSince(firstDate)) }
    private var maximumZoom: Double { max(1, span / (bucketSeconds * 3)) }
    private var visibleDuration: TimeInterval { span / zoom }
    private var visibleStart: Date { clampedStart(scrollDate, duration: visibleDuration) }
    private var visibleEnd: Date { min(endDate, visibleStart.addingTimeInterval(visibleDuration)) }
    private var showBarValues: Bool { zoom >= 6 || visibleDuration <= bucketSeconds * 6 }
    private var selectedSample: DashboardTrendSample? {
        guard let selectedDate else { return nil }
        return series.samples.min {
            abs($0.date.addingTimeInterval(bucketSeconds / 2).timeIntervalSince(selectedDate)) <
            abs($1.date.addingTimeInterval(bucketSeconds / 2).timeIntervalSince(selectedDate))
        }
    }
    private var ticks: [Date] {
        let visible = series.samples.filter { $0.date >= visibleStart && $0.date < visibleEnd }
        guard let first = visible.first, let last = visible.last else { return [] }
        if visible.count <= 4 { return visible.map(\.date) }
        return Array(Set([first.date, visible[visible.count / 2].date, last.date])).sorted()
    }
    private var yDomain: ClosedRange<Double> {
        let values = series.samples.compactMap { metric.plotValue($0.point) }
        let lower = min(0, values.min() ?? 0)
        let upper = max(0, values.max() ?? 0)
        guard lower != 0 || upper != 0 else { return 0...1 }
        return (lower * 1.25)...(upper * 1.25)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("趋势指标", selection: $metric) {
                ForEach(DashboardTrendMetric.allCases) { metric in Text(metric.label).tag(metric) }
            }.pickerStyle(.segmented).accessibilityIdentifier("dashboard.trend.metric")

            if metric != .performance {
                Text("昨日以来的小时趋势，独立自动刷新。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if metric == .performance {
                PerformanceTrendView(initialMetric: performanceMetric)
            } else if series.samples.isEmpty {
                Text("暂无可绘制的用量趋势，请检查加载状态或稍后重试。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                zoomControls
                chart
                Text("当前：\(dateLabel(visibleStart)) — \(dateLabel(visibleEnd))")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("dashboard.trend.visible-range")
                Text("全部：\(dateLabel(firstDate)) — \(dateLabel(series.samples.last!.date))")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("dashboard.trend.range")
                if metric == .actualCost && series.samples.contains(where: { $0.point.actualCost == nil }) {
                    Text("部分时段未返回实际消费，显示为 —；未以标准费用代替。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let sample = selectedSample {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(dateLabel(sample.date)) · \(metric.label)").font(.caption).foregroundStyle(.secondary)
                        Text(displayLabel(sample)).font(.headline).monospacedDigit().textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("dashboard.trend.selection")
                } else {
                    Text("点选柱子查看数值；放大后可左右滑动，双指缩放或使用按钮调整。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(series.isHourly ? "逐小时明细" : "逐日明细") { showingDetails = true }
                    .buttonStyle(.bordered).accessibilityIdentifier("dashboard.trend.details")
            }
            if series.invalidDateCount > 0 {
                Text("\(series.invalidDateCount) 个时间点无法解析，未绘入图表。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: series.samples.map(\.date)) { _, _ in
            zoom = DashboardTrend.clampedZoom(zoom, maximum: maximumZoom)
            scrollDate = clampedStart(scrollDate, duration: visibleDuration)
            if let selectedDate, selectedDate < firstDate || selectedDate >= endDate { self.selectedDate = nil }
        }
        .sheet(isPresented: $showingDetails) { details }
    }

    private var zoomControls: some View {
        HStack {
            Button { animateZoom(zoom / 2) } label: { Image(systemName: "minus.magnifyingglass").frame(minWidth: 40, minHeight: 40) }
                .accessibilityLabel("缩小趋势").accessibilityIdentifier("dashboard.trend.zoom-out").disabled(zoom <= 1)
            Spacer(minLength: 2)
            Text("放大 \(zoom.formatted(.number.precision(.fractionLength(0...1))))×")
                .font(.subheadline).monospacedDigit().accessibilityIdentifier("dashboard.trend.zoom-level")
            Spacer(minLength: 2)
            Button { animateZoom(zoom * 2) } label: { Image(systemName: "plus.magnifyingglass").frame(minWidth: 40, minHeight: 40) }
                .accessibilityLabel("放大趋势").accessibilityIdentifier("dashboard.trend.zoom-in").disabled(zoom >= maximumZoom)
        }.buttonStyle(.bordered)
    }

    private var chart: some View {
        Chart {
            ForEach(series.samples) { sample in
                if let value = metric.plotValue(sample.point) {
                    BarMark(x: .value("时间", sample.date, unit: series.isHourly ? .hour : .day),
                            y: .value(metric.label, value), width: .ratio(0.75))
                        .foregroundStyle(metric == .actualCost ? Color.purple.gradient : Color.indigo.gradient)
                        .annotation(position: .top, spacing: 4) {
                            if showBarValues {
                                Text(metric.displayValue(sample.point)).font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                    .transition(.opacity)
                            }
                        }
                        .accessibilityLabel(dateLabel(sample.date))
                        .accessibilityValue(displayLabel(sample))
                }
            }
            if let selectedSample, let value = metric.plotValue(selectedSample.point) {
                RuleMark(x: .value("选中时间", selectedSample.date.addingTimeInterval(bucketSeconds / 2)))
                    .foregroundStyle(Color.secondary.opacity(0.5)).lineStyle(StrokeStyle(dash: [4]))
                PointMark(x: .value("选中时间", selectedSample.date.addingTimeInterval(bucketSeconds / 2)), y: .value(metric.label, value))
                    .foregroundStyle(Color.primary)
            }
        }
        .chartXScale(domain: firstDate...endDate)
        .chartYScale(domain: yDomain)
        .chartScrollableAxes(.horizontal)
        .chartScrollTargetBehavior(.valueAligned(matching: series.isHourly ? DateComponents(minute: 0) : DateComponents(hour: 0)))
        .modifier(AnimatedTrendViewport(span: span, zoom: zoom))
        .chartScrollPosition(x: $scrollDate)
        .chartXSelection(value: $selectedDate)
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { event in proxy.selectXValue(at: event.location.x) }
        }
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(dateLabel(date).replacingOccurrences(of: " ", with: "\n"))
                            .font(.caption2).multilineTextAlignment(.center).fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let value = value.as(Double.self) {
                        Text(metric.axisLabel(value))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 250).accessibilityLabel("\(series.isHourly ? "每小时" : "每日")\(metric.label)趋势")
        .environment(\.timeZone, series.timeZone)
        .environment(\.calendar, calendar)
        .accessibilityIdentifier("dashboard.trend.chart")
        .simultaneousGesture(MagnifyGesture().onChanged { value in
            if gestureStartZoom == nil { gestureStartZoom = zoom }
            changeZoom((gestureStartZoom ?? zoom) * value.magnification)
        }.onEnded { _ in gestureStartZoom = nil })
    }

    private var details: some View {
        NavigationStack {
            List(series.newestFirst) { sample in
                Button {
                    selectedDate = sample.date.addingTimeInterval(bucketSeconds / 2)
                    scrollDate = clampedStart(sample.date, duration: visibleDuration)
                    showingDetails = false
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(dateLabel(sample.date)).font(.subheadline).foregroundStyle(.secondary)
                        Text(displayLabel(sample)).font(.body.monospacedDigit()).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("dashboard.trend.hour.\(sample.point.date)")
            }
            .accessibilityIdentifier("dashboard.trend.hour-values")
            .navigationTitle("\(metric.label)明细")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingDetails = false } } }
        }
    }
    private func displayLabel(_ sample: DashboardTrendSample) -> String {
        metric.displayValue(sample.point) + (metric == .actualCost ? "" : " " + metric.unit)
    }
    private func dateLabel(_ date: Date) -> String {
        DashboardPresentation.trendAxisLabel(date, hourly: series.isHourly, timeZone: series.timeZone)
    }
    private func clampedStart(_ date: Date, duration: TimeInterval) -> Date {
        min(max(firstDate, date), max(firstDate, endDate.addingTimeInterval(-duration)))
    }
    private func animateZoom(_ next: Double) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { changeZoom(next) }
    }
    private func changeZoom(_ next: Double) {
        // Keep the visible left edge in place: bars stretch to the right instead
        // of combining a centered pan with the visible-domain animation.
        let anchoredStart = visibleStart
        zoom = DashboardTrend.clampedZoom(next, maximum: maximumZoom)
        scrollDate = clampedStart(anchoredStart, duration: visibleDuration)
    }
}
