import Foundation

/// 50 §0.4.4, without `groups.member_batch` or after a 500 GROUP_REPOSITORY_UNSUPPORTED: one account after another, read its
/// detail, add or drop this group locally and PUT only `group_ids` (S2-05's fullUpdate, X24). The result has the batch shape
/// without counts or priorities. The PUT writes the account row back from the read and renumbers its priority in every group.
/// Simple mode must not use it: the detail leaves composite groups out, so the PUT would unbind them (S5-08's writer refuses).
public struct GroupMembersLegacyExecutor: Sendable {
    /// Under the sheets (S5-08, S5-11) and the result page's buttons (S5-09).
    public static let notice = "服务器版本较旧：成员逐个提交，可能覆盖他人同时对这些账号的修改。"
    /// 0.8: only a 500 GROUP_REPOSITORY_UNSUPPORTED from the batch endpoint switches to the fallback.
    public static func isFallbackTrigger(_ error: any Error) -> Bool {
        guard let error = error as? APIError else { return false }
        return error.statusCode == 500 && error.reason == GroupMemberReason.repositoryUnsupported
    }
    public let client: APIClient
    /// `admin.idempotent_writes`: each PUT then carries a new key (00 §2.5.1; every body differs, R05).
    public let sendsIdempotencyKey: Bool
    private let makeKey: @Sendable () -> UUID
    public init(client: APIClient, sendsIdempotencyKey: Bool, makeKey: @escaping @Sendable () -> UUID = { UUID() }) {
        self.client = client; self.sendsIdempotencyKey = sendsIdempotencyKey; self.makeKey = makeKey
    }
    public func run(groupID: Int, _ request: GroupMemberBatchRequest) async throws -> GroupMemberBatchResult {
        try await client.legacyGroupMembers(groupID: groupID, request, makeKey: sendsIdempotencyKey ? makeKey : nil)
    }
}

public enum GroupMembersLegacyPlan {
    /// The detail's `group_ids` (by priority), else the ids of `groups` / `account_groups`, so no other group is cleared.
    public static func currentGroupIDs(of account: UpstreamAccount) -> [Int] {
        var seen = Set<Int>()
        let ids = account.groupIDs.isEmpty ? account.groups.map(\.id) : account.groupIDs
        return ids.filter { $0 > 0 && seen.insert($0).inserted }
    }
    /// Add: this group at the end; remove: without it; the others keep their order. nil when already so (unchanged, no PUT).
    public static func groupIDs(_ current: [Int], groupID: Int, action: GroupMemberAction) -> [Int]? {
        switch action {
        case .add: current.contains(groupID) ? nil : current + [groupID]
        case .remove: current.contains(groupID) ? current.filter { $0 != groupID } : nil
        }
    }
}

/// One account of the fallback: an answer for it, or the error that stops the run with the mark the account gets.
private enum LegacyMemberStep: Sendable {
    case done(GroupMemberResultItem)
    case stopped(any Error, reason: String)
}

extension APIClient {
    /// Every account is checked against the session it started in. A run that stops before any membership changed throws the
    /// error, as the first batch does; after a change it returns with the account marked and the rest not delivered.
    func legacyGroupMembers(groupID: Int, _ request: GroupMemberBatchRequest, makeKey: (@Sendable () -> UUID)?) async throws -> GroupMemberBatchResult {
        let groupID = try validID(groupID)
        let snapshot = currentGeneration()
        let keys = request.keys
        var results: [GroupMemberResultItem] = []
        for (index, key) in keys.enumerated() {
            try check(snapshot)
            switch try await legacyMember(key, groupID: groupID, confirm: request.confirmMixedChannelRisk, makeKey: makeKey, generation: snapshot) {
            case .done(let item):
                results.append(item)
            case .stopped(let error, let reason):
                guard results.contains(where: \.changedMembership) else { throw error }
                let rest = keys[(index + 1)...].map { GroupMemberResultItem.failed($0, reason: GroupMemberReason.notDelivered) }
                return GroupMemberBatchResult(groupID: groupID, results: results + [.failed(key, reason: reason)] + rest, counts: nil)
            }
        }
        return GroupMemberBatchResult(groupID: groupID, results: results, counts: nil)
    }

    /// GET, then PUT only when the membership changes. A missing account and a mixed-channel 409 are per-account answers. A read
    /// that going to the background cancelled (the same session, `suspend`) stops the run like a failed read.
    private func legacyMember(_ member: GroupMemberKey, groupID: Int, confirm: Bool, makeKey: (@Sendable () -> UUID)?,
                              generation snapshot: UUID) async throws -> LegacyMemberStep {
        let detail: UpstreamAccount
        do { detail = try await account(id: member.accountID) }
        catch let error as APIError where Self.isMissingAccount(error) { return .done(.failed(member, reason: GroupMemberReason.accountNotFound)) }
        catch let error where !(error is CancellationError) || (currentGeneration() == snapshot && !Task.isCancelled) {
            return .stopped(error, reason: GroupMemberRetry.unfinishedReason(error, mayHaveWritten: false))
        }
        let current = GroupMembersLegacyPlan.currentGroupIDs(of: detail)
        guard let next = GroupMembersLegacyPlan.groupIDs(current, groupID: groupID, action: member.action) else {
            return .done(GroupMemberResultItem(accountID: member.accountID, action: member.action, status: .unchanged))
        }
        do {
            _ = try await fullUpdate(id: member.accountID, patch: AccountPatchRequest(groupIDs: next, confirmMixedChannelRisk: confirm ? true : nil),
                                     base: nil, idempotencyKey: makeKey?())
            return .done(GroupMemberResultItem(accountID: member.accountID, action: member.action, status: member.action == .add ? .added : .removed))
        } catch let error as APIError where Self.isMissingAccount(error) {
            return .done(.failed(member, reason: GroupMemberReason.accountNotFound))
        } catch let error as APIError where AccountNewFlow.mayBeMixedChannelConflict(error) {
            if let item = await legacyMixedChannel(error, member: member, account: detail, groupIDs: next) { return .done(item) }
            return .stopped(error, reason: GroupMemberRetry.unfinishedReason(error, mayHaveWritten: true))
        } catch let error where !(error is CancellationError) {
            return .stopped(error, reason: GroupMemberRetry.unfinishedReason(error, mayHaveWritten: true))
        }
    }

    /// 20 §0.4-7: the 409's metadata, else check-mixed-channel (an older server's 409 has neither reason nor metadata). nil when
    /// neither names a risk and the 409 does not say MIXED_CHANNEL_WARNING.
    private func legacyMixedChannel(_ error: APIError, member: GroupMemberKey, account: UpstreamAccount, groupIDs: [Int]) async -> GroupMemberResultItem? {
        let warning: MixedChannelWarning?
        if let stated = MixedChannelWarning(error: error) { warning = stated }
        else { warning = (try? await checkMixedChannel(platform: account.platform, groupIDs: groupIDs, accountID: account.id)).flatMap(MixedChannelWarning.init(check:)) }
        guard warning != nil || error.reason == AccountWriteReason.mixedChannelWarning else { return nil }
        return .failed(member, reason: GroupMemberReason.mixedChannelRisk, details: warning.map(GroupMemberMixedChannel.init))
    }

    private static func isMissingAccount(_ error: APIError) -> Bool {
        error.statusCode == 404 && [AccountWriteReason.notFound, "RESOURCE_NOT_FOUND"].contains(error.reason ?? "")
    }
}
