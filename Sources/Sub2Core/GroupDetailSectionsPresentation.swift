import Foundation

// 50 §2 分组详情 (S5-07): the alert banner above the status card, then 贰 · 用量与容量, 叁 · 记录与关联 and 肆 · 配置 after the
// members. The words GroupCopy and GroupFormat already have are called from there.

/// 50 §2.2 / §2.3 叁: a 24-hour count. 404 OPS_DISABLED is a value, not a failure: “运维监控未开启”, and the row still opens the logs.
public enum GroupLogCount: Equatable, Sendable {
    case count(Int)
    case opsDisabled

    /// 404 with reason OPS_DISABLED; the App's one test of it (AccountUpstreamErrors).
    public static func isOpsDisabled(_ error: any Error) -> Bool { AccountUpstreamErrors.isOpsDisabled(error) }
}

/// 50 §2.6 for the five blocks of this part of the page.
public enum GroupDetailSectionReads {
    public static let blocks: Set<GroupDetailBlock> = [.capacity, .usage, .todayUsage, .alert, .errorCounts]

    /// GroupDetailRefreshPlan's blocks for `trigger` that belong here. Without usage and capacity (simple mode, 403) the
    /// usage-summary and capacity reads stay out; dashboard/groups still goes. Only the 60-second refresh skips a block still
    /// backing off (`due`, 00 §4.6) and the banner while the session knows ops monitoring is off.
    public static func reads(for trigger: GroupDetailTrigger, showsUsageAndCapacity: Bool, opsKnownDisabled: Bool,
                             due: [GroupDetailBlock: Date] = [:], unread: Set<GroupDetailBlock> = [], now: Date) -> Set<GroupDetailBlock> {
        var reads = GroupDetailRefreshPlan.blocks(for: trigger, unread: unread).intersection(blocks)
        if !showsUsageAndCapacity { reads.subtract([.usage, .capacity]) }
        guard trigger == .poll else { return reads }
        if opsKnownDisabled { reads.remove(.alert) }
        return reads.filter { block in due[block].map { $0 <= now } ?? true }
    }
    /// 50 §2.2: only entering takes the list's usage-summary of the last 60 seconds; every other read asks again.
    public static func reusesListUsage(_ trigger: GroupDetailTrigger) -> Bool { trigger == .enter }
}

/// 50 §2.3 告警横幅 above the status card.
public struct GroupAlertBannerContent: Equatable, Sendable {
    public static let openTitle = "查看"
    public static let systemImage = "bell.fill"
    public let eventID: Int
    public let tone: Tone
    /// “P1 告警中 · 标准组错误率 5.2%”.
    public let title: String
    /// The rule's summary and the firing time (“错误率 > 5.0%（5 分钟） · 09:29 起”); without a rule only the time.
    public let detail: String?

    /// nil without an event or for one that is not firing.
    public init?(_ event: AlertEvent?, now: Date, timeZone: ServerTimeZone, latencyMetricsSupported: Bool) {
        guard let event, let tone = AlertPresentation.tone(event) else { return nil }
        eventID = event.id
        self.tone = tone
        let status = [event.severity.trimmingCharacters(in: .whitespacesAndNewlines), AlertPresentation.statusWord(event.status)]
        title = status.filter { !$0.isEmpty }.joined(separator: " ") + " · " + AlertPresentation.title(event)
        let rule = Self.hasRule(event) ? AlertPresentation.ruleText(event, latencyMetricsSupported: latencyMetricsSupported) : nil
        let parts = [rule, Self.firedText(event.firedAt, now: now, timeZone: timeZone)].compactMap { $0 }
        detail = parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The last event read, kept through a failed refresh (S5D2a-15); a first read that failed shows nothing. OPS_DISABLED leaves
    /// at once (2.5): the reader turns it into a nil event, and once the session knows ops monitoring is off (another page read
    /// it; the 60-second refresh then skips the banner) the event read before is no longer shown.
    public static func shownEvent(_ state: BlockState<AlertEvent?>, opsKnownDisabled: Bool) -> AlertEvent? {
        opsKnownDisabled ? nil : state.value ?? nil
    }
    /// HH:mm on the server's today, otherwise MM/dd HH:mm (another year yyyy/MM/dd HH:mm), then “ 起” (S5D2a-14).
    public static func firedText(_ firedAt: Date?, now: Date, timeZone: ServerTimeZone) -> String? {
        guard let firedAt else { return nil }
        let sameDay = timeZone.calendar.isDate(firedAt, inSameDayAs: now)
        let time = sameDay ? DisplayFormat.clock(firedAt, timeZone: timeZone.timeZone) : DisplayFormat.monthDayClock(firedAt, timeZone: timeZone, now: now)
        return time + " 起"
    }
    /// A rule with an operator; ruleText would otherwise fall back to the server's English description.
    private static func hasRule(_ event: AlertEvent) -> Bool {
        guard let rule = event.rule else { return false }
        return !rule.comparison.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// 贰's first row: usage-summary's today, yesterday and total. 今日 is the list's own figure (50 §9).
public struct GroupUsageFigures: Equatable, Sendable {
    public static let title = "用量与容量"
    public static let ordinal = ChineseOrdinal.text(2)
    public static let meta = "按 Key 所属分组 · 00:00 切分"
    public static let todayTitle = "今日"
    public static let yesterdayTitle = "昨日"
    public static let totalTitle = "累计 · 全部时间"
    public let today: String
    public let yesterday: String
    public let total: String

    public init(_ summary: GroupUsageSummary?) {
        today = GroupFormat.todayValue(summary)
        yesterday = DisplayFormat.money(summary?.yesterdayCost)
        total = DisplayFormat.money(summary?.totalCost)
    }
}

/// 贰's second row: dashboard/groups' requests, total_tokens and account_cost (never `cost`); a first read that failed is one “—”.
public enum GroupTodayLine: Equatable, Sendable {
    case figures(requests: String, tokens: String, accountCost: String)
    case missing

    public static let label = "今日用量"
    public static let requestsTitle = "请求"
    public static let tokensTitle = "Tokens"
    public static let accountCostTitle = "账号成本"

    public init(_ usage: GroupTodayUsage?) {
        guard let usage else { self = .missing; return }
        self = .figures(requests: DisplayFormat.grouped(usage.requests), tokens: DisplayFormat.compact(usage.totalTokens),
                        accountCost: DisplayFormat.money(usage.accountCost))
    }
    /// “请求 10,194，Tokens 62.9M，账号成本 $370.27”.
    public var spoken: String {
        guard case .figures(let requests, let tokens, let cost) = self else { return DisplayFormat.missingSpoken }
        return [(Self.requestsTitle, requests), (Self.tokensTitle, tokens), (Self.accountCostTitle, cost)]
            .map { "\($0.0) \(DisplayFormat.spoken($0.1))" }.joined(separator: "，")
    }
}

/// 贰's capacity lines: only a positive ceiling draws one, in the order 并发 · 会话 · 调度 RPM (50 §2.3, design gvCaps).
public enum GroupCapacityDisplay: Equatable, Sendable {
    /// The first read is out.
    case placeholder
    case rows([CapacityRow])
    /// “容量 —” with why; a first read that failed has no note.
    case empty(note: String?)

    public static let title = "容量"

    public static func rows(_ summary: GroupCapacitySummary?) -> [CapacityRow] {
        guard let summary else { return [] }
        let lines = [("concurrency", "并发", summary.concurrencyUsed, summary.concurrencyMax), ("sessions", "会话", summary.sessionsUsed, summary.sessionsMax),
                     ("rpm", "调度 RPM", summary.rpmUsed, summary.rpmMax)]
        return lines.compactMap { id, title, used, limit in
            guard let limit, limit > 0 else { return nil }
            return CapacityRow.count(id: id, title: title, used: used, limit: limit)
        }
    }
    /// A value (kept through a failed refresh) draws its lines, or the note when it has none (a stopped group's empty reply too).
    public static func make(_ state: BlockState<GroupCapacitySummary?>, group: AdminGroup, buckets: GroupBuckets) -> GroupCapacityDisplay {
        switch state.display {
        case .placeholder: return .placeholder
        case .value(let summary, _, _, _):
            let lines = rows(summary)
            return lines.isEmpty ? .empty(note: GroupCopy.capacityEmptyNote(group: group, buckets: buckets)) : .rows(lines)
        case .failed, .disabled: return .empty(note: nil)
        }
    }
}

/// S5-高-3: a block whose last refresh failed while its earlier value still shows says so, as the group list does
/// (GroupStoreRules.isStale(_:refresh:)): also while it is read again and after a read the page cancelled, until a read works. A
/// first read that failed stays as it was (“—”, no banner), and a refresh of a block that never failed shows nothing.
public enum GroupDetailSectionsPresentation {
    /// The caution strip under a banner kept through a failed refresh (U-11's own wording).
    public static let alertStaleTitle = "告警更新失败 · 重试"

    /// 贰 has one accessory for its three blocks: the first of usage-summary, dashboard/groups and capacity that is stale.
    public static func staleBlock<Usage, Today, Capacity>(usage: (BlockState<Usage>, BlockRefresh), today: (BlockState<Today>, BlockRefresh),
                                                          capacity: (BlockState<Capacity>, BlockRefresh)) -> GroupDetailBlock? {
        if GroupStoreRules.isStale(usage.0, refresh: usage.1) { return .usage }
        if GroupStoreRules.isStale(today.0, refresh: today.1) { return .todayUsage }
        if GroupStoreRules.isStale(capacity.0, refresh: capacity.1) { return .capacity }
        return nil
    }
    /// What BlockStatusAccessory draws for the stale block: a read the page cancelled went back to the kept value
    /// (BlockState.withCancelledLoad), which still says 更新失败.
    public static func accessoryState<Value>(_ state: BlockState<Value>, refresh: BlockRefresh) -> BlockState<Value> {
        guard case .loaded(let value, let at) = state, refresh.consecutiveFailures > 0 else { return state }
        return .failed(reason: BlockStatusPresentation.loadFailed, previous: value, at: at)
    }
    /// 00 §2.7.2 / S1D1-20: a block the 60-second refresh reads is left to it after a 429 wait; the others read again by themselves.
    public static func resendsAfterWait(_ block: GroupDetailBlock) -> Bool { !GroupDetailRefreshPlan.blocks(for: .poll).contains(block) }
    /// The banner shows an event from an earlier read, since the last one failed.
    public static func alertIsStale(_ state: BlockState<AlertEvent?>, refresh: BlockRefresh) -> Bool {
        GroupStoreRules.isStale(state, refresh: refresh) && state.value.flatMap { $0 } != nil
    }
    /// The strip as the group list's (GroupStoreRules.staleStatus): the banner read again now, then its 429 wait (the 60-second
    /// refresh reads after it), then 更新失败. Only `.updateFailed` takes a tap.
    public static func alertStripStatus(_ state: BlockState<AlertEvent?>, refresh: BlockRefresh, at now: Date) -> BlockStatusPresentation.Accessory {
        GroupStoreRules.staleStatus(refreshing: state.isLoading, waits: [refresh], at: now)
    }
    /// “请求过于频繁，N 秒后自动重试” during the wait, otherwise `alertStaleTitle`.
    public static func alertStripTitle(_ status: BlockStatusPresentation.Accessory) -> String {
        if case .throttled(let message) = status { return message }
        return alertStaleTitle
    }
}

/// 叁's rows in page order; the subscription row is only for a subscription group.
public enum GroupRecordRow: String, CaseIterable, Sendable {
    case errors, upstream, usage, keys, subscriptions
    public var title: String {
        switch self {
        case .errors: "错误请求"
        case .upstream: "上游错误"
        case .usage: "使用记录"
        case .keys: "API 密钥"
        case .subscriptions: "订阅"
        }
    }
    public var systemImage: String {
        switch self {
        case .errors: "exclamationmark.octagon"
        case .upstream: "waveform.path.ecg"
        case .usage: "list.bullet"
        case .keys: "key"
        case .subscriptions: "checkmark.seal"
        }
    }
}

/// 叁's right-hand words. While a first read is out there is none (no flashing “—”); while the session knows ops monitoring is
/// off the two counts say so whatever was read before (2.5).
public enum GroupRecordValues {
    public static let title = "记录与关联"
    public static let ordinal = ChineseOrdinal.text(3)

    public static func logCount(_ state: BlockState<GroupLogCount>, opsKnownDisabled: Bool) -> String? {
        guard !opsKnownDisabled else { return GroupCopy.opsDisabled }
        return switch state.display {
        case .placeholder: nil
        case .value(.count(let count), _, _, _): GroupCopy.last24Hours(count)
        case .value(.opsDisabled, _, _, _): GroupCopy.opsDisabled
        case .failed, .disabled: DisplayFormat.missing
        }
    }
    public static func apiKeys(_ state: BlockState<GroupKeyCounts>) -> String? {
        keyCount(state) { GroupCopy.apiKeysValue($0.totalAPIKeys) }
    }
    public static func activeSubscriptions(_ state: BlockState<GroupKeyCounts>) -> String? {
        keyCount(state) { GroupCopy.activeSubscriptionsValue($0.subscriptionsActive) }
    }
    public static func showsSubscriptions(_ group: AdminGroup) -> Bool { group.subscriptionType == "subscription" }

    private static func keyCount(_ state: BlockState<GroupKeyCounts>, _ text: (GroupKeyCounts) -> String) -> String? {
        switch state.display {
        case .placeholder: nil
        case .value(let counts, _, _, _): text(counts)
        case .failed, .disabled: DisplayFormat.missing
        }
    }
}

/// 肆 · 配置 without the Web row.
public enum GroupConfigDisplay {
    public static let title = "配置"
    public static let ordinal = ChineseOrdinal.text(4)
    public static let limitsTitle = "订阅限额 · 每个订阅"
    /// Shown together as one row of three under `limitsTitle`.
    public static let limitKinds: Set<GroupConfigRow.Kind> = [.dailyLimit, .weeklyLimit, .monthlyLimit]

    /// GroupFormat.configRows; simple mode's replies carry none of the billing fields, so only the description is left.
    public static func rows(_ group: AdminGroup, fallbackName: String?, showsBilling: Bool) -> [GroupConfigRow] {
        let rows = GroupFormat.configRows(group, fallbackName: fallbackName)
        return showsBilling ? rows : rows.filter { $0.kind == .description }
    }
    /// “每日 $20，每周 $100，每月 无限制”.
    public static func limitsSpoken(_ rows: [GroupConfigRow]) -> String {
        rows.filter { limitKinds.contains($0.kind) }.map { "\($0.title) \($0.value)" }.joined(separator: "，")
    }
}

/// 肆's last row (50 §2.1): `<站点>/admin/groups` in the browser (Web route frontend/src/router/index.ts:473).
public enum GroupWebLink {
    public static let title = "模型白名单、组合路由、图片计费"
    public static let subtitle = "在 Web 中编辑"
    public static let openedReceipt = "已打开 Web 分组管理"

    public static func url(siteRoot: URL) -> URL? {
        let root = siteRoot.absoluteString
        return URL(string: (root.hasSuffix("/") ? String(root.dropLast()) : root) + "/admin/groups")
    }
}
