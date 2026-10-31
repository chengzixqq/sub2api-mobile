import Foundation
import Testing
@testable import Sub2Core

// S1-16: 最近结束's pages (10 §6.2, §6.5, §6.6). The cursor is the last event the server sent, firing ones included; a poll merges
// its first page into what was loaded; an older page lands only on the cursor it was asked with.

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func event(_ id: Int, _ status: String = "resolved", minutesAgo: Double) -> AlertEvent {
    AlertEvent(id: id, severity: "P2", status: status, firedAt: now.addingTimeInterval(-minutesAgo * 60))
}
/// `count` events from `firstID` down, a minute apart from `minutesAgo` on.
private func page(from firstID: Int, count: Int, minutesAgo: Double, status: String = "resolved") -> [AlertEvent] {
    (0..<count).map { event(firstID - $0, status, minutesAgo: minutesAgo + Double($0)) }
}

@Test func pagingFollowsSpecRequest() {
    #expect(RecentAlerts.timeRange == "24h" && RecentAlerts.pageLimit == 50)
}

@Test func fullFirstPageCursorIsLastRawEventEvenWhenFiring() {
    let raw = page(from: 500, count: 49, minutesAgo: 1) + [event(451, "firing", minutesAgo: 60)]
    let full = RecentAlerts.firstPage(raw, limit: RecentAlerts.pageLimit)
    #expect(full.cursor == raw.last?.cursor && full.cursor != nil && full.hasMore && full.events.count == 49)
    let short = RecentAlerts.firstPage(Array(raw.prefix(49)), limit: RecentAlerts.pageLimit)
    #expect(short.cursor == nil && !short.hasMore)
}

@Test func appendingEarlierAddsOlderRowsAndAdvancesCursor() throws {
    let first = RecentAlerts.firstPage(page(from: 500, count: 50, minutesAgo: 1), limit: 50)
    let cursor = try #require(first.cursor)
    // The older page repeats #451 with another value: the page's wins.
    let older = [event(451, AlertEvent.manualResolved, minutesAgo: 50)] + page(from: 450, count: 49, minutesAgo: 51)
    let next = first.appendingEarlier(older, expectedCursor: cursor)
    #expect(next.events.map(\.id) == Array((402...500).reversed()))
    #expect(next.events.first { $0.id == 451 }?.status == AlertEvent.manualResolved)
    #expect(next.cursor == older.last?.cursor && next.hasMore)
    let last = next.appendingEarlier(page(from: 401, count: 7, minutesAgo: 100), expectedCursor: try #require(next.cursor))
    #expect(last.events.last?.id == 395 && last.events.count == 106 && !last.hasMore)
}

@Test func appendingEarlierPageOfOnlyFiringStillAdvances() throws {
    let first = RecentAlerts.firstPage(page(from: 500, count: 50, minutesAgo: 1), limit: 50)
    let firing = page(from: 450, count: 50, minutesAgo: 51, status: "firing")
    let next = first.appendingEarlier(firing, expectedCursor: try #require(first.cursor))
    #expect(next.events == first.events && next.cursor == firing.last?.cursor && next.cursor != first.cursor && next.hasMore)
}

@Test func appendingEarlierIgnoredWhenCursorMoved() throws {
    let first = RecentAlerts.firstPage(page(from: 500, count: 50, minutesAgo: 1), limit: 50)
    let stale = try #require(event(999, minutesAgo: 30).cursor)
    #expect(first.appendingEarlier(page(from: 450, count: 50, minutesAgo: 51), expectedCursor: stale) == first)
    #expect(RecentAlerts().appendingEarlier(page(from: 450, count: 3, minutesAgo: 51), expectedCursor: stale) == RecentAlerts())
}

/// A poll's first page: its values win, the older pages stay; more remain only while both say so, from the older end.
@Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
func mergingFirstPageKeepsLoadedEarlierPages(oldHasMore: Bool, newIsFull: Bool) throws {
    let first = RecentAlerts.firstPage(page(from: 300, count: 50, minutesAgo: 10), limit: 50)
    let earlier = page(from: 250, count: oldHasMore ? 50 : 20, minutesAgo: 60)
    let loaded = first.appendingEarlier(earlier, expectedCursor: try #require(first.cursor))
    #expect(loaded.hasMore == oldHasMore)
    let fresh = [event(302, minutesAgo: 1), event(301, minutesAgo: 2), event(300, AlertEvent.manualResolved, minutesAgo: 10)]
        + page(from: 299, count: newIsFull ? 47 : 30, minutesAgo: 11)
    let merged = loaded.mergingFirstPage(fresh)
    #expect(Array(merged.events.prefix(3).map(\.id)) == [302, 301, 300])
    #expect(merged.events.first { $0.id == 300 }?.status == AlertEvent.manualResolved)
    #expect(merged.events.last?.id == earlier.last?.id && Set(merged.events.map(\.id)).count == merged.events.count)
    #expect(merged.hasMore == (oldHasMore && newIsFull))
    #expect(merged.cursor == (oldHasMore && newIsFull ? loaded.cursor : nil))
}

/// A full first page that stops short of the rows loaded leaves a gap: it starts over from that page, so 加载更早 reads the gap.
/// A row placed here since (a manual resolve, a detail read) is not what the server sent and does not close it.
@Test(arguments: [false, true])
func mergingFirstPageStartsOverAcrossGap(oldHasMore: Bool) {
    let loaded = RecentAlerts.firstPage(page(from: 300, count: oldHasMore ? 50 : 20, minutesAgo: 600), limit: 50)
    let fresh = page(from: 400, count: 50, minutesAgo: 1)
    let restart = RecentAlerts.firstPage(fresh, limit: 50)
    #expect(loaded.mergingFirstPage(fresh) == restart && restart.hasMore)
    #expect(loaded.upserting(event(390, AlertEvent.manualResolved, minutesAgo: 11)).mergingFirstPage(fresh) == restart)
}

/// Nothing ended loaded yet (no page, an empty one, one of only firing events): a full page keeps its cursor.
@Test func mergingFullFirstPageIntoNothingKeepsItsCursor() {
    let fresh = page(from: 400, count: 50, minutesAgo: 1)
    let restart = RecentAlerts.firstPage(fresh, limit: 50)
    #expect(RecentAlerts().mergingFirstPage(fresh) == restart)
    #expect(RecentAlerts.firstPage([], limit: 50).mergingFirstPage(fresh) == restart)
    let onlyFiring = RecentAlerts.firstPage(page(from: 300, count: 3, minutesAgo: 600, status: "firing"), limit: 50)
    #expect(onlyFiring.mergingFirstPage(fresh) == restart)
}

/// Rows placed, removed or changed here keep the older pages reachable for a page that meets them.
@Test func localEditsKeepLoadedPagesForOverlappingPage() throws {
    let first = RecentAlerts.firstPage(page(from: 300, count: 50, minutesAgo: 10), limit: 50)
    let loaded = first.appendingEarlier(page(from: 250, count: 50, minutesAgo: 60), expectedCursor: try #require(first.cursor))
        .upserting(event(305, AlertEvent.manualResolved, minutesAgo: 2)).removing(eventID: 299).mapEvents { $0 }
    let merged = loaded.mergingFirstPage(page(from: 305, count: 50, minutesAgo: 2))
    #expect(merged.cursor == loaded.cursor && merged.hasMore && merged.events.last?.id == 201)
}

/// 10 §6.5 last row: the handler's reasonless 400 (a cursor sent without its pair or unreadable); nothing else.
@Test(arguments: zip([APIError.server(status: 400, reason: nil), .server(status: 400, reason: "INVALID_UNTIL"),
                      .server(status: 404, reason: "OPS_DISABLED"), .server(status: 503, reason: "SERVICE_UNAVAILABLE"), .invalidServer],
                     [true, false, false, false, false]))
func cursorRejectionIsReasonless400(error: APIError, rejected: Bool) {
    #expect(RecentAlerts.isCursorRejection(error) == rejected)
}

@Test func noErrorIsNoCursorRejection() {
    #expect(!RecentAlerts.isCursorRejection(nil))
}
