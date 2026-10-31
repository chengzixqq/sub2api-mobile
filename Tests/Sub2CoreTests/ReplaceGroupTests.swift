import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// S3-15: 替换分组 (30 §8.3–§8.4, §0.6; E04, R05): the request, the exact undo, the read back, the failures and the words.

private func exclusive(_ id: Int, _ name: String, status: String = "active", subscription: Bool = false, sort: Int? = nil,
                       rate: String = "1.0") -> AdminGroup {
    AdminGroup(id: id, name: name, platform: "anthropic", status: status, rateMultiplier: Decimal(string: rate), isExclusive: true,
               subscriptionType: subscription ? "subscription" : "standard", sortOrder: sort)
}
/// 5 and 11 active exclusive standard, 7 one more sorted first, 4 a subscription, 12 inactive, 1 public.
private let catalog = UserGroupCatalog(groups: [
    exclusive(5, "Claude Code 组", sort: 5), exclusive(11, "Codex 专线", sort: 11), exclusive(7, "备用专线", sort: 1),
    exclusive(4, "企业专线", subscription: true), exclusive(12, "停用专线", status: "inactive"),
    AdminGroup(id: 1, name: "高级组", platform: "anthropic", isExclusive: false),
])
private func baseline(allowed: [Int]) -> UserBaseline {
    UserBaseline(user: AdminUser(id: 3, email: "xm.wang@example.com", username: "王小明", allowedGroups: allowed))
}
private func key(_ id: Int, group: Int?, masked: String = "sk-…0001") -> AdminAPIKey {
    AdminAPIKey(id: id, userID: 3, keyMasked: masked, name: "脚本", groupID: group)
}
private func request(old: Int = 12, new: Int = 10, keys: [Int]? = nil, keep: Bool = false) -> ReplaceGroupRequest {
    try! ReplaceGroupRequest(oldGroupID: old, newGroupID: new, keyIDs: keys, keepOldGroupAccess: keep)
}
private func bodyText(_ request: ReplaceGroupRequest) throws -> String { String(decoding: try request.requestBody(), as: UTF8.self) }
private func decodeResult(_ json: String) throws -> ReplaceGroupResult { try JSONDecoder().decode(ReplaceGroupResult.self, from: Data(json.utf8)) }
private func groupClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}

// MARK: - 请求与响应

@Test func requestEncodesOnlyGivenFields() throws {
    #expect(try bodyText(request()) == #"{"new_group_id":10,"old_group_id":12}"#)
    #expect(try bodyText(request(old: 10, new: 12, keys: [4087, 4099], keep: true))
            == #"{"keep_old_group_access":true,"key_ids":[4087,4099],"new_group_id":12,"old_group_id":10}"#)
    #expect(try bodyText(request(old: 10, new: 12, keys: [4087])) == #"{"key_ids":[4087],"new_group_id":12,"old_group_id":10}"#)
    #expect(request(keys: [4099, 4087, 4099]).keyIDs == [4099, 4087])
}

@Test func requestRejectsInvalidBeforeSending() {
    for (old, new, keys) in [(5, 5, nil), (0, 5, nil), (5, -1, nil), (5, 11, [Int]()), (5, 11, [0, 301])] as [(Int, Int, [Int]?)] {
        do {
            _ = try ReplaceGroupRequest(oldGroupID: old, newGroupID: new, keyIDs: keys)
            Issue.record("\(old) → \(new) \(String(describing: keys)) 应在发送前被拒绝")
        } catch { #expect((error as? APIError)?.kind == .validation) }
    }
}

@Test func resultDecodesE04AndLegacy() throws {
    let full = try decodeResult(#"{"migrated_keys":2,"migrated_key_ids":[4087,4099],"new_group_newly_granted":true}"#)
    #expect(full == ReplaceGroupResult(migratedKeys: 2, migratedKeyIDs: [4087, 4099], newGroupNewlyGranted: true) && !full.isLegacy)
    let legacy = try decodeResult(#"{"migrated_keys":2}"#)
    #expect(legacy.migratedKeyIDs == nil && legacy.newGroupNewlyGranted == nil && legacy.isLegacy)
    let none = try decodeResult(#"{"migrated_keys":0,"migrated_key_ids":[],"new_group_newly_granted":false}"#)
    #expect(none.migratedKeyIDs == [] && none.newGroupNewlyGranted == false && !none.isLegacy)
    #expect(try decodeResult("{}").migratedKeys == 0)
}

// MARK: - 撤销计划（30 §8.4、§0.6）

@Test func undoReversesWithMigratedKeyIDs() {
    let sent = request(old: 12, new: 10), before = ReplaceGroupSnapshot(allowedGroups: [12], keys: [key(4087, group: 12)], source: 12, target: 10)
    let granted = ReplaceGroupResult(migratedKeys: 2, migratedKeyIDs: [4087, 4099], newGroupNewlyGranted: true)
    #expect(ReplaceGroupUndo.plan(sent, result: granted, before: before) == .reverse(request(old: 10, new: 12, keys: [4087, 4099], keep: false)))
    let had = ReplaceGroupResult(migratedKeys: 1, migratedKeyIDs: [4087], newGroupNewlyGranted: false)
    #expect(ReplaceGroupUndo.plan(sent, result: had, before: before) == .reverse(request(old: 10, new: 12, keys: [4087], keep: true)))
}

@Test func undoWithoutMigratedKeysNeverUsesReplaceGroup() {
    let sent = request(old: 12, new: 10)
    // The target already had keys of its own: a reverse replace without key_ids would move them too.
    let before = ReplaceGroupSnapshot(allowedGroups: [12, 10], keys: [key(1, group: 10)], source: 12, target: 10)
    for newly in [true, false] {
        let plan = ReplaceGroupUndo.plan(sent, result: ReplaceGroupResult(migratedKeys: 0, migratedKeyIDs: [], newGroupNewlyGranted: newly), before: before)
        #expect(plan == .restoreAllowedGroups(restoring: 12, revoking: newly ? 10 : nil))
        if case .reverse = plan { Issue.record("空迁移不能反向 replace-group") }
    }
}

@Test func allowedGroupsAfterUndo() {
    #expect(ReplaceGroupUndo.allowedGroups(current: [2, 10, 7], restoring: 12, revoking: 10) == [2, 7, 12])
    #expect(ReplaceGroupUndo.allowedGroups(current: [2, 10], restoring: 12, revoking: nil) == [2, 10, 12])
    #expect(ReplaceGroupUndo.allowedGroups(current: nil, restoring: 12, revoking: 10) == [12])
    #expect(ReplaceGroupUndo.allowedGroups(current: [12, 2], restoring: 12, revoking: 10) == nil)
}

@Test func legacyResultUndoFollows06() {
    let sent = request(old: 12, new: 10), legacy = ReplaceGroupResult(migratedKeys: 1, migratedKeyIDs: nil, newGroupNewlyGranted: nil)
    let hadTarget = ReplaceGroupSnapshot(allowedGroups: [12, 10], keys: [], source: 12, target: 10)
    #expect(ReplaceGroupUndo.plan(sent, result: legacy, before: hadTarget) == nil)
    let targetKeys = ReplaceGroupSnapshot(allowedGroups: [12], keys: [key(1, group: 10)], source: 12, target: 10)
    #expect(ReplaceGroupUndo.plan(sent, result: legacy, before: targetKeys) == nil)
    let clean = ReplaceGroupSnapshot(allowedGroups: [12], keys: [key(1, group: 12), key(2, group: 10, masked: "")], source: 12, target: 10)
    #expect(ReplaceGroupUndo.plan(sent, result: legacy, before: clean) == .reverse(request(old: 10, new: 12)))
    #expect(legacy.newlyGranted(target: 10, before: clean) && !legacy.newlyGranted(target: 10, before: hadTarget))
    #expect(legacy.movedKeyIDs(before: clean) == [1])
}

@Test func groupsChangeAndReverse() {
    let sent = request(old: 12, new: 10)
    let granted = ReplaceGroupUndo.groupsChange(sent: sent, newlyGranted: true)
    #expect(granted == UserGroupsChange(granted: [10], revoked: [12]) && granted.reversed == UserGroupsChange(granted: [12], revoked: [10]))
    let kept = ReplaceGroupUndo.groupsChange(sent: sent, newlyGranted: false)
    #expect(kept == UserGroupsChange(granted: [], revoked: [12]) && kept.reversed == UserGroupsChange(granted: [12], revoked: []))
}

/// 30 §8.4 “基线与草稿的专属分组去掉 X、加上 Y”: also when the server says the user had Y already (granted on the Web after the
/// page was read), while the undo keeps Y (keep_old_group_access) and puts only X back.
@Test func baseTakesTargetEvenWhenNotNewlyGranted() {
    let sent = request(old: 5, new: 11)
    #expect(ReplaceGroupUndo.baseChange(sent: sent) == UserGroupsChange(granted: [11], revoked: [5]))
    let stale = baseline(allowed: [5, 1])
    let (base, draft) = UserEditRebase.apply(ReplaceGroupUndo.baseChange(sent: sent), baseline: stale,
                                             draft: UserAccessDraft(editing: stale, catalog: catalog), catalog: catalog)
    #expect(base.allowedGroups == [11, 1] && draft.exclusiveGroupIDs == [11])
    let undo = ReplaceGroupUndo.groupsChange(sent: sent, newlyGranted: false).reversed
    let (undone, undoneDraft) = UserEditRebase.apply(undo, baseline: base, draft: draft, catalog: catalog)
    #expect(undone.allowedGroups == [5, 11, 1] && undoneDraft.exclusiveGroupIDs == [5, 11])
}

// MARK: - 来源与目标（30 §8.3）

@Test func targetsAndSources() {
    #expect(ReplaceGroupTargets.sources(baseline: baseline(allowed: [5, 4, 12, 1, 99]), catalog: catalog).map(\.id) == [5])
    #expect(ReplaceGroupTargets.sources(baseline: baseline(allowed: [11, 5]), catalog: catalog).map(\.id) == [5, 11])
    #expect(ReplaceGroupTargets.sources(baseline: baseline(allowed: [1]), catalog: catalog).isEmpty)
    let base = baseline(allowed: [5])
    #expect(ReplaceGroupTargets.options(source: 5, baseline: base, draft: UserAccessDraft(editing: base, catalog: catalog), catalog: catalog).map(\.id)
            == [7, 11])
    var draft = UserAccessDraft(editing: base, catalog: catalog)
    draft.exclusiveGroupIDs.formUnion([11, 7])
    #expect(ReplaceGroupTargets.options(source: 5, baseline: base, draft: draft, catalog: catalog).isEmpty)
}

// MARK: - 结果不明的读回

@Test func readbackOutcome() {
    let sent = request(old: 5, new: 11)
    let before = ReplaceGroupSnapshot(allowedGroups: [5, 2], keys: [key(301, group: 5), key(302, group: 5), key(1, group: 2)], source: 5, target: 11)
    func user(_ allowed: [Int]) -> AdminUser { AdminUser(id: 3, email: "xm.wang@example.com", allowedGroups: allowed) }
    let moved = [key(301, group: 11), key(302, group: 11), key(1, group: 2)]
    #expect(ReplaceGroupReadback.outcome(sent, before: before, user: user([2, 11]), keys: moved, exactUndoSupported: true)
            == .applied(ReplaceGroupResult(migratedKeys: 2, migratedKeyIDs: [301, 302], newGroupNewlyGranted: true)))
    let kept = [key(301, group: 5), key(302, group: 5), key(1, group: 2)]
    #expect(ReplaceGroupReadback.outcome(sent, before: before, user: user([2, 5]), keys: kept, exactUndoSupported: true) == .notApplied)
    #expect(ReplaceGroupReadback.outcome(sent, before: before, user: user([2, 5]), keys: moved, exactUndoSupported: true) == .unclear)
    #expect(ReplaceGroupReadback.outcome(sent, before: before, user: user([2]), keys: moved, exactUndoSupported: true) == .unclear)
    let hadTarget = ReplaceGroupSnapshot(allowedGroups: [5, 11], keys: [key(301, group: 5)], source: 5, target: 11)
    #expect(ReplaceGroupReadback.outcome(sent, before: hadTarget, user: user([11]), keys: [key(301, group: 11)], exactUndoSupported: true)
            == .applied(ReplaceGroupResult(migratedKeys: 1, migratedKeyIDs: [301], newGroupNewlyGranted: false)))
}

/// Without E04 (admin/me missing, 30 §0.1) the read back makes an older reply, so the undo follows §0.6: none when the target
/// already had a key (a reverse replace there would move every key of it), a reverse without key_ids otherwise.
@Test func readbackOnOlderServerFollows06() {
    let sent = request(old: 5, new: 11)
    func user(_ allowed: [Int]) -> AdminUser { AdminUser(id: 3, email: "xm.wang@example.com", allowedGroups: allowed) }
    let targetKey = ReplaceGroupSnapshot(allowedGroups: [5], keys: [key(301, group: 5), key(302, group: 11)], source: 5, target: 11)
    let outcome = ReplaceGroupReadback.outcome(sent, before: targetKey, user: user([11]), keys: [key(301, group: 11), key(302, group: 11)],
                                               exactUndoSupported: false)
    #expect(outcome == .applied(ReplaceGroupResult(migratedKeys: 1, migratedKeyIDs: nil, newGroupNewlyGranted: nil)))
    guard case .applied(let result) = outcome else { return }
    #expect(result.isLegacy && ReplaceGroupUndo.plan(sent, result: result, before: targetKey) == nil)
    let clean = ReplaceGroupSnapshot(allowedGroups: [5], keys: [key(301, group: 5)], source: 5, target: 11)
    guard case .applied(let older) = ReplaceGroupReadback.outcome(sent, before: clean, user: user([11]), keys: [key(301, group: 11)],
                                                                  exactUndoSupported: false) else { Issue.record("应判为已生效"); return }
    #expect(ReplaceGroupUndo.plan(sent, result: older, before: clean) == .reverse(request(old: 11, new: 5)))
    #expect(older.movedKeyIDs(before: clean) == [301] && older.newlyGranted(target: 11, before: clean))
}

// MARK: - 失败（按 reason，不读 message）

@Test func failureMappingByReasonNotMessage() {
    func refusal(_ status: Int, _ reason: String) -> APIError {
        APIError.from(errorReply(status, reason: reason, extra: #","message":"secret-upstream https://upstream.example.invalid""#))
    }
    let table: [(Int, String, ReplaceGroupFailure.Phase, ReplaceGroupFailure, String)] = [
        (400, "SAME_GROUP", .replace, .pickAgain("新旧分组不能相同"), "新旧分组不能相同"),
        (400, "GROUP_NOT_EXCLUSIVE", .replace, .pickAgain("目标分组不是专属分组"), "目标分组不是专属分组"),
        (400, "GROUP_IS_SUBSCRIPTION", .replace, .pickAgain("订阅分组不能用于替换"), "订阅分组不能用于替换"),
        (400, "GROUP_NOT_ACTIVE", .replace, .pickAgain("目标分组已停用"), "目标分组已停用"),
        (400, "GROUP_NOT_ACTIVE", .undo, .sourceInactive, "原分组已停用，无法撤销"),
        (400, "KEY_NOT_IN_GROUP", .undo, .keysMoved, "有 Key 已不在原分组，无法精确撤销"),
        (404, "GROUP_NOT_FOUND", .replace, .groupMissing, "分组不存在"),
        (404, "USER_NOT_FOUND", .replace, .userGone, "这个用户不存在或已删除"),
        (403, "ACCESS_TOKEN_READ_ONLY", .replace, .readOnly, "当前登录的是只读令牌，不能修改"),
    ]
    for (status, reason, phase, expected, text) in table {
        let failure = ReplaceGroupFailure(refusal(status, reason), phase: phase)
        #expect(failure == expected, "\(reason)")
        #expect(failure?.message == text)
        #expect(failure?.message.contains("secret-upstream") == false && failure?.undoReceipt.contains("secret-upstream") == false)
    }
    #expect(ReplaceGroupFailure(refusal(400, "GROUP_NOT_ACTIVE"), phase: .undo)?.undoReceipt == "原分组已停用，无法撤销")
    #expect(ReplaceGroupFailure(refusal(404, "GROUP_NOT_FOUND"), phase: .undo)?.undoReceipt == "撤销没有成功：分组不存在")
    let unknown = ReplaceGroupFailure(refusal(400, "SOMETHING_NEW"), phase: .replace)
    #expect(unknown == .other("请求无效（错误码 SOMETHING_NEW）"))
    let lost = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
    #expect(ReplaceGroupFailure(lost, phase: .replace) == .unconfirmed && ReplaceGroupFailure(lost, phase: .replace)?.message == "结果未确认，请刷新后检查")
    let conflict = KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil)
    #expect(ReplaceGroupFailure(conflict, phase: .replace) == .newKey(conflict.localizedDescription))
    #expect(ReplaceGroupFailure(APIError(kind: .transport, message: "无法连接站点"), phase: .undo) == .unconfirmed)
    #expect(ReplaceGroupFailure(CancellationError(), phase: .replace) == nil)
    #expect(ReplaceGroupFailure(refusal(403, "STEP_UP_REQUIRED").withSecurityOutcome(.cancelled), phase: .replace) == nil)
}

// MARK: - 文案

@Test func copyStrings() {
    #expect(ReplaceGroupCopy.sectionTitle == "替换分组")
    #expect(ReplaceGroupCopy.useReplace == "改用替换分组")
    #expect(ReplaceGroupCopy.rowTitle("Claude Code 组") == "替换「Claude Code 组」…")
    #expect(ReplaceGroupCopy.rowSubtitle(keys: 2) == "绑定 2 个 Key")
    #expect(ReplaceGroupCopy.footnote == "把一个专属分组换成另一个：绑定的 Key 一起迁移，旧分组的权限随之移除。")
    #expect(ReplaceGroupCopy.sheetTitle == "替换专属分组")
    #expect(ReplaceGroupCopy.sheetNote(source: "Claude Code 组", keys: 1) == "选择新分组替换「Claude Code 组」，将自动迁移绑定的 1 个 Key 并更新分组权限。")
    #expect(ReplaceGroupCopy.optionSubtitle(exclusive(11, "Codex 专线"), platformName: "OpenAI") == "OpenAI · 专属分组 · 默认倍率 ×1")
    #expect(ReplaceGroupCopy.optionSubtitle(exclusive(5, "Claude Code 组", rate: "0.8"), platformName: "Anthropic") == "Anthropic · 专属分组 · 默认倍率 ×0.8")
    #expect(ReplaceGroupCopy.empty == "没有其他可用的专属分组")
    #expect(ReplaceGroupCopy.submit(target: "Codex 专线") == "替换为「Codex 专线」" && ReplaceGroupCopy.submit(target: nil) == "选择目标分组")
    #expect(ReplaceGroupCopy.confirmTitle(source: "Claude Code 组", target: "Codex 专线") == "把「Claude Code 组」替换为「Codex 专线」？")
    #expect(ReplaceGroupCopy.confirmMessage(user: "王小明", source: "Claude Code 组", target: "Codex 专线", keys: 1)
            == "王小明绑定在「Claude Code 组」的 1 个 Key 会迁移到「Codex 专线」，并移除「Claude Code 组」的使用权限。立即生效，不经过“保存”。")
    #expect(ReplaceGroupCopy.confirm == "确认替换")
    #expect(ReplaceGroupCopy.receipt(migrated: 1) == "分组替换成功，已迁移 1 个 Key")
    #expect(ReplaceGroupCopy.appliedName(source: "Claude Code 组", target: "Codex 专线") == "替换分组（Claude Code 组 → Codex 专线）")
    #expect(ReplaceGroupCopy.readbackApplied == "分组替换已生效")
    #expect(ReplaceGroupCopy.undoFailed("分组不存在") == "撤销没有成功：分组不存在")
}

@Test func movedToGroupKeepsOtherFields() {
    let original = AdminAPIKey(id: 301, userID: 3, keyMasked: "sk-…x301", name: "A&amp;B", groupID: 5, status: "active", effectiveStatus: "active",
                               ipWhitelist: ["198.51.100.0/24"], ipBlacklist: ["203.0.113.9"], lastUsedAt: Date(timeIntervalSince1970: 1_800_000_000),
                               lastUsedIP: "203.0.113.24", quota: 20, quotaUsed: 2, expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
                               currentConcurrency: 1, rateLimit5h: 5, rateLimit1d: 20, rateLimit7d: 70, usage5h: 1, usage1d: 2, usage7d: 3,
                               reset5hAt: Date(timeIntervalSince1970: 1_800_001_000), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    let moved = original.movedToGroup(11)
    #expect(moved.groupID == 11 && moved != original)
    #expect(moved.movedToGroup(5) == original)
}

// MARK: - 接口

@Test func replaceUserGroupIsKeyedWrite() async throws {
    let key = UUID()
    let reply = #"{"migrated_keys":1,"migrated_key_ids":[301],"new_group_newly_granted":true}"#
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .fail(URLError(.timedOut)), .reply(okReply(reply))])
    let sent = request(old: 5, new: 11)
    let outcome = try await groupClient(transport).replaceUserGroup(userID: 3, sent, idempotencyKey: key)
    #expect(outcome.value == ReplaceGroupResult(migratedKeys: 1, migratedKeyIDs: [301], newGroupNewlyGranted: true))
    let requests = await transport.requests
    #expect(requests.count == 3)
    let body = try sent.requestBody()
    for item in requests {
        #expect(item.httpMethod == "POST" && item.url?.path == "/api/v1/admin/users/3/replace-group" && item.httpBody == body)
        #expect(sentHeader(item, "Idempotency-Key") == key.uuidString.lowercased() && sentHeader(item, "X-Request-ID") == key.uuidString.lowercased())
        #expect(item.timeoutInterval == RequestTimeout.keyedWrite)
    }

    let refused = ScriptedTransport(script: [.reply(errorReply(400, reason: "SAME_GROUP"))])
    let error = await thrownAPIError { _ = try await groupClient(refused).replaceUserGroup(userID: 3, sent, idempotencyKey: UUID()) }
    #expect(error?.reason == "SAME_GROUP" && error?.statusCode == 400)
    #expect(await refused.requests.count == 1)

    let none = ScriptedTransport(script: [.reply(okReply(reply))])
    let invalid = await thrownAPIError { _ = try await groupClient(none).replaceUserGroup(userID: 0, sent, idempotencyKey: UUID()) }
    #expect(invalid?.kind == .validation)
    #expect(await none.requests.isEmpty)
}
