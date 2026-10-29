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
/// and, for an exclusive group, “移除这个专属分组”. Editing adds the user's own rate (“专属倍率”, × prefix, > 0 with at most 3
/// decimals, blank for the group's default) and asks before removing a group keys are bound to. “完成” changes the draft only.
struct UserGroupSheet: View {
    enum Context { case create, edit }
    let group: AdminGroup
    let isExclusive: Bool
    let context: Context
    let restrictsPublic: Bool
    let boundKeys: Int
    let onDone: @MainActor (_ allowed: Bool, _ rate: Decimal?) -> Void
    let onRemove: (@MainActor () -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var allowed: Bool
    @State private var rateText: String
    @State private var confirmsRemoval = false

    init(group: AdminGroup, isExclusive: Bool, context: Context, restrictsPublic: Bool, allowed: Bool, rate: Decimal? = nil, boundKeys: Int = 0,
         onDone: @escaping @MainActor (_ allowed: Bool, _ rate: Decimal?) -> Void, onRemove: (@MainActor () -> Void)?) {
        self.group = group; self.isExclusive = isExclusive; self.context = context; self.restrictsPublic = restrictsPublic
        self.boundKeys = boundKeys; self.onDone = onDone; self.onRemove = onRemove
        _allowed = State(initialValue: allowed)
        _rateText = State(initialValue: rate.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
    }

    private var rate: UserRateInput { UserRateInput(text: rateText) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(context == .edit ? UserEditCopy.groupSheetNote(group, platformName: UserEditAccessSection.platformName(group), boundKeys: boundKeys)
                                          : UserEditCopy.groupSheetNote(group, platformName: UserEditAccessSection.platformName(group)))
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
                    Text(context == .create ? UserEditCopy.groupSheetFootnoteCreate : UserEditCopy.groupSheetFootnoteEdit)
                }
                if context == .edit { rateSection }
                if isExclusive, onRemove != nil {
                    Section {
                        Button(UserEditCopy.removeExclusive, systemImage: "minus.circle", role: .destructive) {
                            if context == .edit && boundKeys > 0 { confirmsRemoval = true } else { remove() }
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
                        onDone(allowed, chosenRate)
                        dismiss()
                    }
                    .disabled(rate == .invalid)
                    .accessibilityIdentifier("user-edit.group-sheet.done")
                }
            }
            // 30 §6.3: “改用替换分组” joins these buttons with S3-15.
            .alert(UserEditCopy.removeGroupTitle(group.name), isPresented: $confirmsRemoval) {
                Button(UserEditCopy.removeAnyway, role: .destructive) { removeAfterAlert() }
                Button("取消", role: .cancel) {}
            } message: { Text(UserEditCopy.removeGroupMessage(group.name, keys: boundKeys)) }
        }
        .presentationDetents([.medium, .large])
    }

    /// 30 §6.3 专属倍率: blank is the group's default.
    private var rateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("×").foregroundStyle(Palette.ink2).accessibilityHidden(true)
                    TextField("", text: $rateText, prompt: Text(UserEditCopy.ratePlaceholder(group)))
                        .keyboardType(.decimalPad).monospacedDigit()
                        .accessibilityLabel(Text(UserEditCopy.rateTitle))
                        .accessibilityIdentifier("user-edit.group-sheet.rate")
                }
                .frame(minHeight: 44)
                if rate == .invalid { UserEditIssueText(message: UserRateInput.errorMessage, identifier: "user-edit.group-sheet.rate.error") }
            }
            if !rateText.isEmpty {
                Button(UserEditCopy.resetRate(group)) { rateText = "" }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("user-edit.group-sheet.reset")
            }
        } header: { Text(UserEditCopy.rateTitle) } footer: { Text(UserEditCopy.rateSubtitle) }
    }
    private var chosenRate: Decimal? {
        if case .rate(let value) = rate { value } else { nil }
    }
    private func remove() {
        onRemove?()
        dismiss()
    }
    /// The sheet closes once the alert has left.
    private func removeAfterAlert() {
        onRemove?()
        Task {
            try? await Task.sleep(for: Self.afterAlertDelay)
            dismiss()
        }
    }
    private static let afterAlertDelay: Duration = .milliseconds(450)
}
