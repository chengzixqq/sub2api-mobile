import SwiftUI
import Sub2Core

// 50 §2.4 on screen (S5-08): a group detail's member actions — the status actions through S2-06's AccountActions, 移出 through
// GroupMemberWriter (NativeApp/Session, unit-tested) — the member row's swipe and long press, their two confirmations, and the
// App's source for the writer.

/// 移出's confirmation for the last available account of an active group.
struct GroupMemberRemoval: Identifiable {
    let account: UpstreamAccount
    let group: AdminGroup
    let wasAvailable: Bool
    let confirmation: GroupConfirmation
    var id: Int { account.id }
}

/// One group detail's member actions; made with the page, so a new session makes new ones.
@MainActor @Observable
final class GroupMemberActions {
    let accounts: AccountActions
    let writer: GroupMemberWriter
    /// accountRecoverDialog's account.
    var recovering: UpstreamAccount?
    var removal: GroupMemberRemoval?
    @ObservationIgnored private weak var detail: GroupDetailModel?
    @ObservationIgnored private weak var model: AppModel?

    init(model: AppModel, router: AppRouter, detail: GroupDetailModel) {
        let groupID = detail.groupID
        // 2.4: after a status action the members, the group's counts and capacity are read again.
        let refresh: @MainActor () -> Void = { [weak model] in model?.memberWriteFinished(GroupMemberChange(groupID: groupID, counts: nil)) }
        accounts = AccountActions(model: model, onChange: { _ in refresh() }, onMissing: { _ in refresh() })
        writer = GroupMemberWriter(model: model, router: router)
        self.detail = detail; self.model = model
    }

    func isBusy(_ accountID: Int) -> Bool { accounts.isRunning(accountID) || writer.busyAccounts.contains(accountID) }
    /// 恢复状态 asks first (AccountActionCopy.recoverDialog); 启用 / 停止调度 go at once with 撤销.
    func perform(_ action: GroupMemberStatusAction, on account: UpstreamAccount) {
        switch action {
        case .recover: recovering = account
        case .enableScheduling: Task { await accounts.setSchedulable(account, enabled: true) }
        case .stopScheduling: Task { await accounts.setSchedulable(account, enabled: false) }
        }
    }
    /// The last available account of an active group asks first; any other goes at once.
    func remove(_ account: UpstreamAccount, from group: AdminGroup, now: Date) {
        let wasAvailable = GroupMemberPresentation.isAvailable(account, now: now)
        guard GroupMemberPresentation.removalNeedsConfirmation(account, in: group, now: now) else {
            Task { await execute(account, from: group, wasAvailable: wasAvailable) }
            return
        }
        let confirmation = GroupMemberPresentation.removalConfirmation(accountName: account.name, groupName: group.name,
                                                                       siteName: model?.activeProfile?.name ?? "")
        removal = GroupMemberRemoval(account: account, group: group, wasAvailable: wasAvailable, confirmation: confirmation)
    }
    func confirmRemoval(_ removal: GroupMemberRemoval) {
        self.removal = nil
        Task { await execute(removal.account, from: removal.group, wasAvailable: removal.wasAvailable) }
    }

    /// The row leaves at once and comes back when the removal did not happen.
    private func execute(_ account: UpstreamAccount, from group: AdminGroup, wasAvailable: Bool) async {
        guard !isBusy(account.id) else { return }
        detail?.beginRemoval(account.id)
        let sent = await writer.remove(account, from: GroupMemberTarget(group), wasAvailable: wasAvailable)
        detail?.endRemoval(account.id, left: Self.left(account.id, after: sent))
    }
    private static func left(_ accountID: Int, after sent: GroupMemberSendResult) -> Bool {
        guard case .result(let result, _) = sent else { return false }
        return result.item(for: accountID, action: .remove)?.isSuccess == true
    }
}

extension GroupMemberWriter {
    /// Writes through AppModel; 查看 opens the per-item results on the current tab (S5D2a-08).
    convenience init(model: AppModel, router: AppRouter) {
        self.init(source: model, receipts: model.receipts, openResults: { [weak router] in router?.showGroupBatch($0) })
    }
}

/// The writer's source: the session's client, or under `-ui-testing` the session's GroupFixtures on AccountDemoStore. S5-13 wraps
/// the two sends for the home refresh (X17, S5D2a-07); they are not in `recordingAccountWrite`.
extension AppModel: GroupMemberWriteSource {
    var groupMemberWriteSession: GroupMemberWriteSession? {
        guard let session = sessionContext else { return nil }
        return GroupMemberWriteSession(generation: session.generation,
                                       usesBatch: session.has(.groupsMemberBatch) && groupStore?.memberBatchUnsupported != true,
                                       allowsLegacy: !session.site.me.isSimpleRunMode, isReadOnlyToken: session.isReadOnlyToken)
    }
    func sendGroupMemberBatch(groupID: Int, _ request: GroupMemberBatchRequest, generation: UUID) async throws -> GroupMemberBatchResult {
        if isUITesting { return try memberFixture(groupID: groupID, request, generation: generation, legacy: false) }
        return try await accountWriteClient(generation).groupMemberBatch(groupID: groupID, request)
    }
    func sendGroupMembersLegacy(groupID: Int, _ request: GroupMemberBatchRequest, generation: UUID) async throws -> GroupMemberBatchResult {
        if isUITesting { return try memberFixture(groupID: groupID, request, generation: generation, legacy: true) }
        let client = try accountWriteClient(generation)
        let executor = GroupMembersLegacyExecutor(client: client, sendsIdempotencyKey: sessionContext?.has(.adminIdempotentWrites) == true)
        return try await executor.run(groupID: groupID, request)
    }
    func noteMemberBatchUnsupported() { groupStore?.noteMemberBatchUnsupported() }
    /// The list and the detail read the group again; the account tab shows the new group names when it next appears.
    func memberWriteFinished(_ change: GroupMemberChange) {
        groupStore?.noteMemberChange(change)
        accountListSignal.bump()
    }
    /// The group leaves the list and the group directory; its detail reads it again and shows 这个分组已删除.
    func groupWentAway(id: Int) {
        groupStore?.remove(id: id)
        groupStore?.noteMemberChange(GroupMemberChange(groupID: id, counts: nil))
    }

    private func memberFixture(groupID: Int, _ request: GroupMemberBatchRequest, generation: UUID, legacy: Bool) throws -> GroupMemberBatchResult {
        guard generation == sessionGeneration, let fixtures = groupStore?.fixtures else { throw CancellationError() }
        return try fixtures.memberBatch(groupID: groupID, request, store: accountDemo, now: accountFixtureNow(), legacy: legacy)
    }
}

extension View {
    /// 50 §2.4 the member row: 移出 (critical) outermost on the trailing swipe, the status action beside it; both in the long press
    /// too, which is how VoiceOver reaches them. A read-only token gets no swipe (C-1) and greyed menu items; without the right to
    /// change members only the status action is left.
    func groupMemberRowActions(_ account: UpstreamAccount, group: AdminGroup, actions: GroupMemberActions?, membersEntry: GroupPermissions.Entry,
                               isReadOnly: Bool, now: Date) -> some View {
        modifier(GroupMemberRowActions(account: account, group: group, actions: actions, membersEntry: membersEntry, isReadOnly: isReadOnly, now: now))
    }
    /// The recover confirmation (AccountActions') and 移出's.
    func groupMemberPrompts(_ actions: GroupMemberActions?) -> some View { modifier(GroupMemberPrompts(actions: actions)) }
}

private struct GroupMemberRowActions: ViewModifier {
    let account: UpstreamAccount
    let group: AdminGroup
    let actions: GroupMemberActions?
    let membersEntry: GroupPermissions.Entry
    let isReadOnly: Bool
    let now: Date

    func body(content: Content) -> some View {
        let status = GroupMemberPresentation.statusAction(for: account, now: now)
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let actions, !isReadOnly {
                    if membersEntry == .enabled { removeButton(actions) }
                    if let status { statusButton(status, actions: actions) }
                }
            }
            .contextMenu {
                if let actions {
                    if let status { statusButton(status, actions: actions).readOnlyGate(showsCaption: false) }
                    if membersEntry.isShown { removeButton(actions).readOnlyGate(showsCaption: false) }
                }
            }
    }

    private func removeButton(_ actions: GroupMemberActions) -> some View {
        Button(role: .destructive) { actions.remove(account, from: group, now: now) } label: {
            Label(GroupMemberPresentation.removeTitle, systemImage: "xmark")
        }
        .tint(Tone.critical.base)
        .disabled(actions.isBusy(account.id))
        .accessibilityIdentifier("group.member.\(account.id).remove")
    }
    private func statusButton(_ status: GroupMemberStatusAction, actions: GroupMemberActions) -> some View {
        Button { actions.perform(status, on: account) } label: { Label(status.title, systemImage: status.systemImage) }
            .tint(status == .stopScheduling ? Tone.neutral.base : Palette.accent)
            .disabled(actions.isBusy(account.id))
            .accessibilityIdentifier("group.member.\(account.id).status")
    }
}

private struct GroupMemberPrompts: ViewModifier {
    let actions: GroupMemberActions?

    @ViewBuilder func body(content: Content) -> some View {
        if let actions {
            let removal = actions.removal
            content
                .accountRecoverDialog(Binding(get: { actions.recovering }, set: { actions.recovering = $0 }), actions: actions.accounts)
                .confirmationDialog(removal?.confirmation.title ?? "", isPresented: Binding(get: { actions.removal != nil }, set: { if !$0 { actions.removal = nil } }),
                                    titleVisibility: .visible, presenting: removal) { removal in
                    Button(removal.confirmation.confirmTitle, role: .destructive) { actions.confirmRemoval(removal) }
                        .accessibilityIdentifier("group.member.remove.confirm")
                    Button(GroupConfirmation.cancelTitle, role: .cancel) {}
                } message: { removal in
                    Text(removal.confirmation.message)
                }
        } else {
            content
        }
    }
}
