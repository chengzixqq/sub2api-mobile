import Foundation
import Testing
@testable import Sub2Core

private let now = ISO8601DateFormatter().date(from: "2026-10-18T01:41:00Z")!
private struct Row: IncrementalRecord, Equatable {
    let id: Int
    let createdAt: String
    var resolved = false
}
/// A row created `age` seconds before `now`.
private func row(_ id: Int, age: TimeInterval, resolved: Bool = false) -> Row {
    Row(id: id, createdAt: ServerTime.utcTimestamp(now.addingTimeInterval(-age)), resolved: resolved)
}
private func ids(_ list: IncrementalList<Row>) -> [Int] { list.items.map(\.id) }
private func item(_ name: String, _ value: String) -> URLQueryItem { URLQueryItem(name: name, value: value) }

@Test func firstPageCursorRewindsThirtySecondsInsteadOfLatestID() {
    let rows = (1...10).reversed().map { row($0, age: TimeInterval(10 - $0) * 10) }
    let list = IncrementalList<Row>().reset(firstPage: rows)
    #expect(list.cursor == 7)
    #expect(ids(list) == Array((1...10).reversed()))
    #expect(list.nextFetch(supportsSinceID: true, now: now) == .since(7))
}

@Test func cursorKeepsPreviousWhenNoRowIsOldEnough() {
    let recent = [row(9, age: 0), row(8, age: 10), row(7, age: 20)]
    let kept = IncrementalList<Row>(cursor: 3).merging(recent, latestID: 9)
    #expect(kept.cursor == 3)
    #expect(kept.nextFetch(supportsSinceID: true, now: now) == .since(3))
    let fresh = IncrementalList<Row>().reset(firstPage: recent)
    #expect(fresh.cursor == nil)
    #expect(fresh.nextFetch(supportsSinceID: true, now: now) == .firstPage)
}

@Test(arguments: [(1_000 as Int?, 800), (150, 0), (nil, 0)])
func unparseableCreatedAtFallsBackTwoHundredIDs(latestID: Int?, expected: Int) {
    let rows = [Row(id: 120, createdAt: "garbage"), Row(id: 119, createdAt: "")]
    #expect(IncrementalList<Row>.cursor(for: rows, latestID: latestID, previous: nil) == expected)
    let large = [Row(id: 950, createdAt: "garbage")]
    #expect(IncrementalList<Row>.cursor(for: large, latestID: nil, previous: nil) == 750)
    #expect(IncrementalList<Row>().merging(rows, latestID: latestID).cursor == expected)
}

@Test func cursorNeverMovesBackwards() {
    let rows = [row(50, age: 0), row(40, age: 60)]
    #expect(IncrementalList<Row>.cursor(for: rows, latestID: 50, previous: 45) == 45)
    #expect(IncrementalList<Row>.cursor(for: rows, latestID: 50, previous: 30) == 40)
    #expect(IncrementalList<Row>.cursor(for: [Row(id: 300, createdAt: "garbage")], latestID: 300, previous: 250) == 250)
    #expect(IncrementalList<Row>.cursor(for: [], latestID: nil, previous: nil) == nil)
}

@Test func outOfOrderCommitDoesNotLoseRows() throws {
    // 104 and 102 were still uncommitted when the first page was read.
    let firstPage = [row(105, age: 0), row(103, age: 5), row(101, age: 10), row(100, age: 40), row(99, age: 50)]
    let list = IncrementalList<Row>().reset(firstPage: firstPage)
    let cursor = try #require(list.cursor)
    #expect(cursor <= 101)
    guard case .merged(let merged) = list.applyingIncrement([row(106, age: -5), row(104, age: 2), row(102, age: 8)], hasMore: false, latestID: 106) else {
        Issue.record("Expected a merge"); return
    }
    #expect(ids(merged) == [106, 105, 104, 103, 102, 101, 100, 99])
    #expect((merged.cursor ?? 0) >= cursor)
}

@Test func mergeDeduplicatesNewerWinsAndSortsByIDDescending() {
    let list = IncrementalList<Row>().reset(firstPage: [row(5, age: 60), row(3, age: 80), row(4, age: 70)])
    #expect(ids(list) == [5, 4, 3])
    let merged = list.merging([row(5, age: 60, resolved: true), row(6, age: 0)], latestID: 6)
    #expect(ids(merged) == [6, 5, 4, 3])
    #expect(merged.items.first { $0.id == 5 }?.resolved == true)
    #expect(IncrementalList<Row>.merged([row(2, age: 0)], [row(2, age: 0, resolved: true), row(2, age: 0)], limit: nil).count == 1)
}

@Test func mergeKeepsNewestNWhenLimited() {
    let list = IncrementalList<Row>(limit: 3).reset(firstPage: [row(1, age: 90), row(2, age: 80), row(3, age: 70)])
    let merged = list.merging([row(4, age: 60), row(5, age: 50)], latestID: 5)
    #expect(ids(merged) == [5, 4, 3])
    let trimmed = merged.trimmed(to: 2)
    #expect(ids(trimmed) == [5, 4]); #expect(trimmed.cursor == merged.cursor)
    #expect(IncrementalList<Row>(items: [row(1, age: 0), row(2, age: 0)], limit: 1).items.map(\.id) == [2])
}

@Test func hasMoreAbandonsIncrementForFirstPageReload() {
    let list = IncrementalList<Row>().reset(firstPage: [row(10, age: 60)])
    guard case .reloadFirstPage = list.applyingIncrement([row(200, age: 0)], hasMore: true, latestID: 200) else {
        Issue.record("has_more must reload page 1"); return
    }
    #expect(ids(list) == [10])
}

@Test func sinceIDBadRequestsRestartFromFirstPage() {
    #expect(IncrementalPolicy.shouldRestartFromFirstPage(APIError.server(status: 400, reason: "SINCE_ID_WITH_PAGE")))
    #expect(IncrementalPolicy.shouldRestartFromFirstPage(APIError.server(status: 400, reason: "INVALID_SINCE_ID")))
    #expect(!IncrementalPolicy.shouldRestartFromFirstPage(APIError.server(status: 400, reason: "INVALID_SORT_BY")))
    #expect(!IncrementalPolicy.shouldRestartFromFirstPage(APIError.server(status: 500, reason: nil)))
    #expect(!IncrementalPolicy.shouldRestartFromFirstPage(URLError(.timedOut)))
}

@Test func missingCapabilityUsesTimeWindowFallback() {
    let list = IncrementalList<Row>().reset(firstPage: [row(8, age: 0), row(7, age: 90)])
    let later = now.addingTimeInterval(60)
    let fetch = list.nextFetch(supportsSinceID: false, now: later)
    #expect(fetch == .window(start: now.addingTimeInterval(-120), end: later))
    let base = [item("page", "2"), item("page_size", "30"), item("start_time", "old"), item("end_time", "old"), item("count_mode", "exact"),
                item("timezone", "Asia/Shanghai"), item("account_id", "9")]
    #expect(fetch.queryItems(base: base, deferredCount: true) == [
        item("account_id", "9"), item("count_mode", "deferred"), item("end_time", "2026-10-18T01:42:00Z"), item("page", "1"),
        item("page_size", "100"), item("start_time", "2026-10-18T01:39:00Z"), item("timezone", "Asia/Shanghai")])
    let ops = fetch.queryItems(base: base, deferredCount: false)
    #expect(!ops.contains { $0.name == "count_mode" })
    #expect(ops.contains(item("page", "1")))
    let undated = IncrementalList<Row>().reset(firstPage: [Row(id: 3, createdAt: "garbage")])
    #expect(undated.nextFetch(supportsSinceID: false, now: later) == .firstPage)
}

@Test func incrementalQueryDropsPageTimeSortAndCountMode() {
    let base = [item("page", "3"), item("page_size", "20"), item("start_time", "a"), item("end_time", "b"), item("sort_by", "created_at"),
                item("sort_order", "desc"), item("count_mode", "deferred"), item("exact_total", "false"), item("account_id", "9"), item("model", "x"),
                item("time_range", "1h"), item("start_date", "c"), item("end_date", "d"), item("since_id", "1")]
    #expect(IncrementalFetch.since(42).queryItems(base: base, deferredCount: true) == [
        item("account_id", "9"), item("model", "x"), item("page_size", "100"), item("since_id", "42")])
}

@Test func emptyListAndMissingCursorStartWithFirstPage() {
    #expect(IncrementalList<Row>().nextFetch(supportsSinceID: true, now: now) == .firstPage)
    #expect(IncrementalList<Row>().nextFetch(supportsSinceID: false, now: now) == .firstPage)
    let base = [item("page", "4"), item("page_size", "30"), item("start_time", "a"), item("sort_by", "created_at"), item("since_id", "9")]
    #expect(IncrementalFetch.firstPage.queryItems(base: base, deferredCount: false) == [
        item("page", "1"), item("page_size", "100"), item("sort_by", "created_at"), item("start_time", "a")])
}

@Test func loadMoreDedupesWithoutMovingCursor() {
    let list = IncrementalList<Row>(limit: 2).reset(firstPage: [row(20, age: 0), row(19, age: 40)])
    let more = list.appendingOlder([row(19, age: 40), row(18, age: 50), row(17, age: 60)])
    #expect(ids(more) == [20, 19, 18, 17])
    #expect(more.cursor == list.cursor)
}

@Test func mergeAfterLoadMoreAppliesLimitAndKeepsOlderPagesWithoutOne() {
    let older = [row(18, age: 50), row(17, age: 60)]
    let limited = IncrementalList<Row>(limit: 2).reset(firstPage: [row(20, age: 0), row(19, age: 40)]).appendingOlder(older)
    #expect(ids(limited.merging([row(21, age: -5)], latestID: 21)) == [21, 20])
    let open = IncrementalList<Row>().reset(firstPage: [row(20, age: 0), row(19, age: 40)]).appendingOlder(older)
    let polled = open.merging([row(21, age: -5)], latestID: 21)
    #expect(ids(polled) == [21, 20, 19, 18, 17])
    #expect(ids(polled.merging([row(21, age: -5), row(20, age: 0)], latestID: 21)) == [21, 20, 19, 18, 17])
    let trimmed = polled.trimmed(to: 2)
    #expect(ids(trimmed) == [21, 20]); #expect(trimmed.cursor == polled.cursor)
}

@Test func resetReplacesItemsAndRecomputesCursor() {
    let loaded = IncrementalList<Row>().reset(firstPage: [row(20, age: 0), row(19, age: 40)]).appendingOlder([row(10, age: 900)])
    #expect(loaded.cursor == 19)
    let refreshed = loaded.reset(firstPage: [row(30, age: 0), row(29, age: 10)])
    #expect(ids(refreshed) == [30, 29]); #expect(refreshed.cursor == nil)
}

@Test func logRecordsConformAndParseOffsetTimestamps() throws {
    let usage = try JSONDecoder().decode([UsageRequestRecord].self, from: Data("""
    [{"id":2,"request_id":"r2","created_at":"2026-10-18T09:41:00.123456+08:00","model":"m","user_id":1,"account_id":1,"api_key_id":1},
     {"id":1,"request_id":"r1","created_at":"2026-10-18T09:40:00.5+08:00","model":"m","user_id":1,"account_id":1,"api_key_id":1}]
    """.utf8))
    #expect(IncrementalList<UsageRequestRecord>().reset(firstPage: usage).cursor == 1)
    let errors = try JSONDecoder().decode([RequestErrorRecord].self, from: Data("""
    [{"id":9,"created_at":"2026-10-18T09:41:00+08:00","request_id":"e9","phase":"upstream","type":"t","status_code":502,"platform":"openai","model":"m","resolved":false,"message":"x"},
     {"id":8,"created_at":"2026-10-18T09:40:00.25+08:00","request_id":"e8","phase":"upstream","type":"t","status_code":502,"platform":"openai","model":"m","resolved":true,"message":"x"}]
    """.utf8))
    #expect(IncrementalList<RequestErrorRecord>().reset(firstPage: errors).cursor == 8)
}
