import Foundation

/// The dimension a section header already names, so a row's second line leaves it out (20 §1.3, 50 §2.3 / §8.3, 60 §2.3):
/// platform sections `.platform`, a group's members `.group`, search results `.none`.
public enum AccountRowOmit: Sendable, Equatable, CaseIterable { case none, platform, group }

/// The row's 今日 cell (20 §1.3, S2D1-18). `.hidden` is for callers without today figures (60 §2.3 search results).
public enum AccountTodayCell: Sendable, Equatable {
    case value(Decimal)
    case failed
    case hidden

    /// A failed read or id, an id the batch left out and an old server's missing user_cost all read “—”.
    public init(stats: AccountTodayStats?, unavailable: Bool) {
        guard !unavailable, let cost = stats?.userCost else { self = .failed; return }
        self = .value(cost)
    }
    /// “$409.38” / “—”; nil when hidden.
    public var text: String? {
        switch self {
        case .value(let cost): DisplayFormat.money(cost)
        case .failed: DisplayFormat.missing
        case .hidden: nil
        }
    }
}

/// `current_concurrency / concurrency` of the third line. An unavailable runtime, a zero or missing limit and a null current
/// count are “— 并发”, never 0 (20 §1.3, 00 §6.5).
public struct AccountRowConcurrency: Sendable, Equatable {
    public let used: Int?
    public let limit: Int?

    public init(_ account: UpstreamAccount) {
        guard account.concurrencyAvailable != false, let limit = account.concurrency, limit > 0, let used = account.currentConcurrency else {
            self.used = nil; self.limit = nil; return
        }
        self.used = max(0, used); self.limit = limit
    }
    public var isMissing: Bool { used == nil || limit == nil }
    /// “2/4 并发” / “— 并发”.
    public var text: String { "\(figures ?? DisplayFormat.missing) 并发" }
    /// “并发 2/4” / “并发 无数据”.
    public var spoken: String { "并发 \(figures ?? DisplayFormat.missingSpoken)" }
    /// Capped at 1 for the bar.
    public var fraction: Double? {
        guard let used, let limit else { return nil }
        return min(Double(used) / Double(limit), 1)
    }
    /// Design BaseCapacity: from 90% critical, from 75% caution, otherwise the bar's plain ink.
    public var tone: Tone? {
        guard let used, let limit else { return nil }
        let ratio = Double(used) / Double(limit)
        return ratio >= 0.9 ? .critical : ratio >= 0.75 ? .caution : nil
    }
    private var figures: String? {
        guard let used, let limit else { return nil }
        return "\(DisplayFormat.grouped(used))/\(DisplayFormat.grouped(limit))"
    }
}

/// The row's third line, one of three kinds (20 §1.3).
public enum AccountRowThirdLine: Sendable, Equatable {
    /// `error_summary`, or “上游返回异常”; never `error_message` (R12).
    case error(summary: String)
    /// [已停止调度 ·] reason · HH:MM 恢复 [· 模型限流 N]; the clock is in the server's time zone.
    case limited(stoppedMark: String?, reason: String, resume: String, modelLimits: String?)
    /// Concurrency on the left, today on the right; `today` nil when the caller hides it.
    case usage(concurrency: AccountRowConcurrency, today: String?)
}

/// 20 §1.3: what the account row shows, shared by the account tab, group members (50) and search results (60).
public enum AccountRowPresentation {
    public static let ungrouped = "未分组"

    /// In `group_ids` order: the directory's name, then the name the row embedded, then “#id”.
    public static func groupNames(_ account: UpstreamAccount, directory: (Int) -> String?) -> [String] {
        account.groupIDs.map { id in
            if let name = nonEmpty(directory(id)) { return name }
            return nonEmpty(account.groups.first { $0.id == id }?.name) ?? "#\(id)"
        }
    }

    /// “高级组、Claude Code 组 · OAuth” in a platform section; “Anthropic · 高级组、Claude Code 组 · OAuth” without a header;
    /// “Anthropic · 另属 Claude Code 组 · OAuth” under the group `home`, or “Anthropic · OAuth” when it is the only one.
    public static func secondLine(_ account: UpstreamAccount, omit: AccountRowOmit, home: String?, catalog: MetaCatalog?,
                                  directory: (Int) -> String?) -> String {
        let platform = AccountNaming.platformName(account.platform, catalog: catalog)
        let groups = groupNames(account, directory: directory)
        let listed = groups.isEmpty ? ungrouped : groups.joined(separator: "、")
        let place: String
        switch omit {
        case .platform: place = listed
        case .none: place = "\(platform) · \(listed)"
        case .group:
            let others = groups.filter { $0 != home }
            place = others.isEmpty ? platform : "\(platform) · 另属 \(others.joined(separator: "、"))"
        }
        return "\(place) · \(AccountNaming.typeName(platform: account.platform, type: account.type))"
    }

    public static func thirdLine(_ account: UpstreamAccount, display: AccountDisplayState, today: AccountTodayCell,
                                 timeZone: TimeZone) -> AccountRowThirdLine {
        if display.state == .error { return .error(summary: display.reason ?? AccountDisplayState.unknownErrorReason) }
        if let target = display.countdownTarget {
            let limits = display.modelRateLimits.count
            return .limited(stoppedMark: display.isStopped ? AccountDisplayState.stoppedMark : nil, reason: display.reason ?? display.label,
                            resume: "\(DisplayFormat.clock(target, timeZone: timeZone)) 恢复", modelLimits: limits > 0 ? "模型限流 \(limits)" : nil)
        }
        return .usage(concurrency: AccountRowConcurrency(account), today: today.text)
    }

    /// The leading glyph and the badge's icon (S2-08's status card uses the same table).
    public static func systemImage(for state: AccountScheduleState) -> String {
        switch state {
        case .available: "circle.fill"
        case .rateLimited: "hourglass"
        case .overloaded: "flame"
        case .tempUnschedulable: "clock.badge.exclamationmark"
        case .error: "exclamationmark.octagon"
        case .paused: "pause"
        case .inactive: "minus"
        }
    }

    /// Paused and disabled rows are dimmed (design `is-idle`).
    public static func isIdle(_ state: AccountScheduleState) -> Bool { state == .paused || state == .inactive }

    /// nil for 正常 (the design draws no badge); “限流中 4:37”; “暂停 · 已过期”.
    public static func badgeText(_ display: AccountDisplayState, now: Date) -> String? {
        guard display.state != .available else { return nil }
        if let target = display.countdownTarget { return "\(display.label) \(DisplayFormat.countdown(until: target, now: now))" }
        return display.note.map { "\(display.label) · \($0)" } ?? display.label
    }

    /// “{name}，{状态}[，剩余 m:ss]，{第 2 行}，{第 3 行}”; a missing value reads “无数据”.
    public static func accessibilityLabel(name: String, display: AccountDisplayState, now: Date, second: String,
                                          third: AccountRowThirdLine) -> String {
        var parts = [name, display.label]
        if let note = display.note { parts.append(note) }
        if let target = display.countdownTarget { parts.append("剩余 \(DisplayFormat.countdown(until: target, now: now))") }
        parts.append(second)
        switch third {
        case .error(let summary): parts.append(summary)
        case .limited(let stopped, let reason, let resume, let limits): parts += [stopped, reason, resume, limits].compactMap { $0 }
        case .usage(let concurrency, let today):
            parts.append(concurrency.spoken)
            if let today { parts.append("今日 \(DisplayFormat.spoken(today))") }
        }
        return parts.joined(separator: "，")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
