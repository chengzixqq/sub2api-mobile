import SwiftUI
import Sub2Core

/// 30 §7.3 换分组 (design UeKeyGroupSheet): 不绑定分组, then every active group; picking one runs the change at once and closes.
struct UserKeyGroupSheet: View {
    let keyName: String
    let options: [UserKeyGroupOption]
    let onPick: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(options) { option in
                        UserKeyGroupOptionRow(option: option) {
                            dismiss()
                            onPick(option.groupID)
                        }
                    }
                } footer: {
                    Text(UserKeyPresentation.groupSheetFootnote)
                }
            }
            .navigationTitle(UserKeyPresentation.groupSheetTitle(keyName: keyName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("keys.group.cancel")
                }
            }
            .accessibilityIdentifier("keys.group.sheet")
        }
        .presentationDetents([.large])
    }
}

/// One group choice: a mark on the current one, the subtitle of 30 §7.3; a subscription group without an active subscription
/// is greyed. S3-13's new key form shows the same rows.
struct UserKeyGroupOptionRow: View {
    let option: UserKeyGroupOption
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 12) {
                Image(systemName: option.isCurrent ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(option.isCurrent ? Palette.accent : Palette.ink3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).foregroundStyle(option.isEnabled ? Palette.ink1 : Palette.ink3)
                    Text(option.subtitle).font(.footnote).foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!option.isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(option.isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("keys.group.option." + (option.groupID.map(String.init) ?? "none"))
    }
}
