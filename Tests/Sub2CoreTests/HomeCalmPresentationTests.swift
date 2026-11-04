import Foundation
import Testing
@testable import Sub2Core

// S1-11: the calm layout's outline, its 自动恢复中 meta and the 按账号 rows it shows (10 §2.2, §2.4, §2.6); S1-04's own cases of
// isCalm, calmFlag and rankingRows are in HomePresentationTests, only their edges are here.

private let now = HomeTestData.now
private func decimal(_ raw: String) -> Decimal { HomeTestData.decimal(raw) }
private func loaded<Value>(_ value: Value) -> BlockState<Value> { .loaded(value, at: now) }
private let quietAlerts = HomeAlerts(firingCount: 0, bySeverity: ["P0": 0, "P1": 0, "P2": 0, "P3": 0])
private let ranking = [
    AccountsRankingItem(accountID: 1, accountName: "Claude-官方-01", platform: "anthropic", requests: 4_418, actualCost: decimal("409.38")),
    AccountsRankingItem(accountID: 2, accountName: "Claude-官方-02", platform: "anthropic", requests: 4_050, actualCost: decimal("384.05"))
]

// MARK: Outline (10 §2.4)

@Test func calmOutlineNumbersRankingSecondAndChannelsThird() {
    let outline = HomePresentation.calmOutline(hasRanking: true)
    #expect(outline == HomeCalmOutline(hourlyOrdinal: "壹", rankingOrdinal: "贰", channelsOrdinal: "叁", moreStatsFollowsRanking: true))
}

@Test func calmOutlineRenumbersChannelsAndMovesMoreStatsWithoutRanking() {
    let outline = HomePresentation.calmOutline(hasRanking: false)
    #expect(outline.hourlyOrdinal == "壹" && outline.rankingOrdinal == nil && outline.channelsOrdinal == "贰")
    #expect(!outline.moreStatsFollowsRanking)
    #expect(HomePresentation.calmRankingMeta == "今日实际扣费 · 前 4")
    #expect(HomePresentation.calmRecoveringTitle == "自动恢复中")
}

// MARK: 自动恢复中 (10 §2.4)

@Test func calmRecoveringMetaCountsLikeTheLimitedRow() throws {
    let accounts = [HomeTestData.account(1, state: .rateLimited, rate: HomeTestData.after(60)),
                    HomeTestData.account(2, state: .rateLimited, rate: HomeTestData.after(90)),
                    HomeTestData.account(3, state: .tempUnschedulable, temp: HomeTestData.after(120)),
                    HomeTestData.account(4, state: .overloaded, overload: HomeTestData.after(60))]
    let summary = HomeTestData.summary(totals: AccountStateCounts(total: 6, available: 1, overloaded: 1, rateLimited: 2, tempUnschedulable: 1, paused: 1),
                                       accounts: accounts)
    #expect(HomePresentation.calmRecoveringMeta(summary) == "3 个")
    #expect(try #require(HomePresentation.limitedItem(summary, now: now)).title == "受限 3 个账号")
    // The server capped the list: the totals count, as the row's title does.
    let truncated = HomeTestData.summary(totals: AccountStateCounts(total: 1_300, rateLimited: 1_000, tempUnschedulable: 234),
                                         accounts: Array(accounts.prefix(3)), truncated: true)
    #expect(HomePresentation.calmRecoveringMeta(truncated) == "1,234 个")
    #expect(try #require(HomePresentation.limitedItem(truncated, now: now)).title == "受限 1,234 个账号")
    #expect(HomePresentation.calmRecoveringMeta(HomeTestData.summary(totals: AccountStateCounts(total: 2, available: 2))) == "0 个")
}

// MARK: 按账号 shown (10 §2.4, §2.6)

@Test func calmRankingShowsRowsOnlyWhileTheLastReadSucceeded() {
    let fresh = BlockRefresh()
    #expect(HomePresentation.calmRanking(loaded(ranking), refresh: fresh).map(\.accountID) == [1, 2])
    // A poll in flight keeps the rows it had.
    #expect(HomePresentation.calmRanking(.loading(previous: ranking, at: now), refresh: fresh).count == 2)
    // 2.6: a failed read hides the section, also while the next read is on its way, until one succeeds.
    let failed = fresh.recordingFailure(APIError.server(status: 500, reason: nil), at: now)
    #expect(HomePresentation.calmRanking(.failed(reason: HomeBlockText.failed, previous: ranking, at: now), refresh: failed).isEmpty)
    #expect(HomePresentation.calmRanking(.loading(previous: ranking, at: now), refresh: failed).isEmpty)
    // Never read (no dashboard.accounts_ranking) or nothing above 0.
    #expect(HomePresentation.calmRanking(.idle, refresh: fresh).isEmpty)
    #expect(HomePresentation.calmRanking(.loading(previous: nil, at: nil), refresh: fresh).isEmpty)
    #expect(HomePresentation.calmRanking(loaded([AccountsRankingItem(accountID: 9, requests: 3, actualCost: 0)]), refresh: fresh).isEmpty)
}

// MARK: Edges of S1-04's functions

@Test func isCalmEdgesNotCoveredByS104() {
    let tempOnly = HomeTestData.summary(totals: AccountStateCounts(total: 3, available: 2, tempUnschedulable: 1),
                                        accounts: [HomeTestData.account(1, state: .tempUnschedulable, temp: HomeTestData.after(60))])
    #expect(HomePresentation.isCalm(availability: loaded(tempOnly), alerts: loaded(quietAlerts), pending: []))
    let overloadedOnly = HomeTestData.summary(totals: AccountStateCounts(total: 1, overloaded: 1))
    #expect(!HomePresentation.isCalm(availability: loaded(overloadedOnly), alerts: .disabled(reason: "OPS_DISABLED"), pending: []))
    // X34: the caller passes the records of this address; one of an earlier login (another site id) keeps the layout regular.
    let earlierLogin = PendingBalanceOperation(serverID: UUID(), userID: 7, amount: 50, operation: .add, actorUserID: 1, createdAt: now)
    #expect(!HomePresentation.isCalm(availability: loaded(tempOnly), alerts: loaded(quietAlerts), pending: [earlierLogin]))
    #expect(!HomePresentation.isCalm(availability: loaded(tempOnly), alerts: loaded(quietAlerts), pending: [HomeTestData.compensation()]))
}

@Test func calmFlagEdges() {
    #expect(HomePresentation.calmFlag(totals: AccountStateCounts(), hasLimited: false).text == "✓ 全部正常 · 0 个账号可调度")
    #expect(HomePresentation.calmFlag(totals: AccountStateCounts(available: 12_840), hasLimited: true).text == "✓ 无需处理 · 12,840 个账号可调度")
}

@Test func rankingRowsEdges() {
    let tied = [AccountsRankingItem(accountID: 1, accountName: "甲", platform: "anthropic", requests: 12_840, actualCost: decimal("0.3")),
                AccountsRankingItem(accountID: 2, accountName: "乙", platform: "openai", requests: 1, actualCost: decimal("0.3")),
                AccountsRankingItem(accountID: 3, accountName: "丙", platform: "openai", requests: 1, actualCost: decimal("-1")),
                AccountsRankingItem(accountID: 4, accountName: "丁", platform: "gemini", requests: 1, actualCost: decimal("0.1") + decimal("0.2")),
                AccountsRankingItem(accountID: 5, accountName: "戊", platform: "openai", requests: 1, actualCost: decimal("0.2")),
                AccountsRankingItem(accountID: 6, accountName: "己", platform: "openai", requests: 1, actualCost: decimal("0.1"))]
    let rows = HomePresentation.rankingRows(tied)
    #expect(rows.map(\.accountID) == [1, 2, 4, 5])
    #expect(rows.prefix(3).allSatisfy { $0.ratio == 1 })
    #expect(rows.allSatisfy { $0.ratio <= 1 })
    #expect(rows[0].detail == "Anthropic · 12,840 次请求")
    let zeroFirst = [AccountsRankingItem(accountID: 7, requests: 9, actualCost: 0)] + Array(tied.prefix(1))
    #expect(HomePresentation.rankingRows(zeroFirst).map(\.accountID) == [1])
}
