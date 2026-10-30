import Foundation

// S1-16, 10 §6.2 / §6.5 / §6.6: 最近结束's pages. A page's cursor is the last event the server sent, firing ones included, so a
// page of only firing events still moves on; a page shorter than the limit is the end. Polls and writes merge the first page
// into what was loaded, a pull starts over (LiveOpsStore+MonitorAlerts.swift).

extension RecentAlerts {
    /// `alert-events?time_range=24h&limit=50`; ended events are filtered here, the server has no such filter.
    public static let timeRange = "24h"
    public static let pageLimit = 50

    public var hasMore: Bool { cursor != nil }

    /// The page's values win and the older pages loaded stay. More remain only while both say so, from the older cursor: the
    /// rows between the two were loaded already.
    public func mergingFirstPage(_ raw: [AlertEvent], limit: Int = pageLimit) -> RecentAlerts {
        let page = RecentAlerts.firstPage(raw, limit: limit)
        let next: AlertEventCursor? = switch (cursor, page.cursor) {
        case let (old?, new?): min(old, new)
        default: nil
        }
        return RecentAlerts(events: page.events + events, cursor: next)
    }
    /// The page older than `expectedCursor`, unless the list moved on meanwhile (a pull started over): then nothing changes.
    public func appendingEarlier(_ raw: [AlertEvent], expectedCursor: AlertEventCursor, limit: Int = pageLimit) -> RecentAlerts {
        guard cursor == expectedCursor else { return self }
        return RecentAlerts(events: raw + events, cursor: raw.count >= limit ? raw.last?.cursor : nil)
    }
    /// The handler's reasonless 400 (`response.BadRequest`): a cursor without its pair or one it cannot read. The App cannot
    /// tell which (it never reads `message`, 00 §3.4); either way the first page is read again without one.
    public static func isCursorRejection(_ error: APIError?) -> Bool {
        guard let error, error.statusCode == 400 else { return false }
        return (error.reason ?? "").isEmpty
    }
}
