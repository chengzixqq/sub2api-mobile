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
    @State private var todayStats = DashboardLoadState<[Int: AccountTodayStats]>()
    @State private var loadedAt: Date?
    @State private var pageRevision = UUID()
    private var query: String { search + "|" + status + "|" + platform + "|\(fieldSelection.isEnabled(.schedulerScore))" }
    private var statsQuery: String { "\(fieldSelection.isEnabled(.todayStats))-\(pageRevision)" }

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
                                    Text("\(field.title)：\(AccountFieldPresentation.value(field, account: account, today: todayStats.value?[account.id]))")
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
            if fieldSelection.isEnabled(.todayStats) {
                Section {
                    if todayStats.isLoading { ProgressView("正在批量加载今日统计…") }
                    if let error = todayStats.error {
                        Text("今日统计：\(error)").font(.footnote).foregroundStyle(.red)
                            .accessibilityIdentifier("accounts.today-stats.error")
                        Button("重试今日统计") { Task { await loadTodayStats() } }
                    }
                }
            }
            if let loadedAt {
                Section {
                    Text("占用快照更新于 \(loadedAt.formatted(date: .omitted, time: .standard))，下拉刷新获取最新值。未提供的在用指标显示不可用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
        .task(id: statsQuery) { await loadTodayStats() }
        .onDisappear { todayStats.cancel() }
        .task(id: query) {
            requestID = UUID(); loading = false
            page = 0; hasMore = false; accounts = []; error = nil; failedPage = nil
            todayStats.cancel(); todayStats.value = nil; loadedAt = nil
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await load(nextPage: 1, replace: true)
        }
    }
    private func loadTodayStats() async {
        guard fieldSelection.isEnabled(.todayStats), !accounts.isEmpty, let generation = session?.generation else {
            todayStats.cancel(); todayStats.value = nil; return
        }
        let ids = accounts.map(\.id)
        let currentQuery = statsQuery
        await todayStats.load(isCurrent: {
            generation == model.sessionGeneration && currentQuery == statsQuery && fieldSelection.isEnabled(.todayStats)
        }) {
            try await model.accountTodayStats(ids: ids)
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
            let result = try await model.accounts(page: nextPage, search: search, status: status.isEmpty ? nil : status, platform: platform.isEmpty ? nil : platform, includeSchedulerScore: fieldSelection.isEnabled(.schedulerScore))
            guard generation == model.sessionGeneration, requestID == ticket, !Task.isCancelled else { return }
            accounts = replace ? result.items : accounts + result.items.filter { next in !accounts.contains { $0.id == next.id } }
            page = result.page; hasMore = result.hasMore; failedPage = nil
            loadedAt = Date(); todayStats.cancel(); todayStats.value = nil; pageRevision = UUID()
        } catch { if generation == model.sessionGeneration && requestID == ticket && !(error is CancellationError) { self.error = error.localizedDescription; failedPage = nextPage } }
    }
}

private enum AccountAction: String, Identifiable { case schedule, refresh; var id: String { rawValue } }

struct AccountDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var account: UpstreamAccount
    @State private var stats: AccountTodayStats?
    @State private var error: String?
    @State private var action: AccountAction?
    @State private var busy = false
    @State private var testing = false
    @State private var stepUp = false
    @State private var visible = false
    @State private var accountLoading = false
    @State private var statsLoading = false
    @State private var accountError: String?
    @State private var statsError: String?
    @State private var accountUpdatedAt: Date?
    @State private var accountRequest = UUID()
    @State private var statsRequest = UUID()
    private var polling: Bool { visible && scenePhase == .active }
    init(initial: UpstreamAccount) { _account = State(initialValue: initial) }

    var body: some View {
        List {
            Section("账号") {
                LabeledValue(label: "名称", value: account.name)
                LabeledValue(label: "平台", value: account.platform)
                LabeledValue(label: "类型", value: account.type)
                LabeledValue(label: "状态", value: account.status)
                LabeledValue(label: "调度", value: account.schedulable ? "已启用" : "已暂停")
                if let message = account.errorMessage, !message.isEmpty { Text("上游返回异常，请在 Web 后台查看详情。").foregroundStyle(.red) }
            }
            Section("容量与实时占用") {
                LabeledValue(label: "容量", value: AccountFieldPresentation.value(.capacity, account: account))
                    .accessibilityIdentifier("account.detail.capacity")
                LabeledValue(label: "在用并发", value: AccountFieldPresentation.value(.concurrency, account: account))
                    .accessibilityIdentifier("account.detail.concurrency")
                if let probe = account.probeConcurrency {
                    LabeledValue(label: "探测并发", value: String(probe))
                }
                LabeledValue(label: "在用 RPM", value: AccountFieldPresentation.value(.rpm, account: account))
                    .accessibilityIdentifier("account.detail.rpm")
                LabeledValue(label: "基础 RPM 限额", value: AccountFieldPresentation.value(.baseRPM, account: account))
                if account.currentRPM == nil {
                    Text("站点仅为部分启用 RPM 统计的账号返回在用 RPM；未提供时不以配置限额代替。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if accountLoading { ProgressView("正在更新容量…") }
                if let date = accountUpdatedAt {
                    Text("更新于 \(date.formatted(date: .omitted, time: .standard)) · 前台每 30 秒刷新")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("account.detail.runtime-updated")
                } else {
                    Text("当前显示列表加载时的快照，正在读取最新数据。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let accountError {
                    Text("刷新失败，保留上次快照：\(accountError)").font(.footnote).foregroundStyle(.red)
                }
                Button("刷新容量与占用") { Task { await reloadAccount() } }
                    .disabled(accountLoading).accessibilityIdentifier("account.detail.reload-runtime")
            }
            Section("今日用量") {
                if let stats {
                    LabeledValue(label: "请求", value: stats.requests.formatted())
                    LabeledValue(label: "Tokens", value: DashboardPresentation.compactNumber(stats.tokens))
                    LabeledValue(label: "扣费", value: DashboardPresentation.money(stats.userCost))
                        .accessibilityIdentifier("account.detail.user-cost")
                    LabeledValue(label: "成本", value: DashboardPresentation.money(stats.cost))
                        .accessibilityIdentifier("account.detail.cost")
                    Text("扣费为此账号今日实际向用户收取的费用，成本为账号上游成本。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if statsLoading {
                    ProgressView("正在读取今日用量…")
                        .accessibilityIdentifier("account.detail.stats-loading")
                }
                if let statsError { Text(statsError).font(.footnote).foregroundStyle(.red) }
                if stats == nil && !statsLoading && statsError == nil { Text("暂未加载").foregroundStyle(.secondary) }
                Button("刷新今日用量") { Task { await reloadStats() } }.disabled(statsLoading)
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
        .onAppear { visible = true }
        .onDisappear { visible = false; cancelReads() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelReads() } }
        .task(id: polling) {
            guard polling else { return }
            async let today: Void = reloadStats()
            async let current: Void = pollAccount()
            _ = await (today, current)
        }
        .confirmationDialog(action == .schedule ? (account.schedulable ? "暂停调度？" : "启用调度？") : "刷新账号凭据？", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
            Button("确认操作", role: .destructive) { let selected = action; action = nil; Task { if let selected { await mutate(selected) } } }
        } message: { Text("站点：\(model.activeProfile?.name ?? "")\n账号：\(account.name)（#\(account.id)）") }
        .sheet(isPresented: $testing) { AccountTestView(account: account) }
        .sheet(isPresented: $stepUp) {
            if let client = session?.client { StepUpView(client: client) { error = "验证通过，请重新确认管理操作。" } }
        }
    }
    private func reload() async {
        async let current: Void = reloadAccount()
        async let today: Void = reloadStats()
        _ = await (current, today)
    }
    private func pollAccount() async {
        await reloadAccount()
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard polling else { return }
            await reloadAccount()
        }
    }
    private func cancelReads() {
        accountRequest = UUID(); statsRequest = UUID()
        accountLoading = false; statsLoading = false
    }
    private func reloadAccount() async {
        guard !accountLoading else { return }
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        let ticket = UUID(); accountRequest = ticket; accountLoading = true
        defer { if accountRequest == ticket { accountLoading = false } }
        do {
            let updated = try await model.account(id: account.id)
            guard generation == model.sessionGeneration, accountRequest == ticket, !Task.isCancelled else { return }
            account = updated; accountError = nil; accountUpdatedAt = Date()
        } catch {
            if generation == model.sessionGeneration, accountRequest == ticket, !(error is CancellationError) {
                accountError = error.localizedDescription
            }
        }
    }
    private func reloadStats() async {
        guard !statsLoading else { return }
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        let ticket = UUID(); statsRequest = ticket; statsLoading = true
        defer { if statsRequest == ticket { statsLoading = false } }
        do {
            let today = try await model.accountTodayStats(id: account.id)
            guard generation == model.sessionGeneration, statsRequest == ticket, !Task.isCancelled else { return }
            stats = today; statsError = nil
        } catch {
            if generation == model.sessionGeneration, statsRequest == ticket, !(error is CancellationError) {
                statsError = error.localizedDescription
            }
        }
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
