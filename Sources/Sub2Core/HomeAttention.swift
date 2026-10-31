import Foundation

/// Where an overview row or cell leads. Sub2Core cannot see the App's routes; the App maps each case to an AppRoute,
/// TabIntent or AppSheet (S1-10 `HomeDestinationAction`).
public enum HomeDestination: Hashable, Sendable {
    case analytics
    case performanceTrend(HomeRateMetric)
    case alert(id: Int)
    case alertsSegment
    case account(id: Int)
    case accountTest(id: Int)
    case limitedAccounts
    case group(id: Int)
    case groupsAttention
    case user(id: Int)
    case redeemReconcile
    case compensation(userID: Int, pendingID: UUID)
    case retryAvailability
    case retryAlerts
}

public enum AttentionKind: Hashable, Sendable {
    case alert, moreAlerts, errorAccount, overloadedAccount, limitedAccounts, groupShortage
    case pendingBalance, pendingRedeemBatch, pendingCompensation, alertsFailed, availabilityFailed
}

/// Text that may tick: a countdown is rebuilt from its absolute target on every redraw (00 §6.2).
public enum AttentionText: Hashable, Sendable {
    case plain(String)
    case countdown(prefix: String, until: Date)
    /// A countdown past its target reads 0:00.
    public func text(now: Date) -> String {
        switch self {
        case .plain(let text): text
        case .countdown(let prefix, let until): prefix + DisplayFormat.countdown(until: until, now: now)
        }
    }
}

/// One 待处理 row (10 §1.3.3). `id` is stable across refreshes: alert-<id>, alerts-more, account-<id>, limited, groups,
/// pending-<record uuid>, retry-alerts, retry-availability.
public struct AttentionItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: AttentionKind
    public let tone: Tone
    public let systemImage: String
    public let title: String
    public let badge: AttentionText?
    public let detail: String?
    /// “已停止调度” ahead of an overloaded row's detail.
    public let detailMark: String?
    /// An error row's bottom line: "OpenAI · 1 分钟前".
    public let footnote: String?
    public let trailing: AttentionText?
    public let countdownTarget: Date?
    /// The limited row's third line: stopped accounts' names, shown after `AccountDisplayState.stoppedMark` + " · ".
    public let stoppedNames: String?
    public let destination: HomeDestination
    /// An error row's 「测试」.
    public let action: HomeDestination?

    init(id: String, kind: AttentionKind, tone: Tone, systemImage: String, title: String, badge: AttentionText? = nil, detail: String? = nil,
         detailMark: String? = nil, footnote: String? = nil, trailing: AttentionText? = nil, countdownTarget: Date? = nil,
         stoppedNames: String? = nil, destination: HomeDestination, action: HomeDestination? = nil) {
        self.id = id; self.kind = kind; self.tone = tone; self.systemImage = systemImage; self.title = title; self.badge = badge
        self.detail = detail; self.detailMark = detailMark; self.footnote = footnote; self.trailing = trailing
        self.countdownTarget = countdownTarget; self.stoppedNames = stoppedNames; self.destination = destination; self.action = action
    }

    public func badgeText(now: Date) -> String? { badge?.text(now: now) }
    public func trailingText(now: Date) -> String? { trailing?.text(now: now) }
    /// The view asks for one refresh when a countdown reaches zero (10 §1.6).
    public func countdownElapsed(at now: Date) -> Bool { countdownTarget.map { $0 <= now } ?? false }
}

extension HomePresentation {
    /// The words alone, for BlockFailureRow, which adds its own “ · 重试” (S1-10).
    public static let alertsFailedText = "告警读取失败"
    public static let availabilityFailedText = "账号状态读取失败"
    public static let alertsFailedTitle = alertsFailedText + " · " + BlockStatusPresentation.retryTitle
    public static let availabilityFailedTitle = availabilityFailedText + " · " + BlockStatusPresentation.retryTitle
    /// X34: a money row whose record an earlier login of this site's address sent ends with this (S1-18 reads the same).
    public static var previousLoginNote: String { MoneyRecordOrigin.oldLoginNote }
    /// U06: the server lists at most five; a fallback that lists more shows the five most severe and counts the rest.
    static let maxAlertRows = 5

    /// 10 §1.3.3 with R02's compensation slot: alerts → error → overloaded → limited → group shortage → balance → redeem batch →
    /// compensation. A failed block puts a neutral retry row at the head of its slot and keeps the rows of its earlier value
    /// (10 §0.5, §1.5). Account rows follow the server's `state` and take their words from AccountDisplayState (20 §0.2).
    /// `pending` is the caller's records of this site's address (X34); one of another site id there, an earlier login, ends with
    /// `previousLoginNote` when `currentServerID` is given. `now` is ServerClock time and `timeZone` the server's.
    public static func attentionItems(alerts: BlockState<HomeAlerts>, availability: BlockState<AccountStatusSummary>, structuredErrors: [UpstreamAccount],
                                      pending: [any PendingMoneyWrite], currentServerID: UUID? = nil, now: Date, timeZone: TimeZone,
                                      platformName: (String) -> String = GroupPlatform.title) -> [AttentionItem] {
        alertItems(alerts, now: now, timeZone: timeZone)
            + accountItems(availability, structuredErrors: structuredErrors, now: now, timeZone: timeZone, platformName: platformName)
            + pendingItems(pending, currentServerID: currentServerID, now: now, timeZone: timeZone)
    }

    /// The 受限 row (rate limited and temporarily unschedulable as one), also the calm layout's “自动恢复中” (10 §2.4). With
    /// `accounts_truncated` the count comes from the totals and the names end with “等”. An account limited only per model is
    /// `available` and never here.
    public static func limitedItem(_ summary: AccountStatusSummary, now: Date) -> AttentionItem? {
        let accounts = limitedAccounts(summary)
        let count = limitedCount(summary)
        guard count > 0 else { return nil }
        let rows = accounts.map { (item: $0, display: AccountDisplayState($0, now: now)) }
        let earliest = rows.compactMap { $0.display.countdownTarget ?? limitWindowEnd($0.item) }.min()
        let stopped = rows.filter { $0.display.state.isLimited ? $0.display.isStopped : $0.item.stopped }.map { accountName($0.item) }
        let names = accounts.map(accountName).joined(separator: "、")
        return AttentionItem(id: "limited", kind: .limitedAccounts, tone: AccountScheduleState.rateLimited.tone, systemImage: "hourglass",
                             title: "受限 \(DisplayFormat.grouped(count)) 个账号", detail: names.isEmpty ? nil : names + (summary.accountsTruncated ? "等" : ""),
                             trailing: earliest.map { .countdown(prefix: "最早 ", until: $0) }, countdownTarget: earliest,
                             stoppedNames: stopped.isEmpty ? nil : stopped.joined(separator: "、"), destination: .limitedAccounts)
    }

    /// U05: active groups the server marks short that also hold accounts needing attention, lowest available share first.
    public static func shortageGroups(_ summary: AccountStatusSummary) -> [AccountStatusGroupSummary] {
        summary.groups.filter { $0.groupStatus == "active" && $0.shortage.isShort && $0.counts.needsAttention > 0 }
            .sorted { (availableShare($0), $0.groupID) < (availableShare($1), $1.groupID) }
    }

    /// The calm flag's “无需处理” (10 §2.4).
    public static func hasLimitedAccounts(_ summary: AccountStatusSummary) -> Bool {
        summary.totals.rateLimited + summary.totals.tempUnschedulable > 0
    }

    /// The 受限 row's count, also the calm layout's “自动恢复中 · N 个”: the listed accounts, or the totals once the list is capped.
    static func limitedCount(_ summary: AccountStatusSummary) -> Int {
        let listed = limitedAccounts(summary).count
        return summary.accountsTruncated ? max(summary.totals.rateLimited + summary.totals.tempUnschedulable, listed) : listed
    }

    private static func limitedAccounts(_ summary: AccountStatusSummary) -> [AccountStatusItem] {
        summary.accounts.filter { $0.state == .rateLimited || $0.state == .tempUnschedulable }
    }

    // MARK: Alert slot

    private static func alertItems(_ state: BlockState<HomeAlerts>, now: Date, timeZone: TimeZone) -> [AttentionItem] {
        let retry = hasFailed(state) ? [AttentionItem(id: "retry-alerts", kind: .alertsFailed, tone: .neutral, systemImage: "arrow.clockwise",
                                                      title: alertsFailedTitle, destination: .retryAlerts)] : []
        guard let alerts = state.value else { return retry }
        let shown = Array(alerts.top.filter(\.isFiring).sorted(by: isListedBefore).prefix(maxAlertRows))
        // Every listed event was firing when counted; one resolved here since (10 §1.4) is not “另有”.
        let counted = shown + alerts.top.filter { !$0.isFiring }
        return retry + shown.map { alertItem($0, now: now, timeZone: timeZone) } + [moreAlertsItem(alerts, counted: counted)].compactMap { $0 }
    }

    private static func alertItem(_ event: AlertEvent, now: Date, timeZone: TimeZone) -> AttentionItem {
        let severity = event.severity.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = AlertPresentation.homeSubtitle(event, now: now, timeZone: timeZone)
        return AttentionItem(id: "alert-\(event.id)", kind: .alert, tone: AlertPresentation.tone(event) ?? .neutral, systemImage: "bell.fill",
                             title: AlertPresentation.title(event), badge: severity.isEmpty ? nil : .plain(severity),
                             detail: detail.isEmpty ? nil : detail, destination: .alert(id: event.id))
    }

    /// Toned by the highest level left once the counted rows are taken from `by_severity`; caution when nothing is known.
    private static func moreAlertsItem(_ alerts: HomeAlerts, counted: [AlertEvent]) -> AttentionItem? {
        let remaining = alerts.firingCount - counted.count
        guard remaining > 0 else { return nil }
        let reported = Dictionary(alerts.bySeverity.map { (severityKey($0.key), $0.value) }, uniquingKeysWith: +)
        let listed = Dictionary(counted.map { (severityKey($0.severity), 1) }, uniquingKeysWith: +)
        let tones = reported.filter { $0.value > listed[$0.key, default: 0] }.compactMap { Tone.alert(severity: $0.key, status: "firing") }
        let tone = [Tone.critical, .caution, .neutral].first { tones.contains($0) } ?? .caution
        return AttentionItem(id: "alerts-more", kind: .moreAlerts, tone: tone, systemImage: "bell.badge",
                             title: "另有 \(DisplayFormat.grouped(remaining)) 条告警中", destination: .alertsSegment)
    }

    /// P0 → P3, then other levels; newest first within a level (no time last), then the higher id.
    private static func isListedBefore(_ a: AlertEvent, _ b: AlertEvent) -> Bool {
        let (rankA, rankB) = (severityRank(a.severity), severityRank(b.severity))
        if rankA != rankB { return rankA < rankB }
        let (firedA, firedB) = (a.firedAt ?? .distantPast, b.firedAt ?? .distantPast)
        if firedA != firedB { return firedA > firedB }
        return a.id > b.id
    }

    private static func severityKey(_ severity: String) -> String { severity.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    private static func severityRank(_ severity: String) -> Int {
        AlertCounts.severities.firstIndex(of: severityKey(severity)) ?? AlertCounts.severities.count
    }

    // MARK: Account and group slots

    private static func accountItems(_ state: BlockState<AccountStatusSummary>, structuredErrors: [UpstreamAccount], now: Date, timeZone: TimeZone,
                                     platformName: (String) -> String) -> [AttentionItem] {
        let unreadable: Bool = if case .disabled = state { true } else { hasFailed(state) }
        let retry = unreadable ? [AttentionItem(id: "retry-availability", kind: .availabilityFailed, tone: .neutral, systemImage: "arrow.clockwise",
                                                title: availabilityFailedTitle, destination: .retryAvailability)] : []
        guard let summary = state.value else { return retry }
        let errors = Dictionary(structuredErrors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let errorRows = summary.accounts.filter { $0.state == .error }
            .map { errorItem($0, structuredError: errors[$0.id], now: now, timeZone: timeZone, platformName: platformName) }
        let overloadRows = summary.accounts.filter { $0.state == .overloaded }.map { overloadedItem($0, now: now, platformName: platformName) }
        return retry + errorRows + overloadRows + [limitedItem(summary, now: now), shortageItem(summary)].compactMap { $0 }
    }

    /// R12: the reason is AccountDisplayState's, “上游返回异常” without C02 fields; `error_message` is never read.
    private static func errorItem(_ item: AccountStatusItem, structuredError: UpstreamAccount?, now: Date, timeZone: TimeZone,
                                  platformName: (String) -> String) -> AttentionItem {
        let display = AccountDisplayState(item, structuredError: structuredError, now: now)
        let state = AccountScheduleState.error
        let reason = display.state == state ? display.reason : nil
        let errorAt = ServerTime.parseTimestamp(structuredError?.errorAt).map { DisplayFormat.relativeTime($0, now: now, timeZone: timeZone) }
        let footnote = [platformText(item, platformName), errorAt].compactMap { $0 }.joined(separator: " · ")
        return AttentionItem(id: "account-\(item.id)", kind: .errorAccount, tone: state.tone, systemImage: "xmark.octagon.fill", title: accountName(item),
                             badge: .plain(state.label), detail: reason ?? AccountDisplayState.unknownErrorReason,
                             footnote: footnote.isEmpty ? nil : footnote, destination: .account(id: item.id), action: .accountTest(id: item.id))
    }

    /// AccountDisplayState's phrase for 过载中; only `handle529` sets overload_until, so it never varies (10 §1.2).
    private static let overloadReason = AccountDisplayState(AccountStateInput(status: "active", schedulable: true, overloadUntil: .distantFuture),
                                                            now: .distantPast).reason ?? ""

    /// Past its window the row keeps the server's state, counting 0:00 until the refresh it triggers (10 §1.6).
    private static func overloadedItem(_ item: AccountStatusItem, now: Date, platformName: (String) -> String) -> AttentionItem {
        let display = AccountDisplayState(item, now: now)
        let state = AccountScheduleState.overloaded
        let isCurrent = display.state == state
        let target = isCurrent ? display.countdownTarget : item.overloadUntil
        let stopped = display.state.isLimited ? display.isStopped : item.stopped
        let reason = (isCurrent ? display.reason : nil) ?? overloadReason
        return AttentionItem(id: "account-\(item.id)", kind: .overloadedAccount, tone: state.tone, systemImage: "flame.fill", title: accountName(item),
                             badge: target.map { .countdown(prefix: state.label + " ", until: $0) } ?? .plain(state.label),
                             detail: [reason, platformText(item, platformName)].compactMap { $0 }.joined(separator: " · "),
                             detailMark: stopped ? AccountDisplayState.stoppedMark : nil, countdownTarget: target, destination: .account(id: item.id))
    }

    /// “可用不足 N 个分组”: critical when any group has none left; one group opens it, several open the groups' 需处理 segment.
    private static func shortageItem(_ summary: AccountStatusSummary) -> AttentionItem? {
        let groups = shortageGroups(summary)
        guard let first = groups.first else { return nil }
        let detail = groups.map { (nonBlank($0.groupName) ?? "分组 #\($0.groupID)") + " \($0.counts.available)/\($0.counts.total)" }
        return AttentionItem(id: "groups", kind: .groupShortage, tone: groups.contains { $0.counts.available == 0 } ? .critical : .caution,
                             systemImage: "square.stack.3d.up.fill", title: "可用不足 \(groups.count) 个分组", detail: detail.joined(separator: " · "),
                             destination: groups.count == 1 ? .group(id: first.groupID) : .groupsAttention)
    }

    private static func availableShare(_ group: AccountStatusGroupSummary) -> Double {
        group.counts.total > 0 ? Double(group.counts.available) / Double(group.counts.total) : 0
    }

    private static func limitWindowEnd(_ item: AccountStatusItem) -> Date? {
        item.state == .rateLimited ? item.rateLimitResetAt : item.tempUnschedulableUntil
    }

    private static func accountName(_ item: AccountStatusItem) -> String { nonBlank(item.name) ?? "账号 #\(item.id)" }
    private static func platformText(_ item: AccountStatusItem, _ platformName: (String) -> String) -> String? {
        nonBlank(item.platform).map(platformName)
    }

    // MARK: Money slots (R02)

    private static let pendingOrder: [AttentionKind] = [.pendingBalance, .pendingRedeemBatch, .pendingCompensation]

    /// Balance → redeem batch → compensation, oldest first within a kind (a legacy balance record without createdAt first, as
    /// in PendingMoneyLedger). Only these three record types exist; a new one needs its case in `pendingRoute`.
    private static func pendingItems(_ records: [any PendingMoneyWrite], currentServerID: UUID?, now: Date, timeZone: TimeZone) -> [AttentionItem] {
        let routed = records.compactMap { record in pendingRoute(record).map { (record: record, route: $0) } }
        let ordered = routed.sorted { a, b in
            let (rankA, rankB) = (pendingOrder.firstIndex(of: a.route.kind) ?? 0, pendingOrder.firstIndex(of: b.route.kind) ?? 0)
            if rankA != rankB { return rankA < rankB }
            return (a.record.summary.createdAt ?? .distantPast) < (b.record.summary.createdAt ?? .distantPast)
        }
        return ordered.map { routed in
            let earlier = currentServerID.map { routed.record.serverID != $0 } ?? false
            return pendingItem(routed.record, kind: routed.route.kind, destination: routed.route.destination, fromEarlierLogin: earlier, now: now,
                               timeZone: timeZone)
        }
    }

    private static func pendingRoute(_ record: any PendingMoneyWrite) -> (kind: AttentionKind, destination: HomeDestination)? {
        switch record {
        case let balance as PendingBalanceOperation: (.pendingBalance, .user(id: balance.userID))
        case is PendingRedeemBatch: (.pendingRedeemBatch, .redeemReconcile)
        case let grant as PendingCompensation: (.pendingCompensation, .compensation(userID: grant.userID, pendingID: grant.id))
        default: nil
        }
    }

    /// Title and detail are PendingMoneyWriteLine's (00 §2.5.5); the amount is echoed unrounded, as the administrator typed it.
    private static func pendingItem(_ record: any PendingMoneyWrite, kind: AttentionKind, destination: HomeDestination, fromEarlierLogin: Bool,
                                    now: Date, timeZone: TimeZone) -> AttentionItem {
        let line = record.line
        let time = record.summary.createdAt.map { DisplayFormat.relativeTime($0, now: now, timeZone: timeZone) }
        let amount: AttentionText? = switch line.amount {
        case .money(let value)?: .plain(DisplayFormat.moneyExact(value))
        case .allBalance?: .plain(PendingMoneyWriteLine.allBalanceText)
        case nil: nil
        }
        return AttentionItem(id: "pending-" + record.key, kind: kind, tone: .caution, systemImage: "doc.text.magnifyingglass", title: line.title,
                             detail: line.detail(relativeTime: time) + (fromEarlierLogin ? " · " + previousLoginNote : ""), trailing: amount,
                             destination: destination)
    }

    private static func hasFailed<Value: Sendable>(_ state: BlockState<Value>) -> Bool {
        if case .failed = state { true } else { false }
    }
}
