import Foundation

/// 20 §5: the four account actions by the word their receipts use.
public enum AccountActionKind: Sendable, Equatable {
    case recover, setSchedulable(Bool), enableAccount, undo
    public var verb: String {
        switch self {
        case .recover: "恢复状态"
        case .setSchedulable(let enabled): enabled ? "启用调度" : "停止调度"
        case .enableAccount: "启用账号"
        case .undo: "撤销"
        }
    }
}

/// A receipt's one button (20 §5.3).
public enum AccountReceiptButton: Sendable, Equatable {
    case undo, enableScheduling, retry
    public var title: String {
        switch self {
        case .undo: "撤销"
        case .enableScheduling: "启用调度"
        case .retry: "重试"
        }
    }
}

public struct AccountReceiptCopy: Sendable, Equatable {
    public let text: String
    public let systemImage: String
    public let tone: Tone
    public let button: AccountReceiptButton?
    public init(text: String, systemImage: String, tone: Tone, button: AccountReceiptButton?) {
        self.text = text; self.systemImage = systemImage; self.tone = tone; self.button = button
    }
}

/// 20 §5.3 `confirmRecover`; 取消 is not among the options.
public struct AccountRecoverDialogCopy: Sendable, Equatable {
    public enum Option: String, Sendable, CaseIterable, Identifiable {
        case recoverAndEnable, recoverOnly, recover
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .recoverAndEnable: "恢复并启用调度"
            case .recoverOnly: "只恢复状态（保持暂停）"
            case .recover: "恢复状态"
            }
        }
        public var enablesScheduling: Bool { self == .recoverAndEnable }
    }
    public let title: String
    public let message: String
    public let options: [Option]
}

/// 20 §1.4: the list row's trailing swipe.
public enum AccountScheduleSwipe: Sendable, Equatable {
    case stop, enable
    public var title: String { AccountActionKind.setSchedulable(enables).verb }
    public var systemImage: String { enables ? "play.fill" : "pause.fill" }
    public var enables: Bool { self == .enable }
}

/// How an action goes on after a failed request.
public enum AccountWriteDisposition: Sendable, Equatable {
    /// Cancelled, or the security sheet was closed: nothing is said.
    case cancelled
    /// The security sheet cleared it (00 §2.6.2 step 4): the user confirms again, a keyed write under its key.
    case reconfirm
    /// The write may have run (00 §2.4, §2.5.4): `GET :id` decides (20 §5.5).
    case readBack
    case versionConflict
    /// 404 ACCOUNT_NOT_FOUND (20 §0.5).
    case missing
    case failed
}

/// 20 §5.3–§5.5 copy and the decisions behind it; `now` is always the site's ServerClock time (20 §0.6).
public enum AccountActionCopy {
    public static let missingReason = "这个账号已删除或不在本工作区"
    public static let modifiedElsewhere = "账号已被其他人修改"
    /// 00 §2.4: a write whose result could not be read back.
    public static let unconfirmed = "结果未确认，请刷新核对后再操作"
    private static let pausedTail = "这个账号已停止调度，恢复后仍是暂停，除非同时启用调度。"
    private static let warning = "exclamationmark.triangle"

    public static func recoverDialog(for account: UpstreamAccount, now: Date) -> AccountRecoverDialogCopy {
        let display = AccountDisplayState(account, now: now)
        let what = clearedPhrase(display)
        let title = "恢复「\(account.name)」？"
        guard !account.schedulable else {
            return AccountRecoverDialogCopy(title: title, message: "清除\(what)，账号立即参与调度。", options: [.recover])
        }
        let message = display.state == .error ? "清除\(what)。出错时账号已被停止调度，恢复后仍是暂停，除非同时启用调度。" : "清除\(what)。" + pausedTail
        return AccountRecoverDialogCopy(title: title, message: message, options: [.recoverAndEnable, .recoverOnly])
    }
    /// Design RECOVER_WHAT: the state recover-state clears, and the model limits still running unless the account is in error.
    public static func clearedPhrase(_ display: AccountDisplayState) -> String {
        let state: String
        switch display.state {
        case .error: return "错误状态"
        case .rateLimited: state = "限流"
        case .overloaded: state = "过载"
        case .tempUnschedulable: state = "临时不可调度"
        case .paused, .inactive, .available: state = "当前阻断"
        }
        let models = display.modelRateLimits.count
        return models > 0 ? "\(state)和 \(models) 项模型限流" : state
    }

    // MARK: Receipts

    public static func recovered(schedulable: Bool) -> AccountReceiptCopy {
        schedulable ? AccountReceiptCopy(text: "已恢复 · 参与调度", systemImage: "checkmark.circle", tone: .ok, button: nil)
            : AccountReceiptCopy(text: "已恢复 · 仍暂停调度", systemImage: "pause.fill", tone: .neutral, button: .enableScheduling)
    }
    public static func scheduled(enabled: Bool) -> AccountReceiptCopy {
        AccountReceiptCopy(text: enabled ? "已启用调度" : "已停止调度", systemImage: enabled ? "play.fill" : "pause.fill",
                           tone: enabled ? .ok : .neutral, button: .undo)
    }
    public static func accountEnabled(name: String, canUndo: Bool = true) -> AccountReceiptCopy {
        AccountReceiptCopy(text: "已启用账号「\(name)」", systemImage: "play.fill", tone: .ok, button: canUndo ? .undo : nil)
    }
    public static func failed(_ kind: AccountActionKind, error: any Error) -> AccountReceiptCopy {
        AccountReceiptCopy(text: failureText(kind, reason: reason(for: error)), systemImage: warning, tone: .critical, button: nil)
    }
    public static func failureText(_ kind: AccountActionKind, reason: String) -> String { "\(kind.verb)没有成功：\(reason)" }
    /// An unkeyed write the read-back shows did not happen: the user sends it again (00 §2.4).
    public static func notApplied(_ kind: AccountActionKind) -> AccountReceiptCopy {
        AccountReceiptCopy(text: "\(kind.verb)没有生效，可以重试", systemImage: warning, tone: .caution, button: .retry)
    }
    /// A keyed write the read-back does not confirm: the same number is safe to send again (00 §2.5.4).
    public static func unconfirmedRetry(_ kind: AccountActionKind) -> AccountReceiptCopy {
        AccountReceiptCopy(text: "\(kind.verb)结果未确认，可用同一编号重试", systemImage: warning, tone: .caution, button: .retry)
    }
    public static var unconfirmedReceipt: AccountReceiptCopy {
        AccountReceiptCopy(text: unconfirmed, systemImage: warning, tone: .caution, button: nil)
    }
    /// 00 §2.5.3: 503 IDEMPOTENCY_STORE_UNAVAILABLE ran nothing and the read-back agrees; 重试 sends the same number once the
    /// cooldown is over.
    public static func storeUnavailable(_ kind: AccountActionKind) -> AccountReceiptCopy {
        AccountReceiptCopy(text: "\(kind.verb)没有生效：服务器暂时无法受理，稍后用同一编号重试", systemImage: warning, tone: .caution, button: .retry)
    }
    /// 00 §2.6.2 step 4: the cleared notice; 重试 is the second confirmation.
    public static func reconfirm(_ error: any Error) -> AccountReceiptCopy {
        AccountReceiptCopy(text: error.localizedDescription, systemImage: "checkmark.shield", tone: .caution, button: .retry)
    }
    /// 00 §2.6.3: nothing is sent with a read-only token.
    public static var readOnly: AccountReceiptCopy {
        AccountReceiptCopy(text: ReasonCatalog.entry(status: 403, reason: "ACCESS_TOKEN_READ_ONLY").message, systemImage: warning,
                           tone: .critical, button: nil)
    }

    /// 20 §0.5 wording over the catalog's for the account reasons; everything else as the error describes itself.
    public static func reason(for error: any Error) -> String {
        guard let api = error as? APIError, let status = api.statusCode else { return error.localizedDescription }
        if status == 404, api.reason == AccountWriteReason.notFound { return missingReason }
        if status == 412, api.reason == AccountWriteReason.versionConflict { return modifiedElsewhere }
        if AccountWriteReason.isRejectedPatch(api), let reason = api.reason { return "服务器拒绝了这次修改（\(reason)）" }
        return api.localizedDescription
    }

    public static func disposition(of error: any Error) -> AccountWriteDisposition {
        if error is CancellationError { return .cancelled }
        if let failure = error as? KeyedWriteFailure {
            if case .unconfirmed = failure.disposition { return .readBack }
            return .failed
        }
        guard let api = error as? APIError else { return .failed }
        switch api.securityOutcome {
        case .cancelled?: return .cancelled
        case .passed?: return .reconfirm
        case .blocked?, nil: break
        }
        // A refresh that failed before sending; a reply without status is a lost connection or an unreadable 2xx.
        guard api != .refreshDeferred else { return .failed }
        guard let status = api.statusCode else { return api.kind == .transport || api == .invalidResponse ? .readBack : .failed }
        if AccountWriteReason.isRecoveredButStillPaused(api) || RequestPolicy.isRetryableStatus(status, marker: api.reason) { return .readBack }
        if status == 404, api.reason == AccountWriteReason.notFound { return .missing }
        if status == 412, api.reason == AccountWriteReason.versionConflict { return .versionConflict }
        return .failed
    }
    /// 00 §2.5.3: until when a keyed write refused with 503 IDEMPOTENCY_STORE_UNAVAILABLE may not go out again under its
    /// number; nil for any other failure.
    public static func storeUnavailableUntil(_ error: any Error) -> Date? {
        guard let failure = error as? KeyedWriteFailure, case .unconfirmed(.storeUnavailable, let notBefore) = failure.disposition else { return nil }
        return notBefore
    }

    /// 20 §1.4: 停止调度 for a normal or timed account whose switch is on, 启用调度 when it is off. An account paused by its expiry
    /// gets neither (S2D1-20): the switch does not make it schedulable.
    public static func swipeAction(for account: UpstreamAccount, now: Date) -> AccountScheduleSwipe? {
        let input = AccountStateInput(account)
        if input.autoPauseOnExpired == true, let expiresAt = input.expiresAt, expiresAt <= now { return nil }
        guard account.schedulable else { return .enable }
        switch AccountDisplayState(input, now: now).state {
        case .available, .overloaded, .rateLimited, .tempUnschedulable: return .stop
        case .error, .paused, .inactive: return nil
        }
    }

    /// What undoing “启用账号” writes back: any status but active or error returns to inactive (PATCH accepts active / inactive / error).
    public static func undoStatus(from original: String) -> AccountPatchRequest.Status? {
        original == "active" || original == "error" ? nil : .inactive
    }
}
