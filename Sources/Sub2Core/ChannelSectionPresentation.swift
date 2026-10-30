import Foundation

/// 10 §5.5: what 监控 · 渠道 shows, in this priority: the monitor switched off, then the block's own state.
public enum ChannelSectionState: Sendable, Equatable {
    /// The first read: the tiles and rows as a skeleton, never 0.
    case loading
    /// features.channel_monitor_enabled is false or the site answered 403 CHANNEL_MONITOR_DISABLED: 渠道监控未开启.
    case disabled
    /// Any other 403 (a vendor workspace, 10 §0.1).
    case forbidden
    /// A failure before any list: the tiles “—” and 渠道加载失败 · 重试.
    case failed
    case empty
    /// `updateFailed`: a failed refresh kept the list (更新失败 beside the title).
    case list(updateFailed: Bool)
}

/// One of the four tiles above the list (10 §5.3). Only a count above 0 is tinted.
public struct ChannelCountCell: Sendable, Equatable, Identifiable {
    /// available / degraded / unavailable / unknown.
    public let key: String
    public let title: String
    public let value: String
    public let tone: Tone?
    public var id: String { key }
    public var spokenValue: String { DisplayFormat.spoken(value) }
}

/// One group's channel as its row shows it (10 §5.3).
public struct ChannelRowDisplay: Sendable, Equatable, Identifiable {
    public enum Trailing: Sendable, Equatable {
        /// Available: its reliability, “—” without one.
        case reliability(String)
        /// Anything else: the status word as a badge.
        case badge(String, Tone)
    }
    public let groupID: Int
    public let title: String
    /// The platform's display name; empty without a platform.
    public let platformName: String
    public let status: ChannelStatus
    public let trailing: Trailing
    /// Always 18 cells, oldest first; nil is an empty cell.
    public let strip: [Tone?]
    public let note: String
    /// Only degraded and unavailable rows draw the capsule; adjacent ones join into one rail.
    public let railPosition: RailPosition?
    public var id: Int { groupID }
    public var tone: Tone { status.tone }
    public var spokenLabel: String { platformName.isEmpty ? title : title + "，" + platformName }
    public var spokenValue: String { status.label + "，" + note }
}

/// 10 §5 监控 · 渠道: the segment's state, tiles and rows. Order, notes, strip and coverage come from ChannelPresentation.
public enum ChannelSectionPresentation {
    /// 10 §5.2, appendix B L11: without it the server answers for 24h.
    public static let range = HomeFallback.channelRange
    public static let sectionTitle = "渠道"
    public static let sectionMeta = "可用率 · 首字"
    public static let sectionOrdinal = ChineseOrdinal.text(1)
    public static let disabledTitle = HomePresentation.channelsDisabledText
    public static let disabledDetail = "可在 Web 后台的渠道监控设置中开启"
    public static let emptyTitle = "还没有渠道数据"
    public static let failedTitle = "渠道加载失败"
    public static let channelMonitorDisabledReason = HomeFallback.channelMonitorDisabledReason

    /// 403 CHANNEL_MONITOR_DISABLED gives its reason; anything else nil.
    public static func disabledReason(_ error: APIError?) -> String? {
        AlertScopePresentation.isChannelMonitorDisabled(error) ? channelMonitorDisabledReason : nil
    }
    /// A 403 that is not the channel monitor's switch: a vendor's FORBIDDEN, or “administrator required” without a reason.
    public static func isForbidden(_ error: APIError?) -> Bool {
        error?.statusCode == 403 && !AlertScopePresentation.isChannelMonitorDisabled(error)
    }
    public static func state(featureEnabled: Bool?, disabledReason: String?, display: BlockDisplay<ChannelOverview>,
                             lastError: APIError?) -> ChannelSectionState {
        if featureEnabled == false || disabledReason != nil { return .disabled }
        switch display {
        case .placeholder: return .loading
        case .disabled: return .disabled
        case .failed:
            if Self.disabledReason(lastError) != nil { return .disabled }
            return isForbidden(lastError) ? .forbidden : .failed
        case .value(let overview, _, _, let updateFailed):
            return overview.items.isEmpty ? .empty : .list(updateFailed: updateFailed)
        }
    }
    /// 可用, 性能下降, 不可用, 未知 as in the design's chan-summary; without a list every tile is “—”.
    public static func countCells(_ items: [ChannelItem]?) -> [ChannelCountCell] {
        let counts = items.map(ChannelPresentation.counts)
        return tileOrder.map { status in
            let count = counts.map { $0.count(of: status) }
            return ChannelCountCell(key: key(status), title: status.label, value: count.map { DisplayFormat.grouped($0) } ?? DisplayFormat.missing,
                                    tone: (count ?? 0) > 0 ? status.tone : nil)
        }
    }
    /// Worst first (ChannelPresentation.sorted).
    public static func rows(_ items: [ChannelItem], platformName: (String) -> String = GroupPlatform.title) -> [ChannelRowDisplay] {
        let sorted = ChannelPresentation.sorted(items)
        let positions = RailPosition.positions(of: sorted) { ChannelPresentation.status($0).tone.drawsRail }
        return zip(sorted, positions).map { item, position in
            let status = ChannelPresentation.status(item)
            let trailing: ChannelRowDisplay.Trailing = status == .available
                ? .reliability(ChannelPresentation.reliabilityText(item)) : .badge(status.label, status.tone)
            return ChannelRowDisplay(groupID: item.groupID, title: ChannelPresentation.title(item), platformName: platformName(item.platform),
                                     status: status, trailing: trailing, strip: ChannelPresentation.strip(item.buckets),
                                     note: ChannelPresentation.note(item), railPosition: position)
        }
    }

    private static let tileOrder: [ChannelStatus] = [.available, .degraded, .unavailable, .unknown]
    private static func key(_ status: ChannelStatus) -> String {
        switch status {
        case .available: "available"
        case .degraded: "degraded"
        case .unavailable: "unavailable"
        case .unknown: "unknown"
        }
    }
}

extension ChannelCounts {
    func count(of status: ChannelStatus) -> Int {
        switch status {
        case .available: available
        case .degraded: degraded
        case .unavailable: unavailable
        case .unknown: unknown
        }
    }
}
