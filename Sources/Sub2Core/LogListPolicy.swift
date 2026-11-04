import Foundation

/// 40 §6.6 around IncrementalList (00 §4.3), which keeps the cursor and the merge by id; lists use `limit: nil` and trim here.
public struct LogListPolicy: Equatable, Sendable {
    /// N (00 §4.3 step 3).
    public static let standardLimit = 500
    /// The list trims only while its first visible row is within these.
    public static let nearTopRows = 20
    /// Every tenth increment re-reads page 1.
    public static let calibrationInterval = 10
    /// How long the ops error logs are kept by default (40 §6.5).
    public static let opsRetention: TimeInterval = 30 * 86_400

    public let limit: Int
    public let pageSize: Int
    /// UI tests pass `limit: 5, pageSize: 5`; both are at least 1.
    public init(limit: Int = LogListPolicy.standardLimit, pageSize: Int = IncrementalPolicy.pageSize) {
        self.limit = max(1, limit); self.pageSize = max(1, pageSize)
    }
    /// “加载更多” after a trim: 500 ÷ 100 + 1 = 6.
    public var nextPageAfterTrim: Int { limit / pageSize + 1 }
    /// nil (not laid out yet, or no rows) counts as the top.
    public func isNearTop(firstVisibleIndex: Int?) -> Bool { (firstVisibleIndex ?? 0) < Self.nearTopRows }
    /// The newest `limit` rows and the next page, or nil while there is nothing to cut or the user is scrolled down; call
    /// again once the first visible row is back near the top.
    public func trimmed<Record: IncrementalRecord>(_ list: IncrementalList<Record>, firstVisibleIndex: Int?) -> LogTrim<Record>? {
        guard list.items.count > limit, isNearTop(firstVisibleIndex: firstVisibleIndex) else { return nil }
        return LogTrim(list: list.trimmed(to: limit), nextPage: nextPageAfterTrim)
    }

    /// After each merge: rows created before the window's start go; rows at the start or without a readable time stay.
    /// Only a fixed range cuts.
    public static func pruned<Record: IncrementalRecord>(_ list: IncrementalList<Record>, to window: LogTimeWindow) -> IncrementalList<Record> {
        guard case .range(let start, _) = window else { return list }
        let parser = TimestampParser()
        let kept = list.items.filter { row in parser.date(row.createdAt).map { $0 >= start } ?? true }
        guard kept.count < list.items.count else { return list }
        return IncrementalList(items: kept, cursor: list.cursor, limit: list.limit)
    }
    /// The poll without `since_id` (upstream errors, or a site without `logs.since_id`; 00 §4.3 step 7): page 1 of 100
    /// from the newest row's `created_at` − 120 seconds to `now`. nil means read page 1 in full instead.
    public static func fallbackRefreshFilter<Record: IncrementalRecord>(after list: IncrementalList<Record>, base: RequestLogFilter,
                                                                        now: Date) -> RequestLogFilter? {
        guard case .window(let start, let end) = list.nextFetch(supportsSinceID: false, now: now), start < end,
              end.timeIntervalSince(start) <= LogTimeWindow.maximumRange else { return nil }
        var filter = base
        filter.time = .range(start, end); filter.pageSize = IncrementalPolicy.pageSize
        return filter
    }
    /// More than one page (`pages` > 1, else `has_more`) left a gap: reload page 1.
    public static func fallbackRefreshStep<Record: IncrementalRecord & Decodable>(_ list: IncrementalList<Record>,
                                                                                  reply: Page<Record>) -> IncrementalStep<Record> {
        list.applyingIncrement(reply.items, hasMore: reply.pages.map { $0 > 1 } ?? reply.hasMore, latestID: nil)
    }
    /// The usage segment's count (`usage/stats` → `total_requests`) with the list's own window and conditions; nil without a
    /// fixed range. `granularity` is not sent by `usage/stats`.
    public static func usageCountQuery(_ filter: RequestLogFilter, timeZone: ServerTimeZone) -> AnalyticsQuery? {
        guard case .range(let start, let end) = filter.time else { return nil }
        return AnalyticsQuery(start: start, end: end, granularity: .day, timeZone: timeZone, accountID: filter.accountID,
                              groupID: filter.groupID, userID: filter.userID, model: filter.model, modelSource: filter.modelSource)
    }
}

public struct LogTrim<Record: IncrementalRecord>: Sendable {
    public let list: IncrementalList<Record>
    /// The page “加载更多” reads next.
    public let nextPage: Int
}

public enum LogPollRead: Sendable, Equatable { case increment, calibration }

/// 40 §6.6 calibration for usage records and request errors: after ten increments the next poll reads page 1. Record
/// `.calibration` after any page-1 read (calibration, pull-to-refresh, the has_more or 400 reload). Upstream errors do not
/// use this: each of their polls already is a page-1 time-window read and is never calibrated (S4-06).
public struct LogPollSchedule: Sendable, Equatable {
    public let incrementsSinceCalibration: Int
    public init(incrementsSinceCalibration: Int = 0) { self.incrementsSinceCalibration = max(0, incrementsSinceCalibration) }
    public var next: LogPollRead { incrementsSinceCalibration >= LogListPolicy.calibrationInterval ? .calibration : .increment }
    public func recording(_ read: LogPollRead) -> LogPollSchedule {
        switch read {
        case .increment: LogPollSchedule(incrementsSinceCalibration: incrementsSinceCalibration + 1)
        case .calibration: LogPollSchedule()
        }
    }
}
