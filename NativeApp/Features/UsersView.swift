import SwiftUI
import Sub2Core

struct UsersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var users: [AdminUser] = []
    @State private var search = ""
    @State private var status = ""
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var failedPage: Int?
    @State private var requestID = UUID()
    private var query: String { search + "|" + status }
    var body: some View {
        List {
            Section {
                Picker("状态", selection: $status) {
                    Text("全部状态").tag(""); Text("正常").tag("active"); Text("已禁用").tag("disabled")
                }
            }
            Section("用户") {
                ForEach(users) { user in
                    NavigationLink { UserDetailView(initial: user) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(user.username.flatMap { $0.isEmpty ? nil : $0 } ?? user.email).font(.headline)
                            Text(user.email).font(.caption).foregroundStyle(.secondary)
                            HStack { Text(money(user.balance)); Spacer(); Text(user.status == "active" ? "正常" : user.status).foregroundStyle(.secondary) }.font(.subheadline)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("user.\(user.id)")
                }
                if users.isEmpty && !loading && error == nil { Text("没有符合条件的用户").foregroundStyle(.secondary) }
                if hasMore { Button("加载更多用户") { Task { await load(nextPage: page + 1) } }.disabled(loading).frame(minHeight: 44).accessibilityIdentifier("users.more") }
                if loading { ProgressView("正在加载…") }
                if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await load(nextPage: failedPage ?? 1, replace: (failedPage ?? 1) == 1) } }.frame(minHeight: 44) }
            }
        }
        .navigationTitle("用户")
        .searchable(text: $search, prompt: "搜索邮箱或用户名")
        .refreshable { await load(nextPage: 1, replace: true) }
        .task(id: query) {
            requestID = UUID(); loading = false
            page = 0; hasMore = false; users = []; error = nil; failedPage = nil
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await load(nextPage: 1, replace: true)
        }
    }
    private func load(nextPage: Int, replace: Bool = false) async {
        guard !loading else { return }
        let ticket = UUID(); requestID = ticket
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        loading = true; error = nil
        defer { if requestID == ticket { loading = false } }
        do {
            let result = try await model.users(page: nextPage, search: search, status: status.isEmpty ? nil : status)
            guard generation == model.sessionGeneration, requestID == ticket, !Task.isCancelled else { return }
            users = replace ? result.items : users + result.items.filter { next in !users.contains { $0.id == next.id } }
            page = result.page; hasMore = result.hasMore; failedPage = nil
        } catch { if generation == model.sessionGeneration && requestID == ticket && !(error is CancellationError) { self.error = error.localizedDescription; failedPage = nextPage } }
    }
}

struct UserDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @State private var user: AdminUser
    @State private var usage: UserUsageSummary?
    @State private var keys: [UserAPIKey] = []
    @State private var keysPage = 0
    @State private var moreKeys = false
    @State private var loadingKeys = false
    @State private var error: String?
    @State private var busy = false
    @State private var confirmStatus = false
    @State private var balanceSheet = false
    @State private var stepUp = false
    init(initial: AdminUser) { _user = State(initialValue: initial) }
    var body: some View {
        List {
            Section("用户详情") {
                LabeledValue(label: "邮箱", value: user.email)
                if let username = user.username { LabeledValue(label: "用户名", value: username) }
                LabeledValue(label: "角色", value: user.role ?? "未知")
                LabeledValue(label: "状态", value: user.status)
                LabeledValue(label: "余额", value: money(user.balance))
                if let concurrency = user.concurrency { LabeledValue(label: "并发", value: String(concurrency)) }
            }
            Section("本月用量") {
                if let usage {
                    LabeledValue(label: "请求", value: usage.totalRequests.formatted())
                    LabeledValue(label: "Tokens", value: usage.totalTokens.formatted())
                    LabeledValue(label: "费用", value: money(usage.totalCost))
                } else { Text("暂未加载").foregroundStyle(.secondary) }
            }
            Section("API Key") {
                ForEach(keys) { key in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(key.name).font(.headline)
                        Text(key.key.map { "••••••••" + String($0.suffix(4)) } ?? "••••••••")
                            .font(.system(.caption, design: .monospaced)).privacySensitive()
                        Text("\(key.status) · 已用 \(money(key.quotaUsed)) / 配额 \(money(key.quota))").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                if keys.isEmpty && !loadingKeys { Text("暂无 API Key").foregroundStyle(.secondary) }
                if moreKeys { Button("加载更多密钥") { Task { await loadKeys(page: keysPage + 1) } }.disabled(loadingKeys).frame(minHeight: 44) }
                if loadingKeys { ProgressView() }
            }
            Section("管理操作") {
                Button(user.status == "active" ? "禁用用户" : "启用用户") { confirmStatus = true }.frame(minHeight: 44)
                Button("调整余额") { balanceSheet = true }.frame(minHeight: 44).accessibilityIdentifier("user.balance")
                if model.pendingBalances.contains(where: { $0.serverID == model.activeProfile?.id && $0.userID == user.id }) {
                    Label("此用户存在结果待确认的余额请求，请打开余额页面处理原请求。", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }.disabled(busy)
            if busy { ProgressView("正在处理…") }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(user.username ?? "用户 #\(user.id)")
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog(user.status == "active" ? "禁用用户？" : "启用用户？", isPresented: $confirmStatus, titleVisibility: .visible) {
            Button("确认操作", role: .destructive) { Task { await changeStatus() } }
        } message: { Text("站点：\(model.activeProfile?.name ?? "")\n用户：\(user.email)（#\(user.id)）") }
        .sheet(isPresented: $balanceSheet, onDismiss: { Task { await reload() } }) { BalanceView(user: user) }
        .sheet(isPresented: $stepUp) { if let client = session?.client { StepUpView(client: client) { error = "验证通过，请重新确认用户操作。" } } }
    }
    private func reload() async {
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        do {
            let result = try await model.user(id: user.id)
            guard generation == model.sessionGeneration, !Task.isCancelled else { return }; user = result
            let statistics = try await model.userUsage(id: user.id)
            guard generation == model.sessionGeneration, !Task.isCancelled else { return }; usage = statistics
            error = nil
            await loadKeys(page: 1)
        } catch { if generation == model.sessionGeneration && !(error is CancellationError) { self.error = error.localizedDescription } }
    }
    private func loadKeys(page: Int) async {
        guard !loadingKeys else { return }; loadingKeys = true
        defer { loadingKeys = false }
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        do {
            let result = try await model.userKeys(id: user.id, page: page)
            guard generation == model.sessionGeneration, !Task.isCancelled else { return }
            keys = page == 1 ? result.items : keys + result.items.filter { item in !keys.contains { $0.id == item.id } }
            keysPage = result.page; moreKeys = result.hasMore
        } catch { if generation == model.sessionGeneration && !(error is CancellationError) { self.error = error.localizedDescription } }
    }
    private func changeStatus() async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        do {
            guard !model.isUITesting else { throw AppFailure("界面测试模式不执行服务器写操作。") }
            guard let client = session?.client else { return }
            let result = try await client.setUserStatus(id: user.id, status: user.status == "active" ? "disabled" : "active")
            guard generation == model.sessionGeneration else { return }; user = result; error = nil
        } catch { guard generation == model.sessionGeneration else { return }; if needsStepUp(error) { stepUp = true } else { self.error = error.localizedDescription } }
    }
}

struct BalanceView: View {
    let user: AdminUser
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var operation = BalanceOperation.add
    @State private var notes = ""
    @State private var message: String?
    @State private var confirm = false
    @State private var prepared: PendingBalanceOperation?
    @State private var busy = false
    @State private var stepUp = false
    private var pending: [PendingBalanceOperation] { model.pendingBalances.filter { $0.userID == user.id && $0.serverID == model.activeProfile?.id } }
    var body: some View {
        NavigationStack {
            Form {
                Section("目标") {
                    LabeledValue(label: "站点", value: model.activeProfile?.name ?? "")
                    LabeledValue(label: "用户", value: user.email)
                    LabeledValue(label: "当前余额", value: money(user.balance))
                }
                if !pending.isEmpty {
                    Section("结果待确认的请求") {
                        Text("不要重新创建请求。使用原始请求重试会保留相同操作编号及金额，避免重复扣加余额。")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(pending) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(operationName(item.operation)) \(money(item.amount))").font(.headline)
                                Text("操作编号：\(item.id.uuidString)").font(.caption).textSelection(.enabled)
                                if !item.notes.isEmpty { Text(item.notes).font(.caption) }
                                Button("确认并重试原请求") { prepared = item; confirm = true }.frame(minHeight: 44)
                            }.padding(.vertical, 4)
                        }
                    }.disabled(busy)
                } else {
                    Section("调整") {
                        Picker("操作", selection: $operation) {
                            ForEach(BalanceOperation.allCases, id: \.self) { item in Text(operationName(item)).tag(item) }
                        }
                        TextField("金额，例如 12.50", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("balance.amount")
                        TextField("备注（可选）", text: $notes, axis: .vertical)
                        Button("核对并确认") { prepare() }.frame(minHeight: 44).accessibilityIdentifier("balance.prepare")
                    }.disabled(busy)
                }
                if busy { ProgressView("正在发送原请求，请勿重复操作…") }
                if let message { Section("处理结果") { Text(message).textSelection(.enabled) } }
            }
            .navigationTitle("调整余额")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .confirmationDialog("确认调整余额？", isPresented: $confirm, titleVisibility: .visible) {
                Button("确认发送", role: .destructive) { if let prepared { Task { await send(prepared) } } }
            } message: {
                if let prepared { Text("站点：\(model.activeProfile?.name ?? "")\n用户：\(user.email)\n\(operationName(prepared.operation))：\(money(prepared.amount))") }
            }
            .sheet(isPresented: $stepUp) { if let client = session?.client { StepUpView(client: client) { message = "验证通过，请点击“重试原请求”并重新确认。" } } }
        }
    }
    private func operationName(_ value: BalanceOperation) -> String {
        switch value { case .add: "增加"; case .subtract: "减少"; case .set: "设置为" }
    }
    private func prepare() {
        let raw = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.range(of: "^[0-9]+([.][0-9]+)?$", options: .regularExpression) != nil,
              let decimal = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), decimal >= 0,
              NSDecimalNumber(decimal: decimal).stringValue != "NaN", let serverID = model.activeProfile?.id else {
            message = "请输入有效的非负十进制金额。"; return
        }
        let candidate = PendingBalanceOperation(serverID: serverID, userID: user.id, amount: decimal, operation: operation, notes: notes)
        do { try candidate.validate() }
        catch { message = error.localizedDescription; return }
        prepared = candidate
        confirm = true; message = nil
    }
    private func send(_ item: PendingBalanceOperation) async {
        guard !busy, item.serverID == model.activeProfile?.id else { return }
        busy = true; defer { busy = false }
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        var submitted = false
        do {
            guard !model.isUITesting else { throw AppFailure("界面测试模式不执行余额写入。") }
            guard let client = session?.client else { return }
            try model.remember(item)
            submitted = true
            let result = try await client.updateBalance(item)
            // Resolve the exact server-bound operation even if the user has switched sites.
            try model.resolve(item)
            guard generation == model.sessionGeneration else { return }
            message = "操作成功，余额为 \(money(result.balance))。"; prepared = nil; amount = ""; notes = ""
        } catch {
            guard generation == model.sessionGeneration else { return }
            if !submitted { message = "请求未发送。\n\(error.localizedDescription)" }
            else if needsStepUp(error) { stepUp = true }
            else if definitelyRejected(error) {
                do { try model.resolve(item); prepared = nil; message = "请求已被拒绝，余额未调整。\n\(error.localizedDescription)" }
                catch { message = "拒绝结果已收到，但无法更新本机记录。请检查设备存储，保留原操作编号。" }
            } else { message = "\(error.localizedDescription)\n如请求已经发送，结果仍待确认。请保留并重试原操作。" }
        }
    }
    private func definitelyRejected(_ error: Error) -> Bool {
        guard let failure = error as? APIError else { return false }
        if failure.kind == .validation { return true }
        if failure.statusCode == 401 || failure.statusCode == 403 { return true }
        let reason = failure.reason?.uppercased() ?? ""
        return failure.statusCode == 400 && ["VALIDATION_ERROR", "INVALID_REQUEST", "INVALID_AMOUNT", "BAD_REQUEST"].contains(reason)
    }
}
