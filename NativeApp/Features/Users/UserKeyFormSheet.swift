import SwiftUI
import Sub2Core

/// 30 §7.4 新建 Key / 编辑 Key (U24: no design, a minimal one-page form). Errors stand under their rows, a refusal without a
/// row at the bottom; “创建” / “保存” only with a change. While sending the sheet cannot be swiped away, and with a change
/// 取消 asks first.
struct UserKeyFormSheet: View {
    @Bindable var model: UserKeyFormModel
    /// The rows of 换分组 for the draft's group (S3-12).
    let groupOptions: (Int?) -> [UserKeyGroupOption]
    let zone: ServerTimeZone
    /// The user's “保存” is not out (S3D1-11).
    let immediateWritesAllowed: Bool
    let onSubmit: @MainActor (UserKeyFormModel) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var asksDiscard = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                form.onChange(of: model.issueAnchor) { _, anchor in
                    guard let anchor else { return }
                    withAnimation { proxy.scrollTo(anchor, anchor: .center) }
                }
            }
            .navigationTitle(model.isCreate ? UserKeyFormCopy.createTitle : UserKeyFormCopy.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog(UserKeyFormCopy.discardTitle, isPresented: $asksDiscard, titleVisibility: .visible) {
                Button(UserKeyFormCopy.discardConfirm, role: .destructive) { dismiss() }
                Button(UserKeyFormCopy.discardKeep, role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(model.isSubmitting || model.hasChanges)
    }

    private var form: some View {
        Form {
            nameSection
            if model.isCreate { groupSection }
            quotaSection
            expirySection
            ipSection(.ipWhitelist, title: "IP 白名单", text: $model.draft.ipWhitelist)
            ipSection(.ipBlacklist, title: "IP 黑名单", text: $model.draft.ipBlacklist)
            rateSection
            if model.formError != nil || model.progressNote != nil { statusSection }
        }
        .disabled(model.isSubmitting)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("keys.form.sheet")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { if model.hasChanges { asksDiscard = true } else { dismiss() } }
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("keys.form.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.isSubmitting {
                ProgressView().accessibilityIdentifier("keys.form.progress")
            } else {
                Button(model.isCreate ? UserKeyFormCopy.createAction : UserKeyFormCopy.saveAction) { Task { await onSubmit(model) } }
                    .disabled(!model.canSubmit(immediateWritesAllowed: immediateWritesAllowed))
                    .accessibilityIdentifier("keys.form.submit")
            }
        }
    }

    private var nameSection: some View {
        Section("名称") {
            TextField(UserKeyFormCopy.namePlaceholder, text: $model.draft.name)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityLabel("名称")
                .accessibilityIdentifier("keys.form.name")
            issue(.name)
        }
    }

    private var groupSection: some View {
        Section {
            NavigationLink {
                UserKeyFormGroupPicker(options: groupOptions(model.draft.groupID)) { model.draft.groupID = $0 }
            } label: {
                LabeledContent("分组", value: groupOptions(model.draft.groupID).first { $0.groupID == model.draft.groupID }?.title ?? "不绑定分组")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("keys.form.group")
            issue(.group)
        } footer: {
            Text(UserKeyFormCopy.groupFootnote)
        }
    }

    private var quotaSection: some View {
        Section {
            amountRow("额度（$）", text: $model.draft.quota, field: .quota)
            if model.showsResetQuota {
                Toggle(UserKeyFormCopy.resetQuotaTitle, isOn: $model.draft.resetQuota)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("keys.form.resetQuota")
            }
        } footer: {
            if model.showsResetQuota { Text(UserKeyFormCopy.resetQuotaFootnote) }
        }
    }

    @ViewBuilder private var expirySection: some View {
        Section("有效期") {
            if model.isCreate {
                Picker("有效期", selection: $model.draft.expiryChoice) {
                    ForEach(UserKeyExpiryChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("keys.form.expiry")
                if model.draft.expiryChoice == .custom {
                    TextField(UserKeyFormCopy.customDaysPlaceholder, text: $model.draft.customDays)
                        .keyboardType(.numberPad)
                        .frame(minHeight: 44)
                        .accessibilityLabel("自定义天数")
                        .accessibilityIdentifier("keys.form.customDays")
                }
            } else {
                UserKeyEditExpiryRows(expiry: $model.draft.editExpiry, original: model.original?.expiresAt, zone: zone)
            }
            issue(.expiry)
        }
    }

    private func ipSection(_ field: UserKeyField, title: String, text: Binding<String>) -> some View {
        Section {
            TextField(UserKeyFormCopy.ipPlaceholder, text: text, axis: .vertical)
                .lineLimit(2...6)
                .font(.body.monospaced())
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityLabel(title)
                .accessibilityIdentifier("keys.form.\(field.rawValue)")
            issue(field)
        } header: {
            Text(title)
        } footer: {
            if field == .ipBlacklist { Text(UserKeyFormCopy.ipFootnote) }
        }
    }

    private var rateSection: some View {
        Section {
            amountRow("5 小时（$）", text: $model.draft.rateLimit5h, field: .rateLimit5h)
            amountRow("1 天（$）", text: $model.draft.rateLimit1d, field: .rateLimit1d)
            amountRow("7 天（$）", text: $model.draft.rateLimit7d, field: .rateLimit7d)
        } header: {
            Text(UserKeyPresentation.rateTitle)
        } footer: {
            Text(UserKeyFormCopy.rateFootnote)
        }
    }

    private var statusSection: some View {
        Section {
            if let note = model.progressNote {
                Label(note, systemImage: "hourglass").font(.footnote).foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("keys.form.progressNote")
            }
            if let error = model.formError {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Palette.critical)
                    .id("keys.form.formError")
                    .accessibilityIdentifier("keys.form.formError")
            }
        }
    }

    private func amountRow(_ title: String, text: Binding<String>, field: UserKeyField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                TextField(UserKeyFormCopy.amountPlaceholder, text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("keys.form.\(field.rawValue)")
            }
            .frame(minHeight: 44)
            issue(field)
        }
    }

    @ViewBuilder private func issue(_ field: UserKeyField) -> some View {
        if let message = model.error(for: field) {
            Text(message).font(.footnote).foregroundStyle(Palette.critical)
                .id("keys.form.error.\(field.rawValue)")
                .accessibilityIdentifier("keys.form.error.\(field.rawValue)")
        }
    }
}

/// 编辑 Key 的有效期: 永久 or a day on the server's calendar (R20).
private struct UserKeyEditExpiryRows: View {
    @Binding var expiry: UserKeyEditExpiry
    let original: Date?
    let zone: ServerTimeZone

    var body: some View {
        Picker("有效期", selection: hasDate) {
            Text(UserKeyFormCopy.editExpiryNever).tag(false)
            Text(UserKeyFormCopy.editExpiryDate).tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("keys.form.expiry")
        if case .on(let day) = expiry {
            DatePicker("到期日", selection: Binding(get: { day }, set: { expiry = .on($0) }), displayedComponents: .date)
                .environment(\.timeZone, zone.timeZone)
                .environment(\.calendar, zone.calendar)
                .frame(minHeight: 44)
                .accessibilityIdentifier("keys.form.expiryDate")
        }
    }

    private var hasDate: Binding<Bool> {
        Binding(get: { expiry != .never }, set: { on in
            guard on != (expiry != .never) else { return }
            expiry = on ? .on(original ?? Date().addingTimeInterval(30 * 86_400)) : .never
        })
    }
}

/// The new key's group: the rows of 换分组, picking one goes back.
private struct UserKeyFormGroupPicker: View {
    let options: [UserKeyGroupOption]
    let onPick: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(options) { option in
                    UserKeyGroupOptionRow(option: option) {
                        onPick(option.groupID)
                        dismiss()
                    }
                }
            } footer: {
                Text(UserKeyFormCopy.groupFootnote)
            }
        }
        .navigationTitle("分组")
        .navigationBarTitleDisplayMode(.inline)
    }
}
