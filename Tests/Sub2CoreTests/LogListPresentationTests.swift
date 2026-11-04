import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 40 §6.3–§6.6: the log page's rows, sections, time presets, condition chips and list policy (S4-04).

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private let utc = ServerTimeZone(identifier: "UTC", utcOffset: "+00:00")!
private let now = ServerTime.parseTimestamp("2026-10-16T01:00:00Z")!
private func date(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private func quoted(_ text: String) -> String { "\"" + text + "\"" }

/// Keys in `fields` replace the defaults; a nil value leaves the key out.
private func object(_ defaults: [String: String], _ fields: [String: String?]) -> String {
    var values = defaults
    for (key, value) in fields { values[key] = value }
    return "{" + values.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",") + "}"
}
private func usage(_ fields: [String: String?] = [:]) throws -> UsageRequestRecord {
    let defaults = ["id": "41", "request_id": quoted("client:example"), "created_at": quoted("2026-10-16T01:41:07Z"), "model": quoted("claude-opus-4"),
                    "user_id": "8", "account_id": "12", "api_key_id": "10", "user": #"{"email":"xm.wang@example.com"}"#,
                    "account": #"{"name":"Claude-官方-01"}"#, "actual_cost": quoted("0.0124"), "first_token_ms": "1200", "duration_ms": "3200"]
    return try JSONDecoder().decode(UsageRequestRecord.self, from: Data(object(defaults, fields).utf8))
}
private func failure(_ fields: [String: String?] = [:]) throws -> RequestErrorRecord {
    let defaults = ["id": "61", "created_at": quoted("2026-10-16T01:41:07Z"), "request_id": quoted("req-61"), "phase": quoted("upstream"),
                    "type": quoted("upstream_error"), "status_code": "504", "platform": quoted("anthropic"), "model": quoted("claude-upstream-name"),
                    "requested_model": quoted("claude-opus-4"), "resolved": "false", "message": quoted("upstream timeout"),
                    "user_email": quoted("xm.wang@example.com"), "account_name": quoted("Claude-官方-01"), "time_to_first_token_ms": "800", "duration_ms": "3200"]
    return try JSONDecoder().decode(RequestErrorRecord.self, from: Data(object(defaults, fields).utf8))
}
private func usageRow(_ id: Int, at raw: String) throws -> LogRowPresentation {
    LogRowPresentation(try usage(["id": String(id), "created_at": quoted(raw)]), timeZone: shanghai)
}
private func errorRow(_ id: Int, status: Int, kind: ErrorLogKind = .request, message: String = "upstream timeout",
                      at raw: String = "2026-10-16T01:41:07Z") throws -> LogRowPresentation {
    let record = try failure(["id": String(id), "status_code": String(status), "message": quoted(message), "created_at": quoted(raw)])
    return LogRowPresentation(record, kind: kind, timeZone: shanghai)
}

private struct Row: IncrementalRecord, Decodable, Equatable {
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
private let day = LogTimeWindow.range(now.addingTimeInterval(-86_400), now)

// MARK: Rows (40 §6.3)

@Test func usageRowFillsEveryCellOfTheUsageColumn() throws {
    let row = LogRowPresentation(try usage(), timeZone: shanghai)
    #expect(row.id == 41); #expect(row.kind == nil)
    #expect(row.createdAt == date("2026-10-16T01:41:07Z")); #expect(row.time == "09:41")
    #expect(row.badge == "200"); #expect(row.badgeTone == .ok)
    #expect(row.model == "claude-opus-4")
    #expect(row.user == "xm.wang@example.com"); #expect(row.account == "Claude-官方-01")
    #expect(row.userAndAccount == "xm.wang@example.com · Claude-官方-01")
    #expect(row.amount == "$0.0124"); #expect(row.timing == "1.2s/3.2s")
    #expect(row.capsule == nil); #expect(!row.drawsRail)
}

@Test(arguments: [(#""1.3""# as String?, "$1.30"), (#""0""#, "$0.00"), (#""0.99996""#, "$1.00"), ("null", "—"), (nil, "—")])
func usageAmountAndTimingFollowTheLineFormats(cost: String?, expected: String) throws {
    #expect(LogRowPresentation(try usage(["actual_cost": cost]), timeZone: shanghai).amount == expected)
}

@Test func usageTimingFollowsTheLineFormat() throws {
    #expect(LogRowPresentation(try usage(["first_token_ms": "null"]), timeZone: shanghai).timing == "—/3.2s")
    #expect(LogRowPresentation(try usage(["first_token_ms": nil]), timeZone: shanghai).timing == "—/3.2s")
    #expect(LogRowPresentation(try usage(["duration_ms": "181600"]), timeZone: shanghai).timing == "1.2s/182s")
    #expect(LogRowPresentation(try usage(["first_token_ms": "null", "duration_ms": "null"]), timeZone: shanghai).timing == "—")
}

@Test func missingUserOrAccountReadsAsDash() throws {
    let bare = LogRowPresentation(try usage(["user": nil, "account": #"{"name":""}"#]), timeZone: shanghai)
    #expect(bare.user == "—"); #expect(bare.account == "—"); #expect(bare.userAndAccount == "— · —")
    let empty = LogRowPresentation(try usage(["user": #"{"email":""}"#, "account": nil]), timeZone: shanghai)
    #expect(empty.userAndAccount == "— · —")
    let partial = LogRowPresentation(try usage(["user": #"{"email":"a@example.com"}"#, "account": #"{"name":"  "}"#]), timeZone: shanghai)
    #expect(partial.userAndAccount == "a@example.com · —")
    #expect(LogRowPresentation(try usage(["model": quoted("")]), timeZone: shanghai).model == "—")
    let error = LogRowPresentation(try failure(["user_email": quoted(""), "account_name": nil]), kind: .request, timeZone: shanghai)
    #expect(error.userAndAccount == "— · —")
    let unnamed = LogRowPresentation(try failure(["requested_model": quoted(""), "model": quoted("  ")]), kind: .upstream, timeZone: shanghai)
    #expect(unnamed.model == "—")
}

@Test(arguments: [(429, Tone.caution), (504, .critical), (529, .critical), (500, .critical), (403, .critical)])
func requestErrorRowUsesStatusCodeToneAndCapsule(status: Int, tone: Tone) throws {
    let row = try errorRow(61, status: status)
    #expect(row.kind == .request); #expect(row.id == 61)
    #expect(row.badge == String(status)); #expect(row.badgeTone == tone)
    #expect(row.capsule == tone); #expect(row.drawsRail)
    #expect(row.model == "claude-opus-4")
    #expect(row.amount == "—"); #expect(row.timing == "0.8s/3.2s")
}

@Test func requestErrorRowFallsBackToTheModelAndOldTimings() throws {
    let unrequested = LogRowPresentation(try failure(["requested_model": quoted("")]), kind: .request, timeZone: shanghai)
    #expect(unrequested.model == "claude-upstream-name")
    let old = LogRowPresentation(try failure(["time_to_first_token_ms": "null", "duration_ms": "null"]), kind: .request, timeZone: shanghai)
    #expect(old.timing == "—")
    let impossible = LogRowPresentation(try failure(["status_code": "0"]), kind: .request, timeZone: shanghai)
    #expect(impossible.badge == "—"); #expect(impossible.badgeTone == .neutral); #expect(impossible.capsule == nil)
}

@Test func upstreamErrorRowReadsTheRecoveredCode() throws {
    let failed = try errorRow(1, status: 502, kind: .upstream)
    #expect(failed.badge == "502"); #expect(failed.badgeTone == .critical); #expect(failed.capsule == .critical)
    let limited = try errorRow(2, status: 200, kind: .upstream, message: "Recovered upstream error 429: rate limited")
    #expect(limited.badge == "429"); #expect(limited.badgeTone == .caution); #expect(limited.capsule == nil); #expect(!limited.drawsRail)
    let overloaded = try errorRow(3, status: 200, kind: .upstream, message: "Recovered upstream error 529")
    #expect(overloaded.badge == "529"); #expect(overloaded.badgeTone == .critical); #expect(overloaded.capsule == nil)
    let auth = LogRowPresentation(try failure(["status_code": "200", "phase": quoted("account_auth"),
                                               "message": quoted("Recovered account authentication failure")]), kind: .upstream, timeZone: shanghai)
    #expect(auth.badge == "鉴权"); #expect(auth.badgeTone == .neutral); #expect(auth.capsule == nil)
    let unknown = try errorRow(5, status: 200, kind: .upstream, message: "Recovered upstream error")
    #expect(unknown.badge == "恢复"); #expect(unknown.badgeTone == .neutral); #expect(unknown.capsule == nil)
    #expect([failed, limited, overloaded, auth, unknown].allSatisfy { $0.amount == "—" && $0.kind == .upstream })
}

@Test func rowTimeFollowsTheSiteZone() throws {
    #expect(LogRowPresentation(try usage(), timeZone: shanghai).time == "09:41")
    #expect(LogRowPresentation(try usage(), timeZone: utc).time == "01:41")
    let offset = LogRowPresentation(try usage(["created_at": quoted("2026-10-16T09:41:07.123456+08:00")]), timeZone: shanghai)
    #expect(offset.time == "09:41"); #expect(offset.createdAt == date("2026-10-16T01:41:07.123Z"))
    let unreadable = LogRowPresentation(try failure(["created_at": quoted("garbage")]), kind: .request, timeZone: shanghai)
    #expect(unreadable.time == "—"); #expect(unreadable.createdAt == nil)
}

@Test func batchRowsMatchSingleRows() throws {
    let records = [try usage(["id": "41"]), try usage(["id": "40", "created_at": quoted("2026-10-15T23:00:00Z")]), try usage(["id": "42"])]
    #expect(LogRowPresentation.rows(records, timeZone: shanghai) == records.map { LogRowPresentation($0, timeZone: shanghai) })
    let errors = [try failure(["id": "7", "status_code": "200", "message": quoted("Recovered upstream error 429")]), try failure(["id": "9"])]
    #expect(LogRowPresentation.rows(errors, kind: .upstream, timeZone: utc) == errors.map { LogRowPresentation($0, kind: .upstream, timeZone: utc) })
    #expect(LogRowPresentation.rows(errors, kind: .upstream, timeZone: utc).map(\.id) == [7, 9])
}

// MARK: Sections (40 §6.3, §6.6)

@Test func sectionsGroupBySiteDayNewestFirst() throws {
    let today = date("2026-10-16T09:00:00+08:00")
    let rows = [try usageRow(3, at: "2026-10-15T12:00:00+08:00"), try usageRow(5, at: "2026-10-16T08:30:00+08:00"),
                try usageRow(1, at: "2026-10-14T10:00:00+08:00"), try usageRow(4, at: "2026-10-16T01:00:00+08:00"),
                try usageRow(2, at: "2026-10-15T23:00:00+08:00")]
    let sections = LogSections.make(rows, timeZone: shanghai, now: today)
    #expect(sections.map(\.title) == ["今天", "昨天", "10月14日"])
    #expect(sections.map(\.id) == ["2026-10-16", "2026-10-15", "2026-10-14"])
    #expect(sections.map { $0.rows.map(\.id) } == [[5, 4], [3, 2], [1]])
    #expect(LogSections.headerTrailing == "金额 · 首字/耗时")
    #expect(LogSections.make([LogRowPresentation](), timeZone: shanghai, now: today).isEmpty)
}

@Test func sectionsUseTheSiteZoneNotTheDevice() throws {
    let record = try usage(["created_at": quoted("2026-10-15T16:30:00Z")])
    let site = LogRowPresentation(record, timeZone: shanghai), plain = LogRowPresentation(record, timeZone: utc)
    #expect(site.time == "00:30"); #expect(plain.time == "16:30")
    #expect(LogSections.make([site], timeZone: shanghai, now: now).map(\.title) == ["今天"])
    #expect(LogSections.make([plain], timeZone: utc, now: now).map(\.title) == ["昨天"])
}

@Test func interleavedIDsAcrossMidnightDoNotSplitASection() throws {
    let rows = [try usageRow(107, at: "2026-10-15T23:59:59+08:00"), try usageRow(106, at: "2026-10-16T00:00:01+08:00"),
                try usageRow(105, at: "2026-10-15T23:59:58+08:00")]
    let sections = LogSections.make(rows, timeZone: shanghai, now: date("2026-10-16T09:00:00+08:00"))
    #expect(sections.map(\.title) == ["今天", "昨天"])
    #expect(sections.map { $0.rows.map(\.id) } == [[106], [107, 105]])
}

@Test func sectionsOutsideThisYearAndUndatedRows() throws {
    let records = [try usage(["id": "2", "created_at": quoted("2025-10-14T10:00:00+08:00")]),
                   try usage(["id": "9", "created_at": quoted("garbage")]),
                   try usage(["id": "3", "created_at": quoted("2026-10-14T10:00:00+08:00")]),
                   try usage(["id": "8", "created_at": quoted("")])]
    let today = date("2026-10-16T09:00:00+08:00")
    let sections = LogSections.make(LogRowPresentation.rows(records, timeZone: shanghai), timeZone: shanghai, now: today)
    #expect(sections.map(\.title) == ["10月14日", "2025年10月14日", "—"])
    #expect(sections.map(\.id) == ["2026-10-14", "2025-10-14", "undated"])
    #expect(sections.last?.rows.map(\.id) == [9, 8])
    let generic = LogSections.make(records, timeZone: shanghai, now: today) { ServerTime.parseTimestamp($0.createdAt) }
    #expect(generic.map(\.id) == sections.map(\.id)); #expect(generic.map(\.title) == sections.map(\.title))
    #expect(generic.map { $0.rows.map(\.id) } == sections.map { $0.rows.map(\.id) })
}

@Test func railPositionsJoinNeighboursWithinASection() throws {
    let rows = [try errorRow(4, status: 504), try errorRow(3, status: 429),
                try errorRow(2, status: 200, kind: .upstream, message: "Recovered upstream error 429"), try errorRow(1, status: 502)]
    let sections = LogSections.make(rows, timeZone: shanghai, now: now)
    #expect(sections.count == 1)
    #expect(sections.first?.railPositions == [.top, .bottom, nil, .single])
    let split = [try errorRow(6, status: 504, at: "2026-10-16T01:00:00Z"), try errorRow(5, status: 429, at: "2026-10-15T01:00:00Z")]
    #expect(LogSections.make(split, timeZone: shanghai, now: now).map(\.railPositions) == [[.single], [.single]])
}

// MARK: Time presets and copy (40 §6.1, §6.3, §6.5)

@Test func timePresetsMapToRangesEndingNow() {
    let later = now.addingTimeInterval(90)
    let spans: [TimeInterval] = [3_600, 86_400, 7 * 86_400, 30 * 86_400]
    for (preset, span) in zip(LogTimePreset.rollingPresets, spans) {
        #expect(preset.window(now: now) == .range(now.addingTimeInterval(-span), now))
        #expect(preset.window(now: later) == .range(later.addingTimeInterval(-span), later))
        #expect(preset.isRolling); #expect(preset.span == span)
    }
    #expect(LogTimePreset.rollingPresets == [.lastHour, .last24Hours, .last7Days, .last30Days])
    #expect(LogTimePreset.rollingPresets.map(\.menuTitle) == ["近 1 小时", "近 24 小时", "近 7 天", "近 30 天"])
    let start = now.addingTimeInterval(-7_200), end = now.addingTimeInterval(-3_600)
    let custom = LogTimePreset.custom(start: start, end: end)
    #expect(custom.window(now: now) == .range(start, end)); #expect(custom.window(now: later) == .range(start, end))
    #expect(custom.menuTitle == "自定义…"); #expect(!custom.isRolling); #expect(custom.span == nil)
    #expect(LogTimePreset.standard == .last24Hours)
}

@Test func customPresetIsAtMost366Days() throws {
    let start = now.addingTimeInterval(-366 * 86_400)
    #expect(LogTimePreset.validatedCustom(start: now, end: now) == nil)
    #expect(LogTimePreset.validatedCustom(start: now, end: start) == nil)
    let longest = try #require(LogTimePreset.validatedCustom(start: start, end: now))
    #expect(longest == .custom(start: start, end: now))
    #expect(LogTimePreset.validatedCustom(start: start.addingTimeInterval(-1), end: now) == nil)
    let filter = RequestLogFilter(time: longest.window(now: now))
    #expect(try filter.queryItems(page: 1, errors: true, timeZone: shanghai).contains(item("start_time", ServerTime.utcTimestamp(start))))
}

@Test func subtitleAddsTheSiteTimeOnlyWhenOffsetsDiffer() {
    let local = TimeZone(identifier: "Asia/Shanghai")!, device = TimeZone(identifier: "UTC")!
    #expect(LogTimePreset.standard.subtitle(siteName: "测试站", timeZone: shanghai, device: local, now: now) == "测试站 · 近 24 小时")
    #expect(LogTimePreset.standard.subtitle(siteName: "测试站", timeZone: shanghai, device: device, now: now) == "测试站 · 近 24 小时（站点时间 UTC+8）")
    let custom = LogTimePreset.custom(start: date("2026-10-14T01:00:00Z"), end: date("2026-10-15T10:00:00Z"))
    #expect(custom.title(timeZone: shanghai, now: now) == "10/14 09:00 – 10/15 18:00")
    #expect(custom.subtitle(siteName: "测试站", timeZone: shanghai, device: local, now: now) == "测试站 · 10/14 09:00 – 10/15 18:00")
    let lastYear = LogTimePreset.custom(start: date("2025-12-30T01:00:00Z"), end: date("2026-01-02T10:00:00Z"))
    #expect(lastYear.title(timeZone: shanghai, now: now) == "2025/12/30 09:00 – 01/02 18:00")
    #expect(LogTimePreset.lastHour.title(timeZone: shanghai, now: now) == "近 1 小时")
}

@Test func emptyMessagesFollowThePreset() {
    #expect(LogTimePreset.standard.emptyMessage(filtered: false) == "近 24 小时内没有记录")
    #expect(LogTimePreset.standard.emptyMessage(filtered: true) == "近 24 小时内，这些条件下没有记录")
    #expect(LogTimePreset.lastHour.emptyMessage(filtered: false) == "近 1 小时内没有记录")
    let custom = LogTimePreset.custom(start: now.addingTimeInterval(-60), end: now)
    #expect(custom.emptyMessage(filtered: false) == "所选时间内没有记录")
    #expect(custom.emptyMessage(filtered: true) == "所选时间内，这些条件下没有记录")
}

@Test func retentionNoticeOnlyForErrorRangesStartingBefore30Days() {
    let old = LogTimePreset.custom(start: now.addingTimeInterval(-31 * 86_400), end: now.addingTimeInterval(-86_400))
    let recent = LogTimePreset.custom(start: now.addingTimeInterval(-29 * 86_400), end: now)
    let later = now.addingTimeInterval(5)
    for preset in LogTimePreset.rollingPresets + [old, recent] { #expect(!preset.showsRetentionNotice(kind: nil, now: later)) }
    for kind in ErrorLogKind.allCases {
        for preset in LogTimePreset.rollingPresets { #expect(!preset.showsRetentionNotice(kind: kind, now: later)) }
        #expect(old.showsRetentionNotice(kind: kind, now: now))
        #expect(!recent.showsRetentionNotice(kind: kind, now: now))
    }
    #expect(LogListCopy.retentionNotice == "运维错误日志默认只保留 30 天，更早的可能已清理")
}

// MARK: Condition chips (40 §6.3, §6.4)

@Test func chipTextsNameEachConditionInSpecOrder() {
    let conditions = LogConditions(account: LogFilterObject(id: 12, name: "Claude-官方-01"), group: LogFilterObject(id: 7),
                                   user: LogFilterObject(id: 9, name: "  "), model: "claude-opus-4")
    let chips = LogFilterChips(conditions, kind: nil, legacyServer: false, supportsModelSource: true)
    #expect(chips.chips.map(\.kind) == [.account, .group, .user, .model])
    #expect(chips.chips.map(\.text) == ["账号：Claude-官方-01", "分组：#7", "用户：#9", "模型：claude-opus-4"])
    #expect(chips.chips.map(\.isMonospaced) == [false, false, false, true])
    #expect(chips.chips.allSatisfy { $0.isApplied }); #expect(chips.note == nil); #expect(chips.hasAppliedConditions)
    #expect(chips.conditions == conditions); #expect(chips.kind == nil)
    let none = LogFilterChips(LogConditions(), kind: .request, legacyServer: false, supportsModelSource: true)
    #expect(none.chips.isEmpty); #expect(none.note == nil); #expect(!none.hasAppliedConditions)
    #expect(LogFilterKind.allCases.map(\.label) == ["账号", "分组", "用户", "模型"])
    #expect(LogFilterKind.allCases.map(\.rawValue) == ["account", "group", "user", "model"])
}

@Test(arguments: [ModelSource.upstream, .mapping])
func modelSourceOtherThanRequestedGreysTheModelOnErrorSegments(source: ModelSource) {
    let conditions = LogConditions(account: LogFilterObject(id: 3, name: "A"), group: LogFilterObject(id: 7, name: "G"),
                                   user: LogFilterObject(id: 9, name: "u@example.com"), model: "claude-opus-4", modelSource: source)
    let usage = LogFilterChips(conditions, kind: nil, legacyServer: false, supportsModelSource: true)
    #expect(usage.chips.allSatisfy { $0.isApplied }); #expect(usage.note == nil)
    #expect(usage.filter(time: day).model == "claude-opus-4"); #expect(usage.filter(time: day).modelSource == source)
    for kind in ErrorLogKind.allCases {
        let chips = LogFilterChips(conditions, kind: kind, legacyServer: false, supportsModelSource: true)
        #expect(chips.chips.map(\.isApplied) == [true, true, true, false])
        #expect(chips.note == LogListCopy.errorModelSourceNote)
        let filter = chips.filter(time: day)
        #expect(filter.model == nil); #expect(filter.modelSource == nil)
        #expect(filter.accountID == 3); #expect(filter.groupID == 7); #expect(filter.userID == 9)
    }
    #expect(LogListCopy.errorModelSourceNote == "错误记录只能按请求模型筛选，这里显示全部模型")
}

@Test func requestedModelSourceAppliesOnEverySegment() {
    let conditions = LogConditions(model: "claude-opus-4")
    for kind in [nil, .request, .upstream] as [ErrorLogKind?] {
        let chips = LogFilterChips(conditions, kind: kind, legacyServer: false, supportsModelSource: true)
        #expect(chips.chips.allSatisfy { $0.isApplied }); #expect(chips.note == nil)
        #expect(chips.filter(time: day).model == "claude-opus-4")
        #expect(chips.filter(time: day).modelSource == (kind == nil ? .requested : nil))
    }
}

@Test func legacyServerGreysUpstreamUserAndModel() {
    let conditions = LogConditions(account: LogFilterObject(id: 3), group: LogFilterObject(id: 7), user: LogFilterObject(id: 9), model: "claude-opus-4")
    let legacy = LogFilterChips(conditions, kind: .upstream, legacyServer: true, supportsModelSource: false)
    #expect(legacy.chips.map(\.isApplied) == [true, true, false, false])
    #expect(legacy.note == LogListCopy.legacyUpstreamNote)
    #expect(LogListCopy.legacyUpstreamNote == "上游错误不能按模型、用户筛选，这里显示全部")
    let full = LogFilterChips(conditions, kind: .upstream, legacyServer: false, supportsModelSource: false).filter(time: day)
    #expect(legacy.filter(time: day) == full.upstreamErrorFilter())
    #expect(legacy.filter(time: day) == RequestLogFilter(time: day, accountID: 3, groupID: 7))
    var mapped = conditions
    mapped.modelSource = .upstream
    #expect(LogFilterChips(mapped, kind: .upstream, legacyServer: true, supportsModelSource: false).note == LogListCopy.legacyUpstreamNote)
    for kind in [nil, ErrorLogKind.request] {
        let chips = LogFilterChips(conditions, kind: kind, legacyServer: true, supportsModelSource: false)
        #expect(chips.chips.allSatisfy { $0.isApplied }); #expect(chips.note == nil)
    }
    let accountOnly = LogFilterChips(LogConditions(account: LogFilterObject(id: 3)), kind: .upstream, legacyServer: true, supportsModelSource: false)
    #expect(accountOnly.note == nil); #expect(accountOnly.hasAppliedConditions)
    let userOnly = LogFilterChips(LogConditions(user: LogFilterObject(id: 9)), kind: .upstream, legacyServer: true, supportsModelSource: false)
    #expect(userOnly.note == LogListCopy.legacyUpstreamNote); #expect(!userOnly.hasAppliedConditions)
}

@Test func chipFilterCarriesTimeAndPageSizeButNoKeyView() throws {
    let chips = LogFilterChips(LogConditions(model: "claude-opus-4", modelSource: .upstream), kind: nil, legacyServer: false, supportsModelSource: true)
    let filter = chips.filter(time: day)
    #expect(filter.time == day); #expect(filter.pageSize == 100)
    #expect(chips.filter(time: day, pageSize: 1).pageSize == 1)
    #expect(filter.requestID == nil); #expect(filter.apiKeyID == nil); #expect(filter.statusCode == nil); #expect(filter.resolved == nil)
    let usageItems = try filter.queryItems(page: 1, errors: false, timeZone: shanghai)
    #expect(!usageItems.contains { $0.name == "key_view" })
    #expect(usageItems.contains(item("model_source", "upstream")))
    let errors = LogFilterChips(LogConditions(model: "claude-opus-4"), kind: .request, legacyServer: false, supportsModelSource: true)
    let errorItems = try errors.filter(time: day).queryItems(page: 1, errors: true, timeZone: shanghai)
    #expect(errorItems.contains(item("view", "all"))); #expect(errorItems.contains(item("model", "claude-opus-4")))
    #expect(!errorItems.contains { $0.name == "model_source" || $0.name == "key_view" })
}

@Test func siteWithoutModelSourceSendsNoModelSource() throws {
    let requested = LogFilterChips(LogConditions(model: "claude-opus-4"), kind: nil, legacyServer: false, supportsModelSource: false)
    #expect(requested.chips.allSatisfy { $0.isApplied }); #expect(requested.note == nil)
    #expect(requested.filter(time: day).modelSource == nil)
    let items = try requested.filter(time: day).queryItems(page: 1, errors: false, timeZone: shanghai)
    #expect(items.contains(item("model", "claude-opus-4"))); #expect(!items.contains { $0.name == "model_source" })
    let mapped = LogFilterChips(LogConditions(model: "claude-opus-4", modelSource: .upstream), kind: nil, legacyServer: false, supportsModelSource: false)
    #expect(mapped.chips.map(\.isApplied) == [false])
    #expect(mapped.note == LogListCopy.usageModelSourceNote)
    #expect(LogListCopy.usageModelSourceNote == "使用记录只能按请求模型筛选，这里显示全部模型")
    #expect(mapped.filter(time: day).model == nil); #expect(!mapped.hasAppliedConditions)
}

@Test func removingAConditionKeepsTheOthers() {
    let full = LogConditions(account: LogFilterObject(id: 3, name: "A"), group: LogFilterObject(id: 7), user: LogFilterObject(id: 9),
                             model: "claude-opus-4", modelSource: .mapping)
    let noModel = full.removing(.model)
    #expect(noModel.model == nil); #expect(noModel.modelSource == .requested)
    #expect(noModel.account == full.account); #expect(noModel.group == full.group); #expect(noModel.user == full.user)
    let noAccount = full.removing(.account)
    #expect(noAccount.account == nil); #expect(noAccount.group == full.group); #expect(noAccount.user == full.user)
    #expect(noAccount.model == full.model); #expect(noAccount.modelSource == .mapping)
    #expect(full.removing(.group).group == nil); #expect(full.removing(.user).user == nil)
    let cleared = full.removing(.account).removing(.group).removing(.user).removing(.model)
    #expect(cleared.isEmpty); #expect(cleared == LogConditions())
    #expect(!full.isEmpty); #expect(full.model == "claude-opus-4"); #expect(full.account?.id == 3)
    let blank = LogConditions(model: "  ")
    #expect(blank.isEmpty); #expect(LogFilterChips(blank, kind: nil, legacyServer: false, supportsModelSource: true).chips.isEmpty)
}

// MARK: List policy (40 §6.6)

@Test func trimsToTheLimitOnlyNearTheTop() throws {
    let list = IncrementalList<Row>().reset(firstPage: (1...7).map { row($0, age: TimeInterval(7 - $0) * 60) })
    let policy = LogListPolicy(limit: 5)
    for index in [0, 19, nil] as [Int?] {
        let trim = try #require(policy.trimmed(list, firstVisibleIndex: index))
        #expect(ids(trim.list) == [7, 6, 5, 4, 3]); #expect(trim.list.cursor == list.cursor); #expect(trim.nextPage == 1)
    }
    #expect(policy.trimmed(list, firstVisibleIndex: 20) == nil)
    let short = IncrementalList<Row>().reset(firstPage: (1...5).map { row($0, age: TimeInterval(5 - $0) * 60) })
    #expect(policy.trimmed(short, firstVisibleIndex: 0) == nil)
    #expect(policy.isNearTop(firstVisibleIndex: nil)); #expect(policy.isNearTop(firstVisibleIndex: 19)); #expect(!policy.isNearTop(firstVisibleIndex: 20))
}

@Test func standardPolicyKeeps500AndNextPageIs6() throws {
    let policy = LogListPolicy()
    #expect(policy.limit == 500); #expect(policy.pageSize == 100); #expect(policy.nextPageAfterTrim == 6)
    #expect(LogListPolicy.standardLimit == 500); #expect(LogListPolicy.nearTopRows == 20); #expect(LogListPolicy.calibrationInterval == 10)
    let list = IncrementalList<Row>().reset(firstPage: (1...600).map { row($0, age: TimeInterval(600 - $0)) })
    let trim = try #require(policy.trimmed(list, firstVisibleIndex: 3))
    #expect(trim.list.items.count == 500); #expect(trim.list.items.first?.id == 600); #expect(trim.list.items.last?.id == 101)
    #expect(trim.nextPage == 6)
    #expect(LogListPolicy(pageSize: 50).nextPageAfterTrim == 11)
    #expect(LogListPolicy(limit: 5, pageSize: 5).nextPageAfterTrim == 2)
    #expect(LogListPolicy(limit: 0).limit == 1); #expect(LogListPolicy(limit: 5, pageSize: 0).pageSize == 1)
}

@Test func pruningDropsRowsBeforeTheWindowStart() {
    let rows = [row(5, age: 0), row(4, age: 86_400), row(3, age: 86_401), Row(id: 2, createdAt: "garbage"), row(1, age: 90_000)]
    let list = IncrementalList<Row>(items: rows, cursor: 4, limit: 10)
    let pruned = LogListPolicy.pruned(list, to: LogTimePreset.last24Hours.window(now: now))
    #expect(ids(pruned) == [5, 4, 2]); #expect(pruned.cursor == 4); #expect(pruned.limit == 10)
    let recent = IncrementalList<Row>(items: [row(5, age: 0), row(4, age: 60)], cursor: 4)
    #expect(LogListPolicy.pruned(recent, to: day).items == recent.items)
    let custom = LogTimePreset.custom(start: now.addingTimeInterval(-100), end: now.addingTimeInterval(-10)).window(now: now)
    #expect(ids(LogListPolicy.pruned(IncrementalList<Row>(items: [row(5, age: 0), row(4, age: 100), row(3, age: 101)]), to: custom)) == [5, 4])
    #expect(ids(LogListPolicy.pruned(list, to: .rolling(.h24))) == [5, 4, 3, 2, 1])
    #expect(ids(LogListPolicy.pruned(list, to: .none)) == [5, 4, 3, 2, 1])
}

@Test func calibrationEveryTenIncrements() {
    #expect(LogPollSchedule().next == .increment)
    var schedule = LogPollSchedule(), reads: [LogPollRead] = []
    for _ in 0..<22 {
        let read = schedule.next
        reads.append(read)
        schedule = schedule.recording(read)
    }
    let ten = [LogPollRead](repeating: .increment, count: 10)
    #expect(reads == ten + [.calibration] + ten + [.calibration])
    let counted = (0..<10).reduce(LogPollSchedule()) { partial, _ in partial.recording(.increment) }
    #expect(counted.incrementsSinceCalibration == 10); #expect(counted.next == .calibration)
    #expect(counted.recording(.calibration) == LogPollSchedule())
    let original = LogPollSchedule(incrementsSinceCalibration: 3)
    #expect(original.recording(.increment).incrementsSinceCalibration == 4); #expect(original.incrementsSinceCalibration == 3)
}

@Test func fallbackRefreshUsesNewestRowMinus120Seconds() throws {
    let newest = now.addingTimeInterval(-300)
    let list = IncrementalList<Row>().reset(firstPage: [Row(id: 9, createdAt: ServerTime.utcTimestamp(newest)), row(8, age: 400), Row(id: 7, createdAt: "garbage")])
    let base = RequestLogFilter(time: day, accountID: 3, groupID: 7, userID: 9, model: "claude-opus-4", pageSize: 5)
    let filter = try #require(LogListPolicy.fallbackRefreshFilter(after: list, base: base, now: now))
    #expect(filter.time == .range(newest.addingTimeInterval(-120), now)); #expect(filter.pageSize == 100)
    #expect(filter.accountID == 3); #expect(filter.groupID == 7); #expect(filter.userID == 9); #expect(filter.model == "claude-opus-4")
    let upstream = try filter.queryItems(page: 1, errors: true, timeZone: shanghai)
    for expected in [item("page", "1"), item("page_size", "100"), item("view", "all"),
                     item("start_time", ServerTime.utcTimestamp(newest.addingTimeInterval(-120))), item("end_time", ServerTime.utcTimestamp(now))] {
        #expect(upstream.contains(expected))
    }
    #expect(!upstream.contains { ["count_mode", "since_id", "time_range"].contains($0.name) })
    #expect(try filter.queryItems(page: 1, errors: false, timeZone: shanghai).contains(item("count_mode", "deferred")))
    #expect(LogListPolicy.fallbackRefreshFilter(after: IncrementalList<Row>(), base: base, now: now) == nil)
    let unreadable = IncrementalList<Row>(items: [Row(id: 2, createdAt: "garbage"), Row(id: 1, createdAt: "")])
    #expect(LogListPolicy.fallbackRefreshFilter(after: unreadable, base: base, now: now) == nil)
    let ahead = IncrementalList<Row>(items: [Row(id: 1, createdAt: ServerTime.utcTimestamp(now.addingTimeInterval(121)))])
    #expect(LogListPolicy.fallbackRefreshFilter(after: ahead, base: base, now: now) == nil)
}

@Test func fallbackReplyWithMoreThanOnePageReloads() {
    let list = IncrementalList<Row>().reset(firstPage: [row(5, age: 60), row(4, age: 70)])
    let twoPages = Page(items: [row(7, age: 0)], total: 150, page: 1, pageSize: 100, pages: 2)
    guard case .reloadFirstPage = LogListPolicy.fallbackRefreshStep(list, reply: twoPages) else { Issue.record("Expected a reload"); return }
    let onePage = Page(items: [row(6, age: 10), row(5, age: 60, resolved: true)], total: 2, page: 1, pageSize: 100, pages: 1)
    guard case .merged(let merged) = LogListPolicy.fallbackRefreshStep(list, reply: onePage) else { Issue.record("Expected a merge"); return }
    #expect(ids(merged) == [6, 5, 4]); #expect(merged.items.first { $0.id == 5 }?.resolved == true); #expect(merged.limit == nil)
    let flagged = Page<Row>(items: [], total: nil, page: 1, pageSize: 100, pages: nil, hasMore: true)
    guard case .reloadFirstPage = LogListPolicy.fallbackRefreshStep(list, reply: flagged) else { Issue.record("Expected a reload"); return }
    let quiet = Page(items: [row(6, age: 10)], total: nil, page: 1, pageSize: 100, pages: nil, hasMore: false)
    guard case .merged(let quietMerge) = LogListPolicy.fallbackRefreshStep(list, reply: quiet) else { Issue.record("Expected a merge"); return }
    #expect(ids(quietMerge) == [6, 5, 4])
}

@Test func usageCountQueryMirrorsTheUsageFilter() throws {
    let start = now.addingTimeInterval(-86_400)
    let filter = RequestLogFilter(time: .range(start, now), accountID: 3, groupID: 7, userID: 9, model: "claude-opus-4", modelSource: .upstream)
    let query = try #require(LogListPolicy.usageCountQuery(filter, timeZone: shanghai))
    #expect(query.start == start); #expect(query.end == now); #expect(query.timeZone == shanghai)
    #expect(query.accountID == 3); #expect(query.groupID == 7); #expect(query.userID == 9)
    #expect(query.model == "claude-opus-4"); #expect(query.modelSource == .upstream)
    let items = try query.queryItems()
    for expected in [item("start_time", ServerTime.utcTimestamp(start)), item("end_time", ServerTime.utcTimestamp(now)), item("timezone", "Asia/Shanghai"),
                     item("account_id", "3"), item("group_id", "7"), item("user_id", "9"), item("model", "claude-opus-4"), item("model_source", "upstream")] {
        #expect(items.contains(expected))
    }
    #expect(!items.contains { $0.name == "granularity" })
    var unmodelled = filter
    unmodelled.model = nil
    let bare = try #require(LogListPolicy.usageCountQuery(unmodelled, timeZone: shanghai)).queryItems()
    #expect(bare.allSatisfy { !["model", "model_source"].contains($0.name) })
    var unsourced = filter
    unsourced.modelSource = nil
    let plain = try #require(LogListPolicy.usageCountQuery(unsourced, timeZone: shanghai)).queryItems()
    #expect(plain.contains(item("model", "claude-opus-4"))); #expect(!plain.contains { $0.name == "model_source" })
    #expect(LogListPolicy.usageCountQuery(RequestLogFilter(time: .rolling(.h24)), timeZone: shanghai) == nil)
    #expect(LogListPolicy.usageCountQuery(RequestLogFilter(time: .none, requestID: "client:example"), timeZone: shanghai) == nil)
    let greyed = LogFilterChips(LogConditions(account: LogFilterObject(id: 3), model: "claude-opus-4", modelSource: .upstream),
                                kind: nil, legacyServer: false, supportsModelSource: false)
    let counted = try #require(LogListPolicy.usageCountQuery(greyed.filter(time: .range(start, now)), timeZone: shanghai))
    #expect(counted.model == nil); #expect(counted.modelSource == nil); #expect(counted.accountID == 3)
}
