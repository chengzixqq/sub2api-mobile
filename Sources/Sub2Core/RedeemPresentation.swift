import Foundation

// MARK: Labels (60 §8.3, §10.3)

extension RedeemCodeType {
    public var label: String {
        switch self {
        case .balance: "余额"
        case .concurrency: "并发数"
        case .subscription: "订阅"
        case .invitation: "邀请码"
        }
    }
}

extension RedeemCodeStatus {
    public var label: String {
        switch self {
        case .unused: "未使用"
        case .used: "已使用"
        case .expired: "已过期"
        case .disabled: "已禁用"
        }
    }
    public var tone: Tone { self == .unused ? .ok : .neutral }
}

extension AdminGroup {
    /// The groups a subscription code may point at (60 §9.2, §10.2): subscription type and enabled.
    public var isActiveSubscriptionGroup: Bool { subscriptionType == "subscription" && status == "active" }
}

public struct RedeemFaceValue: Sendable, Equatable {
    public let text: String
    /// Invitation codes carry no value and are drawn grey.
    public let isMuted: Bool
}

public struct RedeemBadge: Sendable, Equatable {
    public let label: String
    public let tone: Tone
}

/// The expanded card's expiry row; `tone` is caution for an unused code with a day or less left.
public struct RedeemExpiryText: Sendable, Equatable {
    public let text: String
    public let tone: Tone?
}

/// The list's sections by `created_at`, on the server's calendar.
public enum RedeemDayGroup: Sendable, Equatable, CaseIterable {
    case today, yesterday, earlier
    public var title: String {
        switch self {
        case .today: "今天生成"
        case .yesterday: "昨天生成"
        case .earlier: "更早生成"
        }
    }
}

/// The buttons under an open card; `more` is the ··· menu.
public enum RedeemCardAction: Sendable, Equatable, CaseIterable {
    case disable, enable, edit, editNotes, renew, more
    public var title: String {
        switch self {
        case .disable: "禁用"
        case .enable: "启用"
        case .edit: "编辑"
        case .editNotes: "编辑备注"
        case .renew: "续期"
        case .more: "更多操作"
        }
    }
    public var isPrimary: Bool { self == .renew }
}

/// The ··· menu, in order; delete is last and red (60 §0.4).
public enum RedeemMenuItem: Sendable, Equatable {
    case copy
    case viewUser(userID: Int, name: String)
    /// U49: after copy, before delete.
    case viewBatch(UUID)
    case delete
    public var title: String {
        switch self {
        case .copy: "复制兑换码"
        case .viewUser(_, let name): "查看使用者 " + name
        case .viewBatch: "查看同一批"
        case .delete: "删除兑换码…"
        }
    }
    public var isDestructive: Bool { self == .delete }
}

/// 60 §8.3 as pure functions. `now` is the server-corrected clock and `timeZone` the server's (00 §6.3).
public enum RedeemPresentation {
    static let maskedGroup = "••••"
    static let dots = "····"

    // MARK: Code text

    /// “a3f0····d4e8”; a code of 8 characters or fewer shows only its tail.
    public static func shortCode(_ code: String) -> String {
        code.count > 8 ? String(code.prefix(4)) + dots + tail(code) : dots + tail(code)
    }
    public static func tail(_ code: String) -> String { String(code.suffix(4)) }
    /// The delete confirmation's object: “····d4e8”.
    public static func deleteSubject(_ code: String) -> String { dots + tail(code) }
    /// Lines of 16 in groups of 4 (spacing only: a copy is the raw code). Masked, only the first and the last group remain.
    public static func codeLines(_ code: String, revealed: Bool) -> [[String]] {
        guard revealed else {
            return [[String(code.prefix(4)), maskedGroup, maskedGroup, maskedGroup], [maskedGroup, maskedGroup, maskedGroup, tail(code)]]
        }
        return chunks(code, size: 16).map { chunks($0, size: 4) }
    }
    public static func codeSpoken(_ code: String, revealed: Bool) -> String {
        revealed ? code : "兑换码已遮罩，结尾 " + tail(code)
    }

    // MARK: Card head

    public static func typeLabel(_ type: String) -> String {
        if let known = RedeemCodeType(rawValue: type) { return known.label }
        switch type {
        case "admin_balance": return "余额（管理员调整）"
        case "admin_concurrency": return "并发（管理员调整）"
        default: return "其他类型"
        }
    }
    public static func faceValue(_ code: AdminRedeemCode) -> RedeemFaceValue {
        switch code.type {
        case "balance", "admin_balance": RedeemFaceValue(text: DisplayFormat.money(code.value), isMuted: false)
        case "concurrency", "admin_concurrency": RedeemFaceValue(text: code.value.map(concurrencyText) ?? DisplayFormat.missing, isMuted: false)
        case "subscription": RedeemFaceValue(text: code.validityDays.map { "\($0) 天" } ?? DisplayFormat.missing, isMuted: false)
        case "invitation": RedeemFaceValue(text: "注册邀请", isMuted: true)
        default: RedeemFaceValue(text: DisplayFormat.missing, isMuted: false)
        }
    }
    /// Subscription codes lead with their group: the row's own `group`, else the name the caller found in the group catalog.
    public static func prefix(_ code: AdminRedeemCode, groupName: String?) -> String {
        guard code.type == RedeemCodeType.subscription.rawValue else { return typeLabel(code.type) }
        return trimmed(code.group?.name) ?? trimmed(groupName) ?? RedeemCodeType.subscription.label
    }
    /// username, then email, then “用户 #id”.
    public static func userName(_ code: AdminRedeemCode) -> String {
        if let name = trimmed(code.user?.username) ?? trimmed(code.user?.email) { return name }
        return (code.usedBy ?? code.user?.id).map { "用户 #\($0)" } ?? DisplayFormat.missing
    }
    /// The line under the code; a redeemed code names its user even after it expired or was disabled.
    public static func subtitle(_ code: AdminRedeemCode, groupName: String?, now: Date, timeZone: TimeZone) -> String {
        let head = prefix(code, groupName: groupName)
        func dayOf(_ date: Date?) -> String? { date.map { day($0, now: now, timeZone: timeZone) } }
        if code.isRedeemed { return [head, userName(code), dayOf(code.usedAt)].compactMap { $0 }.joined(separator: " · ") }
        switch code.codeStatus {
        case .expired?: return head + " · " + (dayOf(code.expiresAt).map { $0 + " " } ?? "") + "已过期"
        case .disabled?: return head + " · " + (dayOf(code.createdAt).map { $0 + " " } ?? "") + "生成"
        case .unused?: return head + " · " + (dayOf(code.expiresAt).map { $0 + " 过期" } ?? "永不过期")
        case .used?, nil: return head
        }
    }
    public static func badge(_ code: AdminRedeemCode) -> RedeemBadge {
        guard let status = code.codeStatus else { return RedeemBadge(label: "未知", tone: .neutral) }
        return RedeemBadge(label: status.label, tone: status.tone)
    }
    /// Every card but an unused one is drawn idle.
    public static func isDimmed(_ code: AdminRedeemCode) -> Bool { code.codeStatus != .unused }
    /// The ··· menu's second line: “余额 · $10.00 · 未使用”.
    public static func menuMessage(_ code: AdminRedeemCode) -> String {
        [typeLabel(code.type), faceValue(code).text, badge(code).label].joined(separator: " · ")
    }

    // MARK: Expanded card

    /// “10/23 09:12 · 还剩 7 天” for an unused or disabled code, “· 今天到期” on its last day; an expired one adds “（已过期）”.
    public static func expiry(_ code: AdminRedeemCode, now: Date, timeZone: TimeZone) -> RedeemExpiryText {
        guard let expiresAt = code.expiresAt else { return RedeemExpiryText(text: "永不过期", tone: nil) }
        let stamp = timestamp(expiresAt, now: now, timeZone: timeZone)
        if code.isRedeemed { return RedeemExpiryText(text: stamp, tone: nil) }
        switch code.codeStatus {
        case .expired?: return RedeemExpiryText(text: stamp + "（已过期）", tone: nil)
        case .unused?, .disabled?:
            let days = daysUntil(expiresAt, now: now, timeZone: timeZone)
            let tone: Tone? = code.codeStatus == .unused && days <= 1 ? .caution : nil
            return RedeemExpiryText(text: stamp + " · " + (days <= 0 ? "今天到期" : "还剩 \(days) 天"), tone: tone)
        case .used?, nil: return RedeemExpiryText(text: stamp, tone: nil)
        }
    }

    // MARK: Actions (60 §8.3 按钮行 / ··· 菜单, §8.4 滑动)

    /// A read-only token keeps only ···, whose copy is a read.
    public static func actions(_ code: AdminRedeemCode, readOnly: Bool) -> [RedeemCardAction] {
        guard !readOnly else { return [.more] }
        if code.isRedeemed { return [.editNotes, .more] }
        switch code.codeStatus {
        case .unused?: return [.disable, .edit, .more]
        case .disabled?: return [.enable, .edit, .more]
        case .expired?: return [.renew, .more]
        case .used?, nil: return [.more]
        }
    }
    /// The trailing swipe of a collapsed card; never delete.
    public static func trailingSwipe(_ code: AdminRedeemCode, readOnly: Bool) -> RedeemCardAction? {
        guard !readOnly, !code.isRedeemed else { return nil }
        switch code.codeStatus {
        case .unused?: return .disable
        case .disabled?: return .enable
        case .expired?: return .renew
        case .used?, nil: return nil
        }
    }
    /// Copy, the user who redeemed it, the same batch, delete last. A redeemed code and an admin adjustment are never deleted;
    /// a read-only token keeps the reads.
    public static func menuItems(_ code: AdminRedeemCode, readOnly: Bool) -> [RedeemMenuItem] {
        var items: [RedeemMenuItem] = [.copy]
        if code.isRedeemed, let userID = code.user?.id ?? code.usedBy { items.append(.viewUser(userID: userID, name: userName(code))) }
        if let batchID = code.batchID { items.append(.viewBatch(batchID)) }
        if !readOnly, !code.isRedeemed, !code.isAdminAdjustment { items.append(.delete) }
        return items
    }

    // MARK: Filters and sections

    public static let allTypesTitle = "全部类型"
    /// “全部 128” / “未使用 40”; names only without counts.
    public static func statusChipTitle(_ status: RedeemCodeStatus?, stats: RedeemCodeStats?) -> String {
        let name = status?.label ?? "全部"
        return stats.map { name + " " + DisplayFormat.grouped($0.count(status)) } ?? name
    }
    public static func typeChipTitle(_ type: RedeemCodeType?) -> String { type?.label ?? "类型" }
    /// A day ahead of `now` (clock skew) still counts as today.
    public static func dayGroup(_ createdAt: Date?, now: Date, timeZone: TimeZone) -> RedeemDayGroup {
        guard let createdAt else { return .earlier }
        let days = daysUntil(createdAt, now: now, timeZone: timeZone)
        return days >= 0 ? .today : days == -1 ? .yesterday : .earlier
    }

    // MARK: Dates (S6-26 moves these to DisplayFormat.monthDayClock, S6D1-16)

    /// “10/16 09:20”; another year than `now` keeps it: “2027/01/31 09:20”.
    public static func timestamp(_ date: Date?, now: Date, timeZone: TimeZone) -> String {
        guard let date else { return DisplayFormat.missing }
        let parts = calendar(timeZone).dateComponents([.hour, .minute], from: date)
        return day(date, now: now, timeZone: timeZone) + " " + String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    /// “10/16”, or “2027/01/31” in another year.
    public static func day(_ date: Date?, now: Date, timeZone: TimeZone) -> String {
        guard let date else { return DisplayFormat.missing }
        let calendar = calendar(timeZone)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let monthDay = String(format: "%02d/%02d", parts.month ?? 0, parts.day ?? 0)
        return parts.year == calendar.component(.year, from: now) ? monthDay : String(format: "%04d/", parts.year ?? 0) + monthDay
    }
    /// Server calendar days from today to `date`'s day; negative in the past.
    public static func daysUntil(_ date: Date, now: Date, timeZone: TimeZone) -> Int {
        let calendar = calendar(timeZone)
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    // MARK: Helpers

    private static func concurrencyText(_ value: Decimal) -> String {
        (value < 0 ? DisplayFormat.minus : "+") + DisplayFormat.number(abs(value), minFraction: 0, maxFraction: nil) + " 并发"
    }
    private static func chunks(_ text: String, size: Int) -> [String] {
        stride(from: 0, to: text.count, by: size).map { start in
            let from = text.index(text.startIndex, offsetBy: start)
            return String(text[from..<(text.index(from, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex)])
        }
    }
    static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX"); calendar.timeZone = timeZone
        return calendar
    }
}
