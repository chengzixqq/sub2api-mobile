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
    @State private var trend = DashboardLoadState<[TrendPoint]>()
    @State private var monitoring = DashboardLoadState<OpsSnapshot>()
    @State private var visible = false
    private var polling: Bool { visible && scenePhase == .active }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let summary = stats.value {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], spacing: 12) {
                        MetricView(title: "今日请求", value: summary.stats.todayRequests.formatted(), symbol: "arrow.left.arrow.right")
                            .accessibilityIdentifier("dashboard.today-requests")
                        MetricView(title: "今日 Tokens", value: summary.stats.todayTokens.formatted(), symbol: "text.alignleft")
                        MetricView(title: "今日费用", value: money(summary.stats.todayCost), symbol: "dollarsign.circle")
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
                GroupBox("请求趋势") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("昨日以来的小时趋势，按需加载。")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let points = trend.value {
                            if points.isEmpty { Text("暂无趋势数据").foregroundStyle(.secondary) }
                            else {
                                Chart(points) { point in
                                    BarMark(x: .value("时间", point.date), y: .value("请求", point.requests))
                                        .foregroundStyle(.indigo.gradient)
                                }.frame(height: 200).accessibilityLabel("每小时请求趋势")
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
                            LabeledValue(label: "每分钟请求", value: summary.stats.rpm.formatted(.number.precision(.fractionLength(0...2))))
                            LabeledValue(label: "每分钟 Tokens", value: summary.stats.tpm.formatted(.number.precision(.fractionLength(0...2))))
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
        .refreshable { await loadStats() }
        .onAppear { visible = true }
        .onDisappear { visible = false; cancelLoads() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelLoads() } }
        .task(id: polling) {
            guard polling else { return }
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
    private func cancelLoads() { stats.cancel(); trend.cancel(); monitoring.cancel() }
    private func loadStats() async {
        guard let generation = session?.generation else { return }
        await stats.load(isCurrent: { generation == model.sessionGeneration }) { try await model.dashboard() }
    }
    private func loadTrend() async {
        guard let generation = session?.generation else { return }
        await trend.load(isCurrent: { generation == model.sessionGeneration }) { try await model.dashboardTrend() }
    }
    private func loadMonitoring() async {
        guard let generation = session?.generation else { return }
        await monitoring.load(isCurrent: { generation == model.sessionGeneration }) { try await model.dashboardMonitoring() }
    }
}
