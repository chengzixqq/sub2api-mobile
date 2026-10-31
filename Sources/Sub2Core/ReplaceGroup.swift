import Foundation

// 30 §8.3–§8.4 替换分组 (S3-15): POST admin/users/:id/replace-group (E04), its exact undo (§0.6 for an older reply), the read
// back of a result nobody saw, the failures by reason and the words. The page is ReplaceGroupSheet / ReplaceGroupFlow.

/// The body. `key_ids` goes only when given and is never empty (an empty list moves every key of the old group, which an undo
/// must not do); `keep_old_group_access` only when true.
public struct ReplaceGroupRequest: Encodable, Sendable, Equatable {
    public let oldGroupID: Int
    public let newGroupID: Int
    /// De-duplicated, in order.
    public let keyIDs: [Int]?
    public let keepOldGroupAccess: Bool

    public init(oldGroupID: Int, newGroupID: Int, keyIDs: [Int]? = nil, keepOldGroupAccess: Bool = false) throws {
        var seen = Set<Int>()
        let ids = keyIDs.map { $0.filter { seen.insert($0).inserted } }
        guard oldGroupID > 0, newGroupID > 0, oldGroupID != newGroupID, ids.map({ !$0.isEmpty && $0.allSatisfy { $0 > 0 } }) ?? true else {
            throw APIError(kind: .validation, message: "替换分组的参数无效。")
        }
        self.oldGroupID = oldGroupID; self.newGroupID = newGroupID; self.keyIDs = ids; self.keepOldGroupAccess = keepOldGroupAccess
    }
    enum CodingKeys: String, CodingKey {
        case oldGroupID = "old_group_id", newGroupID = "new_group_id", keyIDs = "key_ids", keepOldGroupAccess = "keep_old_group_access"
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(oldGroupID, forKey: .oldGroupID)
        try c.encode(newGroupID, forKey: .newGroupID)
        try c.encodeIfPresent(keyIDs, forKey: .keyIDs)
        if keepOldGroupAccess { try c.encode(true, forKey: .keepOldGroupAccess) }
    }
    public func requestBody() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(self)
    }
}

/// `{migrated_keys, migrated_key_ids, new_group_newly_granted}`; a server before E04 answers only `migrated_keys`.
public struct ReplaceGroupResult: Decodable, Sendable, Equatable {
    public let migratedKeys: Int
    public let migratedKeyIDs: [Int]?
    public let newGroupNewlyGranted: Bool?
    public init(migratedKeys: Int, migratedKeyIDs: [Int]?, newGroupNewlyGranted: Bool?) {
        self.migratedKeys = migratedKeys; self.migratedKeyIDs = migratedKeyIDs; self.newGroupNewlyGranted = newGroupNewlyGranted
    }
    enum CodingKeys: String, CodingKey {
        case migratedKeys = "migrated_keys", migratedKeyIDs = "migrated_key_ids", newGroupNewlyGranted = "new_group_newly_granted"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(migratedKeys: (try? c.decodeIfPresent(Int.self, forKey: .migratedKeys)) ?? 0,
                  migratedKeyIDs: try? c.decodeIfPresent([Int].self, forKey: .migratedKeyIDs),
                  newGroupNewlyGranted: try? c.decodeIfPresent(Bool.self, forKey: .newGroupNewlyGranted))
    }
    public var isLegacy: Bool { migratedKeyIDs == nil || newGroupNewlyGranted == nil }
    /// An older reply: granted when the user did not have the group before.
    public func newlyGranted(target: Int, before: ReplaceGroupSnapshot) -> Bool { newGroupNewlyGranted ?? !before.allowedGroups.contains(target) }
    /// An older reply moved every live key of the old group.
    public func movedKeyIDs(before: ReplaceGroupSnapshot) -> [Int] { migratedKeyIDs ?? before.keyIDsInSource.sorted() }
}

/// 30 §8.3: the section's rows and the sheet's choices, from the session's directory (X11; active standard groups only).
public enum ReplaceGroupTargets {
    /// The exclusive groups the user has (the base), in directory order.
    public static func sources(baseline: UserBaseline, catalog: UserGroupCatalog) -> [AdminGroup] {
        catalog.exclusive.filter { baseline.allowedGroups.contains($0.id) }
    }
    /// Exclusive groups the user neither has nor has added in the draft.
    public static func options(source: Int, baseline: UserBaseline, draft: UserAccessDraft, catalog: UserGroupCatalog) -> [AdminGroup] {
        catalog.exclusive.filter { $0.id != source && !baseline.allowedGroups.contains($0.id) && !draft.exclusiveGroupIDs.contains($0.id) }
    }
}

/// What the page knew at the confirmation: the grant and the live keys of both groups.
public struct ReplaceGroupSnapshot: Sendable, Equatable {
    public let allowedGroups: Set<Int>
    public let keyIDsInSource: Set<Int>
    public let keyIDsInTarget: Set<Int>
    public init(allowedGroups: Set<Int>, keys: [AdminAPIKey], source: Int, target: Int) {
        let live = keys.filter { !$0.isTombstone }
        self.allowedGroups = allowedGroups
        keyIDsInSource = Set(live.filter { $0.groupID == source }.map(\.id))
        keyIDsInTarget = Set(live.filter { $0.groupID == target }.map(\.id))
    }
}

/// 30 §8.4 撤销.
public enum ReplaceGroupUndo: Sendable, Equatable {
    /// replace-group back (new → old) with exactly the moved keys.
    case reverse(ReplaceGroupRequest)
    /// Nothing moved: GET the user, then PUT allowed_groups with the old group back (and the new one out when it was granted).
    case restoreAllowedGroups(restoring: Int, revoking: Int?)

    /// nil: no 撤销 (an older reply where the user already had the new group or it already had keys, §0.6).
    public static func plan(_ sent: ReplaceGroupRequest, result: ReplaceGroupResult, before: ReplaceGroupSnapshot) -> ReplaceGroupUndo? {
        let (old, new) = (sent.oldGroupID, sent.newGroupID)
        if let ids = result.migratedKeyIDs, let newly = result.newGroupNewlyGranted {
            guard !ids.isEmpty else { return .restoreAllowedGroups(restoring: old, revoking: newly ? new : nil) }
            return (try? ReplaceGroupRequest(oldGroupID: new, newGroupID: old, keyIDs: ids, keepOldGroupAccess: !newly)).map(ReplaceGroupUndo.reverse)
        }
        guard !before.allowedGroups.contains(new), before.keyIDsInTarget.isEmpty else { return nil }
        return (try? ReplaceGroupRequest(oldGroupID: new, newGroupID: old)).map(ReplaceGroupUndo.reverse)
    }
    /// The fresh list with `restoring` in and `revoking` out, ascending; nil when that changes nothing (nothing is sent).
    public static func allowedGroups(current: [Int]?, restoring: Int, revoking: Int?) -> [Int]? {
        let before = Set(current ?? [])
        var next = before
        next.insert(restoring)
        if let revoking { next.remove(revoking) }
        return next == before ? nil : next.sorted()
    }
    /// What the replace did to the grant; its undo passes the same value (UserEditorModel.undoImmediate reverses it).
    public static func groupsChange(sent: ReplaceGroupRequest, newlyGranted: Bool) -> UserGroupsChange {
        UserGroupsChange(granted: newlyGranted ? [sent.newGroupID] : [], revoked: [sent.oldGroupID])
    }
}

/// A replace nobody saw the end of, read back from the user and the key list. The server does it in one transaction.
public enum ReplaceGroupReadback: Sendable, Equatable {
    case applied(ReplaceGroupResult)
    case notApplied
    case unclear

    public static func outcome(_ sent: ReplaceGroupRequest, before: ReplaceGroupSnapshot, user: AdminUser, keys: [AdminAPIKey]) -> ReplaceGroupReadback {
        let allowed = Set(user.allowedGroups ?? [])
        let groupOf = Dictionary(keys.filter { !$0.isTombstone }.map { ($0.id, $0.groupID) }, uniquingKeysWith: { first, _ in first })
        if !allowed.contains(sent.oldGroupID) && allowed.contains(sent.newGroupID) {
            let moved = before.keyIDsInSource.filter { groupOf[$0] == sent.newGroupID }.sorted()
            return .applied(ReplaceGroupResult(migratedKeys: moved.count, migratedKeyIDs: moved,
                                               newGroupNewlyGranted: !before.allowedGroups.contains(sent.newGroupID)))
        }
        if allowed.contains(sent.oldGroupID), before.keyIDsInSource.allSatisfy({ groupOf[$0] == sent.oldGroupID }) { return .notApplied }
        return .unclear
    }
}

/// 30 §8.4 errors, by reason and never the server's message (00 §3.4).
public enum ReplaceGroupFailure: Sendable, Equatable {
    public enum Phase: Sendable { case replace, undo }
    /// SAME_GROUP, GROUP_NOT_EXCLUSIVE, GROUP_IS_SUBSCRIPTION, GROUP_NOT_ACTIVE: the directory is read again, the sheet stays.
    case pickAgain(String)
    /// 404 GROUP_NOT_FOUND: the directory is read again.
    case groupMissing
    /// The undo's GROUP_NOT_ACTIVE: the old group was disabled meanwhile.
    case sourceInactive
    /// The undo's KEY_NOT_IN_GROUP: a moved key was changed meanwhile; the keys are read again.
    case keysMoved
    case userGone
    case readOnly
    /// Still unknown after the executor's retries (R04): read back.
    case unconfirmed
    /// The number cannot be used again; the next confirmation makes a new one.
    case newKey(String)
    /// Catalog text.
    case other(String)

    /// nil for a cancelled call or a security prompt the administrator cancelled.
    public init?(_ error: any Error, phase: Phase) {
        if error is CancellationError { return nil }
        if let failure = error as? KeyedWriteFailure {
            if case .needsNewKey = failure.disposition { self = .newKey(failure.localizedDescription) } else { self = .unconfirmed }
            return
        }
        guard let api = error as? APIError else { self = .other(error.localizedDescription); return }
        if api.securityOutcome == .cancelled { return nil }
        if let known = Self.refusal(api, phase: phase) { self = known; return }
        if api.reason == "ACCESS_TOKEN_READ_ONLY" || api.kind == .readOnly { self = .readOnly; return }
        guard let status = api.statusCode else {
            self = api.kind == .transport || api == .invalidResponse ? .unconfirmed : .other(api.localizedDescription)
            return
        }
        self = RequestPolicy.isRetryableStatus(status, marker: api.reason) ? .unconfirmed : .other(api.localizedDescription)
    }
    public var message: String {
        switch self {
        case .pickAgain(let text), .newKey(let text), .other(let text): text
        case .groupMissing: "分组不存在"
        case .sourceInactive: "原分组已停用，无法撤销"
        case .keysMoved: "有 Key 已不在原分组，无法精确撤销"
        case .userGone: UserEditCopy.userGone
        case .readOnly: UserEditCopy.readOnly
        case .unconfirmed: ReplaceGroupCopy.unconfirmed
        }
    }
    /// A failed undo's receipt: the two sentences of 30 §8.4 as they are, the rest after “撤销没有成功：”.
    public var undoReceipt: String {
        switch self {
        case .sourceInactive, .keysMoved: message
        default: ReplaceGroupCopy.undoFailed(message)
        }
    }

    private static func refusal(_ api: APIError, phase: Phase) -> ReplaceGroupFailure? {
        switch (api.statusCode, api.reason) {
        case (400?, "SAME_GROUP"?): .pickAgain("新旧分组不能相同")
        case (400?, "GROUP_NOT_EXCLUSIVE"?): .pickAgain("目标分组不是专属分组")
        case (400?, "GROUP_IS_SUBSCRIPTION"?): .pickAgain("订阅分组不能用于替换")
        case (400?, "GROUP_NOT_ACTIVE"?): phase == .undo ? .sourceInactive : .pickAgain("目标分组已停用")
        case (400?, "KEY_NOT_IN_GROUP"?): .keysMoved
        case (404?, "GROUP_NOT_FOUND"?): .groupMissing
        case (404?, "USER_NOT_FOUND"?): .userGone
        default: nil
        }
    }
}

/// 30 §8.3–§8.4 and design UeReplaceSec / UeReplaceSheet.
public enum ReplaceGroupCopy {
    public static let sectionTitle = "替换分组"
    /// The group sheet's removal confirmation (30 §6.3).
    public static let useReplace = "改用替换分组"
    public static func rowTitle(_ group: String) -> String { "替换「\(group)」…" }
    public static func rowSubtitle(keys: Int) -> String { "绑定 \(DisplayFormat.grouped(keys)) 个 Key" }
    public static let footnote = "把一个专属分组换成另一个：绑定的 Key 一起迁移，旧分组的权限随之移除。"
    public static let sheetTitle = "替换专属分组"
    public static func sheetNote(source: String, keys: Int) -> String {
        "选择新分组替换「\(source)」，将自动迁移绑定的 \(DisplayFormat.grouped(keys)) 个 Key 并更新分组权限。"
    }
    /// “OpenAI · 专属分组 · 默认倍率 ×1”, the App's one rate format (S3D1-21).
    public static func optionSubtitle(_ group: AdminGroup, platformName: String) -> String {
        platformName + " · 专属分组 · 默认倍率 " + UserEditCopy.rateText(group.rateMultiplier)
    }
    public static let empty = "没有其他可用的专属分组"
    public static func submit(target: String?) -> String { target.map { "替换为「\($0)」" } ?? "选择目标分组" }
    public static func confirmTitle(source: String, target: String) -> String { "把「\(source)」替换为「\(target)」？" }
    public static func confirmMessage(user: String, source: String, target: String, keys: Int) -> String {
        "\(user)绑定在「\(source)」的 \(DisplayFormat.grouped(keys)) 个 Key 会迁移到「\(target)」，并移除「\(source)」的使用权限。立即生效，不经过“保存”。"
    }
    public static let confirm = "确认替换"
    public static func receipt(migrated: Int) -> String { "分组替换成功，已迁移 \(DisplayFormat.grouped(migrated)) 个 Key" }
    /// Named in the edit page's leave confirmation.
    public static func appliedName(source: String, target: String) -> String { "替换分组（\(source) → \(target)）" }
    public static let readbackApplied = "分组替换已生效"
    public static let unconfirmed = "结果未确认，请刷新后检查"
    public static func undoFailed(_ message: String) -> String { "撤销没有成功：" + message }
}

extension AdminAPIKey {
    /// The same key bound to another group: the card after a replace, before the list is read again.
    public func movedToGroup(_ groupID: Int) -> AdminAPIKey {
        AdminAPIKey(id: id, userID: userID, keyMasked: keyMasked, name: name, groupID: groupID, status: status, effectiveStatus: effectiveStatus,
                    ipWhitelist: ipWhitelist, ipBlacklist: ipBlacklist, lastUsedAt: lastUsedAt, lastUsedIP: lastUsedIP, quota: quota,
                    quotaUsed: quotaUsed, expiresAt: expiresAt, currentConcurrency: currentConcurrency, rateLimit5h: rateLimit5h,
                    rateLimit1d: rateLimit1d, rateLimit7d: rateLimit7d, usage5h: usage5h, usage1d: usage1d, usage7d: usage7d, reset5hAt: reset5hAt,
                    reset1dAt: reset1dAt, reset7dAt: reset7dAt, createdAt: createdAt, updatedAt: updatedAt, user: user)
    }
}

extension APIClient {
    /// 30 §8.4 (E04): with an Idempotency-Key made at the confirmation (R05); the executor resends the same bytes (R04). No
    /// capability is needed: a server before E04 ignores the key and answers only `migrated_keys`.
    public func replaceUserGroup(userID: Int, _ change: ReplaceGroupRequest, idempotencyKey: UUID,
                                 onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<ReplaceGroupResult> {
        let path = "admin/users/\(try validID(userID))/replace-group"
        return try await performKeyedWrite(KeyedWriteRequest(path: path, method: "POST", body: try change.requestBody(), key: idempotencyKey),
                                           onEvent: onEvent)
    }
}
