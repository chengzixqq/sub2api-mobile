import Foundation
import Testing
@testable import Sub2Core

// 20 §8.2–§8.5: batches of 50, error classes, merged results, undo, receipts and the selection (S2-07).

private func reply(_ rows: [(Int, Bool)], successIDs: [Int]? = nil, failedIDs: [Int]? = nil, error: String? = nil) -> AccountBulkReply {
    let items = rows.map { AccountBulkReply.Item(accountID: $0.0, success: $0.1, error: $0.1 ? nil : error) }
    return AccountBulkReply(success: rows.filter(\.1).count, failed: rows.filter { !$0.1 }.count,
                            successIDs: successIDs ?? rows.filter(\.1).map(\.0), failedIDs: failedIDs ?? rows.filter { !$0.1 }.map(\.0),
                            results: items)
}
private func chunk(_ ids: [Int]) -> AccountBatchChunk { AccountBatchChunk(ids: ids, idempotencyKey: nil) }
private func outcome(enabled: Bool, succeeded: [Int], failures: [(Int, AccountBatchFailure)] = [], refusal: String? = nil) -> AccountBatchOutcome {
    AccountBatchOutcome(enabled: enabled, succeeded: succeeded, failures: failures.map { AccountBatchFailureRow(id: $0.0, failure: $0.1) },
                        refusal: refusal)
}

@Test func chunksSplitIntoFiftiesInSelectionOrder() {
    #expect(AccountBatchPlan.chunks(ids: [], keyed: false).isEmpty)
    #expect(AccountBatchPlan.chunks(ids: [7], keyed: false).map(\.ids) == [[7]])
    #expect(AccountBatchPlan.chunks(ids: Array(1...50), keyed: false).map(\.ids.count) == [50])
    #expect(AccountBatchPlan.chunks(ids: Array(1...51), keyed: false).map(\.ids.count) == [50, 1])
    let large = AccountBatchPlan.chunks(ids: Array((1...120).reversed()), keyed: false)
    #expect(large.map(\.ids.count) == [50, 50, 20])
    #expect(large.flatMap(\.ids) == Array((1...120).reversed()))
    // Repeated and non-positive ids are dropped; the rest keep the order they were first picked in.
    #expect(AccountBatchPlan.chunks(ids: [5, 0, 3, 5, -2, 9, 3], keyed: false).map(\.ids) == [[5, 3, 9]])
    for batch in large { #expect(batch.ids.count <= AccountBatchPlan.maxPerRequest && Set(batch.ids).count == batch.ids.count) }
}

@Test func chunksGetOneFreshKeyPerRequestOnlyWhenKeyed() {
    let keys = [UUID(), UUID(), UUID()]
    var made = 0
    let keyed = AccountBatchPlan.chunks(ids: Array(1...120), keyed: true) {
        defer { made += 1 }
        return keys[made]
    }
    #expect(keyed.map(\.idempotencyKey) == keys)
    var unused = 0
    let unkeyed = AccountBatchPlan.chunks(ids: Array(1...120), keyed: false) {
        unused += 1
        return UUID()
    }
    #expect(unkeyed.allSatisfy { $0.idempotencyKey == nil })
    #expect(unused == 0)
}

@Test func dispositionClassifiesErrorsByHTTPSemantics() {
    let unconfirmed: [any Error] = [
        KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil),
        KeyedWriteFailure(disposition: .unconfirmed(.stillProcessing, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil),
        KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil),
        KeyedWriteFailure(disposition: .unconfirmed(.unreadableResponse, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil),
        APIError.transport(URLError(.timedOut)), APIError.invalidResponse,
        APIError.server(status: 502, reason: nil), APIError.server(status: 504, reason: nil), APIError.server(status: 503, reason: nil),
        APIError.server(status: 408, reason: nil)
    ]
    for error in unconfirmed { #expect(AccountBatchPlan.disposition(of: error) == .unconfirmed, "\(error)") }
    let refused: [any Error] = [
        KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil),
        APIError.server(status: 500, reason: nil), APIError.server(status: 400, reason: nil),
        APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"), APIError.server(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED"),
        APIError.server(status: 429, reason: nil), APIError.server(status: 409, reason: "MIXED_CHANNEL_WARNING"),
        APIError(kind: .validation, message: "请选择 1 至 50 个不同账号。"), APIError.server(status: 503, reason: "STEP_UP_UNAVAILABLE")
    ]
    for error in refused { #expect(AccountBatchPlan.disposition(of: error) == .refused(error.localizedDescription), "\(error)") }
    #expect(AccountBatchPlan.disposition(of: APIError.server(status: 500, reason: nil)) == .refused("站点暂时不可用"))
    let cleared = APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.passed)
    #expect(AccountBatchPlan.disposition(of: cleared) == .refused("二次验证已通过，请重新确认后发送"))
    #expect(AccountBatchPlan.disposition(of: APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.cancelled)) == .cancelled)
    #expect(AccountBatchPlan.disposition(of: CancellationError()) == .cancelled)
}

@Test func mergeRepliedRowsIntoSucceededRejectedAndMissing() {
    // 3 has no row and 4 has two; 9 was not sent.
    let answer = reply([(9, true), (1, true), (2, false), (4, true), (4, true)], successIDs: [9, 1, 4, 4], failedIDs: [2])
    let merged = AccountBatchPlan.merge(chunks: [chunk([1, 2, 3, 4])], results: [.replied(answer)], enabled: false)
    #expect(merged.succeeded == [1])
    #expect(merged.failures == [AccountBatchFailureRow(id: 2, failure: .rejected), AccountBatchFailureRow(id: 3, failure: .missing),
                                AccountBatchFailureRow(id: 4, failure: .missing)])
    #expect(merged.refusal == nil && !merged.hasUnconfirmed && !merged.isUnsent && merged.enabled == false)
}

@Test func mergeStopsAfterRefusalAndMarksLaterChunksSkipped() {
    let chunks = [chunk([1, 2]), chunk([3, 4]), chunk([5])]
    let merged = AccountBatchPlan.merge(chunks: chunks, results: [.replied(reply([(1, true), (2, true)])), .refused(reason: "站点暂时不可用"), .skipped],
                                        enabled: true)
    #expect(merged.succeeded == [1, 2])
    #expect(merged.failures.map(\.id) == [3, 4, 5])
    #expect(merged.failures.map(\.failure) == [.rejected, .rejected, .skipped])
    #expect(merged.refusal == "站点暂时不可用")
    let first = AccountBatchPlan.merge(chunks: chunks, results: [.refused(reason: "站点暂时不可用"), .skipped, .skipped], enabled: true)
    #expect(first.succeeded.isEmpty && first.refusal == "站点暂时不可用" && !first.isUnsent)
    let cancelled = AccountBatchPlan.merge(chunks: chunks, results: [.skipped, .skipped, .skipped], enabled: true)
    #expect(cancelled.isUnsent && cancelled.failures.count == 5)
}

@Test func nextChunkGoesOnlyAfterOneThatClearlyRan() {
    let batch = chunk([1, 2])
    #expect(AccountBatchPlan.continues(after: .replied(reply([(1, true), (2, false)])), chunk: batch, enabled: false))
    #expect(AccountBatchPlan.continues(after: .unconfirmed(readback: [1: false, 2: false]), chunk: batch, enabled: false))
    #expect(!AccountBatchPlan.continues(after: .unconfirmed(readback: [1: false]), chunk: batch, enabled: false))
    #expect(!AccountBatchPlan.continues(after: .unconfirmed(readback: [1: false, 2: true]), chunk: batch, enabled: false))
    #expect(!AccountBatchPlan.continues(after: .unconfirmed(readback: nil), chunk: batch, enabled: false))
    #expect(!AccountBatchPlan.continues(after: .refused(reason: "站点暂时不可用"), chunk: batch, enabled: false))
    #expect(!AccountBatchPlan.continues(after: .skipped, chunk: batch, enabled: false))
}

@Test func mergeUnconfirmedChunkUsesReadback() {
    let merged = AccountBatchPlan.merge(chunks: [chunk([1, 2, 3])], results: [.unconfirmed(readback: [1: false, 2: true])], enabled: false)
    #expect(merged.succeeded == [1])
    #expect(merged.failures == [AccountBatchFailureRow(id: 2, failure: .unconfirmed), AccountBatchFailureRow(id: 3, failure: .missing)])
    #expect(merged.hasUnconfirmed)
    let unread = AccountBatchPlan.merge(chunks: [chunk([1, 2])], results: [.unconfirmed(readback: nil)], enabled: false)
    #expect(unread.succeeded.isEmpty && unread.failures.map(\.failure) == [.unconfirmed, .unconfirmed] && unread.hasUnconfirmed)
}

@Test func undoTargetsOnlyAccountsWhoseScheduleChanged() {
    let stopped = outcome(enabled: false, succeeded: [1, 2], failures: [(3, .rejected)])
    #expect(AccountBatchPlan.undoIDs(for: stopped, prior: [1: true, 2: false, 3: true]) == [1])
    let enabled = outcome(enabled: true, succeeded: [4, 5, 6])
    #expect(AccountBatchPlan.undoIDs(for: enabled, prior: [6: false, 4: false, 5: true]) == [4, 6])
    // An account the snapshot did not have is not undone.
    #expect(AccountBatchPlan.undoIDs(for: enabled, prior: [4: false]) == [4])
    #expect(AccountBatchPlan.undoIDs(for: stopped, prior: [1: false, 2: false]).isEmpty)
}

@Test func receiptCoversEveryOutcome() {
    let stopped = AccountBatchPlan.receipt(for: outcome(enabled: false, succeeded: [1, 2, 3]), isUndo: false, canUndo: true)
    #expect(stopped == AccountBatchReceipt(kind: .done, text: "已停止调度 3 个账号", systemImage: "pause.fill", tone: .neutral, offersUndo: true,
                                           offersDetails: false, keepsSelection: false))
    let enabled = AccountBatchPlan.receipt(for: outcome(enabled: true, succeeded: [1, 2, 3]), isUndo: false, canUndo: true)
    #expect(enabled.text == "已启用调度 3 个账号" && enabled.tone == .ok && enabled.systemImage == "play.fill" && enabled.offersUndo)
    #expect(!AccountBatchPlan.receipt(for: outcome(enabled: true, succeeded: [1]), isUndo: false, canUndo: false).offersUndo)
    let partial = AccountBatchPlan.receipt(for: outcome(enabled: true, succeeded: [1, 2], failures: [(3, .rejected)]), isUndo: false, canUndo: true)
    #expect(partial.kind == .partial && partial.text == "已启用调度 2 个账号 · 1 个失败" && partial.tone == .caution)
    #expect(partial.offersDetails && !partial.offersUndo && !partial.keepsSelection)
    let refused = AccountBatchPlan.receipt(for: outcome(enabled: false, succeeded: [], failures: [(1, .rejected), (2, .skipped)], refusal: "站点暂时不可用"),
                                           isUndo: false, canUndo: false)
    #expect(refused == AccountBatchReceipt(kind: .failed, text: "批量操作没有成功：站点暂时不可用", systemImage: "exclamationmark.triangle",
                                           tone: .critical, offersUndo: false, offersDetails: false, keepsSelection: true))
    let rowsFailed = AccountBatchPlan.receipt(for: outcome(enabled: false, succeeded: [], failures: [(1, .rejected), (2, .missing)]),
                                              isUndo: false, canUndo: false)
    #expect(rowsFailed.kind == .failed && rowsFailed.text == "批量操作没有成功：2 个账号失败" && rowsFailed.offersDetails && rowsFailed.keepsSelection)
    let unknown = AccountBatchPlan.receipt(for: outcome(enabled: false, succeeded: [], failures: [(1, .unconfirmed), (2, .missing)]),
                                           isUndo: false, canUndo: false)
    #expect(unknown.kind == .unconfirmed && unknown.text == "结果未确认，请刷新核对后再操作" && unknown.tone == .caution)
    #expect(unknown.offersDetails && !unknown.keepsSelection && !unknown.offersUndo)
    #expect(AccountBatchPlan.receipt(for: outcome(enabled: false, succeeded: Array(1...1_200)), isUndo: false, canUndo: true).text
            == "已停止调度 1,200 个账号")
    let undone = AccountBatchPlan.receipt(for: outcome(enabled: true, succeeded: [1, 2]), isUndo: true, canUndo: true)
    #expect(undone.text == "已启用调度 2 个账号" && !undone.offersUndo)
    #expect(AccountBatchPlan.receipt(for: outcome(enabled: true, succeeded: [], failures: [(1, .rejected)], refusal: "站点暂时不可用"), isUndo: true,
                                     canUndo: false).text == "撤销没有成功：站点暂时不可用")
    #expect(AccountBatchPlan.receipt(for: outcome(enabled: true, succeeded: [], failures: [(1, .rejected), (2, .rejected)]), isUndo: true,
                                     canUndo: false).text == "撤销没有成功：2 个账号失败")
}

@Test func failureRowsNeverShowServerErrorText() {
    #expect(AccountBatchPlan.rowTitle(name: "主账号", id: 7) == "主账号（#7）")
    #expect(AccountBatchPlan.rowTitle(name: nil, id: 7) == "#7")
    #expect(AccountBatchPlan.rowTitle(name: "  ", id: 7) == "#7")
    #expect(AccountBatchFailure.rejected.text == "服务器拒绝")
    #expect(AccountBatchFailure.unconfirmed.text == "结果不明")
    #expect(AccountBatchFailure.missing.text == "未返回此账号的明确结果，请先刷新核对")
    #expect(AccountBatchFailure.skipped.text == "尚未执行，请重新选择")
    let secret = "upstream key sk-test-secret"
    let merged = AccountBatchPlan.merge(chunks: [chunk([1, 2])], results: [.replied(reply([(1, true), (2, false)], error: secret))], enabled: false)
    let receipt = AccountBatchPlan.receipt(for: merged, isUndo: false, canUndo: true)
    let shown = [receipt.text] + merged.failures.map(\.failure.text) + [String(describing: merged)]
    #expect(shown.allSatisfy { !$0.contains("sk-test-secret") })
}

@Test func batchChromeCopy() {
    #expect(AccountBatchPlan.selectedCount(0) == "已选 0 个" && AccountBatchPlan.selectedCount(1_234) == "已选 1,234 个")
    #expect(AccountBatchPlan.pickedInSection(3) == "已选 3")
    #expect(AccountBatchPlan.sectionToggleTitle(allSelected: false) == "全选" && AccountBatchPlan.sectionToggleTitle(allSelected: true) == "取消全选")
    #expect(AccountBatchPlan.undoTitle(original: false, count: 2) == "撤销已停止调度的 2 个")
    #expect(AccountBatchPlan.undoTitle(original: true, count: 1) == "撤销已启用调度的 1 个")
    #expect(AccountBatchPlan.resultsTitle == "批量操作结果" && AccountBatchPlan.detailsAction == "查看")
}

@Test func selectionTogglesSectionsAndKeepsOnlyLoadedRows() {
    let empty = AccountSelection()
    let one = empty.toggling(3)
    #expect(one.contains(3) && one.count == 1 && empty.isEmpty)
    #expect(one.toggling(3).isEmpty)
    let section = [1, 2, 3]
    let partial = AccountSelection([2, 9])
    let all = partial.togglingAll(section)
    #expect(all.ids == [1, 2, 3, 9])
    #expect(all.togglingAll(section).ids == [9])
    #expect(partial.togglingAll([]) == partial)
    #expect(partial.pickedCount(in: section) == 1 && all.pickedCount(in: section) == 3)
    #expect(all.allSelected(section) && !partial.allSelected(section) && !all.allSelected([]))
    #expect(all.keeping([1, 3, 4]).ids == [1, 3])
    #expect(all.ordered(by: [9, 8, 3, 2, 1]) == [9, 3, 2, 1])
}
