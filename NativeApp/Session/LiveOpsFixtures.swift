import Foundation
import Sub2Core

/// S1D1-11: stage 1's fixture ids, the only source; UI tests copy the literals with a “来源 LiveOpsFixtureIDs” note. Accounts and
/// groups are AccountDemoStore's (DemoData+Accounts.swift): same id, name and platform.
enum LiveOpsFixtureIDs {
    /// P1, group 2 “标准组”, error_rate, not silenced.
    static let alertA = 41
    /// X28: S2-22's group header alert (P2, platform anthropic, silenced as 501). Later items use it and never change it.
    static let anthropicFiringEventID = 40
    static let endedResolved = 37
    static let endedManual = 35
    static let anthropicSilence = 501
    static let errorAccount = 7
    static let overloadedAccount = 11
    static let rateLimitedAccount = 3
    static let tempUnschedulableAccount = 12
    /// “企业专线”, 0 of 1 available.
    static let shortageGroup = 4
    static let standardGroup = 2
    static let premiumGroup = 1
}

/// S1-08: the ops switch a `-ui-testing` site starts with. `-ui-ops-disabled` is setting_off (the App can turn it on),
/// `-ui-ops-config-off` config_off (409 OPS_CONFIG_DISABLED, no button) and wins when both are given. DemoData.adminMe and
/// FixtureLiveOpsSource read the same value; stage 4 (S4-05, S4-16, S4-18) reuses these two arguments.
enum OpsFixtureSwitch: String, Sendable, Equatable {
    case on, settingOff = "setting_off", configOff = "config_off"

    static func from(arguments: [String]) -> OpsFixtureSwitch {
        if arguments.contains(LiveOpsFixtures.Argument.opsConfigOff) { return .configOff }
        return arguments.contains(LiveOpsFixtures.Argument.opsDisabled) ? .settingOff : .on
    }
    /// `/admin/me`'s `ops_monitoring_disabled_reason`.
    var disabledReason: String? { self == .on ? nil : rawValue }
}

/// 10 §1.7 home data for `-ui-testing`, apart from DemoData so NativeSessionSupport compiles and tests it. Times are offsets from
/// `base`, the site clock when the session started; windows run in minutes so they outlast a UI test.
enum LiveOpsFixtures {
    enum HomeVariant: Equatable, Sendable { case allOK, availabilityError, hourlyTimeout, calm, calmLimited }
    enum Argument {
        /// OpsFixtureSwitch: DemoData.adminMe's ops switch follows these two.
        static let opsDisabled = "-ui-ops-disabled"
        static let opsConfigOff = "-ui-ops-config-off"
        static let availabilityError = "-ui-home-availability-error"
        static let hourlyTimeout = "-ui-home-hourly-timeout"
        static let calm = "-ui-home-calm"
        static let calmLimited = "-ui-home-calm-limited"
        /// S1-06: every alert write answers 500 INTERNAL_ERROR (回执“站点暂时不可用”).
        static let alertWriteFails = "-ui-alert-write-fails"
        /// S1-06, S1D1-15: events without the `silence` key, so only 手动解决 is offered.
        static let alertLegacySilence = "-ui-alert-legacy-silence"
        /// S1-07: dashboard/home answers a non-JSON 404 (a site without it), so the overview takes the per-endpoint fallback.
        static let homeLegacy = "-ui-home-legacy"
        /// S1-09: today's account cost above the actual cost, so 利润 is a loss (−$115.50); the other cells stay as in the default.
        static let profitLoss = "-ui-home-loss"
        /// S1-09: the first home read answers 503, before any value, so the overview shows 无法连接到站点; later reads succeed.
        static let homeUnreachableOnce = "-ui-home-unreachable-once"
        /// S1-09: home reads never answer (until cancelled), so the first load's skeleton stays.
        static let homePending = "-ui-home-pending"
        /// S1-09: the fallback's `dashboard/stats` never answers (until cancelled), so only today's figures stay the skeleton.
        static let statsPending = "-ui-home-stats-pending"
        /// S1-09b: only the rates block times out (SECTION_TIMEOUT), so 运行 shows 加载超时 for 错误率 / 上游 429 / 529.
        static let ratesTimeout = "-ui-home-rates-timeout"
        /// S1-10: #11 and #12 stopped and error account #10 without structured fields (LiveOpsFixtures+Attention.swift).
        static let attentionExtra = "-ui-home-attention-extra"
        /// S1-10: seven events firing, so home lists five and 待处理 ends with “另有 2 条告警中”.
        static let alertsOverflow = "-ui-home-alerts-overflow"
        /// S1-10: the first home read past the cache (the 「测试」 sheet closed) no longer lists error account #7.
        static let testRecovers = "-ui-home-test-recovers"
        /// S1-11: calm until the first read past the cache after the first read (a pull or ··· 刷新) finds error account #7; it stays.
        static let calmThenError = "-ui-home-calm-then-error"
    }
    struct Options: Equatable, Sendable {
        var variant: HomeVariant
        /// The switch at the session's start; FixtureLiveOpsSource keeps the current one.
        var ops: OpsFixtureSwitch
        var alertWritesFail: Bool
        var alertsWithoutSilenceKey: Bool
        var homeLegacy: Bool
        // S1-09: these go with any variant.
        var profitLoss = false
        var failsFirstRound = false
        var pendingHome = false
        var pendingStats = false
        var ratesTimeout = false
        // S1-10: these go with any variant; `errorAccountRecovered` is set by FixtureLiveOpsSource, never by an argument.
        var attentionExtra = false
        var alertsOverflow = false
        var testRecovers = false
        var errorAccountRecovered = false
        // S1-11: `calmErrorAppeared` is set by FixtureLiveOpsSource, never by an argument.
        var calmThenError = false
        var calmErrorAppeared = false
        // S1-12 (LiveOpsFixtures+AlertDetail.swift): these go with any variant; `alertDetailTurnedOpsOff` is set by
        // FixtureLiveOpsSource, never by an argument.
        var alertGone = false
        var alertDetailOpsOff = false
        var alertDetailTurnedOpsOff = false
        var withholdsAlertDetails = false
        // S1-13 (LiveOpsFixtures+Monitor.swift): goes with any variant.
        var monitor = MonitorFixtureOptions()
        // S1-15 (LiveOpsFixtures+Channels.swift): goes with any variant.
        var channels = ChannelFixtureOptions()
        var opsDisabled: Bool { ops != .on }
        init(variant: HomeVariant = .allOK, ops: OpsFixtureSwitch = .on, alertWritesFail: Bool = false, alertsWithoutSilenceKey: Bool = false,
             homeLegacy: Bool = false) {
            self.variant = variant; self.ops = ops
            self.alertWritesFail = alertWritesFail; self.alertsWithoutSilenceKey = alertsWithoutSilenceKey; self.homeLegacy = homeLegacy
        }
        /// The most specific variant wins (calm-limited, calm, hourly timeout, availability error); ops off goes with any.
        init(arguments: [String]) {
            let order: [(argument: String, variant: HomeVariant)] = [(Argument.calmLimited, .calmLimited), (Argument.calm, .calm),
                                                                     (Argument.calmThenError, .calm), (Argument.hourlyTimeout, .hourlyTimeout),
                                                                     (Argument.availabilityError, .availabilityError)]
            self.init(variant: order.first { arguments.contains($0.argument) }?.variant ?? .allOK,
                      ops: OpsFixtureSwitch.from(arguments: arguments), alertWritesFail: arguments.contains(Argument.alertWriteFails),
                      alertsWithoutSilenceKey: arguments.contains(Argument.alertLegacySilence), homeLegacy: arguments.contains(Argument.homeLegacy))
            profitLoss = arguments.contains(Argument.profitLoss)
            failsFirstRound = arguments.contains(Argument.homeUnreachableOnce)
            pendingHome = arguments.contains(Argument.homePending)
            pendingStats = arguments.contains(Argument.statsPending)
            ratesTimeout = arguments.contains(Argument.ratesTimeout)
            attentionExtra = arguments.contains(Argument.attentionExtra)
            alertsOverflow = arguments.contains(Argument.alertsOverflow)
            testRecovers = arguments.contains(Argument.testRecovers)
            calmThenError = arguments.contains(Argument.calmThenError)
            alertGone = arguments.contains(Argument.alertGone)
            alertDetailOpsOff = arguments.contains(Argument.alertDetailOpsDisabled)
            withholdsAlertDetails = UITestArguments.withheldCapabilities(arguments: arguments).contains(Capability.opsAlertEventDetails.rawValue)
            monitor = MonitorFixtureOptions(arguments: arguments)
            channels = ChannelFixtureOptions(arguments: arguments)
        }
    }
    /// D30: the same zone as DemoData.serverTimeZone.
    static let serverTimeZone = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
    /// The name S2-22's plan uses.
    static let anthropicFiringEventID = LiveOpsFixtureIDs.anthropicFiringEventID
    static let opsDisabledError = APIError.server(status: 404, reason: "OPS_DISABLED")
    static let opsConfigDisabledError = APIError.server(status: 409, reason: "OPS_CONFIG_DISABLED")
    static let alertWriteError = APIError.server(status: 500, reason: "INTERNAL_ERROR")

    // MARK: 首页

    static func home(_ options: Options, base: Date, events: [AlertEvent]) -> DashboardHome {
        let firing = newestFirst(events.filter(\.isFiring))
        let alerts = HomeAlerts(firingCount: firing.count, bySeverity: AlertCounts.counting(firing).bySeverity, top: Array(firing.prefix(5)))
        let ops = HomeOps(healthScore: 94, sla: 0.992, errorRate: 0.008, upstream429Count: 12, upstream529Count: 3, requestCountTotal: 230,
                          tokenConsumed: 1_200_000)
        return DashboardHome(
            generatedAt: base, stats: .ok(stats(base, profitLoss: options.profitLoss)),
            rates: options.ratesTimeout ? HomeSection(status: .timeout, reason: "SECTION_TIMEOUT")
                : .ok(rates(base: base, opsDisabled: options.opsDisabled)),
            hourly: options.variant == .hourlyTimeout ? HomeSection(status: .timeout, reason: "SECTION_TIMEOUT") : .ok(hourly(base)),
            ops: options.opsDisabled ? opsOff() : .ok(ops), alerts: options.opsDisabled ? opsOff() : .ok(alerts),
            availability: options.variant == .availabilityError ? HomeSection(status: .error, reason: "INTERNAL_ERROR")
                : .ok(calmError(attentionAvailability(availability(options.variant, base: base), options), options)),
            channels: homeChannels(options, base: base))
    }
    /// The design's DEMO.today; `profitLoss` raises today's account cost to $1,400.00 (BACKLOG 利润亏损的固定演示状态).
    static func stats(_ base: Date, profitLoss: Bool = false) -> HomeStats {
        HomeStats(todayRequests: 18_204, todayTokens: 96_400_000, todayCost: money(161_014), todayActualCost: money(128_450),
                  todayAccountCost: money(profitLoss ? 140_000 : 51_208), statsUpdatedAt: base.addingTimeInterval(-30),
                  yesterdaySameTimeActualCost: money(118_830), yesterdaySameTimeRequests: 16_920, yesterdaySameTimeAccountCost: money(48_912),
                  yesterdaySameTimeUntil: base.addingTimeInterval(-86_400))
    }
    /// With ops monitoring off the error figures are null (10 §1.2).
    static func rates(base: Date, opsDisabled: Bool) -> LiveRates {
        LiveRates(rpm: 46, tpm: 240_000, errorRate: opsDisabled ? nil : 0.008, upstream429Count: opsDisabled ? nil : 12,
                  upstream529Count: opsDisabled ? nil : 3, opsMonitoringEnabled: !opsDisabled, errorsAvailable: !opsDisabled,
                  rpmIncludesErrors: true, startTime: base.addingTimeInterval(-300), endTime: base)
    }
    /// DEMO.hourlyToday up to the current hour (continued by yesterday's shape after 09:00) and DEMO.hourlyYesterday.
    static func hourly(_ base: Date) -> HomeHourly {
        let calendar = serverTimeZone.calendar
        let hour = calendar.component(.hour, from: base)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: base) ?? base
        let today = Array((hourlyToday + hourlyYesterday.dropFirst(hourlyToday.count)).prefix(hour + 1))
        return HomeHourly(timezone: serverTimeZone.identifier, today: hourlyPoints(base, today), yesterday: hourlyPoints(yesterday, hourlyYesterday))
    }
    static func availability(_ variant: HomeVariant, base: Date) -> AccountStatusSummary {
        let limited = [account(LiveOpsFixtureIDs.rateLimitedAccount, "Claude-官方-03", "anthropic", groups: [1], state: .rateLimited,
                               rateLimitResetAt: base.addingTimeInterval(2_700)),
                       account(LiveOpsFixtureIDs.tempUnschedulableAccount, "MiniMax-01", "minimax", groups: [9], state: .tempUnschedulable,
                               tempUnschedulableUntil: base.addingTimeInterval(3_000))]
        switch variant {
        case .calm:
            return AccountStatusSummary(collectedAt: base, totals: AccountStateCounts(total: 11, available: 9, paused: 1, inactive: 1))
        case .calmLimited:
            return AccountStatusSummary(collectedAt: base, totals: AccountStateCounts(total: 11, available: 7, rateLimited: 1, tempUnschedulable: 1,
                                                                                      paused: 1, inactive: 1), accounts: limited)
        case .allOK, .availabilityError, .hourlyTimeout:
            // AccountDemoStore's 11 accounts in S0-17's buckets: #1 #2 #4 #8 #9 available, #5 paused, #10 inactive.
            let errored = account(LiveOpsFixtureIDs.errorAccount, "OpenAI-备用-A", "openai", groups: [2, 4], state: .error, status: "error",
                                  schedulable: false)
            let overloaded = account(LiveOpsFixtureIDs.overloadedAccount, "GLM-直连-01", "zhipu", groups: [7], state: .overloaded,
                                     overloadUntil: base.addingTimeInterval(1_800))
            let shortage = AccountStatusGroupSummary(groupID: LiveOpsFixtureIDs.shortageGroup, groupName: "企业专线", platform: "openai",
                                                     counts: AccountStateCounts(total: 1, error: 1),
                                                     shortage: .init(isShort: true, source: "default", threshold: 0.5, current: 0))
            return AccountStatusSummary(collectedAt: base, totals: AccountStateCounts(total: 11, available: 5, error: 1, overloaded: 1, rateLimited: 1,
                                                                                      tempUnschedulable: 1, paused: 1, inactive: 1),
                                        groups: [shortage], accounts: [errored, overloaded] + limited)
        }
    }
    /// `accounts?status=error&lite=1`: #7 with every structured field (AccountDemoStore's values).
    static func structuredErrors(base: Date) -> [UpstreamAccount] {
        [UpstreamAccount(id: LiveOpsFixtureIDs.errorAccount, name: "OpenAI-备用-A", platform: "openai", type: "apikey", status: "error",
                         schedulable: false, groupIDs: [2, 4], errorAt: ServerTime.utcTimestamp(base.addingTimeInterval(-60)),
                         errorStatusCode: 401, errorKind: "auth", errorSummary: "401 凭据已失效（invalid_api_key）")]
    }
    /// The calm layout's 按账号 (today's figures of AccountDemoStore); calm-limited ends with an account at 0, which is not shown.
    static func ranking(_ variant: HomeVariant) -> [AccountsRankingItem] {
        let top = [rank(1, "Claude-官方-01", "anthropic", 4_418, 40_938), rank(2, "Claude-官方-02", "anthropic", 4_050, 38_405),
                   rank(4, "OpenAI-主力-01", "openai", 5_500, 20_350), rank(3, "Claude-官方-03", "anthropic", 2_302, 19_262)]
        return variant == .calmLimited ? Array(top.prefix(2)) + [rank(12, "MiniMax-01", "minimax", 0, 0)] : top
    }

    // MARK: 告警、渠道与运维概况

    /// #41 and #40 firing (none in the calm variants), #37 and #35 ended (DEMO.alerts; #40 is anthropic here, X28).
    static func alertEvents(_ variant: HomeVariant, base: Date) -> [AlertEvent] {
        let rules = alertRules()
        let ended = [
            AlertEvent(id: LiveOpsFixtureIDs.endedResolved, ruleID: 13, severity: "P1", status: "resolved", title: "P1: 内存使用率",
                       description: "memory_usage_percent 87 > 85", metricValue: 87, thresholdValue: 85, firedAt: base.addingTimeInterval(-4_920),
                       resolvedAt: base.addingTimeInterval(-3_600), rule: rules[2]),
            AlertEvent(id: LiveOpsFixtureIDs.endedManual, ruleID: 14, severity: "P2", status: AlertEvent.manualResolved, title: "P2: 高级组可用比例",
                       description: "group_available_ratio 50 < 60", metricValue: 50, thresholdValue: 60, groupID: LiveOpsFixtureIDs.premiumGroup,
                       firedAt: yesterday(base, 21, 52), resolvedAt: yesterday(base, 22, 10), rule: rules[3], groupName: "高级组",
                       resolvedByUserName: "admin")]
        guard variant != .calm, variant != .calmLimited else { return ended }
        let firing = [
            AlertEvent(id: LiveOpsFixtureIDs.alertA, ruleID: 11, severity: "P1", status: "firing", title: "P1: 标准组错误率",
                       description: "error_rate 5.2 > 5", metricValue: 5.2, thresholdValue: 5, groupID: LiveOpsFixtureIDs.standardGroup,
                       firedAt: base.addingTimeInterval(-720), rule: rules[0], groupName: "标准组"),
            AlertEvent(id: LiveOpsFixtureIDs.anthropicFiringEventID, ruleID: 12, severity: "P2", status: "firing", title: "P2: Anthropic 上游错误率",
                       description: "upstream_error_rate 6.1 > 5", metricValue: 6.1, thresholdValue: 5, platform: "anthropic",
                       firedAt: base.addingTimeInterval(-1_560),
                       silence: AlertSilenceRef(id: LiveOpsFixtureIDs.anthropicSilence, until: base.addingTimeInterval(3_600)), rule: rules[1])]
        return firing + ended
    }
    static func alertRules() -> [AlertEventRule] {
        [AlertEventRule(id: 11, name: "标准组错误率", metricType: "error_rate", comparison: ">", threshold: 5, windowMinutes: 5),
         AlertEventRule(id: 12, name: "Anthropic 上游错误率", metricType: "upstream_error_rate", comparison: ">", threshold: 5, windowMinutes: 10),
         AlertEventRule(id: 13, name: "内存使用率", metricType: "memory_usage_percent", comparison: ">", threshold: 85, windowMinutes: 5),
         AlertEventRule(id: 14, name: "高级组可用比例", metricType: "group_available_ratio", comparison: "<", threshold: 60)]
    }
    /// DEMO.server and DEMO.run for any window; today's SLA is 99.2%.
    static func opsOverview(start: Date, end: Date) -> OpsOverview {
        OpsOverview(startTime: start, endTime: end, healthScore: 94, sla: 0.992, errorRate: 0.008, upstreamErrorRate: 0.004, successCount: 18_204,
                    errorCountTotal: 342, businessLimitedCount: 25, errorCountSLA: 317, requestCountTotal: 18_546, requestCountSLA: 18_521,
                    tokenConsumed: 96_400_000, upstream429Count: 12, upstream529Count: 3,
                    systemMetrics: OpsSystemMetricsSnapshot(createdAt: end, cpuUsagePercent: 38, memoryUsagePercent: 61, dbOK: true, redisOK: true))
    }
    static func monitoringStatus(_ ops: OpsFixtureSwitch) -> OpsMonitoringStatus {
        switch ops {
        case .on: OpsMonitoringStatus(configEnabled: true, monitoringEnabled: true, realtimeMonitoringEnabled: true, effective: true)
        case .settingOff: OpsMonitoringStatus(configEnabled: true, monitoringEnabled: false, realtimeMonitoringEnabled: false, effective: false,
                                              disabledReason: ops.disabledReason)
        case .configOff: OpsMonitoringStatus(configEnabled: false, monitoringEnabled: true, realtimeMonitoringEnabled: true, effective: false,
                                             disabledReason: ops.disabledReason)
        }
    }
    /// `fired_at DESC, id DESC`, as the server lists events.
    static func newestFirst(_ events: [AlertEvent]) -> [AlertEvent] {
        events.sorted { lhs, rhs in
            guard let left = lhs.cursor, let right = rhs.cursor else { return lhs.id > rhs.id }
            return right < left
        }
    }

    // MARK: 构造

    private static let hourlyToday = [120, 112, 96, 84, 79, 88, 110, 152, 214, 229]
    private static let hourlyYesterday = [118, 104, 90, 80, 72, 80, 100, 140, 190, 215, 236, 248, 252, 240, 236, 244, 250, 238, 226, 210, 190,
                                          172, 150, 132]

    private static func opsOff<Value: Sendable>() -> HomeSection<Value> { HomeSection(status: .disabled, reason: "OPS_DISABLED") }
    /// Cents to dollars, so no amount passes through Double.
    private static func money(_ cents: Int) -> Decimal { Decimal(cents) / 100 }
    private static func hourlyPoints(_ day: Date, _ actual: [Int]) -> [HomeHourlyPoint] {
        actual.enumerated().map { hour, cost in
            HomeHourlyPoint(date: serverTimeZone.dayString(day) + String(format: " %02d:00", hour), requests: cost * 14, totalTokens: cost * 75_000,
                            actualCost: Decimal(cost), accountCost: money(cost * 40))
        }
    }
    private static func account(_ id: Int, _ name: String, _ platform: String, groups: [Int], state: AccountScheduleState, status: String = "active",
                                schedulable: Bool = true, rateLimitResetAt: Date? = nil, overloadUntil: Date? = nil,
                                tempUnschedulableUntil: Date? = nil) -> AccountStatusItem {
        AccountStatusItem(id: id, name: name, platform: platform, groupIDs: groups, state: state, status: status, schedulable: schedulable,
                          rateLimitResetAt: rateLimitResetAt, overloadUntil: overloadUntil, tempUnschedulableUntil: tempUnschedulableUntil)
    }
    private static func rank(_ id: Int, _ name: String, _ platform: String, _ requests: Int, _ cents: Int) -> AccountsRankingItem {
        AccountsRankingItem(accountID: id, accountName: name, platform: platform, requests: requests, actualCost: money(cents))
    }
    private static func yesterday(_ base: Date, _ hour: Int, _ minute: Int) -> Date {
        let calendar = serverTimeZone.calendar
        let day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: base)) ?? base
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

/// `-ui-testing`'s LiveOpsSource. The alert events are its state (FixtureAlertBook), so S1-06's writes change what is read next;
/// `homeCalls` is for fixtures that change after a pull to refresh (S1-11). Gated reads and the alert writes answer 404
/// OPS_DISABLED while the ops switch is off; S1-08's switch writes change it for what is read next. `time_range` counts back
/// from `base`, the session's start.
actor FixtureLiveOpsSource: LiveOpsSource {
    let base: Date
    /// The launch options with the current ops switch.
    private(set) var options: LiveOpsFixtures.Options
    private(set) var book: FixtureAlertBook
    private(set) var homeCalls = 0
    var events: [AlertEvent] { book.events }
    static let unreachableError = APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")

    init(options: LiveOpsFixtures.Options, base: Date = Date()) {
        self.options = options; self.base = base
        let overflow = options.alertsOverflow ? LiveOpsFixtures.overflowAlerts(base: base) : []
        book = FixtureAlertBook(events: LiveOpsFixtures.alertEvents(options.variant, base: base) + overflow, legacy: options.alertsWithoutSilenceKey,
                                writesFail: options.alertWritesFail)
    }

    func dashboardHome(timezone: ServerTimeZone, include: [HomeSectionKey]?, noCache: Bool) async throws -> DashboardHome {
        homeCalls += 1
        if options.pendingHome { try await Task.sleep(for: .seconds(3_600)) }
        if options.failsFirstRound, homeCalls == 1 { throw Self.unreachableError }
        if options.homeLegacy { throw APIError.server(status: 404, envelope: nil) }
        if options.testRecovers, noCache { options.errorAccountRecovered = true }
        if options.calmThenError, noCache, homeCalls > 1 { options.calmErrorAppeared = true }
        return LiveOpsFixtures.home(options, base: base, events: book.events.map { LiveOpsFixtures.served($0, options) })
    }
    func dashboardRates(window: LiveRatesWindow) -> LiveRates { LiveOpsFixtures.rates(base: base, opsDisabled: options.opsDisabled) }
    func opsOverview(start: Date, end: Date) throws -> OpsOverview {
        try requireOps()
        return LiveOpsFixtures.opsOverview(start: start, end: end)
    }
    /// The same figures for every window, except the home's last five minutes (S1-07's fallback reads them).
    func opsOverview(timeRange: String) throws -> OpsOverview {
        try requireOps()
        if options.monitor.overviewFails { throw Self.unreachableError }
        if timeRange == HomeFallback.opsWindow { return LiveOpsFixtures.fiveMinuteOverview(base: base) }
        return LiveOpsFixtures.opsOverview(start: base.addingTimeInterval(-300), end: base)
    }
    func errorAccounts() -> [UpstreamAccount] {
        guard ![.calm, .calmLimited].contains(options.variant) || options.calmErrorAppeared else { return [] }
        return LiveOpsFixtures.structuredErrors(base: base) + (options.attentionExtra ? [LiveOpsFixtures.errorWithoutStructuredFields] : [])
    }
    func accountsRanking(limit: Int, timezone: ServerTimeZone) -> [AccountsRankingItem] {
        Array(LiveOpsFixtures.ranking(options.variant).prefix(max(0, limit)))
    }
    /// The home summary (the error variant's read succeeds here); platform is not filtered. A group's read (S1-12) holds only that
    /// group.
    func accountStatusSummary(platform: String?, groupID: Int?, includeAccounts: Bool) -> AccountStatusSummary {
        if let groupID { return LiveOpsFixtures.groupStatusSummary(groupID: groupID, base: base) }
        let summary = LiveOpsFixtures.availability(options.variant == .availabilityError ? .allOK : options.variant, base: base)
        return includeAccounts ? summary : AccountStatusSummary(collectedAt: summary.collectedAt, totals: summary.totals, groups: summary.groups)
    }
    func alertEvents(status: String?, timeRange: String?, limit: Int, before: AlertEventCursor?, groupID: Int?,
                     platform: String?) throws -> [AlertEvent] {
        try requireOps()
        return book.events(status: status, timeRange: timeRange, limit: limit, before: before, groupID: groupID, platform: platform, now: base)
            .map { LiveOpsFixtures.served($0, options) }
    }
    func alertEventCounts() throws -> AlertCounts {
        try requireOps()
        return AlertCounts.counting(events)
    }
    /// S1-12: `-ui-alert-gone` answers 404 for every id; `-ui-alert-detail-ops-disabled` finds ops monitoring just turned off.
    func alertEvent(id: Int) throws -> AlertEvent {
        try requireOps()
        if options.alertGone { throw LiveOpsFixtures.alertGoneError }
        if options.alertDetailOpsOff, !options.alertDetailTurnedOpsOff {
            options.alertDetailTurnedOpsOff = true
            options.ops = .settingOff
            throw LiveOpsFixtures.opsDisabledError
        }
        return LiveOpsFixtures.served(try book.event(id: id), options)
    }
    func alertRules() throws -> [AlertEventRule] {
        try requireOps()
        return LiveOpsFixtures.alertRules()
    }
    func channelOverview(range: String, refresh: Bool) throws -> ChannelOverview { try LiveOpsFixtures.channelReply(options, base: base) }
    func opsMonitoringStatus() -> OpsMonitoringStatus { LiveOpsFixtures.monitoringStatus(options.ops) }
    /// The server's configuration switch answers 409 and stays off.
    func setOpsMonitoring(enabled: Bool) throws -> OpsMonitoringStatus {
        guard options.ops != .configOff else { throw LiveOpsFixtures.opsConfigDisabledError }
        options.ops = enabled ? .on : .settingOff
        return LiveOpsFixtures.monitoringStatus(options.ops)
    }
    /// The settings PUT succeeds even while the configuration holds monitoring off, which then stays off (D09).
    func enableOpsMonitoringLegacy() {
        if options.ops != .configOff { options.ops = .on }
    }
    func setAlertEventStatus(id: Int, status: String) throws {
        try requireOps()
        try book.setStatus(id: id, status: status, at: Date())
    }
    func createAlertSilence(ruleID: Int, platform: String?, groupID: Int?, until: Date) throws -> AlertSilence {
        try requireOps()
        return try book.createSilence(ruleID: ruleID, platform: platform, groupID: groupID, until: until)
    }
    func updateAlertSilence(id: Int, until: Date) throws -> AlertSilence {
        try requireOps()
        return try book.updateSilence(id: id, until: until)
    }
    func deleteAlertSilence(id: Int) throws {
        try requireOps()
        try book.deleteSilence(id: id)
    }

    /// Gated reads answer 404 OPS_DISABLED while the switch is off; LiveOpsFixtures+Monitor.swift's reads use it too.
    func requireOps() throws { if options.opsDisabled { throw LiveOpsFixtures.opsDisabledError } }
}

// MARK: - S1-11 平静布局

extension LiveOpsFixtures {
    /// `-ui-home-calm-then-error` once it switched: error account #7, as in the default fixture, joins the calm accounts.
    static func calmError(_ summary: AccountStatusSummary, _ options: Options) -> AccountStatusSummary {
        guard options.calmErrorAppeared else { return summary }
        let errored = account(LiveOpsFixtureIDs.errorAccount, "OpenAI-备用-A", "openai", groups: [2, 4], state: .error, status: "error",
                              schedulable: false)
        let totals = summary.totals
        return AccountStatusSummary(collectedAt: summary.collectedAt,
                                    totals: AccountStateCounts(total: totals.total, available: totals.available - 1, error: totals.error + 1,
                                                               overloaded: totals.overloaded, rateLimited: totals.rateLimited,
                                                               tempUnschedulable: totals.tempUnschedulable, paused: totals.paused,
                                                               inactive: totals.inactive, stopped: totals.stopped),
                                    platforms: summary.platforms, groups: summary.groups, accounts: summary.accounts + [errored],
                                    accountsTruncated: summary.accountsTruncated)
    }
}
