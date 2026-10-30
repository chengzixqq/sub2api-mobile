import Foundation

// 60 §19.1, §19.3–§19.5 words of the compensation sheet that S6-08 left to it (S6-09): the steps, the value step, the block
// before a new grant, and the pending pages with their receipt and buttons. RedeemGrantCopy (S6-08) has the rest; a code is
// only ever shown in its short form.

/// 60 §19.1: 类型 · 数值 · 备注.
public enum GrantStep: Int, CaseIterable, Sendable {
    case type = 1, value, note

    public static let barTitles = ["类型", "数值", "备注"]
    public func title(for type: CompensationType?) -> String {
        switch self {
        case .type: "发放兑换码"
        case .value: type?.grantTitle ?? Self.barTitles[1]
        case .note: "备注与确认"
        }
    }
    /// Top left: 取消 on the first step, 上一步 after it.
    public var leadingTitle: String { self == .type ? "取消" : "上一步" }
    public var previous: GrantStep? { GrantStep(rawValue: rawValue - 1) }
    public var spokenPosition: String { "第 \(rawValue) 步，共 \(Self.allCases.count) 步" }
}

/// Step 2 of a balance grant: the big amount and “发放后余额 $22.40”; no default amount (BUILDER_GUIDE).
public struct BalanceGrantPreview: Sendable, Equatable {
    /// The keypad (KeypadInput): seven digits in all, two of them decimals.
    public static let maxDigits = 7
    public static let maxFractionDigits = 2

    /// “$10”; “$0” in grey before anything is typed.
    public let amountText: String
    public let amount: Decimal?
    /// The balance after it, “$22.40”; nil before anything is typed.
    public let after: String?
    public init(text: String, balance: Decimal) {
        amountText = "$" + (text.isEmpty ? "0" : text)
        amount = text.isEmpty ? nil : KeypadInput.value(of: text)
        after = amount.map { DisplayFormat.money(balance + $0) }
    }
    public var isPlaceholder: Bool { amount == nil }
    public var line: String { after.map { "发放后余额 " + $0 } ?? "输入金额" }
    public var canAdvance: Bool { (amount ?? 0) > 0 }
}

extension RedeemSubscriptionDaysChoice {
    /// A grant's days (60 §19.2): 1–3650, nil for a custom number not typed or out of range.
    public func grantDays(customText: String) -> Int? {
        switch self {
        case .days(let days): return days
        case .custom:
            guard let days = Int(customText), RedeemGrantDraft.daysRange.contains(days) else { return nil }
            return days
        }
    }
}

public enum RedeemGrantPresentation {
    public static let typeFootnote = "发放会生成一个兑换码并立即替这个用户兑换，记录出现在用户的“充值与调整记录”和兑换码列表里。邀请码只能在注册时使用，不能发放。"
    public static let concurrencyLabel = "增加并发"
    public static let groupsFootnote = "只列出订阅类型的分组。"
    public static let notesPlaceholder = "例如：故障补偿 · 工单 #8812"
    public static let notesFootnote = "可选。写进兑换码的备注，也显示在用户的“充值与调整记录”里。"
    public static let sendingTitle = "正在发放…"
    public static let faceIDDetail = "验证后发放"
    public static let viewCodeAction = "查看兑换码"
    public static let disabledBadge = "禁用"
    /// A conflict met on the pending page goes back to step 3 with this line.
    public static let renumberedNotice = "已换新编号，请重新确认"

    /// “提高这个用户的并发上限。发放后：并发上限 5 → 7。”; `change` is GrantSummary.change.
    public static func concurrencyFootnote(change: String) -> String { CompensationType.concurrency.grantHint + "发放后：" + change + "。" }
}

// MARK: 19.1 Before a new grant (X38)

/// “上一次补偿的发放结果未确认”: the earliest record of this user at this address, which 先核对 opens.
public struct GrantBlockPrompt: Sendable, Equatable, Identifiable {
    public static let title = "上一次补偿的发放结果未确认"
    public static let checkTitle = "先核对"
    public static let cancelTitle = "取消"
    public let recordID: UUID
    /// “向 王小明 发放 $10.00 余额 · 5 分钟前发起。\n先核对，避免重复发放。”
    public let message: String
    public var id: UUID { recordID }
    public init(recordID: UUID, message: String) { self.recordID = recordID; self.message = message }
}

public enum GrantEntryDecision: Sendable, Equatable {
    case open
    /// No new compensation until this one is checked (00 §2.5.4 step 4): a compensation has no “仍要…”.
    case blocked(GrantBlockPrompt)
    /// The compensation file cannot be read (00 §2.5.5).
    case paused(message: String)

    /// `gate`: AppModel.moneyWriteGate(.compensation(userID:)), over every site id of this address (X34); `now` is phone time
    /// like createdAt, the clock is the server's.
    public static func decide(gate: PendingMoneyGate, compensations: [PendingCompensation], groupNames: [Int: String], now: Date,
                              timeZone: TimeZone) -> Self {
        let ids: [UUID]
        switch gate {
        case .clear: return .open
        case .paused(let kind): return .paused(message: kind.unreadableMessage)
        case .overridable(let held), .blocked(let held): ids = held
        }
        let earliest = compensations.filter { ids.contains($0.id) }.min { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        guard let earliest else { return .open }
        let time = DisplayFormat.relativeTime(earliest.createdAt, now: now, timeZone: timeZone)
        let what = RedeemGrantCopy.what(of: earliest, groupName: earliest.groupID.flatMap { groupNames[$0] })
        let started = time + (time.last?.isNumber == true ? " " : "") + "发起。\n先核对，避免重复发放。"
        return .blocked(GrantBlockPrompt(recordID: earliest.id, message: "向 \(earliest.userDisplayName) 发放 \(what) · " + started))
    }
}

// MARK: 19.3–19.5 The pending pages

/// Where a pending compensation's page stands.
public enum CompensationPendingState: Sendable, Equatable {
    /// Before a check: 请求可能已提交.
    case awaitingCheck
    case notFound
    /// The code exists, unused: the run stopped half way.
    case createdNotRedeemed
    /// Marked used without a user: checked on the web.
    case unverifiable
    /// Settled without being granted to this user (another user has the code, a conflict, a group or key the server would not
    /// take): the same content may go out again under a new code.
    case regrant(String)
    /// Settled without a grant, nothing to offer (the user is gone, the request was refused).
    case ended(String)
    /// The record is gone: checked, given up or settled elsewhere.
    case settled

    /// A check's answer; nil for `issued`, which closes the page.
    public init?(_ outcome: CompensationReconcileOutcome) {
        switch outcome {
        case .issued: return nil
        case .createdNotRedeemed: self = .createdNotRedeemed
        case .notFound: self = .notFound
        case .redeemedByOther: self = .regrant(CompensationPendingPresentation.otherUserMessage)
        case .unverifiable: self = .unverifiable
        }
    }
}

public struct CompensationPendingAction: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case check, retry, abandon, regrant, markChecked }
    public let kind: Kind
    public let title: String
    public let isPrimary: Bool
    public let isEnabled: Bool
    public var id: Kind { kind }
}

public enum CompensationPendingPresentation {
    public static let navigationTitle = "补偿结果待核对"
    public static let checkTitle = "核对发放结果"
    public static let retryTitle = "用同一编号重试"
    public static let abandonTitle = "放弃这次发放"
    public static let regrantTitle = "重新发放"
    public static let markCheckedTitle = "我已在 Web 核对"
    public static let pendingFootnote = "编号和兑换码已保存在本机。用同一编号重试时，服务器发放过就直接返回那一次，不会重复发放。"
    public static let unusedFootnote = "放弃后这个码留在兑换码列表里，未使用，可以删除。"
    public static let otherUserMessage = "这个兑换码已被其他用户使用，没有发给这个用户。可以用原内容换新编号重新发放。"
    public static let abandonPromptTitle = "放弃这次发放？"
    public static let abandonPromptMessage = "放弃后这笔不会再重试；如果服务器其实已经发放，以服务器为准。"
    public static let abandonReceipt = "已放弃 · 不再提醒"
    public static let markCheckedReceipt = "已核对 · 不再提醒"

    public static func header(for state: CompensationPendingState, userName: String) -> RedeemReconcilePresentation.Header {
        typealias Header = RedeemReconcilePresentation.Header
        return switch state {
        case .awaitingCheck: Header(systemImage: "hourglass", title: "请求可能已提交", message: "没有收到服务器确认。不要重新发放，先核对。", tone: .caution)
        case .notFound: Header(systemImage: "magnifyingglass", title: "服务器上没有这次发放", message: "这次发放没有生效。用同一编号重试，或者放弃。", tone: .neutral)
        case .createdNotRedeemed:
            Header(systemImage: "ticket", title: "兑换码已创建，还没兑换给 \(userName)", message: "上一次执行中途停了。用同一编号重试会把这个码兑换给他。", tone: .caution)
        case .unverifiable:
            Header(systemImage: "questionmark.circle", title: "无法确认这次发放", message: "兑换码已标为已使用，但看不出兑换给了谁。请到 Web 的兑换码列表核对。",
                   tone: .caution)
        case .regrant(let message): Header(systemImage: "arrow.triangle.2.circlepath", title: "这次没有发给 \(userName)", message: message, tone: .neutral)
        case .ended(let message): Header(systemImage: "xmark.octagon", title: "这次发放没有生效", message: message, tone: .critical)
        case .settled: Header(systemImage: "checkmark.circle", title: "这笔已核对或已放弃", message: nil, tone: .neutral)
        }
    }
    public static func footnote(for state: CompensationPendingState) -> String? {
        switch state {
        case .awaitingCheck: pendingFootnote
        case .createdNotRedeemed: unusedFootnote
        case .notFound, .unverifiable, .regrant, .ended, .settled: nil
        }
    }
    /// Why the retry is missing or grey (00 §2.5.2); a compensation retries past its idempotency expiry (19.4 step 7).
    public static func notes(for state: CompensationPendingState, retry: RedeemRetryContext, now: Date) -> [String] {
        switch state {
        case .awaitingCheck, .notFound, .createdNotRedeemed:
            return retry.permission == .otherActor ? [otherActorLine(retry.actorLabel)] : retry.restrictionLines(now: now)
        case .unverifiable, .regrant, .ended, .settled:
            return []
        }
    }
    /// Another administrator's record is only checked or given up; a grey retry stays where it would be.
    public static func actions(for state: CompensationPendingState, retry: RedeemRetryContext, busy: RedeemReconcilePresentation.Busy?,
                               now: Date) -> [CompensationPendingAction] {
        let idle = busy == nil, mayRetry = retry.permission != .otherActor
        let check = CompensationPendingAction(kind: .check, title: busy == .checking ? "正在核对…" : checkTitle, isPrimary: true, isEnabled: idle)
        func retryAction(primary: Bool) -> CompensationPendingAction {
            CompensationPendingAction(kind: .retry, title: busy == .retrying ? "正在用同一编号重试…" : retryTitle, isPrimary: primary,
                                      isEnabled: idle && mayRetry && !retry.isReadOnly && !retry.isHeld(now: now))
        }
        func abandon(primary: Bool) -> CompensationPendingAction {
            CompensationPendingAction(kind: .abandon, title: abandonTitle, isPrimary: primary, isEnabled: idle)
        }
        switch state {
        case .awaitingCheck: return [check, mayRetry ? retryAction(primary: false) : abandon(primary: false)]
        case .notFound, .createdNotRedeemed: return mayRetry ? [retryAction(primary: true), abandon(primary: false)] : [abandon(primary: true)]
        case .unverifiable: return [CompensationPendingAction(kind: .markChecked, title: markCheckedTitle, isPrimary: true, isEnabled: idle)]
        case .regrant: return [CompensationPendingAction(kind: .regrant, title: regrantTitle, isPrimary: true, isEnabled: idle)]
        case .ended, .settled: return []
        }
    }
    /// 对象, 站点 (with the older login's note, S6D1-20), 内容, 发起 on the server's calendar, the code's short form and the full
    /// number, which may be selected (not a secret, 60 §11.3).
    public static func receipt(_ grant: PendingCompensation, siteName: String, groupName: String?, origin: MoneyRecordOrigin.Kind,
                               timeZone: ServerTimeZone, now: Date) -> [MoneyReceiptLine] {
        [MoneyReceiptLine(id: "user", label: "对象", value: grant.userDisplayName + " · " + grant.userEmail),
         MoneyReceiptLine(id: "site", label: "站点", value: siteName, note: origin == .sameAddressOldLogin ? MoneyRecordOrigin.oldLoginNote : nil),
         MoneyReceiptLine(id: "content", label: "内容", value: RedeemGrantCopy.what(of: grant, groupName: groupName)),
         MoneyReceiptLine(id: "started", label: "发起", value: DisplayFormat.monthDayClock(grant.createdAt, timeZone: timeZone, now: now)),
         MoneyReceiptLine(id: "code", label: "兑换码", value: RedeemPresentation.shortCode(grant.code)),
         MoneyReceiptLine(id: "key", label: "编号", value: grant.key, isKey: true)]
    }
    /// 00 §2.5.2: “这笔补偿由 <邮箱> 发起，只能由同一管理员重试；可以放弃后重新发放。”; Latin letters next to Chinese get a space.
    public static func otherActorLine(_ label: String?) -> String {
        let name = label ?? "其他管理员"
        let lead = name.first?.isASCII == true ? " " : "", trail = name.last?.isASCII == true ? " " : ""
        return "这笔补偿由\(lead)\(name)\(trail)发起，只能由同一管理员重试；可以放弃后重新发放。"
    }
}
