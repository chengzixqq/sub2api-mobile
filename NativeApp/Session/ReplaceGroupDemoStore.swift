import Foundation
import Sub2Core

/// S3-15 替换分组's `-ui-testing` launch arguments. The App sends `key_ids` only in an undo.
enum ReplaceGroupFixtureArgument {
    /// A replace answers 400 GROUP_NOT_ACTIVE.
    static let targetInactive = "-ui-replace-target-inactive"
    /// An undo (a replace with key_ids) answers 400 GROUP_NOT_ACTIVE.
    static let undoSourceInactive = "-ui-replace-undo-source-inactive"
    /// A replace goes through and its reply is lost.
    static let uncertain = "-ui-replace-uncertain"
    /// With `uncertain`: the first read back fails as a dropped network does.
    static let unread = "-ui-replace-unread"
    /// The user was granted the target on the Web after the page was read: the replace answers new_group_newly_granted false.
    static let targetGranted = "-ui-replace-target-granted"
}

/// S3-15: replace-group on the session's copies (S3D1-04), checked in admin_api_key_group_undo.go's order; a number seen before
/// answers its first result. Strict like S3-11's update fixture: with E04 the App never reverses a replace without key_ids, so
/// such a request is refused (400 without a reason).
@MainActor final class ReplaceGroupDemoStore {
    private static var stores: [UUID: ReplaceGroupDemoStore] = [:]
    private var results: [UUID: ReplaceGroupResult] = [:]
    /// [user, old, new] of the replaces without key_ids still standing (not reversed since).
    private var done: Set<[Int]> = []
    private var readBackFailed = false

    static func current(for generation: UUID) -> ReplaceGroupDemoStore {
        if let store = stores[generation] { return store }
        let store = ReplaceGroupDemoStore()
        stores[generation] = store
        return store
    }
    func result(for key: UUID) -> ReplaceGroupResult? { results[key] }
    /// `-ui-replace-unread`: true once, for the first read back.
    func failsReadBack(arguments: [String]) -> Bool {
        guard arguments.contains(ReplaceGroupFixtureArgument.unread), !readBackFailed else { return false }
        readBackFailed = true
        return true
    }

    /// The user after the write and the reply; no user is 404 USER_NOT_FOUND, after the group checks as on the server.
    func replace(_ change: ReplaceGroupRequest, user: AdminUser?, keys: UserKeyDemoStore, key: UUID,
                 arguments: [String]) throws -> (AdminUser, ReplaceGroupResult) {
        let refusedArgument = change.keyIDs == nil ? ReplaceGroupFixtureArgument.targetInactive : ReplaceGroupFixtureArgument.undoSourceInactive
        if arguments.contains(refusedArgument) { throw APIError.server(status: 400, reason: "GROUP_NOT_ACTIVE") }
        guard let group = DemoData.accountGroups.first(where: { $0.id == change.newGroupID }) else {
            throw APIError.server(status: 404, reason: "GROUP_NOT_FOUND")
        }
        guard group.status == "active" else { throw APIError.server(status: 400, reason: "GROUP_NOT_ACTIVE") }
        guard group.isExclusive == true else { throw APIError.server(status: 400, reason: "GROUP_NOT_EXCLUSIVE") }
        guard group.subscriptionType != "subscription" else { throw APIError.server(status: 400, reason: "GROUP_IS_SUBSCRIPTION") }
        guard var user else { throw APIError.server(status: 404, reason: "USER_NOT_FOUND") }
        let forward = [user.id, change.oldGroupID, change.newGroupID], reverse = [user.id, change.newGroupID, change.oldGroupID]
        if change.keyIDs == nil, done.contains(reverse) { throw APIError.server(status: 400, reason: nil) }
        let moved = try keys.migrate(userID: user.id, from: change.oldGroupID, to: change.newGroupID, only: change.keyIDs)
        var allowed = Set(user.allowedGroups ?? [])
        if change.keyIDs == nil, arguments.contains(ReplaceGroupFixtureArgument.targetGranted) { allowed.insert(change.newGroupID) }
        let newly = allowed.insert(change.newGroupID).inserted
        if !change.keepOldGroupAccess { allowed.remove(change.oldGroupID) }
        user.allowedGroups = allowed.sorted()
        done.remove(reverse)
        if change.keyIDs == nil { done.insert(forward) }
        let result = ReplaceGroupResult(migratedKeys: moved.count, migratedKeyIDs: moved, newGroupNewlyGranted: newly)
        results[key] = result
        return (user, result)
    }
}
