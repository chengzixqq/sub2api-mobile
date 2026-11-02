import Foundation
import Observation
import os
import Sub2Core

/// What a member write reads of the session at the user's tap (S5D2a-08); its generation goes with every send.
struct GroupMemberWriteSession: Sendable, Equatable {
    let generation: UUID
    /// `groups.member_batch`, and no 500 GROUP_REPOSITORY_UNSUPPORTED yet in this session.
    let usesBatch: Bool
    /// Not in simple mode: there the account detail leaves composite groups out, so the 0.4.4 fallback's PUT would unbind them.
    let allowsLegacy: Bool
    let isReadOnlyToken: Bool
}

/// The group a write goes to, as the page showed it at the tap.
struct GroupMemberTarget: Sendable, Equatable {
    let id: Int
    let name: String
    /// `active_account_count` before the write, for “可用 x → y”.
    let activeBefore: Int?
    init(id: Int, name: String, activeBefore: Int?) { self.id = id; self.name = name; self.activeBefore = activeBefore }
    /// `active_account_count` is omitempty: a group without it had 0 available (00 §6.5).
    init(_ group: AdminGroup) { self.init(id: group.id, name: group.name, activeBefore: group.counts.activeAccountCount) }
}

/// After a member write that ran or may have: GroupStore keeps the latest per group and the detail refreshes from it (S5D2a-10).
struct GroupMemberChange: Sendable, Equatable, Identifiable {
    let id: UUID
    let groupID: Int
    /// The reply's counts; nil after the fallback, a lost reply or an account action.
    let counts: GroupAccountCounts?
    init(groupID: Int, counts: GroupAccountCounts?, id: UUID = UUID()) { self.id = id; self.groupID = groupID; self.counts = counts }
}

/// S5D2a-06: how a member write ended.
enum GroupMemberSendResult: Sendable, Equatable {
    /// Per-item answers: all, some or none done.
    case result(GroupMemberBatchResult, usedLegacy: Bool)
    /// Refused, nothing changed: GroupErrorCopy's fixed words (never the server's message).
    case rejected(String)
    /// 404 GROUP_NOT_FOUND / RESOURCE_NOT_FOUND.
    case groupGone(String)
    /// May have run: no answer, a timeout or a 5xx after S5-03's one resend (AccountWriteMark.mayHaveApplied).
    case unconfirmed
    /// No session, a read-only token, a busy account, another session meanwhile, or cancelled.
    case ignored
}

/// The member writes of the session (AppModel in GroupMemberActions.swift). A send carries the generation of the session the user
/// acted in and throws CancellationError once that session is gone.
@MainActor protocol GroupMemberWriteSource: AnyObject {
    var groupMemberWriteSession: GroupMemberWriteSession? { get }
    /// S5-03's `groupMemberBatch` (one automatic resend inside).
    func sendGroupMemberBatch(groupID: Int, _ request: GroupMemberBatchRequest, generation: UUID) async throws -> GroupMemberBatchResult
    /// S5-03's GroupMembersLegacyExecutor: the batch's shape without counts.
    func sendGroupMembersLegacy(groupID: Int, _ request: GroupMemberBatchRequest, generation: UUID) async throws -> GroupMemberBatchResult
    func noteMemberBatchUnsupported()
    func memberWriteFinished(_ change: GroupMemberChange)
    func groupWentAway(id: Int)
}

/// 50 §0.4 and §2.4, the one way member writes go out (S5D2a-08): the batch, or the 0.4.4 fallback without `groups.member_batch`
/// or after a 500 GROUP_REPOSITORY_UNSUPPORTED (then for the rest of the session). `add` and `remove` end in one receipt — 撤销
/// when everything went through, 查看 when something failed, 重试 when the result is unknown — whose buttons send in the session
/// of the first write; an undo that went through says nothing more (the rows show it), as AccountActions. `send` reports without
/// a receipt (S5-09, S5-11).
@MainActor @Observable
final class GroupMemberWriter {
    /// An add from the picker is out: it spins and cannot be closed.
    private(set) var isSubmitting = false
    /// Accounts a write is out for; another removal of them is ignored.
    private(set) var busyAccounts: Set<Int> = []
    /// The last send got GROUP_REPOSITORY_UNSUPPORTED and went on one account after another.
    private(set) var fellBackToLegacy = false
    @ObservationIgnored private let source: any GroupMemberWriteSource
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let openResults: @MainActor @Sendable (GroupBatchOutcome) -> Void
    private static let log = Logger(subsystem: "com.chengzixqq.sub2mobile", category: "groups")

    init(source: any GroupMemberWriteSource, receipts: ReceiptCenter, openResults: @escaping @MainActor @Sendable (GroupBatchOutcome) -> Void) {
        self.source = source; self.receipts = receipts; self.openResults = openResults
    }

    /// No receipt. A read-only token is refused with the catalog's words, as the server would.
    func send(_ request: GroupMemberBatchRequest, to groupID: Int) async -> GroupMemberSendResult {
        guard let session = source.groupMemberWriteSession else { return .ignored }
        guard !session.isReadOnlyToken else { return .rejected(AccountActionCopy.readOnly.text) }
        return await deliver(request, groupID: groupID, session: session)
    }
    /// 4.4 加入 k 个账号: in the order picked, without priorities. A refusal comes back without a receipt (the picker shows it);
    /// a refusal of its 重试 gets one, the picker being closed by then.
    @discardableResult func add(_ accounts: [UpstreamAccount], to group: GroupMemberTarget) async -> GroupMemberSendResult {
        guard !isSubmitting, let session = writableSession(),
              let request = try? GroupMemberBatchRequest(add: accounts.map { GroupMemberAdd(accountID: $0.id) }) else { return .ignored }
        isSubmitting = true
        defer { isSubmitting = false }
        return await write(MemberWrite(request: request, kind: .add, group: group, accounts: Self.snapshots(accounts)), session: session)
    }
    /// 2.4 移出: “已移出「账号」”, with “ · 可用 x → y” when it was available, and 撤销 that adds it back with its old priority.
    @discardableResult func remove(_ account: UpstreamAccount, from group: GroupMemberTarget, wasAvailable: Bool) async -> GroupMemberSendResult {
        guard !busyAccounts.contains(account.id), let session = writableSession(),
              let request = try? GroupMemberBatchRequest(remove: [account.id]) else { return .ignored }
        let removal = MemberWrite(request: request, kind: .remove(name: account.name, wasAvailable: wasAvailable), group: group,
                                  accounts: Self.snapshots([account]))
        return await write(removal, session: session)
    }

    // MARK: - Writing

    /// One write and how its receipt reads: a retry repeats it, an undo is a new write of the reverse.
    private struct MemberWrite: Sendable {
        enum Kind: Sendable { case add, remove(name: String, wasAvailable: Bool), undo }
        let request: GroupMemberBatchRequest
        let kind: Kind
        let group: GroupMemberTarget
        let accounts: [Int: GroupBatchAccount]
    }

    private func writableSession() -> GroupMemberWriteSession? {
        guard let session = source.groupMemberWriteSession else { return nil }
        guard !session.isReadOnlyToken else { show(AccountActionCopy.readOnly.text, systemImage: "exclamationmark.triangle", tone: .critical); return nil }
        return session
    }
    /// `fromReceipt`: sent by a receipt's button, when the picker that shows an add's refusal is gone.
    private func write(_ write: MemberWrite, session: GroupMemberWriteSession, fromReceipt: Bool = false) async -> GroupMemberSendResult {
        let ids = Set(write.request.accountIDs)
        busyAccounts.formUnion(ids)
        defer { busyAccounts.subtract(ids) }
        let sent = await deliver(write.request, groupID: write.group.id, session: session)
        report(sent, of: write, session: session, fromReceipt: fromReceipt)
        return sent
    }
    /// A receipt's button, in the session it belongs to; the accounts are busy from the tap. The receipt holds the writer, so the
    /// button still works after the page that made it has closed.
    private func relaunch(_ next: MemberWrite, session: GroupMemberWriteSession) {
        busyAccounts.formUnion(next.request.accountIDs)
        Task { _ = await self.write(next, session: session, fromReceipt: true) }
    }
    /// The batch, or the fallback; GROUP_REPOSITORY_UNSUPPORTED switches once and is remembered, except in simple mode.
    private func deliver(_ request: GroupMemberBatchRequest, groupID: Int, session: GroupMemberWriteSession) async -> GroupMemberSendResult {
        fellBackToLegacy = false
        do {
            var usedLegacy = !session.usesBatch
            let result: GroupMemberBatchResult
            if session.usesBatch {
                do { result = try await source.sendGroupMemberBatch(groupID: groupID, request, generation: session.generation) }
                catch where GroupMembersLegacyExecutor.isFallbackTrigger(error) {
                    guard isCurrent(session) else { return .ignored }
                    source.noteMemberBatchUnsupported()
                    guard session.allowsLegacy else { return .rejected(Self.unsupported) }
                    fellBackToLegacy = true; usedLegacy = true
                    result = try await source.sendGroupMembersLegacy(groupID: groupID, request, generation: session.generation)
                }
            } else {
                guard session.allowsLegacy else { return .rejected(Self.unsupported) }
                result = try await source.sendGroupMembersLegacy(groupID: groupID, request, generation: session.generation)
            }
            guard isCurrent(session) else { return .ignored }
            source.memberWriteFinished(GroupMemberChange(groupID: groupID, counts: result.counts))
            return .result(result, usedLegacy: usedLegacy)
        } catch {
            guard isCurrent(session) else { return .ignored }
            return failed(error, groupID: groupID)
        }
    }
    private func failed(_ error: any Error, groupID: Int) -> GroupMemberSendResult {
        if error is CancellationError { return .ignored }
        if let api = error as? APIError {
            let copy = GroupErrorCopy.resolve(api, context: .members)
            if copy.action == .treatAsDeleted {
                source.groupWentAway(id: groupID)
                return .groupGone(copy.message)
            }
            if copy.logs { Self.logRejected(api) }
        }
        guard !AccountWriteMark.mayHaveApplied(error) else {
            source.memberWriteFinished(GroupMemberChange(groupID: groupID, counts: nil))
            return .unconfirmed
        }
        return .rejected(GroupErrorCopy.message(for: error, context: .members))
    }
    private func isCurrent(_ session: GroupMemberWriteSession) -> Bool { source.groupMemberWriteSession?.generation == session.generation }

    // MARK: - Receipts

    private func report(_ sent: GroupMemberSendResult, of write: MemberWrite, session: GroupMemberWriteSession, fromReceipt: Bool) {
        switch sent {
        case .result(let result, _): reportResult(result, of: write, session: session)
        case .unconfirmed:
            let copy = GroupMemberReceipt.unconfirmed
            show(copy.text, systemImage: copy.systemImage, tone: copy.tone,
                 action: ReceiptAction(title: GroupReceiptButton.retry.title) { self.relaunch(write, session: session) })
        case .groupGone(let text): show(text, systemImage: "xmark.octagon", tone: .critical)
        case .rejected(let text):
            switch write.kind {
            case .add: if fromReceipt { show(text, systemImage: "exclamationmark.triangle", tone: .critical) }
            case .remove: show(text, systemImage: "exclamationmark.triangle", tone: .critical)
            case .undo: show(AccountActionCopy.failureText(.undo, reason: text), systemImage: "exclamationmark.triangle", tone: .critical)
            }
        case .ignored: break
        }
    }
    private func reportResult(_ result: GroupMemberBatchResult, of write: MemberWrite, session: GroupMemberWriteSession) {
        let receipt: GroupMemberReceipt
        switch write.kind {
        case .add: receipt = GroupMemberReceipt(result: result, activeBefore: write.group.activeBefore)
        case .remove(let name, let wasAvailable):
            receipt = GroupMemberReceipt.removal(accountName: name, result: result, wasAvailable: wasAvailable, activeBefore: write.group.activeBefore)
        case .undo:
            guard result.failed > 0 else { return }
            receipt = GroupMemberReceipt(result: result, activeBefore: nil)
        }
        show(receipt.text, systemImage: receipt.systemImage, tone: receipt.tone, action: action(receipt.button, result: result, of: write, session: session))
    }
    private func action(_ button: GroupMemberReceipt.Button?, result: GroupMemberBatchResult, of write: MemberWrite,
                        session: GroupMemberWriteSession) -> ReceiptAction? {
        switch button {
        case .undo?:
            guard let reverse = GroupMemberBatchRequest.inverse(of: result) else { return nil }
            let undo = MemberWrite(request: reverse, kind: .undo, group: write.group, accounts: write.accounts)
            return ReceiptAction(title: GroupReceiptButton.undo.title) { self.relaunch(undo, session: session) }
        case .details?:
            let outcome = GroupBatchOutcome(groupID: write.group.id, groupName: write.group.name, request: write.request, result: result,
                                            accounts: write.accounts)
            let open = openResults
            return ReceiptAction(title: GroupReceiptButton.view.title) { open(outcome) }
        case .retry?: return ReceiptAction(title: GroupReceiptButton.retry.title) { self.relaunch(write, session: session) }
        case nil: return nil
        }
    }
    private func show(_ text: String, systemImage: String, tone: Tone, action: ReceiptAction? = nil) {
        receipts.show(Receipt(text: text, systemImage: systemImage, tone: tone, action: action))
    }

    /// 0.8's words for GROUP_REPOSITORY_UNSUPPORTED, when the fallback may not run.
    private static let unsupported = GroupErrorCopy.resolve(.server(status: 500, reason: GroupMemberReason.repositoryUnsupported), context: .members).message
    private static func snapshots(_ accounts: [UpstreamAccount]) -> [Int: GroupBatchAccount] {
        Dictionary(accounts.map { ($0.id, GroupBatchAccount($0)) }, uniquingKeysWith: { first, _ in first })
    }
    /// 50 §0.8: member parameters the App should never have sent; only the status, reason and request ID (00 §3.4).
    private static func logRejected(_ error: APIError) {
        let requestID = String((error.requestID ?? "-").prefix(64))
        log.error("POST admin/groups/:id/accounts/batch \(error.statusCode ?? 0, privacy: .public) \(error.reason ?? "-", privacy: .public) \(requestID, privacy: .public)")
    }
}
