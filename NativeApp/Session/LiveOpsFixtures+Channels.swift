import Foundation
import Sub2Core

// S1-15: the channel list of `-ui-testing` (10 §5), one channel per active DEMO.groups group (6 测试组 is inactive, and the server
// lists active groups only). The overview's channel counts come from the same list, so 首页 and 监控 · 渠道 agree.

/// Switches for the channel monitor; they go with any home variant, and the ops switch does not touch them (10 §5.2).
struct ChannelFixtureOptions: Equatable, Sendable {
    /// features.channel_monitor_enabled false (DemoData.adminMe reads it too), overview 403 CHANNEL_MONITOR_DISABLED, home's block
    /// disabled.
    static let monitorOffArgument = "-ui-channel-monitor-off"
    /// The overview answers 503, so 渠道 shows “—” and 渠道加载失败 · 重试.
    static let failsArgument = "-ui-channel-overview-fails"
    /// coverage.state stale, so 渠道 shows the collection-delay note.
    static let coverageStaleArgument = "-ui-channel-coverage-stale"
    var monitorOff = false
    var fails = false
    var coverageStale = false

    init(monitorOff: Bool = false, fails: Bool = false, coverageStale: Bool = false) {
        self.monitorOff = monitorOff; self.fails = fails; self.coverageStale = coverageStale
    }
    init(arguments: [String]) {
        self.init(monitorOff: arguments.contains(Self.monitorOffArgument), fails: arguments.contains(Self.failsArgument),
                  coverageStale: arguments.contains(Self.coverageStaleArgument))
    }
}

extension LiveOpsFixtures {
    static let channelMonitorDisabledError = APIError.server(status: 403, reason: ChannelSectionPresentation.channelMonitorDisabledReason)

    /// The default: 1 unavailable, 1 degraded, 4 unknown (no collection, few samples, stale, none) and 3 available, one of them with
    /// 19 buckets (a window not on the five minutes). The calm variants: 7 available and Kimi 组 without samples.
    static func channelOverview(_ options: Options, base: Date) -> ChannelOverview {
        let calm = [HomeVariant.calm, .calmLimited].contains(options.variant)
        let coverage = ChannelCoverage(state: options.channels.coverageStale ? "stale" : "complete", collectorState: "healthy")
        return ChannelOverview(refreshIntervalSeconds: 60, coverage: coverage, items: (calm ? calmChannels : defaultChannels).map { $0.item(base: base) })
    }
    /// The overview's channel block: the counts of the same list, or disabled with the channel monitor off.
    static func homeChannels(_ options: Options, base: Date) -> HomeSection<HomeChannels> {
        guard !options.channels.monitorOff else {
            return HomeSection(status: .disabled, reason: ChannelSectionPresentation.channelMonitorDisabledReason)
        }
        return .ok(HomeFallback.homeChannels(channelOverview(options, base: base)))
    }
    /// FixtureLiveOpsSource's `channelOverview`.
    static func channelReply(_ options: Options, base: Date) throws -> ChannelOverview {
        if options.channels.monitorOff { throw channelMonitorDisabledError }
        if options.channels.fails { throw FixtureLiveOpsSource.unreachableError }
        return channelOverview(options, base: base)
    }

    private static let defaultChannels = [
        FixtureChannel(id: 8, name: "Kimi 组", platform: "kimi", state: "critical", reason: "recent_traffic", reliability: 0.69, successes: 690,
                       errors: 310, sample: "sufficient", strip: "gggggggggwwrrrrrrr"),
        FixtureChannel(id: 5, name: "Claude Code 组", platform: "anthropic", state: "warning", reason: "recent_traffic", reliability: 0.975,
                       p50: 8_600, strip: "ggggggggggggwgwgww"),
        FixtureChannel(id: 10, name: "Antigravity 组", platform: "antigravity", state: "unknown", reason: "collection_unavailable",
                       strip: String(repeating: ".", count: 18)),
        FixtureChannel(id: 7, name: "GLM 组", platform: "zhipu", state: "unknown", reason: "insufficient_samples", reliability: 1, successes: 3,
                       errors: 0, sample: "insufficient", strip: "gggggg"),
        FixtureChannel(id: 9, name: "MiniMax 组", platform: "minimax", state: "stale", reason: "traffic_expired", reliability: 0.99,
                       strip: "gggggggggggg......"),
        FixtureChannel(id: 3, name: "默认组", platform: "deepseek", state: "unknown", reason: "no_samples", sample: "no_samples", strip: ""),
        FixtureChannel(id: 4, name: "企业专线", platform: "openai", state: "healthy", reliability: 0.992, p50: 1_100, strip: "gggggggwgggggggggg"),
        FixtureChannel(id: 2, name: "标准组", platform: "openai", state: "healthy", reliability: 0.999, p50: 900, strip: String(repeating: "g", count: 18)),
        FixtureChannel(id: 1, name: "高级组", platform: "anthropic", state: "healthy", reliability: 0.996, p50: 1_400,
                       strip: String(repeating: "g", count: 19))]
    private static let calmChannels = [
        FixtureChannel(id: 1, name: "高级组", platform: "anthropic", state: "healthy", reliability: 0.996, p50: 1_400),
        FixtureChannel(id: 2, name: "标准组", platform: "openai", state: "healthy", reliability: 0.999, p50: 900),
        FixtureChannel(id: 3, name: "默认组", platform: "deepseek", state: "healthy", reliability: 0.995, p50: 1_200),
        FixtureChannel(id: 4, name: "企业专线", platform: "openai", state: "healthy", reliability: 0.992, p50: 1_100),
        FixtureChannel(id: 5, name: "Claude Code 组", platform: "anthropic", state: "healthy", reliability: 0.994, p50: 1_600),
        FixtureChannel(id: 7, name: "GLM 组", platform: "zhipu", state: "healthy", reliability: 0.991, p50: 1_300),
        FixtureChannel(id: 9, name: "MiniMax 组", platform: "minimax", state: "healthy", reliability: 0.993, p50: 1_500),
        FixtureChannel(id: 8, name: "Kimi 组", platform: "kimi", state: "unknown", reason: "no_samples", sample: "no_samples", strip: "")]
}

/// One fixture channel. `strip` is its buckets, oldest first, the last one at `base`, five minutes apart: g healthy, w warning,
/// r critical, . unknown.
private struct FixtureChannel {
    let id: Int
    let name: String
    let platform: String
    let state: String
    var reason: String?
    var reliability: Double?
    var successes: Int?
    var errors: Int?
    var sample: String?
    var p50: Double?
    var strip = String(repeating: "g", count: 18)

    func item(base: Date) -> ChannelItem {
        let metrics = ChannelMetrics(reliabilityRate: reliability, channelErrors: errors, successRequests: successes,
                                     sampleState: sample ?? (state == "unknown" ? nil : "sufficient"), ttft: ChannelLatency(p50Ms: p50))
        return ChannelItem(platform: platform, groupID: id, groupName: name, currentStatus: ChannelCurrentStatus(state: state, reason: reason, updatedAt: base),
                           metrics: metrics, buckets: buckets(base: base))
    }
    private func buckets(base: Date) -> [ChannelBucket] {
        let words: [Character: String] = ["g": "healthy", "w": "warning", "r": "critical", ".": "unknown"]
        return strip.enumerated().map { index, cell in
            ChannelBucket(bucketStart: base.addingTimeInterval(-Double(strip.count - 1 - index) * 300), reliability: words[cell])
        }
    }
}
