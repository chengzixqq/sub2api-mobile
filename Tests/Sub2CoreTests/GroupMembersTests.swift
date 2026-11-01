import Foundation
import Testing
@testable import Sub2Core

// S5-03: 50 §0.4.1–§0.4.3 member request, result, receipt and undo.

private let memberSpecReply = #"{"group_id":3,"added":1,"removed":1,"unchanged":1,"failed":1,"results":[{"account_id":11,"action":"add","status":"added","priority":50},{"account_id":14,"action":"add","status":"failed","reason":"MIXED_CHANNEL_RISK","message":"mixed: secret upstream text","details":{"current_platform":"Antigravity","other_platform":"Anthropic"}}],"counts":{"account_count":6,"active_account_count":4,"rate_limited_account_count":1,"error_account_count":0,"idle_account_count":1}}"#

private func memberRequest(add: [GroupMemberAdd] = [], remove: [Int] = [], confirm: Bool = false) throws -> GroupMemberBatchRequest {
    try GroupMemberBatchRequest(add: add, remove: remove, confirmMixedChannelRisk: confirm)
}
private func memberText(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
/// A failed item defaults to ACCOUNT_NOT_FOUND.
private func memberItem(_ id: Int, _ action: GroupMemberAction, _ status: GroupMemberStatus, priority: Int? = nil,
                        reason: String? = nil) -> GroupMemberResultItem {
    GroupMemberResultItem(accountID: id, action: action, status: status, priority: priority,
                          reason: reason ?? (status == .failed ? GroupMemberReason.accountNotFound : nil))
}
private func memberResult(_ items: [GroupMemberResultItem], active: Int? = nil) -> GroupMemberBatchResult {
    GroupMemberBatchResult(groupID: 3, results: items, counts: active.map { GroupAccountCounts(accountCount: 6, activeAccountCount: $0) })
}
private func memberDecoded(_ json: String) throws -> GroupMemberBatchResult {
    try JSONDecoder().decode(GroupMemberBatchResult.self, from: Data(json.utf8))
}

@Test func memberRequestDedupesKeepingFirstPlaceAndPriority() throws {
    let request = try memberRequest(add: [GroupMemberAdd(accountID: 11), GroupMemberAdd(accountID: 12, priority: 2), GroupMemberAdd(accountID: 11, priority: 9)],
                                    remove: [13, 13])
    #expect(request.add == [GroupMemberAdd(accountID: 11), GroupMemberAdd(accountID: 12, priority: 2)])
    #expect(request.remove == [13])
    #expect(request.accountIDs == [11, 12, 13])
    #expect(request.count == 3)
}

@Test func memberRequestRejectsBothSidesEmptyAndNonPositiveLocally() {
    func message(_ add: [Int], _ remove: [Int]) -> String? {
        do { _ = try memberRequest(add: add.map { GroupMemberAdd(accountID: $0) }, remove: remove); return nil }
        catch let error as APIError { return error.kind == .validation ? error.localizedDescription : "kind \(error.kind)" }
        catch { return "\(error)" }
    }
    #expect(message([11], [11]) == "同一个账号不能同时加入和移出。")
    #expect(message([], []) == "请选择要加入或移出的账号。")
    #expect(message([0], []) == "无效的对象编号。")
    #expect(message([], [-1]) == "无效的对象编号。")
    #expect(message([11], [12]) == nil)
}

@Test func memberRequestBodyBytesAreSortedAndOmitDefaultPriority() throws {
    let request = try memberRequest(add: [GroupMemberAdd(accountID: 11), GroupMemberAdd(accountID: 12, priority: 2), GroupMemberAdd(accountID: 14, priority: 0),
                                          GroupMemberAdd(accountID: 15, priority: -3)], remove: [13])
    #expect(memberText(try request.requestBody())
            == #"{"add":[{"account_id":11},{"account_id":12,"priority":2},{"account_id":14},{"account_id":15}],"confirm_mixed_channel_risk":false,"remove":[13]}"#)
    #expect(memberText(try memberRequest(add: [GroupMemberAdd(accountID: 11)]).requestBody())
            == #"{"add":[{"account_id":11}],"confirm_mixed_channel_risk":false,"remove":[]}"#)
    let confirmed = request.confirmingMixedChannel()
    #expect(confirmed.confirmMixedChannelRisk && confirmed.add == request.add && confirmed.remove == request.remove)
    #expect(GroupMemberAdd(accountID: 1, priority: 0) == GroupMemberAdd(accountID: 1))
}

@Test func memberRequestSplitsIntoOrderedBatchesOf200() throws {
    let request = try memberRequest(add: (1...300).map { GroupMemberAdd(accountID: $0) }, remove: Array(301...450), confirm: true)
    let batches = request.batches()
    #expect(batches.map(\.add.count) == [200, 100, 0])
    #expect(batches.map(\.remove.count) == [0, 100, 50])
    #expect(batches.flatMap(\.accountIDs) == request.accountIDs)
    #expect(batches.allSatisfy { $0.confirmMixedChannelRisk && $0.count <= GroupMemberBatchRequest.maxPerRequest })
    let exact = try memberRequest(remove: Array(1...200))
    #expect(exact.batches() == [exact])
    let small = try memberRequest(add: [GroupMemberAdd(accountID: 1), GroupMemberAdd(accountID: 2, priority: 4)], remove: [3])
    #expect(small.batches(limit: 2).map(\.accountIDs) == [[1, 2], [3]])
    #expect(small.batches(limit: 2).first?.add.last?.priority == 4)
}

@Test func memberResultDecodesSpecReplyWithoutMessage() throws {
    let result = try memberDecoded(memberSpecReply)
    #expect(result.groupID == 3)
    #expect(result.results == [GroupMemberResultItem(accountID: 11, action: .add, status: .added, priority: 50),
                               GroupMemberResultItem(accountID: 14, action: .add, status: .failed, reason: GroupMemberReason.mixedChannelRisk,
                                                     details: GroupMemberMixedChannel(currentPlatform: "Antigravity", otherPlatform: "Anthropic"))])
    #expect(result.counts == GroupAccountCounts(accountCount: 6, activeAccountCount: 4, rateLimitedAccountCount: 1, errorAccountCount: 0, idleAccountCount: 1))
    // Counted from the results, not from the reply's top-level numbers (00 §4.5).
    #expect(result.added == 1 && result.removed == 0 && result.unchanged == 0 && result.failed == 1)
    #expect(!String(describing: result).contains("secret"))
    #expect(Mirror(reflecting: result.results[1]).children.allSatisfy { $0.label != "message" })
}

@Test func memberResultToleratesMissingCountsDetailsAndPriority() throws {
    let rows = [#"{"account_id":11,"action":"remove","status":"removed"}"#,
                #"{"account_id":12,"action":"add","status":"failed","reason":"MIXED_CHANNEL_RISK"}"#,
                #"{"account_id":13,"action":"add","status":"failed","reason":"MIXED_CHANNEL_RISK","details":{"current_platform":"Anthropic"}}"#,
                #"{"account_id":14,"action":"add","status":"failed","reason":"","details":{"current_platform":"Anthropic","other_platform":" "}}"#,
                #"{"account_id":15,"action":"swap","status":"added"}"#]
    let result = try memberDecoded(#"{"group_id":3,"results":[\#(rows.joined(separator: ","))]}"#)
    #expect(result.counts == nil)
    #expect(result.results.map(\.accountID) == [11, 12, 13, 14])
    #expect(result.results.allSatisfy { $0.details == nil && $0.priority == nil })
    #expect(result.results.map(\.reason) == [nil, "MIXED_CHANNEL_RISK", "MIXED_CHANNEL_RISK", nil])
    #expect(try memberDecoded(#"{"group_id":3,"results":null,"counts":null}"#) == GroupMemberBatchResult(groupID: 3, results: [], counts: nil))
    #expect(try memberDecoded("{}") == GroupMemberBatchResult(groupID: 0, results: [], counts: nil))
}

@Test func memberResultScopesToRequestedAccountsAndMarksMissing() throws {
    let request = try memberRequest(add: [GroupMemberAdd(accountID: 11), GroupMemberAdd(accountID: 12)], remove: [13])
    let reply = GroupMemberBatchResult(groupID: 0, results: [memberItem(11, .add, .added, priority: 50), memberItem(99, .add, .added),
                                                            memberItem(11, .add, .unchanged), memberItem(13, .add, .added)], counts: nil)
    let scoped = reply.scoped(to: request, groupID: 3)
    #expect(scoped.groupID == 3)
    // Answered but not about 12 or the removal of 13: whether they ran is unknown (S5D2a-17).
    #expect(scoped.results == [memberItem(11, .add, .added, priority: 50),
                               memberItem(12, .add, .failed, reason: GroupMemberReason.notConfirmed),
                               memberItem(13, .remove, .failed, reason: GroupMemberReason.notConfirmed)])
    #expect(scoped.added == 1 && scoped.failed == 2)
}

@Test func memberResultMergingKeepsOrderAndLaterCounts() throws {
    let first = memberResult([memberItem(11, .add, .added)], active: 2)
    let later = memberResult([memberItem(12, .add, .unchanged)], active: 3)
    #expect(first.merging(later).results == first.results + later.results)
    #expect(first.merging(later).counts == later.counts)
    #expect(later.merging(memberResult([memberItem(13, .remove, .removed)])).counts == nil)
    let request = try memberRequest(add: [GroupMemberAdd(accountID: 11)], remove: [12])
    #expect(GroupMemberBatchResult.undelivered(request, groupID: 3)
            == GroupMemberBatchResult(groupID: 3, results: [memberItem(11, .add, .failed, reason: GroupMemberReason.notDelivered),
                                                            memberItem(12, .remove, .failed, reason: GroupMemberReason.notDelivered)], counts: nil))
}

@Test func memberReceiptAllSucceededRows() {
    let two = memberResult([memberItem(11, .add, .added), memberItem(12, .add, .added)], active: 3)
    #expect(GroupMemberReceipt(result: two, activeBefore: 1)
            == GroupMemberReceipt(text: "已加入 2 个账号 · 可用 1 → 3", systemImage: "checkmark.circle", tone: .ok, button: .undo))
    #expect(GroupMemberReceipt.text(result: memberResult([memberItem(13, .remove, .removed, priority: 7)]), activeBefore: 2) == "已移出 1 个账号")
    #expect(GroupMemberReceipt.text(result: memberResult([memberItem(11, .add, .added), memberItem(12, .add, .added), memberItem(13, .remove, .removed)]),
                                    activeBefore: nil) == "已加入 2 个、已移出 1 个账号")
    // unchanged counts as success and says nothing of its own; an unchanged availability adds no suffix.
    #expect(GroupMemberReceipt.text(result: memberResult([memberItem(11, .add, .added), memberItem(12, .add, .unchanged)], active: 4), activeBefore: 4)
            == "已加入 2 个账号")
    #expect(GroupMemberReceipt.text(result: two, activeBefore: nil) == "已加入 2 个账号")
    #expect(GroupMemberReceipt.text(result: memberResult(two.results), activeBefore: 1) == "已加入 2 个账号")
    let unchanged = GroupMemberReceipt(result: memberResult([memberItem(11, .add, .unchanged)]), activeBefore: nil)
    #expect(unchanged.text == "已加入 1 个账号" && unchanged.button == nil && unchanged.tone == .ok)
    let many = memberResult((1...1234).map { memberItem($0, .add, .added) })
    #expect(GroupMemberReceipt.text(result: many, activeBefore: nil) == "已加入 1,234 个账号")
}

@Test func memberReceiptPartialAndAllFailedRows() {
    #expect(GroupMemberReceipt(result: memberResult([memberItem(11, .add, .added), memberItem(12, .add, .failed)], active: 5), activeBefore: 4)
            == GroupMemberReceipt(text: "已加入 1 个，1 个失败", systemImage: "exclamationmark.triangle", tone: .caution, button: .details))
    #expect(GroupMemberReceipt.text(result: memberResult([memberItem(13, .remove, .removed), memberItem(14, .remove, .failed), memberItem(15, .remove, .failed)]),
                                    activeBefore: nil) == "已移出 1 个，2 个失败")
    #expect(GroupMemberReceipt.text(result: memberResult([memberItem(11, .add, .added), memberItem(12, .add, .failed), memberItem(13, .remove, .removed)]),
                                    activeBefore: nil) == "已加入 1 个、已移出 1 个，1 个失败")
    #expect(GroupMemberReceipt(result: memberResult([memberItem(11, .add, .failed), memberItem(12, .add, .failed)]), activeBefore: 3)
            == GroupMemberReceipt(text: "加入失败 · 2 个账号没有改动", systemImage: "xmark.octagon", tone: .critical, button: .details))
    #expect(GroupMemberReceipt.text(result: memberResult([memberItem(13, .remove, .failed)]), activeBefore: nil) == "移出失败 · 1 个账号没有改动")
    #expect(GroupMemberReceipt.text(result: memberResult([memberItem(11, .add, .failed), memberItem(13, .remove, .failed)]), activeBefore: nil)
            == "成员调整失败 · 2 个账号没有改动")
}

@Test func memberReceiptPrefixesForCreateAndSave() {
    let two = memberResult([memberItem(11, .add, .added), memberItem(12, .add, .added)], active: 2)
    #expect(GroupMemberReceipt.text(result: two, prefix: .created(name: "高级组"), activeBefore: 0) == "已创建「高级组」 · 已加入 2 个账号 · 可用 0 → 2")
    #expect(GroupMemberReceipt.text(result: memberResult([memberItem(11, .add, .added), memberItem(12, .add, .failed)]), prefix: .saved(name: "高级组"),
                                    activeBefore: nil) == "已保存「高级组」 · 已加入 1 个，1 个失败")
    #expect(GroupMemberReceipt.text(result: memberResult([memberItem(11, .add, .added)]), prefix: .saved(name: "高级组", droppedFields: true), activeBefore: nil)
            == "已保存「高级组」 · 部分字段无权修改，未生效 · 已加入 1 个账号")
}

@Test func memberReceiptSingleRemovalAndUnconfirmed() {
    let removed = [memberItem(21, .remove, .removed, priority: 4)]
    #expect(GroupMemberReceipt.removal(accountName: "Claude-01", result: memberResult(removed, active: 2), wasAvailable: true, activeBefore: 3)
            == GroupMemberReceipt(text: "已移出「Claude-01」 · 可用 3 → 2", systemImage: "checkmark.circle", tone: .ok, button: .undo))
    // Without counts: x − 1.
    #expect(GroupMemberReceipt.removal(accountName: "Claude-01", result: memberResult(removed), wasAvailable: true, activeBefore: 3).text
            == "已移出「Claude-01」 · 可用 3 → 2")
    let unavailable = GroupMemberReceipt.removal(accountName: "Claude-01", result: memberResult(removed, active: 3), wasAvailable: false, activeBefore: 3)
    #expect(unavailable.text == "已移出「Claude-01」" && unavailable.button == .undo)
    let unchanged = GroupMemberReceipt.removal(accountName: "Claude-01", result: memberResult([memberItem(21, .remove, .unchanged)]), wasAvailable: true,
                                               activeBefore: 3)
    #expect(unchanged.text == "已移出「Claude-01」" && unchanged.button == nil)
    let failed = GroupMemberReceipt.removal(accountName: "Claude-01", result: memberResult([memberItem(21, .remove, .failed)]), wasAvailable: true, activeBefore: 3)
    #expect(failed.text == "移出失败 · 1 个账号没有改动" && failed.button == .details)
    #expect(GroupMemberReceipt.unconfirmed == GroupMemberReceipt(text: "成员改动未确认", systemImage: "exclamationmark.triangle", tone: .caution, button: .retry))
}

@Test func memberInverseUndoesOnlyChangedMemberships() throws {
    let result = memberResult([memberItem(11, .add, .added, priority: 50), memberItem(12, .add, .unchanged), memberItem(13, .remove, .removed, priority: 7),
                               memberItem(14, .remove, .failed), memberItem(15, .remove, .removed)])
    let inverse = try #require(GroupMemberBatchRequest.inverse(of: result))
    let expected = try memberRequest(add: [GroupMemberAdd(accountID: 13, priority: 7), GroupMemberAdd(accountID: 15)], remove: [11])
    #expect(inverse == expected)
    #expect(!inverse.confirmMixedChannelRisk)
    #expect(GroupMemberBatchRequest.inverse(of: memberResult([memberItem(12, .add, .unchanged), memberItem(14, .remove, .failed)])) == nil)
}
