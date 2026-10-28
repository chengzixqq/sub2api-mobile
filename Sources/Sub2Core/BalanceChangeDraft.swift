import Foundation

/// 30 §3.3: what the top-up / refund keypad has typed, as a value. The keypad's text goes through KeypadInput (7 digits, 2
/// decimals); “全部余额” fills in the balance and is sent as set 0 until the digits or the direction change (U27).
public struct BalanceChangeDraft: Sendable, Equatable {
    public static let maxDigits = 7
    public static let maxFractionDigits = 2

    /// The balance read when the sheet opened.
    public let currentBalance: Decimal
    public let direction: BalanceDirection
    public let amountText: String
    public let isAllBalance: Bool
    public let notes: String

    public init(currentBalance: Decimal, direction: BalanceDirection, amountText: String = "", isAllBalance: Bool = false, notes: String = "") {
        self.currentBalance = currentBalance; self.direction = direction; self.amountText = amountText
        self.isAllBalance = isAllBalance; self.notes = notes
    }

    /// The keypad's new text; a key it refused returns the same text, which keeps “全部余额”.
    public func editingAmount(_ text: String) -> BalanceChangeDraft {
        guard text != amountText else { return self }
        return BalanceChangeDraft(currentBalance: currentBalance, direction: direction, amountText: text, notes: notes)
    }
    public func switching(to direction: BalanceDirection) -> BalanceChangeDraft {
        guard direction != self.direction else { return self }
        return BalanceChangeDraft(currentBalance: currentBalance, direction: direction, amountText: amountText, notes: notes)
    }
    public func choosingAllBalance() -> BalanceChangeDraft {
        guard canChooseAllBalance else { return self }
        return BalanceChangeDraft(currentBalance: currentBalance, direction: direction, amountText: Self.keypadText(currentBalance),
                                  isAllBalance: true, notes: notes)
    }
    public func editingNotes(_ notes: String) -> BalanceChangeDraft {
        BalanceChangeDraft(currentBalance: currentBalance, direction: direction, amountText: amountText, isAllBalance: isAllBalance, notes: notes)
    }

    /// Only for a refund of a positive balance (30 §3.3).
    public var canChooseAllBalance: Bool { direction == .debit && currentBalance > 0 }
    public var amount: Decimal? { KeypadInput.value(of: amountText) }
    /// How far the balance goes down or up: “全部余额” is the whole balance (8 decimals), not its two-decimal keypad text.
    public var changeAmount: Decimal? { isAllBalance ? currentBalance : amount }
    public var isAmountEmpty: Bool { amountText.isEmpty }
    /// A refund beyond the balance would be refused by the server as a 500 without a reason, so it is never sent.
    public var exceedsBalance: Bool {
        guard direction == .debit, !isAllBalance, let amount else { return false }
        return amount > currentBalance
    }
    public var canSubmit: Bool { (changeAmount ?? 0) > 0 && !exceedsBalance }
    public var operation: BalanceOperation {
        if isAllBalance { return .set }
        return direction == .credit ? .add : .subtract
    }
    /// The body's `balance`: “全部余额” sets it to 0 at the server, whatever it is by then.
    public var requestAmount: Decimal? { isAllBalance ? 0 : amount }
    public var resultingBalance: Decimal? {
        if isAllBalance { return 0 }
        return amount.map { direction == .credit ? currentBalance + $0 : currentBalance - $0 }
    }
    /// D26: how far the balance moves, for the Face ID threshold.
    public var biometricAmount: Decimal? {
        requestAmount.flatMap { Self.judgedAmount(operation: operation, amount: $0, currentBalance: currentBalance) }
    }

    /// “$50”, “−$50” for a refund; “$0” in grey while empty; “全部余额” shows every digit of the balance.
    public var amountDisplay: String {
        guard !amountText.isEmpty else { return "$0" }
        let digits = isAllBalance ? DisplayFormat.number(currentBalance, minFraction: Self.maxFractionDigits, maxFraction: nil, grouping: false)
            : amountText
        return (direction == .debit ? DisplayFormat.minus : "") + "$" + digits
    }
    public var previewText: String {
        if exceedsBalance { return "超过当前余额" }
        guard (changeAmount ?? 0) > 0, let after = resultingBalance else { return "输入金额" }
        return BalanceChangeCopy.verb(direction) + "后余额 " + DisplayFormat.money(after)
    }
    public var submitTitle: String {
        let verb = BalanceChangeCopy.verb(direction)
        guard let amount = changeAmount, amount > 0 else { return verb }
        return verb + " " + DisplayFormat.moneyExact(amount)
    }

    /// R05: the record is made when the confirmation is accepted; its bytes never change after that.
    public func pendingOperation(id: UUID, serverID: UUID, userID: Int, actorUserID: Int?, createdAt: Date, userDisplayName: String,
                                 userEmail: String) throws -> PendingBalanceOperation {
        guard canSubmit, let requestAmount else { throw APIError.invalidAmount }
        let operation = PendingBalanceOperation(id: id, serverID: serverID, userID: userID, amount: requestAmount, operation: operation,
                                                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), actorUserID: actorUserID,
                                                createdAt: createdAt, userDisplayName: userDisplayName, userEmail: userEmail)
        try operation.validate()
        return operation
    }

    /// D26, the only definition: add and subtract move the balance by the amount; set moves it from the current balance to the
    /// amount, unknown without a balance.
    public static func judgedAmount(operation: BalanceOperation, amount: Decimal, currentBalance: Decimal?) -> Decimal? {
        switch operation {
        case .add, .subtract: amount
        case .set: currentBalance.map { abs($0 - amount) }
        }
    }
    /// The balance as the keypad would have typed it: two decimals, no grouping.
    public static func keypadText(_ value: Decimal) -> String {
        DisplayFormat.number(value, minFraction: maxFractionDigits, maxFraction: maxFractionDigits, grouping: false)
    }
}

/// 30 §3.3 确认框, from `submitBalanceChange`; R03's second confirmation adds the warning line and “仍要…”.
public struct BalanceConfirmation: Sendable, Equatable {
    public let title: String
    public let message: String
    public let confirmTitle: String

    public init(draft: BalanceChangeDraft, userDisplayName: String, siteName: String, userIsDisabled: Bool, faceIDLine: String?,
                pendingSameDirection: PendingBalanceOperation?) {
        let verb = BalanceChangeCopy.verb(draft.direction), amount = DisplayFormat.moneyExact(draft.amount)
        title = draft.isAllBalance ? "向「\(userDisplayName)」退款全部余额？" : "向「\(userDisplayName)」\(verb) \(amount)？"
        var lines = [pendingSameDirection.map(BalanceChangeCopy.pendingWarning),
                     "站点 \(siteName) · 余额 \(DisplayFormat.money(draft.currentBalance)) → \(DisplayFormat.money(draft.resultingBalance))"]
        if draft.isAllBalance { lines.append("按服务器执行时的余额归零。") }
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { lines.append("备注：" + notes) }
        if userIsDisabled { lines.append(draft.direction == .credit ? "该用户已禁用。\n充值后仍不能调用，需先启用。" : "该用户已禁用。") }
        lines.append(faceIDLine)
        message = lines.compactMap { $0 }.joined(separator: "\n")
        let action = draft.isAllBalance ? "退款全部余额" : "\(verb) \(amount)"
        confirmTitle = (pendingSameDirection == nil ? "" : "仍要") + action
    }
}

/// R03 for one user and direction: the earliest record the gate holds back, or the paused kind's words.
public enum BalancePendingCheck: Sendable, Equatable {
    case clear
    case sameDirection(PendingBalanceOperation)
    case paused(message: String)

    public init(gate: PendingMoneyGate, balances: [PendingBalanceOperation]) {
        switch gate {
        case .clear:
            self = .clear
        case .paused(let kind):
            self = .paused(message: kind.unreadableMessage)
        case .overridable(let ids), .blocked(let ids):
            let held = balances.filter { ids.contains($0.id) }
            let earliest = held.min { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            self = earliest.map(BalancePendingCheck.sameDirection) ?? .clear
        }
    }
}

/// The sheet's state while a write is out (30 §3.5).
public enum BalanceWriteProgress: Sendable, Equatable {
    case submitting
    /// The same key and bytes again after a transport failure.
    case confirming(retry: Int)
    /// IN_PROGRESS / RETRY_BACKOFF.
    case waiting(elapsedSeconds: Int)

    /// nil for the action id, which is saved, not shown.
    public init?(_ event: KeyedWriteEvent) {
        switch event {
        case .actionID: return nil
        case .confirming(let retry): self = .confirming(retry: retry)
        case .waitingForServer(let seconds): self = .waiting(elapsedSeconds: seconds)
        }
    }
    public var title: String {
        switch self {
        case .submitting: "正在提交…"
        case .confirming: "正在确认结果…"
        case .waiting: "正在等待服务器结果…"
        }
    }
    public var detail: String? {
        guard case .waiting(let seconds) = self else { return nil }
        return "已等待 \(seconds) 秒"
    }
}

/// 30 §3.3–§3.4 wording of the keypad and of R03's first confirmation.
public enum BalanceChangeCopy {
    public static let notesLabel = "备注"
    public static let notesPlaceholder = "可选，写进充值记录"
    public static let disabledBadge = "已禁用"
    public static let later = "稍后核对"
    public static let entryMessage = "先核对可避免重复入账"
    public static let reconcileFirst = "先核对"
    /// A refusal the server answered but the phone could not record: the record stays, under its number.
    public static let unresolvedRejection = "拒绝结果已收到，但无法更新本机记录。请检查设备存储，保留原操作编号。"

    public static func verb(_ direction: BalanceDirection) -> String { direction == .credit ? "充值" : "退款" }
    public static func proceedAnyway(_ direction: BalanceDirection) -> String { "仍要" + verb(direction) }
    public static func userLine(name: String, balance: Decimal) -> String { "\(name) · 余额 \(DisplayFormat.money(balance))" }
    public static func allBalancePill(_ balance: Decimal) -> String { "全部余额 " + DisplayFormat.money(balance) }
    /// “上一笔 $50.00 充值结果未确认”.
    public static func entryTitle(_ pending: PendingBalanceOperation) -> String { "上一笔" + subject(pending) + "结果未确认" }
    /// The second confirmation's first line. A refund replaces only “充值” in the design's top-up sentence (30 §3.4); the user
    /// has yet to confirm that wording.
    public static func pendingWarning(_ pending: PendingBalanceOperation) -> String {
        "上一笔" + subject(pending) + "还没核对。如果它其实已入账，这一笔会再入账一次。"
    }

    /// “ $50.00 充值”, “全部余额退款”; an amount is set off by a space from the Chinese before it.
    private static func subject(_ pending: PendingBalanceOperation) -> String {
        let amount = " " + DisplayFormat.moneyExact(pending.amount) + " "
        switch pending.operation {
        case .add: return amount + "充值"
        case .subtract: return amount + "退款"
        case .set: return pending.amount == 0 ? PendingMoneyWriteLine.allBalanceText + "退款" : amount + "余额设置"
        }
    }
}
