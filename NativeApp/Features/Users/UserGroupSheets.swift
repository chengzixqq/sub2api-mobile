import SwiftUI
import Sub2Core

/// 30 §5.3 / §6.3 添加专属分组: several active exclusive standard groups the user does not have yet; “添加 N 个” in the top
/// right. S3-11 opens it from the edit page with `isCreate: false`.
struct UserAddExclusiveGroupsSheet: View {
    let options: [AdminGroup]
    let subscriptionNote: String?
    let isCreate: Bool
    let onAdd: @MainActor (Set<Int>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<Int> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if options.isEmpty {
                        Text(UserEditCopy.addGroupsEmpty).foregroundStyle(Palette.ink2).frame(minHeight: 44)
                            .accessibilityIdentifier("user-edit.add-groups.empty")
                    }
                    ForEach(options) { group in row(group) }
                } footer: { Text(footnote) }
            }
            .navigationTitle(UserEditCopy.addExclusiveGroup)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }.accessibilityIdentifier("user-edit.add-groups.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(UserEditCopy.addGroupsButton(picked.count)) {
                        onAdd(picked)
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                    .accessibilityIdentifier("user-edit.add-groups.confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var footnote: String {
        (isCreate ? UserEditCopy.addGroupsFootnoteCreate : UserEditCopy.addGroupsFootnoteSave) + (subscriptionNote ?? "")
    }
    private func row(_ group: AdminGroup) -> some View {
        let on = picked.contains(group.id)
        return Button {
            if on { picked.remove(group.id) } else { picked.insert(group.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(on ? Palette.accent : Palette.ink3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).foregroundStyle(Palette.ink1)
                    Text(UserEditAccessSection.platformName(group) + " · 默认倍率 " + UserEditCopy.rateText(group.rateMultiplier))
                        .font(.footnote).foregroundStyle(Palette.ink2)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("user-edit.add-groups.\(group.id)")
    }
}

/// 30 §5.3 / §6.3 分组 sheet. A new user (context `.create`) has no rates yet: only the restricted public group's “允许使用”
/// and, for an exclusive group, “移除这个专属分组”. “完成” changes the draft only. S3-11 adds the edit context's rate box.
struct UserGroupSheet: View {
    enum Context { case create, edit }
    let group: AdminGroup
    let isExclusive: Bool
    let context: Context
    let restrictsPublic: Bool
    let onDone: @MainActor (_ allowed: Bool) -> Void
    let onRemove: (@MainActor () -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var allowed: Bool

    init(group: AdminGroup, isExclusive: Bool, context: Context, restrictsPublic: Bool, allowed: Bool,
         onDone: @escaping @MainActor (_ allowed: Bool) -> Void, onRemove: (@MainActor () -> Void)?) {
        self.group = group; self.isExclusive = isExclusive; self.context = context; self.restrictsPublic = restrictsPublic
        self.onDone = onDone; self.onRemove = onRemove
        _allowed = State(initialValue: allowed)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(UserEditCopy.groupSheetNote(group, platformName: UserEditAccessSection.platformName(group)))
                        .font(.subheadline).foregroundStyle(Palette.ink2)
                        .accessibilityIdentifier("user-edit.group-sheet.note")
                    if !isExclusive && restrictsPublic {
                        Toggle(isOn: $allowed) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(UserEditCopy.allowPublicTitle)
                                Text(UserEditCopy.allowPublicSubtitle(allowed)).font(.footnote).foregroundStyle(Palette.ink2)
                            }
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("user-edit.group-sheet.allow")
                    }
                    if context == .create {
                        Text(UserEditCopy.rateAfterCreate).foregroundStyle(Palette.ink3).frame(minHeight: 44)
                    }
                } footer: {
                    if context == .create { Text(UserEditCopy.groupSheetFootnoteCreate) }
                }
                if isExclusive, let onRemove {
                    Section {
                        Button(UserEditCopy.removeExclusive, systemImage: "minus.circle", role: .destructive) {
                            onRemove()
                            dismiss()
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("user-edit.group-sheet.remove")
                    }
                }
            }
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(UserEditCopy.groupSheetDone) {
                        onDone(allowed)
                        dismiss()
                    }
                    .accessibilityIdentifier("user-edit.group-sheet.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
