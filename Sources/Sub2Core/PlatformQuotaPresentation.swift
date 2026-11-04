import Foundation

/// 30 §8.3 one window cell of a platform row (design `UeWin`).
public struct PlatformQuotaCell: Sendable, Equatable, Identifiable {
    public let kind: PlatformQuotaWindowKind
    /// “28.0%”, “不限”, “已禁止”, or “—” for an unreadable row.
    public let headline: String
    /// “$2.80 / $10”, “已用 $1.20”, “不能使用”.
    public let reading: String
    public let progress: Double?
    public let tone: Tone?
    public let isBanned: Bool
    public var id: String { kind.rawValue }
    public init(kind: PlatformQuotaWindowKind, headline: String, reading: String, progress: Double?, tone: Tone?, isBanned: Bool) {
        self.kind = kind; self.headline = headline; self.reading = reading; self.progress = progress; self.tone = tone; self.isBanned = isBanned
    }
}

/// 30 §8.3–§8.5 (S3-14): the platform quota section's words, cells and rules. `now` is the server-corrected clock and days follow
/// the server's zone (R20).
public enum PlatformQuotaPresentation {
    // MARK: 分区

    public static let sectionTitle = "平台限额"
    public static let sectionMeta = "日 · 周 · 月"
    public static let subscriptionNotice = "此用户有活跃订阅：平台限额只在余额模式下生效，订阅模式的请求不受限额约束。"
    public static let footnote = "留空 = 不限制，0 = 禁止使用该平台。月为 30 天滚动窗口。"
    public static let empty = "没有设置，各平台不限制"
    public static let add = "添加平台限额"
    public static let bannedBadge = "已禁止使用"
    public static let listFailed = "平台限额加载失败"
    public static let refreshFailed = "平台限额刷新失败，显示的是上次读取的内容"
    public static let pickerTitle = "添加平台限额"

    // MARK: 平台限额 sheet

    public static func sheetTitle(_ platformName: String) -> String { platformName + " 限额" }
    public static let sheetNoteLead = "留空 = 不限制；"
    public static let sheetNoteBold = "0 = 禁止使用该平台"
    public static let sheetNoteTail = "。月为 30 天滚动窗口。"
    public static func inputTitle(_ kind: PlatformQuotaWindowKind) -> String { kind.title + "限额" }
    public static let inputPlaceholder = "不限制"
    public static func zeroWarning(_ platformName: String) -> String { "填 0 会完全禁止使用 \(platformName)，不论其他窗口" }
    public static let resetWindow = "重置该窗口"
    public static let clearAll = "清空三个窗口（取消这个平台的限额）"
    public static let sheetFootnote = "保存和重置都立即生效。"
    public static let unreadable = "平台限额读取不完整，不能保存，请在 Web 端修改"

    // MARK: 回执与确认

    /// The edit page's leave confirmation names it (S3D1-13).
    public static func appliedName(_ platformName: String) -> String { "平台限额（\(platformName)）" }
    public static func updatedReceipt(_ platformName: String) -> String { "已更新 \(platformName) 的平台限额" }
    public static func cancelledReceipt(_ platformName: String) -> String { "已取消 \(platformName) 的平台限额" }
    /// The whole-table undo of 取消 inserts the row again (30 §8.4).
    public static func undoResetsUsageReceipt(_ platformName: String) -> String { "已撤销，\(platformName) 的已用额度会从 0 重新计算" }
    public static func undoFailed(_ text: String) -> String { "撤销没有成功：" + text }
    public static func resetTitle(platform: String, kind: PlatformQuotaWindowKind) -> String { "重置 \(platform) 的\(kind.title)用量？" }
    public static func resetMessage(userName: String, platform: String, kind: PlatformQuotaWindowKind, usage: Decimal) -> String {
        "\(userName)在 \(platform) 的\(kind.title)用量（\(DisplayFormat.money(usage))）会归零。此操作立即生效。"
    }
    public static func resetReceipt(platform: String, kind: PlatformQuotaWindowKind) -> String { "已重置 \(platform) \(kind.title)用量" }

    // MARK: 窗口格

    public static func cells(_ quota: UserPlatformQuota) -> [PlatformQuotaCell] { PlatformQuotaWindowKind.allCases.map { cell(quota, kind: $0) } }
    public static func cell(_ quota: UserPlatformQuota, kind: PlatformQuotaWindowKind) -> PlatformQuotaCell {
        let window = quota.window(kind), used = "已用 " + DisplayFormat.money(window.usage)
        guard quota.limitsReadable else { return PlatformQuotaCell(kind: kind, headline: DisplayFormat.missing, reading: used, progress: nil, tone: nil, isBanned: false) }
        guard let limit = window.limit else { return PlatformQuotaCell(kind: kind, headline: "不限", reading: used, progress: nil, tone: nil, isBanned: false) }
        guard limit > 0 else { return PlatformQuotaCell(kind: kind, headline: "已禁止", reading: "不能使用", progress: nil, tone: .critical, isBanned: true) }
        let ratio = window.usage / limit
        return PlatformQuotaCell(kind: kind, headline: DisplayFormat.percent(NSDecimalNumber(decimal: ratio * 100).doubleValue),
                                 reading: DisplayFormat.money(window.usage) + " / " + limitText(limit),
                                 progress: min(max(NSDecimalNumber(decimal: ratio).doubleValue, 0), 1), tone: meterTone(ratio), isBanned: false)
    }
    /// The sheet's line under a window: “已用 $2.80 · 明天 00:00 重置”, the month “30 天滚动”; the reset only with a limit above 0.
    public static func usageLine(_ window: PlatformQuotaWindow, kind: PlatformQuotaWindowKind, now: Date, zone: ServerTimeZone) -> String {
        let used = "已用 " + DisplayFormat.money(window.usage)
        guard let limit = window.limit, limit > 0 else { return used }
        if kind == .monthly { return used + " · 30 天滚动" }
        return resetMoment(window.resetsAt, now: now, zone: zone).map { used + " · " + $0 + " 重置" } ?? used
    }
    /// “今天 18:00”, “明天 00:00”, “周一 00:00” within a week, else “11月20日 08:00”, on the server's calendar; a past time is nil.
    public static func resetMoment(_ date: Date?, now: Date, zone: ServerTimeZone) -> String? {
        guard let date, date > now else { return nil }
        let calendar = zone.calendar, time = DisplayFormat.clock(date, timeZone: zone.timeZone)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "今天 " + time
        case 1: return "明天 " + time
        case 2..<7: return weekdayNames[calendar.component(.weekday, from: date) - 1] + " " + time
        default:
            let day = calendar.dateComponents([.month, .day], from: date)
            return "\(day.month ?? 0)月\(day.day ?? 0)日 " + time
        }
    }
    /// 重置该窗口: an existing quota and a window with a limit, 0 included.
    public static func showsReset(_ window: PlatformQuotaWindow, hasQuota: Bool) -> Bool { hasQuota && window.limit != nil }

    // MARK: 平台

    /// AccountNaming's names, so the quota rows say what the accounts and groups say (智谱 GLM, not “Zhipu GLM”).
    public static func platformName(_ platform: String, catalog: MetaCatalog?) -> String { AccountNaming.platformName(platform, catalog: catalog) }
    /// 30 §8.2: the catalog's concrete platforms in its order, minus those with a quota.
    public static func addablePlatforms(catalog: MetaCatalog, existing: [UserPlatformQuota]) -> [String] {
        let taken = Set(existing.map(\.platform))
        return catalog.platforms.map(\.id).filter { $0 != "composite" && !taken.contains($0) }
    }
    /// The server lists rows unordered: catalog order, then platforms the catalog lacks by id.
    public static func ordered(_ quotas: [UserPlatformQuota], catalog: MetaCatalog) -> [UserPlatformQuota] {
        let order = Dictionary(catalog.platforms.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return quotas.sorted { (order[$0.platform] ?? .max, $0.platform) < (order[$1.platform] ?? .max, $1.platform) }
    }
    /// 30 §8.2 有效订阅提示: an active subscription that has not expired.
    public static func hasActiveSubscription(_ subscriptions: [AdminUserSubscription], now: Date) -> Bool {
        subscriptions.contains { $0.status == "active" && ($0.expiresAt.map { $0 > now } ?? true) }
    }

    private static let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    /// A whole limit has no decimals (“$10”), any other two (“$2.50”).
    private static func limitText(_ value: Decimal) -> String {
        DisplayFormat.money(value, digits: DisplayFormat.rounded(value, digits: 0) == value ? 0 : 2)
    }
    /// Design `UeMeter`: caution from 75%, critical from 90%.
    private static func meterTone(_ ratio: Decimal) -> Tone? {
        if ratio >= Decimal(string: "0.9")! { return .critical }
        return ratio >= Decimal(string: "0.75")! ? .caution : nil
    }
}

/// One limit field of the sheet: empty is 不限, a value, or why it cannot be sent.
public enum PlatformQuotaInput: Sendable, Equatable {
    case empty, value(Decimal), invalid(String)

    public init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { self = .empty; return }
        guard let value = PlatformQuotaLimits.parse(trimmed) else { self = .invalid("不是合法数字"); return }
        if value >= PlatformQuotaLimits.ceiling { self = .invalid("限额要小于 100 亿") }
        else if !value.hasAtMostFractionDigits(8) { self = .invalid("最多 8 位小数") }
        else { self = .value(value) }
    }
    /// What typing may leave in the field (design: digits and “.”); a “,” from another keypad becomes “.”.
    public static func sanitized(_ text: String) -> String {
        String(text.replacingOccurrences(of: ",", with: ".").filter { $0.isASCII && ($0.isNumber || $0 == ".") })
    }
    var limit: Decimal? { if case .value(let value) = self { value } else { nil } }
    var isInvalid: Bool { if case .invalid = self { true } else { false } }
}

/// The sheet's three fields against the quota it opened with. “保存” lights only when a window really changes, by value
/// (design `dirty`: “10” and “10.00” are the same).
public struct PlatformQuotaDraft: Sendable, Equatable {
    public let original: PlatformQuotaLimits?
    private let texts: [PlatformQuotaWindowKind: String]

    public init(original: PlatformQuotaLimits?) {
        self.original = original
        texts = Dictionary(uniqueKeysWithValues: PlatformQuotaWindowKind.allCases.map { kind in
            (kind, original?.limit(kind).map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        })
    }
    private init(original: PlatformQuotaLimits?, texts: [PlatformQuotaWindowKind: String]) { self.original = original; self.texts = texts }

    public func text(_ kind: PlatformQuotaWindowKind) -> String { texts[kind] ?? "" }
    public func input(_ kind: PlatformQuotaWindowKind) -> PlatformQuotaInput { PlatformQuotaInput(text(kind)) }
    public func setting(_ kind: PlatformQuotaWindowKind, to text: String) -> PlatformQuotaDraft {
        PlatformQuotaDraft(original: original, texts: texts.merging([kind: text]) { _, new in new })
    }
    /// 清空三个窗口: only the fields; “保存” still sends it.
    public func clearingAll() -> PlatformQuotaDraft { PlatformQuotaDraft(original: original, texts: [:]) }

    public var invalidKinds: [PlatformQuotaWindowKind] { PlatformQuotaWindowKind.allCases.filter { input($0).isInvalid } }
    /// nil while a field is invalid.
    public var limits: PlatformQuotaLimits? {
        guard invalidKinds.isEmpty else { return nil }
        return PlatformQuotaLimits(daily: input(.daily).limit, weekly: input(.weekly).limit, monthly: input(.monthly).limit)
    }
    public var isDirty: Bool {
        PlatformQuotaWindowKind.allCases.contains { kind in input(kind).isInvalid || input(kind).limit != original?.limit(kind) }
    }
    public var canSave: Bool { limits != nil && isDirty }
    /// All three emptied on a platform that has a quota: saving cancels it.
    public var cancelsQuota: Bool { !(original?.isEmpty ?? true) && limits?.isEmpty == true }
    public func showsZeroWarning(_ kind: PlatformQuotaWindowKind) -> Bool { input(kind).limit == 0 }
}

/// What a failed platform quota call means for the section (30 §8.5); the words never echo the server's message (R11).
public enum PlatformQuotaFailure: Sendable, Equatable {
    /// 503: the site has no platform quota service (a GET then answers an empty list; whole-table writes carry no reason).
    case unavailable
    /// 400 INVALID_QUOTA_LIMIT: the local check passed, so only a fixed line at the bottom of the sheet.
    case invalidLimit
    /// 404 USER_NOT_FOUND: back to the list.
    case userGone
    /// 404 USER_PLATFORM_QUOTA_NOT_FOUND: the list is read again.
    case quotaGone
    /// 409 USER_PLATFORM_QUOTA_ACTIVE_EXISTS on restore.
    case activeExists
    /// Lost connection, an unreadable reply, 502 / 504: never resent, read back.
    case unconfirmed
    /// Catalog text (00 §3.3).
    case rejected(String)

    /// nil for a cancelled call or a security prompt the administrator cancelled.
    public init?(_ error: any Error) {
        if error is CancellationError { return nil }
        guard let api = error as? APIError else { self = .rejected(error.localizedDescription); return }
        if api.securityOutcome == .cancelled { return nil }
        switch (api.statusCode, api.reason) {
        case (503?, _): self = .unavailable
        case (_, "INVALID_QUOTA_LIMIT"?): self = .invalidLimit
        case (404?, "USER_NOT_FOUND"?): self = .userGone
        case (404?, "USER_PLATFORM_QUOTA_NOT_FOUND"?): self = .quotaGone
        case (409?, "USER_PLATFORM_QUOTA_ACTIVE_EXISTS"?): self = .activeExists
        case (nil, _) where api.kind == .transport || api == .invalidResponse: self = .unconfirmed
        case (let status?, let reason) where RequestPolicy.isRetryableStatus(status, marker: reason): self = .unconfirmed
        default: self = .rejected(api.localizedDescription)
        }
    }
    public var message: String {
        switch self {
        case .unavailable: "站点没有启用平台限额"
        case .invalidLimit: "限额要大于等于 0、小于 100 亿"
        case .userGone: "用户不存在"
        case .quotaGone: "这个平台的限额已不存在"
        case .activeExists: "已有人重新设置了这个平台的限额，无法恢复"
        case .unconfirmed: "结果未确认，请刷新核对后再操作"
        case .rejected(let text): text
        }
    }
}
