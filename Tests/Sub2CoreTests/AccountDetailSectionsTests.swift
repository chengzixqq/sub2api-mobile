import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 20 §2.2–§2.3 (S2-09): 容量 · 今日 · 记录 and the status card's “最近上游错误” line.

private let now = ServerTime.parseTimestamp("2026-10-24T06:20:00Z")!
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

private func account(_ id: Int = 1, platform: String = "anthropic", type: String = "oauth", status: String = "active",
                     fields: [String: Any] = [:]) throws -> UpstreamAccount {
    var json: [String: Any] = ["id": id, "name": "账号-\(id)", "platform": platform, "type": type, "status": status, "schedulable": true]
    json.merge(fields) { _, new in new }
    return try JSONDecoder().decode(UpstreamAccount.self, from: JSONSerialization.data(withJSONObject: json))
}
private func fullCapacity() -> [String: Any] { [
    "concurrency": 4, "current_concurrency": 2, "concurrency_available": true, "base_rpm": 60, "scheduling_rpm": 14, "max_sessions": 3,
    "active_sessions": 2, "session_idle_timeout_minutes": 5, "quota_daily_used": 96.3, "quota_daily_limit": 150, "quota_weekly_used": 300,
    "quota_weekly_limit": 700, "quota_used": 1200, "quota_limit": 5000
] }
private let fiveHour = AccountUsageWindow(fiveHour: .init(utilization: 42, resetsAt: ServerTime.parseTimestamp("2026-10-24T08:33:00Z")))

private func rows(_ account: UpstreamAccount, window: AccountUsageWindow? = nil, timeZone: TimeZone = shanghai) -> [CapacityRow] {
    AccountDetailPresentation.capacityRows(account: account, usageWindow: window, timeZone: timeZone)
}
private func row(_ id: String, _ rows: [CapacityRow]) -> CapacityRow? { rows.first { $0.id == id } }
private func near(_ value: Double?, _ expected: Double) -> Bool { value.map { abs($0 - expected) < 1e-9 } ?? false }

private func errorRecord(_ id: Int, status: Int, phase: String = "upstream", message: String,
                         createdAt: String = "2026-10-24T06:08:00Z") throws -> RequestErrorRecord {
    let json: [String: Any] = ["id": id, "created_at": createdAt, "request_id": "req-\(id)", "phase": phase, "type": "upstream_error",
                               "status_code": status, "platform": "anthropic", "model": "claude-example", "resolved": false, "message": message]
    return try JSONDecoder().decode(RequestErrorRecord.self, from: JSONSerialization.data(withJSONObject: json))
}
private func latest(_ status: UpstreamErrorStatus, createdAt: Date? = ServerTime.parseTimestamp("2026-10-24T06:08:00Z")) -> AccountUpstreamErrors {
    .records(total: 3, latest: LatestUpstreamError(id: 9701, createdAt: createdAt, status: status))
}
private func line(_ upstream: BlockState<AccountUpstreamErrors>, state: AccountScheduleState = .error, errorAt: Date? = nil,
                  code: Int? = nil) -> LastUpstreamErrorLine? {
    let input = LastUpstreamErrorInput(state: state, upstream: upstream, errorAt: errorAt, errorStatusCode: code)
    return AccountDetailPresentation.lastUpstreamErrorLine(input, now: now, timeZone: shanghai)
}
private func sectionsClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), transport: transport, requestClock: .immediate)
}
private func query(_ request: URLRequest?) -> [String: String] {
    guard let url = request?.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

// MARK: - 容量（壹）

@Test func capacityRowsFollowFixedOrderAndSkipZeroOrMissingLimits() throws {
    let full = rows(try account(fields: fullCapacity()), window: fiveHour)
    #expect(full.map(\.id) == ["concurrency", "rpm", "sessions", "dailyQuota", "weeklyQuota", "totalQuota", "fiveHour"])
    #expect(full.map(\.title) == ["并发", "调度 RPM", "会话", "日配额", "周配额", "总配额", "5 小时窗口"])
    let zeros: [String: Any] = ["concurrency": 0, "base_rpm": 0, "max_sessions": 0, "quota_daily_limit": 0, "quota_weekly_limit": 0, "quota_limit": 0,
                                "quota_daily_used": 3, "scheduling_rpm": 1, "active_sessions": 1]
    #expect(rows(try account(fields: zeros)).isEmpty)
    #expect(rows(try account()).isEmpty)
    let some = rows(try account(fields: ["concurrency": 8, "current_concurrency": 1, "quota_weekly_used": 1, "quota_weekly_limit": 10]))
    #expect(some.map(\.id) == ["concurrency", "weeklyQuota"])
}

@Test func concurrencyRowShowsDashOverLimitWhenUnavailable() throws {
    let unavailable = row("concurrency", rows(try account(fields: ["concurrency": 8, "current_concurrency": 0, "concurrency_available": false])))
    #expect(unavailable?.readout == "— / 8")
    #expect(unavailable?.fraction == nil && unavailable?.tone == nil)
    #expect(unavailable?.spokenReadout == "无数据 / 8")
    let missing = row("concurrency", rows(try account(fields: ["concurrency": 8])))
    #expect(missing?.readout == "— / 8" && missing?.fraction == nil)
    let normal = row("concurrency", rows(try account(fields: ["concurrency": 8, "current_concurrency": 3, "concurrency_available": true])))
    #expect(normal?.readout == "3/8" && normal?.spokenReadout == "3/8")
    #expect(near(normal?.fraction, 0.375) && normal?.tone == nil && normal?.note == nil)
}

@Test func capacityToneThresholdsAndOverflow() {
    #expect(CapacityRow.level(nil) == nil)
    #expect(CapacityRow.level(0.74) == nil)
    #expect(CapacityRow.level(0.75) == .caution)
    #expect(CapacityRow.level(0.89) == .caution)
    #expect(CapacityRow.level(0.9) == .critical)
    #expect(CapacityRow.level(1.2) == .critical)
    let over = CapacityRow.count(id: "concurrency", title: "并发", used: 9, limit: 8)
    #expect(near(over.fraction, 1.125) && over.tone == .critical && over.readout == "9/8")
    let grouped = CapacityRow.count(id: "rpm", title: "调度 RPM", used: 1_200, limit: 2_000)
    #expect(grouped.readout == "1,200/2,000")
}

@Test func schedulingRPMAndSessionsNotes() throws {
    let full = rows(try account(fields: fullCapacity()))
    let rpm = row("rpm", full), sessions = row("sessions", full)
    #expect(rpm?.readout == "14/60" && rpm?.note == "自然分钟")
    #expect(rpm?.spokenValue == "14/60，自然分钟")
    #expect(sessions?.readout == "2/3" && sessions?.note == "空闲 5 分钟释放")
    let partial = rows(try account(fields: ["base_rpm": 60, "max_sessions": 3, "active_sessions": 2]))
    #expect(row("rpm", partial)?.readout == "— / 60")
    #expect(row("sessions", partial)?.note == nil)
    #expect(row("sessions", rows(try account(fields: ["max_sessions": 3])))?.readout == "— / 3")
}

@Test func quotaRowsUseMoneyReadout() throws {
    let full = rows(try account(type: "apikey", fields: fullCapacity()))
    let daily = row("dailyQuota", full)
    #expect(daily?.readout == "$96.30 / $150.00")
    #expect(near(daily?.fraction, 0.642) && daily?.tone == nil)
    #expect(row("weeklyQuota", full)?.readout == "$300.00 / $700.00")
    #expect(row("totalQuota", full)?.readout == "$1,200.00 / $5,000.00")
    let unread = row("dailyQuota", rows(try account(type: "apikey", fields: ["quota_daily_limit": 150])))
    #expect(unread?.readout == "— / $150.00" && unread?.spokenReadout == "无数据 / $150.00" && unread?.fraction == nil)
}

@Test func fiveHourWindowOnlyForAnthropicTokenAccounts() throws {
    let oauth = row("fiveHour", rows(try account(), window: fiveHour))
    #expect(oauth?.readout == "42.0%" && oauth?.note == "16:33 重置")
    #expect(near(oauth?.fraction, 0.42) && oauth?.tone == nil)
    #expect(row("fiveHour", rows(try account(type: "setup-token"), window: fiveHour))?.readout == "42.0%")
    #expect(row("fiveHour", rows(try account(platform: "openai"), window: fiveHour)) == nil)
    #expect(row("fiveHour", rows(try account(type: "apikey"), window: fiveHour)) == nil)
    #expect(row("fiveHour", rows(try account(), window: AccountUsageWindow(fiveHour: nil))) == nil)
    #expect(row("fiveHour", rows(try account(), window: nil)) == nil)
    let over = row("fiveHour", rows(try account(), window: AccountUsageWindow(fiveHour: .init(utilization: 105))))
    #expect(over?.readout == "105.0%" && over?.tone == .critical && over?.note == nil)
}

@Test func mergingCapacityTakesRuntimeCountersAndClearsOmitted() throws {
    let base = try account(fields: fullCapacity().merging(["current_rpm": 1]) { _, new in new })
    let live = AccountRuntime(status: "active", schedulable: true, currentConcurrency: 3, concurrencyAvailable: true, currentRPM: 9,
                              schedulingRPM: 14, activeSessions: 2)
    let merged = AccountDetailPresentation.mergingCapacity(live, into: base)
    #expect(merged.currentConcurrency == 3 && merged.concurrencyAvailable == true)
    #expect(merged.currentRPM == 9 && merged.schedulingRPM == 14 && merged.activeSessions == 2)
    #expect(merged.name == base.name && merged.status == base.status && merged.baseRPM == 60 && merged.maxSessions == 3)
    #expect(merged.quotaDailyLimit == base.quotaDailyLimit && merged.sessionIdleTimeoutMinutes == 5)
    let blank = AccountRuntime(status: "active", schedulable: true, currentConcurrency: nil, concurrencyAvailable: false)
    let cleared = AccountDetailPresentation.mergingCapacity(blank, into: base)
    #expect(cleared.schedulingRPM == nil && cleared.activeSessions == nil && cleared.currentRPM == nil)
    let shown = rows(cleared)
    #expect(row("rpm", shown)?.readout == "— / 60")
    #expect(row("sessions", shown)?.readout == "— / 3")
    #expect(row("concurrency", shown)?.readout == "— / 4")
}

@Test func capacityUpdatedTextUsesServerZoneWithSeconds() throws {
    let synced = try #require(ServerTime.parseTimestamp("2026-10-24T06:05:09Z"))
    #expect(AccountDetailPresentation.capacityUpdatedText(synced, timeZone: shanghai) == "更新于 14:05:09")
    #expect(AccountDetailPresentation.capacityUpdatedText(synced, timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "更新于 23:05:09")
    #expect(AccountDetailPresentation.capacityUpdatedText(nil, timeZone: shanghai) == nil)
}

@Test func clockWithSecondsAndElapsedFormats() throws {
    let utc = TimeZone(identifier: "UTC")!
    #expect(DisplayFormat.clockWithSeconds(ServerTime.parseTimestamp("2026-10-24T09:05:03Z"), timeZone: utc) == "09:05:03")
    #expect(DisplayFormat.clockWithSeconds(nil, timeZone: utc) == "—")
    func ago(_ seconds: TimeInterval) -> String { DisplayFormat.elapsed(since: now.addingTimeInterval(-seconds), now: now) }
    #expect(ago(30) == "刚刚")
    #expect(ago(-10) == "刚刚")
    #expect(ago(12 * 60) == "12 分钟前")
    #expect(ago(59 * 60 + 59) == "59 分钟前")
    #expect(ago(3 * 3_600 + 300) == "3 小时前")
    #expect(ago(49 * 3_600) == "2 天前")
    #expect(DisplayFormat.elapsed(since: nil, now: now) == "—")
}

// MARK: - 今日（贰）

@Test func todayFiguresMapUserCostCostAndStandard() {
    let stats = AccountTodayStats(requests: 4_418, tokens: 27_270_000, cost: Decimal(string: "162.42")!, userCost: Decimal(string: "409.38"),
                                  standardCost: Decimal(string: "511.73"))
    let figures = AccountDetailPresentation.today(stats)
    #expect(figures.actual == "$409.38" && figures.accountCost == "$162.42" && figures.standard == "$511.73")
    #expect(figures.requests == "4,418" && figures.tokens == "27.3M")
    let old = AccountDetailPresentation.today(AccountTodayStats(requests: 0, tokens: 0, cost: 0))
    #expect(old.actual == "—" && old.standard == "—" && old.accountCost == "$0.00" && old.requests == "0" && old.tokens == "0")
    #expect(AccountDetailPresentation.today(nil) == AccountTodayFigures.missing)
    #expect([AccountTodayFigures.missing.actual, AccountTodayFigures.missing.tokens] == ["—", "—"])
    #expect(AccountTodayFigures.footnote == "账号成本与标准只按真实上游调用计算；实际扣费还含合并探测的跟随请求。")
}

/// X37 (S2-23): 今日 uses S1-08's block wording: “读取失败 · 重试” without figures, 更新失败 beside the title with them, and the
/// 429 wait counting down with 重试 held back either way.
@Test func todayFailureRowUsesSharedBlockWording() {
    let stats = AccountTodayStats(requests: 1, tokens: 1, cost: 1)
    let title = AccountDetailPresentation.todayFailureTitle
    #expect(title == "读取失败")
    #expect(BlockStatusPresentation.failureRow(title: title, error: nil, refresh: BlockRefresh(), at: now)
        == .init(text: "读取失败", action: .retry))
    let throttled = BlockRefresh().recordingFailure(APIError.server(status: 429, envelope: nil, retryAfter: 3), at: now)
    #expect(BlockStatusPresentation.failureRow(title: title, error: nil, refresh: throttled, at: now)
        == .init(text: "请求过于频繁，3 秒后自动重试", action: .waiting))
    #expect(BlockStatusPresentation.failureRow(title: title, error: nil, refresh: throttled, at: now.addingTimeInterval(3)).action == .retry)
    let compliance = APIError.server(status: 423, reason: "ADMIN_COMPLIANCE_ACK_REQUIRED")
    #expect(BlockStatusPresentation.failureRow(title: title, error: compliance, refresh: BlockRefresh(), at: now).action == .completeCompliance)
    let failedWithFigures = BlockState<AccountTodayStats>.failed(reason: "x", previous: stats, at: now)
    #expect(BlockStatusPresentation.accessory(for: failedWithFigures, refresh: BlockRefresh(), at: now) == .updateFailed)
    #expect(BlockStatusPresentation.accessory(for: failedWithFigures, refresh: throttled, at: now) == .throttled("请求过于频繁，3 秒后自动重试"))
    #expect(BlockStatusPresentation.accessory(for: BlockState<AccountTodayStats>.failed(reason: "x", previous: nil, at: nil), refresh: throttled, at: now) == .none)
}

// MARK: - 记录（叁）与最近上游错误

@Test func upstreamRecordTrailingCountsOpsDisabledAndFailure() {
    func trailing(_ state: BlockState<AccountUpstreamErrors>) -> String? { AccountDetailPresentation.upstreamRecordTrailing(state) }
    #expect(trailing(.loaded(.records(total: 3, latest: nil), at: now)) == "近 24 小时 3 条")
    #expect(trailing(.loaded(.records(total: 1_234, latest: nil), at: now)) == "近 24 小时 1,234 条")
    #expect(trailing(.loaded(.records(total: 0, latest: nil), at: now)) == "近 24 小时 0 条")
    #expect(trailing(.loaded(.records(total: nil, latest: nil), at: now)) == "—")
    #expect(trailing(.loaded(.opsDisabled, at: now)) == "运维监控未开启")
    #expect(trailing(.failed(reason: "x", previous: nil, at: nil)) == "—")
    #expect(trailing(.failed(reason: "x", previous: .records(total: 3, latest: nil), at: now)) == "近 24 小时 3 条")
    #expect(trailing(.idle) == nil)
    #expect(trailing(.loading(previous: nil, at: nil)) == nil)
}

@Test func upstreamErrorsRequestIsOneCallWithTotalAndLatest() async throws {
    let row = #"{"id":91,"created_at":"2026-10-24T06:08:00Z","request_id":"req-91","phase":"upstream","type":"upstream_error","status_code":200,"platform":"anthropic","model":"claude-example","resolved":false,"message":"Recovered upstream error 429: slow down"}"#
    let transport = ScriptedTransport { _ in okReply("{\"items\":[\(row)],\"total\":3,\"page\":1,\"page_size\":1,\"pages\":3}") }
    let page = try await sectionsClient(transport).errorRecords(page: 1, filter: AccountDetailPresentation.upstreamErrorFilter(accountID: 7),
                                                                 kind: .upstream)
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(requests.first?.httpMethod == "GET")
    #expect(requests.first?.url?.path.hasSuffix("/api/v1/admin/ops/upstream-errors") == true)
    let sent = query(requests.first)
    #expect(sent["account_id"] == "7" && sent["page"] == "1" && sent["page_size"] == "1" && sent["time_range"] == "24h")
    #expect(sent["start_time"] == nil && sent["end_time"] == nil)
    let created = ServerTime.parseTimestamp("2026-10-24T06:08:00Z")
    #expect(AccountUpstreamErrors(page: page) == .records(total: 3, latest: LatestUpstreamError(id: 91, createdAt: created, status: .code(429))))
    let empty = Page<RequestErrorRecord>(items: [], total: 0, page: 1, pageSize: 1, pages: 1)
    #expect(AccountUpstreamErrors(page: empty) == .records(total: 0, latest: nil))
}

@Test func opsDisabledIsMappedOnceWithoutRetry() async throws {
    let transport = ScriptedTransport { _ in errorReply(404, reason: "OPS_DISABLED") }
    let filter = AccountDetailPresentation.upstreamErrorFilter(accountID: 7)
    let thrown = await thrownAPIError { _ = try await sectionsClient(transport).errorRecords(page: 1, filter: filter, kind: .upstream) }
    let error = try #require(thrown)
    #expect(AccountUpstreamErrors.isOpsDisabled(error))
    #expect(await transport.requests.count == 1)
    #expect(!AccountUpstreamErrors.isOpsDisabled(APIError.server(status: 500, reason: nil)))
    #expect(!AccountUpstreamErrors.isOpsDisabled(APIError.server(status: 404, envelope: nil)))
    #expect(!AccountUpstreamErrors.isOpsDisabled(APIError.server(status: 429, envelope: nil, retryAfter: 3)))
    #expect(!AccountUpstreamErrors.isOpsDisabled(URLError(.notConnectedToInternet)))
}

@Test func lastUpstreamErrorLineShowsCodeAuthOrNoSegment() throws {
    let coded = line(.loaded(latest(.code(401)), at: now))
    #expect(coded == .latest(requestID: 9701, time: "14:08", ago: "12 分钟前", code: "401"))
    #expect(coded?.text == "最近上游错误 14:08 · 12 分钟前 · 401")
    #expect(coded?.isTappable == true)
    let recovered = LatestUpstreamError(try errorRecord(92, status: 200, message: "Recovered upstream error 429: slow down"))
    let recoveredLine = line(.loaded(.records(total: 2, latest: recovered), at: now))
    #expect(recoveredLine?.text == "最近上游错误 14:08 · 12 分钟前 · 429")
    let auth = LatestUpstreamError(try errorRecord(93, status: 200, phase: "account_auth", message: "Recovered account authentication failure"))
    #expect(line(.loaded(.records(total: 1, latest: auth), at: now))?.text == "最近上游错误 14:08 · 12 分钟前 · 鉴权")
    let unknown = LatestUpstreamError(try errorRecord(94, status: 200, message: "Recovered upstream error"))
    #expect(line(.loaded(.records(total: 1, latest: unknown), at: now))?.text == "最近上游错误 14:08 · 12 分钟前")
    let untimed = line(.loaded(latest(.code(401), createdAt: nil), at: now))
    #expect(untimed?.text == "最近上游错误 · 401" && untimed?.isTappable == true)
    let stale = line(.failed(reason: "x", previous: latest(.code(401)), at: now), errorAt: now.addingTimeInterval(-1_500), code: 401)
    #expect(stale?.isTappable == true)
}

@Test func erroredAtFallbackFollowsU22() {
    let errorAt = now.addingTimeInterval(-1_500)
    let fallbacks: [BlockState<AccountUpstreamErrors>] = [
        .loaded(.opsDisabled, at: now), .failed(reason: "x", previous: nil, at: nil), .loaded(.records(total: 0, latest: nil), at: now)
    ]
    for upstream in fallbacks {
        let shown = line(upstream, errorAt: errorAt, code: 401)
        #expect(shown == .erroredAt(time: "13:55", ago: "25 分钟前", code: "401"))
        #expect(shown?.text == "出错于 13:55 · 25 分钟前 · 401")
        #expect(shown?.isTappable == false)
        #expect(line(upstream, errorAt: errorAt)?.text == "出错于 13:55 · 25 分钟前")
        #expect(line(upstream) == nil)
    }
    #expect(line(.idle, errorAt: errorAt, code: 401) == nil)
    #expect(line(.loading(previous: nil, at: nil), errorAt: errorAt, code: 401) == nil)
}

@Test func upstreamLineOnlyInErrorState() throws {
    let errorAt = now.addingTimeInterval(-60)
    for state in AccountScheduleState.allCases where state != .error {
        #expect(line(.loaded(latest(.code(401)), at: now), state: state, errorAt: errorAt, code: 401) == nil)
        #expect(line(.loaded(.opsDisabled, at: now), state: state, errorAt: errorAt, code: 401) == nil)
    }
    let errored = try account(7, platform: "openai", type: "apikey", status: "error",
                              fields: ["error_at": "2026-10-24T05:55:00Z", "error_status_code": 401])
    let input = LastUpstreamErrorInput(account: errored, state: .error, upstream: .loaded(.opsDisabled, at: now))
    #expect(input.errorAt == ServerTime.parseTimestamp("2026-10-24T05:55:00Z") && input.errorStatusCode == 401)
}

// MARK: - 刷新与节序号

@Test func blocksToRefreshFollowsApplicabilityOpsDisabledAndBackoff() throws {
    func blocks(_ account: UpstreamAccount?, upstream: AccountUpstreamErrors? = nil, userInitiated: Bool = false,
                inFlight: Set<AccountDetailBlock> = [], due: [AccountDetailBlock: Date] = [:]) -> Set<AccountDetailBlock> {
        AccountDetailPresentation.blocksToRefresh(account: account, upstream: upstream, userInitiated: userInitiated, inFlight: inFlight,
                                                  dueDates: due, now: now)
    }
    let oauth = try account(), apikey = try account(platform: "openai", type: "apikey")
    #expect(blocks(oauth) == [.today, .usageWindow, .upstreamErrors])
    #expect(blocks(apikey) == [.today, .upstreamErrors])
    #expect(blocks(nil) == [.today, .upstreamErrors])
    #expect(blocks(oauth, upstream: .opsDisabled) == [.today, .usageWindow])
    #expect(blocks(oauth, upstream: .opsDisabled, userInitiated: true) == [.today, .usageWindow, .upstreamErrors])
    #expect(blocks(oauth, upstream: .records(total: 1, latest: nil)) == [.today, .usageWindow, .upstreamErrors])
    let later = [AccountDetailBlock.today: now.addingTimeInterval(30), .upstreamErrors: now.addingTimeInterval(-1)]
    #expect(blocks(oauth, due: later) == [.usageWindow, .upstreamErrors])
    #expect(blocks(oauth, userInitiated: true, due: later) == [.today, .usageWindow, .upstreamErrors])
    #expect(blocks(oauth, userInitiated: true, inFlight: [.today]) == [.usageWindow, .upstreamErrors])
}

@Test func upstreamErrorFilterIsRolling24hPageSizeOne() {
    let filter = AccountDetailPresentation.upstreamErrorFilter(accountID: 7)
    #expect(filter.time == .rolling(.h24) && filter.accountID == 7 && filter.pageSize == 1)
    #expect(filter.groupID == nil && filter.userID == nil && filter.model == nil && filter.requestID == nil && filter.statusCode == nil)
}

@Test func sectionOrdinalsRenumberOverShownSections() {
    #expect(AccountDetailPresentation.sectionOrdinals(hasCapacity: true) == AccountDetailSectionOrdinals(capacity: "壹", today: "贰", records: "叁"))
    #expect(AccountDetailPresentation.sectionOrdinals(hasCapacity: false) == AccountDetailSectionOrdinals(capacity: nil, today: "壹", records: "贰"))
}
