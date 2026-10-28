import SwiftUI
import Sub2Core

// 20 §3.3 模型: the row the detail and the sheet share, the sheet's list, and the two pages it pushes (添加模型, 添加映射).

/// The request model (monospaced) over “→ 实际模型” or 原样转发, with “限流 N 分钟” while the actual model is rate limited, counted
/// again every 30 seconds on the site's clock; in the sheet a red − takes the row out.
struct AccountModelRow: View {
    let entry: AccountModelMapping.Entry
    let limits: [AccountModelRateLimit]
    let now: () -> Date
    /// account.models.row / accountSheet.models.row
    let idPrefix: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill").font(.title3).foregroundStyle(Tone.critical.ink)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("移除 \(entry.from)")
                .accessibilityIdentifier("accountSheet.models.remove.\(entry.from)")
            }
            TimelineView(.periodic(from: .now, by: 30)) { _ in content(badge: AccountModelMapping.limitBadge(for: entry, limits: limits, now: now())) }
        }
    }

    private func content(badge: String?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.from).font(.system(.subheadline, design: .monospaced)).foregroundStyle(Palette.ink1)
                if entry.isPassthrough {
                    Text(AccountModelMapping.passthroughText).font(.footnote).foregroundStyle(Palette.ink3)
                } else {
                    Text("→ " + entry.to).font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.ink2)
                }
            }
            Spacer(minLength: 8)
            if let badge { ToneBadge(text: badge, tone: .model) }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([entry.from, entry.isPassthrough ? AccountModelMapping.passthroughText : "映射到 \(entry.to)"] + [badge].compactMap { $0 })
            .joined(separator: "，"))
        .accessibilityIdentifier("\(idPrefix).\(entry.from)")
    }
}

/// “已开启自动透传，模型限制不生效”.
struct AccountModelsPassthroughNote: View {
    let id: String
    var body: some View {
        Label(AccountModelMapping.passthroughNote, systemImage: "arrow.right")
            .font(.footnote).foregroundStyle(Tone.caution.ink)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AccountModelMapping.passthroughNote)
            .accessibilityIdentifier(id)
    }
}

/// The 模型 sheet: the rows with −, “支持所有模型” when emptied, and 添加模型 / 添加映射 pushed inside the sheet.
struct AccountModelEditor: View {
    @Binding var draft: AccountModelsDraft
    let account: UpstreamAccount
    let now: () -> Date

    var body: some View {
        let mapping = draft.mapping
        Section {
            if AccountModelMapping.passthroughEnabled(account) { AccountModelsPassthroughNote(id: "accountSheet.models.passthroughNote") }
            if mapping.isEmpty {
                Text(AccountModelMapping.emptyText).foregroundStyle(Palette.ink2).accessibilityIdentifier("accountSheet.models.empty")
            }
            ForEach(mapping.entries) { entry in
                AccountModelRow(entry: entry, limits: account.extra?.modelRateLimits ?? [], now: now, idPrefix: "accountSheet.models.row") {
                    draft.mapping = draft.mapping.removing(from: entry.from)
                }
            }
            NavigationLink(value: AccountEditPage.addModels) { Label("添加模型", systemImage: "plus") }
                .accessibilityIdentifier("accountSheet.models.addModels")
            NavigationLink(value: AccountEditPage.addMapping) { Label("添加映射", systemImage: "arrow.right") }
                .accessibilityIdentifier("accountSheet.models.addMapping")
        } header: {
            HStack {
                Text(AccountEditSection.models.title)
                Spacer()
                Text(mapping.summary).accessibilityIdentifier("accountSheet.models.summary")
            }
        } footer: {
            Text(AccountModelMapping.footnote)
        }
    }
}

/// 添加模型 (design AeModelAddBody): `GET :id/models`, `display_name` or the id; a tap adds the model as {m: m} or takes a listed
/// one out, its mapping included. The list is read once per sheet and shared with 添加映射.
struct AccountModelPicker: View {
    @Binding var mapping: AccountModelMapping
    let options: LoadState<[AccountModelOption]>
    let load: @MainActor () async -> Void

    var body: some View {
        List {
            Section("这个账号可用的模型") { rows }
        }
        .navigationTitle("添加模型")
        .navigationBarTitleDisplayMode(.inline)
        .task { if options.value == nil, !options.isLoading { await load() } }
    }

    @ViewBuilder private var rows: some View {
        if let list = options.value {
            if list.isEmpty {
                Text("没有可选的模型，可以用“添加映射”手动填写").foregroundStyle(Palette.ink3).accessibilityIdentifier("accountModels.empty")
            }
            ForEach(list) { row($0) }
        } else if options.error != nil {
            BlockFailureRow(title: "读取模型列表失败", error: options.lastError, occurredAt: options.lastErrorAt, refresh: options.refresh,
                            id: "accountModels") { Task { await load() } }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func row(_ option: AccountModelOption) -> some View {
        let listed = mapping.entry(from: option.id)
        return Button { mapping = mapping.toggling(model: option.id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: listed != nil ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(listed != nil ? Palette.accent : Palette.ink3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.displayName).foregroundStyle(Palette.ink1)
                    if option.displayName != option.id {
                        Text(option.id).font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.ink3)
                    }
                    if let listed, !listed.isPassthrough {
                        Text("映射到 \(listed.to)").font(.footnote).foregroundStyle(Palette.ink2)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.displayName)
        .accessibilityValue(listed.map { $0.isPassthrough ? "" : "映射到 \($0.to)" } ?? "")
        .accessibilityAddTraits(listed != nil ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("accountModels.option.\(option.id)")
    }
}

/// 添加映射 (design AeMapBody): request model → actual model, the account's models offered for the actual side; the preview or
/// what is wrong under them. Added at the end of the list, then back to the sheet.
struct AccountMappingForm: View {
    @Binding var mapping: AccountModelMapping
    let options: LoadState<[AccountModelOption]>
    let load: @MainActor () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var from = ""
    @State private var to = ""

    var body: some View {
        let error = AccountModelMapping.validate(from: from, to: to, existing: mapping)
        Form {
            Section("请求模型") { field("例如 claude-3-5-sonnet-*", text: $from, id: "accountMapping.from") }
            Section("实际模型") {
                field("例如 claude-sonnet-4-5", text: $to, id: "accountMapping.to")
                ForEach(options.value ?? []) { option in
                    Button(option.id) { to = option.id }
                        .font(.system(.subheadline, design: .monospaced))
                        .accessibilityIdentifier("accountMapping.suggestion.\(option.id)")
                }
            }
            Section {
                preview(error)
                Button("添加映射") { add() }.disabled(error != nil).accessibilityIdentifier("accountMapping.add")
            }
        }
        .navigationTitle("添加映射")
        .navigationBarTitleDisplayMode(.inline)
        .task { if options.value == nil, !options.isLoading { await load() } }
    }

    private func field(_ placeholder: String, text: Binding<String>, id: String) -> some View {
        TextField(placeholder, text: text)
            .font(.system(.body, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier(id)
    }
    @ViewBuilder private func preview(_ error: AccountModelMappingError?) -> some View {
        if let message = error?.message {
            Text(message).font(.footnote).foregroundStyle(Tone.critical.ink).accessibilityIdentifier("accountMapping.error")
        } else if error == nil {
            Text("\(from.trimmingCharacters(in: .whitespaces)) → \(to.trimmingCharacters(in: .whitespaces))")
                .font(.system(.footnote, design: .monospaced)).foregroundStyle(Palette.ink2)
                .accessibilityIdentifier("accountMapping.preview")
        }
    }
    private func add() {
        guard let added = try? mapping.adding(from: from, to: to) else { return }
        mapping = added
        dismiss()
    }
}
