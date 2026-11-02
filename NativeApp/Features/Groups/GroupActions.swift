import SwiftUI
import Sub2Core

// 50 §0.5 on screen: the App's source for GroupActions, the long-press / ⋯ menu items, the list's left swipe and the host of the
// two confirmations (S5D2a-04, -05). The class is NativeApp/Session/GroupActionsCore.swift, so its flows are unit-tested.

/// Writes through the session's client, or under `-ui-testing` the session's GroupFixtures after the same checks APIClient makes
/// (site, identity, session), answering as simple mode does on such a site (GroupFixtures+SimpleMode). The three sends mark the
/// home refresh (GroupWriteMark, X17).
@MainActor final class AppGroupActionSource: GroupActionSource {
    private weak var model: AppModel?

    init(model: AppModel) { self.model = model }

    var groupWriteSession: GroupWriteSession? {
        guard let model, let session = model.sessionContext else { return nil }
        let permissions = GroupPermissions(me: session.site.me, isReadOnlyToken: session.isReadOnlyToken)
        return GroupWriteSession(generation: session.generation, serverID: session.serverID, siteName: model.activeProfile?.name ?? "",
                                 idempotentWrites: session.has(.adminIdempotentWrites), isReadOnlyToken: session.isReadOnlyToken,
                                 readsStats: permissions.showsStats, isSimpleMode: permissions.isSimpleMode)
    }
    func groupWriteIdentity() async throws -> UUID { try await client().userWriteIdentity() }
    func fetchGroupStats(id: Int) async throws -> GroupStats? {
        if model?.isUITesting == true {
            if isSimpleMode, let refusal = GroupFixtures.simpleModeRefusal(.stats) { throw refusal }
            return GroupFixtures.servedStats(groupID: id)
        }
        return try await client().groupStats(id: id)
    }
    func fetchGroup(id: Int) async throws -> AdminGroup {
        guard let store = model?.groupStore else { throw CancellationError() }
        return try await store.fetch(id: id)
    }
    func sendGroupUpdate(_ operation: GroupWriteOperation, request: GroupUpdateRequest) async throws -> WriteOutcome<AdminGroup> {
        try await GroupWriteMark.run(liveModel()) {
            if let fixture = try await fixtureWrite(operation) {
                guard case .update(let id) = operation.kind else { throw CancellationError() }
                let fixtures = fixture.fixtures
                return WriteOutcome(value: try isSimpleMode ? fixtures.simpleModeUpdate(id: id, request, accounts: fixture.accounts, now: fixture.now)
                                    : fixtures.updateGroup(id: id, request, accounts: fixture.accounts, now: fixture.now))
            }
            return try await client().updateGroup(operation)
        }
    }
    func sendGroupDelete(_ operation: GroupWriteOperation) async throws -> WriteOutcome<GroupDeleteResult> {
        try await GroupWriteMark.run(liveModel()) {
            if let fixture = try await fixtureWrite(operation), let accounts = model?.accountDemo {
                guard case .delete(let id) = operation.kind else { throw CancellationError() }
                if isSimpleMode, let refusal = fixture.fixtures.simpleModeDeleteRefusal(id: id, accounts: fixture.accounts, now: fixture.now) {
                    throw refusal
                }
                return WriteOutcome(value: fixture.fixtures.deleteGroup(id: id, accounts: accounts))
            }
            return try await client().deleteGroup(operation)
        }
    }
    func sendGroupDuplicate(_ operation: GroupWriteOperation) async throws -> WriteOutcome<AdminGroup> {
        try await GroupWriteMark.run(liveModel()) {
            if let fixture = try await fixtureWrite(operation), let accounts = model?.accountDemo {
                guard case .duplicate(let id) = operation.kind else { throw CancellationError() }
                if isSimpleMode, let refusal = GroupFixtures.simpleModeRefusal(.duplicate) { throw refusal }
                return WriteOutcome(value: try fixture.fixtures.duplicateGroup(sourceID: id, accounts: accounts, now: fixture.now))
            }
            return try await client().duplicateGroup(operation)
        }
    }

    private var isSimpleMode: Bool { model?.sessionContext?.site.me.isSimpleRunMode == true }
    private func liveModel() throws -> AppModel {
        guard let model else { throw CancellationError() }
        return model
    }
    private func client() throws -> APIClient {
        guard let client = model?.sessionContext?.client else { throw CancellationError() }
        return client
    }
    /// nil on a real site; under `-ui-testing` the session's fixtures once the operation passes APIClient's checks and
    /// `-ui-group-write-timeout`.
    private func fixtureWrite(_ operation: GroupWriteOperation) async throws -> GroupFixtureContext? {
        guard let model, model.isUITesting else { return nil }
        guard let session = model.sessionContext, operation.serverID == session.serverID else { throw APIError.stationMismatch }
        let identity = await session.client.userWriteIdentity()
        guard operation.identity == identity, session.generation == model.sessionGeneration, let context = model.groupStore?.fixtureContext else {
            throw CancellationError()
        }
        try context.fixtures.interruptFirstWrite(operation)
        return context
    }
}

extension GroupStore: GroupActionStore {
    func refreshAfterWrite(directory: Bool) {
        Task { await refreshAll() }
        if directory { Task { await refreshDirectory() } }
    }
}

extension GroupActions {
    /// Writes through AppGroupActionSource into the session's GroupStore; 查看 opens the copy on the current tab.
    convenience init(model: AppModel, router: AppRouter) {
        self.init(source: AppGroupActionSource(model: model), store: { [weak model] in model?.groupStore }, receipts: model.receipts,
                  openGroup: { [weak router] in router?.showGroup(id: $0) })
    }
}

extension GroupAction {
    var systemImage: String {
        switch self {
        case .edit: "square.and.pencil"
        case .addAccounts: "person.crop.circle.badge.plus"
        case .disable: "pause.fill"
        case .enable: "play.fill"
        case .duplicate: "plus.square.on.square"
        case .delete: "trash"
        }
    }
}

/// 50 §1.4 / §2.4: the long press's and the detail ⋯'s items from `permissions.menu(for:)`, 删除分组… red after a divider. Menus
/// may drop identifiers, so UI tests tap the items by title. 添加账号 shows once a page passes `onAddAccounts` (S5-08).
struct GroupActionMenuItems: View {
    let group: AdminGroup
    let actions: GroupActions
    let permissions: GroupPermissions
    let showsDivider: Bool
    let onEdit: @MainActor () -> Void
    let onAddAccounts: (@MainActor () -> Void)?

    init(group: AdminGroup, actions: GroupActions, permissions: GroupPermissions, showsDivider: Bool = true, onEdit: @escaping @MainActor () -> Void,
         onAddAccounts: (@MainActor () -> Void)? = nil) {
        self.group = group; self.actions = actions; self.permissions = permissions; self.showsDivider = showsDivider
        self.onEdit = onEdit; self.onAddAccounts = onAddAccounts
    }

    private var items: [GroupMenuItem] { permissions.menu(for: group).filter { $0.action != .addAccounts || onAddAccounts != nil } }

    var body: some View {
        ForEach(items) { item in
            if item.action.isDestructive && showsDivider { Divider() }
            Button(role: item.action.isDestructive ? .destructive : nil) { perform(item.action) } label: {
                Label(item.action.menuTitle, systemImage: item.action.systemImage)
            }
            .disabled(actions.isRunning(group.id))
            .readOnlyGate(showsCaption: false)
            .accessibilityIdentifier("group.menu.\(item.action.rawValue)")
        }
    }

    private func perform(_ action: GroupAction) {
        let group = group, actions = actions
        switch action {
        case .edit: onEdit()
        case .addAccounts: onAddAccounts?()
        case .disable: Task { await actions.requestDisable(group) }
        case .enable: Task { await actions.enable(group) }
        case .duplicate: Task { await actions.duplicate(group) }
        case .delete: Task { await actions.requestDelete(group) }
        }
    }
}

extension View {
    /// 50 §1.4 left swipe: 停用 / 启用 outermost, then 编辑, from `permissions.trailingSwipe(for:)` — empty for a read-only token
    /// (C-1: swipes are not offered rather than greyed), in simple mode only 编辑.
    func groupActionSwipe(_ group: AdminGroup, actions: GroupActions?, permissions: GroupPermissions,
                          onEdit: @escaping @MainActor () -> Void) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let actions {
                ForEach(Array(permissions.trailingSwipe(for: group).reversed()), id: \.self) { action in
                    Button { GroupSwipe.perform(action, group: group, actions: actions, onEdit: onEdit) } label: {
                        Label(action.swipeTitle, systemImage: action.systemImage)
                    }
                    .tint(GroupSwipe.tint(action))
                    .disabled(actions.isRunning(group.id))
                    .accessibilityIdentifier("group.swipe.\(action.rawValue)")
                }
            }
        }
    }
    /// The disable alert and the delete confirmation of `actions`; without actions nothing shows. `leaving` runs before the
    /// DELETE goes out: the detail pops, the list passes nil and stays.
    func groupActionsHost(_ actions: GroupActions?, leaving: (@MainActor () -> Void)? = nil) -> some View {
        modifier(GroupActionsHost(actions: actions, leaving: leaving))
    }
}

private enum GroupSwipe {
    @MainActor static func perform(_ action: GroupAction, group: AdminGroup, actions: GroupActions, onEdit: @MainActor () -> Void) {
        switch action {
        case .disable: Task { await actions.requestDisable(group) }
        case .enable: Task { await actions.enable(group) }
        default: onEdit()
        }
    }
    static func tint(_ action: GroupAction) -> Color {
        switch action {
        case .disable: Tone.neutral.base
        case .enable: Palette.accent
        default: Palette.ink3
        }
    }
}

private struct GroupActionsHost: ViewModifier {
    let actions: GroupActions?
    let leaving: (@MainActor () -> Void)?
    @State private var deleteRequest: DeleteRequest?

    func body(content: Content) -> some View {
        let prompt = actions?.disablePrompt
        content
            .alert(prompt?.confirmation.title ?? "", isPresented: disableShown, presenting: prompt) { prompt in
                Button(prompt.confirmation.confirmTitle) { confirm(prompt) }
                Button(GroupConfirmation.cancelTitle, role: .cancel) {}
            } message: { prompt in
                Text(prompt.confirmation.message)
            }
            .confirmDelete($deleteRequest)
            .onChange(of: actions?.deletePrompt?.id) { _, _ in present(actions?.deletePrompt) }
    }

    private var disableShown: Binding<Bool> {
        Binding(get: { actions?.disablePrompt != nil }, set: { if !$0 { actions?.disablePrompt = nil } })
    }
    private func confirm(_ prompt: GroupDisablePrompt) {
        guard let actions else { return }
        Task { await actions.confirmDisable(prompt) }
    }
    /// 60 §0.4's sheet: its title and first line from the noun and the site, then the consequences read when it opened.
    private func present(_ prompt: GroupDeletePrompt?) {
        guard let actions, let prompt else { return }
        actions.deletePrompt = nil
        let leaving = self.leaving
        deleteRequest = DeleteRequest(objectNoun: GroupCopy.objectNoun, displayName: prompt.group.name, siteName: prompt.siteName,
                                      consequences: prompt.consequences) { _ = await actions.performDelete(prompt, leaving: leaving) }
    }
}

// MARK: - 首页刷新接线（S5-13）

@MainActor enum GroupWriteMark {
    /// 10 §1.4, X17: a group write that ran, or may have run (AccountWriteMark's rule), in a session that is still current makes the
    /// home page read past the server cache the next time it shows. `generation` defaults to the current session's.
    static func run<T: Sendable>(_ model: AppModel, generation: UUID? = nil, _ operation: @MainActor () async throws -> T) async throws -> T {
        try await AccountWriteMark.run(generation: generation ?? model.sessionGeneration, isCurrent: { model.sessionGeneration == $0 },
                                       mark: { model.liveOps?.noteExternalWrite() }, operation)
    }
}
