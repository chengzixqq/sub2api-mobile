import Foundation
import Testing
@testable import Sub2Core

/// Fixtures shared by HomePresentationTests and AttentionItemsTests.
enum HomeTestData {
    static let now = ServerTime.parseTimestamp("2026-10-16T02:00:00Z")!
    static let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    static let serverID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    static func decimal(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
    static func after(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    /// `stopped` follows the server: a timed state with scheduling off.
    static func account(_ id: Int, name: String? = nil, platform: String = "openai", state: AccountScheduleState?, schedulable: Bool = true,
                        overload: Date? = nil, rate: Date? = nil, temp: Date? = nil, modelLimits: [AccountModelRateLimit] = []) -> AccountStatusItem {
        AccountStatusItem(id: id, name: name ?? "账号\(id)", platform: platform, state: state, stopped: state?.isLimited == true && !schedulable,
                          status: state == .error ? "error" : "active", schedulable: schedulable, rateLimitResetAt: rate, overloadUntil: overload,
                          tempUnschedulableUntil: temp, modelRateLimits: modelLimits)
    }
    static func summary(totals: AccountStateCounts = .init(), groups: [AccountStatusGroupSummary] = [], accounts: [AccountStatusItem] = [],
                        truncated: Bool = false) -> AccountStatusSummary {
        AccountStatusSummary(collectedAt: now, totals: totals, groups: groups, accounts: accounts, accountsTruncated: truncated)
    }
    static func group(_ id: Int, name: String, available: Int, total: Int, error: Int = 0, rateLimited: Int = 0, paused: Int = 0,
                      status: String = "active", isShort: Bool = true) -> AccountStatusGroupSummary {
        AccountStatusGroupSummary(groupID: id, groupName: name, platform: "openai", groupStatus: status,
                                  counts: AccountStateCounts(total: total, available: available, error: error, rateLimited: rateLimited, paused: paused),
                                  shortage: .init(isShort: isShort, source: "default"))
    }
    static func event(_ id: Int, severity: String = "P1", status: String = "firing", firedAt: Date? = after(-720),
                      silence: AlertSilenceRef? = nil) -> AlertEvent {
        AlertEvent(id: id, ruleID: 7, severity: severity, status: status, title: "\(severity): 标准组错误率", metricValue: 5.2, groupID: 12,
                   firedAt: firedAt, silence: silence,
                   rule: AlertEventRule(id: 7, name: "标准组错误率", metricType: "error_rate", comparison: ">", threshold: 5, windowMinutes: 5),
                   groupName: "标准组")
    }
    static func balance(_ operation: BalanceOperation = .add, amount: String = "50", userID: Int = 7, name: String = "周婷",
                        createdAt: Date = after(-300)) -> PendingBalanceOperation {
        PendingBalanceOperation(serverID: serverID, userID: userID, amount: decimal(amount), operation: operation, actorUserID: 1, createdAt: createdAt,
                                userDisplayName: name, userEmail: "user\(userID)@example.com")
    }
    /// Saved before S0-06: no createdAt, display name or email.
    static func legacyBalance(userID: Int = 7) throws -> PendingBalanceOperation {
        let json = #"{"id":"\#(UUID().uuidString)","serverID":"\#(serverID.uuidString)","userID":\#(userID),"amount":12.5,"operation":"add","notes":""}"#
        return try JSONDecoder().decode(PendingBalanceOperation.self, from: Data(json.utf8))
    }
    static func batch(_ type: RedeemCodeType = .balance, value: String = "10", count: Int = 20, createdAt: Date = after(-300)) -> PendingRedeemBatch {
        PendingRedeemBatch(serverID: serverID, actorUserID: 1, createdAt: createdAt, spec: RedeemGenerateSpec(type: type, value: decimal(value), count: count))
    }
    static func compensation(_ type: CompensationType = .balance, value: String = "5", userID: Int = 8, createdAt: Date = after(-300)) -> PendingCompensation {
        PendingCompensation(serverID: serverID, actorUserID: 1, createdAt: createdAt, userID: userID, userDisplayName: "李雷",
                            userEmail: "lilei@example.com", code: "GRANT-0001", type: type, value: decimal(value))
    }
    static func structuredError(_ id: Int, summary: String?, errorAt: Date?, message: String? = "upstream secret body") -> UpstreamAccount {
        UpstreamAccount(id: id, name: "账号\(id)", platform: "openai", type: "apikey", status: "error", schedulable: true, errorMessage: message,
                        errorAt: errorAt.map(ServerTime.utcTimestamp), errorSummary: summary)
    }
}

private let now = HomeTestData.now
private let shanghai = HomeTestData.shanghai
private func after(_ seconds: TimeInterval) -> Date { HomeTestData.after(seconds) }
private func loaded<Value>(_ value: Value) -> BlockState<Value> { .loaded(value, at: now) }
private func items(alerts: BlockState<HomeAlerts> = .idle, availability: BlockState<AccountStatusSummary> = .idle,
                   structuredErrors: [UpstreamAccount] = [], pending: [any PendingMoneyWrite] = [], at time: Date = now) -> [AttentionItem] {
    HomePresentation.attentionItems(alerts: alerts, availability: availability, structuredErrors: structuredErrors, pending: pending,
                                    now: time, timeZone: shanghai)
}
private func strings(_ item: AttentionItem, now: Date = now) -> [String] {
    [item.title, item.detail, item.detailMark, item.footnote, item.stoppedNames, item.badgeText(now: now), item.trailingText(now: now)].compactMap { $0 }
}

private let errorAccount = HomeTestData.account(7, name: "OpenAI 主号", state: .error)
private let overloadedAccount = HomeTestData.account(8, name: "GLM 备用", platform: "zhipu", state: .overloaded, schedulable: false, overload: after(72))
private let limitedAccounts = [
    HomeTestData.account(9, name: "a", state: .rateLimited, rate: after(300)),
    HomeTestData.account(10, name: "b", state: .rateLimited, schedulable: false, rate: after(277)),
    HomeTestData.account(11, name: "c", state: .tempUnschedulable, temp: after(600))
]
private let busySummary = HomeTestData.summary(
    totals: AccountStateCounts(total: 20, available: 12, error: 1, overloaded: 1, rateLimited: 2, tempUnschedulable: 1, stopped: 2),
    groups: [HomeTestData.group(5, name: "企业专线", available: 0, total: 2, error: 1)],
    accounts: [errorAccount, overloadedAccount] + limitedAccounts)

// MARK: 10 §1.3.3 order

@Test func itemsFollowFixedSlotOrder() {
    let balance = HomeTestData.balance(), batch = HomeTestData.batch(), grant = HomeTestData.compensation()
    let alerts = HomeAlerts(firingCount: 3, bySeverity: ["P0": 1, "P1": 1, "P2": 1], top: [HomeTestData.event(41), HomeTestData.event(42, severity: "P0")])
    let result = items(alerts: loaded(alerts), availability: loaded(busySummary), pending: [grant, batch, balance])
    #expect(result.map(\.kind) == [.alert, .alert, .moreAlerts, .errorAccount, .overloadedAccount, .limitedAccounts, .groupShortage,
                                   .pendingBalance, .pendingRedeemBatch, .pendingCompensation])
    #expect(result.map(\.id) == ["alert-42", "alert-41", "alerts-more", "account-7", "account-8", "limited", "groups",
                                 "pending-" + balance.id.uuidString.lowercased(), "pending-" + batch.id.uuidString.lowercased(),
                                 "pending-" + grant.id.uuidString.lowercased()])
    #expect(Set(result.map(\.id)).count == result.count)
    #expect(result.allSatisfy { !$0.systemImage.isEmpty })
    #expect(items().isEmpty)
}

// MARK: Alert rows (U06)

@Test func alertsSortedBySeverityThenNewest() {
    let top = [
        HomeTestData.event(10, severity: "P2", firedAt: after(-60)), HomeTestData.event(11, severity: "P0", firedAt: after(-3_600)),
        HomeTestData.event(12, severity: "P3", firedAt: after(-30)), HomeTestData.event(13, severity: " p0 ", firedAt: after(-30)),
        HomeTestData.event(14, severity: "S9", firedAt: after(-10)), HomeTestData.event(16, severity: "P0", status: "manual_resolved", firedAt: after(-5))
    ]
    let result = items(alerts: loaded(HomeAlerts(firingCount: 6, top: top)))
    #expect(result.map(\.id) == ["alert-13", "alert-11", "alert-10", "alert-12", "alert-14"])
    // Same level and time: higher id first; no time last.
    let ties = [HomeTestData.event(20, firedAt: after(-60)), HomeTestData.event(22, firedAt: nil), HomeTestData.event(21, firedAt: after(-60))]
    #expect(items(alerts: loaded(HomeAlerts(firingCount: 3, top: ties))).map(\.id) == ["alert-21", "alert-20", "alert-22"])
    #expect(items(alerts: .disabled(reason: "OPS_DISABLED"), availability: loaded(busySummary)).allSatisfy { $0.kind != .alert && $0.kind != .alertsFailed })
    #expect(items(alerts: .idle).isEmpty)
}

@Test func alertRowsShowAtMostFiveAndCountTheRest() {
    let top = (1...7).map { HomeTestData.event($0, severity: $0 == 7 ? "P0" : "P2", firedAt: after(Double(-$0 * 60))) }
    let result = items(alerts: loaded(HomeAlerts(firingCount: 9, bySeverity: ["P0": 1, "P2": 8], top: top)))
    #expect(result.map(\.id) == ["alert-7", "alert-1", "alert-2", "alert-3", "alert-4", "alerts-more"])
    #expect(result.last?.title == "另有 4 条告警中")
    #expect(result.last?.tone == .caution)
}

@Test func alertRowUsesAlertPresentation() throws {
    let event = HomeTestData.event(41, severity: "P1", silence: AlertSilenceRef(id: 3, until: after(3_600)))
    let row = try #require(items(alerts: loaded(HomeAlerts(firingCount: 1, bySeverity: ["P1": 1], top: [event]))).first)
    #expect(row.title == AlertPresentation.title(event) && row.title == "标准组错误率 5.2%")
    #expect(row.badgeText(now: now) == "P1")
    #expect(row.detail == AlertPresentation.homeSubtitle(event, now: now, timeZone: shanghai))
    #expect(row.detail == "阈值 5.0% · 12 分钟前触发 · 已静默")
    #expect(row.tone == Tone.alert(severity: "P1", status: "firing") && row.tone == .caution)
    #expect(row.destination == .alert(id: 41) && row.action == nil && row.countdownTarget == nil)
    let critical = try #require(items(alerts: loaded(HomeAlerts(firingCount: 1, top: [HomeTestData.event(42, severity: "P0")]))).first)
    #expect(critical.tone == .critical)
}

@Test func moreAlertsRowCountAndHighestRemainingTone() throws {
    let shown = [HomeTestData.event(1), HomeTestData.event(2), HomeTestData.event(3), HomeTestData.event(4, severity: "P2"), HomeTestData.event(5, severity: "P2")]
    func more(_ firing: Int, _ bySeverity: [String: Int], top: [AlertEvent] = shown) -> AttentionItem? {
        items(alerts: loaded(HomeAlerts(firingCount: firing, bySeverity: bySeverity, top: top))).first { $0.kind == .moreAlerts }
    }
    let row = try #require(more(7, ["P0": 1, "P1": 4, "P2": 2, "P3": 0]))
    #expect(row.title == "另有 2 条告警中" && row.tone == .critical)
    #expect(row.destination == .alertsSegment && row.id == "alerts-more")
    #expect(more(6, ["P0": 0, "P1": 3, "P2": 2, "P3": 1])?.tone == .neutral)
    #expect(more(6, ["P1": 3, "P2": 2, "S9": 1])?.tone == .caution)
    #expect(more(6, [:])?.tone == .caution)
    #expect(more(5, ["P1": 3, "P2": 2]) == nil)
    // A row resolved here is not “另有” before the next read.
    #expect(more(2, ["P0": 1, "P1": 1], top: [HomeTestData.event(1), HomeTestData.event(9, severity: "P0").resolvedLocally(at: now)]) == nil)
}

// MARK: Account rows (R12, 20 §0.2)

@Test func errorRowReasonMatchesAccountDisplayStateAndNeverErrorMessage() throws {
    let summary = HomeTestData.summary(totals: AccountStateCounts(total: 1, error: 1), accounts: [errorAccount])
    func errorRow(_ structured: [UpstreamAccount]) throws -> AttentionItem {
        try #require(items(availability: loaded(summary), structuredErrors: structured).first)
    }
    let structured = HomeTestData.structuredError(7, summary: "401 凭据失效", errorAt: after(-60))
    let row = try errorRow([HomeTestData.structuredError(99, summary: "别的账号", errorAt: nil), structured])
    #expect(row.title == "OpenAI 主号" && row.badgeText(now: now) == "错误")
    #expect(row.detail == "401 凭据失效")
    #expect(row.footnote == "OpenAI · 1 分钟前")
    #expect(row.tone == .critical && row.kind == .errorAccount && row.id == "account-7")
    #expect(row.destination == .account(id: 7) && row.action == .accountTest(id: 7))
    #expect(row.detail == AccountDisplayState(errorAccount, structuredError: structured, now: now).reason)

    let blank = HomeTestData.structuredError(7, summary: "  ", errorAt: nil)
    let blankRow = try errorRow([blank])
    #expect(blankRow.detail == "上游返回异常" && blankRow.footnote == "OpenAI")
    #expect(blankRow.detail == AccountDisplayState(errorAccount, structuredError: blank, now: now).reason)
    let unmatched = try errorRow([])
    #expect(unmatched.detail == AccountDisplayState.unknownErrorReason && unmatched.footnote == "OpenAI")
    for item in [row, blankRow, unmatched] { #expect(!strings(item).contains { $0.contains("secret") }) }
}

@Test func overloadedRowFixedReasonCountdownAndStoppedMark() throws {
    let summary = HomeTestData.summary(totals: AccountStateCounts(total: 1, overloaded: 1, stopped: 1), accounts: [overloadedAccount])
    let row = try #require(items(availability: loaded(summary)).first)
    #expect(row.kind == .overloadedAccount && row.id == "account-8" && row.tone == .critical)
    #expect(row.title == "GLM 备用")
    #expect(row.badgeText(now: now) == "过载中 1:12")
    #expect(row.countdownTarget == after(72))
    #expect(row.detail == "上游 529 · 智谱 GLM")
    #expect(AccountDisplayState(overloadedAccount, now: now).reason == "上游 529")
    #expect(row.detailMark == AccountDisplayState.stoppedMark)
    #expect(row.destination == .account(id: 8) && row.action == nil)
    #expect(row.badgeText(now: after(77)) == "过载中 0:00")
    #expect(row.countdownElapsed(at: after(77)) && !row.countdownElapsed(at: now))
    // Read after the window: the row keeps the server's state until the next refresh.
    let late = try #require(items(availability: loaded(summary), at: after(100)).first)
    #expect(late.detail == "上游 529 · 智谱 GLM" && late.detailMark == AccountDisplayState.stoppedMark && late.countdownTarget == after(72))
    let scheduling = HomeTestData.account(8, name: "GLM 备用", platform: "zhipu", state: .overloaded, overload: after(72))
    let running = try #require(items(availability: loaded(HomeTestData.summary(accounts: [scheduling]))).first)
    #expect(running.detailMark == nil)
}

@Test func limitedRowMergesNamesEarliestAndStoppedThirdLine() throws {
    let summary = HomeTestData.summary(totals: AccountStateCounts(total: 3, rateLimited: 2, tempUnschedulable: 1, stopped: 1), accounts: limitedAccounts)
    let row = try #require(items(availability: loaded(summary)).first)
    #expect(row.kind == .limitedAccounts && row.id == "limited" && row.tone == .caution)
    #expect(row.title == "受限 3 个账号")
    #expect(row.detail == "a、b、c")
    #expect(row.trailingText(now: now) == "最早 4:37" && row.countdownTarget == after(277))
    #expect(row.stoppedNames == "b")
    #expect(row.destination == .limitedAccounts)
    #expect(HomePresentation.limitedItem(summary, now: now) == row)
    let running = HomeTestData.summary(totals: AccountStateCounts(rateLimited: 1), accounts: [limitedAccounts[0]])
    #expect(HomePresentation.limitedItem(running, now: now)?.stoppedNames == nil)
    #expect(HomePresentation.limitedItem(HomeTestData.summary(accounts: [errorAccount]), now: now) == nil)
}

@Test func limitedRowUsesTotalsAndEllipsisWhenTruncated() throws {
    let listed = Array(limitedAccounts.prefix(2))
    let truncated = HomeTestData.summary(totals: AccountStateCounts(rateLimited: 9, tempUnschedulable: 3), accounts: listed, truncated: true)
    let row = try #require(HomePresentation.limitedItem(truncated, now: now))
    #expect(row.title == "受限 12 个账号" && row.detail == "a、b等")
    let complete = HomeTestData.summary(totals: AccountStateCounts(rateLimited: 2), accounts: listed)
    #expect(HomePresentation.limitedItem(complete, now: now)?.title == "受限 2 个账号")
    #expect(HomePresentation.limitedItem(complete, now: now)?.detail == "a、b")
}

@Test func modelOnlyRateLimitAndUnknownStateStayOut() {
    let modelOnly = HomeTestData.account(20, state: .available, modelLimits: [AccountModelRateLimit(model: "gpt-5", resetAt: after(60))])
    let unknown = HomeTestData.account(21, state: nil, rate: after(60))
    let summary = HomeTestData.summary(totals: AccountStateCounts(total: 2, available: 1), accounts: [modelOnly, unknown])
    #expect(items(availability: loaded(summary)).isEmpty)
    #expect(HomePresentation.limitedItem(summary, now: now) == nil)
}

// MARK: Group shortage (U05)

@Test func groupShortageFilterSortToneAndDestination() throws {
    let standard = HomeTestData.group(2, name: "标准组", available: 1, total: 3, error: 1)
    let enterprise = HomeTestData.group(5, name: "企业专线", available: 0, total: 2, rateLimited: 1)
    let ignored = [
        HomeTestData.group(6, name: "停用组", available: 0, total: 2, error: 1, status: "inactive"),
        HomeTestData.group(7, name: "宽裕组", available: 1, total: 2, error: 1, isShort: false),
        HomeTestData.group(8, name: "暂停组", available: 0, total: 2, paused: 2)
    ]
    let summary = HomeTestData.summary(groups: [standard] + ignored + [enterprise])
    let row = try #require(items(availability: loaded(summary)).first)
    #expect(row.kind == .groupShortage && row.id == "groups")
    #expect(row.title == "可用不足 2 个分组" && row.detail == "企业专线 0/2 · 标准组 1/3")
    #expect(row.tone == .critical && row.destination == .groupsAttention)
    #expect(HomePresentation.shortageGroups(summary).map(\.groupID) == [5, 2])

    let single = try #require(items(availability: loaded(HomeTestData.summary(groups: [standard]))).first)
    #expect(single.title == "可用不足 1 个分组" && single.tone == .caution && single.destination == .group(id: 2))
    let tie = HomeTestData.summary(groups: [HomeTestData.group(9, name: "", available: 1, total: 2, error: 1), HomeTestData.group(4, name: "乙", available: 2, total: 4, error: 1)])
    #expect(HomePresentation.shortageGroups(tie).map(\.groupID) == [4, 9])
    #expect(items(availability: loaded(tie)).first?.detail == "乙 2/4 · 分组 #9 1/2")
    #expect(HomePresentation.shortageGroups(HomeTestData.summary(groups: ignored)).isEmpty)
}

// MARK: Money records (R02)

@Test func pendingMoneyRowsTitlesDetailsAmountsAndDestinations() throws {
    let add = HomeTestData.balance(.add, amount: "50")
    let refund = HomeTestData.balance(.set, amount: "0", createdAt: after(-200))
    let exact = HomeTestData.balance(.subtract, amount: "12.345", createdAt: after(-100))
    let legacy = try HomeTestData.legacyBalance()
    let batch = HomeTestData.batch(), subscriptionBatch = HomeTestData.batch(.subscription, value: "0", count: 3, createdAt: after(-40))
    let grant = HomeTestData.compensation(), dayGrant = HomeTestData.compensation(.concurrency, value: "2", createdAt: after(-30))
    let result = items(pending: [dayGrant, subscriptionBatch, exact, grant, batch, refund, add, legacy])
    let records: [any PendingMoneyWrite] = [legacy, add, refund, exact, batch, subscriptionBatch, grant, dayGrant]
    #expect(result.map(\.id) == records.map { "pending-" + $0.id.uuidString.lowercased() })
    #expect(result.map(\.kind) == [.pendingBalance, .pendingBalance, .pendingBalance, .pendingBalance, .pendingRedeemBatch, .pendingRedeemBatch,
                                   .pendingCompensation, .pendingCompensation])
    #expect(result.allSatisfy { $0.tone == .caution && $0.countdownTarget == nil })
    #expect(result.map(\.title) == ["充值结果待核对", "充值结果待核对", "退款结果待核对", "退款结果待核对", "兑换码生成结果待核对", "兑换码生成结果待核对",
                                    "补偿结果待核对", "补偿结果待核对"])
    #expect(result.map { $0.trailingText(now: now) } == ["$12.50", "$50.00", "全部余额", "$12.345", "$200.00", nil, "$5.00", nil])
    #expect(result.map(\.detail) == ["用户 #7 · 未确认是否入账", "周婷 · 5 分钟前 · 未确认是否入账", "周婷 · 3 分钟前 · 未确认是否入账",
                                     "周婷 · 1 分钟前 · 未确认是否入账", "20 个 · 5 分钟前 · 未确认是否生成", "3 个 · 刚刚 · 未确认是否生成",
                                     "李雷 · 5 分钟前 · 未确认是否发放", "李雷 · 刚刚 · 未确认是否发放"])
    #expect(result.map(\.destination) == [.user(id: 7), .user(id: 7), .user(id: 7), .user(id: 7), .redeemReconcile, .redeemReconcile,
                                          .compensation(userID: 8, pendingID: grant.id), .compensation(userID: 8, pendingID: dayGrant.id)])
    for (row, record) in zip(result, records) {
        let line = PendingMoneyWriteLine(record.summary)
        #expect(row.title == line.title)
        #expect(row.detail == line.detail(relativeTime: record.summary.createdAt.map { DisplayFormat.relativeTime($0, now: now, timeZone: shanghai) }))
    }
}

// MARK: 10 §1.5 failure rows

@Test func failureRowsAreNeutralRetryRowsAtTheirSlot() throws {
    let failedAvailability = items(availability: .failed(reason: "加载失败", previous: nil, at: nil))
    #expect(failedAvailability.map(\.id) == ["retry-availability"])
    let retry = try #require(failedAvailability.first)
    #expect(retry.kind == .availabilityFailed && retry.tone == .neutral && retry.title == "账号状态读取失败 · 重试")
    #expect(retry.destination == .retryAvailability && retry.title == HomePresentation.availabilityFailedTitle)
    #expect(items(availability: .disabled(reason: "X")).map(\.id) == ["retry-availability"])

    let failedAlerts = items(alerts: .failed(reason: "加载超时", previous: nil, at: nil))
    #expect(failedAlerts.map(\.id) == ["retry-alerts"])
    let alertRetry = try #require(failedAlerts.first)
    #expect(alertRetry.kind == .alertsFailed && alertRetry.tone == .neutral && alertRetry.title == "告警读取失败 · 重试")
    #expect(alertRetry.destination == .retryAlerts && alertRetry.title == HomePresentation.alertsFailedTitle)
    #expect(items(alerts: .disabled(reason: "OPS_DISABLED")).isEmpty)

    // An earlier value keeps its rows behind the retry row; money rows are local and unaffected.
    let oldAlerts = HomeAlerts(firingCount: 1, bySeverity: ["P1": 1], top: [HomeTestData.event(41)])
    let oldSummary = HomeTestData.summary(totals: AccountStateCounts(total: 1, error: 1), accounts: [errorAccount])
    let balance = HomeTestData.balance()
    let stale = items(alerts: .failed(reason: "加载失败", previous: oldAlerts, at: now), availability: .failed(reason: "加载失败", previous: oldSummary, at: now),
                      pending: [balance])
    #expect(stale.map(\.id) == ["retry-alerts", "alert-41", "retry-availability", "account-7", "pending-" + balance.id.uuidString.lowercased()])
}

@Test func homeDestinationsAreDistinct() {
    let grant = UUID()
    let all: [HomeDestination] = [.analytics, .performanceTrend(.rpm), .performanceTrend(.tpm), .alert(id: 1), .alertsSegment, .account(id: 1),
                                  .accountTest(id: 1), .limitedAccounts, .group(id: 1), .groupsAttention, .user(id: 1), .redeemReconcile,
                                  .compensation(userID: 1, pendingID: grant), .retryAvailability, .retryAlerts]
    #expect(Set(all).count == all.count)
    #expect(HomeRateMetric.allCases.map(\.rawValue) == ["rpm", "tpm"])
}
