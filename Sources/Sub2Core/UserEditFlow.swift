import Foundation

// 30 §6 (S3-11): the edit user page's rules. Its words are the extension of UserEditCopy in UserEditCopy+Edit.swift.

/// 30 §6.4 steps 2–3: how the role moves between the base and the draft.
public enum UserRoleChange: Sendable, Equatable {
    case none, promote, demote, other

    public init(from: AdminUserRole?, to: AdminUserRole?) {
        if from == to { self = .none }
        else if to == .admin { self = .promote }
        else if from == .admin { self = .demote }
        else { self = .other }
    }
    /// U30: the server refuses to demote the last administrator with a 500 without reason, so the page asks first.
    public static func blocksDemotion(adminTotal: Int) -> Bool { adminTotal <= 1 }
}

/// One segment's marks (design UeSegBar): a dot for changes, a red “!” for issues.
public struct UserEditSegmentMark: Sendable, Equatable {
    public let section: UserDraftSection
    public let changed: Int
    public let issues: Int
    public var spokenLabel: String { section.spoken(issues: issues, changed: changed) }

    /// Both saved segments, in order; issues count only once the check has run.
    public static func marks(changed: [UserDraftField], issues: [UserDraftIssue], showsIssues: Bool) -> [UserEditSegmentMark] {
        UserDraftSection.allCases.map { section in
            UserEditSegmentMark(section: section, changed: changed.filter { $0.section == section }.count,
                                issues: showsIssues ? issues.filter { $0.field.section == section }.count : 0)
        }
    }
}

/// 30 §6.1 the line under the segments.
public enum UserEditStatusLine {
    /// “基础 已改 2 项 · 权限与并发 1 项要修改”; the idle hint when nothing is marked.
    public static func text(_ marks: [UserEditSegmentMark]) -> String {
        let parts = marks.compactMap { mark -> String? in
            let words = (mark.issues > 0 ? ["\(mark.issues) 项要修改"] : []) + (mark.changed > 0 ? ["已改 \(mark.changed) 项"] : [])
            return words.isEmpty ? nil : mark.section.title + " " + words.joined(separator: "、")
        }
        return parts.isEmpty ? UserEditCopy.idleHint : parts.joined(separator: " · ")
    }
}

/// 30 §6.4 step 6.
public enum UserEditSaveReceipt {
    /// Removed exclusive groups that still had keys bound to them.
    public struct Lost: Sendable, Equatable {
        public let groupNames: [String]
        public let keyCount: Int
        public init(groupNames: [String], keyCount: Int) { self.groupNames = groupNames; self.keyCount = keyCount }
    }
    /// “已保存 3 项更改”, with “；绑定在「Claude Code 组」的 2 个 Key 将无法调用” after a removal that strands keys.
    public static func text(changedCount: Int, lost: Lost?) -> String {
        let saved = "已保存 \(changedCount) 项更改"
        guard let lost else { return saved }
        let names = lost.groupNames.map { "「\($0)」" }.joined(separator: "、")
        return saved + "；绑定在\(names)的 \(DisplayFormat.grouped(lost.keyCount)) 个 Key 将无法调用"
    }
    /// nil when no live key is bound to a removed group.
    public static func lost(removedGroups: Set<Int>, keys: [AdminAPIKey], name: (Int) -> String) -> Lost? {
        let stranded = removedGroups.sorted().map { ($0, boundKeyCount(groupID: $0, keys: keys)) }.filter { $0.1 > 0 }
        guard !stranded.isEmpty else { return nil }
        return Lost(groupNames: stranded.map { name($0.0) }, keyCount: stranded.reduce(0) { $0 + $1.1 })
    }
    /// “绑定 N 个 Key”: deleted keys (tombstones) do not count.
    public static func boundKeyCount(groupID: Int, keys: [AdminAPIKey]) -> Int {
        keys.filter { $0.groupID == groupID && !$0.isTombstone }.count
    }
}

/// 30 §6.5: one failed save, classified. Never the server's message (00 §3.4).
public enum UserSaveFailure: Sendable, Equatable {
    case emailTaken, notFound, readOnly
    /// A security prompt cleared it: confirm again with the same number and bytes (00 §2.6.2).
    case reconfirm
    /// A step-up refusal: its notice, nil when the sheet was closed.
    case security(String?)
    /// The number cannot be used again; the next save makes a new one.
    case newKey(String)
    /// The result is unknown after the executor's own retries (R04): the page reads the user back.
    case unconfirmed
    /// 00 §2.5.3: not run; the same number waits until then.
    case storeUnavailable(Date?)
    /// A refusal; `reload` (400 / 500 without a reason) reads the user again.
    case rejected(String, reload: Bool)
    case cancelled

    public init(_ error: any Error) {
        if error is CancellationError { self = .cancelled }
        else if let failure = error as? KeyedWriteFailure { self = Self.classify(failure) }
        else if let api = error as? APIError { self = Self.classify(api) }
        else { self = .rejected(error.localizedDescription, reload: false) }
    }
    /// Whether the same draft sends the same number again.
    public var keepsOperation: Bool {
        switch self {
        case .reconfirm, .security, .storeUnavailable, .cancelled: true
        default: false
        }
    }
    /// The receipt; nil when the page says nothing (a closed sheet, a cancelled run).
    public var receipt: String? {
        switch self {
        case .emailTaken: UserEditCopy.emailTakenReceipt
        case .notFound: UserEditCopy.userGone
        case .readOnly: UserEditCopy.readOnly
        case .reconfirm, .cancelled: nil
        case .security(let text): text
        case .newKey(let text), .rejected(let text, _): text
        case .unconfirmed: UserEditCopy.unconfirmed
        case .storeUnavailable: UserCreateFailure.storeUnavailable
        }
    }

    private static func classify(_ failure: KeyedWriteFailure) -> UserSaveFailure {
        switch failure.disposition {
        case .needsNewKey(.keyConflict): .newKey("请求已变化，请重新提交")
        case .needsNewKey: .newKey(failure.localizedDescription)
        case .unconfirmed(.storeUnavailable, let notBefore): .storeUnavailable(notBefore)
        case .unconfirmed: .unconfirmed
        }
    }
    private static func classify(_ api: APIError) -> UserSaveFailure {
        if api.securityOutcome == .passed { return .reconfirm }
        if let known = refusal(api) { return known }
        guard let status = api.statusCode else {
            return api.kind == .transport || api == .invalidResponse ? .unconfirmed : .rejected(api.localizedDescription, reload: false)
        }
        switch (status, api.reason) {
        case (400, nil): return .rejected(api.localizedDescription, reload: true)
        case (500, nil): return .rejected(UserEditCopy.serverFailed, reload: true)
        default: break
        }
        if status >= 500, api.reason == nil || RequestPolicy.isRetryableStatus(status, marker: api.reason) { return .unconfirmed }
        return .rejected(api.localizedDescription, reload: false)
    }
    private static func refusal(_ api: APIError) -> UserSaveFailure? {
        if api.isUserNotFound { return .notFound }
        switch (api.statusCode, api.reason) {
        case (409?, "EMAIL_EXISTS"?): return .emailTaken
        case (_, "ACCESS_TOKEN_READ_ONLY"?): return .readOnly
        case (_, "STEP_UP_REQUIRED"?): return .security(nil)
        case (_, "STEP_UP_TOTP_NOT_ENABLED"?): return .security(StepUpPolicy.totpNotEnabledTitle)
        case (_, "STEP_UP_ADMIN_API_KEY_FORBIDDEN"?): return .security(StepUpPolicy.machineCredentialNotice)
        default: return api.kind == .readOnly ? .readOnly : nil
        }
    }
}

/// What an immediate write (a key's group change, a replaced group; S3-12, S3-15) did to the user's grant.
public struct UserGroupsChange: Sendable, Equatable {
    public let granted: Set<Int>
    public let revoked: Set<Int>
    public init(granted: Set<Int> = [], revoked: Set<Int> = []) { self.granted = granted; self.revoked = revoked }
    public var isEmpty: Bool { granted.isEmpty && revoked.isEmpty }
    /// Undoing it.
    public var reversed: UserGroupsChange { UserGroupsChange(granted: revoked, revoked: granted) }
}

/// 30 §6.6 (design `both()`): an immediate write moves the base and the draft together, so it never shows as an unsaved
/// change, and every other change in the draft stays. A group the draft had removed is not brought back.
public enum UserEditRebase {
    public static func apply(_ change: UserGroupsChange, baseline: UserBaseline, draft: UserAccessDraft,
                             catalog: UserGroupCatalog) -> (UserBaseline, UserAccessDraft) {
        let granted = change.granted.subtracting(baseline.allowedGroups)
        let revoked = change.revoked.intersection(baseline.allowedGroups)
        var base = baseline, next = draft
        base.allowedGroups = baseline.allowedGroups.union(granted).subtracting(revoked)
        next.exclusiveGroupIDs = draft.exclusiveGroupIDs.union(granted.intersection(catalog.exclusiveIDs)).subtracting(revoked)
        if draft.restrictPublicGroups {
            next.publicGroupIDs = draft.publicGroupIDs.union(granted.intersection(catalog.publicIDs)).subtracting(revoked)
        }
        return (base, next)
    }
}

/// 30 §6.4 step 7: the user PUT went through and its attributes did not, so the page stays and what was saved stops counting
/// as changed. The password and adjustment notes were spent. An exclusive group the save took away takes its rate out of the
/// draft as well: it was held only for “撤回”, and left there it would read as a new rate for a group the user no longer has.
public enum UserEditSettle {
    public static func apply(_ request: UserUpdateRequest, baseline: UserBaseline, draft: UserAccessDraft,
                             catalog: UserGroupCatalog) -> (UserBaseline, UserAccessDraft) {
        var next = draft
        next.password = ""
        next.adjustmentNotes = ""
        if let allowed = request.allowedGroups {
            for id in baseline.allowedGroups.intersection(catalog.exclusiveIDs).subtracting(allowed) { next.groupRates.removeValue(forKey: id) }
        }
        return (baseline.applying(request), next)
    }
}

/// 30 §6.4 / §6.6 and S3D1-11.
public enum UserEditPolicy {
    /// The RPM block reads again this often while it is on screen.
    public static let rpmRefreshInterval: Duration = .seconds(15)
    /// “保存” is pressable with a change, while nothing is being saved and no immediate write is out (S3D1-11). Issues do not
    /// grey it: pressing it is how they show.
    public static func canSave(hasChanges: Bool, saving: Bool, immediateInFlight: Int) -> Bool {
        hasChanges && !saving && immediateInFlight == 0
    }
}

extension UserBaseline {
    /// The base after a user PUT went through while its attributes did not (30 §6.4 step 7): the page stays, so what was
    /// saved stops counting as changed. A cleared rate is gone; password and adjustment notes are not part of the base.
    public func applying(_ request: UserUpdateRequest) -> UserBaseline {
        var next = self
        if let email = request.email { next.email = email }
        if let username = request.username { next.username = username }
        if let notes = request.notes { next.notes = notes }
        if let role = request.role { next.role = role }
        if let status = request.status { next.status = status }
        if let concurrency = request.concurrency { next.concurrency = concurrency }
        if let rpmLimit = request.rpmLimit { next.rpmLimit = rpmLimit }
        if let allowed = request.allowedGroups { next.allowedGroups = Set(allowed) }
        if let restrict = request.restrictPublicGroups { next.restrictPublicGroups = restrict }
        for (id, rate) in request.groupRates ?? [:] {
            if let rate { next.groupRates[id] = rate } else { next.groupRates.removeValue(forKey: id) }
        }
        return next
    }
}
