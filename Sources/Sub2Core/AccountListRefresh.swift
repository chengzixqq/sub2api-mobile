import Foundation

/// 20 §1.6: when the account list refreshes, and what a light refresh changes. Marks are device time: they only measure how long
/// ago something ran (20 §0.6, last rule), so a jump in the site's Date offset never stalls or rushes the timer.
public enum AccountListRefresh {
    public static let lightInterval: TimeInterval = 60
    public static let fullInterval: TimeInterval = 300
    /// A countdown reaching zero refreshes at most once in this long.
    public static let countdownGap: TimeInterval = 10

    public enum Kind: Equatable, Sendable { case light, full }

    /// Timers run only in the foreground, with the tab visible, outside selection mode and with no sheet open.
    public struct Gate: Equatable, Sendable {
        public var isForeground: Bool
        public var isVisible: Bool
        public var isSelecting: Bool
        public var hasSheet: Bool
        public init(isForeground: Bool = true, isVisible: Bool = false, isSelecting: Bool = false, hasSheet: Bool = false) {
            self.isForeground = isForeground; self.isVisible = isVisible; self.isSelecting = isSelecting; self.hasSheet = hasSheet
        }
        public var isOpen: Bool { isForeground && isVisible && !isSelecting && !hasSheet }
    }

    /// When each kind last started. A full refresh also counts as a light one.
    public struct Marks: Equatable, Sendable {
        public var lastLight: Date?
        public var lastFull: Date?
        public var lastCountdown: Date?
        public init(lastLight: Date? = nil, lastFull: Date? = nil, lastCountdown: Date? = nil) {
            self.lastLight = lastLight; self.lastFull = lastFull; self.lastCountdown = lastCountdown
        }
        public func recording(_ kind: Kind, at date: Date) -> Marks {
            var next = self
            switch kind {
            case .light: next.lastLight = date
            case .full: next.lastFull = date
            }
            return next
        }
        public func recordingCountdown(at date: Date) -> Marks {
            var next = self
            next.lastCountdown = date
            return next
        }
        /// A full refresh cut short with only its first pages shown: the next timer check runs one again.
        public func forgettingFull() -> Marks {
            var next = self
            next.lastFull = nil
            return next
        }
    }

    /// A light refresh: when it started, and whether the timer or a countdown started it rather than the user or an event.
    public struct Round: Equatable, Sendable {
        public var start: Date
        public var isScheduled: Bool
        public init(start: Date, isScheduled: Bool) { self.start = start; self.isScheduled = isScheduled }
    }

    /// runtime/batch, status-summary or today-stats/batch, each apart from the list (00 §2.3: a 429 holds back only its block).
    /// No round sends it during a 429 wait (00 §2.7.2); a scheduled round also skips it after failures until the backed-off
    /// interval (60 → 120 → 240 → 300 seconds, 00 §4.6) has passed since the round it last went out in.
    public struct LightBlock: Equatable, Sendable {
        public private(set) var refresh = BlockRefresh()
        public private(set) var lastRound: Date?
        public init() {}

        public func allowsRequest(in round: Round) -> Bool {
            guard refresh.allowsRequest(at: round.start) else { return false }
            guard round.isScheduled, refresh.consecutiveFailures > 0, let lastRound else { return true }
            let wait = BlockRefresh.nextRefreshInterval(base: AccountListRefresh.lightInterval, consecutiveFailures: refresh.consecutiveFailures)
            return !AccountListRefresh.isWithin(wait, since: lastRound, now: round.start)
        }
        public func requesting(in round: Round) -> LightBlock {
            var next = self
            next.lastRound = round.start
            return next
        }
        public func recordingSuccess() -> LightBlock {
            var next = self
            next.refresh = refresh.recordingSuccess()
            return next
        }
        public func recordingFailure(_ error: any Error, at now: Date) -> LightBlock {
            var next = self
            next.refresh = refresh.recordingFailure(error, at: now)
            return next
        }
    }

    /// Without `accounts.runtime_batch` the 60-second refresh reads the whole list.
    public static func resolved(_ kind: Kind, supportsRuntime: Bool) -> Kind { supportsRuntime ? kind : .full }

    /// What the timer should run now, if anything. Consecutive failures stretch the 60 seconds (BlockRefresh); a 429 wait sends nothing.
    public static func due(at now: Date, gate: Gate, marks: Marks, supportsRuntime: Bool, throttle: BlockRefresh) -> Kind? {
        guard gate.isOpen, throttle.allowsRequest(at: now) else { return nil }
        guard let lastFull = marks.lastFull, isWithin(fullInterval, since: lastFull, now: now) else { return .full }
        let lastAny = max(lastFull, marks.lastLight ?? lastFull)
        guard !isWithin(lightInterval(throttle), since: lastAny, now: now) else { return nil }
        return resolved(.light, supportsRuntime: supportsRuntime)
    }

    /// Seconds until `due` may return something; nil while the gate is closed, so the timer stops.
    public static func nextCheck(at now: Date, gate: Gate, marks: Marks, throttle: BlockRefresh) -> TimeInterval? {
        guard gate.isOpen else { return nil }
        var wait: TimeInterval = 0
        if let lastFull = marks.lastFull {
            let lastAny = max(lastFull, marks.lastLight ?? lastFull)
            wait = max(0, min(remaining(fullInterval, since: lastFull, now: now), remaining(lightInterval(throttle), since: lastAny, now: now)))
        }
        if let notBefore = throttle.notBefore, notBefore > now { wait = max(wait, notBefore.timeIntervalSince(now)) }
        return wait
    }

    /// A row's countdown reached zero (20 §1.6): refresh, at most once in `countdownGap`.
    public static func countdownRefresh(at now: Date, gate: Gate, marks: Marks, supportsRuntime: Bool, throttle: BlockRefresh) -> Kind? {
        guard gate.isOpen, throttle.allowsRequest(at: now) else { return nil }
        if let last = marks.lastCountdown, isWithin(countdownGap, since: last, now: now) { return nil }
        return resolved(.light, supportsRuntime: supportsRuntime)
    }

    /// Writes a `runtime/batch` reply over the rows: only concurrency, status, the switch and the three windows (null clears a
    /// window). Rows missing from the reply are left as they are.
    public static func merging(_ rows: [UpstreamAccount], runtime: [Int: AccountRuntime]) -> [UpstreamAccount] {
        rows.map { row in
            guard let live = runtime[row.id] else { return row }
            var merged = row
            merged.currentConcurrency = live.currentConcurrency
            merged.concurrencyAvailable = live.concurrencyAvailable
            merged.status = live.status
            merged.schedulable = live.schedulable
            merged.rateLimitResetAt = live.rateLimitResetAt.map(ServerTime.utcTimestamp)
            merged.overloadUntil = live.overloadUntil.map(ServerTime.utcTimestamp)
            merged.tempUnschedulableUntil = live.tempUnschedulableUntil.map(ServerTime.utcTimestamp)
            return merged
        }
    }
    /// A changed status or switch, or a loaded account the reply left out (deleted, moved out of scope), needs the whole list.
    public static func needsFullRefresh(_ rows: [UpstreamAccount], runtime: [Int: AccountRuntime]) -> Bool {
        rows.contains { row in
            guard let live = runtime[row.id] else { return true }
            return live.status != row.status || live.schedulable != row.schedulable
        }
    }

    /// The page after `page` while fewer than min(total, limit) rows are loaded.
    public static func nextPage(after page: AccountListPage, loaded: Int, limit: Int) -> Int? {
        loaded < min(page.total, limit) && page.page < page.pages ? page.page + 1 : nil
    }
    /// Rows move between pages while they are read; an id already loaded keeps its first copy.
    public static func appending(_ items: [UpstreamAccount], to rows: [UpstreamAccount], limit: Int) -> [UpstreamAccount] {
        var seen = Set(rows.map(\.id)), result = rows
        for item in items where result.count < limit && seen.insert(item.id).inserted { result.append(item) }
        return Array(result.prefix(limit))
    }

    private static func lightInterval(_ throttle: BlockRefresh) -> TimeInterval {
        BlockRefresh.nextRefreshInterval(base: lightInterval, consecutiveFailures: throttle.consecutiveFailures)
    }
    /// A mark in the future means the device clock moved back: treated as overdue.
    private static func isWithin(_ interval: TimeInterval, since mark: Date, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(mark)
        return elapsed >= 0 && elapsed < interval
    }
    private static func remaining(_ interval: TimeInterval, since mark: Date, now: Date) -> TimeInterval {
        let elapsed = now.timeIntervalSince(mark)
        return elapsed < 0 ? 0 : interval - elapsed
    }
}

extension BlockState {
    /// Changes the shown value in place (a runtime merge, a group edit); the kind of state, its time and reason stay.
    public func updatingValue(_ transform: (Value) -> Value) -> BlockState {
        switch self {
        case .loaded(let value, let at): .loaded(transform(value), at: at)
        case .loading(let previous?, let at): .loading(previous: transform(previous), at: at)
        case .failed(let reason, let previous?, let at): .failed(reason: reason, previous: transform(previous), at: at)
        case .idle, .disabled, .loading(nil, _), .failed(_, nil, _): self
        }
    }
}
