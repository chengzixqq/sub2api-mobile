import SwiftUI
import Sub2Core

struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @State private var accounts: [UpstreamAccount] = []
    @State private var search = ""
    @State private var status = ""
    @State private var platform = ""
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
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
                            Text("\(account.platform) · \(account.type)").font(.caption).foregroundStyle(.secondary)
                            Label(account.schedulable ? "参与调度" : "暂停调度", systemImage: account.schedulable ? "checkmark.circle" : "pause.circle")
                                .font(.caption).foregroundStyle(account.schedulable ? .green : .secondary)
                            if let message = account.errorMessage, !message.isEmpty { Text(message).font(.caption).foregroundStyle(.red).lineLimit(2) }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("account.\(account.id)")
                }
                if accounts.isEmpty && !loading && error == nil { Text("没有符合条件的账号").foregroundStyle(.secondary) }
                if hasMore { Button("加载更多账号") { Task { await load(nextPage: page + 1) } }.frame(minHeight: 44).disabled(loading).accessibilityIdentifier("accounts.more") }
                if loading { ProgressView("正在加载…") }
                if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await load(nextPage: page == 0 ? 1 : page + 1) } }.frame(minHeight: 44) }
            }
        }
        .navigationTitle("上游账号")
        .searchable(text: $search, prompt: "搜索账号名称")
        .refreshable { await load(nextPage: 1, replace: true) }
        .task(id: query) {
            requestID = UUID(); loading = false
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await load(nextPage: 1, replace: true)
        }
    }
    private func load(nextPage: Int, replace: Bool = false) async {
        guard !loading else { return }
        let generation = model.sessionGeneration
        let ticket = UUID(); requestID = ticket
        loading = true; error = nil
        defer { if requestID == ticket { loading = false } }
        do {
            let result = try await model.accounts(page: nextPage, search: search, status: status.isEmpty ? nil : status, platform: platform.isEmpty ? nil : platform)
            guard generation == model.sessionGeneration, requestID == ticket, !Task.isCancelled else { return }
            accounts = replace ? result.items : accounts + result.items.filter { next in !accounts.contains { $0.id == next.id } }
            page = result.page; hasMore = result.hasMore
        } catch { if generation == model.sessionGeneration && requestID == ticket && !(error is CancellationError) { self.error = error.localizedDescription } }
    }
}

private enum AccountAction: String, Identifiable { case schedule, refresh; var id: String { rawValue } }

struct AccountDetailView: View {
    @Environment(AppModel.self) private var model
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
                if let message = account.errorMessage { Text(message).foregroundStyle(.red) }
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
            if let client = model.client { StepUpView(client: client) { error = "验证通过，请重新确认管理操作。" } }
        }
    }
    private func reload() async {
        let generation = model.sessionGeneration
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
        let generation = model.sessionGeneration
        do {
            guard !model.isUITesting else { throw AppFailure("界面测试模式不执行服务器写操作。") }
            let client = try model.requireClient()
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
            .sheet(isPresented: $stepUp) { if let client = model.client { StepUpView(client: client) { outcome = "验证通过，请重新确认测试。" } } }
        }
    }
    private func start() {
        guard !running else { return }
        let generation = model.sessionGeneration
        running = true; lines = []; outcome = nil
        task = Task {
            defer { running = false }
            do {
                guard !model.isUITesting else { throw AppFailure("界面测试模式不会发起上游测试。") }
                let stream = try await model.requireClient().testAccount(id: account.id, model: modelName.isEmpty ? nil : modelName)
                var completed = false
                for try await event in stream {
                    guard generation == model.sessionGeneration, !Task.isCancelled else { return }
                    if let content = event.content ?? event.message { lines.append(content); if lines.count > 500 { lines.removeFirst() } }
                    if event.isTerminal { completed = true; outcome = event.isSuccess ? "测试成功" : (event.message ?? "测试失败") }
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
}
