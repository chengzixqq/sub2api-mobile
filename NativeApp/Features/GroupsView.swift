import SwiftUI
import Sub2Core

/// `.groupEdit(id:)` until S5-10's sheet (S5-04): nil opens the old editor for a new group, an id the GroupStore has edits that
/// group, and an id it does not have says so instead of turning into a new group.
struct LegacyGroupEditSheet: View {
    let id: Int?
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let session, session.generation == model.sessionGeneration {
            if let id {
                if let group = model.groupStore?.group(id: id) { GroupEditorView(target: target(group, session: session)) } else { missing }
            } else {
                GroupEditorView(target: target(nil, session: session))
            }
        }
    }
    private func target(_ group: AdminGroup?, session: SessionContext) -> GroupEditorTarget {
        GroupEditorTarget(group: group, context: session, siteName: model.activeProfile?.name ?? "")
    }
    private var missing: some View {
        NavigationStack {
            ContentUnavailableView("找不到这个分组", systemImage: "questionmark.folder", description: Text("返回列表刷新后再试"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("sheet.close") }
                }
        }
    }
}

private struct GroupEditorTarget: Identifiable {
    let id = UUID()
    let group: AdminGroup?
    let context: SessionContext
    let siteName: String
}

private struct GroupEditorView: View {
    let target: GroupEditorTarget
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var platform = "anthropic"
    @State private var rate = "1"
    @State private var exclusive = false
    @State private var subscription = "standard"
    @State private var rpm = "0"
    @State private var daily = ""
    @State private var weekly = ""
    @State private var monthly = ""
    @State private var prepared: GroupWriteDraft?
    @State private var confirming = false
    @State private var busy = false
    @State private var uncertain = false
    @State private var reconciled = false
    @State private var message: String?
    @State private var discardAlert = false
    private var isCurrent: Bool { target.context.generation == model.sessionGeneration && target.context.serverID == model.activeProfile?.id }
    private var store: GroupStore? { model.groupStore }
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
                            ForEach(GroupPlatform.concrete, id: \.self) { Text(GroupPlatform.title($0)).tag($0) }
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
            let intent: GroupWriteDraft.Intent
            if let old = target.group {
                let input = GroupUpdateRequest(name: name == old.name ? nil : name, description: description == (old.description ?? "") ? nil : description,
                    rateMultiplier: parsedRate == old.rateMultiplier ? nil : parsedRate, isExclusive: exclusive == (old.isExclusive ?? false) ? nil : exclusive,
                    subscriptionType: subscription == (old.subscriptionType ?? "standard") ? nil : subscription, rpmLimit: parsedRPM,
                    dailyLimitUSD: subscription == "subscription" ? try limitChange(daily, previous: old.dailyLimitUSD) : nil,
                    weeklyLimitUSD: subscription == "subscription" ? try limitChange(weekly, previous: old.weeklyLimitUSD) : nil,
                    monthlyLimitUSD: subscription == "subscription" ? try limitChange(monthly, previous: old.monthlyLimitUSD) : nil)
                intent = .update(groupID: old.id, input)
            } else {
                guard let parsedRate, let parsedRPM else { throw AppFailure("请填写计费倍率和 RPM 限额。") }
                let input = GroupCreateRequest(name: name, description: description, platform: platform, rateMultiplier: parsedRate, isExclusive: exclusive,
                    subscriptionType: subscription, rpmLimit: parsedRPM, dailyLimitUSD: try limit(daily), weeklyLimitUSD: try limit(weekly), monthlyLimitUSD: try limit(monthly))
                intent = .create(input)
            }
            prepared = try GroupWriteDraft(intent, serverID: target.context.serverID, identity: identity,
                                           sendsIdempotencyKey: target.context.has(.adminIdempotentWrites))
            message = nil; confirming = true
        } catch { message = error.localizedDescription }
    }
    private func send() async {
        guard !busy, !uncertain, isCurrent, let store, var draft = prepared else { return }
        busy = true; defer { busy = false }
        do {
            // Saved before sending, so an unconfirmed result keeps this number and these bytes.
            let operation = try draft.confirmedOperation(); prepared = draft
            switch draft.intent {
            case .create(let input): _ = try await store.legacyCreate(input, operation: operation, context: target.context)
            case .update(let id, let input): _ = try await store.legacyUpdate(id: id, input, operation: operation, context: target.context)
            }
            guard isCurrent else { return }; self.prepared = nil; dismiss()
        } catch {
            guard isCurrent, !(error is CancellationError) else { return }
            let rejected = groupWriteDefinitelyRejected(error)
            if rejected { self.prepared = nil } else { uncertain = true }
            if let failure = error as? KeyedWriteFailure { message = groupKeyedFailureMessage(failure) }
            else { message = rejected ? error.localizedDescription : "\(error.localizedDescription)\n结果待确认。原请求仅保留在本页内存中，不会自动重试。" }
        }
    }
    private func reconcile() async {
        guard !busy, uncertain, isCurrent, let store, let prepared else { return }
        busy = true; defer { busy = false }
        do {
            switch prepared.intent {
            case .update(let id, let input):
                let result = try await store.fetch(id: id)
                guard isCurrent, !Task.isCancelled else { return }
                if input.matches(result) { message = "服务器当前字段已与本次修改一致，可关闭此页。"; uncertain = false; reconciled = true; self.prepared = nil }
                else { message = "服务器当前字段与目标仍不一致。原请求可能仍在处理，请在本站 Web 后台核对；本页不会重发。" }
            case .create(let input):
                let result = try await store.legacySearch(name: input.name, platform: input.platform, context: target.context)
                guard isCurrent, !Task.isCancelled else { return }
                let exact = result.filter { $0.name == input.name }.map { "#\($0.id) \($0.name)" }.joined(separator: "、")
                message = exact.isEmpty ? "当前查询尚未发现同名分组，仍无法确认原创建请求是否完成。请在 Web 核对后再操作。" : "查询到同名分组：\(exact)。同名不能证明是本次创建，请在 Web 核对；本页不会重复创建。"
            }
        } catch { guard isCurrent, !(error is CancellationError) else { return }; message = "核对未完成。\(error.localizedDescription)" }
    }
}

private func groupWriteDefinitelyRejected(_ error: any Error) -> Bool {
    if let failure = error as? KeyedWriteFailure {
        if case .needsNewKey = failure.disposition { return true }
        return false
    }
    guard let failure = error as? APIError else { return false }
    return failure.kind == .validation || [400, 401, 403, 404, 422, 423, 429].contains(failure.statusCode ?? 0)
}

/// S5D1-10: these pages offer no “用同一编号重试”, so the keyed failure's own text is not shown.
private func groupKeyedFailureMessage(_ failure: KeyedWriteFailure) -> String {
    switch failure.disposition {
    case .needsNewKey: "请求未执行，请重新核对并确认。\n\(failure.localizedDescription)"
    case .unconfirmed(.storeUnavailable, _): "服务器暂时无法受理，结果待确认。请稍后读取服务器状态核对。"
    case .unconfirmed: "结果待确认：服务器可能已执行。请先读取服务器状态核对；本页不会再发送这次请求。"
    }
}

/// The old detail's and editor's writes (S5-04), deleted with this file (S5-10). Fixtures write through GroupFixtures' entry
/// points; a success lands in the list and the group directory, and the list reads again when it next appears.
extension GroupStore {
    func legacyCreate(_ input: GroupCreateRequest, operation: GroupWriteOperation, context: SessionContext) async throws -> AdminGroup {
        try requireLive(context)
        let created: AdminGroup
        if let fixture = fixtureContext { created = try fixture.fixtures.createGroup(input, accounts: fixture.accounts, now: fixture.now) }
        else { created = try await context.client.createGroup(operation).value }
        try requireLive(context)
        upsert(created); setNeedsRefresh()
        return created
    }
    func legacyUpdate(id: Int, _ input: GroupUpdateRequest, operation: GroupWriteOperation, context: SessionContext) async throws -> AdminGroup {
        try requireLive(context)
        let updated: AdminGroup
        if let fixture = fixtureContext { updated = try fixture.fixtures.updateGroup(id: id, input, accounts: fixture.accounts, now: fixture.now) }
        else { updated = try await context.client.updateGroup(operation).value }
        try requireLive(context)
        upsert(updated); setNeedsRefresh()
        return updated
    }
    /// Deleted or already gone (50 §0.8): either way the group leaves the list.
    func legacyDelete(id: Int, operation: GroupWriteOperation, context: SessionContext) async throws -> GroupDeleteResult {
        try requireLive(context)
        let result: GroupDeleteResult
        if let fixture = fixtureContext { fixture.fixtures.removeGroup(id: id); result = .deleted }
        else { result = try await context.client.deleteGroup(operation).value }
        try requireLive(context)
        remove(id: id); setNeedsRefresh()
        return result
    }
    /// The creation check: groups of that platform whose name or description contains the name.
    func legacySearch(name: String, platform: String, context: SessionContext) async throws -> [AdminGroup] {
        try requireLive(context)
        if let fixture = fixtureContext { return fixture.fixtures.searchGroups(name: name, platform: platform, accounts: fixture.accounts, now: fixture.now) }
        return try await context.client.groups(page: 1, search: name, platform: platform).items
    }
    private func requireLive(_ context: SessionContext) throws {
        guard context.generation == generation, isLive else { throw CancellationError() }
    }
}
