import Foundation

/// One row of the 分组 picker (20 §3.3): the badges in design order and the line under the name.
public struct AccountGroupChoice: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    /// 停用 / 组合 or the other platform's name / 订阅 / 专属.
    public let badges: [String]
    public let detail: String?
    public let isInactive: Bool
}

/// 20 §3.3 分组选择器, over GroupDirectory (`groups/all?include_inactive=true`, X11).
public enum AccountGroupChoices {
    private static let mixedPlatforms: Set<String> = ["anthropic", "antigravity"]

    /// Lower-cased: the account's platform and composite; Antigravity with `extra.mixed_scheduling` also takes Anthropic and Gemini.
    public static func platforms(for account: UpstreamAccount) -> Set<String> {
        let own = account.platform.lowercased()
        var platforms: Set<String> = [own, "composite"]
        if own == "antigravity", isMixedScheduling(account) { platforms.formUnion(["anthropic", "gemini"]) }
        return platforms
    }
    /// Active groups of those platforms in sort_order, plus every group in `current` (stopped or of another platform, so it can
    /// be taken out). A current id the directory lacks comes last, named from the account or “#id”.
    public static func choices(groups: [AdminGroup], account: UpstreamAccount, current: Set<Int>,
                               platformName: (String) -> String) -> [AccountGroupChoice] {
        let allowed = platforms(for: account)
        let listed = groups.filter { (isActive($0) && allowed.contains($0.platform.lowercased())) || current.contains($0.id) }
            .sorted(by: AdminGroup.displayOrder)
            .map { choice($0, account: account, platformName: platformName) }
        let known = Set(groups.map(\.id))
        let missing = current.subtracting(known).sorted().map { id in
            AccountGroupChoice(id: id, name: account.groups.first { $0.id == id }?.name ?? "#\(id)", badges: [], detail: nil, isInactive: false)
        }
        return listed + missing
    }
    public static func header(account: UpstreamAccount, platformName: (String) -> String) -> String {
        if account.platform.lowercased() == "antigravity", isMixedScheduling(account) {
            return "已开启“在 /v1/messages 中使用”：列出 Antigravity、Anthropic、Gemini 分组和组合分组 · 可多选"
        }
        return "只列出 \(platformName(account.platform)) 分组和组合分组 · 可多选"
    }
    public static func emptyText(account: UpstreamAccount, platformName: (String) -> String) -> String {
        "没有可加入的 \(platformName(account.platform)) 分组"
    }
    /// Shown when every listed group is stopped.
    public static func noActiveText(account: UpstreamAccount, platformName: (String) -> String) -> String {
        "没有启用的 \(platformName(account.platform)) 分组可加入；在“分组”里启用或新建后再来。"
    }
    /// Anthropic and Antigravity accounts only: the server checks their mix when groups are saved.
    public static func mixedChannelNote(account: UpstreamAccount) -> String? {
        mixedPlatforms.contains(account.platform.lowercased()) ? "Anthropic 与 Antigravity 账号进同一分组时，保存会先提示混合渠道风险" : nil
    }

    private static func choice(_ group: AdminGroup, account: UpstreamAccount, platformName: (String) -> String) -> AccountGroupChoice {
        let inactive = !isActive(group)
        var badges: [String] = inactive ? ["停用"] : []
        let platform = group.platform.lowercased()
        if platform == "composite" { badges.append("组合") }
        else if platform != account.platform.lowercased() { badges.append(platformName(group.platform)) }
        if group.subscriptionType == "subscription" { badges.append("订阅") }
        if group.isExclusive == true { badges.append("专属") }
        let total = group.accountCount ?? 0, available = group.activeAccountCount ?? 0
        let detail = inactive ? "分组已停用，不接收请求 · 可以移出"
            : "倍率 \(AccountEditCopy.rate(group.rateMultiplier)) · " + (total > 0 ? "可用 \(available)/\(total)" : "还没有账号")
        return AccountGroupChoice(id: group.id, name: group.name, badges: badges, detail: detail, isInactive: inactive)
    }
    private static func isActive(_ group: AdminGroup) -> Bool { group.status == "active" }
    private static func isMixedScheduling(_ account: UpstreamAccount) -> Bool { account.extra?["mixed_scheduling"]?.boolValue == true }
}

/// 20 §3.3 过期时间 in the phone's time zone (U53): Web's presets, the text, the “must lie ahead” rule and the zone note.
public enum AccountExpiry {
    public enum Preset: Int, CaseIterable, Sendable {
        case oneMonth = 1, oneYear = 12
        public var title: String { self == .oneMonth ? "1 个月后" : "1 年后" }
    }
    public static let never = "不过期"
    public static let custom = "自定义日期和时间…"
    public static let keepCurrent = "保持当前"
    public static let pickerTitle = "过期时间"

    /// Web getAccountExpiryTimestamp: `months` calendar months on `calendar` (the phone's zone), the day clamped to the target
    /// month's last, the time of day kept, seconds rounded down. `now` is the site's ServerClock time (20 §0.6).
    public static func seconds(adding months: Int, to now: Date, calendar: Calendar) -> Int64 {
        let target = calendar.date(byAdding: .month, value: months, to: now) ?? now
        return seconds(of: target)
    }
    public static func seconds(of date: Date) -> Int64 { Int64(date.timeIntervalSince1970.rounded(.down)) }
    public static func date(_ seconds: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }
    /// The Gregorian calendar of `timeZone`, for the presets.
    public static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX"); calendar.timeZone = timeZone
        return calendar
    }
    /// yyyy-MM-dd HH:mm with ASCII digits; nil, 0 and negatives are 不过期.
    public static func text(_ seconds: Int64?, timeZone: TimeZone) -> String {
        guard let seconds, seconds > 0 else { return never }
        let formatter = DateFormatter()
        formatter.calendar = calendar(timeZone); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date(seconds))
    }
    public static func isFuture(_ seconds: Int64, now: Date) -> Bool { TimeInterval(seconds) > now.timeIntervalSince1970 }
    /// The custom page's button: 到期时间 yyyy-MM-dd HH:mm.
    public static func confirmTitle(_ seconds: Int64, timeZone: TimeZone) -> String { "到期时间 " + text(seconds, timeZone: timeZone) }
    /// U53: only when the phone and the site keep different offsets.
    public static func timeZoneNote(device: TimeZone, server: ServerTimeZone, at date: Date) -> String? {
        server.differsFromDevice(device, at: date) ? "按本机时区 \(device.identifier)" : nil
    }
}
