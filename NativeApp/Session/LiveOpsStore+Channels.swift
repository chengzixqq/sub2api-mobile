import Foundation
import Observation
import Sub2Core

// S1-15, 10 §5: the monitor's channel list. 渠道 reads it while it shows, every `refresh_interval_seconds` (30–300, 60 without),
// backing off after failures and holding through a 429 wait; a pull asks past the server's cache. Only the channel monitor's own
// switch gates it, never the ops one (10 §5.2); a site without the route (a non-JSON 404) is not asked again this session (00 §3.3).
// The list is `channels`, which the alert detail's platform row reads too.

extension LiveOpsStore {
    /// `/admin/me`'s features.channel_monitor_enabled: false sends nothing; nil (a server that does not say) asks and lets a 403 tell.
    var channelMonitorFeatureEnabled: Bool? { site()?.me.features.channelMonitorEnabled }
    /// The switch says off, the last answer was 403 CHANNEL_MONITOR_DISABLED, or the site has no channel monitor route.
    var channelsUnavailable: Bool {
        channelMonitorFeatureEnabled == false || monitor.channelsDisabledReason != nil || monitor.channelsUnsupported
    }
    var channelSectionState: ChannelSectionState {
        ChannelSectionPresentation.state(featureEnabled: channelMonitorFeatureEnabled, disabledReason: monitor.channelsDisabledReason,
                                         unsupported: monitor.channelsUnsupported, display: channels.state.display, lastError: channels.lastError)
    }
    var channelPollInterval: TimeInterval { ChannelPresentation.refreshInterval(channels.value?.refreshIntervalSeconds) }

    /// `bypassCache` (a pull, ··· 刷新) sends refresh=true and replaces a read in flight; otherwise one in flight is left to finish.
    /// 403 CHANNEL_MONITOR_DISABLED drops the list until a read succeeds; any other failure keeps it.
    func refreshChannels(bypassCache: Bool) async {
        guard isCurrent(), site() != nil else { return }
        guard channelMonitorFeatureEnabled != false else { return clearChannels() }
        guard !monitor.channelsUnsupported, bypassCache || !channels.isAwaitingAnswer else { return }
        let source = source, answered = MonitorBlockLoad(channels).answeredAt
        await channels.load(isCurrent: isCurrent) {
            try await source.channelOverview(range: ChannelSectionPresentation.range, refresh: bypassCache)
        }
        guard isCurrent(), MonitorBlockLoad(channels).answeredAt != answered else { return }
        recordChannelsAnswer()
    }
    /// While the caller's task lives (渠道 showing, the App active). An answer under ten seconds old waits out the rest first.
    func channelsPolling() async {
        guard channelMonitorFeatureEnabled != false else { return clearChannels() }
        guard !monitor.channelsUnsupported else { return }
        if let wait = channelsReentryWait() {
            do { try await sleep(.seconds(wait)) } catch { return }
        }
        while !Task.isCancelled, isCurrent(), channelMonitorFeatureEnabled != false {
            await refreshChannels(bypassCache: false)
            guard !monitor.channelsUnsupported else { return }
            do { try await sleep(.seconds(channels.nextDelay(base: channelPollInterval))) } catch { return }
        }
    }

    /// The reason is read before the reset, which forgets the error.
    private func recordChannelsAnswer() {
        monitor.markChannelsSettled(at: localNow())
        if ChannelSectionPresentation.isUnsupported(channels.lastError) {
            monitor.markChannelsUnsupported()
            channels.reset()
        } else if let reason = ChannelSectionPresentation.disabledReason(channels.lastError) {
            monitor.recordChannelsReply(disabledReason: reason)
            channels.reset()
        } else if case .loaded = channels.state {
            monitor.recordChannelsReply(disabledReason: nil)
        }
    }
    private func clearChannels() {
        if case .idle = channels.state { return }
        channels.reset()
    }
    private func channelsReentryWait() -> TimeInterval? {
        guard let settled = monitor.channelsSettledAt else { return nil }
        let elapsed = localNow().timeIntervalSince(settled)
        guard elapsed >= 0, elapsed < Self.monitorReentryGap else { return nil }
        return Self.monitorReentryGap - elapsed
    }
}
