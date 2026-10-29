import SwiftUI
import Sub2Core

/// 30 §5.3 基础段: 账户 (email, username, notes, the site's attributes), 登录 (password) and 余额 (initial balance). Every row
/// carries its field as `id`, so a failed check scrolls to it; its message shows under it once “创建用户” was pressed.
struct UserEditBasicSection: View {
    @Bindable var editor: UserEditorModel
    var focus: FocusState<UserDraftField?>.Binding
    let onPickAttribute: @MainActor (Int) -> Void
    @Environment(AppModel.self) private var model
    @State private var showsPassword = false

    /// C-3: a copied password is gone from the pasteboard after a minute.
    private static let passwordCopyLifetime: TimeInterval = 60

    var body: some View {
        Section(UserEditCopy.accountSection) {
            UserEditFieldRow(title: UserDraftField.email.title, error: editor.issue(for: .email), identifier: "user-edit.email") {
                TextField("", text: $editor.draft.email, prompt: Text(UserEditCopy.emailPlaceholder))
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused(focus, equals: .email)
                    .accessibilityIdentifier("user-edit.email")
            }
            .id(UserDraftField.email)
            UserEditFieldRow(title: UserDraftField.username.title, error: nil, identifier: "user-edit.username") {
                TextField("", text: $editor.draft.username, prompt: Text(UserEditCopy.optionalPlaceholder))
                    .autocorrectionDisabled()
                    .focused(focus, equals: .username)
                    .accessibilityIdentifier("user-edit.username")
            }
            .id(UserDraftField.username)
            UserEditFieldRow(title: UserDraftField.notes.title, error: nil, identifier: "user-edit.notes") {
                TextField("", text: $editor.draft.notes, prompt: Text(UserEditCopy.notesPlaceholder), axis: .vertical)
                    .lineLimit(2...4)
                    .focused(focus, equals: .notes)
                    .accessibilityIdentifier("user-edit.notes")
            }
            .id(UserDraftField.notes)
            attributeRows
        }
        Section(UserEditCopy.loginSection) {
            passwordRow
            passwordActions
        }
        Section {
            UserEditFieldRow(title: UserDraftField.initialBalance.title, error: editor.issue(for: .initialBalance), identifier: "user-edit.balance") {
                HStack(spacing: 4) {
                    Text("$").foregroundStyle(Palette.ink2).accessibilityHidden(true)
                    TextField("", text: $editor.draft.initialBalance, prompt: Text(UserEditCopy.balancePlaceholder))
                        .keyboardType(.decimalPad).monospacedDigit()
                        .focused(focus, equals: .initialBalance)
                        .accessibilityIdentifier("user-edit.balance")
                }
            }
            .id(UserDraftField.initialBalance)
        } header: { Text(UserEditCopy.balanceSection) } footer: { Text(UserEditCopy.balanceFootnote) }
    }

    // MARK: - 自定义属性

    @ViewBuilder private var attributeRows: some View {
        if editor.definitionsState == .failed {
            Button(UserEditCopy.attributesFailedToLoad) { Task { await editor.loadDefinitions(model: model) } }
                .frame(minHeight: 44)
                .accessibilityIdentifier("user-edit.attrs.retry")
        }
        ForEach(editor.definitions) { definition in
            let field = UserDraftField.attribute(id: definition.id, name: definition.name)
            Group {
                if definition.isReadOnly {
                    readOnlyRow(definition)
                } else if definition.kind == .select {
                    selectRow(definition, error: editor.issue(for: field))
                } else {
                    UserEditFieldRow(title: definition.name, error: editor.issue(for: field), identifier: "user-edit.attr.\(definition.id)") {
                        TextField("", text: attributeText(definition.id), prompt: Text(UserEditCopy.attributePlaceholder(definition)))
                            .keyboardType(Self.keyboard(for: definition.kind)).autocorrectionDisabled()
                            .textInputAutocapitalization(definition.kind == .email || definition.kind == .url ? .never : nil)
                            .focused(focus, equals: field)
                            .accessibilityIdentifier("user-edit.attr.\(definition.id)")
                    }
                }
            }
            .id(field)
        }
    }
    /// The option sheet has “不填”; the row reads the option's label.
    private func selectRow(_ definition: UserAttributeDefinition, error: String?) -> some View {
        let value = editor.draft.attributes[definition.id] ?? ""
        let shown = value.isEmpty ? UserEditCopy.attributeEmpty : definition.optionLabel(for: value) ?? value
        return VStack(alignment: .leading, spacing: 4) {
            Button { onPickAttribute(definition.id) } label: {
                HStack(spacing: 12) {
                    Text(definition.name).foregroundStyle(Palette.ink2).frame(minWidth: UserEditFieldRow<EmptyView>.labelWidth, alignment: .leading)
                    Text(shown).foregroundStyle(value.isEmpty ? Palette.ink3 : Palette.ink1).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(definition.name))
            .accessibilityValue(Text(shown))
            .accessibilityIdentifier("user-edit.attr.\(definition.id)")
            if let error { UserEditIssueText(message: error, identifier: "user-edit.attr.\(definition.id).error") }
        }
    }
    /// U28: multi_select (and a type this App does not know) is shown as stored and changed on the web.
    private func readOnlyRow(_ definition: UserAttributeDefinition) -> some View {
        let value = editor.draft.attributes[definition.id] ?? ""
        return HStack(spacing: 12) {
            Text(definition.name).foregroundStyle(Palette.ink2).frame(minWidth: UserEditFieldRow<EmptyView>.labelWidth, alignment: .leading)
            Text(value.isEmpty ? DisplayFormat.missing : value).foregroundStyle(Palette.ink1).frame(maxWidth: .infinity, alignment: .leading)
            Text(UserEditCopy.attributeReadOnly).font(.footnote).foregroundStyle(Palette.ink3)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("user-edit.attr.\(definition.id)")
    }
    private func attributeText(_ id: Int) -> Binding<String> {
        Binding(get: { editor.draft.attributes[id] ?? "" }, set: { editor.draft.attributes[id] = $0 })
    }
    private static func keyboard(for kind: UserAttributeDefinition.Kind?) -> UIKeyboardType {
        switch kind {
        case .number?: .numbersAndPunctuation
        case .email?: .emailAddress
        case .url?: .URL
        default: .default
        }
    }

    // MARK: - 密码

    private var passwordRow: some View {
        UserEditFieldRow(title: UserDraftField.password.title, error: editor.issue(for: .password), identifier: "user-edit.password") {
            Group {
                if showsPassword {
                    TextField("", text: $editor.draft.password, prompt: Text(UserEditCopy.passwordPlaceholder)).font(.body.monospaced())
                } else {
                    SecureField("", text: $editor.draft.password, prompt: Text(UserEditCopy.passwordPlaceholder))
                }
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
            .focused(focus, equals: .password)
            .accessibilityIdentifier("user-edit.password")
            Button(showsPassword ? UserEditCopy.hidePassword : UserEditCopy.showPassword) { showsPassword.toggle() }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("user-edit.password.toggle")
        }
        .id(UserDraftField.password)
    }
    /// 30 §5.3: a generated password shows at once; “复制” only while there is one.
    private var passwordActions: some View {
        HStack(spacing: 20) {
            Button(UserEditCopy.generatePassword, systemImage: "arrow.clockwise") {
                editor.generatePassword()
                showsPassword = true
            }
            .accessibilityIdentifier("user-edit.password.generate")
            if !editor.draft.password.isEmpty {
                Button(UserEditCopy.copyPassword, systemImage: "doc.on.doc") {
                    SensitivePasteboard.copy(editor.draft.password, expiresIn: Self.passwordCopyLifetime)
                    model.receipts.show(Receipt(text: UserEditCopy.passwordCopied, systemImage: "doc.on.doc", tone: .neutral))
                }
                .accessibilityIdentifier("user-edit.password.copy")
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
    }
}

/// One form row: the label, the field and, once the check ran, its message in red under it.
struct UserEditFieldRow<Field: View>: View {
    static var labelWidth: CGFloat { 64 }
    let title: String
    let error: String?
    /// The field's identifier; the message is “<identifier>.error”.
    let identifier: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).foregroundStyle(Palette.ink2).frame(minWidth: Self.labelWidth, alignment: .leading).accessibilityHidden(true)
                field
            }
            .frame(minHeight: 44)
            if let error { UserEditIssueText(message: error, identifier: identifier + ".error") }
        }
    }
}

/// A field's message in red (30 §5.3 校验, §5.5).
struct UserEditIssueText: View {
    let message: String
    let identifier: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill").accessibilityHidden(true)
            Text(message).accessibilityIdentifier(identifier)
        }
        .font(.footnote)
        .foregroundStyle(Palette.criticalInk)
    }
}

/// A select attribute's options and “不填” (design UeAttrSheet); picking closes the sheet.
struct UserAttributeOptionSheet: View {
    let definition: UserAttributeDefinition
    let value: String
    let onPick: @MainActor (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(definition.options, id: \.value) { option in row(option.label, value: option.value, identifier: "user-edit.attr-option.\(option.value)") }
                    row(UserEditCopy.attributeNone, value: "", identifier: "user-edit.attr-option.none")
                } footer: { Text(UserEditCopy.attributeSheetFootnote) }
            }
            .navigationTitle(definition.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }.accessibilityIdentifier("user-edit.attr-sheet.cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, value option: String, identifier: String) -> some View {
        Button {
            onPick(option)
            dismiss()
        } label: {
            HStack {
                Text(title).foregroundStyle(Palette.ink1)
                Spacer()
                if value == option { Image(systemName: "checkmark").foregroundStyle(Palette.accent).accessibilityHidden(true) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(value == option ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
