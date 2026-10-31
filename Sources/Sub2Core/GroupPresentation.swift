import Foundation

/// 50 §0.2: a group's four buckets, in the order of the cells, the legend and the breakdown.
public enum GroupBucket: String, CaseIterable, Sendable {
    case available, limited, error, idle
    public var label: String {
        switch self {
        case .available: "可用"
        case .limited: "受限"
        case .error: "错误"
        case .idle: "暂停·停用"
        }
    }
    public var tone: Tone {
        switch self {
        case .available: .ok
        case .limited: .caution
        case .error: .critical
        case .idle: .neutral
        }
    }
}

/// 50 §0.2 / §0.1: F04's counts when the group carries `error_account_count`; otherwise error comes from the
/// `accounts?status=error` fallback and idle is the remainder, both clamped so they never go below 0 or past account_count.
public struct GroupBuckets: Sendable, Equatable {
    public let available: Int
    public let limited: Int
    public let error: Int
    public let idle: Int
    /// `account_count`.
    public let total: Int
    /// F04: the server sent `error_account_count`.
    public let usesServerBuckets: Bool

    public init(_ counts: GroupAccountCounts, fallbackErrors: Int = 0) {
        total = max(0, counts.accountCount); available = max(0, counts.activeAccountCount); limited = max(0, counts.rateLimitedAccountCount)
        let remainder = max(0, total - available - limited)
        if let served = counts.errorAccountCount {
            usesServerBuckets = true; error = max(0, served)
            idle = counts.idleAccountCount.map { max(0, $0) } ?? max(0, remainder - error)
        } else {
            usesServerBuckets = false; error = min(max(0, fallbackErrors), remainder); idle = remainder - error
        }
    }
    public init(group: AdminGroup, fallbackErrors: Int = 0) { self.init(group.counts, fallbackErrors: fallbackErrors) }

    /// The fallback's input is `accounts?status=error&lite=1`: each error account counts once for every group it belongs to.
    public static func errorCounts(accounts: [UpstreamAccount]) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for account in accounts where account.status == "error" {
            for id in Set(account.groupIDs) { counts[id, default: 0] += 1 }
        }
        return counts
    }
    public func count(_ bucket: GroupBucket) -> Int {
        switch bucket {
        case .available: available
        case .limited: limited
        case .error: error
        case .idle: idle
        }
    }
    /// 2.3 右上 “1 个不可用”.
    public var unavailable: Int { max(0, total - available) }
    /// One cell per account.
    public var cellCount: Int { available + limited + error + idle }
    /// 1.3 分档说明 “受限 1 · 错误 1 · 暂停·停用 2”: the non-zero ones; nil when every account is available.
    public var breakdown: String? {
        let parts = [GroupBucket.limited, .error, .idle].filter { count($0) > 0 }.map { "\($0.label) \(DisplayFormat.grouped(count($0)))" }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    public var legend: [GroupLegendItem] { GroupBucket.allCases.map { GroupLegendItem(bucket: $0, count: count($0)) } }
}

/// 0.3 图例: “受限 1”, dimmed at 0.
public struct GroupLegendItem: Sendable, Equatable, Identifiable {
    public let bucket: GroupBucket
    public let count: Int
    public var id: GroupBucket { bucket }
    public var isDimmed: Bool { count == 0 }
    public var text: String { "\(bucket.label) \(DisplayFormat.grouped(count))" }
}

extension GroupAccountCounts {
    /// The buckets of these members by their D02 state: a timed state with scheduling off counts as idle (50 §0.2). Fixtures and
    /// QA use it; an expired auto-pause still inside a window counts as limited here, as D02 does.
    public static func counting(_ members: [AccountDisplayState]) -> GroupAccountCounts {
        let active = members.filter { $0.state == .available }.count
        let limited = members.filter { $0.state.isLimited && !$0.isStopped }.count
        let error = members.filter { $0.state == .error }.count
        return GroupAccountCounts(accountCount: members.count, activeAccountCount: active, rateLimitedAccountCount: limited,
                                  errorAccountCount: error, idleAccountCount: members.count - active - limited - error)
    }
    /// 50 §0.2 D02 → F04: active = available, error = error, rate_limited = the timed states less stopped, idle = paused + inactive + stopped.
    public init(d02 counts: AccountStateCounts) {
        self.init(accountCount: counts.total, activeAccountCount: counts.available, rateLimitedAccountCount: counts.limited - counts.stopped,
                  errorAccountCount: counts.error, idleAccountCount: counts.paused + counts.inactive + counts.stopped)
    }
}

/// 50 §0.2 健康判定, checked in this order. Declaration order is the in-section order none → low → ok → off.
public enum GroupHealth: String, CaseIterable, Sendable, Comparable {
    /// Not `none`, which reads as Optional.none.
    case noAvailable = "none", low, ok, off
    /// The backend's GroupShortageMinRatioDefault, used when D02 has no shortage for the group; the design's 0.6 is a demo rule.
    public static let localShortageRatio = 0.5

    public static func resolve(group: AdminGroup, buckets: GroupBuckets, shortage: AccountStatusGroupSummary.Shortage?) -> GroupHealth {
        if group.status != "active" { return .off }
        if buckets.available == 0 { return .noAvailable }
        let isShort = shortage?.isShort ?? (Double(buckets.available) < Double(buckets.total) * localShortageRatio)
        return isShort ? .low : .ok
    }
    public var tone: Tone {
        switch self {
        case .noAvailable: .critical
        case .low: .caution
        case .ok: .ok
        case .off: .neutral
        }
    }
    /// 1.3 行首图形: octagon, gauge, group, minus.
    public var systemImage: String {
        switch self {
        case .noAvailable: "exclamationmark.octagon"
        case .low: "gauge.with.dots.needle.33percent"
        case .ok: "square.stack.3d.up"
        case .off: "minus.circle"
        }
    }
    public var section: GroupListSection.Kind {
        switch self {
        case .noAvailable, .low: .attention
        case .ok: .normal
        case .off: .off
        }
    }
    /// The list badge; ok has none.
    public func badge(_ buckets: GroupBuckets) -> String? {
        switch self {
        case .noAvailable: buckets.total > 0 ? "无可用账号" : "没有账号"
        case .low: "可用偏低"
        case .ok: nil
        case .off: "已停用"
        }
    }
    /// 2.3 状态卡左上.
    public func cardTitle(_ buckets: GroupBuckets) -> String {
        badge(buckets) ?? (buckets.available == buckets.total ? "全部可用" : "正常")
    }
    public static func < (lhs: GroupHealth, rhs: GroupHealth) -> Bool { lhs.rank < rhs.rank }
    private var rank: Int {
        switch self {
        case .noAvailable: 0
        case .low: 1
        case .ok: 2
        case .off: 3
        }
    }
}

/// 50 §0.3: one cell per account while they fit at the minimum width, otherwise one proportional segment per non-empty bucket.
/// Positions are in points from the leading edge; the page rounds to pixels.
public struct GroupCellsLayout: Sendable, Equatable {
    public struct Cell: Sendable, Equatable, Identifiable {
        public enum Style: Sendable, Equatable {
            case solid
            case outline(lineWidth: Double, opacity: Double)
        }
        public let id: Int
        /// nil for the single cell of a group without members.
        public let bucket: GroupBucket?
        public let x: Double
        public let width: Double
        public let tone: Tone
        public let style: Style
    }
    public static let minimumCellWidth = 3.0
    public let width: Double
    public let height: Double
    public let spacing: Double
    public let cornerRadius: Double
    public let isProportional: Bool
    public let cells: [Cell]
    /// The bar is one element: “可用 x / y”.
    public let accessibilityLabel: String

    public init(_ buckets: GroupBuckets, isActive: Bool, width: Double, height: Double, spacing: Double, cornerRadius: Double) {
        self.width = width; self.height = height; self.spacing = spacing; self.cornerRadius = cornerRadius
        accessibilityLabel = "可用 \(DisplayFormat.grouped(buckets.available)) / \(DisplayFormat.grouped(buckets.total))"
        let count = buckets.cellCount
        guard count > 0 else {
            isProportional = false
            let look: (Tone, Cell.Style) = isActive ? (.critical, .outline(lineWidth: 1, opacity: 0.7)) : (.neutral, Self.offStyle)
            cells = [Cell(id: 0, bucket: nil, x: 0, width: max(0, width), tone: look.0, style: look.1)]
            return
        }
        isProportional = Double(count) * (Self.minimumCellWidth + spacing) > width
        let pieces = isProportional ? Self.segments(buckets, width: width, spacing: spacing) : Self.perAccount(buckets, width: width, spacing: spacing)
        var x = 0.0, built: [Cell] = []
        for (index, piece) in pieces.enumerated() {
            let look = Self.look(piece.bucket, isActive: isActive)
            built.append(Cell(id: index, bucket: piece.bucket, x: x, width: piece.width, tone: look.0, style: look.1))
            x += piece.width + spacing
        }
        cells = built
    }
    /// List row: 96 × 8, 2pt apart.
    public static func list(_ buckets: GroupBuckets, isActive: Bool) -> GroupCellsLayout {
        GroupCellsLayout(buckets, isActive: isActive, width: 96, height: 8, spacing: 2, cornerRadius: 1.5)
    }
    /// Detail status card: full width × 12, 3pt apart.
    public static func detail(_ buckets: GroupBuckets, isActive: Bool, width: Double) -> GroupCellsLayout {
        GroupCellsLayout(buckets, isActive: isActive, width: width, height: 12, spacing: 3, cornerRadius: 2)
    }

    private static let offStyle = Cell.Style.outline(lineWidth: 1.5, opacity: 0.45)
    private static func look(_ bucket: GroupBucket, isActive: Bool) -> (Tone, Cell.Style) {
        guard isActive else { return (.neutral, offStyle) }
        return (bucket.tone, bucket == .idle ? .outline(lineWidth: 1.5, opacity: 0.6) : .solid)
    }
    private static func perAccount(_ buckets: GroupBuckets, width: Double, spacing: Double) -> [(bucket: GroupBucket, width: Double)] {
        let count = buckets.cellCount
        let cell = max(0, (width - spacing * Double(count - 1)) / Double(count))
        return GroupBucket.allCases.flatMap { bucket in Array(repeating: (bucket: bucket, width: cell), count: buckets.count(bucket)) }
    }
    /// Shares by count; a segment under 3pt is pinned at 3pt and the rest shared again. Too narrow for that: equal shares.
    private static func segments(_ buckets: GroupBuckets, width: Double, spacing: Double) -> [(bucket: GroupBucket, width: Double)] {
        let present = GroupBucket.allCases.filter { buckets.count($0) > 0 }
        let counts = present.map { Double(buckets.count($0)) }
        let usable = width - spacing * Double(present.count - 1)
        guard usable >= Double(present.count) * minimumCellWidth else {
            return present.map { (bucket: $0, width: max(0, usable) / Double(present.count)) }
        }
        var pinned = Set<Int>(), widths = counts
        for _ in 0...present.count {
            let free = usable - Double(pinned.count) * minimumCellWidth
            let share = counts.indices.filter { !pinned.contains($0) }.reduce(0) { $0 + counts[$1] }
            widths = counts.indices.map { pinned.contains($0) ? minimumCellWidth : free * counts[$0] / share }
            let short = counts.indices.filter { !pinned.contains($0) && widths[$0] < minimumCellWidth }
            if short.isEmpty { break }
            pinned.formUnion(short)
        }
        return zip(present, widths).map { (bucket: $0.0, width: $0.1) }
    }
}

/// One list row (50 §1.3): the group with its buckets and health.
public struct GroupListRow: Sendable, Equatable, Identifiable {
    public let group: AdminGroup
    public let buckets: GroupBuckets
    public let health: GroupHealth
    public var id: Int { group.id }
    public var badge: String? { health.badge(buckets) }
    /// 停用行 is-idle.
    public var isDimmed: Bool { health == .off }
    /// `fallbackErrors` only counts without F04; `shortage` is D02's for the group, nil for the local half rule.
    public init(group: AdminGroup, fallbackErrors: Int = 0, shortage: AccountStatusGroupSummary.Shortage? = nil) {
        self.group = group
        buckets = GroupBuckets(group: group, fallbackErrors: fallbackErrors)
        health = GroupHealth.resolve(group: group, buckets: buckets, shortage: shortage)
    }
}

public struct GroupListSection: Sendable, Equatable, Identifiable {
    /// Raw values match the route's GroupListSegment (attention / normal / off).
    public enum Kind: String, CaseIterable, Sendable {
        case attention, normal, off
        public var title: String {
            switch self {
            case .attention: "需处理"
            case .normal: "正常"
            case .off: "停用"
            }
        }
    }
    public let kind: Kind
    public let rows: [GroupListRow]
    public var id: Kind { kind }
    /// “需处理 3”.
    public var header: String { "\(kind.title) \(DisplayFormat.grouped(rows.count))" }
}

/// 50 §1.3–§1.5: sections, order, local search and the words around the list.
public enum GroupListSections {
    public static let searchPrompt = "分组名称或平台"
    public static let noMatches = "没有匹配的分组"
    public static let empty = "还没有分组"
    public static let footnote = "左滑编辑或停用，右滑添加账号；长按看全部操作。今日按 Key 所属分组统计。"

    /// `fallbackErrors` is GroupBuckets.errorCounts without groups.account_buckets (empty with it); `shortages` are D02's
    /// groups[].shortage by group id (empty when D02 is unavailable: the local rule decides).
    public static func rows(_ groups: [AdminGroup], fallbackErrors: [Int: Int] = [:],
                            shortages: [Int: AccountStatusGroupSummary.Shortage] = [:]) -> [GroupListRow] {
        groups.map { GroupListRow(group: $0, fallbackErrors: fallbackErrors[$0.id] ?? 0, shortage: shortages[$0.id]) }
    }
    /// Filtered, then split in Kind order; an empty section is left out.
    public static func sections(_ rows: [GroupListRow], query: String = "", catalog: MetaCatalog? = nil) -> [GroupListSection] {
        let shown = rows.filter { matches($0.group, query: query, catalog: catalog) }.sorted(by: ordered)
        return GroupListSection.Kind.allCases.compactMap { kind in
            let members = shown.filter { $0.health.section == kind }
            return members.isEmpty ? nil : GroupListSection(kind: kind, rows: members)
        }
    }
    /// The name or the platform's Chinese name, each on its own, ignoring case and surrounding spaces.
    public static func matches(_ group: AdminGroup, query: String, catalog: MetaCatalog? = nil) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [group.name, GroupFormat.platformName(group.platform, catalog: catalog)].contains { $0.range(of: needle, options: .caseInsensitive) != nil }
    }
    /// Health, then the available share ascending (a group without accounts as 0), then sort_order (missing as 0), then id.
    public static func ordered(_ lhs: GroupListRow, _ rhs: GroupListRow) -> Bool {
        if lhs.health != rhs.health { return lhs.health < rhs.health }
        let left = lhs.buckets.total == 0 ? 0 : lhs.buckets.available * max(rhs.buckets.total, 1)
        let right = rhs.buckets.total == 0 ? 0 : rhs.buckets.available * max(lhs.buckets.total, 1)
        if left != right { return left < right }
        return (lhs.group.sortOrder ?? 0, lhs.id) < (rhs.group.sortOrder ?? 0, rhs.id)
    }
    /// “<站点名> · k 个分组无可用账号”, or “<站点名> · n 个分组” when k is 0; counted before any search.
    public static func subtitle(siteName: String, rows: [GroupListRow]) -> String {
        let none = rows.filter { $0.health == .noAvailable }.count
        return siteName + " · " + (none > 0 ? "\(DisplayFormat.grouped(none)) 个分组无可用账号" : "\(DisplayFormat.grouped(rows.count)) 个分组")
    }
}

/// 50 §0.6, built only from DisplayFormat (R10).
public enum GroupFormat {
    public enum BillingStyle: Sendable { case long, short }

    /// “×0.8”, “×1.0”, “×1.25”: one digit when the value is exact to 0.1, otherwise two.
    public static func rateText(_ value: Decimal?) -> String {
        guard let value else { return DisplayFormat.missing }
        return "×" + DisplayFormat.decimal(NSDecimalNumber(decimal: value).doubleValue, minFractionDigits: 1, maxFractionDigits: 2)
    }
    public static func billingText(_ subscriptionType: String?, style: BillingStyle = .long) -> String {
        guard let type = subscriptionType, !type.isEmpty else { return DisplayFormat.missing }
        switch type {
        case "standard": return style == .long ? "标准（余额）" : "标准计费"
        case "subscription": return style == .long ? "订阅（配额）" : "订阅计费"
        default: return type
        }
    }
    public static func rpmText(_ limit: Int?) -> String {
        guard let limit else { return DisplayFormat.missing }
        return limit == 0 ? "不限" : DisplayFormat.grouped(limit)
    }
    /// null is unlimited; 0 is a real $0 limit (normalizeLimit). Whole dollars without cents; a typed fraction keeps two digits.
    public static func limitText(_ value: Decimal?) -> String {
        guard let value else { return "无限制" }
        return DisplayFormat.money(value, digits: DisplayFormat.rounded(value, digits: 0) == value ? 0 : 2)
    }
    public static func exclusiveText(_ isExclusive: Bool?) -> String {
        isExclusive.map { $0 ? "专属" : "公开" } ?? DisplayFormat.missing
    }
    public static func statusText(_ status: String) -> String {
        switch status {
        case "active": "正常"
        case "inactive": "停用"
        default: status
        }
    }
    public static func platformName(_ platform: String, catalog: MetaCatalog? = nil) -> String {
        AccountNaming.platformName(platform, catalog: catalog)
    }
    public static func clientText(_ claudeCodeOnly: Bool?) -> String {
        claudeCodeOnly.map { $0 ? "仅限 Claude Code" : "所有客户端" } ?? DisplayFormat.missing
    }
    /// 2.3 降级分组: only for a Claude Code only group; `fallbackName` is the fallback's name in the group directory.
    public static func fallbackText(_ group: AdminGroup, fallbackName: String?) -> String {
        guard group.claudeCodeOnly == true else { return DisplayFormat.missing }
        guard let id = group.fallbackGroupID else { return "直接拒绝" }
        return fallbackName ?? "分组 #\(id)"
    }
    /// “Anthropic · 标准（余额） · 公开”; simple mode only names the platform, and a field the reply left out is skipped.
    public static func detailSubtitle(_ group: AdminGroup, isSimpleMode: Bool, catalog: MetaCatalog? = nil) -> String {
        let platform = platformName(group.platform, catalog: catalog)
        guard !isSimpleMode else { return platform }
        let billing = group.subscriptionType.map { billingText($0) }, exclusive = group.isExclusive.map { exclusiveText($0) }
        return [platform, billing, exclusive].compactMap { $0 }.joined(separator: " · ")
    }
    /// 1.3 第三行左 “费率倍数 ×0.8 · 标准计费”.
    public static func billingLine(_ group: AdminGroup) -> String {
        "费率倍数 \(rateText(group.rateMultiplier)) · \(billingText(group.subscriptionType, style: .short))"
    }
    /// “可用 2/3”.
    public static func availability(_ buckets: GroupBuckets) -> String {
        "可用 \(DisplayFormat.grouped(buckets.available))/\(DisplayFormat.grouped(buckets.total))"
    }
    /// The list's “今日” and the detail's 今日 column come from here (50 §9).
    public static func todayValue(_ summary: GroupUsageSummary?) -> String { DisplayFormat.money(summary?.todayCost) }
    public static func todayText(_ summary: GroupUsageSummary?) -> String { "今日 " + todayValue(summary) }
    /// 2.3 肆 · 配置 without the Web row: the description only when not blank, the three limits only for a subscription group.
    public static func configRows(_ group: AdminGroup, fallbackName: String?) -> [GroupConfigRow] {
        var rows = [
            GroupConfigRow(kind: .rate, value: rateText(group.rateMultiplier)), GroupConfigRow(kind: .billing, value: billingText(group.subscriptionType)),
            GroupConfigRow(kind: .rpm, value: rpmText(group.rpmLimit)), GroupConfigRow(kind: .exclusive, value: exclusiveText(group.isExclusive)),
            GroupConfigRow(kind: .client, value: clientText(group.claudeCodeOnly)), GroupConfigRow(kind: .fallback, value: fallbackText(group, fallbackName: fallbackName))
        ]
        let description = (group.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty { rows.append(GroupConfigRow(kind: .description, value: description)) }
        if group.subscriptionType == "subscription" {
            rows += [GroupConfigRow(kind: .dailyLimit, value: limitText(group.dailyLimitUSD)), GroupConfigRow(kind: .weeklyLimit, value: limitText(group.weeklyLimitUSD)),
                     GroupConfigRow(kind: .monthlyLimit, value: limitText(group.monthlyLimitUSD))]
        }
        return rows
    }
}

public struct GroupConfigRow: Sendable, Equatable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable {
        case rate, billing, rpm, exclusive, client, fallback, description, dailyLimit, weeklyLimit, monthlyLimit
        public var title: String {
            switch self {
            case .rate: "费率倍数"
            case .billing: "计费类型"
            case .rpm: "每用户 RPM"
            case .exclusive: "类型"
            case .client: "客户端"
            case .fallback: "降级分组"
            case .description: "描述"
            case .dailyLimit: "每日"
            case .weeklyLimit: "每周"
            case .monthlyLimit: "每月"
            }
        }
    }
    public let kind: Kind
    public let value: String
    public var id: Kind { kind }
    public var title: String { kind.title }
    /// Tapping opens the editor; the page still asks GroupPermissions.canEdit.
    public var opensEditor: Bool { kind == .rate || kind == .rpm || kind == .exclusive }
}

/// Group rules that are neither a format nor a word list. S5-12 adds its own extension in GroupRecordsPresentation.swift.
public enum GroupPresentation {
    /// 50 §3.3 / §3.4 “保存后可用 x”: members whose state is available now and that the group schedules (its platform; a
    /// composite group takes every platform).
    public static func availableAfter(members: [UpstreamAccount], platform: String, now: Date) -> Int {
        members.filter { member in
            (platform == "composite" || member.platform == platform) && AccountDisplayState(member, now: now).state == .available
        }.count
    }
}
