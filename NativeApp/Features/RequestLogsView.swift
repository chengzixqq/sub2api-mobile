import SwiftUI
import Sub2Core

/// The old usage detail, reached by `.request(.usage)` until S4-08 (S4-08b deletes this file).
struct UsageRequestDetailView: View {
    let record: UsageRequestRecord
    var body: some View {
        List {
            Section("请求") {
                LabeledValue(label: "时间", value: RequestLogPresentation.date(record.createdAt))
                LabeledValue(label: "模型", value: record.model)
                if let upstream = record.upstreamModel { LabeledValue(label: "上游模型", value: upstream) }
                LabeledValue(label: "类型", value: record.requestType ?? (record.stream == true ? "stream" : DisplayFormat.missing))
                LabeledValue(label: "请求 ID", value: record.requestID).textSelection(.enabled)
                if let id = record.upstreamRequestID { LabeledValue(label: "上游请求 ID", value: id).textSelection(.enabled) }
                if let endpoint = record.inboundEndpoint { LabeledValue(label: "请求入口", value: endpoint) }
            }
            Section("扣费与成本") {
                LabeledValue(label: "实际扣费", value: DisplayFormat.money(record.actualCost, digits: 4)).accessibilityIdentifier("logs.detail.charge")
                LabeledValue(label: "上游成本", value: DisplayFormat.money(record.accountCost, digits: 4)).accessibilityIdentifier("logs.detail.cost")
                LabeledValue(label: "标准费用", value: DisplayFormat.money(record.standardCost, digits: 4))
                if let actual = record.actualCost, let cost = record.accountCost { LabeledValue(label: "差额", value: DisplayFormat.money(actual - cost, digits: 4)) }
                Text("成本使用该记录保存的定价与账号倍率快照。金额按四位小数显示，不改变原始精度。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Token 与延迟") {
                LabeledValue(label: "输入", value: DisplayFormat.compact(record.inputTokens))
                LabeledValue(label: "输出", value: DisplayFormat.compact(record.outputTokens))
                LabeledValue(label: "缓存创建", value: DisplayFormat.compact(record.cacheCreationTokens))
                LabeledValue(label: "缓存读取", value: DisplayFormat.compact(record.cacheReadTokens))
                LabeledValue(label: "总耗时", value: DisplayFormat.duration(record.durationMs, style: .list))
                LabeledValue(label: "首 Token", value: DisplayFormat.duration(record.firstTokenMs, style: .list))
            }
            Section("关联对象") {
                LabeledValue(label: "用户", value: record.userEmail ?? "#\(record.userID)")
                LabeledValue(label: "API Key ID", value: String(record.apiKeyID))
                NavigationLink("查看账号 \(record.accountName ?? "#\(record.accountID)")") { AccountDestination(id: record.accountID) }
                if let id = record.groupID { LabeledValue(label: "分组", value: record.groupName ?? "#\(id)") }
                NavigationLink("该账号全部请求记录") { RequestLogsView(accountID: record.accountID) }
            }
        }.navigationTitle("请求详情")
    }
}

/// The old error detail, reached by `.request(.error(…, initial:))` until S4-08; under `-ui-testing` it keeps the row it was given.
struct RequestErrorDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var record: RequestErrorRecord
    @State private var loading = false
    @State private var error: String?
    @State private var ticket = UUID()
    @State private var retryTask: Task<Void, Never>?
    let kind: ErrorLogKind
    init(initial: RequestErrorRecord, kind: ErrorLogKind) { _record = State(initialValue: initial); self.kind = kind }
    var body: some View {
        List {
            Section("错误") {
                LabeledValue(label: "HTTP 状态码", value: String(record.statusCode))
                LabeledValue(label: "阶段", value: record.phase)
                LabeledValue(label: "类型", value: record.type)
                LabeledValue(label: "处理状态", value: record.resolved ? "已处理" : "未处理")
                Text(record.message).textSelection(.enabled).accessibilityIdentifier("logs.detail.message")
                if let upstream = record.upstreamMessage, !upstream.isEmpty { Text(upstream).textSelection(.enabled) }
                if let status = record.upstreamStatusCode { LabeledValue(label: "上游状态码", value: String(status)) }
            }
            Section("请求上下文") {
                LabeledValue(label: "时间", value: RequestLogPresentation.date(record.createdAt))
                LabeledValue(label: "平台", value: record.platform)
                LabeledValue(label: "模型", value: record.model)
                if let upstream = record.upstreamModel, !upstream.isEmpty { LabeledValue(label: "上游模型", value: upstream) }
                LabeledValue(label: "请求 ID", value: record.requestID).textSelection(.enabled)
                if let id = record.userID { LabeledValue(label: "用户 ID", value: String(id)) }
                if let id = record.accountID, id > 0 { NavigationLink("查看账号 \(record.accountName ?? "#\(id)")") { AccountDestination(id: id) } }
                if let id = record.groupID { LabeledValue(label: "分组", value: record.groupName ?? "#\(id)") }
            }
            Section("延迟") {
                LabeledValue(label: "上游耗时", value: DisplayFormat.duration(record.upstreamLatencyMs, style: .millis))
                LabeledValue(label: "响应耗时", value: DisplayFormat.duration(record.responseLatencyMs, style: .millis))
                LabeledValue(label: "首 Token", value: DisplayFormat.duration(record.firstTokenMs, style: .list))
            }
            Section {
                if loading { ProgressView("正在读取详情…") }
                if let error { Text(error).foregroundStyle(.red); Button("重试") { retryTask = Task { await reload() } } }
                Text("仅展示错误摘要与指标，凭据及原始请求、响应正文不进入此页面。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("错误详情").task { await reload() }.refreshable { await reload() }
            .onChange(of: model.foregroundRevision) { _, _ in retryTask = Task { await reload() } }
            .onDisappear { ticket = UUID(); retryTask?.cancel(); retryTask = nil; loading = false }
    }
    private func reload() async {
        guard !loading, !model.isUITesting, let session else { return }
        loading = true; error = nil
        let id = UUID(); ticket = id
        let generation = session.generation
        defer { if ticket == id { loading = false } }
        do {
            let result = try await session.client.errorRecord(id: record.id, kind: kind)
            guard ticket == id, generation == model.sessionGeneration, !Task.isCancelled else { return }; record = result
        } catch { if ticket == id, generation == model.sessionGeneration, !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
