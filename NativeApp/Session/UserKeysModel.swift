import Foundation
import Observation
import Sub2Core

/// What the key segment needs from the session (S3-12). The server clock travels here (S3D1-06).
struct UserKeysContext: Sendable {
    let generation: UUID
    let isReadOnlyToken: Bool
    /// `run_mode == simple`: expired and used-up keys still call (30 §7.3).
    let simpleMode: Bool
    /// E01 / E04: admin/me answered, so 停用 / 启用 and the exact undo exist (30 §0.1).
    let adminKeyWrites: Bool
    /// `api_keys.current_concurrency`: a write reply reports 0, so the card is read once more.
    let refreshesConcurrency: Bool
    let serverTimeZone: ServerTimeZone
    let now: @Sendable () -> Date
}

/// S3D1-11: a write that moves allowed_groups waits for “保存”, and “保存” waits for it. After the page has gone it is `open`.
struct UserKeysWriteGate: Sendable {
    let begin: @MainActor @Sendable () -> Bool
    let end: @MainActor @Sendable () -> Void
    static let open = UserKeysWriteGate(begin: { true }, end: {})
}

/// The page around the segment (S3D1-13): its base, the group directory (X11) and what to do after a write.
struct UserKeysHooks {
    let access: @MainActor () -> UserKeyAccess
    let groups: @MainActor () -> [AdminGroup]
    let onImmediate: @MainActor (UserKeyImmediateEvent) -> Void
    /// A grant was added or withdrawn: the user is read again (UserChangeSignal.bump).
    let onUserChanged: @MainActor () -> Void
    /// GROUP_NOT_FOUND / GROUP_NOT_ACTIVE: the directory is out of date.
    let onGroupsStale: @MainActor () -> Void
}

/// The segment's calls: AppModel (with its -ui-testing branches) in the App, stubs in tests.
@MainActor protocol UserKeysSource: AnyObject {
    var userKeysContext: UserKeysContext? { get }
    func userAPIKeys(userID: Int) async throws -> [AdminAPIKey]
    func apiKey(id: Int) async throws -> AdminAPIKey
    func apiKeysTodayUsage(ids: [Int]) async throws -> [Int: Decimal]
    func userSubscriptions(userID: Int) async throws -> [AdminUserSubscription]
    func updateAPIKey(id: Int, _ change: AdminAPIKeyUpdateRequest) async throws -> AdminAPIKeyWriteResult
    func user(id: Int) async throws -> AdminUser
    /// S3D1-10: the only way to withdraw a grant at once; both keys go together.
    func updateUserGroups(userID: Int, allowedGroups: [Int], restrictPublicGroups: Bool) async throws -> AdminUser
}

/// 30 §7 Key 与限额 · API Key 卡片 (S3-12): the user's keys, today's spend and subscriptions, and the writes. Every write waits
/// for the server (no optimistic change), goes out once without a key and is read back when nobody saw the reply (R06). The
/// edit page owns one per user; a receipt's 撤销 keeps it alive after the page has gone. S3-13 to S3-15 add to it from outside.
@MainActor @Observable
final class UserKeysModel {
    enum ListPhase: Equatable { case loading, loaded, failed }

    let userID: Int
    private(set) var phase = ListPhase.loading
    /// Id ascending, deleted ones dropped.
    private(set) var keys: [AdminAPIKey] = []
    /// nil: unavailable (failed, or a read-only token, R14).
    private(set) var todayCosts: [Int: Decimal]?
    private(set) var subscriptions: [AdminUserSubscription] = []
    /// One card open at a time; the first opens by itself after the first read.
    private(set) var expandedID: Int?
    /// Cards with a write out: only their buttons turn into progress.
    private(set) var inFlight: Set<Int> = []

    @ObservationIgnored private weak var source: (any UserKeysSource)?
    @ObservationIgnored let receipts: ReceiptCenter
    @ObservationIgnored let hooks: UserKeysHooks
    @ObservationIgnored let writeGate: UserKeysWriteGate
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var entryTask: Task<Void, Never>?
    @ObservationIgnored private var hasOpenedFirst = false

    init(userID: Int, source: any UserKeysSource, receipts: ReceiptCenter, hooks: UserKeysHooks, writeGate: UserKeysWriteGate = .open) {
        self.userID = userID; self.source = source; self.receipts = receipts; self.hooks = hooks; self.writeGate = writeGate
    }

    var context: UserKeysContext? { source?.userKeysContext }
    /// “Key 与限额（N）”; nil until the list has been read once.
    var count: Int? { phase == .loaded ? keys.count : nil }
    func todayCost(for id: Int) -> UserKeyTodayCost { todayCosts.map { .value($0[id] ?? 0) } ?? .unavailable }
    /// “绑定 N 个 Key” of a group.
    func bindingCount(groupID: Int) -> Int { UserEditSaveReceipt.boundKeyCount(groupID: groupID, keys: keys) }

    // MARK: - 读取（30 §7.6）

    /// The page's first read, for the count; a read already out is shared.
    func ensureListLoaded() async {
        guard listTask != nil || phase != .loaded else { return }
        await loadList()
    }
    /// Switching to the segment reads the list, today's spend and the subscriptions, once per page. The reads are the model's:
    /// the view asking can go (another segment rebuilds the form) without leaving them cancelled for good.
    func enterSegment() async {
        if entryTask == nil { entryTask = Task { await self.refreshAll() } }
        await entryTask?.value
    }
    /// The pull: everything again.
    func refreshAll() async {
        async let subscriptions: Void = loadSubscriptions()
        await loadList()
        await loadToday()
        await subscriptions
    }
    func retryList() async {
        phase = .loading
        await refreshAll()
    }
    @discardableResult func toggleExpanded(_ id: Int) -> Bool {
        expandedID = expandedID == id ? nil : id
        return expandedID == id
    }

    // MARK: - 卡片（S3-13 的新建、编辑与删除也用）

    func replace(_ key: AdminAPIKey) {
        guard let index = keys.firstIndex(where: { $0.id == key.id }) else { return }
        keys[index] = key
    }
    func insert(_ key: AdminAPIKey) { keys = (keys.filter { $0.id != key.id } + [key]).sorted { $0.id < $1.id } }
    func remove(id: Int) {
        keys.removeAll { $0.id == id }
        if expandedID == id { expandedID = nil }
    }

    func isCurrent(_ generation: UUID) -> Bool { source?.userKeysContext?.generation == generation }
    var keySource: (any UserKeysSource)? { source }

    // MARK: - 私有读取

    private func loadList() async {
        if let listTask { return await listTask.value }
        let task = Task { await self.readList() }
        listTask = task
        await task.value
        listTask = nil
    }
    private func readList() async {
        guard let source, let generation = context?.generation else { return }
        do {
            let loaded = try await source.userAPIKeys(userID: userID).filter { !$0.isTombstone }
            guard isCurrent(generation) else { return }
            keys = loaded
            phase = .loaded
            if !hasOpenedFirst { expandedID = loaded.first?.id; hasOpenedFirst = true }
            if let expandedID, !loaded.contains(where: { $0.id == expandedID }) { self.expandedID = nil }
        } catch {
            guard isCurrent(generation), !(error is CancellationError) else { return }
            if phase == .loaded {
                receipts.show(Receipt(text: UserKeyPresentation.refreshFailed, systemImage: "exclamationmark.triangle", tone: .caution))
            } else {
                phase = .failed
            }
        }
    }
    private func loadToday() async {
        guard phase == .loaded, let source, let context else { return }
        guard !context.isReadOnlyToken else { todayCosts = nil; return }
        let ids = keys.map(\.id)
        guard !ids.isEmpty else { todayCosts = [:]; return }
        do {
            let costs = try await source.apiKeysTodayUsage(ids: ids)
            guard isCurrent(context.generation) else { return }
            todayCosts = costs
        } catch {
            guard isCurrent(context.generation), !(error is CancellationError) else { return }
            todayCosts = nil
        }
    }
    /// A failed read leaves no subscription, so subscription groups read as unavailable; a cancelled one keeps what was read.
    func loadSubscriptions() async {
        guard let source, let generation = context?.generation else { return }
        let loaded: [AdminUserSubscription]
        do { loaded = try await source.userSubscriptions(userID: userID) } catch {
            guard !(error is CancellationError) else { return }
            loaded = []
        }
        guard isCurrent(generation) else { return }
        subscriptions = loaded
    }

    // MARK: - 写的公共部分

    enum Sent {
        case done(AdminAPIKeyWriteResult, AdminAPIKey?)
        case failed(UserKeyWriteFailure)
        /// Cancelled, the session changed, or nothing could be sent.
        case dropped
    }

    /// One PUT, never resent: the card takes the reply's key (or a read of it), a lost reply is read back once.
    func send(_ change: UserKeyChange, request: AdminAPIKeyUpdateRequest? = nil, keyID: Int, context: UserKeysContext) async -> Sent {
        guard let source else { return .dropped }
        let body: AdminAPIKeyUpdateRequest
        do { body = try request ?? change.request() } catch { return .failed(.rejected(error.localizedDescription)) }
        inFlight.insert(keyID)
        defer { inFlight.remove(keyID) }
        do {
            let result = try await source.updateAPIKey(id: keyID, body)
            guard isCurrent(context.generation) else { return .dropped }
            var key = result.apiKey
            if key == nil { key = try? await source.apiKey(id: keyID) }
            guard isCurrent(context.generation) else { return .dropped }
            if let key { replace(key) }
            return .done(result, key)
        } catch {
            guard isCurrent(context.generation), let failure = UserKeyWriteFailure(error) else { return .dropped }
            guard failure == .unconfirmed else { await settle(failure, keyID: keyID); return .failed(failure) }
            return await readBack(change, keyID: keyID, source: source, context: context)
        }
    }
    /// R06: the change shows in the key → done; otherwise nobody knows.
    private func readBack(_ change: UserKeyChange, keyID: Int, source: any UserKeysSource, context: UserKeysContext) async -> Sent {
        do {
            let key = try await source.apiKey(id: keyID)
            guard isCurrent(context.generation) else { return .dropped }
            replace(key)
            return UserKeyPresentation.readBackConfirms(change, readBack: key) ? .done(AdminAPIKeyWriteResult(apiKey: key), key) : .failed(.unconfirmed)
        } catch {
            guard isCurrent(context.generation) else { return .dropped }
            guard UserKeyWriteFailure(error) == .keyGone else { return .failed(.unconfirmed) }
            await settle(.keyGone, keyID: keyID)
            return .failed(.keyGone)
        }
    }
    private func settle(_ failure: UserKeyWriteFailure, keyID: Int) async {
        switch failure {
        case .keyGone: remove(id: keyID)
        case .groupGone, .groupInactive: hooks.onGroupsStale()
        case .subscriptionRequired: await loadSubscriptions()
        case .groupStillInUse, .unconfirmed, .rejected: break
        }
    }
    func report(_ sent: Sent, undoing: Bool = false) {
        guard case .failed(let failure) = sent else { return }
        receipts.show(Receipt(text: UserKeyPresentation.failureReceipt(failure, undoing: undoing), systemImage: "exclamationmark.triangle",
                              tone: failure == .unconfirmed ? .caution : .critical))
    }
    /// The card's concurrency after a write; a failure keeps the reply's.
    func refreshConcurrency(_ keyID: Int, context: UserKeysContext) async {
        guard context.refreshesConcurrency, let source, keys.contains(where: { $0.id == keyID }) else { return }
        guard let fresh = try? await source.apiKey(id: keyID), isCurrent(context.generation) else { return }
        replace(fresh)
    }
}


/// 30 §7.4 (S3-12): 换分组 and its 撤销, 停用 / 启用, 重置速率限制. A change that grants or withdraws a group goes through the
/// page's write gate (S3D1-11); every success is named to the page (S3D1-13) and refreshes the card's concurrency.
extension UserKeysModel {
    /// The sheet's pick; the current group sends nothing.
    func changeGroup(_ key: AdminAPIKey, to targetID: Int?) async {
        guard (key.groupID ?? 0) != (targetID ?? 0), canWrite(key), let context else { return }
        let groups = hooks.groups(), access = hooks.access()
        let group = { (id: Int?) in id.flatMap { id in groups.first { $0.id == id } } }
        let granted = UserKeyPresentation.newlyGranted(target: group(targetID), access: access)
        let undoable = UserKeyPresentation.groupUndoAvailable(from: group(key.groupID), access: access)
        let change = UserKeyChange.group(from: key.groupID, to: targetID)
        guard beginGate(granted) else { return }
        let sent = await send(change, keyID: key.id, context: context)
        endGate(granted)
        guard case .done = sent else { report(sent); return }
        let name = change.operationName(keyName: key.displayName)
        hooks.onImmediate(.applied(name: name, grantedGroupID: granted ? targetID : nil))
        if granted { hooks.onUserChanged() }
        let undo = UserKeyGroupUndo(keyID: key.id, keyName: key.displayName, fromGroupID: key.groupID, toGroupID: targetID, newlyGranted: granted)
        let text = UserKeyPresentation.groupReceipt(keyName: key.displayName, targetName: targetID.map { UserKeyPresentation.groupName($0, groups: groups) },
                                                    newlyGranted: granted)
        var undoAction: (@MainActor @Sendable () -> Void)?
        if undoable { undoAction = { [self] in Task { await undoGroup(undo) } } }
        receipts.show(Receipt(text: text, systemImage: "square.stack.3d.up", undo: undoAction))
        await refreshConcurrency(key.id, context: context)
    }

    /// ⋯ 停用 Key / 启用 Key (E01): sent at once, 撤销 writes `previous.status` back.
    func setStatus(_ key: AdminAPIKey, to status: AdminAPIKeyUpdateRequest.Status) async {
        guard canWrite(key), let context, context.adminKeyWrites else { return }
        let change = UserKeyChange.status(status)
        let sent = await send(change, keyID: key.id, context: context)
        guard case .done(let result, let fresh) = sent else { report(sent); return }
        if let fresh, !UserKeyPresentation.statusTook(status, in: fresh) {
            receipts.show(Receipt(text: UserKeyPresentation.statusIgnored(status), systemImage: "exclamationmark.triangle", tone: .caution))
            return
        }
        let name = change.operationName(keyName: key.displayName)
        hooks.onImmediate(.applied(name: name, grantedGroupID: nil))
        let now = context.now()
        let text = UserKeyPresentation.statusReceipt(keyName: key.displayName, requested: status, result: fresh, now: now, simpleMode: context.simpleMode)
        let blocked = UserKeyPresentation.stillBlocked(requested: status, result: fresh, now: now, simpleMode: context.simpleMode)
        var undo: (@MainActor @Sendable () -> Void)?
        if let back = UserKeyPresentation.statusUndo(previous: result.previous) {
            let id = key.id
            undo = { [self] in Task { await undoStatus(id, to: back, name: name) } }
        }
        receipts.show(Receipt(text: text, systemImage: status == .inactive ? "pause.circle" : "play.circle", tone: blocked ? .caution : .ok, undo: undo))
        await refreshConcurrency(key.id, context: context)
    }

    /// After the confirmation: cannot be undone.
    func resetRateLimit(_ key: AdminAPIKey) async {
        guard canWrite(key), let context else { return }
        let change = UserKeyChange.resetRateLimit
        let sent = await send(change, keyID: key.id, context: context)
        guard case .done = sent else { report(sent); return }
        hooks.onImmediate(.applied(name: change.operationName(keyName: key.displayName), grantedGroupID: nil))
        receipts.show(Receipt(text: UserKeyPresentation.resetReceipt, systemImage: "arrow.counterclockwise"))
        await refreshConcurrency(key.id, context: context)
    }

    // MARK: - 撤销

    /// 30 §7.4 / §0.6. Runs after the page has gone too; the page's gate and base then do nothing.
    func undoGroup(_ undo: UserKeyGroupUndo) async {
        guard let context, let plan = try? UserKeyPresentation.groupUndoPlan(undo, exactUndoSupported: context.adminKeyWrites) else { return }
        let name = UserKeyChange.group(from: undo.fromGroupID, to: undo.toGroupID).operationName(keyName: undo.keyName)
        switch plan {
        case .keyOnly(let request):
            let sent = await send(undo.keyChange, request: request, keyID: undo.keyID, context: context)
            guard case .done = sent else { report(sent, undoing: true); return }
            hooks.onImmediate(.withdrawn(name: name, revokedGroupID: nil))
        case .exact(let request):
            guard beginGate(true) else { return }
            await undoExactly(undo, request: request, name: name, context: context)
            endGate(true)
        case .twoStep(let request, let revokeID):
            guard beginGate(true) else { return }
            let sent = await send(undo.keyChange, request: request, keyID: undo.keyID, context: context)
            if case .done = sent { await withdrawGrant(revokeID, name: name, context: context) } else { report(sent, undoing: true) }
            endGate(true)
        }
        await refreshConcurrency(undo.keyID, context: context)
    }

    /// E04 in one transaction; 409 GROUP_STILL_IN_USE rolled all of it back, so the key goes back alone and the grant stays.
    private func undoExactly(_ undo: UserKeyGroupUndo, request: AdminAPIKeyUpdateRequest, name: String, context: UserKeysContext) async {
        let sent = await send(undo.keyChange, request: request, keyID: undo.keyID, context: context)
        switch sent {
        case .done:
            hooks.onImmediate(.withdrawn(name: name, revokedGroupID: undo.toGroupID))
            hooks.onUserChanged()
        case .failed(.groupStillInUse):
            let back = await send(undo.keyChange, keyID: undo.keyID, context: context)
            guard case .done = back else { report(back, undoing: true); return }
            receipts.show(Receipt(text: UserKeyPresentation.undoKeptGrantReceipt, systemImage: "info.circle", tone: .caution))
        case .failed, .dropped:
            report(sent, undoing: true)
        }
    }
    /// 30 §0.6 second step: the fresh allowed_groups without the group, through the one grant writer (S3D1-10).
    private func withdrawGrant(_ groupID: Int, name: String, context: UserKeysContext) async {
        guard let source = keySource else { return }
        do {
            let user = try await source.user(id: userID)
            guard isCurrent(context.generation) else { return }
            if user.allowedGroups?.contains(groupID) == true {
                _ = try await source.updateUserGroups(userID: userID, allowedGroups: UserKeyPresentation.allowedGroupsAfterRevoke(user.allowedGroups, revoking: groupID),
                                                      restrictPublicGroups: user.restrictPublicGroups ?? false)
                guard isCurrent(context.generation) else { return }
            }
            hooks.onImmediate(.withdrawn(name: name, revokedGroupID: groupID))
            hooks.onUserChanged()
        } catch {
            guard isCurrent(context.generation), !(error is CancellationError) else { return }
            receipts.show(Receipt(text: UserKeyPresentation.twoStepPartialReceipt, systemImage: "exclamationmark.triangle", tone: .caution))
        }
    }
    private func undoStatus(_ keyID: Int, to status: AdminAPIKeyUpdateRequest.Status, name: String) async {
        guard let context else { return }
        let sent = await send(.status(status), keyID: keyID, context: context)
        guard case .done = sent else { report(sent, undoing: true); return }
        hooks.onImmediate(.withdrawn(name: name, revokedGroupID: nil))
        await refreshConcurrency(keyID, context: context)
    }

    // MARK: - 闸门

    /// Not while another write on the card is out, nor with a read-only token (R14).
    private func canWrite(_ key: AdminAPIKey) -> Bool {
        !inFlight.contains(key.id) && context?.isReadOnlyToken == false && keys.contains { $0.id == key.id }
    }
    private func beginGate(_ movesGrant: Bool) -> Bool {
        guard movesGrant else { return true }
        if writeGate.begin() { return true }
        receipts.show(Receipt(text: UserEditCopy.immediateBlockedBySave, systemImage: "clock", tone: .caution))
        return false
    }
    private func endGate(_ movesGrant: Bool) { if movesGrant { writeGate.end() } }
}
