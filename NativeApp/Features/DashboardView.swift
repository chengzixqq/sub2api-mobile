import SwiftUI
import Observation
import Charts
import Sub2Core

// A cancelled or late request cannot replace a newer foreground load.
@MainActor @Observable
private final class DashboardLoadState<Value: Sendable> {
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

/// Native iOS 17 chart scrolling and selection keep horizontal panning separate
/// from a tap; magnification and the buttons change the same visible time window.
private struct DashboardTrendChart: View {
    let series: DashboardTrendSeries
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
    private var showBarValues: Bool { zoom >= maximumZoom || span <= bucketSeconds * 4 }
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
        if showBarValues { return visible.map(\.date) }
        return Array(Set([first.date, visible[visible.count / 2].date, last.date])).sorted()
    }
    private var yDomain: ClosedRange<Double> {
        let values = series.samples.compactMap { metric.plotValue($0.point) }
        let lower = min(0, values.min() ?? 0)
        let upper = max(0, values.max() ?? 0)
        return lower...max(lower + 0.001, upper == 0 ? 1 : upper * 1.25)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("趋势指标", selection: $metric) {
                ForEach(DashboardTrendMetric.allCases) { metric in Text(metric.label).tag(metric) }
            }.pickerStyle(.segmented).accessibilityIdentifier("dashboard.trend.metric")

            if series.samples.isEmpty {
                Text("趋势时间格式无法识别，请在网页查看。")
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
                        Text(exactLabel(sample)).font(.headline).monospacedDigit().textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("dashboard.trend.selection")
                } else {
                    Text("点选柱子查看精确数值；放大后可左右滑动，双指缩放或使用按钮调整。")
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
            Button { changeZoom(zoom / 2) } label: { Image(systemName: "minus.magnifyingglass").frame(minWidth: 40, minHeight: 40) }
                .accessibilityLabel("缩小趋势").accessibilityIdentifier("dashboard.trend.zoom-out").disabled(zoom <= 1)
            Spacer(minLength: 2)
            Text("放大 \(zoom.formatted(.number.precision(.fractionLength(0...1))))×")
                .font(.subheadline).monospacedDigit().accessibilityIdentifier("dashboard.trend.zoom-level")
            Spacer(minLength: 2)
            Button { changeZoom(zoom * 2) } label: { Image(systemName: "plus.magnifyingglass").frame(minWidth: 40, minHeight: 40) }
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
                                Text(metric.exactValue(sample.point)).font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        .accessibilityLabel(dateLabel(sample.date))
                        .accessibilityValue(exactLabel(sample))
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
        .chartXVisibleDomain(length: visibleDuration)
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
                        Text(metric == .actualCost ? DashboardPresentation.cost(Decimal(value)) : DashboardPresentation.compactNumber(value))
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
            List(series.samples) { sample in
                Button {
                    selectedDate = sample.date.addingTimeInterval(bucketSeconds / 2)
                    scrollDate = clampedStart(sample.date, duration: visibleDuration)
                    showingDetails = false
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(dateLabel(sample.date)).font(.subheadline).foregroundStyle(.secondary)
                        Text(exactLabel(sample)).font(.body.monospacedDigit()).foregroundStyle(.primary)
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
    private func exactLabel(_ sample: DashboardTrendSample) -> String {
        metric.exactValue(sample.point) + (metric == .actualCost ? "" : " " + metric.unit)
    }
    private func dateLabel(_ date: Date) -> String { DashboardPresentation.trendAxisLabel(date, hourly: series.isHourly) }
    private func clampedStart(_ date: Date, duration: TimeInterval) -> Date {
        min(max(firstDate, date), max(firstDate, endDate.addingTimeInterval(-duration)))
    }
    private func changeZoom(_ next: Double) {
        let center = visibleStart.addingTimeInterval(visibleDuration / 2)
        zoom = DashboardTrend.clampedZoom(next, maximum: maximumZoom)
        scrollDate = clampedStart(center.addingTimeInterval(-visibleDuration / 2), duration: visibleDuration)
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], spacing: 12) {
                        MetricView(title: "今日请求", value: summary.stats.todayRequests.formatted(), symbol: "arrow.left.arrow.right")
                            .accessibilityIdentifier("dashboard.today-requests")
                        MetricView(title: "今日 Tokens", value: DashboardPresentation.compactNumber(summary.stats.todayTokens), symbol: "text.alignleft")
                            .accessibilityIdentifier("dashboard.today-tokens")
                        MetricView(title: "今日实际费用", value: DashboardPresentation.cost(currentCostSnapshot?.actual ?? summary.stats.todayActualCost), symbol: "dollarsign.circle")
                            .accessibilityIdentifier("dashboard.today-actual-cost")
                        MetricView(title: "今日账号成本", value: DashboardPresentation.cost(summary.stats.todayAccountCost ?? currentCostSnapshot?.account), symbol: "creditcard")
                            .accessibilityIdentifier("dashboard.today-account-cost")
                        MetricView(title: "总 Tokens", value: summary.stats.totalTokens.map { DashboardPresentation.compactNumber($0) } ?? "不可用", symbol: "sum")
                            .accessibilityIdentifier("dashboard.total-tokens")
                        performanceCard(summary.stats)
                    }.accessibilityIdentifier("dashboard.metrics")
                }
                if stats.isLoading {
                    ProgressView(stats.value == nil ? "正在加载基础统计…" : "正在更新基础统计…")
                        .frame(maxWidth: .infinity).padding()
                    if stats.value == nil {
                        Text("大站点首次统计可能较慢，请稍候。趋势与监控可单独加载。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                sectionError(stats.error, identifier: "dashboard.stats.error") { Task { await loadStats() } }
                if let date = stats.updatedAt {
                    Text("基础统计更新于 \(date.formatted(date: .omitted, time: .standard)) · 前台每 30 秒刷新")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if stats.value != nil {
                    Text("实际费用为用户扣费，账号成本为上游成本；均按站点的今日统计。")
                        .font(.caption).foregroundStyle(.secondary)
                    if stats.value?.stats.todayAccountCost == nil {
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
                GroupBox("用量趋势") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("昨日以来的小时趋势，按需加载。")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let points = trend.value {
                            if points.isEmpty { Text("暂无趋势数据").foregroundStyle(.secondary) }
                            else {
                                DashboardTrendChart(points: points)
                            }
                        }
                        sectionError(trend.error, identifier: "dashboard.trend.error") { Task { await loadTrend() } }
                        if trend.isLoading { ProgressView("正在加载趋势…") }
                        Button(trend.value == nil ? "加载趋势" : "刷新趋势") { Task { await loadTrend() } }
                            .accessibilityIdentifier("dashboard.trend.load").disabled(trend.isLoading)
                        if let date = trend.updatedAt { lastUpdated(date) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
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
                            LabeledValue(label: "QPS", value: snapshot.qps.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "不可用")
                            LabeledValue(label: "活跃请求", value: snapshot.activeRequests.map(String.init) ?? "不可用")
                        } else {
                            Text("详细运行监控按需加载。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        sectionError(monitoring.error, identifier: "dashboard.monitoring.error") { Task { await loadMonitoring() } }
                        if monitoring.isLoading { ProgressView("正在加载监控…") }
                        Button(monitoring.value == nil ? "加载监控" : "刷新监控") { Task { await loadMonitoring() } }
                            .accessibilityIdentifier("dashboard.monitoring.load").disabled(monitoring.isLoading)
                        if let date = monitoring.updatedAt { lastUpdated(date) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }.padding().frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(model.activeProfile?.name ?? "概览")
        .refreshable { await loadStats(forceCosts: true) }
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
    private func performanceCard(_ stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("性能指标", systemImage: "bolt.fill").font(.subheadline).foregroundStyle(.secondary)
            performanceLine(DashboardPresentation.compactNumber(stats.rpm), unit: "RPM", prominent: true)
                .accessibilityIdentifier("dashboard.performance.rpm")
            performanceLine(DashboardPresentation.compactNumber(stats.tpm), unit: "TPM", prominent: false)
                .accessibilityIdentifier("dashboard.performance.tpm")
            Text("最近 5 分钟平均").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 85, alignment: .leading).padding()
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
    private var currentCostSnapshot: DashboardCostSnapshot? {
        guard stats.value?.stats.todayAccountCost == nil,
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
        guard polling, stats.value != nil, stats.value?.stats.todayAccountCost == nil,
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
        guard let generation = session?.generation else { return }
        await trend.load(isCurrent: { polling && generation == model.sessionGeneration }) { try await model.dashboardTrend() }
    }
    private func loadMonitoring() async {
        guard let generation = session?.generation else { return }
        await monitoring.load(isCurrent: { polling && generation == model.sessionGeneration }) { try await model.dashboardMonitoring() }
    }
}
