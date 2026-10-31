import SwiftUI
import Sub2Core

// 20 §3.3: the 基础 and 调度 forms of AccountSectionSheet. A wrong field says why right under it.

/// 基础: 名称 (required), 账号状态 (正常 | 停用, or 错误 | 停用 for an account in error), the read-only 平台 · 类型, 备注.
struct AccountBasicForm: View {
    @Binding var draft: AccountEditDraft
    let form: AccountEditForm
    let errors: [AccountEditField: String]
    let platformText: String

    var body: some View {
        Section {
            AccountEditTextRow(field: .name, idName: "name", placeholder: "账号名称", text: $draft.name, error: errors[.name])
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(AccountEditField.status.title)
                    Spacer(minLength: 8)
                    Picker(AccountEditField.status.title, selection: $draft.status) {
                        ForEach(form.statusOptions, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier("account.edit.status")
                }
                Text(form.statusFootnote).font(.footnote).foregroundStyle(Palette.ink3)
            }
            LabeledContent("平台", value: platformText).accessibilityIdentifier("account.edit.platform")
            VStack(alignment: .leading, spacing: 6) {
                Text(AccountEditField.notes.title)
                TextField("可选", text: $draft.notes, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityLabel(AccountEditField.notes.title)
                    .accessibilityIdentifier("account.edit.notes")
            }
        }
    }
}

/// 调度: 并发数 (Stepper from 1) and 优先级 (from 0), the rate (read-only while the upstream rate sync keeps it), 负载因子, 分组 and
/// 过期时间 pushed in the sheet, 过期自动暂停调度 only with an expiry; for API Key and Bedrock accounts the 配额 group.
struct AccountScheduleForm: View {
    @Binding var draft: AccountEditDraft
    let form: AccountEditForm
    let errors: [AccountEditField: String]
    let groupNames: [String]

    var body: some View {
        Section {
            stepper(.concurrency, idName: "concurrency", value: \.concurrency, range: 1...10_000)
            stepper(.priority, idName: "priority", note: AccountEditCopy.priorityNote, value: \.priority, range: 0...10_000)
            rateRow
            AccountEditTextRow(field: .loadFactor, idName: "loadFactor", note: AccountEditCopy.loadFactorNote, placeholder: AccountEditCopy.loadFactorDefault,
                               text: $draft.loadFactor, keyboard: .numberPad, error: errors[.loadFactor])
            NavigationLink(value: AccountEditPage.groups) {
                LabeledContent(AccountEditField.groups.title, value: groupSummary)
            }
            .accessibilityValue(groupNames.isEmpty ? AccountEditCopy.ungrouped : groupNames.joined(separator: "、"))
            .accessibilityIdentifier("account.edit.groups")
            expiryRow
            if draft.expiresAt != nil {
                Toggle(AccountEditField.autoPauseOnExpired.title, isOn: $draft.autoPauseOnExpired).accessibilityIdentifier("account.edit.autoPause")
            }
        }
        if form.showsQuota {
            Section {
                ForEach(AccountQuota.allCases, id: \.self) { quota in
                    AccountEditTextRow(field: quota.field, idName: "quota.\(quota.rawValue)", note: AccountEditCopy.quotaUsed(quota.used(in: form.base)),
                                       prefix: "$", placeholder: AccountEditCopy.quotaUnlimited, text: quotaText(quota), keyboard: .decimalPad,
                                       error: errors[quota.field])
                }
            } header: {
                HStack {
                    Text(AccountEditCopy.quotaTitle)
                    Spacer()
                    Text(AccountEditCopy.quotaSectionNote)
                }
            } footer: {
                Text(AccountEditCopy.quotaFootnote)
            }
        }
    }

    @ViewBuilder private var rateRow: some View {
        if form.isRateLocked {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(AccountEditField.rateMultiplier.title, value: AccountEditCopy.rate(form.base.rateMultiplier))
                    .accessibilityIdentifier("account.edit.rate")
                Text(AccountEditCopy.rateLockedNote).font(.footnote).foregroundStyle(Palette.ink3)
            }
        } else {
            AccountEditTextRow(field: .rateMultiplier, idName: "rate", note: AccountEditCopy.rateNote, prefix: "×", placeholder: "1",
                               text: $draft.rateMultiplier, keyboard: .decimalPad, error: errors[.rateMultiplier])
        }
    }
    @ViewBuilder private var expiryRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            NavigationLink(value: AccountEditPage.expiry) {
                LabeledContent(AccountEditField.expiresAt.title, value: AccountExpiry.text(draft.expiresAt, timeZone: .current))
            }
            .accessibilityIdentifier("account.edit.expiry")
            if let error = errors[.expiresAt] { AccountEditError(text: error, field: .expiresAt) }
        }
    }
    /// The first two names, then +N (design AeChipsVal).
    private var groupSummary: String {
        guard !groupNames.isEmpty else { return AccountEditCopy.ungrouped }
        let shown = groupNames.prefix(2).joined(separator: "、")
        return groupNames.count > 2 ? "\(shown) +\(groupNames.count - 2)" : shown
    }
    private func stepper(_ field: AccountEditField, idName: String, note: String? = nil, value: WritableKeyPath<AccountEditDraft, Int?>,
                         range: ClosedRange<Int>) -> some View {
        let binding = Binding(get: { draft[keyPath: value] ?? 0 }, set: { draft[keyPath: value] = max(range.lowerBound, $0) })
        return Stepper(value: binding, in: range) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.title)
                    if let note { Text(note).font(.footnote).foregroundStyle(Palette.ink3) }
                }
                Spacer()
                Text(draft[keyPath: value].map(String.init) ?? DisplayFormat.missing).monospacedDigit().foregroundStyle(Palette.ink2)
            }
        }
        .accessibilityValue(draft[keyPath: value].map(String.init) ?? DisplayFormat.missingSpoken)
        .accessibilityIdentifier("account.edit.\(idName)")
    }
    private func quotaText(_ quota: AccountQuota) -> Binding<String> {
        Binding(get: { draft[quota] }, set: { draft[quota] = $0 })
    }
}

/// A labelled text field (prefix ×, $ where the design has one) with its error underneath.
struct AccountEditTextRow: View {
    let field: AccountEditField
    /// account.edit.<idName>
    let idName: String
    var note: String?
    var prefix: String?
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                HStack(spacing: 2) {
                    if let prefix { Text(prefix).foregroundStyle(Palette.ink3).accessibilityHidden(true) }
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel(field.title)
                        .accessibilityIdentifier("account.edit.\(idName)")
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.title)
                    if let note { Text(note).font(.footnote).foregroundStyle(Palette.ink3) }
                }
            }
            if let error { AccountEditError(text: error, field: field) }
        }
    }
}

struct AccountEditError: View {
    let text: String
    let field: AccountEditField

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Tone.critical.ink).accessibilityIdentifier("account.edit.error.\(field.rawValue)")
    }
}
