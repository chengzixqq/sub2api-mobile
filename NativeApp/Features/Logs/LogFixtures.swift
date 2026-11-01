import Foundation
import Sub2Core

/// X05, C-32, X44: the usage-record page under `-ui-testing`. Only S4-05 and S4-05b change this file; later items extend
/// LogFixtures in their own files and add no row fields. Times are offsets from `base`, the site clock when the list was made;
/// users, accounts, groups and models are DemoData's.
///
/// 各段条数（默认近 24 小时、无条件；UI 测试的计数字面量照此）：
///
/// | 段 | 全部 | 用户 1 Alice | 用户 3 | 用户 8 | 账号 1 | 账号 3 | 账号 7 |
/// |---|---|---|---|---|---|---|---|
/// | 用量明细 1040…1001 | 40 | 10 | 20 | 10 | 14 | 13 | 0 |
/// | 错误请求 2006…2001 | 6 | 0 | 3 | 3 | 1 | 1 | 2 |
/// | 上游错误 3006…3001 | 6 | 1 | 2 | 3 | 0 | 2 | 3 |
///
/// Usage 1040…1016 are today and 1015…1001 yesterday (always inside 24 hours, apart from the site's last two minutes before
/// midnight); every fifth row from 1036 is non-streaming, 1037 has no provider cost. A page holds 30 rows and page k > 1 starts
/// with page k − 1's last row (1011), so “加载更多” has to join by id.
enum LogFixtures {
    enum Argument {
        /// No segment has rows.
        static let empty = "-ui-logs-empty"
        /// Each segment's first page-1 read answers 503.
        static let firstPageFails = "-ui-logs-first-error"
        /// The first page-2 read answers 503.
        static let nextPageFails = "-ui-logs-page-error"
        /// admin/me says ops monitoring is on, yet both error lists answer 404 OPS_DISABLED.
        static let opsDisabledReply = "-ui-logs-ops-404"
    }
    static let pageSize = 30
    static let newestUsageID = 1040
    static let overlapUsageID = 1011
    static let oldestUsageID = 1001
    static let failure = APIError.server(status: 503, reason: nil)

    /// The rows are made once; the reads only filter and page them. `-ui-ops-disabled` / `-ui-ops-config-off` (OpsFixtureSwitch)
    /// also answer 404 on the error lists, which the store does not ask while the switch says off.
    static func source(arguments: [String], base: Date, timeZone: ServerTimeZone) -> LogsSource {
        let isEmpty = arguments.contains(Argument.empty)
        let usage = isEmpty ? [] : usageRows(base: base, timeZone: timeZone)
        let request = isEmpty ? [] : errorRows(.request, base: base, timeZone: timeZone)
        let upstream = isEmpty ? [] : errorRows(.upstream, base: base, timeZone: timeZone)
        let opsOff = OpsFixtureSwitch.from(arguments: arguments) != .on || arguments.contains(Argument.opsDisabledReply)
        let failures = LogFixtureFailures(firstPage: arguments.contains(Argument.firstPageFails),
                                          nextPage: arguments.contains(Argument.nextPageFails))
        return LogsSource(usage: { page, filter in
            try await failures.check("usage", page: page)
            return LogFixtures.page(usage.filter { matches($0, filter) }, page: page, countsTotal: false)
        }, errors: { page, filter, kind in
            if opsOff { throw LiveOpsFixtures.opsDisabledError }
            try await failures.check(kind.rawValue, page: page)
            let rows = (kind == .upstream ? upstream : request).filter { matches($0, filter) }
            return LogFixtures.page(rows, page: page, countsTotal: true, reportsHasMore: kind == .request)
        })
    }

    /// Newest id first. Usage pages page by `has_more` without a total; the error lists count (`ops/upstream-errors` has no
    /// `has_more`, so `pages` decides).
    static func page<Record: IncrementalRecord & Decodable>(_ matched: [Record], page: Int, countsTotal: Bool,
                                                            reportsHasMore: Bool = true) -> Page<Record> {
        let sorted = matched.sorted { $0.id > $1.id }
        let start = page <= 1 ? 0 : (page - 1) * pageSize - 1
        let items = start < sorted.count ? Array(sorted[start..<min(sorted.count, start + pageSize)]) : []
        let hasMore = start + pageSize < sorted.count
        guard countsTotal else { return Page(items: items, total: nil, page: page, pageSize: pageSize, pages: nil, hasMore: hasMore) }
        let pages = max(1, (sorted.count + pageSize - 1) / pageSize)
        return Page(items: items, total: sorted.count, page: page, pageSize: pageSize, pages: pages, hasMore: reportsHasMore ? hasMore : nil)
    }

    static func usageRows(base: Date, timeZone: ServerTimeZone) -> [UsageRequestRecord] {
        let clock = LogFixtureClock(base: base, timeZone: timeZone)
        return (0..<40).map { index in
            let createdAt = index < 25 ? clock.today(minutesAgo: 2 + 20 * index, rank: 25 - index)
                                       : clock.yesterday(minutesBeforeMidnight: 90 + 40 * (index - 25), rank: 40 - index)
            return decode(usageRow(index, createdAt: createdAt))
        }
    }
    static func errorRows(_ kind: ErrorLogKind, base: Date, timeZone: ServerTimeZone) -> [RequestErrorRecord] {
        let clock = LogFixtureClock(base: base, timeZone: timeZone)
        return (kind == .upstream ? upstreamSpecs : requestSpecs).map { spec in
            decode(errorRow(spec, kind: kind, createdAt: spec.when.date(clock, rank: spec.id % 100)))
        }
    }

    // MARK: Rows

    private static func usageRow(_ index: Int, createdAt: Date) -> [String: Any] {
        let id = newestUsageID - index, user = users[[0, 1, 2, 1][index % 4]], target = targets[index % 3]
        let cost = decimal(["0.0124", "1.2800", "0.3500", "0.0042"][index % 4])
        let stream = index % 5 != 4, recorded = id != 1037
        var row: [String: Any] = [
            "id": id, "request_id": "client:00000000-0000-4000-8000-00000000\(id)", "created_at": ServerTime.utcTimestamp(createdAt),
            "model": target.model, "upstream_model": target.upstreamModel, "user_id": user.id, "account_id": target.accountID,
            "api_key_id": user.keyID, "group_id": target.groupID, "user": ["id": user.id, "email": user.email, "username": user.name],
            "api_key": ["id": user.keyID, "name": user.keyName, "key_masked": user.keyMasked],
            "group": ["id": target.groupID, "name": target.groupName], "account": ["id": target.accountID, "name": target.accountName],
            "input_tokens": 1_200 + 37 * index, "output_tokens": 240 + 11 * index, "cache_read_tokens": index % 2 == 0 ? 512 : 0,
            "cache_creation_tokens": index % 3 == 0 ? 128 : 0, "actual_cost": "\(cost)", "total_cost": "\(cost * decimal("1.25"))",
            "account_cost": recorded ? "\(cost * decimal("0.6"))" : "0", "provider_cost_recorded": recorded,
            "request_type": stream ? "stream" : "sync", "stream": stream, "inbound_endpoint": target.endpoint,
            "upstream_request_id": "upreq-\(id)", "duration_ms": 3_200,
        ]
        row["first_token_ms"] = stream ? 1_200 : NSNull()
        return row
    }
    private static func errorRow(_ spec: ErrorSpec, kind: ErrorLogKind, createdAt: Date) -> [String: Any] {
        let target = spec.target, user = spec.user
        var row: [String: Any] = [
            "id": spec.id, "created_at": ServerTime.utcTimestamp(createdAt), "request_id": "req-err-\(spec.id)", "phase": spec.phase,
            "type": spec.type, "status_code": spec.status, "platform": target.platform, "model": target.model,
            "requested_model": target.model, "upstream_model": target.upstreamModel, "resolved": false, "message": spec.message,
            "user_id": user.id, "user_email": user.email, "api_key_id": user.keyID, "api_key_name": user.keyName,
            "account_id": target.accountID, "account_name": target.accountName, "group_id": target.groupID, "group_name": target.groupName,
            "error_owner": spec.owner, "error_source": kind == .upstream ? "upstream_http" : "gateway", "severity": spec.severity,
            "stream": true, "request_type": 2,
        ]
        row["duration_ms"] = spec.isTimed ? 2_400 : NSNull()
        row["time_to_first_token_ms"] = spec.isTimed ? 900 : NSNull()
        // 3005 carries no client request id: the detail looks it up by request_id (S4-08).
        if spec.id != 3005 { row["client_request_id"] = "00000000-0000-4000-9000-00000000\(spec.id)" }
        return row
    }

    // MARK: Objects

    private struct FixtureUser {
        let id: Int, email: String, name: String, keyID: Int, keyName: String, keyMasked: String
    }
    private struct FixtureTarget {
        let accountID: Int, accountName: String, groupID: Int, groupName: String, platform: String
        let model: String, upstreamModel: String, endpoint: String
    }
    private static let users = [
        FixtureUser(id: 1, email: "alice@example.com", name: "Alice", keyID: 101, keyName: "默认", keyMasked: "sk-…a101"),
        FixtureUser(id: 3, email: "xm.wang@example.com", name: "王小明", keyID: 301, keyName: "脚本", keyMasked: "sk-…b301"),
        FixtureUser(id: 8, email: "siyuan.chen@example.com", name: "陈思远", keyID: 801, keyName: "生产", keyMasked: "sk-…c801"),
    ]
    private static let targets = [
        FixtureTarget(accountID: 1, accountName: "Claude-官方-01", groupID: 1, groupName: "高级组", platform: "anthropic",
                      model: "claude-opus-4", upstreamModel: "claude-opus-4", endpoint: "/v1/messages"),
        FixtureTarget(accountID: 4, accountName: "OpenAI-主力-01", groupID: 2, groupName: "标准组", platform: "openai",
                      model: "gpt-4.1", upstreamModel: "gpt-4.1-2025-04-14", endpoint: "/v1/chat/completions"),
        FixtureTarget(accountID: 3, accountName: "Claude-官方-03", groupID: 1, groupName: "高级组", platform: "anthropic",
                      model: "claude-sonnet-4", upstreamModel: "claude-sonnet-4", endpoint: "/v1/messages"),
    ]
    private static let backup = FixtureTarget(accountID: 7, accountName: "OpenAI-备用-A", groupID: 2, groupName: "标准组",
                                              platform: "openai", model: "gpt-4.1", upstreamModel: "gpt-4.1-2025-04-14",
                                              endpoint: "/v1/chat/completions")

    private enum When {
        case today(minutesAgo: Int)
        case yesterday(minutesBeforeMidnight: Int)
        func date(_ clock: LogFixtureClock, rank: Int) -> Date {
            switch self {
            case .today(let minutes): clock.today(minutesAgo: minutes, rank: rank)
            case .yesterday(let minutes): clock.yesterday(minutesBeforeMidnight: minutes, rank: rank)
            }
        }
    }
    private struct ErrorSpec {
        let id: Int, status: Int, target: FixtureTarget, user: FixtureUser, when: When
        let phase: String, type: String, owner: String, severity: String, message: String
        var isTimed = true
    }
    /// 2003 is a row from before D04: no timings.
    private static let requestSpecs = [
        ErrorSpec(id: 2006, status: 429, target: targets[1], user: users[1], when: .today(minutesAgo: 5), phase: "upstream",
                  type: "rate_limit_error", owner: "provider", severity: "P2", message: "上游请求受限，请稍后重试。"),
        ErrorSpec(id: 2005, status: 500, target: backup, user: users[2], when: .today(minutesAgo: 30), phase: "internal",
                  type: "api_error", owner: "platform", severity: "P1", message: "网关内部错误"),
        ErrorSpec(id: 2004, status: 502, target: targets[0], user: users[1], when: .today(minutesAgo: 120), phase: "upstream",
                  type: "upstream_error", owner: "provider", severity: "P1", message: "上游服务暂时不可用"),
        ErrorSpec(id: 2003, status: 400, target: targets[1], user: users[2], when: .today(minutesAgo: 240), phase: "request",
                  type: "invalid_request_error", owner: "client", severity: "P3", message: "请求参数无效", isTimed: false),
        ErrorSpec(id: 2002, status: 504, target: targets[2], user: users[1], when: .yesterday(minutesBeforeMidnight: 120),
                  phase: "upstream", type: "timeout_error", owner: "provider", severity: "P1", message: "上游响应超时"),
        ErrorSpec(id: 2001, status: 429, target: backup, user: users[2], when: .yesterday(minutesBeforeMidnight: 300), phase: "upstream",
                  type: "rate_limit_error", owner: "provider", severity: "P2", message: "上游请求受限，请稍后重试。"),
    ]
    /// 3005, 3004 and 3003 are recovered rows (status 200): a retried 429, an account_auth recovery, one without a code.
    private static let upstreamSpecs = [
        ErrorSpec(id: 3006, status: 502, target: backup, user: users[2], when: .today(minutesAgo: 3), phase: "upstream",
                  type: "upstream_error", owner: "provider", severity: "P1", message: "Upstream error 502"),
        ErrorSpec(id: 3005, status: 200, target: targets[2], user: users[1], when: .today(minutesAgo: 20), phase: "upstream",
                  type: "upstream_error", owner: "provider", severity: "P3", message: "Recovered upstream error 429: rate limited"),
        ErrorSpec(id: 3004, status: 200, target: targets[2], user: users[2], when: .today(minutesAgo: 60), phase: "account_auth",
                  type: "authentication_error", owner: "provider", severity: "P3", message: "Recovered account authentication failure"),
        ErrorSpec(id: 3003, status: 200, target: targets[1], user: users[1], when: .today(minutesAgo: 180), phase: "upstream",
                  type: "upstream_error", owner: "provider", severity: "P3", message: "Recovered upstream error"),
        ErrorSpec(id: 3002, status: 401, target: backup, user: users[2], when: .yesterday(minutesBeforeMidnight: 150),
                  phase: "account_auth", type: "authentication_error", owner: "provider", severity: "P1", message: "Upstream authentication failed"),
        ErrorSpec(id: 3001, status: 529, target: backup, user: users[0], when: .yesterday(minutesBeforeMidnight: 400), phase: "upstream",
                  type: "overloaded_error", owner: "provider", severity: "P2", message: "Upstream overloaded"),
    ]

    // MARK: Filters

    private static func matches(_ row: UsageRequestRecord, _ filter: RequestLogFilter) -> Bool {
        objectsMatch(account: row.accountID, group: row.groupID, user: row.userID, filter)
            && modelMatches(filter, requested: row.model, upstream: row.upstreamModel) && isInside(row.createdAt, filter.time)
    }
    /// The error lists match the requested model only.
    private static func matches(_ row: RequestErrorRecord, _ filter: RequestLogFilter) -> Bool {
        objectsMatch(account: row.accountID, group: row.groupID, user: row.userID, filter)
            && (filter.model.map { $0 == row.model } ?? true) && isInside(row.createdAt, filter.time)
    }
    private static func objectsMatch(account: Int?, group: Int?, user: Int?, _ filter: RequestLogFilter) -> Bool {
        (filter.accountID.map { $0 == account } ?? true) && (filter.groupID.map { $0 == group } ?? true)
            && (filter.userID.map { $0 == user } ?? true)
    }
    private static func modelMatches(_ filter: RequestLogFilter, requested: String, upstream: String?) -> Bool {
        guard let model = filter.model else { return true }
        switch filter.modelSource ?? .requested {
        case .requested: return requested == model
        case .upstream: return upstream == model
        case .mapping: return requested == model || upstream == model
        }
    }
    /// A fixed range is start-inclusive, end-exclusive.
    private static func isInside(_ createdAt: String, _ time: LogTimeWindow) -> Bool {
        guard case .range(let start, let end) = time, let date = ServerTime.parseTimestamp(createdAt) else { return true }
        return date >= start && date < end
    }

    private static func decimal(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    /// try! only here: a row that no longer decodes stops the first UI test instead of showing a wrong list.
    private static func decode<Record: Decodable>(_ row: [String: Any]) -> Record {
        try! JSONDecoder().decode(Record.self, from: JSONSerialization.data(withJSONObject: row))
    }
}

/// Today's rows stay after the site's midnight and yesterday's inside the last 24 hours; `rank` keeps a newer row later when
/// either bound pushes them together.
private struct LogFixtureClock {
    let base: Date
    let dayStart: Date

    init(base: Date, timeZone: ServerTimeZone) { self.base = base; dayStart = timeZone.calendar.startOfDay(for: base) }

    func today(minutesAgo: Int, rank: Int) -> Date {
        max(base.addingTimeInterval(-TimeInterval(minutesAgo * 60)), dayStart.addingTimeInterval(TimeInterval(rank * 2)))
    }
    func yesterday(minutesBeforeMidnight: Int, rank: Int) -> Date {
        max(dayStart.addingTimeInterval(-TimeInterval(minutesBeforeMidnight * 60)), base.addingTimeInterval(TimeInterval(-86_400 + 120 + rank * 2)))
    }
}

/// `-ui-logs-first-error` fails each segment's first page 1 once, `-ui-logs-page-error` the first page 2.
private actor LogFixtureFailures {
    private let firstPage: Bool
    private let nextPage: Bool
    private var failed: Set<String> = []

    init(firstPage: Bool, nextPage: Bool) { self.firstPage = firstPage; self.nextPage = nextPage }

    func check(_ segment: String, page: Int) throws {
        let key: String? = if page == 1, firstPage { segment } else if page == 2, nextPage { "page-2" } else { nil }
        guard let key, failed.insert(key).inserted else { return }
        throw LogFixtures.failure
    }
}
