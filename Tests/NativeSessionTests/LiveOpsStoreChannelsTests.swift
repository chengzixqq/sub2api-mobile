import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// S1-15: LiveOpsStore's channel list for 监控 · 渠道 (10 §5.2, §5.5, §5.6; 00 §4.6).

private let serverFailure = APIError.server(status: 503, reason: "SERVICE_UNAVAILABLE")
private let disabledError = APIError.server(status: 403, reason: "CHANNEL_MONITOR_DISABLED")
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private func isChannelRead(_ call: StubLiveOpsSource.Call) -> Bool { if case .channels = call { true } else { false } }
private func overview(_ states: [String] = ["warning", "critical", "healthy"], interval: Int? = 60) -> ChannelOverview {
    ChannelOverview(refreshIntervalSeconds: interval, items: states.enumerated().map {
        ChannelItem(platform: "openai", groupID: $0.offset + 1, groupName: "组 \($0.offset + 1)", currentStatus: ChannelCurrentStatus(state: $0.element))
    })
}
/// A connected site whose `/admin/me` says the channel monitor is `enabled` (nil: an older server that does not say).
private func channelSite(_ enabled: Bool?) -> SiteSession {
    let me = AdminMe(user: .init(id: 1, role: "admin"), features: .init(opsMonitoringEnabled: true, channelMonitorEnabled: enabled),
                     server: .init(serverTimezone: liveOpsZone.identifier, serverUTCOffset: liveOpsZone.rawUTCOffset,
                                   capabilities: Set(liveOpsCapabilities.map(\.rawValue))))
    return SiteSession(me: me, credential: sessionTokens(), accessTokenScope: nil, serverTimeZone: liveOpsZone, clockOffset: 0, probedAt: Date())
}
@MainActor private func channelHarness(_ reply: @escaping @Sendable () async throws -> ChannelOverview, enabled: Bool? = true,
                            sleeper: PollSleeper = PollSleeper()) -> LiveOpsHarness {
    LiveOpsHarness(StubLiveOpsSource(.init(channels: reply)), site: channelSite(enabled), sleeper: sleeper)
}

@MainActor @Test func pollingRequestsNinetyMinutesWithoutRefresh() async {
    let harness = channelHarness({ overview() }, sleeper: PollSleeper(stopAfter: 1))
    await harness.store.channelsPolling()
    #expect(await harness.source.calls == [.channels(range: "90m", refresh: false)])
    #expect(harness.store.channels.value == overview())
    #expect(harness.store.channelSectionState == .list(updateFailed: false))
    #expect(await harness.sleeper.seconds == [60])
}

/// 10 §5.6: a pull asks the server past its cache.
@MainActor @Test func bypassCacheSendsRefreshTrue() async {
    let harness = channelHarness({ overview() })
    await harness.store.refreshChannels(bypassCache: true)
    await harness.store.refreshChannels(bypassCache: false)
    #expect(await harness.source.calls == [.channels(range: "90m", refresh: true), .channels(range: "90m", refresh: false)])
}

/// 10 §5.2: features.channel_monitor_enabled false shows the off state at once and sends nothing; the earlier list goes.
@MainActor @Test func featureOffSendsNothingAndClearsOldValue() async {
    let source = StubLiveOpsSource(.init(home: { _ in homeReply(channels: .ok(HomeChannels(total: 2, warning: 1, critical: 1))) },
                                         channels: { overview() }))
    let harness = LiveOpsHarness(source, site: channelSite(true))
    let store = harness.store
    await store.refreshHome(noCache: false)
    await store.refreshChannels(bypassCache: false)
    #expect(store.channels.value != nil && store.monitorSegmentCount(.channels) == 2)
    harness.context.site = channelSite(false)
    await store.refreshChannels(bypassCache: true)
    await store.channelsPolling()
    #expect(await source.count(isChannelRead) == 1)
    #expect(await harness.sleeper.seconds.isEmpty)
    #expect(store.channels.value == nil && store.channels.updatedAt == nil && store.channels.error == nil)
    #expect(store.channelSectionState == .disabled && store.channelsUnavailable)
    #expect(store.monitorSegmentCount(.channels) == nil)
}

@MainActor @Test func unknownFeatureStillRequests() async {
    let harness = channelHarness({ overview() }, enabled: nil)
    await harness.store.refreshChannels(bypassCache: false)
    #expect(await harness.source.count(isChannelRead) == 1)
    #expect(harness.store.channelMonitorFeatureEnabled == nil && !harness.store.channelsUnavailable)
}

/// 10 §5.5: 403 CHANNEL_MONITOR_DISABLED drops the earlier list (the count and the subtitle with it) until a read succeeds.
@MainActor @Test func disabledReplyClearsListUntilSuccess() async {
    let replies = Tally()
    let harness = channelHarness({ if replies.next() == 2 { throw disabledError }; return overview() })
    let store = harness.store
    await store.refreshChannels(bypassCache: false)
    #expect(store.monitorSegmentCount(.channels) == 2)
    await store.refreshChannels(bypassCache: false)
    #expect(store.monitor.channelsDisabledReason == "CHANNEL_MONITOR_DISABLED")
    #expect(store.channels.value == nil && store.channelSectionState == .disabled)
    #expect(store.monitorSegmentCount(.channels) == nil)
    #expect(store.monitorSubtitle(for: .channels, now: Date(), timeZone: shanghai) == "渠道 · 近 90 分钟")
    await store.refreshChannels(bypassCache: false)
    #expect(store.monitor.channelsDisabledReason == nil)
    #expect(store.channelSectionState == .list(updateFailed: false) && store.monitorSegmentCount(.channels) == 2)
}

/// 10 §5.5: another failure keeps the list (更新失败) and the off mark alike; without a list it is 渠道加载失败.
@MainActor @Test func failureKeepsPreviousListAndKeepsDisabledMark() async {
    let replies = Tally()
    let shown = channelHarness({ if replies.next() == 2 { throw serverFailure }; return overview() })
    await shown.store.refreshChannels(bypassCache: false)
    await shown.store.refreshChannels(bypassCache: false)
    #expect(shown.store.channels.value == overview() && shown.store.channelSectionState == .list(updateFailed: true))
    #expect(shown.store.monitor.channelsDisabledReason == nil)

    let offReplies = Tally()
    let off = channelHarness({ throw offReplies.next() == 1 ? disabledError : serverFailure })
    await off.store.refreshChannels(bypassCache: false)
    await off.store.refreshChannels(bypassCache: false)
    #expect(await off.source.count(isChannelRead) == 2)
    #expect(off.store.monitor.channelsDisabledReason == "CHANNEL_MONITOR_DISABLED" && off.store.channelSectionState == .disabled)

    let never = channelHarness({ throw serverFailure })
    await never.store.refreshChannels(bypassCache: false)
    #expect(never.store.channelSectionState == .failed && never.store.channels.lastError == serverFailure)
}

@MainActor @Test func forbiddenReplyIsNotDisabled() async {
    let harness = channelHarness({ throw APIError.server(status: 403, reason: "FORBIDDEN") })
    await harness.store.refreshChannels(bypassCache: false)
    #expect(harness.store.monitor.channelsDisabledReason == nil)
    #expect(harness.store.channelSectionState == .forbidden)
}

/// 00 §3.3: a site without channel-monitor-v2 (a non-JSON 404) shows 站点版本较旧 and is not asked again this session, a pull included.
@MainActor @Test func unsupportedRouteStopsChannelReadsForSession() async {
    let harness = channelHarness({ throw APIError.server(status: 404, envelope: nil) }, enabled: nil, sleeper: PollSleeper(stopAfter: 3))
    let store = harness.store
    await store.channelsPolling()
    #expect(await harness.source.count(isChannelRead) == 1)
    #expect(await harness.sleeper.seconds.isEmpty)
    #expect(store.monitor.channelsUnsupported && store.channelsUnavailable)
    #expect(store.channelSectionState == .unsupported && store.channels.error == nil && store.channels.value == nil)
    #expect(store.monitorSegmentCount(.channels) == nil && store.monitor.channelsDisabledReason == nil)
    await store.refreshChannels(bypassCache: true)
    await store.refreshChannels(bypassCache: false)
    await store.channelsPolling()
    #expect(await harness.source.count(isChannelRead) == 1)
    #expect(await harness.sleeper.seconds.isEmpty)
}

struct ChannelIntervalCase: Sendable, CustomTestStringConvertible {
    let seconds: Int?
    let wait: TimeInterval
    var testDescription: String { seconds.map(String.init) ?? "nil" }
}

/// 10 §5.6: refresh_interval_seconds, kept within 30–300; 60 without it.
@MainActor @Test(arguments: [ChannelIntervalCase(seconds: 120, wait: 120), ChannelIntervalCase(seconds: 10, wait: 30),
                             ChannelIntervalCase(seconds: 900, wait: 300), ChannelIntervalCase(seconds: nil, wait: 60)])
func pollIntervalFollowsServerSettingClamped(row: ChannelIntervalCase) async {
    let harness = channelHarness({ overview(interval: row.seconds) }, sleeper: PollSleeper(stopAfter: 1))
    await harness.store.channelsPolling()
    #expect(await harness.sleeper.seconds == [row.wait])
    #expect(harness.store.channelPollInterval == row.wait)
}

/// 00 §4.6: failures double the interval up to 300 seconds; a cancelled wait ends the timer.
@MainActor @Test func failuresBackOffFromInterval() async {
    let harness = channelHarness({ throw serverFailure }, sleeper: PollSleeper(stopAfter: 4))
    await harness.store.channelsPolling()
    #expect(await harness.sleeper.seconds == [120, 240, 300, 300])
    #expect(await harness.source.count(isChannelRead) == 4)
}

/// 00 §2.7.2: a 429 holds the next read for its wait; meanwhile nothing goes out.
@MainActor @Test func rateLimitWaitsBeforeNextRequest() async {
    let harness = channelHarness({ throw APIError.server(status: 429, envelope: nil, retryAfter: 30) }, sleeper: PollSleeper(stopAfter: 1))
    let store = harness.store
    await store.channelsPolling()
    #expect(await harness.sleeper.seconds == [30])
    await store.refreshChannels(bypassCache: false)
    await store.refreshChannels(bypassCache: true)
    #expect(await harness.source.count(isChannelRead) == 1)
    #expect(store.monitor.channelsDisabledReason == nil)
}

/// Coming back to the segment within ten seconds of the last answer waits out the rest before reading again.
@MainActor @Test func channelsPollingWaitsOutReentryGap() async {
    let recent = channelHarness({ overview() }, sleeper: PollSleeper(parks: true))
    await recent.store.refreshChannels(bypassCache: false)
    recent.advance(by: 4)
    let polling = Task { await recent.store.channelsPolling() }
    await waitUntil { await recent.sleeper.parkedCount == 1 }
    #expect(await recent.sleeper.seconds == [6])
    #expect(await recent.source.count(isChannelRead) == 1)
    await recent.sleeper.stop()
    await polling.value

    let older = channelHarness({ overview() }, sleeper: PollSleeper(parks: true))
    await older.store.refreshChannels(bypassCache: false)
    older.advance(by: 11)
    let next = Task { await older.store.channelsPolling() }
    await waitUntil { await older.sleeper.parkedCount == 1 }
    #expect(await older.sleeper.seconds == [60])
    #expect(await older.source.count(isChannelRead) == 2)
    await older.sleeper.stop()
    await next.value
}

/// 00 §4.6: an answer that lands after the session ended changes nothing, the off mark included.
@MainActor @Test func lateReplyAfterSessionEndIsDropped() async {
    let gate = SessionGate()
    let harness = channelHarness({ await gate.wait(); throw disabledError })
    let store = harness.store
    let read = Task { await store.refreshChannels(bypassCache: false) }
    await waitUntil { await gate.arrived }
    harness.isCurrent = false
    await gate.open()
    await read.value
    #expect(store.channels.value == nil && store.channels.error == nil)
    #expect(store.monitor.channelsDisabledReason == nil)
}

/// 10 §5.2: the ops switch does not gate the channel monitor.
@MainActor @Test func channelsIgnoreOpsSwitch() async {
    let harness = channelHarness({ overview() })
    let store = harness.store
    await store.noteOpsDisabled()
    #expect(store.opsDisabled)
    await store.refreshChannels(bypassCache: false)
    #expect(await harness.source.count(isChannelRead) == 1)
    #expect(store.channelSectionState == .list(updateFailed: false))
}

/// S1-13's count of the segment: unavailable + degraded of the list read.
@MainActor @Test func segmentCountUsesLoadedList() async {
    let base = Date()
    let harness = channelHarness({ LiveOpsFixtures.channelOverview(LiveOpsFixtures.Options(), base: base) })
    await harness.store.refreshChannels(bypassCache: false)
    #expect(harness.store.monitorSegmentCount(.channels) == 2)
    #expect(harness.store.channelPollInterval == 60)
}
