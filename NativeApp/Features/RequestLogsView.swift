import SwiftUI
import Sub2Core

struct RequestLogsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var filter: RequestLogFilter
    @State private var rollingLastDay = true
    @State private var mode = LogMode.requests
    @State private var records: [UsageRequestRecord] = []
    @State private var errors: [RequestErrorRecord] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var total: Int?
    @State private var loading = false
    @State private var failure: String?
    @State private var failedPage = 1
    @State private var updatedAt: Date?
    @State private var editingFilter = false
    @State private var revision = UUID()
    @State private var ticket = UUID()
    @State private var pendingTask: Task<Void, Never>?
    init(accountID: Int? = nil, groupID: Int? = nil) {
        _filter = State(initialValue: RequestLogFilter(accountID: accountID, groupID: groupID))
    }
    private var queryKey: String { mode.rawValue + revision.uuidString }
    private var effectiveFilter: RequestLogFilter { mode == .upstream ? filter.upstreamErrorFilter() : filter }
    var body: some View {
        List {
            Section {
                Picker("记录类型", selection: $mode) {
                    ForEach(LogMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("logs.mode")
                Text("\(filter.start.formatted(date: .abbreviated, time: .shortened)) — \(filter.end.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                if rollingLastDay {
                    Text("最近 24 小时；下拉刷新时更新至现在。")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("logs.range.rolling")
                } else {
                    Text("固定时间范围；下拉刷新保留以上起止时间。")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("logs.range.fixed")
                    Button("查看最新记录（近 24 小时）") {
                        rollingLastDay = true
                        advanceLastDay()
                        revision = UUID()
                    }.accessibilityIdentifier("logs.range.latest")
                }
                if let id = filter.accountID { Text("账号 #\(id)").font(.caption).accessibilityIdentifier("logs.account-filter") }
                if let id = filter.groupID { Text("分组 #\(id)").font(.caption) }
                if !effectiveFilter.model.isEmpty { Text("模型：\(effectiveFilter.model)").font(.caption) }
                if mode == .upstream { Text("上游错误按时间、账号、分组与状态筛选。用户、密钥和模型条件仅用于请求记录及失败请求。")
                    .font(.caption).foregroundStyle(.secondary) }
                if let updatedAt {
                    Text("已加载 \(mode == .requests ? records.count : errors.count) 条\(total.map { " / 共 \($0) 条" } ?? "") · 更新于 \(updatedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("logs.loaded")
                }
            }
            Section(mode.title) {
                if mode == .requests {
                    ForEach(records) { record in
                        NavigationLink { UsageRequestDetailView(record: record) } label: { requestRow(record) }
                            .accessibilityIdentifier("logs.request.\(record.id)")
                    }
                } else {
                    ForEach(errors) { record in
                        NavigationLink { RequestErrorDetailView(initial: record, kind: mode.errorKind) } label: { errorRow(record) }
                            .accessibilityIdentifier("logs.error.\(record.id)")
                    }
                }
                if loading { ProgressView("正在读取记录…") }
                if !loading && failure == nil && records.isEmpty && errors.isEmpty {
                    Text("当前条件下暂无记录").foregroundStyle(.secondary).accessibilityIdentifier("logs.empty")
                }
                if hasMore {
                    Button("加载更多记录") { beginLoad(page: page + 1) }
                        .disabled(loading).frame(minHeight: 44).accessibilityIdentifier("logs.more")
                }
                if let failure {
                    Text("\(failure)\(updatedAt == nil ? "" : "\n保留上次成功加载的记录。")")
                        .foregroundStyle(.red).accessibilityIdentifier("logs.error")
                    Button("重试") { beginLoad(page: failedPage) }.disabled(loading).frame(minHeight: 44)
                }
            }
            Section {
                Text(mode == .requests ? "请求记录按时间倒序。实际扣费与上游成本分别展示；按需翻页，无需等待全站总数。" : "失败请求是客户端可见错误；上游错误包含重试过程中恢复的上游异常。日志监控关闭时，站点可能无法提供错误记录。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("请求与错误日志")
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button("筛选", systemImage: "line.3.horizontal.decrease.circle") { editingFilter = true }
                .accessibilityIdentifier("logs.filter")
        } }
        .sheet(isPresented: $editingFilter) {
            RequestLogFilterEditor(initial: effectiveFilter, errors: mode != .requests, upstream: mode == .upstream) { value in
                filter = value; rollingLastDay = false; revision = UUID()
            }
        }
        .task(id: queryKey) {
            invalidate()
            records = []; errors = []; page = 0; total = nil; updatedAt = nil; hasMore = false; failure = nil
            await load(page: 1)
        }
        .refreshable {
            guard !loading else { return }
            if rollingLastDay { advanceLastDay() }
            await load(page: 1)
        }
        // A load cancelled by going to the background ends silently; reload on return (D18).
        .onChange(of: model.foregroundRevision) { _, _ in beginLoad(page: 1) }
        .onDisappear { invalidate() }
    }
    private func advanceLastDay() {
        let now = Date()
        filter.start = now.addingTimeInterval(-86_400)
        filter.end = now
    }
    private func requestRow(_ record: UsageRequestRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.model).font(.headline)
            Text(RequestLogPresentation.date(record.createdAt)).font(.caption).foregroundStyle(.secondary)
            Text("用户 #\(record.userID) · \(record.accountName ?? "账号 #\(record.accountID)")").font(.caption)
            HStack {
                Text("扣费 \(DisplayFormat.moneyLineItem(record.actualCost))").foregroundStyle(.green)
                Text("成本 \(DisplayFormat.moneyLineItem(record.accountCost))").foregroundStyle(.orange)
            }.font(.caption)
            Text("\(DisplayFormat.compact(record.totalTokens)) Token · \(DisplayFormat.duration(record.durationMs, style: .list))")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
    private func errorRow(_ record: RequestErrorRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text("HTTP \(record.statusCode)").foregroundStyle(.red); Text(record.model).lineLimit(1) }.font(.headline)
            Text(record.message).font(.subheadline).lineLimit(3)
            Text("\(RequestLogPresentation.date(record.createdAt)) · \(record.phase) · \(record.resolved ? "已处理" : "未处理")")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
    private func invalidate() {
        ticket = UUID(); pendingTask?.cancel(); pendingTask = nil; loading = false
    }
    private func beginLoad(page: Int) {
        guard !loading else { return }
        pendingTask = Task { await load(page: page) }
    }
    private func load(page requested: Int) async {
        guard !loading, let session, session.generation == model.sessionGeneration else { return }
        let id = UUID(); ticket = id; loading = true; failure = nil
        let query = effectiveFilter; let selected = mode; let generation = session.generation
        defer { if ticket == id { loading = false } }
        do {
            if selected == .requests {
                let result = try await (model.isUITesting ? LogFixtures.requests(page: requested, filter: query) : session.client.requestRecords(page: requested, filter: query))
                guard ticket == id, generation == model.sessionGeneration, effectiveFilter == query, mode == selected, !Task.isCancelled else { return }
                records = requested == 1 ? result.items : records + result.items.filter { next in !records.contains { $0.id == next.id } }
                page = result.page; hasMore = result.hasMore; total = result.totalExact ? result.total : nil
            } else {
                let result = try await (model.isUITesting ? LogFixtures.errors(page: requested, filter: query) : session.client.errorRecords(page: requested, filter: query, kind: selected.errorKind))
                guard ticket == id, generation == model.sessionGeneration, effectiveFilter == query, mode == selected, !Task.isCancelled else { return }
                errors = requested == 1 ? result.items : errors + result.items.filter { next in !errors.contains { $0.id == next.id } }
                page = result.page; hasMore = result.hasMore; total = result.totalExact ? result.total : nil
            }
            updatedAt = Date()
        } catch {
            if ticket == id, generation == model.sessionGeneration, !(error is CancellationError), !Task.isCancelled {
                failure = error.localizedDescription; failedPage = requested
            }
        }
    }
}

private enum LogMode: String, CaseIterable, Identifiable {
    case requests, failures, upstream
    var id: Self { self }
    var title: String { switch self { case .requests: "请求记录"; case .failures: "失败请求"; case .upstream: "上游错误" } }
    var errorKind: ErrorLogKind { self == .upstream ? .upstream : .request }
}

private struct RequestLogFilterEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var value: RequestLogFilter
    @State private var userID: String
    @State private var accountID: String
    @State private var groupID: String
    @State private var apiKeyID: String
    @State private var statusCode: String
    @State private var resolved: String
    @State private var error: String?
    let errors: Bool
    let upstream: Bool
    let save: (RequestLogFilter) -> Void
    init(initial: RequestLogFilter, errors: Bool, upstream: Bool, save: @escaping (RequestLogFilter) -> Void) {
        _value = State(initialValue: initial); self.errors = errors; self.upstream = upstream; self.save = save
        _userID = State(initialValue: initial.userID.map(String.init) ?? "")
        _accountID = State(initialValue: initial.accountID.map(String.init) ?? "")
        _groupID = State(initialValue: initial.groupID.map(String.init) ?? "")
        _apiKeyID = State(initialValue: initial.apiKeyID.map(String.init) ?? "")
        _statusCode = State(initialValue: initial.statusCode.map(String.init) ?? "")
        _resolved = State(initialValue: initial.resolved.map { $0 ? "true" : "false" } ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("时间范围") {
                    DatePicker("开始", selection: $value.start)
                    DatePicker("结束", selection: $value.end)
                    HStack {
                        Button("近 24 小时") { setRange(days: 1) }
                        Spacer(); Button("近 7 天") { setRange(days: 7) }
                        Spacer(); Button("近 30 天") { setRange(days: 30) }
                    }.font(.caption)
                }
                Section("关联对象") {
                    if !upstream { TextField("用户 ID", text: $userID).keyboardType(.numberPad).accessibilityIdentifier("logs.filter.user") }
                    TextField("账号 ID", text: $accountID).keyboardType(.numberPad).accessibilityIdentifier("logs.filter.account")
                    TextField("分组 ID", text: $groupID).keyboardType(.numberPad)
                    if !upstream {
                        TextField("API Key ID", text: $apiKeyID).keyboardType(.numberPad)
                        TextField("模型（精确匹配）", text: $value.model).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("logs.filter.model")
                        TextField("请求 ID", text: $value.requestID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
                if errors {
                    Section("错误条件") {
                        TextField("HTTP 状态码", text: $statusCode).keyboardType(.numberPad)
                        Picker("处理状态", selection: $resolved) {
                            Text("全部").tag(""); Text("未处理").tag("false"); Text("已处理").tag("true")
                        }
                        if !upstream { Picker("分类", selection: $value.category) {
                            Text("全部").tag(""); Text("认证").tag("auth"); Text("限流").tag("rate_limit"); Text("上游").tag("upstream"); Text("服务不可用").tag("service_unavailable"); Text("内部").tag("internal"); Text("配额").tag("quota"); Text("无效请求").tag("invalid_request"); Text("安全策略").tag("cyber")
                        } }
                    }
                } else {
                    Section {
                        Picker("请求类型", selection: $value.requestType) {
                            Text("全部").tag(""); Text("流式").tag("stream"); Text("非流式").tag("sync"); Text("WebSocket").tag("ws_v2"); Text("实时会话").tag("live"); Text("安全策略").tag("cyber")
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section { Button("清除筛选") { value = RequestLogFilter(); userID = ""; accountID = ""; groupID = ""; apiKeyID = ""; statusCode = ""; resolved = "" }.accessibilityIdentifier("logs.filter.clear") }
            }
            .navigationTitle("筛选记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("应用") { apply() }.accessibilityIdentifier("logs.filter.apply") }
            }
        }
    }
    private func setRange(days: Double) { value.end = Date(); value.start = value.end.addingTimeInterval(-days * 86_400) }
    private func parse(_ raw: String) throws -> Int? {
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        guard let id = Int(raw), id > 0 else { throw APIError(kind: .validation, message: "ID 和状态码必须为正整数。") }
        return id
    }
    private func apply() {
        do {
            value.userID = try parse(userID); value.accountID = try parse(accountID); value.groupID = try parse(groupID); value.apiKeyID = try parse(apiKeyID)
            value.statusCode = try parse(statusCode); value.resolved = resolved.isEmpty ? nil : resolved == "true"
            _ = try value.queryItems(page: 1, errors: errors, errorKind: upstream ? .upstream : .request)
            save(value); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct UsageRequestDetailView: View {
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
                NavigationLink("查看账号 \(record.accountName ?? "#\(record.accountID)")") { LogAccountDestination(id: record.accountID) }
                if let id = record.groupID { LabeledValue(label: "分组", value: record.groupName ?? "#\(id)") }
                NavigationLink("该账号全部请求记录") { RequestLogsView(accountID: record.accountID) }
            }
        }.navigationTitle("请求详情")
    }
}

private struct RequestErrorDetailView: View {
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
                if let id = record.accountID, id > 0 { NavigationLink("查看账号 \(record.accountName ?? "#\(id)")") { LogAccountDestination(id: id) } }
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
        guard !loading, let session else { return }
        loading = true; error = nil
        let id = UUID(); ticket = id
        let generation = session.generation
        defer { if ticket == id { loading = false } }
        do {
            let result = try await (model.isUITesting ? LogFixtures.errorDetail() : session.client.errorRecord(id: record.id, kind: kind))
            guard ticket == id, generation == model.sessionGeneration, !Task.isCancelled else { return }; record = result
        } catch { if ticket == id, generation == model.sessionGeneration, !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

private struct LogAccountDestination: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var account: UpstreamAccount?
    @State private var error: String?
    let id: Int
    var body: some View {
        Group {
            if let account { AccountDetailView(initial: account) }
            else if let error { FailureView(message: error) }
            else { ProgressView("正在读取账号…") }
        }.task { await load() }
        // A read the background stopped left nothing to show; the loaded detail page refreshes itself.
        .onChange(of: model.foregroundRevision) { _, _ in if account == nil { Task { await load() } } }
    }
    private func load() async {
        guard let session else { return }
        do {
            let result = model.isUITesting ? UpstreamAccount(id: id, name: "演示账号", platform: "openai", type: "apikey") : try await session.client.account(id: id)
            guard session.generation == model.sessionGeneration, !Task.isCancelled else { return }; account = result
        } catch { if session.generation == model.sessionGeneration, !(error is CancellationError) { self.error = error.localizedDescription } }
    }
}

private enum LogFixtures {
    static func requests(page: Int, filter: RequestLogFilter) async throws -> RequestLogPage<UsageRequestRecord> {
        try Task.checkCancellation()
        let id = page == 1 ? 101 : 102
        let empty = (filter.userID != nil && filter.userID != 8) || (filter.accountID != nil && filter.accountID != 1) || (filter.groupID != nil && filter.groupID != 3) || (filter.apiKeyID != nil && filter.apiKeyID != 9) || (!filter.model.isEmpty && filter.model != "gpt-demo") || (!filter.requestType.isEmpty && filter.requestType != "stream") || (!filter.requestID.isEmpty && filter.requestID != "req-demo-\(id)")
        let row = #"{"id":ID,"request_id":"req-demo-ID","created_at":"2026-10-16T08:12:00Z","model":"gpt-demo","user_id":8,"account_id":1,"api_key_id":9,"group_id":3,"input_tokens":1200000,"output_tokens":2400,"cache_creation_tokens":0,"cache_read_tokens":0,"total_cost":"0.50","actual_cost":"0.35","account_stats_cost":"0.40","account_rate_multiplier":"0.30","duration_ms":1250,"first_token_ms":210,"request_type":"stream","account":{"name":"演示账号"},"group":{"name":"演示分组"}}"#.replacingOccurrences(of: "ID", with: String(id))
        return try JSONDecoder().decode(RequestLogPage<UsageRequestRecord>.self, from: Data("{\"items\":[\(empty ? "" : row)],\"total\":null,\"page\":\(page),\"page_size\":30,\"pages\":null,\"total_exact\":false,\"has_more\":\(!empty && page == 1)}".utf8))
    }
    static let errorJSON = #"{"id":201,"created_at":"2026-10-16T08:12:00Z","request_id":"req-error-201","phase":"upstream","type":"upstream_error","status_code":429,"platform":"openai","model":"gpt-demo","resolved":false,"message":"上游请求受限，请稍后重试。","user_id":8,"account_id":1,"group_id":3,"account_name":"演示账号","group_name":"演示分组","upstream_status_code":429,"upstream_latency_ms":530,"response_latency_ms":550}"#
    static func errors(page: Int, filter: RequestLogFilter) async throws -> RequestLogPage<RequestErrorRecord> {
        try Task.checkCancellation()
        let empty = (filter.statusCode != nil && filter.statusCode != 429) || filter.resolved == true || (filter.userID != nil && filter.userID != 8) || (filter.accountID != nil && filter.accountID != 1) || (filter.groupID != nil && filter.groupID != 3) || (!filter.model.isEmpty && filter.model != "gpt-demo") || (!filter.requestID.isEmpty && filter.requestID != "req-error-201") || (!filter.category.isEmpty && filter.category != "upstream")
        return try JSONDecoder().decode(RequestLogPage<RequestErrorRecord>.self, from: Data("{\"items\":[\(empty ? "" : errorJSON)],\"total\":\(empty ? 0 : 1),\"page\":1,\"page_size\":30,\"pages\":1,\"total_exact\":true,\"has_more\":false}".utf8))
    }
    static func errorDetail() async throws -> RequestErrorRecord { try JSONDecoder().decode(RequestErrorRecord.self, from: Data(errorJSON.utf8)) }
}
