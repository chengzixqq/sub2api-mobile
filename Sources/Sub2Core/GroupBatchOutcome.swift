import Foundation

/// 5.2: an account's name and state when the change was sent (the App keeps no session-wide account cache).
public struct GroupBatchAccount: Sendable, Equatable {
    public let name: String
    /// nil: the page draws the “停用” glyph.
    public let state: AccountStateInput?
    public init(name: String, state: AccountStateInput? = nil) { self.name = name; self.state = state }
    public init(_ account: UpstreamAccount) { self.init(name: account.name, state: AccountStateInput(account)) }
}

/// One row of 50 §5.3.
public struct GroupBatchItem: Sendable, Equatable, Identifiable {
    public enum Success: Sendable, Equatable { case added, removed, unchanged, undone, retriedAdded(changed: Bool), retriedRemoved(changed: Bool) }
    public enum Failure: Sendable, Equatable {
        case notFound
        case mixedChannel(GroupMemberMixedChannel?)
        /// Never sent (REQUEST_NOT_DELIVERED).
        case requestFailed
        /// Sent, but whether it ran is unknown (REQUEST_UNCONFIRMED, S5D2a-17).
        case unconfirmed
        case other(reason: String?)
        init(reason: String?, details: GroupMemberMixedChannel?) {
            switch reason ?? "" {
            case GroupMemberReason.accountNotFound: self = .notFound
            case GroupMemberReason.mixedChannelRisk: self = .mixedChannel(details)
            case GroupMemberReason.notDelivered: self = .requestFailed
            case GroupMemberReason.notConfirmed: self = .unconfirmed
            default: self = .other(reason: reason)
            }
        }
    }
    public enum Result: Sendable, Equatable { case succeeded(Success), failed(Failure) }
    public let accountID: Int
    public let name: String
    public let state: AccountStateInput?
    public let action: GroupMemberAction
    public let result: Result
    /// An add's requested priority, the answer's once there is one; a removal's old priority, which its undo brings back.
    public let priority: Int?
    public init(accountID: Int, name: String, state: AccountStateInput? = nil, action: GroupMemberAction, result: Result, priority: Int? = nil) {
        self.accountID = accountID; self.name = name; self.state = state; self.action = action; self.result = result; self.priority = priority
    }
    /// A request names an account on one side only.
    public var id: Int { accountID }
    public var isFailed: Bool {
        switch result { case .failed: true; case .succeeded: false }
    }
    /// Every failure but a missing account: the endpoint answers a resend `unchanged` where it already ran.
    public var isRetryable: Bool {
        switch result { case .failed(.notFound), .succeeded: false; case .failed: true }
    }
    public var needsMixedChannelConfirmation: Bool {
        if case .failed(.mixedChannel) = result { return true }
        return false
    }
    public var isUndoable: Bool {
        switch result {
        case .succeeded(.added), .succeeded(.removed), .succeeded(.retriedAdded(changed: true)), .succeeded(.retriedRemoved(changed: true)): true
        default: false
        }
    }
    public var isUndone: Bool { result == .succeeded(.undone) }
    public var resultLabel: String {
        switch result {
        case .failed: action == .add ? "加入失败" : "移出失败"
        case .succeeded(.added): "已加入"
        case .succeeded(.removed): "已移出"
        case .succeeded(.retriedAdded): "重试后已加入"
        case .succeeded(.retriedRemoved): "重试后已移出"
        case .succeeded(.unchanged): "无需改动"
        case .succeeded(.undone): "已撤销"
        }
    }
    /// The second line of a failed row.
    public var reasonText: String? {
        guard case .failed(let failure) = result else { return nil }
        return GroupBatchCopy.reason(failure)
    }
    var mixedChannelDetails: GroupMemberMixedChannel? {
        guard case .failed(.mixedChannel(let details)) = result else { return nil }
        return details
    }
    /// An account the answer left out may have run (S5D2a-17).
    static func result(of answer: GroupMemberResultItem?) -> Result {
        guard let answer else { return .failed(.unconfirmed) }
        switch answer.status {
        case .added: return .succeeded(.added)
        case .removed: return .succeeded(.removed)
        case .unchanged: return .succeeded(.unchanged)
        case .failed: return .failed(Failure(reason: answer.reason, details: answer.details))
        }
    }
    /// After a retry: a change is undoable, an `unchanged` says “重试后…” without being undoable, a failure takes its new reason.
    func retried(by answer: GroupMemberResultItem) -> GroupBatchItem {
        let changed = answer.changedMembership
        let next: Result = answer.status == .failed ? .failed(Failure(reason: answer.reason, details: answer.details))
            : .succeeded(action == .add ? .retriedAdded(changed: changed) : .retriedRemoved(changed: changed))
        return replacing(next, priority: changed ? answer.priority ?? priority : priority)
    }
    func replacing(_ result: Result, priority: Int?) -> GroupBatchItem {
        GroupBatchItem(accountID: accountID, name: name, state: state, action: action, result: result, priority: priority)
    }
}

public enum GroupBatchStep: Sendable, Equatable { case retry, undo }

/// 5.4: asked before the mixed-channel items go out again.
public struct GroupMixedChannelConfirmation: Sendable, Equatable {
    public static let cancelTitle = "取消"
    public let title: String
    public let message: String
    public let confirmTitle: String
    /// The other platforms once each, in order, joined with “、”.
    public init(otherPlatforms: [String]) {
        var seen = Set<String>()
        let others = otherPlatforms.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: "、")
        title = "仍然加入混合渠道账号？"
        message = (others.isEmpty ? "分组里已有其他渠道的账号。" : "分组里已有 \(others) 账号。")
            + "同一分组混用 Anthropic 与 Antigravity 账号可能导致思考块签名校验失败，历史消息会降级为非思考模式。"
        confirmTitle = "仍然加入"
    }
}

/// 5.4 “重试 n 个”: what failed for the request goes out as it was; the mixed-channel items go alone with the confirmation,
/// because the server skips the check for every add of a confirmed request.
public struct GroupBatchRetryPlan: Sendable, Equatable {
    public let resend: GroupMemberBatchRequest?
    public let mixedChannel: GroupMemberBatchRequest?
    /// Only with `mixedChannel`.
    public let confirmation: GroupMixedChannelConfirmation?
    public var isEmpty: Bool { resend == nil && mixedChannel == nil }
}

public enum GroupBatchStatusCard: Sendable, Equatable {
    /// caution: GroupBatchCopy.failedBadge, succeededText and failureNote.
    case failures(failed: Int, succeeded: Int)
    /// The quiet card, “全部完成 · 已加入 2 个账号”.
    case allDone(String)
    case allUndone
}

/// 50 §5: the per-item results of one member write, then its retries and undos. Every change returns a new value.
public struct GroupBatchOutcome: Sendable, Equatable {
    public let groupID: Int
    public let groupName: String
    public let items: [GroupBatchItem]
    public init(groupID: Int, groupName: String, items: [GroupBatchItem]) { self.groupID = groupID; self.groupName = groupName; self.items = items }
    /// In request order (adds first). An account without a snapshot is “账号 #id” with no state.
    public init(groupID: Int, groupName: String, request: GroupMemberBatchRequest, result: GroupMemberBatchResult, accounts: [Int: GroupBatchAccount] = [:]) {
        let answers = result.answers
        let requested = Dictionary(request.add.compactMap { add in add.priority.map { (add.accountID, $0) } }, uniquingKeysWith: { first, _ in first })
        let items = request.keys.map { key in
            let answer = answers[key], account = accounts[key.accountID]
            return GroupBatchItem(accountID: key.accountID, name: account?.name ?? GroupBatchCopy.unnamedAccount(key.accountID), state: account?.state,
                                  action: key.action, result: GroupBatchItem.result(of: answer),
                                  priority: answer?.priority ?? (key.action == .add ? requested[key.accountID] : nil))
        }
        self.init(groupID: groupID, groupName: groupName, items: items)
    }
    /// 壹 · 失败, in order.
    public var failures: [GroupBatchItem] { items.filter(\.isFailed) }
    /// 贰 · 成功, in order, the undone ones last.
    public var successes: [GroupBatchItem] { items.filter { !$0.isFailed && !$0.isUndone } + items.filter(\.isUndone) }
    /// The status card's and 贰's count: successes not undone, unchanged included.
    public var succeededCount: Int { items.filter { !$0.isFailed && !$0.isUndone }.count }
    /// “重试 n 个”.
    public var retryableCount: Int { items.filter(\.isRetryable).count }
    /// “撤销成功的 s 个”.
    public var undoableCount: Int { items.filter(\.isUndoable).count }
    public var statusCard: GroupBatchStatusCard {
        let failed = failures.count
        if failed > 0 { return .failures(failed: failed, succeeded: succeededCount) }
        if items.contains(where: \.isUndone), undoableCount == 0 { return .allUndone }
        let kept = items.filter { !$0.isUndone }
        return .allDone(GroupBatchCopy.allDone(GroupMemberReceipt.summary(added: kept.filter { $0.action == .add }.count,
                                                                          removed: kept.filter { $0.action == .remove }.count)))
    }
    public func retryPlan() -> GroupBatchRetryPlan {
        let retryable = items.filter(\.isRetryable)
        let mixed = retryable.filter(\.needsMixedChannelConfirmation)
        let mixedRequest = Self.request(mixed, confirm: true)
        return GroupBatchRetryPlan(resend: Self.request(retryable.filter { !$0.needsMixedChannelConfirmation }, confirm: false), mixedChannel: mixedRequest,
                                   confirmation: mixedRequest.map { _ in GroupMixedChannelConfirmation(otherPlatforms: mixed.compactMap { $0.mixedChannelDetails?.otherPlatform }) })
    }
    /// 0.4.3's reverse request for the undoable items, never confirmed.
    public func undoPlan() -> GroupMemberBatchRequest? {
        let undoable = items.filter(\.isUndoable)
        return GroupMemberBatchRequest.nonEmpty(add: undoable.filter { $0.action == .remove }.map { GroupMemberAdd(accountID: $0.accountID, priority: $0.priority) },
                                                remove: undoable.filter { $0.action == .add }.map(\.accountID), confirm: false)
    }
    /// A retry changes only retryable items by the answer for the same account and action; an undo only undoable items by the
    /// answer for the reverse action (a failed undo leaves the item as it was). Other answers are ignored.
    public func applying(_ result: GroupMemberBatchResult, as step: GroupBatchStep) -> GroupBatchOutcome {
        let answers = result.answers
        let updated = items.map { (item: GroupBatchItem) -> GroupBatchItem in
            switch step {
            case .retry:
                guard item.isRetryable, let answer = answers[GroupMemberKey(accountID: item.accountID, action: item.action)] else { return item }
                return item.retried(by: answer)
            case .undo:
                guard item.isUndoable, answers[GroupMemberKey(accountID: item.accountID, action: item.action.inverse)]?.isSuccess == true else { return item }
                return item.replacing(.succeeded(.undone), priority: item.priority)
            }
        }
        return GroupBatchOutcome(groupID: groupID, groupName: groupName, items: updated)
    }
    /// 5.4, shown on the page itself, so without a button: “重试成功 · …”, or 0.4.3's words when some still failed.
    public static func retryReceipt(_ result: GroupMemberBatchResult) -> GroupMemberReceipt {
        guard result.failed == 0 else {
            let receipt = GroupMemberReceipt(result: result, activeBefore: nil)
            return GroupMemberReceipt(text: receipt.text, systemImage: receipt.systemImage, tone: receipt.tone, button: nil)
        }
        let summary = GroupMemberReceipt.summary(added: result.succeeded(.add), removed: result.succeeded(.remove))
        return GroupMemberReceipt(text: "重试成功" + (summary.map { " · " + $0 } ?? ""), systemImage: "checkmark.circle", tone: .ok, button: nil)
    }
    /// 5.4 “已撤销 s 个账号的改动”, or how many could not be undone.
    public static func undoReceipt(_ result: GroupMemberBatchResult) -> GroupMemberReceipt {
        let undone = DisplayFormat.grouped(result.results.filter(\.isSuccess).count), failed = DisplayFormat.grouped(result.failed)
        if result.failed == 0 { return GroupMemberReceipt(text: "已撤销 \(undone) 个账号的改动", systemImage: "arrow.uturn.backward.circle", tone: .neutral, button: nil) }
        if result.results.contains(where: \.isSuccess) {
            return GroupMemberReceipt(text: "已撤销 \(undone) 个账号的改动 · \(failed) 个没有撤销", systemImage: "exclamationmark.triangle", tone: .caution, button: nil)
        }
        return GroupMemberReceipt(text: "撤销没有成功 · \(failed) 个账号没有改动", systemImage: "xmark.octagon", tone: .critical, button: nil)
    }
    /// Each item's own action; an add carries its priority.
    private static func request(_ items: [GroupBatchItem], confirm: Bool) -> GroupMemberBatchRequest? {
        GroupMemberBatchRequest.nonEmpty(add: items.filter { $0.action == .add }.map { GroupMemberAdd(accountID: $0.accountID, priority: $0.priority) },
                                         remove: items.filter { $0.action == .remove }.map(\.accountID), confirm: confirm)
    }
}

/// 50 §5.3–§5.5 words; numbers grouped.
public enum GroupBatchCopy {
    public static let title = "逐项结果"
    public static let failureNote = "失败的账号没有改动，可以直接重试，或点开账号单独处理。"
    /// 5.5: the retry or undo request itself failed; the items stay as they were.
    public static let requestFailed = "没有完成，请稍后重试"
    public static let allUndone = "已全部撤销"
    public static let notFound = "账号不存在或已删除"
    public static let notDelivered = "请求没有送达，账号没有改动"
    public static let unconfirmed = "结果未确认，可以重试"
    public static func subtitle(groupName: String, count: Int) -> String { "\(groupName) · \(DisplayFormat.grouped(count)) 个账号" }
    public static func failedBadge(_ count: Int) -> String { "\(DisplayFormat.grouped(count)) 个失败" }
    public static func succeededText(_ count: Int) -> String { "\(DisplayFormat.grouped(count)) 个成功" }
    public static func failuresMeta(_ count: Int) -> String { "\(DisplayFormat.grouped(count)) 个 · 没有改动" }
    public static func successesMeta(_ count: Int) -> String { "\(DisplayFormat.grouped(count)) 个" }
    public static func retryButton(_ count: Int) -> String { "重试 \(DisplayFormat.grouped(count)) 个" }
    public static func undoButton(_ count: Int) -> String { "撤销成功的 \(DisplayFormat.grouped(count)) 个" }
    public static func allDone(_ summary: String?) -> String { summary.map { "全部完成 · " + $0 } ?? "全部完成" }
    /// An account submitted without a snapshot.
    public static func unnamedAccount(_ id: Int) -> String { "账号 #\(id)" }
    public static func mixedChannel(_ details: GroupMemberMixedChannel?) -> String {
        guard let details else { return "分组里已有其他渠道的账号，混用有风险" }
        return "分组里已有 \(details.otherPlatform) 账号，与 \(details.currentPlatform) 账号混用有风险"
    }
    /// R11: GroupErrorCopy's words for the reason, else its stable code, else nothing of it; never the server's message.
    public static func otherFailure(reason: String?) -> String {
        if let reason, let text = GroupErrorCopy.reasonText(reason, context: .members) { return text }
        guard let code = ReasonCatalog.displayCode(reason) else { return "没有完成，账号没有改动" }
        return "没有完成（错误码 \(code)），账号没有改动"
    }
    public static func reason(_ failure: GroupBatchItem.Failure) -> String {
        switch failure {
        case .notFound: notFound
        case .mixedChannel(let details): mixedChannel(details)
        case .requestFailed: notDelivered
        case .unconfirmed: unconfirmed
        case .other(let reason): otherFailure(reason: reason)
        }
    }
}
