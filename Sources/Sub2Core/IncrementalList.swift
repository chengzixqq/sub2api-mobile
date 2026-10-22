import Foundation

/// A log row the 00 §4.3 merge can order by id and age by `created_at` (usage records, request errors).
public protocol IncrementalRecord: Identifiable, Sendable where ID == Int {
    var createdAt: String { get }
}
extension UsageRequestRecord: IncrementalRecord {}
extension RequestErrorRecord: IncrementalRecord {}

/// 00 §4.3 numbers (U04).
public enum IncrementalPolicy {
    public static let pageSize = 100
    /// Ids are not committed in order, so the cursor stays behind rows younger than this.
    public static let createdAtRewind: TimeInterval = 30
    /// Used instead when no `created_at` can be read.
    public static let idRewind = 200
    /// Without `logs.since_id`, polls re-read from the newest row's `created_at` minus this.
    public static let fallbackWindow: TimeInterval = 120
    /// 400 `SINCE_ID_WITH_PAGE` / `INVALID_SINCE_ID` (step 6): drop the cursor and start again from page 1.
    public static func shouldRestartFromFirstPage(_ error: any Error) -> Bool {
        (error as? APIError)?.action == .restartFromFirstPage
    }
}

/// The next 00 §4.3 read: page 1, the id cursor, or the time window used without `logs.since_id`.
public enum IncrementalFetch: Equatable, Sendable {
    case firstPage
    case since(Int)
    case window(start: Date, end: Date)

    private static let pagingKeys: Set<String> = ["page", "page_size", "since_id"]
    private static let timeKeys: Set<String> = ["time_range", "start_time", "end_time", "start_date", "end_date"]
    /// Ignored by the server next to since_id; sending page would even be rejected (`SINCE_ID_WITH_PAGE`).
    private static let cursorIgnoredKeys: Set<String> = ["sort_by", "sort_order", "count_mode", "exact_total"]

    /// `base` is the page's own query (object filters, time, sort). An incremental read keeps only the object filters;
    /// `deferredCount` adds `count_mode=deferred` to the window read of `admin/usage` (ops endpoints do not take it).
    public func queryItems(base: [URLQueryItem], deferredCount: Bool) -> [URLQueryItem] {
        let firstPage = URLQueryItem(name: "page", value: "1"), size = URLQueryItem(name: "page_size", value: String(IncrementalPolicy.pageSize))
        let items: [URLQueryItem]
        switch self {
        case .firstPage:
            items = Self.dropping(Self.pagingKeys, from: base) + [firstPage, size]
        case .since(let id):
            items = Self.dropping(Self.pagingKeys.union(Self.timeKeys).union(Self.cursorIgnoredKeys), from: base)
                + [size, URLQueryItem(name: "since_id", value: String(id))]
        case .window(let start, let end):
            items = Self.dropping(Self.pagingKeys.union(Self.timeKeys).union(["count_mode"]), from: base) + [firstPage, size]
                + ServerTime.timeRangeItems(start: start, end: end)
                + (deferredCount ? [URLQueryItem(name: "count_mode", value: "deferred")] : [])
        }
        return items.sorted { $0.name < $1.name }
    }
    private static func dropping(_ names: Set<String>, from items: [URLQueryItem]) -> [URLQueryItem] {
        items.filter { !names.contains($0.name) }
    }
}

public enum IncrementalStep<Record: IncrementalRecord>: Sendable {
    case merged(IncrementalList<Record>)
    /// has_more: new rows overflowed one page and left a gap.
    case reloadFirstPage
}

/// 00 §4.3 list state: rows unique by id, newest id first, and the next `since_id`. Every change returns a new value.
public struct IncrementalList<Record: IncrementalRecord>: Sendable {
    public let items: [Record]
    /// The next `since_id`; nil sends the next read to page 1.
    public let cursor: Int?
    /// Merges keep only the newest N rows (the page decides N); "load more" may go past it until `trimmed(to:)`.
    public let limit: Int?

    public init(items: [Record] = [], cursor: Int? = nil, limit: Int? = nil) {
        self.init(sorted: Self.merged([], items, limit: limit), cursor: cursor, limit: limit)
    }
    private init(sorted items: [Record], cursor: Int?, limit: Int?) { self.items = items; self.cursor = cursor; self.limit = limit }

    /// First screen, pull-to-refresh and the reload after has_more: page 1 replaces the rows and recalibrates the cursor.
    public func reset(firstPage rows: [Record]) -> Self {
        let fresh = Self.merged([], rows, limit: limit)
        return Self(sorted: fresh, cursor: Self.cursor(for: fresh, latestID: nil, previous: nil), limit: limit)
    }
    /// A poll (since_id or time window): new copies replace old ones, then the cursor moves on from the merged rows.
    public func merging(_ rows: [Record], latestID: Int?) -> Self {
        let combined = Self.merged(items, rows, limit: limit)
        return Self(sorted: combined, cursor: Self.cursor(for: combined, latestID: latestID, previous: cursor), limit: limit)
    }
    public func applyingIncrement(_ rows: [Record], hasMore: Bool, latestID: Int?) -> IncrementalStep<Record> {
        hasMore ? .reloadFirstPage : .merged(merging(rows, latestID: latestID))
    }
    /// "Load more": older pages join without moving the cursor.
    public func appendingOlder(_ rows: [Record]) -> Self {
        Self(sorted: Self.merged(items, rows, limit: nil), cursor: cursor, limit: limit)
    }
    public func trimmed(to count: Int) -> Self { Self(sorted: Array(items.prefix(max(0, count))), cursor: cursor, limit: limit) }

    public func nextFetch(supportsSinceID: Bool, now: Date) -> IncrementalFetch {
        guard !items.isEmpty else { return .firstPage }
        if supportsSinceID { return cursor.map(IncrementalFetch.since) ?? .firstPage }
        let parser = TimestampParser()
        guard let newest = items.compactMap({ parser.date($0.createdAt) }).max() else { return .firstPage }
        return .window(start: newest.addingTimeInterval(-IncrementalPolicy.fallbackWindow), end: now)
    }

    /// Step 2: the largest id at least 30 s older than the newest row, never `latest_id` itself. No such row keeps the previous
    /// cursor; when no `created_at` reads, `latest_id` (else the largest id) minus 200. The cursor never moves backwards.
    public static func cursor(for rows: [Record], latestID: Int?, previous: Int?) -> Int? {
        let parser = TimestampParser()
        let dated = rows.compactMap { row in parser.date(row.createdAt).map { (id: row.id, at: $0) } }
        let computed: Int?
        if let newest = dated.map(\.at).max() {
            let threshold = newest.addingTimeInterval(-IncrementalPolicy.createdAtRewind)
            computed = dated.filter { $0.at <= threshold }.map(\.id).max()
        } else {
            computed = (latestID ?? rows.map(\.id).max()).map { max(0, $0 - IncrementalPolicy.idRewind) }
        }
        guard let computed else { return previous }
        return max(computed, previous ?? computed)
    }
    /// Step 3: one row per id with the incoming copy winning, newest id first, then the first `limit` rows.
    public static func merged(_ existing: [Record], _ incoming: [Record], limit: Int?) -> [Record] {
        var byID = [Int: Record](minimumCapacity: existing.count + incoming.count)
        for row in existing + incoming { byID[row.id] = row }
        let ordered = byID.values.sorted { $0.id > $1.id }
        guard let limit else { return ordered }
        return Array(ordered.prefix(max(0, limit)))
    }
}
