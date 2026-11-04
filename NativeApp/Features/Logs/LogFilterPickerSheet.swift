import Foundation
import SwiftUI
import Sub2Core

/// 40 §6.3 “+ 筛选” at the end of the chip row: opens 按对象筛选.
struct LogFilterAddChip: View {
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) { self.action = action }

    var body: some View {
        Button(action: action) { LogChipLabel(LogFilterPicker.addChipTitle, isOn: false, leadingSymbol: "plus") }
            .buttonStyle(.plain)
            .accessibilityLabel(LogFilterPicker.title)
            .accessibilityIdentifier("logs.chip.add")
    }
}

extension View {
    /// 40 §6.1: the bar's filter button (`logs.picker.open`) and the 按对象筛选 sheet, which ticks the objects in `conditions`;
    /// `onPick` gets the row chosen.
    func logFilterPicker(isPresented: Binding<Bool>, conditions: LogConditions,
                         onPick: @escaping @MainActor (LogFilterPick) -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPresented.wrappedValue = true } label: {
                    Label(LogFilterPicker.title, systemImage: "line.3.horizontal.decrease")
                }
                .accessibilityIdentifier("logs.picker.open")
            }
        }
        .sheet(isPresented: isPresented) { LogFilterPickerSheet(conditions: conditions, onPick: onPick) }
    }
}

/// 40 §6.4 按对象筛选: a search field over three groups — accounts (state glyph, name, #id, platform · groups), groups (name,
/// platform, 停用) and, once there is a keyword, users (initial, email, 已删除). Each group loads and fails on its own; a group
/// read with no row is hidden. The object a condition already holds ends in a tick. A row sets the condition of its kind and
/// closes the sheet.
struct LogFilterPickerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: LogFilterPickerModel?
    @State private var catalog = MetaCatalog.builtin
    private let conditions: LogConditions
    private let onPick: @MainActor (LogFilterPick) -> Void

    init(conditions: LogConditions, onPick: @escaping @MainActor (LogFilterPick) -> Void) {
        self.conditions = conditions; self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(LogFilterPicker.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("sheet.close") }
                }
        }
        .presentationDetents([.large])
        .task { await open() }
        .onDisappear { model?.stop() }
    }

    @ViewBuilder private var content: some View {
        if let model {
            let directory = model.groups
            LogFilterPickerList(model: model, catalog: catalog, conditions: conditions, now: app.serverNow(),
                                groupName: { directory?.name(for: $0) }) { pick in
                onPick(pick)
                dismiss()
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func open() async {
        let app = app, model = self.model ?? LogFilterPickerModel(app: app)
        self.model = model
        async let loaded = app.metaCatalog()
        await model.start()
        catalog = await loaded
    }
}

private struct LogFilterPickerList: View {
    let model: LogFilterPickerModel
    let catalog: MetaCatalog
    let conditions: LogConditions
    let now: Date
    let groupName: (Int) -> String?
    let choose: @MainActor (LogFilterPick) -> Void

    var body: some View {
        List {
            accountSection
            groupSection
            if model.showsUsers { userSection }
            if model.hasNoMatches {
                Text(LogFilterPicker.noMatches).font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("logs.picker.empty")
            }
        }
        .searchable(text: Binding(get: { model.searchText }, set: { model.searchChanged($0) }),
                    placement: .navigationBarDrawer(displayMode: .always), prompt: LogFilterPicker.searchPrompt)
        .onSubmit(of: .search) { Task { await model.applySearch() } }
    }

    // MARK: Groups

    @ViewBuilder private var accountSection: some View {
        let rows = model.accountRows
        if !rows.isEmpty || model.accounts.isLoading || model.accounts.error != nil {
            Section(LogFilterPicker.accountsTitle) {
                ForEach(rows) { accountRow($0) }
                if rows.isEmpty, model.accounts.isLoading { loadingRow("logs.picker.accounts.loading") }
                if model.accounts.error != nil {
                    BlockFailureRow(model.accounts, id: "logs.picker.accounts") { Task { await model.retryAccounts() } }
                }
            }
        }
    }
    @ViewBuilder private var groupSection: some View {
        if let directory = model.groups {
            let rows = model.groupRows
            if directory.state.value != nil {
                if !rows.isEmpty { Section(LogFilterPicker.groupsTitle) { ForEach(rows) { groupRow($0) } } }
            } else if directory.state.failureReason != nil {
                Section(LogFilterPicker.groupsTitle) {
                    BlockFailureRow(state: directory.state, refresh: directory.refreshState, id: "logs.picker.groups") {
                        Task { await model.retryGroups() }
                    }
                }
            } else {
                Section(LogFilterPicker.groupsTitle) { loadingRow("logs.picker.groups.loading") }
            }
        }
    }
    @ViewBuilder private var userSection: some View {
        let rows = model.userRows
        if !rows.isEmpty || model.users.isLoading || model.users.error != nil {
            Section(LogFilterPicker.usersTitle) {
                ForEach(rows) { userRow($0) }
                if rows.isEmpty, model.users.isLoading { loadingRow("logs.picker.users.loading") }
                if model.users.error != nil {
                    BlockFailureRow(model.users, id: "logs.picker.users") { Task { await model.retryUsers() } }
                }
            }
        }
    }
    private func loadingRow(_ id: String) -> some View {
        ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier(id)
    }

    // MARK: Rows

    private func accountRow(_ account: UpstreamAccount) -> some View {
        let display = AccountDisplayState(account, now: now)
        let meta = LogFilterPicker.accountMeta(account, catalog: catalog, directory: groupName)
        let trailing = LogFilterPicker.accountTrailing(account)
        return pickButton(LogFilterPick(account: account), id: "logs.picker.account.\(account.id)",
                          label: [account.name, display.label, meta, trailing].joined(separator: "，")) {
            HStack(spacing: 10) {
                AccountStateGlyph(state: display.state)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(account.name).font(.body).foregroundStyle(Palette.ink1).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(trailing).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink3)
                    }
                    Text(meta).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
                }
            }
        }
    }
    private func groupRow(_ group: AdminGroup) -> some View {
        let platform = LogFilterPicker.groupPlatform(group, catalog: catalog)
        let inactive = LogFilterPicker.isInactive(group)
        let label = [group.name, platform] + (inactive ? [LogFilterPicker.inactiveGroup] : [])
        return pickButton(LogFilterPick(group: group), id: "logs.picker.group.\(group.id)", label: label.joined(separator: "，")) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink3)
                    .frame(width: 22).accessibilityHidden(true)
                Text(group.name).font(.body).foregroundStyle(Palette.ink1).lineLimit(1)
                if inactive { LogFilterPickerTag(text: LogFilterPicker.inactiveGroup) }
                Spacer(minLength: 8)
                Text(platform).font(.subheadline).foregroundStyle(Palette.ink3).lineLimit(1)
            }
        }
    }
    private func userRow(_ user: UsageUserMatch) -> some View {
        let email = user.email.isEmpty ? DisplayFormat.missing : user.email
        return pickButton(LogFilterPick(user: user), id: "logs.picker.user.\(user.id)",
                          label: user.deleted ? email + "，" + LogFilterPicker.deletedUser : email) {
            HStack(spacing: 10) {
                UserInitialAvatar(initial: UserPresentation.initial(user.email), size: 32)
                Text(email).font(.body).foregroundStyle(Palette.ink1).lineLimit(1).truncationMode(.middle)
                if user.deleted { LogFilterPickerTag(text: LogFilterPicker.deletedUser) }
                Spacer(minLength: 0)
            }
        }
    }
    /// The row of the object its kind's condition already holds ends in a tick and reads as selected.
    private func pickButton<Content: View>(_ pick: LogFilterPick, id: String, label: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        let isOn = pick.isSameObject(in: conditions)
        return Button { choose(pick) } label: {
            HStack(spacing: 10) {
                content()
                if isOn {
                    Image(systemName: "checkmark").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// 已删除 after a user, 停用 after a group.
private struct LogFilterPickerTag: View {
    let text: String

    var body: some View {
        Text(text).font(.caption).foregroundStyle(Palette.ink2)
            .padding(.horizontal, 6).padding(.vertical, 2).background(Palette.sunken, in: Capsule())
    }
}

extension LogFilterPickerModel {
    /// The session open when the sheet appears; its replies are dropped once another one starts.
    convenience init(app: AppModel) {
        let generation = app.sessionGeneration
        self.init(source: .app(app), groups: app.groupDirectory, isCurrent: { [weak app] in app?.sessionGeneration == generation })
    }
}

extension LogFilterPickerSource {
    /// R19's account read (AccountDemoStore under `-ui-testing`) and `usage/search-users` (LogFixtures under `-ui-testing`).
    @MainActor static func app(_ app: AppModel) -> LogFilterPickerSource {
        let isUITesting = app.isUITesting, arguments = ProcessInfo.processInfo.arguments
        let client = Result { try app.requireClient() }
        return LogFilterPickerSource(accounts: { [weak app] search in
            guard let app else { throw CancellationError() }
            return try await app.managedAccounts(page: 1, query: LogFilterPicker.accountQuery(search: search)).items
        }, users: { keyword in
            if isUITesting { return try await LogFixtures.pickerUsers(keyword, arguments: arguments) }
            return try await client.get().searchUsageUsers(keyword)
        })
    }
}
