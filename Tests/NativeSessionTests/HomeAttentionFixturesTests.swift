import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-10: the 待处理 variants the overview's UI tests launch with (-ui-home-attention-extra, -ui-home-alerts-overflow,
// -ui-home-test-recovers), read through the same pure function the page uses.

private let base = Date()
private let zone = LiveOpsFixtures.serverTimeZone

private func queue(_ source: FixtureLiveOpsSource, noCache: Bool = false) async throws -> [AttentionItem] {
    let home = try await source.dashboardHome(timezone: zone, include: nil, noCache: noCache)
    let blocks = HomeBlocks().merging(home, receivedAt: base)
    let errors = blocks.availability.value?.aligningStructuredErrors(try await source.errorAccounts()) ?? []
    return HomePresentation.attentionItems(alerts: blocks.alerts, availability: blocks.availability, structuredErrors: errors, pending: [],
                                           now: base, timeZone: zone.timeZone)
}
private func source(_ arguments: [String]) -> FixtureLiveOpsSource {
    FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: arguments), base: base)
}
private func strings(_ item: AttentionItem) -> [String] {
    [item.title, item.detail, item.detailMark, item.footnote, item.stoppedNames, item.badgeText(now: base), item.trailingText(now: base)]
        .compactMap { $0 }
}

@Test func attentionVariantsParseAndGoWithAnyVariant() {
    let options = LiveOpsFixtures.Options(arguments: [LiveOpsFixtures.Argument.attentionExtra, LiveOpsFixtures.Argument.alertsOverflow,
                                                      LiveOpsFixtures.Argument.testRecovers])
    #expect(options.attentionExtra && options.alertsOverflow && options.testRecovers && options.variant == .allOK)
    #expect(!options.errorAccountRecovered)
    let plain = LiveOpsFixtures.Options(arguments: [])
    #expect(!plain.attentionExtra && !plain.alertsOverflow && !plain.testRecovers && !plain.errorAccountRecovered)
    #expect(LiveOpsFixtures.Argument.attentionExtra == "-ui-home-attention-extra")
    #expect(LiveOpsFixtures.Argument.alertsOverflow == "-ui-home-alerts-overflow")
    #expect(LiveOpsFixtures.Argument.testRecovers == "-ui-home-test-recovers")
}

@Test func attentionExtraStopsTimedAccountsAndAddsAnErrorWithoutStructuredFields() async throws {
    let items = try await queue(source([LiveOpsFixtures.Argument.attentionExtra]))
    #expect(items.map(\.id) == ["alert-41", "alert-40", "account-7", "account-10", "account-11", "limited", "groups"])
    let grok = items[3]
    #expect(grok.title == "Grok-旧-01" && grok.detail == AccountDisplayState.unknownErrorReason && grok.action == .accountTest(id: 10))
    #expect(items[2].detail == "401 凭据已失效（invalid_api_key）" && items[2].footnote == "OpenAI · 1 分钟前")
    #expect(items[4].detailMark == AccountDisplayState.stoppedMark && items[4].detail == "上游 529 · 智谱 GLM")
    #expect(items[5].title == "受限 2 个账号" && items[5].stoppedNames == "MiniMax-01")
    #expect(items.allSatisfy { !strings($0).contains { $0.contains(LiveOpsFixtures.sentinelErrorMessage) } })
    let errors = try await source([LiveOpsFixtures.Argument.attentionExtra]).errorAccounts()
    #expect(errors.first { $0.id == 10 }?.errorMessage == LiveOpsFixtures.sentinelErrorMessage)
    // The default keeps its queue.
    #expect(try await queue(source([]))
        .map(\.id) == ["alert-41", "alert-40", "account-7", "account-11", "limited", "groups"])
}

@Test func alertsOverflowListsFiveAndCountsTwoMore() async throws {
    let fixture = source([LiveOpsFixtures.Argument.alertsOverflow])
    let home = try await fixture.dashboardHome(timezone: zone, include: nil, noCache: false)
    #expect(home.alerts.data?.firingCount == 7 && home.alerts.data?.top.count == 5)
    #expect(home.alerts.data?.bySeverity.values.reduce(0, +) == 7)
    let items = try await queue(fixture)
    let alertRows = items.filter { $0.kind == .alert }
    #expect(alertRows.count == 5 && alertRows.first?.id == "alert-41")
    let more = try #require(items.first { $0.kind == .moreAlerts })
    #expect(more.title == "另有 2 条告警中" && more.tone == .caution && more.destination == .alertsSegment)
    #expect(items.firstIndex(of: more) == 5)
}

@Test func testRecoversDropsTheErrorAccountAfterTheFirstNoCacheRead() async throws {
    let fixture = source([LiveOpsFixtures.Argument.testRecovers])
    func errors(noCache: Bool) async throws -> (Int?, [Int]) {
        let summary = try await fixture.dashboardHome(timezone: zone, include: nil, noCache: noCache).availability.data
        return (summary?.totals.error, summary?.accounts.map(\.id) ?? [])
    }
    let first = try await errors(noCache: false)
    #expect(first.0 == 1 && first.1.contains(LiveOpsFixtureIDs.errorAccount))
    let polled = try await errors(noCache: false)
    #expect(polled.0 == 1 && polled.1.contains(LiveOpsFixtureIDs.errorAccount))
    let refreshed = try await errors(noCache: true)
    #expect(refreshed.0 == 0 && !refreshed.1.contains(LiveOpsFixtureIDs.errorAccount))
    let after = try await errors(noCache: false)
    #expect(after.0 == 0 && !after.1.contains(LiveOpsFixtureIDs.errorAccount))
    #expect(!(try await queue(fixture)).contains { $0.id == "account-7" })
    // Without the variant a pull changes nothing.
    let plain = source([])
    _ = try await plain.dashboardHome(timezone: zone, include: nil, noCache: true)
    #expect(try await plain.dashboardHome(timezone: zone, include: nil, noCache: false).availability.data?.totals.error == 1)
}
