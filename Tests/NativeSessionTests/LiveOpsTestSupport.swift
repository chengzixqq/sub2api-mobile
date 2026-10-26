import Foundation
import Synchronization
import Sub2Core
@testable import NativeSessionSupport

// S1D1-06: StubLiveOpsSource is the only LiveOpsSource stand-in in this target. Whoever adds a LiveOpsSource method adds it here,
// to ClientLiveOpsSource and to FixtureLiveOpsSource in the same commit (otherwise NativeSessionTests stops compiling); never
// write `extension LiveOpsSource` default implementations in the test target.

struct StubMissing: Error {}

/// Records every call; a method without a handler throws StubMissing.
actor StubLiveOpsSource: LiveOpsSource {
    enum Call: Equatable, Sendable {
        case home(noCache: Bool), rates(LiveRatesWindow), overview(start: Date, end: Date), overviewRange(String), errorAccounts
        case ranking(limit: Int, timezone: String), summary, alertEvents(status: String?, limit: Int), alertCounts, alertEvent(Int)
        case alertRules, channels(range: String, refresh: Bool), monitoringStatus
        case setAlertStatus(Int, String), createSilence(rule: Int, until: Date), updateSilence(Int, Date), deleteSilence(Int)
    }
    struct Handlers: Sendable {
        var home: (@Sendable (_ noCache: Bool) async throws -> DashboardHome)?
        var rates: (@Sendable () async throws -> LiveRates)?
        var overview: (@Sendable (_ start: Date, _ end: Date) async throws -> OpsOverview)?
        var errorAccounts: (@Sendable () async throws -> [UpstreamAccount])?
        var ranking: (@Sendable () async throws -> [AccountsRankingItem])?
        var summary: (@Sendable () async throws -> AccountStatusSummary)?
        var alertEvents: (@Sendable (_ status: String?, _ limit: Int) async throws -> [AlertEvent])?
        var alertCounts: (@Sendable () async throws -> AlertCounts)?
        var alertEvent: (@Sendable (Int) async throws -> AlertEvent)?
        var alertRules: (@Sendable () async throws -> [AlertEventRule])?
        var channels: (@Sendable () async throws -> ChannelOverview)?
        var monitoringStatus: (@Sendable () async throws -> OpsMonitoringStatus)?
        var setAlertStatus: (@Sendable (Int, String) async throws -> Void)?
        var createSilence: (@Sendable (Int, Date) async throws -> AlertSilence)?
        var updateSilence: (@Sendable (Int, Date) async throws -> AlertSilence)?
        var deleteSilence: (@Sendable (Int) async throws -> Void)?
    }
    private var handlers: Handlers
    private(set) var calls: [Call] = []

    init(_ handlers: Handlers = Handlers()) { self.handlers = handlers }
    func update(_ change: @Sendable (inout Handlers) -> Void) { change(&handlers) }
    func count(_ matches: @Sendable (Call) -> Bool) -> Int { calls.filter(matches).count }
    var homeCalls: [Bool] { calls.compactMap { if case .home(let noCache) = $0 { noCache } else { nil } } }

    func dashboardHome(timezone: ServerTimeZone, include: [HomeSectionKey]?, noCache: Bool) async throws -> DashboardHome {
        calls.append(.home(noCache: noCache))
        guard let handler = handlers.home else { throw StubMissing() }
        return try await handler(noCache)
    }
    func dashboardRates(window: LiveRatesWindow) async throws -> LiveRates {
        calls.append(.rates(window))
        guard let handler = handlers.rates else { throw StubMissing() }
        return try await handler()
    }
    func opsOverview(start: Date, end: Date) async throws -> OpsOverview {
        calls.append(.overview(start: start, end: end))
        guard let handler = handlers.overview else { throw StubMissing() }
        return try await handler(start, end)
    }
    func opsOverview(timeRange: String) async throws -> OpsOverview {
        calls.append(.overviewRange(timeRange))
        guard let handler = handlers.overview else { throw StubMissing() }
        let end = Date()
        return try await handler(end.addingTimeInterval(-300), end)
    }
    func errorAccounts() async throws -> [UpstreamAccount] {
        calls.append(.errorAccounts)
        guard let handler = handlers.errorAccounts else { throw StubMissing() }
        return try await handler()
    }
    func accountsRanking(limit: Int, timezone: ServerTimeZone) async throws -> [AccountsRankingItem] {
        calls.append(.ranking(limit: limit, timezone: timezone.identifier))
        guard let handler = handlers.ranking else { throw StubMissing() }
        return try await handler()
    }
    func accountStatusSummary(platform: String?, groupID: Int?, includeAccounts: Bool) async throws -> AccountStatusSummary {
        calls.append(.summary)
        guard let handler = handlers.summary else { throw StubMissing() }
        return try await handler()
    }
    func alertEvents(status: String?, timeRange: String?, limit: Int, before: AlertEventCursor?, groupID: Int?,
                     platform: String?) async throws -> [AlertEvent] {
        calls.append(.alertEvents(status: status, limit: limit))
        guard let handler = handlers.alertEvents else { throw StubMissing() }
        return try await handler(status, limit)
    }
    func alertEventCounts() async throws -> AlertCounts {
        calls.append(.alertCounts)
        guard let handler = handlers.alertCounts else { throw StubMissing() }
        return try await handler()
    }
    func alertEvent(id: Int) async throws -> AlertEvent {
        calls.append(.alertEvent(id))
        guard let handler = handlers.alertEvent else { throw StubMissing() }
        return try await handler(id)
    }
    func alertRules() async throws -> [AlertEventRule] {
        calls.append(.alertRules)
        guard let handler = handlers.alertRules else { throw StubMissing() }
        return try await handler()
    }
    func channelOverview(range: String, refresh: Bool) async throws -> ChannelOverview {
        calls.append(.channels(range: range, refresh: refresh))
        guard let handler = handlers.channels else { throw StubMissing() }
        return try await handler()
    }
    func opsMonitoringStatus() async throws -> OpsMonitoringStatus {
        calls.append(.monitoringStatus)
        guard let handler = handlers.monitoringStatus else { throw StubMissing() }
        return try await handler()
    }
    func setAlertEventStatus(id: Int, status: String) async throws {
        calls.append(.setAlertStatus(id, status))
        guard let handler = handlers.setAlertStatus else { throw StubMissing() }
        try await handler(id, status)
    }
    func createAlertSilence(ruleID: Int, platform: String?, groupID: Int?, until: Date) async throws -> AlertSilence {
        calls.append(.createSilence(rule: ruleID, until: until))
        guard let handler = handlers.createSilence else { throw StubMissing() }
        return try await handler(ruleID, until)
    }
    func updateAlertSilence(id: Int, until: Date) async throws -> AlertSilence {
        calls.append(.updateSilence(id, until))
        guard let handler = handlers.updateSilence else { throw StubMissing() }
        return try await handler(id, until)
    }
    func deleteAlertSilence(id: Int) async throws {
        calls.append(.deleteSilence(id))
        guard let handler = handlers.deleteSilence else { throw StubMissing() }
        try await handler(id)
    }
}

/// Records the polling waits in seconds and ends the loop at the `stopAfter`-th one, as a cancelled task would. With `parks`
/// a wait holds until `releaseAll()`; it ignores task cancellation, so such a test ends its polling with `stop()`.
actor PollSleeper {
    private(set) var seconds: [TimeInterval] = []
    private let limit: Int
    private let parks: Bool
    private var isStopped = false
    private var parked: [CheckedContinuation<Void, any Error>] = []
    init(stopAfter limit: Int = .max, parks: Bool = false) { self.limit = limit; self.parks = parks }
    var parkedCount: Int { parked.count }
    func sleep(_ duration: Duration) async throws {
        let parts = duration.components
        seconds.append(TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18)
        if isStopped || seconds.count >= limit { throw CancellationError() }
        guard parks else { return }
        try await withCheckedThrowingContinuation { parked.append($0) }
    }
    func releaseAll() { resumeParked(with: .success(())) }
    func stop() {
        isStopped = true
        resumeParked(with: .failure(CancellationError()))
    }
    private func resumeParked(with result: Result<Void, any Error>) {
        let waiting = parked
        parked.removeAll()
        waiting.forEach { $0.resume(with: result) }
    }
}

@MainActor final class TestSwitch { var isOn = true }
@MainActor final class TestCounter { var count = 0 }
/// Counts calls from any isolation, for handlers whose answer depends on how often they ran.
final class Tally: Sendable {
    private let value = Mutex(0)
    func next() -> Int { value.withLock { $0 += 1; return $0 } }
}

let liveOpsZone = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
let liveOpsCapabilities: [Capability] = [.dashboardHome, .accountsStructuredError, .dashboardAccountsRanking, .opsAlertEventCounts]

/// A connected site in Asia/Shanghai with `capabilities`; `opsEnabled` is `/admin/me` `features.ops_monitoring_enabled`.
func liveOpsSite(_ capabilities: [Capability] = liveOpsCapabilities, opsEnabled: Bool? = true) -> SiteSession {
    let me = AdminMe(user: .init(id: 1, role: "admin"), features: .init(opsMonitoringEnabled: opsEnabled),
                     server: .init(serverTimezone: liveOpsZone.identifier, serverUTCOffset: liveOpsZone.rawUTCOffset,
                                   capabilities: Set(capabilities.map(\.rawValue))))
    return SiteSession(me: me, credential: sessionTokens(), accessTokenScope: nil, serverTimeZone: liveOpsZone, clockOffset: 0, probedAt: Date())
}

/// One store over a stub, with the session flag, the device clock, the site and the badge its closures read.
@MainActor final class LiveOpsHarness {
    @MainActor final class Context {
        var isCurrent = true
        var localNow = Date()
        var site: SiteSession?
        let badge = AccountErrorBadge()
        init(site: SiteSession?) { self.site = site }
    }
    let context: Context
    let source: StubLiveOpsSource
    let sleeper: PollSleeper
    let store: LiveOpsStore

    init(_ source: StubLiveOpsSource = StubLiveOpsSource(), site: SiteSession? = liveOpsSite(), serverNow: Date = Date(),
         sleeper: PollSleeper = PollSleeper()) {
        let context = Context(site: site)
        self.context = context; self.source = source; self.sleeper = sleeper
        store = LiveOpsStore(generation: UUID(), source: source, site: { context.site }, isCurrent: { context.isCurrent },
                             errorBadge: { context.badge }, serverNow: { serverNow }, localNow: { context.localNow },
                             sleep: { try await sleeper.sleep($0) })
    }
    var isCurrent: Bool {
        get { context.isCurrent }
        set { context.isCurrent = newValue }
    }
    var site: SiteSession? { context.site }
    var badge: AccountErrorBadge { context.badge }
    func advance(by seconds: TimeInterval) { context.localNow = context.localNow.addingTimeInterval(seconds) }
}

/// Every block ok unless replaced.
func homeReply(stats: HomeSection<HomeStats> = .ok(HomeStats(todayRequests: 1)), rates: HomeSection<LiveRates> = .ok(LiveRates(rpm: 1)),
               hourly: HomeSection<HomeHourly> = .ok(HomeHourly()), ops: HomeSection<HomeOps> = .ok(HomeOps(healthScore: 90)),
               alerts: HomeSection<HomeAlerts> = .ok(HomeAlerts()), availability: HomeSection<AccountStatusSummary> = .ok(AccountStatusSummary()),
               channels: HomeSection<HomeChannels> = .ok(HomeChannels())) -> DashboardHome {
    DashboardHome(stats: stats, rates: rates, hourly: hourly, ops: ops, alerts: alerts, availability: availability, channels: channels)
}
/// An availability block with these error accounts (and their count in the totals).
func errorSummary(_ ids: [Int]) -> AccountStatusSummary {
    AccountStatusSummary(totals: AccountStateCounts(total: ids.count + 1, available: 1, error: ids.count),
                         accounts: ids.map { AccountStatusItem(id: $0, name: "账号 \($0)", state: .error, status: "error", schedulable: false) })
}
func structuredAccount(_ id: Int, summary: String = "401 凭据已失效") -> UpstreamAccount {
    UpstreamAccount(id: id, name: "账号 \(id)", platform: "openai", type: "apikey", status: "error", errorSummary: summary)
}
func firingEvent(_ id: Int, severity: String = "P1", platform: String? = nil) -> AlertEvent {
    AlertEvent(id: id, ruleID: id, severity: severity, status: "firing", platform: platform, firedAt: Date().addingTimeInterval(-600))
}
let opsDisabledError = APIError.server(status: 404, reason: "OPS_DISABLED")

/// Lets tasks started by the store run until `done` holds.
@MainActor func waitUntil(_ done: @MainActor () async -> Bool) async {
    var spins = 0
    while await !done(), spins < 10_000 { await Task.yield(); spins += 1 }
}
