import Foundation
import Observation
import Sub2Core

/// 50 §3.4 / §3.5's reads and writes for the group sheet; AppGroupEditSource on screen, a script in tests.
@MainActor protocol GroupEditSource: AnyObject {
    var groupWriteSession: GroupWriteSession? { get }
    /// APIClient.userWriteIdentity(); CancellationError without a session.
    func groupWriteIdentity() async throws -> UUID
    func fetchGroupStats(id: Int) async throws -> GroupStats?
    func fetchGroup(id: Int) async throws -> AdminGroup
    /// POST admin/groups or PUT admin/groups/:id under the operation made at the last confirmation (R05).
    func sendGroupWrite(_ intent: GroupWriteDraft.Intent, operation: GroupWriteOperation, onEvent: KeyedWriteEventHandler?) async throws -> WriteOutcome<AdminGroup>
    /// GET admin/groups?search=&platform=: the creation check.
    func searchGroups(name: String, platform: String) async throws -> [AdminGroup]
}

/// What the page knew when 创建 / 保存 was tapped.
struct GroupEditContext: Sendable, Equatable {
    /// GroupPermissions.editableFields(in: original).
    let editable: Set<GroupPermissions.Field>
    /// The list's ids then; a creation check only takes a group that was not among them.
    let knownGroupIDs: Set<Int>
    /// For the platform's name in the new group's confirmation.
    let catalog: MetaCatalog?
    /// The server's clock, for the members' states (S5-11).
    let now: Date
}

struct GroupEditPrompt: Identifiable, Equatable, Sendable {
    let id: UUID
    let confirmation: GroupConfirmation
}

enum GroupEditFailure: Equatable, Sendable {
    /// 409 GROUP_EXISTS: red under the name; the sheet stays.
    case nameTaken
    /// A refusal in fixed words (GroupWriteDisposition, R11).
    case message(String)
    /// The group was deleted meanwhile: the form locks, only 取消 is left.
    case gone
    /// An unkeyed write the check shows did not happen: it may be sent again as a new request.
    case notApplied
}

struct GroupEditUnconfirmed: Equatable, Sendable {
    /// The write carried an Idempotency-Key, so 用同一编号重试 is offered.
    let keyed: Bool
    /// 503 IDEMPOTENCY_STORE_UNAVAILABLE's cooldown, on the device clock.
    let retryNotBefore: Date?
    let text: String
    /// The last check's finding.
    let check: GroupEditCheck?
    func checked(_ finding: GroupEditCheck) -> GroupEditUnconfirmed {
        GroupEditUnconfirmed(keyed: keyed, retryNotBefore: retryNotBefore, text: text, check: finding)
    }
}

/// What the server holds after a write that went through; the members go out from here (S5-11). Only members changed: the group
/// as the sheet opened it.
struct GroupEditSaved: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case created, saved(droppedFields: Bool) }
    let kind: Kind
    let group: AdminGroup
}

/// 50 §3.4–§3.5: 创建 / 保存 of the group sheet. A public group with nothing available and a risky edit ask first; the number is
/// made at the last confirmation, or at the tap without one (R05), and kept for its retries. A refusal stays on the sheet; a
/// result that may have run is read back once by itself and never sent again by itself (S5D2a-06) — the sheet keeps 核对 and,
/// with a key, 用同一编号重试. Every way to success ends in `finish(_:)`, which writes the members once the group's own step went
/// through (S5-11, GroupEditFlow+Members.swift); a change of members only sends no PUT. Answers for another session are dropped.
@MainActor @Observable
final class GroupEditFlow {
    enum Phase: Equatable {
        case editing
        /// The identity, and before disabling the active key count.
        case preparing
        case confirming(GroupEditPrompt)
        case saving(KeyedWriteEvent?)
        case checking
        case failed(GroupEditFailure)
        case unconfirmed(GroupEditUnconfirmed)
    }
    nonisolated static let reconcilePageSize = 100

    let original: AdminGroup?
    private(set) var phase: Phase = .editing
    /// The write landed or the check settled it: the sheet closes.
    private(set) var isFinished = false
    /// Names 409 GROUP_EXISTS refused in this sheet; the page counts them as taken.
    private(set) var rejectedNames: Set<String> = []
    /// The send `confirm()` started.
    @ObservationIgnored private(set) var sending: Task<Void, Never>?

    @ObservationIgnored private let source: any GroupEditSource
    @ObservationIgnored private let store: @MainActor () -> (any GroupActionStore)?
    @ObservationIgnored let receipts: ReceiptCenter
    /// S5-08's one way member writes go out; nil sends no members.
    @ObservationIgnored let memberWriter: GroupMemberWriter?
    /// 查看 → the per-item results (S5-09).
    @ObservationIgnored let openResults: (@MainActor @Sendable (GroupBatchOutcome) -> Void)?
    @ObservationIgnored private let makeKey: @MainActor () -> UUID
    @ObservationIgnored private let deviceNow: @MainActor () -> Date
    @ObservationIgnored private let pause: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let statsWait: Duration
    /// The checked write; its operation once confirmed, kept while the result is open.
    @ObservationIgnored private var pending: GroupWriteDraft?
    @ObservationIgnored private var session: GroupWriteSession?
    @ObservationIgnored private var context: GroupEditContext?
    /// The members to write after the group's own step, taken at the tap.
    @ObservationIgnored private var memberPlan: GroupMemberCommitPlan?
    /// Only members changed: no PUT and no number.
    @ObservationIgnored private var savesMembersOnly = false

    init(original: AdminGroup?, source: any GroupEditSource, store: @escaping @MainActor () -> (any GroupActionStore)?, receipts: ReceiptCenter,
         makeKey: @escaping @MainActor () -> UUID = { UUID() }, deviceNow: @escaping @MainActor () -> Date = { Date() },
         pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, statsWait: Duration = GroupActions.statsWait,
         memberWriter: GroupMemberWriter? = nil, openResults: (@MainActor @Sendable (GroupBatchOutcome) -> Void)? = nil) {
        self.original = original; self.source = source; self.store = store; self.receipts = receipts; self.makeKey = makeKey
        self.deviceNow = deviceNow; self.pause = pause; self.statsWait = statsWait; self.memberWriter = memberWriter; self.openResults = openResults
    }

    private var isNew: Bool { original == nil }
    var isBusy: Bool {
        switch phase {
        case .preparing, .saving, .checking: true
        default: false
        }
    }
    /// 00 §2.5.4: the server may have run the write; closing asks first (稍后核对).
    var isUnconfirmed: Bool {
        if case .unconfirmed = phase { true } else { false }
    }
    /// The form waits while a write runs or its result is open, and for good once the group is gone.
    var locksForm: Bool {
        switch phase {
        case .editing, .failed(.nameTaken), .failed(.message), .failed(.notApplied): false
        default: true
        }
    }
    var prompt: GroupEditPrompt? {
        if case .confirming(let prompt) = phase { prompt } else { nil }
    }
    /// The red line under the form; 409 GROUP_EXISTS speaks under the name instead.
    var failureMessage: String? {
        guard case .failed(let failure) = phase else { return nil }
        return switch failure {
        case .nameTaken: nil
        case .message(let text): text
        case .gone: GroupErrorCopy.deleted
        case .notApplied: GroupEditCopy.notApplied(isNew: isNew)
        }
    }

    // MARK: - 创建 / 保存

    /// Nothing without a session or with a read-only token. Asks when 3.4 says so (reading the active key count before a disable,
    /// at most `statsWait`); otherwise the number is made now and the write goes out.
    func submit(_ draft: GroupEditDraft, context: GroupEditContext) async {
        guard !locksForm, !isFinished, let session = source.groupWriteSession, !session.isReadOnlyToken else { return }
        let steps = draft.steps(editable: context.editable)
        memberPlan = steps.sendsMembers ? (try? draft.members.commitPlan()) : nil
        savesMembersOnly = steps == .membersOnly
        if savesMembersOnly { return await submitMembers(draft, session: session, context: context) }
        guard let intent = try? makeIntent(draft, editable: context.editable) else { return }
        phase = .preparing
        guard let identity = try? await source.groupWriteIdentity(), isCurrent(session) else { return settleIfCurrent(session) }
        do {
            pending = try GroupWriteDraft(intent, serverID: session.serverID, identity: identity, sendsIdempotencyKey: session.idempotentWrites)
        } catch {
            pending = nil
            phase = .failed(.message(GroupErrorCopy.message(for: error, context: .write)))
            return
        }
        self.session = session
        self.context = context
        guard let confirmation = await confirmation(for: draft, intent: intent, session: session, context: context) else {
            guard isCurrent(session) else { return }
            return await sendConfirmed(session)
        }
        guard isCurrent(session) else { return }
        phase = .confirming(GroupEditPrompt(id: UUID(), confirmation: confirmation))
    }
    /// The confirmation's 仍然创建 / 保存修改 / 仍然保存: the number is made now (R05). The phase leaves `confirming` at once, so the
    /// alert's binding does not bring it back.
    func confirm() {
        guard case .confirming = phase, let session, isCurrent(session) else { return }
        phase = .saving(nil)
        sending = Task {
            if self.savesMembersOnly { await self.saveMembersOnly() } else { await self.sendConfirmed(session) }
        }
    }
    /// 取消: nothing is sent and no number was made.
    func cancelConfirmation() {
        guard case .confirming = phase else { return }
        pending = nil
        memberPlan = nil
        phase = .editing
    }
    /// The form changed after a refusal: back to editing; the next tap makes a new number.
    func draftChanged() {
        guard case .failed(let failure) = phase, failure != .gone else { return }
        phase = .editing
    }

    private func makeIntent(_ draft: GroupEditDraft, editable: Set<GroupPermissions.Field>) throws -> GroupWriteDraft.Intent? {
        guard let original else { return .create(try draft.createRequest()) }
        return try draft.updateRequest(editable: editable).map { .update(groupID: original.id, $0) }
    }
    private func confirmation(for draft: GroupEditDraft, intent: GroupWriteDraft.Intent, session: GroupWriteSession,
                              context: GroupEditContext) async -> GroupConfirmation? {
        switch intent {
        case .create(let request):
            let available = draft.members.availableAfter(now: context.now) ?? 0
            return GroupCopy.createConfirmation(request, siteName: session.siteName, availableAfter: available, catalog: context.catalog)
        case .update(let id, let request):
            guard let diff = draft.diff(request, now: context.now), diff.requiresConfirmation else { return nil }
            let disabling = request.status == "inactive" && draft.original?.status == "active"
            let stats = disabling ? await statsWithin(id, session: session) : nil
            return diff.confirmation(siteName: session.siteName, activeAPIKeys: stats?.activeAPIKeys)
        }
    }
    private func sendConfirmed(_ session: GroupWriteSession) async {
        guard var write = pending, let operation = try? write.confirmedOperation(id: makeKey()) else { return settleIfCurrent(session) }
        pending = write
        await send(write.intent, operation: operation, session: session)
    }
    /// 3.4 编辑 2–3 with members only: asks only when the group would be left without an available account (S5-11).
    private func submitMembers(_ draft: GroupEditDraft, session: GroupWriteSession, context: GroupEditContext) async {
        guard memberPlan != nil, let diff = draft.diff(GroupUpdateRequest(), now: context.now) else { return }
        self.session = session
        self.context = context
        guard diff.requiresConfirmation else {
            phase = .saving(nil)
            return await saveMembersOnly()
        }
        phase = .confirming(GroupEditPrompt(id: UUID(), confirmation: diff.confirmation(siteName: session.siteName, activeAPIKeys: nil)))
    }
    private func saveMembersOnly() async {
        guard let original, let session, isCurrent(session) else { return }
        await finish(GroupEditSaved(kind: .saved(droppedFields: false), group: original), wroteGroup: false)
    }

    // MARK: - 发送

    private func send(_ intent: GroupWriteDraft.Intent, operation: GroupWriteOperation, session: GroupWriteSession) async {
        phase = .saving(nil)
        let handler: KeyedWriteEventHandler = { [weak self] event in await self?.note(event) }
        do {
            let outcome = try await source.sendGroupWrite(intent, operation: operation, onEvent: handler)
            guard isCurrent(session) else { return }
            switch intent {
            case .create: await finish(GroupEditSaved(kind: .created, group: outcome.value))
            case .update(_, let request):
                await finish(GroupEditSaved(kind: .saved(droppedFields: GroupEditReconcile.droppedFields(request, response: outcome.value)), group: outcome.value))
            }
        } catch {
            guard isCurrent(session) else { return }
            await settle(error, intent: intent, operation: operation)
        }
    }
    private func note(_ event: KeyedWriteEvent) {
        guard case .saving = phase else { return }
        phase = .saving(event)
    }
    /// 409 GROUP_EXISTS first (the name field), then GroupWriteDisposition (S5D2a-06).
    private func settle(_ error: any Error, intent: GroupWriteDraft.Intent, operation: GroupWriteOperation) async {
        if let api = error as? APIError, GroupErrorCopy.resolve(api, context: .write).action == .nameField {
            rejectedNames.insert(Self.name(of: intent, original: original))
            return fail(.nameTaken)
        }
        switch GroupWriteDisposition.of(error) {
        case .cancelled: fail(nil)
        case .gone:
            guard let original else { return fail(.message(GroupErrorCopy.message(for: error, context: .write))) }
            gone(original.id)
        case .rejected(let text): fail(.message(text))
        case .reconfirm: fail(.message(GroupEditCopy.reconfirm(isNew: isNew)))
        case .unconfirmed(let notBefore):
            let keyed = operation.sendsIdempotencyKey
            phase = .unconfirmed(GroupEditUnconfirmed(keyed: keyed, retryNotBefore: notBefore, text: GroupEditCopy.unconfirmedText(error, keyed: keyed),
                                                      check: nil))
            await reconcile()
        }
    }
    /// The number is dropped: the next tap makes a new one.
    private func fail(_ failure: GroupEditFailure?) {
        pending = nil
        phase = failure.map(Phase.failed) ?? .editing
    }
    private func gone(_ id: Int) {
        pending = nil
        store()?.remove(id: id)
        phase = .failed(.gone)
    }

    // MARK: - 结果不明

    /// 读取服务器状态核对 (also once by itself when the result is lost): an edit compares the fields it sent, a creation looks for
    /// its exact name on its platform. Settled → done; 404 → gone; unkeyed and not there → the form opens again.
    func reconcile() async {
        guard case .unconfirmed(let state) = phase, let write = pending, let session, isCurrent(session) else { return }
        phase = .checking
        switch write.intent {
        case .update(let id, let request): await checkUpdate(id, request, state: state, session: session)
        case .create(let request): await checkCreate(request, state: state, session: session)
        }
    }
    private func checkUpdate(_ id: Int, _ request: GroupUpdateRequest, state: GroupEditUnconfirmed, session: GroupWriteSession) async {
        do {
            let fresh = try await source.fetchGroup(id: id)
            guard isCurrent(session) else { return }
            if GroupEditReconcile.saved(request, server: fresh) { return await finish(GroupEditSaved(kind: .saved(droppedFields: false), group: fresh)) }
            notApplied(state, finding: .differs)
        } catch {
            guard isCurrent(session) else { return }
            if case .gone = GroupWriteDisposition.of(error) { return gone(id) }
            phase = .unconfirmed(state.checked(.failed))
        }
    }
    private func checkCreate(_ request: GroupCreateRequest, state: GroupEditUnconfirmed, session: GroupWriteSession) async {
        do {
            let rows = try await source.searchGroups(name: request.name, platform: request.platform)
            guard isCurrent(session) else { return }
            if let found = GroupEditReconcile.created(request, in: rows, knownIDs: context?.knownGroupIDs ?? []) {
                return await finish(GroupEditSaved(kind: .created, group: found))
            }
            notApplied(state, finding: .notFound)
        } catch {
            guard isCurrent(session) else { return }
            phase = .unconfirmed(state.checked(.failed))
        }
    }
    /// Keyed, the same number may still be on its way: the result stays open. Unkeyed (00 §2.4), the form opens for a new request.
    private func notApplied(_ state: GroupEditUnconfirmed, finding: GroupEditCheck) {
        guard state.keyed else { return fail(.notApplied) }
        phase = .unconfirmed(state.checked(finding))
    }
    /// 用同一编号重试: the same operation (number and bytes), after what is left of the cooldown.
    func retrySameKey() async {
        guard case .unconfirmed(let state) = phase, state.keyed, let write = pending, let operation = write.operation, let session,
              isCurrent(session) else { return }
        if let wait = cooldownLeft(until: state.retryNotBefore) {
            phase = .saving(nil)
            do { try await pause(.seconds(wait)) } catch { phase = .unconfirmed(state); return }
            guard isCurrent(session) else { return }
        }
        await send(write.intent, operation: operation, session: session)
    }
    /// 稍后核对: the number is let go and the list reads again; the sheet then closes.
    func checkLater() {
        guard isUnconfirmed, !isFinished, let session, isCurrent(session) else { return }
        pending = nil
        phase = .editing
        store()?.refreshAfterWrite(directory: true)
    }

    // MARK: - 完成

    /// The one way out of a write that went through: the list and the directory, then the members while the sheet stays busy, one
    /// receipt (none when the members' answer was for another session), and the sheet closes. `wroteGroup` false: only members.
    private func finish(_ saved: GroupEditSaved, wroteGroup: Bool = true) async {
        let renames = saved.kind == .created || pendingRenames
        let plan = memberPlan
        pending = nil
        memberPlan = nil
        if wroteGroup {
            let store = store()
            store?.upsert(saved.group)
            store?.refreshAfterWrite(directory: renames)
        }
        var receipt: Receipt? = Self.receipt(saved)
        if let plan, let memberWriter {
            phase = .saving(nil)
            receipt = await memberReceipt(plan, after: saved, writer: memberWriter)
        }
        if let receipt { receipts.show(receipt) }
        phase = .editing
        isFinished = true
    }
    private var pendingRenames: Bool {
        guard case .update(_, let request)? = pending?.intent else { return false }
        return request.name != nil
    }
    private static func receipt(_ saved: GroupEditSaved) -> Receipt {
        switch saved.kind {
        case .created: Receipt(text: GroupCopy.createdReceipt(name: saved.group.name))
        case .saved(let dropped):
            dropped ? Receipt(text: GroupCopy.savedReceipt(name: saved.group.name, droppedFields: true), systemImage: "exclamationmark.triangle", tone: .caution)
                : Receipt(text: GroupCopy.savedReceipt(name: saved.group.name))
        }
    }

    // MARK: - Helpers

    private func isCurrent(_ session: GroupWriteSession) -> Bool { source.groupWriteSession?.generation == session.generation }
    /// A step that ended without an answer for this session: the form opens again unless the session changed.
    private func settleIfCurrent(_ session: GroupWriteSession) {
        guard isCurrent(session) else { return }
        fail(nil)
    }
    /// At most `statsWait`: a failure, a slow read and an older server all leave the number out (U39).
    private func statsWithin(_ id: Int, session: GroupWriteSession) async -> GroupStats? {
        guard session.readsStats else { return nil }
        phase = .preparing
        let pause = self.pause, wait = statsWait
        return await withTaskGroup(of: GroupStats?.self) { group in
            group.addTask { await self.readStats(id) }
            group.addTask { try? await pause(wait); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
    private func readStats(_ id: Int) async -> GroupStats? { try? await source.fetchGroupStats(id: id) }
    /// Counted on the device clock that set it and never longer than the cooldown.
    private func cooldownLeft(until notBefore: Date?) -> TimeInterval? {
        guard let notBefore else { return nil }
        let left = min(notBefore.timeIntervalSince(deviceNow()), IdempotencyPolicy.storeUnavailableCooldown)
        return left > 0 ? left : nil
    }
    private static func name(of intent: GroupWriteDraft.Intent, original: AdminGroup?) -> String {
        switch intent {
        case .create(let request): request.name
        case .update(_, let request): request.name ?? original?.name ?? ""
        }
    }
}
