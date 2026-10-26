import Foundation
import Testing
@testable import Sub2Core

private let now = HomeTestData.now
private let shanghai = HomeTestData.shanghai
private let serverShanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private func decimal(_ raw: String) -> Decimal { HomeTestData.decimal(raw) }
private func loaded<Value>(_ value: Value) -> BlockState<Value> { .loaded(value, at: now) }

private let fullStats = HomeStats(todayRequests: 18_240, todayTokens: 96_400_000, todayCost: decimal("1500.10"), todayActualCost: decimal("1284.50"),
                                  todayAccountCost: decimal("1100.25"), yesterdaySameTimeActualCost: decimal("1190.45"))
private let fullRates = LiveRates(rpm: 46.2, tpm: 240_000, errorRate: 0.0086, opsMonitoringEnabled: true, errorsAvailable: true)
private func ticker(_ stats: HomeStats? = fullStats, _ rates: LiveRates? = fullRates, _ source: HomeRatesSource = .home) -> [HomeTickerCell] {
    HomePresentation.tickerCells(stats: stats, rates: rates, ratesSource: source)
}

// MARK: 10 §1.3.2 six cells

@Test func tickerCellsFollowFixedOrderLabelsAndDestinations() {
    let cells = ticker()
    #expect(cells.map(\.kind) == HomeTickerKind.allCases)
    #expect(cells.map(\.label) == ["今日实际扣费", "请求", "错误率", "利润", "RPM", "TPM"])
    #expect(cells.map(\.destination) == [.analytics, .analytics, .analytics, .analytics, .performanceTrend(.rpm), .performanceTrend(.tpm)])
    #expect(cells.map(\.id) == HomeTickerKind.allCases)
}

@Test func tickerCellsFormatThroughDisplayFormat() {
    let cells = ticker()
    #expect(cells.map(\.value) == ["$1,284.50", "18.2K", "0.9%", "$184.25", "46", "240K"])
    #expect(cells.allSatisfy { !$0.isMissing })
    let slow = ticker(fullStats, LiveRates(rpm: 0.4, tpm: 0, errorRate: 0))
    #expect(slow.suffix(2).map(\.value) == ["0.4", "0"])
    #expect(slow[2].value == "0.0%")
}

@Test func tickerCellsShowDashWhenMissing() {
    let none = ticker(nil, nil)
    #expect(none.allSatisfy { $0.value == DisplayFormat.missing && $0.isMissing && $0.change == nil })
    let opsOff = ticker(fullStats, LiveRates(rpm: 46.2, tpm: 240_000, errorRate: nil, opsMonitoringEnabled: false))
    #expect(opsOff[2].value == "—" && opsOff[2].isMissing)
    #expect(opsOff[4].value == "46" && opsOff[5].value == "240K")
    // 00 §6.5: errors_available == false hides a rate the server still sent.
    let unavailable = ticker(fullStats, LiveRates(rpm: 46.2, tpm: 240_000, errorRate: 0.0086, errorsAvailable: false))
    #expect(unavailable[2].value == "—" && unavailable[2].isMissing)
    let noAccountCost = ticker(HomeStats(todayRequests: 3, todayActualCost: decimal("10")), nil)
    #expect(noAccountCost.map(\.value) == ["$10.00", "3", "—", "—", "—", "—"])
    #expect(noAccountCost.map(\.isMissing) == [false, false, true, true, true, true])
}

@Test func profitIsActualMinusAccountWithUnicodeMinusAndNoPlus() {
    func profitCell(_ actual: String?, _ account: String?) -> String {
        ticker(HomeStats(todayActualCost: actual.map(decimal), todayAccountCost: account.map(decimal)), nil)[3].value
    }
    #expect(profitCell("100", "112.30") == "\u{2212}$12.30")
    #expect(profitCell("112.30", "100") == "$12.30")
    #expect(profitCell(nil, "100") == "—")
    #expect(profitCell("100", nil) == "—")
    #expect(profitCell("100.004", "100") == "$0.00")
    #expect(profitCell("100", "100.004") == "$0.00")
    // Decimal throughout: a Double would give −0.19999….
    #expect(HomePresentation.profit(actual: decimal("0.1"), account: decimal("0.3")) == decimal("-0.2"))
    #expect(HomePresentation.profit(actual: nil, account: decimal("1")) == nil)
}

@Test func yesterdayChangeArrowOneDecimalAndHiddenCases() throws {
    let up = try #require(HomePresentation.yesterdayChange(today: decimal("1284.50"), yesterday: decimal("1190.45")))
    #expect(up.direction == .up && up.text == "▲7.9%" && up.spoken == "比昨天同时上升 7.9%")
    let down = try #require(HomePresentation.yesterdayChange(today: decimal("96.8"), yesterday: decimal("100")))
    #expect(down.direction == .down && down.text == "▼3.2%" && down.spoken == "比昨天同时下降 3.2%")
    let flat = try #require(HomePresentation.yesterdayChange(today: decimal("100.04"), yesterday: decimal("100")))
    #expect(flat.direction == .flat && flat.text == "0.0%" && flat.spoken == "与昨天同时持平")
    #expect(HomePresentation.yesterdayChange(today: decimal("10"), yesterday: nil) == nil)
    #expect(HomePresentation.yesterdayChange(today: decimal("10"), yesterday: 0) == nil)
    #expect(HomePresentation.yesterdayChange(today: nil, yesterday: decimal("100")) == nil)
    let cells = ticker()
    #expect(cells[0].change == up)
    #expect(cells.dropFirst().allSatisfy { $0.change == nil })
    #expect(ticker(HomeStats(todayActualCost: decimal("5"), yesterdaySameTimeActualCost: 0), nil)[0].change == nil)
}

@Test func tickerAccessibilityLabelsFollowSpec() {
    let cells = ticker()
    #expect(cells.map(\.accessibilityLabel) == [
        "今日实际扣费 $1,284.50，比昨天同时上升 7.9%。打开统计分析", "请求 18.2K。打开统计分析", "错误率 0.9%。打开统计分析",
        "利润 $184.25。打开统计分析", "RPM 46。打开 RPM 趋势", "TPM 240K。打开 TPM 趋势"
    ])
    let missing = ticker(nil, nil)
    #expect(missing[0].accessibilityLabel == "今日实际扣费 无数据。打开统计分析")
    #expect(missing[4].accessibilityLabel == "RPM 无数据。打开 RPM 趋势")
    let flat = ticker(HomeStats(todayActualCost: decimal("100.04"), yesterdaySameTimeActualCost: decimal("100")), nil)
    #expect(flat[0].accessibilityLabel == "今日实际扣费 $100.04，与昨天同时持平。打开统计分析")
}

@Test func tpmFallbackMarkOnlyForDashboardStats() {
    let fallback = ticker(fullStats, fullRates, .dashboardStats)
    #expect(fallback[5].footnoteMark == "*")
    #expect(fallback[5].accessibilityLabel == "TPM 240K，不含缓存 Tokens。打开 TPM 趋势")
    #expect(fallback.dropLast().allSatisfy { $0.footnoteMark == nil })
    #expect(HomeRatesSource.dashboardStats.tpmExcludesCache)
    for source in [HomeRatesSource.home, .dashboardRates, .opsOverview] {
        #expect(!source.tpmExcludesCache)
        #expect(ticker(fullStats, fullRates, source).allSatisfy { $0.footnoteMark == nil })
    }
}

// MARK: 10 §1.3.1 subtitle

@Test func subtitleShowsServerDateAndRefreshStates() {
    func subtitle(_ status: HomeRefreshStatus) -> String {
        HomePresentation.subtitle(now: now, status: status, serverTimeZone: serverShanghai, deviceTimeZone: shanghai)
    }
    #expect(subtitle(.loading) == "10月16日 周五 · 正在加载…")
    #expect(subtitle(.updated(at: now.addingTimeInterval(-20))) == "10月16日 周五 · 刚刚更新")
    #expect(subtitle(.updated(at: now.addingTimeInterval(-300))) == "10月16日 周五 · 5 分钟前更新")
    #expect(subtitle(.updated(at: now.addingTimeInterval(-7_200))) == "10月16日 周五 · 更新于 今天 08:00")
    #expect(subtitle(.partial) == "10月16日 周五 · 部分数据未更新")
}

@Test func subtitleUsesServerCalendarAndAppendsOffsetOnlyWhenDifferent() throws {
    let late = try #require(ServerTime.parseTimestamp("2026-10-15T17:00:00Z"))
    let utc = try #require(TimeZone(identifier: "UTC"))
    // The server's day (Friday the 16th), not the phone's Thursday the 15th.
    #expect(HomePresentation.subtitle(now: late, status: .updated(at: late), serverTimeZone: serverShanghai, deviceTimeZone: utc)
            == "10月16日 周五 · 刚刚更新 · 按 UTC+8")
    #expect(HomePresentation.subtitle(now: late, status: .updated(at: late), serverTimeZone: serverShanghai, deviceTimeZone: shanghai)
            == "10月16日 周五 · 刚刚更新")
    let sunday = try #require(ServerTime.parseTimestamp("2026-10-18T02:00:00Z"))
    #expect(HomePresentation.subtitle(now: sunday, status: .loading, serverTimeZone: serverShanghai, deviceTimeZone: shanghai)
            == "10月18日 周日 · 正在加载…")
}

// MARK: 10 §2.2 calm (§2.8 cases first)

private let quietAlerts = HomeAlerts(firingCount: 0, bySeverity: ["P0": 0, "P1": 0, "P2": 0, "P3": 0])
private let limitedOnly = HomeTestData.summary(
    totals: AccountStateCounts(total: 17, available: 15, rateLimited: 1, tempUnschedulable: 1),
    accounts: [HomeTestData.account(1, state: .rateLimited, rate: HomeTestData.after(60)), HomeTestData.account(2, state: .tempUnschedulable, temp: HomeTestData.after(120))])
private func calm(availability: BlockState<AccountStatusSummary> = loaded(limitedOnly), alerts: BlockState<HomeAlerts> = loaded(quietAlerts),
                  pending: [any PendingMoneyWrite] = []) -> Bool {
    HomePresentation.isCalm(availability: availability, alerts: alerts, pending: pending)
}

@Test func calmWhenOnlyLimitedAccounts() {
    #expect(calm())
    #expect(calm(availability: loaded(HomeTestData.summary(totals: AccountStateCounts(total: 3, available: 3)))))
}

@Test func silencedFiringAlertIsNotCalm() {
    let silenced = HomeTestData.event(41, severity: "P1", silence: AlertSilenceRef(id: 3, until: HomeTestData.after(3_600)))
    #expect(!calm(alerts: loaded(HomeAlerts(firingCount: 1, bySeverity: ["P1": 1], top: [silenced]))))
    #expect(!calm(alerts: loaded(HomeAlerts(firingCount: 0, top: [silenced]))))
    #expect(!calm(alerts: loaded(HomeAlerts(firingCount: 2, bySeverity: ["P1": 2]))))
    // A row resolved here (10 §1.4) no longer counts once the server agrees.
    #expect(calm(alerts: loaded(HomeAlerts(firingCount: 0, top: [silenced.resolvedLocally(at: now)]))))
}

@Test func opsDisabledWithoutIssuesIsCalm() {
    #expect(calm(alerts: .disabled(reason: "OPS_DISABLED")))
}

@Test func availabilityFailureIsNotCalm() {
    #expect(!calm(availability: .failed(reason: "加载失败", previous: nil, at: nil)))
    #expect(!calm(availability: .failed(reason: "加载失败", previous: limitedOnly, at: now)))
    #expect(!calm(availability: .idle))
    #expect(!calm(availability: .loading(previous: nil, at: nil)))
    #expect(!calm(availability: .disabled(reason: "OPS_DISABLED")))
    #expect(calm(availability: .loading(previous: limitedOnly, at: now)))
}

@Test func localPendingRecordsIncludingCompensationAreNotCalm() {
    let records: [any PendingMoneyWrite] = [HomeTestData.balance(), HomeTestData.batch(), HomeTestData.compensation()]
    for record in records { #expect(!calm(pending: [record])) }
    #expect(calm(pending: []))
}

@Test func errorOverloadShortageOrAlertFailureAreNotCalm() {
    #expect(!calm(availability: loaded(HomeTestData.summary(totals: AccountStateCounts(total: 2, available: 1, error: 1)))))
    #expect(!calm(availability: loaded(HomeTestData.summary(totals: AccountStateCounts(total: 2, available: 1, overloaded: 1)))))
    let short = HomeTestData.group(3, name: "标准组", available: 1, total: 3, rateLimited: 2)
    #expect(!calm(availability: loaded(HomeTestData.summary(totals: AccountStateCounts(total: 3, available: 1, rateLimited: 2), groups: [short]))))
    #expect(!calm(alerts: .failed(reason: "加载失败", previous: nil, at: nil)))
    #expect(!calm(alerts: .failed(reason: "加载失败", previous: quietAlerts, at: now)))
    #expect(!calm(alerts: .idle))
    #expect(!calm(alerts: .loading(previous: nil, at: nil)))
}

// MARK: 10 §2.4 calm layout

@Test func calmFlagWordsAndAvailableCount() {
    let calmFlag = HomePresentation.calmFlag(totals: AccountStateCounts(total: 15, available: 15), hasLimited: false)
    #expect(calmFlag.title == "全部正常" && calmFlag.detail == "15 个账号可调度")
    #expect(calmFlag.text == "✓ 全部正常 · 15 个账号可调度")
    let limited = HomePresentation.calmFlag(totals: AccountStateCounts(total: 17, available: 15, rateLimited: 2), hasLimited: true)
    #expect(limited.title == "无需处理" && limited.text == "✓ 无需处理 · 15 个账号可调度")
    #expect(HomePresentation.calmFlag(totals: AccountStateCounts(available: 1_234), hasLimited: false).detail == "1,234 个账号可调度")
    #expect(HomePresentation.hasLimitedAccounts(limitedOnly))
    #expect(HomePresentation.hasLimitedAccounts(HomeTestData.summary(totals: AccountStateCounts(tempUnschedulable: 1))))
    #expect(!HomePresentation.hasLimitedAccounts(HomeTestData.summary(totals: AccountStateCounts(error: 1, overloaded: 1, paused: 2))))
}

@Test func rankingRowsTopFourPositiveWithRatioAndDetail() {
    let items = [
        AccountsRankingItem(accountID: 1, accountName: "主号", platform: "openai", requests: 12_345, actualCost: decimal("24.60")),
        AccountsRankingItem(accountID: 7, accountName: "", platform: "anthropic", requests: 80, actualCost: decimal("12.30")),
        AccountsRankingItem(accountID: 3, accountName: "备用", platform: "zhipu", requests: 5, actualCost: decimal("6.15")),
        AccountsRankingItem(accountID: 4, accountName: "小号", platform: "custom_x", requests: 1, actualCost: decimal("0.01")),
        AccountsRankingItem(accountID: 5, accountName: "零", platform: "openai", requests: 0, actualCost: 0),
        AccountsRankingItem(accountID: 6, accountName: "第六", platform: "openai", requests: 1, actualCost: decimal("0.005"))
    ]
    let rows = HomePresentation.rankingRows(items)
    #expect(rows.map(\.accountID) == [1, 7, 3, 4])
    #expect(rows.prefix(3).map(\.ratio) == [1.0, 0.5, 0.25])
    #expect(abs(rows[3].ratio - 0.01 / 24.6) < 1e-12)
    #expect(rows.map(\.amount) == ["$24.60", "$12.30", "$6.15", "$0.01"])
    #expect(rows[0].detail == "OpenAI · 12,345 次请求")
    #expect(rows[2].detail == "智谱 GLM · 5 次请求")
    #expect(rows[3].detail == "custom_x · 1 次请求")
    #expect(rows[1].name == "账号 #7" && rows[0].name == "主号")
    #expect(rows.map(\.destination) == [.account(id: 1), .account(id: 7), .account(id: 3), .account(id: 4)])
    #expect(HomePresentation.rankingRows([AccountsRankingItem(accountID: 9, actualCost: 0)]).isEmpty)
    #expect(HomePresentation.rankingRows(items, platformName: { "平台" + $0 })[0].detail == "平台openai · 12,345 次请求")
    #expect(HomePresentation.rankingRows([AccountsRankingItem(accountID: 2, accountName: "空", requests: 3, actualCost: 1)])[0].detail == "3 次请求")
}

@Test func todayCellsAndSuccessRate() {
    let cells = HomePresentation.todayCells(stats: fullStats, todaySLA: 0.983)
    #expect(cells.map(\.kind) == HomeTodayKind.allCases)
    #expect(cells.map(\.label) == ["账号成本", "标准", "利润", "Tokens", "成功率"])
    #expect(cells.map(\.value) == ["$1,100.25", "$1,500.10", "$184.25", "96.4M", "98.3%"])
    #expect(cells.allSatisfy { !$0.isMissing })
    let opsOff = HomePresentation.todayCells(stats: fullStats, todaySLA: nil)
    #expect(opsOff[4].value == "—" && opsOff[4].isMissing)
    let none = HomePresentation.todayCells(stats: nil, todaySLA: 1)
    #expect(none.map(\.value) == ["—", "—", "—", "—", "100.0%"])
    #expect(HomePresentation.todaySectionMeta == "00:00 起")
}

@Test func statsFreshnessOnlyWhenStale() {
    let stale = HomeStats(statsUpdatedAt: ServerTime.parseTimestamp("2026-10-16T02:04:00Z"), statsStale: true)
    #expect(HomePresentation.statsFreshness(stale, timeZone: shanghai) == "统计更新于 10:04")
    #expect(HomePresentation.statsFreshness(HomeStats(statsUpdatedAt: now, statsStale: false), timeZone: shanghai) == nil)
    #expect(HomePresentation.statsFreshness(HomeStats(statsStale: true), timeZone: shanghai) == nil)
    #expect(HomePresentation.statsFreshness(nil, timeZone: shanghai) == nil)
}

@Test func channelSummarySkipsZeroAndCarriesTone() {
    let full = HomePresentation.channelSummaryLine(HomeChannels(total: 6, healthy: 3, warning: 1, critical: 1, unknown: 1))
    #expect(full == [HomeChannelPart(text: "可用 3", tone: .ok), HomeChannelPart(text: "性能下降 1", tone: .caution),
                     HomeChannelPart(text: "不可用 1", tone: .critical), HomeChannelPart(text: "未知 1", tone: .neutral)])
    #expect(HomePresentation.channelSummaryLine(HomeChannels(total: 4, healthy: 3, unknown: 1)).map(\.text) == ["可用 3", "未知 1"])
    #expect(HomePresentation.channelSummaryLine(HomeChannels()).isEmpty)
    #expect(HomePresentation.channelCountTitle(HomeChannels(total: 8)) == "8 个渠道")
    #expect(HomePresentation.channelsDisabledText == "渠道监控未开启")
    #expect(HomePresentation.channelsFailedText == "渠道状态加载失败")
}

@Test func sessionRenewalBannerUsesMinutesLeft() {
    #expect(HomePresentation.sessionRenewalBanner(expiresAt: now.addingTimeInterval(720), now: now) == "本次登录无法自动续期，约 12 分钟后需要重新登录")
    #expect(HomePresentation.sessionRenewalBanner(expiresAt: now.addingTimeInterval(3_900), now: now) == "本次登录无法自动续期，约 1 小时 5 分钟后需要重新登录")
    #expect(HomePresentation.sessionRenewalBanner(expiresAt: nil, now: now) == "本次登录无法自动续期，到期后需要重新登录")
}
