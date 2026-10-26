import SwiftUI
import Sub2Core

// The account detail and test pages before 20 §2 and §4 rewrite them, moved unchanged from AccountsView.swift (S2-04).
// S2-08 removes the detail and S2-14 the test page; the later of the two deletes this file and moves accountWriteFailure,
// which AccountEditView still calls.

func accountWriteFailure(_ error: any Error) -> String {
    // Compliance, step-up and read-only refusals come before the handler; the global sheet already answered them.
    if let api = error as? APIError, SecurityInterruption(api) != nil { return "尚未执行：\(api.localizedDescription)" }
    if let api = error as? APIError, let status = api.statusCode, (400..<500).contains(status), status != 408 {
        if status == 409 { return "服务器拒绝：账号或分组存在冲突，请核对配置；未自动覆盖混合渠道限制。" }
        return "服务器拒绝：\(api.localizedDescription)"
    }
    return "结果不明：\(error.localizedDescription) 请先刷新核对，未自动重试。"
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
    @State private var editing = false
    @State private var visible = false
    @State private var accountLoading = false
    @State private var statsLoading = false
    @State private var accountError: String?
    @State private var statsError: String?
    @State private var accountUpdatedAt: Date?
    @State private var editedFixture: UpstreamAccount?
    @State private var accountRequest = UUID()
    @State private var statsRequest = UUID()
    private var polling: Bool { visible && scenePhase == .active && !editing && !busy }
    init(initial: UpstreamAccount) { _account = State(initialValue: initial) }

    var body: some View {
        // Match the task's captured ID even if onAppear changes visibility
        // before SwiftUI starts an earlier inactive task.
        let shouldPoll = polling
        let now = session?.client.serverClock.now() ?? Date()
        List {
            Section("账号") {
                LabeledValue(label: "名称", value: account.name)
                LabeledValue(label: "平台", value: account.platform)
                LabeledValue(label: "类型", value: account.type)
                LabeledValue(label: "状态", value: AccountFieldPresentation.status(account, now: now))
                LabeledValue(label: "调度", value: account.schedulable ? "已启用" : "已暂停")
                if let message = account.errorMessage, !message.isEmpty { Text("上游返回异常，可在下方请求记录与错误日志中查看。").foregroundStyle(.red) }
            }
            Section("容量与实时占用") {
                LabeledValue(label: "容量", value: AccountFieldPresentation.value(.capacity, account: account, now: now))
                    .accessibilityIdentifier("account.detail.capacity")
                LabeledValue(label: "在用并发", value: AccountFieldPresentation.value(.concurrency, account: account, now: now))
                    .accessibilityIdentifier("account.detail.concurrency")
                if let probe = account.probeConcurrency {
                    LabeledValue(label: "探测并发", value: String(probe))
                }
                LabeledValue(label: "在用 RPM", value: AccountFieldPresentation.value(.rpm, account: account, now: now))
                    .accessibilityIdentifier("account.detail.rpm")
                Text("在用 RPM 为最近 60 秒成功请求数。").font(.caption).foregroundStyle(.secondary)
                LabeledValue(label: "基础 RPM 限额", value: AccountFieldPresentation.value(.baseRPM, account: account, now: now))
                if account.currentRPM == nil {
                    Text("站点未返回此账号的在用 RPM，可能暂时无法读取运行统计；未提供时不以配置限额或零代替。")
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
                    LabeledValue(label: "请求", value: DisplayFormat.grouped(stats.requests))
                    LabeledValue(label: "Tokens", value: DisplayFormat.compact(stats.tokens))
                    LabeledValue(label: "扣费", value: DisplayFormat.money(stats.userCost))
                        .accessibilityIdentifier("account.detail.user-cost")
                    LabeledValue(label: "成本", value: DisplayFormat.money(stats.cost))
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
                Button("快捷编辑账号", systemImage: "pencil") { editing = true }.accessibilityIdentifier("account.edit")
                Button(account.schedulable ? "暂停调度" : "启用调度") { action = .schedule }.frame(minHeight: 44)
                Button("刷新账号凭据") { action = .refresh }.frame(minHeight: 44)
                Button("手动测试账号") { testing = true }.frame(minHeight: 44).accessibilityIdentifier("account.test")
            }.disabled(busy)
            Section("记录与分析") {
                NavigationLink("请求记录与错误日志") { RequestLogsView(accountID: account.id) }
                    .accessibilityIdentifier("account.logs")
                NavigationLink("账号统计分析") { AnalyticsView(accountID: account.id) }
                    .accessibilityIdentifier("account.analytics")
            }
            if busy { ProgressView("正在处理…") }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(account.name)
        .refreshable { await reload() }
        .onAppear { visible = true }
        .onDisappear { visible = false; cancelReads() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelReads() } }
        .onChange(of: editing) { _, value in if value { cancelReads() } }
        .onChange(of: busy) { _, value in if value { cancelReads() } }
        .task(id: shouldPoll) {
            guard shouldPoll else { return }
            async let today: Void = reloadStats()
            async let current: Void = pollAccount()
            _ = await (today, current)
        }
        .confirmationDialog(action == .schedule ? (account.schedulable ? "暂停调度？" : "启用调度？") : "刷新账号凭据？", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
            Button("确认操作", role: .destructive) { let selected = action; action = nil; Task { if let selected { await mutate(selected) } } }
        } message: { Text("站点：\(model.activeProfile?.name ?? "")\n账号：\(account.name)（#\(account.id)）") }
        .sheet(isPresented: $testing) { AccountTestView(account: account) }
        .sheet(isPresented: $editing) {
            AccountEditView(initial: account) { updated in
                account = updated; if model.isUITesting { editedFixture = updated }
            }
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
            let updated: UpstreamAccount
            if model.isUITesting, let editedFixture { updated = editedFixture }
            else { updated = try await model.account(id: account.id) }
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
                // R05: the key is made when the user confirms.
                let key: UUID? = session?.has(.adminIdempotentWrites) == true ? UUID() : nil
                let result = try await client.setSchedulable(id: account.id, enabled: !account.schedulable, idempotencyKey: key)
                guard generation == model.sessionGeneration else { return }; account = result.value
            } else { try await client.refreshAccount(id: account.id); guard generation == model.sessionGeneration else { return }; await reload() }
            error = nil
        } catch {
            guard generation == model.sessionGeneration else { return }
            self.error = error.localizedDescription
            // Cleared by the global sheet: the same operation is confirmed again (00 §2.6.2 step 4).
            if isClearedForReconfirmation(error) { self.action = action }
            // An unknown result is read back (00 §2.4, §2.5.4).
            else if error is KeyedWriteFailure || (error as? APIError)?.kind == .transport { await reloadAccount() }
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
                // A compliance or step-up refusal was answered in the global sheet; the text says whether to start again.
                if !(error is CancellationError) { outcome = error.localizedDescription }
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
