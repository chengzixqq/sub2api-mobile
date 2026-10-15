import SwiftUI
import Charts
import Sub2Core

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var summary: DashboardSummary?
    @State private var error: String?
    @State private var loading = false
    @State private var visible = false
    @State private var updatedAt: Date?
    private var polling: Bool { visible && scenePhase == .active }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let summary {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], spacing: 12) {
                        MetricView(title: "今日请求", value: summary.stats.todayRequests.formatted(), symbol: "arrow.left.arrow.right")
                        MetricView(title: "今日 Tokens", value: summary.stats.todayTokens.formatted(), symbol: "text.alignleft")
                        MetricView(title: "今日费用", value: money(summary.stats.todayCost), symbol: "dollarsign.circle")
                        MetricView(title: "异常账号", value: summary.stats.errorAccounts.formatted(), symbol: "exclamationmark.triangle")
                    }.accessibilityIdentifier("dashboard.metrics")
                    GroupBox("请求趋势") {
                        if summary.trend.isEmpty { Text("暂无趋势数据").foregroundStyle(.secondary).frame(height: 160) }
                        else {
                            Chart(summary.trend) { point in
                                BarMark(x: .value("日期", point.date), y: .value("请求", point.requests)).foregroundStyle(.indigo.gradient)
                            }.frame(height: 200).padding(.top, 10).accessibilityLabel("每日请求趋势")
                        }
                    }
                    GroupBox("运行监控") {
                        VStack {
                            LabeledValue(label: "每分钟请求", value: summary.stats.rpm.formatted(.number.precision(.fractionLength(0...2))))
                            LabeledValue(label: "每分钟 Tokens", value: summary.stats.tpm.formatted(.number.precision(.fractionLength(0...2))))
                            if let monitoring = summary.monitoring {
                                LabeledValue(label: "错误率", value: monitoring.errorRate.map { ($0 * 100).formatted(.number.precision(.fractionLength(0...2))) + "%" } ?? "不可用")
                                LabeledValue(label: "QPS", value: monitoring.qps.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "不可用")
                                LabeledValue(label: "活跃请求", value: monitoring.activeRequests.map(String.init) ?? "不可用")
                            } else { Text("运行监控暂不可用；概览数据仍可使用。").font(.footnote).foregroundStyle(.secondary).padding(.top) }
                            Divider()
                            LabeledValue(label: "用户总数", value: summary.stats.totalUsers.formatted())
                            LabeledValue(label: "账号总数", value: summary.stats.totalAccounts.formatted())
                        }.padding(.top, 8)
                    }
                } else if loading { ProgressView("正在加载概览…").frame(maxWidth: .infinity).padding(60) }
                if let error { FailureView(message: error) { Task { await load() } }.frame(minHeight: 200) }
                if let updatedAt {
                    Text("更新于 \(updatedAt.formatted(date: .omitted, time: .standard)) · 前台每 30 秒刷新")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding().frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(model.activeProfile?.name ?? "概览")
        .refreshable { await load() }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .task(id: polling) {
            guard polling else { return }
            while !Task.isCancelled {
                await load()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
    private func load() async {
        guard !loading else { return }
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await model.dashboard()
            guard generation == model.sessionGeneration, !Task.isCancelled else { return }
            summary = result; error = nil; updatedAt = Date()
        } catch { if generation == model.sessionGeneration, !(error is CancellationError) { self.error = error.localizedDescription } }
    }
}
