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
                        MetricView(title: "异常账号", value: summary.stats.errorAccounts.formatted(), symbol: "exclamationmark.triangle")
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
                    GroupBox("性能指标") {
                        VStack(spacing: 8) {
                            Text("RPM / TPM 为最近 5 分钟平均值。")
                                .font(.caption).foregroundStyle(.secondary)
                            LabeledValue(label: "RPM · 每分钟请求", value: DashboardPresentation.compactNumber(summary.stats.rpm) + " RPM")
                                .accessibilityElement(children: .combine).accessibilityIdentifier("dashboard.performance.rpm")
                            LabeledValue(label: "TPM · 每分钟 Tokens", value: DashboardPresentation.compactNumber(summary.stats.tpm) + " TPM")
                                .accessibilityElement(children: .combine).accessibilityIdentifier("dashboard.performance.tpm")
                            LabeledValue(label: "平均响应时间", value: DashboardPresentation.duration(summary.stats.averageDurationMs))
                                .accessibilityElement(children: .combine).accessibilityIdentifier("dashboard.performance.duration")
                        }.padding(.top, 8)
                    }
                }
                GroupBox("请求趋势") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("昨日以来的小时趋势，按需加载。")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let points = trend.value {
                            if points.isEmpty { Text("暂无趋势数据").foregroundStyle(.secondary) }
                            else {
                                requestChart(points)
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
    private struct DatedPoint: Identifiable {
        let date: Date
        let requests: Int
        var id: Date { date }
    }
    @ViewBuilder private func requestChart(_ points: [TrendPoint]) -> some View {
        let dated = points.compactMap { point in
            DashboardPresentation.trendDate(point.date).map { DatedPoint(date: $0, requests: point.requests) }
        }.sorted { $0.date < $1.date }
        let hourly = points.contains { $0.date.contains(":") }
        if let first = dated.first, let last = dated.last {
            let ticks = Array(Set([first.date, dated[dated.count / 2].date, last.date])).sorted()
            let range = DashboardPresentation.trendAxisLabel(first.date, hourly: hourly) + " — " + DashboardPresentation.trendAxisLabel(last.date, hourly: hourly)
            VStack(alignment: .leading, spacing: 8) {
                Chart(dated) { point in
                    BarMark(x: .value("时间", point.date, unit: hourly ? .hour : .day), y: .value("请求", point.requests), width: .ratio(0.8))
                        .foregroundStyle(.indigo.gradient)
                }
                .chartXAxis {
                    AxisMarks(values: ticks) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(DashboardPresentation.trendAxisLabel(date, hourly: hourly).replacingOccurrences(of: " ", with: "\n"))
                                    .font(.caption2).multilineTextAlignment(.center).fixedSize()
                            }
                        }
                    }
                }
                .chartXScale(range: .plotDimension(startPadding: 28, endPadding: 28))
                .frame(height: 220).accessibilityLabel(hourly ? "每小时请求趋势" : "每日请求趋势")
                .accessibilityIdentifier("dashboard.trend.chart")
                Text(range).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("dashboard.trend.range")
                if dated.count != points.count {
                    Text("部分时间点无法解析，未绘入图表。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("趋势时间格式无法识别，请在网页查看。")
                .font(.footnote).foregroundStyle(.secondary)
        }
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
