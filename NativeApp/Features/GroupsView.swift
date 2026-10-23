import SwiftUI
import Observation
import Sub2Core

@MainActor @Observable
private final class GroupWorkspace {
    var revision = 0
    var fixtureGroups = [
        AdminGroup(id: 10, name: "标准分组", description: "按量使用", rateMultiplier: Decimal(string: "1.2"), accountCount: 2, activeAccountCount: 2),
        AdminGroup(id: 11, name: "高级分组", description: "订阅用户", platform: "anthropic", isExclusive: true, subscriptionType: "subscription", dailyLimitUSD: 20, weeklyLimitUSD: 100, monthlyLimitUSD: 300, rpmLimit: 60, accountCount: 1, activeAccountCount: 1)
    ]
    func list(context: SessionContext, fixture: Bool, page: Int, search: String, platform: String, status: String) async throws -> Page<AdminGroup> {
        if !fixture { return try await context.client.groups(page: page, search: search, platform: platform.isEmpty ? nil : platform, status: status.isEmpty ? nil : status) }
        let rows = fixtureGroups.filter { (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) && (platform.isEmpty || $0.platform == platform) && (status.isEmpty || $0.status == status) }
        return Page(items: page == 1 ? rows : [], total: rows.count, page: page, pageSize: 20, pages: rows.isEmpty ? 0 : 1)
    }
    func get(_ id: Int, context: SessionContext, fixture: Bool) async throws -> AdminGroup {
        if !fixture { return try await context.client.group(id: id) }
        guard let group = fixtureGroups.first(where: { $0.id == id }) else { throw APIError.server(status: 404, reason: nil) }
        return group
    }
    func create(_ input: GroupCreateRequest, identity: UUID, context: SessionContext, fixture: Bool) async throws -> AdminGroup {
        if !fixture { let result = try await context.client.createGroup(input, identity: identity); revision += 1; return result }
        try input.validate()
        let row = AdminGroup(id: (fixtureGroups.map(\.id).max() ?? 11) + 1, name: input.name, description: input.description,
            platform: input.platform, rateMultiplier: input.rateMultiplier, isExclusive: input.isExclusive, subscriptionType: input.subscriptionType,
            dailyLimitUSD: value(input.dailyLimitUSD), weeklyLimitUSD: value(input.weeklyLimitUSD), monthlyLimitUSD: value(input.monthlyLimitUSD), rpmLimit: input.rpmLimit, accountCount: 0, activeAccountCount: 0)
        fixtureGroups.insert(row, at: 0); revision += 1; return row
    }
    func update(_ id: Int, input: GroupUpdateRequest, identity: UUID, context: SessionContext, fixture: Bool) async throws -> AdminGroup {
        if !fixture { let result = try await context.client.updateGroup(id: id, input: input, identity: identity); revision += 1; return result }
        try input.validate(); var row = try await get(id, context: context, fixture: true)
        if let name = input.name { row.name = name }; if let description = input.description { row.description = description }
        if let rate = input.rateMultiplier { row.rateMultiplier = rate }; if let exclusive = input.isExclusive { row.isExclusive = exclusive }
        if let status = input.status { row.status = status }; if let subscription = input.subscriptionType { row.subscriptionType = subscription }
        if let rpm = input.rpmLimit { row.rpmLimit = rpm }
        if let limit = input.dailyLimitUSD { row.dailyLimitUSD = value(limit) }; if let limit = input.weeklyLimitUSD { row.weeklyLimitUSD = value(limit) }
        if let limit = input.monthlyLimitUSD { row.monthlyLimitUSD = value(limit) }
        if let index = fixtureGroups.firstIndex(where: { $0.id == id }) { fixtureGroups[index] = row }
        revision += 1; return row
    }
    func delete(_ id: Int, identity: UUID, context: SessionContext, fixture: Bool) async throws {
        if !fixture { try await context.client.deleteGroup(id: id, identity: identity); revision += 1; return }
        fixtureGroups.removeAll { $0.id == id }; revision += 1
    }
    private func value(_ change: GroupLimitChange) -> Decimal? { switch change { case .unlimited: nil; case .amount(let value): value } }
}

struct GroupsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var workspace = GroupWorkspace()
    @State private var groups: [AdminGroup] = []
    @State private var search = ""
    @State private var platform = ""
    @State private var status = ""
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var failedPage: Int?
    @State private var ticket = UUID()
    @State private var pageTask: Task<Void, Never>?
    @State private var editor: GroupEditorTarget?
    private var query: String { search + "|" + platform + "|" + status }

    var body: some View {
        List {
            Section("筛选") {
                Picker("平台", selection: $platform) {
                    Text("全部平台").tag("")
                    ForEach(GroupPlatform.values, id: \.self) { Text(GroupPlatform.title($0)).tag($0) }
                }.accessibilityIdentifier("groups.platform")
                Picker("状态", selection: $status) {
                    Text("全部状态").tag(""); Text("启用").tag("active"); Text("停用").tag("inactive")
                }.accessibilityIdentifier("groups.status")
            }
            Section("分组") {
                ForEach(groups) { group in
                    NavigationLink {
                        GroupDetailView(initial: group).environment(workspace)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.name).font(.headline)
                            Text("\(GroupPlatform.title(group.platform)) · \(group.status == "active" ? "启用" : "停用") · \(group.subscriptionType == "subscription" ? "订阅" : "按量")").font(.caption).foregroundStyle(.secondary)
                            Text("倍率 \(group.rateMultiplier.map { NSDecimalNumber(decimal: $0).stringValue } ?? DisplayFormat.missing) · 账号 \(DisplayFormat.grouped(group.accountCount ?? 0)) · RPM 限额 \(group.rpmLimit.map { $0 == 0 ? "不限制" : DisplayFormat.grouped($0) } ?? DisplayFormat.missing)").font(.caption).foregroundStyle(.secondary)
                            if let description = group.description, !description.isEmpty { Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("group.\(group.id)")
                }
                if groups.isEmpty && !loading && error == nil { Text("没有符合条件的分组").foregroundStyle(.secondary) }
                if hasMore { Button("加载更多分组") { startLoad(page + 1) }.disabled(loading).frame(minHeight: 44).accessibilityIdentifier("groups.more") }
                if loading { ProgressView("正在加载分组…") }
                if let error {
                    Text(error).foregroundStyle(.red)
                    Button("重试") { startLoad(failedPage ?? 1, replace: (failedPage ?? 1) == 1) }.frame(minHeight: 44)
                }
            }
        }
        .navigationTitle("分组")
        .searchable(text: $search, prompt: "搜索分组名称")
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button("创建分组", systemImage: "plus") {
                if let session, session.generation == model.sessionGeneration {
                    editor = GroupEditorTarget(group: nil, context: session, siteName: model.activeProfile?.name ?? "")
                }
            }.accessibilityIdentifier("groups.create")
        } }
        .sheet(item: $editor, onDismiss: { startLoad(1, replace: true) }) { GroupEditorView(target: $0).environment(workspace) }
        .refreshable { await load(1, replace: true) }
        // A load cancelled by going to the background ends silently; reload on return (D18).
        .onChange(of: model.foregroundRevision) { _, _ in startLoad(1, replace: true) }
        .task(id: query) {
            pageTask?.cancel()
            ticket = UUID(); loading = false; groups = []; page = 0; hasMore = false; error = nil; failedPage = nil
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await load(1, replace: true)
        }
        .task(id: workspace.revision) {
            guard workspace.revision > 0 else { return }
            await load(1, replace: true)
        }
        .onDisappear { pageTask?.cancel(); ticket = UUID(); loading = false }
    }
    private func startLoad(_ page: Int, replace: Bool = false) {
        guard !loading else { return }
        pageTask?.cancel(); pageTask = Task { await load(page, replace: replace) }
    }
    private func load(_ nextPage: Int, replace: Bool = false) async {
        guard !loading, let context = session, context.generation == model.sessionGeneration else { return }
        let current = UUID(); let querySnapshot = query; ticket = current; loading = true; error = nil
        defer { if ticket == current { loading = false } }
        do {
            let result = try await workspace.list(context: context, fixture: model.isUITesting, page: nextPage, search: search, platform: platform, status: status)
            guard context.generation == model.sessionGeneration, ticket == current, query == querySnapshot, !Task.isCancelled else { return }
            groups = replace ? result.items : groups + result.items.filter { next in !groups.contains { $0.id == next.id } }
            page = result.page; hasMore = result.hasMore; failedPage = nil
        } catch {
            guard context.generation == model.sessionGeneration, ticket == current, query == querySnapshot, !(error is CancellationError), !Task.isCancelled else { return }
            self.error = error.localizedDescription; failedPage = nextPage
        }
    }
}

private struct GroupDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(GroupWorkspace.self) private var workspace
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var group: AdminGroup
    @State private var capacity: GroupCapacitySummary?
    @State private var capacityDate: Date?
    @State private var capacityError: String?
    @State private var error: String?
    @State private var busy = false
    @State private var readTicket = UUID()
    @State private var capacityTicket = UUID()
    @State private var confirmAction: GroupDetailAction?
    @State private var uncertainAction: GroupDetailAction?
    @State private var editor: GroupEditorTarget?
    init(initial: AdminGroup) { _group = State(initialValue: initial) }
    var body: some View {
        List {
            Section("分组信息") {
                LabeledValue(label: "名称", value: group.name)
                LabeledValue(label: "平台", value: GroupPlatform.title(group.platform))
                LabeledValue(label: "状态", value: group.status == "active" ? "启用" : "停用")
                LabeledValue(label: "计费", value: group.subscriptionType == "subscription" ? "订阅" : "按量")
                LabeledValue(label: "计费倍率", value: group.rateMultiplier.map { NSDecimalNumber(decimal: $0).stringValue } ?? DisplayFormat.missing)
                LabeledValue(label: "专属分组", value: group.isExclusive.map { $0 ? "是" : "否" } ?? DisplayFormat.missing)
                LabeledValue(label: "RPM 限额", value: group.rpmLimit.map { $0 == 0 ? "不限制" : DisplayFormat.grouped($0) } ?? DisplayFormat.missing)
                if let description = group.description, !description.isEmpty { LabeledValue(label: "描述", value: description) }
                LabeledValue(label: "创建时间", value: ListFieldPresentation.timestamp(group.createdAt))
                LabeledValue(label: "更新时间", value: ListFieldPresentation.timestamp(group.updatedAt))
            }
            if group.subscriptionType == "subscription" {
                Section("订阅限额") {
                    LabeledValue(label: "每日", value: group.dailyLimitUSD.map { DisplayFormat.money($0) } ?? "不限制")
                    LabeledValue(label: "每周", value: group.weeklyLimitUSD.map { DisplayFormat.money($0) } ?? "不限制")
                    LabeledValue(label: "每月", value: group.monthlyLimitUSD.map { DisplayFormat.money($0) } ?? "不限制")
                }
            }
            Section("账号与容量") {
                // omitempty counts: a missing value is zero (00 §6.5).
                LabeledValue(label: "绑定账号", value: DisplayFormat.grouped(group.accountCount ?? 0))
                LabeledValue(label: "活跃账号", value: DisplayFormat.grouped(group.activeAccountCount ?? 0))
                LabeledValue(label: "限流账号", value: DisplayFormat.grouped(group.rateLimitedAccountCount ?? 0))
                if let capacity {
                    LabeledValue(label: "可调度账号并发", value: ratio(capacity.concurrencyUsed, capacity.concurrencyMax))
                    LabeledValue(label: "可调度账号会话", value: ratio(capacity.sessionsUsed, capacity.sessionsMax))
                    LabeledValue(label: "调度 RPM（自然分钟）", value: ratio(capacity.rpmUsed, capacity.rpmMax))
                }
                if let capacityDate { Text("容量更新：\(capacityDate.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
                if let capacityError { Text(capacityError).font(.caption).foregroundStyle(.secondary) }
                NavigationLink("查看与管理分组账号") { AccountsView(initialGroupID: group.id) }.accessibilityIdentifier("group.accounts")
            }
            Section("用量") {
                NavigationLink("统计分析") { AnalyticsView(groupID: group.id) }.accessibilityIdentifier("group.analytics")
                NavigationLink("请求记录") { RequestLogsView(groupID: group.id) }.accessibilityIdentifier("group.logs")
            }
            Section("管理") {
                Button("编辑分组") {
                    if let context = session, context.generation == model.sessionGeneration {
                        editor = GroupEditorTarget(group: group, context: context, siteName: model.activeProfile?.name ?? "")
                    }
                }.frame(minHeight: 44).accessibilityIdentifier("group.edit")
                Button(group.status == "active" ? "停用分组" : "启用分组") { confirmAction = .status(group.status == "active" ? "inactive" : "active") }
                    .frame(minHeight: 44).accessibilityIdentifier("group.status")
                Button("删除分组", role: .destructive) { confirmAction = .delete }.frame(minHeight: 44).accessibilityIdentifier("group.delete")
            }.disabled(busy || uncertainAction != nil)
            if uncertainAction != nil {
                Section("结果待确认") {
                    Text("请求不会自动重发。先读取服务器当前状态；关闭前请在本站后台核对，避免重复操作。")
                    Button("读取服务器状态核对") { Task { await reconcile() } }.disabled(busy).frame(minHeight: 44)
                }
            }
            if busy { ProgressView("正在处理…") }
            if let error { Section("处理结果") { Text(error).textSelection(.enabled).accessibilityIdentifier("group.result") } }
        }
        .navigationTitle(group.name)
        .task { await refresh() }
        .task { await refreshCapacity() }
        .refreshable { await refresh(); await refreshCapacity() }
        .onChange(of: model.foregroundRevision) { _, _ in Task { await refresh(); await refreshCapacity() } }
        .sheet(item: $editor, onDismiss: { Task { await refresh() } }) { GroupEditorView(target: $0).environment(workspace) }
        .confirmationDialog(confirmAction?.title ?? "确认操作", isPresented: Binding(get: { confirmAction != nil }, set: { if !$0 { confirmAction = nil } }), titleVisibility: .visible) {
            if let action = confirmAction { Button("确认发送", role: .destructive) { Task { await perform(action) } } }
        } message: {
            Text("站点：\(model.activeProfile?.name ?? "")\n地址：\(session?.client.server.baseURL.absoluteString ?? "")\n分组：\(group.name)（#\(group.id)）\n\(confirmAction == .delete ? "删除将解除此分组的关联，关联订阅等限制由服务器校验。" : "停用会影响该分组的请求和关联用户。")")
        }
    }
    private func ratio(_ used: Int?, _ max: Int?) -> String {
        guard let used, let max else { return DisplayFormat.missing }
        return "\(DisplayFormat.grouped(used)) / \(DisplayFormat.grouped(max))"
    }
    private func refresh() async {
        guard !busy, let context = session, context.generation == model.sessionGeneration else { return }
        let ticket = UUID(); readTicket = ticket
        do {
            let result = try await workspace.get(group.id, context: context, fixture: model.isUITesting)
            guard context.generation == model.sessionGeneration, readTicket == ticket, !Task.isCancelled else { return }
            group = result
        } catch {
            guard context.generation == model.sessionGeneration, readTicket == ticket, !(error is CancellationError), !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
    private func refreshCapacity() async {
        guard let context = session, context.generation == model.sessionGeneration, !model.isUITesting else { return }
        let ticket = UUID(); capacityTicket = ticket
        do {
            let result = try await context.client.groupCapacities().first { $0.groupID == group.id }
            guard context.generation == model.sessionGeneration, capacityTicket == ticket, !Task.isCancelled else { return }
            capacity = result; capacityDate = Date(); capacityError = result == nil ? "当前分组未提供容量数据。" : nil
        } catch {
            guard context.generation == model.sessionGeneration, capacityTicket == ticket, !(error is CancellationError), !Task.isCancelled else { return }
            capacityError = "容量刷新失败，保留上次数据。\(error.localizedDescription)"
        }
    }
    private func perform(_ action: GroupDetailAction) async {
        guard !busy, uncertainAction == nil, let context = session, context.generation == model.sessionGeneration else { return }
        busy = true; readTicket = UUID(); error = nil; defer { busy = false }
        do {
            let identity = await context.client.userWriteIdentity()
            guard context.generation == model.sessionGeneration, !Task.isCancelled else { return }
            switch action {
            case .delete: try await workspace.delete(group.id, identity: identity, context: context, fixture: model.isUITesting)
            case .status(let status):
                let result = try await workspace.update(group.id, input: GroupUpdateRequest(status: status), identity: identity, context: context, fixture: model.isUITesting)
                guard context.generation == model.sessionGeneration else { return }; group = result
            }
            guard context.generation == model.sessionGeneration else { return }
            if action == .delete { dismiss() } else { error = "分组状态已更新。" }
        } catch {
            guard context.generation == model.sessionGeneration, !(error is CancellationError) else { return }
            self.error = error.localizedDescription
            if !groupWriteDefinitelyRejected(error) { uncertainAction = action }
        }
    }
    private func reconcile() async {
        guard !busy, let action = uncertainAction, let context = session, context.generation == model.sessionGeneration else { return }
        busy = true; defer { busy = false }
        do {
            let result = try await workspace.get(group.id, context: context, fixture: model.isUITesting)
            guard context.generation == model.sessionGeneration, !Task.isCancelled else { return }
            group = result
            if case .status(let value) = action, result.status == value { uncertainAction = nil; error = "服务器当前状态已与目标一致。" }
            else { error = "分组仍存在，当前状态为\(result.status == "active" ? "启用" : "停用")。原请求是否仍在处理尚不确定，请先在 Web 核对；本页不会重发。" }
        } catch {
            guard context.generation == model.sessionGeneration, !(error is CancellationError) else { return }
            if action == .delete, (error as? APIError)?.statusCode == 404 { uncertainAction = nil; dismiss() }
            else { self.error = "核对未完成。\(error.localizedDescription)" }
        }
    }
}

private enum GroupDetailAction: Equatable {
    case status(String), delete
    var title: String { switch self { case .status(let value): value == "active" ? "确认启用分组？" : "确认停用分组？"; case .delete: "确认删除分组？" } }
}

private struct GroupEditorTarget: Identifiable {
    let id = UUID()
    let group: AdminGroup?
    let context: SessionContext
    let siteName: String
}

private enum PreparedGroupWrite {
    case create(GroupCreateRequest, UUID)
    case update(GroupUpdateRequest, UUID)
}

private struct GroupEditorView: View {
    let target: GroupEditorTarget
    @Environment(AppModel.self) private var model
    @Environment(GroupWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var platform = "openai"
    @State private var rate = "1"
    @State private var exclusive = false
    @State private var subscription = "standard"
    @State private var rpm = "0"
    @State private var daily = ""
    @State private var weekly = ""
    @State private var monthly = ""
    @State private var prepared: PreparedGroupWrite?
    @State private var confirming = false
    @State private var busy = false
    @State private var uncertain = false
    @State private var reconciled = false
    @State private var message: String?
    @State private var discardAlert = false
    private var isCurrent: Bool { target.context.generation == model.sessionGeneration && target.context.serverID == model.activeProfile?.id }
    init(target: GroupEditorTarget) {
        self.target = target
        if let group = target.group {
            _name = State(initialValue: group.name); _description = State(initialValue: group.description ?? ""); _platform = State(initialValue: group.platform)
            _rate = State(initialValue: group.rateMultiplier.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
            _exclusive = State(initialValue: group.isExclusive ?? false); _subscription = State(initialValue: group.subscriptionType ?? "standard")
            _rpm = State(initialValue: group.rpmLimit.map(String.init) ?? "")
            _daily = State(initialValue: group.dailyLimitUSD.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
            _weekly = State(initialValue: group.weeklyLimitUSD.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
            _monthly = State(initialValue: group.monthlyLimitUSD.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("目标站点") {
                    LabeledValue(label: "站点", value: target.siteName)
                    Text(target.context.client.server.baseURL.absoluteString).font(.caption).foregroundStyle(.secondary)
                }
                Section("基本设置") {
                    TextField("分组名称", text: $name).accessibilityIdentifier("group-editor.name")
                    TextField("描述（可选）", text: $description, axis: .vertical).accessibilityIdentifier("group-editor.description")
                    if target.group == nil {
                        Picker("平台", selection: $platform) {
                            ForEach(GroupPlatform.values, id: \.self) { Text(GroupPlatform.title($0)).tag($0) }
                        }.accessibilityIdentifier("group-editor.platform")
                    } else { LabeledValue(label: "平台", value: GroupPlatform.title(platform)) }
                    Toggle("专属分组", isOn: $exclusive).accessibilityIdentifier("group-editor.exclusive")
                }.disabled(busy || uncertain || reconciled)
                Section {
                    Picker("计费类型", selection: $subscription) { Text("按量").tag("standard"); Text("订阅").tag("subscription") }.accessibilityIdentifier("group-editor.subscription")
                    TextField("计费倍率", text: $rate).keyboardType(.decimalPad).accessibilityIdentifier("group-editor.rate")
                    TextField("RPM 限额（0 表示不限制）", text: $rpm).keyboardType(.numberPad).accessibilityIdentifier("group-editor.rpm")
                    if subscription == "subscription" {
                        TextField("每日限额 USD（留空不限制）", text: $daily).keyboardType(.decimalPad).accessibilityIdentifier("group-editor.daily")
                        TextField("每周限额 USD（留空不限制）", text: $weekly).keyboardType(.decimalPad).accessibilityIdentifier("group-editor.weekly")
                        TextField("每月限额 USD（留空不限制）", text: $monthly).keyboardType(.decimalPad).accessibilityIdentifier("group-editor.monthly")
                    }
                } header: { Text("计费与限额") } footer: {
                    Text("编辑仅提交变更字段。模型路由、模型价格、利润控制等高级配置保留服务器设置；可在当前站点 Web 后台管理。")
                }.disabled(busy || uncertain || reconciled)
                Section {
                    if uncertain {
                        Text("请求结果尚未确认，不会自动重发或新建相同请求。")
                        Button("读取服务器状态核对") { Task { await reconcile() } }.frame(minHeight: 44).accessibilityIdentifier("group-editor.reconcile")
                    } else if !reconciled {
                        Button("核对并确认") { Task { await prepare() } }.frame(minHeight: 44).accessibilityIdentifier("group-editor.prepare")
                    }
                    if busy { ProgressView("正在处理，请勿重复提交…") }
                    if let message { Text(message).textSelection(.enabled).accessibilityIdentifier("group-editor.result") }
                }.disabled(busy || !isCurrent)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(target.group == nil ? "创建分组" : "编辑分组")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { if uncertain { discardAlert = true } else { dismiss() } }.disabled(busy).accessibilityIdentifier("group-editor.close")
            } }
            .interactiveDismissDisabled(busy || uncertain)
            .confirmationDialog(target.group == nil ? "确认创建分组？" : "确认修改分组？", isPresented: $confirming, titleVisibility: .visible) {
                Button("确认发送", role: .destructive) { Task { await send() } }
            } message: {
                Text("站点：\(target.siteName)\n地址：\(target.context.client.server.baseURL.absoluteString)\n分组：\(name)\(target.group.map { "（#\($0.id)）" } ?? "")\n平台：\(GroupPlatform.title(platform))\n计费倍率：\(rate)\nRPM 限额：\(rpm)")
            }
            .alert("请求结果尚未确认", isPresented: $discardAlert) {
                Button("继续核对", role: .cancel) { }
                Button("关闭并手动核对", role: .destructive) { dismiss() }
            } message: { Text("请先在当前站点确认实际分组状态，再进行相同操作。关闭后不会重发本次请求。") }
            .onChange(of: model.sessionGeneration) { _, _ in prepared = nil; dismiss() }
        }
    }
    private func decimal(_ raw: String, label: String) throws -> Decimal {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[0-9]+([.][0-9]+)?$"#, options: .regularExpression) != nil,
              let parsed = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), !parsed.isNaN else { throw AppFailure("\(label)须为有效的非负十进制数。") }
        return parsed
    }
    private func limit(_ raw: String) throws -> GroupLimitChange { raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .unlimited : .amount(try decimal(raw, label: "订阅限额")) }
    private func limitChange(_ raw: String, previous: Decimal?) throws -> GroupLimitChange? {
        let change = try limit(raw)
        switch change { case .unlimited: return previous == nil ? nil : change; case .amount(let value): return value == previous ? nil : change }
    }
    private func prepare() async {
        guard !busy, !uncertain, !reconciled, isCurrent else { return }
        busy = true; defer { busy = false }
        do {
            let identity = await target.context.client.userWriteIdentity()
            guard isCurrent, !Task.isCancelled else { return }
            let rpmText = rpm.trimmingCharacters(in: .whitespacesAndNewlines)
            // Legacy responses may omit these fields. Unchanged blank values must remain omitted.
            let changedRPM = target.group?.rpmLimit.map(String.init) != rpmText && !(target.group?.rpmLimit == nil && rpmText.isEmpty)
            var parsedRPM: Int?
            if target.group == nil || changedRPM {
                guard !rpmText.isEmpty, rpmText.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(rpmText), value <= Int(Int32.max) else { throw AppFailure("RPM 限额须为 0 至 2147483647 的整数。") }
                parsedRPM = value
            }
            let parsedRate = rate.isEmpty && target.group?.rateMultiplier == nil ? nil : try decimal(rate, label: "计费倍率")
            if let old = target.group {
                let input = GroupUpdateRequest(name: name == old.name ? nil : name, description: description == (old.description ?? "") ? nil : description,
                    rateMultiplier: parsedRate == old.rateMultiplier ? nil : parsedRate, isExclusive: exclusive == (old.isExclusive ?? false) ? nil : exclusive,
                    subscriptionType: subscription == (old.subscriptionType ?? "standard") ? nil : subscription, rpmLimit: parsedRPM,
                    dailyLimitUSD: subscription == "subscription" ? try limitChange(daily, previous: old.dailyLimitUSD) : nil,
                    weeklyLimitUSD: subscription == "subscription" ? try limitChange(weekly, previous: old.weeklyLimitUSD) : nil,
                    monthlyLimitUSD: subscription == "subscription" ? try limitChange(monthly, previous: old.monthlyLimitUSD) : nil)
                try input.validate(); prepared = .update(input, identity)
            } else {
                guard let parsedRate, let parsedRPM else { throw AppFailure("请填写计费倍率和 RPM 限额。") }
                let input = GroupCreateRequest(name: name, description: description, platform: platform, rateMultiplier: parsedRate, isExclusive: exclusive,
                    subscriptionType: subscription, rpmLimit: parsedRPM, dailyLimitUSD: try limit(daily), weeklyLimitUSD: try limit(weekly), monthlyLimitUSD: try limit(monthly))
                try input.validate(); prepared = .create(input, identity)
            }
            message = nil; confirming = true
        } catch { message = error.localizedDescription }
    }
    private func send() async {
        guard !busy, !uncertain, isCurrent, let prepared else { return }
        busy = true; defer { busy = false }
        do {
            switch prepared {
            case .create(let input, let identity): _ = try await workspace.create(input, identity: identity, context: target.context, fixture: model.isUITesting)
            case .update(let input, let identity):
                guard let id = target.group?.id else { return }
                _ = try await workspace.update(id, input: input, identity: identity, context: target.context, fixture: model.isUITesting)
            }
            guard isCurrent else { return }; self.prepared = nil; dismiss()
        } catch {
            guard isCurrent, !(error is CancellationError) else { return }
            message = error.localizedDescription
            if groupWriteDefinitelyRejected(error) { self.prepared = nil }
            else { uncertain = true; message = "\(error.localizedDescription)\n结果待确认。原请求仅保留在本页内存中，不会自动重试。" }
        }
    }
    private func reconcile() async {
        guard !busy, uncertain, isCurrent, let prepared else { return }
        busy = true; defer { busy = false }
        do {
            switch prepared {
            case .update(let input, _):
                guard let id = target.group?.id else { return }
                let result = try await workspace.get(id, context: target.context, fixture: model.isUITesting)
                guard isCurrent, !Task.isCancelled else { return }
                if input.matches(result) { message = "服务器当前字段已与本次修改一致，可关闭此页。"; uncertain = false; reconciled = true; self.prepared = nil }
                else { message = "服务器当前字段与目标仍不一致。原请求可能仍在处理，请在本站 Web 后台核对；本页不会重发。" }
            case .create(let input, _):
                let result = try await workspace.list(context: target.context, fixture: model.isUITesting, page: 1, search: input.name, platform: input.platform, status: "")
                guard isCurrent, !Task.isCancelled else { return }
                let exact = result.items.filter { $0.name == input.name }.map { "#\($0.id) \($0.name)" }.joined(separator: "、")
                message = exact.isEmpty ? "当前查询尚未发现同名分组，仍无法确认原创建请求是否完成。请在 Web 核对后再操作。" : "查询到同名分组：\(exact)。同名不能证明是本次创建，请在 Web 核对；本页不会重复创建。"
            }
        } catch { guard isCurrent, !(error is CancellationError) else { return }; message = "核对未完成。\(error.localizedDescription)" }
    }
}

private func groupWriteDefinitelyRejected(_ error: any Error) -> Bool {
    guard let failure = error as? APIError else { return false }
    return failure.kind == .validation || [400, 401, 403, 404, 422, 423, 429].contains(failure.statusCode ?? 0)
}
