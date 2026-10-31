import Foundation
import Testing
@testable import Sub2Core

// S3-11: the edit user page's words and rules (30 §6, R04, R05, U30; S3D1-01, S3D1-11, S3D1-13, S3D1-18).

private func amount(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
private func group(_ id: Int, _ name: String, exclusive: Bool, rate: String = "0.8") -> AdminGroup {
    AdminGroup(id: id, name: name, platform: "anthropic", status: "active", rateMultiplier: Decimal(string: rate), isExclusive: exclusive,
               subscriptionType: "standard")
}
/// Exclusive 5 and 9, public 1 and 2.
private let catalog = UserGroupCatalog(groups: [group(1, "高级组", exclusive: false), group(2, "标准组", exclusive: false),
                                                group(5, "Claude Code 组", exclusive: true), group(9, "Codex 专线", exclusive: true, rate: "1.0")])
private func baseline(allowed: [Int] = [5], restrict: Bool = false, rates: [Int: Decimal]? = [5: amount("1.3")], role: String = "user") -> UserBaseline {
    UserBaseline(user: AdminUser(id: 3, email: "xm.wang@example.com", username: "王小明", status: "active", role: role, concurrency: 2, notes: "",
                                 rpmLimit: 0, allowedGroups: allowed, groupRates: rates, restrictPublicGroups: restrict))
}
private func key(_ id: Int, group: Int?, masked: String? = "sk-…0001") -> AdminAPIKey {
    AdminAPIKey(id: id, userID: 3, keyMasked: masked, name: "脚本", groupID: group)
}

// MARK: - 离开与升管理员

@Test func leaveMessage() {
    #expect(UserEditCopy.leaveTitle == "放弃未保存的更改？")
    #expect(UserEditCopy.leaveDiscard == "放弃更改")
    #expect(UserEditCopy.leaveMessage(changed: [.email, .concurrency], applied: []) == "邮箱、并发数还没保存，会被放弃。")
    #expect(UserEditCopy.leaveMessage(changed: [.notes], applied: ["Key「脚本」换分组", "余额"])
            == "备注还没保存，会被放弃。\n已经立即生效、不会撤回：Key「脚本」换分组、余额。")
}

@Test func promoteCopy() {
    #expect(UserEditCopy.promoteTitle(name: "王小明") == "把「王小明」设为管理员？")
    #expect(UserEditCopy.promoteMessage(changed: [.role, .concurrency], verified: true)
            == "二次验证已通过。管理员可以管理全部账号、用户和资金。\n同时保存：角色、并发数")
    #expect(UserEditCopy.promoteMessage(changed: [.role], verified: false) == "管理员可以管理全部账号、用户和资金。\n同时保存：角色")
    #expect(UserEditCopy.promoteConfirm == "设为管理员并保存")
}

@Test func roleChangeAndLastAdmin() {
    #expect(UserRoleChange(from: .user, to: .admin) == .promote)
    #expect(UserRoleChange(from: nil, to: .admin) == .promote)
    #expect(UserRoleChange(from: .admin, to: .vendor) == .demote)
    #expect(UserRoleChange(from: .user, to: .vendor) == .other)
    #expect(UserRoleChange(from: .admin, to: .admin) == .none)
    #expect(UserRoleChange.blocksDemotion(adminTotal: 0))
    #expect(UserRoleChange.blocksDemotion(adminTotal: 1))
    #expect(!UserRoleChange.blocksDemotion(adminTotal: 2))
    #expect(UserEditCopy.lastAdminField == "站点只剩这一位管理员，不能降级")
    #expect(UserEditCopy.lastAdminReceipt == "保存失败：不能降级站点最后一个管理员")
}

/// 本人 > 升管理员 > 降级 > 供应商; nothing for an ordinary user.
@Test func roleFootnotePriority() {
    #expect(UserEditCopy.roleFootnote(isSelf: true, selfName: "陈思远", from: .admin, to: .admin, stepUpRequired: true)
            == "这是你当前登录的账号（陈思远）：不能把自己降级，也不能禁用或删除。")
    #expect(UserEditCopy.roleFootnote(isSelf: false, selfName: "", from: .user, to: .admin, stepUpRequired: true)
            == "保存时需要输入二次验证码，验证后再确认一次。")
    #expect(UserEditCopy.roleFootnote(isSelf: false, selfName: "", from: .user, to: .admin, stepUpRequired: false) == "保存时会再确认一次。")
    #expect(UserEditCopy.roleFootnote(isSelf: false, selfName: "", from: .admin, to: .vendor, stepUpRequired: true)
            == "降级后会失去后台权限。如果他是站点最后一个管理员，保存会失败。")
    #expect(UserEditCopy.roleFootnote(isSelf: false, selfName: "", from: .user, to: .vendor, stepUpRequired: true)
            == "供应商只能访问账号、代理、分组和用量，看不到用户与资金。")
    #expect(UserEditCopy.roleFootnote(isSelf: false, selfName: "", from: .user, to: .user, stepUpRequired: true) == nil)
}

// MARK: - 分段标记与说明行

@Test func segmentMarksAndStatusLine() {
    let issues = [UserDraftIssue(field: .concurrency, message: "x")]
    let marks = UserEditSegmentMark.marks(changed: [.email, .notes], issues: issues, showsIssues: true)
    #expect(marks.map(\.section) == [.basic, .access])
    #expect(marks.map(\.changed) == [2, 0])
    #expect(marks.map(\.issues) == [0, 1])
    #expect(UserEditStatusLine.text(marks) == "基础 已改 2 项 · 权限与并发 1 项要修改")
    #expect(UserEditSegmentMark.marks(changed: [.email, .notes], issues: issues, showsIssues: false).map(\.issues) == [0, 0])
    #expect(UserEditStatusLine.text(UserEditSegmentMark.marks(changed: [], issues: issues, showsIssues: false)) == UserEditCopy.idleHint)
    #expect(UserEditCopy.idleHint == "基础、权限与并发改完点右上“保存”，两段一起提交")
    let both = UserEditSegmentMark.marks(changed: [.email], issues: [UserDraftIssue(field: .email, message: "x")], showsIssues: true)
    #expect(both[0].spokenLabel == "基础，有 1 项要修改、已改 1 项")
    #expect(UserEditStatusLine.text(both) == "基础 1 项要修改、已改 1 项")
}

// MARK: - 回执

@Test func saveReceipt() {
    #expect(UserEditSaveReceipt.text(changedCount: 3, lost: nil) == "已保存 3 项更改")
    let keys = [key(1, group: 5), key(2, group: 5), key(3, group: 5, masked: ""), key(4, group: 9), key(5, group: nil)]
    #expect(UserEditSaveReceipt.boundKeyCount(groupID: 5, keys: keys) == 2)
    let lost = UserEditSaveReceipt.lost(removedGroups: [5], keys: keys) { $0 == 5 ? "Claude Code 组" : "?" }
    #expect(lost == UserEditSaveReceipt.Lost(groupNames: ["Claude Code 组"], keyCount: 2))
    #expect(UserEditSaveReceipt.text(changedCount: 2, lost: lost) == "已保存 2 项更改；绑定在「Claude Code 组」的 2 个 Key 将无法调用")
    #expect(UserEditSaveReceipt.lost(removedGroups: [11], keys: keys) { _ in "Codex 专线" } == nil)
    #expect(UserEditSaveReceipt.lost(removedGroups: [], keys: keys) { _ in "" } == nil)
}

// MARK: - 失败分类

@Test func saveFailureClassification() {
    #expect(UserSaveFailure(APIError.server(status: 409, reason: "EMAIL_EXISTS")) == .emailTaken)
    #expect(UserSaveFailure(APIError.server(status: 404, reason: "USER_NOT_FOUND")) == .notFound)
    #expect(UserSaveFailure(APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY")) == .readOnly)
    let cleared = APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed)
    #expect(UserSaveFailure(cleared) == .reconfirm)
    #expect(UserSaveFailure(APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.cancelled)) == .security(nil))
    #expect(UserSaveFailure(APIError.server(status: 403, reason: "STEP_UP_TOTP_NOT_ENABLED").withSecurityOutcome(.blocked))
            == .security(StepUpPolicy.totpNotEnabledTitle))
    #expect(UserSaveFailure(APIError.server(status: 403, reason: "STEP_UP_ADMIN_API_KEY_FORBIDDEN"))
            == .security(StepUpPolicy.machineCredentialNotice))
    let conflict = KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil)
    #expect(UserSaveFailure(conflict) == .newKey("请求已变化，请重新提交"))
    let lost = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
    #expect(UserSaveFailure(lost) == .unconfirmed)
    let later = Date(timeIntervalSince1970: 1_000)
    let store = KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: later), key: "k", actionID: nil, lastError: nil)
    #expect(UserSaveFailure(store) == .storeUnavailable(later))
    let invalid = APIError.server(status: 400, reason: nil)
    #expect(UserSaveFailure(invalid) == .rejected(invalid.localizedDescription, reload: true))
    #expect(UserSaveFailure(APIError.server(status: 500, reason: nil)) == .rejected(UserEditCopy.serverFailed, reload: true))
    #expect(UserSaveFailure(APIError.server(status: 504, reason: nil)) == .unconfirmed)
    #expect(UserSaveFailure(APIError(kind: .transport, message: "网络")) == .unconfirmed)
    #expect(UserSaveFailure(APIError.invalidResponse) == .unconfirmed)
    let other = APIError.server(status: 422, reason: "SOMETHING")
    #expect(UserSaveFailure(other) == .rejected(other.localizedDescription, reload: false))
    #expect(UserSaveFailure(CancellationError()) == .cancelled)
}

// MARK: - 立即生效同步基线与草稿（30 §6.6 both()）

@Test func rebase() {
    var draft = UserAccessDraft(editing: baseline(allowed: []), catalog: catalog)
    draft.notes = "改过"
    let (base, next) = UserEditRebase.apply(UserGroupsChange(granted: [5]), baseline: baseline(allowed: []), draft: draft, catalog: catalog)
    #expect(base.allowedGroups == [5])
    #expect(next.exclusiveGroupIDs == [5])
    #expect(next.notes == "改过")
    #expect(next.changedFields(from: base, catalog: catalog, definitions: []) == [.notes])

    // A group the draft removed stays removed when it is granted again.
    var removed = UserAccessDraft(editing: baseline(), catalog: catalog)
    removed.exclusiveGroupIDs = []
    let (_, kept) = UserEditRebase.apply(UserGroupsChange(granted: [5]), baseline: baseline(), draft: removed, catalog: catalog)
    #expect(kept.exclusiveGroupIDs.isEmpty)

    // Replace 5 → 9.
    let replace = UserGroupsChange(granted: [9], revoked: [5])
    let start = UserAccessDraft(editing: baseline(), catalog: catalog)
    let (replacedBase, replaced) = UserEditRebase.apply(replace, baseline: baseline(), draft: start, catalog: catalog)
    #expect(replacedBase.allowedGroups == [9])
    #expect(replaced.exclusiveGroupIDs == [9])
    #expect(replaced.changedFields(from: replacedBase, catalog: catalog, definitions: []).isEmpty)

    // A restricted public group follows too.
    let restricted = baseline(allowed: [1], restrict: true, rates: nil)
    let (publicBase, publicDraft) = UserEditRebase.apply(UserGroupsChange(granted: [2]), baseline: restricted,
                                                         draft: UserAccessDraft(editing: restricted, catalog: catalog), catalog: catalog)
    #expect(publicBase.allowedGroups == [1, 2])
    #expect(publicDraft.publicGroupIDs == [1, 2])

    // apply, then the reverse, is where it started.
    let (back, backDraft) = UserEditRebase.apply(replace.reversed, baseline: replacedBase, draft: replaced, catalog: catalog)
    #expect(back == baseline())
    #expect(backDraft == start)
    #expect(replace.reversed == UserGroupsChange(granted: [5], revoked: [9]))
    #expect(UserGroupsChange().isEmpty && !replace.isEmpty)
}

/// After the user PUT succeeds and the attributes fail, the page stays with the base moved to what was saved.
@Test func baselineApplyingRequest() {
    let request = UserUpdateRequest(email: "new@example.invalid", username: "", concurrency: 4, status: "disabled", allowedGroups: [9],
                                    restrictPublicGroups: true, groupRates: [5: nil, 9: amount("1.25")])
    let moved = baseline().applying(request)
    #expect(moved.email == "new@example.invalid")
    #expect(moved.username == "")
    #expect(moved.concurrency == 4)
    #expect(moved.status == "disabled")
    #expect(moved.allowedGroups == [9])
    #expect(moved.restrictPublicGroups)
    #expect(moved.groupRates == [9: amount("1.25")])
    #expect(moved.notes == baseline().notes && moved.role == .user && moved.rpmLimit == 0)
}

/// The same save moves the draft too: a removed exclusive group's rate was kept only for “撤回”, so once the removal is saved
/// it goes, or the next “保存” would write it back for a group the user no longer has.
@Test func settlingASavedRemovalDropsItsRate() throws {
    var draft = UserAccessDraft(editing: baseline(), catalog: catalog)
    draft.exclusiveGroupIDs = []
    draft.notes = "改过"
    draft.password = "abc12345"
    let request = try #require(draft.updateRequest(from: baseline(), catalog: catalog))
    #expect(request.groupRates == [5: nil])
    let (base, next) = UserEditSettle.apply(request, baseline: baseline(), draft: draft, catalog: catalog)
    #expect(base.allowedGroups.isEmpty && base.groupRates.isEmpty)
    #expect(next.groupRates.isEmpty)
    #expect(next.password.isEmpty)
    #expect(next.changedFields(from: base, catalog: catalog, definitions: []).isEmpty)
    #expect(next.updateRequest(from: base, catalog: catalog) == nil)

    // A rate typed for the group before removing it was never sent; it goes as well.
    let plain = baseline(rates: nil)
    var typed = UserAccessDraft(editing: plain, catalog: catalog)
    typed.groupRates[5] = amount("1.5")
    typed.exclusiveGroupIDs = []
    let removal = try #require(typed.updateRequest(from: plain, catalog: catalog))
    #expect(removal.groupRates == nil)
    let (plainBase, settled) = UserEditSettle.apply(removal, baseline: plain, draft: typed, catalog: catalog)
    #expect(settled.changedFields(from: plainBase, catalog: catalog, definitions: []).isEmpty)

    // The rates of groups the user keeps stay as saved.
    let both = baseline(allowed: [5, 9])
    var replaced = UserAccessDraft(editing: both, catalog: catalog)
    replaced.groupRates[9] = amount("1.25")
    replaced.exclusiveGroupIDs = [9]
    let replacing = try #require(replaced.updateRequest(from: both, catalog: catalog))
    let (replacedBase, kept) = UserEditSettle.apply(replacing, baseline: both, draft: replaced, catalog: catalog)
    #expect(kept.groupRates == [9: amount("1.25")])
    #expect(kept.changedFields(from: replacedBase, catalog: catalog, definitions: []).isEmpty)
}

/// What S3-09's request already guarantees, checked once more from the edit page's side.
@Test func requestShapeGuards() throws {
    var attributesOnly = UserAccessDraft(editing: baseline(), catalog: catalog)
    attributesOnly.attributes = [11: "Studio-K"]
    #expect(attributesOnly.updateRequest(from: baseline(), catalog: catalog) == nil)

    var removed = UserAccessDraft(editing: baseline(), catalog: catalog)
    removed.exclusiveGroupIDs = []
    let removal = try #require(removed.updateRequest(from: baseline(), catalog: catalog))
    let body = try #require(JSONSerialization.jsonObject(with: removal.requestBody()) as? [String: Any])
    #expect((body["group_rates"] as? [String: Any])?["5"] is NSNull)
    #expect(body["allowed_groups"] as? [Int] == [])

    var concurrency = UserAccessDraft(editing: baseline(), catalog: catalog)
    concurrency.concurrency = 4
    let concurrencyRequest = try #require(concurrency.updateRequest(from: baseline(), catalog: catalog))
    let keys = try #require(JSONSerialization.jsonObject(with: concurrencyRequest.requestBody()) as? [String: Any]).keys
    #expect(Set(keys) == ["concurrency"])

    var promote = UserAccessDraft(editing: baseline(), catalog: catalog)
    promote.role = .admin
    let promotion = try #require(promote.updateRequest(from: baseline(), catalog: catalog))
    let promotionBody = try #require(JSONSerialization.jsonObject(with: promotion.requestBody()) as? [String: Any])
    #expect(Set(promotionBody.keys) == ["role"])
    let keyed = try PendingUserUpdateOperation(serverID: UUID(), identity: UUID(), userID: 3, request: promotion, serverSupportsIdempotentWrites: true)
    #expect(keyed.supportsSafeRetry)
    let unkeyed = try PendingUserUpdateOperation(serverID: UUID(), identity: UUID(), userID: 3, request: promotion)
    #expect(!unkeyed.supportsSafeRetry)
}

// MARK: - 互斥与刷新

@Test func saveAndImmediateWritesExclude() {
    #expect(UserEditPolicy.canSave(hasChanges: true, saving: false, immediateInFlight: 0))
    #expect(!UserEditPolicy.canSave(hasChanges: false, saving: false, immediateInFlight: 0))
    #expect(!UserEditPolicy.canSave(hasChanges: true, saving: true, immediateInFlight: 0))
    #expect(!UserEditPolicy.canSave(hasChanges: true, saving: false, immediateInFlight: 1))
    #expect(UserEditCopy.immediateBlockedBySave == "正在保存，请稍后再试")
}

@Test func rpmInterval() {
    #expect(UserEditPolicy.rpmRefreshInterval == .seconds(15))
}

// MARK: - 行内文案

@Test func editRowCopy() {
    let claude = group(5, "Claude Code 组", exclusive: true)
    #expect(UserEditCopy.rateLine(amount("1.3"), group: claude) == "专属倍率 ×1.3")
    #expect(UserEditCopy.rateLine(nil, group: claude) == "默认 ×0.8")
    #expect(UserEditCopy.exclusiveRowSubtitle(platformName: "Anthropic", added: false, boundKeys: 1) == "Anthropic · 绑定 1 个 Key")
    #expect(UserEditCopy.exclusiveRowSubtitle(platformName: "Anthropic", added: true, boundKeys: 0) == "Anthropic · 新添加 · 保存后生效")
    #expect(UserEditCopy.removedRowSubtitle(boundKeys: 2) == "保存后移除 · 2 个 Key 会无法调用")
    #expect(UserEditCopy.removedRowSubtitle(boundKeys: 0) == "保存后移除")
    #expect(UserEditCopy.changedCount(3) == "已改 3 项")
    #expect(UserEditCopy.removeGroupTitle("Claude Code 组") == "移除「Claude Code 组」？")
    #expect(UserEditCopy.removeGroupMessage("Claude Code 组", keys: 1) == "绑定在「Claude Code 组」的 1 个 Key 会无法调用。要保留请用替换分组。")
    #expect(UserEditCopy.adjustmentPlaceholder(from: 2, to: 4) == "可选 · 并发 2 → 4 的原因")
    #expect(UserEditCopy.adjustmentPlaceholder(from: nil, to: 1) == "可选 · 并发 — → 1 的原因")
    #expect(UserEditCopy.statusSubtitle(active: true, locked: false) == "可以登录，Key 可以调用")
    #expect(UserEditCopy.statusSubtitle(active: false, locked: false) == "不能登录，Key 调用会被拒绝")
    #expect(UserEditCopy.statusSubtitle(active: true, locked: true) == "管理员不能禁用")
    #expect(UserEditCopy.groupSheetNote(claude, platformName: "Anthropic", boundKeys: 1) == "专属分组 · Anthropic · 默认倍率 ×0.8 · 绑定 1 个 Key")
    #expect(UserEditCopy.groupSheetNote(claude, platformName: "Anthropic", boundKeys: 0) == "专属分组 · Anthropic · 默认倍率 ×0.8")
    #expect(UserEditCopy.resetRate(claude) == "改回默认倍率 ×0.8")
    #expect(UserEditCopy.ratePlaceholder(claude) == "默认 0.8")
    #expect(UserEditCopy.keysSegmentTitle(count: 2) == "Key 与限额（2）")
    #expect(UserEditCopy.keysSegmentTitle(count: nil) == "Key 与限额")
}
