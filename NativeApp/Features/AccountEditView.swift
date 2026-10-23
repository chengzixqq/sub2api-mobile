import SwiftUI
import Sub2Core

struct AccountEditView: View {
    let initial: UpstreamAccount
    let onSaved: (UpstreamAccount) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var original: UpstreamAccount?
    @State private var name = ""
    @State private var notes = ""
    @State private var concurrency = ""
    @State private var priority = ""
    @State private var rateMultiplier = ""
    @State private var loadFactor = ""
    @State private var groupIDs = Set<Int>()
    @State private var groups: [AdminGroup] = []
    @State private var error: String?
    @State private var groupsError: String?
    @State private var loading = false
    @State private var saving = false
    @State private var unresolved = false
    @State private var confirming = false
    @State private var pending: PendingAccountUpdate?
    @State private var changedFields: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("目标") {
                    LabeledValue(label: "站点", value: model.activeProfile?.name ?? "")
                    LabeledValue(label: "账号", value: "\(initial.name) · #\(initial.id)")
                }
                if loading { ProgressView("正在读取最新账号…") }
                if original != nil {
                    Section("基本信息") {
                        TextField("名称", text: $name).accessibilityIdentifier("account.edit.name")
                        TextField("备注", text: $notes, axis: .vertical).accessibilityIdentifier("account.edit.notes")
                    }
                    Section("调度与成本") {
                        TextField("并发上限", text: $concurrency).keyboardType(.numberPad).accessibilityIdentifier("account.edit.concurrency")
                        TextField("优先级", text: $priority).keyboardType(.numberPad).accessibilityIdentifier("account.edit.priority")
                        TextField("成本倍率", text: $rateMultiplier).keyboardType(.decimalPad).accessibilityIdentifier("account.edit.rate")
                        TextField("负载因子（留空恢复默认）", text: $loadFactor).keyboardType(.numberPad)
                        Text("并发与优先级为非负整数。负载因子为 1 至 10000，留空或 0 恢复默认。仅提交修改的字段。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("所属分组") {
                        ForEach(groups) { group in
                            Toggle("\(group.name) · \(group.platform)", isOn: Binding(get: { groupIDs.contains(group.id) }, set: { if $0 { groupIDs.insert(group.id) } else { groupIDs.remove(group.id) } }))
                                .accessibilityIdentifier("account.edit.group.\(group.id)")
                        }
                        let known = Set(groups.map(\.id))
                        ForEach(groupIDs.subtracting(known).sorted(), id: \.self) { id in
                            Toggle("保留当前分组 #\(id)（当前列表未返回）", isOn: Binding(get: { groupIDs.contains(id) }, set: { if !$0 { groupIDs.remove(id) } }))
                        }
                        if let groupsError { Text(groupsError).font(.caption).foregroundStyle(.red); Button("重试读取分组") { Task { await loadGroups() } } }
                        Text("服务器检查分组兼容性；当前未返回的原分组会保留，取消勾选才移除。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if unresolved {
                    Section("待核对") {
                        Text("服务器可能已应用更改。本页已停止提交，请先读取并核对，再关闭重开编辑。")
                        Button("读取当前服务器状态") { Task { await loadCurrent(reconcile: true) } }.disabled(loading)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("account.edit.error") } }
                if original == nil && !loading { Button("重试读取账号") { Task { await loadCurrent() } } }
            }
            .disabled(saving)
            .navigationTitle("快捷编辑账号")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await prepare() } }.disabled(original == nil || loading || saving || unresolved)
                        .accessibilityIdentifier("account.edit.save")
                }
            }
            .task { async let current: Void = loadCurrent(); async let groupList: Void = loadGroups(); _ = await (current, groupList) }
            .confirmationDialog("确认修改账号？", isPresented: $confirming, titleVisibility: .visible) {
                Button("确认保存", role: .destructive) { Task { await save() } }
            } message: {
                Text("站点：\(model.activeProfile?.name ?? "")\n账号：\(initial.name)（#\(initial.id)）\n修改：\(changedFields.joined(separator: "、"))")
            }
            .interactiveDismissDisabled(saving)
        }
    }
    private func loadCurrent(reconcile: Bool = false) async {
        guard !loading, let session, session.generation == model.sessionGeneration else { return }
        loading = true; defer { loading = false }
        do {
            let current = try await model.account(id: initial.id)
            guard session.generation == model.sessionGeneration, !Task.isCancelled else { return }
            original = current; name = current.name; notes = current.notes ?? ""
            concurrency = current.concurrency.map(String.init) ?? ""; priority = current.priority.map(String.init) ?? ""
            rateMultiplier = current.rateMultiplier.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            loadFactor = current.loadFactor.map(String.init) ?? ""
            groupIDs = Set(current.groupIDs + current.groups.map(\.id))
            error = reconcile ? "已读取当前状态，请核对以上字段；关闭后可重新发起新的编辑。" : nil
        } catch { if session.generation == model.sessionGeneration, !(error is CancellationError) { self.error = error.localizedDescription } }
    }
    private func loadGroups() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        do {
            let result: [AdminGroup]
            if model.isUITesting { result = [AdminGroup(id: 10, name: "标准分组"), AdminGroup(id: 11, name: "高级分组")] }
            else { result = try await session.client.allGroups() }
            guard session.generation == model.sessionGeneration, !Task.isCancelled else { return }; groups = result; groupsError = nil
        } catch { if session.generation == model.sessionGeneration, !(error is CancellationError) { groupsError = "读取分组失败；已有分组保持不变：\(error.localizedDescription)" } }
    }
    private func integer(_ text: String, label: String) throws -> Int? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let value = Int(text) else { throw AppFailure("\(label)必须填写整数。") }; return value
    }
    private func buildRequest() throws -> AccountUpdateRequest {
        guard let original else { throw APIError.invalidResponse }
        var input = AccountUpdateRequest(); var fields: [String] = []
        if name != original.name { input.name = name; fields.append("名称") }
        if notes != (original.notes ?? "") { input.notes = notes; fields.append("备注") }
        if concurrency != (original.concurrency.map(String.init) ?? "") {
            guard let value = try integer(concurrency, label: "并发上限") else { throw AppFailure("并发上限不能为空。") }; input.concurrency = value; fields.append("并发上限")
        }
        if priority != (original.priority.map(String.init) ?? "") {
            guard let value = try integer(priority, label: "优先级") else { throw AppFailure("优先级不能为空。") }; input.priority = value; fields.append("优先级")
        }
        if rateMultiplier != (original.rateMultiplier.map { NSDecimalNumber(decimal: $0).stringValue } ?? "") {
            guard rateMultiplier.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
                  let value = Decimal(string: rateMultiplier, locale: Locale(identifier: "en_US_POSIX")) else { throw AppFailure("请输入有效的成本倍率。") }
            input.rateMultiplier = value; fields.append("成本倍率")
        }
        if loadFactor != (original.loadFactor.map(String.init) ?? "") {
            input.loadFactor = try integer(loadFactor, label: "负载因子") ?? 0; fields.append("负载因子")
        }
        if groupIDs != Set(original.groupIDs + original.groups.map(\.id)) { input.groupIDs = groupIDs.sorted(); fields.append("所属分组") }
        try input.validate(); changedFields = fields; return input
    }
    private func prepare() async {
        guard !saving, !unresolved, let session, session.generation == model.sessionGeneration else { return }
        do {
            let request = try buildRequest()
            pending = try PendingAccountUpdate(serverID: session.serverID, identity: await session.client.userWriteIdentity(), accountID: initial.id, request: request)
            guard session.generation == model.sessionGeneration else { pending = nil; return }
            error = nil; confirming = true
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        guard !saving, !unresolved, let session, session.generation == model.sessionGeneration, let pending else { return }
        saving = true; defer { saving = false }
        do {
            let updated: UpstreamAccount
            if model.isUITesting {
                let request = try buildRequest(); var fixture = original ?? initial
                if let value = request.name { fixture.name = value }; if let value = request.notes { fixture.notes = value }
                if let value = request.concurrency { fixture.concurrency = value }; if let value = request.priority { fixture.priority = value }
                if let value = request.rateMultiplier { fixture.rateMultiplier = value }; if let value = request.loadFactor { fixture.loadFactor = value }
                if let value = request.groupIDs { fixture.groupIDs = value; fixture.groups = groups.filter { value.contains($0.id) }.map { .init(id: $0.id, name: $0.name) } }
                updated = fixture
            } else { updated = try await session.client.updateAccount(pending) }
            guard session.generation == model.sessionGeneration else { return }; onSaved(updated); dismiss()
        } catch {
            guard session.generation == model.sessionGeneration else { return }
            self.error = accountWriteFailure(error)
            // Cleared by the global sheet: the same pending update is confirmed again (00 §2.6.2 step 4).
            if isClearedForReconfirmation(error) { self.error = error.localizedDescription; confirming = true }
            else if let api = error as? APIError, let code = api.statusCode, (400..<500).contains(code), code != 408 { /* Explicit rejection permits a corrected request. */ }
            else { unresolved = true }
        }
    }
}
