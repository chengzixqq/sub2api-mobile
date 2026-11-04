import Foundation

/// 10 §1.3.5 运行区 (S1-09b): the 健康分 row, 错误率 / 上游 429 / 529 and the 渠道 row. The score's bands are MonitorPresentation's,
/// shared with the monitor overview; numbers go through DisplayFormat (R10).
public enum HomeRunPresentation {
    /// Where the gauge marks the bands; the bands themselves are `MonitorPresentation.health(_:)`.
    public static let healthZones = [60, 90]
    public static let opsDisabledWord = "运维监控未开启"
    public static let healthFailedText = "健康分加载失败"
    /// A site without channels: the row still opens the monitor's 渠道 segment.
    public static let channelsEmptyText = "还没有渠道数据"

    public enum Health: Sendable, Equatable {
        /// First load: the skeleton.
        case loading
        case score(MonitorPresentation.HealthReading, updateFailed: Bool)
        case opsDisabled
        /// The block answered without `health_score`.
        case unavailable
        /// Failed without an earlier score: “—” and a retry row.
        case failed

        /// Without a score the gauge draws its track and marks only.
        public var reading: MonitorPresentation.HealthReading {
            if case .score(let reading, _) = self { reading } else { MonitorPresentation.health(nil) }
        }
        public var numberText: String { reading.value }
        public var wordText: String? { self == .opsDisabled ? opsDisabledWord : reading.word }
        public var tone: Tone? { reading.tone }
        /// “92，良好”, “无数据，运维监控未开启”, “无数据”.
        public var spokenValue: String {
            if self == .loading { return "正在加载" }
            return [DisplayFormat.spoken(numberText), wordText].compactMap { $0 }.joined(separator: "，")
        }
    }

    /// A failed refresh keeps the earlier score (10 §0.5). Ops monitoring off wins over whatever the block still holds: the switch
    /// may come from rates, `/admin/me` or a 404 before the next reply.
    public static func health(_ ops: BlockDisplay<HomeOps>, opsDisabled: Bool) -> Health {
        if opsDisabled { return .opsDisabled }
        switch ops {
        case .placeholder: return .loading
        case .disabled: return .opsDisabled
        case .failed: return .failed
        case .value(let value, _, _, let updateFailed):
            guard let score = value.healthScore else { return .unavailable }
            return .score(MonitorPresentation.health(score), updateFailed: updateFailed)
        }
    }

    public struct RunRates: Sendable, Equatable {
        public let errorRate: String
        public let upstream429: String
        public let upstream529: String
    }
    /// The rates block, as the six cells read it: with monitoring off (or a rate the server marks unavailable) “—”, never 0.
    public static func rates(_ rates: LiveRates?) -> RunRates {
        let errorRate = rates?.errorsAvailable == false ? nil : rates?.errorRate
        return RunRates(errorRate: DisplayFormat.ratioPercent(errorRate), upstream429: DisplayFormat.grouped(rates?.upstream429Count),
                        upstream529: DisplayFormat.grouped(rates?.upstream529Count))
    }

    public enum Channels: Sendable, Equatable {
        case loading
        case summary([HomeChannelPart], updateFailed: Bool)
        case empty
        case disabled
        /// Failed without earlier counts.
        case failed

        /// Only a row with something to see opens the monitor's 渠道 segment.
        public var isTappable: Bool {
            switch self {
            case .summary, .empty: true
            case .loading, .disabled, .failed: false
            }
        }
        public var text: String {
            switch self {
            case .loading: "正在加载…"
            case .summary(let parts, _): parts.map(\.text).joined(separator: " · ")
            case .empty: HomeRunPresentation.channelsEmptyText
            case .disabled: HomePresentation.channelsDisabledText
            case .failed: HomePresentation.channelsFailedText
            }
        }
    }
    public static func channels(_ display: BlockDisplay<HomeChannels>) -> Channels {
        switch display {
        case .placeholder: return .loading
        case .disabled: return .disabled
        case .failed: return .failed
        case .value(let counts, _, _, let updateFailed):
            let parts = HomePresentation.channelSummaryLine(counts)
            return parts.isEmpty ? .empty : .summary(parts, updateFailed: updateFailed)
        }
    }
}
