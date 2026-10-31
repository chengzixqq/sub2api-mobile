import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// S1-07: the home page's per-endpoint fallback (10 §1.2), read into the same models as dashboard/home.

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let newYork = ServerTimeZone(identifier: "America/New_York", utcOffset: "-04:00")!
private let gateway404 = APIError.server(status: 404, envelope: nil)
private let opsOff = APIError.server(status: 404, reason: "OPS_DISABLED")

private func at(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private func stats(requests: Int = 100, rpm: Double = 9, tpm: Double = 90, rpmAvailable: Bool? = nil, actual: Decimal? = 10,
                   account: Decimal? = 3, updatedAt: String? = nil, stale: Bool? = nil) -> DashboardStats {
    DashboardStats(todayRequests: requests, todayTokens: 2_000, todayCost: 15, totalUsers: 1, totalAccounts: 2, errorAccounts: 0, rpm: rpm, tpm: tpm,
                   todayActualCost: actual, todayAccountCost: account, rpmAvailable: rpmAvailable, statsUpdatedAt: updatedAt, statsStale: stale)
}
private func resolved(_ inputs: RatesInputs) -> (source: HomeRatesSource, rates: LiveRates?, error: (any Error)?)? {
    guard case .resolved(let outcome, let source) = HomeFallback.resolveRates(inputs) else { return nil }
    if case .failed(let error) = outcome { return (source, nil, error) }
    return (source, outcome.value, nil)
}
private func account(_ id: Int, status: String = "active", schedulable: Bool = true, groups: [Int] = [], overload: Date? = nil, rateLimit: Date? = nil,
                     temporary: Date? = nil, autoPause: Bool? = nil, expires: Int64? = nil) -> UpstreamAccount {
    UpstreamAccount(id: id, name: "账号 \(id)", platform: "openai", type: "apikey", status: status, schedulable: schedulable, expiresAt: expires,
                    groupIDs: groups, rateLimitResetAt: rateLimit.map(ServerTime.utcTimestamp), overloadUntil: overload.map(ServerTime.utcTimestamp),
                    tempUnschedulableUntil: temporary.map(ServerTime.utcTimestamp), autoPauseOnExpired: autoPause)
}
private func trendQuery(_ request: URLRequest?) -> [String: String] {
    let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
private func trendClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate, serverTimeZone: shanghai)
}

// MARK: rates

@Test func ratesFromOverviewUseWindowSeconds() {
    let start = at("2026-10-15T10:00:00Z"), end = at("2026-10-15T10:05:00Z")
    let overview = OpsOverview(startTime: start, endTime: end, errorRate: 0.0086, requestCountTotal: 230, tokenConsumed: 1_200_000,
                               upstream429Count: 3, upstream529Count: 1)
    #expect(HomeFallback.rates(fromOverview: overview) == LiveRates(rpm: 46, tpm: 240_000, errorRate: 0.0086, upstream429Count: 3, upstream529Count: 1,
                                                                    opsMonitoringEnabled: true, errorsAvailable: true, rpmIncludesErrors: true,
                                                                    startTime: start, endTime: end))
    let cut = HomeFallback.rates(fromOverview: OpsOverview(startTime: start, endTime: start.addingTimeInterval(290), requestCountTotal: 290, tokenConsumed: 29))
    #expect(cut.rpm == 60 && cut.tpm == 6)
}

@Test func ratesFromOverviewWithoutUsableWindowLeavesRatesMissing() {
    let start = at("2026-10-15T10:00:00Z")
    let missing = HomeFallback.rates(fromOverview: OpsOverview(errorRate: 0.01, requestCountTotal: 5, tokenConsumed: 5))
    #expect(missing.rpm == nil && missing.tpm == nil && missing.errorRate == 0.01)
    for end in [start, start.addingTimeInterval(-300)] {
        let rates = HomeFallback.rates(fromOverview: OpsOverview(startTime: start, endTime: end, requestCountTotal: 5, tokenConsumed: 5))
        #expect(rates.rpm == nil && rates.tpm == nil)
    }
}

@Test func ratesFromStatsHideUnavailableRPMAndExcludeCache() {
    let off = HomeFallback.rates(fromStats: stats(rpm: 12, tpm: 3_000, rpmAvailable: false))
    #expect(off.rpm == nil && off.tpm == 3_000 && off.errorRate == nil && off.upstream429Count == nil && off.upstream529Count == nil)
    #expect(off.opsMonitoringEnabled == false && off.errorsAvailable == false && off.rpmIncludesErrors == false)
    #expect(off.startTime == nil && off.endTime == nil)
    #expect(HomeFallback.rates(fromStats: stats(rpm: 12, rpmAvailable: nil)).rpm == 12)
    #expect(HomeFallback.rates(fromStats: stats(), opsMonitoringEnabled: nil).opsMonitoringEnabled == nil)
    #expect(HomeRatesSource.dashboardStats.tpmExcludesCache && !HomeRatesSource.opsOverview.tpmExcludesCache)
}

@Test func ratesResolutionWalksThreeLevels() {
    let start = at("2026-10-15T10:00:00Z")
    let overview = OpsOverview(startTime: start, endTime: start.addingTimeInterval(300), requestCountTotal: 30, tokenConsumed: 300)
    let legacy = stats(rpm: 9, tpm: 90, rpmAvailable: false)
    let server = APIError.server(status: 500, reason: nil)
    #expect(resolved(RatesInputs(hasDashboardRates: true)) == nil)
    #expect(resolved(RatesInputs(hasDashboardRates: true, dashboardRates: .success(LiveRates(rpm: 7))))?.rates == LiveRates(rpm: 7))
    #expect(resolved(RatesInputs(hasDashboardRates: true, dashboardRates: .success(LiveRates(rpm: 7))))?.source == .dashboardRates)
    #expect(resolved(RatesInputs(hasDashboardRates: true, dashboardRates: .failure(gateway404))) == nil)
    let second = resolved(RatesInputs(hasDashboardRates: true, dashboardRates: .failure(gateway404), opsOverview: .success(overview)))
    #expect(second?.source == .opsOverview && second?.rates?.rpm == 6 && second?.rates?.tpm == 60)
    let failedFirst = resolved(RatesInputs(hasDashboardRates: true, dashboardRates: .failure(server), opsOverview: .success(overview)))
    #expect(failedFirst?.source == .dashboardRates && (failedFirst?.error as? APIError)?.statusCode == 500)
    #expect(resolved(RatesInputs(hasDashboardRates: false, opsOverview: .failure(opsOff))) == nil)
    let third = resolved(RatesInputs(hasDashboardRates: false, opsOverview: .failure(opsOff), stats: .success(legacy)))
    #expect(third?.source == .dashboardStats && third?.rates?.rpm == nil && third?.rates?.tpm == 90 && third?.rates?.opsMonitoringEnabled == false)
    let noOps = resolved(RatesInputs(hasDashboardRates: false, opsOverview: .failure(gateway404), stats: .success(legacy)))
    #expect(noOps?.source == .dashboardStats && noOps?.rates?.tpm == 90 && noOps?.rates?.opsMonitoringEnabled == nil)
    let overviewFailed = resolved(RatesInputs(hasDashboardRates: false, opsOverview: .failure(server)))
    #expect(overviewFailed?.source == .opsOverview && overviewFailed?.error != nil)
    let statsFailed = resolved(RatesInputs(hasDashboardRates: false, opsOverview: .failure(opsOff), stats: .failure(server)))
    #expect(statsFailed?.source == .dashboardStats && statsFailed?.error != nil)
}

// MARK: stats

@Test func yesterdayWindowFollowsServerCalendar() {
    let now = at("2026-10-16T02:30:00Z")
    #expect(HomeFallback.yesterdayWindow(now: now, zone: shanghai, statsUpdatedAt: nil, statsStale: false)
            == DateInterval(start: at("2026-10-14T16:00:00Z"), end: at("2026-10-15T02:30:00Z")))
    // 22:30 on the 15th in New York: its yesterday began at 00:00 on the 14th there.
    #expect(HomeFallback.yesterdayWindow(now: now, zone: newYork, statsUpdatedAt: nil, statsStale: false)
            == DateInterval(start: at("2026-10-14T04:00:00Z"), end: at("2026-10-15T02:30:00Z")))
}

@Test func yesterdayWindowUsesUpdatedAtOnlyWhenStale() {
    let now = at("2026-10-16T02:30:00Z"), updated = at("2026-10-16T02:00:00Z")
    #expect(HomeFallback.yesterdayWindow(now: now, zone: shanghai, statsUpdatedAt: updated, statsStale: true)?.end == at("2026-10-15T02:00:00Z"))
    #expect(HomeFallback.yesterdayWindow(now: now, zone: shanghai, statsUpdatedAt: updated, statsStale: false)?.end == at("2026-10-15T02:30:00Z"))
    #expect(HomeFallback.yesterdayWindow(now: now, zone: shanghai, statsUpdatedAt: nil, statsStale: true)?.end == at("2026-10-15T02:30:00Z"))
}

@Test func yesterdayWindowClampsAndSkipsEmptyRange() {
    let now = at("2026-10-16T02:30:00Z"), midnight = at("2026-10-15T16:00:00Z")
    #expect(HomeFallback.yesterdayWindow(now: now, zone: shanghai, statsUpdatedAt: at("2026-10-15T10:00:00Z"), statsStale: true) == nil)
    #expect(HomeFallback.yesterdayWindow(now: midnight, zone: shanghai, statsUpdatedAt: nil, statsStale: false) == nil)
    #expect(HomeFallback.yesterdayWindow(now: now, zone: shanghai, statsUpdatedAt: at("2026-10-16T03:00:00Z"), statsStale: true)?.end
            == at("2026-10-15T02:30:00Z"))
}

@Test func yesterdaySameTimeSumsDayBuckets() throws {
    let until = at("2026-10-15T02:30:00Z"), exact = try #require(Decimal(string: "12.34567891"))
    let one = DashboardTrendReply(points: [TrendPoint(date: "2026-10-15", requests: 300, totalTokens: 1, cost: 20, actualCost: exact)],
                                  timeZone: shanghai.timeZone)
    #expect(HomeFallback.yesterdaySameTime(one, until: until) == YesterdaySameTime(actualCost: exact, requests: 300, until: until))
    let two = DashboardTrendReply(points: one.points + [TrendPoint(date: "2026-10-16", requests: 2, totalTokens: 1, cost: 1, actualCost: 1)],
                                  timeZone: shanghai.timeZone)
    #expect(HomeFallback.yesterdaySameTime(two, until: until) == YesterdaySameTime(actualCost: exact + 1, requests: 302, until: until))
    let none = HomeFallback.yesterdaySameTime(DashboardTrendReply(points: [], timeZone: shanghai.timeZone), until: until)
    #expect(none == YesterdaySameTime(actualCost: nil, requests: nil, until: until))
}

@Test func homeStatsReplacesCostsOnlyAsAPair() {
    let partial = stats(actual: 10, account: nil, updatedAt: "2026-10-16T02:00:00Z", stale: true)
    let snapshot = DashboardCostSnapshot(actual: 11, account: 4), until = at("2026-10-15T02:00:00Z")
    let yesterday = YesterdaySameTime(actualCost: 9, requests: 80, until: until)
    #expect(HomeFallback.homeStats(partial, snapshot: snapshot, yesterday: yesterday)
            == HomeStats(todayRequests: 100, todayTokens: 2_000, todayCost: 15, todayActualCost: 11, todayAccountCost: 4,
                         statsUpdatedAt: at("2026-10-16T02:00:00Z"), statsStale: true, yesterdaySameTimeActualCost: 9, yesterdaySameTimeRequests: 80,
                         yesterdaySameTimeUntil: until))
    let alone = HomeFallback.homeStats(partial, snapshot: nil, yesterday: nil)
    #expect(alone.todayActualCost == 10 && alone.todayAccountCost == nil && alone.yesterdaySameTimeActualCost == nil && alone.yesterdaySameTimeUntil == nil)
    let complete = HomeFallback.homeStats(stats(actual: 10, account: 3), snapshot: snapshot, yesterday: nil)
    #expect(complete.todayActualCost == 10 && complete.todayAccountCost == 3 && !complete.statsStale && complete.statsUpdatedAt == nil)
}

@Test func dashboardStatsDecodesFreshnessFieldsAndKeepsThemThroughJSON() throws {
    let legacyJSON = #"{"today_requests":1,"today_tokens":2,"today_cost":"3","total_users":4,"total_accounts":5,"error_accounts":0,"rpm":6,"tpm":7}"#
    let json = legacyJSON.dropLast() + #","stats_updated_at":"2026-10-16T02:00:00Z","stats_stale":true}"#
    let decoded = try JSONDecoder().decode(DashboardStats.self, from: Data(json.utf8))
    #expect(decoded.statsUpdatedAt == "2026-10-16T02:00:00Z" && decoded.statsStale == true)
    let again = try JSONDecoder().decode(DashboardStats.self, from: JSONEncoder().encode(decoded))
    #expect(again.statsUpdatedAt == "2026-10-16T02:00:00Z" && again.statsStale == true)
    let legacy = try JSONDecoder().decode(DashboardStats.self, from: Data(legacyJSON.utf8))
    #expect(legacy.statsUpdatedAt == nil && legacy.statsStale == nil)
}

// MARK: hourly, alerts, channels

@Test func hourlySplitsByServerDatePrefix() {
    func point(_ date: String, _ count: Int, actual: Decimal? = nil) -> TrendPoint {
        TrendPoint(date: date, requests: count, totalTokens: count * 10, cost: Decimal(count * 2), actualCost: actual ?? Decimal(count))
    }
    let reply = DashboardTrendReply(points: [point("2026-10-16 00:00", 3), point("2026-10-15 23:00", 2), point("2026-10-15 01:00", 1),
                                             point("2026-10-14 23:00", 9), TrendPoint(date: "2026-10-16 01:00", requests: 4, totalTokens: 0, cost: 1)],
                                    timeZone: shanghai.timeZone)
    let hourly = HomeFallback.hourly(reply, now: at("2026-10-15T17:30:00Z"))
    #expect(hourly.timezone == "Asia/Shanghai")
    #expect(hourly.today == [HomeHourlyPoint(date: "2026-10-16 00:00", requests: 3, totalTokens: 30, actualCost: 3),
                             HomeHourlyPoint(date: "2026-10-16 01:00", requests: 4, totalTokens: 0, actualCost: 0)])
    #expect(hourly.yesterday.map(\.date) == ["2026-10-15 01:00", "2026-10-15 23:00"] && hourly.yesterday.allSatisfy { $0.accountCost == nil })
}

@Test func homeAlertsKeepCountsAndTheNewestFiveFiring() {
    let now = at("2026-10-16T02:30:00Z")
    let ages: [(id: Int, severity: String, seconds: TimeInterval)] = [(1, "P0", 600), (2, "P1", 300), (3, "P1", 300), (4, " p2", 900), (5, "P3", 100),
                                                                       (6, "P3", 1_200), (7, "X", 50)]
    let firing = ages.map { AlertEvent(id: $0.id, severity: $0.severity, status: "firing", firedAt: now.addingTimeInterval(-$0.seconds)) }
    let ended = AlertEvent(id: 8, severity: "P0", status: "resolved", firedAt: now.addingTimeInterval(-10))
    let counted = AlertCounts.counting(firing + [ended])
    #expect(counted.firing == 7 && counted.count(severity: "P0") == 1 && counted.count(severity: "P1") == 2 && counted.count(severity: "P2") == 1)
    #expect(counted.count(severity: "P3") == 2)
    let alerts = HomeFallback.homeAlerts(counts: AlertCounts(firing: 9, bySeverity: ["P1": 9]), firing: firing + [ended])
    #expect(alerts.firingCount == 9 && alerts.count(severity: "P1") == 9 && alerts.top.map(\.id) == [7, 5, 3, 2, 1])
}

@Test func homeChannelsCountFourBuckets() {
    let states = ["healthy", "warning", "critical", "unknown", "stale", ""]
    let overview = ChannelOverview(coverage: ChannelCoverage(state: "complete", collectorState: "healthy"),
                                   items: states.enumerated().map { ChannelItem(groupID: $0.offset + 1, currentStatus: ChannelCurrentStatus(state: $0.element)) })
    #expect(HomeFallback.homeChannels(overview) == HomeChannels(total: 6, healthy: 1, warning: 1, critical: 1, unknown: 3, coverageState: "complete",
                                                                collectorState: "healthy"))
    #expect(HomeFallback.homeChannels(ChannelOverview()) == HomeChannels())
}

@Test func homeOpsTakesTheOverviewFigures() {
    let overview = OpsOverview(healthScore: 94, sla: 0.992, errorRate: 0.008, requestCountTotal: 230, tokenConsumed: 1_200_000, upstream429Count: 12,
                               upstream529Count: 3)
    #expect(HomeFallback.homeOps(overview) == HomeOps(healthScore: 94, sla: 0.992, errorRate: 0.008, upstream429Count: 12, upstream529Count: 3,
                                                      requestCountTotal: 230, tokenConsumed: 1_200_000))
}

// MARK: availability

@Test func localAvailabilityMatchesD02ForEveryState() {
    let now = at("2026-10-16T02:30:00Z"), later = now.addingTimeInterval(600)
    let accounts = [account(1, status: "error", schedulable: false), account(2, status: "disabled"), account(3, overload: later),
                    account(4, rateLimit: later), account(5, temporary: later), account(6, schedulable: false),
                    account(7, autoPause: true, expires: Int64(now.timeIntervalSince1970) - 60), account(8), account(9, overload: now)]
    let summary = HomeFallback.localAvailability(groups: [], accounts: accounts, accountsComplete: true, now: now)
    #expect(summary.totals == AccountStateCounts(total: 9, available: 2, error: 1, overloaded: 1, rateLimited: 1, tempUnschedulable: 1, paused: 2, inactive: 1))
    #expect(summary.accounts.map(\.id) == [1, 3, 4, 5] && !summary.accountsTruncated && summary.collectedAt == now && summary.platforms.isEmpty)
    for item in summary.accounts {
        let source = accounts.first { $0.id == item.id }!
        #expect(item.state == AccountDisplayState.scheduleState(AccountStateInput(source), now: now))
    }
    #expect(summary.accounts.first { $0.id == 4 }?.rateLimitResetAt == later)
}

@Test func localAvailabilityCountsStoppedAndMultiGroupAccounts() {
    let now = at("2026-10-16T02:30:00Z")
    let groups = [AdminGroup(id: 1, name: "甲"), AdminGroup(id: 2, name: "乙")]
    let accounts = [account(1, schedulable: false, groups: [1], overload: now.addingTimeInterval(60)), account(2, status: "error", groups: [1, 2])]
    let summary = HomeFallback.localAvailability(groups: groups, accounts: accounts, accountsComplete: true, now: now)
    #expect(summary.totals.overloaded == 1 && summary.totals.stopped == 1 && summary.totals.error == 1 && summary.totals.total == 2)
    #expect(summary.accounts.first { $0.id == 1 }?.stopped == true && summary.accounts.first { $0.id == 2 }?.stopped == false)
    #expect(summary.groups.map(\.counts.error) == [1, 1] && summary.groups.map(\.counts.stopped) == [1, 0])
}

@Test func localAvailabilityGroupTotalsComeFromGroupFields() {
    let now = at("2026-10-16T02:30:00Z")
    let groups = [AdminGroup(id: 4, name: "停用有账号", status: "inactive"), AdminGroup(id: 3, name: "停用无账号", status: "inactive"),
                  AdminGroup(id: 2, name: "无计数"), AdminGroup(id: 1, name: "标准组", platform: "openai", accountCount: 4, activeAccountCount: 1)]
    let accounts = [account(1, status: "error", groups: [1]), account(2, groups: [1]), account(3, groups: [4])]
    let summary = HomeFallback.localAvailability(groups: groups, accounts: accounts, accountsComplete: true, now: now)
    #expect(summary.groups.map(\.groupID) == [1, 2, 4])
    let standard = summary.groups[0]
    #expect(standard.groupName == "标准组" && standard.platform == "openai" && standard.groupStatus == "active")
    #expect(standard.counts == AccountStateCounts(total: 4, available: 1, error: 1))
    #expect(summary.groups[1].counts == AccountStateCounts() && summary.groups[2].groupStatus == "inactive")
}

@Test func shortageFollowsBackendDefault() {
    #expect(HomeFallback.shortage(available: 0, total: 2) == .init(isShort: true, source: "default", threshold: 0.5, current: 0))
    #expect(HomeFallback.shortage(available: 1, total: 3).isShort && HomeFallback.shortage(available: 1, total: 3).current == 1.0 / 3)
    #expect(!HomeFallback.shortage(available: 2, total: 4).isShort && HomeFallback.shortage(available: 2, total: 4).current == 0.5)
    #expect(HomeFallback.shortage(available: 0, total: 0) == .init(isShort: true, source: "default", threshold: 0.5, current: 0))
}

@Test func availabilityAccountsKeepOnlyAbnormalUpTo100() {
    let mixed = AccountStatusSummary(totals: AccountStateCounts(total: 4, available: 1, error: 1, paused: 1, inactive: 1),
                                     accounts: [AccountStatusItem(id: 1, state: .available), AccountStatusItem(id: 2, state: .paused),
                                                AccountStatusItem(id: 3, state: .inactive), AccountStatusItem(id: 4, state: .error), AccountStatusItem(id: 5)])
    let trimmed = HomeFallback.homeAvailability(mixed)
    #expect(trimmed.accounts.map(\.id) == [4] && trimmed.totals == mixed.totals && !trimmed.accountsTruncated)
    let many = AccountStatusSummary(accounts: (1...101).map { AccountStatusItem(id: $0, state: .error) })
    #expect(HomeFallback.homeAvailability(many).accounts.count == 100 && HomeFallback.homeAvailability(many).accountsTruncated)
    let now = at("2026-10-16T02:30:00Z")
    #expect(HomeFallback.localAvailability(groups: [], accounts: [account(1)], accountsComplete: false, now: now).accountsTruncated)
}

// MARK: 触发与归类

@Test func fallbackTriggerAndDisabledClassification() {
    let jsonNotFound = APIError.server(status: 404, reason: "NOT_FOUND"), offline = APIError.transport(URLError(.notConnectedToInternet))
    for error in [jsonNotFound, gateway404, offline] { #expect(HomeFallback.shouldFallBack(afterHomeError: error)) }
    let staying: [any Error] = [APIError.server(status: 500, reason: nil), APIError.server(status: 503, reason: nil), APIError.server(status: 429, reason: nil),
                                APIError.server(status: 401, reason: nil), APIError.server(status: 423, reason: nil), APIError.refreshDeferred,
                                CancellationError(), APIError(kind: .validation, message: "无效")]
    for error in staying { #expect(!HomeFallback.shouldFallBack(afterHomeError: error)) }
    #expect(HomeFallback.isMissingEndpoint(jsonNotFound) && HomeFallback.isMissingEndpoint(gateway404) && !HomeFallback.isMissingEndpoint(offline))
    #expect(HomeFallback.disabledReason(opsOff) == "OPS_DISABLED")
    #expect(HomeFallback.disabledReason(APIError.server(status: 403, reason: "CHANNEL_MONITOR_DISABLED")) == "CHANNEL_MONITOR_DISABLED")
    #expect(HomeFallback.disabledReason(jsonNotFound) == nil && HomeFallback.disabledReason(APIError.server(status: 403, reason: "FORBIDDEN")) == nil)
    let missing: Result<Int, any Error> = .failure(gateway404)
    #expect(HomeFallback.outcome(missing, unsupportedAsDisabled: true).disabledReason == "UNSUPPORTED")
    #expect(HomeFallback.outcome(missing).disabledReason == nil && HomeFallback.outcome(missing).value == nil)
    #expect(HomeFallback.outcome(Result<Int, any Error>.failure(opsOff)).disabledReason == "OPS_DISABLED")
    #expect(HomeFallback.outcome(Result<Int, any Error>.success(3)).value == 3)
    #expect(HomeFallback.isTimeout(APIError.transport(URLError(.timedOut))) && HomeFallback.isTimeout(APIError.server(status: 504, reason: nil)))
    #expect(!HomeFallback.isTimeout(offline) && !HomeFallback.isTimeout(jsonNotFound))
}

@Test func legacyDetailsFillRuleAndGroupNameOnlyWhereMissing() {
    let rule = AlertEventRule(id: 11, name: "标准组错误率"), firedAt = at("2026-10-16T02:00:00Z")
    let bare = AlertEvent(id: 1, ruleID: 11, severity: "P1", status: "firing", groupID: 2, firedAt: firedAt)
    let filled = HomeFallback.fillingLegacyDetails(bare, rules: [11: rule], groupNames: [2: "标准组"])
    #expect(filled.rule == rule && filled.groupName == "标准组" && filled.cursor == bare.cursor && filled.id == 1)
    let own = AlertEvent(id: 2, ruleID: 11, severity: "P1", status: "firing", groupID: 2, firedAt: firedAt, rule: AlertEventRule(id: 11, name: "原规则"),
                         groupName: "原名")
    #expect(HomeFallback.fillingLegacyDetails(own, rules: [11: rule], groupNames: [2: "标准组"]) == own)
    #expect(HomeFallback.fillingLegacyDetails(bare, rules: [:], groupNames: [:]) == bare)
}

// MARK: dashboard/trend 显式范围

@Test func explicitTrendSendsUTCInstantsGranularityAndServerZone() async throws {
    let body = #"{"trend":[{"date":"2026-10-15","requests":300,"total_tokens":1,"cost":"2","actual_cost":"1.5"}],"query":{"timezone":"Asia/Tokyo"}}"#
    let transport = ScriptedTransport { _ in okReply(body) }
    let reply = try await trendClient(transport).dashboardTrend(start: at("2026-10-14T16:00:00Z"), end: at("2026-10-15T02:30:00Z"), granularity: .day)
    let sent = await transport.requests
    #expect(sent.count == 1 && sent[0].url?.path == "/api/v1/admin/dashboard/trend" && sent[0].timeoutInterval == RequestTimeout.aggregate)
    #expect(trendQuery(sent.first) == ["start_time": "2026-10-14T16:00:00Z", "end_time": "2026-10-15T02:30:00Z", "granularity": "day",
                                       "timezone": "Asia/Shanghai"])
    #expect(reply.points.map(\.requests) == [300] && reply.points.first?.actualCost == Decimal(string: "1.5") && reply.timeZone.identifier == "Asia/Tokyo")
    let empty = try await trendClient(ScriptedTransport { _ in okReply(#"{"query":{"timezone":""}}"#) })
        .dashboardTrend(start: at("2026-10-15T00:00:00Z"), end: at("2026-10-15T01:00:00Z"), granularity: .hour)
    #expect(empty.points.isEmpty && empty.timeZone.identifier == "Asia/Shanghai")
}

@Test func explicitTrendRejectsEmptyRangeAndLateReply() async {
    let transport = ScriptedTransport { _ in okReply(#"{"trend":[]}"#) }
    let client = trendClient(transport), moment = at("2026-10-15T02:30:00Z")
    #expect(await thrownAPIError { _ = try await client.dashboardTrend(start: moment, end: moment, granularity: .hour) }?.kind == .validation)
    #expect(await thrownAPIError { _ = try await client.dashboardTrend(start: moment, end: moment.addingTimeInterval(-1), granularity: .day) }?.kind == .validation)
    #expect(await transport.requests.isEmpty)
    let started = OpenGate(), release = OpenGate()
    let slow = trendClient(ScriptedTransport { _ in
        await started.open(); await release.wait()
        return okReply(#"{"trend":[]}"#)
    })
    let pending = Task { try await slow.dashboardTrend(start: moment, end: moment.addingTimeInterval(60), granularity: .hour) }
    let watcher = Task { _ = try? await pending.value; await started.open() }
    await started.wait(); await slow.cancelAll(); await release.open()
    _ = await watcher.value
    await #expect(throws: CancellationError.self) { _ = try await pending.value }
}
