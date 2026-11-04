import Foundation

/// The name S6-04 / S6-06 use for where a money record came from (S3D1-08); the rule itself is MoneyRecordOrigin's.
public typealias PendingRecordOrigin = MoneyRecordOrigin.Kind

/// One row of the user detail's pending area (30 §2.3, R02): the user's earliest balance record, then their compensations.
public struct PendingBannerEntry: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable { case balance, compensation }
    public let id: UUID
    public let kind: Kind
    public let title: String
    public let detail: String
    /// Set for a record of an older login at this address (C-26).
    public let originNote: String?
    public init(id: UUID, kind: Kind, title: String, detail: String, originNote: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail; self.originNote = originNote
    }
}

/// Who may send the record again now (30 §3.4, D17): the sender only, not during STORE_UNAVAILABLE's cooldown, not with a
/// read-only token.
public struct BalanceRetryContext: Sendable, Equatable {
    public let permission: PendingRetryPermission
    /// The sender's email or “管理员 #7”; read only for another administrator's record.
    public let actorLabel: String?
    public let isHeld: Bool
    public let isReadOnly: Bool
    public init(permission: PendingRetryPermission, actorLabel: String? = nil, isHeld: Bool = false, isReadOnly: Bool = false) {
        self.permission = permission; self.actorLabel = actorLabel; self.isHeld = isHeld; self.isReadOnly = isReadOnly
    }
    public var mayRetry: Bool { permission != .otherActor }
    public var canRetryNow: Bool { mayRetry && !isHeld && !isReadOnly }
}

/// One dialog of the reconciliation (30 §3.4 steps 4–5, candidates).
public struct BalanceReconcilePrompt: Sendable, Equatable {
    public struct Action: Sendable, Equatable, Identifiable {
        public enum Kind: Sendable, Equatable, Hashable { case retry, retryNotThis, markExecuted, abandon, cancel }
        public let kind: Kind
        public let title: String
        public let isEnabled: Bool
        public init(kind: Kind, title: String, isEnabled: Bool = true) { self.kind = kind; self.title = title; self.isEnabled = isEnabled }
        public var id: Kind { kind }
        public var isDestructive: Bool { kind == .abandon }
        public var isCancel: Bool { kind == .cancel }
    }
    public let title: String
    public let message: String
    public let actions: [Action]
    public init(title: String, message: String, actions: [Action]) { self.title = title; self.message = message; self.actions = actions }
}

/// 30 §2.3 and §3.4 as text: the banner, the dialogs of each reconciliation result and the receipts.
public enum BalanceReconcilePresentation {
    public static let stillRunningText = "服务器可能还在执行，请稍后再核对"
    public static let failedText = "核对失败，请稍后再试"
    public static let unknownActorLine = "无法确认发起人"
    public static let readOnlyLine = "当前登录的是只读令牌，不能修改"
    public static var heldLine: String { BalanceReconciliation.storeUnavailableMessage }
    public static let notExecutedTitle = "服务器上没有这笔记录"
    public static let notExecutedMessage = "可能还没执行，或请求没送达。用同一编号重试是安全的：服务器做过会直接返回原结果，不会重复入账。"
    public static let candidateTitle = "找到 1 条可能是这笔的记录"
    public static let ambiguousTitle = "无法确定这笔是否入账"
    public static let ambiguousMessage = "请在 Web 的“余额调整记录”里核对"
    public static let retryTitle = "用同一编号重试"
    public static let abandonTitle = "放弃这笔"
    public static let abandonPrompt = BalanceReconcilePrompt(title: "放弃这笔？", message: "放弃后这笔不会再重试；如果服务器其实已经执行，余额以服务器为准。",
                                                             actions: [abandon, cancel])

    /// After a security prompt cleared a retry: the same record, confirmed once more (00 §2.6.2 step 4).
    public static func reconfirmPrompt(notice: String) -> BalanceReconcilePrompt {
        BalanceReconcilePrompt(title: retryTitle + "？", message: notice, actions: [.init(kind: .retry, title: retryTitle), cancel])
    }

    // MARK: Banner

    /// R02: “充值 $50.00 结果待核对”, “退款结果待核对 · 全部余额”; an old set above 0 and a compensation keep the shared title.
    public static func bannerTitle(_ summary: PendingMoneyWriteSummary) -> String {
        let line = PendingMoneyWriteLine(summary)
        switch summary.subject {
        case .balance(.add, let amount): return "充值 \(DisplayFormat.moneyExact(amount)) 结果待核对"
        case .balance(.subtract, let amount): return "退款 \(DisplayFormat.moneyExact(amount)) 结果待核对"
        case .balance(.set, let amount): return amount == 0 ? line.title + " · " + PendingMoneyWriteLine.allBalanceText : line.title
        case .compensation(.balance, let value): return line.title + " · " + DisplayFormat.moneyExact(value)
        case .compensation, .redeemBatch: return line.title
        }
    }
    /// “5 分钟前发起，未收到服务器确认”; a time ending in a digit gets a space (“今天 09:41 发起”).
    public static func bannerDetail(createdAt: Date?, now: Date, timeZone: TimeZone) -> String {
        let tail = "未收到服务器确认"
        guard let createdAt else { return tail }
        let time = DisplayFormat.relativeTime(createdAt, now: now, timeZone: timeZone)
        return time + (time.last?.isNumber == true ? " " : "") + "发起，" + tail
    }
    /// `records` are the address's (AppModel.pendingMoneyWrites(sameAddressAs:)); a record of another site id there is an older
    /// login's. Shows one balance record at a time, the earliest, and every compensation; batches belong to no user.
    public static func bannerEntries(_ records: [any PendingMoneyWrite], userID: Int, currentServerID: UUID, now: Date,
                                     timeZone: TimeZone) -> [PendingBannerEntry] {
        let mine = records.filter { $0.summary.userID == userID }
        let earliest: (any PendingMoneyWrite, any PendingMoneyWrite) -> Bool = {
            ($0.summary.createdAt ?? .distantPast) < ($1.summary.createdAt ?? .distantPast)
        }
        let balance = mine.filter { $0 is PendingBalanceOperation }.min(by: earliest)
        let grants = mine.filter { $0 is PendingCompensation }
        return ([balance].compactMap { $0 } + grants).map { record in
            PendingBannerEntry(id: record.id, kind: record is PendingCompensation ? .compensation : .balance, title: bannerTitle(record.summary),
                               detail: bannerDetail(createdAt: record.summary.createdAt, now: now, timeZone: timeZone),
                               originNote: record.serverID == currentServerID ? nil : "这笔在" + MoneyRecordOrigin.oldLoginNote)
        }
    }

    // MARK: Receipts

    /// 30 §3.4 step 3 from the ledger row: “已核对：服务器已入账 $50.00（余额 $12.40 → $62.40）”, “已扣除” for a refund.
    public static func executedReceipt(_ row: UserAdjustment, for op: PendingBalanceOperation) -> String {
        let moved: String
        if let delta = row.delta, delta != 0 {
            moved = (delta > 0 ? "已入账 " : "已扣除 ") + DisplayFormat.moneyExact(abs(delta))
        } else {
            switch op.operation {
            case .add: moved = "已入账 " + DisplayFormat.moneyExact(op.amount)
            case .subtract: moved = "已扣除 " + DisplayFormat.moneyExact(op.amount)
            case .set: moved = op.amount == 0 ? "已扣除全部余额" : "已执行余额设置"
            }
        }
        guard let before = row.beforeValue, let after = row.afterValue else { return "已核对：服务器" + moved }
        return "已核对：服务器\(moved)（余额 \(DisplayFormat.moneyExact(before)) → \(DisplayFormat.moneyExact(after))）"
    }
    /// 30 §3.4 result table, 200: “已向 王小明 充值 $50.00”; a replay ran nothing new.
    public static func writtenReceipt(for op: PendingBalanceOperation, replayed: Bool) -> String {
        let wording = Wording(op)
        if replayed { return "这笔此前\(wording.done)，没有重复执行" }
        let name = PendingMoneyWriteLine(op.summary).object
        switch op.operation {
        case .add: return "已向 \(name) 充值 \(DisplayFormat.moneyExact(op.amount))"
        case .subtract: return "已向 \(name) 退款 \(DisplayFormat.moneyExact(op.amount))"
        case .set: return op.amount == 0 ? "已向 \(name) 退款全部余额" : "已将 \(name) 的余额设置为 \(DisplayFormat.moneyExact(op.amount))"
        }
    }
    /// “今天 09:41 · +$50.00 · 余额 $12.40 → $62.40 · 备注：补偿”; missing parts are left out.
    public static func candidateLine(_ row: UserAdjustment, now: Date, timeZone: TimeZone) -> String {
        let time = row.createdAt.map { DisplayFormat.relativeTime($0, now: now, timeZone: timeZone) }
        let delta = row.delta.map { ($0 > 0 ? "+" : "") + DisplayFormat.moneyExact($0) }
        var balances: String?
        if let before = row.beforeValue, let after = row.afterValue {
            balances = "余额 \(DisplayFormat.moneyExact(before)) → \(DisplayFormat.moneyExact(after))"
        }
        let notes = row.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [time, delta, balances, notes.flatMap { $0.isEmpty ? nil : "备注：" + $0 }].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Dialogs

    /// nil for `executed` (a receipt) and `stillRunning` (a receipt, nothing to decide). `notFound` cannot conclude, like
    /// several candidates.
    public static func prompt(for outcome: BalanceReconcileOutcome, op: PendingBalanceOperation, context: BalanceRetryContext,
                              now: Date, timeZone: TimeZone) -> BalanceReconcilePrompt? {
        let wording = Wording(op)
        let sender = context.mayRetry ? nil : otherActorLine(context.actorLabel, verb: wording.verb)
        let retry = context.mayRetry ? [BalanceReconcilePrompt.Action(kind: .retry, title: retryTitle, isEnabled: context.canRetryNow)] : []
        switch outcome {
        case .executed, .stillRunning:
            return nil
        case .notExecuted:
            return BalanceReconcilePrompt(title: notExecutedTitle, message: lines([sender ?? notExecutedMessage], context),
                                          actions: retry + [abandon, cancel])
        case .candidate(let row):
            let mark = BalanceReconcilePrompt.Action(kind: .markExecuted, title: "是这笔，标为" + wording.done)
            let other = context.mayRetry ? BalanceReconcilePrompt.Action(kind: .retryNotThis, title: "不是，" + retryTitle, isEnabled: context.canRetryNow)
                : abandon
            return BalanceReconcilePrompt(title: candidateTitle, message: lines([candidateLine(row, now: now, timeZone: timeZone), sender], context),
                                          actions: [mark, other, cancel])
        case .ambiguous, .notFound:
            return BalanceReconcilePrompt(title: ambiguousTitle, message: lines([ambiguousMessage, sender], context), actions: retry + [abandon, cancel])
        }
    }

    private static let abandon = BalanceReconcilePrompt.Action(kind: .abandon, title: abandonTitle)
    private static let cancel = BalanceReconcilePrompt.Action(kind: .cancel, title: "取消")

    /// 30 §3.4: “这笔由 <邮箱> 发起，只能由同一管理员重试；可以放弃后重新充值。”; Latin letters and digits next to Chinese get a space.
    private static func otherActorLine(_ label: String?, verb: String) -> String {
        let name = label ?? "其他管理员"
        let lead = name.first?.isASCII == true ? " " : "", trail = name.last?.isASCII == true ? " " : ""
        return "这笔由\(lead)\(name)\(trail)发起，只能由同一管理员重试；可以放弃后重新\(verb)。"
    }
    /// Why a retry the sender may make is not offered now; read-only says it all.
    private static func lines(_ base: [String?], _ context: BalanceRetryContext) -> String {
        var extra: [String] = []
        if context.mayRetry {
            if context.permission == .allowedActorUnknown { extra.append(unknownActorLine) }
            if context.isReadOnly { extra.append(readOnlyLine) } else if context.isHeld { extra.append(heldLine) }
        }
        return (base.compactMap { $0 } + extra).joined(separator: "\n")
    }

    /// The direction's words: 充值 / 已入账, 退款 / 已扣除 (“全部余额” too), an old set above 0 设置余额 / 已执行.
    private struct Wording {
        let verb: String
        let done: String
        init(_ op: PendingBalanceOperation) {
            switch op.operation {
            case .add: (verb, done) = ("充值", "已入账")
            case .subtract: (verb, done) = ("退款", "已扣除")
            case .set: (verb, done) = op.amount == 0 ? ("退款", "已扣除") : ("设置余额", "已执行")
            }
        }
    }
}
