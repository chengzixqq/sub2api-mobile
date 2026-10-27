import Foundation

// 20 §2.2–§2.3 (S2-09): the account detail's 容量（壹）· 今日（贰）· 记录（叁） and the status card's “最近上游错误” line.

/// One 容量 line: the bar's fill, its readout and what VoiceOver reads. Group details draw theirs with `count` (C-7, S5-07).
public struct CapacityRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// used ÷ limit, not clamped (the bar fills at most once); nil when the used part is unknown, which draws the track only.
    public let fraction: Double?
    public let readout: String
    public let spokenReadout: String
    public let note: String?
    /// nil is the normal ink; the design's BaseCapacity turns caution from 75% and critical from 90%.
    public let tone: Tone?

    public var spokenValue: String { note.map { "\(spokenReadout)，\($0)" } ?? spokenReadout }

    public init(id: String, title: String, fraction: Double?, readout: String, spokenReadout: String? = nil, note: String? = nil, tone: Tone? = nil) {
        self.id = id; self.title = title; self.fraction = fraction; self.readout = readout
        self.spokenReadout = spokenReadout ?? readout; self.note = note; self.tone = tone
    }

    /// “2/4”; an unknown used part is “— / 4” (00 §6.5: unknown is not 0).
    public static func count(id: String, title: String, used: Int?, limit: Int, note: String? = nil) -> CapacityRow {
        let limitText = DisplayFormat.grouped(limit)
        guard let used else { return unknown(id: id, title: title, limit: limitText, note: note) }
        let fraction = limit > 0 ? Double(used) / Double(limit) : nil
        return CapacityRow(id: id, title: title, fraction: fraction, readout: DisplayFormat.grouped(used) + "/" + limitText, note: note,
                           tone: level(fraction))
    }
    /// “$96.30 / $150.00”.
    public static func money(id: String, title: String, used: Decimal?, limit: Decimal) -> CapacityRow {
        let limitText = DisplayFormat.money(limit)
        guard let used else { return unknown(id: id, title: title, limit: limitText, note: nil) }
        let fraction = limit > 0 ? NSDecimalNumber(decimal: used / limit).doubleValue : nil
        return CapacityRow(id: id, title: title, fraction: fraction, readout: DisplayFormat.money(used) + " / " + limitText, tone: level(fraction))
    }
    /// A percentage that already is one (`five_hour.utilization`): “42.0%”.
    public static func percent(id: String, title: String, utilization: Double, note: String? = nil) -> CapacityRow {
        let fraction = utilization.isFinite ? utilization / 100 : nil
        return CapacityRow(id: id, title: title, fraction: fraction, readout: DisplayFormat.percent(utilization), note: note, tone: level(fraction))
    }
    public static func level(_ fraction: Double?) -> Tone? {
        guard let fraction else { return nil }
        if fraction >= 0.9 { return .critical }
        return fraction >= 0.75 ? .caution : nil
    }

    private static func unknown(id: String, title: String, limit: String, note: String?) -> CapacityRow {
        CapacityRow(id: id, title: title, fraction: nil, readout: DisplayFormat.missing + " / " + limit,
                    spokenReadout: DisplayFormat.missingSpoken + " / " + limit, note: note)
    }
}

/// 今日: `user_cost` is 实际, `cost` 账号成本, `standard_cost` 标准; “—” where the server sent nothing or nothing was read.
public struct AccountTodayFigures: Equatable, Sendable {
    /// 附录 B L17.
    public static let footnote = "账号成本与标准只按真实上游调用计算；实际扣费还含合并探测的跟随请求。"
    public static let missing = AccountTodayFigures(actual: DisplayFormat.missing, accountCost: DisplayFormat.missing, standard: DisplayFormat.missing,
                                                    requests: DisplayFormat.missing, tokens: DisplayFormat.missing)
    public let actual: String
    public let accountCost: String
    public let standard: String
    public let requests: String
    /// Cache tokens included, as the server counts them.
    public let tokens: String

    public init(actual: String, accountCost: String, standard: String, requests: String, tokens: String) {
        self.actual = actual; self.accountCost = accountCost; self.standard = standard; self.requests = requests; self.tokens = tokens
    }
}

/// The newest upstream error of the last 24 hours, as the status card shows and opens it.
public struct LatestUpstreamError: Equatable, Sendable {
    public let id: Int
    public let createdAt: Date?
    public let status: UpstreamErrorStatus

    public init(id: Int, createdAt: Date?, status: UpstreamErrorStatus) { self.id = id; self.createdAt = createdAt; self.status = status }
    public init(_ record: RequestErrorRecord) {
        self.init(id: record.id, createdAt: ServerTime.parseTimestamp(record.createdAt), status: record.upstreamStatus)
    }
}

/// One `upstream-errors` read of page size 1 serves both places (X08): `total` for 记录, `items.first` for the status card.
/// 404 OPS_DISABLED is a value, not a failure: 记录 says “运维监控未开启” and the light refresh stops asking (20 §0.5).
public enum AccountUpstreamErrors: Equatable, Sendable {
    case records(total: Int?, latest: LatestUpstreamError?)
    case opsDisabled

    public static let opsDisabledReason = "OPS_DISABLED"

    public init(page: Page<RequestErrorRecord>) { self = .records(total: page.total, latest: page.items.first.map { LatestUpstreamError($0) }) }
    public static func isOpsDisabled(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return api.statusCode == 404 && api.reason == opsDisabledReason
    }
}

/// What the status card's line needs: the shown state, the upstream errors read and the account's C02 `error_at`.
public struct LastUpstreamErrorInput: Equatable, Sendable {
    public let state: AccountScheduleState
    public let upstream: BlockState<AccountUpstreamErrors>
    public let errorAt: Date?
    public let errorStatusCode: Int?

    public init(state: AccountScheduleState, upstream: BlockState<AccountUpstreamErrors>, errorAt: Date?, errorStatusCode: Int?) {
        self.state = state; self.upstream = upstream; self.errorAt = errorAt; self.errorStatusCode = errorStatusCode
    }
    public init(account: UpstreamAccount, state: AccountScheduleState, upstream: BlockState<AccountUpstreamErrors>) {
        self.init(state: state, upstream: upstream, errorAt: ServerTime.parseTimestamp(account.errorAt), errorStatusCode: account.errorStatusCode)
    }
}

/// “最近上游错误 14:08 · 12 分钟前 · 401 ›” opens that request; U22's “出错于 13:55 · 25 分钟前 · 401” only says when.
public enum LastUpstreamErrorLine: Equatable, Sendable {
    case latest(requestID: Int, time: String?, ago: String?, code: String?)
    case erroredAt(time: String, ago: String, code: String?)

    public var text: String {
        switch self {
        case .latest(_, let time, let ago, let code):
            return ["最近上游错误" + (time.map { " " + $0 } ?? ""), ago, code].compactMap { $0 }.joined(separator: " · ")
        case .erroredAt(let time, let ago, let code):
            return ["出错于 " + time, ago, code].compactMap { $0 }.joined(separator: " · ")
        }
    }
    public var isTappable: Bool {
        if case .latest = self { true } else { false }
    }
}

/// The detail's reads besides the account; each fails on its own (20 §2.5).
public enum AccountDetailBlock: String, CaseIterable, Sendable {
    case today, usageWindow, upstreamErrors
}

/// 壹 · 贰 · 叁 over the sections shown: without 容量, 今日 is 壹.
public struct AccountDetailSectionOrdinals: Equatable, Sendable {
    public let capacity: String?
    public let today: String
    public let records: String
    public init(capacity: String?, today: String, records: String) { self.capacity = capacity; self.today = today; self.records = records }
}

extension AccountDetailPresentation {
    /// 容量 in the design's order; empty leaves the section out. The 5-hour row needs an Anthropic token account and its window.
    public static func capacityRows(account: UpstreamAccount, usageWindow: AccountUsageWindow?, timeZone: TimeZone) -> [CapacityRow] {
        var rows: [CapacityRow] = []
        if let limit = account.concurrency, limit > 0 {
            let used = account.concurrencyAvailable == false ? nil : account.currentConcurrency
            rows.append(.count(id: "concurrency", title: "并发", used: used, limit: limit))
        }
        if let limit = account.baseRPM, limit > 0 {
            rows.append(.count(id: "rpm", title: "调度 RPM", used: account.schedulingRPM, limit: limit, note: "自然分钟"))
        }
        if let limit = account.maxSessions, limit > 0 {
            rows.append(.count(id: "sessions", title: "会话", used: account.activeSessions, limit: limit,
                               note: account.sessionIdleTimeoutMinutes.map { "空闲 \($0) 分钟释放" }))
        }
        let quotas: [(String, String, Decimal?, Decimal?)] = [
            ("dailyQuota", "日配额", account.quotaDailyUsed, account.quotaDailyLimit),
            ("weeklyQuota", "周配额", account.quotaWeeklyUsed, account.quotaWeeklyLimit),
            ("totalQuota", "总配额", account.quotaUsed, account.quotaLimit)
        ]
        for (id, title, used, limit) in quotas {
            guard let limit, limit > 0 else { continue }
            rows.append(.money(id: id, title: title, used: used, limit: limit))
        }
        if AccountUsageWindow.applies(to: account), let window = usageWindow?.fiveHour {
            rows.append(.percent(id: "fiveHour", title: "5 小时窗口", utilization: window.utilization,
                                 note: window.resetsAt.map { DisplayFormat.clock($0, timeZone: timeZone) + " 重置" }))
        }
        return rows
    }

    /// The runtime counters 容量 reads, on top of the list's merge (AccountDetailRefresh): an omitted one is unknown, not 0.
    /// `current_window_cost` stays, since the detail does not ask for it.
    public static func mergingCapacity(_ runtime: AccountRuntime, into account: UpstreamAccount) -> UpstreamAccount {
        var merged = account
        merged.currentConcurrency = runtime.currentConcurrency
        merged.concurrencyAvailable = runtime.concurrencyAvailable
        merged.currentRPM = runtime.currentRPM
        merged.schedulingRPM = runtime.schedulingRPM
        merged.activeSessions = runtime.activeSessions
        return merged
    }

    /// “更新于 HH:MM:SS” beside 容量's title, in the server's zone.
    public static func capacityUpdatedText(_ date: Date?, timeZone: TimeZone) -> String? {
        date.map { "更新于 " + DisplayFormat.clockWithSeconds($0, timeZone: timeZone) }
    }

    public static func today(_ stats: AccountTodayStats?) -> AccountTodayFigures {
        guard let stats else { return .missing }
        return AccountTodayFigures(actual: DisplayFormat.money(stats.userCost), accountCost: DisplayFormat.money(stats.cost),
                                   standard: DisplayFormat.money(stats.standardCost), requests: DisplayFormat.grouped(stats.requests),
                                   tokens: DisplayFormat.compact(stats.tokens))
    }

    /// 记录 · 上游错误's right side: nothing while the first read is out, “—” when it failed.
    public static func upstreamRecordTrailing(_ state: BlockState<AccountUpstreamErrors>) -> String? {
        switch state.value {
        case .records(let total, _)?: return total.map { "近 24 小时 \(DisplayFormat.grouped($0)) 条" } ?? DisplayFormat.missing
        case .opsDisabled?: return "运维监控未开启"
        case nil: return isFailed(state) ? DisplayFormat.missing : nil
        }
    }

    /// Only in 错误. The newest upstream error when there is one; after OPS_DISABLED, a failed read or a quiet day, the account's
    /// `error_at` (U22); nothing while the first read is out, so the fallback does not flash.
    public static func lastUpstreamErrorLine(_ input: LastUpstreamErrorInput, now: Date, timeZone: TimeZone) -> LastUpstreamErrorLine? {
        guard input.state == .error else { return nil }
        if case .records(_, let latest?)? = input.upstream.value {
            return .latest(requestID: latest.id, time: latest.createdAt.map { DisplayFormat.clock($0, timeZone: timeZone) },
                           ago: latest.createdAt.map { DisplayFormat.elapsed(since: $0, now: now) }, code: codeText(latest.status))
        }
        guard input.upstream.value != nil || isFailed(input.upstream), let errorAt = input.errorAt else { return nil }
        return .erroredAt(time: DisplayFormat.clock(errorAt, timeZone: timeZone), ago: DisplayFormat.elapsed(since: errorAt, now: now),
                          code: input.errorStatusCode.map(String.init))
    }

    /// 近 24 小时 of this account's upstream errors, one row: the same view as the log page it opens (S4-01).
    public static func upstreamErrorFilter(accountID: Int) -> RequestLogFilter {
        RequestLogFilter(time: .rolling(.h24), accountID: accountID, pageSize: 1)
    }

    /// The blocks a refresh reads. The 5-hour window only for an Anthropic token account; after OPS_DISABLED only a refresh the
    /// user asked for (pull, foreground, entering again) tries the upstream errors. A block already loading is left to finish,
    /// and the light refresh skips a block still backing off after failures (00 §4.6).
    public static func blocksToRefresh(account: UpstreamAccount?, upstream: AccountUpstreamErrors?, userInitiated: Bool,
                                       inFlight: Set<AccountDetailBlock> = [], dueDates: [AccountDetailBlock: Date] = [:],
                                       now: Date) -> Set<AccountDetailBlock> {
        var blocks: Set<AccountDetailBlock> = [.today, .upstreamErrors]
        if let account, AccountUsageWindow.applies(to: account) { blocks.insert(.usageWindow) }
        if upstream == .opsDisabled, !userInitiated { blocks.remove(.upstreamErrors) }
        blocks.subtract(inFlight)
        guard !userInitiated else { return blocks }
        return blocks.filter { block in dueDates[block].map { $0 <= now } ?? true }
    }

    public static func sectionOrdinals(hasCapacity: Bool) -> AccountDetailSectionOrdinals {
        let first = hasCapacity ? 2 : 1
        return AccountDetailSectionOrdinals(capacity: hasCapacity ? ChineseOrdinal.text(1) : nil, today: ChineseOrdinal.text(first),
                                            records: ChineseOrdinal.text(first + 1))
    }

    /// 40 §6.3: the code itself, “鉴权” for a recovered account authentication failure; nothing when the row does not say.
    private static func codeText(_ status: UpstreamErrorStatus) -> String? {
        switch status {
        case .code(let code): String(code)
        case .accountAuth: "鉴权"
        case .unknown: nil
        }
    }
    private static func isFailed<Value: Sendable>(_ state: BlockState<Value>) -> Bool {
        if case .failed = state { true } else { false }
    }
}

// MARK: - 今日 429（X37）

// S2-23 replaces these two with S1-08's BlockFailureRow and deletes them; nothing else depends on them.

/// The line under 今日's figures: a failure to retry, or the 429 wait with 重试 greyed out until it ends.
public struct AccountTodayStatusLine: Equatable, Sendable {
    public let text: String
    public let retryEnabled: Bool
    public init(text: String, retryEnabled: Bool) { self.text = text; self.retryEnabled = retryEnabled }
}

extension AccountDetailPresentation {
    /// `throttle` is `BlockRefresh.throttleMessage(at:)`: “请求过于频繁，N 秒后自动重试” wins over the failure while it lasts.
    public static func todayStatusLine(_ state: BlockState<AccountTodayStats>, throttle: String?) -> AccountTodayStatusLine? {
        guard case .failed(_, let previous, _) = state else { return nil }
        if let throttle { return AccountTodayStatusLine(text: throttle, retryEnabled: false) }
        return AccountTodayStatusLine(text: previous == nil ? "读取失败 · 重试" : "刷新失败 · 重试", retryEnabled: true)
    }
}
