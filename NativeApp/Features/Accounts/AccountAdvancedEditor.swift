import SwiftUI
import Sub2Core

/// 20 §3.3 高级 sheet: the account's rows in table order — switches with their notes, a limit's switch with its amount (and
/// what is wrong with it) under it, 账号类型 as a segment, API 协议 and Responses API 支持 as option lists pushed inside the sheet.
/// A custom endpoint leaves 账号类型 and API 协议 read-only with a footnote.
struct AccountAdvancedEditor: View {
    @Binding var draft: AccountAdvancedDraft
    /// {平台} · {类型}
    let header: String

    var body: some View {
        Section {
            ForEach(draft.fields) { row($0) }
        } header: {
            Text(header).textCase(nil)
        } footer: {
            if draft.endpointsLocked {
                Text(AccountAdvancedDraft.endpointsLockedNote).accessibilityIdentifier("accountSheet.adv.endpointsLocked")
            }
        }
    }

    @ViewBuilder private func row(_ field: AccountAdvancedField) -> some View {
        switch field.kind {
        case .toggle:
            Toggle(isOn: $draft.values[toggle: field]) { labels(field) }.accessibilityIdentifier(id(field))
        case .limit:
            Toggle(isOn: $draft.values[limit: field].isOn) { labels(field) }.accessibilityIdentifier(id(field))
            if draft.values[limit: field].isOn { amountRow(field) }
        case .segment:
            if draft.endpointsLocked { lockedRow(field) } else { modeRow(field) }
        case .options:
            if field == .apiProtocol && draft.endpointsLocked {
                lockedRow(field)
            } else {
                NavigationLink(value: AccountEditPage.advOption(field)) {
                    LabeledContent(field.title, value: AccountAdvancedDraft.display(field, values: draft.values).text)
                }
                .accessibilityIdentifier(id(field))
            }
        }
    }

    private func labels(_ field: AccountAdvancedField) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.title)
            if let note = field.subtitle { Text(note).font(.footnote).foregroundStyle(Palette.ink3) }
        }
    }
    private func amountRow(_ field: AccountAdvancedField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                HStack(spacing: 2) {
                    if field == .windowCost { Text("$").foregroundStyle(Palette.ink3).accessibilityHidden(true) }
                    TextField(placeholder(field), text: $draft.values[limit: field].text)
                        .keyboardType(field == .windowCost ? .decimalPad : .numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .accessibilityLabel(field.limitLabel ?? field.title)
                        .accessibilityIdentifier(id(field) + ".value")
                }
            } label: {
                Text(field.limitLabel ?? "").foregroundStyle(Palette.ink2)
            }
            .padding(.leading, 16)
            if let error = draft.error(for: field) {
                Text(error).font(.footnote).foregroundStyle(Tone.critical.ink).accessibilityIdentifier(id(field) + ".error")
            }
        }
    }
    private func modeRow(_ field: AccountAdvancedField) -> some View {
        let selection = Binding(get: { draft.values.accountMode ?? "" }, set: { draft = draft.withMode($0) })
        return HStack(spacing: 12) {
            Text(field.title)
            Spacer(minLength: 8)
            Picker(field.title, selection: selection) {
                ForEach(draft.modeOptions, id: \.self) { Text(AccountProtocolEndpoints.modeTitle($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier(id(field))
        }
    }
    private func lockedRow(_ field: AccountAdvancedField) -> some View {
        LabeledContent(field.title, value: AccountAdvancedDraft.display(field, values: draft.values).text)
            .accessibilityIdentifier(id(field))
    }
    private func id(_ field: AccountAdvancedField) -> String { "accountSheet.adv.\(field.rawValue)" }
    private func placeholder(_ field: AccountAdvancedField) -> String { field == .windowCost ? "50" : "1" }
}

/// The options of API 协议 or Responses API 支持 (Picker(.navigationLink) in the design): a tick on the current one; a tap
/// chooses and goes back.
struct AccountAdvancedOptionList: View {
    let field: AccountAdvancedField
    @Binding var draft: AccountAdvancedDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let current = selected
        List {
            ForEach(options) { option in
                Button { choose(option.value) } label: {
                    HStack {
                        Text(option.title).foregroundStyle(Palette.ink1)
                        Spacer()
                        if option.value == current { Image(systemName: "checkmark").foregroundStyle(Palette.accent).accessibilityHidden(true) }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option.value == current ? [.isButton, .isSelected] : [.isButton])
                .accessibilityIdentifier("accountSheet.adv.option.\(option.value)")
            }
        }
        .navigationTitle(field.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct Option: Identifiable {
        let value: String
        let title: String
        var id: String { value }
    }
    private var options: [Option] {
        field == .apiProtocol
            ? draft.protocolOptions.map { Option(value: $0, title: AccountProtocolEndpoints.protocolTitle($0)) }
            : AccountResponsesMode.allCases.map { Option(value: $0.rawValue, title: $0.title) }
    }
    private var selected: String { field == .apiProtocol ? draft.values.apiProtocol ?? "" : draft.values.responsesMode.rawValue }
    private func choose(_ value: String) {
        if field == .apiProtocol { draft = draft.withProtocol(value) } else { draft.values.responsesMode = AccountResponsesMode(rawValue: value) ?? .auto }
        dismiss()
    }
}
