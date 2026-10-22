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
    @State private var fieldSelection = ListFieldSelection<UserListField>()
    @State private var editingFields = false
    @State private var fieldProfileID: UUID?
    @State private var editorTarget: UserEditorTarget?
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
                            Text(user.email).font(.headline)
                            ListFieldFlow {
                                ForEach(fieldSelection.visibleFields, id: \.rawValue) { field in
                                    Text("\(field.title)：\(userFieldValue(field, user: user))")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("user.\(user.id).field.\(field.rawValue)")
                                }
                            }
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
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("显示字段", systemImage: "line.3.horizontal.decrease") { editingFields = true }
                    .accessibilityIdentifier("users.fields")
                Button("创建用户", systemImage: "plus") {
                    if let session, session.generation == model.sessionGeneration {
                        editorTarget = UserEditorTarget(user: nil, context: session, siteName: model.activeProfile?.name ?? "")
                    }
                }.accessibilityIdentifier("users.create")
            }
        }
        .sheet(isPresented: $editingFields) { ListFieldEditor(title: "用户列表字段", selection: $fieldSelection) }
        .sheet(item: $editorTarget, onDismiss: { Task { await load(nextPage: 1, replace: true) } }) { UserEditorView(target: $0) }
        .task(id: model.activeProfile?.id) {
            fieldProfileID = model.activeProfile?.id
            fieldSelection = ListFieldSelection(rawValue: UserDefaults.standard.string(forKey: ListFieldSelection<UserListField>.storageKey(profileID: fieldProfileID)))
        }
        .onChange(of: fieldSelection) { _, value in
            guard fieldProfileID == model.activeProfile?.id else { return }
            UserDefaults.standard.set(value.rawValue, forKey: ListFieldSelection<UserListField>.storageKey(profileID: fieldProfileID))
        }
        .searchable(text: $search, prompt: "搜索邮箱或用户名")
        .refreshable { await load(nextPage: 1, replace: true) }
        .task(id: query) {
            requestID = UUID(); loading = false
            page = 0; hasMore = false; users = []; error = nil; failedPage = nil
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await load(nextPage: 1, replace: true)
        }
    }
    private func userFieldValue(_ field: UserListField, user: AdminUser) -> String {
        switch field {
        case .username: return user.username.flatMap { $0.isEmpty ? nil : $0 } ?? "未设置"
        case .role: return AdminUserRole(rawValue: user.role ?? "")?.title ?? user.role ?? "未知"
        case .status: return user.status == "active" ? "正常" : user.status == "disabled" ? "已禁用" : user.status
        case .balance: return DisplayFormat.money(user.balance)
        case .concurrency:
            if let maximum = user.concurrency {
                let limit = maximum == 0 ? "不限制" : DisplayFormat.grouped(maximum)
                if let current = user.currentConcurrency { return "\(DisplayFormat.grouped(current)) / \(limit)" }
                return limit
            }
            return DisplayFormat.missing
        case .createdAt: return ListFieldPresentation.timestamp(user.createdAt)
        case .lastUsedAt: return ListFieldPresentation.timestamp(user.lastUsedAt)
        case .lastActiveAt: return ListFieldPresentation.timestamp(user.lastActiveAt)
        case .notes: return user.notes.flatMap { $0.isEmpty ? nil : $0 } ?? "无"
        case .rpm: return user.rpmLimit.map { $0 == 0 ? "不限制" : DisplayFormat.grouped($0) } ?? DisplayFormat.missing
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
    @State private var editorTarget: UserEditorTarget?
    init(initial: AdminUser) { _user = State(initialValue: initial) }
    var body: some View {
        List {
            Section("用户详情") {
                LabeledValue(label: "邮箱", value: user.email)
                if let username = user.username { LabeledValue(label: "用户名", value: username) }
                LabeledValue(label: "角色", value: user.role ?? "未知")
                LabeledValue(label: "状态", value: user.status)
                LabeledValue(label: "余额", value: DisplayFormat.money(user.balance))
                if let concurrency = user.concurrency { LabeledValue(label: "并发", value: String(concurrency)) }
                if let rpm = user.rpmLimit { LabeledValue(label: "RPM 限额", value: rpm == 0 ? "不限制" : String(rpm)) }
                if let notes = user.notes, !notes.isEmpty { LabeledValue(label: "备注", value: notes) }
                LabeledValue(label: "创建时间", value: ListFieldPresentation.timestamp(user.createdAt))
                LabeledValue(label: "最后使用", value: ListFieldPresentation.timestamp(user.lastUsedAt))
                LabeledValue(label: "最后活跃", value: ListFieldPresentation.timestamp(user.lastActiveAt))
            }
            Section("本月用量") {
                if let usage {
                    LabeledValue(label: "请求", value: DisplayFormat.grouped(usage.totalRequests))
                    LabeledValue(label: "Tokens", value: DisplayFormat.compact(usage.totalTokens))
                    LabeledValue(label: "费用", value: DisplayFormat.money(usage.totalCost))
                } else { Text("暂未加载").foregroundStyle(.secondary) }
            }
            Section("API Key") {
                ForEach(keys) { key in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(key.name).font(.headline)
                        Text(key.key.map { "••••••••" + String($0.suffix(4)) } ?? "••••••••")
                            .font(.system(.caption, design: .monospaced)).privacySensitive()
                        Text("\(key.status) · 已用 \(DisplayFormat.money(key.quotaUsed)) / 配额 \(DisplayFormat.money(key.quota))").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                if keys.isEmpty && !loadingKeys { Text("暂无 API Key").foregroundStyle(.secondary) }
                if moreKeys { Button("加载更多密钥") { Task { await loadKeys(page: keysPage + 1) } }.disabled(loadingKeys).frame(minHeight: 44) }
                if loadingKeys { ProgressView() }
            }
            Section("管理操作") {
                Button("编辑用户") {
                    if let session, session.generation == model.sessionGeneration {
                        editorTarget = UserEditorTarget(user: user, context: session, siteName: model.activeProfile?.name ?? "")
                    }
                }.frame(minHeight: 44).accessibilityIdentifier("user.edit")
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
        .sheet(item: $editorTarget, onDismiss: { Task { await reload() } }) { UserEditorView(target: $0) }
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

private struct UserEditorTarget: Identifiable {
    let id = UUID()
    let user: AdminUser?
    let context: SessionContext
    let siteName: String
}

private enum PreparedUserMutation {
    case create(PendingUserCreateOperation)
    case update(PendingUserUpdateOperation)
    var id: UUID {
        switch self {
        case .create(let operation): operation.id
        case .update(let operation): operation.id
        }
    }
    /// Sent with an Idempotency-Key, so the same number can be retried.
    var supportsSafeRetry: Bool {
        switch self {
        case .create(let operation): operation.sendsIdempotencyKey
        case .update(let operation): operation.supportsSafeRetry
        }
    }
}

private struct UserEditorView: View {
    let target: UserEditorTarget
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var username: String
    @State private var password = ""
    @State private var role: String
    @State private var notes: String
    @State private var concurrency: String
    @State private var rpmLimit: String
    @State private var initialBalance = ""
    @State private var adjustmentNotes = ""
    @State private var prepared: PreparedUserMutation?
    @State private var busy = false
    @State private var confirming = false
    @State private var stepUp = false
    @State private var uncertain = false
    @State private var discardAlert = false
    @State private var message: String?

    init(target: UserEditorTarget) {
        self.target = target
        _email = State(initialValue: target.user?.email ?? "")
        _username = State(initialValue: target.user?.username ?? "")
        _role = State(initialValue: target.user?.role ?? AdminUserRole.user.rawValue)
        _notes = State(initialValue: target.user?.notes ?? "")
        _concurrency = State(initialValue: target.user?.concurrency.map(String.init) ?? (target.user == nil ? "1" : ""))
        _rpmLimit = State(initialValue: target.user?.rpmLimit.map(String.init) ?? (target.user == nil ? "0" : ""))
    }
    private var isCurrent: Bool {
        target.context.generation == model.sessionGeneration && target.context.serverID == model.activeProfile?.id
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("目标") {
                    LabeledValue(label: "站点", value: target.siteName)
                    LabeledValue(label: "地址", value: target.context.client.server.baseURL.absoluteString)
                    if let user = target.user { LabeledValue(label: "用户", value: "\(user.email)（#\(user.id)）") }
                }
                Section {
                    TextField("邮箱", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("user-editor.email")
                    TextField("用户名", text: $username).textContentType(.username).autocorrectionDisabled()
                        .accessibilityIdentifier("user-editor.username")
                    SecureField(target.user == nil ? "密码（至少 6 个字符）" : "新密码（留空不修改）", text: $password)
                        .textContentType(.newPassword).privacySensitive().accessibilityIdentifier("user-editor.password")
                    Picker("角色", selection: $role) {
                        ForEach(AdminUserRole.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        if AdminUserRole(rawValue: role) == nil { Text("未知角色：\(role)").tag(role) }
                    }.accessibilityIdentifier("user-editor.role")
                    TextField("管理员备注", text: $notes, axis: .vertical).accessibilityIdentifier("user-editor.notes")
                } header: { Text("基本信息") } footer: {
                    Text("密码只在本次表单和请求内存中保留，关闭后清除。提升或创建管理员时，站点可能要求二次验证。")
                }.disabled(busy || prepared != nil)
                Section {
                    TextField("最大并发（0 表示不限制）", text: $concurrency).keyboardType(.numberPad)
                        .accessibilityIdentifier("user-editor.concurrency")
                    TextField("RPM 限额（0 表示不限制）", text: $rpmLimit).keyboardType(.numberPad)
                        .accessibilityIdentifier("user-editor.rpm")
                    if target.user == nil {
                        TextField("初始余额（留空使用站点默认值）", text: $initialBalance).keyboardType(.decimalPad)
                            .accessibilityIdentifier("user-editor.initial-balance")
                    } else {
                        TextField("并发调整备注（可选）", text: $adjustmentNotes, axis: .vertical)
                            .accessibilityIdentifier("user-editor.adjustment-notes")
                    }
                } header: { Text("限额") } footer: {
                    Text("并发和 RPM 接受非负整数。编辑只提交实际变更的字段；余额调整仍在独立余额页面处理。")
                }.disabled(busy || prepared != nil)
                Section {
                    if let prepared {
                        if prepared.supportsSafeRetry {
                            Text("操作编号：\(prepared.id.uuidString.lowercased())").font(.caption).textSelection(.enabled)
                        }
                        if !uncertain || prepared.supportsSafeRetry {
                            Button(uncertain ? "核对并重试原请求" : "核对并确认发送") { confirming = true }
                                .frame(minHeight: 44).accessibilityIdentifier("user-editor.send")
                        }
                        if !uncertain {
                            Button("返回修改") { self.prepared = nil; password = ""; message = nil }
                                .frame(minHeight: 44)
                        }
                    } else {
                        Button("核对并确认") { Task { await prepare() } }
                            .frame(minHeight: 44).accessibilityIdentifier("user-editor.prepare")
                    }
                    if busy { ProgressView("正在处理，请勿重复提交…") }
                }.disabled(busy || !isCurrent)
                if let message { Section("处理结果") { Text(message).textSelection(.enabled).accessibilityIdentifier("user-editor.result") } }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(target.user == nil ? "创建用户" : "编辑用户")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { if uncertain { discardAlert = true } else { dismiss() } }.disabled(busy).accessibilityIdentifier("user-editor.close")
            } }
            .interactiveDismissDisabled(busy || uncertain)
            .confirmationDialog(target.user == nil ? "确认创建用户？" : "确认修改用户？", isPresented: $confirming, titleVisibility: .visible) {
                Button("确认发送", role: .destructive) { Task { await send() } }
            } message: {
                Text("站点：\(target.siteName)\n地址：\(target.context.client.server.baseURL.absoluteString)\n用户：\(email)\(target.user.map { "（#\($0.id)）" } ?? "")\n角色：\(AdminUserRole(rawValue: role)?.title ?? role)\n最大并发：\(concurrency.isEmpty ? "保持原值" : concurrency)\nRPM：\(rpmLimit.isEmpty ? "保持原值" : rpmLimit)")
            }
            .alert("请求结果尚未确认", isPresented: $discardAlert) {
                Button("保留原请求", role: .cancel) { }
                Button("关闭并手动核对", role: .destructive) { password = ""; prepared = nil; dismiss() }
            } message: {
                Text("关闭会清除内存中的原始请求和密码。请先保存操作编号（如有）；关闭后先在列表或 Web 核对实际状态，不要新建相同操作。")
            }
            .sheet(isPresented: $stepUp) {
                StepUpView(client: target.context.client) {
                    guard isCurrent else { return }
                    message = "二次验证通过。原请求尚未重发，请再次核对并确认发送。"
                }
            }
            .onChange(of: model.sessionGeneration) { _, _ in password = ""; prepared = nil; dismiss() }
            .onDisappear { password = ""; prepared = nil }
        }
    }

    private func integer(_ raw: String) throws -> Int {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }), let parsed = Int(value), parsed <= Int(Int32.max) else {
            throw AppFailure("并发和 RPM 必须是 0 至 2147483647 的整数。")
        }
        return parsed
    }
    private func prepare() async {
        guard !busy, isCurrent else { return }
        busy = true; defer { busy = false }
        do {
            let identity = await target.context.client.userWriteIdentity()
            guard isCurrent, !Task.isCancelled else { return }
            if let user = target.user {
                let maxConcurrency = concurrency == (user.concurrency.map(String.init) ?? "") ? nil : try integer(concurrency)
                let rpm = rpmLimit == (user.rpmLimit.map(String.init) ?? "") ? nil : try integer(rpmLimit)
                let changedRole = role == user.role ? nil : AdminUserRole(rawValue: role)
                let changes = UserUpdateRequest(
                    email: email == user.email ? nil : email, password: password.isEmpty ? nil : password,
                    username: username == (user.username ?? "") ? nil : username,
                    notes: notes == (user.notes ?? "") ? nil : notes,
                    role: changedRole, concurrency: maxConcurrency, rpmLimit: rpm,
                    adjustmentNotes: maxConcurrency == nil || adjustmentNotes.isEmpty ? nil : adjustmentNotes)
                prepared = .update(try PendingUserUpdateOperation(serverID: target.context.serverID, identity: identity, userID: user.id, request: changes))
            } else {
                guard let selectedRole = AdminUserRole(rawValue: role) else { throw AppFailure("请选择有效的角色。") }
                let rawBalance = initialBalance.trimmingCharacters(in: .whitespacesAndNewlines)
                var balance: Decimal?
                if !rawBalance.isEmpty {
                    guard rawBalance.range(of: "^[0-9]+([.][0-9]+)?$", options: .regularExpression) != nil,
                          let value = Decimal(string: rawBalance, locale: Locale(identifier: "en_US_POSIX")) else { throw APIError.invalidAmount }
                    balance = value
                }
                let input = UserCreateRequest(email: email, password: password, username: username, notes: notes, role: selectedRole,
                    concurrency: try integer(concurrency), rpmLimit: try integer(rpmLimit), balance: balance)
                // S0-10 passes admin.idempotent_writes here (D24); until then creation is sent without a key.
                prepared = .create(try PendingUserCreateOperation(serverID: target.context.serverID, identity: identity, request: input,
                                                                  sendsIdempotencyKey: false))
            }
            password = ""; uncertain = false; message = nil; confirming = true
        } catch { message = error.localizedDescription }
    }
    private func send() async {
        guard !busy, isCurrent, let prepared, !uncertain || prepared.supportsSafeRetry else { return }
        busy = true; defer { busy = false }
        do {
            switch prepared {
            case .create(let operation): _ = try await model.createUser(operation)
            case .update(let operation): _ = try await model.updateUser(operation)
            }
            guard isCurrent else { return }
            self.prepared = nil; password = ""; uncertain = false; dismiss()
        } catch {
            guard isCurrent else { return }
            handleFailure(error, of: prepared)
        }
    }
    private func handleFailure(_ error: Error, of prepared: PreparedUserMutation) {
        if let failure = error as? KeyedWriteFailure, case .needsNewKey = failure.disposition {
            self.prepared = nil; password = ""; uncertain = false
            message = "请求未执行，请重新核对并确认。\n\(failure.localizedDescription)"
        } else if let failure = error as? KeyedWriteFailure {
            uncertain = true
            message = "\(failure.localizedDescription)\n表单已锁定，请使用相同操作编号和原始请求重试，不要另建请求。原始请求仅保留在本页内存中。"
        } else if let failure = error as? APIError, ["STEP_UP_ADMIN_API_KEY_FORBIDDEN", "STEP_UP_TOTP_NOT_ENABLED"].contains(failure.reason?.uppercased() ?? "") {
            self.prepared = nil; password = ""
            message = "此敏感操作需要使用已启用双因素验证的管理员账号登录，请在 Web 完成配置后重试。"
        } else if needsStepUp(error) {
            uncertain = false; stepUp = true
            message = "站点要求二次验证。验证后仍需手动重新确认原请求，不会自动重发。"
        } else if let failure = error as? APIError, definitelyRejected(failure) {
            self.prepared = nil; password = ""; uncertain = false
            message = "请求被拒绝，未确认任何修改。\n\(error.localizedDescription)"
        } else {
            uncertain = true
            message = prepared.supportsSafeRetry
                ? "\(error.localizedDescription)\n结果尚未确认。表单已锁定，请使用相同操作编号和原始请求手动重试，不要另建请求。原始请求仅保留在本页内存中。"
                : "\(error.localizedDescription)\n结果尚未确认。站点未为此请求提供幂等重试，不会自动或直接重发。请先在用户列表或 Web 核对实际状态，再决定下一步。"
        }
    }
    /// A repeated creation can only get 409 EMAIL_EXISTS, never a second account (00 §2.5.2), so that answer is final too (D31).
    private func definitelyRejected(_ failure: APIError) -> Bool {
        [400, 401, 403, 404, 422].contains(failure.statusCode ?? 0) || failure.kind == .validation
            || (failure.statusCode == 409 && failure.reason == "EMAIL_EXISTS")
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
    @State private var sending: Task<Void, Never>?
    @State private var stepUp = false
    private var pending: [PendingBalanceOperation] { model.pendingBalances.filter { $0.userID == user.id && $0.serverID == model.activeProfile?.id } }
    var body: some View {
        NavigationStack {
            Form {
                Section("目标") {
                    LabeledValue(label: "站点", value: model.activeProfile?.name ?? "")
                    LabeledValue(label: "用户", value: user.email)
                    LabeledValue(label: "当前余额", value: DisplayFormat.money(user.balance))
                }
                if !pending.isEmpty {
                    Section("结果待确认的请求") {
                        Text("不要重新创建请求。使用原始请求重试会保留相同操作编号及金额，避免重复扣加余额。")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(pending) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(operationName(item.operation)) \(DisplayFormat.moneyExact(item.amount))").font(.headline)
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
                if busy {
                    // Keyed writes now confirm on their own (00 §2.5.4); stopping keeps the record for checking later (D31).
                    ProgressView("正在确认结果…")
                    Button("稍后核对") { sending?.cancel() }.frame(minHeight: 44).accessibilityIdentifier("balance.later")
                }
                if let message { Section("处理结果") { Text(message).textSelection(.enabled) } }
            }
            .navigationTitle("调整余额")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .confirmationDialog("确认调整余额？", isPresented: $confirm, titleVisibility: .visible) {
                Button("确认发送", role: .destructive) { if let prepared { sending = Task { await send(prepared) } } }
            } message: {
                if let prepared { Text("站点：\(model.activeProfile?.name ?? "")\n用户：\(user.email)\n\(operationName(prepared.operation))：\(DisplayFormat.moneyExact(prepared.amount))") }
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
        let candidate = PendingBalanceOperation(serverID: serverID, userID: user.id, amount: decimal, operation: operation, notes: notes,
                                                userDisplayName: user.displayName, userEmail: user.email)
        do { try candidate.validate() }
        catch { message = error.localizedDescription; return }
        prepared = candidate
        confirm = true; message = nil
    }
    private func send(_ item: PendingBalanceOperation) async {
        guard !busy, item.serverID == model.activeProfile?.id else { return }
        busy = true; defer { busy = false; sending = nil }
        let generation = session?.generation ?? UUID()
        guard generation == model.sessionGeneration else { return }
        var submitted = false
        do {
            guard !model.isUITesting else { throw AppFailure("界面测试模式不执行余额写入。") }
            guard let client = session?.client else { return }
            let write = try model.persisted(item)
            submitted = true
            let outcome = try await client.updateBalance(write, onEvent: actionIDSaver(for: item))
            // Resolve the exact server-bound operation even if the user has switched sites.
            try model.resolve(item)
            guard generation == model.sessionGeneration else { return }
            let balance = DisplayFormat.money(outcome.value.balance)
            message = outcome.replayed ? "这笔此前已入账，没有重复执行。余额为 \(balance)。" : "操作成功，余额为 \(balance)。"
            prepared = nil; amount = ""; notes = ""
        } catch {
            guard generation == model.sessionGeneration else { return }
            if !submitted { message = "请求未发送。\n\(error.localizedDescription)" }
            else if error is CancellationError { message = KeyedWriteFailure.unconfirmedMessage }
            else if let failure = error as? KeyedWriteFailure { handle(failure, of: item) }
            else if needsStepUp(error) { stepUp = true }
            else if definitelyRejected(error) {
                do { try model.resolve(item); prepared = nil; message = "请求已被拒绝，余额未调整。\n\(error.localizedDescription)" }
                catch { message = "拒绝结果已收到，但无法更新本机记录。请检查设备存储，保留原操作编号。" }
            } else { message = "\(error.localizedDescription)\n如请求已经发送，结果仍待确认。请保留并重试原操作。" }
        }
    }
    /// 30 §3.4: a key conflict keeps the record for checking; an invalid key or body was never executed.
    private func handle(_ failure: KeyedWriteFailure, of item: PendingBalanceOperation) {
        switch failure.disposition {
        case .needsNewKey(.keyConflict): message = "这个操作编号已被另一笔请求占用，请先核对"
        case .needsNewKey:
            do { try model.resolve(item); prepared = nil; message = "请求格式错误，未入账" }
            catch { message = "拒绝结果已收到，但无法更新本机记录。请检查设备存储，保留原操作编号。" }
        case .unconfirmed: message = failure.localizedDescription
        }
    }
    /// Saves the action id with the record as soon as any reply carries it (30 §3.4 step 4). If that save fails the record
    /// can still be matched by its request id, so the write goes on.
    private func actionIDSaver(for item: PendingBalanceOperation) -> KeyedWriteEventHandler {
        let model = model
        return { @MainActor event in
            guard case .actionID(let id) = event else { return }
            try? model.remember(item.with(actionID: id))
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
