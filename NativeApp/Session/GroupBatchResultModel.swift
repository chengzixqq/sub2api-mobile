import Foundation
import Observation
import Sub2Core

/// 50 §5.4: how the page sends. In the App S5-08's GroupMemberWriter.send (the batch, the 0.4.4 fallback or the `-ui-testing`
/// fixtures; the group list and detail read again afterwards), stubs in tests.
struct GroupBatchEndpoints: Sendable {
    typealias Send = @MainActor @Sendable (GroupMemberBatchRequest) async -> GroupMemberSendResult
    let send: Send
}

enum GroupBatchRunOutcome: Sendable, Equatable {
    /// Every item sent went through.
    case done
    /// Answered, some items still failed.
    case stillFailing
    /// 仍然加入混合渠道账号？ is up; nothing sent yet.
    case needsConfirmation
    /// A request did not finish: what arrived before it is applied, the rest is as it was, the red line says why.
    case failed
    /// Running already, nothing to send, another session meanwhile or cancelled.
    case ignored
}

/// 50 §5.4 and §5.5, the per-item results of one member write (S5-09). 重试 n 个 resends what failed for the request as it was
/// and, once 仍然加入 is tapped, the mixed-channel items alone with `confirm_mixed_channel_risk` (the server skips the check for
/// every add of a confirmed request); 取消 sends nothing. 撤销成功的 s 个 sends the reverse. Each answer goes through S5-03's
/// `applying`; after the last one S5-03's receipt. A request that did not finish stops there with the red line, the items it
/// did not reach unchanged. One run at a time; answers from another session are dropped.
@MainActor @Observable
final class GroupBatchResultModel {
    enum Running: Sendable, Equatable { case retry, undo }
    private(set) var outcome: GroupBatchOutcome
    private(set) var running: Running?
    /// 5.5's red line under the status card; cleared when the next run starts.
    private(set) var failureLine: String?
    private(set) var mixedChannelPrompt: GroupMixedChannelConfirmation?

    @ObservationIgnored private let endpoints: GroupBatchEndpoints
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let isCurrent: @MainActor () -> Bool

    init(outcome: GroupBatchOutcome, endpoints: GroupBatchEndpoints, receipts: ReceiptCenter, isCurrent: @escaping @MainActor () -> Bool) {
        self.outcome = outcome; self.endpoints = endpoints; self.receipts = receipts; self.isCurrent = isCurrent
    }

    var retryCount: Int { outcome.retryableCount }
    var undoCount: Int { outcome.undoableCount }

    /// With mixed-channel items only the prompt goes up; otherwise the resend goes out.
    @discardableResult func retry() async -> GroupBatchRunOutcome {
        guard running == nil, isCurrent() else { return .ignored }
        let plan = outcome.retryPlan()
        guard !plan.isEmpty else { return .ignored }
        if let confirmation = plan.confirmation {
            mixedChannelPrompt = confirmation
            return .needsConfirmation
        }
        return await run(.retry, [plan.resend].compactMap { $0 })
    }
    /// 仍然加入: the plain resend first, then the mixed-channel items with the confirmation.
    @discardableResult func confirmMixedChannel() async -> GroupBatchRunOutcome {
        mixedChannelPrompt = nil
        guard running == nil, isCurrent() else { return .ignored }
        let plan = outcome.retryPlan()
        guard plan.mixedChannel != nil else { return .ignored }
        return await run(.retry, [plan.resend, plan.mixedChannel].compactMap { $0 })
    }
    func cancelMixedChannel() { mixedChannelPrompt = nil }
    @discardableResult func undo() async -> GroupBatchRunOutcome {
        guard running == nil, isCurrent(), let reverse = outcome.undoPlan() else { return .ignored }
        return await run(.undo, [reverse])
    }

    private func run(_ step: Running, _ requests: [GroupMemberBatchRequest]) async -> GroupBatchRunOutcome {
        running = step
        failureLine = nil
        defer { running = nil }
        var answered: GroupMemberBatchResult?
        for request in requests {
            let sent = await endpoints.send(request)
            guard isCurrent() else { return .ignored }
            switch sent {
            case .result(let result, _):
                outcome = outcome.applying(result, as: step == .retry ? .retry : .undo)
                answered = answered.map { $0.merging(result) } ?? result
            case .rejected(let text), .groupGone(let text):
                failureLine = text
                return .failed
            case .unconfirmed:
                failureLine = GroupBatchCopy.requestFailed
                return .failed
            case .ignored: return .ignored
            }
        }
        guard let answered else { return .ignored }
        let receipt = step == .retry ? GroupBatchOutcome.retryReceipt(answered) : GroupBatchOutcome.undoReceipt(answered)
        receipts.show(Receipt(text: receipt.text, systemImage: receipt.systemImage, tone: receipt.tone))
        return answered.failed == 0 ? .done : .stillFailing
    }
}
