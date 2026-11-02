import Foundation
import Sub2Core

// 50 §3.4 新建 3–4 / 编辑 3–4 and §3.5 成员写入失败 (S5-11): after the group's own step the members go out through S5-08's
// GroupMemberWriter, and one receipt carries the group's prefix (0.4.3). A failure of the members never takes back the group's
// success. All done gives no 撤销 here: it would undo the members only, not the creation or the fields. With members only there
// is no success of the group's to report: a refusal stays on the sheet (§3.5 其他明确失败), and 已保存「名称」 leads the receipt
// only when a member changed.

extension GroupEditSaved {
    /// 已创建「名称」 / 已保存「名称」 in front of the member words.
    var memberPrefix: GroupMemberReceipt.Prefix {
        switch kind {
        case .created: .created(name: group.name)
        case .saved(let dropped): .saved(name: group.name, droppedFields: dropped)
        }
    }
    /// “可用 x → y”'s x: none in a group just created (its POST reply counts nothing), else the PUT reply's or, with members only,
    /// the group's as the sheet opened it.
    var activeBefore: Int { kind == .created ? 0 : group.counts.activeAccountCount }
}

/// The members' answer for the sheet: close with one receipt (nil when the answer was for another session), or stay with the
/// refusal in red when it was the sheet's only write.
enum GroupEditMemberStep: Sendable {
    case close(Receipt?)
    case refused(String)
}

extension GroupEditFlow {
    /// The members' write and what the sheet does with its answer. `wroteGroup` false: only members changed.
    func memberStep(_ plan: GroupMemberCommitPlan, after saved: GroupEditSaved, wroteGroup: Bool, writer: GroupMemberWriter) async -> GroupEditMemberStep {
        let write = GroupEditMemberWrite(writer: writer, receipts: receipts, openResults: openResults, plan: plan, group: saved.group,
                                         activeBefore: saved.activeBefore)
        let sent = await writer.send(plan.request, to: saved.group.id)
        if !wroteGroup, case .rejected(let reason) = sent { return .refused(reason) }
        return .close(write.receipt(sent, prefix: wroteGroup || sent.changedMembers ? saved.memberPrefix : .none))
    }
}

private extension GroupMemberSendResult {
    /// At least one item went through.
    var changedMembers: Bool {
        guard case .result(let result, _) = self else { return false }
        return result.failed < result.results.count
    }
}

/// One member write of the sheet and what its receipt's buttons need once the sheet has closed: the writer (it holds the session),
/// the receipts and the per-item page.
private struct GroupEditMemberWrite: Sendable {
    let writer: GroupMemberWriter
    let receipts: ReceiptCenter
    let openResults: (@MainActor @Sendable (GroupBatchOutcome) -> Void)?
    let plan: GroupMemberCommitPlan
    let group: AdminGroup
    let activeBefore: Int

    /// `.result` as 0.4.3 (查看 when something failed); 网络错误 / 超时 “… · 成员改动未确认” with 重试; a refusal “… · 成员没有改动：…”;
    /// a deleted group says so; `.ignored` nothing.
    @MainActor func receipt(_ sent: GroupMemberSendResult, prefix: GroupMemberReceipt.Prefix) -> Receipt? {
        switch sent {
        case .result(let result, _):
            let copy = GroupMemberReceipt(result: result, prefix: prefix, activeBefore: activeBefore)
            return Receipt(text: copy.text, systemImage: copy.systemImage, tone: copy.tone, action: copy.button == .details ? details(result) : nil)
        case .unconfirmed:
            let copy = GroupMemberReceipt.unconfirmed
            return Receipt(text: GroupMemberDraftCopy.unconfirmedAfterSave(prefix), systemImage: copy.systemImage, tone: copy.tone,
                           action: ReceiptAction(title: GroupReceiptButton.retry.title) { resend() })
        case .rejected(let reason):
            let text = prefix == GroupMemberReceipt.Prefix.none ? reason : GroupMemberDraftCopy.rejectedAfterSave(prefix, reason: reason)
            return Receipt(text: text, systemImage: "exclamationmark.triangle", tone: .caution)
        case .groupGone(let text): return Receipt(text: text, systemImage: "xmark.octagon", tone: .critical)
        case .ignored: return nil
        }
    }

    private func details(_ result: GroupMemberBatchResult) -> ReceiptAction? {
        guard let openResults else { return nil }
        let outcome = GroupBatchOutcome(groupID: group.id, groupName: group.name, request: plan.request, result: result, accounts: plan.snapshots)
        return ReceiptAction(title: GroupReceiptButton.view.title) { openResults(outcome) }
    }
    /// The same request again in the session of the first write; its receipt says the members only.
    @MainActor private func resend() {
        Task {
            if let receipt = receipt(await writer.send(plan.request, to: group.id), prefix: .none) { receipts.show(receipt) }
        }
    }
}
