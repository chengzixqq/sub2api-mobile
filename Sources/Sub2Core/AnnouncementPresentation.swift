import Foundation

public struct AnnouncementBadge: Sendable, Equatable {
    public let label: String
    public let tone: Tone
    public init(label: String, tone: Tone) { self.label = label; self.tone = tone }
}

/// The 已读情况 row of the detail (60 §16.3).
public struct AnnouncementReadLine: Sendable, Equatable {
    public let title: String
    /// “已读 410 / 符合条件 1,036”; nil without `announcements.read_stats` or when the summary failed.
    public let value: String?
    public let detail: String
    public init(title: String, value: String?, detail: String) { self.title = title; self.value = value; self.detail = detail }
}

/// A row of the 已读情况 page (60 §18.3).
public struct AnnouncementReadRowText: Sendable, Equatable {
    public let initial: String
    public let email: String
    public let balance: String
    public let username: String
    public let badge: AnnouncementBadge
    /// “10/16 08:12”, or “未读” drawn grey (`isRead == false`).
    public let readText: String
    public let isRead: Bool
    /// No longer eligible: the row is idle.
    public let isDimmed: Bool
    public init(initial: String, email: String, balance: String, username: String, badge: AnnouncementBadge, readText: String, isRead: Bool,
                isDimmed: Bool) {
        self.initial = initial; self.email = email; self.balance = balance; self.username = username; self.badge = badge
        self.readText = readText; self.isRead = isRead; self.isDimmed = isDimmed
    }
}

/// 发布 / 重新发布 confirmation (60 §16.4, §17.4); the button titles are the caller's.
public struct AnnouncementPublishConfirmation: Sendable, Equatable {
    public let title: String
    public let message: String
    public init(title: String, message: String) { self.title = title; self.message = message }
}

/// The only source of announcement wording (60 §15.3, §16.3, §17.3, §18.3, S6D1-01). Start and end are times the administrator
/// typed, so they follow the phone's zone (00 §6.3); updated_at, read_at and computed_at follow the server's (R20).
public enum AnnouncementPresentation {
    public static let everyoneText = "所有用户", otherConditionText = "其他条件"
    public static let startNowText = "立即", endNeverText = "永久"
    public static let untitledText = "未命名公告"
    public static let readsTitle = "已读情况", readsHint = "逐个用户看：是否符合条件、什么时候读的"
    public static let readsSearchPrompt = "搜索邮箱或用户名", eligibleOnlyTitle = "只看符合条件"
    public static let loadingMoreText = "滚到底自动加载下一页", unreadText = "未读"
    public static let titleTooLongFootnote = "标题太长（最多约 66 个汉字）"

    // MARK: Targeting (15.3)

    /// Conditions of a group joined by “ 且 ”, groups by “ 或 ”; a group name not in the directory is “分组 #3”.
    public static func targetText(_ targeting: AnnouncementTargeting, groupNames: (Int) -> String?) -> String {
        guard !targeting.isEveryone else { return everyoneText }
        return targeting.anyOf.map { group in
            group.allOf.map { conditionText($0, groupNames: groupNames) }.joined(separator: " 且 ")
        }.joined(separator: " 或 ")
    }
    public static func targetText(_ targeting: AnnouncementTargeting, groupNames: [Int: String]) -> String {
        targetText(targeting, groupNames: { groupNames[$0] })
    }
    /// “订阅 企业专线、高级组”, “余额 < $5.00” (a balance the backend left out is 0); anything else “其他条件”.
    public static func conditionText(_ condition: AnnouncementCondition, groupNames: (Int) -> String?) -> String {
        guard condition.isValid else { return otherConditionText }
        if condition.type == AnnouncementCondition.subscriptionType {
            return "订阅 " + condition.groupIDs.map { nonBlank(groupNames($0)) ?? "分组 #\($0)" }.joined(separator: "、")
        }
        guard let symbol = comparisonSymbol(condition.operator) else { return otherConditionText }
        return "余额 \(symbol) " + DisplayFormat.money(condition.effectiveValue)
    }
    public static func comparisonSymbol(_ comparison: String) -> String? {
        switch comparison {
        case "gt": ">"
        case "gte": "≥"
        case "lt": "<"
        case "lte": "≤"
        case "eq": "="
        default: nil
        }
    }
    /// What the phone can edit (60 §17.3): everyone, or exactly one valid condition. Anything else is read-only.
    public static func isSimpleTarget(_ targeting: AnnouncementTargeting) -> Bool {
        guard let group = targeting.anyOf.first else { return true }
        return targeting.anyOf.count == 1 && group.allOf.count == 1 && group.allOf[0].isValid
    }

    // MARK: Status and titles (15.1, 15.3, 16.1)

    public static func statusTitle(_ status: AnnouncementStatus) -> String {
        switch status {
        case .draft: "草稿"
        case .active: "展示中"
        case .archived: "已归档"
        }
    }
    public static func badge(_ status: AnnouncementStatus?) -> AnnouncementBadge? {
        status.map { AnnouncementBadge(label: statusTitle($0), tone: $0 == .active ? .ok : .neutral) }
    }
    public static func isDimmed(_ status: AnnouncementStatus?) -> Bool { status == .archived }
    /// nil = 全部.
    public static func segmentName(_ status: AnnouncementStatus?) -> String { status.map(statusTitle) ?? "全部" }
    /// “全部 5”; a count that failed shows the name only.
    public static func segmentTitle(_ status: AnnouncementStatus?, counts: AnnouncementCounts?) -> String {
        guard let count = counts?.count(for: status) else { return segmentName(status) }
        return segmentName(status) + " " + DisplayFormat.grouped(count)
    }
    public static func notifyTitle(_ mode: AnnouncementNotifyMode) -> String { mode == .popup ? "弹窗" : "静默" }
    public static func notifySymbol(_ mode: AnnouncementNotifyMode) -> String { mode == .popup ? "megaphone" : "bell" }
    /// “<站点名> · N 条”.
    public static func navigationSubtitle(siteName: String, count: Int?) -> String {
        guard let count else { return siteName }
        let total = DisplayFormat.grouped(count) + " 条"
        return nonBlank(siteName) == nil ? total : siteName + " · " + total
    }
    /// “展示中 · 弹窗”: the detail's subtitle and the ··· menu's caption.
    public static func detailSubtitle(status: AnnouncementStatus?, notifyMode: AnnouncementNotifyMode) -> String {
        [status.map(statusTitle), notifyTitle(notifyMode)].compactMap { $0 }.joined(separator: " · ")
    }
    public static func displayTitle(_ title: String) -> String { nonBlank(title) == nil ? untitledText : title }
    public static func publishConfirmation(title: String, targetText: String, notifyMode: AnnouncementNotifyMode, startsAt: Date?, endsAt: Date?,
                                           now: Date, timeZone: TimeZone) -> AnnouncementPublishConfirmation {
        let delivery = notifyMode == .popup ? "用户打开时弹窗提示" : "静默出现在通知里"
        let range = rangeText(startsAt: startsAt, endsAt: endsAt, now: now, timeZone: timeZone)
        return AnnouncementPublishConfirmation(title: "发布「\(displayTitle(title))」？", message: "\(targetText) · \(delivery)\n有效期 \(range)")
    }

    // MARK: Times (15.3, 16.3)

    /// “10/16 08:00”, “2027/01/31 09:20” in another year than `now`. S6-26 moves this to DisplayFormat.monthDayClock (S6D1-16).
    public static func timestamp(_ date: Date?, now: Date, timeZone: TimeZone) -> String {
        guard let date else { return DisplayFormat.missing }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = pad(parts.month) + "/" + pad(parts.day) + " " + pad(parts.hour) + ":" + pad(parts.minute)
        guard let year = parts.year, year != calendar.component(.year, from: now) else { return stamp }
        return String(year) + "/" + stamp
    }
    public static func startText(_ date: Date?, now: Date, timeZone: TimeZone) -> String {
        date == nil ? startNowText : timestamp(date, now: now, timeZone: timeZone)
    }
    public static func endText(_ date: Date?, now: Date, timeZone: TimeZone) -> String {
        date == nil ? endNeverText : timestamp(date, now: now, timeZone: timeZone)
    }
    public static func rangeText(startsAt: Date?, endsAt: Date?, now: Date, timeZone: TimeZone) -> String {
        startText(startsAt, now: now, timeZone: timeZone) + " – " + endText(endsAt, now: now, timeZone: timeZone)
    }
    /// The row's third line: “弹窗 · 10/16 08:00 – 10/18 06:00”, a draft “静默 · 更新于 10/16 09:05”. Only an active one gets
    /// “（未开始）” / “（已结束）”, on the backend's IsActiveAt bounds; `now` is the server-corrected clock.
    public static func scheduleLine(_ announcement: Announcement, now: Date, localTimeZone: TimeZone, serverTimeZone: TimeZone) -> String {
        let notify = notifyTitle(announcement.notifyMode)
        guard announcement.status != .draft else { return notify + " · 更新于 " + timestamp(announcement.updatedAt, now: now, timeZone: serverTimeZone) }
        let line = notify + " · " + rangeText(startsAt: announcement.startsAt, endsAt: announcement.endsAt, now: now, timeZone: localTimeZone)
        guard announcement.status == .active else { return line }
        if let startsAt = announcement.startsAt, now < startsAt { return line + "（未开始）" }
        if let endsAt = announcement.endsAt, now >= endsAt { return line + "（已结束）" }
        return line
    }

    // MARK: Reads (15.3, 16.3, 18.3, U44)

    /// “已读 410/1,036” (eligible readers / eligible users) beside a published row.
    public static func listReadProgress(_ announcement: Announcement, supportsReadStats: Bool) -> String? {
        guard supportsReadStats, announcement.status != .draft, let stats = announcement.readStats else { return nil }
        return "已读 " + DisplayFormat.grouped(stats.eligibleReadCount) + "/" + DisplayFormat.grouped(stats.eligibleCount)
    }
    /// nil for a draft. The share follows 00 §6.2 (one decimal), the readers who no longer qualify only when there are any.
    public static func detailReadLine(status: AnnouncementStatus?, supportsReadStats: Bool, summary: AnnouncementReadSummary?,
                                      serverTimeZone: TimeZone) -> AnnouncementReadLine? {
        guard status != .draft else { return nil }
        guard supportsReadStats, let summary else { return AnnouncementReadLine(title: readsTitle, value: nil, detail: readsHint) }
        let share = summary.eligibleCount > 0 ? DisplayFormat.ratioPercent(Double(summary.eligibleReadCount) / Double(summary.eligibleCount)) : nil
        let others = summary.readButIneligible > 0 ? "另有 \(DisplayFormat.grouped(summary.readButIneligible)) 人读后已不符合条件" : nil
        let detail = [share, others, computedText(summary, serverTimeZone)].compactMap { $0 }.joined(separator: " · ")
        let value = "已读 \(DisplayFormat.grouped(summary.eligibleReadCount)) / 符合条件 \(DisplayFormat.grouped(summary.eligibleCount))"
        return AnnouncementReadLine(title: readsTitle, value: value, detail: detail)
    }
    /// With a summary “已读 412 · 符合条件 1,036 · 共 1,036 位用户 · 统计于 09:41” (all readers); without one the page's `total`.
    public static func readsSummaryBar(_ summary: AnnouncementReadSummary?, total: Int?, serverTimeZone: TimeZone) -> String {
        guard let summary else { return ["第 1 页", total.map { "共 \(DisplayFormat.grouped($0)) 位用户" }].compactMap { $0 }.joined(separator: " · ") }
        return ["已读 \(DisplayFormat.grouped(summary.readCount))", "符合条件 \(DisplayFormat.grouped(summary.eligibleCount))",
                "共 \(DisplayFormat.grouped(summary.totalUsers)) 位用户", computedText(summary, serverTimeZone)].compactMap { $0 }.joined(separator: " · ")
    }
    /// “找到 N 位”, only while a search or filter is on.
    public static func readsResultCount(total: Int?, isFiltered: Bool) -> String? {
        guard isFiltered, let total else { return nil }
        return "找到 \(DisplayFormat.grouped(total)) 位"
    }
    public static func readRow(_ row: AnnouncementReadStatusRow, now: Date, serverTimeZone: TimeZone) -> AnnouncementReadRowText {
        let badge = row.eligible ? AnnouncementBadge(label: "符合条件", tone: .ok) : AnnouncementBadge(label: "不符合", tone: .neutral)
        return AnnouncementReadRowText(initial: initial(username: row.username, email: row.email), email: row.email,
                                       balance: DisplayFormat.money(row.balance), username: row.username, badge: badge,
                                       readText: row.readAt.map { timestamp($0, now: now, timeZone: serverTimeZone) } ?? unreadText,
                                       isRead: row.readAt != nil, isDimmed: !row.eligible)
    }

    // MARK: Title (17.3)

    /// UTF-8 bytes after trimming, as the backend counts them.
    public static func titleByteCount(_ title: String) -> Int { title.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count }
    public static func isTitleTooLong(_ title: String) -> Bool { titleByteCount(title) > AnnouncementCreateRequest.titleByteLimit }

    // MARK: Helpers

    private static func computedText(_ summary: AnnouncementReadSummary, _ serverTimeZone: TimeZone) -> String? {
        summary.computedAt.map { "统计于 " + DisplayFormat.clock($0, timeZone: serverTimeZone) }
    }
    /// The username's first character, else the email's, uppercased; “?” when both are blank.
    private static func initial(username: String, email: String) -> String {
        let first = [username, email].lazy.compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).first }.first
        return first.map { String($0).uppercased() } ?? "?"
    }
    private static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
    private static func pad(_ value: Int?) -> String {
        let value = value ?? 0
        return value < 10 ? "0\(value)" : String(value)
    }
}
