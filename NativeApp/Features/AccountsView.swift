import SwiftUI
import Sub2Core

struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var accounts: [UpstreamAccount] = []
    @State private var search = ""
    @State private var status = ""
    @State private var platform = ""
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var failedPage: Int?
    @State private var requestID = UUID()
    @State private var fieldSelection = ListFieldSelection<AccountListField>()
    @State private var editingFields = false
    @State private var fieldProfileID: UUID?
    private var query: String { search + "|" + status + "|" + platform }

    var body: some View {
        List {
            Section {
                Picker("状态", selection: $status) {
                    Text("全部状态").tag(""); Text("正常").tag("active"); Text("异常").tag("error"); Text("已禁用").tag("inactive")
                }.accessibilityIdentifier("accounts.status")
                Picker("平台", selection: $platform) {
                    Text("全部平台").tag(""); Text("OpenAI").tag("openai"); Text("Anthropic").tag("anthropic"); Text("Gemini").tag("gemini"); Text("Antigravity").tag("antigravity")
                }
            }
            Section("上游账号") {
                ForEach(accounts) { account in
                    NavigationLink { AccountDetailView(initial: account) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(account.name).font(.headline)
                            ListFieldFlow {
                                ForEach(fieldSelection.visibleFields, id: \.rawValue) { field in
                                    Text("\(field.title)：\(fieldValue(field, account: account))")
                                        .font(.caption).foregroundStyle(field == .schedulable && account.schedulable ? .green : .secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("account.\(account.id).field.\(field.rawValue)")
                                }
                            }
                            if let message = account.errorMessage, !message.isEmpty { Text("上游返回异常，请在 Web 后台查看详情。").font(.caption).foregroundStyle(.red).lineLimit(2) }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("account.\(account.id)")
                }
                if accounts.isEmpty && !loading && error == nil { Text("没有符合条件的账号").foregroundStyle(.secondary) }
                if hasMore { Button("加载更多账号") { Task { await load(nextPage: page + 1) } }.frame(minHeight: 44).disabled(loading).accessibilityIdentifier("accounts.more") }
                if loading { ProgressView("正在加载…") }
                if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await load(nextPage: failedPage ?? 1, replace: (failedPage ?? 1) == 1) } }.frame(minHeight: 44) }
            }
        }
        .navigationTitle("上游账号")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("显示字段", systemImage: "line.3.horizontal.decrease") { editingFields = true }
                    .accessibilityIdentifier("accounts.fields")
            }
        }
        .sheet(isPresented: $editingFields) { ListFieldEditor(title: "账号列表字段", selection: $fieldSelection) }
        .task(id: model.activeProfile?.id) {
            fieldProfileID = model.activeProfile?.id
            fieldSelection = ListFieldSelection(rawValue: UserDefaults.standard.string(forKey: ListFieldSelection<AccountListField>.storageKey(profileID: fieldProfileID)))
        }
        .onChange(of: fieldSelection) { _, value in
            guard fieldProfileID == model.activeProfile?.id else { return }
            UserDefaults.standard.set(value.rawValue, forKey: ListFieldSelection<AccountListField>.storageKey(profileID: fieldProfileID))
        }
        .searchable(text: $search, prompt: "搜索账号名称")
        .refreshable { await load(nextPage: 1, replace: true) }
        .task(id: query) {
            requestID = UUID(); loading = false
            page = 0; hasMore = false; accounts = []; error = nil; failedPage = nil
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await load(nextPage: 1, replace: true)
        }
    }
    private func fieldValue(_ field: AccountListField, account: UpstreamAccount) -> String {
        switch field {
        case .platform: account.platform
        case .authenticationType: account.type
        case .groups:
            if !account.groups.isEmpty { account.groups.map(\.name).joined(separator: "、") }
            else if !account.groupIDs.isEmpty { account.groupIDs.map { "#\($0)" }.joined(separator: "、") }
            else { "未分组" }
        case .concurrency: account.concurrency.map(String.init) ?? "不可用"
        case .priority: account.priority.map(String.init) ?? "不可用"
        case .rateMultiplier: account.rateMultiplier.map { NSDecimalNumber(decimal: $0).stringValue + "×" } ?? "不可用"
        case .status:
            switch account.status {
            case "active": "正常"
            case "inactive": "已禁用"
            case "error": "异常"
            default: account.status
            }
        case .schedulable: account.schedulable ? "参与调度" : "暂停调度"
        case .expiresAt: ListFieldPresentation.timestamp(seconds: account.expiresAt)
        case .lastUsedAt: ListFieldPresentation.timestamp(account.lastUsedAt)
        case .createdAt: ListFieldPresentation.timestamp(account.createdAt)
        case .notes: account.notes.flatMap { $0.isEmpty ? nil : $0 } ?? "无"
        case .rpm: account.baseRPM.map(String.init) ?? "不可用"
        case .usage: account.quotaUsed.map { NSDecimalNumber(decimal: $0).stringValue } ?? "不可用"
        }
    }
    private func load(nextPage: Int, replace: Bool = false) async {
        guard !loading else { return }
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        let ticket = UUID(); requestID = ticket
        loading = true; error = nil
        defer { if requestID == ticket { loading = false } }
        do {
            let result = try await model.accounts(page: nextPage, search: search, status: status.isEmpty ? nil : status, platform: platform.isEmpty ? nil : platform)
            guard generation == model.sessionGeneration, requestID == ticket, !Task.isCancelled else { return }
            accounts = replace ? result.items : accounts + result.items.filter { next in !accounts.contains { $0.id == next.id } }
            page = result.page; hasMore = result.hasMore; failedPage = nil
        } catch { if generation == model.sessionGeneration && requestID == ticket && !(error is CancellationError) { self.error = error.localizedDescription; failedPage = nextPage } }
    }
}

private enum AccountAction: String, Identifiable { case schedule, refresh; var id: String { rawValue } }

struct AccountDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var account: UpstreamAccount
    @State private var stats: AccountTodayStats?
    @State private var error: String?
    @State private var action: AccountAction?
    @State private var busy = false
    @State private var testing = false
    @State private var stepUp = false
    init(initial: UpstreamAccount) { _account = State(initialValue: initial) }

    var body: some View {
        List {
            Section("账号") {
                LabeledValue(label: "名称", value: account.name)
                LabeledValue(label: "平台", value: account.platform)
                LabeledValue(label: "类型", value: account.type)
                LabeledValue(label: "状态", value: account.status)
                LabeledValue(label: "调度", value: account.schedulable ? "已启用" : "已暂停")
                if let concurrency = account.concurrency { LabeledValue(label: "并发", value: String(concurrency)) }
                if let message = account.errorMessage, !message.isEmpty { Text("上游返回异常，请在 Web 后台查看详情。").foregroundStyle(.red) }
            }
            Section("今日用量") {
                if let stats {
                    LabeledValue(label: "请求", value: stats.requests.formatted())
                    LabeledValue(label: "Tokens", value: stats.tokens.formatted())
                    LabeledValue(label: "费用", value: money(stats.cost))
                } else { Text("暂未加载").foregroundStyle(.secondary) }
            }
            Section("管理操作") {
                Button(account.schedulable ? "暂停调度" : "启用调度") { action = .schedule }.frame(minHeight: 44)
                Button("刷新账号凭据") { action = .refresh }.frame(minHeight: 44)
                Button("手动测试账号") { testing = true }.frame(minHeight: 44).accessibilityIdentifier("account.test")
            }.disabled(busy)
            if busy { ProgressView("正在处理…") }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(account.name)
        .refreshable { await reload() }
        .task { await reload() }
        .confirmationDialog(action == .schedule ? (account.schedulable ? "暂停调度？" : "启用调度？") : "刷新账号凭据？", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
            Button("确认操作", role: .destructive) { let selected = action; action = nil; Task { if let selected { await mutate(selected) } } }
        } message: { Text("站点：\(model.activeProfile?.name ?? "")\n账号：\(account.name)（#\(account.id)）") }
        .sheet(isPresented: $testing) { AccountTestView(account: account) }
        .sheet(isPresented: $stepUp) {
            if let client = session?.client { StepUpView(client: client) { error = "验证通过，请重新确认管理操作。" } }
        }
    }
    private func reload() async {
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        do {
            let updated = try await model.account(id: account.id)
            guard generation == model.sessionGeneration, !Task.isCancelled else { return }
            account = updated
            let today = try await model.accountTodayStats(id: account.id)
            guard generation == model.sessionGeneration, !Task.isCancelled else { return }
            stats = today; error = nil
        } catch { if generation == model.sessionGeneration && !(error is CancellationError) { self.error = error.localizedDescription } }
    }
    private func mutate(_ action: AccountAction) async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        do {
            guard !model.isUITesting else { throw AppFailure("界面测试模式不执行服务器写操作。") }
            guard let client = session?.client else { return }
            if action == .schedule {
                let result = try await client.setSchedulable(id: account.id, enabled: !account.schedulable)
                guard generation == model.sessionGeneration else { return }; account = result
            } else { try await client.refreshAccount(id: account.id); guard generation == model.sessionGeneration else { return }; await reload() }
            error = nil
        } catch {
            guard generation == model.sessionGeneration else { return }
            if needsStepUp(error) { stepUp = true } else { self.error = error.localizedDescription }
        }
    }
}

struct AccountTestView: View {
    let account: UpstreamAccount
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var modelName = ""
    @State private var lines: [String] = []
    @State private var running = false
    @State private var outcome: String?
    @State private var task: Task<Void, Never>?
    @State private var stepUp = false
    var body: some View {
        NavigationStack {
            Form {
                Section("测试目标") {
                    LabeledValue(label: "站点", value: model.activeProfile?.name ?? "")
                    LabeledValue(label: "账号", value: account.name)
                    TextField("模型（可选，使用后端默认值）", text: $modelName).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("测试会向上游发起实际请求，可能产生费用。").font(.footnote).foregroundStyle(.secondary)
                    Button(running ? "正在测试…" : "确认并开始测试") { start() }.disabled(running).frame(minHeight: 44).accessibilityIdentifier("account.test.start")
                }
                if let outcome { Section("结果") { Text(outcome).textSelection(.enabled) } }
                if !lines.isEmpty { Section("流式输出") { Text(lines.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled) } }
            }
            .navigationTitle("手动测试")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(running ? "停止并关闭" : "关闭") { task?.cancel(); dismiss() } } }
            .onDisappear { task?.cancel() }
            .sheet(isPresented: $stepUp) { if let client = session?.client { StepUpView(client: client) { outcome = "验证通过，请重新确认测试。" } } }
        }
    }
    private func start() {
        guard !running else { return }
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        guard let client = session?.client else { return }
        running = true; lines = []; outcome = nil
        task = Task {
            defer { running = false }
            do {
                guard generation == model.sessionGeneration else { return }
                guard !model.isUITesting else { throw AppFailure("界面测试模式不会发起上游测试。") }
                let stream = try await client.testAccount(id: account.id, model: modelName.isEmpty ? nil : modelName)
                var completed = false
                for try await event in stream {
                    guard generation == model.sessionGeneration, !Task.isCancelled else { return }
                    if event.type != "error", let content = event.content ?? event.message { lines.append(sanitizedTestOutput(content)); if lines.count > 500 { lines.removeFirst() } }
                    if event.isTerminal { completed = true; outcome = event.isSuccess ? "测试成功" : "测试失败，请在 Web 后台查看详细错误。" }
                }
                guard generation == model.sessionGeneration, !Task.isCancelled else { return }
                if !completed { outcome = "连接结束，但未收到测试完成事件，不能判定成功。" }
            } catch {
                guard generation == model.sessionGeneration else { return }
                if needsStepUp(error) { stepUp = true }
                else if !(error is CancellationError) { outcome = error.localizedDescription }
            }
        }
    }

    private func sanitizedTestOutput(_ value: String) -> String {
        var result = value
        for pattern in ["(?i)Bearer\\s+[^\\s]+", "(?i)sk-[A-Za-z0-9_-]{6,}", "https?://[^\\s]+"] {
            result = result.replacingOccurrences(of: pattern, with: "[已隐藏]", options: .regularExpression)
        }
        return String(result.prefix(8_192))
    }
}
