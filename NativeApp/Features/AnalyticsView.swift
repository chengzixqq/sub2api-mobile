import SwiftUI
import Charts
import Sub2Core

struct AnalyticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var query: AnalyticsQuery
    @State private var lastQuery: AnalyticsQuery?
    @State private var filters = false
    @State private var summary = DashboardLoadState<AnalyticsSummary>()
    @State private var trend = DashboardLoadState<[TrendPoint]>()
    @State private var models = DashboardLoadState<[AnalyticsBreakdown]>()
    @State private var groups = DashboardLoadState<[AnalyticsBreakdown]>()

    init(accountID: Int? = nil, groupID: Int? = nil) {
        let now = Date()
        _query = State(initialValue: AnalyticsQuery(start: Calendar.current.startOfDay(for: now), end: now, accountID: accountID, groupID: groupID))
    }

    var body: some View {
        List {
            Section {
                Text("\(query.start.formatted(date: .abbreviated, time: .shortened)) — \(query.end.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote).accessibilityIdentifier("analytics.range")
                if let id = query.accountID { Text("账号 #\(id)") }
                if let id = query.groupID { Text("分组 #\(id)") }
                if let id = query.userID { Text("用户 #\(id)") }
                if !query.model.isEmpty { Text("模型：\(query.model)") }
                HStack {
                    ForEach(["今日", "近7天", "本月"], id: \.self) { title in
                        Button(title) { applyPreset(title) }.buttonStyle(.bordered).accessibilityIdentifier("analytics.preset.\(title)")
                    }
                }
                Button("时间与筛选", systemImage: "line.3.horizontal.decrease") { filters = true }
                    .accessibilityIdentifier("analytics.filters")
                Text("下拉刷新上方固定范围；点今日、近7天或本月可更新截止时间至现在。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("统计汇总") {
                if let value = summary.value {
                    LabeledValue(label: "请求数", value: value.requests.formatted())
                    LabeledValue(label: "总 Tokens", value: DashboardPresentation.compactNumber(value.tokens))
                    LabeledValue(label: "输入 Tokens", value: value.inputTokens.map { DashboardPresentation.compactNumber($0) } ?? "不可用")
                    LabeledValue(label: "输出 Tokens", value: value.outputTokens.map { DashboardPresentation.compactNumber($0) } ?? "不可用")
                    LabeledValue(label: "缓存 Tokens", value: value.cacheTokens.map { DashboardPresentation.compactNumber($0) } ?? "不可用")
                    LabeledValue(label: "实际扣费", value: DashboardPresentation.money(value.actualCost)).foregroundStyle(.green)
                    LabeledValue(label: "上游成本", value: DashboardPresentation.money(value.accountCost)).foregroundStyle(.orange)
                    LabeledValue(label: "扣费与成本差额", value: DashboardPresentation.money(value.difference))
                        .accessibilityIdentifier("analytics.difference")
                    LabeledValue(label: "平均响应", value: DashboardPresentation.duration(value.averageDurationMs))
                    Text("差额仅为实际扣费减上游成本，未包含服务器等其他费用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                loadStatus(summary) { Task { await loadSummary() } }
            }
            Section("实际消费趋势") {
                if let points = trend.value {
                    if points.isEmpty { Text("该范围暂无请求记录") }
                    else {
                        if points.allSatisfy({ $0.actualCost == nil }) {
                            Text("站点未提供该范围的实际消费，明细保留请求与 Token 数；未以标准费用代替。")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if points.contains(where: { $0.actualCost == nil }) {
                            Text("部分时段的实际消费不可用，图表只绘制已返回的金额。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Chart(points) { point in
                            if let cost = point.actualCost {
                                BarMark(x: .value("时间", point.date), y: .value("实际扣费", NSDecimalNumber(decimal: cost).doubleValue))
                                    .foregroundStyle(.green)
                            }
                        }
                        .chartScrollableAxes(.horizontal)
                        .chartXVisibleDomain(length: min(10, max(1, points.count)))
                        .frame(height: 190).accessibilityIdentifier("analytics.chart")
                        NavigationLink("\(query.hourly ? "逐小时" : "逐日")明细") {
                            List(points.reversed()) { point in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(point.date).font(.headline)
                                    Text("实际 \(DashboardPresentation.money(point.actualCost)) · \(point.requests) 请求 · \(DashboardPresentation.compactNumber(point.totalTokens)) Tokens")
                                        .font(.subheadline).textSelection(.enabled)
                                }
                            }.navigationTitle("消费明细")
                        }
                    }
                }
                loadStatus(trend) { Task { await loadTrend() } }
            }
            breakdownSection("模型统计", state: models) { Task { await loadModels() } }
            breakdownSection("分组统计", state: groups) { Task { await loadGroups() } }
        }
        .navigationTitle("统计分析")
        .refreshable { await refresh() }
        .sheet(isPresented: $filters) { AnalyticsFilterView(initial: query) { query = $0 } }
        .task(id: query) {
            cancel()
            if lastQuery != query {
                summary = DashboardLoadState(); trend = DashboardLoadState()
                models = DashboardLoadState(); groups = DashboardLoadState()
                lastQuery = query
            }
            await refresh()
        }
        .onDisappear { cancel() }
    }

    private func applyPreset(_ preset: String) {
        let now = Date(); let calendar = Calendar.current
        query.end = now
        query.start = preset == "本月" ? (calendar.dateInterval(of: .month, for: now)?.start ?? now) :
            calendar.date(byAdding: .day, value: preset == "近7天" ? -6 : 0, to: calendar.startOfDay(for: now))!
    }
    private func cancel() { summary.cancel(); trend.cancel(); models.cancel(); groups.cancel() }
    private func refresh() async {
        async let a: Void = loadSummary()
        async let b: Void = loadTrend()
        async let c: Void = loadModels()
        async let d: Void = loadGroups()
        _ = await (a, b, c, d)
    }
    private func load<T: Sendable>(_ state: DashboardLoadState<T>, fixture: @escaping @MainActor @Sendable () throws -> T,
                                   operation: @escaping @MainActor @Sendable (APIClient, AnalyticsQuery) async throws -> T) async {
        guard !state.isLoading, let session else { return }
        let selected = query
        await state.load(isCurrent: { session.generation == model.sessionGeneration && query == selected }) {
            if model.isUITesting { return try fixture() }
            return try await operation(session.client, selected)
        }
    }
    private func loadSummary() async {
        await load(summary, fixture: { try JSONDecoder().decode(AnalyticsSummary.self, from: Data(#"{"total_requests":125,"total_tokens":1250000,"total_input_tokens":1000000,"total_output_tokens":250000,"total_cache_tokens":600000,"total_actual_cost":"12.34","total_account_cost":"5.67","average_duration_ms":1200}"#.utf8)) }) { try await $0.usageAnalysis($1) }
    }
    private func loadTrend() async {
        await load(trend, fixture: { [TrendPoint(date: "2026-10-16 09:00", requests: 100, totalTokens: 1000000, cost: 25, actualCost: Decimal(string: "10.10"))] }) { try await $0.usageAnalysisTrend($1) }
    }
    private func loadModels() async {
        await load(models, fixture: { try JSONDecoder().decode([AnalyticsBreakdown].self, from: Data(#"[{"model":"gpt-5","requests":125,"total_tokens":1250000,"actual_cost":"12.34","account_cost":"5.67"}]"#.utf8)) }) { try await $0.usageAnalysisModels($1) }
    }
    private func loadGroups() async {
        await load(groups, fixture: { try JSONDecoder().decode([AnalyticsBreakdown].self, from: Data(#"[{"group_id":1,"group_name":"默认分组","requests":125,"total_tokens":1250000,"actual_cost":"12.34","account_cost":"5.67"}]"#.utf8)) }) { try await $0.usageAnalysisGroups($1) }
    }
    @ViewBuilder private func loadStatus<T>(_ state: DashboardLoadState<T>, retry: @escaping () -> Void) -> some View {
        if state.isLoading { ProgressView("正在独立加载…") }
        if let error = state.error { Text(error).foregroundStyle(.red); Button("重试本项", action: retry) }
        if let date = state.updatedAt { Text("更新于 \(date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
    }
    private func breakdownSection(_ title: String, state: DashboardLoadState<[AnalyticsBreakdown]>, retry: @escaping () -> Void) -> some View {
        Section(title) {
            if let values = state.value {
                if values.isEmpty { Text("暂无数据") }
                ForEach(values.sorted { ($0.actualCost ?? -1) > ($1.actualCost ?? -1) }) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name).font(.headline)
                        Text("\(item.requests) 请求 · \(DashboardPresentation.compactNumber(item.tokens)) Tokens").font(.subheadline)
                        Text("扣费 \(DashboardPresentation.money(item.actualCost))").foregroundStyle(.green)
                        Text("成本 \(DashboardPresentation.money(item.accountCost)) · 差额 \(DashboardPresentation.money(item.difference))")
                            .foregroundStyle(.secondary)
                    }.font(.footnote).padding(.vertical, 3).textSelection(.enabled)
                }
            }
            loadStatus(state, retry: retry)
        }
    }
}

private struct AnalyticsFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AnalyticsQuery
    @State private var account: String
    @State private var group: String
    @State private var user: String
    @State private var error: String?
    let apply: (AnalyticsQuery) -> Void
    init(initial: AnalyticsQuery, apply: @escaping (AnalyticsQuery) -> Void) {
        _draft = State(initialValue: initial); _account = State(initialValue: initial.accountID.map(String.init) ?? "")
        _group = State(initialValue: initial.groupID.map(String.init) ?? ""); _user = State(initialValue: initial.userID.map(String.init) ?? "")
        self.apply = apply
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("时间范围") {
                    DatePicker("开始", selection: $draft.start)
                    DatePicker("结束（不含）", selection: $draft.end)
                    Text("按设备时区统计，支持一年内自定义范围。").font(.caption)
                }
                Section("筛选（留空代表全部）") {
                    TextField("账号 ID", text: $account).keyboardType(.numberPad)
                    TextField("分组 ID", text: $group).keyboardType(.numberPad)
                    TextField("用户 ID", text: $user).keyboardType(.numberPad)
                    TextField("模型名称", text: $draft.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("统计筛选")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("应用") {
                            do {
                                draft.accountID = try id(account); draft.groupID = try id(group); draft.userID = try id(user)
                                _ = try draft.queryItems(); apply(draft); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("analytics.filters.apply")
                    }
                }
        }
    }
    private func id(_ text: String) throws -> Int? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard let value = Int(text), value > 0 else { throw AppFailure("ID 必须是正整数。") }
        return value
    }
}
