import SwiftUI
import UIKit
import Sub2Core

/// 50 §3.3: 基本, 计费 and 订阅限额 (or the standard billing note) as GroupPermissions lets this identity see them — a field it
/// may change is a control, one it may not reads as text, a hidden one is left out — then the Web note and the last write's
/// result at the bottom, scrolled to when it changes.
struct GroupEditForm<Members: View>: View {
    @Binding var draft: GroupEditDraft
    let permissions: GroupPermissions
    let platforms: [String]
    let catalog: MetaCatalog?
    let issues: [GroupEditIssue]
    let flow: GroupEditFlow?
    /// A write runs, its result is open or the group is gone.
    let isLocked: Bool
    /// S5-11 成员账号 N, before the Web note.
    let members: Members

    private var group: AdminGroup? { draft.original }
    private func access(_ field: GroupPermissions.Field) -> GroupPermissions.FieldAccess { permissions.access(field, in: group) }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                basicSection.disabled(isLocked)
                if access(.rateMultiplier) != .hidden { billingSection.disabled(isLocked) }
                if access(.limits) != .hidden { limitsSection.disabled(isLocked) }
                members.disabled(isLocked)
                Section {} footer: {
                    Text(GroupEditCopy.webNote).accessibilityIdentifier("group-edit.web")
                }
                if let flow { GroupEditResultSection(flow: flow) }
            }
            .scrollDismissesKeyboard(.immediately)
            .accessibilityIdentifier("group-edit.form")
            .onChange(of: flow?.phase) { _, phase in
                guard let phase, Self.showsResult(phase) else { return }
                withAnimation { proxy.scrollTo(GroupEditResultSection.anchor, anchor: .bottom) }
            }
        }
    }

    private static func showsResult(_ phase: GroupEditFlow.Phase) -> Bool {
        switch phase {
        case .failed(.nameTaken), .editing, .preparing, .confirming: false
        default: true
        }
    }

    // MARK: 基本

    private var basicSection: some View {
        Section {
            nameRow
            if access(.description) == .editable {
                GroupEditTextRow(label: "描述", text: $draft.description, prompt: GroupEditCopy.descriptionPlaceholder, id: "description")
            } else if access(.description) == .readOnly {
                GroupEditValueRow(label: "描述", value: draft.description.isEmpty ? DisplayFormat.missing : draft.description, id: "description.value")
            }
            platformRow
            statusRow
            exclusiveRow
        } header: { Text(GroupEditCopy.basicSection) } footer: { basicFooter }
    }

    @ViewBuilder private var nameRow: some View {
        switch access(.name) {
        case .editable: GroupEditTextRow(label: "名称", text: $draft.name, prompt: GroupEditCopy.namePlaceholder, id: "name", isFlagged: nameIssue != nil)
        case .readOnly: GroupEditValueRow(label: "名称", value: draft.name, id: "name.value")
        case .hidden: EmptyView()
        }
    }
    @ViewBuilder private var platformRow: some View {
        if draft.isNew && access(.platform) == .editable {
            Picker("平台", selection: $draft.platform) {
                ForEach(platforms, id: \.self) { Text(GroupFormat.platformName($0, catalog: catalog)).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
            .accessibilityIdentifier("group-edit.platform")
        } else if access(.platform) != .hidden {
            GroupEditValueRow(label: "平台", value: GroupFormat.platformName(draft.platform, catalog: catalog), id: "platform.value")
        }
    }
    @ViewBuilder private var statusRow: some View {
        switch access(.status) {
        case .editable:
            GroupEditSwitchRow(label: "状态", detail: GroupFormat.statusText(draft.isActive ? "active" : "inactive"), isOn: $draft.isActive, id: "status")
        case .readOnly:
            GroupEditValueRow(label: "状态", value: GroupFormat.statusText(draft.isNew ? "active" : group?.status ?? "active"), id: "status.value")
        case .hidden: EmptyView()
        }
    }
    @ViewBuilder private var exclusiveRow: some View {
        switch access(.exclusive) {
        case .editable:
            GroupEditSwitchRow(label: "专属分组", detail: GroupFormat.exclusiveText(draft.isExclusive), isOn: $draft.isExclusive, id: "exclusive")
        case .readOnly: GroupEditValueRow(label: "专属分组", value: GroupFormat.exclusiveText(draft.isExclusive), id: "exclusive.value")
        case .hidden: EmptyView()
        }
    }
    private var nameIssue: GroupEditIssue? { issues.first { $0 == .nameTaken || $0 == .nameTooLong } }
    @ViewBuilder private var basicFooter: some View {
        let note = GroupEditCopy.basicFootnote(isNew: draft.isNew, isExclusive: draft.isExclusive, isActive: draft.isActive,
                                               showsExclusive: access(.exclusive) != .hidden, showsStatus: access(.status) != .hidden,
                                               isSimpleMode: permissions.isSimpleMode)
        VStack(alignment: .leading, spacing: 4) {
            if let issue = nameIssue, let text = issue.footnote {
                Text(text).foregroundStyle(Palette.criticalInk)
                    .accessibilityIdentifier(issue == .nameTaken ? "group-edit.name.taken" : "group-edit.name.tooLong")
            }
            if !note.isEmpty { Text(note).accessibilityIdentifier("group-edit.basic.footnote") }
        }
    }

    // MARK: 计费

    private var billingSection: some View {
        Section {
            rateRow
            billingTypeRow
            if access(.rpmLimit) == .editable {
                GroupEditDigitsRow(label: "每用户 RPM", value: $draft.rpmText, prompt: GroupEditCopy.rpmPlaceholder, id: "rpm")
            } else if access(.rpmLimit) == .readOnly {
                GroupEditValueRow(label: "每用户 RPM", value: GroupFormat.rpmText(group?.rpmLimit), id: "rpm.value")
            }
        } header: { Text(GroupEditCopy.billingSection) } footer: {
            Text(GroupEditCopy.billingFootnote(managedNote: permissions.billingNote(for: group))).accessibilityIdentifier("group-edit.billing.footnote")
        }
    }
    @ViewBuilder private var rateRow: some View {
        if access(.rateMultiplier) == .editable {
            GroupEditRateRow(text: $draft.rateText, isFlagged: issues.contains(.rateInvalid)) { draft.stepRate(up: $0) }
        } else {
            GroupEditValueRow(label: "费率倍数", value: GroupFormat.rateText(group?.rateMultiplier), id: "rate.value")
        }
    }
    @ViewBuilder private var billingTypeRow: some View {
        if draft.isNew && access(.billingType) == .editable {
            VStack(alignment: .leading, spacing: 8) {
                Text("计费类型").foregroundStyle(Palette.ink1)
                Picker("计费类型", selection: $draft.subscriptionType) {
                    ForEach(["standard", "subscription"], id: \.self) { Text(GroupFormat.billingText($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("group-edit.billing")
            }
            .padding(.vertical, 4)
        } else {
            GroupEditValueRow(label: "计费类型", value: GroupFormat.billingText(draft.subscriptionType), note: GroupEditCopy.billingFixed, id: "billing.value")
        }
    }

    // MARK: 订阅限额

    @ViewBuilder private var limitsSection: some View {
        if draft.isSubscription {
            Section {
                ForEach(GroupLimitPeriod.allCases, id: \.self) { limitRow($0) }
            } header: { Text(GroupEditCopy.limitsSection) } footer: {
                Text(GroupEditCopy.limitsFootnote).accessibilityIdentifier("group-edit.limits.footnote")
            }
        } else {
            Section {} footer: {
                Text(GroupEditCopy.standardBillingNote).accessibilityIdentifier("group-edit.limits.standard")
            }
        }
    }
    @ViewBuilder private func limitRow(_ period: GroupLimitPeriod) -> some View {
        if access(.limits) == .editable {
            VStack(alignment: .leading, spacing: 2) {
                GroupEditAmountRow(label: "\(period.title)限额", text: Binding(get: { draft[limit: period] }, set: { draft[limit: period] = $0 }),
                                   isFlagged: issues.contains(.limitInvalid(period)), id: "limit.\(period.rawValue)")
                // U-13: until the backend gives 0 one meaning.
                if draft.zeroLimitPeriods().contains(period) {
                    Text(GroupEditCopy.zeroLimitNote).font(.footnote).foregroundStyle(Tone.caution.ink)
                        .padding(.bottom, 6)
                        .accessibilityIdentifier("group-edit.limit.\(period.rawValue).zeroNote")
                }
            }
        } else {
            GroupEditValueRow(label: "\(period.title)限额", value: GroupFormat.limitText(limitValue(period)), id: "limit.\(period.rawValue).value")
        }
    }
    private func limitValue(_ period: GroupLimitPeriod) -> Decimal? {
        switch period {
        case .daily: group?.dailyLimitUSD
        case .weekly: group?.weeklyLimitUSD
        case .monthly: group?.monthlyLimitUSD
        }
    }
}

/// The last write at the bottom (50 §3.5): progress, a refusal in red, or the open result with 核对 and 用同一编号重试.
private struct GroupEditResultSection: View {
    /// The first row's id, for scrolling to it.
    static let anchor = "group-edit.result"
    let flow: GroupEditFlow

    var body: some View {
        switch flow.phase {
        case .saving(let event): Section { progress(GroupEditCopy.savingText(event), id: "progress") }
        case .checking: Section { progress(GroupEditCopy.checking, id: "checking") }
        case .unconfirmed(let state):
            Section {
                StatusBanner(tone: .caution, systemImage: "questionmark.circle", title: state.text)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("group-edit.unconfirmed")
                    .id(Self.anchor)
                if let check = state.check {
                    Text(GroupEditCopy.checkNote(check)).font(.footnote).foregroundStyle(Palette.ink2)
                        .accessibilityIdentifier("group-edit.check.note")
                }
                button(GroupEditCopy.reconcile, id: "reconcile") { await flow.reconcile() }
                if state.keyed { button(GroupEditCopy.retrySame, id: "retry-same") { await flow.retrySameKey() } }
            }
        default:
            if let message = flow.failureMessage {
                Section {
                    Text(message).font(.subheadline).foregroundStyle(Palette.criticalInk)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .accessibilityIdentifier("group-edit.error")
                        .id(Self.anchor)
                }
            }
        }
    }

    private func progress(_ text: String, id: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(text).font(.footnote).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("group-edit.\(id)")
        .id(Self.anchor)
    }
    private func button(_ title: String, id: String, action: @escaping @MainActor () async -> Void) -> some View {
        Button(title) { Task { await action() } }
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityIdentifier("group-edit.\(id)")
    }
}

/// A labelled text row: the label on the left, the input on the right (design GvField); outlined red when flagged.
private struct GroupEditTextRow: View {
    let label: String
    @Binding var text: String
    let prompt: String
    let id: String
    var isFlagged = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(Palette.ink1)
            TextField(label, text: $text, prompt: Text(prompt))
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
                .accessibilityIdentifier("group-edit.\(id)")
        }
        .frame(minHeight: 44)
        .flagged(isFlagged)
    }
}

/// A read-only value, with the reason under it when there is one.
private struct GroupEditValueRow: View {
    let label: String
    let value: String
    var note: String?
    let id: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(Palette.ink1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).foregroundStyle(Palette.ink2)
                if let note { Text(note).font(.caption).foregroundStyle(Palette.ink3) }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("group-edit.\(id)")
    }
}

/// A switch whose second line says what the current value means (正常 / 停用, 专属 / 公开).
private struct GroupEditSwitchRow: View {
    let label: String
    let detail: String
    @Binding var isOn: Bool
    let id: String

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(Palette.ink1)
                Text(detail).font(.footnote).foregroundStyle(Palette.ink2)
            }
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("group-edit.\(id)")
    }
}

/// 费率倍数: − and + step 0.1 (44pt each), the value typed in between; outlined red when it does not read as above 0.
private struct GroupEditRateRow: View {
    @Binding var text: String
    let isFlagged: Bool
    let step: (Bool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("费率倍数").foregroundStyle(Palette.ink1)
            Spacer(minLength: 8)
            stepButton(up: false)
            TextField("费率倍数", text: $text, prompt: Text(""))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 76, height: 36)
                .background(Palette.sunken, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isFlagged ? Palette.critical : .clear, lineWidth: 1.5))
                .accessibilityLabel("费率倍数")
                .accessibilityHint(isFlagged ? GroupEditCopy.rateInvalidHint : "")
                .accessibilityIdentifier("group-edit.rate")
            stepButton(up: true)
        }
        .frame(minHeight: 44)
    }

    private func stepButton(up: Bool) -> some View {
        Button { step(up) } label: {
            Image(systemName: up ? "plus" : "minus").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(up ? "增加 0.1" : "减少 0.1")
        .accessibilityIdentifier(up ? "group-edit.rate.increment" : "group-edit.rate.decrement")
    }
}

/// A limit in dollars: “$” only once there is an amount, “无限制” when blank.
private struct GroupEditAmountRow: View {
    let label: String
    @Binding var text: String
    let isFlagged: Bool
    let id: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(Palette.ink1)
            Spacer(minLength: 8)
            if !text.isEmpty {
                Text("$").foregroundStyle(Palette.ink2).accessibilityIdentifier("group-edit.\(id).currency")
            }
            TextField(label, text: $text, prompt: Text(GroupEditCopy.limitPlaceholder))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 72, alignment: .trailing)
                .accessibilityLabel(label)
                .accessibilityIdentifier("group-edit.\(id)")
        }
        .frame(minHeight: 44)
        .flagged(isFlagged)
    }
}

/// Digits only. The field keeps its own text and cuts it on the next turn: set in the same update, SwiftUI skips a value equal to
/// the one it last showed and the dropped key would stay on screen.
private struct GroupEditDigitsRow: View {
    let label: String
    @Binding var value: String
    let prompt: String
    let id: String
    @State private var text: String

    init(label: String, value: Binding<String>, prompt: String, id: String) {
        self.label = label; _value = value; self.prompt = prompt; self.id = id
        _text = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        GroupEditTextRow(label: label, text: $text, prompt: prompt, id: id, keyboard: .numberPad)
            .onChange(of: text) { _, typed in
                let clean = GroupEditDraft.digitsOnly(typed)
                if value != clean { value = clean }
                if clean != typed { Task { @MainActor in text = clean } }
            }
    }
}

private extension View {
    /// 3.5 校验不通过: a red outline around the row's input area.
    func flagged(_ isFlagged: Bool) -> some View {
        overlay(alignment: .trailing) {
            if isFlagged {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.critical, lineWidth: 1.5).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}
