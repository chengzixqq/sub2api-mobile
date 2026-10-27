import SwiftUI
import Sub2Core

/// 20 §3.3 分组, pushed inside the sheet (S2-19's new account reuses it): GroupDirectory's active groups of the account's platform
/// and composite ones, plus the groups it is already in (stopped or of another platform, so they can be taken out). A tap adds
/// the group at the end (the account's priority in it follows its place, S2D1-07) or takes it out.
struct AccountGroupPicker: View {
    @Binding var selection: [Int]
    let account: UpstreamAccount
    let platformName: (String) -> String
    @Environment(AppModel.self) private var model

    var body: some View {
        let directory = model.groupDirectory
        let state = directory?.state ?? .idle
        let current = Set(AccountEditDraft.groupOrder(account)).union(selection)
        let choices = AccountGroupChoices.choices(groups: directory?.groups ?? [], account: account, current: current, platformName: platformName)
        List {
            Section {
                if case .failed(let reason, _, _) = state { failure(reason ?? "", directory: directory) }
                if choices.isEmpty, state.value != nil {
                    Text(AccountGroupChoices.emptyText(account: account, platformName: platformName)).foregroundStyle(Palette.ink3)
                }
                if choices.isEmpty, state.isLoading { ProgressView().frame(maxWidth: .infinity) }
                ForEach(choices) { row($0) }
            } header: {
                Text(AccountGroupChoices.header(account: account, platformName: platformName))
                    .textCase(nil)
                    .accessibilityIdentifier("account.groups.header")
            } footer: {
                footer(choices)
            }
        }
        .navigationTitle(AccountEditField.groups.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await directory?.ensureLoaded() }
    }

    private func row(_ choice: AccountGroupChoice) -> some View {
        let selected = selection.contains(choice.id)
        return Button { toggle(choice.id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Palette.accent : Palette.ink3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(choice.name).foregroundStyle(Palette.ink1)
                        ForEach(choice.badges, id: \.self) { ToneBadge(text: $0, tone: .neutral) }
                    }
                    if let detail = choice.detail { Text(detail).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink3) }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([choice.name] + choice.badges).joined(separator: "，"))
        .accessibilityValue(choice.detail ?? "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("account.groups.\(choice.id)")
    }

    @ViewBuilder private func failure(_ reason: String, directory: GroupDirectory?) -> some View {
        HStack {
            Text("读取分组失败").foregroundStyle(Tone.critical.ink)
            Spacer()
            Button("重试") { Task { await directory?.refresh() } }
                .buttonStyle(.borderless).frame(minHeight: 44).accessibilityIdentifier("account.groups.retry")
        }
        .accessibilityHint(reason)
    }

    @ViewBuilder private func footer(_ choices: [AccountGroupChoice]) -> some View {
        let noActive = !choices.isEmpty && choices.allSatisfy(\.isInactive)
        let lines = [noActive ? AccountGroupChoices.noActiveText(account: account, platformName: platformName) : nil,
                     AccountGroupChoices.mixedChannelNote(account: account)].compactMap { $0 }
        if !lines.isEmpty {
            Text(lines.joined(separator: "\n")).accessibilityIdentifier("account.groups.note")
        }
    }

    private func toggle(_ id: Int) {
        if selection.contains(id) { selection.removeAll { $0 == id } } else { selection.append(id) }
    }
}
