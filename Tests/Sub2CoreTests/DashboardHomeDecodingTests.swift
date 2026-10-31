import Foundation
import Testing
@testable import Sub2Core

private func decodeHome(_ json: String) throws -> DashboardHome { try JSONDecoder().decode(DashboardHome.self, from: Data(json.utf8)) }
private func ok(_ data: String) -> String { #"{"status":"ok","data":\#(data)}"# }

private let statsData = #"{"timezone":"Asia/Shanghai","today_requests":18200,"today_tokens":5400000,"today_cost":1500.25,"today_actual_cost":1284.5,"today_account_cost":620.75,"active_users":12,"stats_updated_at":"2026-10-23T02:04:00Z","stats_stale":false,"yesterday_same_time_requests":16000,"yesterday_same_time_actual_cost":1100.5,"yesterday_same_time_account_cost":null,"yesterday_same_time_until":"2026-10-22T10:04:05+08:00"}"#
private let ratesData = #"{"window_seconds":300,"start_time":"2026-10-23T01:59:05Z","end_time":"2026-10-23T02:04:05Z","success_count":231,"error_count":2,"error_count_sla":2,"request_count":233,"token_consumed":1200000,"rpm":46.2,"tpm":240000,"error_rate":0.0086,"upstream_429_count":3,"upstream_529_count":0,"ops_monitoring_enabled":true,"errors_available":true,"rpm_includes_errors":true}"#
private let hourlyData = #"{"timezone":"Asia/Shanghai","today":[{"date":"2026-10-23 00:00","requests":900,"input_tokens":1000,"output_tokens":2000,"cache_creation_tokens":0,"cache_read_tokens":0,"total_tokens":3000,"cost":1.5,"actual_cost":1.25,"account_cost":0.5},{"date":"2026-10-23 01:00","requests":1200,"total_tokens":4000,"cost":2,"actual_cost":2.5}],"yesterday":[{"date":"2026-10-22 23:00","requests":700,"total_tokens":2500,"cost":1,"actual_cost":1.1}]}"#
private let opsData = #"{"start_time":"2026-10-23T01:59:05Z","end_time":"2026-10-23T02:04:05Z","health_score":92,"sla":0.983,"error_rate":0.0086,"upstream_error_rate":0.002,"upstream_429_count":3,"upstream_529_count":1,"success_count":231,"error_count_total":2,"error_count_sla":2,"business_limited_count":0,"request_count_total":233,"request_count_sla":233,"token_consumed":1200000}"#
private let alertsData = #"{"firing_count":3,"by_severity":{"P0":0,"P1":2,"P2":1,"P3":0},"top":[{"id":101,"rule_id":7,"severity":"P1","status":"firing","title":"P1: 标准组错误率","fired_at":"2026-10-23T02:00:00Z","silence":null}]}"#
private let availabilityData = #"{"collected_at":"2026-10-23T02:04:00Z","totals":{"total":12,"available":9,"error":1,"overloaded":1,"rate_limited":1,"temp_unschedulable":0,"paused":0,"inactive":0,"stopped":0},"groups":[{"group_id":2,"group_name":"标准组","platform":"anthropic","group_status":"active","total":3,"available":1,"error":1,"overloaded":0,"rate_limited":1,"temp_unschedulable":0,"paused":0,"inactive":0,"stopped":0,"shortage":{"is_short":true,"source":"default","threshold":0.5,"current":0.33}}],"accounts":[{"id":7,"name":"账号七","platform":"anthropic","group_ids":[2],"state":"error","stopped":false,"status":"error","schedulable":true,"error_message":"upstream said no","rate_limit_reset_at":null},{"id":3,"name":"账号三","platform":"openai","group_ids":[2],"state":"rate_limited","stopped":false,"status":"active","schedulable":true,"error_message":"","rate_limit_reset_at":"2026-10-23T03:00:00Z"}],"accounts_truncated":true}"#
private let channelsData = #"{"total":6,"healthy":3,"warning":1,"critical":1,"unknown":1,"coverage_state":"partial","collector_state":"running"}"#

private func sectionData(_ key: HomeSectionKey) -> String {
    switch key {
    case .stats: statsData
    case .rates: ratesData
    case .hourly: hourlyData
    case .ops: opsData
    case .alerts: alertsData
    case .availability: availabilityData
    case .channels: channelsData
    }
}
/// A full `dashboard/home` data object; `replacing` swaps a whole block, `omitting` leaves its key out.
private func homeJSON(replacing: [HomeSectionKey: String] = [:], omitting: Set<HomeSectionKey> = []) -> String {
    let blocks = HomeSectionKey.allCases.filter { !omitting.contains($0) }.map { "\"\($0.rawValue)\":\(replacing[$0] ?? ok(sectionData($0)))" }
    return "{" + ([#""generated_at":"2026-10-23T02:04:05Z""#, #""timezone":"Asia/Shanghai""#] + blocks).joined(separator: ",") + "}"
}
private func reason(_ home: DashboardHome, _ key: HomeSectionKey) -> String? {
    switch key {
    case .stats: home.stats.reason
    case .rates: home.rates.reason
    case .hourly: home.hourly.reason
    case .ops: home.ops.reason
    case .alerts: home.alerts.reason
    case .availability: home.availability.reason
    case .channels: home.channels.reason
    }
}

@Test func homeDecodesEverySectionOfAFullResponse() throws {
    let home = try decodeHome(homeJSON())
    #expect(home.generatedAt == ServerTime.parseTimestamp("2026-10-23T02:04:05Z"))
    let stats = try #require(home.stats.data)
    #expect(stats.todayRequests == 18200 && stats.todayTokens == 5_400_000 && stats.todayActualCost == Decimal(string: "1284.5"))
    #expect(stats.todayCost == Decimal(string: "1500.25") && stats.todayAccountCost == Decimal(string: "620.75") && !stats.statsStale)
    #expect(stats.statsUpdatedAt == ServerTime.parseTimestamp("2026-10-23T02:04:00Z"))
    #expect(stats.yesterdaySameTimeRequests == 16000 && stats.yesterdaySameTimeActualCost == Decimal(string: "1100.5"))
    #expect(stats.yesterdaySameTimeAccountCost == nil && stats.yesterdaySameTimeUntil == ServerTime.parseTimestamp("2026-10-22T02:04:05Z"))
    let rates = try #require(home.rates.data)
    #expect(rates.rpm == 46.2 && rates.tpm == 240_000 && rates.errorRate == 0.0086 && rates.upstream429Count == 3 && rates.upstream529Count == 0)
    #expect(rates.opsMonitoringEnabled == true && rates.errorsAvailable == true && rates.rpmIncludesErrors == true)
    #expect(rates.startTime == ServerTime.parseTimestamp("2026-10-23T01:59:05Z") && rates.endTime == ServerTime.parseTimestamp("2026-10-23T02:04:05Z"))
    let hourly = try #require(home.hourly.data)
    #expect(hourly.timezone == "Asia/Shanghai" && hourly.today.map(\.date) == ["2026-10-23 00:00", "2026-10-23 01:00"] && hourly.yesterday.count == 1)
    #expect(home.ops.data == HomeOps(healthScore: 92, sla: 0.983, errorRate: 0.0086, upstream429Count: 3, upstream529Count: 1, requestCountTotal: 233,
                                     tokenConsumed: 1_200_000))
    let alerts = try #require(home.alerts.data)
    #expect(alerts.firingCount == 3 && alerts.count(severity: "P1") == 2 && alerts.top.map(\.id) == [101])
    let availability = try #require(home.availability.data)
    #expect(availability.totals.error == 1 && availability.groups.first?.shortage.isShort == true)
    #expect(home.channels.data == HomeChannels(total: 6, healthy: 3, warning: 1, critical: 1, unknown: 1, coverageState: "partial", collectorState: "running"))
    #expect(HomeSectionKey.allCases.allSatisfy { home.status(of: $0) == .ok && reason(home, $0) == nil })
    #expect(home.degradedSections().isEmpty)
}

@Test func partialSuccessKeepsEachSectionIndependent() throws {
    let home = try decodeHome(homeJSON(replacing: [
        .ops: #"{"status":"disabled","error":"OPS_DISABLED","data":{"health_score":1}}"#,
        .alerts: #"{"status":"disabled","error":"OPS_DISABLED"}"#,
        .channels: #"{"status":"disabled","error":"CHANNEL_MONITOR_DISABLED"}"#,
        .hourly: #"{"status":"timeout","error":"SECTION_TIMEOUT"}"#
    ]))
    #expect(home.stats.status == .ok && home.rates.status == .ok && home.availability.status == .ok)
    #expect(home.stats.data?.todayRequests == 18200 && home.availability.data?.accounts.count == 2 && home.rates.data?.rpm == 46.2)
    #expect(home.ops == HomeSection<HomeOps>(status: .disabled, reason: "OPS_DISABLED"))
    #expect(home.alerts == HomeSection<HomeAlerts>(status: .disabled, reason: "OPS_DISABLED"))
    #expect(home.channels == HomeSection<HomeChannels>(status: .disabled, reason: "CHANNEL_MONITOR_DISABLED"))
    #expect(home.hourly == HomeSection<HomeHourly>(status: .timeout, reason: "SECTION_TIMEOUT"))
    #expect(home.status(of: .ops) == .disabled && home.status(of: .hourly) == .timeout && home.status(of: .channels) == .disabled)
    #expect(home.degradedSections() == [.hourly])
}

private let unknownBlocks: [(String, String?)] = [
    (#"{"status":"degraded","error":"SOMETHING_NEW","data":{"health_score":1}}"#, "SOMETHING_NEW"),
    (#"{"status":"","data":{"health_score":1}}"#, nil),
    (#"{"status":1,"data":{"health_score":1}}"#, nil),
    (#"{"data":{"health_score":1}}"#, nil)
]

@Test(arguments: unknownBlocks)
func unknownSectionStatusDecodesAsError(block: String, expectedReason: String?) throws {
    let home = try decodeHome(homeJSON(replacing: [.ops: block]))
    #expect(home.ops == HomeSection<HomeOps>(status: .error, reason: expectedReason))
    #expect(home.ops.data == nil && home.stats.status == .ok)
}

@Test func wireStatusReadsOnlyTheFourKnownValues() {
    #expect(HomeSectionStatus.allCases.allSatisfy { HomeSectionStatus(wire: $0.rawValue) == $0 })
    #expect(HomeSectionStatus(wire: nil) == .error && HomeSectionStatus(wire: "degraded") == .error)
}

@Test func missingOrNullSectionDecodesAsError() throws {
    let home = try decodeHome(homeJSON(replacing: [.ops: "null", .stats: #""x""#], omitting: [.channels]))
    #expect(home.channels == .missing && home.ops == .missing && home.stats == .missing)
    #expect([HomeSectionKey.rates, .hourly, .alerts, .availability].allSatisfy { home.status(of: $0) == .ok })
    #expect(throws: (any Error).self) { try decodeHome("[]") }
}

private let brokenBlocks: [(HomeSectionKey, String)] = [
    (.stats, #"{"status":"ok","data":"oops"}"#),
    (.rates, #"{"status":"ok"}"#),
    (.stats, #"{"status":"ok","data":{"today_requests":1,"today_actual_cost":"abc"}}"#),
    (.hourly, #"{"status":"ok","data":{"today":[{"requests":1,"actual_cost":1}],"yesterday":[]}}"#),
    (.alerts, #"{"status":"ok","data":{"firing_count":1,"by_severity":{"P1":1},"top":["x"]}}"#),
    (.channels, #"{"status":"ok","data":{"total":"x","healthy":1}}"#),
    (.ops, #"{"status":"ok","data":{"health_score":"high"}}"#)
]

@Test(arguments: brokenBlocks)
func brokenSectionDataOnlyFailsThatSection(key: HomeSectionKey, block: String) throws {
    let home = try decodeHome(homeJSON(replacing: [key: block]))
    #expect(home.status(of: key) == .error && reason(home, key) == nil)
    #expect(HomeSectionKey.allCases.filter { $0 != key }.allSatisfy { home.status(of: $0) == .ok })
    #expect(home.degradedSections() == [key])
}

@Test func moneyFieldsKeepFullDecimalPrecision() throws {
    let long = "12.34567890123456789"
    let stats = #"{"today_cost":"\#(long)","today_actual_cost":"\#(long)","today_account_cost":"\#(long)","yesterday_same_time_actual_cost":"\#(long)","yesterday_same_time_account_cost":"\#(long)"}"#
    let hourly = #"{"today":[{"date":"2026-10-23 00:00","actual_cost":"\#(long)","account_cost":"\#(long)"}]}"#
    let home = try decodeHome(homeJSON(replacing: [.stats: ok(stats), .hourly: ok(hourly)]))
    let exact = try #require(Decimal(string: long)), double = try #require(Double(long))
    #expect(exact != Decimal(double))
    let money = try #require(home.stats.data)
    let values = [money.todayCost, money.todayActualCost, money.todayAccountCost, money.yesterdaySameTimeActualCost, money.yesterdaySameTimeAccountCost]
    #expect(values.allSatisfy { $0 == exact })
    let point = try #require(home.hourly.data?.today.first)
    #expect(point.actualCost == exact && point.accountCost == exact)
    let numbers = try #require(try decodeHome(homeJSON(replacing: [.stats: ok(#"{"today_actual_cost":1284.5012345678,"today_cost":null}"#)])).stats.data)
    #expect(numbers.todayActualCost == Decimal(string: "1284.5012345678"))
    #expect(numbers.todayCost == nil && numbers.todayAccountCost == nil)
}

@Test func availabilityDecodesAsAccountStatusSummary() throws {
    let summary = try #require(try decodeHome(homeJSON()).availability.data)
    #expect(summary.collectedAt == ServerTime.parseTimestamp("2026-10-23T02:04:00Z"))
    #expect(summary.totals == AccountStateCounts(total: 12, available: 9, error: 1, overloaded: 1, rateLimited: 1))
    #expect(summary.groups.first?.shortage == .init(isShort: true, source: "default", threshold: 0.5, current: 0.33))
    #expect(summary.accounts.map(\.id) == [7, 3] && summary.accounts[0].state == .error && summary.accounts[1].state == .rateLimited)
    #expect(summary.accounts[1].rateLimitResetAt == ServerTime.parseTimestamp("2026-10-23T03:00:00Z"))
    #expect(summary.accountsTruncated && summary.platforms.isEmpty)
}

@Test func alertsTopDecodesFullAlertEvents() throws {
    let top = #"[{"id":101,"rule_id":7,"severity":"P1","status":"firing","title":"P1: 标准组错误率","description":"error rate high","metric_value":0.052,"threshold_value":0.05,"dimensions":{"platform":"anthropic","group_id":2},"fired_at":"2026-10-23T10:04:05.123456+08:00","silence":{"id":5,"until":"2026-10-23T04:00:00Z"},"rule":{"id":7,"name":"标准组错误率","metric_type":"error_rate","operator":">","threshold":5,"window_minutes":5,"sustained_minutes":2,"deleted":false},"group_name":"标准组"},{"id":100,"severity":"P2","status":"firing","silence":null}]"#
    let block = ok(#"{"firing_count":3,"by_severity":{"P0":0,"P1":2,"P2":1,"P3":0},"top":\#(top)}"#)
    let alerts = try #require(try decodeHome(homeJSON(replacing: [.alerts: block])).alerts.data)
    #expect(alerts.top.map(\.id) == [101, 100])
    let first = alerts.top[0]
    #expect(first.rule?.name == "标准组错误率" && first.silence == AlertSilenceRef(id: 5, until: ServerTime.parseTimestamp("2026-10-23T04:00:00Z")))
    #expect(first.silenceSupported && first.thresholdValue == 0.05 && first.groupName == "标准组" && first.groupID == 2)
    #expect(first.firedAt == ServerTime.parseTimestamp("2026-10-23T02:04:05.123456Z"))
    #expect(alerts.top[1].silence == nil && alerts.top[1].silenceSupported)
    #expect(alerts.count(severity: "P1") == 2 && alerts.count(severity: "P2") == 1 && alerts.count(severity: "P0") == 0 && alerts.count(severity: "P9") == 0)
    let nullTop = try #require(try decodeHome(homeJSON(replacing: [.alerts: ok(#"{"firing_count":0,"top":null}"#)])).alerts.data)
    #expect(nullTop.top.isEmpty && nullTop.bySeverity.isEmpty)
    let uncounted = try #require(try decodeHome(homeJSON(replacing: [.alerts: ok(#"{"top":\#(top)}"#)])).alerts.data)
    #expect(uncounted.firingCount == 2)
}

@Test func ratesWithMonitoringOffKeepNullErrorFields() throws {
    let off = #"{"rpm":0.4,"tpm":1200,"error_count":null,"error_rate":null,"upstream_429_count":null,"upstream_529_count":null,"ops_monitoring_enabled":false,"errors_available":false,"rpm_includes_errors":false}"#
    let rates = try #require(try decodeHome(homeJSON(replacing: [.rates: ok(off)])).rates.data)
    #expect(rates == LiveRates(rpm: 0.4, tpm: 1200, opsMonitoringEnabled: false, errorsAvailable: false, rpmIncludesErrors: false))
    let unknown = try #require(try decodeHome(homeJSON(replacing: [.rates: ok(#"{"rpm":1}"#)])).rates.data)
    #expect(unknown.opsMonitoringEnabled == nil && unknown.errorsAvailable == nil && unknown.rpmIncludesErrors == nil)
}

@Test func emptySectionObjectsDecodeWithDefaults() throws {
    let home = try decodeHome(homeJSON(replacing: Dictionary(uniqueKeysWithValues: HomeSectionKey.allCases.map { ($0, ok("{}")) })))
    let expected = DashboardHome(generatedAt: home.generatedAt, stats: .ok(HomeStats()), rates: .ok(LiveRates()), hourly: .ok(HomeHourly()), ops: .ok(HomeOps()),
                                 alerts: .ok(HomeAlerts()), availability: .ok(AccountStatusSummary()), channels: .ok(HomeChannels()))
    #expect(home == expected)
    #expect(home.stats.data?.statsStale == false && home.alerts.data?.firingCount == 0 && home.channels.data?.coverageState == nil)
}

@Test func hourlyPointsKeepServerLabelsAndOptionalAccountCost() throws {
    let data = #"{"timezone":"America/New_York","today":[{"date":"2026-10-23 00:00","requests":9007199254740993,"total_tokens":9007199254740995,"actual_cost":1.5,"account_cost":0.25},{"date":"2026-10-23 01:00"}],"yesterday":[{"date":"2026-10-22 23:00","requests":3,"total_tokens":30,"actual_cost":0.1}]}"#
    let hourly = try #require(try decodeHome(homeJSON(replacing: [.hourly: ok(data)])).hourly.data)
    #expect(hourly.timezone == "America/New_York")
    #expect(hourly.today[0] == HomeHourlyPoint(date: "2026-10-23 00:00", requests: 9_007_199_254_740_993, totalTokens: 9_007_199_254_740_995,
                                               actualCost: 1.5, accountCost: 0.25))
    #expect(hourly.today[1] == HomeHourlyPoint(date: "2026-10-23 01:00"))
    #expect(hourly.yesterday.map(\.id) == ["2026-10-22 23:00"] && hourly.yesterday[0].accountCost == nil && hourly.yesterday[0].requests == 3)
}

@Test func sectionInitKeepsDataOnlyWhenOK() {
    #expect(HomeSection<HomeOps>(status: .ok) == HomeSection(status: .error))
    #expect(HomeSection<HomeOps>(status: .ok, reason: "X").reason == nil)
    let disabled = HomeSection(status: .disabled, reason: "OPS_DISABLED", data: HomeOps(healthScore: 90))
    #expect(disabled.status == .disabled && disabled.reason == "OPS_DISABLED" && disabled.data == nil)
    let fine = HomeSection.ok(HomeStats(todayRequests: 1))
    #expect(fine.status == .ok && fine.reason == nil && fine.data?.todayRequests == 1)
    #expect(HomeSection(status: .ok, reason: "IGNORED", data: HomeStats()).reason == nil)
    #expect(HomeSection<HomeStats>.missing == HomeSection(status: .error))
    let empty = DashboardHome()
    #expect(empty.generatedAt == nil && HomeSectionKey.allCases.allSatisfy { empty.status(of: $0) == .error })
    #expect(DashboardHome(stats: .ok(HomeStats())).degradedSections() == [.rates, .hourly, .ops, .alerts, .availability, .channels])
}

@Test func degradedSectionsFollowRequestedKeys() throws {
    let home = try decodeHome(homeJSON(omitting: [.hourly, .ops, .alerts, .availability, .channels]))
    #expect(home.degradedSections() == [.hourly, .ops, .alerts, .availability, .channels])
    #expect(home.degradedSections(among: [.stats, .rates]).isEmpty)
    #expect(home.status(of: .ops) == .error && home.stats.status == .ok && home.rates.status == .ok)
}
