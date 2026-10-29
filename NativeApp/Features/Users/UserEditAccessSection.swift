import SwiftUI
import Sub2Core

/// 30 §5.3 权限与并发段: role, exclusive groups (granted one by one), public groups behind the restriction switch, and the
/// two steppers. Groups are the session's directory (C-10, X11); only active standard groups count (UserGroupCatalog).
struct UserEditAccessSection: View {
    @Bindable var editor: UserEditorModel
    let catalog: UserGroupCatalog
    let groups: BlockDisplay<[AdminGroup]>
    let onRetryGroups: @MainActor () -> Void
    let onAddGroups: @MainActor () -> Void
    let onOpenGroup: @MainActor (Int) -> Void

    var body: some View {
        roleSection
        exclusiveSection
        publicSection
        limitSection
    }

    // MARK: - 角色

    private var roleSection: some View {
        Section {
            Picker(UserDraftField.role.title, selection: role) {
                ForEach(AdminUserRole.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityIdentifier("user-edit.role")
            .id(UserDraftField.role)
        } header: { Text(UserEditCopy.accessSection) } footer: {
            if let note = UserEditCopy.createRoleFootnote(editor.draft.role) { Text(note).accessibilityIdentifier("user-edit.role.footnote") }
        }
    }
    private var role: Binding<AdminUserRole> {
        Binding(get: { editor.draft.role ?? .user }, set: { editor.draft.role = $0 })
    }

    // MARK: - 专属分组

    private var exclusiveSection: some View {
        Section {
            switch groups {
            case .placeholder, .disabled: loadingRow
            case .failed: retryRow
            case .value:
                if catalog.exclusive.isEmpty {
                    note(UserEditCopy.noExclusiveGroups, detail: catalog.subscriptionNote, identifier: "user-edit.exclusive.empty")
                } else {
                    exclusiveRows
                }
            }
        } header: {
            NumberedSectionHeader(title: UserEditCopy.exclusiveSection, meta: UserEditCopy.groupCount(editor.draft.exclusiveGroupIDs.count))
        } footer: {
            if !catalog.exclusive.isEmpty { Text(UserEditCopy.exclusiveFootnote(catalog: catalog)) }
        }
        .id(UserDraftField.exclusiveGroups)
    }
    @ViewBuilder private var exclusiveRows: some View {
        let chosen = catalog.exclusive.filter { editor.draft.exclusiveGroupIDs.contains($0.id) }
        if chosen.isEmpty { note(UserEditCopy.noExclusiveSelected, detail: nil, identifier: "user-edit.exclusive.none") }
        ForEach(chosen) { group in
            Button { onOpenGroup(group.id) } label: {
                groupLabel(group, subtitle: Self.platformName(group) + " · " + UserEditCopy.exclusiveSection)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("user-edit.exclusive.\(group.id)")
        }
        Button(UserEditCopy.addExclusiveGroup, systemImage: "plus", action: onAddGroups)
            .frame(minHeight: 44)
            .accessibilityIdentifier("user-edit.exclusive.add")
    }

    // MARK: - 公开分组

    private var publicSection: some View {
        Section {
            switch groups {
            case .placeholder, .disabled: loadingRow
            case .failed: retryRow
            case .value: publicRows
            }
        } header: {
            NumberedSectionHeader(title: UserEditCopy.publicSection, meta: publicMeta)
        } footer: { Text(UserEditCopy.publicFootnoteCreate) }
        .id(UserDraftField.publicGroups)
    }
    @ViewBuilder private var publicRows: some View {
        let restricted = editor.draft.restrictPublicGroups
        Toggle(isOn: restrict) {
            VStack(alignment: .leading, spacing: 2) {
                Text(UserEditCopy.restrictPublicTitle)
                Text(UserEditCopy.restrictPublicSubtitle(restricted)).font(.footnote).foregroundStyle(Palette.ink2)
            }
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("user-edit.public.restrict")
        ForEach(catalog.publicGroups) { group in
            let allowed = editor.draft.allowsPublicGroup(group.id)
            HStack(spacing: 12) {
                Button { editor.setPublicGroup(group.id, allowed: !allowed) } label: {
                    Image(systemName: allowed ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(restricted ? (allowed ? Palette.accent : Palette.ink3) : Palette.ink3)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!restricted)
                .accessibilityLabel(Text(group.name))
                .accessibilityValue(Text(allowed ? "已勾选" : "未勾选"))
                .accessibilityIdentifier("user-edit.public.\(group.id)")
                Button { onOpenGroup(group.id) } label: {
                    groupLabel(group, subtitle: UserEditCopy.publicRowSubtitle(platformName: Self.platformName(group), restricted: restricted, allowed: allowed))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("user-edit.public.\(group.id).sheet")
            }
        }
    }
    private var restrict: Binding<Bool> {
        Binding(get: { editor.draft.restrictPublicGroups }, set: { editor.setRestrictPublicGroups($0, catalog: catalog) })
    }
    private var publicMeta: String? {
        guard case .value = groups else { return nil }
        let total = catalog.publicGroups.count
        guard editor.draft.restrictPublicGroups else { return UserEditCopy.groupCount(total) }
        return UserEditCopy.publicAvailable(allowed: catalog.publicGroups.filter { editor.draft.allowsPublicGroup($0.id) }.count, total: total)
    }

    // MARK: - 并发与 RPM

    private var limitSection: some View {
        Section {
            stepper(.concurrency, value: editor.draft.concurrency, step: 1, identifier: "user-edit.concurrency")
            stepper(.rpmLimit, value: editor.draft.rpmLimit, step: UserEditCopy.rpmStep, identifier: "user-edit.rpm")
        } header: { Text(UserEditCopy.limitSection) } footer: { Text(UserEditCopy.limitFootnote) }
    }
    /// 30 §5.3: 0 reads “不限制”; minus stops at 0.
    private func stepper(_ field: UserDraftField, value: Int?, step: Int, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(field.title).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                Text(UserEditCopy.limitText(value)).monospacedDigit().foregroundStyle(value == 0 ? Palette.ink2 : Palette.ink1)
                    .accessibilityIdentifier(identifier + ".value")
                HStack(spacing: 0) {
                    stepButton("减少", systemImage: "minus", identifier: identifier + ".minus") { editor.step(field, by: -step) }
                        .disabled((value ?? 0) <= 0)
                    Divider().frame(height: 20)
                    stepButton("增加", systemImage: "plus", identifier: identifier + ".plus") { editor.step(field, by: step) }
                }
                .background(Palette.sunken, in: Capsule())
            }
            .frame(minHeight: 44)
            if let error = editor.issue(for: field) { UserEditIssueText(message: error, identifier: identifier + ".error") }
        }
        .id(field)
    }
    private func stepButton(_ title: String, systemImage: String, identifier: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.body.weight(.semibold)).frame(width: 46, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(identifier)
    }

    // MARK: - 小部件

    private func groupLabel(_ group: AdminGroup, subtitle: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).foregroundStyle(Palette.ink1)
                Text(subtitle).font(.footnote).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 8)
            Text(UserEditCopy.defaultRate(group)).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    private func note(_ text: String, detail: String?, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).foregroundStyle(Palette.ink2)
            if let detail { Text(detail).font(.footnote).foregroundStyle(Palette.ink3) }
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
    private var loadingRow: some View {
        ProgressView().frame(maxWidth: .infinity, minHeight: 44)
    }
    private var retryRow: some View {
        Button(UserEditCopy.groupsFailedToLoad, action: onRetryGroups)
            .frame(minHeight: 44)
            .accessibilityIdentifier("user-edit.groups.retry")
    }
    static func platformName(_ group: AdminGroup) -> String { AccountNaming.platformName(group.platform, catalog: nil) }
}
