import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-15: the `-ui-testing` channel list (LiveOpsFixtures+Channels.swift), which the overview's channel counts come from too.

private let base = ServerTime.parseTimestamp("2026-10-16T02:00:00Z")!
private func refused(_ call: () async throws -> Void) async -> APIError? {
    do { try await call(); return nil } catch { return error as? APIError }
}

/// DEMO.groups' active groups (6 测试组 is inactive, so the server leaves it out): every status, reason and sample note.
@Test func defaultFixtureCoversEveryChannelState() throws {
    let overview = LiveOpsFixtures.channelOverview(LiveOpsFixtures.Options(), base: base)
    #expect(overview.items.count == 9 && overview.refreshIntervalSeconds == 60)
    #expect(ChannelPresentation.counts(overview.items) == ChannelCounts(available: 3, degraded: 1, unavailable: 1, unknown: 4))
    let sorted = ChannelPresentation.sorted(overview.items)
    #expect(sorted.map(\.groupID) == [8, 5, 10, 7, 9, 3, 4, 2, 1])
    #expect(sorted.map(ChannelPresentation.note) == ["错误率 31.0% · 首字 —", "可用率 97.5% · 首字 8.6s", "采集不可用", "样本不足", "数据已过期",
                                                     "无样本", "可用率 99.2% · 首字 1.1s", "可用率 99.9% · 首字 900ms", "可用率 99.6% · 首字 1.4s"])
    let buckets = Dictionary(uniqueKeysWithValues: overview.items.map { ($0.groupID, $0.buckets) })
    #expect(buckets[1]?.count == 19 && buckets[7]?.count == 6 && buckets[3]?.isEmpty == true)
    #expect(overview.items.filter { ![1, 7, 3].contains($0.groupID) }.allSatisfy { $0.buckets.count == 18 })
    let premium = try #require(buckets[1]), glm = try #require(buckets[7])
    #expect(ChannelPresentation.strip(premium).count == 18)
    #expect(ChannelPresentation.strip(glm).prefix(12).allSatisfy { $0 == nil } && ChannelPresentation.strip(glm).suffix(6).allSatisfy { $0 == .ok })
    #expect(ChannelPresentation.strip([]).allSatisfy { $0 == nil })
    #expect(premium.map(\.bucketStart) == premium.map(\.bucketStart).sorted { ($0 ?? .distantPast) < ($1 ?? .distantPast) })
    #expect(premium.last?.bucketStart == base)
    #expect(!ChannelPresentation.showsCoverageHint(overview.coverage))
    #expect(Set(overview.items.filter { $0.platform == "anthropic" }.map(\.groupID)) == [1, 5])
}

/// The calm variants keep S1-11's 8 channels: 7 available and 1 without samples.
@Test func calmFixtureMatchesCalmHomeChannels() {
    for variant in [LiveOpsFixtures.HomeVariant.calm, .calmLimited] {
        let options = LiveOpsFixtures.Options(variant: variant)
        let overview = LiveOpsFixtures.channelOverview(options, base: base)
        #expect(overview.items.count == 8)
        #expect(ChannelPresentation.counts(overview.items) == ChannelCounts(available: 7, unknown: 1))
        #expect(LiveOpsFixtures.homeChannels(options, base: base).data == HomeChannels(total: 8, healthy: 7, unknown: 1, coverageState: "complete",
                                                                                         collectorState: "healthy"))
    }
}

@Test func homeChannelsDerivedFromOverview() {
    let options = LiveOpsFixtures.Options()
    let home = LiveOpsFixtures.home(options, base: base, events: [])
    #expect(home.channels.status == .ok)
    #expect(home.channels.data == HomeFallback.homeChannels(LiveOpsFixtures.channelOverview(options, base: base)))
    #expect(home.channels.data == HomeChannels(total: 9, healthy: 3, warning: 1, critical: 1, unknown: 4, coverageState: "complete",
                                               collectorState: "healthy"))
    let off = LiveOpsFixtures.home(LiveOpsFixtures.Options(arguments: [ChannelFixtureOptions.monitorOffArgument]), base: base, events: [])
    #expect(off.channels.status == .disabled && off.channels.reason == "CHANNEL_MONITOR_DISABLED" && off.channels.data == nil)
}

@Test func channelArgumentsParse() {
    #expect(ChannelFixtureOptions(arguments: ["-ui-channel-monitor-off"]) == ChannelFixtureOptions(monitorOff: true))
    #expect(ChannelFixtureOptions(arguments: ["-ui-channel-overview-fails"]) == ChannelFixtureOptions(fails: true))
    #expect(ChannelFixtureOptions(arguments: ["-ui-channel-coverage-stale"]) == ChannelFixtureOptions(coverageStale: true))
    #expect(ChannelFixtureOptions(arguments: ["-ui-channel-overview-unsupported"]) == ChannelFixtureOptions(unsupported: true))
    #expect(ChannelFixtureOptions(arguments: ["-ui-testing"]) == ChannelFixtureOptions())
    let arguments = ["-ui-channel-monitor-off", "-ui-channel-coverage-stale"]
    #expect(LiveOpsFixtures.Options(arguments: arguments).channels == ChannelFixtureOptions(arguments: arguments))
}

/// 10 §5.2, §5.5: the fixture site answers 403 CHANNEL_MONITOR_DISABLED, 503, a non-JSON 404 or a stale coverage; the ops switch changes
/// nothing.
@Test func fixtureSourceHonoursChannelOptions() async throws {
    func source(_ arguments: [String]) -> FixtureLiveOpsSource {
        FixtureLiveOpsSource(options: LiveOpsFixtures.Options(arguments: arguments), base: base)
    }
    let off = await refused { _ = try await source([ChannelFixtureOptions.monitorOffArgument]).channelOverview(range: "90m", refresh: false) }
    #expect(off?.statusCode == 403 && off?.reason == "CHANNEL_MONITOR_DISABLED")
    let failing = await refused { _ = try await source([ChannelFixtureOptions.failsArgument]).channelOverview(range: "90m", refresh: true) }
    #expect(failing?.statusCode == 503)
    let old = await refused { _ = try await source([ChannelFixtureOptions.unsupportedArgument]).channelOverview(range: "90m", refresh: false) }
    #expect(old?.statusCode == 404 && old?.kind == .unsupported)
    let stale = try await source([ChannelFixtureOptions.coverageStaleArgument]).channelOverview(range: "90m", refresh: false)
    #expect(stale.coverage?.state == "stale" && ChannelPresentation.showsCoverageHint(stale.coverage))
    let opsOff = try await source([LiveOpsFixtures.Argument.opsDisabled]).channelOverview(range: "90m", refresh: false)
    #expect(opsOff.items.count == 9)
}
