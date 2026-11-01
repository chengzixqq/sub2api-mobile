import Foundation
import Sub2Core

/// 50 §0.5 `-ui-testing` (S5-05, X44): what the group actions read and write in the session's fixtures — each group's keys and
/// subscriptions, copying with the backend's names and memberships, deleting with its memberships, and a lost first write.
extension GroupFixtures {
    /// The first write to each group in the session is lost: nothing changes, a keyed write ends unconfirmed and an unkeyed one
    /// in a transport failure. Later writes, under the same number or a new one, go through.
    static let writeTimeout = "-ui-group-write-timeout"

    /// The design's DEMO.groups apiKeys / subscriptions, the one source of every group's key and subscription counts (S5-06,
    /// S5-12). 高级组 has 2 disabled keys, so its active count tells U39's two figures apart; new groups and copies have none.
    static func stats(groupID: Int) -> GroupStats {
        let keys = [1: 38, 2: 64, 3: 21, 4: 6, 5: 14, 6: 3, 7: 9, 8: 7, 9: 2][groupID] ?? 0
        let subscriptions = groupID == 4 ? (total: 15, active: 12) : (total: 0, active: 0)
        return GroupStats(totalAPIKeys: keys, activeAPIKeys: groupID == 1 ? keys - 2 : keys, subscriptionsTotal: subscriptions.total,
                          subscriptionsActive: subscriptions.active)
    }
    /// What the fixture server answers to groups/:id/stats: nil, as an older server without F02, when `groups.account_buckets`
    /// is withheld.
    static func servedStats(groupID: Int, arguments: [String] = ProcessInfo.processInfo.arguments) -> GroupStats? {
        UITestArguments.withheldCapabilities(arguments: arguments).contains(Capability.groupsAccountBuckets.rawValue) ? nil : stats(groupID: groupID)
    }

    /// `-ui-group-write-timeout`: throws for the first write to the operation's group in this session.
    func interruptFirstWrite(_ operation: GroupWriteOperation, arguments: [String] = ProcessInfo.processInfo.arguments) throws {
        guard arguments.contains(Self.writeTimeout) else { return }
        let target: Int = switch operation.kind {
        case .create: 0
        case .update(let id), .delete(let id), .duplicate(let id): id
        }
        let key = ObjectIdentifier(self)
        guard !Self.interrupted[key, default: []].contains(target) else { return }
        Self.interrupted[key, default: []].insert(target)
        guard operation.sendsIdempotencyKey else { throw APIError(kind: .transport, message: "网络连接已中断") }
        throw KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: operation.key, actionID: nil, lastError: nil)
    }
    /// `POST admin/groups/:id/duplicate`: an inactive copy named as the backend does, with the source's members.
    func duplicateGroup(sourceID: Int, accounts: AccountDemoStore, now: Date) throws -> AdminGroup {
        guard let source = groups.first(where: { $0.id == sourceID }) else { throw APIError.server(status: 404, reason: "GROUP_NOT_FOUND") }
        let id = (groups.map(\.id).max() ?? 0) + 1
        let copy = Self.copy(of: source, id: id, name: Self.duplicateName(of: source.name, existing: Set(groups.map(\.name))))
        groups.append(copy)
        for var account in accounts.accounts where account.groupIDs.contains(sourceID) {
            account.groupIDs.append(id)
            account.groups.append(UpstreamAccount.Group(id: id, name: copy.name))
            accounts.replace(account)
        }
        return counted(copy, accounts: accounts.accounts, now: now)
    }
    /// `DELETE admin/groups/:id`: the group and its memberships (account_groups) go; a group already gone reads as such.
    func deleteGroup(id: Int, accounts: AccountDemoStore) -> GroupDeleteResult {
        guard groups.contains(where: { $0.id == id }) else { return .alreadyGone }
        removeGroup(id: id)
        for var account in accounts.accounts where account.groupIDs.contains(id) {
            account.groupIDs.removeAll { $0 == id }
            account.groups.removeAll { $0.id == id }
            accounts.replace(account)
        }
        return .deleted
    }
    /// The backend's duplicateGroupName: the trimmed name plus “ (Copy)”, then “ (Copy 2)”, “ (Copy 3)”… while taken, the
    /// name cut so the whole stays within 100 characters (runes).
    static func duplicateName(of source: String, existing: Set<String>) -> String {
        let base = source.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
        for number in 1... {
            let suffix = number == 1 ? " (Copy)" : " (Copy \(number))"
            var kept = String.UnicodeScalarView()
            kept.append(contentsOf: base.prefix(max(0, 100 - suffix.unicodeScalars.count)))
            let name = String(kept) + suffix
            if !existing.contains(name) { return name }
        }
        return source
    }

    private static var interrupted: [ObjectIdentifier: Set<Int>] = [:]
    private static func copy(of group: AdminGroup, id: Int, name: String) -> AdminGroup {
        AdminGroup(id: id, name: name, description: group.description, platform: group.platform, status: "inactive", rateMultiplier: group.rateMultiplier,
                   isExclusive: group.isExclusive, subscriptionType: group.subscriptionType, dailyLimitUSD: group.dailyLimitUSD,
                   weeklyLimitUSD: group.weeklyLimitUSD, monthlyLimitUSD: group.monthlyLimitUSD, rpmLimit: group.rpmLimit,
                   billingLocked: group.billingLocked, sortOrder: id, claudeCodeOnly: group.claudeCodeOnly, fallbackGroupID: group.fallbackGroupID)
    }
}
