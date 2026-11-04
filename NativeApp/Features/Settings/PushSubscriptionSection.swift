import SwiftUI
import Sub2Core

/// 60 §7.3 推送内容, shared by this phone's target on the push page and every other target's page. Each change is handed
/// over as the whole new subscription at once (7.4); the platform and group scopes are chosen in a sheet and handed over
/// on 完成, so ticking several sends one PUT. Nothing greys while a save is out: the owner merges the edits.
struct PushSubscriptionSection: View {
    let subscription: PushSubscription
    let timezone: String?
    let catalog: MetaCatalog
    let groups: GroupDirectory?
    let isSaving: Bool
    let onChange: (PushSubscription) -> Void
    @State private var picker: PushScopePicker?

    var body: some View {
        Section {
            ForEach(PushEvent.allCases, id: \.self) { event in
                Toggle(PushPresentation.eventTitle(event), isOn: Binding(get: { subscription.events.contains(event) }, set: { isOn in
                    onChange(PushSubscriptionEdit.setting(event, on: isOn, in: subscription))
                }))
                .tint(Palette.accentFill)
                .frame(minHeight: 44)
                .accessibilityIdentifier("push.subscription.event.\(event.rawValue)")
            }
            if subscription.isPaused {
                Text(PushPresentation.pausedNote).font(.footnote).foregroundStyle(Tone.caution.ink)
                    .accessibilityIdentifier("push.subscription.paused")
            }
            severityMenu
            scopeRow(title: PushPresentation.platformScopeTitle, note: nil,
                     value: PushPresentation.platformScope(subscription.platforms) { AccountNaming.platformName($0, catalog: catalog) },
                     id: "push.subscription.platforms") { picker = .platforms }
            scopeRow(title: PushPresentation.groupScopeTitle, note: PushPresentation.groupScopeNote,
                     value: PushPresentation.groupScope(subscription.groupIDs) { groups?.name(for: $0) },
                     id: "push.subscription.groups") { picker = .groups }
                .sheet(item: $picker) { pickerSheet($0) }
            quietRows
        } header: {
            NumberedSectionHeader(title: PushPresentation.contentSectionTitle) {
                if isSaving { ProgressView().controlSize(.mini).accessibilityHidden(true) }
            }
        } footer: {
            Text(PushPresentation.footer).accessibilityIdentifier("push.subscription.footer")
        }
    }

    private var severityMenu: some View {
        Menu {
            Picker(PushPresentation.severityRowTitle, selection: Binding(get: { subscription.minSeverity }, set: { severity in
                onChange(PushSubscriptionEdit.setting(minSeverity: severity, in: subscription))
            })) {
                ForEach(PushSeverity.allCases, id: \.self) { Text(PushPresentation.severitySummary($0)).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 8) {
                Text(PushPresentation.severityRowTitle).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                Text(PushPresentation.severitySummary(subscription.minSeverity)).foregroundStyle(Palette.ink2)
                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(Palette.ink3).accessibilityHidden(true)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(PushPresentation.severityRowTitle)
        .accessibilityValue(PushPresentation.severitySummary(subscription.minSeverity))
        .accessibilityIdentifier("push.subscription.severity")
    }

    private func scopeRow(title: String, note: String?, value: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Palette.ink1)
                    if let note { Text(note).font(.footnote).foregroundStyle(Palette.ink2) }
                }
                Spacer(minLength: 8)
                Text(value).foregroundStyle(Palette.ink2).lineLimit(1)
                SettingsChevron()
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// The window is a wall clock in the target's zone; the pickers never shift it by the device's zone.
    @ViewBuilder private var quietRows: some View {
        Toggle(isOn: Binding(get: { subscription.quietHours != nil }, set: { isOn in
            onChange(PushSubscriptionEdit.setting(quietHours: isOn, in: subscription))
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PushPresentation.quietHoursTitle).foregroundStyle(Palette.ink1)
                Text(PushPresentation.quietHoursNote(timezone: timezone)).font(.footnote).foregroundStyle(Palette.ink2)
            }
        }
        .tint(Palette.accentFill)
        .frame(minHeight: 44)
        .accessibilityIdentifier("push.subscription.quiet")
        if let quiet = subscription.quietHours {
            quietPicker(PushPresentation.quietStartTitle, minute: quiet.startMinute, id: "push.subscription.quiet.start") {
                PushSubscriptionEdit.setting(quietStart: $0, in: subscription)
            }
            quietPicker(PushPresentation.quietEndTitle, minute: quiet.endMinute, id: "push.subscription.quiet.end") {
                PushSubscriptionEdit.setting(quietEnd: $0, in: subscription)
            }
        }
    }

    private func quietPicker(_ title: String, minute: Int, id: String, edit: @escaping (Int) -> PushSubscription) -> some View {
        DatePicker(title, selection: Binding(get: { PushQuietClock.date(minuteOfDay: minute) }, set: { date in
            let next = PushQuietClock.minuteOfDay(date)
            if next != minute { onChange(edit(next)) }
        }), displayedComponents: .hourAndMinute)
        .environment(\.timeZone, PushQuietClock.timeZone)
        .frame(minHeight: 44)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private func pickerSheet(_ picker: PushScopePicker) -> some View {
        switch picker {
        case .platforms:
            PushScopePickerSheet(title: PushPresentation.platformScopeTitle, allTitle: PushPresentation.allPlatformsOption,
                                 options: PushScopeOptions.platforms(catalog: catalog, selected: subscription.platforms),
                                 initial: subscription.platforms, limit: PushSubscription.maxPlatforms, limitNote: PushPresentation.platformLimitNote,
                                 loadFailed: false, onRetry: {}) { onChange(PushSubscriptionEdit.setting(platforms: $0, in: subscription)) }
        case .groups:
            PushScopePickerSheet(title: PushPresentation.groupScopeTitle, allTitle: PushPresentation.allGroupsOption,
                                 options: PushScopeOptions.groups(groups?.groups ?? [], selected: subscription.groupIDs),
                                 initial: subscription.groupIDs, limit: PushSubscription.maxGroupIDs, limitNote: PushPresentation.groupLimitNote,
                                 loadFailed: groups?.state.failureReason != nil && groups?.state.value == nil,
                                 onRetry: { Task { await groups?.refresh() } }) { onChange(PushSubscriptionEdit.setting(groupIDs: $0, in: subscription)) }
        }
    }
}

private enum PushScopePicker: String, Identifiable {
    case platforms, groups
    var id: String { rawValue }
}

/// “全部” (an empty list) or a ticked set within the backend's limit; 完成 hands over a changed choice once, 取消 or a swipe
/// keeps the old one.
private struct PushScopePickerSheet<ID: Hashable & Sendable>: View {
    let title: String
    let allTitle: String
    let options: [PushScopeOption<ID>]
    let initial: [ID]
    let limit: Int
    let limitNote: String
    let loadFailed: Bool
    let onRetry: () -> Void
    let onDone: ([ID]) -> Void
    @State private var selection: [ID]
    @State private var reachedLimit = false
    @Environment(\.dismiss) private var dismiss

    init(title: String, allTitle: String, options: [PushScopeOption<ID>], initial: [ID], limit: Int, limitNote: String, loadFailed: Bool,
         onRetry: @escaping () -> Void, onDone: @escaping ([ID]) -> Void) {
        self.title = title; self.allTitle = allTitle; self.options = options; self.initial = initial; self.limit = limit
        self.limitNote = limitNote; self.loadFailed = loadFailed; self.onRetry = onRetry; self.onDone = onDone
        _selection = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    choice(allTitle, isSelected: selection.isEmpty, id: "push.scope.all") { selection = []; reachedLimit = false }
                    if loadFailed { PushRetryRow(identifier: "push.scope.retry", action: onRetry) }
                    ForEach(options) { option in
                        choice(option.title, isSelected: selection.contains(option.id), id: "push.scope.option.\(option.id)") { toggle(option.id) }
                    }
                } footer: {
                    if reachedLimit { Text(limitNote).accessibilityIdentifier("push.scope.limit") }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("push.scope.sheet")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("push.scope.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if selection != initial { onDone(selection) }
                        dismiss()
                    }
                    .accessibilityIdentifier("push.scope.done")
                }
            }
        }
    }

    private func toggle(_ id: ID) {
        guard let next = PushScopeOptions.toggling(id, in: selection, limit: limit) else { reachedLimit = true; return }
        selection = next
        reachedLimit = false
    }

    private func choice(_ title: String, isSelected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                if isSelected { Image(systemName: "checkmark").foregroundStyle(Palette.accent).accessibilityHidden(true) }
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}
