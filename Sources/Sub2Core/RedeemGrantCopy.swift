import Foundation

// 60 §19.3's wording of the compensation sheet (S6-08): tiles, the subject line, the subscription plan, the summary, the
// receipt rows, the confirmation and the receipts. Step titles, footnotes and the pending pages are the sheet's (S6-09).
// Money follows DisplayFormat (typed amounts exact), dates the server's zone (00 §6.3), and a code only its short form.

extension CompensationType {
    /// Receipt “类型” and the tiles.
    public var grantLabel: String {
        switch self {
        case .balance: "余额"
        case .concurrency: "并发"
        case .subscription: "订阅"
        }
    }
    /// Step 2's title.
    public var grantTitle: String { grantLabel + "补偿" }
    public var grantHint: String {
        switch self {
        case .balance: "直接计入余额，按资金操作确认。"
        case .concurrency: "提高这个用户的并发上限。"
        case .subscription: "开通或延长一个订阅分组。"
        }
    }
}

/// One grant in words: “$10.00 余额” / “+2 并发” / “企业专线 30 天订阅” and what it changes.
public struct GrantSummary: Sendable, Equatable {
    public let type: CompensationType
    /// USD for a balance, the increase for concurrency, days for a subscription.
    public let amount: Decimal
    /// The confirmation's title: “$10.00 余额” / “+2 并发” / “企业专线 30 天订阅”.
    public let what: String
    /// The button: “$10.00” / “+2 并发” / “30 天订阅”.
    public let short: String
    /// The receipt's “数值”: “$10.00” / “+2 并发” / “企业专线 · 30 天”.
    public let value: String
    /// The receipt's “变化”: “余额 $12.40 → $22.40” / “并发上限 5 → 7” / the plan's change.
    public let change: String

    /// `groupName` nil writes “分组 #<id>”; `plan` nil (the user's subscriptions could not be read) leaves the end to the server.
    public init(draft: RedeemGrantDraft, user: AdminUser, groupName: String?, plan: SubscriptionGrantPlan?, now: Date, timeZone: TimeZone) {
        type = draft.type
        switch draft.value {
        case .balance(let amount):
            let money = DisplayFormat.moneyExact(amount)
            self.amount = amount; what = money + " 余额"; short = money; value = money
            change = "余额 " + DisplayFormat.money(user.balance) + " → " + DisplayFormat.money(user.balance + amount)
        case .concurrency(let count):
            let text = RedeemGrantCopy.concurrencyText(count)
            amount = Decimal(count); what = text; short = text; value = text
            change = Self.concurrencyChange(current: user.concurrency, adding: count)
        case .subscription(let groupID, let days):
            let group = groupName ?? RedeemGrantCopy.unnamedGroup(groupID)
            amount = Decimal(days); what = "\(group) \(days) 天订阅"; short = "\(days) 天订阅"; value = "\(group) · \(days) 天"
            change = plan.map { RedeemGrantCopy.planChange($0, now: now, timeZone: timeZone) } ?? "到期以服务器结果为准"
        }
    }
    /// Balance grants go through the money confirmation and the Face ID threshold.
    public var isMoney: Bool { type == .balance }
    public var submitTitle: String { "发放 " + short }

    private static func concurrencyChange(current: Int?, adding count: Int) -> String {
        guard let current else { return "并发上限 +\(count)" }
        return "并发上限 " + (current == 0 ? "不限制" : "\(current)") + " → \(current + count)"
    }
}

public struct GrantReceiptRow: Sendable, Equatable {
    public let label: String
    public let value: String
    /// “发放 $10.00” of a balance grant.
    public let isEmphasized: Bool
    public init(label: String, value: String, isEmphasized: Bool = false) { self.label = label; self.value = value; self.isEmphasized = isEmphasized }
}

public struct GrantConfirmation: Sendable, Equatable {
    public let title: String
    /// Lines joined by "\n".
    public let message: String
    public let button: String
    /// Balance grants use the destructive style.
    public let isDestructive: Bool
    public init(title: String, message: String, button: String, isDestructive: Bool) {
        self.title = title; self.message = message; self.button = button; self.isDestructive = isDestructive
    }
}

public enum RedeemGrantCopy {
    public static let rebateFootnote = "按兑换处理：开启邀请返利时，邀请人会照常得到返利（和用户自己兑换一样，不看“管理员充值参与返利”开关）。"
    public static let subscriptionsUnavailableNote = "暂时读不到这个用户的订阅，发放后以服务器结果为准"

    /// The subject line after “王小明 · ”: the email on step 1, then what the chosen type changes.
    public static func subjectLine(user: AdminUser, type: CompensationType?, groupName: String?, plan: SubscriptionGrantPlan?,
                                   now: Date, timeZone: TimeZone) -> String {
        switch type {
        case nil: return user.email
        case .balance?: return "余额 " + DisplayFormat.money(user.balance)
        case .concurrency?: return "并发上限 " + (user.concurrency.map { $0 == 0 ? "不限制" : "\($0)" } ?? DisplayFormat.missing)
        case .subscription?:
            let group = groupName ?? CompensationType.subscription.grantLabel
            guard let plan else { return group }
            let end = plan.currentExpiry.map { RedeemPresentation.day($0, now: now, timeZone: timeZone) }
            return switch plan.kind {
            case .new: group + " 未订阅"
            case .extend: group + " 至 " + (end ?? DisplayFormat.missing)
            case .resume: group + " 已暂停，至 " + (end ?? DisplayFormat.missing)
            case .renew: end.map { "\(group) \($0) 已过期" } ?? group + " 已过期"
            }
        }
    }
    /// “新开通 · 到期 11/15” / “到期 10/30 → 11/29” / “恢复生效 · 到期 10/30 → 11/29” / “重新开通 · 到期 11/15”.
    public static func planChange(_ plan: SubscriptionGrantPlan, now: Date, timeZone: TimeZone) -> String {
        let new = RedeemPresentation.day(plan.newExpiry, now: now, timeZone: timeZone)
        let old = RedeemPresentation.day(plan.currentExpiry, now: now, timeZone: timeZone)
        return switch plan.kind {
        case .new: "新开通 · 到期 " + new
        case .extend: "到期 \(old) → \(new)"
        case .resume: "恢复生效 · 到期 \(old) → \(new)"
        case .renew: "重新开通 · 到期 " + new
        }
    }
    /// Step 2's explanation of the plan.
    public static func planNote(_ plan: SubscriptionGrantPlan, now: Date, timeZone: TimeZone) -> String {
        let old = plan.currentExpiry.map { RedeemPresentation.day($0, now: now, timeZone: timeZone) }
        return switch plan.kind {
        case .new: "还没有这个订阅：从今天开通。"
        case .extend: "已有生效中的订阅：在原到期日 \(old ?? DisplayFormat.missing) 上延长。"
        case .resume: "订阅暂停中：在原到期日上延长，并恢复为生效。"
        case .renew: "订阅" + (old.map { " \($0) " } ?? "") + "已过期：从今天重新算，用量清零。"
        }
    }
    /// Step 3's receipt: 对象, 站点, 类型, 数值 (not for balance), 变化, 兑换码 (short), 发放 (balance only, emphasized).
    public static func receiptRows(_ summary: GrantSummary, user: AdminUser, siteName: String, code: String) -> [GrantReceiptRow] {
        var rows = [GrantReceiptRow(label: "对象", value: user.displayName + " · " + user.email), GrantReceiptRow(label: "站点", value: siteName),
                    GrantReceiptRow(label: "类型", value: summary.type.grantLabel)]
        if !summary.isMoney { rows.append(GrantReceiptRow(label: "数值", value: summary.value)) }
        rows += [GrantReceiptRow(label: "变化", value: summary.change), GrantReceiptRow(label: "兑换码", value: RedeemPresentation.shortCode(code))]
        if summary.isMoney { rows.append(GrantReceiptRow(label: "发放", value: summary.short, isEmphasized: true)) }
        return rows
    }
    /// 向「王小明」发放 $10.00 余额？ with “站点 主站 · <变化>”, the notes, a disabled user's warning and the Face ID line.
    public static func confirmation(_ summary: GrantSummary, userName: String, siteName: String, notes: String, userDisabled: Bool,
                                    faceIDLine: String?) -> GrantConfirmation {
        var lines = ["站点 \(siteName) · \(summary.change)"]
        if !notes.isEmpty { lines.append("备注：" + notes) }
        if userDisabled { lines.append("该用户已禁用。\n发放后仍不能调用，需先启用。") }
        if let faceIDLine { lines.append(faceIDLine) }
        return GrantConfirmation(title: "向「\(userName)」发放 \(summary.what)？", message: lines.joined(separator: "\n"), button: summary.submitTitle,
                                 isDestructive: summary.isMoney)
    }
    /// A saved record in words, for receipts and the pending page: “$10.00 余额” / “+2 并发” / “企业专线 30 天订阅”.
    public static func what(of grant: PendingCompensation, groupName: String?) -> String {
        switch grant.type {
        case .balance: return DisplayFormat.moneyExact(grant.value) + " 余额"
        case .concurrency: return "+" + DisplayFormat.number(grant.value, minFraction: 0, maxFraction: nil) + " 并发"
        case .subscription:
            let group = groupName ?? grant.groupID.map(unnamedGroup) ?? CompensationType.subscription.grantLabel
            return "\(group) \(grant.validityDays ?? NSDecimalNumber(decimal: grant.value).intValue) 天订阅"
        }
    }
    public static func grantedReceipt(userName: String, what: String, replayed: Bool) -> String {
        replayed ? "这笔补偿此前已发放，没有重复执行" : "已向 \(userName) 发放 \(what)"
    }
    /// 60 §19.4 step 6: the check found it redeemed for this user.
    public static func reconciledReceipt(_ grant: PendingCompensation, groupName: String?) -> String {
        "已核对：" + grantedReceipt(userName: grant.userDisplayName, what: what(of: grant, groupName: groupName), replayed: false)
    }

    static func concurrencyText(_ count: Int) -> String { "+\(count) 并发" }
    static func unnamedGroup(_ id: Int) -> String { "分组 #\(id)" }
}
