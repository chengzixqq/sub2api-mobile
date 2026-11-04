import Foundation

/// 50 §0.5: the group actions by the word their receipts use.
public enum GroupActionKind: Sendable, Equatable {
    case disable, enable, duplicate, delete, undo
    public var verb: String {
        switch self {
        case .disable: "停用"
        case .enable: "启用"
        case .duplicate: "复制"
        case .delete: "删除"
        case .undo: "撤销"
        }
    }
}

/// A group receipt's one button.
public enum GroupReceiptButton: Sendable, Equatable {
    case undo, view, retry, retrySameKey, check
    public var title: String {
        switch self {
        case .undo: "撤销"
        case .view: "查看"
        case .retry: "重试"
        case .retrySameKey: "用同一编号重试"
        case .check: "核对"
        }
    }
}

public struct GroupReceiptCopy: Sendable, Equatable {
    public let text: String
    public let systemImage: String
    public let tone: Tone
    public let button: GroupReceiptButton?
    public init(text: String, systemImage: String, tone: Tone, button: GroupReceiptButton?) {
        self.text = text; self.systemImage = systemImage; self.tone = tone; self.button = button
    }
}

/// How a failed write of a group itself (create, update, delete, duplicate) goes on (50 §0.8, §3.5, S5D2a-06). Member writes
/// are classified by S5-08's GroupMemberSendResult. As AccountWriteMark.mayHaveApplied, anything but a 4xx may have run.
public enum GroupWriteDisposition: Sendable, Equatable {
    /// Cancelled, or the security sheet was closed: nothing is said.
    case cancelled
    /// 404 GROUP_NOT_FOUND / RESOURCE_NOT_FOUND.
    case gone
    /// The server will not take this number (KEY_CONFLICT, KEY_INVALID, KEY_REQUIRED) or the security sheet cleared the write:
    /// the user acts again, under a new number.
    case reconfirm
    /// Refused; the words are GroupErrorCopy's or the catalog's, never the server's (R11).
    case rejected(String)
    /// May have run (5xx, 408, a lost connection, an unreadable reply, an unconfirmed keyed write): read back once.
    /// `retryNotBefore` only after 503 IDEMPOTENCY_STORE_UNAVAILABLE.
    case unconfirmed(retryNotBefore: Date?)

    public static func of(_ error: any Error) -> GroupWriteDisposition {
        if error is CancellationError { return .cancelled }
        if let failure = error as? KeyedWriteFailure {
            switch failure.disposition {
            case .unconfirmed(.storeUnavailable, let notBefore): return .unconfirmed(retryNotBefore: notBefore)
            case .unconfirmed: return .unconfirmed(retryNotBefore: nil)
            case .needsNewKey: return .reconfirm
            }
        }
        guard let api = error as? APIError else { return .rejected(error.localizedDescription) }
        switch api.securityOutcome {
        case .cancelled?: return .cancelled
        case .passed?: return .reconfirm
        case .blocked?, nil: break
        }
        // A refresh that failed before sending; a reply without status is a lost connection or an unreadable 2xx.
        guard api != .refreshDeferred else { return .rejected(api.localizedDescription) }
        guard let status = api.statusCode else {
            return api.kind == .transport || api == .invalidResponse ? .unconfirmed(retryNotBefore: nil) : .rejected(api.localizedDescription)
        }
        if status >= 500 || status == 408 { return .unconfirmed(retryNotBefore: nil) }
        let copy = GroupErrorCopy.resolve(api, context: .write)
        return copy.action == .treatAsDeleted ? .gone : .rejected(copy.message)
    }
}

/// 50 §0.5 receipts; the success words are GroupCopy's. The delete receipt is DeleteConfirmationCopy's (App side).
public enum GroupActionCopy {
    private static let warning = "exclamationmark.triangle"

    public static func statusChanged(name: String, active: Bool) -> GroupReceiptCopy {
        active ? GroupReceiptCopy(text: GroupCopy.enabledReceipt(name: name), systemImage: "play.fill", tone: .ok, button: .undo)
            : GroupReceiptCopy(text: GroupCopy.disabledReceipt(name: name), systemImage: "pause.fill", tone: .neutral, button: .undo)
    }
    /// 查看 opens the copy, which is created inactive.
    public static func duplicated(newName: String, memberCount: Int) -> GroupReceiptCopy {
        GroupReceiptCopy(text: GroupCopy.duplicateReceipt(newName: newName, memberCount: memberCount), systemImage: "plus.square.on.square",
                         tone: .neutral, button: .view)
    }
    public static func failed(_ kind: GroupActionKind, reason: String) -> GroupReceiptCopy {
        GroupReceiptCopy(text: "\(kind.verb)没有成功：\(reason)", systemImage: warning, tone: .critical, button: nil)
    }
    /// 2xx, but the group came back without the change (simple mode, or a vendor without group_ops: 50 §0.7).
    public static func notAccepted(_ kind: GroupActionKind) -> GroupReceiptCopy {
        GroupReceiptCopy(text: "\(kind.verb)没有生效：服务器没有接受这项修改", systemImage: warning, tone: .caution, button: nil)
    }
    /// An unkeyed write the read-back shows did not happen: sent again under a new request id (00 §2.4).
    public static func notApplied(_ kind: GroupActionKind) -> GroupReceiptCopy {
        GroupReceiptCopy(text: "\(kind.verb)没有生效，可以重试", systemImage: warning, tone: .caution, button: .retry)
    }
    /// A keyed write the read-back does not confirm: the same number is safe to send again (00 §2.5.4).
    public static func unconfirmedRetry(_ kind: GroupActionKind) -> GroupReceiptCopy {
        GroupReceiptCopy(text: "\(kind.verb)结果未确认，可用同一编号重试", systemImage: warning, tone: .caution, button: .retrySameKey)
    }
    /// 00 §2.5.3: 503 IDEMPOTENCY_STORE_UNAVAILABLE ran nothing; the same number goes again once the cooldown is over.
    public static func storeUnavailable(_ kind: GroupActionKind) -> GroupReceiptCopy {
        GroupReceiptCopy(text: "\(kind.verb)没有生效：服务器暂时无法受理，稍后用同一编号重试", systemImage: warning, tone: .caution,
                         button: .retrySameKey)
    }
    /// The read-back itself failed; 核对 reads once more and sends nothing.
    public static func checkFailed(_ kind: GroupActionKind) -> GroupReceiptCopy {
        GroupReceiptCopy(text: "\(kind.verb)结果未确认，请刷新核对后再操作", systemImage: warning, tone: .caution, button: .check)
    }
    /// A copy has no group to read back: the list is read again instead.
    public static let duplicateUnconfirmed = GroupReceiptCopy(text: "复制结果未确认，已刷新列表，请核对是否已有副本", systemImage: warning,
                                                              tone: .caution, button: .retrySameKey)
    public static func reconfirm(_ kind: GroupActionKind) -> GroupReceiptCopy {
        GroupReceiptCopy(text: "\(kind.verb)没有执行，请重新操作", systemImage: warning, tone: .caution, button: .retry)
    }
    /// 00 §2.6.3: nothing is sent with a read-only token.
    public static var readOnly: GroupReceiptCopy {
        GroupReceiptCopy(text: ReasonCatalog.entry(status: 403, reason: "ACCESS_TOKEN_READ_ONLY").message, systemImage: warning,
                         tone: .critical, button: nil)
    }
}
