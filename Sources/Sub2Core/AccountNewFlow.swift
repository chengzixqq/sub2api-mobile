import Foundation

/// Where the created account stands in the scheduler: the third part of the sheet subtitle (20 §7.1).
public enum AccountNewScheduleStatus: String, Sendable, CaseIterable {
    case paused, error, unconfirmed, active
    public var title: String {
        switch self {
        case .paused: "暂停调度"
        case .error: "错误（已停止调度）"
        case .unconfirmed: "调度状态待核对"
        case .active: "参与调度"
        }
    }
}

/// The create request fixed when “创建并测试” is tapped (R05): its bytes, its key (nil on a site without admin.idempotent_writes)
/// and the ServerTime of the first send, which bounds the by-name check of an unknown result.
public struct AccountNewFrozenRequest: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let request: AccountCreateRequest
    public let key: UUID?
    public let submittedAt: Date
    public init(request: AccountCreateRequest, key: UUID?, submittedAt: Date) { self.request = request; self.key = key; self.submittedAt = submittedAt }
    /// “继续创建”: the body changes, so a keyed request takes a new key (00 §2.5.2); the first send time stays.
    public func confirmingMixedChannel(renewingKeyWith newKey: UUID) -> AccountNewFrozenRequest {
        AccountNewFrozenRequest(request: request.confirmingMixedChannel(), key: key == nil ? nil : newKey, submittedAt: submittedAt)
    }
    public var description: String { "AccountNewFrozenRequest(\(request.platform), \(request.type), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// What 取消 does in the new-account sheet (20 §7.4-4, design cancel).
public enum AccountNewCancelAction: Sendable, Equatable {
    /// No platform picked: just close.
    case close
    /// Ask with the draft's discardConfirmation.
    case confirmDiscard
    /// A create, stop-scheduling or save request is out: the sheet cannot close.
    case blocked
    /// Testing or enabling: hand the run to the background (4.4).
    case continueInBackground
    /// Passed: close with the receipt.
    case finish
    /// “账号「{name}」可能还在参与调度”.
    case resolvePauseFailed
    /// “账号「{name}」已创建，怎么处理？”.
    case resolveCreated
    /// The create's result is still unknown (00 §2.5.4: the sheet stays): “账号「{name}」可能已经创建”.
    case resolveUnconfirmed
}

/// The new-account flow's shared rules (S2D1-13): plain functions and copy. The create and stop-scheduling stages are S2-19's,
/// the test and enable stages S2-20's.
public enum AccountNewFlow {
    /// “{站点} · 还差 N 项 / 必填已填齐” before creating; “{站点} · #{id} 已创建 · {调度状态}” after.
    public static func subtitle(site: String, missingCount: Int, createdID: Int?, status: AccountNewScheduleStatus) -> String {
        guard let createdID else { return missingCount > 0 ? "\(site) · 还差 \(missingCount) 项" : "\(site) · 必填已填齐" }
        return "\(site) · #\(createdID) 已创建 · \(status.title)"
    }
    /// The dock's main button, also the test sheet's title.
    public static func dockActionTitle(isCreated: Bool, hasChanges: Bool) -> String {
        guard isCreated else { return "创建并测试" }
        return hasChanges ? "保存并重新测试" : "重新测试"
    }
    /// `resultUnconfirmed`: the create's result and the check by name are both unknown, so the account may exist.
    public static func cancelAction(hasPlatform: Bool, isCreated: Bool, isBusy: Bool, isTesting: Bool, isPassed: Bool,
                                    pauseUnconfirmed: Bool, resultUnconfirmed: Bool = false) -> AccountNewCancelAction {
        if !hasPlatform, !isCreated, !resultUnconfirmed { return .close }
        if isTesting { return .continueInBackground }
        if isBusy { return .blocked }
        if resultUnconfirmed { return .resolveUnconfirmed }
        if isPassed { return .finish }
        if pauseUnconfirmed { return .resolvePauseFailed }
        return isCreated ? .resolveCreated : .confirmDiscard
    }
    /// 20 §7.4-1: without accounts.mixed_channel_details an Anthropic / Antigravity account with groups is checked before sending,
    /// unless these groups were already accepted in this flow.
    public static func needsMixedChannelPrecheck(platform: String, groupIDs: [Int], hasMixedChannelDetails: Bool, alreadyConfirmed: Bool) -> Bool {
        [OAuthPlatform.anthropic.rawValue, OAuthPlatform.antigravity.rawValue].contains(platform) && !groupIDs.isEmpty
            && !hasMixedChannelDetails && !alreadyConfirmed
    }
    /// A 409 MIXED_CHANNEL_WARNING, or an older server's 409 without a reason (error / message only): when MixedChannelWarning(error:)
    /// is nil, the caller asks check-mixed-channel for the group. A 409 can come without groups too (the default group joined).
    public static func mayBeMixedChannelConflict(_ error: APIError) -> Bool {
        guard error.statusCode == 409 else { return false }
        return error.reason == AccountWriteReason.mixedChannelWarning || (error.reason ?? "").isEmpty
    }
    /// 20 §7.3: the test marked the account as an error, or it reads back as one.
    public static func heldInError(markedError: Bool?, statusAfterTest: String?) -> Bool {
        markedError == true || statusAfterTest == "error"
    }
}
