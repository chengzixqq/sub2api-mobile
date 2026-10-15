import SwiftUI
import Charts
import Sub2Core

/// Created only when the fourth trend tab is selected. Historical throughput
/// can be expensive, so it has its own foreground request and cancellation.
struct PerformanceTrendView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var history = DashboardLoadState<PerformanceTrend>()
    @State private var hours = 1
    @State private var metric = PerformanceMetric.rpm
    @State private var selectedDate: Date?
    @State private var showingDetails = false
    @State private var visible = false
    private var polling: Bool { visible && scenePhase == .active }
    private var taskID: String { "\(polling)-\(hours)" }

    var body: some View {
        let shouldPoll = polling
        let requestedHours = hours
        VStack(alignment: .leading, spacing: 12) {
            Picker("性能时间范围", selection: $hours) {
                Text("近 1 小时").tag(1); Text("近 6 小时").tag(6); Text("近 24 小时").tag(24)
            }.pickerStyle(.segmented).accessibilityIdentifier("dashboard.performance.range")
            Picker("性能指标", selection: $metric) {
                ForEach(PerformanceMetric.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("dashboard.performance.metric")
            if let value = history.value {
                if value.points.isEmpty { Text("此时间范围暂无性能数据").foregroundStyle(.secondary) }
                else {
                    performanceChart(value)
                    Text("每桶 \(value.bucket.label)平均速率；RPM 含成功请求和错误请求，TPM 为成功请求的含缓存 Tokens。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let selected = selected(value) {
                        Text("\(dateLabel(selected.date)) · \(metric.rawValue) \(rateLabel(value, selected))")
                            .font(.subheadline.monospacedDigit()).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("dashboard.performance.selection")
                    }
                    Button("性能明细") { showingDetails = true }
                        .buttonStyle(.bordered).accessibilityIdentifier("dashboard.performance.details")
                }
            }
            if history.isLoading {
                ProgressView("正在加载性能趋势…").accessibilityIdentifier("dashboard.performance.loading")
            }
            if let error = history.error {
                Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("dashboard.performance.error")
                Text("站点需启用运行监控并支持吞吐趋势接口。其他概览数据可继续查看。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("刷新性能") { Task { await load() } }
                .disabled(history.isLoading).accessibilityIdentifier("dashboard.performance.reload")
            if let date = history.updatedAt {
                Text("性能更新于 \(date.formatted(date: .omitted, time: .standard)) · 前台每 30 秒刷新")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; history.cancel() }
        .onChange(of: hours) { _, _ in history.cancel(); history.value = nil; history.updatedAt = nil; selectedDate = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { history.cancel() } }
        .task(id: taskID) {
            guard shouldPoll, hours == requestedHours else { return }
            while !Task.isCancelled {
                if !history.isLoading { await load() }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                List(history.value?.newestFirst ?? []) { point in
                    Button {
                        selectedDate = point.date; showingDetails = false
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(dateLabel(point.date)).font(.caption).foregroundStyle(.secondary)
                            if let value = history.value {
                                Text("RPM \(DashboardPresentation.compactNumber(value.rate(point, metric: .rpm))) · TPM \(DashboardPresentation.compactNumber(value.rate(point, metric: .tpm)))")
                                    .font(.body.monospacedDigit()).foregroundStyle(.primary)
                            }
                        }
                    }.accessibilityIdentifier("dashboard.performance.row.\(point.requestCount)")
                }.navigationTitle("性能明细 · 最新在上")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingDetails = false } } }
            }
        }
    }

    private func performanceChart(_ value: PerformanceTrend) -> some View {
        Chart {
            ForEach(value.points) { point in
                LineMark(x: .value("时间", point.date), y: .value(metric.rawValue, value.rate(point, metric: metric)))
                    .foregroundStyle(metric == .rpm ? Color.blue : Color.purple)
                    .accessibilityLabel(dateLabel(point.date))
                    .accessibilityValue("\(rateLabel(value, point)) \(metric.rawValue)")
            }
            if let point = selected(value) {
                RuleMark(x: .value("选中时间", point.date)).foregroundStyle(.secondary.opacity(0.5))
                PointMark(x: .value("选中时间", point.date), y: .value(metric.rawValue, value.rate(point, metric: metric)))
                    .foregroundStyle(Color.primary)
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in
            AxisGridLine(); AxisValueLabel {
                if let date = value.as(Date.self) { Text(dateLabel(date).replacingOccurrences(of: " ", with: "\n")).font(.caption2) }
            }
        } }
        .chartYAxis { AxisMarks(position: .leading) { value in
            AxisGridLine(); AxisValueLabel {
                if let number = value.as(Double.self) { Text(DashboardPresentation.compactNumber(number)).font(.caption2) }
            }
        } }
        .frame(height: 230).accessibilityLabel("\(metric.rawValue) 性能趋势")
        .accessibilityIdentifier("dashboard.performance.chart")
    }
    private func selected(_ value: PerformanceTrend) -> PerformanceTrend.Point? {
        guard let selectedDate else { return nil }
        return value.points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private func dateLabel(_ date: Date) -> String { DashboardPresentation.trendAxisLabel(date, hourly: true) }
    private func rateLabel(_ value: PerformanceTrend, _ point: PerformanceTrend.Point) -> String {
        DashboardPresentation.compactNumber(value.rate(point, metric: metric))
    }
    private func load() async {
        guard !history.isLoading, let generation = session?.generation else { return }
        let requestedHours = hours
        await history.load(isCurrent: { polling && hours == requestedHours && generation == model.sessionGeneration }) {
            try await model.dashboardPerformanceTrend(hours: requestedHours)
        }
    }
}
