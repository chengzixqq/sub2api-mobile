import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-09: the three home variants the overview's UI tests launch with (-ui-home-loss, -ui-home-unreachable-once, -ui-home-pending).

private let base = Date()
private let zone = LiveOpsFixtures.serverTimeZone

private func cells(_ arguments: [String]) async throws -> [HomeTickerCell] {
    let source = FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: arguments), base: base)
    let home = try await source.dashboardHome(timezone: zone, include: nil, noCache: false)
    return HomePresentation.tickerCells(stats: home.stats.data, rates: home.rates.data, ratesSource: .home)
}

@Test func lossVariantProducesNegativeProfit() async throws {
    let options = LiveOpsFixtures.Options(arguments: [LiveOpsFixtures.Argument.profitLoss])
    #expect(options.profitLoss && options.variant == .allOK)
    let loss = try await cells([LiveOpsFixtures.Argument.profitLoss]), allOK = try await cells([])
    #expect(loss[3].value == "\u{2212}$115.50" && !loss[3].value.contains("+"))
    #expect(allOK[3].value == "$772.42")
    let others = [0, 1, 2, 4, 5]
    #expect(others.map { loss[$0] } == others.map { allOK[$0] })
}

@Test func unreachableOnceFailsOnlyTheFirstRound() async throws {
    #expect(LiveOpsFixtures.Options(arguments: [LiveOpsFixtures.Argument.homeUnreachableOnce]).failsFirstRound)
    #expect(!LiveOpsFixtures.Options(arguments: []).failsFirstRound && !LiveOpsFixtures.Options(arguments: []).pendingHome)
    let source = FixtureLiveOpsSource(options: .init(arguments: [LiveOpsFixtures.Argument.homeUnreachableOnce]), base: base)
    let first = await #expect(throws: APIError.self) { try await source.dashboardHome(timezone: zone, include: nil, noCache: false) }
    #expect(first?.statusCode == 503)
    let second = try await source.dashboardHome(timezone: zone, include: nil, noCache: true)
    #expect(second.stats.data?.todayRequests == 18_204 && second.degradedSections().isEmpty)
}

/// Through the store: a whole-home 5xx before any value is the full-page 无法连接到站点; 重试 fills the page.
@MainActor @Test func unreachableOnceLeadsTheOverviewThroughEmptyStateToContent() async {
    let source = FixtureLiveOpsSource(options: .init(arguments: [LiveOpsFixtures.Argument.homeUnreachableOnce]), base: base)
    let site = liveOpsSite(Capability.allCases)
    let store = LiveOpsStore(generation: UUID(), source: source, site: { site }, isCurrent: { true }, serverNow: { base })
    func state() -> HomeScreenState { HomeScreenState.resolve(isVendor: false, sections: store.home.phases, requestFailed: store.homeFailed) }
    #expect(state() == .skeleton)
    await store.refreshHome(noCache: false)
    #expect(state() == .unreachable && !store.isOnFallback)
    await store.refreshHome(noCache: true)
    #expect(state() == .content && store.home.stats.value?.todayRequests == 18_204)
}

@Test func pendingVariantWaitsUntilCancelled() async throws {
    let source = FixtureLiveOpsSource(options: .init(arguments: [LiveOpsFixtures.Argument.homePending]), base: base)
    let read = Task { try await source.dashboardHome(timezone: zone, include: nil, noCache: false) }
    try await Task.sleep(for: .milliseconds(200))
    read.cancel()
    await #expect(throws: CancellationError.self) { try await read.value }
}

/// S1-09b review: only the rates block times out, so the run section's rates row shows 加载超时 and nothing else changes.
@Test func ratesTimeoutVariantOnlyAffectsRates() async throws {
    let options = LiveOpsFixtures.Options(arguments: [LiveOpsFixtures.Argument.ratesTimeout, LiveOpsFixtures.Argument.profitLoss])
    #expect(options.ratesTimeout && options.variant == .allOK && options.profitLoss)
    #expect(!LiveOpsFixtures.Options(arguments: []).ratesTimeout)
    let timedOut = try await FixtureLiveOpsSource(options: .init(arguments: [LiveOpsFixtures.Argument.ratesTimeout]), base: base)
        .dashboardHome(timezone: zone, include: nil, noCache: false)
    let regular = try await FixtureLiveOpsSource(options: .init(), base: base).dashboardHome(timezone: zone, include: nil, noCache: false)
    #expect(timedOut.rates.status == .timeout && timedOut.rates.reason == "SECTION_TIMEOUT" && timedOut.degradedSections() == [.rates])
    #expect(timedOut.stats == regular.stats && timedOut.hourly == regular.hourly && timedOut.ops == regular.ops)
    #expect(timedOut.alerts == regular.alerts && timedOut.availability == regular.availability && timedOut.channels == regular.channels)
    let rates = HomeBlocks().merging(timedOut, receivedAt: base).rates
    #expect(rates.display == .failed(reason: HomeBlockText.timedOut) && BlockStatusPresentation.failureTitle(for: rates) == "加载超时")
}
