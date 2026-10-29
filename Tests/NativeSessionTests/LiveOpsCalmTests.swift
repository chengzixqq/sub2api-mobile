import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-11: the calm layout's session side — its `-ui-testing` fixtures and what S1-05's LiveOpsStore leaves to the layout when the
// ranking fails or the layout goes away (10 §2.3, §2.6, §2.7).

private let base = Date()
private let zone = LiveOpsFixtures.serverTimeZone
private let serverFailure = APIError.server(status: 500, reason: nil)

private func blocks(_ source: FixtureLiveOpsSource, noCache: Bool) async throws -> HomeBlocks {
    HomeBlocks().merging(try await source.dashboardHome(timezone: zone, include: nil, noCache: noCache), receivedAt: base)
}
private func isCalm(_ blocks: HomeBlocks) -> Bool { HomePresentation.isCalm(availability: blocks.availability, alerts: blocks.alerts, pending: []) }

// MARK: Fixtures

/// The first read is calm whatever it asks; the first read past the cache after it (a pull or ··· 刷新) finds error account #7,
/// and every read after keeps it, so a UI test switches back to the regular layout without waiting for a timer.
@Test func calmThenErrorFixtureSwitchesOnTheFirstPullAndStays() async throws {
    let options = LiveOpsFixtures.Options(arguments: [LiveOpsFixtures.Argument.calmThenError])
    #expect(LiveOpsFixtures.Argument.calmThenError == "-ui-home-calm-then-error")
    #expect(options.variant == .calm && options.calmThenError && !options.calmErrorAppeared)
    #expect(!LiveOpsFixtures.Options(arguments: [LiveOpsFixtures.Argument.calm]).calmThenError)
    let source = FixtureLiveOpsSource(options: options, base: base)
    #expect(isCalm(try await blocks(source, noCache: true)))
    #expect(isCalm(try await blocks(source, noCache: false)))
    #expect(await source.errorAccounts().isEmpty)
    let pulled = try await blocks(source, noCache: true)
    let summary = try #require(pulled.availability.value)
    #expect(!isCalm(pulled) && summary.totals.error == 1 && summary.totals.available == 8)
    #expect(summary.errorAccountIDs == [LiveOpsFixtureIDs.errorAccount])
    let structured = await source.errorAccounts()
    #expect(structured.map(\.id) == [LiveOpsFixtureIDs.errorAccount])
    let queue = HomePresentation.attentionItems(alerts: pulled.alerts, availability: pulled.availability,
                                                structuredErrors: summary.aligningStructuredErrors(structured), pending: [], now: base,
                                                timeZone: zone.timeZone)
    #expect(queue.map(\.id) == ["account-7"])
    #expect(!isCalm(try await blocks(source, noCache: false)))
}

/// 来源 S1D1-11: the calm ranking of AccountDemoStore's accounts; channels 8 with 7 healthy and 1 unknown in both calm variants.
@Test func calmFixturesRankingAndChannels() async throws {
    let calm = FixtureLiveOpsSource(options: .init(variant: .calm), base: base)
    let rows = HomePresentation.rankingRows(await calm.accountsRanking(limit: LiveOpsStore.rankingLimit, timezone: zone))
    #expect(rows.map(\.accountID) == [1, 2, 4, 3] && rows[0].ratio == 1)
    #expect(rows[0].name == "Claude-官方-01" && rows[0].amount == "$409.38" && rows[0].detail == "Anthropic · 4,418 次请求")
    #expect(rows[2].detail == "OpenAI · 5,500 次请求" && rows[3].amount == "$192.62")
    let limited = FixtureLiveOpsSource(options: .init(variant: .calmLimited), base: base)
    #expect(HomePresentation.rankingRows(await limited.accountsRanking(limit: LiveOpsStore.rankingLimit, timezone: zone)).count == 2)
    for source in [calm, limited] {
        let channels = try #require(try await blocks(source, noCache: false).channels.value)
        #expect(HomePresentation.channelCountTitle(channels) == "8 个渠道")
        #expect(HomePresentation.channelSummaryLine(channels).map(\.text) == ["可用 7", "未知 1"])
    }
    let regular = try await blocks(FixtureLiveOpsSource(options: .init(), base: base), noCache: false)
    #expect(regular.channels.value?.total == 10)
}

// MARK: LiveOpsStore (S1-05) as the calm layout reads it

/// 10 §2.6: a failed ranking read changes nothing else; the section stays hidden until a read succeeds.
@MainActor @Test func rankingFailureLeavesHomeBlocksAndLayoutUnchanged() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }, ranking: { throw serverFailure }))
    let store = LiveOpsHarness(source).store
    await store.refreshHome(noCache: false)
    let before = store.home
    let calmBefore = HomePresentation.isCalm(availability: before.availability, alerts: before.alerts, pending: [])
    store.setCalmVisible(true)
    await store.rankingTask?.value
    #expect(store.ranking.value == nil && store.ranking.error != nil)
    #expect(store.home == before && store.lastFullSuccessAt == before.lastFullSuccessAt && !store.homeFailed)
    #expect(HomePresentation.isCalm(availability: store.home.availability, alerts: store.home.alerts, pending: []) == calmBefore)
    #expect(HomePresentation.calmRanking(store.ranking.state, refresh: store.ranking.refresh).isEmpty)
    await source.update { $0.ranking = { [AccountsRankingItem(accountID: 1, actualCost: 5)] } }
    await store.refreshHome(noCache: false)
    #expect(HomePresentation.calmRanking(store.ranking.state, refresh: store.ranking.refresh).map(\.accountID) == [1])
}

/// 10 §2.7: only while the calm layout shows; a read still on its way when it goes away never lands.
@MainActor @Test func hidingTheCalmLayoutDropsARankingReadInFlight() async {
    let gate = SessionGate()
    let source = StubLiveOpsSource(.init(home: { _ in homeReply() }, ranking: {
        await gate.wait()
        return [AccountsRankingItem(accountID: 1, actualCost: 5)]
    }))
    let store = LiveOpsHarness(source).store
    store.setCalmVisible(true)
    await waitUntil { store.ranking.isLoading }
    store.setCalmVisible(false)
    #expect(!store.ranking.isLoading)
    await gate.open()
    await store.rankingTask?.value
    #expect(store.ranking.value == nil)
    await store.refreshHome(noCache: false)
    #expect(await source.count { if case .ranking = $0 { true } else { false } } == 1)
}
