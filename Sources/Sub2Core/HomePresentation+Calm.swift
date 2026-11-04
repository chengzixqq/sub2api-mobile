import Foundation

/// 10 §2.4 the calm layout's numbered sections: 每小时实际扣费, then 按账号 when it shows, then 渠道, numbered without a gap
/// (as the search directory renumbers its empty sections). 更多统计 closes 按账号, or 每小时实际扣费 without it.
public struct HomeCalmOutline: Sendable, Equatable {
    public let hourlyOrdinal: String
    public let rankingOrdinal: String?
    public let channelsOrdinal: String
    public let moreStatsFollowsRanking: Bool

    public init(hourlyOrdinal: String, rankingOrdinal: String?, channelsOrdinal: String, moreStatsFollowsRanking: Bool) {
        self.hourlyOrdinal = hourlyOrdinal; self.rankingOrdinal = rankingOrdinal; self.channelsOrdinal = channelsOrdinal
        self.moreStatsFollowsRanking = moreStatsFollowsRanking
    }
}

extension HomePresentation {
    public static let calmRecoveringTitle = "自动恢复中"
    public static let calmRankingMeta = "今日实际扣费 · 前 4"

    public static func calmOutline(hasRanking: Bool) -> HomeCalmOutline {
        HomeCalmOutline(hourlyOrdinal: ChineseOrdinal.text(1), rankingOrdinal: hasRanking ? ChineseOrdinal.text(2) : nil,
                        channelsOrdinal: ChineseOrdinal.text(hasRanking ? 3 : 2), moreStatsFollowsRanking: hasRanking)
    }

    /// “N 个”, counted as the 受限 row it heads.
    public static func calmRecoveringMeta(_ summary: AccountStatusSummary) -> String {
        DisplayFormat.grouped(limitedCount(summary)) + " 个"
    }

    /// 10 §2.6: 按账号 shows only while the last ranking read succeeded; a failed one hides it, also while the next read is on its
    /// way, until one succeeds. A refresh after a success keeps the rows it had.
    public static func calmRanking(_ state: BlockState<[AccountsRankingItem]>, refresh: BlockRefresh) -> [HomeRankingRow] {
        guard refresh.consecutiveFailures == 0, state.failureReason == nil, let items = state.value else { return [] }
        return rankingRows(items)
    }
}
