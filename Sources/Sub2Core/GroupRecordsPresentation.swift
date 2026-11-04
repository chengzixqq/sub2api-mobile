import Foundation

// 50 §6–§7 (S5-12): the group's API key page and subscription page — paging, rows and words. Key statuses are AdminAPIKeyStatus
// (R13), limits GroupFormat.limitText, group errors GroupErrorCopy (S5-02).

public enum GroupRecordsPolicy {
    /// 50 §6.2 / §7.2.
    public static let pageSize = PageSize.standard
    /// 50 §7.3: an active subscription ending within this many days (today included) is caution.
    public static let soonDays = 7
}

/// The pages read so far (50 §6.6, §7.6). Offset pages shift when a row is added meanwhile, so a later page adds only ids not
/// shown yet; total and hasMore follow the latest page, and an empty page ends paging. A pull starts again from `init(first:)`.
public struct GroupRecordsFeed<Row: Decodable & Identifiable & Sendable>: Sendable where Row.ID == Int {
    public let rows: [Row]
    public let total: Int?
    public let page: Int
    public let hasMore: Bool
    public var nextPage: Int { page + 1 }

    public init(first: Page<Row>) { self.init(rows: first.items, latest: first) }
    private init(rows: [Row], latest: Page<Row>) {
        self.rows = rows; total = latest.total; page = latest.page; hasMore = latest.hasMore && !latest.items.isEmpty
    }
    public func appending(_ next: Page<Row>) -> GroupRecordsFeed<Row> {
        var seen = Set(rows.map(\.id))
        return GroupRecordsFeed(rows: rows + next.items.filter { seen.insert($0.id).inserted }, latest: next)
    }
    /// “已显示 20 / 38 个 · 滚动到底继续加载”; without a total “已显示 20 个 · …”; nil once everything is shown.
    public func moreHint(unit: String) -> String? {
        guard hasMore else { return nil }
        let shown = DisplayFormat.grouped(rows.count)
        return "已显示 " + (total.map { shown + " / " + DisplayFormat.grouped($0) } ?? shown) + " \(unit) · 滚动到底继续加载"
    }
}
extension GroupRecordsFeed: Equatable where Row: Equatable {}

/// 50 §6.3 第二行右: today's actual charge. `missing` is a failed usage read or a read-only token, which never asks (R14); `stale`
/// is an earlier amount kept through a failed read (S5-高-3), so only a first read that failed says 今日 —.
public enum GroupKeyToday: Sendable, Equatable {
    case pending, amount(Decimal), stale(Decimal), missing

    public var text: String {
        switch self {
        case .amount(let value): "今日 " + DisplayFormat.money(value)
        case .stale(let value): "今日 " + DisplayFormat.money(value) + " · " + BlockStatusPresentation.updateFailed
        case .pending, .missing: "今日 " + DisplayFormat.missing
        }
    }
    public var spoken: String {
        switch self {
        case .amount: text
        case .stale(let value): "今日 " + DisplayFormat.money(value) + "，" + BlockStatusPresentation.updateFailed
        case .pending: "今日读取中"
        case .missing: "今日" + DisplayFormat.missingSpoken
        }
    }
    /// A fresh amount only.
    public var isAmount: Bool { if case .amount = self { true } else { false } }
    public var isStale: Bool { if case .stale = self { true } else { false } }
    /// The amount the row shows, fresh or kept.
    public var lastAmount: Decimal? {
        switch self {
        case .amount(let value), .stale(let value): value
        case .pending, .missing: nil
        }
    }
    /// After a failed read: the amount shown so far stays, marked; without one 今日 —.
    public var afterFailure: GroupKeyToday { lastAmount.map(GroupKeyToday.stale) ?? .missing }
    /// A requested id the reply leaves out spent nothing today (the server omits it).
    public static func resolve(id: Int, reply: [Int: Decimal]) -> GroupKeyToday { .amount(reply[id] ?? 0) }
}

/// 50 §6.3 one key row; only key_masked is ever shown, never a plaintext.
public struct GroupKeyRow: Sendable, Equatable, Identifiable {
    public let id: Int
    /// nil leaves the row without a destination.
    public let userID: Int?
    /// S3D1-12: the unescaped name.
    public let name: String
    public let status: AdminAPIKeyStatus
    public let mask: String
    public let owner: String
    public let lastUsed: String
    public let today: GroupKeyToday
    /// Only for a key with its own quota (quota > 0).
    public let quota: CapacityRow?

    public init(_ key: AdminAPIKey, today: GroupKeyToday, now: Date, timeZone: ServerTimeZone) {
        id = key.id; userID = key.userID ?? key.user?.id; name = key.displayName; status = key.status(now: now)
        mask = key.keyMasked.flatMap { $0.isEmpty ? nil : $0 } ?? DisplayFormat.missing
        owner = Self.owner(key); lastUsed = Self.lastUsedText(key.lastUsedAt, now: now, timeZone: timeZone); self.today = today
        quota = key.quota > 0 ? .money(id: "quota", title: "额度", used: key.quotaUsed, limit: key.quota) : nil
    }

    /// 已停用 / 额度耗尽 / 已过期; none for an active key. Simple mode never reaches this page (50 §6.3).
    public var badge: String? { status.badge(simpleMode: false) }
    public var badgeTone: Tone { status.tone }
    public var railTone: Tone? { status == .quotaExhausted ? .caution : nil }
    public var isDimmed: Bool { status == .inactive || status == .expired }
    /// “Nova 工作室 · 09:38”.
    public var secondLine: String { owner + " · " + lastUsed }
    public var spokenLabel: String {
        [name, badge, DisplayFormat.spoken(mask), secondLine, today.spoken, quota.map { $0.title + " " + $0.spokenValue }]
            .compactMap { $0 }.joined(separator: "，")
    }

    /// The username, else the email, else “用户 #id”; “（已禁用）” after a disabled user.
    public static func owner(_ key: AdminAPIKey) -> String {
        let user = key.user
        let name = GroupRecordsCopy.nonBlank(user?.username) ?? GroupRecordsCopy.nonBlank(user?.email)
            ?? (key.userID ?? user?.id).map { "用户 #\($0)" } ?? DisplayFormat.missing
        return user?.status == "disabled" ? name + "（已禁用）" : name
    }
    /// S5D2a-14: HH:mm on the server's today, otherwise DisplayFormat.monthDayClock; 从未使用 without a time.
    public static func lastUsedText(_ date: Date?, now: Date, timeZone: ServerTimeZone) -> String {
        guard let date else { return "从未使用" }
        guard timeZone.calendar.isDate(date, inSameDayAs: now) else { return DisplayFormat.monthDayClock(date, timeZone: timeZone, now: now) }
        return DisplayFormat.clock(date, timeZone: timeZone.timeZone)
    }
}

/// 50 §7.3 one usage column of an active subscription against the group's per-subscription limit.
public struct GroupSubscriptionWindow: Sendable, Equatable, Identifiable {
    public enum Span: String, CaseIterable, Sendable {
        case daily, weekly, monthly
        public var label: String {
            switch self {
            case .daily: "每日"
            case .weekly: "每周"
            case .monthly: "每月"
            }
        }
    }
    public static let unlimited = "无限制"
    public let span: Span
    public let used: String
    /// nil is 无限制: no bar.
    public let limit: String?
    public let fraction: Double?
    public let tone: Tone?
    public var id: Span { span }

    public init(_ span: Span, used: Decimal?, limit: Decimal?) {
        self.span = span
        self.used = DisplayFormat.money(used)
        self.limit = limit.map { GroupFormat.limitText($0) }
        fraction = GroupPresentation.usageFraction(used: used, limit: limit)
        tone = GroupPresentation.usageTone(used: used, limit: limit)
    }
    /// “$18.60 / $100”, or “$18.60” without a limit.
    public var readout: String { limit.map { used + " / " + $0 } ?? used }
    public var spoken: String {
        let usedText = DisplayFormat.spoken(used)
        guard let limit else { return "\(span.label) \(usedText)，\(Self.unlimited)" }
        return "\(span.label) \(usedText) / \(limit)"
    }
}

/// 50 §7.3 one subscription row.
public struct GroupSubscriptionRow: Sendable, Equatable, Identifiable {
    public enum Trailing: Sendable, Equatable { case daysLeft(text: String, tone: Tone?), badge(String), none }
    public let id: Int
    public let userID: Int?
    public let initial: String
    public let name: String
    public let isActive: Bool
    public let trailing: Trailing
    /// Only an active subscription shows its usage.
    public let windows: [GroupSubscriptionWindow]
    /// “至 2026-10-20 · lin@…”, “2026-10-09 已到期 · …”.
    public let detail: String

    public init(_ subscription: AdminUserSubscription, group: AdminGroup, now: Date, timeZone: ServerTimeZone) {
        let user = subscription.user, email = GroupRecordsCopy.nonBlank(user?.email)
        id = subscription.id; userID = subscription.userID ?? user?.id
        name = GroupRecordsCopy.nonBlank(user?.username) ?? email ?? userID.map { "用户 #\($0)" } ?? DisplayFormat.missing
        initial = user == nil ? "?" : UserPresentation.initial(name)
        isActive = subscription.status == "active"
        trailing = Self.trailing(subscription, now: now, timeZone: timeZone)
        windows = isActive ? [GroupSubscriptionWindow(.daily, used: subscription.dailyUsageUSD, limit: group.dailyLimitUSD),
                              GroupSubscriptionWindow(.weekly, used: subscription.weeklyUsageUSD, limit: group.weeklyLimitUSD),
                              GroupSubscriptionWindow(.monthly, used: subscription.monthlyUsageUSD, limit: group.monthlyLimitUSD)] : []
        let day = subscription.expiresAt.map(timeZone.dayString) ?? DisplayFormat.missing
        let end = subscription.status == "expired" ? day + " 已到期" : "至 " + day
        detail = email.map { end + " · " + $0 } ?? end
    }

    public var railTone: Tone? { if case .daysLeft(_, let tone) = trailing { tone } else { nil } }
    public var isDimmed: Bool { !isActive }
    public var trailingText: String? {
        switch trailing {
        case .daysLeft(let text, _), .badge(let text): text
        case .none: nil
        }
    }
    public var spokenLabel: String {
        ([name] + [trailingText].compactMap { $0 } + windows.map(\.spoken) + [detail]).joined(separator: "，")
    }

    private static func trailing(_ subscription: AdminUserSubscription, now: Date, timeZone: ServerTimeZone) -> Trailing {
        switch subscription.status {
        case "active":
            guard let days = GroupPresentation.subscriptionDaysLeft(subscription.expiresAt, now: now, timeZone: timeZone) else { return .none }
            return .daysLeft(text: GroupPresentation.subscriptionDaysText(days), tone: GroupPresentation.subscriptionDaysTone(days))
        case "suspended": return .badge("已暂停")
        case "expired": return .badge("已过期")
        default: return .none
        }
    }
}

/// 50 §7.3 页头: one of the group's three per-subscription limits.
public struct GroupSubscriptionLimit: Sendable, Equatable, Identifiable {
    public let span: GroupSubscriptionWindow.Span
    public let value: String
    public var id: GroupSubscriptionWindow.Span { span }
}

/// 50 §6.3 / §7.3 words.
public enum GroupRecordsCopy {
    public static let keysTitle = "API 密钥"
    public static let keysHeadLeading = "新建的在前"
    public static let keysHeadTrailing = "所属用户 · 最近使用 · 今日"
    public static let keysEmpty = "还没有 API 密钥使用这个分组"
    public static let keysFootnote = "点按进入所属用户。给 Key 换分组、重置速率限制在用户的 Key 里操作。"
    public static let keysUnit = "个"
    public static let subscriptionsTitle = "订阅"
    public static let limitsCaption = "每个订阅的限额"
    public static let subscriptionsHeadLeading = "新分配的在前"
    public static let subscriptionsHeadTrailing = "用量 · 到期"
    public static let subscriptionsEmpty = "这个分组还没有订阅"
    public static let subscriptionsFootnote = "点按进入用户。调整有效期、重置配额、撤销在 Web 订阅管理中操作。"
    public static let subscriptionsUnit = "条"
    public static let moreFailed = "加载失败 · 重试"
    public static let refreshFailed = "刷新失败 · 重试"
    /// S5-高-3 (U-12's own wording): above the keys whose today amount is kept through a failed read, and above the limits while
    /// the subtitle's 生效中 count is.
    public static let todayStale = "今日金额更新失败 · 重试"
    public static let activeCountStale = "生效中计数更新失败 · 重试"

    /// “高级组 · 共 38 个”; either part alone when the other is unknown.
    public static func keysSubtitle(groupName: String?, total: Int?) -> String {
        [groupName, total.map { "共 \(DisplayFormat.grouped($0)) 个" }].compactMap { $0 }.joined(separator: " · ")
    }
    /// “企业专线 · 生效中 12 个”; only the name while the active count is unknown.
    public static func subscriptionsSubtitle(groupName: String?, active: Int?) -> String {
        [groupName, active.map { "生效中 \(DisplayFormat.grouped($0)) 个" }].compactMap { $0 }.joined(separator: " · ")
    }
    public static func limits(_ group: AdminGroup) -> [GroupSubscriptionLimit] {
        [(GroupSubscriptionWindow.Span.daily, group.dailyLimitUSD), (.weekly, group.weeklyLimitUSD), (.monthly, group.monthlyLimitUSD)]
            .map { GroupSubscriptionLimit(span: $0.0, value: GroupFormat.limitText($0.1)) }
    }
    /// “每个订阅的限额，每日 $20，每周 $100，每月 $300”.
    public static func limitsSpoken(_ limits: [GroupSubscriptionLimit]) -> String {
        ([limitsCaption] + limits.map { $0.span.label + " " + $0.value }).joined(separator: "，")
    }
    /// “更新于 09:41” beside 刷新失败 (00 §4.6).
    public static func updatedText(_ date: Date?, timeZone: ServerTimeZone) -> String? {
        date.map { "更新于 " + DisplayFormat.clock($0, timeZone: timeZone.timeZone) }
    }
    /// 50 §6.5: on these two reads only the App's own parameters earn a 400 (an unknown key_view, with an empty reason).
    public static func isParameterError(_ error: any Error) -> Bool { (error as? APIError)?.statusCode == 400 }
    /// 50 §0.8's words for 403 FORBIDDEN / SIMPLE_MODE_OPERATION_UNSUPPORTED (the entries are hidden, so neither should come);
    /// anything else is 加载失败 (R11: the server's message is never shown).
    public static func failureTitle(_ error: APIError?) -> String {
        guard let error, error.statusCode == 403, let reason = error.reason,
              let text = GroupErrorCopy.reasonText(reason, context: .read) else { return BlockStatusPresentation.loadFailed }
        return text
    }

    static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

// MARK: - S5-12 订阅剩余天数与用量色调（50 §7.3，S5D2a-18）

extension GroupPresentation {
    /// Whole days on the server's calendar from today to the day of `expiresAt` (00 §6.3); negative once past, nil without a date.
    public static func subscriptionDaysLeft(_ expiresAt: Date?, now: Date, timeZone: ServerTimeZone) -> Int? {
        expiresAt.map { ProxyExpiry.days(until: $0, now: now, timeZone: timeZone) }
    }
    /// “剩余 4 天”; 0 or less (a lapse the server has not marked yet) is “今天到期”.
    public static func subscriptionDaysText(_ days: Int) -> String { days <= 0 ? "今天到期" : "剩余 \(days) 天" }
    /// Caution within GroupRecordsPolicy.soonDays, today included.
    public static func subscriptionDaysTone(_ days: Int) -> Tone? { days <= GroupRecordsPolicy.soonDays ? .caution : nil }
    /// used ÷ limit, not clamped; nil without a usage, or with no limit (无限制) or one of 0 or less.
    public static func usageFraction(used: Decimal?, limit: Decimal?) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return NSDecimalNumber(decimal: used / limit).doubleValue
    }
    /// Caution from 75%, critical from 90% (CapacityRow.level's thresholds).
    public static func usageTone(used: Decimal?, limit: Decimal?) -> Tone? { CapacityRow.level(usageFraction(used: used, limit: limit)) }
}
