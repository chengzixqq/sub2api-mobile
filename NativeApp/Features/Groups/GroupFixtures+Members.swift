import Foundation
import Sub2Core

/// 50 §0.4 `-ui-testing` (S5-08, X44): the member batch on the session's demo accounts, by the backend's rules — a missing account
/// fails ACCOUNT_NOT_FOUND, a member added again or a non-member removed is `unchanged`, an unconfirmed Anthropic / Antigravity mix
/// fails MIXED_CHANNEL_RISK, an add takes priority 50 unless it names one and a removal answers the default 50 back. Memberships
/// live in each account's `group_ids` (AccountDemoStore.setGroupIDs), so the account tab names the same groups; the counts are the
/// group list's, counted after the write.
extension GroupFixtures {
    enum MemberArgument {
        /// S5D2a-12, only the adds of a request without `confirm_mixed_channel_risk`: with two or more, the highest id fails
        /// ACCOUNT_NOT_FOUND; among the other adds the lowest Anthropic or Antigravity id fails MIXED_CHANNEL_RISK (current: its
        /// platform's display name, other: the other one); the rest go in. Removals are untouched.
        static let batchPartial = "-ui-group-batch-partial"
        /// Every member write, batch or fallback, is lost on the way: nothing changes.
        static let batchOffline = "-ui-group-batch-offline"
        /// The server lists `groups.member_batch` but its repository answers 500 GROUP_REPOSITORY_UNSUPPORTED: the writer switches
        /// to the 0.4.4 fallback for the session.
        static let legacy = "-ui-group-legacy"
    }
    private static let defaultPriority = 50

    /// `POST admin/groups/:id/accounts/batch`, or with `legacy` the fallback's result (no counts, no priorities).
    func memberBatch(groupID: Int, _ request: GroupMemberBatchRequest, store: AccountDemoStore, now: Date, legacy: Bool,
                     arguments: [String] = ProcessInfo.processInfo.arguments) throws -> GroupMemberBatchResult {
        if arguments.contains(MemberArgument.batchOffline) { throw APIError(kind: .transport, message: "网络连接已中断") }
        if !legacy, arguments.contains(MemberArgument.legacy) { throw APIError.server(status: 500, reason: GroupMemberReason.repositoryUnsupported) }
        guard let group = groups.first(where: { $0.id == groupID }) else { throw APIError.server(status: 404, reason: "GROUP_NOT_FOUND") }
        let refused = arguments.contains(MemberArgument.batchPartial) && !request.confirmMixedChannelRisk
            ? Self.partialFailures(request.add.map(\.accountID), store: store) : [:]
        let adds = request.add.map { add in
            refused[add.accountID] ?? join(add, groupID: groupID, confirm: request.confirmMixedChannelRisk, store: store, arguments: arguments)
        }
        let removals = request.remove.map { leave($0, groupID: groupID, store: store) }
        let results = (adds + removals).map { legacy ? Self.withoutPriority($0) : $0 }
        return GroupMemberBatchResult(groupID: groupID, results: results, counts: legacy ? nil : counted(group, accounts: store.accounts, now: now).counts)
    }

    private func join(_ add: GroupMemberAdd, groupID: Int, confirm: Bool, store: AccountDemoStore, arguments: [String]) -> GroupMemberResultItem {
        guard let account = store.account(id: add.accountID) else { return Self.failed(add.accountID, .add, GroupMemberReason.accountNotFound) }
        guard !account.groupIDs.contains(groupID) else { return GroupMemberResultItem(accountID: account.id, action: .add, status: .unchanged) }
        let check = store.mixedChannelCheck(platform: account.platform, groupIDs: [groupID], accountID: account.id, arguments: arguments)
        if !confirm, check.hasRisk {
            let details = check.details.map { GroupMemberMixedChannel(currentPlatform: $0.currentPlatform, otherPlatform: $0.otherPlatform) }
            return Self.failed(account.id, .add, GroupMemberReason.mixedChannelRisk, details: details)
        }
        _ = try? store.setGroupIDs(accountID: account.id, account.groupIDs + [groupID])
        return GroupMemberResultItem(accountID: account.id, action: .add, status: .added, priority: add.priority ?? Self.defaultPriority)
    }
    private func leave(_ accountID: Int, groupID: Int, store: AccountDemoStore) -> GroupMemberResultItem {
        guard let account = store.account(id: accountID) else { return Self.failed(accountID, .remove, GroupMemberReason.accountNotFound) }
        guard account.groupIDs.contains(groupID) else { return GroupMemberResultItem(accountID: accountID, action: .remove, status: .unchanged) }
        _ = try? store.setGroupIDs(accountID: accountID, account.groupIDs.filter { $0 != groupID })
        return GroupMemberResultItem(accountID: accountID, action: .remove, status: .removed, priority: Self.defaultPriority)
    }

    /// `-ui-group-batch-partial`'s failures by account id.
    private static func partialFailures(_ ids: [Int], store: AccountDemoStore) -> [Int: GroupMemberResultItem] {
        guard ids.count >= 2, let missing = ids.max() else { return [:] }
        var failures = [missing: failed(missing, .add, GroupMemberReason.accountNotFound)]
        let mixable = ids.filter { $0 != missing }.compactMap(store.account(id:)).filter { ["anthropic", "antigravity"].contains($0.platform) }
        if let first = mixable.min(by: { $0.id < $1.id }) {
            let current = GroupPlatform.title(first.platform), other = first.platform == "anthropic" ? "Antigravity" : "Anthropic"
            failures[first.id] = failed(first.id, .add, GroupMemberReason.mixedChannelRisk,
                                        details: GroupMemberMixedChannel(currentPlatform: current, otherPlatform: other))
        }
        return failures
    }
    private static func failed(_ id: Int, _ action: GroupMemberAction, _ reason: String, details: GroupMemberMixedChannel? = nil) -> GroupMemberResultItem {
        GroupMemberResultItem(accountID: id, action: action, status: .failed, reason: reason, details: details)
    }
    private static func withoutPriority(_ item: GroupMemberResultItem) -> GroupMemberResultItem {
        GroupMemberResultItem(accountID: item.accountID, action: item.action, status: item.status, reason: item.reason, details: item.details)
    }
}
