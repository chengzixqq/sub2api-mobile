import SwiftUI
import Observation
import Charts
import Sub2Core

// A cancelled or late request cannot replace a newer foreground load.
@MainActor @Observable
final class DashboardLoadState<Value: Sendable> {
    var value: Value?
    var error: String?
    var updatedAt: Date?
    var isLoading = false
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var task: Task<Value, any Error>?

    func cancel() {
        requestID = nil
        task?.cancel(); task = nil; isLoading = false
    }
    func load(isCurrent: @MainActor () -> Bool, operation: @escaping @MainActor @Sendable () async throws -> Value) async {
        guard isCurrent(), !Task.isCancelled else { return }
        cancel()
        let id = UUID()
        let current = Task { try await operation() }
        requestID = id; task = current; isLoading = true; error = nil
        defer {
            if requestID == id { task = nil; requestID = nil; isLoading = false }
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await current.value
            } onCancel: { current.cancel() }
            guard requestID == id, isCurrent(), !Task.isCancelled else { return }
            value = result; updatedAt = Date()
        } catch {
            guard requestID == id, isCurrent(), !current.isCancelled, !Task.isCancelled,
                  !(error is CancellationError) else { return }
            self.error = error.localizedDescription
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var metric = DashboardTrendMetric.actualCost
    @State private var zoom = 1.0
    @State private var gestureStartZoom: Double?
    @State private var scrollDate: Date
    @State private var selectedDate: Date?
    @State private var showingDetails = false

    init(points: [TrendPoint]) {
        let parsed = DashboardTrend.series(points)
        series = parsed
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
                PerformanceTrendView()
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
                    Text("部分时段未返回实际消费，显示为不可用；未以标准费用代替。")
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
                        Text(metric == .actualCost ? DashboardPresentation.money(Decimal(value)) : DashboardPresentation.compactNumber(value))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 250).accessibilityLabel("\(series.isHourly ? "每小时" : "每日")\(metric.label)趋势")
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
    private func dateLabel(_ date: Date) -> String { DashboardPresentation.trendAxisLabel(date, hourly: series.isHourly) }
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

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var summaryCardHeight = 92.0
    @State private var stats = DashboardLoadState<DashboardSummary>()
    @State private var costs = DashboardLoadState<DashboardCostSnapshot>()
    @State private var costAttemptAt: Date?
    @State private var costLaunchID: UUID?
    @State private var trend = DashboardLoadState<[TrendPoint]>()
    @State private var monitoring = DashboardLoadState<OpsSnapshot>()
    @State private var visible = false
    private var polling: Bool { visible && scenePhase == .active }

    var body: some View {
        // The closure must use its own task ID, even if onAppear has already
        // changed visibility before SwiftUI starts the initial inactive task.
        let shouldPoll = polling
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let summary = stats.value {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 300 : 150), alignment: .leading)], spacing: 12) {
                        MetricView(title: "今日请求", value: summary.stats.todayRequests.formatted(), symbol: "arrow.left.arrow.right", contentHeight: summaryCardHeight) {
                            Text("总计：\(summary.stats.totalRequests?.formatted() ?? "不可用")")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("dashboard.total-requests")
                        }
                            .accessibilityIdentifier("dashboard.today-requests")
                        MetricView(title: "今日 Tokens", value: DashboardPresentation.compactNumber(summary.stats.todayTokens), symbol: "text.alignleft", contentHeight: summaryCardHeight) {
                            costBreakdown(actual: summary.stats.todayActualCost, account: summary.stats.todayAccountCost,
                                          snapshotActual: currentCostSnapshot?.actual, snapshotAccount: currentCostSnapshot?.account,
                                          period: "今日", identifier: "dashboard.today")
                        }
                            .accessibilityIdentifier("dashboard.today-tokens")
                        MetricView(title: "总 Tokens", value: summary.stats.totalTokens.map { DashboardPresentation.compactNumber($0) } ?? "不可用", symbol: "sum", contentHeight: summaryCardHeight) {
                            costBreakdown(actual: summary.stats.totalActualCost, account: summary.stats.totalAccountCost,
                                          snapshotActual: currentCostSnapshot?.totalActual, snapshotAccount: currentCostSnapshot?.totalAccount,
                                          period: "累计", identifier: "dashboard.total")
                        }
                            .accessibilityIdentifier("dashboard.total-tokens")
                        performanceCard(summary.stats)
                    }.accessibilityIdentifier("dashboard.metrics")
                }
                if stats.isLoading {
                    ProgressView(stats.value == nil ? "正在加载基础统计…" : "正在更新基础统计…")
                        .accessibilityIdentifier("dashboard.stats.loading")
                        .frame(maxWidth: .infinity).padding()
                    if stats.value == nil {
                        Text("大站点首次统计可能较慢，各分区会独立加载并显示。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                sectionError(stats.error, identifier: "dashboard.stats.error") { Task { await loadStats() } }
                if let date = stats.updatedAt {
                    Text("基础统计更新于 \(date.formatted(date: .omitted, time: .standard)) · 前台每 30 秒刷新")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if stats.value != nil {
                    Text("绿色为实际费用，黄色为上游成本；分别显示今日和累计统计。")
                        .font(.caption).foregroundStyle(.secondary)
                    if needsCostSnapshot {
                        if costs.isLoading { ProgressView("正在加载费用快照…") }
                        sectionError(costs.error, identifier: "dashboard.costs.error") { requestCosts(force: true) }
                        if let date = costs.updatedAt {
                            Text("费用快照更新于 \(date.formatted(date: .abbreviated, time: .standard))\(currentCostSnapshot == nil ? " · 已过期" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("刷新费用") { requestCosts(force: true) }
                            .disabled(costs.isLoading).accessibilityIdentifier("dashboard.costs.load")
                    }
                }
                GroupBox("用量趋势") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Performance has an independent endpoint and must remain
                        // reachable even while the usage query is slow or fails.
                        DashboardTrendChart(points: trend.value ?? [])
                        sectionError(trend.error, identifier: "dashboard.trend.error") { Task { await loadTrend() } }
                        if trend.isLoading { ProgressView("正在加载趋势…").accessibilityIdentifier("dashboard.trend.loading") }
                        Button(trend.value == nil ? "重试趋势" : "刷新趋势") { Task { await loadTrend() } }
                            .accessibilityIdentifier("dashboard.trend.load").disabled(trend.isLoading)
                        if let date = trend.updatedAt { lastUpdated(date) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }.accessibilityIdentifier("dashboard.trend.section")
                if let summary = stats.value {
                    GroupBox("运行健康") {
                        VStack(spacing: 10) {
                            LabeledValue(label: "异常账号", value: summary.stats.errorAccounts.formatted())
                                .accessibilityElement(children: .combine).accessibilityIdentifier("dashboard.health.errors")
                            LabeledValue(label: "平均响应时间", value: DashboardPresentation.duration(summary.stats.averageDurationMs))
                                .accessibilityElement(children: .combine).accessibilityIdentifier("dashboard.performance.duration")
                            Text("平均响应时间为累计请求平均值。")
                                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.top, 8)
                    }.accessibilityIdentifier("dashboard.health")
                }
                GroupBox("运行监控") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let summary = stats.value {
                            LabeledValue(label: "用户总数", value: summary.stats.totalUsers.formatted())
                            LabeledValue(label: "账号总数", value: summary.stats.totalAccounts.formatted())
                            Divider()
                        }
                        if let snapshot = monitoring.value {
                            LabeledValue(label: "错误率", value: snapshot.errorRate.map { ($0 * 100).formatted(.number.precision(.fractionLength(0...2))) + "%" } ?? "不可用")
                                .accessibilityElement(children: .combine).accessibilityIdentifier("dashboard.monitoring.error-rate")
                            LabeledValue(label: "QPS", value: snapshot.qps.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "不可用")
                                .accessibilityElement(children: .combine).accessibilityIdentifier("dashboard.monitoring.qps")
                            LabeledValue(label: "活跃请求", value: snapshot.activeRequests.map(String.init) ?? "不可用")
                                .accessibilityElement(children: .combine).accessibilityIdentifier("dashboard.monitoring.active-requests")
                        } else {
                            Text("运行监控独立自动刷新。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        sectionError(monitoring.error, identifier: "dashboard.monitoring.error") { Task { await loadMonitoring() } }
                        if monitoring.isLoading { ProgressView("正在加载监控…").accessibilityIdentifier("dashboard.monitoring.loading") }
                        Button(monitoring.value == nil ? "重试监控" : "刷新监控") { Task { await loadMonitoring() } }
                            .accessibilityIdentifier("dashboard.monitoring.load").disabled(monitoring.isLoading)
                        if let date = monitoring.updatedAt { lastUpdated(date) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }.padding().frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(model.activeProfile?.name ?? "概览")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AnalyticsView() } label: { Label("统计分析", systemImage: "chart.xyaxis.line") }
                    .accessibilityIdentifier("dashboard.analytics")
            }
        }
        .refreshable {
            async let primary: Void = loadStats(forceCosts: true)
            async let hourly: Void = loadTrend()
            async let operations: Void = loadMonitoring()
            _ = await (primary, hourly, operations)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; cancelLoads() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelLoads() } }
        .task(id: shouldPoll) {
            guard shouldPoll else { return }
            while !Task.isCancelled {
                // A scheduled tick must not restart a slow pull-to-refresh.
                if !stats.isLoading { await loadStats() }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task(id: shouldPoll) {
            guard shouldPoll else { return }
            while !Task.isCancelled {
                if !trend.isLoading { await loadTrend() }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task(id: shouldPoll) {
            guard shouldPoll else { return }
            while !Task.isCancelled {
                if !monitoring.isLoading { await loadMonitoring() }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
    @ViewBuilder
    private func sectionError(_ message: String?, identifier: String, retry: @escaping () -> Void) -> some View {
        if let message {
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.red).accessibilityIdentifier(identifier)
                Button("重试", action: retry).buttonStyle(.bordered).frame(minHeight: 44)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func lastUpdated(_ date: Date) -> some View {
        Text("更新于 \(date.formatted(date: .omitted, time: .standard))")
            .font(.caption).foregroundStyle(.secondary)
    }
    private func costBreakdown(actual: Decimal?, account: Decimal?, snapshotActual: Decimal?, snapshotAccount: Decimal?, period: String, identifier: String) -> some View {
        // A complete fallback pair comes from one response, never mixed timestamps.
        let useSnapshot = (actual == nil || account == nil) && snapshotActual != nil && snapshotAccount != nil
        let actual = useSnapshot ? snapshotActual : actual
        let account = useSnapshot ? snapshotAccount : account
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                costValue(actual, actual: true, period: period, identifier: identifier + "-actual-cost")
                Text("/").foregroundStyle(.secondary).accessibilityHidden(true)
                costValue(account, actual: false, period: period, identifier: identifier + "-account-cost")
            }
            VStack(alignment: .leading, spacing: 2) {
                costValue(actual, actual: true, period: period, identifier: identifier + "-actual-cost")
                costValue(account, actual: false, period: period, identifier: identifier + "-account-cost")
            }
        }
        .font(.caption).monospacedDigit()
        .accessibilityElement(children: .contain).accessibilityIdentifier(identifier + "-costs")
    }
    private func costValue(_ value: Decimal?, actual: Bool, period: String, identifier: String) -> some View {
        // Darker green/gold keep the small values legible on light cards.
        let tint: Color = actual
            ? (colorScheme == .dark ? .green : Color(red: 0.08, green: 0.47, blue: 0.23))
            : (colorScheme == .dark ? .yellow : Color(red: 0.55, green: 0.37, blue: 0))
        return Text(DashboardPresentation.compactCost(value))
            .foregroundStyle(value == nil ? Color.secondary : tint)
            .fixedSize()
            .accessibilityLabel("\(period)\(actual ? "实际费用" : "上游成本")")
            .accessibilityValue(DashboardPresentation.compactCost(value))
            .accessibilityIdentifier(identifier)
    }
    private func performanceCard(_ stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("性能指标", systemImage: "bolt.fill").font(.subheadline).foregroundStyle(.secondary)
            performanceLine(DashboardPresentation.rpmValue(stats), unit: "RPM", prominent: true)
                .accessibilityIdentifier("dashboard.performance.rpm")
            performanceLine(DashboardPresentation.compactNumber(stats.tpm), unit: "TPM", prominent: false)
                .accessibilityIdentifier("dashboard.performance.tpm")
            Text(DashboardPresentation.performanceWindow(stats)).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("dashboard.performance.window")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: summaryCardHeight, alignment: .topLeading).padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain).accessibilityIdentifier("dashboard.performance.card")
    }
    private func performanceLine(_ value: String, unit: String, prominent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(prominent ? .title2.bold() : .headline).foregroundStyle(prominent ? Color.primary : Color.purple)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .lineLimit(1).minimumScaleFactor(0.6).accessibilityElement(children: .combine)
    }
    private var needsCostSnapshot: Bool {
        guard let current = stats.value?.stats else { return false }
        return current.todayActualCost == nil || current.todayAccountCost == nil || current.totalActualCost == nil || current.totalAccountCost == nil
    }
    private var currentCostSnapshot: DashboardCostSnapshot? {
        guard needsCostSnapshot,
              let updatedAt = costs.updatedAt, Date().timeIntervalSince(updatedAt) < 90 else { return nil }
        return costs.value
    }
    private func cancelLoads() {
        if costLaunchID != nil { costAttemptAt = nil }
        costLaunchID = nil
        stats.cancel(); costs.cancel(); trend.cancel(); monitoring.cancel()
    }
    private func loadStats(forceCosts: Bool = false) async {
        guard let generation = session?.generation else { return }
        await stats.load(isCurrent: { polling && generation == model.sessionGeneration }) { try await model.dashboard() }
        requestCosts(force: forceCosts)
    }
    private func requestCosts(force: Bool = false) {
        guard polling, needsCostSnapshot,
              costLaunchID == nil, !costs.isLoading else { return }
        if !force, let costAttemptAt, Date().timeIntervalSince(costAttemptAt) < 90 { return }
        costAttemptAt = Date()
        let ticket = UUID()
        costLaunchID = ticket
        Task {
            guard costLaunchID == ticket else { return }
            defer { if costLaunchID == ticket { costLaunchID = nil } }
            await loadCosts()
        }
    }
    private func loadCosts() async {
        guard let generation = session?.generation else { return }
        await costs.load(isCurrent: { polling && generation == model.sessionGeneration }) { try await model.dashboardCostSnapshot() }
    }
    private func loadTrend() async {
        guard !trend.isLoading, let generation = session?.generation else { return }
        await trend.load(isCurrent: { polling && generation == model.sessionGeneration }) { try await model.dashboardTrend() }
    }
    private func loadMonitoring() async {
        guard !monitoring.isLoading, let generation = session?.generation else { return }
        await monitoring.load(isCurrent: { polling && generation == model.sessionGeneration }) { try await model.dashboardMonitoring() }
    }
}
