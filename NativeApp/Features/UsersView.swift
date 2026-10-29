import SwiftUI
import Sub2Core

/// The old editor's target: the detail's ⋯ 编辑用户 opens it until S3-11 replaces it; creating moved to UserEditView (S3-10).
struct UserEditorTarget: Identifiable {
    let id = UUID()
    let user: AdminUser
    let context: SessionContext
    let siteName: String
}

enum PreparedUserMutation {
    case update(PendingUserUpdateOperation)
    var id: UUID {
        switch self {
        case .update(let operation): operation.id
        }
    }
    /// Sent with an Idempotency-Key, so the same number can be retried.
    var supportsSafeRetry: Bool {
        switch self {
        case .update(let operation): operation.supportsSafeRetry
        }
    }
}

struct UserEditorView: View {
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
    @State private var adjustmentNotes = ""
    @State private var prepared: PreparedUserMutation?
    @State private var busy = false
    @State private var confirming = false
    @State private var uncertain = false
    @State private var discardAlert = false
    @State private var message: String?

    init(target: UserEditorTarget) {
        self.target = target
        _email = State(initialValue: target.user.email)
        _username = State(initialValue: target.user.username ?? "")
        _role = State(initialValue: target.user.role ?? AdminUserRole.user.rawValue)
        _notes = State(initialValue: target.user.notes ?? "")
        _concurrency = State(initialValue: target.user.concurrency.map(String.init) ?? "")
        _rpmLimit = State(initialValue: target.user.rpmLimit.map(String.init) ?? "")
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
                    LabeledValue(label: "用户", value: "\(target.user.email)（#\(target.user.id)）")
                }
                Section {
                    TextField("邮箱", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("user-editor.email")
                    TextField("用户名", text: $username).textContentType(.username).autocorrectionDisabled()
                        .accessibilityIdentifier("user-editor.username")
                    SecureField("新密码（留空不修改）", text: $password)
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
                    TextField("并发调整备注（可选）", text: $adjustmentNotes, axis: .vertical)
                        .accessibilityIdentifier("user-editor.adjustment-notes")
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
            .navigationTitle("编辑用户")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { if uncertain { discardAlert = true } else { dismiss() } }.disabled(busy).accessibilityIdentifier("user-editor.close")
            } }
            .interactiveDismissDisabled(busy || uncertain)
            .confirmationDialog("确认修改用户？", isPresented: $confirming, titleVisibility: .visible) {
                Button("确认发送", role: .destructive) { Task { await send() } }
            } message: {
                Text("站点：\(target.siteName)\n地址：\(target.context.client.server.baseURL.absoluteString)\n用户：\(email)（#\(target.user.id)）\n角色：\(AdminUserRole(rawValue: role)?.title ?? role)\n最大并发：\(concurrency.isEmpty ? "保持原值" : concurrency)\nRPM：\(rpmLimit.isEmpty ? "保持原值" : rpmLimit)")
            }
            .alert("请求结果尚未确认", isPresented: $discardAlert) {
                Button("保留原请求", role: .cancel) { }
                Button("关闭并手动核对", role: .destructive) { password = ""; prepared = nil; dismiss() }
            } message: {
                Text("关闭会清除内存中的原始请求和密码。请先保存操作编号（如有）；关闭后先在列表或 Web 核对实际状态，不要新建相同操作。")
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
            let user = target.user
            let maxConcurrency = concurrency == (user.concurrency.map(String.init) ?? "") ? nil : try integer(concurrency)
            let rpm = rpmLimit == (user.rpmLimit.map(String.init) ?? "") ? nil : try integer(rpmLimit)
            let changedRole = role == user.role ? nil : AdminUserRole(rawValue: role)
            let changes = UserUpdateRequest(
                email: email == user.email ? nil : email, password: password.isEmpty ? nil : password,
                username: username == (user.username ?? "") ? nil : username,
                notes: notes == (user.notes ?? "") ? nil : notes,
                role: changedRole, concurrency: maxConcurrency, rpmLimit: rpm,
                adjustmentNotes: maxConcurrency == nil || adjustmentNotes.isEmpty ? nil : adjustmentNotes)
            prepared = .update(try PendingUserUpdateOperation(serverID: target.context.serverID, identity: identity, userID: user.id, request: changes,
                                                              serverSupportsIdempotentWrites: target.context.has(.adminIdempotentWrites)))
            password = ""; uncertain = false; message = nil; confirming = true
        } catch { message = error.localizedDescription }
    }
    private func send() async {
        guard !busy, isCurrent, let prepared, !uncertain || prepared.supportsSafeRetry else { return }
        busy = true; defer { busy = false }
        // A locked form sends again a request that may have run (00 §2.5.4).
        let retrying = uncertain
        do {
            switch prepared {
            case .update(let operation): _ = try await model.updateUser(operation)
            }
            guard isCurrent else { return }
            self.prepared = nil; password = ""; uncertain = false; dismiss()
        } catch {
            guard isCurrent else { return }
            handleFailure(error, of: prepared, retrying: retrying)
        }
    }
    private func handleFailure(_ error: Error, of prepared: PreparedUserMutation, retrying: Bool) {
        if let failure = error as? KeyedWriteFailure, case .needsNewKey = failure.disposition {
            self.prepared = nil; password = ""; uncertain = false
            message = "请求未执行，请重新核对并确认。\n\(failure.localizedDescription)"
        } else if let failure = error as? KeyedWriteFailure {
            uncertain = true
            message = "\(failure.localizedDescription)\n表单已锁定，请使用相同操作编号和原始请求重试，不要另建请求。原始请求仅保留在本页内存中。"
        } else if isClearedForReconfirmation(error) {
            // Verified or accepted in the global sheet: the same number and bytes are confirmed again (00 §2.6.2 step 4); a
            // locked form stays locked.
            message = error.localizedDescription; confirming = true
        } else if let failure = error as? APIError, definitelyRejected(failure, retrying: retrying) {
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
    /// Security refusals come before the handler (00 §0 rules 5–6), but for a retry they say nothing about the attempt that
    /// may have run (00 §2.5.4 step 2).
    private func definitelyRejected(_ failure: APIError, retrying: Bool) -> Bool {
        if retrying && failure.isRefusedBeforeHandler { return false }
        return [400, 401, 403, 404, 422].contains(failure.statusCode ?? 0) || failure.kind == .validation
            || SecurityInterruption(failure) != nil || (failure.statusCode == 409 && failure.reason == "EMAIL_EXISTS")
    }
}
