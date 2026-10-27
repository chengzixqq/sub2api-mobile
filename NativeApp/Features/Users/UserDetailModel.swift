import Foundation
import Observation
import Sub2Core

/// 30 §2: one user's page. The profile, today's and this month's spend, the keys and the latest five records load together and
/// fail on their own (30 §2.5); every profile read is written back to the session's list (30 §1.6). Requests go through
/// AppModel's wrappers (fixtures included); a reply for an older session is dropped.
@MainActor @Observable
final class UserDetailModel {
    let userID: Int
    let profile = LoadState<AdminUser>()
    let today = LoadState<Decimal>()
    let month = LoadState<UserUsageSummary>()
    let keys = LoadState<[AdminAPIKey]>()
    let ledger = LoadState<BalanceHistoryPage>()
    /// 404 USER_NOT_FOUND: the page says so and the row has left the list.
    private(set) var isMissing = false
    private(set) var isWritingStatus = false
    /// The delete went through or found the user gone; the page pops once the confirmation has closed.
    private(set) var didDelete = false

    @ObservationIgnored private weak var app: AppModel?
    private let generation: UUID

    init(app: AppModel, userID: Int) {
        self.app = app
        self.userID = userID
        generation = app.sessionGeneration
    }

    var user: AdminUser? { profile.value }
    var isReadOnlyToken: Bool { app?.siteSession?.isReadOnlyToken ?? false }
    var isSelf: Bool { user.map { UserDetailPresentation.isSelf($0, meID: app?.currentAdminUserID) } ?? false }
    /// Until settings/public is read only the user's own threshold counts.
    var isLowBalance: Bool {
        guard let user else { return false }
        return UserPresentation.isLowBalance(user: user, global: app?.userList?.lowBalanceGlobal ?? .off)
    }
    /// A read-only token never asks for it (R14), so it reads “—” without a retry.
    var todayCost: Decimal? { isReadOnlyToken ? nil : today.value }
    var monthCost: Decimal? { month.value?.totalActualCost }
    var keySummary: UserKeySummary? {
        guard let app, let shown = keys.value else { return nil }
        let names = Dictionary((app.groupDirectory?.groups ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return UserDetailPresentation.keySummary(shown, groupNames: names, now: serverNow, timeZone: serverTimeZone, simpleMode: isSimpleMode,
                                                 canManageKeys: app.siteSession?.me.isLegacyServer != true)
    }
    /// The keys a disable stops, counted as the section meta counts them; nil while the keys are unknown.
    var activeKeyCount: Int? {
        let now = serverNow, simple = isSimpleMode
        return keys.value?.filter { $0.status(now: now).countsAsActive(simpleMode: simple) }.count
    }
    var serverTimeZone: TimeZone { app?.siteSession?.serverTimeZone.timeZone ?? .current }
    var serverNow: Date { app?.sessionContext?.client.serverClock.now() ?? Date() }
    /// 30 §2.6: the next profile and today read, stretched by failures and held during a 429 wait.
    func nextLiveDelay() -> TimeInterval { profile.nextDelay(base: UserDetailPresentation.liveRefreshInterval) }

    // MARK: - Reads

    /// Entering, pulling and returning to the foreground; the group names and the global low-balance threshold come along.
    func loadAll() async {
        async let profileRead: Void = reloadProfile()
        async let todayRead: Void = reloadToday()
        async let monthRead: Void = reloadMonth()
        async let keysRead: Void = reloadKeys()
        async let ledgerRead: Void = reloadLedger()
        async let support: Void = loadSupport()
        _ = await (profileRead, todayRead, monthRead, keysRead, ledgerRead, support)
    }
    /// Every 60 seconds while shown: what billing and other administrators change. A status write in flight keeps the profile.
    func refreshLive() async {
        guard !isWritingStatus else { await reloadToday(); return }
        async let profileRead: Void = reloadProfile()
        async let todayRead: Void = reloadToday()
        _ = await (profileRead, todayRead)
    }
    /// Pushing a page over this one stops the reads still out, and a first read goes back to nothing; on reappearing those
    /// blocks are read again. Back from the editor the profile, the keys and the records are read whatever their state (30 §2.6);
    /// other loaded and failed blocks wait for a pull, a retry or the timer.
    func resumeIfInterrupted(afterEditor: Bool = false) async {
        let blocks: [(Bool, @MainActor @Sendable () async -> Void)] = [
            (afterEditor || isIdle(profile.state), { [weak self] in await self?.reloadProfile() }),
            (isIdle(today.state) && !isReadOnlyToken, { [weak self] in await self?.reloadToday() }),
            (isIdle(month.state), { [weak self] in await self?.reloadMonth() }),
            (afterEditor || isIdle(keys.state), { [weak self] in await self?.reloadKeys() }),
            (afterEditor || isIdle(ledger.state), { [weak self] in await self?.reloadLedger() }),
        ]
        await withTaskGroup(of: Void.self) { group in
            for (due, read) in blocks where due { group.addTask { await read() } }
        }
    }
    /// The old editor sheet closed (until S3-11 pushes `.userEdit`).
    func reloadAfterEdit() async { await resumeIfInterrupted(afterEditor: true) }
    /// `userChanges.revision(userID:)` moved: a balance write, a compensation or a save elsewhere (C-12).
    func reloadAfterChange() async {
        async let profileRead: Void = reloadProfile()
        async let todayRead: Void = reloadToday()
        async let keysRead: Void = reloadKeys()
        async let ledgerRead: Void = reloadLedger()
        _ = await (profileRead, todayRead, keysRead, ledgerRead)
    }

    func reloadProfile() async {
        guard let app else { return }
        let id = userID
        await profile.load(isCurrent: { self.isLive }) { try await app.user(id: id) }
        settleProfile()
    }
    func reloadToday() async {
        guard let app, !isReadOnlyToken else { return }
        let id = userID
        await today.load(isCurrent: { self.isLive }) { try await app.userTodayCost(id: id) }
    }
    func reloadMonth() async {
        guard let app else { return }
        let id = userID
        await month.load(isCurrent: { self.isLive }) { try await app.userMonthUsage(id: id) }
    }
    func reloadKeys() async {
        guard let app else { return }
        let id = userID
        await keys.load(isCurrent: { self.isLive }) { try await app.userAPIKeys(userID: id) }
    }
    func reloadLedger() async {
        guard let app else { return }
        let id = userID
        await ledger.load(isCurrent: { self.isLive }) {
            try await app.balanceHistory(userID: id, page: 1, pageSize: UserDetailPresentation.ledgerPeekSize)
        }
    }

    // MARK: - Writes

    /// 30 §2.4: at once, no confirmation; the receipt's 撤销 sends the opposite status.
    func setStatus(enable: Bool) async {
        guard let app, isLive, let user, !isWritingStatus else { return }
        isWritingStatus = true
        defer { isWritingStatus = false }
        await UserStatusAction.run(app: app, userID: userID, displayName: user.displayName, enable: enable, activeKeyCount: activeKeyCount,
                                   offersUndo: true, apply: { [weak self] in self?.apply($0) },
                                   readBack: { [weak self] in await self?.reloadProfile() })
    }
    /// The generic confirmation (C-2): the whole display name, or the email when the username is blank; 30's own site line.
    func deleteRequest(siteName: String) -> DeleteRequest? {
        guard let user else { return nil }
        return DeleteRequest(objectNoun: "用户", displayName: user.displayName, siteName: siteName,
                             siteLine: UserDetailPresentation.deleteSiteLine(siteName: siteName),
                             consequences: UserDetailPresentation.deleteConsequences(keyCount: keys.value?.count),
                             expectedText: UserDetailPresentation.deleteExpectedText(user)) { [weak self] in await self?.delete() }
    }
    /// A bare DELETE; already gone counts as deleted. The row leaves the list and the receipt shows before the page pops.
    func delete() async {
        guard let app, isLive, let user else { return }
        do {
            _ = try await app.deleteUser(id: userID)
            guard isLive else { return }
            didDelete = true
            app.userList?.remove(id: userID)
            app.receipts.show(Receipt(text: DeleteConfirmationCopy.deletedReceipt(objectNoun: "用户", displayName: user.displayName), systemImage: "trash"))
        } catch {
            guard isLive, !(error is CancellationError) else { return }
            let failure = UserDetailPresentation.statusFailure(error)
            app.receipts.show(Receipt(text: failure.text, systemImage: "exclamationmark.triangle", tone: .critical))
            if failure.readsBack { await reloadProfile() }
        }
    }

    // MARK: - Internals

    private var isLive: Bool { app?.sessionGeneration == generation }
    private var isSimpleMode: Bool { app?.siteSession?.me.isSimpleRunMode ?? false }
    private func isIdle<Value: Sendable>(_ state: BlockState<Value>) -> Bool {
        if case .idle = state { true } else { false }
    }

    private func loadSupport() async {
        async let groups: Void = ensureGroups()
        async let global: Void = ensureLowBalanceGlobal()
        _ = await (groups, global)
    }
    private func ensureGroups() async { await app?.groupDirectory?.ensureLoaded() }
    private func ensureLowBalanceGlobal() async { await app?.userList?.ensureLowBalanceGlobal() }
    /// A missing user leaves the list; any other profile is the list's newest copy.
    private func settleProfile() {
        guard let app, isLive else { return }
        if profile.lastError?.isUserNotFound == true {
            isMissing = true
            app.userList?.remove(id: userID)
        } else if case .loaded(let user, _) = profile.state {
            app.userList?.replace(user)
        }
    }
    private func apply(_ user: AdminUser) {
        guard isLive, user.id == userID, profile.value != nil else { return }
        profile.updateValue { _ in user }
    }
}

/// 30 §2.4 启用 / 禁用 and its undo, which may run after the page is gone: `apply` and `readBack` hold the page weakly, the list is
/// written through AppModel.
@MainActor
enum UserStatusAction {
    static func run(app: AppModel, userID: Int, displayName: String, enable: Bool, activeKeyCount: Int?, offersUndo: Bool,
                    apply: @escaping @MainActor @Sendable (AdminUser) -> Void, readBack: @escaping @MainActor @Sendable () async -> Void) async {
        let generation = app.sessionGeneration
        do {
            let outcome = try await app.setUserStatus(id: userID, status: enable ? "active" : "disabled")
            guard app.sessionGeneration == generation else { return }
            apply(outcome.value)
            app.userList?.replace(outcome.value)
            let undo = offersUndo ? undoAction(app: app, userID: userID, displayName: displayName, enable: !enable, activeKeyCount: activeKeyCount,
                                               apply: apply, readBack: readBack) : nil
            let text = UserDetailPresentation.statusReceipt(displayName: displayName, disabling: !enable, activeKeyCount: activeKeyCount)
            app.receipts.show(Receipt(text: text, systemImage: enable ? "checkmark.circle" : "pause.circle", tone: enable ? .ok : .neutral, undo: undo))
        } catch {
            guard app.sessionGeneration == generation, !(error is CancellationError) else { return }
            let failure = UserDetailPresentation.statusFailure(error)
            app.receipts.show(Receipt(text: failure.text, systemImage: "exclamationmark.triangle", tone: .critical))
            if failure.readsBack {
                app.userList?.setNeedsRefresh()
                await readBack()
            }
        }
    }
    /// The opposite status, offered once: the undo's own receipt has no 撤销.
    private static func undoAction(app: AppModel, userID: Int, displayName: String, enable: Bool, activeKeyCount: Int?,
                                   apply: @escaping @MainActor @Sendable (AdminUser) -> Void,
                                   readBack: @escaping @MainActor @Sendable () async -> Void) -> @MainActor @Sendable () -> Void {
        {
            _ = Task {
                await run(app: app, userID: userID, displayName: displayName, enable: enable, activeKeyCount: activeKeyCount, offersUndo: false,
                          apply: apply, readBack: readBack)
            }
        }
    }
}
