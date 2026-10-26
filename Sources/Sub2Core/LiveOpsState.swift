import Foundation

// S1-05: the pure parts of LiveOpsStore (10 §0.5, §1.5, §7.1). The store keeps one HomeBlocks; every other file writes it
// through `LiveOpsStore.replaceHome(_:)`.

/// 10 §1.5 block titles. BlockState has no timeout case, so “加载超时” is a failure whose reason is `timedOut`.
public enum HomeBlockText {
    public static let failed = "加载失败"
    public static let timedOut = "加载超时"
}

extension HomeSection {
    /// 10 §1.5: ok takes the new value at the local receive time; disabled keeps its reason and no value; error and timeout keep
    /// the previous value and mark it.
    public func blockState(after previous: BlockState<Value>, receivedAt: Date) -> BlockState<Value> {
        switch status {
        case .ok: data.map { .loaded($0, at: receivedAt) } ?? previous.withFailure(HomeBlockText.failed)
        case .disabled: .disabled(reason: reason ?? "")
        case .error: previous.withFailure(HomeBlockText.failed)
        case .timeout: previous.withFailure(HomeBlockText.timedOut)
        }
    }
}

/// The seven home blocks (S1D1-03): `home.channels` holds the four channel counts, not the monitor's channel list.
public struct HomeBlocks: Sendable, Equatable {
    public var stats: BlockState<HomeStats> = .idle
    public var rates: BlockState<LiveRates> = .idle
    public var hourly: BlockState<HomeHourly> = .idle
    public var ops: BlockState<HomeOps> = .idle
    public var alerts: BlockState<HomeAlerts> = .idle
    public var availability: BlockState<AccountStatusSummary> = .idle
    public var channels: BlockState<HomeChannels> = .idle
    /// The last reply without an error or timeout block, at the local receive time (S0-05; generated_at is stale in a 304).
    public var lastFullSuccessAt: Date?

    public init() {}

    public func merging(_ home: DashboardHome, receivedAt: Date) -> HomeBlocks {
        var next = self
        next.stats = home.stats.blockState(after: stats, receivedAt: receivedAt)
        next.rates = home.rates.blockState(after: rates, receivedAt: receivedAt)
        next.hourly = home.hourly.blockState(after: hourly, receivedAt: receivedAt)
        next.ops = home.ops.blockState(after: ops, receivedAt: receivedAt)
        next.alerts = home.alerts.blockState(after: alerts, receivedAt: receivedAt)
        next.availability = home.availability.blockState(after: availability, receivedAt: receivedAt)
        next.channels = home.channels.blockState(after: channels, receivedAt: receivedAt)
        if home.degradedSections().isEmpty { next.lastFullSuccessAt = receivedAt }
        return next
    }
    /// The subtitle's “部分数据未更新”.
    public var hasFailedBlock: Bool {
        [stats.failureReason, rates.failureReason, hourly.failureReason, ops.failureReason, alerts.failureReason,
         availability.failureReason, channels.failureReason].contains { $0 != nil }
    }
}

extension DashboardHome {
    /// 10 §7.2 from one reply (S1D1-02): true when ops or alerts is disabled or rates say monitoring is off; false when the server
    /// answered ops or alerts (a timed-out or failed ops block still ran); nil when nothing here tells.
    public var opsDisabledEvidence: Bool? {
        if ops.status == .disabled || alerts.status == .disabled || rates.data?.opsMonitoringEnabled == false { return true }
        let opsRan = ops.status == .ok || (ops.reason != nil && [.error, .timeout].contains(ops.status))
        if opsRan || alerts.status == .ok || rates.data?.opsMonitoringEnabled == true { return false }
        return nil
    }
}

extension AccountStatusSummary {
    /// The error accounts' ids in the server's order; `errorAccounts()` fills in their structured fields.
    public var errorAccountIDs: [Int] { accounts.filter { $0.state == .error }.map(\.id) }
    /// Only this summary's error accounts, in its order.
    public func aligningStructuredErrors(_ fetched: [UpstreamAccount]) -> [UpstreamAccount] {
        let byID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return errorAccountIDs.compactMap { byID[$0] }
    }
}

extension AlertCounts {
    /// 10 §0.2 without `ops.alert_event_counts`: the firing events of a list, silenced ones included (S1D1-23).
    public static func counting(_ events: [AlertEvent]) -> AlertCounts {
        let firing = events.filter(\.isFiring)
        return AlertCounts(firing: firing.count, bySeverity: Dictionary(firing.map { ($0.severity, 1) }, uniquingKeysWith: +))
    }
    /// One firing event of `severity` resolved here; never below zero.
    public func removingFiring(severity: String) -> AlertCounts {
        let key = AlertCounts.normalized(severity)
        var levels = bySeverity
        if let count = levels[key] { levels[key] = max(0, count - 1) }
        return AlertCounts(firing: max(0, firing - 1), bySeverity: levels)
    }
    static func normalized(_ severity: String) -> String { severity.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
}

extension HomeAlerts {
    /// 10 §1.4: a resolved event leaves the list and the counts at once, even when it was not among the five listed.
    public func removingFiring(_ event: AlertEvent) -> HomeAlerts {
        let key = AlertCounts.normalized(event.severity)
        let levels = Dictionary(uniqueKeysWithValues: bySeverity.map { name, count in
            (name, AlertCounts.normalized(name) == key ? max(0, count - 1) : count)
        })
        return HomeAlerts(firingCount: max(0, firingCount - 1), bySeverity: levels, top: top.filter { $0.id != event.id })
    }
    public func mapEvents(_ transform: (AlertEvent) -> AlertEvent) -> HomeAlerts {
        HomeAlerts(firingCount: firingCount, bySeverity: bySeverity, top: top.map(transform))
    }
}

/// 10 §6.2 最近结束 (S1D1-17): ended events only, newest first (`fired_at DESC, id DESC`), each id once. `cursor` is the last
/// event of the last page as the server sent it; nil means there is nothing older.
public struct RecentAlerts: Sendable, Equatable {
    public let events: [AlertEvent]
    public let cursor: AlertEventCursor?

    public init(events: [AlertEvent] = [], cursor: AlertEventCursor? = nil) {
        var seen = Set<Int>()
        self.events = events.filter { !$0.isFiring && seen.insert($0.id).inserted }.sorted(by: Self.isNewer)
        self.cursor = cursor
    }
    /// `raw` is one `alert-events?time_range=24h` page; a full page may have older events after it.
    public static func firstPage(_ raw: [AlertEvent], limit: Int) -> RecentAlerts {
        RecentAlerts(events: raw, cursor: raw.count >= limit ? raw.last?.cursor : nil)
    }
    /// Inserts or replaces in order; an event that is firing again leaves the list.
    public func upserting(_ event: AlertEvent) -> RecentAlerts {
        RecentAlerts(events: [event] + events.filter { $0.id != event.id }, cursor: cursor)
    }
    public func removing(eventID: Int) -> RecentAlerts { RecentAlerts(events: events.filter { $0.id != eventID }, cursor: cursor) }
    public func mapEvents(_ transform: (AlertEvent) -> AlertEvent) -> RecentAlerts { RecentAlerts(events: events.map(transform), cursor: cursor) }

    /// Events without a fire time go last.
    private static func isNewer(_ a: AlertEvent, _ b: AlertEvent) -> Bool {
        switch (a.cursor, b.cursor) {
        case let (left?, right?): right < left
        case (.some, nil): true
        case (nil, .some): false
        case (nil, nil): a.id > b.id
        }
    }
}
