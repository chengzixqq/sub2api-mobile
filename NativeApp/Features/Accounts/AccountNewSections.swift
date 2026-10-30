import SwiftUI
import Sub2Core

/// 20 §7.3 平台与认证方式: the platform menu by shelf (only what platform_auth allows), then the method rows; locked once the
/// account exists. A failed catalog read keeps the built-in list and offers 重试.
struct AccountNewPlatformSection: View {
    let model: AccountNewModel

    var body: some View {
        let locked = model.submission.createdAccountID != nil
        Section {
            Group {
                if locked { lockedRow } else if model.shelves.isEmpty { unavailableRow } else { platformMenu }
            }
            .id(AccountNewModel.Anchor.platform)
            if model.catalogFailed {
                AccountNewFailureRow(identifier: "account-new.platform.retry") { await model.loadCatalog() }
            }
            ForEach(model.methods) { methodRow($0) }
        } header: {
            Text("平台与认证方式")
        } footer: {
            if locked { Text(AccountNewCopy.lockedFootnote) }
        }
    }

    private var platformMenu: some View {
        Menu {
            ForEach(model.shelves) { shelf in
                Section(shelf.shelf.title) {
                    ForEach(shelf.platforms) { choice in
                        Toggle(isOn: Binding(get: { model.draft.platform == choice.id }, set: { if $0 { model.requestPlatform(choice.id) } })) {
                            Text(choice.name)
                            Text(choice.methodSummary)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("平台").foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                Text(model.platformName ?? AccountNewCopy.selectPlatform).foregroundStyle(model.platformName == nil ? Palette.ink3 : Palette.ink1)
                Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("平台")
        .accessibilityValue(model.platformName ?? AccountNewCopy.selectPlatform)
        .accessibilityIdentifier("account-new.platform")
    }
    private var lockedRow: some View {
        HStack(spacing: 8) {
            Text("平台").foregroundStyle(Palette.ink1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(model.platformName ?? "").foregroundStyle(Palette.ink1)
                Text(AccountNewCopy.lockedPlatform).font(.footnote).foregroundStyle(Palette.ink3)
            }
            Image(systemName: "lock.fill").font(.footnote).foregroundStyle(Palette.ink3).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account-new.platform.locked")
    }
    private var unavailableRow: some View {
        Text(AccountNewCopy.platformsUnavailable).foregroundStyle(Palette.ink2).frame(minHeight: 44)
            .accessibilityIdentifier("account-new.platform.unavailable")
    }

    private func methodRow(_ method: AccountNewMethod) -> some View {
        let selected = model.draft.method?.id == method.id
        return Button { model.requestMethod(method) } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3).foregroundStyle(selected ? Palette.accent : Palette.ink3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(method.title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink1)
                        Text(method.subtitle).font(.footnote).foregroundStyle(Palette.ink2)
                    }
                    Text(method.detail).font(.footnote).foregroundStyle(Palette.ink3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("account-new.method.\(method.id)")
    }
}

/// 20 §7.3 名称: suggested from the platform (“{短名}-{NN}”) until the admin types one.
struct AccountNewNameSection: View {
    @Bindable var model: AccountNewModel

    var body: some View {
        Section {
            AccountNewTextRow(title: "名称", text: $model.draft.name, prompt: model.draft.platform == nil ? "例如 Claude-04" : "必填",
                              identifier: "account-new.name")
                .id(AccountNewModel.Anchor.name)
            AccountNewTextRow(title: "备注", text: $model.draft.notes, prompt: "可选", identifier: "account-new.notes")
        } header: {
            Text("名称")
        } footer: {
            if model.draft.isNameAutomatic, !model.draft.name.isEmpty {
                Text(AccountNewCopy.nameFootnote).accessibilityIdentifier("account-new.name.footnote")
            }
        }
    }
}

/// 20 §7.3 调度: 并发数 1–100, 优先级 1–99, 账号计费倍率 (a plain decimal, 0 not billed).
struct AccountNewScheduleSection: View {
    @Bindable var model: AccountNewModel

    var body: some View {
        Section {
            AccountNewStepperRow(title: "并发数", hint: nil, value: $model.draft.concurrency, range: AccountNewDefaults.concurrencyRange,
                                 identifier: "account-new.concurrency")
                .id(AccountNewModel.Anchor.schedule)
            AccountNewStepperRow(title: "优先级", hint: "数值越小越优先", value: $model.draft.priority, range: AccountNewDefaults.priorityRange,
                                 identifier: "account-new.priority")
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("账号计费倍率").foregroundStyle(Palette.ink1)
                    Text("0 表示不计费，只影响账号计费").font(.footnote).foregroundStyle(Palette.ink3)
                }
                Spacer(minLength: 8)
                TextField("1", text: $model.draft.rateMultiplierText)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                    .frame(maxWidth: 90)
                    .accessibilityLabel("账号计费倍率")
                    .accessibilityIdentifier("account-new.rate")
                Text("×").foregroundStyle(Palette.ink3).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        } header: {
            Text("调度")
        }
    }
}

/// 20 §7.3 网络: the proxy, picked on a pushed page (S2-11's picker); 无代理 when none.
struct AccountNewNetworkSection: View {
    let model: AccountNewModel

    var body: some View {
        Section {
            NavigationLink(value: AccountNewPage.proxy) {
                LabeledContent("代理") { Text(model.proxyName ?? AccountNewCopy.noProxy).accessibilityIdentifier("account-new.proxy.value") }
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("account-new.proxy")
            .id(AccountNewModel.Anchor.network)
            if model.proxies.value == nil, model.proxies.error != nil {
                AccountNewFailureRow(identifier: "account-new.proxy.retry") { await model.loadProxies() }
            }
        } header: {
            Text("网络")
        }
    }
}

/// 20 §7.3 更多, folded: the expiry (S2-10's picker), its auto-pause, the load factor (blank is the default) and Antigravity's
/// AI Credits.
struct AccountNewMoreSection: View {
    @Bindable var model: AccountNewModel

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $model.moreExpanded) {
                NavigationLink(value: AccountNewPage.expiry) {
                    LabeledContent(AccountExpiry.pickerTitle) { Text(expiryText ?? AccountExpiry.never).monospacedDigit() }
                }
                .accessibilityIdentifier("account-new.expiry")
                if model.draft.expiresAt != nil {
                    Toggle("过期自动暂停调度", isOn: $model.draft.autoPauseOnExpired).accessibilityIdentifier("account-new.auto-pause")
                }
                AccountNewLoadFactorRow(value: $model.draft.loadFactor)
                if model.isAntigravity {
                    Toggle(isOn: $model.draft.allowOverages) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("允许超量请求（AI Credits）")
                            Text("免费配额确认用完后才用 AI Credits，普通 429 不切换").font(.footnote).foregroundStyle(Palette.ink3)
                        }
                    }
                    .accessibilityIdentifier("account-new.overages")
                }
            } label: {
                HStack(spacing: 8) {
                    Text(AccountNewCopy.moreLabel(isAntigravity: model.isAntigravity)).foregroundStyle(Palette.ink1)
                    Spacer(minLength: 8)
                    if !model.moreExpanded {
                        Text(AccountNewCopy.moreSummary(expiry: expiryText)).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink3)
                            .accessibilityIdentifier("account-new.more.summary")
                    }
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("account-new.more")
            .id(AccountNewModel.Anchor.more)
        } header: {
            Text("更多")
        } footer: {
            if model.moreExpanded { Text(AccountNewCopy.moreFootnote).accessibilityIdentifier("account-new.more.footnote") }
        }
    }

    private var expiryText: String? { model.draft.expiresAt.map { AccountExpiry.text($0, timeZone: .current) } }
}

// MARK: - Rows

/// “读取失败” and 重试 in the section that could not be read (20 §7.5).
struct AccountNewFailureRow: View {
    let identifier: String
    let retry: @MainActor () async -> Void

    var body: some View {
        HStack {
            Text(AccountNewCopy.loadFailed).foregroundStyle(Tone.critical.ink)
            Spacer()
            Button(AccountNewCopy.retry) { Task { await retry() } }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier(identifier)
        }
        .accessibilityElement(children: .contain)
    }
}

struct AccountNewTextRow: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let identifier: String
    var monospaced = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(Palette.ink1)
            TextField(title, text: $text, prompt: Text(prompt))
                .font(monospaced ? .body.monospaced() : .body)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
        .frame(minHeight: 44)
    }
}

struct AccountNewStepperRow: View {
    let title: String
    let hint: String?
    @Binding var value: Int
    let range: ClosedRange<Int>
    let identifier: String

    var body: some View {
        Stepper(value: $value, in: range) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).foregroundStyle(Palette.ink1)
                    Spacer(minLength: 8)
                    Text("\(value)").monospacedDigit().foregroundStyle(Palette.ink1)
                }
                if let hint { Text(hint).font(.footnote).foregroundStyle(Palette.ink3) }
            }
        }
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityIdentifier(identifier)
    }
}

/// 负载因子 1–10, or blank for the default: − below 1 clears it.
private struct AccountNewLoadFactorRow: View {
    @Binding var value: Int?
    private let range = AccountNewDefaults.loadFactorRange

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("负载因子").foregroundStyle(Palette.ink1)
                Text("提高后调度更频繁").font(.footnote).foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 8)
            Button { value = value.flatMap { $0 <= range.lowerBound ? nil : $0 - 1 } } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(value == nil)
            .accessibilityLabel("减少负载因子")
            Text(value.map(String.init) ?? "默认").monospacedDigit().foregroundStyle(value == nil ? Palette.ink3 : Palette.ink1)
                .frame(minWidth: 36)
                .accessibilityIdentifier("account-new.load-factor")
            Button { value = min(range.upperBound, (value ?? range.lowerBound - 1) + 1) } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(value == range.upperBound)
            .accessibilityLabel("增加负载因子")
        }
    }
}

/// 20 §7.3 分组: chips of the platform's active groups and the composite ones (Antigravity's “在 /v1/messages 中使用” adds the
/// Anthropic and Gemini ones), picked in order; a pick the pre-check found at risk gets a bell and a footnote. None is fine.
struct AccountNewGroupSection: View {
    let model: AccountNewModel

    var body: some View {
        let risky = model.riskyGroups
        Section {
            if model.isAntigravity {
                Toggle(isOn: Binding(get: { model.draft.mixedScheduling }, set: { model.setMixedScheduling($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AccountNewCopy.mixedSchedulingTitle)
                        Text(AccountNewCopy.mixedSchedulingDetail).font(.footnote).foregroundStyle(Palette.ink3)
                    }
                }
                .accessibilityIdentifier("account-new.groups.mixed")
            }
            content.id(AccountNewModel.Anchor.groups)
        } header: {
            HStack {
                Text("分组")
                Spacer()
                Text(AccountNewCopy.groupsTrailing(selected: model.draft.groupIDs.count, risky: risky.count))
                    .accessibilityIdentifier("account-new.groups.count")
            }
        } footer: {
            footer(risky)
        }
    }

    @ViewBuilder private var content: some View {
        let state = model.groupsState
        if model.draft.platform == nil {
            Text(AccountNewCopy.pickPlatformFirst).foregroundStyle(Palette.ink3).frame(minHeight: 44)
        } else if state.value == nil, state.failureReason != nil {
            AccountNewFailureRow(identifier: "account-new.groups.retry") { await model.retryGroups() }
        } else if state.value == nil {
            ProgressView().frame(maxWidth: .infinity, minHeight: 44)
        } else if model.eligibleGroups.isEmpty {
            Text(AccountNewCopy.noGroups(platformName: model.platformName ?? "")).foregroundStyle(Palette.ink2).frame(minHeight: 44)
                .accessibilityIdentifier("account-new.groups.empty")
        } else {
            ListFieldFlow(spacing: 8) {
                ForEach(model.eligibleGroups) { chip($0) }
            }
            .padding(.vertical, 6)
        }
    }

    private func chip(_ group: AdminGroup) -> some View {
        let selected = model.draft.groupIDs.contains(group.id)
        let risk = selected ? model.mixedRisks[group.id] : nil
        let foreign = group.platform == model.draft.platform ? nil : platformLabel(group.platform)
        let spoken = [group.name, "倍率 " + AccountEditCopy.rate(group.rateMultiplier), foreign.map { "\($0) 分组" }, risk.map { _ in "有混合渠道风险" }]
        return Button { model.toggleGroup(group.id) } label: {
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(group.name).lineLimit(1)
                if risk != nil { Image(systemName: "bell.fill").font(.caption).foregroundStyle(Tone.caution.ink) }
                if let foreign { Text(foreign).font(.caption2).foregroundStyle(Palette.ink3) }
                Text(AccountEditCopy.rate(group.rateMultiplier)).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink2)
            }
            .font(.subheadline)
            .foregroundStyle(selected ? Palette.accent : Palette.ink1)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(selected ? Palette.accentWash : Palette.sunken, in: Capsule())
            .overlay { if selected { Capsule().strokeBorder(risk == nil ? Palette.accent : Tone.caution.base, lineWidth: 1) } }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(spoken.compactMap { $0 }.joined(separator: "，"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("account-new.group.\(group.id)")
    }

    @ViewBuilder private func footer(_ risky: [AdminGroup]) -> some View {
        if let platform = model.draft.platform {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(risky) { group in
                    if let warning = model.mixedRisks[group.id] {
                        Text(AccountNewCopy.riskFootnote(group: group.name, otherPlatform: warning.otherPlatform)).foregroundStyle(Tone.caution.ink)
                            .accessibilityIdentifier("account-new.groups.risk.\(group.id)")
                    }
                }
                if model.isAntigravity, model.draft.mixedScheduling {
                    Text(AccountNewCopy.mixedSchedulingFootnote).foregroundStyle(Tone.caution.ink)
                } else {
                    Text(AccountNewCopy.groupsScope(platformName: model.platformName ?? platform))
                }
                if model.draft.groupIDs.isEmpty {
                    Text(AccountNewCopy.defaultGroupFootnote(platformID: platform)).accessibilityIdentifier("account-new.groups.default")
                }
            }
        }
    }
    private func platformLabel(_ platform: String) -> String {
        platform == "composite" ? "组合" : AccountNaming.platformName(platform, catalog: model.catalog)
    }
}
