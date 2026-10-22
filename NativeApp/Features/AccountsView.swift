import SwiftUI
import Sub2Core

private enum AccountBatchAction: String, Identifiable {
    case pause, resume, refresh
    var id: String { rawValue }
    var title: String { switch self { case .pause: "暂停调度"; case .resume: "启用调度"; case .refresh: "刷新凭据" } }
}
private struct AccountBatchConfirmation: Identifiable {
    let id = UUID()
    let action: AccountBatchAction
    let accounts: [UpstreamAccount]
    let generation: UUID
    let site: String
}
private struct AccountBatchOutcome: Identifiable {
    let id: Int
    let name: String
    let message: String
}

struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var accounts: [UpstreamAccount] = []
    @State private var filters = AccountListQuery()
    @State private var page = 0
    @State private var hasMore = false
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var failedPage: Int?
    @State private var requestID = UUID()
    @State private var readTask: Task<(Page<UpstreamAccount>, [UpstreamAccount]), any Error>?
    @State private var fieldSelection = ListFieldSelection<AccountListField>()
    @State private var editingFields = false
    @State private var editingFilters = false
    @State private var fieldProfileID: UUID?
    @State private var todayStats = DashboardLoadState<[Int: AccountTodayStats]>()
    @State private var loadedAt: Date?
    @State private var pageRevision = UUID()
    @State private var groups: [AdminGroup] = []
    @State private var groupsError: String?
    @State private var visible = false
    @State private var autoRefresh = false
    @State private var selecting = false
    @State private var selected = Set<Int>()
    @State private var editingAccount: UpstreamAccount?
    @State private var pendingBatch: AccountBatchConfirmation?
    @State private var batchRunning = false
    @State private var batchOutcomes: [AccountBatchOutcome] = []
    @State private var batchSite = ""
    @State private var showOutcomes = false
    @State private var stepUp = false
    private var query: AccountListQuery {
        var result = filters; result.includeSchedulerScore = fieldSelection.isEnabled(.schedulerScore); return result
    }
    private var statsQuery: String { "\(fieldSelection.isEnabled(.todayStats))-\(pageRevision)" }
    private var polling: Bool { visible && scenePhase == .active && autoRefresh && !selecting && !batchRunning && editingAccount == nil }
    init(initialGroupID: Int? = nil) {
        var initial = AccountListQuery(); if let initialGroupID { initial.group = String(initialGroupID) }
        _filters = State(initialValue: initial)
    }

    var body: some View {
        List {
            Section {
                Button { editingFilters = true } label: {
                    HStack { Label("筛选与排序", systemImage: "line.3.horizontal.decrease.circle"); Spacer(); Text("\(total) 个").foregroundStyle(.secondary) }
                }.accessibilityIdentifier("accounts.filters")
                Toggle("前台自动刷新（30 秒）", isOn: $autoRefresh).accessibilityIdentifier("accounts.auto-refresh")
                if selecting {
                    HStack {
                        Button("选择已加载账号") { selected = Set(accounts.prefix(50).map(\.id)) }
                        Spacer(); Text("已选 \(selected.count) / 50").foregroundStyle(.secondary)
                    }
                    Menu {
                        ForEach([AccountBatchAction.pause, .resume, .refresh]) { action in
                            Button(action.title) { prepareBatch(action) }
                                .accessibilityIdentifier("accounts.batch.\(action.rawValue)")
                        }
                    } label: {
                        Label("批量操作", systemImage: "checklist")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }.disabled(selected.isEmpty || batchRunning).accessibilityIdentifier("accounts.batch-actions")
                }
            }
            Section("上游账号") {
                ForEach(accounts) { account in
                    HStack(alignment: .top) {
                        if selecting {
                            Button { toggleSelection(account.id) } label: {
                                Image(systemName: selected.contains(account.id) ? "checkmark.circle.fill" : "circle").font(.title3)
                            }.buttonStyle(.borderless).accessibilityLabel("选择 \(account.name)")
                                .accessibilityIdentifier("account.\(account.id).select")
                        }
                        NavigationLink { AccountDetailView(initial: account) } label: { accountRow(account) }
                            .accessibilityIdentifier("account.\(account.id)")
                    }
                    .swipeActions(edge: .trailing) {
                        Button("快捷编辑") { editingAccount = account }.tint(.blue)
                    }
                    .contextMenu { Button("快捷编辑", systemImage: "pencil") { editingAccount = account } }
                }
                if accounts.isEmpty && !loading && error == nil { Text("没有符合条件的账号").foregroundStyle(.secondary) }
                if hasMore { Button("加载更多账号") { Task { await load(nextPage: page + 1) } }.frame(minHeight: 44).disabled(loading || batchRunning).accessibilityIdentifier("accounts.more") }
                if loading { ProgressView("正在加载…") }
                if let error {
                    Text(error).foregroundStyle(.red)
                    Button("重试读取") { Task { await load(nextPage: failedPage ?? 1, replace: (failedPage ?? 1) == 1) } }.disabled(loading)
                }
            }
            if fieldSelection.isEnabled(.todayStats) {
                Section {
                    if todayStats.isLoading { ProgressView("正在批量加载今日统计…") }
                    if let error = todayStats.error {
                        Text("今日统计：\(error)").font(.footnote).foregroundStyle(.red).accessibilityIdentifier("accounts.today-stats.error")
                        Button("重试今日统计") { Task { await loadTodayStats() } }
                    }
                }
            }
            if let loadedAt {
                Section {
                    Text("占用快照更新于 \(loadedAt.formatted(date: .omitted, time: .standard))。\(autoRefresh ? "前台每 30 秒刷新已加载页面；选择账号时暂停。" : "下拉刷新获取最新值。")未提供的在用指标显示不可用。")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("accounts.updated")
                }
            }
            if !batchOutcomes.isEmpty { Section { Button("查看最近批量结果") { showOutcomes = true } } }
        }
        .navigationTitle("上游账号")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(selecting ? "完成选择" : "选择") { selecting.toggle(); if !selecting { selected = [] } }
                    .disabled(batchRunning).accessibilityIdentifier("accounts.select")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("显示字段", systemImage: "line.3.horizontal.decrease") { editingFields = true }.accessibilityIdentifier("accounts.fields")
            }
        }
        .sheet(isPresented: $editingFields) { ListFieldEditor(title: "账号列表字段", selection: $fieldSelection) }
        .sheet(isPresented: $editingFilters) { filterSheet }
        .sheet(item: $editingAccount) { initial in
            AccountEditView(initial: initial) { updated in
                cancelReads()
                if let index = accounts.firstIndex(where: { $0.id == updated.id }) { accounts[index] = updated }
            }
        }
        .sheet(isPresented: $showOutcomes) { outcomeSheet }
        .sheet(isPresented: $stepUp) {
            if let client = session?.client { StepUpView(client: client) { error = "验证通过，请核对批量结果后重新选择尚未执行的账号。" } }
        }
        .confirmationDialog(pendingBatch.map { "\($0.action.title)：\($0.accounts.count) 个账号？" } ?? "批量操作", isPresented: Binding(get: { pendingBatch != nil }, set: { if !$0 { pendingBatch = nil } }), titleVisibility: .visible) {
            Button("确认执行", role: .destructive) {
                if let pending = pendingBatch { pendingBatch = nil; Task { await executeBatch(pending) } }
            }
        } message: {
            if let pendingBatch {
                Text("站点：\(pendingBatch.site)\n\(pendingBatch.accounts.map { "\($0.name)（#\($0.id)）" }.joined(separator: "、"))\n结果不明的写入不会自动重试。")
            }
        }
        .task(id: model.activeProfile?.id) {
            fieldProfileID = model.activeProfile?.id
            fieldSelection = ListFieldSelection(rawValue: UserDefaults.standard.string(forKey: ListFieldSelection<AccountListField>.storageKey(profileID: fieldProfileID)))
            await loadGroups()
        }
        .onChange(of: fieldSelection) { _, value in
            guard fieldProfileID == model.activeProfile?.id else { return }
            UserDefaults.standard.set(value.rawValue, forKey: ListFieldSelection<AccountListField>.storageKey(profileID: fieldProfileID))
        }
        .searchable(text: $filters.search, prompt: "搜索账号名称")
        .refreshable { await load(nextPage: 1, replace: true) }
        .task(id: statsQuery) { await loadTodayStats() }
        .onAppear { visible = true; pageRevision = UUID() }
        .onDisappear { visible = false; cancelReads() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelReads() } }
        .onChange(of: editingAccount?.id) { _, value in
            if value != nil { cancelReads() } else { pageRevision = UUID() }
        }
        .task(id: polling) {
            guard polling else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard polling else { return }
                await load(nextPage: 1, replace: true)
            }
        }
        .task(id: query) {
            cancelReads()
            page = 0; hasMore = false; accounts = []; total = 0; error = nil; failedPage = nil; selected = []
            todayStats.cancel(); todayStats.value = nil; loadedAt = nil
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await load(nextPage: 1, replace: true)
        }
    }
    private func accountRow(_ account: UpstreamAccount) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(account.name).font(.headline)
            ListFieldFlow {
                ForEach(fieldSelection.visibleFields, id: \.rawValue) { field in
                    Text("\(field.title)：\(AccountFieldPresentation.value(field, account: account, today: todayStats.value?[account.id]))")
                        .font(.caption).foregroundStyle(field == .schedulable && account.schedulable ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("account.\(account.id).field.\(field.rawValue)")
                }
            }
            if let message = account.errorMessage, !message.isEmpty { Text("上游返回异常，点入查看错误日志。").font(.caption).foregroundStyle(.red).lineLimit(2) }
        }.padding(.vertical, 4)
    }
    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("筛选") {
                    Picker("状态与调度", selection: $filters.status) {
                        Text("全部状态").tag(""); Text("可调度").tag("active"); Text("已暂停调度").tag("unschedulable")
                        Text("限流中").tag("rate_limited"); Text("临时不可调度").tag("temp_unschedulable")
                        Text("异常").tag("error"); Text("已禁用").tag("inactive")
                    }.accessibilityIdentifier("accounts.status")
                    Picker("平台", selection: $filters.platform) {
                        Text("全部平台").tag("")
                        ForEach(GroupPlatform.values.filter { $0 != "composite" }, id: \.self) { Text(GroupPlatform.title($0)).tag($0) }
                    }.accessibilityIdentifier("accounts.platform")
                    Picker("认证类型", selection: $filters.type) {
                        Text("全部类型").tag(""); Text("API Key").tag("apikey"); Text("OAuth").tag("oauth")
                        Text("Setup Token").tag("setup-token"); Text("上游").tag("upstream"); Text("Bedrock").tag("bedrock"); Text("Service Account").tag("service_account")
                    }.accessibilityIdentifier("accounts.type")
                    Picker("分组", selection: $filters.group) {
                        Text("全部分组").tag(""); Text("未分组").tag("ungrouped")
                        ForEach(groups) { Text("\($0.name) · #\($0.id)").tag(String($0.id)) }
                        if let id = Int(filters.group), !groups.contains(where: { $0.id == id }) { Text("分组 #\(id)").tag(filters.group) }
                    }.accessibilityIdentifier("accounts.group")
                    if let groupsError { Text(groupsError).font(.caption).foregroundStyle(.red); Button("重新读取分组") { Task { await loadGroups() } } }
                }
                Section("全量结果排序") {
                    Picker("排序字段", selection: $filters.sort) { ForEach(AccountSort.allCases, id: \.self) { Text($0.title).tag($0) } }
                        .accessibilityIdentifier("accounts.sort")
                    Toggle("降序排列", isOn: $filters.descending)
                    Text("排序应用于全部分页结果。").font(.caption).foregroundStyle(.secondary)
                }
                Button("重置筛选与排序") { filters = AccountListQuery() }
            }
            .navigationTitle("账号筛选")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { editingFilters = false }.accessibilityIdentifier("accounts.filters.done") } }
        }
    }
    private var outcomeSheet: some View {
        NavigationStack {
            List {
                Section { Text("站点：\(batchSite)"); Text("写操作未自动重试；结果不明时先刷新并核对服务器状态。凭据刷新响应丢失时，无法仅靠读取确认结果。").font(.caption).foregroundStyle(.secondary) }
                ForEach(batchOutcomes) { item in VStack(alignment: .leading) { Text("\(item.name)（#\(item.id)）").font(.headline); Text(item.message).font(.subheadline) } }
            }.navigationTitle("批量操作结果")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showOutcomes = false } } }
        }
    }
    private func toggleSelection(_ id: Int) {
        if selected.contains(id) { selected.remove(id) } else if selected.count < 50 { selected.insert(id) }
    }
    private func prepareBatch(_ action: AccountBatchAction) {
        guard let generation = session?.generation, generation == model.sessionGeneration, !batchRunning else { return }
        let targets = accounts.filter { selected.contains($0.id) }
        guard !targets.isEmpty else { return }
        pendingBatch = AccountBatchConfirmation(action: action, accounts: targets, generation: generation, site: model.activeProfile?.name ?? "")
    }
    private func executeBatch(_ operation: AccountBatchConfirmation) async {
        guard !batchRunning, operation.generation == model.sessionGeneration, let client = session?.client else { return }
        cancelReads()
        batchRunning = true; batchOutcomes = []; batchSite = operation.site; error = nil
        defer { batchRunning = false }
        let identity = await client.userWriteIdentity()
        guard operation.generation == model.sessionGeneration else { return }
        do {
            if model.isUITesting {
                batchOutcomes = operation.accounts.map { AccountBatchOutcome(id: $0.id, name: $0.name, message: "界面测试：已确认操作，未发送服务器写入。") }
            } else if operation.action == .refresh {
                for (index, account) in operation.accounts.enumerated() {
                    guard operation.generation == model.sessionGeneration else { return }
                    do {
                        try await client.refreshManagedAccount(id: account.id, identity: identity)
                        guard operation.generation == model.sessionGeneration else { return }
                        batchOutcomes.append(.init(id: account.id, name: account.name, message: "凭据刷新成功"))
                    } catch {
                        guard operation.generation == model.sessionGeneration else { return }
                        batchOutcomes.append(.init(id: account.id, name: account.name, message: accountWriteFailure(error)))
                        // Stop the batch when every later account would hit the same session, verification or compliance gate.
                        let kind = (error as? APIError)?.kind
                        if needsStepUp(error) || kind == .authentication || kind == .compliance {
                            if needsStepUp(error) { stepUp = true }
                            for skipped in operation.accounts.dropFirst(index + 1) { batchOutcomes.append(.init(id: skipped.id, name: skipped.name, message: "尚未执行，请完成验证后手动选择。")) }
                            break
                        }
                    }
                }
            } else {
                let result = try await client.setAccountsSchedulable(ids: operation.accounts.map(\.id), enabled: operation.action == .resume, identity: identity)
                guard operation.generation == model.sessionGeneration else { return }
                batchOutcomes = operation.accounts.map { account in
                    let outcome = result.outcome(for: account.id)
                    return .init(id: account.id, name: account.name, message: outcome == true ? "\(operation.action.title)成功" : outcome == false ? "服务器明确返回失败，请检查账号权限、状态或分组配置。" : "未返回此账号的明确结果，请先刷新核对。")
                }
            }
        } catch {
            guard operation.generation == model.sessionGeneration else { return }
            batchOutcomes = operation.accounts.map { .init(id: $0.id, name: $0.name, message: accountWriteFailure(error)) }
            if needsStepUp(error) { stepUp = true }
        }
        guard operation.generation == model.sessionGeneration else { return }
        selected = []; selecting = false; showOutcomes = !stepUp
        await load(nextPage: 1, replace: true)
    }
    private func loadGroups() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        do {
            let result: [AdminGroup]
            if model.isUITesting { result = [AdminGroup(id: 10, name: "标准分组"), AdminGroup(id: 11, name: "高级分组")] }
            else { result = try await session.client.allGroups() }
            guard session.generation == model.sessionGeneration, !Task.isCancelled else { return }
            groups = result; groupsError = nil; accounts = accounts.map(withGroupNames)
        } catch { if session.generation == model.sessionGeneration, !(error is CancellationError) { groupsError = "分组读取失败：\(error.localizedDescription)" } }
    }
    private func cancelReads() { requestID = UUID(); readTask?.cancel(); readTask = nil; loading = false; todayStats.cancel() }
    private func withGroupNames(_ initial: UpstreamAccount) -> UpstreamAccount {
        var account = initial
        guard !account.groupIDs.isEmpty else { return account }
        account.groups = account.groupIDs.map { id in
            .init(id: id, name: groups.first(where: { $0.id == id })?.name ?? account.groups.first(where: { $0.id == id })?.name ?? "#\(id)")
        }
        return account
    }
    private func loadTodayStats() async {
        guard fieldSelection.isEnabled(.todayStats), !accounts.isEmpty, let generation = session?.generation else { todayStats.cancel(); todayStats.value = nil; return }
        let ids = accounts.map(\.id); let currentQuery = statsQuery
        await todayStats.load(isCurrent: { generation == model.sessionGeneration && currentQuery == statsQuery && fieldSelection.isEnabled(.todayStats) }) { try await model.accountTodayStats(ids: ids) }
    }
    private func fetchPage(_ number: Int, query: AccountListQuery) async throws -> Page<UpstreamAccount> {
        if model.isUITesting {
            // Fetch fixture pages through AppModel to retain runtime/stats regression switches.
            let all = try await model.accounts(page: 1, search: query.search, status: nil, platform: query.platform.isEmpty ? nil : query.platform)
            var source = all.items
            if all.hasMore { source += try await model.accounts(page: 2, search: query.search, status: nil, platform: query.platform.isEmpty ? nil : query.platform).items }
            source = source.filter { account in
                (query.type.isEmpty || account.type == query.type) && (query.group.isEmpty || (query.group == "ungrouped" ? account.groupIDs.isEmpty : account.groupIDs.contains(Int(query.group) ?? 0))) &&
                (query.status.isEmpty || (query.status == "active" ? account.status == "active" && account.schedulable : query.status == "unschedulable" ? !account.schedulable : account.status == query.status))
            }
            source.sort { query.descending ? $0.name > $1.name : $0.name < $1.name }
            return Page(items: Array(source.dropFirst(max(0, number - 1)).prefix(1)), total: source.count, page: number, pageSize: 1, pages: source.count)
        }
        guard let client = session?.client else { throw APIError.authenticationRequired }
        let result = try await client.managedAccounts(page: number, query: query)
        return Page(items: result.items.map(withGroupNames), total: result.total, page: result.page, pageSize: result.pageSize, pages: result.pages)
    }
    private func load(nextPage: Int, replace: Bool = false) async {
        guard !loading, let generation = session?.generation, generation == model.sessionGeneration else { return }
        let ticket = UUID(); requestID = ticket; let captured = query; let previousPage = page
        loading = true; error = nil
        defer { if requestID == ticket { readTask = nil; loading = false } }
        do {
            let current = Task { @MainActor in
                var result = try await fetchPage(nextPage, query: captured)
                var items = result.items
                if replace, previousPage > 1 {
                    for number in 2...previousPage {
                        guard result.hasMore, generation == model.sessionGeneration, requestID == ticket, captured == query, !Task.isCancelled else { break }
                        result = try await fetchPage(number, query: captured)
                        items += result.items.filter { next in !items.contains { $0.id == next.id } }
                    }
                }
                try Task.checkCancellation()
                return (result, items)
            }
            readTask = current
            let (result, items) = try await withTaskCancellationHandler { try await current.value } onCancel: { current.cancel() }
            guard generation == model.sessionGeneration, requestID == ticket, captured == query, !Task.isCancelled else { return }
            accounts = replace ? items : accounts + items.filter { next in !accounts.contains { $0.id == next.id } }
            page = result.page; hasMore = result.hasMore; total = result.total; failedPage = nil
            loadedAt = Date(); todayStats.cancel(); pageRevision = UUID()
        } catch {
            if generation == model.sessionGeneration, requestID == ticket, !(error is CancellationError) { self.error = "读取失败，保留上次列表：\(error.localizedDescription)"; failedPage = replace ? 1 : nextPage }
        }
    }
}

func accountWriteFailure(_ error: any Error) -> String {
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
    @State private var stepUp = false
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
        List {
            Section("账号") {
                LabeledValue(label: "名称", value: account.name)
                LabeledValue(label: "平台", value: account.platform)
                LabeledValue(label: "类型", value: account.type)
                LabeledValue(label: "状态", value: account.status)
                LabeledValue(label: "调度", value: account.schedulable ? "已启用" : "已暂停")
                if let message = account.errorMessage, !message.isEmpty { Text("上游返回异常，可在下方请求记录与错误日志中查看。").foregroundStyle(.red) }
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
                Text("在用 RPM 为最近 60 秒成功请求数。").font(.caption).foregroundStyle(.secondary)
                LabeledValue(label: "基础 RPM 限额", value: AccountFieldPresentation.value(.baseRPM, account: account))
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
