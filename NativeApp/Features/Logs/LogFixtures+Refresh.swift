import Foundation
import Sub2Core

/// S4-06 (X44): the auto refresh under `-ui-testing`. The cursor reads answer the rows past the cursor out of S4-05's page 1, so
/// no row is new; `-ui-logs-live` puts every usage row on page 1 and has each usage cursor read bring one newer row (2001, 2002…,
/// stamped with the site clock), and `-ui-logs-poll-interval <秒>` replaces the 60 seconds.
extension LogFixtures {
    enum RefreshArgument {
        /// N = 5 over pages of 5, so a trim reads page 2 next, which the live rows leave empty.
        static let live = "-ui-logs-live"
        /// Followed by the seconds, 1…3600.
        static let pollInterval = "-ui-logs-poll-interval"
    }

    struct RefreshTuning: Equatable, Sendable {
        static let liveLimit = 5
        static let intervals: ClosedRange<TimeInterval> = 1...3_600
        let isLive: Bool
        let interval: TimeInterval?

        /// nil without either argument.
        init?(arguments: [String]) {
            let seconds = arguments.firstIndex(of: RefreshArgument.pollInterval).map { arguments.index(after: $0) }
                .flatMap { arguments.indices.contains($0) ? TimeInterval(arguments[$0]) : nil }
            isLive = arguments.contains(RefreshArgument.live)
            interval = seconds.map { min(max($0, Self.intervals.lowerBound), Self.intervals.upperBound) }
            guard isLive || interval != nil else { return nil }
        }
        var policy: LogListPolicy { isLive ? LogListPolicy(limit: Self.liveLimit, pageSize: Self.liveLimit) : LogListPolicy() }
    }

    /// S4-05's lists with their cursor reads; `now` is the site clock.
    static func refreshSource(wrapping lists: LogsSource, arguments: [String], now: @escaping @Sendable () -> Date) -> LogsSource {
        let errorsSince: LogsSource.CursorRead<RequestErrorRecord> = { sinceID, filter in
            try await LogFixtures.past(sinceID, in: lists.errors(1, filter, .request).items)
        }
        guard arguments.contains(RefreshArgument.live) else {
            return LogsSource(usage: lists.usage, errors: lists.errors,
                              usageSince: { sinceID, filter in try await LogFixtures.past(sinceID, in: lists.usage(1, filter).items) },
                              errorsSince: errorsSince)
        }
        let feed = LiveUsageFeed(lists: lists.usage, now: now)
        return LogsSource(usage: { page, filter in try await feed.page(page, filter: filter) }, errors: lists.errors,
                          usageSince: { sinceID, filter in try await feed.since(sinceID, filter: filter) }, errorsSince: errorsSince)
    }

    /// A cursor reply: the rows past `sinceID`, newest first, on one page with nothing after it.
    fileprivate static func past<Record: IncrementalRecord & Decodable>(_ sinceID: Int, in rows: [Record]) -> Page<Record> {
        let items = rows.filter { $0.id > sinceID }.sorted { $0.id > $1.id }
        return Page(items: items, total: nil, page: 1, pageSize: IncrementalPolicy.pageSize, pages: nil, hasMore: false,
                    sinceID: sinceID, latestID: max(items.first?.id ?? sinceID, sinceID))
    }
}

/// `-ui-logs-live`: S4-05's usage rows on one page, and the newer rows the cursor reads have brought since.
private actor LiveUsageFeed {
    static let firstAddedID = 2_001
    private let lists: @Sendable (Int, RequestLogFilter) async throws -> Page<UsageRequestRecord>
    private let now: @Sendable () -> Date
    private var added: [UsageRequestRecord] = []

    init(lists: @escaping @Sendable (Int, RequestLogFilter) async throws -> Page<UsageRequestRecord>, now: @escaping @Sendable () -> Date) {
        self.lists = lists; self.now = now
    }

    /// Page 1 holds every row in the filter whatever its page size; later pages are empty.
    func page(_ page: Int, filter: RequestLogFilter) async throws -> Page<UsageRequestRecord> {
        let rows = page == 1 ? try await all(filter) : []
        return Page(items: rows, total: nil, page: page, pageSize: IncrementalPolicy.pageSize, pages: nil, hasMore: false)
    }
    /// The rows past the cursor, and one more, newer than all of them.
    func since(_ sinceID: Int, filter: RequestLogFilter) async throws -> Page<UsageRequestRecord> {
        let rows = try await all(filter)
        let newer = try Self.row(id: Self.firstAddedID + added.count, at: now())
        added.append(newer)
        return LogFixtures.past(sinceID, in: rows + [newer])
    }

    /// S4-05's pages joined, and the rows added so far that fall in the filter's window.
    private func all(_ filter: RequestLogFilter) async throws -> [UsageRequestRecord] {
        var rows: [UsageRequestRecord] = [], page = 1
        while true {
            let reply = try await lists(page, filter)
            rows += reply.items
            guard reply.hasMore, !reply.items.isEmpty else { break }
            page += 1
        }
        return IncrementalList.merged(rows, added.filter { Self.isInside($0.createdAt, filter.time) }, limit: nil)
    }
    /// A fixed range is start-inclusive, end-exclusive.
    private static func isInside(_ createdAt: String, _ time: LogTimeWindow) -> Bool {
        guard case .range(let start, let end) = time, let date = ServerTime.parseTimestamp(createdAt) else { return true }
        return date >= start && date < end
    }
    /// Alice's request on Claude-官方-01, like the newest fixture row.
    private static func row(id: Int, at date: Date) throws -> UsageRequestRecord {
        let row: [String: Any] = [
            "id": id, "request_id": "client:00000000-0000-4000-8000-00000000\(id)", "created_at": ServerTime.utcTimestamp(date),
            "model": "claude-opus-4", "upstream_model": "claude-opus-4", "user_id": 1, "account_id": 1, "api_key_id": 101, "group_id": 1,
            "user": ["id": 1, "email": "alice@example.com", "username": "Alice"],
            "api_key": ["id": 101, "name": "默认", "key_masked": "sk-…a101"], "group": ["id": 1, "name": "高级组"],
            "account": ["id": 1, "name": "Claude-官方-01"], "input_tokens": 1_200, "output_tokens": 240, "actual_cost": "0.0124",
            "total_cost": "0.0155", "account_cost": "0.00744", "provider_cost_recorded": true, "request_type": "stream", "stream": true,
            "inbound_endpoint": "/v1/messages", "upstream_request_id": "upreq-\(id)", "duration_ms": 3_200, "first_token_ms": 1_200,
        ]
        return try JSONDecoder().decode(UsageRequestRecord.self, from: JSONSerialization.data(withJSONObject: row))
    }
}
